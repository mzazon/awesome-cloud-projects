# Variable definitions for the distributed session management infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "session-mgmt"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to deploy resources across"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

# MemoryDB Configuration
variable "memorydb_node_type" {
  description = "Node type for MemoryDB cluster"
  type        = string
  default     = "db.r6g.large"

  validation {
    condition = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.memorydb_node_type))
    error_message = "MemoryDB node type must be a valid instance type (e.g., db.r6g.large)."
  }
}

variable "memorydb_num_shards" {
  description = "Number of shards for MemoryDB cluster"
  type        = number
  default     = 2

  validation {
    condition     = var.memorydb_num_shards >= 1 && var.memorydb_num_shards <= 500
    error_message = "Number of shards must be between 1 and 500."
  }
}

variable "memorydb_num_replicas_per_shard" {
  description = "Number of replica nodes per shard"
  type        = number
  default     = 1

  validation {
    condition     = var.memorydb_num_replicas_per_shard >= 0 && var.memorydb_num_replicas_per_shard <= 5
    error_message = "Number of replicas per shard must be between 0 and 5."
  }
}

variable "memorydb_parameter_group" {
  description = "Parameter group for MemoryDB cluster"
  type        = string
  default     = "default.memorydb-redis7"
}

variable "memorydb_engine_version" {
  description = "Engine version for MemoryDB cluster"
  type        = string
  default     = "7.0"
}

# ECS Configuration
variable "ecs_task_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.ecs_task_cpu)
    error_message = "ECS task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "ecs_task_memory" {
  description = "Memory (MB) for ECS task"
  type        = number
  default     = 512

  validation {
    condition     = var.ecs_task_memory >= 512 && var.ecs_task_memory <= 30720
    error_message = "ECS task memory must be between 512 MB and 30 GB."
  }
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2

  validation {
    condition     = var.ecs_desired_count >= 1
    error_message = "Desired count must be at least 1."
  }
}

variable "ecs_container_image" {
  description = "Container image for the session management application"
  type        = string
  default     = "nginx:latest"
}

# Auto Scaling Configuration
variable "autoscaling_min_capacity" {
  description = "Minimum number of ECS tasks for auto scaling"
  type        = number
  default     = 2

  validation {
    condition     = var.autoscaling_min_capacity >= 1
    error_message = "Minimum capacity must be at least 1."
  }
}

variable "autoscaling_max_capacity" {
  description = "Maximum number of ECS tasks for auto scaling"
  type        = number
  default     = 10

  validation {
    condition     = var.autoscaling_max_capacity >= var.autoscaling_min_capacity
    error_message = "Maximum capacity must be greater than or equal to minimum capacity."
  }
}

variable "autoscaling_target_cpu" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 70

  validation {
    condition     = var.autoscaling_target_cpu > 0 && var.autoscaling_target_cpu <= 100
    error_message = "Target CPU utilization must be between 1 and 100."
  }
}

# Session Configuration
variable "session_timeout_seconds" {
  description = "Session timeout in seconds"
  type        = number
  default     = 1800

  validation {
    condition     = var.session_timeout_seconds > 0
    error_message = "Session timeout must be greater than 0 seconds."
  }
}

variable "redis_database_number" {
  description = "Redis database number for session storage"
  type        = number
  default     = 0

  validation {
    condition     = var.redis_database_number >= 0 && var.redis_database_number <= 15
    error_message = "Redis database number must be between 0 and 15."
  }
}

# ALB Configuration
variable "alb_enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "Idle timeout for ALB in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "ALB idle timeout must be between 1 and 4000 seconds."
  }
}

# Health Check Configuration
variable "health_check_path" {
  description = "Health check path for ALB target group"
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2

  validation {
    condition     = var.healthy_threshold >= 2 && var.healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 3

  validation {
    condition     = var.unhealthy_threshold >= 2 && var.unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Enable Spot instances for ECS tasks (cost optimization)"
  type        = bool
  default     = false
}

# Monitoring and Alerting
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for resources"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_container_insights" {
  description = "Enable Container Insights for ECS cluster"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging containers"
  type        = bool
  default     = false
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}