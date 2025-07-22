# Main Terraform configuration for Azure Resource Rightsizing Automation
# This file contains the core infrastructure resources for automated rightsizing

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-resource-group"
  })
}

# Create Storage Account for Function App
resource "azurerm_storage_account" "function_storage" {
  name                     = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Enable secure transfer and disable public access
  enable_https_traffic_only = true
  allow_nested_items_to_be_public = false
  
  # Configure blob properties for security
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-function-storage"
  })
}

# Create Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-log-analytics"
  })
}

# Create Application Insights
resource "azurerm_application_insights" "main" {
  name                = "ai-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-app-insights"
  })
}

# Create Service Plan for Function App
resource "azurerm_service_plan" "function_plan" {
  name                = "plan-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.function_app_sku
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-function-plan"
  })
}

# Create Function App for Rightsizing Logic
resource "azurerm_linux_function_app" "rightsizing_function" {
  name                       = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.function_plan.id
  storage_account_name       = azurerm_storage_account.function_storage.name
  storage_account_access_key = azurerm_storage_account.function_storage.primary_access_key
  
  # Configure Function App settings
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"         = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"     = "~18"
    "APPINSIGHTS_INSTRUMENTATIONKEY"   = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    
    # Custom settings for rightsizing logic
    "SUBSCRIPTION_ID"                  = data.azurerm_client_config.current.subscription_id
    "RESOURCE_GROUP"                   = azurerm_resource_group.main.name
    "LOG_ANALYTICS_WORKSPACE_ID"       = azurerm_log_analytics_workspace.main.workspace_id
    "CPU_THRESHOLD_LOW"                = var.cpu_threshold_low
    "CPU_THRESHOLD_HIGH"               = var.cpu_threshold_high
    "ANALYSIS_PERIOD_DAYS"             = var.analysis_period_days
    "ENABLE_AUTO_SCALING"              = var.enable_auto_scaling
    "NOTIFICATION_EMAIL"               = var.notification_email
    
    # Azure Functions configuration
    "WEBSITE_RUN_FROM_PACKAGE"         = "1"
    "FUNCTIONS_EXTENSION_VERSION"      = "~4"
    "WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED" = "1"
  }
  
  # Configure site settings
  site_config {
    application_stack {
      node_version = "18"
    }
    
    # Enable Application Insights
    application_insights_key = azurerm_application_insights.main.instrumentation_key
    
    # Configure CORS for Azure Developer CLI integration
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
    
    # Security settings
    ftps_state = "Disabled"
    http2_enabled = true
    minimum_tls_version = "1.2"
  }
  
  # Configure authentication if needed
  auth_settings {
    enabled = false
  }
  
  # Configure identity for Azure resource access
  identity {
    type = "SystemAssigned"
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-function-app"
  })
}

# Create Logic App for Workflow Automation
resource "azurerm_logic_app_workflow" "rightsizing_workflow" {
  name                = "logic-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  # Configure workflow parameters
  parameters = {
    "functionAppUrl" = {
      type         = "string"
      defaultValue = "https://${azurerm_linux_function_app.rightsizing_function.default_hostname}"
    }
    "notificationEmail" = {
      type         = "string"
      defaultValue = var.notification_email
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-logic-app"
  })
}

# Assign roles to Function App managed identity
resource "azurerm_role_assignment" "function_monitoring_reader" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_linux_function_app.rightsizing_function.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_cost_management_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_linux_function_app.rightsizing_function.identity[0].principal_id
}

# Conditionally assign Contributor role for auto-scaling
resource "azurerm_role_assignment" "function_contributor" {
  count                = var.enable_auto_scaling ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_function_app.rightsizing_function.identity[0].principal_id
}

# Create Action Group for Alerts
resource "azurerm_monitor_action_group" "rightsizing_alerts" {
  count               = var.enable_cost_alerts ? 1 : 0
  name                = "ag-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "rightsizing"
  
  email_receiver {
    name          = "admin"
    email_address = var.notification_email
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-action-group"
  })
}

# Create Metric Alert for Function App Errors
resource "azurerm_monitor_metric_alert" "function_error_alert" {
  name                = "alert-function-errors-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.rightsizing_function.id]
  description         = "Alert when rightsizing function encounters errors"
  
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "FunctionExecutionCount"
    aggregation      = "Total"
    operator         = "LessThan"
    threshold        = 1
    
    dimension {
      name     = "Instance"
      operator = "Include"
      values   = ["*"]
    }
  }
  
  window_size        = "PT15M"
  frequency          = "PT5M"
  severity           = 2
  
  action {
    action_group_id = var.enable_cost_alerts ? azurerm_monitor_action_group.rightsizing_alerts[0].id : null
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-function-error-alert"
  })
}

# Create Consumption Budget for Cost Management
resource "azurerm_consumption_budget_subscription" "rightsizing_budget" {
  count           = var.enable_cost_alerts ? 1 : 0
  name            = "budget-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  subscription_id = data.azurerm_client_config.current.subscription_id
  
  amount     = var.cost_budget_amount
  time_grain = "Monthly"
  
  time_period {
    start_date = "2025-01-01T00:00:00Z"
    end_date   = "2025-12-31T23:59:59Z"
  }
  
  filter {
    dimension {
      name = "ResourceGroupName"
      values = [azurerm_resource_group.main.name]
    }
  }
  
  notification {
    enabled   = true
    threshold = var.cost_alert_threshold
    operator  = "GreaterThan"
    
    contact_emails = [var.notification_email]
  }
  
  notification {
    enabled   = true
    threshold = 100
    operator  = "GreaterThan"
    
    contact_emails = [var.notification_email]
  }
}

# Create test resources if enabled
resource "azurerm_linux_virtual_machine" "test_vm" {
  count                           = var.enable_test_resources ? 1 : 0
  name                            = "vm-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = "Standard_B2s"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  
  network_interface_ids = [
    azurerm_network_interface.test_vm_nic[0].id,
  ]
  
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-test-vm"
  })
}

# Create virtual network for test resources
resource "azurerm_virtual_network" "test_vnet" {
  count               = var.enable_test_resources ? 1 : 0
  name                = "vnet-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-test-vnet"
  })
}

# Create subnet for test resources
resource "azurerm_subnet" "test_subnet" {
  count                = var.enable_test_resources ? 1 : 0
  name                 = "subnet-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.test_vnet[0].name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create network security group for test resources
resource "azurerm_network_security_group" "test_nsg" {
  count               = var.enable_test_resources ? 1 : 0
  name                = "nsg-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
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
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-test-nsg"
  })
}

# Create network interface for test VM
resource "azurerm_network_interface" "test_vm_nic" {
  count               = var.enable_test_resources ? 1 : 0
  name                = "nic-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.test_subnet[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.test_vm_pip[0].id
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-test-nic"
  })
}

# Create public IP for test VM
resource "azurerm_public_ip" "test_vm_pip" {
  count               = var.enable_test_resources ? 1 : 0
  name                = "pip-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Dynamic"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-test-pip"
  })
}

# Associate security group with network interface
resource "azurerm_network_interface_security_group_association" "test_vm_nsg_association" {
  count                     = var.enable_test_resources ? 1 : 0
  network_interface_id      = azurerm_network_interface.test_vm_nic[0].id
  network_security_group_id = azurerm_network_security_group.test_nsg[0].id
}

# Create test App Service Plan
resource "azurerm_service_plan" "test_app_plan" {
  count               = var.enable_test_resources ? 1 : 0
  name                = "plan-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "S1"
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-test-app-plan"
  })
}

# Create test Web App
resource "azurerm_linux_web_app" "test_webapp" {
  count               = var.enable_test_resources ? 1 : 0
  name                = "app-test-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.test_app_plan[0].id
  
  site_config {
    always_on = true
    
    application_stack {
      node_version = "18-lts"
    }
  }
  
  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-test-webapp"
  })
}

# Create Function App deployment package
data "archive_file" "function_app_zip" {
  type        = "zip"
  output_path = "${path.module}/function-app.zip"
  
  source {
    content = templatefile("${path.module}/function-code/index.js", {
      subscription_id = data.azurerm_client_config.current.subscription_id
      resource_group = azurerm_resource_group.main.name
      workspace_id = azurerm_log_analytics_workspace.main.workspace_id
    })
    filename = "RightsizingAnalyzer/index.js"
  }
  
  source {
    content = templatefile("${path.module}/function-code/function.json", {
      schedule = var.rightsizing_schedule
    })
    filename = "RightsizingAnalyzer/function.json"
  }
  
  source {
    content = file("${path.module}/function-code/host.json")
    filename = "host.json"
  }
  
  source {
    content = file("${path.module}/function-code/package.json")
    filename = "package.json"
  }
}

# Create Function App deployment
resource "azurerm_function_app_function" "rightsizing_analyzer" {
  name            = "RightsizingAnalyzer"
  function_app_id = azurerm_linux_function_app.rightsizing_function.id
  language        = "Javascript"
  
  file {
    name    = "index.js"
    content = templatefile("${path.module}/function-code/index.js", {
      subscription_id = data.azurerm_client_config.current.subscription_id
      resource_group = azurerm_resource_group.main.name
      workspace_id = azurerm_log_analytics_workspace.main.workspace_id
    })
  }
  
  config_json = jsonencode({
    "bindings" = [
      {
        "authLevel" = "function"
        "type"      = "timerTrigger"
        "direction" = "in"
        "name"      = "myTimer"
        "schedule"  = var.rightsizing_schedule
      }
    ]
  })
}