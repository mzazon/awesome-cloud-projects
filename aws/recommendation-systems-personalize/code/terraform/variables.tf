# Core configuration variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
}

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
  description = "Name of the project for resource naming"
  type        = string
  default     = "recommendation-system"
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for training data (will be made unique with random suffix)"
  type        = string
  default     = "personalize-training-data"
}

variable "s3_versioning_enabled" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

# Amazon Personalize Configuration
variable "dataset_group_name" {
  description = "Name of the Amazon Personalize dataset group"
  type        = string
  default     = "ecommerce-recommendations"
}

variable "solution_name" {
  description = "Name of the Amazon Personalize solution"
  type        = string
  default     = "user-personalization-solution"
}

variable "campaign_name" {
  description = "Name of the Amazon Personalize campaign"
  type        = string
  default     = "real-time-recommendations"
}

variable "min_provisioned_tps" {
  description = "Minimum provisioned transactions per second for the Personalize campaign"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_provisioned_tps >= 1
    error_message = "Minimum provisioned TPS must be at least 1."
  }
}

variable "personalize_recipe_arn" {
  description = "ARN of the Amazon Personalize recipe to use"
  type        = string
  default     = "arn:aws:personalize:::recipe/aws-user-personalization"
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name of the Lambda function for recommendation API"
  type        = string
  default     = "recommendation-api"
}

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
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

# API Gateway Configuration
variable "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  type        = string
  default     = "recommendation-api"
}

variable "api_gateway_stage_name" {
  description = "Name of the API Gateway deployment stage"
  type        = string
  default     = "prod"
}

variable "api_gateway_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 1000
}

variable "api_gateway_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 2000
}

variable "enable_api_gateway_logs" {
  description = "Enable API Gateway access logs"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda and API Gateway"
  type        = bool
  default     = true
}

# Monitoring and Alerting
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_email_endpoint" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "error_rate_threshold" {
  description = "Error rate threshold for CloudWatch alarms (percentage)"
  type        = number
  default     = 5.0
}

variable "latency_threshold" {
  description = "Latency threshold for CloudWatch alarms (milliseconds)"
  type        = number
  default     = 5000
}

# Security Configuration
variable "enable_waf" {
  description = "Enable AWS WAF for API Gateway"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "List of allowed headers for CORS"
  type        = list(string)
  default     = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token"]
}

# Cost Optimization
variable "enable_s3_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days after which to transition S3 objects to IA storage"
  type        = number
  default     = 30
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}