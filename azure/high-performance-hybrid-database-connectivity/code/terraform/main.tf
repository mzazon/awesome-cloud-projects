# Main Terraform configuration for Azure hybrid database connectivity
# This configuration creates a secure hybrid architecture with ExpressRoute and Application Gateway

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
  
  tags = merge(var.common_tags, {
    Name = var.resource_group_name
  })
}

# Create Log Analytics Workspace for monitoring and diagnostics
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_workspace_sku
  retention_in_days   = var.log_retention_in_days
  
  tags = merge(var.common_tags, {
    Name = "law-${var.project_name}-${random_string.suffix.result}"
  })
}

# Create DDoS Protection Plan (optional)
resource "azurerm_network_ddos_protection_plan" "main" {
  count = var.enable_ddos_protection ? 1 : 0
  
  name                = "ddos-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(var.common_tags, {
    Name = "ddos-${var.project_name}-${random_string.suffix.result}"
  })
}

# Create Hub Virtual Network
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  
  dynamic "ddos_protection_plan" {
    for_each = var.enable_ddos_protection ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.main[0].id
      enable = true
    }
  }
  
  tags = merge(var.common_tags, {
    Name = "vnet-hub-${random_string.suffix.result}"
    Type = "Hub"
  })
}

# Create Gateway Subnet (required for ExpressRoute Gateway)
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.gateway_subnet_address_prefix]
}

# Create Application Gateway Subnet
resource "azurerm_subnet" "application_gateway" {
  name                 = "ApplicationGatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.appgw_subnet_address_prefix]
}

# Create Database Subnet with service endpoints
resource "azurerm_subnet" "database" {
  name                 = "DatabaseSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.database_subnet_address_prefix]
  service_endpoints    = ["Microsoft.Storage"]
  
  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Create Management Subnet
resource "azurerm_subnet" "management" {
  name                 = "ManagementSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.management_subnet_address_prefix]
}

# Create Azure Bastion Subnet (if enabled)
resource "azurerm_subnet" "bastion" {
  count = var.enable_bastion ? 1 : 0
  
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.bastion_subnet_address_prefix]
}

# Create Network Security Group for Database Subnet
resource "azurerm_network_security_group" "database" {
  name                = "nsg-database-subnet-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Allow Application Gateway to PostgreSQL
  security_rule {
    name                       = "AllowApplicationGatewayToPostgreSQL"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.appgw_subnet_address_prefix
    destination_address_prefix = "*"
  }
  
  # Allow ExpressRoute/On-premises to PostgreSQL
  security_rule {
    name                       = "AllowExpressRouteToPostgreSQL"
    priority                   = 1100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefixes    = var.allowed_on_premises_address_prefixes
    destination_address_prefix = "*"
  }
  
  # Allow management subnet for administrative access
  security_rule {
    name                       = "AllowManagementToPostgreSQL"
    priority                   = 1200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.management_subnet_address_prefix
    destination_address_prefix = "*"
  }
  
  # Deny all other inbound traffic
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  tags = merge(var.common_tags, {
    Name = "nsg-database-subnet-${random_string.suffix.result}"
  })
}

# Associate NSG with Database Subnet
resource "azurerm_subnet_network_security_group_association" "database" {
  subnet_id                 = azurerm_subnet.database.id
  network_security_group_id = azurerm_network_security_group.database.id
}

# Create Route Table for Database Subnet
resource "azurerm_route_table" "database" {
  name                = "rt-database-subnet-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Route for on-premises traffic via ExpressRoute
  route {
    name           = "route-onpremises"
    address_prefix = "10.0.0.0/8"
    next_hop_type  = "VnetLocal"
  }
  
  tags = merge(var.common_tags, {
    Name = "rt-database-subnet-${random_string.suffix.result}"
  })
}

# Associate Route Table with Database Subnet
resource "azurerm_subnet_route_table_association" "database" {
  subnet_id      = azurerm_subnet.database.id
  route_table_id = azurerm_route_table.database.id
}

# Create Public IP for ExpressRoute Gateway
resource "azurerm_public_ip" "expressroute_gateway" {
  name                = "pip-ergw-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  
  tags = merge(var.common_tags, {
    Name = "pip-ergw-${random_string.suffix.result}"
  })
}

# Create ExpressRoute Gateway
resource "azurerm_virtual_network_gateway" "expressroute" {
  name                = "ergw-hub-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  type     = "ExpressRoute"
  vpn_type = "RouteBased"
  
  active_active = false
  enable_bgp    = true
  sku           = var.expressroute_gateway_sku
  
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.expressroute_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
  
  tags = merge(var.common_tags, {
    Name = "ergw-hub-${random_string.suffix.result}"
  })
}

# Create ExpressRoute Connection (optional - only if circuit ID is provided)
resource "azurerm_virtual_network_gateway_connection" "expressroute" {
  count = var.expressroute_circuit_id != "" ? 1 : 0
  
  name                = "connection-ergw-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  type                       = "ExpressRoute"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.expressroute.id
  express_route_circuit_id   = var.expressroute_circuit_id
  
  tags = merge(var.common_tags, {
    Name = "connection-ergw-${random_string.suffix.result}"
  })
}

# Generate random password for PostgreSQL if not provided
resource "random_password" "postgresql_admin" {
  count = var.postgresql_admin_password == null ? 1 : 0
  
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Create Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgresql" {
  name                = "${var.project_name}-${random_string.suffix.result}.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${random_string.suffix.result}.private.postgres.database.azure.com"
  })
}

# Link Private DNS Zone to Virtual Network
resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                  = "link-${azurerm_virtual_network.hub.name}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  
  tags = merge(var.common_tags, {
    Name = "link-${azurerm_virtual_network.hub.name}"
  })
}

# Create PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "postgres-hybrid-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = var.postgresql_version
  delegated_subnet_id    = azurerm_subnet.database.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgresql.id
  administrator_login    = var.postgresql_admin_username
  administrator_password = var.postgresql_admin_password != null ? var.postgresql_admin_password : random_password.postgresql_admin[0].result
  zone                   = "1"
  
  storage_mb   = var.postgresql_storage_mb
  sku_name     = var.postgresql_sku_name
  
  backup_retention_days        = var.postgresql_backup_retention_days
  geo_redundant_backup_enabled = var.postgresql_geo_redundant_backup_enabled
  
  maintenance_window {
    day_of_week  = 0
    start_hour   = 8
    start_minute = 0
  }
  
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
  
  tags = merge(var.common_tags, {
    Name = "postgres-hybrid-${random_string.suffix.result}"
  })
}

# Configure PostgreSQL parameters for optimal performance
resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "200"
}

resource "azurerm_postgresql_flexible_server_configuration" "shared_preload_libraries" {
  name      = "shared_preload_libraries"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "pg_stat_statements"
}

# Create Public IP for Application Gateway
resource "azurerm_public_ip" "application_gateway" {
  name                = "pip-appgw-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  
  tags = merge(var.common_tags, {
    Name = "pip-appgw-${random_string.suffix.result}"
  })
}

# Create Web Application Firewall Policy
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "waf-policy-db-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }
  
  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
  
  tags = merge(var.common_tags, {
    Name = "waf-policy-db-${random_string.suffix.result}"
  })
}

# Create Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "appgw-db-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  
  sku {
    name     = var.application_gateway_sku
    tier     = var.application_gateway_sku
    capacity = var.application_gateway_capacity
  }
  
  firewall_policy_id = azurerm_web_application_firewall_policy.main.id
  
  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.application_gateway.id
  }
  
  frontend_port {
    name = "httpsPort"
    port = 443
  }
  
  frontend_port {
    name = "httpPort"
    port = 80
  }
  
  frontend_ip_configuration {
    name                 = "appGatewayFrontendIP"
    public_ip_address_id = azurerm_public_ip.application_gateway.id
  }
  
  backend_address_pool {
    name  = "PostgreSQLBackendPool"
    fqdns = [azurerm_postgresql_flexible_server.main.fqdn]
  }
  
  backend_http_settings {
    name                  = "PostgreSQLBackendHttpSettings"
    cookie_based_affinity = "Enabled"
    path                  = "/"
    port                  = 5432
    protocol              = "Https"
    request_timeout       = 60
    
    probe_name = "PostgreSQLHealthProbe"
  }
  
  http_listener {
    name                           = "appGatewayHttpsListener"
    frontend_ip_configuration_name = "appGatewayFrontendIP"
    frontend_port_name             = "httpsPort"
    protocol                       = "Https"
    ssl_certificate_name           = "appGatewaySslCert"
  }
  
  http_listener {
    name                           = "appGatewayHttpListener"
    frontend_ip_configuration_name = "appGatewayFrontendIP"
    frontend_port_name             = "httpPort"
    protocol                       = "Http"
  }
  
  probe {
    name                = "PostgreSQLHealthProbe"
    protocol            = "Https"
    path                = "/"
    host                = azurerm_postgresql_flexible_server.main.fqdn
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    
    match {
      status_code = ["200-399"]
    }
  }
  
  request_routing_rule {
    name                       = "PostgreSQLRoutingRule"
    rule_type                  = "Basic"
    http_listener_name         = "appGatewayHttpsListener"
    backend_address_pool_name  = "PostgreSQLBackendPool"
    backend_http_settings_name = "PostgreSQLBackendHttpSettings"
    priority                   = 1000
  }
  
  # HTTP to HTTPS redirect rule
  request_routing_rule {
    name               = "HttpToHttpsRedirect"
    rule_type          = "Basic"
    http_listener_name = "appGatewayHttpListener"
    redirect_configuration_name = "HttpToHttpsRedirectConfig"
    priority           = 2000
  }
  
  redirect_configuration {
    name                 = "HttpToHttpsRedirectConfig"
    redirect_type        = "Permanent"
    target_listener_name = "appGatewayHttpsListener"
  }
  
  # Self-signed certificate for testing (replace with proper certificate in production)
  ssl_certificate {
    name     = "appGatewaySslCert"
    data     = filebase64("${path.module}/certificates/self-signed.pfx")
    password = "password"
  }
  
  ssl_policy {
    policy_type = "Custom"
    min_protocol_version = "TLSv1_2"
    cipher_suites = [
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
    ]
  }
  
  tags = merge(var.common_tags, {
    Name = "appgw-db-${random_string.suffix.result}"
  })
  
  depends_on = [azurerm_postgresql_flexible_server.main]
}

# Create Azure Bastion (if enabled)
resource "azurerm_public_ip" "bastion" {
  count = var.enable_bastion ? 1 : 0
  
  name                = "pip-bastion-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = merge(var.common_tags, {
    Name = "pip-bastion-${random_string.suffix.result}"
  })
}

resource "azurerm_bastion_host" "main" {
  count = var.enable_bastion ? 1 : 0
  
  name                = "bastion-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
  
  tags = merge(var.common_tags, {
    Name = "bastion-${random_string.suffix.result}"
  })
}

# Create diagnostic settings for key resources (if enabled)
resource "azurerm_monitor_diagnostic_setting" "application_gateway" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "diag-appgw-${random_string.suffix.result}"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  dynamic "enabled_log" {
    for_each = [
      "ApplicationGatewayAccessLog",
      "ApplicationGatewayPerformanceLog",
      "ApplicationGatewayFirewallLog"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "diag-postgres-${random_string.suffix.result}"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  dynamic "enabled_log" {
    for_each = [
      "PostgreSQLLogs"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "virtual_network_gateway" {
  count = var.enable_diagnostic_logs ? 1 : 0
  
  name                       = "diag-ergw-${random_string.suffix.result}"
  target_resource_id         = azurerm_virtual_network_gateway.expressroute.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  
  dynamic "enabled_log" {
    for_each = [
      "GatewayDiagnosticLog",
      "TunnelDiagnosticLog",
      "RouteDiagnosticLog",
      "IKEDiagnosticLog"
    ]
    content {
      category = enabled_log.value
    }
  }
  
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}