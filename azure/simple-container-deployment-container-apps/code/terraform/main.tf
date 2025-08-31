# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Use provided suffix or generated one
locals {
  suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix.result
  
  # Resource naming with defaults
  resource_group_name           = var.resource_group_name != "" ? var.resource_group_name : "rg-containerapp-demo-${local.suffix}"
  container_apps_environment    = var.container_apps_environment_name != "" ? var.container_apps_environment_name : "env-demo-${local.suffix}"
  log_analytics_workspace_name  = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-demo-${local.suffix}"
  container_app_name           = var.container_app_name != "" ? var.container_app_name : "hello-app-${local.suffix}"
  
  # Merge default tags with user-provided tags
  common_tags = merge(var.tags, {
    deployment-method = "terraform"
    managed-by       = "terraform"
    creation-date    = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Resource Group for organizing all Container Apps resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for Container Apps monitoring and observability
# Container Apps requires Log Analytics for application insights and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Standard retention for demo/development workloads
  retention_in_days = 30
  sku              = "PerGB2018"
  
  tags = merge(local.common_tags, {
    component = "monitoring"
    purpose   = "container-apps-logs"
  })
}

# Container Apps Environment - provides secure boundary and shared resources
# The environment includes compute resources, networking, and observability configuration
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_apps_environment
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  tags = merge(local.common_tags, {
    component = "container-platform"
    purpose   = "serverless-container-hosting"
  })
}

# Container App - deploys the containerized application with automatic scaling
# This resource creates the actual running application with ingress and scaling configuration
resource "azurerm_container_app" "main" {
  name                         = local.container_app_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  
  # Template defines the application specification
  template {
    # Container configuration specifying the application image and resources
    container {
      name   = "hello-app"
      image  = var.container_image
      cpu    = var.cpu_requests
      memory = var.memory_requests
      
      # Environment variables can be added here as needed
      # env {
      #   name  = "ENV_VAR_NAME"
      #   value = "ENV_VAR_VALUE"
      # }
    }
    
    # Scaling configuration for automatic horizontal scaling
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
  }
  
  # Ingress configuration for external access
  dynamic "ingress" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      external_enabled           = true
      target_port               = var.container_port
      allow_insecure_connections = var.ingress_allow_insecure
      
      traffic_weight {
        latest_revision = true
        percentage      = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    component    = "application"
    purpose      = "web-application"
    image        = var.container_image
    scaling-mode = "automatic"
  })
  
  # Ensure environment is ready before creating the container app
  depends_on = [azurerm_container_app_environment.main]
}

# Output the application URL immediately after deployment for easy access
output "container_app_url" {
  description = "The URL of the deployed container application"
  value       = var.ingress_enabled ? "https://${azurerm_container_app.main.latest_revision_fqdn}" : "Ingress not enabled"
}

# Output resource group information for management
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

# Output environment information for additional container app deployments
output "container_app_environment_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.main.id
}