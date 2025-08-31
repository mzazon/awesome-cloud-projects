# Azure Simple Web Container with Container Instances and Container Registry
# This Terraform configuration deploys a complete containerized web application
# using Azure Container Registry for image storage and Azure Container Instances for hosting

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = var.random_suffix_length
  upper   = false
  special = false
  numeric = true
}

# Local values for computed resource names and configuration
locals {
  # Generate unique suffix for resource names
  suffix = var.use_random_suffix ? random_string.suffix[0].result : ""
  
  # Computed resource names with optional random suffix
  resource_group_name     = var.resource_group_name != null ? var.resource_group_name : "rg-simple-web-container${local.suffix != "" ? "-${local.suffix}" : ""}"
  container_registry_name = var.container_registry_name != null ? var.container_registry_name : "acrsimpleweb${local.suffix}"
  container_instance_name = var.container_instance_name != null ? var.container_instance_name : "aci-nginx${local.suffix != "" ? "-${local.suffix}" : ""}"
  dns_name_label         = var.dns_name_label != null ? var.dns_name_label : "aci-web${local.suffix != "" ? "-${local.suffix}" : ""}"
  
  # Full container image reference
  container_image_full = "${azurerm_container_registry.acr.login_server}/${var.container_image}:${var.container_image_tag}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    DeployedBy  = "Terraform"
    Recipe      = "simple-web-container-aci-registry"
  })
}

# Create Resource Group
# Azure Resource Group provides a logical container for related Azure resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Azure Container Registry
# ACR provides secure, private Docker registry hosting with enterprise features
resource "azurerm_container_registry" "acr" {
  name                = local.container_registry_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.container_registry_sku
  admin_enabled       = var.enable_admin_user

  # Enable public network access for simplified deployment
  public_network_access_enabled = true
  
  # Anonymous pull is disabled for security
  anonymous_pull_enabled = false

  # Configure identity for future enhancements (managed identity support)
  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.common_tags, {
    Name = "Azure Container Registry"
    SKU  = var.container_registry_sku
  })
}

# Create Azure Container Instance
# ACI provides serverless container hosting with automatic scaling and public IP
resource "azurerm_container_group" "aci" {
  name                = local.container_instance_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Container group configuration
  ip_address_type = var.ip_address_type
  dns_name_label  = var.ip_address_type == "Public" ? local.dns_name_label : null
  os_type         = var.os_type
  restart_policy  = var.restart_policy

  # Container definition with nginx web server
  container {
    name   = "nginx-web"
    image  = local.container_image_full
    cpu    = var.container_cpu
    memory = var.container_memory

    # Port configuration for web traffic
    ports {
      port     = var.container_port
      protocol = var.container_protocol
    }

    # Environment variables for container configuration
    environment_variables = {
      "NGINX_PORT" = tostring(var.container_port)
      "ENV"        = var.environment
    }

    # Liveness probe to ensure container health
    liveness_probe {
      http_get {
        path   = "/"
        port   = var.container_port
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      failure_threshold     = 3
      success_threshold     = 1
    }

    # Readiness probe to determine when container is ready to serve traffic
    readiness_probe {
      http_get {
        path   = "/"
        port   = var.container_port
        scheme = "Http"
      }
      initial_delay_seconds = 5
      period_seconds        = 10
      timeout_seconds       = 5
      failure_threshold     = 3
      success_threshold     = 1
    }
  }

  # Container registry authentication using admin credentials
  # This enables ACI to pull images from the private ACR
  image_registry_credential {
    server                    = azurerm_container_registry.acr.login_server
    username                  = azurerm_container_registry.acr.admin_username
    password                  = azurerm_container_registry.acr.admin_password
  }

  # Expose the container port publicly
  exposed_port {
    port     = var.container_port
    protocol = var.container_protocol
  }

  tags = merge(local.common_tags, {
    Name           = "Azure Container Instance"
    ContainerImage = local.container_image_full
    Port           = tostring(var.container_port)
  })

  # Ensure container registry is created before deploying container instance
  depends_on = [azurerm_container_registry.acr]
}

# Data source to get current Azure client configuration
# Used for constructing resource identifiers and validation
data "azurerm_client_config" "current" {}

# Data source to get resource group information after creation
# Provides additional metadata about the deployed resource group
data "azurerm_resource_group" "main" {
  name = azurerm_resource_group.main.name
  
  depends_on = [azurerm_resource_group.main]
}