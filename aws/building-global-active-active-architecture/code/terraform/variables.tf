# Variables for multi-region active-active application with Global Accelerator

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "global-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "primary_region" {
  description = "Primary AWS region for the application"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region_eu" {
  description = "Secondary AWS region in Europe"
  type        = string
  default     = "eu-west-1"
}

variable "secondary_region_asia" {
  description = "Secondary AWS region in Asia Pacific"
  type        = string
  default     = "ap-southeast-1"
}

# DynamoDB Configuration
variable "dynamodb_table_name" {
  description = "Name of the DynamoDB Global Table"
  type        = string
  default     = "GlobalUserData"
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
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

# Application Load Balancer Configuration
variable "alb_enable_deletion_protection" {
  description = "Enable deletion protection for Application Load Balancers"
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "ALB idle timeout must be between 1 and 4000 seconds."
  }
}

# Global Accelerator Configuration
variable "accelerator_name" {
  description = "Name of the Global Accelerator"
  type        = string
  default     = "global-app-accelerator"
}

variable "accelerator_ip_address_type" {
  description = "IP address type for Global Accelerator"
  type        = string
  default     = "IPV4"
  
  validation {
    condition     = contains(["IPV4", "DUAL_STACK"], var.accelerator_ip_address_type)
    error_message = "IP address type must be either IPV4 or DUAL_STACK."
  }
}

variable "accelerator_enabled" {
  description = "Whether the Global Accelerator is enabled"
  type        = bool
  default     = true
}

# Health Check Configuration
variable "health_check_interval_seconds" {
  description = "Health check interval in seconds for Global Accelerator endpoints"
  type        = number
  default     = 30
  
  validation {
    condition     = var.health_check_interval_seconds >= 10 && var.health_check_interval_seconds <= 30
    error_message = "Health check interval must be between 10 and 30 seconds."
  }
}

variable "healthy_threshold_count" {
  description = "Number of consecutive health checks for healthy endpoint"
  type        = number
  default     = 3
  
  validation {
    condition     = var.healthy_threshold_count >= 2 && var.healthy_threshold_count <= 10
    error_message = "Healthy threshold count must be between 2 and 10."
  }
}

variable "unhealthy_threshold_count" {
  description = "Number of consecutive health checks for unhealthy endpoint"
  type        = number
  default     = 3
  
  validation {
    condition     = var.unhealthy_threshold_count >= 2 && var.unhealthy_threshold_count <= 10
    error_message = "Unhealthy threshold count must be between 2 and 10."
  }
}

# Traffic Configuration
variable "traffic_dial_percentage" {
  description = "Percentage of traffic directed to endpoint group"
  type        = number
  default     = 100
  
  validation {
    condition     = var.traffic_dial_percentage >= 0 && var.traffic_dial_percentage <= 100
    error_message = "Traffic dial percentage must be between 0 and 100."
  }
}

variable "endpoint_weight" {
  description = "Weight for endpoints in endpoint groups"
  type        = number
  default     = 100
  
  validation {
    condition     = var.endpoint_weight >= 0 && var.endpoint_weight <= 255
    error_message = "Endpoint weight must be between 0 and 255."
  }
}

# Networking Configuration
variable "use_default_vpc" {
  description = "Whether to use the default VPC in each region"
  type        = bool
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for ALBs"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_waf" {
  description = "Enable AWS WAF for Application Load Balancers"
  type        = bool
  default     = false
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions (null for unreserved)"
  type        = number
  default     = null
}

# Monitoring and Logging
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
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
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

# Optional Custom Domain Configuration
variable "custom_domain_name" {
  description = "Custom domain name for the application (optional)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (required if custom_domain_name is provided)"
  type        = string
  default     = ""
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization (if applicable)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 1 and 35."
  }
}