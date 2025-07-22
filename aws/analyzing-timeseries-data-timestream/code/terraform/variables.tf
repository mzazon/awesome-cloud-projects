# Variables for Amazon Timestream Time-Series Data Solution
# This file defines all input variables for the Terraform configuration

# === GENERAL CONFIGURATION ===

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "cost_center" {
  description = "Cost center for resource billing and tracking"
  type        = string
  default     = "engineering"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "timestream-iot"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# === TIMESTREAM DATABASE CONFIGURATION ===

variable "database_name" {
  description = "Name of the Timestream database"
  type        = string
  default     = null  # Will be auto-generated if not provided
  
  validation {
    condition = var.database_name == null || (
      length(var.database_name) >= 3 && 
      length(var.database_name) <= 64 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.database_name))
    )
    error_message = "Database name must be 3-64 characters, start with letter, contain only alphanumeric, underscore, or hyphen."
  }
}

variable "table_name" {
  description = "Name of the Timestream table for sensor data"
  type        = string
  default     = "sensor-data"
  
  validation {
    condition = (
      length(var.table_name) >= 3 && 
      length(var.table_name) <= 64 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.table_name))
    )
    error_message = "Table name must be 3-64 characters, start with letter, contain only alphanumeric, underscore, or hyphen."
  }
}

# === DATA RETENTION CONFIGURATION ===

variable "memory_store_retention_hours" {
  description = "Memory store retention period in hours (for fast queries)"
  type        = number
  default     = 24
  
  validation {
    condition     = var.memory_store_retention_hours >= 1 && var.memory_store_retention_hours <= 8766
    error_message = "Memory store retention must be between 1 hour and 8766 hours (1 year)."
  }
}

variable "magnetic_store_retention_days" {
  description = "Magnetic store retention period in days (for cost-effective storage)"
  type        = number
  default     = 365
  
  validation {
    condition     = var.magnetic_store_retention_days >= 1 && var.magnetic_store_retention_days <= 73000
    error_message = "Magnetic store retention must be between 1 day and 73000 days (~200 years)."
  }
}

variable "enable_magnetic_store_writes" {
  description = "Enable writes to magnetic store for long-term storage"
  type        = bool
  default     = true
}

# === LAMBDA FUNCTION CONFIGURATION ===

variable "lambda_function_name" {
  description = "Name of the Lambda function for data ingestion"
  type        = string
  default     = null  # Will be auto-generated if not provided
  
  validation {
    condition = var.lambda_function_name == null || (
      length(var.lambda_function_name) >= 1 && 
      length(var.lambda_function_name) <= 64 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.lambda_function_name))
    )
    error_message = "Lambda function name must be 1-64 characters, start with letter, contain only alphanumeric, underscore, or hyphen."
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10240 MB."
  }
}

# === IOT CORE CONFIGURATION ===

variable "iot_rule_name" {
  description = "Name of the IoT Core rule for routing sensor data"
  type        = string
  default     = null  # Will be auto-generated if not provided
  
  validation {
    condition = var.iot_rule_name == null || (
      length(var.iot_rule_name) >= 1 && 
      length(var.iot_rule_name) <= 128 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.iot_rule_name))
    )
    error_message = "IoT rule name must be 1-128 characters, start with letter, contain only alphanumeric and underscore."
  }
}

variable "iot_topic_pattern" {
  description = "MQTT topic pattern for IoT sensor data"
  type        = string
  default     = "topic/sensors"
  
  validation {
    condition     = length(var.iot_topic_pattern) >= 1 && length(var.iot_topic_pattern) <= 256
    error_message = "IoT topic pattern must be between 1 and 256 characters."
  }
}

variable "iot_sql_version" {
  description = "AWS IoT SQL version for the rule"
  type        = string
  default     = "2016-03-23"
  
  validation {
    condition     = contains(["2015-10-08", "2016-03-23", "beta"], var.iot_sql_version)
    error_message = "IoT SQL version must be one of: 2015-10-08, 2016-03-23, beta."
  }
}

# === MONITORING CONFIGURATION ===

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "ingestion_latency_threshold_ms" {
  description = "CloudWatch alarm threshold for ingestion latency in milliseconds"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.ingestion_latency_threshold_ms > 0
    error_message = "Ingestion latency threshold must be positive."
  }
}

variable "query_latency_threshold_ms" {
  description = "CloudWatch alarm threshold for query latency in milliseconds"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.query_latency_threshold_ms > 0
    error_message = "Query latency threshold must be positive."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

# === S3 CONFIGURATION FOR REJECTED DATA ===

variable "enable_rejected_data_location" {
  description = "Enable S3 location for storing rejected Timestream records"
  type        = bool
  default     = true
}

variable "rejected_data_bucket_name" {
  description = "S3 bucket name for rejected data (if not provided, will be auto-generated)"
  type        = string
  default     = null
}

variable "rejected_data_prefix" {
  description = "S3 object key prefix for rejected data"
  type        = string
  default     = "rejected-records/"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9!_.*'()-/]*/$", var.rejected_data_prefix))
    error_message = "S3 prefix must be a valid S3 object key pattern ending with '/'."
  }
}

# === ENCRYPTION CONFIGURATION ===

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for Timestream database"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for Timestream encryption (if not provided, AWS managed key will be used)"
  type        = string
  default     = null
}

# === LOGGING CONFIGURATION ===

variable "log_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the supported CloudWatch retention periods."
  }
}

# === NETWORK CONFIGURATION ===

variable "enable_vpc_endpoint" {
  description = "Enable VPC endpoint for Timestream (requires VPC configuration)"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for VPC endpoint (required if enable_vpc_endpoint is true)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Subnet IDs for VPC endpoint (required if enable_vpc_endpoint is true)"
  type        = list(string)
  default     = []
}

# === ADDITIONAL TAGS ===

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.additional_tags) <= 50
    error_message = "Maximum of 50 additional tags allowed."
  }
}