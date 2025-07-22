# Variables for CloudWatch Evidently feature flags infrastructure

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the Evidently project"
  type        = string
  default     = "feature-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for feature evaluation"
  type        = string
  default     = "evidently-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "feature_flag_name" {
  description = "Name of the feature flag to create"
  type        = string
  default     = "new-checkout-flow"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.feature_flag_name))
    error_message = "Feature flag name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "launch_name" {
  description = "Name of the Evidently launch configuration"
  type        = string
  default     = "checkout-gradual-rollout"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.launch_name))
    error_message = "Launch name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "treatment_traffic_percentage" {
  description = "Percentage of traffic to route to the treatment group (new feature)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.treatment_traffic_percentage >= 0 && var.treatment_traffic_percentage <= 100
    error_message = "Traffic percentage must be between 0 and 100."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for the Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12",
      "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python or Node.js version."
  }
}

variable "enable_data_delivery" {
  description = "Enable data delivery to CloudWatch Logs for Evidently evaluations"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}


variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "feature-flags-evidently"
    Environment = "demo"
    Owner       = "terraform"
    Recipe      = "feature-flags-cloudwatch-evidently"
  }
}