# Variable Definitions for Apps Script Calendar Automation
# This file defines all configurable parameters for the automated event creation solution

# Project Configuration Variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.zone))
    error_message = "Zone must be a valid GCP zone identifier."
  }
}

# Resource Naming and Tagging Variables
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "event-automation"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
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

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "event-automation"
    component   = "apps-script-calendar"
    managed-by  = "terraform"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Google Apps Script Configuration Variables
variable "apps_script_title" {
  description = "Title for the Google Apps Script project"
  type        = string
  default     = "Event Automation Script"
  validation {
    condition     = length(var.apps_script_title) > 0 && length(var.apps_script_title) <= 100
    error_message = "Apps Script title must be between 1 and 100 characters."
  }
}

variable "apps_script_timezone" {
  description = "Timezone for the Apps Script project"
  type        = string
  default     = "America/New_York"
}

variable "trigger_hour" {
  description = "Hour of day (0-23) when the automation trigger should run"
  type        = number
  default     = 8
  validation {
    condition     = var.trigger_hour >= 0 && var.trigger_hour <= 23
    error_message = "Trigger hour must be between 0 and 23."
  }
}

# Google Drive and Sheets Configuration
variable "sheet_name" {
  description = "Name for the Google Sheet containing event data"
  type        = string
  default     = "Event Schedule"
  validation {
    condition     = length(var.sheet_name) > 0 && length(var.sheet_name) <= 100
    error_message = "Sheet name must be between 1 and 100 characters."
  }
}

variable "drive_folder_name" {
  description = "Name for the Google Drive folder to organize automation files"
  type        = string
  default     = "Event Automation Resources"
  validation {
    condition     = length(var.drive_folder_name) > 0 && length(var.drive_folder_name) <= 100
    error_message = "Drive folder name must be between 1 and 100 characters."
  }
}

# API Configuration Variables
variable "enable_apis" {
  description = "List of Google APIs to enable for the project"
  type        = list(string)
  default = [
    "script.googleapis.com",
    "calendar-json.googleapis.com",
    "sheets.googleapis.com",
    "drive.googleapis.com",
    "gmail.googleapis.com",
    "admin.googleapis.com"
  ]
}

# Security and Access Variables
variable "oauth_scopes" {
  description = "OAuth scopes required for the Apps Script project"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/script.external_request"
  ]
}

variable "service_account_roles" {
  description = "IAM roles to assign to the service account for automation"
  type        = list(string)
  default = [
    "roles/script.developer",
    "roles/calendar.editor",
    "roles/drive.editor",
    "roles/sheets.editor"
  ]
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for automation notifications (leave empty to use default user email)"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Performance and Limits Configuration
variable "execution_timeout_seconds" {
  description = "Maximum execution time for Apps Script functions (in seconds)"
  type        = number
  default     = 300
  validation {
    condition     = var.execution_timeout_seconds >= 60 && var.execution_timeout_seconds <= 3600
    error_message = "Execution timeout must be between 60 and 3600 seconds."
  }
}

variable "max_events_per_execution" {
  description = "Maximum number of events to process in a single execution"
  type        = number
  default     = 50
  validation {
    condition     = var.max_events_per_execution >= 1 && var.max_events_per_execution <= 100
    error_message = "Max events per execution must be between 1 and 100."
  }
}

# Development and Testing Variables
variable "enable_debug_logging" {
  description = "Enable detailed debug logging in Apps Script"
  type        = bool
  default     = false
}

variable "create_sample_data" {
  description = "Create sample event data in the Google Sheet for testing"
  type        = bool
  default     = true
}

variable "dry_run_mode" {
  description = "Enable dry-run mode that logs actions without creating calendar events"
  type        = bool
  default     = false
}