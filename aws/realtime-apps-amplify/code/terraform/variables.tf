# Variables for AWS Full-Stack Real-Time Applications with Amplify and AppSync

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = contains(["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1", "ap-northeast-1"], var.aws_region)
    error_message = "AWS region must be one of: us-east-1, us-west-2, eu-west-1, ap-southeast-1, ap-northeast-1."
  }
}

variable "project_name" {
  description = "Name of the project, used as a prefix for resources"
  type        = string
  default     = "realtime-chat-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "appsync_authentication_type" {
  description = "Primary authentication type for AppSync API"
  type        = string
  default     = "AMAZON_COGNITO_USER_POOLS"
  
  validation {
    condition     = contains(["API_KEY", "AWS_IAM", "AMAZON_COGNITO_USER_POOLS", "OPENID_CONNECT"], var.appsync_authentication_type)
    error_message = "Authentication type must be one of: API_KEY, AWS_IAM, AMAZON_COGNITO_USER_POOLS, OPENID_CONNECT."
  }
}

variable "enable_api_key_auth" {
  description = "Enable API key authentication for public access"
  type        = bool
  default     = true
}

variable "api_key_expires_in_days" {
  description = "Number of days until API key expires"
  type        = number
  default     = 365
  
  validation {
    condition     = var.api_key_expires_in_days > 0 && var.api_key_expires_in_days <= 365
    error_message = "API key expiration must be between 1 and 365 days."
  }
}

variable "cognito_user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
  default     = "realtime-chat-users"
}

variable "cognito_user_pool_client_name" {
  description = "Name for the Cognito User Pool Client"
  type        = string
  default     = "realtime-chat-client"
}

variable "enable_cognito_mfa" {
  description = "Enable multi-factor authentication for Cognito users"
  type        = bool
  default     = false
}

variable "cognito_password_policy" {
  description = "Password policy configuration for Cognito User Pool"
  type = object({
    minimum_length                   = number
    require_uppercase                = bool
    require_lowercase                = bool
    require_numbers                  = bool
    require_symbols                  = bool
    temporary_password_validity_days = number
  })
  default = {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity > 0
    error_message = "DynamoDB read capacity must be greater than 0."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity > 0
    error_message = "DynamoDB write capacity must be greater than 0."
  }
}

variable "enable_dynamodb_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB tables"
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"
  
  validation {
    condition     = contains(["nodejs18.x", "nodejs20.x", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be one of: nodejs18.x, nodejs20.x, python3.9, python3.10, python3.11."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions (MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions (seconds)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for all resources"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch logs retention must be a valid value."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions and AppSync"
  type        = bool
  default     = true
}

variable "amplify_app_name" {
  description = "Name for the Amplify application"
  type        = string
  default     = "realtime-chat-frontend"
}

variable "amplify_repository_url" {
  description = "Git repository URL for Amplify application (optional)"
  type        = string
  default     = ""
}

variable "amplify_branch_name" {
  description = "Git branch name for Amplify application"
  type        = string
  default     = "main"
}

variable "amplify_build_spec" {
  description = "Build specification for Amplify application"
  type        = string
  default     = ""
}

variable "enable_amplify_auto_branch_creation" {
  description = "Enable automatic branch creation for Amplify"
  type        = bool
  default     = false
}

variable "amplify_environment_variables" {
  description = "Environment variables for Amplify application"
  type        = map(string)
  default     = {}
}

variable "notification_email" {
  description = "Email address for notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}