# Input variables for the conversational AI application

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
  default     = "conversational-ai"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "claude_model_id" {
  description = "Claude model ID to use for Bedrock"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
  
  validation {
    condition     = can(regex("^anthropic\\.claude-.*", var.claude_model_id))
    error_message = "Claude model ID must be a valid Anthropic Claude model identifier."
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

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240 && var.lambda_memory_size % 64 == 0
    error_message = "Lambda memory size must be between 128 and 10240 MB and must be a multiple of 64."
  }
}

variable "max_tokens" {
  description = "Maximum tokens for Claude responses"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.max_tokens >= 1 && var.max_tokens <= 4096
    error_message = "Max tokens must be between 1 and 4096."
  }
}

variable "temperature" {
  description = "Temperature setting for Claude model (0.0 to 1.0)"
  type        = number
  default     = 0.7
  
  validation {
    condition     = var.temperature >= 0.0 && var.temperature <= 1.0
    error_message = "Temperature must be between 0.0 and 1.0."
  }
}

variable "api_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_stage_name))
    error_message = "API stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "conversation_history_limit" {
  description = "Maximum number of conversation turns to retain for context"
  type        = number
  default     = 10
  
  validation {
    condition     = var.conversation_history_limit >= 1 && var.conversation_history_limit <= 50
    error_message = "Conversation history limit must be between 1 and 50."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = true
}

variable "enable_cors" {
  description = "Enable CORS for API Gateway"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["POST", "OPTIONS", "GET"]
}

variable "cors_allowed_headers" {
  description = "List of allowed headers for CORS"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
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

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}