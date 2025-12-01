# RUNBOOK: Deployment Rollback (ECS + ECR + Terraform)

## Purpose
Provide a safe procedure to revert a broken release when the newest image or task definition fails.

---

## Symptoms
- ECS task fails repeatedly (STOPPED loop)
- Wake Lambda redirects to a dead IP
- Application crashes after deployment
- CD workflow applied a broken task definition

---

## Step 1 — List Available Image Tags

aws ecr list-images \
  --repository-name ecs-demo-app \
  --region us-east-1 \
  --query 'imageIds[].imageTag'

Select the last known working tag.

---

## Step 2 — Fetch Current Task Definition

aws ecs describe-services \
  --cluster ecs-demo-cluster \
  --services ecs-demo-svc \
  --region us-east-1 \
  --query 'services[0].taskDefinition'

aws ecs describe-task-definition \
  --task-definition <TD_ARN> \
  --region us-east-1 \
  --query 'taskDefinition' > td.json

Replace the image with a known-good ECR tag inside td.json.

---

## Step 3 — Register Recovered Task Definition

aws ecs register-task-definition \
  --cli-input-json file://td.json \
  --region us-east-1

Copy the returned TaskDefinitionArn.

---

## Step 4 — Update ECS Service

aws ecs update-service \
  --cluster ecs-demo-cluster \
  --service ecs-demo-svc \
  --task-definition <NEW_TD_ARN> \
  --desired-count 1 \
  --region us-east-1

Wait for stabilization.

---

## Step 5 — Validate Wake Flow

Open:
https://api.ecs-demo.online/

Expected:
Redirect to working task IP.

---

## Step 6 — Restore Terraform Sync (Optional)
If Terraform state references old task definition:
- Update locals or variables
- Commit fix
- Re-run CD apply

This prevents Terraform from reintroducing a broken TD later.