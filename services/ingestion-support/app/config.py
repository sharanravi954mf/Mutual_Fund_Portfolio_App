from __future__ import annotations

from functools import lru_cache
from urllib.parse import urlparse

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def _trusted_provider_url(value: str) -> str:
    parsed = urlparse(value)
    is_local = parsed.hostname in {"localhost", "127.0.0.1"}
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("provider URL must not contain credentials, query, or fragment")
    if parsed.scheme != "https" and not (parsed.scheme == "http" and is_local):
        raise ValueError("provider URL must use HTTPS or explicit localhost HTTP")
    if not parsed.hostname:
        raise ValueError("provider URL requires a host")
    return value.rstrip("/")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=None,
        extra="ignore",
        case_sensitive=True,
    )

    mailbox_connector_service_token: str = Field(
        min_length=32, validation_alias="MAILBOX_CONNECTOR_SERVICE_TOKEN"
    )
    pdf_text_extractor_service_token: str = Field(
        min_length=32, validation_alias="PDF_TEXT_EXTRACTOR_SERVICE_TOKEN"
    )
    malware_scanner_service_token: str = Field(
        min_length=32, validation_alias="MALWARE_SCANNER_SERVICE_TOKEN"
    )
    gmail_oauth_client_id: str = Field(min_length=3, validation_alias="GMAIL_OAUTH_CLIENT_ID")
    gmail_oauth_client_secret: str = Field(
        min_length=8, validation_alias="GMAIL_OAUTH_CLIENT_SECRET"
    )
    gmail_oauth_redirect_uri: str = Field(
        min_length=12, validation_alias="GMAIL_OAUTH_REDIRECT_URI"
    )

    gmail_oauth_authorization_url: str = Field(
        default="https://accounts.google.com/o/oauth2/v2/auth",
        validation_alias="GMAIL_OAUTH_AUTHORIZATION_URL",
    )
    gmail_oauth_token_url: str = Field(
        default="https://oauth2.googleapis.com/token",
        validation_alias="GMAIL_OAUTH_TOKEN_URL",
    )
    gmail_oauth_revocation_url: str = Field(
        default="https://oauth2.googleapis.com/revoke",
        validation_alias="GMAIL_OAUTH_REVOCATION_URL",
    )
    gmail_api_base_url: str = Field(
        default="https://gmail.googleapis.com/gmail/v1",
        validation_alias="GMAIL_API_BASE_URL",
    )
    allowed_hosts: str = Field(
        default="localhost,127.0.0.1,testserver,ingestion-support",
        validation_alias="ALLOWED_HOSTS",
    )
    clamav_host: str = Field(default="clamav", validation_alias="CLAMAV_HOST")
    clamav_port: int = Field(default=3310, ge=1, le=65535, validation_alias="CLAMAV_PORT")
    clamav_timeout_seconds: float = Field(
        default=5.0, gt=0, le=30, validation_alias="CLAMAV_TIMEOUT_SECONDS"
    )
    provider_timeout_seconds: float = Field(
        default=5.0, gt=0, le=30, validation_alias="PROVIDER_TIMEOUT_SECONDS"
    )
    request_body_timeout_seconds: float = Field(
        default=10.0, gt=0, le=60, validation_alias="REQUEST_BODY_TIMEOUT_SECONDS"
    )
    pdf_timeout_seconds: float = Field(
        default=10.0, gt=0, le=60, validation_alias="PDF_TIMEOUT_SECONDS"
    )
    max_json_body_bytes: int = Field(
        default=65_536, ge=1024, le=1_048_576, validation_alias="MAX_JSON_BODY_BYTES"
    )
    max_provider_response_bytes: int = Field(
        default=1_048_576,
        ge=1024,
        le=4_194_304,
        validation_alias="MAX_PROVIDER_RESPONSE_BYTES",
    )
    max_attachment_bytes: int = Field(
        default=20_971_519,
        ge=1024,
        le=20_971_519,
        validation_alias="MAX_ATTACHMENT_BYTES",
    )
    max_pdf_bytes: int = Field(
        default=20_971_519, ge=1024, le=20_971_519, validation_alias="MAX_PDF_BYTES"
    )
    max_pdf_response_bytes: int = Field(
        default=1_048_576,
        ge=1024,
        le=4_194_304,
        validation_alias="MAX_PDF_RESPONSE_BYTES",
    )
    max_pdf_rows: int = Field(default=5000, ge=1, le=20_000, validation_alias="MAX_PDF_ROWS")
    max_mailbox_messages: int = Field(
        default=25, ge=1, le=100, validation_alias="MAX_MAILBOX_MESSAGES"
    )
    max_mailbox_pages_per_poll: int = Field(
        default=4,
        ge=1,
        le=20,
        validation_alias="MAX_MAILBOX_PAGES_PER_POLL",
    )
    max_mailbox_candidates_per_poll: int = Field(
        default=100,
        ge=1,
        le=1000,
        validation_alias="MAX_MAILBOX_CANDIDATES_PER_POLL",
    )
    gmail_detail_fetch_concurrency: int = Field(
        default=5,
        ge=1,
        le=10,
        validation_alias="GMAIL_DETAIL_FETCH_CONCURRENCY",
    )
    max_attachments_per_message: int = Field(
        default=5, ge=1, le=20, validation_alias="MAX_ATTACHMENTS_PER_MESSAGE"
    )
    mailbox_token_cache_ttl_seconds: int = Field(
        default=300,
        ge=30,
        le=900,
        validation_alias="MAILBOX_TOKEN_CACHE_TTL_SECONDS",
    )
    mailbox_token_cache_max_entries: int = Field(
        default=256,
        ge=1,
        le=4096,
        validation_alias="MAILBOX_TOKEN_CACHE_MAX_ENTRIES",
    )

    @field_validator(
        "gmail_oauth_authorization_url",
        "gmail_oauth_token_url",
        "gmail_oauth_revocation_url",
        "gmail_api_base_url",
    )
    @classmethod
    def validate_provider_url(cls, value: str) -> str:
        return _trusted_provider_url(value)

    @field_validator("gmail_oauth_redirect_uri")
    @classmethod
    def validate_redirect_uri(cls, value: str) -> str:
        parsed = urlparse(value)
        is_local = parsed.hostname in {"localhost", "127.0.0.1"}
        if (
            not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or (parsed.scheme != "https" and not (parsed.scheme == "http" and is_local))
        ):
            raise ValueError("GMAIL_OAUTH_REDIRECT_URI must be an exact HTTPS callback URI")
        return value

    @model_validator(mode="after")
    def validate_separate_tokens(self) -> Settings:
        tokens = {
            self.mailbox_connector_service_token,
            self.pdf_text_extractor_service_token,
            self.malware_scanner_service_token,
        }
        if len(tokens) != 3:
            raise ValueError("service bearer tokens must be distinct")
        return self

    @property
    def trusted_hosts(self) -> list[str]:
        hosts = [host.strip() for host in self.allowed_hosts.split(",") if host.strip()]
        if not hosts or "*" in hosts:
            raise ValueError("ALLOWED_HOSTS must contain explicit hosts")
        return hosts


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
