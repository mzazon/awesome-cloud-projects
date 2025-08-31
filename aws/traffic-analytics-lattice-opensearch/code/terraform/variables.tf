# Variables for Traffic Analytics with VPC Lattice and OpenSearch
# Customize these variables for your specific deployment requirements

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "traffic-analytics"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

# OpenSearch Configuration Variables
variable "opensearch_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.11"
  
  validation {
    condition     = can(regex("^OpenSearch_[0-9]+\\.[0-9]+$", var.opensearch_version))
    error_message = "OpenSearch version must be in format OpenSearch_X.Y (e.g., OpenSearch_2.11)."
  }
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type for the domain"
  type        = string
  default     = "t3.small.search"
  
  validation {
    condition = contains([
      "t3.small.search", "t3.medium.search",
      "m6g.large.search", "m6g.xlarge.search", "m6g.2xlarge.search",
      "r6g.large.search", "r6g.xlarge.search", "r6g.2xlarge.search",
      "c6g.large.search", "c6g.xlarge.search", "c6g.2xlarge.search"
    ], var.opensearch_instance_type)
    error_message = "OpenSearch instance type must be a valid search instance type."
  }
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances in the domain"
  type        = number
  default     = 1
  
  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 10
    error_message = "OpenSearch instance count must be between 1 and 10."
  }
}

variable "opensearch_volume_size" {
  description = "EBS volume size for OpenSearch instances (in GB)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.opensearch_volume_size >= 10 && var.opensearch_volume_size <= 3584
    error_message = "OpenSearch volume size must be between 10 GB and 3584 GB."
  }
}

# Firehose Configuration Variables
variable "firehose_buffer_size" {
  description = "Buffer size for Firehose delivery stream (in MB)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 128
    error_message = "Firehose buffer size must be between 1 MB and 128 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Buffer interval for Firehose delivery stream (in seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Firehose buffer interval must be between 60 and 900 seconds."
  }
}

# Lambda Configuration Variables
variable "lambda_timeout" {
  description = "Lambda function timeout (in seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation (in MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10240 MB."
  }
}

# Monitoring and Logging Variables
variable "log_retention_days" {
  description = "CloudWatch log retention period (in days)"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# Security Configuration Variables
variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "enable_opensearch_encryption" {
  description = "Enable OpenSearch encryption at rest and node-to-node"
  type        = bool
  default     = true
}

variable "enforce_https" {
  description = "Enforce HTTPS for OpenSearch domain endpoint"
  type        = bool
  default     = true
}

# Cost Optimization Variables
variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning for backup bucket"
  type        = bool
  default     = true
}

variable "s3_storage_class" {
  description = "Default storage class for S3 objects"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "STANDARD_IA", "ONEZONE_IA", "REDUCED_REDUNDANCY",
      "GLACIER", "DEEP_ARCHIVE", "INTELLIGENT_TIERING"
    ], var.s3_storage_class)
    error_message = "S3 storage class must be a valid storage class."
  }
}

# Network Configuration Variables (for future VPC integration)
variable "vpc_id" {
  description = "VPC ID for VPC Lattice service network (optional)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for VPC Lattice services (optional)"
  type        = list(string)
  default     = []
}

# Advanced Configuration Variables
variable "opensearch_advanced_options" {
  description = "Advanced options for OpenSearch domain"
  type        = map(string)
  default = {
    "indices.fielddata.cache.size"  = "20"
    "indices.query.bool.max_clause_count" = "1024"
  }
}

variable "custom_opensearch_policy" {
  description = "Custom access policy for OpenSearch domain (JSON string)"
  type        = string
  default     = ""
}

variable "enable_cognito_auth" {
  description = "Enable Cognito authentication for OpenSearch Dashboards"
  type        = bool
  default     = false
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID for OpenSearch authentication"
  type        = string
  default     = ""
}

variable "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID for OpenSearch authentication"
  type        = string
  default     = ""
}

# Resource tagging variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_center" {
  description = "Cost center for resource billing and tracking"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner of the resources for tracking and management"
  type        = string
  default     = ""
}