"""Storage access via Managed Identity (passwordless).

``BlobServiceClient`` is built from the account URL and a token credential
(``DefaultAzureCredential``). In Azure this resolves to the Function App's
system-assigned identity, which is granted the ``Storage Blob Data Contributor``
role on the account (least privilege) — no account keys are ever used.
"""
from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Protocol


class BlobRepository(Protocol):
    def upload(self, container: str, blob_name: str, data: bytes) -> None: ...
    def count(self, container: str) -> int: ...


class AzureBlobRepository:
    """Thin, dependency-injectable wrapper over ``BlobServiceClient``.

    The client is created lazily so importing this module never requires
    Azure connectivity (keeps unit tests hermetic).
    """

    def __init__(self, account_url: str, client=None, credential=None):
        self._account_url = account_url
        self._client = client
        self._credential = credential

    def _get_client(self):
        if self._client is not None:
            return self._client
        # Imported lazily to keep the offline test path free of Azure SDKs.
        from azure.identity import DefaultAzureCredential
        from azure.storage.blob import BlobServiceClient

        credential = self._credential or DefaultAzureCredential()
        self._client = BlobServiceClient(account_url=self._account_url, credential=credential)
        return self._client

    def _get_container(self, container: str):
        client = self._get_client()
        container_client = client.get_container_client(container)
        try:
            container_client.create_container()
        except Exception:  # noqa: BLE001 - container already exists is expected
            pass
        return container_client

    def upload(self, container: str, blob_name: str, data: bytes) -> None:
        container_client = self._get_container(container)
        container_client.upload_blob(name=blob_name, data=data, overwrite=True)

    def count(self, container: str) -> int:
        container_client = self._get_container(container)
        return sum(1 for _ in container_client.list_blobs())


def build_heartbeat(service_name: str, environment: str, now: datetime | None = None) -> dict:
    ts = (now or datetime.now(UTC)).isoformat()
    return {
        "service": service_name,
        "environment": environment,
        "type": "heartbeat",
        "timestamp": ts,
    }


def heartbeat_blob_name(now: datetime | None = None) -> str:
    ts = now or datetime.now(UTC)
    return f"heartbeat-{ts.strftime('%Y%m%dT%H%M%SZ')}.json"


def serialize(payload: dict) -> bytes:
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")
