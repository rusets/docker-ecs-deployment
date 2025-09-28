#!/usr/bin/env bash
set -euo pipefail

CLUSTER="ecs-demo-cluster"
SERVICE="ecs-demo-svc"
REGION="us-east-1"

echo "Cluster: $CLUSTER"
echo "Service: $SERVICE"
echo "Region : $REGION"

echo "⏳ Waiting for a RUNNING task..."
for i in {1..90}; do
  TASKS=$(aws ecs list-tasks \
    --cluster "$CLUSTER" \
    --service-name "$SERVICE" \
    --region "$REGION" \
    --desired-status RUNNING \
    --query 'taskArns' \
    --output text)
  if [ -n "$TASKS" ] && [ "$TASKS" != "None" ]; then
    echo "✅ Found tasks: $TASKS"
    break
  fi
  sleep 5
done

if [ -z "${TASKS:-}" ] || [ "$TASKS" = "None" ]; then
  echo "❌ No RUNNING tasks found"
  exit 1
fi

IP=""
PRIV=""
for T in $TASKS; do
  for j in {1..60}; do
    PRIV=$(aws ecs describe-tasks \
      --cluster "$CLUSTER" \
      --tasks "$T" \
      --region "$REGION" \
      --query "tasks[0].containers[0].networkInterfaces[0].privateIpv4Address" \
      --output text 2>/dev/null || echo "")
    if [ -n "$PRIV" ] && [ "$PRIV" != "None" ]; then
      PUB=$(aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --filters "Name=addresses.private-ip-address,Values=$PRIV" \
        --query 'NetworkInterfaces[0].Association.PublicIp' \
        --output text 2>/dev/null || echo "")
      if [ -n "$PUB" ] && [ "$PUB" != "None" ]; then
        IP="$PUB"
        break
      fi
    fi
    sleep 5
  done
  [ -n "$IP" ] && break
done

if [ -n "$IP" ] && [ "$IP" != "None" ]; then
  echo "🌍 Public URL: http://$IP"
else
  echo "⚠️ Could not resolve Public IP"
  if [ -n "$PRIV" ] && [ "$PRIV" != "None" ]; then
    echo "ℹ️ Private IP (VPC only): http://$PRIV"
  fi
fi