"""
Thin async Supabase REST client — only the queries this service needs.
Avoids the supabase-py sync client; uses httpx directly.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx

from config import Settings

log = logging.getLogger(__name__)


@dataclass
class AppointmentInfo:
    id:          str
    title:       str
    starts_at:   datetime
    ends_at:     datetime
    status:      str
    clinic_id:   str
    clinic_name: str
    clinic_tz:   str
    client_id:   str | None
    client_name: str | None
    client_phone: str | None
    client_email: str | None


def _sb_headers(cfg: Settings) -> dict[str, str]:
    return {
        "apikey":        cfg.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {cfg.SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type":  "application/json",
        "Accept":        "application/vnd.pgrst.object+json",  # single-row mode
    }


async def fetch_appointment(cfg: Settings, appointment_id: str) -> AppointmentInfo | None:
    """
    Joins appointments → clients → clinics in a single PostgREST call.
    Returns None if not found.
    """
    url = (
        f"{cfg.SUPABASE_URL}/rest/v1/appointments"
        f"?id=eq.{appointment_id}"
        f"&select=id,title,starts_at,ends_at,status,clinic_id,client_id,"
        f"clients(name,phone,email),"
        f"clinics(name,timezone)"
    )
    headers = {
        **_sb_headers(cfg),
        "Accept": "application/json",  # list mode (filter gives one row)
    }

    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(url, headers=headers)

    if not r.is_success:
        log.error("[sb] fetch_appointment %s → %s %s", appointment_id, r.status_code, r.text)
        return None

    rows = r.json()
    if not rows:
        return None

    row     = rows[0]
    clinic  = row.get("clinics") or {}
    cl      = row.get("clients") or {}

    return AppointmentInfo(
        id           = row["id"],
        title        = row.get("title") or "(sin título)",
        starts_at    = datetime.fromisoformat(row["starts_at"].replace("Z", "+00:00")),
        ends_at      = datetime.fromisoformat(row["ends_at"].replace("Z", "+00:00")),
        status       = row.get("status", "scheduled"),
        clinic_id    = row["clinic_id"],
        clinic_name  = clinic.get("name", "Óptica"),
        clinic_tz    = clinic.get("timezone", "America/Monterrey"),
        client_id    = row.get("client_id"),
        client_name  = cl.get("name"),
        client_phone = cl.get("phone"),
        client_email = cl.get("email"),
    )


async def fetch_appointments_for_remind(
    cfg: Settings,
    *,
    from_iso: str,
    to_iso: str,
    reminder_col: str,  # "reminder_24h_sent" or "reminder_1h_sent"
) -> list[AppointmentInfo]:
    """
    Returns appointments within [from_iso, to_iso) that haven't had
    the specified reminder sent yet and are in an active status.
    """
    url = (
        f"{cfg.SUPABASE_URL}/rest/v1/appointments"
        f"?starts_at=gte.{from_iso}"
        f"&starts_at=lt.{to_iso}"
        f"&{reminder_col}=eq.false"
        f"&status=in.(scheduled,confirmed)"
        f"&select=id,title,starts_at,ends_at,status,clinic_id,client_id,"
        f"clients(name,phone,email),"
        f"clinics(name,timezone)"
    )
    headers = {**_sb_headers(cfg), "Accept": "application/json"}

    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(url, headers=headers)

    if not r.is_success:
        log.error("[sb] fetch_remind → %s %s", r.status_code, r.text)
        return []

    result = []
    for row in r.json():
        clinic = row.get("clinics") or {}
        cl     = row.get("clients") or {}
        result.append(AppointmentInfo(
            id           = row["id"],
            title        = row.get("title") or "(sin título)",
            starts_at    = datetime.fromisoformat(row["starts_at"].replace("Z", "+00:00")),
            ends_at      = datetime.fromisoformat(row["ends_at"].replace("Z", "+00:00")),
            status       = row.get("status", "scheduled"),
            clinic_id    = row["clinic_id"],
            clinic_name  = clinic.get("name", "Óptica"),
            clinic_tz    = clinic.get("timezone", "America/Monterrey"),
            client_id    = row.get("client_id"),
            client_name  = cl.get("name"),
            client_phone = cl.get("phone"),
            client_email = cl.get("email"),
        ))
    return result


async def mark_reminder_sent(cfg: Settings, appointment_id: str, col: str) -> None:
    url = f"{cfg.SUPABASE_URL}/rest/v1/appointments?id=eq.{appointment_id}"
    headers = {**_sb_headers(cfg), "Accept": "application/json", "Prefer": "return=minimal"}
    async with httpx.AsyncClient(timeout=10) as client:
        await client.patch(url, headers=headers, json={col: True})
