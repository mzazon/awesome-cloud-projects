# ================================================================
# Variables for Customer Support Agent Infrastructure
# Recipe: Persistent Customer Support Agent with Bedrock AgentCore Memory
# ================================================================

# ================================================================
# GENERAL CONFIGURATION
# ================================================================

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default = {
    Project     = "CustomerSupportAgent"
    Environment = "development"
    Recipe      = "persistent-customer-support-agentcore-memory"
    ManagedBy   = "Terraform"
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-west-2", "eu-west-1", "eu-central-1",
      "ap-southeast-1", "ap-northeast-1"
    ], var.aws_region)
    error_message = "The aws_region must be a valid AWS region that supports Bedrock AgentCore."
  }
}

# ================================================================
# BEDROCK AGENTCORE MEMORY CONFIGURATION
# ================================================================

variable "memory_name_prefix" {
  description = "Prefix for the AgentCore Memory name"
  type        = string
  default     = "customer-support-memory"
  
  validation {
    condition     = length(var.memory_name_prefix) <= 50
    error_message = "Memory name prefix must be 50 characters or less."
  }
}

variable "memory_event_expiry_duration" {
  description = "Duration after which events expire from memory (ISO 8601 format)"
  type        = string
  default     = "P30D"
  
  validation {
    condition     = can(regex("^P\\d+[DWM]$", var.memory_event_expiry_duration))
    error_message = "Memory event expiry duration must be in ISO 8601 format (e.g., P30D, P4W, P6M)."
  }
}

variable "enable_memory_summarization" {
  description = "Enable summarization strategy for AgentCore Memory"
  type        = bool
  default     = true
}

variable "enable_semantic_memory" {
  description = "Enable semantic memory strategy for AgentCore Memory"
  type        = bool
  default     = true
}

variable "enable_user_preferences" {
  description = "Enable user preferences strategy for AgentCore Memory"
  type        = bool
  default     = true
}

variable "enable_custom_extraction" {
  description = "Enable custom extraction strategy for AgentCore Memory"
  type        = bool
  default     = true
}

variable "custom_extraction_prompt" {
  description = "Custom prompt for memory extraction strategy"
  type        = string
  default     = "Extract the following from customer support conversations: 1) Customer preferences and requirements, 2) Technical issues and their resolutions, 3) Product interests and purchasing intent, 4) Satisfaction levels and feedback. Focus on actionable insights that improve future support interactions."
}

# ================================================================
# BEDROCK MODEL CONFIGURATION
# ================================================================

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID for generating responses"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
  
  validation {
    condition = contains([
      "anthropic.claude-3-haiku-20240307-v1:0",
      "anthropic.claude-3-sonnet-20240229-v1:0",
      "anthropic.claude-v2:1",
      "amazon.titan-text-express-v1",
      "ai21.j2-ultra-v1",
      "cohere.command-text-v14"
    ], var.bedrock_model_id)
    error_message = "The bedrock_model_id must be a valid foundation model ID available in Amazon Bedrock."
  }
}

variable "bedrock_max_tokens" {
  description = "Maximum number of tokens for Bedrock model responses"
  type        = number
  default     = 500
  
  validation {
    condition     = var.bedrock_max_tokens >= 1 && var.bedrock_max_tokens <= 4096
    error_message = "Bedrock max tokens must be between 1 and 4096."
  }
}

# ================================================================
# DYNAMODB CONFIGURATION
# ================================================================

variable "table_name_prefix" {
  description = "Prefix for the DynamoDB table name"
  type        = string
  default     = "customer-data"
  
  validation {
    condition     = length(var.table_name_prefix) <= 50
    error_message = "Table name prefix must be 50 characters or less."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PROVISIONED"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40000."
  }
}

variable "enable_dynamodb_encryption" {
  description = "Enable server-side encryption for DynamoDB table"
  type        = bool
  default     = true
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

# ================================================================
# LAMBDA CONFIGURATION
# ================================================================

variable "lambda_function_name_prefix" {
  description = "Prefix for the Lambda function name"
  type        = string
  default     = "support-agent"
  
  validation {
    condition     = length(var.lambda_function_name_prefix) <= 50
    error_message = "Lambda function name prefix must be 50 characters or less."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda function logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.lambda_log_retention_days)
    error_message = "Lambda log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_lambda_dlq" {
  description = "Enable dead letter queue for Lambda function"
  type        = bool
  default     = true
}

variable "lambda_reserved_concurrency" {
  description = "Lambda function reserved concurrency limit (null for no limit)"
  type        = number
  default     = null
  
  validation {
    condition     = var.lambda_reserved_concurrency == null || (var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000)
    error_message = "Lambda reserved concurrency must be null or between 0 and 1000."
  }
}

# ================================================================
# API GATEWAY CONFIGURATION
# ================================================================

variable "api_name_prefix" {
  description = "Prefix for the API Gateway name"
  type        = string
  default     = "support-api"
  
  validation {
    condition     = length(var.api_name_prefix) <= 50
    error_message = "API name prefix must be 50 characters or less."
  }
}

variable "api_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
  
  validation {
    condition     = length(var.api_stage_name) <= 64 && can(regex("^[a-zA-Z0-9\\-_]+$", var.api_stage_name))
    error_message = "API stage name must be 64 characters or less and contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "api_log_retention_days" {
  description = "Number of days to retain API Gateway access logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.api_log_retention_days)
    error_message = "API log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_api_caching" {
  description = "Enable caching for API Gateway"
  type        = bool
  default     = false
}

variable "api_cache_cluster_size" {
  description = "API Gateway cache cluster size (only used when caching is enabled)"
  type        = string
  default     = "0.5"
  
  validation {
    condition = contains([
      "0.5", "1.6", "6.1", "13.5", "28.4", "58.2", "118", "237"
    ], var.api_cache_cluster_size)
    error_message = "API cache cluster size must be a valid value."
  }
}

variable "enable_api_throttling" {
  description = "Enable throttling for API Gateway"
  type        = bool
  default     = true
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.api_throttle_rate_limit >= 1
    error_message = "API throttle rate limit must be at least 1 request per second."
  }
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.api_throttle_burst_limit >= var.api_throttle_rate_limit
    error_message = "API throttle burst limit must be greater than or equal to rate limit."
  }
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
  default     = ["POST", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "List of allowed headers for CORS"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

# ================================================================
# MONITORING AND ALERTING
# ================================================================

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "alarm_notification_topic" {
  description = "SNS topic ARN for alarm notifications (leave empty to disable notifications)"
  type        = string
  default     = ""
}

variable "lambda_error_threshold" {
  description = "Threshold for Lambda error alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_error_threshold >= 1
    error_message = "Lambda error threshold must be at least 1."
  }
}

variable "api_4xx_error_threshold" {
  description = "Threshold for API Gateway 4XX error alarm"
  type        = number
  default     = 10
  
  validation {
    condition     = var.api_4xx_error_threshold >= 1
    error_message = "API 4XX error threshold must be at least 1."
  }
}

variable "api_5xx_error_threshold" {
  description = "Threshold for API Gateway 5XX error alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.api_5xx_error_threshold >= 1
    error_message = "API 5XX error threshold must be at least 1."
  }
}

variable "lambda_duration_threshold" {
  description = "Threshold for Lambda duration alarm in milliseconds"
  type        = number
  default     = 25000
  
  validation {
    condition     = var.lambda_duration_threshold >= 1000
    error_message = "Lambda duration threshold must be at least 1000 milliseconds."
  }
}

# ================================================================
# SAMPLE DATA CONFIGURATION
# ================================================================

variable "create_sample_data" {
  description = "Create sample customer data in DynamoDB"
  type        = bool
  default     = true
}

variable "sample_customers" {
  description = "List of sample customer data to create"
  type = list(object({
    customer_id       = string
    name             = string
    email            = string
    preferred_channel = string
    product_interests = list(string)
    support_tier     = string
  }))
  default = [
    {
      customer_id       = "customer-001"
      name             = "Sarah Johnson"
      email            = "sarah.johnson@example.com"
      preferred_channel = "chat"
      product_interests = ["enterprise-software", "analytics"]
      support_tier     = "premium"
    },
    {
      customer_id       = "customer-002"
      name             = "Michael Chen"
      email            = "michael.chen@example.com"
      preferred_channel = "email"
      product_interests = ["mobile-apps", "integration"]
      support_tier     = "standard"
    }
  ]
}

# ================================================================
# SECURITY CONFIGURATION
# ================================================================

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services (requires VPC configuration)"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for VPC endpoints (required if enable_vpc_endpoints is true)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC endpoints (required if enable_vpc_endpoints is true)"
  type        = list(string)
  default     = []
}

variable "enable_waf" {
  description = "Enable AWS WAF for API Gateway"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF rule (requests per 5-minute period)"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.waf_rate_limit >= 100
    error_message = "WAF rate limit must be at least 100 requests per 5-minute period."
  }
}

variable "enable_api_key_required" {
  description = "Require API key for API Gateway requests"
  type        = bool
  default     = false
}

variable "api_key_usage_plan_quota_limit" {
  description = "API key usage plan quota limit per period"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.api_key_usage_plan_quota_limit >= 1
    error_message = "API key usage plan quota limit must be at least 1."
  }
}

variable "api_key_usage_plan_quota_period" {
  description = "API key usage plan quota period (DAY, WEEK, or MONTH)"
  type        = string
  default     = "DAY"
  
  validation {
    condition     = contains(["DAY", "WEEK", "MONTH"], var.api_key_usage_plan_quota_period)
    error_message = "API key usage plan quota period must be DAY, WEEK, or MONTH."
  }
}

# ================================================================
# COST OPTIMIZATION
# ================================================================

variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for all resources"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "CustomerSupport"
}

variable "budget_limit" {
  description = "Monthly budget limit in USD for cost monitoring"
  type        = number
  default     = 100
  
  validation {
    condition     = var.budget_limit >= 1
    error_message = "Budget limit must be at least $1."
  }
}

variable "enable_budget_alerts" {
  description = "Enable budget alerts for cost monitoring"
  type        = bool
  default     = false
}

variable "budget_alert_email" {
  description = "Email address for budget alert notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.budget_alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.budget_alert_email))
    error_message = "Budget alert email must be a valid email address or empty string."
  }
}