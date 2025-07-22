# Main Terraform Configuration for Container Security Scanning
# This file contains the primary infrastructure resources for implementing
# container security scanning with Azure Container Registry and Microsoft Defender

# Data Sources
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and tagging
locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment     = var.environment
    Project         = var.project_name
    DeployedBy      = "Terraform"
    CreatedDate     = formatdate("YYYY-MM-DD", timestamp())
    ResourcePrefix  = local.resource_prefix
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_prefix}-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags
}

# Log Analytics Workspace for monitoring and compliance
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

# Azure Container Registry with security features
resource "azurerm_container_registry" "main" {
  name                = "acr${replace(local.resource_prefix, "-", "")}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = var.acr_admin_enabled

  # Enable public network access (can be restricted with IP rules)
  public_network_access_enabled = var.acr_public_network_access_enabled

  # Network rules for security
  network_rule_set {
    default_action = "Allow"
    
    dynamic "ip_rule" {
      for_each = var.allowed_ip_ranges
      content {
        action   = "Allow"
        ip_range = ip_rule.value
      }
    }
  }

  # Enable quarantine policy to prevent vulnerable images from being pulled
  quarantine_policy_enabled = var.acr_quarantine_policy_enabled

  # Enable trust policy for signed images
  trust_policy {
    enabled = var.acr_trust_policy_enabled
  }

  # Configure retention policy for untagged manifests
  retention_policy {
    enabled = true
    days    = var.acr_retention_policy_days
  }

  # Enable encryption with customer-managed keys (Premium SKU only)
  dynamic "encryption" {
    for_each = var.acr_sku == "Premium" ? [1] : []
    content {
      enabled = false # Set to true if customer-managed keys are needed
    }
  }

  tags = local.common_tags
}

# Azure Kubernetes Service (AKS) cluster for container deployments
resource "azurerm_kubernetes_cluster" "main" {
  count               = var.create_aks_cluster ? 1 : 0
  name                = "aks-${local.resource_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-${local.resource_prefix}-${random_string.suffix.result}"
  kubernetes_version  = var.aks_kubernetes_version

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_node_vm_size

    # Enable Azure CNI for better network integration
    # vnet_subnet_id = azurerm_subnet.aks.id # Uncomment if using custom VNet
  }

  # Use system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Enable Azure Policy for Kubernetes
  azure_policy_enabled = var.enable_policy_enforcement

  # Enable Microsoft Defender for Kubernetes
  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Enable monitoring
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Network configuration
  network_profile {
    network_plugin = "kubenet"
    dns_service_ip = "10.0.0.10"
    service_cidr   = "10.0.0.0/16"
  }

  tags = local.common_tags
}

# Role assignment for AKS to pull images from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.create_aks_cluster ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main[0].kubelet_identity[0].object_id
}

# Microsoft Defender for Containers pricing tier
resource "azurerm_security_center_subscription_pricing" "containers" {
  count         = var.defender_for_containers_enabled ? 1 : 0
  tier          = "Standard"
  resource_type = "Containers"
}

# Microsoft Defender for Container Registries pricing tier
resource "azurerm_security_center_subscription_pricing" "container_registries" {
  count         = var.defender_for_container_registries_enabled ? 1 : 0
  tier          = "Standard"
  resource_type = "ContainerRegistry"
}

# Enable Microsoft Defender for Cloud settings
resource "azurerm_security_center_setting" "mcas" {
  setting_name   = "MCAS"
  enabled        = true
  depends_on     = [azurerm_security_center_subscription_pricing.containers]
}

# Diagnostic settings for Azure Container Registry
resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "acr-diagnostics"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for AKS cluster
resource "azurerm_monitor_diagnostic_setting" "aks" {
  count                      = var.create_aks_cluster ? 1 : 0
  name                       = "aks-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.main[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Azure Policy Assignment - Container Registry Vulnerability Assessment
resource "azurerm_resource_policy_assignment" "container_registry_vulnerability_assessment" {
  count                = var.enable_policy_enforcement ? 1 : 0
  name                 = "container-registry-vulnerability-assessment"
  display_name         = "Container images should have vulnerability findings resolved"
  resource_id          = azurerm_container_registry.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/090c7b07-b4ed-4561-ad20-e9075f3ccaff"
  enforcement_mode     = var.policy_enforcement_mode

  parameters = jsonencode({
    effect = {
      value = "AuditIfNotExists"
    }
  })
}

# Azure Policy Assignment - Container Registry Trusted Services
resource "azurerm_resource_policy_assignment" "container_registry_trusted_services" {
  count                = var.enable_policy_enforcement ? 1 : 0
  name                 = "container-registry-trusted-services"
  display_name         = "Container registries should allow trusted Microsoft services"
  resource_id          = azurerm_container_registry.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/d0793b48-0edc-4296-a390-4c75d1bdfd71"
  enforcement_mode     = var.policy_enforcement_mode

  parameters = jsonencode({
    effect = {
      value = "Audit"
    }
  })
}

# Azure Policy Assignment - Disable Anonymous Pull
resource "azurerm_resource_policy_assignment" "container_registry_disable_anonymous_pull" {
  count                = var.enable_policy_enforcement ? 1 : 0
  name                 = "container-registry-disable-anonymous-pull"
  display_name         = "Container registries should not allow unrestricted network access"
  resource_id          = azurerm_container_registry.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/d0793b48-0edc-4296-a390-4c75d1bdfd71"
  enforcement_mode     = var.policy_enforcement_mode

  parameters = jsonencode({
    effect = {
      value = "Audit"
    }
  })
}

# Azure Active Directory Application for DevOps integration
resource "azuread_application" "devops" {
  count        = var.create_service_principal ? 1 : 0
  display_name = "${var.service_principal_name}-${random_string.suffix.result}"
  owners       = [data.azurerm_client_config.current.object_id]
}

# Service Principal for the Azure AD Application
resource "azuread_service_principal" "devops" {
  count          = var.create_service_principal ? 1 : 0
  application_id = azuread_application.devops[0].application_id
  owners         = [data.azurerm_client_config.current.object_id]
}

# Service Principal Password
resource "azuread_service_principal_password" "devops" {
  count                = var.create_service_principal ? 1 : 0
  service_principal_id = azuread_service_principal.devops[0].object_id
  end_date_relative    = "2160h" # 90 days
}

# Role assignment for Service Principal - ACR Push
resource "azurerm_role_assignment" "devops_acr_push" {
  count                = var.create_service_principal ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.devops[0].object_id
}

# Role assignment for Service Principal - Reader (to access vulnerability reports)
resource "azurerm_role_assignment" "devops_reader" {
  count                = var.create_service_principal ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.devops[0].object_id
}

# Security Contact for Microsoft Defender alerts
resource "azurerm_security_center_contact" "main" {
  count = var.enable_security_alerts && length(var.alert_email_addresses) > 0 ? 1 : 0
  email = var.alert_email_addresses[0]
  phone = ""

  alert_notifications                = true
  alerts_to_admins                   = true
  notification_by_role_built_in_owner = true
}

# Action Group for security alerts
resource "azurerm_monitor_action_group" "security_alerts" {
  count               = var.enable_security_alerts ? 1 : 0
  name                = "ag-security-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "SecAlerts"

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  tags = local.common_tags
}

# Activity Log Alert for ACR security events
resource "azurerm_monitor_activity_log_alert" "security_events" {
  count               = var.enable_security_alerts ? 1 : 0
  name                = "alert-acr-security-events-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_container_registry.main.id]
  description         = "Alert for container registry security events"

  criteria {
    resource_id    = azurerm_container_registry.main.id
    operation_name = "Microsoft.ContainerRegistry/registries/quarantineRead/action"
    category       = "Security"
  }

  action {
    action_group_id = azurerm_monitor_action_group.security_alerts[0].id
  }

  tags = local.common_tags
}

# Log Analytics Queries for Security Monitoring
resource "azurerm_log_analytics_saved_search" "container_vulnerability_query" {
  name                       = "ContainerVulnerabilityTrends"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  category                   = "Container Security"
  display_name               = "Container Vulnerability Trends"
  query                      = <<-EOT
    ContainerRegistryRepositoryEvents
    | where OperationName == "Push"
    | extend Repository = tostring(split(Repository, "/")[0])
    | join kind=leftouter (
        SecurityRecommendation
        | where RecommendationDisplayName contains "vulnerabilities"
        | summarize VulnerabilityCount = count() by AssessedResourceId
    ) on $left.Repository == $right.AssessedResourceId
    | project TimeGenerated, Repository, Tag, VulnerabilityCount
    | order by TimeGenerated desc
  EOT
}

# Log Analytics Queries for Compliance Monitoring
resource "azurerm_log_analytics_saved_search" "compliance_query" {
  name                       = "ContainerComplianceStatus"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  category                   = "Container Security"
  display_name               = "Container Compliance Status"
  query                      = <<-EOT
    SecurityRecommendation
    | where RecommendationDisplayName contains "container"
    | summarize CompliancePercentage = (countif(RecommendationState == "Healthy") * 100.0) / count() by bin(TimeGenerated, 1d)
    | order by TimeGenerated desc
  EOT
}

# Private Endpoint for Container Registry (Premium SKU only)
resource "azurerm_private_endpoint" "acr" {
  count               = var.enable_private_endpoint && var.acr_sku == "Premium" ? 1 : 0
  name                = "pe-acr-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  # subnet_id           = azurerm_subnet.private_endpoints.id # Uncomment if using custom VNet

  private_service_connection {
    name                           = "psc-acr-${random_string.suffix.result}"
    private_connection_resource_id = azurerm_container_registry.main.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  tags = local.common_tags
}

# Storage Account for Data Export (optional)
resource "azurerm_storage_account" "data_export" {
  count                    = var.enable_data_export ? 1 : 0
  name                     = "st${replace(local.resource_prefix, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Enable blob encryption
  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 7
    }
  }

  tags = local.common_tags
}

# Data Export Configuration for Microsoft Defender
resource "azurerm_security_center_automation" "data_export" {
  count               = var.enable_data_export ? 1 : 0
  name                = "automation-data-export-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  action {
    type        = "logicapp"
    resource_id = azurerm_storage_account.data_export[0].id
    connection_string = azurerm_storage_account.data_export[0].primary_connection_string
  }

  source {
    event_source = "Assessments"
    rule_set {
      rule {
        property_path  = "type"
        operator       = "Contains"
        expected_value = "Microsoft.ContainerRegistry"
        property_type  = "String"
      }
    }
  }

  scopes = [data.azurerm_subscription.current.id]

  tags = local.common_tags
}