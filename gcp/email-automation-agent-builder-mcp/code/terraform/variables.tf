# Variables for GCP Email Automation with Vertex AI Agent Builder and MCP
# This file defines all input variables for the Terraform configuration

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Cloud Functions 2nd gen."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout in seconds for Cloud Functions execution"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (e.g., '256Mi', '512Mi', '1Gi')"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "max_function_instances" {
  description = "Maximum number of function instances that can run concurrently"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 3000
    error_message = "Maximum function instances must be between 1 and 3000."
  }
}

variable "min_function_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_function_instances >= 0 && var.min_function_instances <= 1000
    error_message = "Minimum function instances must be between 0 and 1000."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "The maximum time after receiving a message before acknowledgment deadline"
  type        = number
  default     = 300
  
  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Pub/Sub ack deadline must be between 10 and 600 seconds."
  }
}

variable "storage_lifecycle_age_days" {
  description = "Number of days after which objects in storage bucket will be deleted"
  type        = number
  default     = 30
  
  validation {
    condition     = var.storage_lifecycle_age_days >= 1 && var.storage_lifecycle_age_days <= 365
    error_message = "Storage lifecycle age must be between 1 and 365 days."
  }
}

variable "enable_function_versioning" {
  description = "Enable versioning for Cloud Storage bucket containing function source code"
  type        = bool
  default     = true
}

variable "enable_logging_sink" {
  description = "Enable Cloud Logging sink for email automation monitoring"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values can contain lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "gmail_api_service_account" {
  description = "Gmail API service account for Pub/Sub publishing permissions"
  type        = string
  default     = "gmail-api-push@system.gserviceaccount.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.gmail_api_service_account))
    error_message = "Gmail API service account must be a valid email address."
  }
}

variable "mcp_server_name" {
  description = "Name for the MCP (Model Context Protocol) server configuration"
  type        = string
  default     = "email-automation-mcp"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.mcp_server_name))
    error_message = "MCP server name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vertex_ai_agent_instructions" {
  description = "Instructions for the Vertex AI Agent for email processing"
  type        = string
  default     = <<-EOT
    You are an intelligent email automation assistant that helps process customer emails.
    Your responsibilities include:
    1. Categorizing emails by urgency and type (billing, technical, general support)
    2. Extracting key information and intent from email content
    3. Accessing relevant customer data through MCP tools
    4. Generating appropriate response drafts based on email context
    5. Escalating complex issues to human agents when necessary
    
    Always maintain a professional tone and ensure accuracy in customer information.
    For urgent emails containing words like 'urgent', 'asap', 'critical', or 'emergency', 
    categorize as high priority and suggest immediate escalation.
  EOT
}

variable "enable_public_function_access" {
  description = "Allow unauthenticated access to Cloud Functions for webhook processing"
  type        = bool
  default     = true
}

variable "pubsub_retry_minimum_backoff" {
  description = "Minimum backoff time for Pub/Sub message retry policy"
  type        = string
  default     = "10s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_retry_minimum_backoff))
    error_message = "Retry minimum backoff must be in seconds format (e.g., '10s')."
  }
}

variable "pubsub_retry_maximum_backoff" {
  description = "Maximum backoff time for Pub/Sub message retry policy"
  type        = string
  default     = "600s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_retry_maximum_backoff))
    error_message = "Retry maximum backoff must be in seconds format (e.g., '600s')."
  }
}

variable "enable_secret_manager_replication" {
  description = "Enable automatic replication for Secret Manager secrets"
  type        = bool
  default     = true
}

variable "function_cpu" {
  description = "CPU allocation for Cloud Functions (e.g., '1', '2')"
  type        = string
  default     = "1"
  
  validation {
    condition = contains([
      "1", "2", "4", "8"
    ], var.function_cpu)
    error_message = "Function CPU must be one of: 1, 2, 4, 8."
  }
}

variable "workflow_function_memory" {
  description = "Memory allocation for the email workflow orchestration function"
  type        = string
  default     = "1Gi"
  
  validation {
    condition = contains([
      "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.workflow_function_memory)
    error_message = "Workflow function memory must be one of: 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "workflow_function_timeout" {
  description = "Timeout in seconds for the email workflow orchestration function"
  type        = number
  default     = 120
  
  validation {
    condition     = var.workflow_function_timeout >= 60 && var.workflow_function_timeout <= 540
    error_message = "Workflow function timeout must be between 60 and 540 seconds."
  }
}