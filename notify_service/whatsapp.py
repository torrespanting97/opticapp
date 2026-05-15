"""
Meta WhatsApp Business Cloud API client (free tier).

Free tier: ~1,000 service conversations / month.

Two message modes:
  • free_text   — works only inside a 24-h customer-service window
                  (i.e. the client messaged you first).
  • template    — business-initiated; requires an approved template in
                  Meta Business Manager. Use this for reminders /
                  confirmations sent without a prior client message.

In this implementation we always try free_text first and fall back to
a generic template if the API rejects the request (error code 131026 /
"outside the 24-hour window").  Create the template once in Meta Business
Manager and set WA_TEMPLATE_NAME in your .env (default: "appointment_notify").
"""

import logging
from dataclasses import dataclass
from enum import StrEnum

import httpx

from config import Settings

log = logging.getLogger(__name__)

_BASE = "https://graph.facebook.com/{version}/{phone_id}/messages"


class NotifyKind(StrEnum):
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"
    NO_SHOW   = "no_show"
    REMIND_24 = "remind_24h"
    REMIND_1  = "remind_1h"


# ── Message builders ──────────────────────────────────────────────────────

def _body(kind: NotifyKind, name: str, title: str, date: str, time: str, clinic: str) -> str:
    match kind:
        case NotifyKind.CONFIRMED:
            return (
                f"Hola {name} 👋, tu cita *{title}* el {date} a las {time} "
                f"en *{clinic}* ha sido *confirmada*. ¡Te esperamos!"
            )
        case NotifyKind.CANCELLED:
            return (
                f"Hola {name}, lamentamos informarte que tu cita *{title}* "
                f"el {date} a las {time} en *{clinic}* fue *cancelada*. "
                "Para reagendar comunícate con nosotros."
            )
        case NotifyKind.NO_SHOW:
            return (
                f"Hola {name}, notamos que no pudiste asistir a tu cita del "
                f"{date} a las {time} en *{clinic}*. "
                "Comunícate con nosotros para reagendar."
            )
        case NotifyKind.REMIND_24:
            return (
                f"Recordatorio 📅: Hola {name}, mañana tienes cita a las {time} "
                f"({date}) en *{clinic}*. ¡Te esperamos!"
            )
        case NotifyKind.REMIND_1:
            return (
                f"⏰ Hola {name}, en 1 hora tienes tu cita a las {time} "
                f"en *{clinic}*. ¡Ya casi!"
            )


@dataclass
class WaResult:
    ok: bool
    message_id: str | None = None
    error: str | None = None


# ── Send helpers ──────────────────────────────────────────────────────────

async def send_text(
    cfg: Settings,
    to: str,
    body: str,
    *,
    template_name: str | None = None,
    template_lang: str = "es_MX",
    template_params: list[str] | None = None,
) -> WaResult:
    """
    Send a WhatsApp message.  Tries free-form text first; if the API
    returns error 131026 (outside 24-h window), retries with the
    fallback template (if configured).
    """
    url = _BASE.format(
        version=cfg.WA_API_VERSION,
        phone_id=cfg.WA_PHONE_NUMBER_ID,
    )
    headers = {
        "Authorization": f"Bearer {cfg.WA_ACCESS_TOKEN}",
        "Content-Type":  "application/json",
    }

    # Normalise phone: strip non-digits then prepend country code if needed
    phone = "".join(c for c in to if c.isdigit())
    if phone.startswith("0"):
        phone = "52" + phone[1:]   # Mexico local → international
    elif not phone.startswith("52") and len(phone) == 10:
        phone = "52" + phone       # bare 10-digit MX number

    payload_text = {
        "messaging_product": "whatsapp",
        "to":   phone,
        "type": "text",
        "text": {"body": body, "preview_url": False},
    }

    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.post(url, headers=headers, json=payload_text)
        data = r.json()

        # Outside 24-h window → try template fallback
        if (
            r.status_code == 400
            and template_name
            and _is_window_error(data)
        ):
            log.info("[wa] outside 24h window — falling back to template %s", template_name)
            components = []
            if template_params:
                components = [{
                    "type": "body",
                    "parameters": [{"type": "text", "text": p} for p in template_params],
                }]
            payload_tpl = {
                "messaging_product": "whatsapp",
                "to":   phone,
                "type": "template",
                "template": {
                    "name":     template_name,
                    "language": {"code": template_lang},
                    "components": components,
                },
            }
            r = await client.post(url, headers=headers, json=payload_tpl)
            data = r.json()

        if r.is_success:
            msg_id = data.get("messages", [{}])[0].get("id")
            return WaResult(ok=True, message_id=msg_id)

        log.error("[wa] error %s: %s", r.status_code, data)
        return WaResult(ok=False, error=str(data.get("error", data)))


def _is_window_error(body: dict) -> bool:
    err = body.get("error", {})
    # 131026 = message not deliverable (outside 24h window)
    # 131047 = re-engagement message
    return err.get("code") in (131026, 131047)


# ── High-level helpers ────────────────────────────────────────────────────

async def notify_status_change(
    cfg: Settings,
    *,
    to: str,
    kind: NotifyKind,
    client_name: str,
    appt_title: str,
    date_str: str,
    time_str: str,
    clinic_name: str,
) -> WaResult:
    body = _body(kind, client_name, appt_title, date_str, time_str, clinic_name)
    import os
    tpl = os.getenv("WA_TEMPLATE_NAME") or None
    params = [client_name, appt_title, date_str, time_str, clinic_name]
    return await send_text(cfg, to, body, template_name=tpl, template_params=params)
