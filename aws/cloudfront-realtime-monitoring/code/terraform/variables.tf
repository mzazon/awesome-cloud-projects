# CloudFront Real-time Monitoring and Analytics - Terraform Variables
# This file defines all input variables for the infrastructure configuration

# General Configuration
variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "cf-monitoring"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
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

variable "owner" {
  description = "Owner of the resources (email or team name)"
  type        = string
  default     = "devops-team"
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# Kinesis Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for the primary Kinesis stream"
  type        = number
  default     = 2
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 10
    error_message = "Kinesis shard count must be between 1 and 10."
  }
}

variable "kinesis_processed_shard_count" {
  description = "Number of shards for the processed Kinesis stream"
  type        = number
  default     = 1
  
  validation {
    condition     = var.kinesis_processed_shard_count >= 1 && var.kinesis_processed_shard_count <= 5
    error_message = "Processed Kinesis shard count must be between 1 and 5."
  }
}

variable "kinesis_retention_period" {
  description = "Kinesis stream retention period in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Kinesis retention period must be between 24 hours and 8760 hours (1 year)."
  }
}

# OpenSearch Configuration
variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"
  
  validation {
    condition = contains([
      "t3.small.search", "t3.medium.search", "t3.large.search",
      "r6g.large.search", "r6g.xlarge.search", "r6g.2xlarge.search",
      "m6g.large.search", "m6g.xlarge.search", "m6g.2xlarge.search"
    ], var.opensearch_instance_type)
    error_message = "OpenSearch instance type must be a valid search instance type."
  }
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 1
  
  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 10
    error_message = "OpenSearch instance count must be between 1 and 10."
  }
}

variable "opensearch_ebs_volume_size" {
  description = "EBS volume size for OpenSearch instances (GB)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.opensearch_ebs_volume_size >= 10 && var.opensearch_ebs_volume_size <= 3584
    error_message = "OpenSearch EBS volume size must be between 10 GB and 3584 GB."
  }
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version"
  type        = string
  default     = "OpenSearch_2.3"
  
  validation {
    condition = contains([
      "OpenSearch_1.3", "OpenSearch_2.3", "OpenSearch_2.5", "OpenSearch_2.7"
    ], var.opensearch_engine_version)
    error_message = "OpenSearch engine version must be a supported version."
  }
}

variable "opensearch_access_ip_ranges" {
  description = "IP ranges allowed to access OpenSearch (CIDR notation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.opensearch_access_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "nodejs18.x"
  
  validation {
    condition = contains([
      "nodejs16.x", "nodejs18.x", "nodejs20.x", "python3.9", "python3.10", "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported runtime version."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size (MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
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

variable "lambda_maximum_batching_window" {
  description = "Lambda maximum batching window in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_maximum_batching_window >= 0 && var.lambda_maximum_batching_window <= 300
    error_message = "Lambda maximum batching window must be between 0 and 300 seconds."
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

variable "dynamodb_ttl_days" {
  description = "DynamoDB TTL in days for automatic record deletion"
  type        = number
  default     = 7
  
  validation {
    condition     = var.dynamodb_ttl_days >= 1 && var.dynamodb_ttl_days <= 365
    error_message = "DynamoDB TTL must be between 1 and 365 days."
  }
}

# Kinesis Firehose Configuration
variable "firehose_buffer_size" {
  description = "Kinesis Firehose buffer size (MB)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 128
    error_message = "Firehose buffer size must be between 1 MB and 128 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Kinesis Firehose buffer interval (seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Firehose buffer interval must be between 60 and 900 seconds."
  }
}

variable "firehose_compression_format" {
  description = "Kinesis Firehose compression format"
  type        = string
  default     = "GZIP"
  
  validation {
    condition     = contains(["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"], var.firehose_compression_format)
    error_message = "Firehose compression format must be a valid compression type."
  }
}

# CloudFront Configuration
variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "cloudfront_enable_ipv6" {
  description = "Enable IPv6 for CloudFront distribution"
  type        = bool
  default     = true
}

variable "cloudfront_default_root_object" {
  description = "Default root object for CloudFront distribution"
  type        = string
  default     = "index.html"
}

variable "cloudfront_minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version for CloudFront"
  type        = string
  default     = "TLSv1.2_2021"
  
  validation {
    condition = contains([
      "SSLv3", "TLSv1", "TLSv1_2016", "TLSv1.1_2016", "TLSv1.2_2018", "TLSv1.2_2019", "TLSv1.2_2021"
    ], var.cloudfront_minimum_protocol_version)
    error_message = "CloudFront minimum protocol version must be a valid SSL/TLS version."
  }
}

# S3 Configuration
variable "s3_enable_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning S3 objects to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_days >= 1 && var.s3_lifecycle_transition_days <= 365
    error_message = "S3 lifecycle transition days must be between 1 and 365."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before expiring S3 objects"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 1 && var.s3_lifecycle_expiration_days <= 3650
    error_message = "S3 lifecycle expiration days must be between 1 and 3650."
  }
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_dashboard" {
  description = "Enable CloudWatch dashboard creation"
  type        = bool
  default     = true
}

# Sample Content Configuration
variable "create_sample_content" {
  description = "Create sample content for testing CloudFront distribution"
  type        = bool
  default     = true
}

# Cost Management
variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for billing"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_s3_public_access_block" {
  description = "Enable S3 public access block for all buckets"
  type        = bool
  default     = true
}

variable "force_ssl_requests_only" {
  description = "Force SSL-only requests to S3 buckets"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for applicable resources"
  type        = bool
  default     = true
}

variable "enable_real_time_logs" {
  description = "Enable CloudFront real-time logs"
  type        = bool
  default     = true
}