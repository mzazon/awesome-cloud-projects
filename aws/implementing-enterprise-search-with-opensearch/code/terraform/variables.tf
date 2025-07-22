# AWS Region Configuration
variable "aws_region" {
  description = "The AWS region to create resources in"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Project Configuration
variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "opensearch-search"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must only contain lowercase letters, numbers, and hyphens."
  }
}

# OpenSearch Domain Configuration
variable "opensearch_version" {
  description = "OpenSearch version to deploy"
  type        = string
  default     = "OpenSearch_2.11"

  validation {
    condition = can(regex("^OpenSearch_[0-9]+\\.[0-9]+$", var.opensearch_version))
    error_message = "OpenSearch version must be in format OpenSearch_X.Y (e.g., OpenSearch_2.11)."
  }
}

variable "opensearch_instance_type" {
  description = "Instance type for OpenSearch data nodes"
  type        = string
  default     = "m6g.large.search"

  validation {
    condition = can(regex("^[a-z0-9]+\\.[a-z0-9]+\\.search$", var.opensearch_instance_type))
    error_message = "OpenSearch instance type must be a valid search instance type."
  }
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch data nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.opensearch_instance_count >= 3 && var.opensearch_instance_count <= 20
    error_message = "OpenSearch instance count must be between 3 and 20 for multi-AZ deployments."
  }
}

variable "opensearch_master_instance_type" {
  description = "Instance type for OpenSearch dedicated master nodes"
  type        = string
  default     = "m6g.medium.search"

  validation {
    condition = can(regex("^[a-z0-9]+\\.[a-z0-9]+\\.search$", var.opensearch_master_instance_type))
    error_message = "OpenSearch master instance type must be a valid search instance type."
  }
}

variable "opensearch_master_instance_count" {
  description = "Number of OpenSearch dedicated master nodes"
  type        = number
  default     = 3

  validation {
    condition     = contains([3, 5], var.opensearch_master_instance_count)
    error_message = "OpenSearch master instance count must be 3 or 5 for high availability."
  }
}

# Storage Configuration
variable "opensearch_ebs_volume_size" {
  description = "Size of EBS volume for each OpenSearch node (GB)"
  type        = number
  default     = 100

  validation {
    condition     = var.opensearch_ebs_volume_size >= 10 && var.opensearch_ebs_volume_size <= 16000
    error_message = "EBS volume size must be between 10 and 16000 GB."
  }
}

variable "opensearch_ebs_volume_type" {
  description = "Type of EBS volume for OpenSearch nodes"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.opensearch_ebs_volume_type)
    error_message = "EBS volume type must be one of: gp3, gp2, io1, io2."
  }
}

variable "opensearch_ebs_iops" {
  description = "IOPS for EBS volumes (only applicable for gp3, io1, io2)"
  type        = number
  default     = 3000

  validation {
    condition     = var.opensearch_ebs_iops >= 3000 && var.opensearch_ebs_iops <= 64000
    error_message = "EBS IOPS must be between 3000 and 64000."
  }
}

variable "opensearch_ebs_throughput" {
  description = "Throughput for EBS volumes in MB/s (only applicable for gp3)"
  type        = number
  default     = 125

  validation {
    condition     = var.opensearch_ebs_throughput >= 125 && var.opensearch_ebs_throughput <= 1000
    error_message = "EBS throughput must be between 125 and 1000 MB/s."
  }
}

# Security Configuration
variable "opensearch_admin_username" {
  description = "Admin username for OpenSearch fine-grained access control"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.opensearch_admin_username) >= 4 && length(var.opensearch_admin_username) <= 20
    error_message = "OpenSearch admin username must be between 4 and 20 characters."
  }
}

variable "opensearch_admin_password" {
  description = "Admin password for OpenSearch fine-grained access control"
  type        = string
  sensitive   = true
  default     = "TempPassword123!"

  validation {
    condition     = length(var.opensearch_admin_password) >= 8 && can(regex("[A-Z]", var.opensearch_admin_password)) && can(regex("[a-z]", var.opensearch_admin_password)) && can(regex("[0-9]", var.opensearch_admin_password)) && can(regex("[^A-Za-z0-9]", var.opensearch_admin_password))
    error_message = "Password must be at least 8 characters with uppercase, lowercase, number, and special character."
  }
}

# Network Configuration
variable "availability_zones" {
  description = "List of availability zones to deploy across"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || (length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3)
    error_message = "If specified, availability zones must be between 2 and 3 zones."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda indexer function"
  type        = string
  default     = "python3.9"

  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Monitoring Configuration
variable "enable_logging" {
  description = "Enable CloudWatch logging for OpenSearch"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and dashboards"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# Cost Optimization
variable "enable_ultrawarm" {
  description = "Enable UltraWarm storage for cost optimization"
  type        = bool
  default     = false
}

variable "ultrawarm_instance_type" {
  description = "Instance type for UltraWarm nodes"
  type        = string
  default     = "ultrawarm1.medium.search"

  validation {
    condition = can(regex("^ultrawarm[0-9]+\\.[a-z]+\\.search$", var.ultrawarm_instance_type))
    error_message = "UltraWarm instance type must be a valid UltraWarm instance type."
  }
}

variable "ultrawarm_instance_count" {
  description = "Number of UltraWarm nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.ultrawarm_instance_count >= 2 && var.ultrawarm_instance_count <= 150
    error_message = "UltraWarm instance count must be between 2 and 150."
  }
}

# S3 Configuration
variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 bucket with objects"
  type        = bool
  default     = false
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}