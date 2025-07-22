# Core configuration variables
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
  description = "Name of the project (used for resource naming and tagging)"
  type        = string
  default     = "ecommerce-api"
  
  validation {
    condition     = length(var.project_name) <= 32 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must be 32 characters or less, start with a letter, and contain only alphanumeric characters and hyphens."
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

# DynamoDB configuration variables
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "enable_dynamodb_streams" {
  description = "Enable DynamoDB streams for real-time data processing"
  type        = bool
  default     = true
}

# OpenSearch configuration variables
variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"
  
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+\\.search$", var.opensearch_instance_type))
    error_message = "OpenSearch instance type must be a valid instance type ending with .search."
  }
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 1
  
  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 20
    error_message = "OpenSearch instance count must be between 1 and 20."
  }
}

variable "opensearch_ebs_volume_size" {
  description = "OpenSearch EBS volume size in GB"
  type        = number
  default     = 20
  
  validation {
    condition     = var.opensearch_ebs_volume_size >= 10 && var.opensearch_ebs_volume_size <= 1000
    error_message = "OpenSearch EBS volume size must be between 10 and 1000 GB."
  }
}

variable "enable_opensearch_encryption" {
  description = "Enable encryption at rest and in transit for OpenSearch"
  type        = bool
  default     = true
}

# Cognito configuration variables
variable "cognito_password_policy" {
  description = "Cognito User Pool password policy configuration"
  type = object({
    minimum_length    = number
    require_lowercase = bool
    require_numbers   = bool
    require_symbols   = bool
    require_uppercase = bool
  })
  default = {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
}

variable "cognito_user_groups" {
  description = "Cognito user groups to create for role-based access"
  type = list(object({
    name        = string
    description = string
  }))
  default = [
    {
      name        = "admin"
      description = "Administrator users with full access"
    },
    {
      name        = "seller"
      description = "Seller users with product management access"
    },
    {
      name        = "customer"
      description = "Customer users with read-only access"
    }
  ]
}

# Lambda configuration variables
variable "lambda_runtime" {
  description = "Lambda runtime for business logic function"
  type        = string
  default     = "nodejs18.x"
  
  validation {
    condition     = contains(["nodejs16.x", "nodejs18.x", "nodejs20.x", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported runtime version."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

# AppSync configuration variables
variable "appsync_authentication_type" {
  description = "AppSync primary authentication type"
  type        = string
  default     = "AMAZON_COGNITO_USER_POOLS"
  
  validation {
    condition = contains([
      "API_KEY",
      "AWS_IAM",
      "AMAZON_COGNITO_USER_POOLS",
      "OPENID_CONNECT",
      "AWS_LAMBDA"
    ], var.appsync_authentication_type)
    error_message = "AppSync authentication type must be a valid authentication type."
  }
}

variable "enable_appsync_logging" {
  description = "Enable AppSync field-level logging"
  type        = bool
  default     = true
}

variable "enable_appsync_xray" {
  description = "Enable X-Ray tracing for AppSync"
  type        = bool
  default     = true
}

variable "api_key_expires_days" {
  description = "Number of days until AppSync API key expires"
  type        = number
  default     = 30
  
  validation {
    condition     = var.api_key_expires_days >= 1 && var.api_key_expires_days <= 365
    error_message = "API key expiration must be between 1 and 365 days."
  }
}

# Sample data configuration
variable "enable_sample_data" {
  description = "Load sample data into DynamoDB tables"
  type        = bool
  default     = true
}

variable "create_test_user" {
  description = "Create a test user in Cognito User Pool"
  type        = bool
  default     = true
}

variable "test_user_email" {
  description = "Email address for test user"
  type        = string
  default     = "developer@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.test_user_email))
    error_message = "Test user email must be a valid email address."
  }
}

# Security and compliance variables
variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "enable_backup" {
  description = "Enable automated backups for DynamoDB tables"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

# Cost optimization variables
variable "enable_cost_optimization" {
  description = "Enable cost optimization features (reserved capacity, etc.)"
  type        = bool
  default     = false
}

# Monitoring and alerting variables
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring and alerting"
  type        = bool
  default     = true
}