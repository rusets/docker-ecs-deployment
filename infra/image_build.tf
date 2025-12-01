resource "null_resource" "build_and_push_image" {
  triggers = {
    dockerfile_hash   = filesha256("${path.module}/../app/Dockerfile")
    package_json_hash = filesha256("${path.module}/../app/package.json")
    server_js_hash    = filesha256("${path.module}/../app/src/server.js")
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../app"
    command     = <<EOT
set -e

AWS_REGION="${var.region}"
REPO_URL="${aws_ecr_repository.this.repository_url}"
REGISTRY_URL="${local.ecr_registry_url}"
TAG="${local.app_image_tag}"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY_URL"

docker build --platform=linux/amd64 -t ecs-demo-app:"$TAG" .

docker tag ecs-demo-app:"$TAG" "$REPO_URL:$TAG"

docker push "$REPO_URL:$TAG"

echo "✅ Image pushed: $REPO_URL:$TAG"
EOT
  }
}
