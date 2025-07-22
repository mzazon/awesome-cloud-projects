# AWS region configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

# Environment identifier
variable "environment" {
  description = "Environment name for resource naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

# Project name for resource naming
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "secrets-mgmt"
}

# ECS Configuration
variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = ""
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS task"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.ecs_task_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "ecs_task_memory" {
  description = "Memory (MiB) for ECS task"
  type        = number
  default     = 512
  
  validation {
    condition     = var.ecs_task_memory >= 512 && var.ecs_task_memory <= 30720
    error_message = "Memory must be between 512 and 30720 MiB."
  }
}

# EKS Configuration
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_group_min_size" {
  description = "Minimum number of nodes in EKS node group"
  type        = number
  default     = 1
}

variable "eks_node_group_max_size" {
  description = "Maximum number of nodes in EKS node group"
  type        = number
  default     = 3
}

variable "eks_node_group_desired_size" {
  description = "Desired number of nodes in EKS node group"
  type        = number
  default     = 2
}

# Secrets configuration
variable "database_secret_name" {
  description = "Name for the database secret"
  type        = string
  default     = ""
}

variable "api_secret_name" {
  description = "Name for the API keys secret"
  type        = string
  default     = ""
}

variable "database_credentials" {
  description = "Database credentials for secret"
  type = object({
    username = string
    password = string
    host     = string
    port     = string
    database = string
  })
  default = {
    username = "appuser"
    password = "temp-password123"
    host     = "demo-db.cluster-xyz.us-west-2.rds.amazonaws.com"
    port     = "5432"
    database = "appdb"
  }
  sensitive = true
}

variable "api_credentials" {
  description = "API credentials for secret"
  type = object({
    github_token = string
    stripe_key   = string
    twilio_sid   = string
  })
  default = {
    github_token = "ghp_example_token"
    stripe_key   = "sk_test_example_key"
    twilio_sid   = "AC_example_sid"
  }
  sensitive = true
}

# Lambda configuration
variable "lambda_function_name" {
  description = "Name for the Lambda rotation function"
  type        = string
  default     = ""
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"
}

# Rotation configuration
variable "rotation_days" {
  description = "Number of days for automatic rotation"
  type        = number
  default     = 30
  
  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365
    error_message = "Rotation days must be between 1 and 365."
  }
}

# Networking configuration
variable "vpc_id" {
  description = "VPC ID for resources (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for resources (leave empty to use default subnets)"
  type        = list(string)
  default     = []
}

# CloudWatch configuration
variable "cloudwatch_log_retention_days" {
  description = "Retention period for CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch retention periods."
  }
}

# Security configuration
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for secrets"
  type        = bool
  default     = true
}

variable "enable_secret_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

# CSI driver configuration
variable "install_csi_driver" {
  description = "Install Secrets Store CSI driver for EKS"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}