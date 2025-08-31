# Input Variables for VPC Lattice Cost Analytics Infrastructure
# These variables allow customization of the deployment without modifying the code

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "lattice-cost-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "cost_center" {
  description = "Cost center for billing and cost allocation"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Owner or team responsible for the resources"
  type        = string
  default     = "platform-team"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
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

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "cost_analysis_schedule" {
  description = "Schedule expression for automated cost analysis (EventBridge rate expression)"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition     = can(regex("^(rate|cron)\\(.*\\)$", var.cost_analysis_schedule))
    error_message = "Schedule must be a valid EventBridge rate or cron expression."
  }
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning for analytics data"
  type        = bool
  default     = true
}

variable "s3_encryption_enabled" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard creation"
  type        = bool
  default     = true
}

variable "enable_demo_vpc_lattice" {
  description = "Create demo VPC Lattice service network for testing"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "lattice-cost-analytics"
    Environment = "demo"
    CostCenter  = "engineering"
    Owner       = "platform-team"
    ServiceMesh = "vpc-lattice"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to specific resources"
  type        = map(string)
  default     = {}
}

# Data source for current AWS region
data "aws_region" "current" {}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}