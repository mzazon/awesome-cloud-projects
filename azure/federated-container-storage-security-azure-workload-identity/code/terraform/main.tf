# Main Terraform configuration for Azure Workload Identity and Container Storage

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for computed names and configurations
locals {
  resource_group_name    = var.resource_group_name != null ? var.resource_group_name : "rg-workload-identity-${random_string.suffix.result}"
  aks_cluster_name      = var.aks_cluster_name != null ? var.aks_cluster_name : "aks-workload-identity-${random_string.suffix.result}"
  key_vault_name        = var.key_vault_name != null ? var.key_vault_name : "kv-workload-${random_string.suffix.result}"
  managed_identity_name = var.managed_identity_name != null ? var.managed_identity_name : "workload-identity-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    created-by = "terraform"
    recipe     = "securing-ephemeral-workload-storage"
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# User-assigned Managed Identity for Workload Identity
resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = local.managed_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Azure Key Vault for secrets management
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku
  
  # Enable Azure RBAC for access control
  enable_rbac_authorization = true
  
  # Soft delete configuration
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  
  tags = local.common_tags
}

# Sample secret for testing Key Vault access
resource "azurerm_key_vault_secret" "storage_encryption_key" {
  name         = "storage-encryption-key"
  value        = "demo-encryption-key-value"
  key_vault_id = azurerm_key_vault.main.id
  
  tags = local.common_tags
  
  depends_on = [azurerm_role_assignment.current_user_kv_admin]
}

# Grant current user Key Vault Administrator role for secret creation
resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant managed identity Key Vault Secrets User role
resource "azurerm_role_assignment" "workload_identity_kv_access" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
}

# AKS Cluster with Workload Identity and OIDC Issuer enabled
resource "azurerm_kubernetes_cluster" "aks" {
  name                = local.aks_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.aks_cluster_name}-dns"
  kubernetes_version  = var.kubernetes_version
  
  # Enable Workload Identity and OIDC Issuer
  workload_identity_enabled = true
  oidc_issuer_enabled      = true
  
  # Default node pool configuration
  default_node_pool {
    name                = "nodepool1"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    type                = "VirtualMachineScaleSets"
    zones               = ["1", "2", "3"]
    enable_auto_scaling = true
    min_count          = 1
    max_count          = 5
    
    # Enable ephemeral OS disk for better performance
    os_disk_type    = "Ephemeral"
    os_disk_size_gb = 30
    
    tags = local.common_tags
  }
  
  # Managed identity configuration
  identity {
    type = "SystemAssigned"
  }
  
  # Network configuration
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    dns_service_ip    = "10.2.0.10"
    service_cidr      = "10.2.0.0/24"
    load_balancer_sku = "standard"
  }
  
  # Enable various add-ons
  azure_policy_enabled             = true
  http_application_routing_enabled = false
  
  tags = local.common_tags
}

# Wait for AKS cluster to be fully provisioned
resource "time_sleep" "aks_provisioning" {
  depends_on      = [azurerm_kubernetes_cluster.aks]
  create_duration = "30s"
}

# Azure Container Storage extension
resource "azurerm_kubernetes_cluster_extension" "container_storage" {
  count            = var.enable_container_storage ? 1 : 0
  name             = "azure-container-storage"
  cluster_id       = azurerm_kubernetes_cluster.aks.id
  extension_type   = "microsoft.azurecontainerstorage"
  release_namespace = var.container_storage_release_namespace
  
  # Disable auto-upgrade for demo purposes
  configuration_settings = {
    "autoUpgrade.enabled" = "false"
  }
  
  depends_on = [time_sleep.aks_provisioning]
}

# Wait for Container Storage extension to be ready
resource "time_sleep" "container_storage_provisioning" {
  count           = var.enable_container_storage ? 1 : 0
  depends_on      = [azurerm_kubernetes_cluster_extension.container_storage[0]]
  create_duration = "60s"
}

# Federated Credential for Workload Identity
resource "azurerm_federated_identity_credential" "workload_identity" {
  name                = "workload-identity-federation"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.workload_identity.id
  subject             = "system:serviceaccount:${var.namespace_name}:${var.service_account_name}"
}

# Kubernetes namespace for workload identity demo
resource "kubernetes_namespace" "workload_identity_demo" {
  metadata {
    name = var.namespace_name
    labels = {
      "azure.workload.identity/system-namespace" = "true"
    }
  }
  
  depends_on = [time_sleep.aks_provisioning]
}

# Kubernetes service account with workload identity annotations
resource "kubernetes_service_account" "workload_identity" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.workload_identity_demo.metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload_identity.client_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }
}

# Storage Pool for ephemeral workloads (applied via kubectl)
resource "kubernetes_manifest" "storage_pool" {
  count = var.enable_container_storage ? 1 : 0
  
  manifest = {
    apiVersion = "containerstorage.azure.com/v1"
    kind       = "StoragePool"
    metadata = {
      name      = "ephemeral-pool"
      namespace = var.container_storage_release_namespace
    }
    spec = {
      poolType = {
        ephemeralDisk = {
          diskType = "temp"
          diskSize = "${var.storage_pool_size}Gi"
        }
      }
      nodePoolName   = "nodepool1"
      reclaimPolicy  = "Delete"
    }
  }
  
  depends_on = [time_sleep.container_storage_provisioning[0]]
}

# Storage Class for ephemeral storage
resource "kubernetes_storage_class_v1" "ephemeral_storage" {
  count = var.enable_container_storage ? 1 : 0
  
  metadata {
    name = "ephemeral-storage"
  }
  
  storage_provisioner    = "containerstorage.csi.azure.com"
  volume_binding_mode   = "Immediate"
  reclaim_policy        = "Delete"
  allow_volume_expansion = true
  
  parameters = {
    protocol     = "nfs"
    storagePool  = "ephemeral-pool"
    server       = "ephemeral-pool.${var.container_storage_release_namespace}.svc.cluster.local"
  }
  
  depends_on = [kubernetes_manifest.storage_pool[0]]
}

# Persistent Volume Claim for ephemeral storage
resource "kubernetes_persistent_volume_claim_v1" "ephemeral_pvc" {
  count = var.enable_test_workload && var.enable_container_storage ? 1 : 0
  
  metadata {
    name      = "ephemeral-pvc"
    namespace = kubernetes_namespace.workload_identity_demo.metadata[0].name
  }
  
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class_v1.ephemeral_storage[0].metadata[0].name
    
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

# Test workload deployment
resource "kubernetes_deployment_v1" "workload_identity_test" {
  count = var.enable_test_workload ? 1 : 0
  
  metadata {
    name      = "workload-identity-test"
    namespace = kubernetes_namespace.workload_identity_demo.metadata[0].name
    labels = {
      app = "workload-identity-test"
    }
  }
  
  spec {
    replicas = 1
    
    selector {
      match_labels = {
        app = "workload-identity-test"
      }
    }
    
    template {
      metadata {
        labels = {
          app                              = "workload-identity-test"
          "azure.workload.identity/use"   = "true"
        }
      }
      
      spec {
        service_account_name = kubernetes_service_account.workload_identity.metadata[0].name
        
        container {
          name  = "test-container"
          image = "mcr.microsoft.com/azure-cli:latest"
          
          command = ["/bin/bash"]
          args = [
            "-c",
            <<-EOT
              echo "Installing Azure Identity SDK..."
              pip install azure-identity azure-keyvault-secrets
              echo "Starting workload identity test..."
              while true; do
                echo "Testing Key Vault access with workload identity..."
                python3 -c "
              from azure.identity import DefaultAzureCredential
              from azure.keyvault.secrets import SecretClient
              import os
              
              # Use workload identity for authentication
              credential = DefaultAzureCredential()
              vault_url = 'https://${azurerm_key_vault.main.name}.vault.azure.net/'
              client = SecretClient(vault_url=vault_url, credential=credential)
              
              try:
                  secret = client.get_secret('storage-encryption-key')
                  print(f'Successfully retrieved secret: {secret.name}')
                  
                  # Test ephemeral storage access
                  with open('/ephemeral-storage/test-file.txt', 'w') as f:
                      f.write('Workload identity test successful!')
                  
                  with open('/ephemeral-storage/test-file.txt', 'r') as f:
                      content = f.read()
                  print(f'Ephemeral storage test: {content}')
                  
              except Exception as e:
                  print(f'Error: {e}')
                "
                echo "Test completed. Sleeping for 30 seconds..."
                sleep 30
              done
            EOT
          ]
          
          dynamic "volume_mount" {
            for_each = var.enable_container_storage ? [1] : []
            content {
              name       = "ephemeral-storage"
              mount_path = "/ephemeral-storage"
            }
          }
          
          env {
            name  = "AZURE_CLIENT_ID"
            value = azurerm_user_assigned_identity.workload_identity.client_id
          }
          
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
        
        dynamic "volume" {
          for_each = var.enable_container_storage && var.enable_test_workload ? [1] : []
          content {
            name = "ephemeral-storage"
            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim_v1.ephemeral_pvc[0].metadata[0].name
            }
          }
        }
      }
    }
  }
  
  depends_on = [
    azurerm_federated_identity_credential.workload_identity,
    azurerm_role_assignment.workload_identity_kv_access
  ]
}