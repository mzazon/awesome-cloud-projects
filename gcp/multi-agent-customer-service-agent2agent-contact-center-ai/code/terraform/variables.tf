# =============================================================================
# TERRAFORM VARIABLES FOR MULTI-AGENT CUSTOMER SERVICE
# =============================================================================
# Input variables for configuring the multi-agent customer service system
# with Contact Center AI Platform, Vertex AI, and Cloud Functions

# =============================================================================
# PROJECT AND LOCATION CONFIGURATION
# =============================================================================

variable "project_id" {
  description = "Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]){4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports AI Platform and Cloud Functions."
  }
}

variable "zone" {
  description = "Google Cloud zone within the specified region"
  type        = string
  default     = ""
  
  validation {
    condition     = var.zone == "" || can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be empty or a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# =============================================================================
# RESOURCE NAMING AND ORGANIZATION
# =============================================================================

variable "name_prefix" {
  description = "Prefix for resource names. If empty, a random prefix will be generated"
  type        = string
  default     = ""
  
  validation {
    condition     = var.name_prefix == "" || can(regex("^[a-z][a-z0-9-]{2,15}$", var.name_prefix))
    error_message = "Name prefix must be 3-16 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment designation (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# =============================================================================
# FIRESTORE DATABASE CONFIGURATION
# =============================================================================

variable "firestore_location" {
  description = "Firestore database location. If empty, uses the region variable"
  type        = string
  default     = ""
  
  validation {
    condition = var.firestore_location == "" || contains([
      "us-central", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be empty or a valid multi-region location."
  }
}

variable "enable_firestore_backups" {
  description = "Enable automatic backups for Firestore database"
  type        = bool
  default     = true
}

# =============================================================================
# VERTEX AI CONFIGURATION
# =============================================================================

variable "vertex_ai_dataset_name" {
  description = "Display name for the Vertex AI dataset"
  type        = string
  default     = "multi-agent-customer-service"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9\\s\\-_]{2,127}$", var.vertex_ai_dataset_name))
    error_message = "Dataset name must be 3-128 characters, start with a letter, and contain only letters, numbers, spaces, hyphens, and underscores."
  }
}

variable "vertex_ai_model_location" {
  description = "Location for Vertex AI models. If empty, uses the region variable"
  type        = string
  default     = ""
}

# =============================================================================
# CLOUD FUNCTIONS CONFIGURATION
# =============================================================================

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "broker_memory_mb" {
  description = "Memory allocation for Message Broker function in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192], var.broker_memory_mb)
    error_message = "Broker memory must be one of: 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "broker_timeout_seconds" {
  description = "Timeout for Message Broker function in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.broker_timeout_seconds >= 60 && var.broker_timeout_seconds <= 540
    error_message = "Broker timeout must be between 60 and 540 seconds."
  }
}

variable "python_runtime" {
  description = "Python runtime version for Cloud Functions"
  type        = string
  default     = "python311"
  
  validation {
    condition     = contains(["python38", "python39", "python310", "python311"], var.python_runtime)
    error_message = "Python runtime must be one of: python38, python39, python310, python311."
  }
}

# =============================================================================
# SECURITY AND ACCESS CONTROL
# =============================================================================

variable "allow_public_access" {
  description = "Allow public access to Cloud Functions (for testing only)"
  type        = bool
  default     = true
  
  validation {
    condition     = var.allow_public_access == true || var.allow_public_access == false
    error_message = "Allow public access must be a boolean value."
  }
}

variable "service_account_email" {
  description = "Custom service account email for Cloud Functions. If empty, a new service account will be created"
  type        = string
  default     = ""
  
  validation {
    condition     = var.service_account_email == "" || can(regex("^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$", var.service_account_email))
    error_message = "Service account email must be empty or a valid email address."
  }
}

variable "authorized_networks" {
  description = "CIDR blocks authorized to access the functions (when public access is disabled)"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for cidr in var.authorized_networks : can(cidrhost(cidr, 0))])
    error_message = "All authorized networks must be valid CIDR blocks."
  }
}

# =============================================================================
# BIGQUERY ANALYTICS CONFIGURATION
# =============================================================================

variable "analytics_dataset_location" {
  description = "BigQuery dataset location for analytics. If empty, uses the region variable"
  type        = string
  default     = ""
}

variable "analytics_admin_email" {
  description = "Email address of the analytics administrator"
  type        = string
  default     = ""
  
  validation {
    condition     = var.analytics_admin_email == "" || can(regex("^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$", var.analytics_admin_email))
    error_message = "Analytics admin email must be empty or a valid email address."
  }
}

variable "organization_domain" {
  description = "Organization domain for BigQuery access control"
  type        = string
  default     = ""
  
  validation {
    condition     = var.organization_domain == "" || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.organization_domain))
    error_message = "Organization domain must be empty or a valid domain name."
  }
}

variable "data_retention_days" {
  description = "Data retention period in days for conversation logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.data_retention_days >= 1 && var.data_retention_days <= 365
    error_message = "Data retention days must be between 1 and 365."
  }
}

# =============================================================================
# CONTACT CENTER AI PLATFORM CONFIGURATION
# =============================================================================

variable "ccai_display_name" {
  description = "Display name for the Contact Center AI Platform instance"
  type        = string
  default     = "Multi-Agent Customer Service"
  
  validation {
    condition     = length(var.ccai_display_name) >= 3 && length(var.ccai_display_name) <= 64
    error_message = "CCAI display name must be between 3 and 64 characters."
  }
}

variable "ccai_description" {
  description = "Description for the Contact Center AI Platform instance"
  type        = string
  default     = "AI-powered customer service with specialized agent collaboration"
  
  validation {
    condition     = length(var.ccai_description) <= 256
    error_message = "CCAI description must be 256 characters or less."
  }
}

variable "supported_languages" {
  description = "List of supported language codes for the CCAI platform"
  type        = list(string)
  default     = ["en"]
  
  validation {
    condition     = length(var.supported_languages) > 0 && alltrue([for lang in var.supported_languages : length(lang) == 2])
    error_message = "At least one language must be specified, and all language codes must be 2 characters."
  }
}

variable "time_zone" {
  description = "Time zone for the Contact Center AI Platform"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z_/]*$", var.time_zone))
    error_message = "Time zone must be a valid IANA time zone identifier."
  }
}

variable "enable_voice_support" {
  description = "Enable voice support features in CCAI platform"
  type        = bool
  default     = true
}

variable "enable_chat_support" {
  description = "Enable chat support features in CCAI platform"
  type        = bool
  default     = true
}

variable "enable_email_support" {
  description = "Enable email support features in CCAI platform"
  type        = bool
  default     = true
}

# =============================================================================
# MONITORING AND LOGGING CONFIGURATION
# =============================================================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and logging for all components"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for Cloud Functions (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}

variable "enable_alerting" {
  description = "Enable alerting for function errors and performance issues"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for receiving alerts"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alert_email == "" || can(regex("^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$", var.alert_email))
    error_message = "Alert email must be empty or a valid email address."
  }
}

# =============================================================================
# COST OPTIMIZATION CONFIGURATION
# =============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features like lifecycle policies"
  type        = bool
  default     = true
}

variable "storage_lifecycle_days" {
  description = "Number of days after which storage objects are deleted"
  type        = number
  default     = 90
  
  validation {
    condition     = var.storage_lifecycle_days >= 1 && var.storage_lifecycle_days <= 365
    error_message = "Storage lifecycle days must be between 1 and 365."
  }
}

variable "enable_preemptible_instances" {
  description = "Use preemptible instances where possible for cost savings"
  type        = bool
  default     = false
}

# =============================================================================
# AGENT CONFIGURATION
# =============================================================================

variable "agent_specializations" {
  description = "Configuration for specialized agents"
  type = map(object({
    capabilities    = list(string)
    expertise_level = string
    memory_mb      = optional(number, 256)
    timeout_seconds = optional(number, 60)
  }))
  default = {
    billing = {
      capabilities    = ["payments", "invoices", "refunds", "subscriptions"]
      expertise_level = "expert"
      memory_mb      = 256
      timeout_seconds = 60
    }
    technical = {
      capabilities    = ["troubleshooting", "installations", "configurations", "diagnostics"]
      expertise_level = "expert"
      memory_mb      = 256
      timeout_seconds = 60
    }
    sales = {
      capabilities    = ["product_info", "pricing", "demos", "upgrades"]
      expertise_level = "expert"
      memory_mb      = 256
      timeout_seconds = 60
    }
  }
  
  validation {
    condition = alltrue([
      for agent_name, config in var.agent_specializations : 
      contains(["expert", "intermediate", "basic"], config.expertise_level)
    ])
    error_message = "Agent expertise level must be one of: expert, intermediate, basic."
  }
  
  validation {
    condition = alltrue([
      for agent_name, config in var.agent_specializations : 
      length(config.capabilities) > 0
    ])
    error_message = "Each agent must have at least one capability defined."
  }
}

variable "routing_keywords" {
  description = "Keywords for intelligent agent routing"
  type = map(list(string))
  default = {
    billing   = ["bill", "payment", "invoice", "charge", "refund", "subscription"]
    technical = ["not working", "error", "install", "setup", "configure", "trouble"]
    sales     = ["price", "purchase", "demo", "upgrade", "plan", "features"]
  }
  
  validation {
    condition = alltrue([
      for agent_type, keywords in var.routing_keywords : 
      length(keywords) > 0
    ])
    error_message = "Each agent type must have at least one routing keyword."
  }
}

# =============================================================================
# FEATURE FLAGS
# =============================================================================

variable "enable_a2a_protocol" {
  description = "Enable Agent2Agent protocol for inter-agent communication"
  type        = bool
  default     = true
}

variable "enable_conversation_history" {
  description = "Enable conversation history tracking and context preservation"
  type        = bool
  default     = true
}

variable "enable_sentiment_analysis" {
  description = "Enable sentiment analysis for customer interactions"
  type        = bool
  default     = false
}

variable "enable_real_time_analytics" {
  description = "Enable real-time analytics and dashboards"
  type        = bool
  default     = true
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "custom_domains" {
  description = "Custom domains for Cloud Functions (optional)"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for name, domain in var.custom_domains : 
      can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", domain))
    ])
    error_message = "All custom domains must be valid domain names."
  }
}

variable "vpc_connector" {
  description = "VPC connector for Cloud Functions private network access"
  type        = string
  default     = ""
  
  validation {
    condition     = var.vpc_connector == "" || can(regex("^projects/.+/locations/.+/connectors/.+$", var.vpc_connector))
    error_message = "VPC connector must be empty or in the format: projects/PROJECT/locations/REGION/connectors/CONNECTOR."
  }
}

variable "max_instances" {
  description = "Maximum number of instances for each Cloud Function"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

variable "min_instances" {
  description = "Minimum number of instances for each Cloud Function (for reduced cold starts)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}