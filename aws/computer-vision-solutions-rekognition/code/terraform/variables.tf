# Input variables for the Computer Vision Solutions with Amazon Rekognition
# These variables allow customization of the deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1", "ap-southeast-1",
      "ap-southeast-2", "ap-northeast-1", "ap-northeast-2"
    ], var.aws_region)
    error_message = "The AWS region must be a valid region where Rekognition is available."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 10
    error_message = "Environment name must be between 1 and 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "rekognition-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "face_collection_name" {
  description = "Name for the Rekognition face collection"
  type        = string
  default     = ""
  
  validation {
    condition     = var.face_collection_name == "" || can(regex("^[a-zA-Z0-9_.-]+$", var.face_collection_name))
    error_message = "Face collection name must contain only alphanumeric characters, underscores, periods, and hyphens."
  }
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (bucket name will be prefix-random-suffix)"
  type        = string
  default     = "rekognition-computer-vision"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle policies on S3 bucket to manage costs"
  type        = bool
  default     = true
}

variable "s3_transition_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_days >= 1 && var.s3_transition_days <= 365
    error_message = "Transition days must be between 1 and 365."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.11"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
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

variable "enable_api_gateway" {
  description = "Create API Gateway for Lambda function endpoints"
  type        = bool
  default     = true
}

variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_dynamodb" {
  description = "Create DynamoDB table for storing analysis results"
  type        = bool
  default     = true
}

variable "dynamodb_billing_mode" {
  description = "Billing mode for DynamoDB table (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for S3 bucket"
  type        = bool
  default     = false
}

variable "replication_destination_region" {
  description = "Destination region for S3 cross-region replication"
  type        = string
  default     = "us-west-2"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "Computer Vision Solutions"
    Component = "Rekognition Demo"
    Owner     = "DevOps Team"
  }
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for analysis results"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for SNS notifications (required if enable_sns_notifications is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "enable_vpc_endpoint" {
  description = "Create VPC endpoint for S3 to improve security and reduce data transfer costs"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for creating VPC endpoint (required if enable_vpc_endpoint is true)"
  type        = string
  default     = ""
}

variable "route_table_ids" {
  description = "Route table IDs for VPC endpoint (required if enable_vpc_endpoint is true)"
  type        = list(string)
  default     = []
}