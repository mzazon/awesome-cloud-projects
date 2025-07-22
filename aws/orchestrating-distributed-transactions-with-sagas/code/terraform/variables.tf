# variables.tf - Input variables for the saga patterns infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., demo, prod, staging)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "saga-patterns"
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 10 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 10 and 900 seconds."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "step_functions_logging_level" {
  description = "Step Functions logging level"
  type        = string
  default     = "ALL"
  
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_functions_logging_level)
    error_message = "Step Functions logging level must be ALL, ERROR, FATAL, or OFF."
  }
}

variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "payment_failure_rate" {
  description = "Simulated payment failure rate (0.0 to 1.0)"
  type        = number
  default     = 0.2
  
  validation {
    condition     = var.payment_failure_rate >= 0.0 && var.payment_failure_rate <= 1.0
    error_message = "Payment failure rate must be between 0.0 and 1.0."
  }
}

variable "initial_inventory_data" {
  description = "Initial inventory data for DynamoDB"
  type = list(object({
    product_id = string
    quantity   = number
    price      = number
  }))
  default = [
    {
      product_id = "laptop-001"
      quantity   = 10
      price      = 999.99
    },
    {
      product_id = "phone-002"
      quantity   = 25
      price      = 599.99
    }
  ]
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway access logging"
  type        = bool
  default     = true
}

variable "enable_x_ray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}