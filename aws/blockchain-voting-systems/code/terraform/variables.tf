# General Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
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

variable "project_name" {
  description = "Name of the voting system project"
  type        = string
  default     = "blockchain-voting-system"
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for voting system data (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before S3 objects are deleted"
  type        = number
  default     = 2555 # 7 years for audit compliance
}

# DynamoDB Configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be PROVISIONED or PAY_PER_REQUEST."
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

variable "enable_dynamodb_encryption" {
  description = "Enable DynamoDB encryption at rest"
  type        = bool
  default     = true
}

variable "enable_dynamodb_backup" {
  description = "Enable DynamoDB point-in-time recovery"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
}

# Blockchain Configuration
variable "blockchain_node_instance_type" {
  description = "Instance type for blockchain node"
  type        = string
  default     = "bc.t3.medium"
  
  validation {
    condition = contains([
      "bc.t3.small", "bc.t3.medium", "bc.t3.large", "bc.t3.xlarge",
      "bc.m5.large", "bc.m5.xlarge", "bc.m5.2xlarge", "bc.m5.4xlarge"
    ], var.blockchain_node_instance_type)
    error_message = "Blockchain node instance type must be a valid Amazon Managed Blockchain instance type."
  }
}

variable "blockchain_network_type" {
  description = "Blockchain network type"
  type        = string
  default     = "ETHEREUM"
  
  validation {
    condition     = contains(["ETHEREUM"], var.blockchain_network_type)
    error_message = "Currently only ETHEREUM is supported for blockchain network type."
  }
}

variable "ethereum_network" {
  description = "Ethereum network to connect to"
  type        = string
  default     = "GOERLI"
  
  validation {
    condition     = contains(["GOERLI", "MAINNET"], var.ethereum_network)
    error_message = "Ethereum network must be GOERLI or MAINNET."
  }
}

# Cognito Configuration
variable "cognito_password_policy" {
  description = "Cognito user pool password policy"
  type = object({
    minimum_length                   = number
    require_lowercase                = bool
    require_numbers                  = bool
    require_symbols                  = bool
    require_uppercase                = bool
    temporary_password_validity_days = number
  })
  default = {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
}

variable "cognito_mfa_configuration" {
  description = "Multi-factor authentication configuration"
  type        = string
  default     = "OPTIONAL"
  
  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.cognito_mfa_configuration)
    error_message = "Cognito MFA configuration must be OFF, ON, or OPTIONAL."
  }
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_log_group_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 30
}

variable "enable_cloudwatch_insights" {
  description = "Enable CloudWatch Insights for log analysis"
  type        = bool
  default     = true
}

# Security Configuration
variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "enable_kms_key_rotation" {
  description = "Enable automatic KMS key rotation"
  type        = bool
  default     = true
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for system notifications"
  type        = string
  default     = ""
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for voting events"
  type        = bool
  default     = true
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "v1"
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway access logging"
  type        = bool
  default     = true
}

variable "api_gateway_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 1000
}

variable "api_gateway_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 2000
}

# EventBridge Configuration
variable "enable_eventbridge_archive" {
  description = "Enable EventBridge event archiving"
  type        = bool
  default     = true
}

variable "eventbridge_archive_retention_days" {
  description = "EventBridge archive retention period in days"
  type        = number
  default     = 365
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}