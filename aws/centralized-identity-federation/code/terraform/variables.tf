# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# IAM Identity Center Configuration
variable "sso_instance_name" {
  description = "Name for the IAM Identity Center instance"
  type        = string
  default     = "enterprise-sso"
}

variable "identity_store_display_name" {
  description = "Display name for the identity store"
  type        = string
  default     = "Enterprise Identity Store"
}

# External Identity Provider Configuration
variable "external_idp_metadata_url" {
  description = "SAML metadata URL for external identity provider"
  type        = string
  default     = "https://your-idp.example.com/metadata"
  
  validation {
    condition = can(regex("^https://", var.external_idp_metadata_url))
    error_message = "External IdP metadata URL must use HTTPS."
  }
}

variable "enable_external_idp" {
  description = "Enable external identity provider integration"
  type        = bool
  default     = false
}

# Permission Set Configuration
variable "permission_sets" {
  description = "Configuration for IAM Identity Center permission sets"
  type = map(object({
    name              = string
    description       = string
    session_duration  = string
    managed_policies  = list(string)
    inline_policy     = string
    relay_state       = optional(string)
  }))
  
  default = {
    developer = {
      name             = "Developer"
      description      = "Development environment access with limited permissions"
      session_duration = "PT8H"
      managed_policies = ["arn:aws:iam::aws:policy/PowerUserAccess"]
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Deny"
            Action = [
              "iam:*",
              "organizations:*",
              "account:*",
              "billing:*",
              "aws-portal:*"
            ]
            Resource = "*"
          },
          {
            Effect = "Allow"
            Action = [
              "iam:GetRole",
              "iam:GetRolePolicy",
              "iam:ListRoles",
              "iam:ListRolePolicies",
              "iam:PassRole"
            ]
            Resource = "*"
            Condition = {
              StringLike = {
                "iam:PassedToService" = [
                  "lambda.amazonaws.com",
                  "ec2.amazonaws.com",
                  "ecs-tasks.amazonaws.com"
                ]
              }
            }
          }
        ]
      })
    }
    
    administrator = {
      name             = "Administrator"
      description      = "Full administrative access across all accounts"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      inline_policy    = ""
    }
    
    readonly = {
      name             = "ReadOnly"
      description      = "Read-only access for business users and auditors"
      session_duration = "PT12H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "s3:GetObject",
              "s3:ListBucket",
              "cloudwatch:GetMetricStatistics",
              "cloudwatch:ListMetrics",
              "logs:DescribeLogGroups",
              "logs:DescribeLogStreams",
              "logs:FilterLogEvents",
              "quicksight:*"
            ]
            Resource = "*"
          }
        ]
      })
    }
  }
}

# Account Assignment Configuration
variable "account_assignments" {
  description = "Configuration for account assignments"
  type = map(object({
    account_id       = string
    permission_set   = string
    principal_type   = string
    principal_id     = string
  }))
  
  default = {
    # Example assignments - update with your actual account IDs and principal IDs
    dev_access = {
      account_id     = "123456789012"  # Replace with your dev account ID
      permission_set = "developer"
      principal_type = "GROUP"
      principal_id   = "developers-group-id"  # Replace with your group ID
    }
    
    prod_admin = {
      account_id     = "234567890123"  # Replace with your prod account ID
      permission_set = "administrator"
      principal_type = "GROUP"
      principal_id   = "administrators-group-id"  # Replace with your group ID
    }
    
    prod_readonly = {
      account_id     = "234567890123"  # Replace with your prod account ID
      permission_set = "readonly"
      principal_type = "GROUP"
      principal_id   = "business-users-group-id"  # Replace with your group ID
    }
  }
}

# Application Configuration
variable "applications" {
  description = "Configuration for SAML applications"
  type = map(object({
    name                = string
    description         = string
    application_url     = string
    client_token        = optional(string)
    status              = string
    portal_visibility   = bool
    attribute_mappings  = map(string)
  }))
  
  default = {
    business_app1 = {
      name            = "BusinessApp1"
      description     = "Primary business application SAML integration"
      application_url = "https://app1.company.com"
      status          = "ENABLED"
      portal_visibility = true
      attribute_mappings = {
        email     = "$${path:enterprise.email}"
        firstName = "$${path:enterprise.givenName}"
        lastName  = "$${path:enterprise.familyName}"
        groups    = "$${path:enterprise.groups}"
      }
    }
  }
}

# CloudTrail Configuration
variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_retention_days" {
  description = "Number of days to retain CloudTrail logs"
  type        = number
  default     = 365
  
  validation {
    condition = var.cloudtrail_retention_days >= 1 && var.cloudtrail_retention_days <= 3653
    error_message = "CloudTrail retention days must be between 1 and 3653 days."
  }
}

# CloudWatch Configuration
variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_notification_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.alarm_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alarm_notification_email))
    error_message = "If provided, alarm notification email must be a valid email address."
  }
}

# Security Configuration
variable "session_timeout" {
  description = "Default session timeout for permission sets"
  type        = string
  default     = "PT8H"
  
  validation {
    condition = can(regex("^PT[0-9]+H$", var.session_timeout))
    error_message = "Session timeout must be in ISO 8601 duration format (e.g., PT8H)."
  }
}

variable "require_mfa" {
  description = "Require multi-factor authentication"
  type        = bool
  default     = true
}

variable "enable_trusted_device_management" {
  description = "Enable trusted device management"
  type        = bool
  default     = true
}

variable "max_trusted_devices_per_user" {
  description = "Maximum number of trusted devices per user"
  type        = number
  default     = 3
  
  validation {
    condition = var.max_trusted_devices_per_user >= 1 && var.max_trusted_devices_per_user <= 10
    error_message = "Max trusted devices per user must be between 1 and 10."
  }
}

# Backup and Disaster Recovery Configuration
variable "enable_backup_configuration" {
  description = "Enable backup configuration for disaster recovery"
  type        = bool
  default     = true
}

variable "backup_regions" {
  description = "List of regions for backup configuration"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = var.backup_retention_period >= 7 && var.backup_retention_period <= 365
    error_message = "Backup retention period must be between 7 and 365 days."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "identity-federation"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}