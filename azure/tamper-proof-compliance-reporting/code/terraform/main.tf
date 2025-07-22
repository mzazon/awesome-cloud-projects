# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming
locals {
  name_suffix = random_id.suffix.hex
  common_tags = merge(var.tags, var.additional_tags, {
    DeployedBy  = "terraform"
    Environment = var.environment
    Project     = var.project_name
  })
  
  # Resource names with validation
  resource_group_name           = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${local.name_suffix}"
  confidential_ledger_name      = var.confidential_ledger_name != "" ? var.confidential_ledger_name : "acl-${var.project_name}-${local.name_suffix}"
  storage_account_name          = var.storage_account_name != "" ? var.storage_account_name : "st${var.project_name}${local.name_suffix}"
  logic_app_name               = var.logic_app_name != "" ? var.logic_app_name : "la-${var.project_name}-${local.name_suffix}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-${var.project_name}-${local.name_suffix}"
}

# Get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group
resource "azurerm_resource_group" "compliance" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Create Log Analytics Workspace for monitoring and compliance
resource "azurerm_log_analytics_workspace" "compliance" {
  name                = local.log_analytics_workspace_name
  location            = azurerm_resource_group.compliance.location
  resource_group_name = azurerm_resource_group.compliance.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags

  # Enable solutions for comprehensive monitoring
  lifecycle {
    ignore_changes = [tags]
  }
}

# Create Storage Account for compliance reports with security hardening
resource "azurerm_storage_account" "compliance" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.compliance.name
  location                 = azurerm_resource_group.compliance.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  
  # Security configurations
  https_traffic_only_enabled = var.enable_https_only
  min_tls_version            = var.minimum_tls_version
  
  # Advanced threat protection
  shared_access_key_enabled = false
  
  # Network access restrictions
  public_network_access_enabled = false
  
  # Blob properties for compliance
  blob_properties {
    versioning_enabled = var.enable_blob_versioning
    
    dynamic "delete_retention_policy" {
      for_each = var.enable_blob_soft_delete ? [1] : []
      content {
        days = var.blob_soft_delete_retention_days
      }
    }
    
    # Container delete retention policy
    container_delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }
  }
  
  tags = local.common_tags
}

# Create Storage Container for compliance reports
resource "azurerm_storage_container" "compliance_reports" {
  name                  = var.compliance_container_name
  storage_account_name  = azurerm_storage_account.compliance.name
  container_access_type = "private"
  
  depends_on = [azurerm_storage_account.compliance]
}

# Create Azure Confidential Ledger for immutable audit trails
resource "azurerm_confidential_ledger" "compliance" {
  name                = local.confidential_ledger_name
  resource_group_name = azurerm_resource_group.compliance.name
  location            = azurerm_resource_group.compliance.location
  ledger_type         = var.ledger_type
  
  # Configure Azure AD-based authentication
  azuread_based_service_principal {
    principal_id     = data.azurerm_client_config.current.object_id
    tenant_id        = data.azurerm_client_config.current.tenant_id
    ledger_role_name = "Administrator"
  }
  
  tags = local.common_tags
}

# Create Action Group for alert notifications
resource "azurerm_monitor_action_group" "compliance" {
  name                = var.action_group_name
  resource_group_name = azurerm_resource_group.compliance.name
  short_name          = var.action_group_short_name
  
  # Logic App webhook receiver will be configured after Logic App creation
  tags = local.common_tags
}

# Create Logic App for compliance workflow automation
resource "azurerm_logic_app_workflow" "compliance" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.compliance.location
  resource_group_name = azurerm_resource_group.compliance.name
  
  # Enable system-assigned managed identity for secure access
  identity {
    type = "SystemAssigned"
  }
  
  tags = local.common_tags
}

# Define the Logic App workflow for compliance automation
resource "azurerm_logic_app_trigger_http_request" "compliance_trigger" {
  name         = "When_Alert_Triggered"
  logic_app_id = azurerm_logic_app_workflow.compliance.id
  
  schema = jsonencode({
    type = "object"
    properties = {
      alertType = {
        type = "string"
      }
      severity = {
        type = "string"
      }
      description = {
        type = "string"
      }
      timestamp = {
        type = "string"
      }
      resourceId = {
        type = "string"
      }
    }
  })
}

# Logic App action to record compliance events in Confidential Ledger
resource "azurerm_logic_app_action_http" "record_to_ledger" {
  name         = "Record_to_Ledger"
  logic_app_id = azurerm_logic_app_workflow.compliance.id
  method       = "POST"
  uri          = "${azurerm_confidential_ledger.compliance.ledger_uri}/app/transactions"
  
  headers = {
    "Content-Type" = "application/json"
  }
  
  body = jsonencode({
    contents = "@{triggerBody()}"
  })
  
  depends_on = [azurerm_logic_app_trigger_http_request.compliance_trigger]
}

# Role assignments for Logic App managed identity
resource "azurerm_role_assignment" "logic_app_to_ledger" {
  scope                = azurerm_confidential_ledger.compliance.id
  role_definition_name = "Confidential Ledger Contributor"
  principal_id         = azurerm_logic_app_workflow.compliance.identity[0].principal_id
}

resource "azurerm_role_assignment" "logic_app_to_storage" {
  scope                = azurerm_storage_account.compliance.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_logic_app_workflow.compliance.identity[0].principal_id
}

resource "azurerm_role_assignment" "logic_app_monitoring" {
  scope                = azurerm_resource_group.compliance.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_logic_app_workflow.compliance.identity[0].principal_id
}

# Create metric alert for compliance violations
resource "azurerm_monitor_metric_alert" "cpu_compliance" {
  name                = "alert-compliance-cpu-violation"
  resource_group_name = azurerm_resource_group.compliance.name
  scopes              = [azurerm_log_analytics_workspace.compliance.id]
  description         = "Compliance threshold violation detected - CPU usage"
  
  criteria {
    metric_namespace = "Microsoft.OperationalInsights/workspaces"
    metric_name      = "Average_% Processor Time"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_threshold
  }
  
  window_size = var.alert_window_size
  frequency   = var.alert_frequency
  
  action {
    action_group_id = azurerm_monitor_action_group.compliance.id
    
    webhook_properties = {
      logicAppUrl = azurerm_logic_app_trigger_http_request.compliance_trigger.callback_url
    }
  }
  
  tags = local.common_tags
}

# Create scheduled query rule for security events
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "security_events" {
  name                = "alert-security-events"
  resource_group_name = azurerm_resource_group.compliance.name
  location            = azurerm_resource_group.compliance.location
  
  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"
  scopes               = [azurerm_log_analytics_workspace.compliance.id]
  severity             = 2
  
  criteria {
    query                   = <<-QUERY
      SecurityEvent
      | where EventID == 4625
      | summarize Count = count() by bin(TimeGenerated, 5m)
      | where Count > 5
    QUERY
    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"
    
    resource_id_column    = "ResourceId"
    metric_measure_column = "Count"
    
    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }
  
  action {
    action_groups = [azurerm_monitor_action_group.compliance.id]
    
    custom_properties = {
      alertType   = "SecurityViolation"
      severity    = "High"
      description = "Multiple failed authentication attempts detected"
    }
  }
  
  tags = local.common_tags
}

# Create Application Insights for Logic App monitoring
resource "azurerm_application_insights" "compliance" {
  name                = "ai-${var.project_name}-${local.name_suffix}"
  location            = azurerm_resource_group.compliance.location
  resource_group_name = azurerm_resource_group.compliance.name
  workspace_id        = azurerm_log_analytics_workspace.compliance.id
  application_type    = "web"
  
  tags = local.common_tags
}

# Private endpoint for Storage Account (recommended for production)
resource "azurerm_private_endpoint" "storage" {
  name                = "pe-${azurerm_storage_account.compliance.name}"
  location            = azurerm_resource_group.compliance.location
  resource_group_name = azurerm_resource_group.compliance.name
  subnet_id           = azurerm_subnet.compliance.id
  
  private_service_connection {
    name                           = "psc-${azurerm_storage_account.compliance.name}"
    private_connection_resource_id = azurerm_storage_account.compliance.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  
  private_dns_zone_group {
    name                 = "dzg-${azurerm_storage_account.compliance.name}"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage.id]
  }
  
  tags = local.common_tags
}

# Virtual Network for secure communication
resource "azurerm_virtual_network" "compliance" {
  name                = "vnet-${var.project_name}-${local.name_suffix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.compliance.location
  resource_group_name = azurerm_resource_group.compliance.name
  
  tags = local.common_tags
}

# Subnet for private endpoints
resource "azurerm_subnet" "compliance" {
  name                 = "snet-compliance"
  resource_group_name  = azurerm_resource_group.compliance.name
  virtual_network_name = azurerm_virtual_network.compliance.name
  address_prefixes     = ["10.0.1.0/24"]
  
  # Disable network security group and route table association for private endpoints
  private_endpoint_network_policies_enabled = false
}

# Private DNS Zone for Storage Account
resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.compliance.name
  
  tags = local.common_tags
}

# Link Private DNS Zone to Virtual Network
resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  name                  = "vnetlink-storage"
  resource_group_name   = azurerm_resource_group.compliance.name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = azurerm_virtual_network.compliance.id
  registration_enabled  = false
  
  tags = local.common_tags
}

# Network Security Group for additional security
resource "azurerm_network_security_group" "compliance" {
  name                = "nsg-${var.project_name}-${local.name_suffix}"
  location            = azurerm_resource_group.compliance.location
  resource_group_name = azurerm_resource_group.compliance.name
  
  # Allow HTTPS traffic
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  # Deny all other inbound traffic
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = local.common_tags
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "compliance" {
  subnet_id                 = azurerm_subnet.compliance.id
  network_security_group_id = azurerm_network_security_group.compliance.id
}