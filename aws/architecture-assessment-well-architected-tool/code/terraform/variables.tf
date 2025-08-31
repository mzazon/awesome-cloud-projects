# Variables for AWS Well-Architected Tool Assessment Infrastructure

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "well-architected-assessment"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 64
    error_message = "Project name must be between 1 and 64 characters."
  }
}

variable "environment" {
  description = "Environment for the workload assessment (e.g., development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production", "test", "demo"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, test, demo."
  }
}

variable "workload_description" {
  description = "Description of the workload being assessed"
  type        = string
  default     = "Sample web application workload for Well-Architected assessment"
  
  validation {
    condition     = length(var.workload_description) > 0 && length(var.workload_description) <= 255
    error_message = "Workload description must be between 1 and 255 characters."
  }
}

variable "industry_type" {
  description = "Industry type for the workload assessment"
  type        = string
  default     = "InfoTech"
  
  validation {
    condition = contains([
      "Advertising", "Agriculture", "Automotive", "Aerospace", "Banking", 
      "Construction", "Education", "Energy", "Entertainment", "Finance", 
      "Government", "Healthcare", "InfoTech", "Insurance", "Manufacturing", 
      "Media", "Mining", "NonProfit", "PowerUtilities", "Professional", 
      "RealEstate", "Retail", "SocialMedia", "Telecommunications", 
      "Transportation", "Travel", "Utilities", "WaterUtilities", "Other"
    ], var.industry_type)
    error_message = "Industry type must be a valid AWS industry classification."
  }
}

variable "architectural_design" {
  description = "High-level architectural design description"
  type        = string
  default     = "Three-tier web application with load balancer, application servers, and database"
}

variable "review_owner" {
  description = "Email address or ARN of the review owner"
  type        = string
  default     = ""
}

variable "lenses" {
  description = "List of lenses to apply for the assessment"
  type        = list(string)
  default     = ["wellarchitected"]
  
  validation {
    condition     = length(var.lenses) > 0
    error_message = "At least one lens must be specified."
  }
}

variable "aws_regions" {
  description = "List of AWS regions where the workload operates"
  type        = list(string)
  default     = []
}

variable "cost_center" {
  description = "Cost center for billing and resource tracking"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Owner of the workload and assessment"
  type        = string
  default     = "platform-team"
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for workload monitoring"
  type        = bool
  default     = true
}

variable "enable_notifications" {
  description = "Enable SNS notifications for assessment milestones"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for assessment notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "create_sample_resources" {
  description = "Create sample AWS resources to demonstrate assessment capabilities"
  type        = bool
  default     = false
}

variable "workload_tags" {
  description = "Additional tags to apply to the workload and resources"
  type        = map(string)
  default     = {}
}

variable "assessment_notes" {
  description = "Initial notes for the workload assessment"
  type        = string
  default     = "Automated workload created for Well-Architected Framework assessment demonstration"
}