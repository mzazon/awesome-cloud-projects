# General Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "live-event-broadcasting"
}

# MediaConnect Configuration
variable "mediaconnect_availability_zones" {
  description = "Availability zones for MediaConnect flows"
  type        = list(string)
  default     = ["a", "b"]
  
  validation {
    condition     = length(var.mediaconnect_availability_zones) >= 2
    error_message = "At least 2 availability zones are required for redundancy."
  }
}

variable "mediaconnect_ingest_whitelist_cidrs" {
  description = "CIDR blocks allowed to send video to MediaConnect flows"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mediaconnect_primary_ingest_port" {
  description = "Ingest port for primary MediaConnect flow"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.mediaconnect_primary_ingest_port >= 1024 && var.mediaconnect_primary_ingest_port <= 65535
    error_message = "Port must be between 1024 and 65535."
  }
}

variable "mediaconnect_backup_ingest_port" {
  description = "Ingest port for backup MediaConnect flow"
  type        = number
  default     = 5001
  
  validation {
    condition     = var.mediaconnect_backup_ingest_port >= 1024 && var.mediaconnect_backup_ingest_port <= 65535
    error_message = "Port must be between 1024 and 65535."
  }
}

variable "mediaconnect_output_port_primary" {
  description = "Output port for primary MediaConnect flow to MediaLive"
  type        = number
  default     = 5002
}

variable "mediaconnect_output_port_backup" {
  description = "Output port for backup MediaConnect flow to MediaLive"
  type        = number
  default     = 5003
}

# MediaLive Configuration
variable "medialive_video_bitrate" {
  description = "Video bitrate for MediaLive encoding (bits per second)"
  type        = number
  default     = 2000000
  
  validation {
    condition     = var.medialive_video_bitrate >= 100000 && var.medialive_video_bitrate <= 20000000
    error_message = "Video bitrate must be between 100000 and 20000000 bps."
  }
}

variable "medialive_audio_bitrate" {
  description = "Audio bitrate for MediaLive encoding (bits per second)"
  type        = number
  default     = 128000
  
  validation {
    condition     = var.medialive_audio_bitrate >= 64000 && var.medialive_audio_bitrate <= 384000
    error_message = "Audio bitrate must be between 64000 and 384000 bps."
  }
}

variable "medialive_video_width" {
  description = "Video width for MediaLive encoding"
  type        = number
  default     = 1280
}

variable "medialive_video_height" {
  description = "Video height for MediaLive encoding"
  type        = number
  default     = 720
}

variable "medialive_framerate" {
  description = "Video framerate for MediaLive encoding"
  type        = number
  default     = 30
}

variable "medialive_gop_size" {
  description = "GOP size for MediaLive encoding"
  type        = number
  default     = 90
}

# MediaPackage Configuration
variable "mediapackage_segment_duration" {
  description = "Segment duration for MediaPackage HLS output (seconds)"
  type        = number
  default     = 6
  
  validation {
    condition     = var.mediapackage_segment_duration >= 1 && var.mediapackage_segment_duration <= 30
    error_message = "Segment duration must be between 1 and 30 seconds."
  }
}

variable "mediapackage_playlist_window" {
  description = "Playlist window duration for MediaPackage HLS output (seconds)"
  type        = number
  default     = 60
}

# CloudWatch Configuration
variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
}

variable "cloudwatch_alarm_period" {
  description = "Period for CloudWatch alarm evaluation (seconds)"
  type        = number
  default     = 300
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for all resources"
  type        = bool
  default     = true
}

# Auto-start Configuration
variable "auto_start_flows" {
  description = "Automatically start MediaConnect flows after creation"
  type        = bool
  default     = false
}

variable "auto_start_channel" {
  description = "Automatically start MediaLive channel after creation"
  type        = bool
  default     = false
}

# Security Configuration
variable "enable_flow_source_encryption" {
  description = "Enable encryption for MediaConnect flow sources"
  type        = bool
  default     = true
}

variable "allowed_source_ips" {
  description = "List of IP addresses allowed to send video to MediaConnect flows"
  type        = list(string)
  default     = []
}

# Cost Optimization
variable "enable_cost_optimization" {
  description = "Enable cost optimization features (may impact performance)"
  type        = bool
  default     = false
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}