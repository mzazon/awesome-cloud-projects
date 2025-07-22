# Variable definitions for the Advanced DynamoDB Streaming with Global Tables recipe
# These variables allow customization of the infrastructure deployment

variable "primary_region" {
  description = "Primary AWS region for the global tables deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for the global tables deployment"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., eu-west-1)."
  }
}

variable "tertiary_region" {
  description = "Tertiary AWS region for the global tables deployment"
  type        = string
  default     = "ap-southeast-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.tertiary_region))
    error_message = "Tertiary region must be a valid AWS region format (e.g., ap-southeast-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "table_base_name" {
  description = "Base name for the DynamoDB table (will be suffixed with random string)"
  type        = string
  default     = "ecommerce-global"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.table_base_name))
    error_message = "Table base name must start with a letter and can contain alphanumeric characters, underscores, and hyphens."
  }
}

variable "kinesis_stream_base_name" {
  description = "Base name for the Kinesis Data Streams (will be suffixed with random string)"
  type        = string
  default     = "ecommerce-events"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.kinesis_stream_base_name))
    error_message = "Kinesis stream base name must start with a letter and can contain alphanumeric characters, underscores, and hyphens."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for each Kinesis Data Stream"
  type        = number
  default     = 3
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 100
    error_message = "Kinesis shard count must be between 1 and 100."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11",
      "nodejs16.x", "nodejs18.x", "nodejs20.x"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported AWS Lambda runtime."
  }
}

variable "stream_batch_size" {
  description = "Batch size for DynamoDB Streams event source mapping"
  type        = number
  default     = 10
  
  validation {
    condition     = var.stream_batch_size >= 1 && var.stream_batch_size <= 1000
    error_message = "Stream batch size must be between 1 and 1000."
  }
}

variable "kinesis_batch_size" {
  description = "Batch size for Kinesis Data Streams event source mapping"
  type        = number
  default     = 100
  
  validation {
    condition     = var.kinesis_batch_size >= 1 && var.kinesis_batch_size <= 10000
    error_message = "Kinesis batch size must be between 1 and 10000."
  }
}

variable "stream_parallelization_factor" {
  description = "Parallelization factor for Kinesis event source mapping"
  type        = number
  default     = 2
  
  validation {
    condition     = var.stream_parallelization_factor >= 1 && var.stream_parallelization_factor <= 10
    error_message = "Stream parallelization factor must be between 1 and 10."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Kinesis Data Streams"
  type        = bool
  default     = true
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB tables"
  type        = bool
  default     = true
}

variable "cloudwatch_dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = "ECommerce-Global-Monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.cloudwatch_dashboard_name))
    error_message = "Dashboard name must start with a letter and can contain alphanumeric characters, underscores, and hyphens."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Random suffix for unique resource naming
variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 12
    error_message = "Random suffix length must be between 4 and 12 characters."
  }
}