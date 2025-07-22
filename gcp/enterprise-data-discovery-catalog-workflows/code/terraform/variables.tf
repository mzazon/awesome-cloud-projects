# Project and environment configuration
variable "project_id" {
  description = "The ID of the Google Cloud project where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be created"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone where resources will be created"
  type        = string
  default     = "us-central1-a"
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "data-discovery"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

# Data Catalog configuration
variable "tag_templates" {
  description = "Configuration for Data Catalog tag templates"
  type = map(object({
    display_name = string
    description  = string
    fields = map(object({
      display_name = string
      type         = string
      is_required  = optional(bool, false)
      enum_values  = optional(list(string), [])
    }))
  }))
  default = {
    data_classification = {
      display_name = "Data Classification Template"
      description  = "Template for classifying data sensitivity and ownership"
      fields = {
        sensitivity = {
          display_name = "Data Sensitivity"
          type         = "ENUM"
          is_required  = true
          enum_values  = ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"]
        }
        owner = {
          display_name = "Data Owner"
          type         = "STRING"
          is_required  = true
        }
        department = {
          display_name = "Department"
          type         = "STRING"
          is_required  = false
        }
        last_updated = {
          display_name = "Last Updated"
          type         = "DATETIME"
          is_required  = false
        }
      }
    }
    data_quality = {
      display_name = "Data Quality Metrics"
      description  = "Template for tracking data quality metrics and validation status"
      fields = {
        completeness_score = {
          display_name = "Completeness Score"
          type         = "DOUBLE"
          is_required  = false
        }
        accuracy_score = {
          display_name = "Accuracy Score"
          type         = "DOUBLE"
          is_required  = false
        }
        freshness_days = {
          display_name = "Data Freshness (Days)"
          type         = "DOUBLE"
          is_required  = false
        }
        validation_date = {
          display_name = "Last Validation"
          type         = "DATETIME"
          is_required  = false
        }
      }
    }
  }
}

# Cloud Function configuration
variable "function_config" {
  description = "Configuration for the metadata extraction Cloud Function"
  type = object({
    name         = optional(string, "metadata-extractor")
    runtime      = optional(string, "python311")
    memory       = optional(string, "1Gi")
    timeout      = optional(number, 540)
    max_instances = optional(number, 10)
    min_instances = optional(number, 0)
  })
  default = {}
}

# Cloud Workflows configuration
variable "workflow_config" {
  description = "Configuration for the data discovery workflow"
  type = object({
    name        = optional(string, "data-discovery-workflow")
    description = optional(string, "Orchestrates automated data discovery and cataloging")
  })
  default = {}
}

# Cloud Scheduler configuration
variable "scheduler_config" {
  description = "Configuration for automated discovery scheduling"
  type = object({
    daily_schedule   = optional(string, "0 2 * * *")  # 2 AM daily
    weekly_schedule  = optional(string, "0 1 * * 0")  # 1 AM Sunday
    time_zone       = optional(string, "America/New_York")
    description     = optional(string, "Automated data discovery and cataloging")
  })
  default = {}
}

# BigQuery configuration for sample data
variable "sample_datasets" {
  description = "Configuration for sample BigQuery datasets for testing"
  type = map(object({
    description     = string
    location       = optional(string, "US")
    friendly_name  = optional(string, "")
    tables = optional(map(object({
      description = string
      schema = list(object({
        name = string
        type = string
        mode = optional(string, "NULLABLE")
      }))
    })), {})
  }))
  default = {
    customer_analytics = {
      description   = "Sample customer data for discovery testing"
      friendly_name = "Customer Analytics"
      tables = {
        transactions = {
          description = "Customer transaction history"
          schema = [
            { name = "customer_id", type = "STRING" },
            { name = "transaction_date", type = "TIMESTAMP" },
            { name = "amount", type = "FLOAT64" },
            { name = "product_category", type = "STRING" },
            { name = "payment_method", type = "STRING" }
          ]
        }
      }
    }
    hr_internal = {
      description   = "Internal employee data for testing"
      friendly_name = "HR Internal"
      tables = {
        employees = {
          description = "Employee personal information"
          schema = [
            { name = "employee_id", type = "STRING" },
            { name = "first_name", type = "STRING" },
            { name = "last_name", type = "STRING" },
            { name = "email", type = "STRING" },
            { name = "department", type = "STRING" },
            { name = "salary", type = "INTEGER" },
            { name = "hire_date", type = "DATE" }
          ]
        }
      }
    }
  }
}

# Storage configuration
variable "storage_buckets" {
  description = "Configuration for sample Cloud Storage buckets"
  type = map(object({
    location      = optional(string, "US")
    storage_class = optional(string, "STANDARD")
    description   = string
    versioning    = optional(bool, false)
    sample_files  = optional(map(string), {})
  }))
  default = {
    public_datasets = {
      description   = "Public datasets for testing discovery"
      storage_class = "STANDARD"
      sample_files = {
        "sample-public-data.txt" = "Sample public dataset content for discovery testing"
      }
    }
    confidential_reports = {
      description   = "Confidential reports for sensitivity testing"
      storage_class = "STANDARD"
      sample_files = {
        "financial-report-q4.txt" = "Confidential financial report data for classification testing"
      }
    }
  }
}

# IAM and security configuration
variable "service_account_roles" {
  description = "IAM roles to assign to the service account"
  type        = list(string)
  default = [
    "roles/datacatalog.admin",
    "roles/bigquery.dataViewer",
    "roles/storage.objectViewer",
    "roles/cloudsql.viewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ]
}

# Labels for resource organization
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "data-discovery"
    managed_by  = "terraform"
    component   = "data-catalog"
  }
}