# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"
    ], var.aws_region)
    error_message = "AWS region must be one of the regions where Bedrock is available."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

variable "owner" {
  description = "Owner or team responsible for the infrastructure"
  type        = string
  default     = "platform-team"
}

# Multi-Agent Configuration
variable "project_name" {
  description = "Name of the multi-agent AI project"
  type        = string
  default     = "multi-agent-workflows"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "supervisor_agent_name" {
  description = "Name of the supervisor agent"
  type        = string
  default     = "supervisor-agent"
}

variable "finance_agent_name" {
  description = "Name of the financial analysis agent"
  type        = string
  default     = "finance-agent"
}

variable "support_agent_name" {
  description = "Name of the customer support agent"
  type        = string
  default     = "support-agent"
}

variable "analytics_agent_name" {
  description = "Name of the data analytics agent"
  type        = string
  default     = "analytics-agent"
}

# Bedrock Configuration
variable "foundation_model" {
  description = "Bedrock foundation model for agents"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
  
  validation {
    condition = contains([
      "anthropic.claude-3-sonnet-20240229-v1:0",
      "anthropic.claude-3-haiku-20240307-v1:0",
      "anthropic.claude-v2:1"
    ], var.foundation_model)
    error_message = "Foundation model must be a supported Claude model."
  }
}

variable "agent_session_timeout" {
  description = "Agent session timeout in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.agent_session_timeout >= 600 && var.agent_session_timeout <= 28800
    error_message = "Session timeout must be between 600 and 28800 seconds (10 minutes to 8 hours)."
  }
}

# Lambda Configuration
variable "coordinator_memory_size" {
  description = "Memory allocation for the coordinator Lambda function in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.coordinator_memory_size >= 128 && var.coordinator_memory_size <= 10240
    error_message = "Lambda memory must be between 128 MB and 10,240 MB."
  }
}

variable "coordinator_timeout" {
  description = "Timeout for the coordinator Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.coordinator_timeout >= 1 && var.coordinator_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# DynamoDB Configuration
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

variable "memory_retention_days" {
  description = "Number of days to retain agent memory records"
  type        = number
  default     = 30
  
  validation {
    condition     = var.memory_retention_days >= 1 && var.memory_retention_days <= 365
    error_message = "Memory retention must be between 1 and 365 days."
  }
}

# EventBridge Configuration
variable "enable_eventbridge_encryption" {
  description = "Enable encryption for EventBridge"
  type        = bool
  default     = true
}

variable "event_retention_days" {
  description = "Number of days to retain failed events in DLQ"
  type        = number
  default     = 14
  
  validation {
    condition     = var.event_retention_days >= 1 && var.event_retention_days <= 1209600
    error_message = "Event retention must be between 1 and 1209600 seconds (14 days)."
  }
}

# Monitoring Configuration
variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for observability"
  type        = bool
  default     = true
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring with custom CloudWatch metrics"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

# Security Configuration
variable "enable_resource_encryption" {
  description = "Enable encryption at rest for supported resources"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}