# variables.tf - Input variables for the multi-region Aurora DSQL deployment

# ----- Region Configuration -----

variable "primary_region" {
  description = "Primary AWS region for Aurora DSQL cluster and Lambda deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-west-3",
      "ap-northeast-1", "ap-northeast-2", "ap-northeast-3"
    ], var.primary_region)
    error_message = "Primary region must be one of the supported Aurora DSQL regions."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for Aurora DSQL cluster and Lambda deployment"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-west-3",
      "ap-northeast-1", "ap-northeast-2", "ap-northeast-3"
    ], var.secondary_region)
    error_message = "Secondary region must be one of the supported Aurora DSQL regions."
  }
}

variable "witness_region" {
  description = "Witness region for Aurora DSQL multi-region consensus"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-west-3",
      "ap-northeast-1", "ap-northeast-2", "ap-northeast-3"
    ], var.witness_region)
    error_message = "Witness region must be one of the supported Aurora DSQL regions."
  }
}

# ----- Project Configuration -----

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "aurora-dsql-multiregion"
  
  validation {
    condition     = length(var.project_name) <= 30 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be 30 characters or less and contain only lowercase letters, numbers, and hyphens."
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

# ----- Aurora DSQL Configuration -----

variable "deletion_protection_enabled" {
  description = "Enable deletion protection for Aurora DSQL clusters"
  type        = bool
  default     = false
}

variable "database_name" {
  description = "Name of the initial database to create in Aurora DSQL clusters"
  type        = string
  default     = "distributed_app"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "Database name must start with a letter, contain only lowercase letters, numbers, and underscores, and be 63 characters or less."
  }
}

# ----- Lambda Configuration -----

variable "lambda_runtime" {
  description = "Runtime version for Lambda functions"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# ----- EventBridge Configuration -----

variable "eventbridge_bus_name" {
  description = "Name for custom EventBridge bus"
  type        = string
  default     = null
}

variable "enable_eventbridge_replication" {
  description = "Enable cross-region EventBridge event replication"
  type        = bool
  default     = true
}

# ----- Security Configuration -----

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for private connectivity"
  type        = bool
  default     = false
}

variable "lambda_vpc_config" {
  description = "VPC configuration for Lambda functions (optional)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

# ----- Monitoring Configuration -----

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention period."
  }
}

variable "enable_x_ray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

# ----- Cost Management -----

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for resource billing"
  type        = bool
  default     = true
}

variable "auto_scaling_enabled" {
  description = "Enable auto-scaling for Lambda concurrency (if needed)"
  type        = bool
  default     = false
}

# ----- Common Tags -----

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "aurora-dsql-multiregion"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Recipe      = "multi-region-distributed-applications-aurora-dsql"
  }
}

# ----- Database Schema -----

variable "create_sample_schema" {
  description = "Create sample database schema for demonstration"
  type        = bool
  default     = true
}

variable "sample_data_count" {
  description = "Number of sample records to insert for testing"
  type        = number
  default     = 100
  
  validation {
    condition     = var.sample_data_count >= 0 && var.sample_data_count <= 10000
    error_message = "Sample data count must be between 0 and 10000."
  }
}