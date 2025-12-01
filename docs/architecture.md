# Architecture Overview

docker-ecs-deployment
├── app/
│   ├── Dockerfile
│   ├── package.json
│   ├── package-lock.json
│   └── src/
│       └── server.js
│
├── autosleep/
│   └── auto_sleep.py                  # Auto-sleep Lambda source (Python)
│
├── wake/
│   └── lambda_function.py             # Wake Lambda source (Python)
│
├── build/
│   ├── wake.zip                       # Auto-built by Terraform (archive_file)
│   └── sleep.zip                      # Auto-built by Terraform
│
├── infra/                             # All Terraform infrastructure
│   ├── backend.tf                     # S3 + DynamoDB remote state backend
│   ├── providers.tf                   # AWS provider + versions (aws/null/archive)
│   ├── variables.tf                   # Input variables
│   ├── locals.tf                      # Derived locals (paths, ECR, image tag)
│   ├── networking.tf                  # VPC, subnets, security groups
│   ├── ecr.tf                         # ECR repository
│   ├── ecs.tf                         # ECS cluster, task definition, service
│   ├── image_build.tf                 # Terraform-driven Docker build & push
│   ├── wake.tf                        # Wake Lambda + API Gateway integration
│   ├── logs.tf                        # CloudWatch Log Groups
│   ├── api-mapping.tf                 # Optional API mappings (root, subdomain)
│   ├── main.tf                        # High-level resources assembly
│   └── outputs.tf                     # Exported values
│    
│
├── docs/
│   ├── architecture.md                # High-level system description
│   ├── cost.md
│   ├── monitoring.md
│   ├── slo.md
│   ├── threat-model.md
│   ├── adr/                           # Architecture Decision Records
│   │   ├── ADR-001-oidc-vs-access-keys.md
│   │   ├── ADR-002-single-az-vs-multi-az.md
│   │   ├── ADR-003-api-gateway-as-public-entrypoint.md
│   │   ├── ADR-004-ecs-fargate.md
│   │   └── ADR-005-autosleep-lambda-eventbridge.md
│   ├── diagrams
│   │   ├── architecture.md
│   │   └── sequence.md
│   ├── runbooks/
│   │   ├── RUNBOOK-wake-failures.md
│   │   ├── RUNBOOK-autosleep-issues.md
│   │   └── RUNBOOK-deployment-rollback.md
│   └── readme-screenshots/            # Images included in README
│       ├── 1-warming-up.png
│       ├── 2-app-running.png
│       ├── 3-ecs-service-awake.png
│       ├── 4-ecs-service-sleep.png
│       └── 5-autosleep-log.png
│
├── .github/
│   ├── ISSUE_TEMPLATE/              # Issue templates for GitHub UI
│   │   ├── bug.md
│   │   └── feature.md
│   ├── pull_request_template.md     # PR checklist & sections
│   └── workflows/                   # CI/CD/OPS GitHub Actions
│       ├── cd.yml                   # Terraform apply/destroy + deploy
│       ├── ci.yml                   # App build & push to ECR
│       ├── ops.yml                  # Wake/Sleep on demand
│       └── terraform-ci.yml         # Terraform lint/validate for PRs
│
├── .gitignore
├── .tflint.hcl
└── README.md

## 1. Components

### Compute
- Amazon ECS (Fargate)
- ECR registry
- Node.js App Container (x86_64)

### Network
- VPC (public-only)
- 2 public subnets
- Internet Gateway
- Security Group (App port only)

### API Layer
- API Gateway HTTP API  
  - Route: `GET /` → wake Lambda

### Lambda Functions
- **wake** — start ECS service, wait for app readiness  
- **autosleep** — detect idle and scale service to 0

### Automation
- EventBridge rule (every 1 minute) → autosleep Lambda
- GitHub Actions (OIDC):
  - CI — fmt, validate, tflint, tfsec, checkov  
  - CD — Terraform deploy/destroy, register new TaskDefinition  
  - OPS — Manual wake/sleep

### Logs
- `/ecs/ecs-demo`
- `/aws/lambda/ecs-demo-wake`
- `/aws/lambda/ecs-demo-autosleep`
- `/apigw/ecs-demo-wake`

---

## 2. Request Flow (Wake → App)

Client → API Gateway → wake Lambda → ECS UpdateService → Fargate Task → App

---

## 3. Autosleep Flow

EventBridge (1 minute) → autosleep Lambda → ECS (ListTasks / DescribeTasks) → scale service to 0 when idle
---

## 4. Destroy/Apply Cycle (Reproducible Infra)

`terraform destroy` removes all infrastructure created by this project  
(VPC, ECS, API Gateway, Lambdas, log groups, EventBridge, ECR, API mappings).

External DNS/ACM configuration for the custom domain is managed separately and is not touched.

`terraform apply` recreates the full stack:

- VPC  
- ECS cluster & service  
- Task Definition  
- API Gateway + routes  
- Lambdas  
- Logs  
- EventBridge  
- Docker image build & push via Terraform  

Everything is deterministic and reproducible.