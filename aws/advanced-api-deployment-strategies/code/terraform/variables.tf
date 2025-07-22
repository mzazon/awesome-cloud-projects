# General Configuration Variables
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "advanced-api-deployment"
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "advanced-api-deployment"
    ManagedBy   = "terraform"
  }
}

# API Gateway Configuration
variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
  default     = "advanced-deployment-api"
}

variable "api_description" {
  description = "Description of the API Gateway"
  type        = string
  default     = "Advanced deployment patterns demo API"
}

variable "api_stage_name" {
  description = "Name of the API Gateway production stage"
  type        = string
  default     = "production"
}

variable "api_staging_stage_name" {
  description = "Name of the API Gateway staging stage"
  type        = string
  default     = "staging"
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 128
}

# Blue-Green Deployment Configuration
variable "blue_function_name" {
  description = "Name for the blue Lambda function"
  type        = string
  default     = "blue-api-function"
}

variable "green_function_name" {
  description = "Name for the green Lambda function"
  type        = string
  default     = "green-api-function"
}

variable "blue_version" {
  description = "Version identifier for blue environment"
  type        = string
  default     = "v1.0.0"
}

variable "green_version" {
  description = "Version identifier for green environment"
  type        = string
  default     = "v2.0.0"
}

# Canary Deployment Configuration
variable "canary_percent_traffic" {
  description = "Percentage of traffic to route to canary deployment"
  type        = number
  default     = 10
  validation {
    condition     = var.canary_percent_traffic >= 0 && var.canary_percent_traffic <= 100
    error_message = "Canary traffic percentage must be between 0 and 100."
  }
}

variable "enable_canary_deployment" {
  description = "Enable canary deployment for the API"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_api_gateway_logging" {
  description = "Enable API Gateway logging"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for API Gateway"
  type        = bool
  default     = true
}

variable "enable_detailed_metrics" {
  description = "Enable detailed CloudWatch metrics"
  type        = bool
  default     = true
}

# CloudWatch Alarms Configuration
variable "error_rate_threshold" {
  description = "Error rate threshold for CloudWatch alarms"
  type        = number
  default     = 5
}

variable "latency_threshold" {
  description = "Latency threshold in milliseconds for CloudWatch alarms"
  type        = number
  default     = 5000
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for alarm evaluation"
  type        = number
  default     = 2
}

variable "alarm_datapoints_to_alarm" {
  description = "Number of datapoints that must be breaching to trigger alarm"
  type        = number
  default     = 2
}

# API Gateway Throttling Configuration
variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit per second"
  type        = number
  default     = 1000
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 2000
}

# Custom Domain Configuration (optional)
variable "custom_domain_name" {
  description = "Custom domain name for the API (optional)"
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for custom domain (required if custom_domain_name is set)"
  type        = string
  default     = null
}

# Route 53 Configuration (optional)
variable "route53_hosted_zone_id" {
  description = "Route 53 hosted zone ID for custom domain (optional)"
  type        = string
  default     = null
}

# Lambda Layer Configuration (optional)
variable "lambda_layer_arn" {
  description = "ARN of Lambda layer to attach to functions (optional)"
  type        = string
  default     = null
}

# VPC Configuration (optional)
variable "vpc_config" {
  description = "VPC configuration for Lambda functions"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

# Dead Letter Queue Configuration
variable "enable_dlq" {
  description = "Enable Dead Letter Queue for Lambda functions"
  type        = bool
  default     = true
}

# Reserved Concurrency Configuration
variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions"
  type        = number
  default     = 10
}