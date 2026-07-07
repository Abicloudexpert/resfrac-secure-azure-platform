"""Pure-ish business logic orchestrating storage interactions.

Kept free of Azure Functions bindings so it can be unit-tested with a fake
``BlobRepository``. All logging goes through the standard ``logging`` module,
which the Functions host automatically forwards to Application Insights when
``APPLICATIONINSIGHTS_CONNECTION_STRING`` is configured.
"""
from __future__ import annotations

import logging
from datetime import UTC, datetime

from .config import FunctionConfig
from .storage import (
    BlobRepository,
    build_heartbeat,
    heartbeat_blob_name,
    serialize,
)

logger = logging.getLogger("resfrac.func")


def write_heartbeat(
    config: FunctionConfig,
    repo: BlobRepository,
    now: datetime | None = None,
) -> dict:
    """Write a heartbeat blob and return the payload (used by the timer trigger)."""
    now = now or datetime.now(UTC)
    payload = build_heartbeat(config.service_name, config.environment, now)
    blob_name = heartbeat_blob_name(now)
    repo.upload(config.heartbeat_container, blob_name, serialize(payload))
    logger.info(
        "heartbeat written",
        extra={"custom_dimensions": {"blob": blob_name, "container": config.heartbeat_container}},
    )
    return {"blob": blob_name, **payload}


def summarize(config: FunctionConfig, repo: BlobRepository) -> dict:
    """Return a summary of stored heartbeats (used by the HTTP trigger)."""
    count = repo.count(config.heartbeat_container)
    logger.info(
        "summary computed",
        extra={"custom_dimensions": {"container": config.heartbeat_container, "count": count}},
    )
    return {
        "service": config.service_name,
        "environment": config.environment,
        "container": config.heartbeat_container,
        "heartbeatCount": count,
        "timestamp": datetime.now(UTC).isoformat(),
    }
