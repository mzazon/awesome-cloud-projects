# Input Variables for EC2 Image Builder Pipeline

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "web-server"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "instance_types" {
  description = "EC2 instance types for Image Builder"
  type        = list(string)
  default     = ["t3.medium"]
  
  validation {
    condition     = length(var.instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "base_image_name" {
  description = "Base image name pattern for Amazon Linux 2"
  type        = string
  default     = "Amazon Linux 2 x86"
}

variable "image_recipe_version" {
  description = "Semantic version for the image recipe"
  type        = string
  default     = "1.0.0"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.image_recipe_version))
    error_message = "Image recipe version must follow semantic versioning (e.g., 1.0.0)."
  }
}

variable "component_version" {
  description = "Semantic version for build and test components"
  type        = string
  default     = "1.0.0"
  
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.component_version))
    error_message = "Component version must follow semantic versioning (e.g., 1.0.0)."
  }
}

variable "pipeline_schedule" {
  description = "Cron expression for pipeline scheduling"
  type        = string
  default     = "cron(0 2 * * SUN)"
  
  validation {
    condition     = can(regex("^cron\\([0-9*,-/\\s]+\\)$", var.pipeline_schedule))
    error_message = "Pipeline schedule must be a valid cron expression."
  }
}

variable "image_tests_enabled" {
  description = "Enable image testing during pipeline execution"
  type        = bool
  default     = true
}

variable "image_tests_timeout_minutes" {
  description = "Timeout for image tests in minutes"
  type        = number
  default     = 90
  
  validation {
    condition     = var.image_tests_timeout_minutes >= 60 && var.image_tests_timeout_minutes <= 720
    error_message = "Image tests timeout must be between 60 and 720 minutes."
  }
}

variable "pipeline_status" {
  description = "Status of the image pipeline (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.pipeline_status)
    error_message = "Pipeline status must be either ENABLED or DISABLED."
  }
}

variable "terminate_instance_on_failure" {
  description = "Terminate build instance on failure"
  type        = bool
  default     = true
}

variable "distribution_regions" {
  description = "List of AWS regions for AMI distribution"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for region in var.distribution_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", region))
    ])
    error_message = "All distribution regions must be valid AWS region names."
  }
}

variable "notification_email" {
  description = "Email address for build notifications (optional)"
  type        = string
  default     = ""
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log group retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention value."
  }
}