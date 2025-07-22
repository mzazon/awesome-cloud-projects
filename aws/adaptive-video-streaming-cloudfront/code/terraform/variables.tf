# Input variables for Adaptive Bitrate Streaming infrastructure

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
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
  default     = "adaptive-bitrate-streaming"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "source_bucket_name" {
  description = "Name for the source video bucket (optional, will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "output_bucket_name" {
  description = "Name for the output/processed video bucket (optional, will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition = contains([
      "PriceClass_All",
      "PriceClass_200", 
      "PriceClass_100"
    ], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_All, PriceClass_200, PriceClass_100."
  }
}

variable "enable_cors" {
  description = "Enable CORS on output bucket for web playback"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "mediaconvert_queue_name" {
  description = "MediaConvert queue name (optional, will use default queue if not provided)"
  type        = string
  default     = ""
}

variable "video_file_extensions" {
  description = "List of video file extensions to process"
  type        = list(string)
  default     = [".mp4", ".mov", ".avi", ".mkv", ".mxf", ".mts", ".m2ts"]
}

variable "abr_bitrate_ladder" {
  description = "Adaptive bitrate ladder configuration"
  type = object({
    enable_1080p = bool
    enable_720p  = bool
    enable_480p  = bool
    enable_360p  = bool
  })
  default = {
    enable_1080p = true
    enable_720p  = true
    enable_480p  = true
    enable_360p  = true
  }
}

variable "enable_thumbnails" {
  description = "Enable thumbnail generation"
  type        = bool
  default     = true
}

variable "enable_dash_output" {
  description = "Enable DASH output format"
  type        = bool
  default     = true
}

variable "enable_hls_output" {
  description = "Enable HLS output format"
  type        = bool
  default     = true
}

variable "hls_segment_length" {
  description = "HLS segment length in seconds"
  type        = number
  default     = 6
  
  validation {
    condition     = var.hls_segment_length >= 2 && var.hls_segment_length <= 10
    error_message = "HLS segment length must be between 2 and 10 seconds."
  }
}

variable "dash_segment_length" {
  description = "DASH segment length in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.dash_segment_length >= 10 && var.dash_segment_length <= 60
    error_message = "DASH segment length must be between 10 and 60 seconds."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_monitoring" {
  description = "Enable enhanced monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for processing notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}