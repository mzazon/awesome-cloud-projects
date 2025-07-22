# Environment and naming variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "fraud-detection"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for unique resource naming"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

# S3 configuration
variable "training_data_bucket_versioning" {
  description = "Enable versioning on the S3 bucket for training data"
  type        = bool
  default     = true
}

variable "training_data_bucket_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

variable "training_data_lifecycle_enabled" {
  description = "Enable lifecycle management on training data bucket"
  type        = bool
  default     = true
}

variable "training_data_expiration_days" {
  description = "Number of days after which training data expires"
  type        = number
  default     = 365
  
  validation {
    condition     = var.training_data_expiration_days > 0
    error_message = "Training data expiration days must be greater than 0."
  }
}

# Fraud Detector configuration
variable "entity_type_description" {
  description = "Description for the customer entity type"
  type        = string
  default     = "Customer entity for fraud detection analysis"
}

variable "event_type_description" {
  description = "Description for the payment fraud event type"
  type        = string
  default     = "Payment fraud detection event for transaction analysis"
}

variable "model_type" {
  description = "Type of machine learning model for fraud detection"
  type        = string
  default     = "ONLINE_FRAUD_INSIGHTS"
  
  validation {
    condition     = contains(["ONLINE_FRAUD_INSIGHTS", "TRANSACTION_FRAUD_INSIGHTS"], var.model_type)
    error_message = "Model type must be either ONLINE_FRAUD_INSIGHTS or TRANSACTION_FRAUD_INSIGHTS."
  }
}

variable "event_ingestion" {
  description = "Enable event ingestion for the event type"
  type        = string
  default     = "ENABLED"
  
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.event_ingestion)
    error_message = "Event ingestion must be either ENABLED or DISABLED."
  }
}

# Rule configuration
variable "high_risk_score_threshold" {
  description = "Fraud score threshold for high-risk transactions requiring review"
  type        = number
  default     = 700
  
  validation {
    condition     = var.high_risk_score_threshold >= 0 && var.high_risk_score_threshold <= 1000
    error_message = "High risk score threshold must be between 0 and 1000."
  }
}

variable "fraud_score_threshold" {
  description = "Fraud score threshold for blocking obvious fraud"
  type        = number
  default     = 900
  
  validation {
    condition     = var.fraud_score_threshold >= 0 && var.fraud_score_threshold <= 1000
    error_message = "Fraud score threshold must be between 0 and 1000."
  }
}

variable "high_value_transaction_threshold" {
  description = "Transaction amount threshold for additional review"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.high_value_transaction_threshold > 0
    error_message = "High value transaction threshold must be greater than 0."
  }
}

variable "rule_execution_mode" {
  description = "Rule execution mode for the detector"
  type        = string
  default     = "FIRST_MATCHED"
  
  validation {
    condition     = contains(["FIRST_MATCHED", "ALL_MATCHED"], var.rule_execution_mode)
    error_message = "Rule execution mode must be either FIRST_MATCHED or ALL_MATCHED."
  }
}

# Lambda configuration
variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = can(regex("^python3\\.[89]$", var.lambda_runtime))
    error_message = "Lambda runtime must be python3.8 or python3.9."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for the Lambda function"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for the Lambda function"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Sample data configuration
variable "create_sample_data" {
  description = "Create sample training data for demonstration purposes"
  type        = bool
  default     = true
}

variable "sample_data_file_name" {
  description = "Name of the sample training data file"
  type        = string
  default     = "training-data.csv"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}