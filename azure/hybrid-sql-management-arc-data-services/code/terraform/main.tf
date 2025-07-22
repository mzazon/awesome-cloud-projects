# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source for current subscription
data "azurerm_subscription" "current" {}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.log_analytics_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create AKS cluster (if create_aks_cluster is true)
resource "azurerm_kubernetes_cluster" "main" {
  count               = var.create_aks_cluster ? 1 : 0
  name                = "aks-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-${random_string.suffix.result}"
  kubernetes_version  = var.aks_kubernetes_version

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  tags = var.tags
}

# Data source for existing Kubernetes cluster (if not creating new one)
data "azurerm_kubernetes_cluster" "main" {
  name                = var.create_aks_cluster ? azurerm_kubernetes_cluster.main[0].name : var.kubernetes_cluster_name
  resource_group_name = var.create_aks_cluster ? azurerm_resource_group.main.name : var.kubernetes_cluster_resource_group
}

# Create Azure Arc-enabled Kubernetes cluster
resource "azapi_resource" "arc_kubernetes" {
  depends_on = [
    azurerm_kubernetes_cluster.main
  ]
  
  type      = "Microsoft.Kubernetes/connectedClusters@2024-01-01"
  name      = "arc-k8s-${random_string.suffix.result}"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  body = jsonencode({
    properties = {
      agentPublicKeyCertificate = ""
      kubernetesVersion        = var.aks_kubernetes_version
      totalNodeCount           = var.aks_node_count
      totalCoreCount           = var.aks_node_count * 2
      
      # Arc agent configuration
      arcAgentProfile = {
        desiredAgentVersion = "1.13.0"
        agentAutoUpgrade   = "Enabled"
      }
      
      # RBAC configuration
      rbac = {
        enabled = var.enable_rbac
      }
    }
  })

  tags = var.tags
}

# Create namespace for Arc Data Controller
resource "kubernetes_namespace" "arc" {
  depends_on = [
    azapi_resource.arc_kubernetes
  ]
  
  metadata {
    name = var.arc_data_controller_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "azure-arc-data-services"
    }
  }
}

# Create secret for SQL MI admin credentials
resource "kubernetes_secret" "sql_login" {
  depends_on = [
    kubernetes_namespace.arc
  ]
  
  metadata {
    name      = "sql-login-secret"
    namespace = var.arc_data_controller_namespace
  }

  data = {
    username = var.sql_mi_admin_username
    password = var.sql_mi_admin_password != "" ? var.sql_mi_admin_password : "MySecurePassword123!"
  }

  type = "Opaque"
}

# Create Azure Arc Data Controller using Azure API
resource "azapi_resource" "arc_data_controller" {
  depends_on = [
    kubernetes_namespace.arc,
    azurerm_log_analytics_workspace.main
  ]
  
  type      = "Microsoft.AzureArcData/dataControllers@2023-01-15-preview"
  name      = "${var.arc_data_controller_name}-${random_string.suffix.result}"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  body = jsonencode({
    properties = {
      # Basic configuration
      infrastructure = "kubernetes"
      onPremiseProperty = {
        id = azapi_resource.arc_kubernetes.id
      }
      
      # Kubernetes configuration
      k8sRaw = {
        spec = {
          docker = {
            registry     = "mcr.microsoft.com"
            repository   = "arcdata"
            imageTag     = "v1.25.0_2023-11-14"
            imagePullPolicy = "IfNotPresent"
          }
          
          controller = {
            replicas = 1
            resources = {
              requests = {
                cpu    = "100m"
                memory = "128Mi"
              }
              limits = {
                cpu    = "1000m"
                memory = "2Gi"
              }
            }
          }
          
          # Storage configuration
          storage = {
            data = {
              className = var.sql_mi_storage_class
              size      = "10Gi"
            }
            logs = {
              className = var.sql_mi_storage_class
              size      = "5Gi"
            }
          }
          
          # Security configuration
          security = {
            allowDumps      = false
            allowNodeMetricsCollection = true
            allowPodMetricsCollection  = true
            allowRunAsRoot  = false
          }
        }
      }
      
      # Monitoring configuration
      monitoring = {
        enabled = var.enable_monitoring
        logAnalyticsWorkspaceConfig = var.enable_monitoring ? {
          workspaceId = azurerm_log_analytics_workspace.main.workspace_id
          primaryKey  = azurerm_log_analytics_workspace.main.primary_shared_key
        } : null
      }
      
      # Upload configuration
      uploadServicePrincipal = {
        clientId     = data.azurerm_client_config.current.client_id
        tenantId     = data.azurerm_client_config.current.tenant_id
        authority    = "https://login.microsoftonline.com"
        clientSecret = ""
      }
    }
    
    # Extended location for Arc
    extendedLocation = {
      name = azapi_resource.arc_kubernetes.id
      type = "ConnectedCluster"
    }
  })

  tags = var.tags
}

# Create SQL Managed Instance
resource "azapi_resource" "sql_managed_instance" {
  depends_on = [
    azapi_resource.arc_data_controller,
    kubernetes_secret.sql_login
  ]
  
  type      = "Microsoft.AzureArcData/sqlManagedInstances@2023-01-15-preview"
  name      = "${var.sql_mi_name}-${random_string.suffix.result}"
  location  = azurerm_resource_group.main.location
  parent_id = azurerm_resource_group.main.id

  body = jsonencode({
    properties = {
      # Basic configuration
      dataControllerId = azapi_resource.arc_data_controller.id
      admin            = var.sql_mi_admin_username
      
      # Kubernetes configuration
      k8sRaw = {
        spec = {
          # Compute resources
          dev = true
          tier = var.sql_mi_service_tier
          
          # Resource limits
          limits = {
            cpu    = "${var.sql_mi_cores_limit}"
            memory = var.sql_mi_memory_limit
          }
          
          # Resource requests
          requests = {
            cpu    = "${var.sql_mi_cores_request}"
            memory = var.sql_mi_memory_request
          }
          
          # Storage configuration
          storage = {
            data = {
              className = var.sql_mi_storage_class
              size      = var.sql_mi_data_volume_size
            }
            logs = {
              className = var.sql_mi_storage_class
              size      = var.sql_mi_logs_volume_size
            }
          }
          
          # Security configuration
          security = {
            adminLoginSecret = kubernetes_secret.sql_login.metadata[0].name
          }
          
          # Service configuration
          service = {
            type = "LoadBalancer"
            annotations = {
              "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
            }
          }
          
          # Backup configuration
          backup = {
            retentionPeriodInDays = 7
            recoveryModel         = "Full"
          }
        }
      }
    }
    
    # Extended location for Arc
    extendedLocation = {
      name = azapi_resource.arc_kubernetes.id
      type = "ConnectedCluster"
    }
  })

  tags = var.tags
}

# Create Action Group for alerts
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_alerting ? 1 : 0
  name                = "arc-sql-alerts-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "arcsql"

  email_receiver {
    name          = "admin"
    email_address = var.alert_email
  }

  tags = var.tags
}

# Create CPU utilization alert
resource "azurerm_monitor_metric_alert" "cpu_alert" {
  count               = var.enable_alerting ? 1 : 0
  name                = "arc-sql-high-cpu-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azapi_resource.sql_managed_instance.id]
  description         = "High CPU usage on Arc SQL MI"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.AzureArcData/sqlManagedInstances"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  depends_on = [
    azapi_resource.sql_managed_instance
  ]

  tags = var.tags
}

# Create storage utilization alert
resource "azurerm_monitor_metric_alert" "storage_alert" {
  count               = var.enable_alerting ? 1 : 0
  name                = "arc-sql-low-storage-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azapi_resource.sql_managed_instance.id]
  description         = "Low storage space on Arc SQL MI"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.AzureArcData/sqlManagedInstances"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.storage_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  depends_on = [
    azapi_resource.sql_managed_instance
  ]

  tags = var.tags
}

# Create Azure Policy assignment for security
resource "azurerm_resource_policy_assignment" "arc_security" {
  count                = var.enable_azure_policy ? 1 : 0
  name                 = "arc-sql-security-policy-${random_string.suffix.result}"
  resource_id          = azurerm_resource_group.main.id
  policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/89c8a434-18f2-449b-9327-9579c0b9c2f2"
  display_name         = "Arc SQL Security Policy"
  description          = "Security policy for Arc-enabled SQL resources"
  
  depends_on = [
    azapi_resource.sql_managed_instance
  ]
}

# Create Azure Monitor Workbook for custom dashboard
resource "azurerm_application_insights_workbook" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "arc-sql-monitoring-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Arc SQL Monitoring Dashboard"
  source_id           = azurerm_log_analytics_workspace.main.id
  category            = "workbook"

  # Basic workbook template with CPU and memory monitoring
  serialized_data = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Azure Arc SQL Managed Instance Monitoring Dashboard\n\nThis dashboard provides monitoring insights for your Arc-enabled SQL Managed Instance."
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "Perf | where CounterName == \"Processor(_Total)\\\\% Processor Time\" | summarize avg(CounterValue) by bin(TimeGenerated, 5m) | render timechart"
          size = 0
          title = "CPU Utilization"
          queryType = 0
          visualization = "timechart"
          resourceType = "microsoft.operationalinsights/workspaces"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "Perf | where CounterName == \"Memory\\\\Available MBytes\" | summarize avg(CounterValue) by bin(TimeGenerated, 5m) | render timechart"
          size = 0
          title = "Available Memory"
          queryType = 0
          visualization = "timechart"
          resourceType = "microsoft.operationalinsights/workspaces"
        }
      },
      {
        type = 3
        content = {
          version = "KqlItem/1.0"
          query = "KubePodInventory | where Namespace == \"arc\" | summarize count() by PodStatus | render piechart"
          size = 0
          title = "Pod Status Distribution"
          queryType = 0
          visualization = "piechart"
          resourceType = "microsoft.operationalinsights/workspaces"
        }
      }
    ]
  })

  tags = var.tags
}

# Create diagnostic settings for Arc Data Controller
resource "azurerm_monitor_diagnostic_setting" "arc_data_controller" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "arc-dc-diagnostics"
  target_resource_id = azapi_resource.arc_data_controller.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ArcDataControllerLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [
    azapi_resource.arc_data_controller
  ]
}

# Create diagnostic settings for SQL Managed Instance
resource "azurerm_monitor_diagnostic_setting" "sql_managed_instance" {
  count              = var.enable_monitoring ? 1 : 0
  name               = "arc-sql-diagnostics"
  target_resource_id = azapi_resource.sql_managed_instance.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "SqlManagedInstanceLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [
    azapi_resource.sql_managed_instance
  ]
}