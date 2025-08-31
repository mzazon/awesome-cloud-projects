# AWS Region configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format 'us-west-2', 'eu-central-1', etc."
  }
}

# Environment configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Lambda function configuration
variable "function_name" {
  description = "Name for the log retention management Lambda function"
  type        = string
  default     = "log-retention-manager"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]{1,64}$", var.function_name))
    error_message = "Function name must be 1-64 characters and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Default retention policy configuration
variable "default_retention_days" {
  description = "Default retention period in days for unmatched log groups"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.default_retention_days)
    error_message = "Retention days must be a valid CloudWatch Logs retention period."
  }
}

# EventBridge schedule configuration
variable "schedule_expression" {
  description = "EventBridge schedule expression for automated execution"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.schedule_expression))
    error_message = "Schedule expression must be a valid rate() or cron() expression."
  }
}

variable "schedule_enabled" {
  description = "Whether to enable the EventBridge schedule"
  type        = bool
  default     = true
}

# Log retention rules configuration
variable "retention_rules" {
  description = "Map of log group patterns to retention days"
  type = map(number)
  default = {
    "/aws/lambda/"      = 30
    "/aws/apigateway/"  = 90
    "/aws/codebuild/"   = 14
    "/aws/ecs/"         = 60
    "/aws/stepfunctions/" = 90
    "/application/"     = 180
    "/system/"          = 365
  }
  
  validation {
    condition = alltrue([
      for retention in values(var.retention_rules) :
      contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], retention)
    ])
    error_message = "All retention values must be valid CloudWatch Logs retention periods."
  }
}

# Test log groups configuration
variable "create_test_log_groups" {
  description = "Whether to create test log groups for demonstration"
  type        = bool
  default     = false
}

variable "test_log_groups" {
  description = "List of test log group names to create"
  type        = list(string)
  default = [
    "/aws/lambda/test-function",
    "/aws/apigateway/test-api",
    "/application/web-app",
    "/aws/test-logs"
  ]
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = ""
  
  validation {
    condition = var.resource_prefix == "" || can(regex("^[a-zA-Z0-9-_]{1,20}$", var.resource_prefix))
    error_message = "Resource prefix must be empty or 1-20 characters containing only letters, numbers, hyphens, and underscores."
  }
}

# IAM role configuration
variable "iam_role_name" {
  description = "Name for the Lambda execution IAM role"
  type        = string
  default     = "LogRetentionManagerRole"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.iam_role_name))
    error_message = "IAM role name must be 1-64 characters and contain only valid IAM characters."
  }
}

# EventBridge rule configuration
variable "eventbridge_rule_name" {
  description = "Name for the EventBridge rule"
  type        = string
  default     = "log-retention-schedule"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]{1,64}$", var.eventbridge_rule_name))
    error_message = "EventBridge rule name must be 1-64 characters and contain only letters, numbers, periods, hyphens, and underscores."
  }
}

# Lambda runtime configuration
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.12"
  
  validation {
    condition = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}