# variables.tf - Input variables for AWS Proton and CDK infrastructure

# General Configuration
variable "aws_region" {
  type        = string
  description = "AWS region for resource deployment"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod)"
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment name can only contain lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  type        = string
  description = "Owner or team responsible for the infrastructure"
  default     = "platform-team"
}

variable "project_name" {
  type        = string
  description = "Name of the project"
  default     = "proton-cdk-automation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name can only contain lowercase letters, numbers, and hyphens."
  }
}

# VPC Configuration
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones to deploy across"
  default     = ["us-east-1a", "us-east-1b"]
  
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

# ECS Configuration
variable "ecs_cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
  default     = "proton-ecs-cluster"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.ecs_cluster_name))
    error_message = "ECS cluster name can only contain letters, numbers, hyphens, and underscores."
  }
}

variable "enable_container_insights" {
  type        = bool
  description = "Enable CloudWatch Container Insights for ECS cluster"
  default     = true
}

# S3 Configuration
variable "template_bucket_name" {
  type        = string
  description = "Name of the S3 bucket for storing Proton templates (will be suffixed with random string)"
  default     = "proton-templates"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.template_bucket_name))
    error_message = "S3 bucket name can only contain lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  type        = bool
  description = "Enable versioning for the S3 bucket"
  default     = true
}

variable "enable_server_side_encryption" {
  type        = bool
  description = "Enable server-side encryption for the S3 bucket"
  default     = true
}

# Proton Configuration
variable "proton_service_role_name" {
  type        = string
  description = "Name of the IAM role for AWS Proton service"
  default     = "ProtonServiceRole"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_+=,.@]+$", var.proton_service_role_name))
    error_message = "IAM role name contains invalid characters."
  }
}

variable "environment_template_name" {
  type        = string
  description = "Name of the Proton environment template"
  default     = "vpc-ecs-environment"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.environment_template_name))
    error_message = "Environment template name can only contain letters, numbers, hyphens, and underscores."
  }
}

variable "service_template_name" {
  type        = string
  description = "Name of the Proton service template"
  default     = "fargate-web-service"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.service_template_name))
    error_message = "Service template name can only contain letters, numbers, hyphens, and underscores."
  }
}

# CloudWatch Configuration
variable "log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the allowed values."
  }
}

# Network Configuration
variable "enable_nat_gateway" {
  type        = bool
  description = "Enable NAT Gateway for private subnet internet access"
  default     = true
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames in the VPC"
  default     = true
}

variable "enable_dns_support" {
  type        = bool
  description = "Enable DNS support in the VPC"
  default     = true
}

# Security Configuration
variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC Flow Logs"
  default     = true
}

variable "create_vpc_endpoints" {
  type        = bool
  description = "Create VPC endpoints for AWS services"
  default     = true
}

# Service Configuration Defaults
variable "default_container_image" {
  type        = string
  description = "Default container image for services"
  default     = "nginx:latest"
}

variable "default_container_port" {
  type        = number
  description = "Default container port"
  default     = 80
  
  validation {
    condition     = var.default_container_port >= 1 && var.default_container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

variable "default_memory" {
  type        = number
  description = "Default memory allocation in MiB"
  default     = 512
  
  validation {
    condition     = var.default_memory >= 256 && var.default_memory <= 8192
    error_message = "Memory must be between 256 and 8192 MiB."
  }
}

variable "default_cpu" {
  type        = number
  description = "Default CPU allocation"
  default     = 256
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.default_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "default_desired_count" {
  type        = number
  description = "Default desired number of tasks"
  default     = 2
  
  validation {
    condition     = var.default_desired_count >= 1 && var.default_desired_count <= 10
    error_message = "Desired count must be between 1 and 10."
  }
}

variable "default_min_capacity" {
  type        = number
  description = "Default minimum number of tasks"
  default     = 1
  
  validation {
    condition     = var.default_min_capacity >= 1
    error_message = "Minimum capacity must be at least 1."
  }
}

variable "default_max_capacity" {
  type        = number
  description = "Default maximum number of tasks"
  default     = 5
  
  validation {
    condition     = var.default_max_capacity >= 2
    error_message = "Maximum capacity must be at least 2."
  }
}

variable "default_health_check_path" {
  type        = string
  description = "Default health check path"
  default     = "/"
}

# Scaling Configuration
variable "cpu_scaling_target" {
  type        = number
  description = "Target CPU utilization for auto-scaling"
  default     = 70
  
  validation {
    condition     = var.cpu_scaling_target >= 20 && var.cpu_scaling_target <= 90
    error_message = "CPU scaling target must be between 20 and 90 percent."
  }
}

variable "memory_scaling_target" {
  type        = number
  description = "Target memory utilization for auto-scaling"
  default     = 80
  
  validation {
    condition     = var.memory_scaling_target >= 20 && var.memory_scaling_target <= 90
    error_message = "Memory scaling target must be between 20 and 90 percent."
  }
}

# Cost Optimization
variable "enable_spot_instances" {
  type        = bool
  description = "Enable Spot instances for cost optimization (not recommended for production)"
  default     = false
}

variable "enable_schedule_scaling" {
  type        = bool
  description = "Enable scheduled auto-scaling for cost optimization"
  default     = false
}

# Monitoring and Alerting
variable "enable_cloudwatch_alarms" {
  type        = bool
  description = "Enable CloudWatch alarms for monitoring"
  default     = true
}

variable "alarm_email" {
  type        = string
  description = "Email address for CloudWatch alarm notifications"
  default     = ""
}

# Backup and Disaster Recovery
variable "enable_backup" {
  type        = bool
  description = "Enable automated backup for critical resources"
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups"
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Tagging
variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}