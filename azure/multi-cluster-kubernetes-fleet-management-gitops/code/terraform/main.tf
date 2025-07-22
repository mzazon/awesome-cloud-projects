# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Azure Kubernetes Fleet Manager
resource "azurerm_kubernetes_fleet_manager" "main" {
  name                = var.fleet_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags

  depends_on = [azurerm_resource_group.main]
}

# Create AKS clusters in different regions
resource "azurerm_kubernetes_cluster" "clusters" {
  count               = length(var.regions)
  name                = "${var.aks_cluster_prefix}-${count.index + 1}"
  location            = var.regions[count.index]
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.aks_cluster_prefix}-${count.index + 1}"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    node_count          = var.aks_node_count
    vm_size             = var.aks_node_vm_size
    type                = "VirtualMachineScaleSets"
    os_disk_size_gb     = 30
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 5
    
    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }

  # Network configuration
  network_profile {
    network_plugin = var.network_plugin
    network_policy = var.network_policy
    service_cidr   = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
  }

  # Enable Azure AD integration
  azure_active_directory_role_based_access_control {
    managed = true
  }

  # Enable Azure Policy
  azure_policy_enabled = true

  tags = merge(var.tags, {
    fleet  = "demo"
    region = var.regions[count.index]
  })

  depends_on = [azurerm_resource_group.main]
}

# Create fleet members (join AKS clusters to fleet)
resource "azurerm_kubernetes_fleet_member" "members" {
  count                   = length(azurerm_kubernetes_cluster.clusters)
  name                    = "member-${count.index + 1}"
  kubernetes_fleet_id     = azurerm_kubernetes_fleet_manager.main.id
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.clusters[count.index].id
  group                   = count.index == 0 ? "test-group" : "prod-group"

  depends_on = [
    azurerm_kubernetes_fleet_manager.main,
    azurerm_kubernetes_cluster.clusters
  ]
}

# Create service principal for Azure Service Operator
resource "azuread_application" "aso" {
  display_name = "${var.aso_service_principal_name}-${random_string.suffix.result}"
}

resource "azuread_service_principal" "aso" {
  application_id = azuread_application.aso.application_id
}

resource "azuread_service_principal_password" "aso" {
  service_principal_id = azuread_service_principal.aso.object_id
  end_date_relative    = "8760h" # 1 year
}

# Assign Contributor role to service principal
resource "azurerm_role_assignment" "aso_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.aso.object_id
}

# Create Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = "${var.acr_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false

  quarantine_policy_enabled = false
  trust_policy_enabled      = false
  
  retention_policy {
    days    = 7
    enabled = false
  }

  tags = var.tags

  depends_on = [azurerm_resource_group.main]
}

# Create Azure Key Vault
resource "azurerm_key_vault" "main" {
  name                = "${var.key_vault_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = var.key_vault_sku

  enabled_for_deployment          = true
  enabled_for_disk_encryption     = true
  enabled_for_template_deployment = true
  enable_rbac_authorization       = false
  soft_delete_retention_days      = var.key_vault_soft_delete_retention_days
  purge_protection_enabled        = false

  tags = var.tags

  depends_on = [azurerm_resource_group.main]
}

# Create access policy for current user
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Backup",
    "Restore",
    "Purge"
  ]
}

# Create sample secret in Key Vault
resource "azurerm_key_vault_secret" "database_connection" {
  name         = "database-connection"
  value        = "Server=tcp:myserver.database.windows.net;Database=mydb;User ID=admin;Password=SecureP@ssw0rd!;Encrypt=true"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

# Create storage accounts in each region
resource "azurerm_storage_account" "regional" {
  count               = length(var.regions)
  name                = "${var.storage_account_prefix}${random_string.suffix.result}${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.regions[count.index]

  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = var.storage_account_kind
  access_tier              = var.storage_account_access_tier

  https_traffic_only_enabled = true

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = merge(var.tags, {
    region = var.regions[count.index]
  })

  depends_on = [azurerm_resource_group.main]
}

# Grant AKS clusters access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = length(azurerm_kubernetes_cluster.clusters)
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.clusters[count.index].kubelet_identity[0].object_id
}

# Configure Kubernetes providers for each cluster
data "azurerm_kubernetes_cluster" "clusters" {
  count               = length(azurerm_kubernetes_cluster.clusters)
  name                = azurerm_kubernetes_cluster.clusters[count.index].name
  resource_group_name = azurerm_resource_group.main.name
  depends_on          = [azurerm_kubernetes_cluster.clusters]
}

# Install cert-manager on each cluster
resource "kubernetes_namespace" "cert_manager" {
  count = length(azurerm_kubernetes_cluster.clusters)
  
  provider = kubernetes.cluster1
  
  metadata {
    name = var.cert_manager_namespace
  }
  
  depends_on = [azurerm_kubernetes_cluster.clusters]
}

# Install Azure Service Operator on each cluster using Helm
resource "kubernetes_namespace" "aso" {
  count = length(azurerm_kubernetes_cluster.clusters)
  
  provider = kubernetes.cluster1
  
  metadata {
    name = var.aso_namespace
  }
  
  depends_on = [azurerm_kubernetes_cluster.clusters]
}

# Create Kubernetes secret for ASO authentication
resource "kubernetes_secret" "aso_credentials" {
  count = length(azurerm_kubernetes_cluster.clusters)
  
  provider = kubernetes.cluster1
  
  metadata {
    name      = "aso-credentials"
    namespace = var.aso_namespace
  }

  data = {
    AZURE_SUBSCRIPTION_ID = data.azurerm_client_config.current.subscription_id
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
    AZURE_CLIENT_ID       = azuread_service_principal.aso.application_id
    AZURE_CLIENT_SECRET   = azuread_service_principal_password.aso.value
  }

  depends_on = [
    kubernetes_namespace.aso,
    azuread_service_principal_password.aso
  ]
}

# Create application namespace on each cluster
resource "kubernetes_namespace" "app" {
  count = length(azurerm_kubernetes_cluster.clusters)
  
  provider = kubernetes.cluster1
  
  metadata {
    name = var.app_namespace
  }
  
  depends_on = [azurerm_kubernetes_cluster.clusters]
}

# Create namespace for Azure resources managed by ASO
resource "kubernetes_namespace" "azure_resources" {
  count = length(azurerm_kubernetes_cluster.clusters)
  
  provider = kubernetes.cluster1
  
  metadata {
    name = "azure-resources"
  }
  
  depends_on = [azurerm_kubernetes_cluster.clusters]
}

# Deploy sample application to each cluster
resource "kubernetes_deployment" "regional_app" {
  count = length(azurerm_kubernetes_cluster.clusters)
  
  provider = kubernetes.cluster1
  
  metadata {
    name      = "regional-app"
    namespace = var.app_namespace
    labels = {
      app = "regional-app"
    }
  }

  spec {
    replicas = var.app_replicas

    selector {
      match_labels = {
        app = "regional-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "regional-app"
        }
      }

      spec {
        container {
          image = var.app_image
          name  = "app"

          env {
            name  = "REGION"
            value = var.regions[count.index]
          }

          env {
            name  = "STORAGE_ACCOUNT"
            value = azurerm_storage_account.regional[count.index].name
          }

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.app,
    azurerm_storage_account.regional
  ]
}

# Create service for the application
resource "kubernetes_service" "regional_app" {
  count = length(azurerm_kubernetes_cluster.clusters)
  
  provider = kubernetes.cluster1
  
  metadata {
    name      = "regional-app"
    namespace = var.app_namespace
  }

  spec {
    selector = {
      app = "regional-app"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.regional_app]
}