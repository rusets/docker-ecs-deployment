import os
import time
import boto3

CLUSTER = os.environ["CLUSTER_NAME"]
SERVICE = os.environ["SERVICE_NAME"]
SLEEP_AFTER_MIN = int(os.environ.get("SLEEP_AFTER_MINUTES", "5"))

ecs = boto3.client("ecs")


def handler(event, context):
    svc = ecs.describe_services(cluster=CLUSTER, services=[
                                SERVICE])["services"][0]
    desired = svc.get("desiredCount", 0)
    running = svc.get("runningCount", 0)

    if desired == 0 or running == 0:
        return {"ok": True, "msg": "already stopped or no tasks"}

    tasks_arns = ecs.list_tasks(
        cluster=CLUSTER, serviceName=SERVICE, desiredStatus="RUNNING").get("taskArns", [])
    if not tasks_arns:
        return {"ok": True, "msg": "no running tasks"}

    tasks = ecs.describe_tasks(cluster=CLUSTER, tasks=tasks_arns)["tasks"]

    now = time.time()
    min_uptime = min([(now - t["startedAt"].timestamp()) /
                     60 for t in tasks if "startedAt" in t], default=0)

    if min_uptime >= SLEEP_AFTER_MIN:
        ecs.update_service(cluster=CLUSTER, service=SERVICE, desiredCount=0)
        return {"ok": True, "stopped": True, "uptime_min": round(min_uptime, 1)}

    return {"ok": True, "skipped": True, "uptime_min": round(min_uptime, 1)}
