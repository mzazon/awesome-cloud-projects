# Variables for CloudFront Cache Invalidation Strategies
# This file defines all input variables for the infrastructure deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-west-2' or similar."
  }
}

variable "project_name" {
  description = "Name of the project - used for resource naming and tagging"
  type        = string
  default     = "cf-invalidation"
  
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

variable "enable_event_notifications" {
  description = "Enable S3 event notifications to EventBridge"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "sqs_visibility_timeout" {
  description = "Visibility timeout for SQS queue in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.sqs_visibility_timeout >= 0 && var.sqs_visibility_timeout <= 43200
    error_message = "SQS visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "sqs_message_retention_period" {
  description = "Message retention period for SQS queue in seconds"
  type        = number
  default     = 1209600 # 14 days
  
  validation {
    condition     = var.sqs_message_retention_period >= 60 && var.sqs_message_retention_period <= 1209600
    error_message = "SQS message retention period must be between 60 and 1209600 seconds."
  }
}

variable "sqs_batch_size" {
  description = "Batch size for SQS event source mapping"
  type        = number
  default     = 5
  
  validation {
    condition     = var.sqs_batch_size >= 1 && var.sqs_batch_size <= 10
    error_message = "SQS batch size must be between 1 and 10."
  }
}

variable "sqs_maximum_batching_window" {
  description = "Maximum batching window for SQS event source mapping in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.sqs_maximum_batching_window >= 0 && var.sqs_maximum_batching_window <= 300
    error_message = "SQS maximum batching window must be between 0 and 300 seconds."
  }
}

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
  description = "TTL for DynamoDB records in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.dynamodb_ttl_days >= 1 && var.dynamodb_ttl_days <= 365
    error_message = "DynamoDB TTL must be between 1 and 365 days."
  }
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "cloudfront_http_version" {
  description = "CloudFront HTTP version"
  type        = string
  default     = "http2"
  
  validation {
    condition     = contains(["http1.1", "http2"], var.cloudfront_http_version)
    error_message = "CloudFront HTTP version must be either http1.1 or http2."
  }
}

variable "cloudfront_minimum_protocol_version" {
  description = "CloudFront minimum protocol version"
  type        = string
  default     = "TLSv1.2_2021"
  
  validation {
    condition = contains([
      "SSLv3",
      "TLSv1",
      "TLSv1_2016",
      "TLSv1.1_2016",
      "TLSv1.2_2018",
      "TLSv1.2_2019",
      "TLSv1.2_2021"
    ], var.cloudfront_minimum_protocol_version)
    error_message = "Invalid CloudFront minimum protocol version."
  }
}

variable "create_sample_content" {
  description = "Whether to create sample content in S3 bucket"
  type        = bool
  default     = true
}

variable "enable_monitoring_dashboard" {
  description = "Whether to create CloudWatch monitoring dashboard"
  type        = bool
  default     = true
}

variable "sns_notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_notification_email))
    error_message = "SNS notification email must be a valid email address or empty string."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda function"
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_in_days)
    error_message = "Log retention must be one of the allowed values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}