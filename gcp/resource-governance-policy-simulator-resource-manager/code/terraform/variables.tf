# Variables Configuration for GCP Resource Governance Solution
# This file defines all input variables for the governance infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 6 && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "organization_id" {
  description = "The GCP organization ID for implementing organization-wide policies"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "Organization ID must be a numeric string."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid GCP region name."
  }
}

variable "billing_account" {
  description = "The billing account ID for budget and cost management"
  type        = string
  default     = ""
  validation {
    condition     = var.billing_account == "" || can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "Billing account must be in format XXXXXX-XXXXXX-XXXXXX or empty string."
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

variable "team" {
  description = "Team responsible for the governance infrastructure"
  type        = string
  default     = "platform"
  validation {
    condition     = length(var.team) > 0 && length(var.team) <= 50
    error_message = "Team name must be between 1 and 50 characters."
  }
}

variable "cost_center" {
  description = "Cost center for resource allocation and billing"
  type        = string
  default     = "engineering"
  validation {
    condition     = length(var.cost_center) > 0 && length(var.cost_center) <= 50
    error_message = "Cost center must be between 1 and 50 characters."
  }
}

variable "budget_amount" {
  description = "Budget amount in USD for governance resources monitoring"
  type        = number
  default     = 100
  validation {
    condition     = var.budget_amount > 0 && var.budget_amount <= 10000
    error_message = "Budget amount must be between 1 and 10000 USD."
  }
}

variable "budget_threshold_percent" {
  description = "Budget threshold percentage for alerts (0.0 to 1.0)"
  type        = number
  default     = 0.8
  validation {
    condition     = var.budget_threshold_percent > 0 && var.budget_threshold_percent <= 1
    error_message = "Budget threshold must be between 0.01 and 1.0."
  }
}

variable "allowed_compute_regions" {
  description = "List of approved regions for compute resources"
  type        = list(string)
  default     = ["us-central1", "us-east1", "us-west1"]
  validation {
    condition     = length(var.allowed_compute_regions) > 0 && length(var.allowed_compute_regions) <= 10
    error_message = "Must specify between 1 and 10 allowed compute regions."
  }
}

variable "required_resource_labels" {
  description = "List of required labels for all resources"
  type        = list(string)
  default     = ["environment", "team", "cost-center", "project-code"]
  validation {
    condition     = length(var.required_resource_labels) > 0
    error_message = "At least one required resource label must be specified."
  }
}

variable "audit_schedule" {
  description = "Cron schedule for governance audits (Cloud Scheduler format)"
  type        = string
  default     = "0 9 * * 1"
  validation {
    condition     = can(regex("^[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+$", var.audit_schedule))
    error_message = "Audit schedule must be a valid cron expression."
  }
}

variable "cost_monitoring_schedule" {
  description = "Cron schedule for cost monitoring (Cloud Scheduler format)"
  type        = string
  default     = "0 8 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+$", var.cost_monitoring_schedule))
    error_message = "Cost monitoring schedule must be a valid cron expression."
  }
}

variable "enable_policy_simulation" {
  description = "Enable policy simulation features"
  type        = bool
  default     = true
}

variable "enable_billing_monitoring" {
  description = "Enable billing and cost monitoring features"
  type        = bool
  default     = true
}

variable "enable_asset_inventory" {
  description = "Enable Cloud Asset Inventory for compliance monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  validation {
    condition     = length(var.tags) <= 20
    error_message = "Maximum of 20 additional tags allowed."
  }
}