# Main Terraform configuration for Azure cloud-native service connectivity infrastructure
# This configuration creates the complete infrastructure for implementing cloud-native service connectivity
# with Azure Application Gateway for Containers and Service Connector

# Data sources for current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create User-assigned Managed Identity for workload identity
resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = "wi-connectivity-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

# Create AKS Cluster with workload identity and required configurations
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.cluster_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.cluster_name_prefix}-${random_string.suffix.result}"
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # Default node pool configuration
  default_node_pool {
    name                = "default"
    node_count          = var.enable_auto_scaling ? null : var.node_count
    vm_size             = var.node_vm_size
    enable_auto_scaling = var.enable_auto_scaling
    min_count           = var.enable_auto_scaling ? var.min_node_count : null
    max_count           = var.enable_auto_scaling ? var.max_node_count : null
    tags                = var.tags
  }

  # Identity configuration
  identity {
    type = "SystemAssigned"
  }

  # Enable workload identity
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Enable RBAC
  role_based_access_control_enabled = var.enable_rbac

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    network_policy    = var.enable_network_policy ? "azure" : null
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  # Enable monitoring addon
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Configure private cluster if enabled
  private_cluster_enabled = var.enable_private_cluster

  depends_on = [
    azurerm_log_analytics_workspace.main
  ]
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-analytics-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# Enable Application Gateway for Containers addon
resource "azurerm_kubernetes_cluster_extension" "agc_extension" {
  name           = "alb-controller"
  cluster_id     = azurerm_kubernetes_cluster.main.id
  extension_type = "microsoft.alb.controller"

  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
}

# Create Azure Storage Account for Service Connector integration
resource "azurerm_storage_account" "main" {
  name                     = "storage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  
  # Security configurations
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  
  # Enable secure transfer
  enable_https_traffic_only = true
  
  tags = var.tags
}

# Create Azure SQL Server
resource "azurerm_mssql_server" "main" {
  name                         = "sqlserver-${random_string.suffix.result}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  
  # Enable Azure AD authentication
  azuread_administrator {
    login_username = data.azurerm_client_config.current.object_id
    object_id      = data.azurerm_client_config.current.object_id
  }
  
  tags = var.tags
}

# Create Azure SQL Database
resource "azurerm_mssql_database" "main" {
  name      = "application-db"
  server_id = azurerm_mssql_server.main.id
  sku_name  = var.sql_database_sku
  
  # Configure serverless compute model for Basic SKU
  auto_pause_delay_in_minutes = 60
  min_capacity                = 0.5
  max_size_gb                 = 2
  
  tags = var.tags
}

# Create Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                = "kv-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  
  sku_name = var.key_vault_sku
  
  # Enable RBAC authorization
  enable_rbac_authorization = true
  
  # Network ACLs
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = var.tags
}

# Create sample secrets in Key Vault
resource "azurerm_key_vault_secret" "database_connection_timeout" {
  name         = "database-connection-timeout"
  value        = "30"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_role_assignment.current_user_key_vault_admin
  ]
}

resource "azurerm_key_vault_secret" "api_rate_limit" {
  name         = "api-rate-limit"
  value        = "1000"
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [
    azurerm_role_assignment.current_user_key_vault_admin
  ]
}

# Create federated identity credential for workload identity
resource "azurerm_federated_identity_credential" "main" {
  name                = "aks-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.workload_identity.id
  subject             = "system:serviceaccount:${var.namespace_name}:${var.service_account_name}"
  
  depends_on = [
    azurerm_kubernetes_cluster.main,
    azurerm_user_assigned_identity.workload_identity
  ]
}

# Role assignment: Storage Blob Data Contributor for managed identity
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  
  depends_on = [
    azurerm_storage_account.main,
    azurerm_user_assigned_identity.workload_identity
  ]
}

# Role assignment: SQL DB Contributor for managed identity
resource "azurerm_role_assignment" "sql_db_contributor" {
  scope                = azurerm_mssql_database.main.id
  role_definition_name = "SQL DB Contributor"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  
  depends_on = [
    azurerm_mssql_database.main,
    azurerm_user_assigned_identity.workload_identity
  ]
}

# Role assignment: Key Vault Secrets User for managed identity
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  
  depends_on = [
    azurerm_key_vault.main,
    azurerm_user_assigned_identity.workload_identity
  ]
}

# Role assignment: Key Vault Administrator for current user (to create secrets)
resource "azurerm_role_assignment" "current_user_key_vault_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
  
  depends_on = [
    azurerm_key_vault.main
  ]
}

# Role assignment: AKS cluster access for managed identity
resource "azurerm_role_assignment" "aks_cluster_contributor" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  
  depends_on = [
    azurerm_kubernetes_cluster.main,
    azurerm_user_assigned_identity.workload_identity
  ]
}

# Allow Azure services to access SQL Server
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Create Application Gateway for Containers (this is a placeholder as the actual resource type may vary)
# Note: Application Gateway for Containers resources might need specific provider version or preview features
resource "null_resource" "application_gateway_for_containers" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Application Gateway for Containers would be created here"
      echo "This may require specific Azure CLI commands or preview features"
      echo "Resource Group: ${azurerm_resource_group.main.name}"
      echo "Location: ${azurerm_resource_group.main.location}"
      echo "AKS Cluster: ${azurerm_kubernetes_cluster.main.name}"
    EOT
  }
  
  depends_on = [
    azurerm_kubernetes_cluster.main,
    azurerm_kubernetes_cluster_extension.agc_extension
  ]
}

# Output important values for post-deployment configuration
output "post_deployment_commands" {
  value = <<-EOT
    # Commands to run after Terraform deployment:
    
    # 1. Get AKS credentials
    az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing
    
    # 2. Create Kubernetes namespace
    kubectl create namespace ${var.namespace_name}
    
    # 3. Create service account with workload identity annotation
    kubectl create serviceaccount ${var.service_account_name} --namespace ${var.namespace_name}
    kubectl annotate serviceaccount ${var.service_account_name} --namespace ${var.namespace_name} azure.workload.identity/client-id=${azurerm_user_assigned_identity.workload_identity.client_id}
    
    # 4. Create Application Gateway for Containers resource (if not automated)
    az network application-gateway for-containers create \
      --resource-group ${azurerm_resource_group.main.name} \
      --name agc-connectivity-${random_string.suffix.result} \
      --location ${azurerm_resource_group.main.location} \
      --frontend-configurations '[{"name": "frontend-config", "port": 80, "protocol": "Http"}]'
    
    # 5. Apply Gateway API resources and application deployments using kubectl
    # (Gateway, HTTPRoute, and application deployments as shown in the recipe)
    
    # 6. Create Service Connector connections using Azure CLI
    # (Storage, SQL, and Key Vault connections as shown in the recipe)
  EOT
}