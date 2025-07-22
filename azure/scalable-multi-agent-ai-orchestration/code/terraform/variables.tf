# ==============================================================================
# GENERAL VARIABLES
# ==============================================================================

variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
  
  validation {
    condition = can(regex("^[A-Za-z0-9 ]+$", var.location))
    error_message = "Location must be a valid Azure region name."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-multiagent-orchestration"
  
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "multiagent"
  
  validation {
    condition     = length(var.project_name) >= 1 && length(var.project_name) <= 20
    error_message = "Project name must be between 1 and 20 characters."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Purpose     = "multi-agent-orchestration"
    Environment = "demo"
    ManagedBy   = "terraform"
  }
}

# ==============================================================================
# AZURE AI FOUNDRY VARIABLES
# ==============================================================================

variable "ai_foundry_sku" {
  description = "SKU for Azure AI Foundry (Cognitive Services)"
  type        = string
  default     = "S0"
  
  validation {
    condition     = contains(["F0", "S0", "S1", "S2", "S3"], var.ai_foundry_sku)
    error_message = "AI Foundry SKU must be one of: F0, S0, S1, S2, S3."
  }
}

variable "ai_foundry_kind" {
  description = "Kind of Azure AI Foundry service"
  type        = string
  default     = "AIServices"
  
  validation {
    condition     = contains(["AIServices", "CognitiveServices"], var.ai_foundry_kind)
    error_message = "AI Foundry kind must be AIServices or CognitiveServices."
  }
}

variable "gpt_model_deployment" {
  description = "Configuration for GPT model deployment"
  type = object({
    model_name    = string
    model_version = string
    model_format  = string
    sku_name      = string
    sku_capacity  = number
  })
  default = {
    model_name    = "gpt-4"
    model_version = "0613"
    model_format  = "OpenAI"
    sku_name      = "Standard"
    sku_capacity  = 10
  }
}

# ==============================================================================
# STORAGE VARIABLES
# ==============================================================================

variable "storage_account_tier" {
  description = "Performance tier for storage account"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be Standard or Premium."
  }
}

variable "storage_account_replication" {
  description = "Replication type for storage account"
  type        = string
  default     = "LRS"
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication)
    error_message = "Storage replication must be LRS, GRS, RAGRS, or ZRS."
  }
}

# ==============================================================================
# COSMOS DB VARIABLES
# ==============================================================================

variable "cosmos_db_offer_type" {
  description = "Offer type for Cosmos DB"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = var.cosmos_db_offer_type == "Standard"
    error_message = "Cosmos DB offer type must be Standard."
  }
}

variable "cosmos_db_kind" {
  description = "Kind of Cosmos DB account"
  type        = string
  default     = "GlobalDocumentDB"
  
  validation {
    condition     = contains(["GlobalDocumentDB", "MongoDB", "Parse"], var.cosmos_db_kind)
    error_message = "Cosmos DB kind must be GlobalDocumentDB, MongoDB, or Parse."
  }
}

variable "cosmos_db_consistency_policy" {
  description = "Consistency policy for Cosmos DB"
  type = object({
    consistency_level       = string
    max_interval_in_seconds = number
    max_staleness_prefix    = number
  })
  default = {
    consistency_level       = "Session"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }
}

variable "cosmos_db_enable_automatic_failover" {
  description = "Enable automatic failover for Cosmos DB"
  type        = bool
  default     = true
}

# ==============================================================================
# CONTAINER APPS VARIABLES
# ==============================================================================

variable "container_apps_environment_name" {
  description = "Name of the Container Apps environment"
  type        = string
  default     = ""
}

variable "container_apps_log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace for Container Apps"
  type        = string
  default     = ""
}

variable "container_apps_workload_profile" {
  description = "Workload profile configuration for Container Apps"
  type = object({
    name                = string
    workload_profile_type = string
    minimum_count       = number
    maximum_count       = number
  })
  default = {
    name                = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count       = 0
    maximum_count       = 1000
  }
}

# ==============================================================================
# AGENT CONFIGURATION VARIABLES
# ==============================================================================

variable "coordinator_agent_config" {
  description = "Configuration for the coordinator agent"
  type = object({
    image         = string
    cpu           = number
    memory        = string
    min_replicas  = number
    max_replicas  = number
    target_port   = number
    ingress_type  = string
  })
  default = {
    image         = "mcr.microsoft.com/azure-cognitive-services/language/agent-coordinator:latest"
    cpu           = 1.0
    memory        = "2.0Gi"
    min_replicas  = 1
    max_replicas  = 5
    target_port   = 8080
    ingress_type  = "external"
  }
}

variable "document_agent_config" {
  description = "Configuration for the document processing agent"
  type = object({
    image         = string
    cpu           = number
    memory        = string
    min_replicas  = number
    max_replicas  = number
    target_port   = number
    ingress_type  = string
  })
  default = {
    image         = "mcr.microsoft.com/azure-cognitive-services/document-intelligence/agent:latest"
    cpu           = 2.0
    memory        = "4.0Gi"
    min_replicas  = 0
    max_replicas  = 10
    target_port   = 8080
    ingress_type  = "internal"
  }
}

variable "data_analysis_agent_config" {
  description = "Configuration for the data analysis agent"
  type = object({
    image         = string
    cpu           = number
    memory        = string
    min_replicas  = number
    max_replicas  = number
    target_port   = number
    ingress_type  = string
  })
  default = {
    image         = "mcr.microsoft.com/azure-cognitive-services/data-analysis/agent:latest"
    cpu           = 4.0
    memory        = "8.0Gi"
    min_replicas  = 0
    max_replicas  = 8
    target_port   = 8080
    ingress_type  = "internal"
  }
}

variable "customer_service_agent_config" {
  description = "Configuration for the customer service agent"
  type = object({
    image         = string
    cpu           = number
    memory        = string
    min_replicas  = number
    max_replicas  = number
    target_port   = number
    ingress_type  = string
  })
  default = {
    image         = "mcr.microsoft.com/azure-cognitive-services/language/customer-service-agent:latest"
    cpu           = 1.0
    memory        = "2.0Gi"
    min_replicas  = 1
    max_replicas  = 15
    target_port   = 8080
    ingress_type  = "internal"
  }
}

variable "api_gateway_config" {
  description = "Configuration for the API gateway"
  type = object({
    image         = string
    cpu           = number
    memory        = string
    min_replicas  = number
    max_replicas  = number
    target_port   = number
    ingress_type  = string
  })
  default = {
    image         = "mcr.microsoft.com/azure-api-management/gateway:latest"
    cpu           = 0.5
    memory        = "1.0Gi"
    min_replicas  = 2
    max_replicas  = 10
    target_port   = 8080
    ingress_type  = "external"
  }
}

# ==============================================================================
# EVENT GRID VARIABLES
# ==============================================================================

variable "event_grid_topic_name" {
  description = "Name of the Event Grid topic"
  type        = string
  default     = ""
}

variable "event_grid_input_schema" {
  description = "Input schema for Event Grid topic"
  type        = string
  default     = "EventGridSchema"
  
  validation {
    condition     = contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomInputSchema"], var.event_grid_input_schema)
    error_message = "Event Grid input schema must be EventGridSchema, CloudEventSchemaV1_0, or CustomInputSchema."
  }
}

variable "event_grid_subscriptions" {
  description = "Configuration for Event Grid subscriptions"
  type = map(object({
    included_event_types = list(string)
    subject_filter       = string
    max_delivery_attempts = number
    event_ttl            = number
    endpoint_type        = string
  }))
  default = {
    document_agent = {
      included_event_types = ["DocumentProcessing.Requested"]
      subject_filter       = "multi-agent"
      max_delivery_attempts = 3
      event_ttl            = 1440
      endpoint_type        = "webhook"
    }
    data_analysis = {
      included_event_types = ["DataAnalysis.Requested", "DataProcessing.Completed"]
      subject_filter       = "multi-agent"
      max_delivery_attempts = 3
      event_ttl            = 1440
      endpoint_type        = "webhook"
    }
    customer_service = {
      included_event_types = ["CustomerService.Requested", "CustomerInquiry.Received"]
      subject_filter       = "multi-agent"
      max_delivery_attempts = 3
      event_ttl            = 1440
      endpoint_type        = "webhook"
    }
    workflow_orchestration = {
      included_event_types = ["Workflow.Started", "Agent.Completed", "Agent.Failed"]
      subject_filter       = "multi-agent"
      max_delivery_attempts = 3
      event_ttl            = 1440
      endpoint_type        = "webhook"
    }
    health_monitoring = {
      included_event_types = ["Agent.HealthCheck", "Agent.Error"]
      subject_filter       = "multi-agent"
      max_delivery_attempts = 5
      event_ttl            = 1440
      endpoint_type        = "webhook"
    }
  }
}

# ==============================================================================
# MONITORING VARIABLES
# ==============================================================================

variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
  default     = ""
}

variable "application_insights_type" {
  description = "Type of Application Insights instance"
  type        = string
  default     = "web"
  
  validation {
    condition     = contains(["web", "other"], var.application_insights_type)
    error_message = "Application Insights type must be web or other."
  }
}

variable "log_analytics_workspace_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
  
  validation {
    condition     = contains(["Free", "PerNode", "Premium", "Standard", "Standalone", "Unlimited", "CapacityReservation", "PerGB2018"], var.log_analytics_workspace_sku)
    error_message = "Log Analytics workspace SKU must be a valid pricing tier."
  }
}

variable "log_analytics_workspace_retention" {
  description = "Retention period for Log Analytics workspace in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_workspace_retention >= 30 && var.log_analytics_workspace_retention <= 730
    error_message = "Log Analytics workspace retention must be between 30 and 730 days."
  }
}

# ==============================================================================
# SECURITY VARIABLES
# ==============================================================================

variable "key_vault_name" {
  description = "Name of the Key Vault"
  type        = string
  default     = ""
}

variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "key_vault_enabled_for_deployment" {
  description = "Enable Key Vault for Azure deployment"
  type        = bool
  default     = false
}

variable "key_vault_enabled_for_disk_encryption" {
  description = "Enable Key Vault for disk encryption"
  type        = bool
  default     = false
}

variable "key_vault_enabled_for_template_deployment" {
  description = "Enable Key Vault for template deployment"
  type        = bool
  default     = false
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = false
}

variable "key_vault_soft_delete_retention_days" {
  description = "Soft delete retention period for Key Vault in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention must be between 7 and 90 days."
  }
}

# ==============================================================================
# CONTAINER REGISTRY VARIABLES
# ==============================================================================

variable "container_registry_name" {
  description = "Name of the Container Registry"
  type        = string
  default     = ""
}

variable "container_registry_sku" {
  description = "SKU for Container Registry"
  type        = string
  default     = "Basic"
  
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "Container Registry SKU must be Basic, Standard, or Premium."
  }
}

variable "container_registry_admin_enabled" {
  description = "Enable admin user for Container Registry"
  type        = bool
  default     = false
}