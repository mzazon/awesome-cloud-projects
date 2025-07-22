# Input Variables for Video Processing Workflow
# Defines all configurable parameters for the infrastructure deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "video-processing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_source_bucket_name" {
  description = "Name of the S3 bucket for source video files (will be made unique with random suffix)"
  type        = string
  default     = "video-source"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_source_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_output_bucket_name" {
  description = "Name of the S3 bucket for processed video files (will be made unique with random suffix)"
  type        = string
  default     = "video-output"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_output_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for video processing"
  type        = string
  default     = "video-processor"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "video_file_extensions" {
  description = "List of video file extensions to process"
  type        = list(string)
  default     = ["mp4", "mov", "avi", "mkv", "m4v"]
  
  validation {
    condition     = length(var.video_file_extensions) > 0
    error_message = "At least one video file extension must be specified."
  }
}

variable "cloudfront_enabled" {
  description = "Whether to create CloudFront distribution for video delivery"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "enable_completion_handler" {
  description = "Whether to create completion handler Lambda function and EventBridge rule"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.tags : can(regex("^[a-zA-Z0-9\\s\\-_.:/@]+$", k)) && can(regex("^[a-zA-Z0-9\\s\\-_.:/@]+$", v))])
    error_message = "Tag keys and values must contain only alphanumeric characters, spaces, and the following special characters: - _ . : / @"
  }
}

# MediaConvert settings
variable "mediaconvert_bitrate" {
  description = "Video bitrate for MediaConvert jobs in bits per second"
  type        = number
  default     = 2000000
  
  validation {
    condition     = var.mediaconvert_bitrate >= 100000 && var.mediaconvert_bitrate <= 100000000
    error_message = "MediaConvert bitrate must be between 100,000 and 100,000,000 bits per second."
  }
}

variable "mediaconvert_framerate" {
  description = "Video framerate for MediaConvert jobs (frames per second)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.mediaconvert_framerate >= 1 && var.mediaconvert_framerate <= 120
    error_message = "MediaConvert framerate must be between 1 and 120 fps."
  }
}

variable "mediaconvert_width" {
  description = "Video width for MediaConvert jobs in pixels"
  type        = number
  default     = 1280
  
  validation {
    condition     = var.mediaconvert_width >= 128 && var.mediaconvert_width <= 4096
    error_message = "MediaConvert width must be between 128 and 4096 pixels."
  }
}

variable "mediaconvert_height" {
  description = "Video height for MediaConvert jobs in pixels"
  type        = number
  default     = 720
  
  validation {
    condition     = var.mediaconvert_height >= 96 && var.mediaconvert_height <= 2160
    error_message = "MediaConvert height must be between 96 and 2160 pixels."
  }
}

variable "s3_versioning_enabled" {
  description = "Whether to enable versioning on S3 buckets"
  type        = bool
  default     = false
}

variable "s3_lifecycle_enabled" {
  description = "Whether to enable lifecycle management on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days after which to transition objects to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_days >= 1
    error_message = "S3 lifecycle transition days must be at least 1."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which to expire objects (0 to disable)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 0
    error_message = "S3 lifecycle expiration days must be 0 or greater."
  }
}