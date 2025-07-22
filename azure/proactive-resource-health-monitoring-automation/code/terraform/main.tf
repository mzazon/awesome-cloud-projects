# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "health_monitoring" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics Workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "health_monitoring" {
  name                = "log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create Service Bus Namespace for health event messaging
resource "azurerm_servicebus_namespace" "health_monitoring" {
  name                          = "sb-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.health_monitoring.location
  resource_group_name           = azurerm_resource_group.health_monitoring.name
  sku                          = var.service_bus_sku
  capacity                     = var.service_bus_sku == "Premium" ? var.service_bus_capacity : null
  premium_messaging_partitions = var.service_bus_sku == "Premium" ? 1 : null
  tags                         = var.tags
}

# Create Service Bus Authorization Rule for application access
resource "azurerm_servicebus_namespace_authorization_rule" "health_monitoring" {
  name         = "health-monitoring-access"
  namespace_id = azurerm_servicebus_namespace.health_monitoring.id
  listen       = true
  send         = true
  manage       = false
}

# Create Service Bus Queue for health events
resource "azurerm_servicebus_queue" "health_events" {
  name         = "health-events"
  namespace_id = azurerm_servicebus_namespace.health_monitoring.id

  # Queue configuration
  max_size_in_megabytes                = var.health_queue_max_size
  enable_duplicate_detection           = var.enable_duplicate_detection
  duplicate_detection_history_time_window = var.duplicate_detection_history_time_window
  
  # Message handling configuration
  default_message_ttl                  = "P14D"  # 14 days
  max_delivery_count                   = var.max_delivery_count
  dead_lettering_on_message_expiration = true
  
  # Performance and reliability settings
  enable_partitioning = var.service_bus_sku != "Premium"
  enable_express      = var.service_bus_sku == "Premium" ? false : true
}

# Create Service Bus Topic for remediation actions
resource "azurerm_servicebus_topic" "remediation_actions" {
  name         = "remediation-actions"
  namespace_id = azurerm_servicebus_namespace.health_monitoring.id

  # Topic configuration
  max_size_in_megabytes                = var.remediation_topic_max_size
  enable_duplicate_detection           = var.enable_duplicate_detection
  duplicate_detection_history_time_window = var.duplicate_detection_history_time_window
  
  # Message handling configuration
  default_message_ttl = "P7D"  # 7 days
  
  # Performance settings
  enable_partitioning = var.service_bus_sku != "Premium"
  enable_express      = var.service_bus_sku == "Premium" ? false : true
  
  # Topic-specific settings
  enable_batched_operations = true
  support_ordering         = false
}

# Create Service Bus Subscription for auto-scale handler
resource "azurerm_servicebus_subscription" "auto_scale_handler" {
  name     = "auto-scale-handler"
  topic_id = azurerm_servicebus_topic.remediation_actions.id

  max_delivery_count                = var.max_delivery_count
  default_message_ttl               = "P7D"
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
  enable_batched_operations         = true
}

# Create Service Bus Subscription for restart handler
resource "azurerm_servicebus_subscription" "restart_handler" {
  name     = "restart-handler"
  topic_id = azurerm_servicebus_topic.remediation_actions.id

  max_delivery_count                = var.max_delivery_count
  default_message_ttl               = "P7D"
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
  enable_batched_operations         = true
}

# Create Service Bus Subscription for webhook notifications
resource "azurerm_servicebus_subscription" "webhook_notifications" {
  name     = "webhook-notifications"
  topic_id = azurerm_servicebus_topic.remediation_actions.id

  max_delivery_count                = var.max_delivery_count
  default_message_ttl               = "P7D"
  dead_lettering_on_message_expiration = true
  dead_lettering_on_filter_evaluation_error = true
  enable_batched_operations         = true
}

# Create Logic App for health event orchestration
resource "azurerm_logic_app_workflow" "health_orchestrator" {
  name                = "la-health-orchestrator-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name
  tags                = var.tags

  # Workflow definition for health event processing
  workflow_schema  = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
  
  # Enable integration with Azure Monitor
  enabled = true
}

# Create Logic App Connection for Service Bus
resource "azurerm_api_connection" "servicebus" {
  name                = "servicebus-connection-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name

  managed_api_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.health_monitoring.location}/managedApis/servicebus"

  parameter_values = {
    connectionString = azurerm_servicebus_namespace_authorization_rule.health_monitoring.primary_connection_string
  }

  tags = var.tags
}

# Create Logic App for restart handler
resource "azurerm_logic_app_workflow" "restart_handler" {
  name                = "la-restart-handler-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name
  tags                = var.tags

  workflow_schema  = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
  enabled          = true
}

# Create Action Group for Resource Health alerts
resource "azurerm_monitor_action_group" "health_alerts" {
  name                = "ag-health-alerts-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.health_monitoring.name
  short_name          = "HealthAlert"
  tags                = var.tags

  # Logic App webhook action
  logic_app_receiver {
    name                    = "health-orchestrator-webhook"
    resource_id            = azurerm_logic_app_workflow.health_orchestrator.id
    callback_url           = "https://${azurerm_logic_app_workflow.health_orchestrator.name}.azurewebsites.net/api/triggers/request/invoke"
    use_common_alert_schema = true
  }
}

# Create demo VM for health monitoring testing (conditional)
resource "azurerm_virtual_network" "demo" {
  count               = var.create_demo_vm ? 1 : 0
  name                = "vnet-demo-${var.environment}-${random_string.suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name
  tags                = var.tags
}

resource "azurerm_subnet" "demo" {
  count                = var.create_demo_vm ? 1 : 0
  name                 = "subnet-demo"
  resource_group_name  = azurerm_resource_group.health_monitoring.name
  virtual_network_name = azurerm_virtual_network.demo[0].name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "demo" {
  count               = var.create_demo_vm ? 1 : 0
  name                = "nsg-demo-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name
  tags                = var.tags

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
}

resource "azurerm_network_interface" "demo" {
  count               = var.create_demo_vm ? 1 : 0
  name                = "nic-demo-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.demo[0].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "demo" {
  count                     = var.create_demo_vm ? 1 : 0
  network_interface_id      = azurerm_network_interface.demo[0].id
  network_security_group_id = azurerm_network_security_group.demo[0].id
}

# Generate SSH key pair for demo VM
resource "tls_private_key" "demo" {
  count     = var.create_demo_vm ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "demo" {
  count               = var.create_demo_vm ? 1 : 0
  name                = "vm-health-demo-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.health_monitoring.location
  resource_group_name = azurerm_resource_group.health_monitoring.name
  size                = var.vm_size
  admin_username      = var.vm_admin_username
  tags                = var.tags

  # Disable password authentication and use SSH keys
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.demo[0].id,
  ]

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = tls_private_key.demo[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  # Install Azure CLI and monitoring agent
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y curl
    
    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    
    # Configure automatic updates
    apt-get install -y unattended-upgrades
    echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/20auto-upgrades
    
    # Configure system monitoring
    systemctl enable --now systemd-resolved
    systemctl enable --now systemd-networkd
    EOF
  )
}

# Create Resource Health alert for the demo VM
resource "azurerm_monitor_activity_log_alert" "vm_health" {
  count               = var.create_demo_vm ? 1 : 0
  name                = "vm-health-alert-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.health_monitoring.name
  scopes              = [azurerm_linux_virtual_machine.demo[0].id]
  description         = "Alert when VM health status changes"
  tags                = var.tags

  criteria {
    category = "ResourceHealth"
    
    resource_health {
      current  = ["Unavailable", "Degraded"]
      previous = ["Available"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.health_alerts.id
  }
}

# Create diagnostic settings for Service Bus monitoring
resource "azurerm_monitor_diagnostic_setting" "servicebus" {
  name                       = "servicebus-diagnostics"
  target_resource_id         = azurerm_servicebus_namespace.health_monitoring.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.health_monitoring.id

  enabled_log {
    category = "OperationalLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create diagnostic settings for Logic Apps monitoring
resource "azurerm_monitor_diagnostic_setting" "logic_app_orchestrator" {
  name                       = "logic-app-orchestrator-diagnostics"
  target_resource_id         = azurerm_logic_app_workflow.health_orchestrator.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.health_monitoring.id

  enabled_log {
    category = "WorkflowRuntime"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "logic_app_restart" {
  name                       = "logic-app-restart-diagnostics"
  target_resource_id         = azurerm_logic_app_workflow.restart_handler.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.health_monitoring.id

  enabled_log {
    category = "WorkflowRuntime"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}