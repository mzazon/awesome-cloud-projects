# General Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Networking Configuration
variable "vpc_id" {
  description = "VPC ID for resources (if not provided, uses default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for ALB and Fargate (if not provided, uses default VPC subnets)"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones (if not provided, uses first 3 AZs in region)"
  type        = list(string)
  default     = []
}

# Container Configuration
variable "container_image" {
  description = "Container image URI (if not provided, will be set to ECR repository URI)"
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 3000
}

variable "container_cpu" {
  description = "CPU units for the container (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.container_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "container_memory" {
  description = "Memory for the container in MB (must be compatible with CPU)"
  type        = number
  default     = 512
}

# ECS Configuration
variable "cluster_name" {
  description = "Name of the ECS cluster (if not provided, generates unique name)"
  type        = string
  default     = ""
}

variable "service_name" {
  description = "Name of the ECS service (if not provided, generates unique name)"
  type        = string
  default     = ""
}

variable "task_definition_family" {
  description = "Family name for the task definition (if not provided, generates unique name)"
  type        = string
  default     = ""
}

variable "desired_count" {
  description = "Desired number of tasks to run"
  type        = number
  default     = 3
  
  validation {
    condition     = var.desired_count >= 1 && var.desired_count <= 100
    error_message = "Desired count must be between 1 and 100."
  }
}

variable "platform_version" {
  description = "Fargate platform version"
  type        = string
  default     = "LATEST"
}

# Auto Scaling Configuration
variable "enable_auto_scaling" {
  description = "Enable auto scaling for the ECS service"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto scaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto scaling"
  type        = number
  default     = 10
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 70
  
  validation {
    condition     = var.cpu_target_value >= 10 && var.cpu_target_value <= 100
    error_message = "CPU target value must be between 10 and 100."
  }
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto scaling"
  type        = number
  default     = 80
  
  validation {
    condition     = var.memory_target_value >= 10 && var.memory_target_value <= 100
    error_message = "Memory target value must be between 10 and 100."
  }
}

variable "scale_in_cooldown" {
  description = "Cooldown period in seconds for scale in operations"
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Cooldown period in seconds for scale out operations"
  type        = number
  default     = 300
}

# Load Balancer Configuration
variable "alb_name" {
  description = "Name of the Application Load Balancer (if not provided, generates unique name)"
  type        = string
  default     = ""
}

variable "alb_internal" {
  description = "Whether the ALB is internal (true) or internet-facing (false)"
  type        = bool
  default     = false
}

variable "alb_deletion_protection" {
  description = "Enable deletion protection for the ALB"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks before considering target healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before considering target unhealthy"
  type        = number
  default     = 3
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 120
}

# ECR Configuration
variable "ecr_repository_name" {
  description = "Name of the ECR repository (if not provided, generates unique name)"
  type        = string
  default     = ""
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting for ECR repository"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable image scanning on push to ECR"
  type        = bool
  default     = true
}

variable "ecr_encryption_type" {
  description = "Encryption type for ECR repository"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "KMS"], var.ecr_encryption_type)
    error_message = "Encryption type must be either AES256 or KMS."
  }
}

# Logging Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Security Configuration
variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging"
  type        = bool
  default     = false
}

variable "enable_fargate_spot" {
  description = "Enable Fargate Spot capacity provider"
  type        = bool
  default     = true
}

variable "fargate_spot_weight" {
  description = "Weight for Fargate Spot capacity provider"
  type        = number
  default     = 4
}

variable "fargate_weight" {
  description = "Weight for regular Fargate capacity provider"
  type        = number
  default     = 1
}

variable "fargate_base" {
  description = "Base number of tasks to run on regular Fargate"
  type        = number
  default     = 1
}

# Additional Environment Variables
variable "container_environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default = {
    NODE_ENV = "production"
    PORT     = "3000"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}