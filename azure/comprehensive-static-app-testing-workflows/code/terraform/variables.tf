# Variables for Azure CI/CD Testing Workflow Infrastructure
# This file defines all the customizable parameters for the deployment

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US", "West Central US",
      "Canada Central", "Canada East", "Brazil South", "UK South", "UK West",
      "North Europe", "West Europe", "France Central", "Germany West Central",
      "Switzerland North", "Norway East", "Sweden Central", "Italy North",
      "Poland Central", "Spain Central", "Australia East", "Australia Southeast",
      "East Asia", "Southeast Asia", "Japan East", "Japan West", "Korea Central",
      "Korea South", "India Central", "India South", "India West"
    ], var.location)
    error_message = "The location must be a valid Azure region."
  }
}

variable "tenant_id" {
  description = "The Azure Active Directory tenant ID"
  type        = string
  default     = null
}

variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "The name of the project (used for resource naming)"
  type        = string
  default     = "cicd-testing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "The name of the resource group (if not provided, will be generated)"
  type        = string
  default     = null
}

variable "github_repository_url" {
  description = "The GitHub repository URL for the Static Web App"
  type        = string
  default     = "https://github.com/example/example-repo"
  
  validation {
    condition     = can(regex("^https://github\\.com/[a-zA-Z0-9-]+/[a-zA-Z0-9-_.]+$", var.github_repository_url))
    error_message = "GitHub repository URL must be in the format https://github.com/username/repository."
  }
}

variable "github_branch" {
  description = "The GitHub branch to deploy from"
  type        = string
  default     = "main"
}

variable "github_app_location" {
  description = "The location of the application source code in the repository"
  type        = string
  default     = "/"
}

variable "github_output_location" {
  description = "The location of the build output in the repository"
  type        = string
  default     = "dist"
}

variable "container_registry_sku" {
  description = "The SKU for the Azure Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Whether admin user is enabled for the Container Registry"
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "The number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

variable "integration_test_timeout" {
  description = "Timeout for integration test jobs in seconds"
  type        = number
  default     = 1800
  
  validation {
    condition     = var.integration_test_timeout >= 300 && var.integration_test_timeout <= 3600
    error_message = "Integration test timeout must be between 300 and 3600 seconds."
  }
}

variable "load_test_timeout" {
  description = "Timeout for load test jobs in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.load_test_timeout >= 300 && var.load_test_timeout <= 7200
    error_message = "Load test timeout must be between 300 and 7200 seconds."
  }
}

variable "test_job_retry_limit" {
  description = "Number of retry attempts for failed test jobs"
  type        = number
  default     = 3
  
  validation {
    condition     = var.test_job_retry_limit >= 0 && var.test_job_retry_limit <= 10
    error_message = "Test job retry limit must be between 0 and 10."
  }
}

variable "test_parallelism" {
  description = "Number of parallel test executions"
  type        = number
  default     = 1
  
  validation {
    condition     = var.test_parallelism >= 1 && var.test_parallelism <= 10
    error_message = "Test parallelism must be between 1 and 10."
  }
}

variable "test_completion_count" {
  description = "Number of successful test completions required"
  type        = number
  default     = 1
  
  validation {
    condition     = var.test_completion_count >= 1 && var.test_completion_count <= 10
    error_message = "Test completion count must be between 1 and 10."
  }
}

variable "enable_load_testing" {
  description = "Whether to enable Azure Load Testing resource"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to enable comprehensive monitoring with Application Insights"
  type        = bool
  default     = true
}

variable "enable_github_actions_integration" {
  description = "Whether to create service principal for GitHub Actions integration"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Purpose     = "CI/CD Testing Workflow"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}