"""ResFrac Python Azure Function (v2 programming model).

Triggers:
  * timer_heartbeat  – runs every 5 minutes, writes a heartbeat blob to Storage.
  * http_summary     – GET /api/summary, returns heartbeat statistics.
  * http_health      – GET /api/health, dependency-free liveness probe.

All application logs are emitted via the standard ``logging`` module and are
forwarded to Application Insights automatically by the Functions host when
``APPLICATIONINSIGHTS_CONNECTION_STRING`` is set on the Function App.
"""
import json
import logging

import azure.functions as func

from shared.config import load_config
from shared.processor import summarize, write_heartbeat
from shared.storage import AzureBlobRepository

app = func.FunctionApp()

logger = logging.getLogger("resfrac.func")


def _repo(config):
    return AzureBlobRepository(account_url=config.storage_account_url)


@app.function_name(name="timer_heartbeat")
@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False)
def timer_heartbeat(timer: func.TimerRequest) -> None:
    config = load_config()
    if timer.past_due:
        logger.warning("timer is past due")
    if not config.storage_configured:
        logger.error("STORAGE_ACCOUNT_URL not configured; skipping heartbeat")
        return
    result = write_heartbeat(config, _repo(config))
    logger.info("timer_heartbeat completed: %s", result["blob"])


@app.function_name(name="http_summary")
@app.route(route="summary", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
def http_summary(req: func.HttpRequest) -> func.HttpResponse:
    config = load_config()
    if not config.storage_configured:
        return func.HttpResponse(
            json.dumps({"error": "storage_not_configured"}),
            status_code=503,
            mimetype="application/json",
        )
    try:
        body = summarize(config, _repo(config))
        return func.HttpResponse(
            json.dumps(body), status_code=200, mimetype="application/json"
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("http_summary failed")
        return func.HttpResponse(
            json.dumps({"error": "internal_error", "detail": str(exc)}),
            status_code=500,
            mimetype="application/json",
        )


@app.function_name(name="http_health")
@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def http_health(req: func.HttpRequest) -> func.HttpResponse:
    config = load_config()
    return func.HttpResponse(
        json.dumps({"status": "ok", "service": config.service_name, "env": config.environment}),
        status_code=200,
        mimetype="application/json",
    )
