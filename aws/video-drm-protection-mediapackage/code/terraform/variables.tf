# Input Variables for DRM-Protected Video Streaming Infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
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
  description = "Project name for resource naming"
  type        = string
  default     = "drm-protected-streaming"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# DRM Configuration Variables
variable "drm_config" {
  description = "DRM system configuration settings"
  type = object({
    widevine_provider           = string
    playready_provider          = string
    fairplay_provider          = string
    content_id_template        = string
    key_rotation_interval_seconds = number
    license_duration_seconds   = number
  })
  default = {
    widevine_provider           = "speke-reference"
    playready_provider          = "speke-reference"
    fairplay_provider          = "speke-reference"
    content_id_template        = "urn:uuid:"
    key_rotation_interval_seconds = 3600
    license_duration_seconds   = 86400
  }
}

# MediaLive Configuration Variables
variable "medialive_config" {
  description = "MediaLive channel configuration settings"
  type = object({
    input_specification = object({
      codec           = string
      resolution      = string
      maximum_bitrate = string
    })
    video_quality_tiers = list(object({
      name        = string
      width       = number
      height      = number
      bitrate     = number
      profile     = string
      level       = string
    }))
    audio_config = object({
      bitrate     = number
      sample_rate = number
      coding_mode = string
    })
  })
  default = {
    input_specification = {
      codec           = "AVC"
      resolution      = "HD"
      maximum_bitrate = "MAX_20_MBPS"
    }
    video_quality_tiers = [
      {
        name    = "1080p"
        width   = 1920
        height  = 1080
        bitrate = 5000000
        profile = "HIGH"
        level   = "H264_LEVEL_4_1"
      },
      {
        name    = "720p"
        width   = 1280
        height  = 720
        bitrate = 3000000
        profile = "HIGH"
        level   = "H264_LEVEL_3_1"
      },
      {
        name    = "480p"
        width   = 854
        height  = 480
        bitrate = 1500000
        profile = "MAIN"
        level   = "H264_LEVEL_3_0"
      }
    ]
    audio_config = {
      bitrate     = 128000
      sample_rate = 48000
      coding_mode = "CODING_MODE_2_0"
    }
  }
}

# MediaPackage Configuration Variables
variable "mediapackage_config" {
  description = "MediaPackage endpoint configuration settings"
  type = object({
    segment_duration_seconds = number
    playlist_window_seconds  = number
    playlist_type           = string
    key_rotation_interval   = number
    drm_systems = object({
      widevine_system_id  = string
      playready_system_id = string
      fairplay_system_id  = string
    })
  })
  default = {
    segment_duration_seconds = 6
    playlist_window_seconds  = 300
    playlist_type           = "EVENT"
    key_rotation_interval   = 3600
    drm_systems = {
      widevine_system_id  = "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"
      playready_system_id = "9a04f079-9840-4286-ab92-e65be0885f95"
      fairplay_system_id  = "94ce86fb-07ff-4f43-adb8-93d2fa968ca2"
    }
  }
}

# CloudFront Configuration Variables
variable "cloudfront_config" {
  description = "CloudFront distribution configuration settings"
  type = object({
    price_class = string
    geographic_restrictions = object({
      restriction_type = string
      locations        = list(string)
    })
    cache_policies = object({
      manifest_default_ttl = number
      manifest_max_ttl     = number
      license_default_ttl  = number
      license_max_ttl      = number
    })
    viewer_protocol_policy = string
    minimum_protocol_version = string
  })
  default = {
    price_class = "PriceClass_All"
    geographic_restrictions = {
      restriction_type = "blacklist"
      locations        = ["CN", "RU"]
    }
    cache_policies = {
      manifest_default_ttl = 5
      manifest_max_ttl     = 60
      license_default_ttl  = 0
      license_max_ttl      = 0
    }
    viewer_protocol_policy   = "https-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Lambda Configuration Variables
variable "lambda_config" {
  description = "Lambda function configuration for SPEKE provider"
  type = object({
    runtime     = string
    timeout     = number
    memory_size = number
  })
  default = {
    runtime     = "python3.9"
    timeout     = 30
    memory_size = 256
  }
}

# Network Configuration Variables
variable "network_config" {
  description = "Network access configuration for MediaLive"
  type = object({
    allowed_cidr_blocks = list(string)
  })
  default = {
    allowed_cidr_blocks = ["0.0.0.0/0"]
  }
}

# S3 Configuration Variables
variable "s3_config" {
  description = "S3 bucket configuration for test content"
  type = object({
    enable_website_hosting = bool
    force_destroy         = bool
  })
  default = {
    enable_website_hosting = true
    force_destroy         = true
  }
}

# Resource Tagging Variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}