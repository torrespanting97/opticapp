"""
Quick WhatsApp send test — runs directly without the FastAPI server.
Usage:  python test_wa.py +521234567890
"""
import asyncio
import sys
from dotenv import load_dotenv
load_dotenv()

from config import get_settings
from whatsapp import NotifyKind, notify_status_change


async def main():
    if len(sys.argv) < 2:
        print("Usage: python test_wa.py +521234567890")
        sys.exit(1)

    to = sys.argv[1]
    cfg = get_settings()

    print(f"Sending test WhatsApp to {to} …")
    result = await notify_status_change(
        cfg,
        to=to,
        kind=NotifyKind.CONFIRMED,
        client_name="Cliente Prueba",
        appt_title="Examen de la Vista",
        date_str="15 de mayo",
        time_str="10:00",
        clinic_name="Óptica Salud Visual",
    )

    if result.ok:
        print(f"✓ Sent — message_id: {result.message_id}")
    else:
        print(f"✗ Failed — {result.error}")


asyncio.run(main())
