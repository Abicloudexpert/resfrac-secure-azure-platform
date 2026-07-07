import json
from datetime import UTC, datetime

from shared.config import load_config
from shared.processor import summarize, write_heartbeat
from shared.storage import build_heartbeat, heartbeat_blob_name, serialize


class FakeRepo:
    """In-memory BlobRepository double."""

    def __init__(self):
        self.blobs: dict[str, dict[str, bytes]] = {}

    def upload(self, container: str, blob_name: str, data: bytes) -> None:
        self.blobs.setdefault(container, {})[blob_name] = data

    def count(self, container: str) -> int:
        return len(self.blobs.get(container, {}))


def make_config():
    return load_config(
        {
            "STORAGE_ACCOUNT_URL": "https://stresfractest.blob.core.windows.net",
            "HEARTBEAT_CONTAINER": "heartbeats",
            "ENVIRONMENT": "test",
            "SERVICE_NAME": "resfrac-func-test",
        }
    )


def test_write_heartbeat_persists_a_blob():
    config = make_config()
    repo = FakeRepo()
    now = datetime(2026, 7, 7, 9, 24, 0, tzinfo=UTC)

    result = write_heartbeat(config, repo, now=now)

    assert result["blob"] == "heartbeat-20260707T092400Z.json"
    stored = repo.blobs["heartbeats"][result["blob"]]
    payload = json.loads(stored)
    assert payload["service"] == "resfrac-func-test"
    assert payload["environment"] == "test"
    assert payload["type"] == "heartbeat"


def test_summarize_counts_heartbeats():
    config = make_config()
    repo = FakeRepo()
    write_heartbeat(config, repo, now=datetime(2026, 7, 7, 9, 0, tzinfo=UTC))
    write_heartbeat(config, repo, now=datetime(2026, 7, 7, 9, 5, tzinfo=UTC))

    summary = summarize(config, repo)

    assert summary["heartbeatCount"] == 2
    assert summary["container"] == "heartbeats"
    assert summary["service"] == "resfrac-func-test"


def test_serialize_is_compact_json():
    payload = build_heartbeat("svc", "env", datetime(2026, 1, 1, tzinfo=UTC))
    raw = serialize(payload)
    assert b" " not in raw  # compact separators
    assert json.loads(raw)["service"] == "svc"


def test_blob_name_is_timestamped():
    name = heartbeat_blob_name(datetime(2026, 12, 31, 23, 59, 59, tzinfo=UTC))
    assert name == "heartbeat-20261231T235959Z.json"


def test_storage_not_configured_flag():
    config = load_config({})
    assert config.storage_configured is False
