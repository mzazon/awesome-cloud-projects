# Input variables for the content caching strategies infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cache-demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "elasticache_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
  
  validation {
    condition = can(regex("^cache\\.", var.elasticache_node_type))
    error_message = "ElastiCache node type must be a valid cache instance type."
  }
}

variable "elasticache_port" {
  description = "Port for ElastiCache Redis cluster"
  type        = number
  default     = 6379
  
  validation {
    condition = var.elasticache_port > 1024 && var.elasticache_port < 65535
    error_message = "ElastiCache port must be between 1024 and 65535."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "api_cache_ttl_default" {
  description = "Default TTL for API responses in CloudFront (seconds)"
  type        = number
  default     = 60
  
  validation {
    condition = var.api_cache_ttl_default >= 0 && var.api_cache_ttl_default <= 31536000
    error_message = "API cache TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "api_cache_ttl_max" {
  description = "Maximum TTL for API responses in CloudFront (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition = var.api_cache_ttl_max >= var.api_cache_ttl_default && var.api_cache_ttl_max <= 31536000
    error_message = "API cache max TTL must be greater than or equal to default TTL and less than 31536000 seconds."
  }
}

variable "elasticache_ttl" {
  description = "Default TTL for data in ElastiCache (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition = var.elasticache_ttl > 0 && var.elasticache_ttl <= 86400
    error_message = "ElastiCache TTL must be between 1 and 86400 seconds (24 hours)."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "cache_hit_ratio_threshold" {
  description = "CloudFront cache hit ratio threshold for alarms (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition = var.cache_hit_ratio_threshold >= 0 && var.cache_hit_ratio_threshold <= 100
    error_message = "Cache hit ratio threshold must be between 0 and 100."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}