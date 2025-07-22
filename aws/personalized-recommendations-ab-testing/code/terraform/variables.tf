# General Configuration
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "personalize-ab-test"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
}

# DynamoDB Configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 10
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "v1"
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway access logging"
  type        = bool
  default     = true
}

# Personalize Configuration
variable "personalize_domain" {
  description = "Amazon Personalize domain type"
  type        = string
  default     = "ECOMMERCE"
  
  validation {
    condition     = contains(["ECOMMERCE", "VIDEO_ON_DEMAND"], var.personalize_domain)
    error_message = "Personalize domain must be either ECOMMERCE or VIDEO_ON_DEMAND."
  }
}

variable "personalize_recipes" {
  description = "List of Personalize recipe ARNs for A/B testing"
  type = list(object({
    name        = string
    recipe_arn  = string
    description = string
  }))
  default = [
    {
      name        = "user-personalization"
      recipe_arn  = "arn:aws:personalize:::recipe/aws-user-personalization"
      description = "User-Personalization Algorithm"
    },
    {
      name        = "sims"
      recipe_arn  = "arn:aws:personalize:::recipe/aws-sims"
      description = "Item-to-Item Similarity Algorithm"
    },
    {
      name        = "popularity-count"
      recipe_arn  = "arn:aws:personalize:::recipe/aws-popularity-count"
      description = "Popularity-Based Algorithm"
    }
  ]
}

# S3 Configuration
variable "s3_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

# A/B Testing Configuration
variable "ab_test_variants" {
  description = "A/B test variant configuration with traffic distribution"
  type = map(object({
    traffic_percentage = number
    description        = string
  }))
  default = {
    variant_a = {
      traffic_percentage = 33
      description        = "User-Personalization Algorithm"
    }
    variant_b = {
      traffic_percentage = 33
      description        = "Item-to-Item Similarity Algorithm"
    }
    variant_c = {
      traffic_percentage = 34
      description        = "Popularity-Based Algorithm"
    }
  }
  
  validation {
    condition = sum([for variant in var.ab_test_variants : variant.traffic_percentage]) == 100
    error_message = "Traffic percentages must sum to 100."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_insights" {
  description = "Enable CloudWatch Logs Insights for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Security Configuration
variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services"
  type        = bool
  default     = false
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Cost Optimization
variable "enable_cost_allocation_tags" {
  description = "Enable detailed cost allocation tags"
  type        = bool
  default     = true
}

variable "enable_reserved_capacity" {
  description = "Enable reserved capacity for DynamoDB (cost optimization)"
  type        = bool
  default     = false
}