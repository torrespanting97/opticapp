"""
Salud Visual — Notify Service
FastAPI microservice that handles WhatsApp (Meta Cloud API) + email (Resend)
notifications for appointment status changes and scheduled reminders.

Endpoints
---------
GET  /health                         — liveness probe
POST /webhook/appointment-status     — called by Supabase pg_net trigger
POST /remind                         — called by pg_cron every 30 min

Security
--------
Both POST endpoints require the header:  X-Webhook-Secret: <WEBHOOK_SECRET>
The secret is set in your .env and stored in Supabase DB settings so the
pg_net trigger and pg_cron can include it automatically.
"""

from __future__ import annotations

import logging
import os

from dotenv import load_dotenv
load_dotenv()  # reads notify_service/.env when running locally
from datetime import datetime, timedelta, timezone
from typing import Literal

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

from config import get_settings
from supabase_client import (
    AppointmentInfo,
    fetch_appointment,
    fetch_appointments_for_remind,
    mark_reminder_sent,
)
from whatsapp import NotifyKind, WaResult, notify_status_change

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
log = logging.getLogger(__name__)

app = FastAPI(title="Salud Visual Notify Service", docs_url=None, redoc_url=None)

# ── Security guard ────────────────────────────────────────────────────────

def _require_secret(x_webhook_secret: str | None) -> None:
    cfg = get_settings()
    if not x_webhook_secret or x_webhook_secret != cfg.WEBHOOK_SECRET:
        raise HTTPException(status_code=403, detail="Forbidden")


# ── Timezone / date helpers ───────────────────────────────────────────────

def _fmt_date(dt: datetime, tz_name: str) -> str:
    try:
        from zoneinfo import ZoneInfo
        local = dt.astimezone(ZoneInfo(tz_name))
    except Exception:
        local = dt
    return local.strftime("%-d de %B").lower()   # "14 de mayo"


def _fmt_time(dt: datetime, tz_name: str) -> str:
    try:
        from zoneinfo import ZoneInfo
        local = dt.astimezone(ZoneInfo(tz_name))
    except Exception:
        local = dt
    return local.strftime("%H:%M")


# ── Email helper (Resend) ─────────────────────────────────────────────────

async def _send_email(*, to: str, subject: str, html: str, from_: str) -> None:
    cfg = get_settings()
    if not cfg.RESEND_API_KEY:
        log.info("[email] RESEND_API_KEY not set — skipping")
        return
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {cfg.RESEND_API_KEY}", "Content-Type": "application/json"},
            json={"from": from_, "to": [to], "subject": subject, "html": html},
        )
    if not r.is_success:
        log.error("[email] Resend %s: %s", r.status_code, r.text)


async def _notify_email(appt: AppointmentInfo, kind: NotifyKind) -> None:
    if not appt.client_email:
        return
    cfg = get_settings()
    from_ = f"{appt.clinic_name} <{cfg.NOTIFY_FROM_EMAIL}>"
    tz    = appt.clinic_tz
    date  = _fmt_date(appt.starts_at, tz)
    time  = _fmt_time(appt.starts_at, tz)

    subjects = {
        NotifyKind.CONFIRMED: f"Cita confirmada — {appt.clinic_name}",
        NotifyKind.CANCELLED: f"Cita cancelada — {appt.clinic_name}",
        NotifyKind.NO_SHOW:   f"Tu cita en {appt.clinic_name}",
        NotifyKind.REMIND_24: f"Recordatorio: cita mañana — {appt.clinic_name}",
        NotifyKind.REMIND_1:  f"Tu cita es en 1 hora — {appt.clinic_name}",
    }
    bodies = {
        NotifyKind.CONFIRMED: f"Hola {appt.client_name}, tu cita <b>{appt.title}</b> el {date} a las {time} en <b>{appt.clinic_name}</b> ha sido <b>confirmada</b>. ¡Te esperamos!",
        NotifyKind.CANCELLED: f"Hola {appt.client_name}, tu cita <b>{appt.title}</b> el {date} a las {time} en <b>{appt.clinic_name}</b> fue <b>cancelada</b>. Para reagendar comunícate con nosotros.",
        NotifyKind.NO_SHOW:   f"Hola {appt.client_name}, notamos que no asististe a tu cita del {date} a las {time}. Comunícate con nosotros para reagendar.",
        NotifyKind.REMIND_24: f"Hola {appt.client_name}, mañana tienes cita a las {time} ({date}) en <b>{appt.clinic_name}</b>. ¡Te esperamos!",
        NotifyKind.REMIND_1:  f"Hola {appt.client_name}, en 1 hora tienes tu cita a las {time} en <b>{appt.clinic_name}</b>. ¡Ya casi!",
    }

    await _send_email(
        to=appt.client_email,
        subject=subjects[kind],
        html=f"<p>{bodies[kind]}</p>",
        from_=from_,
    )


# ── Full notify (WA + email) ──────────────────────────────────────────────

async def _notify(appt: AppointmentInfo, kind: NotifyKind) -> dict:
    cfg     = get_settings()
    tz      = appt.clinic_tz
    date    = _fmt_date(appt.starts_at, tz)
    time    = _fmt_time(appt.starts_at, tz)
    results: dict[str, str] = {}

    if appt.client_phone:
        wa: WaResult = await notify_status_change(
            cfg,
            to=appt.client_phone,
            kind=kind,
            client_name=appt.client_name or "Cliente",
            appt_title=appt.title,
            date_str=date,
            time_str=time,
            clinic_name=appt.clinic_name,
        )
        results["whatsapp"] = "ok" if wa.ok else f"error: {wa.error}"
    else:
        results["whatsapp"] = "skipped (no phone)"

    await _notify_email(appt, kind)
    results["email"] = "sent" if appt.client_email else "skipped (no email)"

    return results


# ── Endpoints ─────────────────────────────────────────────────────────────

@app.get("/health")
async def health() -> dict:
    return {"ok": True}


# ── Meta WhatsApp webhook ─────────────────────────────────────────────────

@app.get("/wa/webhook")
async def wa_verify(request: Request):
    """Meta calls this once to verify the endpoint owns the verify token."""
    params           = request.query_params
    hub_mode         = params.get("hub.mode")
    hub_verify_token = params.get("hub.verify_token")
    hub_challenge    = params.get("hub.challenge")
    log.info("[wa-webhook] verify request — mode=%s token=%s", hub_mode, hub_verify_token)
    cfg = get_settings()
    if hub_mode == "subscribe" and hub_verify_token == cfg.WA_VERIFY_TOKEN:
        log.info("[wa-webhook] verification accepted")
        return PlainTextResponse(hub_challenge)
    log.warning("[wa-webhook] verification failed — mode=%s token=%s expected=%s", hub_mode, hub_verify_token, cfg.WA_VERIFY_TOKEN)
    raise HTTPException(status_code=403, detail="Forbidden")


@app.post("/wa/webhook")
async def wa_webhook(request: Request) -> dict:
    """Receives incoming messages and status updates from Meta."""
    body = await request.json()
    log.info("[wa-webhook] %s", body)

    for entry in body.get("entry", []):
        for change in entry.get("changes", []):
            value = change.get("value", {})

            # Incoming messages from users
            for msg in value.get("messages", []):
                from_number = msg.get("from")
                msg_type    = msg.get("type")
                text        = msg.get("text", {}).get("body", "") if msg_type == "text" else f"[{msg_type}]"
                log.info("[wa-webhook] message from %s: %s", from_number, text)

            # Delivery / read status updates
            for status in value.get("statuses", []):
                log.info("[wa-webhook] status %s → %s", status.get("id"), status.get("status"))

    return {"ok": True}


class StatusWebhookPayload(BaseModel):
    appointment_id: str
    new_status: Literal["confirmed", "cancelled", "no_show", "done", "scheduled"]
    old_status: str | None = None
    clinic_id:  str | None = None
    client_id:  str | None = None


@app.post("/webhook/appointment-status")
async def appointment_status_webhook(
    payload: StatusWebhookPayload,
    x_webhook_secret: str | None = Header(default=None),
) -> dict:
    _require_secret(x_webhook_secret)

    # Only notify on actionable statuses
    notifiable = {"confirmed", "cancelled", "no_show"}
    if payload.new_status not in notifiable:
        return {"ok": True, "skipped": f"status '{payload.new_status}' not notifiable"}

    cfg  = get_settings()
    appt = await fetch_appointment(cfg, payload.appointment_id)
    if not appt:
        log.warning("[webhook] appointment %s not found", payload.appointment_id)
        return {"ok": False, "error": "appointment not found"}

    if not appt.client_id:
        return {"ok": True, "skipped": "no client linked"}

    kind_map = {
        "confirmed": NotifyKind.CONFIRMED,
        "cancelled":  NotifyKind.CANCELLED,
        "no_show":    NotifyKind.NO_SHOW,
    }
    kind    = kind_map[payload.new_status]
    results = await _notify(appt, kind)

    log.info("[webhook] %s → %s | %s", payload.appointment_id, payload.new_status, results)
    return {"ok": True, "results": results}


@app.post("/remind")
async def send_reminders(
    x_webhook_secret: str | None = Header(default=None),
) -> dict:
    """
    Called by pg_cron every 30 min.
    Sends reminders for appointments in the ±30-min window around 24 h and 1 h.
    """
    _require_secret(x_webhook_secret)
    cfg = get_settings()
    now = datetime.now(timezone.utc)

    async def _process_window(
        from_dt: datetime,
        to_dt:   datetime,
        col:     str,
        kind:    NotifyKind,
    ) -> int:
        appts = await fetch_appointments_for_remind(
            cfg,
            from_iso=from_dt.isoformat(),
            to_iso=to_dt.isoformat(),
            reminder_col=col,
        )
        sent = 0
        for appt in appts:
            if not appt.client_id:
                continue
            res = await _notify(appt, kind)
            await mark_reminder_sent(cfg, appt.id, col)
            log.info("[remind] %s | %s | %s", appt.id, kind, res)
            sent += 1
        return sent

    sent_24 = await _process_window(
        from_dt=now + timedelta(hours=23),
        to_dt=  now + timedelta(hours=25),
        col="reminder_24h_sent",
        kind=NotifyKind.REMIND_24,
    )
    sent_1 = await _process_window(
        from_dt=now + timedelta(minutes=50),
        to_dt=  now + timedelta(minutes=70),
        col="reminder_1h_sent",
        kind=NotifyKind.REMIND_1,
    )

    return {"ok": True, "sent_24h": sent_24, "sent_1h": sent_1}
