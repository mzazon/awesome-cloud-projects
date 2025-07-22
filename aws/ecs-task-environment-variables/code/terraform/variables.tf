# Variables for ECS Task Definitions with Environment Variable Management

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
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
  default     = "ecs-envvar-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = ""
}

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
  default     = ""
}

variable "task_family" {
  description = "Family name for the ECS task definition"
  type        = string
  default     = "envvar-demo-task"
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 80
  
  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

variable "task_cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "Task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memory for the task in MiB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.task_memory >= 512 && var.task_memory <= 30720
    error_message = "Task memory must be between 512 and 30720 MiB."
  }
}

variable "desired_count" {
  description = "Desired number of tasks in the service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.desired_count >= 0 && var.desired_count <= 10
    error_message = "Desired count must be between 0 and 10."
  }
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging"
  type        = bool
  default     = false
}

variable "app_parameters" {
  description = "Application configuration parameters to store in Systems Manager"
  type = map(object({
    value       = string
    type        = string
    description = string
  }))
  default = {
    "database/host" = {
      value       = "dev-database.internal.com"
      type        = "String"
      description = "Database host"
    }
    "database/port" = {
      value       = "5432"
      type        = "String"
      description = "Database port"
    }
    "api/debug" = {
      value       = "true"
      type        = "String"
      description = "API debug mode"
    }
  }
}

variable "app_secrets" {
  description = "Application secrets to store in Systems Manager (SecureString)"
  type = map(object({
    value       = string
    description = string
  }))
  default = {
    "database/password" = {
      value       = "dev-secure-password-123"
      description = "Database password"
    }
    "api/secret-key" = {
      value       = "dev-api-secret-key-456"
      description = "API secret key"
    }
  }
  sensitive = true
}

variable "environment_files" {
  description = "Environment files configuration"
  type = map(object({
    content = map(string)
  }))
  default = {
    "app-config.env" = {
      content = {
        LOG_LEVEL        = "info"
        MAX_CONNECTIONS  = "100"
        TIMEOUT_SECONDS  = "30"
        FEATURE_FLAGS    = "auth,logging,metrics"
        APP_VERSION      = "1.2.3"
      }
    }
    "prod-config.env" = {
      content = {
        LOG_LEVEL           = "warn"
        MAX_CONNECTIONS     = "500"
        TIMEOUT_SECONDS     = "60"
        FEATURE_FLAGS       = "auth,logging,metrics,cache"
        APP_VERSION         = "1.2.3"
        MONITORING_ENABLED  = "true"
      }
    }
  }
}

variable "use_existing_vpc" {
  description = "Use existing default VPC instead of creating new one"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID to use (if use_existing_vpc is true)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS service (if use_existing_vpc is true)"
  type        = list(string)
  default     = []
}