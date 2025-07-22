# ==============================================================================
# VARIABLES - Customer Service Chatbots with Amazon Lex
# ==============================================================================

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "CustomerServiceBot"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# ==============================================================================
# BOT CONFIGURATION
# ==============================================================================

variable "bot_name" {
  description = "Name of the Amazon Lex bot"
  type        = string
  default     = "CustomerServiceBot"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.bot_name))
    error_message = "Bot name must start with a letter and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "bot_description" {
  description = "Description of the Amazon Lex bot"
  type        = string
  default     = "Customer service chatbot for handling common inquiries"
}

variable "bot_idle_session_ttl" {
  description = "Idle session timeout in seconds"
  type        = number
  default     = 600
  
  validation {
    condition     = var.bot_idle_session_ttl >= 60 && var.bot_idle_session_ttl <= 86400
    error_message = "Idle session TTL must be between 60 and 86400 seconds."
  }
}

variable "nlu_confidence_threshold" {
  description = "NLU intent confidence threshold (0.0 to 1.0)"
  type        = number
  default     = 0.40
  
  validation {
    condition     = var.nlu_confidence_threshold >= 0.0 && var.nlu_confidence_threshold <= 1.0
    error_message = "NLU confidence threshold must be between 0.0 and 1.0."
  }
}

variable "voice_id" {
  description = "Amazon Polly voice ID for bot responses"
  type        = string
  default     = "Joanna"
  
  validation {
    condition = contains([
      "Joanna", "Matthew", "Ivy", "Justin", "Kendra", "Kimberly", "Salli",
      "Joey", "Nicole", "Russell", "Amy", "Brian", "Emma", "Aditi", "Raveena"
    ], var.voice_id)
    error_message = "Voice ID must be a valid Amazon Polly voice."
  }
}

# ==============================================================================
# LAMBDA CONFIGURATION
# ==============================================================================

variable "lambda_function_name" {
  description = "Name of the Lambda fulfillment function"
  type        = string
  default     = "lex-fulfillment"
}

variable "lambda_runtime" {
  description = "Lambda runtime environment"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# ==============================================================================
# DYNAMODB CONFIGURATION
# ==============================================================================

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB customer data table"
  type        = string
  default     = "customer-data"
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
  description = "DynamoDB read capacity units (only used with PROVISIONED billing)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used with PROVISIONED billing)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable DynamoDB point-in-time recovery"
  type        = bool
  default     = true
}

# ==============================================================================
# SAMPLE DATA CONFIGURATION
# ==============================================================================

variable "create_sample_data" {
  description = "Whether to create sample customer data in DynamoDB"
  type        = bool
  default     = true
}

variable "sample_customers" {
  description = "Sample customer data to populate DynamoDB table"
  type = list(object({
    customer_id        = string
    name              = string
    email             = string
    last_order_id     = string
    last_order_status = string
    account_balance   = number
  }))
  default = [
    {
      customer_id        = "12345"
      name              = "John Smith"
      email             = "john.smith@example.com"
      last_order_id     = "ORD-789"
      last_order_status = "Shipped"
      account_balance   = 156.78
    },
    {
      customer_id        = "67890"
      name              = "Jane Doe"
      email             = "jane.doe@example.com"
      last_order_id     = "ORD-456"
      last_order_status = "Processing"
      account_balance   = 89.23
    }
  ]
}

# ==============================================================================
# INTENT CONFIGURATION
# ==============================================================================

variable "max_slot_retries" {
  description = "Maximum number of retries for slot elicitation"
  type        = number
  default     = 2
  
  validation {
    condition     = var.max_slot_retries >= 1 && var.max_slot_retries <= 5
    error_message = "Max slot retries must be between 1 and 5."
  }
}

# ==============================================================================
# TAGS
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}