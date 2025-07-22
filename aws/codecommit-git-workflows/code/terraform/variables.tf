# Input variables for the CodeCommit Git workflows infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "development"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "enterprise-app"
  
  validation {
    condition = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be between 1 and 50 characters."
  }
}

variable "repository_name" {
  description = "Name of the CodeCommit repository"
  type        = string
  default     = null
  
  validation {
    condition = var.repository_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.repository_name))
    error_message = "Repository name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "repository_description" {
  description = "Description for the CodeCommit repository"
  type        = string
  default     = "Enterprise application with Git workflow automation"
}

variable "notification_emails" {
  description = "List of email addresses for SNS notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification emails must be valid email addresses."
  }
}

variable "team_lead_users" {
  description = "List of IAM user ARNs for team leads (approval pool)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.team_lead_users : can(regex("^arn:aws:iam::[0-9]{12}:user/.+$", arn))
    ])
    error_message = "All team lead users must be valid IAM user ARNs."
  }
}

variable "senior_developer_users" {
  description = "List of IAM user ARNs for senior developers (approval pool)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.senior_developer_users : can(regex("^arn:aws:iam::[0-9]{12}:user/.+$", arn))
    ])
    error_message = "All senior developer users must be valid IAM user ARNs."
  }
}

variable "required_approvals" {
  description = "Number of required approvals for pull requests to protected branches"
  type        = number
  default     = 2
  
  validation {
    condition = var.required_approvals >= 1 && var.required_approvals <= 10
    error_message = "Required approvals must be between 1 and 10."
  }
}

variable "protected_branches" {
  description = "List of branch names that require approval rules"
  type        = list(string)
  default     = ["main", "master", "develop"]
  
  validation {
    condition = length(var.protected_branches) > 0
    error_message = "At least one protected branch must be specified."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_email_notifications" {
  description = "Whether to create email subscriptions for SNS topics"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}