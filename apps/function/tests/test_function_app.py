"""Smoke tests over the actual Azure Functions bindings.

These import ``function_app`` (which imports ``azure.functions``) and invoke the
handlers directly with constructed binding objects — verifying the decorators,
routes, and handler wiring without the Functions host.
"""
import json

import azure.functions as func

import function_app


def test_functions_are_registered():
    names = {f.get_function_name() for f in function_app.app.get_functions()}
    assert {"timer_heartbeat", "http_summary", "http_health"}.issubset(names)


def test_http_health_returns_ok():
    req = func.HttpRequest(method="GET", url="/api/health", headers={}, params={}, body=b"")
    resp = function_app.http_health(req)
    assert resp.status_code == 200
    body = json.loads(resp.get_body())
    assert body["status"] == "ok"


def test_http_summary_503_when_storage_unconfigured(monkeypatch):
    monkeypatch.delenv("STORAGE_ACCOUNT_URL", raising=False)
    req = func.HttpRequest(method="GET", url="/api/summary", headers={}, params={}, body=b"")
    resp = function_app.http_summary(req)
    assert resp.status_code == 503
