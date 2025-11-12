#############################################
# Variables (tune cost/perf here)
#############################################

# Human-friendly project prefix used for names/tags of AWS resources
variable "project_name" {
  type        = string
  default     = "ecs-demo"
  description = "Name prefix applied to AWS resources (cluster/service/roles/etc.)."
}

# Primary region
variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources."
}

# Simple /16 VPC CIDR with two public /24 subnets (no NAT, public-only)
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

# Desired count of ECS tasks. Set to 0 to pay $0 when idle (Fargate).
variable "desired_count" {
  type        = number
  default     = 0
  description = "ECS desired tasks. 0 = fully idle (no Fargate charge)."
}

# Fargate task size (CPU units). 256 = 0.25 vCPU.
variable "task_cpu" {
  type    = string
  default = "256"
}

# Fargate task memory (MiB). 512 = 0.5GB.
variable "task_memory" {
  type    = string
  default = "512"
}

# Container port exposed by the app (Express listens on :80)
variable "app_port" {
  type        = number
  default     = 80
  description = "Application container port exposed via awsvpc ENI."
}

# ECR repo name (holds docker images for the app)
variable "ecr_repo_name" {
  type    = string
  default = "ecs-demo-app"
}

# Feature flags: HTTP “wake” endpoint (API GW + Lambda)
variable "enable_wake_api" {
  type    = bool
  default = true
}

# Feature flags: Auto-sleep Lambda (EventBridge cron each minute)
variable "enable_auto_sleep" {
  type    = bool
  default = true
}

# Auto-sleep delay (minutes since last RUNNING task)
variable "sleep_after_minutes" {
  type    = number
  default = 5
}

############################################
# Input variables
############################################




