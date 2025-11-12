#############################################
# Terraform backend + providers
#############################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws",
      version = ">= 5.0"
    }
  }
}


# Default AWS region comes from var.region
provider "aws" {
  region = var.region
}

