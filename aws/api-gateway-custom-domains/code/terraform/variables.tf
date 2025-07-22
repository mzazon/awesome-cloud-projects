# Core Configuration Variables
variable "domain_name" {
  type        = string
  description = "The base domain name (e.g., example.com)"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.domain_name))
    error_message = "Domain name must be a valid domain format (e.g., example.com)."
  }
}

variable "api_subdomain" {
  type        = string
  description = "The subdomain for the API (e.g., api)"
  default     = "api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.api_subdomain))
    error_message = "API subdomain must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  type        = string
  description = "Name of the project for resource naming"
  default     = "petstore-api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# SSL/TLS Configuration
variable "certificate_validation_method" {
  type        = string
  description = "Method to validate ACM certificate (DNS or EMAIL)"
  default     = "DNS"
  
  validation {
    condition     = contains(["DNS", "EMAIL"], var.certificate_validation_method)
    error_message = "Certificate validation method must be either DNS or EMAIL."
  }
}

variable "certificate_transparency_logging" {
  type        = bool
  description = "Enable certificate transparency logging for ACM certificate"
  default     = true
}

# API Gateway Configuration
variable "api_gateway_endpoint_type" {
  type        = string
  description = "API Gateway endpoint type (REGIONAL, EDGE, or PRIVATE)"
  default     = "REGIONAL"
  
  validation {
    condition     = contains(["REGIONAL", "EDGE", "PRIVATE"], var.api_gateway_endpoint_type)
    error_message = "API Gateway endpoint type must be REGIONAL, EDGE, or PRIVATE."
  }
}

variable "api_gateway_minimum_tls_version" {
  type        = string
  description = "Minimum TLS version for custom domain"
  default     = "TLS_1_2"
  
  validation {
    condition     = contains(["TLS_1_0", "TLS_1_2"], var.api_gateway_minimum_tls_version)
    error_message = "TLS version must be TLS_1_0 or TLS_1_2."
  }
}

# Throttling Configuration
variable "api_throttle_rate_limit" {
  type        = number
  description = "API Gateway throttling rate limit (requests per second)"
  default     = 100
  
  validation {
    condition     = var.api_throttle_rate_limit > 0 && var.api_throttle_rate_limit <= 10000
    error_message = "Throttle rate limit must be between 1 and 10000."
  }
}

variable "api_throttle_burst_limit" {
  type        = number
  description = "API Gateway throttling burst limit"
  default     = 200
  
  validation {
    condition     = var.api_throttle_burst_limit > 0 && var.api_throttle_burst_limit <= 5000
    error_message = "Throttle burst limit must be between 1 and 5000."
  }
}

variable "dev_throttle_rate_limit" {
  type        = number
  description = "Development stage throttling rate limit"
  default     = 50
  
  validation {
    condition     = var.dev_throttle_rate_limit > 0 && var.dev_throttle_rate_limit <= 1000
    error_message = "Dev throttle rate limit must be between 1 and 1000."
  }
}

variable "dev_throttle_burst_limit" {
  type        = number
  description = "Development stage throttling burst limit"
  default     = 100
  
  validation {
    condition     = var.dev_throttle_burst_limit > 0 && var.dev_throttle_burst_limit <= 2000
    error_message = "Dev throttle burst limit must be between 1 and 2000."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  type        = string
  description = "Lambda runtime version"
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported version."
  }
}

variable "lambda_timeout" {
  type        = number
  description = "Lambda function timeout in seconds"
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  type        = number
  description = "Lambda function memory size in MB"
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Authorizer Configuration
variable "authorizer_token_ttl" {
  type        = number
  description = "Custom authorizer token TTL in seconds"
  default     = 300
  
  validation {
    condition     = var.authorizer_token_ttl >= 0 && var.authorizer_token_ttl <= 3600
    error_message = "Authorizer token TTL must be between 0 and 3600 seconds."
  }
}

# DNS Configuration
variable "route53_hosted_zone_id" {
  type        = string
  description = "Route 53 hosted zone ID for the domain (optional)"
  default     = ""
}

variable "dns_record_ttl" {
  type        = number
  description = "TTL for DNS records in seconds"
  default     = 300
  
  validation {
    condition     = var.dns_record_ttl >= 60 && var.dns_record_ttl <= 86400
    error_message = "DNS record TTL must be between 60 and 86400 seconds."
  }
}

# Monitoring and Logging
variable "enable_cloudwatch_logs" {
  type        = bool
  description = "Enable CloudWatch logging for Lambda functions"
  default     = true
}

variable "cloudwatch_log_retention_days" {
  type        = number
  description = "CloudWatch log retention period in days"
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid value."
  }
}

variable "enable_api_gateway_logging" {
  type        = bool
  description = "Enable API Gateway access logging"
  default     = true
}

# Tags
variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}