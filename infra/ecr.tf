# infra/ecr.tf
#############################################
# ECR (repo + lifecycle policy)
#############################################

resource "aws_ecr_repository" "this" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE" # allow retagging 'latest'
  force_delete         = true      # destroy even if images remain

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }

  tags = { Project = var.project_name }
}

# Keep it clean: expire untagged, trim 'latest' images
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Expire untagged after 7 days",
        selection = {
          tagStatus   = "untagged",
          countType   = "sinceImagePushed",
          countUnit   = "days",
          countNumber = 7
        },
        action = { type = "expire" }
      },
      {
        rulePriority = 2,
        description  = "Keep last 10 'latest' images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["latest"],
          countType     = "imageCountMoreThan",
          countNumber   = 10
        },
        action = { type = "expire" }
      }
    ]
  })
}
