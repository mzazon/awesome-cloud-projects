# Input variables for AWS Lambda Cost Optimization with Compute Optimizer infrastructure
# These variables allow customization of the deployment for different environments and requirements

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "lambda-cost-optimizer"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "cost_center" {
  description = "Cost center tag for billing and cost tracking"
  type        = string
  default     = "engineering"
}

# Compute Optimizer Configuration
variable "enable_compute_optimizer" {
  description = "Whether to automatically enroll in AWS Compute Optimizer"
  type        = bool
  default     = true
}

variable "compute_optimizer_enrollment_status" {
  description = "Compute Optimizer enrollment status (Active or Inactive)"
  type        = string
  default     = "Active"

  validation {
    condition     = contains(["Active", "Inactive"], var.compute_optimizer_enrollment_status)
    error_message = "Compute Optimizer enrollment status must be either 'Active' or 'Inactive'."
  }
}

# Lambda Function Configuration
variable "create_sample_functions" {
  description = "Whether to create sample Lambda functions for testing optimization"
  type        = bool
  default     = true
}

variable "sample_function_count" {
  description = "Number of sample Lambda functions to create for testing"
  type        = number
  default     = 3

  validation {
    condition     = var.sample_function_count >= 1 && var.sample_function_count <= 10
    error_message = "Sample function count must be between 1 and 10."
  }
}

variable "lambda_memory_sizes" {
  description = "List of memory sizes for sample Lambda functions (in MB)"
  type        = list(number)
  default     = [128, 512, 1024]

  validation {
    condition = alltrue([
      for size in var.lambda_memory_sizes : size >= 128 && size <= 10240
    ])
    error_message = "Lambda memory sizes must be between 128 MB and 10,240 MB."
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

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.11"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x", "java11", "java17", "java21",
      "dotnet6", "dotnet8", "go1.x", "ruby3.2", "ruby3.3"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported AWS Lambda runtime."
  }
}

# Monitoring and Alerting Configuration
variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "error_threshold" {
  description = "Error count threshold for CloudWatch alarms"
  type        = number
  default     = 5

  validation {
    condition     = var.error_threshold >= 1
    error_message = "Error threshold must be at least 1."
  }
}

variable "duration_threshold_ms" {
  description = "Duration threshold in milliseconds for CloudWatch alarms"
  type        = number
  default     = 10000

  validation {
    condition     = var.duration_threshold_ms >= 1000
    error_message = "Duration threshold must be at least 1000 milliseconds."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

# Notification Configuration
variable "create_sns_topic" {
  description = "Whether to create SNS topic for notifications"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Cost and Usage Analysis Configuration
variable "enable_cost_analysis" {
  description = "Whether to create resources for cost analysis and reporting"
  type        = bool
  default     = true
}

variable "cost_analysis_schedule" {
  description = "CloudWatch Events schedule expression for cost analysis (e.g., 'rate(1 day)')"
  type        = string
  default     = "rate(1 day)"

  validation {
    condition     = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.cost_analysis_schedule))
    error_message = "Cost analysis schedule must be a valid CloudWatch Events schedule expression."
  }
}

# Test Configuration
variable "enable_test_invocations" {
  description = "Whether to automatically invoke sample functions to generate metrics"
  type        = bool
  default     = false
}

variable "test_invocation_count" {
  description = "Number of test invocations per sample function"
  type        = number
  default     = 50

  validation {
    condition     = var.test_invocation_count >= 10 && var.test_invocation_count <= 1000
    error_message = "Test invocation count must be between 10 and 1000."
  }
}

# Resource Management
variable "retention_in_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.retention_in_days)
    error_message = "Retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_xray_tracing" {
  description = "Whether to enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

# Security Configuration
variable "create_kms_key" {
  description = "Whether to create a KMS key for encryption"
  type        = bool
  default     = false
}

variable "lambda_environment_variables" {
  description = "Environment variables for Lambda functions"
  type        = map(string)
  default = {
    LOG_LEVEL = "INFO"
    ENVIRONMENT = "development"
  }

  validation {
    condition     = length(var.lambda_environment_variables) <= 10
    error_message = "Maximum of 10 environment variables allowed."
  }
}