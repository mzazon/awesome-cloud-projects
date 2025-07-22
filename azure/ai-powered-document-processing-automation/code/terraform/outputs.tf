# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Azure OpenAI Service Outputs
output "openai_account_name" {
  description = "Name of the Azure OpenAI Service account"
  value       = azurerm_cognitive_account.openai.name
}

output "openai_endpoint" {
  description = "Endpoint URL for the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_account_id" {
  description = "Resource ID of the Azure OpenAI Service account"
  value       = azurerm_cognitive_account.openai.id
}

output "openai_custom_domain" {
  description = "Custom domain for the Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.custom_domain
}

output "gpt4_deployment_name" {
  description = "Name of the GPT-4 model deployment"
  value       = azurerm_cognitive_deployment.gpt4.name
}

output "gpt4_deployment_id" {
  description = "Resource ID of the GPT-4 model deployment"
  value       = azurerm_cognitive_deployment.gpt4.id
}

# Azure OpenAI API Key (marked as sensitive)
output "openai_api_key" {
  description = "Primary API key for Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}

output "openai_secondary_api_key" {
  description = "Secondary API key for Azure OpenAI Service"
  value       = azurerm_cognitive_account.openai.secondary_access_key
  sensitive   = true
}

# Service Bus Outputs
output "servicebus_namespace_name" {
  description = "Name of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.name
}

output "servicebus_namespace_id" {
  description = "Resource ID of the Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.id
}

output "servicebus_connection_string" {
  description = "Primary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "servicebus_secondary_connection_string" {
  description = "Secondary connection string for Service Bus namespace"
  value       = azurerm_servicebus_namespace.main.default_secondary_connection_string
  sensitive   = true
}

output "processing_queue_name" {
  description = "Name of the processing queue"
  value       = azurerm_servicebus_queue.processing.name
}

output "processing_queue_id" {
  description = "Resource ID of the processing queue"
  value       = azurerm_servicebus_queue.processing.id
}

output "results_topic_name" {
  description = "Name of the results topic"
  value       = azurerm_servicebus_topic.results.name
}

output "results_topic_id" {
  description = "Resource ID of the results topic"
  value       = azurerm_servicebus_topic.results.id
}

output "notification_subscription_name" {
  description = "Name of the notification subscription"
  value       = azurerm_servicebus_subscription.notifications.name
}

output "notification_subscription_id" {
  description = "Resource ID of the notification subscription"
  value       = azurerm_servicebus_subscription.notifications.id
}

# Container Registry Outputs
output "container_registry_name" {
  description = "Name of the Container Registry"
  value       = azurerm_container_registry.main.name
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_admin_username" {
  description = "Admin username for Container Registry"
  value       = azurerm_container_registry.main.admin_username
}

output "container_registry_admin_password" {
  description = "Admin password for Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "container_registry_id" {
  description = "Resource ID of the Container Registry"
  value       = azurerm_container_registry.main.id
}

# Container Apps Environment Outputs
output "container_apps_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_apps_environment_id" {
  description = "Resource ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_apps_environment_default_domain" {
  description = "Default domain of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "container_apps_environment_static_ip" {
  description = "Static IP address of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.static_ip_address
}

# Container Apps Jobs Outputs
output "document_processor_job_name" {
  description = "Name of the document processor job"
  value       = azurerm_container_app_job.document_processor.name
}

output "document_processor_job_id" {
  description = "Resource ID of the document processor job"
  value       = azurerm_container_app_job.document_processor.id
}

output "notification_service_job_name" {
  description = "Name of the notification service job"
  value       = azurerm_container_app_job.notification_service.name
}

output "notification_service_job_id" {
  description = "Resource ID of the notification service job"
  value       = azurerm_container_app_job.notification_service.id
}

# Managed Identity Outputs
output "container_apps_identity_principal_id" {
  description = "Principal ID of the Container Apps managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_user_assigned_identity.container_apps[0].principal_id : null
}

output "container_apps_identity_client_id" {
  description = "Client ID of the Container Apps managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_user_assigned_identity.container_apps[0].client_id : null
}

output "container_apps_identity_id" {
  description = "Resource ID of the Container Apps managed identity"
  value       = var.enable_system_assigned_identity ? azurerm_user_assigned_identity.container_apps[0].id : null
}

# Monitoring Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_primary_shared_key" {
  description = "Primary shared key for Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.primary_shared_key
  sensitive   = true
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
}

# Dashboard Outputs
output "dashboard_name" {
  description = "Name of the monitoring dashboard"
  value       = var.enable_dashboard ? azurerm_portal_dashboard.main[0].name : null
}

output "dashboard_id" {
  description = "Resource ID of the monitoring dashboard"
  value       = var.enable_dashboard ? azurerm_portal_dashboard.main[0].id : null
}

# Configuration and Connection Information
output "deployment_summary" {
  description = "Summary of the deployed resources and configuration"
  value = {
    resource_group = {
      name     = azurerm_resource_group.main.name
      location = azurerm_resource_group.main.location
    }
    openai = {
      account_name     = azurerm_cognitive_account.openai.name
      endpoint         = azurerm_cognitive_account.openai.endpoint
      custom_domain    = azurerm_cognitive_account.openai.custom_domain
      gpt4_deployment  = azurerm_cognitive_deployment.gpt4.name
    }
    service_bus = {
      namespace_name        = azurerm_servicebus_namespace.main.name
      processing_queue      = azurerm_servicebus_queue.processing.name
      results_topic         = azurerm_servicebus_topic.results.name
      notification_subscription = azurerm_servicebus_subscription.notifications.name
    }
    container_registry = {
      name         = azurerm_container_registry.main.name
      login_server = azurerm_container_registry.main.login_server
    }
    container_apps = {
      environment_name        = azurerm_container_app_environment.main.name
      document_processor_job  = azurerm_container_app_job.document_processor.name
      notification_service_job = azurerm_container_app_job.notification_service.name
    }
    monitoring = {
      log_analytics_workspace = azurerm_log_analytics_workspace.main.name
      application_insights     = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
      dashboard               = var.enable_dashboard ? azurerm_portal_dashboard.main[0].name : null
    }
  }
}

# Environment Variables for Container Jobs
output "container_job_environment_variables" {
  description = "Environment variables needed for container jobs"
  value = {
    OPENAI_ENDPOINT         = azurerm_cognitive_account.openai.endpoint
    PROCESSING_QUEUE_NAME   = azurerm_servicebus_queue.processing.name
    RESULTS_TOPIC_NAME      = azurerm_servicebus_topic.results.name
    NOTIFICATION_SUBSCRIPTION_NAME = azurerm_servicebus_subscription.notifications.name
    CONTAINER_REGISTRY_URL  = azurerm_container_registry.main.login_server
  }
}

# Connection Strings and Keys (for manual setup if needed)
output "connection_information" {
  description = "Connection information for services"
  value = {
    openai_endpoint    = azurerm_cognitive_account.openai.endpoint
    servicebus_namespace = azurerm_servicebus_namespace.main.name
    container_registry = azurerm_container_registry.main.login_server
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.workspace_id
  }
  sensitive = false
}

# Random suffix used for unique naming
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}