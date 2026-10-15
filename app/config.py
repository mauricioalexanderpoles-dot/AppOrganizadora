"""Configuración única de AppOrganizadora.

No hay singleton global: crear_app() construye un Settings y lo inyecta. En los tests
se pasa un Settings(...) con valores falsos sin tocar el entorno.

Orden de prioridad (pydantic-settings): variables de entorno > fichero .env > defaults.
En Docker las variables llegan por env_file y el .env no está dentro de la imagen;
en desarrollo local se lee el .env del directorio actual.
"""
from __future__ import annotations

from pathlib import Path
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",   # variables ajenas en el entorno no rompen el arranque
        frozen=True,      # la configuración no cambia en caliente
    )

    # ── Seguridad ──
    api_key_mobile: SecretStr

    # ── OpenAI ──
    openai_api_key: SecretStr
    openai_modelo: str = Field(min_length=1)
    openai_timeout_segundos: float = Field(default=30.0, gt=0, le=120)

    # ── Google ──
    google_token_path: Path = Path("/app/secrets/token.json")
    google_client_secret_path: Path = Path("/app/secrets/client_secret.json")
    duracion_evento_minutos: int = Field(default=60, ge=5, le=24 * 60)

    # ── Datos y localización ──
    db_path: Path = Path("/app/data/organizadora.db")
    zona_horaria: str = "Europe/Madrid"

    # ── Agenda ──
    dias_eventos: int = Field(default=7, ge=1, le=60)
    cache_agenda_segundos: int = Field(default=60, ge=0, le=3600)

    # ── Worker ──
    worker_max_intentos: int = Field(default=5, ge=1, le=20)
    worker_backoff_base_segundos: float = Field(default=5.0, gt=0)
    worker_backoff_max_segundos: float = Field(default=300.0, gt=0)
    worker_espera_max_segundos: float = Field(default=30.0, gt=0, le=300)

    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"

    # ── Validaciones (fail-fast: mejor no arrancar que arrancar mal) ──

    @field_validator("api_key_mobile")
    @classmethod
    def _api_key_robusta(cls, v: SecretStr) -> SecretStr:
        if len(v.get_secret_value()) < 32:
            raise ValueError("API_KEY_MOBILE debe tener al menos 32 caracteres")
        return v

    @field_validator("openai_api_key")
    @classmethod
    def _openai_no_vacia(cls, v: SecretStr) -> SecretStr:
        if not v.get_secret_value().strip():
            raise ValueError("OPENAI_API_KEY está vacía")
        return v

    @field_validator("zona_horaria")
    @classmethod
    def _zona_valida(cls, v: str) -> str:
        try:
            ZoneInfo(v)  # requiere el paquete tzdata en la imagen slim
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise ValueError(f"Zona horaria desconocida: {v!r}") from exc
        return v

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.zona_horaria)  # ZoneInfo cachea internamente
