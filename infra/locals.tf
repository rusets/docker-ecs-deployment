############################################
# Lambda Package — wake function
# Purpose: Build ZIP from source on terraform apply
############################################
data "archive_file" "wake_zip" {
  type        = "zip"
  source_file = "${path.root}/../wake/lambda_function.py"
  output_path = "${path.root}/../build/wake.zip"
}

############################################
# Lambda Package — autosleep function
# Purpose: Build ZIP from source on terraform apply
############################################
data "archive_file" "sleep_zip" {
  type        = "zip"
  source_file = "${path.root}/../autosleep/auto_sleep.py"
  output_path = "${path.root}/../build/sleep.zip"
}

############################################
# Image build locals — ECR registry + tag
############################################
locals {
  ecr_registry_url = split("/", aws_ecr_repository.this.repository_url)[0]
  app_image_tag    = "${substr(filesha256("${path.module}/../app/src/server.js"), 0, 8)}-amd64"
}
