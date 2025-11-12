############################################
# Backend — Remote state in S3 with DynamoDB locking
# Purpose: Store Terraform state in S3 (encrypted) and coordinate locks via DynamoDB
############################################
terraform {
  backend "s3" {
    bucket         = "docker-ecs-deployment"
    key            = "ecs-demo/infra.tfstate"
    region         = "us-east-1"
    dynamodb_table = "docker-ecs-deployment"
    encrypt        = true
  }
}
