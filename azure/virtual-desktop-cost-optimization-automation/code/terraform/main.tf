# Azure Virtual Desktop Cost Optimization Infrastructure
# This Terraform configuration deploys a complete AVD environment with cost optimization features

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Data sources for current Azure configuration
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_prefix}-rg-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Purpose     = "cost-optimization"
    Environment = var.environment
    Project     = "avd-optimization"
  })
}

# Log Analytics Workspace for monitoring and cost tracking
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.resource_prefix}-law-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days

  tags = merge(var.tags, {
    Purpose    = "monitoring"
    Department = "shared"
  })
}

# Storage Account for cost reports and function app data
resource "azurerm_storage_account" "main" {
  name                     = "stcostopt${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable advanced threat protection
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"

  blob_properties {
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(var.tags, {
    Department = "shared"
    Purpose    = "cost-reporting"
  })
}

# Storage container for cost analysis data
resource "azurerm_storage_container" "cost_analysis" {
  name                  = "cost-analysis"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Virtual Network for AVD infrastructure
resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_prefix}-vnet-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space

  tags = merge(var.tags, {
    Department = "shared"
    Purpose    = "networking"
  })
}

# Subnet for AVD session hosts
resource "azurerm_subnet" "avd_subnet" {
  name                 = "subnet-avd"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]
}

# Network Security Group for AVD subnet
resource "azurerm_network_security_group" "avd_nsg" {
  name                = "${var.resource_prefix}-nsg-avd-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow RDP access from Azure Virtual Desktop service
  security_rule {
    name                       = "AllowRDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Allow outbound internet access
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  tags = var.tags
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "avd_nsg_assoc" {
  subnet_id                 = azurerm_subnet.avd_subnet.id
  network_security_group_id = azurerm_network_security_group.avd_nsg.id
}

# AVD Workspace
resource "azurerm_virtual_desktop_workspace" "main" {
  name                = "${var.resource_prefix}-workspace-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Cost-optimized virtual desktop workspace"

  tags = merge(var.tags, {
    Department = "shared"
    Purpose    = "virtual-desktop"
  })
}

# AVD Host Pool for cost-optimized pooled desktops
resource "azurerm_virtual_desktop_host_pool" "main" {
  name                = "${var.resource_prefix}-hp-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  type                     = var.avd_host_pool_type
  load_balancer_type       = var.avd_load_balancer_type
  maximum_sessions_allowed = var.avd_max_session_limit
  validate_environment     = false

  tags = merge(var.tags, {
    Department     = "shared"
    WorkloadType   = "pooled"
    CostCenter     = "100"
    Optimization   = "cost-optimized"
  })
}

# AVD Application Group
resource "azurerm_virtual_desktop_application_group" "main" {
  name                = "${var.resource_prefix}-ag-desktop-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  type         = "Desktop"
  host_pool_id = azurerm_virtual_desktop_host_pool.main.id

  tags = merge(var.tags, {
    Department = "shared"
    Purpose    = "desktop-delivery"
  })
}

# Associate Application Group with Workspace
resource "azurerm_virtual_desktop_workspace_application_group_association" "main" {
  workspace_id         = azurerm_virtual_desktop_workspace.main.id
  application_group_id = azurerm_virtual_desktop_application_group.main.id
}

# VM Scale Set for AVD session hosts with cost optimization
resource "azurerm_windows_virtual_machine_scale_set" "avd_hosts" {
  name                = "${var.resource_prefix}-vmss-avd-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.vmss_sku
  instances           = var.vmss_instance_count
  upgrade_mode        = "Automatic"

  admin_username = var.admin_username
  admin_password = var.admin_password

  disable_password_authentication = false

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-22h2-avd"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_SSD_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic-avd"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.avd_subnet.id
    }
  }

  # Enable auto-scaling optimizations
  overprovision = false
  
  # Configure for cost optimization with spot instances (optional)
  priority        = "Regular"  # Change to "Spot" for additional cost savings
  eviction_policy = "Deallocate"

  tags = merge(var.tags, {
    Workload         = "avd"
    Department       = "shared"
    CostOptimization = "enabled"
    BillingCode      = "AVD-PROD"
    Environment      = var.environment
    CostCenter       = "100"
  })

  depends_on = [azurerm_virtual_desktop_host_pool.main]
}

# Monitor Auto-scale Settings for VM Scale Set
resource "azurerm_monitor_autoscale_setting" "avd_autoscale" {
  name                = "${var.resource_prefix}-autoscale-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.avd_hosts.id

  profile {
    name = "defaultProfile"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_min_capacity
      maximum = var.autoscale_max_capacity
    }

    # Scale out rule - increase instances when CPU is high
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.avd_hosts.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in rule - decrease instances when CPU is low
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.avd_hosts.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = merge(var.tags, {
    Purpose = "cost-optimization"
  })
}

# Logic App for cost optimization automation
resource "azurerm_logic_app_workflow" "cost_optimizer" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = "${var.resource_prefix}-la-cost-optimizer-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Purpose    = "cost-automation"
    Department = "shared"
  })
}

# Function App for Reserved Instance analysis
resource "azurerm_service_plan" "function_plan" {
  count               = var.function_app_enabled ? 1 : 0
  name                = "${var.resource_prefix}-plan-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "Y1"  # Consumption plan for cost optimization
}

resource "azurerm_linux_function_app" "ri_analyzer" {
  count               = var.function_app_enabled ? 1 : 0
  name                = "${var.resource_prefix}-func-ri-analyzer-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan[0].id

  site_config {
    application_stack {
      node_version = "18"
    }
  }

  app_settings = {
    "SUBSCRIPTION_ID"             = data.azurerm_subscription.current.subscription_id
    "RESOURCE_GROUP"              = azurerm_resource_group.main.name
    "STORAGE_CONNECTION_STRING"   = azurerm_storage_account.main.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
  }

  tags = merge(var.tags, {
    Purpose    = "cost-analysis"
    Department = "shared"
  })
}

# Application Insights for monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.resource_prefix}-ai-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = merge(var.tags, {
    Purpose = "monitoring"
  })
}

# Cost Management Budget for each department
resource "azurerm_consumption_budget_resource_group" "department_budgets" {
  count           = length(var.departments)
  name            = "${var.resource_prefix}-budget-${var.departments[count.index].name}-${random_string.suffix.result}"
  resource_group_id = azurerm_resource_group.main.id

  amount     = var.departments[count.index].budget
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01", timestamp())
    end_date   = formatdate("YYYY-MM-01", timeadd(timestamp(), "8760h")) # One year from now
  }

  filter {
    tag {
      name = "Department"
      values = [var.departments[count.index].name]
    }
  }

  notification {
    enabled        = true
    threshold      = var.budget_alert_threshold_actual
    operator       = "GreaterThan"
    threshold_type = "Actual"

    contact_emails = [
      "finance@company.com",
      "${var.departments[count.index].name}@company.com"
    ]
  }

  notification {
    enabled        = true
    threshold      = var.budget_alert_threshold_forecast
    operator       = "GreaterThan"
    threshold_type = "Forecasted"

    contact_emails = [
      "finance@company.com",
      "${var.departments[count.index].name}@company.com"
    ]
  }

  depends_on = [azurerm_resource_group.main]
}

# Diagnostic settings for cost monitoring
resource "azurerm_monitor_diagnostic_setting" "vmss_diagnostics" {
  name                       = "vmss-diagnostics"
  target_resource_id         = azurerm_windows_virtual_machine_scale_set.avd_hosts.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AutoscaleEvaluations"
  }

  enabled_log {
    category = "AutoscaleScaleActions"
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Role assignment for Logic App to access Cost Management APIs
resource "azurerm_role_assignment" "logic_app_cost_reader" {
  count                = var.logic_app_enabled ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_logic_app_workflow.cost_optimizer[0].identity[0].principal_id

  depends_on = [azurerm_logic_app_workflow.cost_optimizer]
}

# Role assignment for Function App to access resource data
resource "azurerm_role_assignment" "function_app_reader" {
  count                = var.function_app_enabled ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_function_app.ri_analyzer[0].identity[0].principal_id

  depends_on = [azurerm_linux_function_app.ri_analyzer]
}

# Add system assigned identity to Logic App
resource "azurerm_logic_app_workflow" "cost_optimizer_identity" {
  count               = var.logic_app_enabled ? 1 : 0
  name                = azurerm_logic_app_workflow.cost_optimizer[0].name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  identity {
    type = "SystemAssigned"
  }

  tags = merge(var.tags, {
    Purpose    = "cost-automation"
    Department = "shared"
  })

  depends_on = [azurerm_logic_app_workflow.cost_optimizer]
}

# Add system assigned identity to Function App
resource "azurerm_linux_function_app" "ri_analyzer_identity" {
  count               = var.function_app_enabled ? 1 : 0
  name                = azurerm_linux_function_app.ri_analyzer[0].name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key
  service_plan_id            = azurerm_service_plan.function_plan[0].id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      node_version = "18"
    }
  }

  app_settings = {
    "SUBSCRIPTION_ID"             = data.azurerm_subscription.current.subscription_id
    "RESOURCE_GROUP"              = azurerm_resource_group.main.name
    "STORAGE_CONNECTION_STRING"   = azurerm_storage_account.main.primary_connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
  }

  tags = merge(var.tags, {
    Purpose    = "cost-analysis"
    Department = "shared"
  })

  depends_on = [azurerm_linux_function_app.ri_analyzer]
}