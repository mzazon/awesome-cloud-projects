# Variables configuration for Multi-Agent Knowledge Management System
# Provides customizable parameters for enterprise deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1)."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "multi-agent-km"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens, and be <= 20 characters."
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

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for knowledge base documents"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for S3 buckets and DynamoDB"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 1000
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit"
  type        = number
  default     = 500
}

variable "session_ttl_hours" {
  description = "Session TTL in hours for DynamoDB table"
  type        = number
  default     = 24
  
  validation {
    condition     = var.session_ttl_hours >= 1 && var.session_ttl_hours <= 168
    error_message = "Session TTL must be between 1 and 168 hours (1 week)."
  }
}

variable "q_business_app_name" {
  description = "Name for the Q Business application"
  type        = string
  default     = "Enterprise Knowledge Management System"
}

variable "q_business_app_description" {
  description = "Description for the Q Business application"
  type        = string
  default     = "Multi-agent knowledge management with specialized domain expertise"
}

variable "knowledge_domains" {
  description = "Configuration for knowledge domains and their S3 bucket settings"
  type = map(object({
    display_name = string
    description  = string
    metadata_prefix = string
  }))
  default = {
    finance = {
      display_name = "Finance Knowledge Base"
      description  = "Financial policies, budget guidelines, and approval processes"
      metadata_prefix = "finance/"
    }
    hr = {
      display_name = "HR Knowledge Base"
      description  = "Human resources policies, employee procedures, and benefits"
      metadata_prefix = "hr/"
    }
    technical = {
      display_name = "Technical Knowledge Base"
      description  = "Technical documentation, development standards, and system procedures"
      metadata_prefix = "technical/"
    }
  }
}

variable "agent_configurations" {
  description = "Configuration for specialized agents"
  type = map(object({
    display_name = string
    description  = string
    memory_size  = number
    timeout      = number
  }))
  default = {
    supervisor = {
      display_name = "Supervisor Agent"
      description  = "Coordinates specialized agents for knowledge retrieval"
      memory_size  = 512
      timeout      = 60
    }
    finance = {
      display_name = "Finance Agent"
      description  = "Specialist for financial policies and budget queries"
      memory_size  = 256
      timeout      = 30
    }
    hr = {
      display_name = "HR Agent"
      description  = "Specialist for employee and policy queries"
      memory_size  = 256
      timeout      = 30
    }
    technical = {
      display_name = "Technical Agent"
      description  = "Specialist for engineering and system queries"
      memory_size  = 256
      timeout      = 30
    }
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS configuration"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "List of allowed headers for CORS configuration"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}