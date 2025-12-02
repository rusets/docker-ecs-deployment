# Architecture Overview

```text
docker-ecs-deployment/
├── .checkov.yml                      # Checkov config (policy-as-code for Terraform)
├── .gitignore                        # Git ignore rules (builds, .terraform/, logs, IDE)
├── .tflint.hcl                       # TFLint config (Terraform lint rules)
├── LICENSE                           # Project license (MIT)
├── README.md                         # Main project documentation
│
├── app/                              # Node.js demo application (Express)
│   ├── Dockerfile                    # App container image definition
│   ├── package.json                  # Node.js dependencies and scripts
│   ├── package-lock.json             # Locked dependency versions
│   └── src/
│       └── server.js                 # Express HTTP API entrypoint
│
├── autosleep/                        # Auto-sleep Lambda source (Python)
│   └── auto_sleep.py                 # Stops ECS service when idle
│
├── wake/                             # Wake Lambda source (Python)
│   └── lambda_function.py            # Starts ECS service on demand
│
├── build/                            # Terraform-built Lambda bundles (gitignored)
│   ├── wake.zip                      # Packaged wake Lambda (archive_file)
│   └── sleep.zip                     # Packaged autosleep Lambda (archive_file)
│
├── infra/                            # All Terraform infrastructure
│   ├── backend.tf                    # S3 + DynamoDB remote state backend
│   ├── providers.tf                  # AWS provider + versions (aws/archive/random)
│   ├── variables.tf                  # Input variables
│   ├── locals.tf                     # Derived locals (paths, names, image tags)
│   ├── networking.tf                 # VPC, subnets, security groups
│   ├── ecr.tf                        # ECR repository for app image
│   ├── ecs.tf                        # ECS cluster, task definition, service
│   ├── image_build.tf                # Terraform-driven Docker build & push to ECR
│   ├── wake.tf                       # Wake/Autosleep Lambdas + EventBridge + IAM
│   ├── logs.tf                       # CloudWatch Log Groups for app and Lambdas
│   ├── api-mapping.tf                # API Gateway + custom domain / mappings
│   ├── main.tf                       # High-level module wiring / orchestration
│   └── outputs.tf                    # Exported values (URLs, ARNs, IDs)
│
├── docs/                             # Architecture, ops, and security documentation
│   ├── architecture.md               # High-level system diagram and flow
│   ├── cost.md                       # Cost model and optimization notes
│   ├── monitoring.md                 # Metrics, logs, and alerting strategy
│   ├── slo.md                        # SLOs / SLIs for the service
│   ├── threat-model.md               # Threat model and security assumptions
│   ├── adr/                          # Architecture Decision Records
│   │   ├── ADR-001-oidc-vs-access-keys.md
│   │   ├── ADR-002-single-az-vs-multi-az.md
│   │   ├── ADR-003-api-gateway-as-public-entrypoint.md
│   │   ├── ADR-004-ecs-fargate.md
│   │   └── ADR-005-autosleep-lambda-eventbridge.md
│   ├── diagrams/                     # Text diagrams for README / docs
│   │   ├── architecture.md           # Mermaid-style architecture diagram
│   │   └── sequence.md               # Wake / autosleep sequence diagram
│   ├── runbooks/                     # Operational runbooks
│   │   ├── RUNBOOK-wake-failures.md
│   │   ├── RUNBOOK-autosleep-issues.md
│   │   └── RUNBOOK-deployment-rollback.md
│   └── readme-screenshots/           # Screenshots embedded in README
│       ├── 1-warming-up.png
│       ├── 2-app-running.png
│       ├── 3-ecs-service-awake.png
│       ├── 4-ecs-service-sleep.png
│       └── 5-autosleep-log.png
│
└── .github/                          # GitHub configuration and workflows
    ├── ISSUE_TEMPLATE/               # Issue templates for GitHub UI
    │   ├── bug.md
    │   └── feature.md
    ├── pull_request_template.md      # PR checklist & structure
    └── workflows/                    # CI/CD and ops GitHub Actions
        ├── ci.yml                    # App build & push to ECR
        ├── cd.yml                    # Terraform apply/destroy + deploy
        ├── ops.yml                   # Manual wake/sleep operations
        └── terraform-ci.yml          # Terraform lint/validate for PRs
```

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