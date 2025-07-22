# Variables for AWS Single Sign-On with External Identity Providers
# This file defines all the configurable parameters for the SSO deployment

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
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

variable "organization_name" {
  description = "Name of the organization for resource naming"
  type        = string
  default     = "MyOrg"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,63}$", var.organization_name))
    error_message = "Organization name must start with a letter, contain only alphanumeric characters and hyphens, and be 2-64 characters long."
  }
}

variable "identity_provider_name" {
  description = "Name of the external identity provider"
  type        = string
  default     = "ExternalIdP"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,31}$", var.identity_provider_name))
    error_message = "Identity provider name must start with a letter, contain only alphanumeric characters and hyphens, and be 2-32 characters long."
  }
}

variable "saml_metadata_document" {
  description = "SAML metadata document content from your external identity provider"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_scim" {
  description = "Enable SCIM for automatic user and group provisioning"
  type        = bool
  default     = true
}

variable "enable_external_idp" {
  description = "Enable external identity provider integration (set to false for local users only)"
  type        = bool
  default     = false # Set to false by default for demo purposes
}

variable "permission_sets" {
  description = "Map of permission sets to create with their configurations"
  type = map(object({
    description           = string
    session_duration     = string
    managed_policy_arns  = list(string)
    inline_policy       = optional(string)
    relay_state         = optional(string)
  }))
  
  default = {
    DeveloperAccess = {
      description         = "Developer access with PowerUser permissions"
      session_duration   = "PT8H"  # 8 hours
      managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]
      inline_policy      = null
      relay_state        = null
    }
    
    AdministratorAccess = {
      description         = "Full administrator access"
      session_duration   = "PT4H"  # 4 hours
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      inline_policy      = null
      relay_state        = null
    }
    
    ReadOnlyAccess = {
      description         = "Read-only access to AWS resources"
      session_duration   = "PT12H" # 12 hours
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy      = null
      relay_state        = null
    }
  }
  
  validation {
    condition = alltrue([
      for ps in values(var.permission_sets) : 
      can(regex("^PT([0-9]+H|[0-9]+M)$", ps.session_duration))
    ])
    error_message = "Session duration must be in ISO 8601 duration format (e.g., PT8H for 8 hours, PT480M for 480 minutes)."
  }
}

variable "test_users" {
  description = "Test users to create in the local identity store for demonstration"
  type = map(object({
    display_name = string
    given_name   = string
    family_name  = string
    email        = string
  }))
  
  default = {
    testuser = {
      display_name = "Test User"
      given_name   = "Test"
      family_name  = "User"
      email        = "testuser@example.com"
    }
  }
  
  validation {
    condition = alltrue([
      for user in values(var.test_users) : 
      can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", user.email))
    ])
    error_message = "All user emails must be valid email addresses."
  }
}

variable "test_groups" {
  description = "Test groups to create in the local identity store for demonstration"
  type = map(object({
    display_name = string
    description  = string
    members      = list(string) # List of user keys from test_users
  }))
  
  default = {
    developers = {
      display_name = "Developers"
      description  = "Developer group for testing SSO access"
      members      = ["testuser"]
    }
    
    admins = {
      display_name = "Administrators"
      description  = "Administrator group for testing SSO access"
      members      = []
    }
  }
}

variable "attribute_mappings" {
  description = "Attribute mappings for external identity provider integration"
  type = map(object({
    attribute_key    = string
    attribute_source = list(string)
  }))
  
  default = {
    Department = {
      attribute_key    = "Department"
      attribute_source = ["${path:enterprise.department}"]
    }
    
    CostCenter = {
      attribute_key    = "CostCenter"
      attribute_source = ["${path:enterprise.costCenter}"]
    }
    
    JobTitle = {
      attribute_key    = "JobTitle"
      attribute_source = ["${path:enterprise.title}"]
    }
  }
}

variable "account_assignments" {
  description = "Account assignments for users and groups to permission sets"
  type = map(object({
    account_id       = string
    permission_set   = string
    principal_type   = string # USER or GROUP
    principal_name   = string # Name of user or group from test_users/test_groups
  }))
  
  default = {
    developers_dev_access = {
      account_id     = "" # Will be populated with current account
      permission_set = "DeveloperAccess"
      principal_type = "GROUP"
      principal_name = "developers"
    }
    
    testuser_readonly = {
      account_id     = "" # Will be populated with current account
      permission_set = "ReadOnlyAccess"
      principal_type = "USER"
      principal_name = "testuser"
    }
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for SSO events"
  type        = bool
  default     = true
}

variable "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs (leave empty to auto-generate)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}