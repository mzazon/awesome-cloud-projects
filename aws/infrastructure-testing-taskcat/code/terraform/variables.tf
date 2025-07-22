# Variables for TaskCat CloudFormation testing infrastructure
# These variables allow customization of the testing environment

variable "project_name" {
  description = "Name of the TaskCat testing project"
  type        = string
  default     = "taskcat-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment_name" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "testing"
  
  validation {
    condition     = contains(["development", "testing", "staging", "production"], var.environment_name)
    error_message = "Environment name must be one of: development, testing, staging, production."
  }
}

variable "aws_regions" {
  description = "List of AWS regions where TaskCat will run tests"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
  
  validation {
    condition     = length(var.aws_regions) >= 1 && length(var.aws_regions) <= 10
    error_message = "Must specify between 1 and 10 AWS regions for testing."
  }
}

variable "s3_bucket_force_destroy" {
  description = "Whether to force destroy the S3 bucket even if it contains objects"
  type        = bool
  default     = true
}

variable "s3_bucket_versioning_enabled" {
  description = "Enable versioning for the TaskCat artifacts S3 bucket"
  type        = bool
  default     = true
}

variable "cloudformation_template_path" {
  description = "Local path to CloudFormation templates directory"
  type        = string
  default     = "./templates"
}

variable "taskcat_config_path" {
  description = "Local path to TaskCat configuration file"
  type        = string
  default     = "./.taskcat.yml"
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for TaskCat testing activities"
  type        = bool
  default     = false
}

variable "cloudtrail_retention_days" {
  description = "Number of days to retain CloudTrail logs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.cloudtrail_retention_days >= 1 && var.cloudtrail_retention_days <= 365
    error_message = "CloudTrail retention days must be between 1 and 365."
  }
}

variable "iam_role_path" {
  description = "Path for IAM roles created for TaskCat testing"
  type        = string
  default     = "/taskcat/"
  
  validation {
    condition     = can(regex("^/.*/$", var.iam_role_path))
    error_message = "IAM role path must start and end with forward slashes."
  }
}

variable "vpc_cidr_blocks" {
  description = "CIDR blocks for test VPCs in different scenarios"
  type        = map(string)
  default = {
    basic      = "10.0.0.0/16"
    no_nat     = "10.1.0.0/16"
    custom     = "172.16.0.0/16"
    dynamic    = "10.2.0.0/16"
    regional   = "10.3.0.0/16"
  }
  
  validation {
    condition = alltrue([
      for cidr in values(var.vpc_cidr_blocks) : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "key_pair_name" {
  description = "Name of existing EC2 key pair for test instances (optional)"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address for TaskCat test notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_cost_monitoring" {
  description = "Enable AWS Cost and Usage Reports for test resource monitoring"
  type        = bool
  default     = false
}

variable "test_timeout_minutes" {
  description = "Maximum time (in minutes) for TaskCat tests to run"
  type        = number
  default     = 60
  
  validation {
    condition     = var.test_timeout_minutes >= 5 && var.test_timeout_minutes <= 480
    error_message = "Test timeout must be between 5 and 480 minutes (8 hours)."
  }
}

variable "enable_security_scanning" {
  description = "Enable AWS Security Hub and Config for template security scanning"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}