# Main Terraform configuration for Azure GitOps CI/CD with Workload Identity and ArgoCD
# This configuration implements secure GitOps workflows with keyless authentication

# Data sources for current subscription and client configuration
data "azurerm_client_config" "current" {}
data "azuread_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Construct unique names using the random suffix
  key_vault_name         = "${var.key_vault_name}-${random_id.suffix.hex}"
  managed_identity_name  = "${var.managed_identity_name}-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge(var.common_tags, {
    DeployedAt = timestamp()
  })
}

# Resource Group for all GitOps resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# User-Assigned Managed Identity for ArgoCD workload identity
resource "azurerm_user_assigned_identity" "argocd" {
  name                = local.managed_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Azure Key Vault for secure secret storage
resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Enable RBAC authorization for modern access control
  enable_rbac_authorization = true

  # Security settings
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Network ACLs - allowing all networks for demo purposes
  # In production, restrict to specific networks
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = local.common_tags
}

# Store sample secrets in Key Vault for demonstration
resource "azurerm_key_vault_secret" "sample_secrets" {
  for_each = var.sample_secrets

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.current_user_kv_admin]
}

# Grant current user Key Vault Administrator role for secret management
resource "azurerm_role_assignment" "current_user_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant managed identity Key Vault Secrets User role
resource "azurerm_role_assignment" "mi_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.argocd.principal_id

  depends_on = [azurerm_user_assigned_identity.argocd]
}

# Log Analytics Workspace for AKS monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_azure_monitor ? 1 : 0

  name                = "law-${var.cluster_name}-${random_id.suffix.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

# AKS Cluster with Workload Identity and OIDC Issuer
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  # Default node pool configuration
  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = false
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"

    # Enable workload identity and other features
    workload_runtime = "OCIContainer"
  }

  # System-assigned managed identity for AKS
  identity {
    type = "SystemAssigned"
  }

  # Enable OIDC issuer for workload identity federation
  oidc_issuer_enabled = true

  # Enable workload identity
  workload_identity_enabled = true

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    network_policy    = var.enable_network_policy != "" ? var.enable_network_policy : null
    load_balancer_sku = "standard"
    service_cidr      = "10.0.0.0/16"
    dns_service_ip    = "10.0.0.10"
  }

  # Azure Monitor addon for container insights
  dynamic "oms_agent" {
    for_each = var.enable_azure_monitor ? [1] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
    }
  }

  # Azure Policy addon
  dynamic "azure_policy_enabled" {
    for_each = var.enable_azure_policy ? [true] : []
    content {
      enabled = true
    }
  }

  # Key Vault Secrets Provider addon for CSI driver
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.current_user_kv_admin,
    azurerm_log_analytics_workspace.main
  ]
}

# Federated Identity Credential for ArgoCD Application Controller
resource "azurerm_federated_identity_credential" "argocd_application_controller" {
  name                = "argocd-application-controller"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.argocd.id
  subject             = "system:serviceaccount:${var.argocd_namespace}:argocd-application-controller"

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Federated Identity Credential for ArgoCD Server
resource "azurerm_federated_identity_credential" "argocd_server" {
  name                = "argocd-server"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.argocd.id
  subject             = "system:serviceaccount:${var.argocd_namespace}:argocd-server"

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Federated Identity Credential for Sample Application
resource "azurerm_federated_identity_credential" "sample_app" {
  name                = "sample-app"
  resource_group_name = azurerm_resource_group.main.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.argocd.id
  subject             = "system:serviceaccount:${var.sample_app_namespace}:sample-app-sa"

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      name                              = var.argocd_namespace
      "azure.workload.identity/use"     = "true"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Sample application namespace
resource "kubernetes_namespace" "sample_app" {
  metadata {
    name = var.sample_app_namespace
    labels = {
      name                              = var.sample_app_namespace
      "azure.workload.identity/use"     = "true"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# ArgoCD Helm installation
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # ArgoCD configuration values
  values = [
    yamlencode({
      # Global settings
      global = {
        domain = "argocd.example.com"
      }

      # Server configuration
      server = {
        service = {
          type = var.enable_argocd_ui_loadbalancer ? "LoadBalancer" : "ClusterIP"
        }
        # Enable insecure mode for demo purposes
        extraArgs = ["--insecure"]
      }

      # Application controller configuration
      controller = {
        serviceAccount = {
          annotations = {
            "azure.workload.identity/client-id" = azurerm_user_assigned_identity.argocd.client_id
          }
        }
      }

      # Server service account configuration
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.argocd.client_id
        }
      }

      # Configs
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    azurerm_federated_identity_credential.argocd_application_controller,
    azurerm_federated_identity_credential.argocd_server
  ]
}

# Service account for sample application
resource "kubernetes_service_account" "sample_app" {
  metadata {
    name      = "sample-app-sa"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.argocd.client_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }

  depends_on = [
    kubernetes_namespace.sample_app,
    azurerm_federated_identity_credential.sample_app
  ]
}

# SecretProviderClass for Key Vault integration
resource "kubernetes_manifest" "secret_provider_class" {
  manifest = {
    apiVersion = "secrets-store.csi.x-k8s.io/v1"
    kind       = "SecretProviderClass"
    metadata = {
      name      = "sample-app-secrets"
      namespace = kubernetes_namespace.sample_app.metadata[0].name
    }
    spec = {
      provider = "azure"
      parameters = {
        usePodIdentity              = "false"
        useVMManagedIdentity        = "false"
        userAssignedIdentityID      = azurerm_user_assigned_identity.argocd.client_id
        keyvaultName                = azurerm_key_vault.main.name
        tenantId                    = data.azurerm_client_config.current.tenant_id
        objects = yamlencode({
          array = [
            {
              objectName    = "database-connection-string"
              objectType    = "secret"
              objectVersion = ""
            },
            {
              objectName    = "api-key"
              objectType    = "secret"
              objectVersion = ""
            }
          ]
        })
      }
      secretObjects = [
        {
          secretName = "sample-app-secrets"
          type       = "Opaque"
          data = [
            {
              objectName = "database-connection-string"
              key        = "database-connection-string"
            },
            {
              objectName = "api-key"
              key        = "api-key"
            }
          ]
        }
      ]
    }
  }

  depends_on = [
    kubernetes_namespace.sample_app,
    azurerm_key_vault_secret.sample_secrets,
    kubernetes_service_account.sample_app
  ]
}

# Sample application deployment
resource "kubernetes_deployment" "sample_app" {
  metadata {
    name      = "sample-app"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
    labels = {
      app = "sample-app"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sample-app"
      }
    }

    template {
      metadata {
        labels = {
          app                               = "sample-app"
          "azure.workload.identity/use"     = "true"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.sample_app.metadata[0].name

        container {
          name  = "sample-app"
          image = "nginx:latest"

          port {
            container_port = 80
          }

          volume_mount {
            name       = "secrets-store"
            mount_path = "/mnt/secrets"
            read_only  = true
          }

          env {
            name = "DATABASE_CONNECTION_STRING"
            value_from {
              secret_key_ref {
                name = "sample-app-secrets"
                key  = "database-connection-string"
              }
            }
          }

          env {
            name = "API_KEY"
            value_from {
              secret_key_ref {
                name = "sample-app-secrets"
                key  = "api-key"
              }
            }
          }
        }

        volume {
          name = "secrets-store"
          csi {
            driver   = "secrets-store.csi.k8s.io"
            read_only = true
            volume_attributes = {
              secretProviderClass = kubernetes_manifest.secret_provider_class.manifest.metadata.name
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.secret_provider_class,
    kubernetes_service_account.sample_app
  ]
}

# ArgoCD Application for GitOps deployment
resource "kubernetes_manifest" "argocd_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "sample-app-gitops"
      namespace = kubernetes_namespace.argocd.metadata[0].name
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repository_url
        targetRevision = var.git_target_revision
        path           = var.git_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.sample_app.metadata[0].name
      }
      syncPolicy = var.auto_sync_enabled ? {
        automated = {
          prune    = var.prune_enabled
          selfHeal = var.self_heal_enabled
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      } : null
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.sample_app
  ]
}

# Optional: Expose ArgoCD UI via LoadBalancer
resource "kubernetes_service" "argocd_server_lb" {
  count = var.enable_argocd_ui_loadbalancer ? 1 : 0

  metadata {
    name      = "argocd-server-lb"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  spec {
    type = "LoadBalancer"

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      "app.kubernetes.io/component" = "server"
      "app.kubernetes.io/name"      = "argocd-server"
      "app.kubernetes.io/part-of"   = "argocd"
    }
  }

  depends_on = [helm_release.argocd]
}