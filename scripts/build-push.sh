#!/usr/bin/env bash
set -euo pipefail

############################################
# Build & Push Docker Image to ECR
# Purpose: build multi-arch image and push to AWS ECR from Terraform outputs
############################################

ECR_URL=$(terraform -chdir=infra output -raw ecr_repository_url)
REGISTRY=${ECR_URL%%/*}
TAG="${1:-latest}"
FULL_TAG="$ECR_URL:$TAG"

echo "Registry : [$REGISTRY]"
echo "Repo URL : [$ECR_URL]"
echo "Tag      : [$TAG]"
echo "Full tag : [$FULL_TAG]"

if [[ "$FULL_TAG" != *":"* ]]; then
  echo "❌ Invalid tag format. Expected: <repo>:<tag>" >&2
  exit 2
fi

aws ecr get-login-password --region us-east-1 \
| docker login --username AWS --password-stdin "$REGISTRY"

docker buildx create --use >/dev/null 2>&1 || true

docker buildx build --platform linux/arm64/v8 \
  -f app/Dockerfile \
  -t "$FULL_TAG" app \
  --push