# autosleep/auto_sleep.py
# -----------------------------------------------------------------------------
# Purpose:
#   Lambda function that periodically checks an ECS service and, if all running
#   tasks have been up for at least SLEEP_AFTER_MINUTES, scales the service
#   down to desiredCount=0 (i.e., "sleeps" it to save cost).
#
# How it’s used:
#   - Triggered by EventBridge rule on a schedule (e.g., rate(1 minute)).
#   - Reads target cluster/service and the threshold minutes from environment.
#   - Safe to run repeatedly: if the service is already stopped or has no
#     running tasks, it exits without changes.
#
# Notes:
#   - This function is intentionally side-effect-free unless the threshold is
#     met; it only calls UpdateService when it’s time to sleep.
#   - We choose the *minimum* uptime among running tasks; that means we won’t
#     sleep until even the newest task has been running long enough.
#   - IAM requirements for the Lambda role:
#       ecs:DescribeServices, ecs:ListTasks, ecs:DescribeTasks, ecs:UpdateService
#     (plus standard CloudWatch Logs permissions).
# -----------------------------------------------------------------------------

import os
import time
import boto3

# --- Configuration from environment variables ---
# The ECS cluster name to operate on (e.g., "ecs-demo-cluster").
CLUSTER = os.environ["CLUSTER_NAME"]
# The ECS service name within that cluster (e.g., "ecs-demo-svc").
SERVICE = os.environ["SERVICE_NAME"]
# How many minutes a task should run before we consider auto-sleeping.
# Default is 5 minutes if not provided.
SLEEP_AFTER_MIN = int(os.environ.get("SLEEP_AFTER_MINUTES", "5"))

# ECS client (uses Lambda’s execution role credentials and region from env).
ecs = boto3.client("ecs")


def handler(event, context):
    """
    EventBridge entry point.

    Logic:
      1) Describe the ECS service → read current desiredCount and runningCount.
         - If the service is already stopped (desired=0) OR nothing is running,
           we do nothing and exit.
      2) List running tasks and describe them to get startedAt timestamps.
      3) Compute the minimum uptime (minutes) among all running tasks.
         - If that minimum uptime >= SLEEP_AFTER_MIN, scale service to 0.
         - Otherwise, skip (not enough idle time yet).

    Returns a small JSON object for quick inspection in logs.
    """

    # Get current service status (desired vs running replicas).
    svc = ecs.describe_services(
        cluster=CLUSTER,
        services=[SERVICE]
    )["services"][0]
    desired = svc.get("desiredCount", 0)  # target replicas
    running = svc.get("runningCount", 0)  # actual running tasks

    # If already stopped OR nothing is running, there is nothing to do.
    if desired == 0 or running == 0:
        return {"ok": True, "msg": "already stopped or no tasks"}

    # Get ARNs of RUNNING tasks for this service.
    tasks_arns = ecs.list_tasks(
        cluster=CLUSTER,
        serviceName=SERVICE,
        desiredStatus="RUNNING"
    ).get("taskArns", [])
    if not tasks_arns:
        # Defensive: if DescribeServices said running>0 but list returns none.
        return {"ok": True, "msg": "no running tasks"}

    # Describe tasks to fetch start times.
    tasks = ecs.describe_tasks(cluster=CLUSTER, tasks=tasks_arns)["tasks"]

    # Compute uptime (in minutes) for each task that has startedAt.
    # We take the MIN uptime so we don't sleep until *all* tasks are older
    # than the threshold (prevents sleeping right after a new deployment).
    now = time.time()
    min_uptime = min(
        [
            (now - t["startedAt"].timestamp()) / 60
            for t in tasks
            if "startedAt" in t
        ],
        default=0
    )

    # If every running task is older than the threshold → scale to zero.
    if min_uptime >= SLEEP_AFTER_MIN:
        ecs.update_service(cluster=CLUSTER, service=SERVICE, desiredCount=0)
        return {"ok": True, "stopped": True, "uptime_min": round(min_uptime, 1)}

    # Otherwise, keep the service as-is and report current minimum uptime.
    return {"ok": True, "skipped": True, "uptime_min": round(min_uptime, 1)}
