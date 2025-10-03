# wake/lambda_function.py
import os
import time
import html
import urllib.parse
from datetime import datetime, timezone

import boto3
from botocore.config import Config

REGION = os.getenv("AWS_REGION", "us-east-1")
CLUSTER_NAME = os.getenv("CLUSTER_NAME", "ecs-demo-cluster")
SERVICE_NAME = os.getenv("SERVICE_NAME", "ecs-demo-svc")
APP_PORT = int(os.getenv("APP_PORT", "80"))
# Total wait budget across retries (default: 3 minutes)
WAIT_MS = int(os.getenv("WAIT_MS", "180000"))

_cfg = Config(retries={"max_attempts": 3,
              "mode": "standard"}, region_name=REGION)
ecs = boto3.client("ecs", config=_cfg)
ec2 = boto3.client("ec2", config=_cfg)


def _now_ms() -> int:
    return int(datetime.now(tz=timezone.utc).timestamp() * 1000)


def _qs_get(event, key, default=None):
    qs = event.get("queryStringParameters") or {}
    return qs.get(key, default)


def _redirect(url: str):
    # 302 + small HTML fallback
    body = f"""<!doctype html>
<meta charset="utf-8">
<title>Redirecting…</title>
<meta http-equiv="refresh" content="0;url={html.escape(url)}">
<body style="font-family:system-ui,Segoe UI,Roboto;margin:40px">
<h1>Ready! Redirecting…</h1>
<p>If the redirect didn’t happen automatically, click:
  <a href="{html.escape(url)}">{html.escape(url)}</a>
</p>
</body>"""
    return {
        "statusCode": 302,
        "headers": {"Location": url, "Content-Type": "text/html; charset=utf-8"},
        "body": body,
    }


def _waiting_page(api_url: str, started_ms: int, elapsed_ms: int):
    secs_elapsed = elapsed_ms // 1000
    secs_total = WAIT_MS // 1000

    # Auto-retry every 3s, preserving original start timestamp (?s=...)
    s_param = urllib.parse.quote_plus(str(started_ms))
    retry_url = f"{api_url}?s={s_param}"

    body = f"""<!doctype html>
<meta charset="utf-8">
<title>Warming up the service…</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body{{font-family:system-ui,Segoe UI,Roboto;margin:40px;line-height:1.45}}
  .card{{max-width:680px;margin:auto;padding:24px;border:1px solid #e5e7eb;border-radius:16px;box-shadow:0 4px 16px rgba(0,0,0,.06)}}
  .row{{display:flex;align-items:center;gap:16px}}
  .spinner{{width:28px;height:28px;border:4px solid #e5e7eb;border-top-color:#111827;border-radius:50%;animation:spin 1s linear infinite}}
  @keyframes spin{{to{{transform:rotate(360deg)}}}}
  .muted{{color:#6b7280}}
  .pill{{display:inline-block;padding:4px 10px;border-radius:999px;background:#f3f4f6;color:#374151;font-size:12px}}
  button{{padding:10px 16px;border:1px solid #e5e7eb;border-radius:10px;background:white;cursor:pointer}}
</style>
<body>
  <div class="card">
    <div class="row">
      <div class="spinner" aria-hidden="true"></div>
      <h1 style="margin:0">Warming up the service…</h1>
    </div>
    <p class="muted" style="margin-top:8px">
      A cold start may take 10–120 seconds.
    </p>
    <p style="margin:16px 0 8px">
      Progress: <span class="pill">{secs_elapsed}s / ~{secs_total}s</span>
    </p>
    <div class="row" style="margin-top:8px">
      <button onclick="location.reload()">Refresh manually</button>
      <button onclick="location.href='{html.escape(retry_url)}'">Try again</button>
    </div>
    <p class="muted" style="margin-top:16px;font-size:14px">
      This page will auto-refresh.
    </p>
  </div>
<script>
  setTimeout(function(){{
    window.location.replace("{html.escape(retry_url)}");
  }}, 3000);
</script>
</body>"""
    return {"statusCode": 200, "headers": {"Content-Type": "text/html; charset=utf-8"}, "body": body}


def _ensure_desired_one():
    try:
        ecs.update_service(cluster=CLUSTER_NAME,
                           service=SERVICE_NAME, desiredCount=1)
    except Exception:
        # Ignore race/permission errors; we'll still attempt to read status
        pass


def _get_public_ip_from_running_task():
    svc = ecs.describe_services(cluster=CLUSTER_NAME, services=[
                                SERVICE_NAME])["services"][0]
    if (svc.get("runningCount") or 0) < 1:
        return None

    tasks_arns = ecs.list_tasks(
        cluster=CLUSTER_NAME, serviceName=SERVICE_NAME, desiredStatus="RUNNING"
    ).get("taskArns") or []
    if not tasks_arns:
        return None

    td = ecs.describe_tasks(cluster=CLUSTER_NAME, tasks=[tasks_arns[0]])
    t = (td.get("tasks") or [None])[0] or {}
    attachments = t.get("attachments") or []
    for att in attachments:
        if att.get("type") == "ElasticNetworkInterface":
            details = {d["name"]: d["value"] for d in att.get(
                "details", []) if "name" in d and "value" in d}
            eni_id = details.get("networkInterfaceId")
            if not eni_id:
                continue
            eni = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])[
                "NetworkInterfaces"][0]
            pub_ip = (eni.get("Association") or {}).get("PublicIp")
            if pub_ip:
                return pub_ip
            priv_ip = eni.get("PrivateIpAddress")
            if priv_ip:
                return priv_ip
    return None


def _current_api_url(event) -> str:
    """Build absolute URL back to this Lambda via API Gateway HTTP API (v2)."""
    req_ctx = event.get("requestContext", {})
    domain = req_ctx.get("domainName", "")
    stage = req_ctx.get("stage", "")
    raw_path = event.get("rawPath", "/")
    if stage and stage != "$default":
        base = f"https://{domain}/{stage}"
    else:
        base = f"https://{domain}"
    return base + raw_path


def handler(event, context):
    # Compute elapsed time across retries
    try:
        started_ms = int(_qs_get(event, "s") or _now_ms())
    except Exception:
        started_ms = _now_ms()
    elapsed_ms = max(_now_ms() - started_ms, 0)

    # Always request desiredCount=1 (idempotent)
    _ensure_desired_one()

    # Try a quick poll loop within this single Lambda run (<= ~2–3s total)
    deadline = time.monotonic() + 2.5
    ip = None
    while time.monotonic() < deadline:
        ip = _get_public_ip_from_running_task()
        if ip:
            break
        time.sleep(0.4)

    if ip:
        # Build final URL (hide :80 if default HTTP)
        if APP_PORT in (80, 443):
            url = f"http://{ip}" if APP_PORT == 80 else f"https://{ip}"
        else:
            url = f"http://{ip}:{APP_PORT}"
        return _redirect(url)

    # Not ready yet → waiting page with auto-retry within the global WAIT budget
    api_url = _current_api_url(event)
    if elapsed_ms < WAIT_MS:
        return _waiting_page(api_url, started_ms, elapsed_ms)

    # Budget exceeded → gentle fallback
    body = f"""<!doctype html>
<meta charset="utf-8">
<title>Timeout</title>
<body style="font-family:system-ui,Segoe UI,Roboto;margin:40px">
<h1>Looks like the container is taking longer than usual to start.</h1>
<p>Try again: <a href="{html.escape(api_url)}">{html.escape(api_url)}</a></p>
<p class="muted" style="color:#6b7280">Tip: increase WAIT_MS via Lambda env or Terraform.</p>
</body>"""
    return {"statusCode": 200, "headers": {"Content-Type": "text/html; charset=utf-8"}, "body": body}
