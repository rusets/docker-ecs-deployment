# wake/auto_sleep.py
import os, boto3
from datetime import datetime, timezone, timedelta

ecs = boto3.client("ecs")

CLUSTER = os.environ["CLUSTER_NAME"]
SERVICE = os.environ["SERVICE_NAME"]
SLEEP_AFTER_MIN = int(os.environ.get("SLEEP_AFTER_MINUTES", "5"))

def handler(event, context):
    # 1) Проверяем сервис
    svc = ecs.describe_services(cluster=CLUSTER, services=[SERVICE])["services"][0]
    desired = svc.get("desiredCount", 0)
    running = svc.get("runningCount", 0)

    # Если уже спит — ничего не делаем
    if desired == 0 and running == 0:
        return {"ok": True, "message": "Service already sleeping"}

    # 2) Берем раннящиеся таски и их startedAt
    tasks_arns = ecs.list_tasks(
        cluster=CLUSTER,
        serviceName=SERVICE,
        desiredStatus="RUNNING"
    ).get("taskArns", [])

    if not tasks_arns:
        # Нет RUNNING — можно усыпить на всякий
        ecs.update_service(cluster=CLUSTER, service=SERVICE, desiredCount=0)
        return {"ok": True, "action": "sleep", "reason": "No running tasks"}

    td = ecs.describe_tasks(cluster=CLUSTER, tasks=tasks_arns)
    now = datetime.now(timezone.utc)
    threshold = now - timedelta(minutes=SLEEP_AFTER_MIN)

    # Если ЛЮБОЙ таск старше порога — усыпляем
    for t in td.get("tasks", []):
        started = t.get("startedAt")
        if started and started < threshold:
            ecs.update_service(cluster=CLUSTER, service=SERVICE, desiredCount=0)
            return {
                "ok": True,
                "action": "sleep",
                "reason": f"Task {t.get('taskArn')} startedAt={started.isoformat()} < {threshold.isoformat()}",
            }

    return {"ok": True, "message": "Still within active window"}
