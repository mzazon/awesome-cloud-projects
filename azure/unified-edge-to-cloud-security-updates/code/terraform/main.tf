# Main Terraform configuration for IoT Edge-to-Cloud Security Updates
# This configuration deploys Azure IoT Device Update and Azure Update Manager
# for orchestrating security updates across hybrid edge-to-cloud environments

# Data source to get current Azure subscription information
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and tagging
locals {
  # Generate resource group name if not provided
  resource_group_name = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Determine Device Update location (fallback to main location if not specified)
  device_update_location = var.device_update_location != "" ? var.device_update_location : var.location
  
  # Common tags applied to all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    DeployedBy    = "Terraform"
    LastModified  = formatdate("YYYY-MM-DD", timestamp())
    RandomSuffix  = random_string.suffix.result
  })
  
  # Resource naming convention
  resource_prefix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
}

# ==============================================================================
# RESOURCE GROUP
# ==============================================================================

# Main resource group to contain all IoT and security update resources
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# ==============================================================================
# STORAGE ACCOUNT FOR DEVICE UPDATE ARTIFACTS
# ==============================================================================

# Storage account for storing firmware update packages and deployment artifacts
resource "azurerm_storage_account" "main" {
  name                     = "st${replace(local.resource_prefix, "-", "")}du"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  # Security configurations
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = true

  # Network access rules for enhanced security
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  # Blob properties for versioning and lifecycle management
  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    # Container delete retention policy
    container_delete_retention_policy {
      days = 7
    }

    # Blob delete retention policy
    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Container for storing device update packages
resource "azurerm_storage_container" "device_updates" {
  name                  = "device-updates"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Container for storing deployment logs and artifacts
resource "azurerm_storage_container" "deployment_logs" {
  name                  = "deployment-logs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# ==============================================================================
# LOG ANALYTICS WORKSPACE FOR MONITORING
# ==============================================================================

# Log Analytics workspace for centralized logging and monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days

  tags = local.common_tags
}

# ==============================================================================
# IOT HUB FOR DEVICE CONNECTIVITY
# ==============================================================================

# Azure IoT Hub for secure device connectivity and communication
resource "azurerm_iothub" "main" {
  name                = "iothub-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # SKU configuration for IoT Hub
  sku {
    name     = var.iot_hub_sku
    capacity = var.iot_hub_capacity
  }

  # Event Hub endpoints for device telemetry routing
  endpoint {
    type                       = "AzureIotHub.EventHub"
    connection_string          = azurerm_eventhub_authorization_rule.iothub.primary_connection_string
    name                       = "export"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.deployment_logs.name
    encoding                   = "Avro"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }

  # Route for device telemetry
  route {
    name           = "export"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["export"]
    enabled        = true
  }

  # Cloud-to-device messaging configuration
  cloud_to_device {
    max_delivery_count = 30
    default_ttl        = "PT1H"
    feedback {
      time_to_live       = "PT1H10M"
      max_delivery_count = 10
      lock_duration      = "PT30S"
    }
  }

  # File upload configuration using the storage account
  file_upload {
    connection_string  = azurerm_storage_account.main.primary_connection_string
    container_name     = azurerm_storage_container.deployment_logs.name
    default_ttl        = "PT1H"
    lock_duration      = "PT1M"
    max_delivery_count = 10
    notifications      = true
    sas_ttl           = "PT1H"
  }

  tags = local.common_tags
}

# Event Hub Namespace for IoT Hub message routing (required for endpoints)
resource "azurerm_eventhub_namespace" "iothub" {
  name                = "ehns-${local.resource_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  capacity            = 1
  tags                = local.common_tags
}

# Event Hub for IoT telemetry routing
resource "azurerm_eventhub" "iothub" {
  name                = "eh-iothub-${local.resource_prefix}"
  namespace_name      = azurerm_eventhub_namespace.iothub.name
  resource_group_name = azurerm_resource_group.main.name
  partition_count     = 2
  message_retention   = 1
}

# Authorization rule for Event Hub access
resource "azurerm_eventhub_authorization_rule" "iothub" {
  name                = "iothub-sender"
  namespace_name      = azurerm_eventhub_namespace.iothub.name
  eventhub_name       = azurerm_eventhub.iothub.name
  resource_group_name = azurerm_resource_group.main.name
  listen              = true
  send                = true
  manage              = false
}

# ==============================================================================
# DEVICE UPDATE ACCOUNT AND INSTANCE
# ==============================================================================

# Azure IoT Device Update account for managing firmware updates
resource "azurerm_iothub_device_update_account" "main" {
  name                = "deviceupdate-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.device_update_location

  # Identity configuration for accessing storage
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Device Update instance linked to IoT Hub
resource "azurerm_iothub_device_update_instance" "main" {
  name               = "deviceupdate-instance-${local.resource_prefix}"
  device_update_account_id = azurerm_iothub_device_update_account.main.id
  iothub_id         = azurerm_iothub.main.id

  # Diagnostic settings for monitoring
  diagnostic_enabled                = true
  diagnostic_storage_account_id     = azurerm_storage_account.main.id

  tags = local.common_tags
}

# Role assignment for Device Update to access storage account
resource "azurerm_role_assignment" "device_update_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_iothub_device_update_account.main.identity[0].principal_id
}

# ==============================================================================
# VIRTUAL NETWORK AND SUBNET (CONDITIONAL)
# ==============================================================================

# Virtual network for private endpoints (if enabled)
resource "azurerm_virtual_network" "main" {
  count               = var.enable_private_endpoints ? 1 : 0
  name                = "vnet-${local.resource_prefix}"
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Subnet for hosting VMs and private endpoints
resource "azurerm_subnet" "main" {
  count                = var.enable_private_endpoints ? 1 : 0
  name                 = "subnet-${local.resource_prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.subnet_address_prefix]

  # Enable private endpoint network policies
  private_endpoint_network_policies_enabled = false
}

# ==============================================================================
# TEST VIRTUAL MACHINE FOR UPDATE MANAGER (CONDITIONAL)
# ==============================================================================

# Network Security Group for VM
resource "azurerm_network_security_group" "test_vm" {
  count               = var.enable_test_vm ? 1 : 0
  name                = "nsg-${local.resource_prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Public IP for test VM
resource "azurerm_public_ip" "test_vm" {
  count               = var.enable_test_vm ? 1 : 0
  name                = "pip-${local.resource_prefix}-vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Network interface for test VM
resource "azurerm_network_interface" "test_vm" {
  count               = var.enable_test_vm ? 1 : 0
  name                = "nic-${local.resource_prefix}-vm"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.enable_private_endpoints ? azurerm_subnet.main[0].id : null
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.test_vm[0].id
  }

  tags = local.common_tags
}

# Associate Network Security Group to Network Interface
resource "azurerm_network_interface_security_group_association" "test_vm" {
  count                     = var.enable_test_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.test_vm[0].id
  network_security_group_id = azurerm_network_security_group.test_vm[0].id
}

# Linux Virtual Machine for testing Update Manager
resource "azurerm_linux_virtual_machine" "test_vm" {
  count               = var.enable_test_vm ? 1 : 0
  name                = "vm-${local.resource_prefix}-test"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.vm_admin_username

  # Disable password authentication and use SSH keys
  disable_password_authentication = true

  # Network interface association
  network_interface_ids = [
    azurerm_network_interface.test_vm[0].id,
  ]

  # Admin SSH key configuration
  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = tls_private_key.test_vm[0].public_key_openssh
  }

  # OS disk configuration
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  # Source image for Ubuntu 22.04 LTS
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Patch management configuration for Update Manager
  patch_mode                                                    = "AutomaticByPlatform"
  provision_vm_agent                                           = true
  bypass_platform_safety_checks_on_user_schedule_enabled      = false

  # Identity for managed identity access
  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# SSH key pair for VM access
resource "tls_private_key" "test_vm" {
  count     = var.enable_test_vm ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Azure VM extension for monitoring agent
resource "azurerm_virtual_machine_extension" "monitoring_agent" {
  count                = var.enable_test_vm ? 1 : 0
  name                 = "OmsAgentForLinux"
  virtual_machine_id   = azurerm_linux_virtual_machine.test_vm[0].id
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
  type                 = "OmsAgentForLinux"
  type_handler_version = "1.13"

  settings = jsonencode({
    workspaceId = azurerm_log_analytics_workspace.main.workspace_id
  })

  protected_settings = jsonencode({
    workspaceKey = azurerm_log_analytics_workspace.main.primary_shared_key
  })

  tags = local.common_tags
}

# ==============================================================================
# SIMULATED IOT DEVICES (CONDITIONAL)
# ==============================================================================

# Simulated IoT devices for testing Device Update
resource "azurerm_iothub_device" "simulated" {
  count           = var.enable_device_simulation ? var.simulated_device_count : 0
  name            = "sim-device-${format("%03d", count.index + 1)}"
  iothub_name     = azurerm_iothub.main.name
  resource_group_name = azurerm_resource_group.main.name

  # Authentication using symmetric keys
  authentication_type = "sas"
}

# ==============================================================================
# LOGIC APP WORKFLOW FOR UPDATE ORCHESTRATION
# ==============================================================================

# Logic App for orchestrating updates between Device Update and Update Manager
resource "azurerm_logic_app_workflow" "update_orchestration" {
  name                = "logic-${local.resource_prefix}-orchestration"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Workflow parameters for flexibility
  parameters = {
    "resourceGroupName" = {
      type  = "String"
      value = azurerm_resource_group.main.name
    }
    "subscriptionId" = {
      type  = "String"
      value = data.azurerm_client_config.current.subscription_id
    }
    "deviceUpdateAccount" = {
      type  = "String"
      value = azurerm_iothub_device_update_account.main.name
    }
    "deviceUpdateInstance" = {
      type  = "String"
      value = azurerm_iothub_device_update_instance.main.name
    }
  }

  tags = local.common_tags
}

# HTTP trigger for the Logic App workflow
resource "azurerm_logic_app_trigger_http_request" "update_trigger" {
  name         = "manual"
  logic_app_id = azurerm_logic_app_workflow.update_orchestration.id

  schema = jsonencode({
    type = "object"
    properties = {
      updateType = {
        type = "string"
        enum = ["device", "infrastructure", "coordinated"]
      }
      deviceGroups = {
        type = "array"
        items = {
          type = "string"
        }
      }
      maintenanceWindow = {
        type = "object"
        properties = {
          startTime = { type = "string" }
          duration  = { type = "string" }
        }
      }
    }
    required = ["updateType"]
  })
}

# Logic App action to check infrastructure update status
resource "azurerm_logic_app_action_http" "check_infrastructure" {
  name         = "checkInfrastructure"
  logic_app_id = azurerm_logic_app_workflow.update_orchestration.id

  method = "GET"
  uri    = "https://management.azure.com/subscriptions/@{parameters('subscriptionId')}/resourceGroups/@{parameters('resourceGroupName')}/providers/Microsoft.Maintenance/updates"

  headers = {
    "Authorization" = "Bearer @{listCallbackUrl()}"
    "Content-Type"  = "application/json"
  }
}

# Logic App action to deploy device updates
resource "azurerm_logic_app_action_http" "deploy_device_updates" {
  name         = "deployDeviceUpdates"
  logic_app_id = azurerm_logic_app_workflow.update_orchestration.id

  method = "POST"
  uri    = "https://management.azure.com/subscriptions/@{parameters('subscriptionId')}/resourceGroups/@{parameters('resourceGroupName')}/providers/Microsoft.DeviceUpdate/accounts/@{parameters('deviceUpdateAccount')}/instances/@{parameters('deviceUpdateInstance')}/deployments"

  headers = {
    "Authorization" = "Bearer @{listCallbackUrl()}"
    "Content-Type"  = "application/json"
  }

  body = jsonencode({
    properties = {
      startDateTime = "@{utcNow()}"
      deviceGroupType = "All"
      deviceGroupDefinition = ["*"]
    }
  })

  run_after {
    check_infrastructure = ["Succeeded"]
  }
}

# ==============================================================================
# MONITORING AND ALERTING (CONDITIONAL)
# ==============================================================================

# Action group for alert notifications
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "ag-${local.resource_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "iotupdates"

  # Email notification action
  email_receiver {
    name          = "admin-email"
    email_address = "admin@example.com"  # Update with actual email
  }

  # Azure Function action for custom notifications
  azure_function_receiver {
    name                     = "update-notification"
    function_app_resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Web/sites/func-notifications"
    function_name            = "UpdateNotification"
    http_trigger_url         = "https://func-notifications.azurewebsites.net/api/UpdateNotification"
    use_common_alert_schema  = true
  }

  tags = local.common_tags
}

# Metric alert for device update failures
resource "azurerm_monitor_metric_alert" "device_update_failures" {
  count               = var.enable_monitoring_alerts ? 1 : 0
  name                = "alert-${local.resource_prefix}-device-update-failures"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_iothub_device_update_account.main.id]
  description         = "Alert when device updates fail"

  # Alert criteria
  criteria {
    metric_namespace = "Microsoft.DeviceUpdate/accounts"
    metric_name      = "TotalFailures"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "Result"
      operator = "Include"
      values   = ["Failed"]
    }
  }

  # Alert configuration
  auto_mitigate       = true
  enabled             = true
  frequency           = "PT5M"
  severity            = 2
  window_size         = "PT15M"

  # Action to take when alert fires
  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  tags = local.common_tags
}

# Diagnostic settings for IoT Hub
resource "azurerm_monitor_diagnostic_setting" "iothub" {
  name                       = "diag-${azurerm_iothub.main.name}"
  target_resource_id         = azurerm_iothub.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Log categories
  enabled_log {
    category = "Connections"
  }

  enabled_log {
    category = "DeviceTelemetry"
  }

  enabled_log {
    category = "C2DCommands"
  }

  enabled_log {
    category = "DeviceIdentityOperations"
  }

  enabled_log {
    category = "FileUploadOperations"
  }

  # Metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Device Update account
resource "azurerm_monitor_diagnostic_setting" "device_update" {
  name                       = "diag-${azurerm_iothub_device_update_account.main.name}"
  target_resource_id         = azurerm_iothub_device_update_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  # Log categories for Device Update
  enabled_log {
    category = "DeviceUpdate"
  }

  enabled_log {
    category = "DeviceUpdateDiagnosticLogs"
  }

  # Metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}