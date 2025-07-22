# General Configuration
variable "aws_region" {
  description = "AWS region for all resources"
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "central-logging"
}

# OpenSearch Configuration
variable "opensearch_version" {
  description = "OpenSearch version"
  type        = string
  default     = "OpenSearch_2.9"
}

variable "opensearch_instance_type" {
  description = "Instance type for OpenSearch nodes"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch data instances"
  type        = number
  default     = 3
  
  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 20
    error_message = "OpenSearch instance count must be between 1 and 20."
  }
}

variable "opensearch_master_instance_type" {
  description = "Instance type for OpenSearch master nodes"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_master_instance_count" {
  description = "Number of OpenSearch master instances"
  type        = number
  default     = 3
  
  validation {
    condition     = var.opensearch_master_instance_count >= 3 && var.opensearch_master_instance_count <= 5
    error_message = "OpenSearch master instance count must be 3 or 5 for production."
  }
}

variable "opensearch_ebs_volume_size" {
  description = "EBS volume size for OpenSearch nodes (GB)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.opensearch_ebs_volume_size >= 10 && var.opensearch_ebs_volume_size <= 3584
    error_message = "EBS volume size must be between 10 and 3584 GB."
  }
}

variable "opensearch_ebs_volume_type" {
  description = "EBS volume type for OpenSearch nodes"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.opensearch_ebs_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2."
  }
}

# Kinesis Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis Data Stream"
  type        = number
  default     = 2
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 500
    error_message = "Kinesis shard count must be between 1 and 500."
  }
}

variable "kinesis_retention_period" {
  description = "Kinesis stream retention period in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Kinesis retention period must be between 24 and 8760 hours."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
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

variable "lambda_batch_size" {
  description = "Lambda event source mapping batch size"
  type        = number
  default     = 100
  
  validation {
    condition     = var.lambda_batch_size >= 1 && var.lambda_batch_size <= 10000
    error_message = "Lambda batch size must be between 1 and 10000."
  }
}

# Firehose Configuration
variable "firehose_buffer_size" {
  description = "Firehose buffer size in MB"
  type        = number
  default     = 5
  
  validation {
    condition     = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 128
    error_message = "Firehose buffer size must be between 1 and 128 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Firehose buffer interval in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Firehose buffer interval must be between 60 and 900 seconds."
  }
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access OpenSearch"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for OpenSearch"
  type        = bool
  default     = true
}

variable "enable_node_to_node_encryption" {
  description = "Enable node-to-node encryption for OpenSearch"
  type        = bool
  default     = true
}

variable "enforce_https" {
  description = "Enforce HTTPS for OpenSearch domain"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for OpenSearch"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# Optional Configuration
variable "create_test_log_group" {
  description = "Create a test log group for validation"
  type        = bool
  default     = true
}

variable "enable_multi_az" {
  description = "Enable multi-AZ deployment for OpenSearch"
  type        = bool
  default     = true
}

variable "availability_zone_count" {
  description = "Number of availability zones for OpenSearch"
  type        = number
  default     = 3
  
  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 3
    error_message = "Availability zone count must be 2 or 3."
  }
}