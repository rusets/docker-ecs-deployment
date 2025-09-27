# 💸 ECS Fargate *No‑ALB* Starter (Ultra‑Cheap)

**Goal:** portfolio-friendly ECS app with **$0 while idle**.  
We run a single Fargate task with a **public IP** (no ALB). Default `desired_count=0`.

## Structure
```
.
├─ app/                 # Node server (your server.js)
│  ├─ Dockerfile
│  ├─ .dockerignore
│  ├─ package.json
│  └─ src/server.js
├─ infra/
│  └─ main.tf           # all Terraform in 1 file
├─ scripts/
│  └─ get-public-url.sh # prints http://<ip>:<port> of running task
└─ .github/workflows/
   ├─ deploy.yml        # build & push image, force new deployment
   └─ scale.yml         # manual scale up/down (0 or 1)
```

## Prereqs
- Terraform >= 1.6, AWS CLI, Docker
- AWS account in `us-east-1`
- **Optional:** create an OIDC role `github-actions-ecs-role` (least-privilege) for CI
- For zero-hassle state, this project uses local Terraform state by default
  (S3 backend example is commented in `infra/main.tf`).

## Deploy steps

### 1) Provision infra
```bash
cd infra
terraform init
terraform apply -auto-approve
```
Outputs will include: `ecr_repository_url`, `cluster_name`, `service_name`.

### 2) Build & push image (first time local; later via CI)
```bash
ECR_URL=$(terraform -chdir=infra output -raw ecr_repository_url)

aws ecr get-login-password --region us-east-1  | docker login --username AWS --password-stdin "$ECR_URL"

cd app
docker build -t "$ECR_URL:latest" .
docker push "$ECR_URL:latest"
```

### 3) Start the service (pay only while running)
```bash
aws ecs update-service   --cluster "$(terraform -chdir=infra output -raw cluster_name)"   --service "$(terraform -chdir=infra output -raw service_name)"   --desired-count 1 --region us-east-1
```

### 4) Get the public URL
```bash
./scripts/get-public-url.sh
# -> http://<public-ip>:80
```

Open the URL in a browser — you'll see your live dashboard.

### 5) Stop (go back to $0)
```bash
aws ecs update-service   --cluster "$(terraform -chdir=infra output -raw cluster_name)"   --service "$(terraform -chdir=infra output -raw service_name)"   --desired-count 0 --region us-east-1
```

## Notes
- Uses **ARM64** (Graviton) for lower price.
- CloudWatch log retention: **3 days**.
- Security group: allows **0.0.0.0/0** on app port (demo). Lock down for prod.
- If you prefer S3 backend for Terraform state, uncomment the backend block in `infra/main.tf`.

Enjoy the $0 idle! ✨
