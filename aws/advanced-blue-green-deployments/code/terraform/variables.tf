# Variables for Advanced Blue-Green Deployments Infrastructure
# This file defines all configurable parameters for the deployment

# Basic Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "advanced-deployment"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Networking Configuration
variable "vpc_id" {
  description = "VPC ID to deploy resources into (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for ALB and ECS tasks (leave empty to use default VPC subnets)"
  type        = list(string)
  default     = []
}

variable "enable_public_access" {
  description = "Whether to enable public internet access for ALB"
  type        = bool
  default     = true
}

# ECS Configuration
variable "ecs_cluster_capacity_providers" {
  description = "List of capacity providers for ECS cluster"
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS tasks (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
  
  validation {
    condition = contains([256, 512, 1024, 2048, 4096], var.ecs_task_cpu)
    error_message = "ECS task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "ecs_task_memory" {
  description = "Memory (MB) for ECS tasks"
  type        = number
  default     = 512
  
  validation {
    condition = var.ecs_task_memory >= 512 && var.ecs_task_memory <= 30720
    error_message = "ECS task memory must be between 512 MB and 30720 MB."
  }
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
  
  validation {
    condition = var.ecs_desired_count >= 1 && var.ecs_desired_count <= 100
    error_message = "ECS desired count must be between 1 and 100."
  }
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 8080
}

# Application Configuration
variable "initial_app_version" {
  description = "Initial application version to deploy"
  type        = string
  default     = "1.0.0"
}

variable "container_image_tag" {
  description = "Initial container image tag to deploy"
  type        = string
  default     = "1.0.0"
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10240 MB."
  }
}

# ALB Configuration
variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "ALB idle timeout must be between 1 and 4000 seconds."
  }
}

variable "health_check_path" {
  description = "Health check path for target groups"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  
  validation {
    condition = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "healthy_threshold_count" {
  description = "Number of consecutive successful health checks before marking target healthy"
  type        = number
  default     = 2
  
  validation {
    condition = var.healthy_threshold_count >= 2 && var.healthy_threshold_count <= 10
    error_message = "Healthy threshold count must be between 2 and 10."
  }
}

variable "unhealthy_threshold_count" {
  description = "Number of consecutive failed health checks before marking target unhealthy"
  type        = number
  default     = 3
  
  validation {
    condition = var.unhealthy_threshold_count >= 2 && var.unhealthy_threshold_count <= 10
    error_message = "Unhealthy threshold count must be between 2 and 10."
  }
}

# CodeDeploy Configuration
variable "ecs_deployment_config" {
  description = "CodeDeploy deployment configuration for ECS"
  type        = string
  default     = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
  
  validation {
    condition = can(regex("^CodeDeployDefault\\.ECS", var.ecs_deployment_config))
    error_message = "ECS deployment config must be a valid CodeDeploy ECS configuration."
  }
}

variable "lambda_deployment_config" {
  description = "CodeDeploy deployment configuration for Lambda"
  type        = string
  default     = "CodeDeployDefault.LambdaLinear10PercentEvery1Minute"
  
  validation {
    condition = can(regex("^CodeDeployDefault\\.Lambda", var.lambda_deployment_config))
    error_message = "Lambda deployment config must be a valid CodeDeploy Lambda configuration."
  }
}

variable "auto_rollback_enabled" {
  description = "Enable automatic rollback on deployment failure"
  type        = bool
  default     = true
}

variable "auto_rollback_events" {
  description = "Events that trigger automatic rollback"
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_INSTANCE_FAILURE"]
}

variable "termination_wait_time_in_minutes" {
  description = "Time to wait before terminating blue instances (minutes)"
  type        = number
  default     = 5
  
  validation {
    condition = var.termination_wait_time_in_minutes >= 0 && var.termination_wait_time_in_minutes <= 2880
    error_message = "Termination wait time must be between 0 and 2880 minutes (48 hours)."
  }
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 3
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "alarm_period" {
  description = "Period for CloudWatch alarms in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = contains([10, 30, 60, 120, 300, 600, 900, 1800, 3600], var.alarm_period)
    error_message = "Alarm period must be one of: 10, 30, 60, 120, 300, 600, 900, 1800, 3600 seconds."
  }
}

variable "error_rate_threshold" {
  description = "Threshold for error rate alarms (errors per period)"
  type        = number
  default     = 10
  
  validation {
    condition = var.error_rate_threshold > 0
    error_message = "Error rate threshold must be greater than 0."
  }
}

variable "response_time_threshold" {
  description = "Threshold for response time alarms (seconds)"
  type        = number
  default     = 2.0
  
  validation {
    condition = var.response_time_threshold > 0
    error_message = "Response time threshold must be greater than 0."
  }
}

variable "lambda_duration_threshold" {
  description = "Threshold for Lambda duration alarms (milliseconds)"
  type        = number
  default     = 5000
  
  validation {
    condition = var.lambda_duration_threshold > 0
    error_message = "Lambda duration threshold must be greater than 0."
  }
}

# ECR Configuration
variable "enable_image_scanning" {
  description = "Enable ECR image vulnerability scanning"
  type        = bool
  default     = true
}

variable "image_mutability" {
  description = "Image mutability setting for ECR repository"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition = contains(["MUTABLE", "IMMUTABLE"], var.image_mutability)
    error_message = "Image mutability must be either MUTABLE or IMMUTABLE."
  }
}

# Logging Configuration
variable "log_retention_in_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for deployment notifications (leave empty to skip SNS)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Security Configuration
variable "enable_waf" {
  description = "Enable AWS WAF for ALB protection"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All CIDR blocks must be valid CIDR notation."
  }
}

# Resource Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}