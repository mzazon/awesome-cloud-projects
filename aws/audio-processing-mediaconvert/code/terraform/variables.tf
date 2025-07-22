# Variables for Audio Processing Pipeline with AWS Elemental MediaConvert
# This file defines all configurable parameters for the infrastructure

# General Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format like us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must contain only lowercase letters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "audio-processing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 Configuration
variable "input_bucket_name" {
  description = "Name for the S3 input bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "output_bucket_name" {
  description = "Name for the S3 output bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_encryption_enabled" {
  description = "Enable server-side encryption on S3 buckets"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name for the Lambda function (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be one of: python3.8, python3.9, python3.10, python3.11."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# MediaConvert Configuration
variable "mediaconvert_job_template_name" {
  description = "Name for the MediaConvert job template"
  type        = string
  default     = ""
}

variable "mediaconvert_preset_name" {
  description = "Name for the MediaConvert audio preset"
  type        = string
  default     = ""
}

variable "audio_bitrate_mp3" {
  description = "Bitrate for MP3 output in bits per second"
  type        = number
  default     = 128000
  
  validation {
    condition     = var.audio_bitrate_mp3 >= 32000 && var.audio_bitrate_mp3 <= 320000
    error_message = "MP3 bitrate must be between 32000 and 320000 bps."
  }
}

variable "audio_bitrate_aac" {
  description = "Bitrate for AAC output in bits per second"
  type        = number
  default     = 128000
  
  validation {
    condition     = var.audio_bitrate_aac >= 32000 && var.audio_bitrate_aac <= 256000
    error_message = "AAC bitrate must be between 32000 and 256000 bps."
  }
}

variable "audio_sample_rate" {
  description = "Sample rate for audio output in Hz"
  type        = number
  default     = 44100
  
  validation {
    condition     = contains([22050, 44100, 48000, 96000], var.audio_sample_rate)
    error_message = "Audio sample rate must be one of: 22050, 44100, 48000, 96000."
  }
}

variable "audio_channels" {
  description = "Number of audio channels"
  type        = number
  default     = 2
  
  validation {
    condition     = var.audio_channels >= 1 && var.audio_channels <= 8
    error_message = "Audio channels must be between 1 and 8."
  }
}

variable "loudness_target_lkfs" {
  description = "Target loudness in LKFS for audio normalization"
  type        = number
  default     = -23.0
  
  validation {
    condition     = var.loudness_target_lkfs >= -50.0 && var.loudness_target_lkfs <= 0.0
    error_message = "Loudness target must be between -50.0 and 0.0 LKFS."
  }
}

# SNS Configuration
variable "sns_topic_name" {
  description = "Name for the SNS topic (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address for processing notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# CloudWatch Configuration
variable "cloudwatch_dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = ""
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be one of the valid values (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653)."
  }
}

# Security Configuration
variable "enable_s3_access_logging" {
  description = "Enable access logging for S3 buckets"
  type        = bool
  default     = true
}

variable "enable_s3_public_access_block" {
  description = "Enable public access block for S3 buckets"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS keys"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Supported audio file extensions for S3 event filtering
variable "supported_audio_extensions" {
  description = "List of supported audio file extensions"
  type        = list(string)
  default     = ["mp3", "wav", "flac", "m4a", "aac"]
  
  validation {
    condition     = length(var.supported_audio_extensions) > 0
    error_message = "At least one audio extension must be supported."
  }
}