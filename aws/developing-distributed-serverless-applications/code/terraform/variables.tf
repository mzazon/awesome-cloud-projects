# Variables for Multi-Region Aurora DSQL Application Infrastructure
# This file defines all configurable parameters for the multi-region deployment

# =============================================================================
# REGION CONFIGURATION
# =============================================================================

variable "primary_region" {
  description = "Primary AWS region for Aurora DSQL cluster deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1", "ap-southeast-1",
      "ap-southeast-2", "ap-northeast-1"
    ], var.primary_region)
    error_message = "Primary region must be a valid AWS region supported by Aurora DSQL."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for Aurora DSQL cluster deployment"
  type        = string
  default     = "us-east-2"

  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1", "ap-southeast-1",
      "ap-southeast-2", "ap-northeast-1"
    ], var.secondary_region)
    error_message = "Secondary region must be a valid AWS region supported by Aurora DSQL."
  }
}

variable "witness_region" {
  description = "Witness region for Aurora DSQL multi-region configuration"
  type        = string
  default     = "us-west-2"

  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1", "ap-southeast-1",
      "ap-southeast-2", "ap-northeast-1"
    ], var.witness_region)
    error_message = "Witness region must be a valid AWS region supported by Aurora DSQL."
  }
}

# =============================================================================
# AURORA DSQL CONFIGURATION
# =============================================================================

variable "cluster_name_prefix" {
  description = "Prefix for Aurora DSQL cluster names"
  type        = string
  default     = "multi-region-app"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.cluster_name_prefix))
    error_message = "Cluster name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and be 1-62 characters long."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Aurora DSQL clusters"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Name of the database to create in Aurora DSQL clusters"
  type        = string
  default     = "postgres"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores."
  }
}

# =============================================================================
# LAMBDA CONFIGURATION
# =============================================================================

variable "lambda_function_name_prefix" {
  description = "Prefix for Lambda function names"
  type        = string
  default     = "multi-region-app"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,63}$", var.lambda_function_name_prefix))
    error_message = "Lambda function name prefix must contain only alphanumeric characters, hyphens, and underscores, and be 1-63 characters long."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.11"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions (null for unreserved)"
  type        = number
  default     = null

  validation {
    condition     = var.lambda_reserved_concurrency == null || (var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000)
    error_message = "Lambda reserved concurrency must be between 0 and 1000, or null for unreserved."
  }
}

# =============================================================================
# API GATEWAY CONFIGURATION
# =============================================================================

variable "api_gateway_name_prefix" {
  description = "Prefix for API Gateway names"
  type        = string
  default     = "multi-region-api"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]{1,128}$", var.api_gateway_name_prefix))
    error_message = "API Gateway name prefix must contain only alphanumeric characters, hyphens, dots, and underscores, and be 1-128 characters long."
  }
}

variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,128}$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, hyphens, and underscores, and be 1-128 characters long."
  }
}

variable "enable_api_gateway_logging" {
  description = "Enable CloudWatch logging for API Gateway"
  type        = bool
  default     = true
}

variable "api_gateway_throttle_rate_limit" {
  description = "Request rate limit for API Gateway throttling"
  type        = number
  default     = 1000

  validation {
    condition     = var.api_gateway_throttle_rate_limit > 0
    error_message = "API Gateway throttle rate limit must be greater than 0."
  }
}

variable "api_gateway_throttle_burst_limit" {
  description = "Burst limit for API Gateway throttling"
  type        = number
  default     = 2000

  validation {
    condition     = var.api_gateway_throttle_burst_limit > 0
    error_message = "API Gateway throttle burst limit must be greater than 0."
  }
}

# =============================================================================
# ROUTE 53 CONFIGURATION
# =============================================================================

variable "create_route53_health_checks" {
  description = "Create Route 53 health checks for API Gateway endpoints"
  type        = bool
  default     = false
}

variable "route53_hosted_zone_id" {
  description = "Route 53 hosted zone ID for custom domain (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.route53_hosted_zone_id == "" || can(regex("^Z[A-Z0-9]{13}$", var.route53_hosted_zone_id))
    error_message = "Route 53 hosted zone ID must be empty or a valid hosted zone ID format."
  }
}

variable "custom_domain_name" {
  description = "Custom domain name for API Gateway (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.custom_domain_name == "" || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.custom_domain_name))
    error_message = "Custom domain name must be empty or a valid domain name."
  }
}

# =============================================================================
# MONITORING AND OBSERVABILITY
# =============================================================================

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "lambda_security_group_ids" {
  description = "List of security group IDs for Lambda functions (if deployed in VPC)"
  type        = list(string)
  default     = []
}

variable "lambda_subnet_ids" {
  description = "List of subnet IDs for Lambda functions (if deployed in VPC)"
  type        = list(string)
  default     = []
}

variable "enable_api_key_required" {
  description = "Require API key for API Gateway endpoints"
  type        = bool
  default     = false
}

variable "cors_allow_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allow_headers" {
  description = "List of allowed headers for CORS configuration"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

variable "cors_allow_methods" {
  description = "List of allowed HTTP methods for CORS configuration"
  type        = list(string)
  default     = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
}

# =============================================================================
# TAGGING AND METADATA
# =============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "Environment must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 1-16 characters long."
  }
}

variable "cost_center" {
  description = "Cost center for resource allocation and billing"
  type        = string
  default     = "engineering"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.cost_center))
    error_message = "Cost center must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 1-32 characters long."
  }
}

variable "project_name" {
  description = "Project name for resource organization"
  type        = string
  default     = "multi-region-aurora-dsql"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.project_name))
    error_message = "Project name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 1-32 characters long."
  }
}

variable "owner" {
  description = "Owner or team responsible for the infrastructure"
  type        = string
  default     = "platform-team"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,31}$", var.owner))
    error_message = "Owner must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 1-32 characters long."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.additional_tags) <= 20
    error_message = "Additional tags map cannot contain more than 20 key-value pairs."
  }
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "create_sample_data" {
  description = "Create sample data in the database during initialization"
  type        = bool
  default     = true
}

variable "lambda_layer_arns" {
  description = "List of Lambda layer ARNs to attach to functions"
  type        = list(string)
  default     = []
}

variable "lambda_environment_variables" {
  description = "Additional environment variables for Lambda functions"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.lambda_environment_variables) <= 10
    error_message = "Lambda environment variables map cannot contain more than 10 key-value pairs."
  }
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights for Aurora DSQL clusters (if supported)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention period in days for Aurora DSQL clusters"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "maintenance_window" {
  description = "Preferred maintenance window for Aurora DSQL clusters (format: ddd:hh24:mi-ddd:hh24:mi)"
  type        = string
  default     = "sun:03:00-sun:04:00"

  validation {
    condition     = can(regex("^[a-z]{3}:[0-2][0-9]:[0-5][0-9]-[a-z]{3}:[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "Maintenance window must be in the format ddd:hh24:mi-ddd:hh24:mi (e.g., sun:03:00-sun:04:00)."
  }
}