variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "fraud-detection"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis stream"
  type        = number
  default     = 3
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 10
    error_message = "Kinesis shard count must be between 1 and 10."
  }
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table"
  type        = number
  default     = 100
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table"
  type        = number
  default     = 100
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "lambda_enrichment_memory" {
  description = "Memory size for event enrichment Lambda function"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_enrichment_memory >= 128 && var.lambda_enrichment_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "lambda_processor_memory" {
  description = "Memory size for fraud detection processor Lambda function"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_processor_memory >= 128 && var.lambda_processor_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "alert_email" {
  description = "Email address for fraud alerts"
  type        = string
  default     = "fraud-alerts@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the supported values."
  }
}

variable "fraud_model_training_data_path" {
  description = "S3 path to fraud model training data (relative to bucket)"
  type        = string
  default     = "training-data/enhanced_training_data.csv"
}

variable "high_risk_score_threshold" {
  description = "Threshold for high risk fraud scores (0-1000)"
  type        = number
  default     = 900
  
  validation {
    condition     = var.high_risk_score_threshold >= 0 && var.high_risk_score_threshold <= 1000
    error_message = "High risk score threshold must be between 0 and 1000."
  }
}

variable "medium_risk_score_threshold" {
  description = "Threshold for medium risk fraud scores (0-1000)"
  type        = number
  default     = 600
  
  validation {
    condition     = var.medium_risk_score_threshold >= 0 && var.medium_risk_score_threshold <= 1000
    error_message = "Medium risk score threshold must be between 0 and 1000."
  }
}

variable "low_risk_score_threshold" {
  description = "Threshold for low risk fraud scores (0-1000)"
  type        = number
  default     = 400
  
  validation {
    condition     = var.low_risk_score_threshold >= 0 && var.low_risk_score_threshold <= 1000
    error_message = "Low risk score threshold must be between 0 and 1000."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for resources"
  type        = bool
  default     = true
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "fraud-detection"
    Environment = "dev"
    ManagedBy   = "terraform"
    Recipe      = "real-time-fraud-detection-amazon-fraud-detector"
  }
}