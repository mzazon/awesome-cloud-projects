# AWS region for resource deployment
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
}

# Environment name for resource tagging and naming
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

# Project name prefix for resource naming
variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
  default     = "fargate-demo"
}

# Container image URI (will be set after ECR repository is created)
variable "container_image" {
  description = "Container image URI to deploy (defaults to nginx for initial deployment)"
  type        = string
  default     = "nginx:latest"
}

# ECS task CPU allocation (in CPU units)
variable "task_cpu" {
  description = "CPU units for the ECS task (256 = 0.25 vCPU, 512 = 0.5 vCPU, 1024 = 1 vCPU)"
  type        = number
  default     = 256
  
  validation {
    condition = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096"
  }
}

# ECS task memory allocation (in MB)
variable "task_memory" {
  description = "Memory for the ECS task in MB"
  type        = number
  default     = 512
  
  validation {
    condition = (
      (var.task_cpu == 256 && contains([512, 1024, 2048], var.task_memory)) ||
      (var.task_cpu == 512 && var.task_memory >= 1024 && var.task_memory <= 4096) ||
      (var.task_cpu == 1024 && var.task_memory >= 2048 && var.task_memory <= 8192) ||
      (var.task_cpu == 2048 && var.task_memory >= 4096 && var.task_memory <= 16384) ||
      (var.task_cpu == 4096 && var.task_memory >= 8192 && var.task_memory <= 30720)
    )
    error_message = "Memory must be compatible with CPU allocation. See AWS Fargate documentation for valid combinations."
  }
}

# Container port for the application
variable "container_port" {
  description = "Port on which the container application listens"
  type        = number
  default     = 3000
}

# Desired number of tasks to run
variable "desired_count" {
  description = "Desired number of ECS tasks to run"
  type        = number
  default     = 2
  
  validation {
    condition     = var.desired_count >= 1 && var.desired_count <= 20
    error_message = "Desired count must be between 1 and 20"
  }
}

# Auto-scaling configuration
variable "min_capacity" {
  description = "Minimum number of tasks for auto-scaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_capacity >= 1 && var.min_capacity <= var.max_capacity
    error_message = "Min capacity must be at least 1 and not greater than max capacity"
  }
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto-scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 50
    error_message = "Max capacity must be between 1 and 50"
  }
}

# CPU utilization target for auto-scaling
variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 50
  
  validation {
    condition     = var.cpu_target_value >= 10 && var.cpu_target_value <= 90
    error_message = "CPU target value must be between 10 and 90"
  }
}

# Enable ECR image scanning
variable "enable_ecr_scan" {
  description = "Enable vulnerability scanning for ECR images"
  type        = bool
  default     = true
}

# Health check configuration
variable "health_check_path" {
  description = "Path for container health checks"
  type        = string
  default     = "/health"
}

# VPC configuration (optional - will use default VPC if not provided)
variable "vpc_id" {
  description = "VPC ID for ECS deployment (uses default VPC if not provided)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS service (uses default subnets if not provided)"
  type        = list(string)
  default     = []
}

# Security group ingress CIDR blocks
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the container port"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified"
  }
}

# Log retention period
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period"
  }
}