
############################################
# Availability Zones — discover at least two in the region
############################################
data "aws_availability_zones" "available" {}

############################################
# VPC Module — public-only subnets, DNS enabled, no NAT gateways
############################################
#tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.2.0"

  name                 = var.project_name
  cidr                 = var.vpc_cidr
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets       = var.public_subnets
  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  ##########################################
  # VPC Flow Logs → CloudWatch Logs
  ##########################################
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60
}


############################################
# Security Group — ECS service
# Purpose: Public HTTP to app, egress all
############################################
resource "aws_security_group" "service" {
  name_prefix = "${var.project_name}-svc-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ECS Fargate demo service"

  #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  ingress {
    description = "Allow public HTTP traffic to the demo application"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #tfsec:ignore:aws-ec2-no-public-egress-sgr
  egress {
    description = "Allow ECS tasks to access the internet and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}
