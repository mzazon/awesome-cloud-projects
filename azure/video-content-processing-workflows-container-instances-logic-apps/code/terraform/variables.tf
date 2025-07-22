# Variables for Azure video processing workflow infrastructure

variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
  default     = "rg-video-workflow"
  
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 3 and 90 characters."
  }
}

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "North Europe", "West Europe",
      "UK South", "UK West", "France Central", "Germany West Central", "Norway East",
      "Switzerland North", "Sweden Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "India Central", "UAE North", "South Africa North"
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "video-processing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "storage_account_tier" {
  description = "Storage account performance tier"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "Storage replication type must be LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS."
  }
}

variable "container_cpu" {
  description = "Number of CPU cores for video processing container"
  type        = number
  default     = 2
  
  validation {
    condition     = var.container_cpu >= 1 && var.container_cpu <= 4
    error_message = "Container CPU must be between 1 and 4 cores."
  }
}

variable "container_memory" {
  description = "Memory in GB for video processing container"
  type        = number
  default     = 4
  
  validation {
    condition     = var.container_memory >= 1 && var.container_memory <= 16
    error_message = "Container memory must be between 1 and 16 GB."
  }
}

variable "enable_cdn" {
  description = "Enable Azure CDN for video distribution"
  type        = bool
  default     = false
}

variable "ffmpeg_image" {
  description = "Docker image for FFmpeg video processing"
  type        = string
  default     = "jrottenberg/ffmpeg:latest"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$", var.ffmpeg_image))
    error_message = "FFmpeg image must be a valid Docker image reference with tag."
  }
}

variable "video_formats" {
  description = "List of video output formats to generate"
  type        = list(string)
  default     = ["mp4", "webm"]
  
  validation {
    condition     = length(var.video_formats) > 0
    error_message = "At least one video format must be specified."
  }
}

variable "video_resolutions" {
  description = "List of video resolutions to generate"
  type        = list(string)
  default     = ["720p", "1080p"]
  
  validation {
    condition = alltrue([
      for resolution in var.video_resolutions :
      contains(["480p", "720p", "1080p", "4k"], resolution)
    ])
    error_message = "Video resolutions must be 480p, 720p, 1080p, or 4k."
  }
}

variable "retention_days" {
  description = "Number of days to retain processed videos"
  type        = number
  default     = 30
  
  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 365
    error_message = "Retention days must be between 1 and 365."
  }
}

variable "notification_email" {
  description = "Email address for processing notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to the resources"
  type        = map(string)
  default = {
    Purpose     = "video-processing"
    Environment = "demo"
    CreatedBy   = "terraform"
  }
}