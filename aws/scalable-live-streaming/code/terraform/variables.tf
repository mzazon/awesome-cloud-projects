# General Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

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
  description = "Name of the project"
  type        = string
  default     = "live-streaming-solution"
}

# Resource Naming
variable "resource_name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "live-stream"
}

# MediaLive Configuration
variable "medialive_input_cidr_allow_list" {
  description = "CIDR blocks allowed to send streams to MediaLive input"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "medialive_input_type" {
  description = "MediaLive input type"
  type        = string
  default     = "RTMP_PUSH"
  
  validation {
    condition     = contains(["RTMP_PUSH", "RTMP_PULL", "RTP_PUSH", "UDP_PUSH"], var.medialive_input_type)
    error_message = "Input type must be one of: RTMP_PUSH, RTMP_PULL, RTP_PUSH, UDP_PUSH."
  }
}

variable "medialive_channel_class" {
  description = "MediaLive channel class"
  type        = string
  default     = "SINGLE_PIPELINE"
  
  validation {
    condition     = contains(["SINGLE_PIPELINE", "STANDARD"], var.medialive_channel_class)
    error_message = "Channel class must be either SINGLE_PIPELINE or STANDARD."
  }
}

variable "medialive_input_resolution" {
  description = "Input resolution for MediaLive"
  type        = string
  default     = "HD"
  
  validation {
    condition     = contains(["SD", "HD", "UHD"], var.medialive_input_resolution)
    error_message = "Input resolution must be one of: SD, HD, UHD."
  }
}

variable "medialive_input_max_bitrate" {
  description = "Maximum bitrate for MediaLive input"
  type        = string
  default     = "MAX_10_MBPS"
  
  validation {
    condition     = contains(["MAX_10_MBPS", "MAX_20_MBPS", "MAX_50_MBPS"], var.medialive_input_max_bitrate)
    error_message = "Max bitrate must be one of: MAX_10_MBPS, MAX_20_MBPS, MAX_50_MBPS."
  }
}

# Video Encoding Configuration
variable "video_bitrates" {
  description = "Video bitrates for different resolutions"
  type = object({
    video_1080p = number
    video_720p  = number
    video_480p  = number
  })
  default = {
    video_1080p = 6000000
    video_720p  = 3000000
    video_480p  = 1500000
  }
}

variable "video_frame_rate" {
  description = "Video frame rate"
  type        = number
  default     = 30
  
  validation {
    condition     = var.video_frame_rate >= 15 && var.video_frame_rate <= 60
    error_message = "Frame rate must be between 15 and 60."
  }
}

variable "audio_bitrate" {
  description = "Audio bitrate in bits per second"
  type        = number
  default     = 96000
  
  validation {
    condition     = var.audio_bitrate >= 64000 && var.audio_bitrate <= 320000
    error_message = "Audio bitrate must be between 64000 and 320000."
  }
}

variable "audio_sample_rate" {
  description = "Audio sample rate in Hz"
  type        = number
  default     = 48000
  
  validation {
    condition     = contains([44100, 48000], var.audio_sample_rate)
    error_message = "Audio sample rate must be either 44100 or 48000."
  }
}

# MediaPackage Configuration
variable "segment_duration_seconds" {
  description = "Duration of each segment in seconds"
  type        = number
  default     = 6
  
  validation {
    condition     = var.segment_duration_seconds >= 1 && var.segment_duration_seconds <= 30
    error_message = "Segment duration must be between 1 and 30 seconds."
  }
}

variable "playlist_window_seconds" {
  description = "Playlist window duration in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.playlist_window_seconds >= 30 && var.playlist_window_seconds <= 3600
    error_message = "Playlist window must be between 30 and 3600 seconds."
  }
}

# CloudFront Configuration
variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_All"
  
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Price class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "cloudfront_cache_policy" {
  description = "CloudFront cache policy configuration"
  type = object({
    min_ttl     = number
    default_ttl = number
    max_ttl     = number
  })
  default = {
    min_ttl     = 0
    default_ttl = 5
    max_ttl     = 60
  }
}

# S3 Configuration
variable "s3_enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_enable_server_side_encryption" {
  description = "Enable S3 server-side encryption"
  type        = bool
  default     = true
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which objects expire"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 1 && var.s3_lifecycle_expiration_days <= 365
    error_message = "Lifecycle expiration must be between 1 and 365 days."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "sns_notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = ""
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for alarm evaluation"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

# Security Configuration
variable "enable_input_security_group" {
  description = "Enable MediaLive input security group"
  type        = bool
  default     = true
}

variable "create_test_resources" {
  description = "Create test resources (test player, etc.)"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}