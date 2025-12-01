# RUNBOOK: Auto-Sleep Issues (ECS Does Not Scale Down to Zero)

## Purpose
Handle cases where ECS does not automatically scale back to desiredCount=0 after inactivity.

---

## Symptoms
- ECS service stays at desiredCount=1
- ECS task keeps running indefinitely
- Autosleep Lambda logs show errors
- EventBridge rule is not triggering Lambda

---

## Step 1 — Check Autosleep Lambda Logs

aws logs tail /aws/lambda/ecs-demo-autosleep --region us-east-1 --follow

Common findings:
- AccessDeniedException
- ecs:ListTasks missing
- ecs:DescribeTasks missing
- ecs:UpdateService denied

---

## Step 2 — Check Autosleep Role Permissions

aws iam get-role-policy \
  --role-name ecs-demo-autosleep-role \
  --policy-name ecs-demo-autosleep-policy

Required permissions:
- ecs:DescribeServices
- ecs:ListTasks
- ecs:DescribeTasks
- ecs:UpdateService

---

## Step 3 — Manually Invoke Autosleep Lambda

aws lambda invoke \
  --function-name ecs-demo-autosleep \
  --region us-east-1 \
  --payload '{}' \
  /tmp/sleep.json

cat /tmp/sleep.json

Expected:
{"ok": true, "msg": "scaled to 0"}

If output says "already stopped" → ECS is idle.

---

## Step 4 — Verify EventBridge Rule

aws events list-rules --name-prefix ecs-demo-autosleep
aws events list-targets-by-rule --rule ecs-demo-autosleep

Expected:
State = ENABLED  
Target = autosleep Lambda ARN

---

## Step 5 — Check ECS Service State

aws ecs describe-services \
  --cluster ecs-demo-cluster \
  --services ecs-demo-svc \
  --region us-east-1 \
  --query '{Desired:services[0].desiredCount,Running:services[0].runningCount}'

If Desired remains 1 → autosleep Lambda cannot update the service.

---

## Step 6 — Final Steps
- Reapply Terraform
- Recreate execution roles if corrupted
- Re-register task definition

If issue persists → check CloudWatch logs for ECS task crashes.