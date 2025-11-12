#############################################
# Variables (tune cost/perf here)
#############################################

variable "project_name" {
  type        = string
  default     = "ecs-demo"
  description = "Name prefix applied to AWS resources (cluster/service/roles/etc.)."
}


variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources."
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}


variable "desired_count" {
  type        = number
  default     = 0
  description = "ECS desired tasks. 0 = fully idle (no Fargate charge)."
}

variable "task_cpu" {
  type    = string
  default = "256"
}


variable "task_memory" {
  type    = string
  default = "512"
}


variable "app_port" {
  type        = number
  default     = 80
  description = "Application container port exposed via awsvpc ENI."
}


variable "ecr_repo_name" {
  type    = string
  default = "ecs-demo-app"
}


variable "enable_wake_api" {
  type    = bool
  default = true
}


variable "enable_auto_sleep" {
  type    = bool
  default = true
}


variable "sleep_after_minutes" {
  type    = number
  default = 5
}




