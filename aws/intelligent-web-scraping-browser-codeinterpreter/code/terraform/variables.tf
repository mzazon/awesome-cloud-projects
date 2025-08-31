# Variables for Intelligent Web Scraping Infrastructure
# This file defines all configurable parameters for the Terraform deployment

#==============================================================================
# GENERAL CONFIGURATION VARIABLES
#==============================================================================

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format of 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and configuration"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "intelligent-scraper"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_prefix))
    error_message = "Project prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

#==============================================================================
# LAMBDA FUNCTION CONFIGURATION
#==============================================================================

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds (max 900 for standard Lambda)"
  type        = number
  default     = 900
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB (must be between 128 and 10240)"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.11"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "log_level" {
  description = "Log level for Lambda function (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

#==============================================================================
# SCHEDULING AND AUTOMATION CONFIGURATION
#==============================================================================

variable "enable_scheduling" {
  description = "Enable automatic scheduling of scraping jobs via EventBridge"
  type        = bool
  default     = true
}

variable "scraping_schedule" {
  description = "EventBridge schedule expression for automated scraping (rate or cron format)"
  type        = string
  default     = "rate(6 hours)"
  
  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.scraping_schedule))
    error_message = "Schedule must be a valid EventBridge rate or cron expression."
  }
}

#==============================================================================
# MONITORING AND ALERTING CONFIGURATION
#==============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_alerts" {
  description = "Enable CloudWatch alarms for monitoring Lambda function performance"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "ARN of SNS topic for alarm notifications (optional, leave empty to disable notifications)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_topic_arn == "" || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]+$", var.sns_topic_arn))
    error_message = "SNS topic ARN must be empty or a valid ARN format."
  }
}

variable "alarm_error_threshold" {
  description = "Number of errors that trigger CloudWatch alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.alarm_error_threshold > 0 && var.alarm_error_threshold <= 100
    error_message = "Error threshold must be between 1 and 100."
  }
}

#==============================================================================
# S3 CONFIGURATION
#==============================================================================

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names (will be combined with random suffix)"
  type        = string
  default     = "intelligent-scraper"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets for data retention and recovery"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle policies for cost optimization"
  type        = bool
  default     = false
}

variable "s3_transition_days" {
  description = "Number of days after which objects transition to Standard-IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_days >= 30
    error_message = "S3 transition days must be at least 30 days for Standard-IA."
  }
}

variable "s3_glacier_transition_days" {
  description = "Number of days after which objects transition to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_glacier_transition_days >= 90
    error_message = "S3 Glacier transition days must be at least 90 days."
  }
}

#==============================================================================
# AGENTCORE CONFIGURATION
#==============================================================================

variable "browser_session_timeout" {
  description = "Default timeout for AgentCore Browser sessions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.browser_session_timeout >= 30 && var.browser_session_timeout <= 3600
    error_message = "Browser session timeout must be between 30 and 3600 seconds."
  }
}

variable "code_interpreter_timeout" {
  description = "Default timeout for AgentCore Code Interpreter sessions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.code_interpreter_timeout >= 30 && var.code_interpreter_timeout <= 3600
    error_message = "Code interpreter timeout must be between 30 and 3600 seconds."
  }
}

variable "max_concurrent_sessions" {
  description = "Maximum number of concurrent AgentCore sessions (per service type)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_concurrent_sessions >= 1 && var.max_concurrent_sessions <= 20
    error_message = "Max concurrent sessions must be between 1 and 20."
  }
}

#==============================================================================
# SCRAPING CONFIGURATION
#==============================================================================

variable "default_user_agent" {
  description = "Default user agent string for web scraping sessions"
  type        = string
  default     = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

variable "scraping_retry_attempts" {
  description = "Number of retry attempts for failed scraping operations"
  type        = number
  default     = 3
  
  validation {
    condition     = var.scraping_retry_attempts >= 1 && var.scraping_retry_attempts <= 10
    error_message = "Retry attempts must be between 1 and 10."
  }
}

variable "data_quality_threshold" {
  description = "Minimum data quality score (0-100) required for successful scraping"
  type        = number
  default     = 70
  
  validation {
    condition     = var.data_quality_threshold >= 0 && var.data_quality_threshold <= 100
    error_message = "Data quality threshold must be between 0 and 100."
  }
}

#==============================================================================
# SECURITY CONFIGURATION
#==============================================================================

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for S3 and other AWS services (requires VPC deployment)"
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting sensitive data (optional, uses default AWS managed keys if not specified)"
  type        = string
  default     = ""
  
  validation {
    condition = var.kms_key_id == "" || can(regex("^(arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+|[a-f0-9-]+)$", var.kms_key_id))
    error_message = "KMS key ID must be empty or a valid key ID or ARN."
  }
}

variable "allowed_source_ips" {
  description = "List of IP addresses/CIDR blocks allowed to invoke Lambda (empty list allows all)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for ip in var.allowed_source_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All entries in allowed_source_ips must be valid CIDR blocks."
  }
}

#==============================================================================
# COST OPTIMIZATION CONFIGURATION
#==============================================================================

variable "enable_cost_allocation_tags" {
  description = "Enable comprehensive cost allocation tags for resource tracking"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center identifier for billing and resource allocation tracking"
  type        = string
  default     = "engineering"
}

variable "business_unit" {
  description = "Business unit responsible for the scraping infrastructure"
  type        = string
  default     = "data-analytics"
}

#==============================================================================
# ADVANCED CONFIGURATION
#==============================================================================

variable "enable_x_ray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda function performance monitoring"
  type        = bool
  default     = false
}

variable "reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (0 = unlimited, -1 = disable function)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.reserved_concurrency >= -1 && var.reserved_concurrency <= 1000
    error_message = "Reserved concurrency must be between -1 and 1000."
  }
}

variable "provisioned_concurrency" {
  description = "Provisioned concurrency for Lambda function to reduce cold starts"
  type        = number
  default     = 0
  
  validation {
    condition     = var.provisioned_concurrency >= 0 && var.provisioned_concurrency <= 1000
    error_message = "Provisioned concurrency must be between 0 and 1000."
  }
}

variable "custom_metrics_namespace" {
  description = "Custom CloudWatch metrics namespace for application-specific metrics"
  type        = string
  default     = "IntelligentScraper"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+$", var.custom_metrics_namespace))
    error_message = "Metrics namespace must contain only letters, numbers, periods, underscores, hyphens, and forward slashes."
  }
}