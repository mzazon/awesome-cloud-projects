# Variables for Amazon Polly Text-to-Speech Solutions
# This file defines all input variables for the Terraform configuration

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "polly-tts"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket to store audio files (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Name for the Lambda function (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "iam_role_name" {
  description = "Name for the IAM role (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "default_voice_id" {
  description = "Default Amazon Polly voice ID"
  type        = string
  default     = "Joanna"

  validation {
    condition = contains([
      "Joanna", "Matthew", "Ivy", "Kevin", "Kimberly", "Salli", 
      "Joey", "Justin", "Kendra", "Amy", "Brian", "Emma"
    ], var.default_voice_id)
    error_message = "Voice ID must be a valid Amazon Polly neural voice."
  }
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution for audio file delivery"
  type        = bool
  default     = false
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = false
}

variable "s3_storage_class" {
  description = "Default S3 storage class for audio files"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains(["STANDARD", "STANDARD_IA", "ONEZONE_IA", "GLACIER", "DEEP_ARCHIVE"], var.s3_storage_class)
    error_message = "S3 storage class must be one of: STANDARD, STANDARD_IA, ONEZONE_IA, GLACIER, DEEP_ARCHIVE."
  }
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "custom_lexicons" {
  description = "Map of custom lexicon names and their content"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_api_gateway" {
  description = "Enable API Gateway for HTTP access to Lambda function"
  type        = bool
  default     = false
}

variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "v1"
}