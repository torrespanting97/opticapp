import os
from functools import lru_cache

from dotenv import load_dotenv
load_dotenv()


class Settings:
    # Meta WhatsApp Business Cloud API
    # https://developers.facebook.com/docs/whatsapp/cloud-api
    WA_ACCESS_TOKEN:    str = os.getenv("WA_ACCESS_TOKEN", "")      # permanent token from Meta Business
    WA_PHONE_NUMBER_ID: str = os.getenv("WA_PHONE_NUMBER_ID", "")   # numeric ID, not the phone number
    WA_API_VERSION:     str = os.getenv("WA_API_VERSION", "v20.0")
    WA_VERIFY_TOKEN:    str = os.getenv("WA_VERIFY_TOKEN", "")      # any string you choose; entered in Meta portal

    # Resend (email)
    RESEND_API_KEY:     str = os.getenv("RESEND_API_KEY", "")
    NOTIFY_FROM_EMAIL:  str = os.getenv("NOTIFY_FROM_EMAIL", "noreply@saludvisual.app")

    # Supabase
    SUPABASE_URL:             str = os.environ["SUPABASE_URL"]
    SUPABASE_SERVICE_ROLE_KEY: str = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

    # Webhook security — must match value stored in Supabase DB settings
    WEBHOOK_SECRET: str = os.environ["WEBHOOK_SECRET"]

    # Clinic timezone default (override per-clinic from DB)
    DEFAULT_TZ: str = os.getenv("DEFAULT_TZ", "America/Monterrey")


@lru_cache
def get_settings() -> Settings:
    return Settings()
