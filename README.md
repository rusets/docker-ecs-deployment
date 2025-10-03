# Docker ECS Deployment — Fargate with Wake/Sleep (No ALB)

Run a tiny Node.js app on **Amazon ECS Fargate** with a public IP (no ALB).  
Scale down to zero when idle, and **wake on demand** via **API Gateway + Lambda**.

> ✅ Goals: minimal cost, simple infra, nice demo UI, autosleep, manual wake.

---

## 🗺️ Architecture

```mermaid
flowchart LR
  subgraph GitHub
    A1[CI — Build & Push to ECR\n(ci.yml)]
    A2[CD — Terraform Apply + Deploy/Destroy\n(cd.yml)]
    A3[OPS — Wake/Sleep ECS Service\n(ops.yml)]
  end

  subgraph AWS
    subgraph VPC
      E[ECS Service (Fargate)]
      C[Task/Container (Node.js)]
      SG[(Security Group)]
      Sub1[(Public Subnet A)]
      Sub2[(Public Subnet B)]
    end

    L[Lambda "wake"] -->|UpdateService(desired=1)| E
    EV[EventBridge rule (rate 1m)] -->|invoke| SLP[Lambda "autosleep"]
    SLP -->|UpdateService(desired=0)| E

    APIGW[API Gateway (HTTP API)] -->|proxy| L
  end

  user((User)) -->|open wake URL| APIGW
  A2 -->|terraform apply| AWS
  E -.public IP.-> user

  C -->|/health,/api| user
```

**Why no ALB?** For the cheapest always-public option in a demo: Fargate task gets a public IP directly, security group allows `:80`.

---

## 📁 Repository structure

```
.
├─ app/                   # Node.js demo app (Express)
│  ├─ Dockerfile
│  ├─ package.json
│  └─ src/server.js
├─ infra/                 # Terraform (VPC, ECS, API GW, Lambdas, EventBridge)
│  └─ main.tf
├─ wake/                  # Lambda "wake" (API Gateway handler)
│  └─ lambda_function.py
├─ autosleep/             # Lambda "autosleep"
│  └─ auto_sleep.py
├─ .github/workflows/
│  ├─ ci.yml              # CI — Build & Push to ECR
│  ├─ cd.yml              # CD — Terraform Apply + Deploy/Destroy
│  └─ ops.yml             # OPS — Wake/Sleep ECS Service
├─ make_zips.sh           # builds infra/wake.zip and infra/sleep.zip
└─ README.md
```

> **Tip:** `infra/wake.zip` and `infra/sleep.zip` must exist **before** `terraform apply`. Use `./make_zips.sh` locally or add a build step to `cd.yml`.

---

## 🧰 Prerequisites

- AWS account + S3 bucket & DynamoDB table for Terraform backend (see `infra/main.tf`).
- IAM role for **GitHub OIDC** with least-privilege (ECR/ECS/EC2/Lambda/API GW/Events + S3+DDB backend).
- Docker, AWS CLI, Terraform (for local runs).

---

## 🚀 Quick start (local)

```bash
# 1) Build lambda zips (must exist for TF)
./make_zips.sh

# 2) Terraform
cd infra
terraform init -input=false
terraform apply -auto-approve -input=false

# 3) Outputs
terraform output wake_url           # HTTP API to wake the service
terraform output ecr_repository_url # ECR URL for images
```

**Wake flow**  
Open `wake_url` in a browser → Lambda sets `desiredCount=1`, polls task ENI, and redirects to the task’s IP (or shows a “Warming up…” page with auto-retry until `WAIT_MS`).

**Auto-sleep**  
`autosleep` Lambda runs every minute. If the task uptime ≥ `sleep_after_minutes` (default **5**), the service scales to `0`.

---

## 🧪 GitHub Actions Workflows

### 1) **CI — Build & Push to ECR** (`.github/workflows/ci.yml`)
- Triggers on push to `main` (or tags).
- Logs in to ECR, builds Docker image from `app/`, pushes as `:latest` and `:${GIT_SHA}`.
- Useful outputs: the full `ECR_URL:TAG` for the CD job.

### 2) **CD — Terraform Apply + Deploy/Destroy** (`.github/workflows/cd.yml`)
- Manual **workflow_dispatch** with inputs:
  - `mode`: `apply` (provision + deploy) or `destroy` (cleanup).
  - `imageTag`: optional image tag (default `latest`).
- Steps (apply):
  1. `terraform init`
  2. Import existing ECR (if needed) to avoid state drift.
  3. `terraform apply`
  4. Assert image tag exists in ECR.
  5. Download current TaskDefinition JSON.
  6. Patch container image to the selected tag.
  7. Register new TaskDefinition.
  8. Update the ECS Service & **wait** for `services-stable`.
- Steps (destroy):
  - Scale ECS service to 0, delete CloudWatch log group, then `terraform destroy` (with guard to skip deleting API Gateway stage if a custom domain is mapped).

### 3) **OPS — Wake/Sleep ECS Service** (`.github/workflows/ops.yml`)
- Manual operational commands:
  - **Wake**: calls the Lambda/API to set `desired=1`.
  - **Sleep**: sets `desired=0`.
- Handy for quick manual interventions without touching Terraform.

---

## ⚙️ Terraform variables

| Variable               | Default     | Notes                                       |
|------------------------|-------------|---------------------------------------------|
| `project_name`         | `ecs-demo`  | Name prefix                                 |
| `region`               | `us-east-1` | AWS Region                                  |
| `app_port`             | `80`        | Container port                              |
| `task_cpu` / `task_memory` | `256` / `512` | Fargate task size                       |
| `desired_count`        | `0`         | 0 = idle on boot                            |
| `enable_wake_api`      | `true`      | API Gateway + Lambda (wake)                 |
| `enable_auto_sleep`    | `true`      | EventBridge + Lambda (autosleep)            |
| `sleep_after_minutes`  | `5`         | Scale to 0 after N minutes                  |
| `WAIT_MS` (Lambda env) | `120000`    | Total wait budget on the waiting page (ms)  |

---

## 🌐 Custom domain (optional)

- Buy a domain (e.g., **ecs-demo.online**).
- **Apex** (`ecs-demo.online`): use `A/AAAA` (or **ALIAS**) — **CNAME at apex is not allowed**.
- Subdomain (`app.ecs-demo.online`): you can use **CNAME** to a stable target (e.g., CloudFront or ALB).  
  This project redirects to **task public IP** after wake; if you want a stable hostname in the browser bar during wake, keep a public edge (CloudFront/ALB) up to proxy to the task once ready.

- TLS: issue an ACM certificate (DNS validation in Route 53). When deleting API GW `$default` stage, remove any **base path mappings** first.

---

## 💸 Costs (rough, us-east-1)

- Fargate task 0→1 sporadically: pay only when running (~$0.04–0.06/hr for 0.25 vCPU/0.5GB) + data out.
- Lambda + API Gateway + EventBridge: cents/month for tiny traffic.
- Route 53 hosted zone: ~$0.50/mo; DNS queries ~$0.40 per 1M (very low).
- ECR: first 500MB free tier, storage pennies after.

---

## 🛠 Troubleshooting

- **`ENOENT wake.zip/sleep.zip` in Terraform** → run `./make_zips.sh` first.
- **`iam:PassRole` / `lambda:GetPolicy` / `events:*` AccessDenied** → extend the OIDC role policy with:
  - `iam:PassRole` for Lambda roles (`wake-ecs-role`, `${project}-autosleep-role`)
  - `lambda:GetPolicy`, `lambda:ListVersionsByFunction`, `lambda:GetFunctionCodeSigningConfig`
  - `events:DescribeRule`, `events:ListTagsForResource`
  - `apigateway:*` as needed for stage reads/deletes (or skip deletes on destroy)
- **API GW `$default` stage deletion fails** → remove base path mappings first or guard in Terraform during `destroy`.

---

## 🧹 Clean up

```bash
# Optional: scale to 0
aws ecs update-service --cluster ecs-demo-cluster --service ecs-demo-svc --desired-count 0 --region us-east-1

# Terraform
cd infra
terraform destroy -auto-approve -input=false
```

If you mapped a custom API domain, remove the base path mapping before destroying the `$default` stage.

---

## 📄 License

MIT (or your preference)
