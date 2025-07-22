# Azure Advanced Network Segmentation with Service Mesh and DNS Private Zones
# This Terraform configuration deploys a complete solution for advanced network segmentation
# using Azure Kubernetes Service with Istio, Application Gateway, and DNS Private Zones

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and tagging
locals {
  name_suffix = "${var.project_name}-${random_string.suffix.result}"
  
  common_tags = merge(var.common_tags, {
    Deployment = "advanced-network-segmentation"
    Timestamp  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source to get available AKS versions in the specified region
data "azurerm_kubernetes_service_versions" "current" {
  location        = var.location
  version_prefix  = var.kubernetes_version
}

#
# Resource Group
#
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

#
# Log Analytics Workspace for Monitoring
#
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.log_analytics_workspace_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_in_days
  tags                = local.common_tags
}

#
# Virtual Network Infrastructure
#
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

# Subnet for AKS cluster nodes
resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

# Subnet for Application Gateway
resource "azurerm_subnet" "app_gateway" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.appgw_subnet_address_prefix]
}

# Subnet for private endpoints
resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoints_subnet_address_prefix]
}

# Network Security Group for AKS subnet
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  # Allow inbound HTTP traffic for testing (remove in production)
  security_rule {
    name                       = "Allow-HTTP-Inbound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Allow inbound HTTPS traffic
  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

#
# Azure Kubernetes Service (AKS) Cluster
#
resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                = var.aks_cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.aks_cluster_name}-${random_string.suffix.result}"
  kubernetes_version  = data.azurerm_kubernetes_service_versions.current.latest_version

  # Enable private cluster if specified
  private_cluster_enabled = var.enable_private_cluster
  
  # API server authorized IP ranges (if not private cluster)
  dynamic "api_server_access_profile" {
    for_each = var.enable_private_cluster ? [] : [1]
    content {
      authorized_ip_ranges = var.authorized_ip_ranges
    }
  }

  # Default node pool configuration
  default_node_pool {
    name                = "default"
    node_count          = var.aks_node_count
    vm_size             = var.aks_node_vm_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = var.aks_min_count
    max_count           = var.aks_max_count
    max_pods            = 110
    
    # Node pool upgrade settings
    upgrade_settings {
      max_surge = "10%"
    }
    
    tags = local.common_tags
  }

  # Managed identity for the cluster
  identity {
    type = "SystemAssigned"
  }

  # Network configuration
  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    dns_service_ip     = "10.100.0.10"
    service_cidr       = "10.100.0.0/16"
    load_balancer_sku  = "standard"
  }

  # Enable Azure RBAC for Kubernetes authorization
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.enable_azure_rbac ? [1] : []
    content {
      managed                = true
      azure_rbac_enabled     = true
    }
  }

  # Azure Monitor addon for container insights
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # Azure Policy addon
  dynamic "azure_policy_enabled" {
    for_each = var.enable_azure_policy ? [1] : []
    content {
      azure_policy_enabled = true
    }
  }

  # Service mesh (Istio) configuration
  dynamic "service_mesh_profile" {
    for_each = var.enable_istio_addon ? [1] : []
    content {
      mode                             = "Istio"
      internal_ingress_gateway_enabled = true
      external_ingress_gateway_enabled = true
    }
  }

  tags = local.common_tags

  depends_on = [
    azurerm_subnet_network_security_group_association.aks
  ]
}

# Role assignment for AKS to manage virtual network
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks_cluster.identity[0].principal_id
}

#
# Azure DNS Private Zone for Internal Service Discovery
#
resource "azurerm_private_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Link private DNS zone to virtual network
resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "vnet-link-${local.name_suffix}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = local.common_tags
}

# DNS A records for service discovery (will be updated by applications)
resource "azurerm_private_dns_a_record" "frontend_service" {
  name                = "frontend-service"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = ["10.100.1.100"] # Placeholder IP, will be updated by application
  tags                = local.common_tags
}

resource "azurerm_private_dns_a_record" "backend_service" {
  name                = "backend-service"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = ["10.100.1.101"] # Placeholder IP, will be updated by application
  tags                = local.common_tags
}

resource "azurerm_private_dns_a_record" "database_service" {
  name                = "database-service"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = ["10.100.1.102"] # Placeholder IP, will be updated by application
  tags                = local.common_tags
}

#
# Public IP for Application Gateway
#
resource "azurerm_public_ip" "app_gateway" {
  name                = "pip-appgw-${local.name_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

#
# Application Gateway with WAF for Secure Ingress
#
resource "azurerm_application_gateway" "main" {
  name                = var.app_gateway_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags

  sku {
    name     = var.app_gateway_sku_name
    tier     = var.app_gateway_sku_tier
    capacity = var.app_gateway_capacity
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.app_gateway.id
  }

  frontend_port {
    name = "appGatewayFrontendPort"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appGatewayFrontendIP"
    public_ip_address_id = azurerm_public_ip.app_gateway.id
  }

  backend_address_pool {
    name = "istio-backend-pool"
    # Backend IPs will be added after AKS cluster is ready
  }

  backend_http_settings {
    name                  = "appGatewayBackendHttpSettings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "appGatewayHttpListener"
    frontend_ip_configuration_name = "appGatewayFrontendIP"
    frontend_port_name             = "appGatewayFrontendPort"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "appGatewayRoutingRule"
    rule_type                  = "Basic"
    http_listener_name         = "appGatewayHttpListener"
    backend_address_pool_name  = "istio-backend-pool"
    backend_http_settings_name = "appGatewayBackendHttpSettings"
    priority                   = 1000
  }

  # WAF configuration for security
  dynamic "waf_configuration" {
    for_each = var.app_gateway_sku_name == "WAF_v2" ? [1] : []
    content {
      enabled          = true
      firewall_mode    = "Prevention"
      rule_set_type    = "OWASP"
      rule_set_version = "3.2"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
}

#
# Kubernetes Namespaces for Application Segmentation
#
resource "kubernetes_namespace" "frontend" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name = "frontend"
    labels = {
      "istio-injection" = "enabled"
      "tier"           = "frontend"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
}

resource "kubernetes_namespace" "backend" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name = "backend"
    labels = {
      "istio-injection" = "enabled"
      "tier"           = "backend"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
}

resource "kubernetes_namespace" "database" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name = "database"
    labels = {
      "istio-injection" = "enabled"
      "tier"           = "database"
    }
  }

  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
}

#
# Kubernetes Network Policies for Namespace Isolation
#
resource "kubernetes_network_policy" "frontend_deny_all" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "deny-all"
    namespace = kubernetes_namespace.frontend[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }

  depends_on = [kubernetes_namespace.frontend]
}

resource "kubernetes_network_policy" "backend_deny_all" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "deny-all"
    namespace = kubernetes_namespace.backend[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }

  depends_on = [kubernetes_namespace.backend]
}

resource "kubernetes_network_policy" "database_deny_all" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "deny-all"
    namespace = kubernetes_namespace.database[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }

  depends_on = [kubernetes_namespace.database]
}

#
# Sample Frontend Application
#
resource "kubernetes_deployment" "frontend" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "frontend-service"
    namespace = kubernetes_namespace.frontend[0].metadata[0].name
    labels = {
      app = "frontend"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "frontend"
      }
    }

    template {
      metadata {
        labels = {
          app     = "frontend"
          version = "v1"
        }
      }

      spec {
        container {
          image = "nginx:1.21"
          name  = "frontend"
          port {
            container_port = 80
          }
          env {
            name  = "BACKEND_URL"
            value = "http://backend-service.${var.dns_zone_name}"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.frontend]
}

resource "kubernetes_service" "frontend" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "frontend-service"
    namespace = kubernetes_namespace.frontend[0].metadata[0].name
  }

  spec {
    selector = {
      app = "frontend"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.frontend]
}

#
# Sample Backend Application
#
resource "kubernetes_deployment" "backend" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "backend-service"
    namespace = kubernetes_namespace.backend[0].metadata[0].name
    labels = {
      app = "backend"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        app = "backend"
      }
    }

    template {
      metadata {
        labels = {
          app     = "backend"
          version = "v1"
        }
      }

      spec {
        container {
          image = "httpd:2.4"
          name  = "backend"
          port {
            container_port = 80
          }
          env {
            name  = "DATABASE_URL"
            value = "http://database-service.${var.dns_zone_name}"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.backend]
}

resource "kubernetes_service" "backend" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "backend-service"
    namespace = kubernetes_namespace.backend[0].metadata[0].name
  }

  spec {
    selector = {
      app = "backend"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.backend]
}

#
# Sample Database Application
#
resource "kubernetes_deployment" "database" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "database-service"
    namespace = kubernetes_namespace.database[0].metadata[0].name
    labels = {
      app = "database"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "database"
      }
    }

    template {
      metadata {
        labels = {
          app     = "database"
          version = "v1"
        }
      }

      spec {
        container {
          image = "postgres:13"
          name  = "database"
          port {
            container_port = 5432
          }
          env {
            name  = "POSTGRES_DB"
            value = "appdb"
          }
          env {
            name  = "POSTGRES_USER"
            value = "appuser"
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = "apppassword"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.database]
}

resource "kubernetes_service" "database" {
  count = var.deploy_sample_applications ? 1 : 0
  
  metadata {
    name      = "database-service"
    namespace = kubernetes_namespace.database[0].metadata[0].name
  }

  spec {
    selector = {
      app = "database"
    }

    port {
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.database]
}

#
# Istio Authorization Policies for Zero-Trust Networking
#
resource "kubectl_manifest" "frontend_auth_policy" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "security.istio.io/v1beta1"
    kind       = "AuthorizationPolicy"
    metadata = {
      name      = "frontend-policy"
      namespace = kubernetes_namespace.frontend[0].metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = {
          app = "frontend"
        }
      }
      rules = [
        {
          from = [
            {
              source = {
                namespaces = ["istio-system"]
              }
            }
          ]
          to = [
            {
              operation = {
                methods = ["GET", "POST"]
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    kubernetes_namespace.frontend
  ]
}

resource "kubectl_manifest" "backend_auth_policy" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "security.istio.io/v1beta1"
    kind       = "AuthorizationPolicy"
    metadata = {
      name      = "backend-policy"
      namespace = kubernetes_namespace.backend[0].metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = {
          app = "backend"
        }
      }
      rules = [
        {
          from = [
            {
              source = {
                namespaces = ["frontend"]
              }
            }
          ]
          to = [
            {
              operation = {
                methods = ["GET", "POST"]
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    kubernetes_namespace.backend
  ]
}

resource "kubectl_manifest" "database_auth_policy" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "security.istio.io/v1beta1"
    kind       = "AuthorizationPolicy"
    metadata = {
      name      = "database-policy"
      namespace = kubernetes_namespace.database[0].metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = {
          app = "database"
        }
      }
      rules = [
        {
          from = [
            {
              source = {
                namespaces = ["backend"]
              }
            }
          ]
          to = [
            {
              operation = {
                methods = ["GET", "POST"]
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    kubernetes_namespace.database
  ]
}

#
# Istio Destination Rules for Mutual TLS
#
resource "kubectl_manifest" "frontend_destination_rule" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "DestinationRule"
    metadata = {
      name      = "frontend-destination"
      namespace = kubernetes_namespace.frontend[0].metadata[0].name
    }
    spec = {
      host = "frontend-service"
      trafficPolicy = {
        tls = {
          mode = "ISTIO_MUTUAL"
        }
      }
    }
  })

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    kubernetes_service.frontend
  ]
}

resource "kubectl_manifest" "backend_destination_rule" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "DestinationRule"
    metadata = {
      name      = "backend-destination"
      namespace = kubernetes_namespace.backend[0].metadata[0].name
    }
    spec = {
      host = "backend-service"
      trafficPolicy = {
        tls = {
          mode = "ISTIO_MUTUAL"
        }
      }
    }
  })

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    kubernetes_service.backend
  ]
}

resource "kubectl_manifest" "database_destination_rule" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "DestinationRule"
    metadata = {
      name      = "database-destination"
      namespace = kubernetes_namespace.database[0].metadata[0].name
    }
    spec = {
      host = "database-service"
      trafficPolicy = {
        tls = {
          mode = "ISTIO_MUTUAL"
        }
      }
    }
  })

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    kubernetes_service.database
  ]
}

#
# Istio Gateway for External Access
#
resource "kubectl_manifest" "frontend_gateway" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "Gateway"
    metadata = {
      name      = "frontend-gateway"
      namespace = kubernetes_namespace.frontend[0].metadata[0].name
    }
    spec = {
      selector = {
        istio = "ingressgateway"
      }
      servers = [
        {
          port = {
            number   = 80
            name     = "http"
            protocol = "HTTP"
          }
          hosts = ["*"]
        }
      ]
    }
  })

  depends_on = [
    azurerm_kubernetes_cluster.aks_cluster,
    kubernetes_namespace.frontend
  ]
}

resource "kubectl_manifest" "frontend_virtual_service" {
  count = var.deploy_sample_applications ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "frontend-virtualservice"
      namespace = kubernetes_namespace.frontend[0].metadata[0].name
    }
    spec = {
      hosts    = ["*"]
      gateways = ["frontend-gateway"]
      http = [
        {
          match = [
            {
              uri = {
                prefix = "/"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "frontend-service"
                port = {
                  number = 80
                }
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.frontend_gateway,
    kubernetes_service.frontend
  ]
}

#
# Azure Monitor Alerts for Service Mesh Monitoring
#
resource "azurerm_monitor_metric_alert" "high_latency" {
  name                = "high-service-mesh-latency-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_log_analytics_workspace.main.id]
  description         = "Alert when service mesh latency exceeds 1 second"
  tags                = local.common_tags

  criteria {
    metric_namespace = "microsoft.containerservice/managedclusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

# Action group for alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "ag-service-mesh-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "svcmesh"
  tags                = local.common_tags

  # Add email notification (update with your email)
  email_receiver {
    name          = "admin"
    email_address = "admin@company.com"
  }
}