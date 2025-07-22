# ==============================================================================
# GENERAL CONFIGURATION
# ==============================================================================

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
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "serverless-etl"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# S3 CONFIGURATION
# ==============================================================================

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (suffix will be auto-generated)"
  type        = string
  default     = "serverless-etl-pipeline"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30

  validation {
    condition = var.s3_transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "s3_transition_to_glacier_days" {
  description = "Number of days after which objects transition to Glacier storage class"
  type        = number
  default     = 90

  validation {
    condition = var.s3_transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

# ==============================================================================
# AWS GLUE CONFIGURATION
# ==============================================================================

variable "glue_database_name" {
  description = "Name for AWS Glue database"
  type        = string
  default     = "etl_database"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.glue_database_name))
    error_message = "Glue database name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "glue_job_name" {
  description = "Name for AWS Glue ETL job"
  type        = string
  default     = "etl_job"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.glue_job_name))
    error_message = "Glue job name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "glue_crawler_name" {
  description = "Name for AWS Glue crawler"
  type        = string
  default     = "etl_crawler"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.glue_crawler_name))
    error_message = "Glue crawler name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "glue_workflow_name" {
  description = "Name for AWS Glue workflow"
  type        = string
  default     = "etl_workflow"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.glue_workflow_name))
    error_message = "Glue workflow name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "glue_job_timeout" {
  description = "Timeout for Glue job in minutes"
  type        = number
  default     = 60

  validation {
    condition = var.glue_job_timeout > 0 && var.glue_job_timeout <= 2880
    error_message = "Glue job timeout must be between 1 and 2880 minutes."
  }
}

variable "glue_job_max_retries" {
  description = "Maximum number of retries for Glue job"
  type        = number
  default     = 1

  validation {
    condition = var.glue_job_max_retries >= 0 && var.glue_job_max_retries <= 10
    error_message = "Glue job max retries must be between 0 and 10."
  }
}

variable "glue_job_worker_type" {
  description = "Worker type for Glue job"
  type        = string
  default     = "G.1X"

  validation {
    condition = contains(["Standard", "G.1X", "G.2X", "G.025X"], var.glue_job_worker_type)
    error_message = "Glue job worker type must be one of: Standard, G.1X, G.2X, G.025X."
  }
}

variable "glue_job_number_of_workers" {
  description = "Number of workers for Glue job"
  type        = number
  default     = 2

  validation {
    condition = var.glue_job_number_of_workers >= 2
    error_message = "Glue job must have at least 2 workers."
  }
}

variable "glue_job_glue_version" {
  description = "AWS Glue version for ETL job"
  type        = string
  default     = "4.0"

  validation {
    condition = contains(["2.0", "3.0", "4.0"], var.glue_job_glue_version)
    error_message = "Glue version must be one of: 2.0, 3.0, 4.0."
  }
}

variable "crawler_schedule" {
  description = "Schedule expression for Glue crawler (cron format)"
  type        = string
  default     = "cron(0 1 * * ? *)"

  validation {
    condition = can(regex("^cron\\(.*\\)$", var.crawler_schedule))
    error_message = "Crawler schedule must be a valid cron expression."
  }
}

# ==============================================================================
# LAMBDA CONFIGURATION
# ==============================================================================

variable "lambda_function_name" {
  description = "Name for Lambda function"
  type        = string
  default     = "etl-orchestrator"

  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"

  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300

  validation {
    condition = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256

  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# ==============================================================================
# WORKFLOW CONFIGURATION
# ==============================================================================

variable "workflow_schedule" {
  description = "Schedule expression for workflow trigger (cron format)"
  type        = string
  default     = "cron(0 2 * * ? *)"

  validation {
    condition = can(regex("^cron\\(.*\\)$", var.workflow_schedule))
    error_message = "Workflow schedule must be a valid cron expression."
  }
}

variable "enable_workflow_trigger" {
  description = "Enable scheduled trigger for workflow"
  type        = bool
  default     = true
}

# ==============================================================================
# MONITORING CONFIGURATION
# ==============================================================================

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for all services"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

# ==============================================================================
# S3 EVENT NOTIFICATION CONFIGURATION
# ==============================================================================

variable "enable_s3_notifications" {
  description = "Enable S3 event notifications to trigger Lambda"
  type        = bool
  default     = true
}

variable "s3_notification_prefix" {
  description = "S3 object prefix filter for notifications"
  type        = string
  default     = "raw-data/"
}

variable "s3_notification_suffix" {
  description = "S3 object suffix filter for notifications"
  type        = string
  default     = ".csv"
}

# ==============================================================================
# TAGGING CONFIGURATION
# ==============================================================================

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ServerlessETL"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Recipe      = "serverless-etl-pipelines-glue-lambda"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}