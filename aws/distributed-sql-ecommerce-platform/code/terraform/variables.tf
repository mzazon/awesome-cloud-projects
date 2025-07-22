# Core Configuration Variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "global-ecommerce"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Regional Configuration
variable "primary_region" {
  description = "Primary AWS region for deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-2", 
      "eu-west-1", "eu-west-2", "eu-central-1",
      "ap-northeast-1", "ap-southeast-1", "ap-southeast-2"
    ], var.primary_region)
    error_message = "Primary region must be a supported Aurora DSQL region."
  }
}

variable "enable_multi_region" {
  description = "Enable multi-region deployment"
  type        = bool
  default     = false
}

variable "secondary_regions" {
  description = "List of secondary regions for multi-region deployment"
  type        = list(string)
  default     = ["us-west-2", "eu-west-1"]

  validation {
    condition = alltrue([
      for region in var.secondary_regions : contains([
        "us-east-1", "us-east-2", "us-west-2", 
        "eu-west-1", "eu-west-2", "eu-central-1",
        "ap-northeast-1", "ap-southeast-1", "ap-southeast-2"
      ], region)
    ])
    error_message = "All secondary regions must be supported Aurora DSQL regions."
  }
}

# Aurora DSQL Configuration
variable "dsql_cluster_name" {
  description = "Name for the Aurora DSQL cluster"
  type        = string
  default     = ""
  
  validation {
    condition     = var.dsql_cluster_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.dsql_cluster_name))
    error_message = "DSQL cluster name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Aurora DSQL cluster"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11",
      "nodejs16.x", "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters."
  }
}

variable "enable_api_gateway_logging" {
  description = "Enable CloudWatch logging for API Gateway"
  type        = bool
  default     = true
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 1000

  validation {
    condition     = var.api_throttle_rate_limit > 0
    error_message = "API throttle rate limit must be greater than 0."
  }
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 2000

  validation {
    condition     = var.api_throttle_burst_limit > 0
    error_message = "API throttle burst limit must be greater than 0."
  }
}

# CloudFront Configuration
variable "cloudfront_price_class" {
  description = "Price class for CloudFront distribution"
  type        = string
  default     = "PriceClass_All"

  validation {
    condition = contains([
      "PriceClass_100", "PriceClass_200", "PriceClass_All"
    ], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "cloudfront_min_ttl" {
  description = "Minimum TTL for CloudFront cache"
  type        = number
  default     = 0

  validation {
    condition     = var.cloudfront_min_ttl >= 0
    error_message = "CloudFront minimum TTL must be non-negative."
  }
}

variable "cloudfront_default_ttl" {
  description = "Default TTL for CloudFront cache"
  type        = number
  default     = 0

  validation {
    condition     = var.cloudfront_default_ttl >= 0
    error_message = "CloudFront default TTL must be non-negative."
  }
}

variable "cloudfront_max_ttl" {
  description = "Maximum TTL for CloudFront cache"
  type        = number
  default     = 0

  validation {
    condition     = var.cloudfront_max_ttl >= 0
    error_message = "CloudFront maximum TTL must be non-negative."
  }
}

# Security Configuration
variable "enable_waf" {
  description = "Enable AWS WAF for API Gateway protection"
  type        = bool
  default     = false
}

variable "allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Database Configuration
variable "initial_database_name" {
  description = "Initial database name for Aurora DSQL"
  type        = string
  default     = "postgres"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.initial_database_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

# Resource Naming
variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = can([for k, v in var.resource_tags : regex("^[a-zA-Z0-9+\\-=._:/@]+$", k)])
    error_message = "Tag keys must contain only valid characters."
  }
}