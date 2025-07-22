# Input variables for the API Gateway and WAF security configuration

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1' or similar."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "api-security"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "api_name" {
  description = "Name for the API Gateway REST API"
  type        = string
  default     = "protected-api"
  
  validation {
    condition     = length(var.api_name) >= 3 && length(var.api_name) <= 64
    error_message = "API name must be between 3 and 64 characters."
  }
}

variable "rate_limit" {
  description = "Rate limit for WAF rule (requests per 5-minute window per IP)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.rate_limit >= 100 && var.rate_limit <= 20000000
    error_message = "Rate limit must be between 100 and 20,000,000 requests per 5-minute window."
  }
}

variable "blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2 format)"
  type        = list(string)
  default     = ["CN", "RU", "KP"]
  
  validation {
    condition = alltrue([
      for code in var.blocked_countries : can(regex("^[A-Z]{2}$", code))
    ])
    error_message = "Country codes must be 2-letter uppercase ISO 3166-1 alpha-2 format (e.g., US, GB, JP)."
  }
}

variable "enable_geo_blocking" {
  description = "Enable geographic blocking rule in WAF"
  type        = bool
  default     = true
}

variable "enable_waf_logging" {
  description = "Enable WAF request logging to CloudWatch"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain WAF logs in CloudWatch"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be one of the allowed CloudWatch values."
  }
}

variable "api_stage_name" {
  description = "Name of the API Gateway deployment stage"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.api_stage_name))
    error_message = "Stage name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for API Gateway"
  type        = bool
  default     = true
}