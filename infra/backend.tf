# Remote state in S3 with DynamoDB state locking
terraform {
  backend "s3" {
    bucket         = "docker-ecs-deployment"  # S3 bucket for tfstate
    key            = "ecs-demo/infra.tfstate" # Key (path) inside the bucket
    region         = "us-east-1"              # Bucket region
    dynamodb_table = "docker-ecs-deployment"  # Table for state locking
    encrypt        = true                     # Server-side encryption for state
  }
}
