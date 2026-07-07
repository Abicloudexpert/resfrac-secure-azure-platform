"""Environment-driven configuration for the Function app.

No secrets are stored here. The Storage account is reached via the account
URL + Managed Identity (DefaultAzureCredential), so there are no storage
keys or connection strings containing secrets in configuration.
"""
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class FunctionConfig:
    storage_account_url: str
    heartbeat_container: str
    environment: str
    service_name: str

    @property
    def storage_configured(self) -> bool:
        return bool(self.storage_account_url)


def load_config(env: dict | None = None) -> FunctionConfig:
    env = env if env is not None else os.environ
    return FunctionConfig(
        # e.g. https://stresfracdev.blob.core.windows.net
        storage_account_url=env.get("STORAGE_ACCOUNT_URL", ""),
        heartbeat_container=env.get("HEARTBEAT_CONTAINER", "heartbeats"),
        environment=env.get("ENVIRONMENT", "development"),
        service_name=env.get("SERVICE_NAME", "resfrac-func"),
    )
