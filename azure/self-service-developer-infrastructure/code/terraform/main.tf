# Generate random suffix for resource names if enabled
resource "random_string" "suffix" {
  count   = var.use_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Get current Azure AD user (for demo purposes)
data "azuread_user" "current" {
  object_id = data.azurerm_client_config.current.object_id
}

# Local variables for resource naming and tagging
locals {
  suffix = var.use_random_suffix ? random_string.suffix[0].result : var.resource_suffix
  
  # Resource names with optional suffix
  vnet_name               = "vnet-devbox${local.suffix != null ? "-${local.suffix}" : ""}"
  subnet_name             = "snet-devbox"
  network_connection_name = "nc-devbox${local.suffix != null ? "-${local.suffix}" : ""}"
  
  # Common tags applied to all resources
  common_tags = merge({
    Environment = var.environment
    CostCenter  = var.cost_center
    Purpose     = "developer-infrastructure"
    ManagedBy   = "terraform"
  }, var.additional_tags)
}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Wait for resource provider registration
resource "time_sleep" "provider_registration" {
  depends_on = [azurerm_resource_group.main]
  
  create_duration = "30s"
}

# Create virtual network for Dev Boxes
resource "azurerm_virtual_network" "devbox_vnet" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags

  depends_on = [time_sleep.provider_registration]
}

# Create subnet for Dev Boxes
resource "azurerm_subnet" "devbox_subnet" {
  name                 = local.subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.devbox_vnet.name
  address_prefixes     = [var.devbox_subnet_address_prefix]
}

# Create network connection for Dev Center
resource "azurerm_dev_center_network_connection" "main" {
  name                = local.network_connection_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  domain_join_type    = "AzureADJoin"
  subnet_id           = azurerm_subnet.devbox_subnet.id
  tags                = local.common_tags

  depends_on = [azurerm_subnet.devbox_subnet]
}

# Create Azure DevCenter
resource "azurerm_dev_center" "main" {
  name                = var.devcenter_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  depends_on = [time_sleep.provider_registration]
}

# Assign Contributor role to DevCenter managed identity
resource "azurerm_role_assignment" "devcenter_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_dev_center.main.identity[0].principal_id
}

# Assign User Access Administrator role to DevCenter managed identity
resource "azurerm_role_assignment" "devcenter_uaa" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = azurerm_dev_center.main.identity[0].principal_id
}

# Attach network connection to DevCenter
resource "azurerm_dev_center_attached_network" "main" {
  name                      = "default"
  dev_center_id             = azurerm_dev_center.main.id
  network_connection_id     = azurerm_dev_center_network_connection.main.id

  depends_on = [
    azurerm_dev_center_network_connection.main,
    azurerm_dev_center.main
  ]
}

# Create DevCenter catalog
resource "azurerm_dev_center_catalog" "quickstart" {
  name           = var.catalog_name
  dev_center_id  = azurerm_dev_center.main.id
  
  catalog_github {
    branch = var.catalog_branch
    path   = var.catalog_path
    uri    = var.catalog_repo_url
  }

  depends_on = [azurerm_dev_center.main]
}

# Wait for catalog synchronization
resource "time_sleep" "catalog_sync" {
  depends_on = [azurerm_dev_center_catalog.quickstart]
  
  create_duration = "60s"
}

# Create environment types
resource "azurerm_dev_center_environment_type" "main" {
  for_each = toset(var.environment_types)
  
  name          = each.value
  dev_center_id = azurerm_dev_center.main.id
  
  tags = merge(local.common_tags, {
    EnvironmentType = each.value
  })

  depends_on = [azurerm_dev_center.main]
}

# Create Dev Box definition
resource "azurerm_dev_center_dev_box_definition" "main" {
  name               = var.devbox_definition_name
  dev_center_id      = azurerm_dev_center.main.id
  location           = azurerm_resource_group.main.location
  image_reference_id = "${azurerm_dev_center.main.id}/galleries/default/images/${var.devbox_image_reference}"
  sku_name           = var.devbox_sku_name
  
  hibernate_support = var.hibernate_support ? "Enabled" : "Disabled"
  tags              = local.common_tags

  depends_on = [azurerm_dev_center.main]
}

# Create DevCenter project
resource "azurerm_dev_center_project" "main" {
  name               = var.project_name
  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  dev_center_id      = azurerm_dev_center.main.id
  description        = var.project_description
  tags               = local.common_tags

  depends_on = [azurerm_dev_center.main]
}

# Create project environment types
resource "azurerm_dev_center_project_environment_type" "main" {
  for_each = toset(var.environment_types)
  
  name                         = each.value
  dev_center_project_id        = azurerm_dev_center_project.main.id
  location                     = azurerm_resource_group.main.location
  deployment_target_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  creator_role_assignment_roles = ["Contributor"]
  
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(local.common_tags, {
    EnvironmentType = each.value
  })

  depends_on = [
    azurerm_dev_center_project.main,
    azurerm_dev_center_environment_type.main
  ]
}

# Create Dev Box pool
resource "azurerm_dev_center_dev_box_pool" "main" {
  name                           = var.devbox_pool_name
  dev_center_project_id          = azurerm_dev_center_project.main.id
  location                       = azurerm_resource_group.main.location
  dev_box_definition_name        = azurerm_dev_center_dev_box_definition.main.name
  local_administrator_enabled    = var.enable_local_admin
  stop_on_disconnect_grace_period_minutes = 60
  
  tags = local.common_tags

  depends_on = [
    azurerm_dev_center_project.main,
    azurerm_dev_center_dev_box_definition.main,
    azurerm_dev_center_attached_network.main
  ]
}

# Create auto-stop schedule for Dev Box pool
resource "azurerm_dev_center_dev_box_pool_schedule" "auto_stop" {
  name                  = "AutoStop-Schedule"
  dev_box_pool_id       = azurerm_dev_center_dev_box_pool.main.id
  state                 = "Enabled"
  type                  = "StopDevBox"
  frequency             = "Daily"
  time                  = var.auto_stop_time
  time_zone             = var.auto_stop_timezone
  
  depends_on = [azurerm_dev_center_dev_box_pool.main]
}

# Role assignments for developer users
resource "azurerm_role_assignment" "developer_devbox_user" {
  count = length(var.developer_user_principal_names)
  
  scope                = azurerm_dev_center_project.main.id
  role_definition_name = "DevCenter Dev Box User"
  principal_id         = data.azuread_user.developers[count.index].object_id

  depends_on = [azurerm_dev_center_project.main]
}

resource "azurerm_role_assignment" "developer_deployment_user" {
  count = length(var.developer_user_principal_names)
  
  scope                = azurerm_dev_center_project.main.id
  role_definition_name = "Deployment Environments User"
  principal_id         = data.azuread_user.developers[count.index].object_id

  depends_on = [azurerm_dev_center_project.main]
}

# Role assignments for developer groups
resource "azurerm_role_assignment" "group_devbox_user" {
  count = length(var.developer_group_object_ids)
  
  scope                = azurerm_dev_center_project.main.id
  role_definition_name = "DevCenter Dev Box User"
  principal_id         = var.developer_group_object_ids[count.index]

  depends_on = [azurerm_dev_center_project.main]
}

resource "azurerm_role_assignment" "group_deployment_user" {
  count = length(var.developer_group_object_ids)
  
  scope                = azurerm_dev_center_project.main.id
  role_definition_name = "Deployment Environments User"
  principal_id         = var.developer_group_object_ids[count.index]

  depends_on = [azurerm_dev_center_project.main]
}

# Assign current user DevCenter roles for demo purposes
resource "azurerm_role_assignment" "current_user_devbox" {
  scope                = azurerm_dev_center_project.main.id
  role_definition_name = "DevCenter Dev Box User"
  principal_id         = data.azuread_user.current.object_id

  depends_on = [azurerm_dev_center_project.main]
}

resource "azurerm_role_assignment" "current_user_deployment" {
  scope                = azurerm_dev_center_project.main.id
  role_definition_name = "Deployment Environments User"
  principal_id         = data.azuread_user.current.object_id

  depends_on = [azurerm_dev_center_project.main]
}

# Data source for developer users
data "azuread_user" "developers" {
  count               = length(var.developer_user_principal_names)
  user_principal_name = var.developer_user_principal_names[count.index]
}