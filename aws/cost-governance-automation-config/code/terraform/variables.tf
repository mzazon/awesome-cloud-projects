# Variables for Cost Governance Infrastructure

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
  default     = "cost-governance"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "notification_email" {
  description = "Email address for cost governance notifications"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold for idle instance detection (percentage)"
  type        = number
  default     = 5.0
  
  validation {
    condition = var.cpu_utilization_threshold >= 0 && var.cpu_utilization_threshold <= 100
    error_message = "CPU utilization threshold must be between 0 and 100."
  }
}

variable "volume_age_threshold_days" {
  description = "Age threshold in days for unattached volume cleanup"
  type        = number
  default     = 7
  
  validation {
    condition = var.volume_age_threshold_days >= 1
    error_message = "Volume age threshold must be at least 1 day."
  }
}

variable "enable_config_recorder" {
  description = "Enable AWS Config recorder (may incur costs)"
  type        = bool
  default     = true
}

variable "enable_scheduled_scans" {
  description = "Enable scheduled cost optimization scans"
  type        = bool
  default     = true
}

variable "scan_schedule_rate" {
  description = "Schedule expression for cost optimization scans (e.g., 'rate(7 days)')"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition = can(regex("^(rate|cron)\\(.*\\)$", var.scan_schedule_rate))
    error_message = "Schedule rate must be a valid AWS EventBridge schedule expression."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for ALB"
  type        = bool
  default     = false
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days after which to transition S3 objects to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition = var.s3_lifecycle_transition_days >= 30
    error_message = "S3 lifecycle transition must be at least 30 days."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "CostGovernance"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

variable "config_resource_types" {
  description = "List of AWS resource types to monitor with Config"
  type        = list(string)
  default = [
    "AWS::EC2::Instance",
    "AWS::EC2::Volume",
    "AWS::ElasticLoadBalancing::LoadBalancer",
    "AWS::ElasticLoadBalancingV2::LoadBalancer",
    "AWS::RDS::DBInstance",
    "AWS::S3::Bucket"
  ]
}