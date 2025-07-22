# Input variables for the content moderation infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "content-moderation"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "notification_email" {
  description = "Email address for SNS notifications about content moderation decisions"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "bedrock_model_id" {
  description = "Amazon Bedrock model ID for content analysis"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
  
  validation {
    condition     = can(regex("^anthropic\\.claude", var.bedrock_model_id))
    error_message = "Model ID must be a valid Anthropic Claude model."
  }
}

variable "content_analysis_timeout" {
  description = "Timeout in seconds for content analysis Lambda function"
  type        = number
  default     = 60
  
  validation {
    condition     = var.content_analysis_timeout >= 30 && var.content_analysis_timeout <= 900
    error_message = "Timeout must be between 30 and 900 seconds."
  }
}

variable "content_analysis_memory" {
  description = "Memory allocation in MB for content analysis Lambda function"
  type        = number
  default     = 512
  
  validation {
    condition     = var.content_analysis_memory >= 128 && var.content_analysis_memory <= 10240
    error_message = "Memory must be between 128 and 10240 MB."
  }
}

variable "workflow_timeout" {
  description = "Timeout in seconds for workflow Lambda functions"
  type        = number
  default     = 30
  
  validation {
    condition     = var.workflow_timeout >= 15 && var.workflow_timeout <= 900
    error_message = "Timeout must be between 15 and 900 seconds."
  }
}

variable "workflow_memory" {
  description = "Memory allocation in MB for workflow Lambda functions"
  type        = number
  default     = 256
  
  validation {
    condition     = var.workflow_memory >= 128 && var.workflow_memory <= 10240
    error_message = "Memory must be between 128 and 10240 MB."
  }
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_encryption_enabled" {
  description = "Enable server-side encryption on S3 buckets"
  type        = bool
  default     = true
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention period in days for Lambda functions"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.lambda_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_bedrock_guardrails" {
  description = "Enable Amazon Bedrock Guardrails for enhanced content filtering"
  type        = bool
  default     = true
}

variable "guardrail_content_filters" {
  description = "Content filter configuration for Bedrock Guardrails"
  type = map(object({
    input_strength  = string
    output_strength = string
  }))
  default = {
    SEXUAL = {
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    VIOLENCE = {
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    HATE = {
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    INSULTS = {
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    MISCONDUCT = {
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
  }
  
  validation {
    condition = alltrue([
      for filter in values(var.guardrail_content_filters) : 
      contains(["NONE", "LOW", "MEDIUM", "HIGH"], filter.input_strength) &&
      contains(["NONE", "LOW", "MEDIUM", "HIGH"], filter.output_strength)
    ])
    error_message = "Filter strengths must be NONE, LOW, MEDIUM, or HIGH."
  }
}