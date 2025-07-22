# Variables for Video Streaming Platform Infrastructure
# This file defines all configurable parameters for the streaming platform

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1'."
  }
}

variable "project_name" {
  description = "Name of the streaming platform project"
  type        = string
  default     = "video-streaming-platform"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.project_name))
    error_message = "Project name must be 3-32 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  description = "Environment for the streaming platform (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# MediaLive Channel Configuration
variable "channel_name" {
  description = "Name for the MediaLive channel"
  type        = string
  default     = ""
}

variable "input_codec" {
  description = "Input codec for MediaLive channel"
  type        = string
  default     = "AVC"

  validation {
    condition     = contains(["AVC", "HEVC"], var.input_codec)
    error_message = "Input codec must be either AVC or HEVC."
  }
}

variable "input_resolution" {
  description = "Input resolution for MediaLive channel"
  type        = string
  default     = "HD"

  validation {
    condition     = contains(["SD", "HD", "UHD"], var.input_resolution)
    error_message = "Input resolution must be one of: SD, HD, UHD."
  }
}

variable "maximum_bitrate" {
  description = "Maximum bitrate for MediaLive input"
  type        = string
  default     = "MAX_50_MBPS"

  validation {
    condition = contains([
      "MAX_10_MBPS", "MAX_20_MBPS", "MAX_50_MBPS"
    ], var.maximum_bitrate)
    error_message = "Maximum bitrate must be one of: MAX_10_MBPS, MAX_20_MBPS, MAX_50_MBPS."
  }
}

# Video Quality Configuration
variable "enable_4k_output" {
  description = "Enable 4K (2160p) video output"
  type        = bool
  default     = true
}

variable "enable_hd_outputs" {
  description = "Enable HD video outputs (1080p, 720p)"
  type        = bool
  default     = true
}

variable "enable_sd_outputs" {
  description = "Enable SD video outputs (480p, 240p)"
  type        = bool
  default     = true
}

variable "video_bitrates" {
  description = "Bitrates for different video quality levels"
  type = object({
    video_2160p = number
    video_1080p = number
    video_720p  = number
    video_480p  = number
    video_240p  = number
  })
  default = {
    video_2160p = 15000000  # 15 Mbps for 4K
    video_1080p = 6000000   # 6 Mbps for 1080p
    video_720p  = 3000000   # 3 Mbps for 720p
    video_480p  = 1500000   # 1.5 Mbps for 480p
    video_240p  = 500000    # 500 Kbps for 240p
  }

  validation {
    condition = alltrue([
      var.video_bitrates.video_2160p >= 10000000,
      var.video_bitrates.video_1080p >= 3000000,
      var.video_bitrates.video_720p >= 1000000,
      var.video_bitrates.video_480p >= 500000,
      var.video_bitrates.video_240p >= 200000
    ])
    error_message = "Video bitrates must be within reasonable ranges for each quality level."
  }
}

variable "audio_bitrates" {
  description = "Bitrates for audio channels"
  type = object({
    stereo   = number
    surround = number
  })
  default = {
    stereo   = 128000  # 128 Kbps for stereo
    surround = 256000  # 256 Kbps for 5.1 surround
  }
}

# MediaPackage Configuration
variable "package_channel_name" {
  description = "Name for the MediaPackage channel"
  type        = string
  default     = ""
}

variable "startover_window_seconds" {
  description = "Start-over window duration in seconds for MediaPackage endpoints"
  type        = number
  default     = 3600

  validation {
    condition     = var.startover_window_seconds >= 300 && var.startover_window_seconds <= 2419200
    error_message = "Start-over window must be between 300 seconds (5 minutes) and 2419200 seconds (28 days)."
  }
}

variable "segment_duration_seconds" {
  description = "Segment duration in seconds for MediaPackage"
  type        = number
  default     = 4

  validation {
    condition     = var.segment_duration_seconds >= 1 && var.segment_duration_seconds <= 30
    error_message = "Segment duration must be between 1 and 30 seconds."
  }
}

# Low Latency Configuration
variable "enable_low_latency" {
  description = "Enable low latency streaming with CMAF"
  type        = bool
  default     = true
}

variable "low_latency_segment_duration" {
  description = "Segment duration for low latency streaming"
  type        = number
  default     = 2

  validation {
    condition     = var.low_latency_segment_duration >= 1 && var.low_latency_segment_duration <= 10
    error_message = "Low latency segment duration must be between 1 and 10 seconds."
  }
}

# DRM Configuration
variable "enable_drm" {
  description = "Enable DRM protection for content"
  type        = bool
  default     = true
}

variable "drm_key_rotation_interval" {
  description = "DRM key rotation interval in hours"
  type        = number
  default     = 24

  validation {
    condition     = var.drm_key_rotation_interval >= 1 && var.drm_key_rotation_interval <= 8760
    error_message = "DRM key rotation interval must be between 1 hour and 1 year (8760 hours)."
  }
}

# S3 Storage Configuration
variable "archive_enabled" {
  description = "Enable archiving of live streams to S3"
  type        = bool
  default     = true
}

variable "archive_rollover_interval" {
  description = "Archive rollover interval in seconds"
  type        = number
  default     = 3600

  validation {
    condition     = var.archive_rollover_interval >= 60 && var.archive_rollover_interval <= 86400
    error_message = "Archive rollover interval must be between 60 seconds and 86400 seconds (24 hours)."
  }
}

variable "lifecycle_transitions" {
  description = "S3 lifecycle transition rules for archived content"
  type = object({
    standard_ia_days  = number
    glacier_days      = number
    deep_archive_days = number
  })
  default = {
    standard_ia_days  = 30
    glacier_days      = 90
    deep_archive_days = 365
  }

  validation {
    condition = (
      var.lifecycle_transitions.standard_ia_days < var.lifecycle_transitions.glacier_days &&
      var.lifecycle_transitions.glacier_days < var.lifecycle_transitions.deep_archive_days
    )
    error_message = "Lifecycle transition days must be in ascending order: IA < Glacier < Deep Archive."
  }
}

# CloudFront Configuration
variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_All"

  validation {
    condition = contains([
      "PriceClass_100", "PriceClass_200", "PriceClass_All"
    ], var.cloudfront_price_class)
    error_message = "CloudFront price class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "cloudfront_default_ttl" {
  description = "Default TTL for CloudFront cache (in seconds)"
  type        = number
  default     = 5

  validation {
    condition     = var.cloudfront_default_ttl >= 0 && var.cloudfront_default_ttl <= 31536000
    error_message = "CloudFront default TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

variable "cloudfront_max_ttl" {
  description = "Maximum TTL for CloudFront cache (in seconds)"
  type        = number
  default     = 31536000

  validation {
    condition     = var.cloudfront_max_ttl >= 0 && var.cloudfront_max_ttl <= 31536000
    error_message = "CloudFront maximum TTL must be between 0 and 31536000 seconds (1 year)."
  }
}

# Input Security Configuration
variable "input_whitelist_cidrs" {
  description = "CIDR blocks allowed to send content to MediaLive inputs"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Allow all by default - restrict in production

  validation {
    condition = alltrue([
      for cidr in var.input_whitelist_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All input whitelist entries must be valid CIDR blocks."
  }
}

variable "internal_cidrs" {
  description = "Internal CIDR blocks for professional equipment access"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition = alltrue([
      for cidr in var.internal_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All internal CIDR entries must be valid CIDR blocks."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "alarm_email_endpoint" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""

  validation {
    condition = var.alarm_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alarm_email_endpoint))
    error_message = "Alarm email endpoint must be a valid email address or empty string."
  }
}

variable "input_loss_threshold" {
  description = "Threshold for input loss alarm (0.0 to 1.0)"
  type        = number
  default     = 0.5

  validation {
    condition     = var.input_loss_threshold >= 0.0 && var.input_loss_threshold <= 1.0
    error_message = "Input loss threshold must be between 0.0 and 1.0."
  }
}

variable "error_rate_threshold" {
  description = "Threshold for error rate alarms (percentage)"
  type        = number
  default     = 5

  validation {
    condition     = var.error_rate_threshold >= 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 0 and 100 percent."
  }
}

# Additional Configuration
variable "create_web_player" {
  description = "Create a web player interface for testing"
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Enable IPv6 for CloudFront distribution"
  type        = bool
  default     = true
}

variable "web_player_title" {
  description = "Title for the web player interface"
  type        = string
  default     = "Enterprise Streaming Platform"
}

# Cost Optimization
variable "auto_start_channel" {
  description = "Automatically start MediaLive channel after creation"
  type        = bool
  default     = false
}

variable "channel_schedule" {
  description = "Schedule for starting/stopping the channel (not implemented in this version)"
  type = object({
    enabled    = bool
    start_time = string
    stop_time  = string
    timezone   = string
  })
  default = {
    enabled    = false
    start_time = "09:00"
    stop_time  = "17:00"
    timezone   = "UTC"
  }
}