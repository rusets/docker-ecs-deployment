#!/usr/bin/env bash
# scripts/get-public-url.sh
# Scale service to 1 if needed, wait for RUNNING, print http://<public-ip>:<port>

set -euo pipefail

# --- Config (can be overridden via env or args) ---
PORT="${APP_PORT:-80}"
TIMEOUT_SEC="${TIMEOUT_SEC:-600}"   # сколько максимум ждать (по умолч. 10 мин)

# Если переданы позиционные: cluster service [region] [port]
CLUSTER="${1:-}"
SERVICE="${2:-}"
REGION="${3:-${AWS_REGION:-}}"
if [[ -n "${4:-}" ]]; then PORT="$4"; fi

# --- Helpers ---
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
infra_dir="$repo_root/infra"

tf_out() {
  local key="$1"
  terraform -chdir="$infra_dir" output -raw "$key" 2>/dev/null || true
}

# Подтягиваем значения из terraform outputs, если не пришли аргументами
CLUSTER="${CLUSTER:-$(tf_out cluster_name)}"
SERVICE="${SERVICE:-$(tf_out service_name)}"
REGION="${REGION:-$(tf_out region)}"

if [[ -z "$CLUSTER" || -z "$SERVICE" || -z "$REGION" ]]; then
  echo "Missing CLUSTER/SERVICE/REGION. Pass as args: get-public-url.sh <cluster> <service> [region] [port]" >&2
  exit 1
fi

echo "Cluster: $CLUSTER"
echo "Service: $SERVICE"
echo "Region : $REGION"
echo "Port   : $PORT"

# --- Ensure service desiredCount = 1 ---
current_desired="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].desiredCount' --output text 2>/dev/null || echo 0)"
if [[ "$current_desired" -lt 1 || "$current_desired" == "None" ]]; then
  echo "Scaling service to desiredCount=1…"
  aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 1 --region "$REGION" >/dev/null
fi

# --- Wait for at least one RUNNING task ---
echo "Waiting for a RUNNING task (timeout ${TIMEOUT_SEC}s)…"
end=$((SECONDS + TIMEOUT_SEC))
running="0"
while [[ $SECONDS -lt $end ]]; do
  running="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].runningCount' --output text 2>/dev/null || echo 0)"
  pending="$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].pendingCount' --output text 2>/dev/null || echo 0)"
  echo "running=$running pending=$pending"
  if [[ "$running" -ge 1 ]]; then break; fi
  sleep 6
done
if [[ "$running" -lt 1 ]]; then
  echo "Timeout waiting for RUNNING task" >&2
  exit 2
fi

# --- Pick first RUNNING task ARN ---
task_arn="$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" --desired-status RUNNING --region "$REGION" --query 'taskArns[0]' --output text)"
if [[ -z "$task_arn" || "$task_arn" == "None" ]]; then
  echo "No RUNNING tasks found after wait" >&2
  exit 3
fi

# --- Get ENI and Public IP ---
eni_id="$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$task_arn" --region "$REGION" \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value | [0]' --output text)"

if [[ -z "$eni_id" || "$eni_id" == "None" ]]; then
  echo "ENI not found. Ensure awsvpc networking and assign_public_ip=true" >&2
  exit 4
fi

public_ip="$(aws ec2 describe-network-interfaces --network-interface-ids "$eni_id" --region "$REGION" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)"

if [[ -z "$public_ip" || "$public_ip" == "None" ]]; then
  echo "Public IP not found. Check subnets and assign_public_ip=true" >&2
  exit 5
fi

url="http://$public_ip:$PORT"
echo "URL: $url"