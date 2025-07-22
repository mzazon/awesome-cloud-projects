# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

# Clean Rooms Configuration
variable "collaboration_name" {
  description = "Name for the Clean Rooms collaboration"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.collaboration_name) <= 100
    error_message = "Collaboration name must be 100 characters or less."
  }
}

variable "collaboration_description" {
  description = "Description for the Clean Rooms collaboration"
  type        = string
  default     = "Privacy-preserving analytics collaboration for cross-organizational insights"
}

variable "enable_query_logging" {
  description = "Enable query logging for Clean Rooms collaboration"
  type        = bool
  default     = true
}

variable "member_abilities" {
  description = "List of abilities for collaboration members"
  type        = list(string)
  default     = ["CAN_QUERY", "CAN_RECEIVE_RESULTS"]
  
  validation {
    condition = alltrue([
      for ability in var.member_abilities : 
      contains(["CAN_QUERY", "CAN_RECEIVE_RESULTS"], ability)
    ])
    error_message = "Member abilities must be from: CAN_QUERY, CAN_RECEIVE_RESULTS."
  }
}

# Data Configuration
variable "org_a_data_bucket_name" {
  description = "S3 bucket name for Organization A data (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "org_b_data_bucket_name" {
  description = "S3 bucket name for Organization B data (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "results_bucket_name" {
  description = "S3 bucket name for Clean Rooms query results (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "glue_database_name" {
  description = "AWS Glue database name (leave empty for auto-generated)"
  type        = string
  default     = ""
}

# Sample Data Configuration
variable "create_sample_data" {
  description = "Whether to create sample datasets for testing"
  type        = bool
  default     = true
}

variable "sample_data_org_a" {
  description = "Sample data for Organization A"
  type = list(object({
    customer_id       = string
    age_group        = string
    region           = string
    purchase_amount  = string
    product_category = string
    registration_date = string
  }))
  default = [
    {
      customer_id       = "1001"
      age_group        = "25-34"
      region           = "east"
      purchase_amount  = "250.00"
      product_category = "electronics"
      registration_date = "2023-01-15"
    },
    {
      customer_id       = "1002"
      age_group        = "35-44"
      region           = "west"
      purchase_amount  = "180.50"
      product_category = "clothing"
      registration_date = "2023-02-20"
    },
    {
      customer_id       = "1003"
      age_group        = "45-54"
      region           = "central"
      purchase_amount  = "320.75"
      product_category = "home"
      registration_date = "2023-01-10"
    },
    {
      customer_id       = "1004"
      age_group        = "25-34"
      region           = "east"
      purchase_amount  = "95.25"
      product_category = "books"
      registration_date = "2023-03-05"
    },
    {
      customer_id       = "1005"
      age_group        = "55-64"
      region           = "west"
      purchase_amount  = "450.00"
      product_category = "electronics"
      registration_date = "2023-02-28"
    }
  ]
}

variable "sample_data_org_b" {
  description = "Sample data for Organization B"
  type = list(object({
    customer_id        = string
    age_group         = string
    region            = string
    engagement_score  = string
    channel_preference = string
    last_interaction  = string
  }))
  default = [
    {
      customer_id        = "2001"
      age_group         = "25-34"
      region            = "east"
      engagement_score  = "85"
      channel_preference = "email"
      last_interaction  = "2023-03-15"
    },
    {
      customer_id        = "2002"
      age_group         = "35-44"
      region            = "west"
      engagement_score  = "72"
      channel_preference = "social"
      last_interaction  = "2023-03-20"
    },
    {
      customer_id        = "2003"
      age_group         = "45-54"
      region            = "central"
      engagement_score  = "91"
      channel_preference = "email"
      last_interaction  = "2023-03-10"
    },
    {
      customer_id        = "2004"
      age_group         = "25-34"
      region            = "east"
      engagement_score  = "68"
      channel_preference = "mobile"
      last_interaction  = "2023-03-25"
    },
    {
      customer_id        = "2005"
      age_group         = "55-64"
      region            = "west"
      engagement_score  = "88"
      channel_preference = "email"
      last_interaction  = "2023-03-18"
    }
  ]
}

# IAM Configuration
variable "clean_rooms_role_name" {
  description = "IAM role name for Clean Rooms service (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "glue_role_name" {
  description = "IAM role name for AWS Glue service (leave empty for auto-generated)"
  type        = string
  default     = ""
}

# QuickSight Configuration
variable "enable_quicksight" {
  description = "Whether to configure QuickSight resources"
  type        = bool
  default     = true
}

variable "quicksight_account_name" {
  description = "QuickSight account name"
  type        = string
  default     = "Clean Rooms Analytics"
}

variable "quicksight_edition" {
  description = "QuickSight edition (STANDARD or ENTERPRISE)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "ENTERPRISE"], var.quicksight_edition)
    error_message = "QuickSight edition must be STANDARD or ENTERPRISE."
  }
}

variable "quicksight_notification_email" {
  description = "Email address for QuickSight notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.quicksight_notification_email))
    error_message = "Must be a valid email address."
  }
}

# Security Configuration
variable "enable_bucket_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "enable_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_bucket_public_access_block" {
  description = "Enable S3 bucket public access block"
  type        = bool
  default     = true
}

# Differential Privacy Configuration
variable "differential_privacy_epsilon" {
  description = "Epsilon value for differential privacy (lower = more privacy)"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.differential_privacy_epsilon > 0 && var.differential_privacy_epsilon <= 10
    error_message = "Epsilon must be between 0 and 10."
  }
}

variable "min_query_threshold" {
  description = "Minimum number of records required for query results"
  type        = number
  default     = 3
  
  validation {
    condition     = var.min_query_threshold >= 1
    error_message = "Minimum query threshold must be at least 1."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for resource names (leave empty for auto-generated)"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}