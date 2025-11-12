# infra/networking.tf
#############################################
# Networking (VPC with two PUBLIC subnets)
#############################################

# Discover at least two AZs in the region
data "aws_availability_zones" "available" {}

# Minimal-cost VPC: only public subnets, no NAT
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.2.0"

  name                 = var.project_name
  cidr                 = var.vpc_cidr
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets       = var.public_subnets
  enable_nat_gateway   = false # Save cost: no NAT
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Security group allowing HTTP inbound and all outbound
resource "aws_security_group" "service" {
  name_prefix = "${var.project_name}-svc-"
  vpc_id      = module.vpc.vpc_id

  # Inbound: world -> app port
  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: allow everything (needed for ECR pull, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = var.project_name }
}
