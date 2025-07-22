# Main Terraform configuration for MLOps Pipeline with AKS and Azure Machine Learning
# This configuration creates a complete MLOps infrastructure including:
# - Azure Kubernetes Service (AKS) cluster with ML extensions
# - Azure Machine Learning workspace with dependencies
# - Azure Container Registry for model images
# - Monitoring and logging infrastructure

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Generate random suffix for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Create main resource group
resource "azurerm_resource_group" "mlops" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Purpose     = "MLOps Pipeline"
    Environment = var.environment
    CreatedBy   = "Terraform"
  }
}

# Create storage account for ML workspace
resource "azurerm_storage_account" "mlops_storage" {
  name                     = "${var.storage_account_prefix}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.mlops.name
  location                 = azurerm_resource_group.mlops.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = {
    Purpose     = "ML Workspace Storage"
    Environment = var.environment
  }
}

# Create diagnostic storage account
resource "azurerm_storage_account" "diagnostic_storage" {
  name                     = "${var.storage_account_prefix}diag${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.mlops.name
  location                 = azurerm_resource_group.mlops.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  tags = {
    Purpose     = "Diagnostic Storage"
    Environment = var.environment
  }
}

# Create Azure Container Registry
resource "azurerm_container_registry" "mlops_acr" {
  name                = "${var.acr_name_prefix}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.mlops.name
  location            = azurerm_resource_group.mlops.location
  sku                 = var.acr_sku
  admin_enabled       = true

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Purpose     = "ML Model Container Registry"
    Environment = var.environment
  }
}

# Create Key Vault for ML workspace secrets
resource "azurerm_key_vault" "mlops_kv" {
  name                        = "${var.key_vault_name_prefix}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.mlops.location
  resource_group_name         = azurerm_resource_group.mlops.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 90
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
      "List",
      "Delete",
      "Purge",
      "Update",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "List",
      "Delete",
      "Purge",
    ]
  }

  tags = {
    Purpose     = "ML Workspace Key Vault"
    Environment = var.environment
  }
}

# Create Application Insights for monitoring
resource "azurerm_application_insights" "mlops_insights" {
  name                = "${var.app_insights_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.mlops.location
  resource_group_name = azurerm_resource_group.mlops.name
  application_type    = "web"

  tags = {
    Purpose     = "ML Monitoring"
    Environment = var.environment
  }
}

# Create Log Analytics workspace
resource "azurerm_log_analytics_workspace" "mlops_logs" {
  name                = "${var.log_analytics_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.mlops.location
  resource_group_name = azurerm_resource_group.mlops.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Purpose     = "ML Logging"
    Environment = var.environment
  }
}

# Create Azure Machine Learning workspace
resource "azurerm_machine_learning_workspace" "mlops_workspace" {
  name                    = var.ml_workspace_name
  location                = azurerm_resource_group.mlops.location
  resource_group_name     = azurerm_resource_group.mlops.name
  storage_account_id      = azurerm_storage_account.mlops_storage.id
  key_vault_id            = azurerm_key_vault.mlops_kv.id
  application_insights_id = azurerm_application_insights.mlops_insights.id
  container_registry_id   = azurerm_container_registry.mlops_acr.id

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Purpose     = "ML Workspace"
    Environment = var.environment
  }
}

# Create AKS cluster with ML extensions
resource "azurerm_kubernetes_cluster" "mlops_aks" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.mlops.location
  resource_group_name = azurerm_resource_group.mlops.name
  dns_prefix          = "${var.aks_cluster_name}-dns"

  default_node_pool {
    name                = "system"
    node_count          = var.aks_system_node_count
    vm_size             = var.aks_system_vm_size
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    min_count           = var.aks_system_min_nodes
    max_count           = var.aks_system_max_nodes
    os_disk_size_gb     = 30
    
    tags = {
      Purpose     = "AKS System Pool"
      Environment = var.environment
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Enable monitoring addon
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.mlops_logs.id
  }

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = {
    Purpose     = "ML Compute Cluster"
    Environment = var.environment
  }
}

# Create additional user node pool for ML workloads
resource "azurerm_kubernetes_cluster_node_pool" "ml_pool" {
  name                  = "mlpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.mlops_aks.id
  vm_size               = var.aks_ml_vm_size
  node_count            = var.aks_ml_node_count
  enable_auto_scaling   = true
  min_count             = var.aks_ml_min_nodes
  max_count             = var.aks_ml_max_nodes
  mode                  = "User"
  os_disk_size_gb       = 30

  node_taints = [
    "workload=ml:NoSchedule"
  ]

  tags = {
    Purpose     = "ML Workload Pool"
    Environment = var.environment
  }
}

# Grant AKS access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.mlops_acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.mlops_aks.kubelet_identity[0].object_id
}

# Create diagnostic settings for AKS
resource "azurerm_monitor_diagnostic_setting" "aks_diagnostics" {
  name                       = "aks-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.mlops_aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.mlops_logs.id

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

    retention_policy {
      enabled = true
      days    = 30
    }
  }
}

# Create action group for alerts
resource "azurerm_monitor_action_group" "mlops_alerts" {
  name                = "${var.resource_group_name}-alerts"
  resource_group_name = azurerm_resource_group.mlops.name
  short_name          = "mlops-ag"

  email_receiver {
    name          = "admin"
    email_address = var.alert_email
  }

  tags = {
    Purpose     = "ML Alerting"
    Environment = var.environment
  }
}

# Create metric alert for high response time
resource "azurerm_monitor_metric_alert" "high_latency" {
  name                = "high-latency-alert"
  resource_group_name = azurerm_resource_group.mlops.name
  scopes              = [azurerm_kubernetes_cluster.mlops_aks.id]
  description         = "Alert when response time is high"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.mlops_alerts.id
  }

  tags = {
    Purpose     = "ML Monitoring"
    Environment = var.environment
  }
}

# Data source for current Azure configuration
data "azurerm_client_config" "current" {}