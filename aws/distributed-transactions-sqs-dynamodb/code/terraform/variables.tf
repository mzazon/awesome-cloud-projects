# Variables for Distributed Transaction Processing Infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "distributed-tx"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "sqs_visibility_timeout" {
  description = "Visibility timeout for SQS queues in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.sqs_visibility_timeout > 0 && var.sqs_visibility_timeout <= 43200
    error_message = "SQS visibility timeout must be between 1 and 43200 seconds."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = can(regex("^(PAY_PER_REQUEST|PROVISIONED)$", var.dynamodb_billing_mode))
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "api_gateway_stage" {
  description = "API Gateway deployment stage"
  type        = string
  default     = "prod"
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "sample_inventory_data" {
  description = "Sample inventory data to populate the inventory table"
  type = list(object({
    product_id         = string
    product_name       = string
    quantity_available = number
    price             = number
  }))
  default = [
    {
      product_id         = "PROD-001"
      product_name       = "Premium Laptop"
      quantity_available = 50
      price             = 1299.99
    },
    {
      product_id         = "PROD-002"
      product_name       = "Wireless Headphones"
      quantity_available = 100
      price             = 199.99
    },
    {
      product_id         = "PROD-003"
      product_name       = "Smartphone"
      quantity_available = 25
      price             = 799.99
    }
  ]
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold for CloudWatch alarms"
  type        = number
  default     = 5
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
}