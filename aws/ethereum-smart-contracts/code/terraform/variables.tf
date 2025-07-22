# Core Configuration Variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-z0-9]+$", var.environment))
    error_message = "Environment must contain only lowercase letters and numbers."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "ethereum-blockchain"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Managed Blockchain Configuration
variable "ethereum_network" {
  description = "Ethereum network to connect to (mainnet or testnet)"
  type        = string
  default     = "n-ethereum-mainnet"
  
  validation {
    condition = contains(["n-ethereum-mainnet", "n-ethereum-goerli", "n-ethereum-sepolia"], var.ethereum_network)
    error_message = "Ethereum network must be mainnet, goerli, or sepolia."
  }
}

variable "blockchain_node_instance_type" {
  description = "EC2 instance type for the Ethereum node"
  type        = string
  default     = "bc.t3.xlarge"
  
  validation {
    condition = can(regex("^bc\\.[a-z0-9]+\\.[a-z0-9]+$", var.blockchain_node_instance_type))
    error_message = "Instance type must be a valid blockchain instance type (e.g., bc.t3.xlarge)."
  }
}

variable "blockchain_node_availability_zone" {
  description = "Availability zone for the blockchain node (will be appended with 'a' if not specified)"
  type        = string
  default     = ""
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime for the contract manager function"
  type        = string
  default     = "nodejs18.x"
  
  validation {
    condition = contains(["nodejs18.x", "nodejs20.x"], var.lambda_runtime)
    error_message = "Lambda runtime must be nodejs18.x or nodejs20.x."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "prod"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters."
  }
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 100
  
  validation {
    condition = var.api_throttle_rate_limit >= 1 && var.api_throttle_rate_limit <= 10000
    error_message = "API throttle rate limit must be between 1 and 10000."
  }
}

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 200
  
  validation {
    condition = var.api_throttle_burst_limit >= 1 && var.api_throttle_burst_limit <= 5000
    error_message = "API throttle burst limit must be between 1 and 5000."
  }
}

# S3 Configuration
variable "s3_bucket_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "Enable server-side encryption for S3 bucket"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard creation"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

# Contract Configuration
variable "initial_token_supply" {
  description = "Initial supply for the sample token contract"
  type        = number
  default     = 1000000
  
  validation {
    condition = var.initial_token_supply > 0
    error_message = "Initial token supply must be greater than 0."
  }
}

# Security Configuration
variable "enable_api_key_required" {
  description = "Require API key for API Gateway access"
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "CORS allowed origins for API Gateway"
  type        = list(string)
  default     = ["*"]
}

variable "cors_allowed_methods" {
  description = "CORS allowed methods for API Gateway"
  type        = list(string)
  default     = ["GET", "POST", "OPTIONS"]
}

variable "cors_allowed_headers" {
  description = "CORS allowed headers for API Gateway"
  type        = list(string)
  default     = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}