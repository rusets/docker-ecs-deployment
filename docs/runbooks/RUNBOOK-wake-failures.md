# RUNBOOK: Wake API Failures (ECS Service Does Not Scale Up)

## Purpose
Handle cases where calling the Wake API fails to start the ECS service or redirect the user to the running task.

---

## Symptoms
- Wake API returns:
  - {"message": "Internal Server Error"}
  - HTTP 500 responses
- No redirect to the task public IP
- ECS desiredCount remains 0
- Lambda logs show permission or timeout errors

---

## Step 1 — Check Wake Lambda Logs

aws logs tail /aws/lambda/ecs-demo-wake --region us-east-1 --follow

Common findings:
- AccessDeniedException
- ServiceNotFoundException
- TaskDefinition not found
- Timed out waiting for ECS stabilization

---

## Step 2 — Verify ECS Service State

aws ecs describe-services \
  --cluster ecs-demo-cluster \
  --services ecs-demo-svc \
  --region us-east-1 \
  --query "services[0].{Desired:desiredCount,Running:runningCount}"

Expected:
Desired=1 after wake
Running=1 within ~30 seconds

---

## Step 3 — Manually Trigger the Wake Lambda

aws lambda invoke \
  --function-name ecs-demo-wake \
  --region us-east-1 \
  --payload '{}' \
  /tmp/wake.json

cat /tmp/wake.json

If manual invoke works → issue is API Gateway integration.

---

## Step 4 — Verify Lambda Permissions

aws iam get-role-policy \
  --role-name ecs-demo-wake-role \
  --policy-name ecs-demo-wake-policy

Required:
- ecs:UpdateService
- ecs:DescribeServices

---

## Step 5 — Verify API Gateway → Lambda Integration

aws apigatewayv2 get-integrations --api-id <API_ID>

Common issues:
- Wrong integration type
- Wrong route key
- Wrong Lambda ARN binding

---

## Step 6 — Final Check
Open:

https://api.ecs-demo.online/

Expected:
Redirect to ECS task public IP.