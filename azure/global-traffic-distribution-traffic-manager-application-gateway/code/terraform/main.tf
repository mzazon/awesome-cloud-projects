# Main Terraform configuration for global traffic distribution with Azure Traffic Manager and Application Gateway

# Generate random suffix for unique naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for SSH public key (optional for VMSS)
data "azurerm_client_config" "current" {}

# Data source for available VM sizes in each region
data "azurerm_virtual_machine_scale_set" "test" {
  count               = 0 # This is just for validation
  name                = "test"
  resource_group_name = "test"
}

# Local values for consistent naming and configuration
locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Resource names
  resource_group_names = {
    primary   = "rg-${local.name_prefix}-primary-${local.name_suffix}"
    secondary = "rg-${local.name_prefix}-secondary-${local.name_suffix}"
    tertiary  = "rg-${local.name_prefix}-tertiary-${local.name_suffix}"
  }
  
  # Virtual network names
  vnet_names = {
    primary   = "vnet-${local.name_prefix}-primary-${local.name_suffix}"
    secondary = "vnet-${local.name_prefix}-secondary-${local.name_suffix}"
    tertiary  = "vnet-${local.name_prefix}-tertiary-${local.name_suffix}"
  }
  
  # Application Gateway names
  appgw_names = {
    primary   = "agw-${local.name_prefix}-primary-${local.name_suffix}"
    secondary = "agw-${local.name_prefix}-secondary-${local.name_suffix}"
    tertiary  = "agw-${local.name_prefix}-tertiary-${local.name_suffix}"
  }
  
  # Public IP names
  pip_names = {
    primary   = "pip-agw-primary-${local.name_suffix}"
    secondary = "pip-agw-secondary-${local.name_suffix}"
    tertiary  = "pip-agw-tertiary-${local.name_suffix}"
  }
  
  # VMSS names
  vmss_names = {
    primary   = "vmss-${local.name_prefix}-primary-${local.name_suffix}"
    secondary = "vmss-${local.name_prefix}-secondary-${local.name_suffix}"
    tertiary  = "vmss-${local.name_prefix}-tertiary-${local.name_suffix}"
  }
  
  # Common tags
  common_tags = merge(var.tags, {
    DeployedBy    = "terraform"
    GeneratedBy   = "azure-recipe-global-traffic-distribution"
    RandomSuffix  = local.name_suffix
  })
}

# =============================================================================
# RESOURCE GROUPS
# =============================================================================

# Primary region resource group
resource "azurerm_resource_group" "primary" {
  name     = local.resource_group_names.primary
  location = var.primary_region
  tags     = local.common_tags
}

# Secondary region resource group
resource "azurerm_resource_group" "secondary" {
  name     = local.resource_group_names.secondary
  location = var.secondary_region
  tags     = local.common_tags
}

# Tertiary region resource group
resource "azurerm_resource_group" "tertiary" {
  name     = local.resource_group_names.tertiary
  location = var.tertiary_region
  tags     = local.common_tags
}

# =============================================================================
# VIRTUAL NETWORKS AND SUBNETS
# =============================================================================

# Primary region virtual network
resource "azurerm_virtual_network" "primary" {
  name                = local.vnet_names.primary
  address_space       = [var.vnet_address_spaces.primary]
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  tags                = local.common_tags
}

# Primary region Application Gateway subnet
resource "azurerm_subnet" "appgw_primary" {
  name                 = "subnet-appgw-primary"
  resource_group_name  = azurerm_resource_group.primary.name
  virtual_network_name = azurerm_virtual_network.primary.name
  address_prefixes     = [var.appgw_subnet_prefixes.primary]
}

# Primary region backend subnet
resource "azurerm_subnet" "backend_primary" {
  name                 = "subnet-backend-primary"
  resource_group_name  = azurerm_resource_group.primary.name
  virtual_network_name = azurerm_virtual_network.primary.name
  address_prefixes     = [var.backend_subnet_prefixes.primary]
}

# Secondary region virtual network
resource "azurerm_virtual_network" "secondary" {
  name                = local.vnet_names.secondary
  address_space       = [var.vnet_address_spaces.secondary]
  location            = azurerm_resource_group.secondary.location
  resource_group_name = azurerm_resource_group.secondary.name
  tags                = local.common_tags
}

# Secondary region Application Gateway subnet
resource "azurerm_subnet" "appgw_secondary" {
  name                 = "subnet-appgw-secondary"
  resource_group_name  = azurerm_resource_group.secondary.name
  virtual_network_name = azurerm_virtual_network.secondary.name
  address_prefixes     = [var.appgw_subnet_prefixes.secondary]
}

# Secondary region backend subnet
resource "azurerm_subnet" "backend_secondary" {
  name                 = "subnet-backend-secondary"
  resource_group_name  = azurerm_resource_group.secondary.name
  virtual_network_name = azurerm_virtual_network.secondary.name
  address_prefixes     = [var.backend_subnet_prefixes.secondary]
}

# Tertiary region virtual network
resource "azurerm_virtual_network" "tertiary" {
  name                = local.vnet_names.tertiary
  address_space       = [var.vnet_address_spaces.tertiary]
  location            = azurerm_resource_group.tertiary.location
  resource_group_name = azurerm_resource_group.tertiary.name
  tags                = local.common_tags
}

# Tertiary region Application Gateway subnet
resource "azurerm_subnet" "appgw_tertiary" {
  name                 = "subnet-appgw-tertiary"
  resource_group_name  = azurerm_resource_group.tertiary.name
  virtual_network_name = azurerm_virtual_network.tertiary.name
  address_prefixes     = [var.appgw_subnet_prefixes.tertiary]
}

# Tertiary region backend subnet
resource "azurerm_subnet" "backend_tertiary" {
  name                 = "subnet-backend-tertiary"
  resource_group_name  = azurerm_resource_group.tertiary.name
  virtual_network_name = azurerm_virtual_network.tertiary.name
  address_prefixes     = [var.backend_subnet_prefixes.tertiary]
}

# =============================================================================
# PUBLIC IP ADDRESSES
# =============================================================================

# Primary region public IP for Application Gateway
resource "azurerm_public_ip" "appgw_primary" {
  name                = local.pip_names.primary
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.appgw_zones
  tags                = local.common_tags
}

# Secondary region public IP for Application Gateway
resource "azurerm_public_ip" "appgw_secondary" {
  name                = local.pip_names.secondary
  location            = azurerm_resource_group.secondary.location
  resource_group_name = azurerm_resource_group.secondary.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.appgw_zones
  tags                = local.common_tags
}

# Tertiary region public IP for Application Gateway
resource "azurerm_public_ip" "appgw_tertiary" {
  name                = local.pip_names.tertiary
  location            = azurerm_resource_group.tertiary.location
  resource_group_name = azurerm_resource_group.tertiary.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.appgw_zones
  tags                = local.common_tags
}

# =============================================================================
# WEB APPLICATION FIREWALL POLICIES
# =============================================================================

# Primary region WAF policy
resource "azurerm_web_application_firewall_policy" "primary" {
  name                = "waf-policy-primary-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  tags                = local.common_tags

  policy_settings {
    enabled                     = true
    mode                       = var.waf_mode
    request_body_check         = true
    file_upload_limit_in_mb    = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = var.waf_rule_set_type
      version = var.waf_rule_set_version
    }
  }
}

# Secondary region WAF policy
resource "azurerm_web_application_firewall_policy" "secondary" {
  name                = "waf-policy-secondary-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  tags                = local.common_tags

  policy_settings {
    enabled                     = true
    mode                       = var.waf_mode
    request_body_check         = true
    file_upload_limit_in_mb    = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = var.waf_rule_set_type
      version = var.waf_rule_set_version
    }
  }
}

# Tertiary region WAF policy
resource "azurerm_web_application_firewall_policy" "tertiary" {
  name                = "waf-policy-tertiary-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.tertiary.name
  location            = azurerm_resource_group.tertiary.location
  tags                = local.common_tags

  policy_settings {
    enabled                     = true
    mode                       = var.waf_mode
    request_body_check         = true
    file_upload_limit_in_mb    = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = var.waf_rule_set_type
      version = var.waf_rule_set_version
    }
  }
}

# =============================================================================
# VIRTUAL MACHINE SCALE SETS
# =============================================================================

# Primary region VMSS
resource "azurerm_linux_virtual_machine_scale_set" "primary" {
  name                = local.vmss_names.primary
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  sku                 = var.vmss_sku
  instances           = var.vmss_instance_count
  admin_username      = var.vmss_admin_username
  zones               = var.vmss_zones
  tags                = local.common_tags

  # Disable password authentication and enable SSH keys
  disable_password_authentication = var.disable_password_authentication

  # SSH key configuration
  dynamic "admin_ssh_key" {
    for_each = var.enable_ssh_key_authentication ? [1] : []
    content {
      username   = var.vmss_admin_username
      public_key = tls_private_key.ssh_key.public_key_openssh
    }
  }

  # Network interface configuration
  network_interface {
    name    = "nic-${local.vmss_names.primary}"
    primary = true

    ip_configuration {
      name      = "ip-config-primary"
      primary   = true
      subnet_id = azurerm_subnet.backend_primary.id
    }
  }

  # OS disk configuration
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  # Source image configuration
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Upgrade policy
  upgrade_mode = "Manual"

  # Health probe configuration
  dynamic "health_probe_id" {
    for_each = var.enable_health_probe ? [azurerm_lb_probe.primary.id] : []
    content {
      value = health_probe_id.value
    }
  }

  # Automatic OS upgrade configuration
  dynamic "automatic_os_upgrade_policy" {
    for_each = var.enable_automatic_os_upgrade ? [1] : []
    content {
      disable_automatic_rollback  = false
      enable_automatic_os_upgrade = true
    }
  }

  # Custom data for nginx installation
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Primary Region - ${var.primary_region}</h1><p>Server: $(hostname)</p><p>Region: ${var.primary_region}</p>" > /var/www/html/index.html
    systemctl restart nginx
  EOF
  )

  depends_on = [
    azurerm_subnet.backend_primary
  ]
}

# Secondary region VMSS
resource "azurerm_linux_virtual_machine_scale_set" "secondary" {
  name                = local.vmss_names.secondary
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  sku                 = var.vmss_sku
  instances           = var.vmss_instance_count
  admin_username      = var.vmss_admin_username
  zones               = var.vmss_zones
  tags                = local.common_tags

  # Disable password authentication and enable SSH keys
  disable_password_authentication = var.disable_password_authentication

  # SSH key configuration
  dynamic "admin_ssh_key" {
    for_each = var.enable_ssh_key_authentication ? [1] : []
    content {
      username   = var.vmss_admin_username
      public_key = tls_private_key.ssh_key.public_key_openssh
    }
  }

  # Network interface configuration
  network_interface {
    name    = "nic-${local.vmss_names.secondary}"
    primary = true

    ip_configuration {
      name      = "ip-config-secondary"
      primary   = true
      subnet_id = azurerm_subnet.backend_secondary.id
    }
  }

  # OS disk configuration
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  # Source image configuration
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Upgrade policy
  upgrade_mode = "Manual"

  # Health probe configuration
  dynamic "health_probe_id" {
    for_each = var.enable_health_probe ? [azurerm_lb_probe.secondary.id] : []
    content {
      value = health_probe_id.value
    }
  }

  # Automatic OS upgrade configuration
  dynamic "automatic_os_upgrade_policy" {
    for_each = var.enable_automatic_os_upgrade ? [1] : []
    content {
      disable_automatic_rollback  = false
      enable_automatic_os_upgrade = true
    }
  }

  # Custom data for nginx installation
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Secondary Region - ${var.secondary_region}</h1><p>Server: $(hostname)</p><p>Region: ${var.secondary_region}</p>" > /var/www/html/index.html
    systemctl restart nginx
  EOF
  )

  depends_on = [
    azurerm_subnet.backend_secondary
  ]
}

# Tertiary region VMSS
resource "azurerm_linux_virtual_machine_scale_set" "tertiary" {
  name                = local.vmss_names.tertiary
  resource_group_name = azurerm_resource_group.tertiary.name
  location            = azurerm_resource_group.tertiary.location
  sku                 = var.vmss_sku
  instances           = var.vmss_instance_count
  admin_username      = var.vmss_admin_username
  zones               = var.vmss_zones
  tags                = local.common_tags

  # Disable password authentication and enable SSH keys
  disable_password_authentication = var.disable_password_authentication

  # SSH key configuration
  dynamic "admin_ssh_key" {
    for_each = var.enable_ssh_key_authentication ? [1] : []
    content {
      username   = var.vmss_admin_username
      public_key = tls_private_key.ssh_key.public_key_openssh
    }
  }

  # Network interface configuration
  network_interface {
    name    = "nic-${local.vmss_names.tertiary}"
    primary = true

    ip_configuration {
      name      = "ip-config-tertiary"
      primary   = true
      subnet_id = azurerm_subnet.backend_tertiary.id
    }
  }

  # OS disk configuration
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  # Source image configuration
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Upgrade policy
  upgrade_mode = "Manual"

  # Health probe configuration
  dynamic "health_probe_id" {
    for_each = var.enable_health_probe ? [azurerm_lb_probe.tertiary.id] : []
    content {
      value = health_probe_id.value
    }
  }

  # Automatic OS upgrade configuration
  dynamic "automatic_os_upgrade_policy" {
    for_each = var.enable_automatic_os_upgrade ? [1] : []
    content {
      disable_automatic_rollback  = false
      enable_automatic_os_upgrade = true
    }
  }

  # Custom data for nginx installation
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<h1>Tertiary Region - ${var.tertiary_region}</h1><p>Server: $(hostname)</p><p>Region: ${var.tertiary_region}</p>" > /var/www/html/index.html
    systemctl restart nginx
  EOF
  )

  depends_on = [
    azurerm_subnet.backend_tertiary
  ]
}

# =============================================================================
# SSH KEY GENERATION
# =============================================================================

# Generate SSH key pair for VMSS access
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# =============================================================================
# LOAD BALANCER HEALTH PROBES (for VMSS health monitoring)
# =============================================================================

# Primary region load balancer (for health probe)
resource "azurerm_lb" "primary" {
  count               = var.enable_health_probe ? 1 : 0
  name                = "lb-${local.vmss_names.primary}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  sku                 = "Standard"
  tags                = local.common_tags

  frontend_ip_configuration {
    name                 = "frontend-ip-primary"
    subnet_id            = azurerm_subnet.backend_primary.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Primary region load balancer health probe
resource "azurerm_lb_probe" "primary" {
  count               = var.enable_health_probe ? 1 : 0
  name                = "health-probe-primary"
  loadbalancer_id     = azurerm_lb.primary[0].id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 15
  number_of_probes    = 2
}

# Secondary region load balancer (for health probe)
resource "azurerm_lb" "secondary" {
  count               = var.enable_health_probe ? 1 : 0
  name                = "lb-${local.vmss_names.secondary}"
  location            = azurerm_resource_group.secondary.location
  resource_group_name = azurerm_resource_group.secondary.name
  sku                 = "Standard"
  tags                = local.common_tags

  frontend_ip_configuration {
    name                 = "frontend-ip-secondary"
    subnet_id            = azurerm_subnet.backend_secondary.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Secondary region load balancer health probe
resource "azurerm_lb_probe" "secondary" {
  count               = var.enable_health_probe ? 1 : 0
  name                = "health-probe-secondary"
  loadbalancer_id     = azurerm_lb.secondary[0].id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 15
  number_of_probes    = 2
}

# Tertiary region load balancer (for health probe)
resource "azurerm_lb" "tertiary" {
  count               = var.enable_health_probe ? 1 : 0
  name                = "lb-${local.vmss_names.tertiary}"
  location            = azurerm_resource_group.tertiary.location
  resource_group_name = azurerm_resource_group.tertiary.name
  sku                 = "Standard"
  tags                = local.common_tags

  frontend_ip_configuration {
    name                 = "frontend-ip-tertiary"
    subnet_id            = azurerm_subnet.backend_tertiary.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Tertiary region load balancer health probe
resource "azurerm_lb_probe" "tertiary" {
  count               = var.enable_health_probe ? 1 : 0
  name                = "health-probe-tertiary"
  loadbalancer_id     = azurerm_lb.tertiary[0].id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 15
  number_of_probes    = 2
}

# =============================================================================
# APPLICATION GATEWAYS
# =============================================================================

# Primary region Application Gateway
resource "azurerm_application_gateway" "primary" {
  name                = local.appgw_names.primary
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  zones               = var.appgw_zones
  tags                = local.common_tags

  # Enable WAF if using WAF_v2 SKU
  firewall_policy_id = var.appgw_sku == "WAF_v2" ? azurerm_web_application_firewall_policy.primary.id : null

  sku {
    name     = var.appgw_sku
    tier     = var.appgw_sku
    capacity = var.appgw_capacity
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config-primary"
    subnet_id = azurerm_subnet.appgw_primary.id
  }

  frontend_port {
    name = "frontend-port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config-primary"
    public_ip_address_id = azurerm_public_ip.appgw_primary.id
  }

  backend_address_pool {
    name = "backend-pool-primary"
  }

  backend_http_settings {
    name                  = "backend-http-settings-primary"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "health-probe-primary"
  }

  probe {
    name                = "health-probe-primary"
    protocol            = "Http"
    path                = "/"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = "http-listener-primary"
    frontend_ip_configuration_name = "frontend-ip-config-primary"
    frontend_port_name             = "frontend-port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule-primary"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener-primary"
    backend_address_pool_name  = "backend-pool-primary"
    backend_http_settings_name = "backend-http-settings-primary"
    priority                   = 1
  }

  depends_on = [
    azurerm_public_ip.appgw_primary,
    azurerm_subnet.appgw_primary,
    azurerm_web_application_firewall_policy.primary
  ]
}

# Secondary region Application Gateway
resource "azurerm_application_gateway" "secondary" {
  name                = local.appgw_names.secondary
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  zones               = var.appgw_zones
  tags                = local.common_tags

  # Enable WAF if using WAF_v2 SKU
  firewall_policy_id = var.appgw_sku == "WAF_v2" ? azurerm_web_application_firewall_policy.secondary.id : null

  sku {
    name     = var.appgw_sku
    tier     = var.appgw_sku
    capacity = var.appgw_capacity
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config-secondary"
    subnet_id = azurerm_subnet.appgw_secondary.id
  }

  frontend_port {
    name = "frontend-port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config-secondary"
    public_ip_address_id = azurerm_public_ip.appgw_secondary.id
  }

  backend_address_pool {
    name = "backend-pool-secondary"
  }

  backend_http_settings {
    name                  = "backend-http-settings-secondary"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "health-probe-secondary"
  }

  probe {
    name                = "health-probe-secondary"
    protocol            = "Http"
    path                = "/"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = "http-listener-secondary"
    frontend_ip_configuration_name = "frontend-ip-config-secondary"
    frontend_port_name             = "frontend-port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule-secondary"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener-secondary"
    backend_address_pool_name  = "backend-pool-secondary"
    backend_http_settings_name = "backend-http-settings-secondary"
    priority                   = 1
  }

  depends_on = [
    azurerm_public_ip.appgw_secondary,
    azurerm_subnet.appgw_secondary,
    azurerm_web_application_firewall_policy.secondary
  ]
}

# Tertiary region Application Gateway
resource "azurerm_application_gateway" "tertiary" {
  name                = local.appgw_names.tertiary
  resource_group_name = azurerm_resource_group.tertiary.name
  location            = azurerm_resource_group.tertiary.location
  zones               = var.appgw_zones
  tags                = local.common_tags

  # Enable WAF if using WAF_v2 SKU
  firewall_policy_id = var.appgw_sku == "WAF_v2" ? azurerm_web_application_firewall_policy.tertiary.id : null

  sku {
    name     = var.appgw_sku
    tier     = var.appgw_sku
    capacity = var.appgw_capacity
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config-tertiary"
    subnet_id = azurerm_subnet.appgw_tertiary.id
  }

  frontend_port {
    name = "frontend-port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config-tertiary"
    public_ip_address_id = azurerm_public_ip.appgw_tertiary.id
  }

  backend_address_pool {
    name = "backend-pool-tertiary"
  }

  backend_http_settings {
    name                  = "backend-http-settings-tertiary"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = "health-probe-tertiary"
  }

  probe {
    name                = "health-probe-tertiary"
    protocol            = "Http"
    path                = "/"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = "http-listener-tertiary"
    frontend_ip_configuration_name = "frontend-ip-config-tertiary"
    frontend_port_name             = "frontend-port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule-tertiary"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener-tertiary"
    backend_address_pool_name  = "backend-pool-tertiary"
    backend_http_settings_name = "backend-http-settings-tertiary"
    priority                   = 1
  }

  depends_on = [
    azurerm_public_ip.appgw_tertiary,
    azurerm_subnet.appgw_tertiary,
    azurerm_web_application_firewall_policy.tertiary
  ]
}

# =============================================================================
# APPLICATION GATEWAY BACKEND POOL ASSOCIATIONS
# =============================================================================

# Data source to get VMSS network interface details
data "azurerm_virtual_machine_scale_set" "primary" {
  name                = azurerm_linux_virtual_machine_scale_set.primary.name
  resource_group_name = azurerm_resource_group.primary.name
  depends_on         = [azurerm_linux_virtual_machine_scale_set.primary]
}

data "azurerm_virtual_machine_scale_set" "secondary" {
  name                = azurerm_linux_virtual_machine_scale_set.secondary.name
  resource_group_name = azurerm_resource_group.secondary.name
  depends_on         = [azurerm_linux_virtual_machine_scale_set.secondary]
}

data "azurerm_virtual_machine_scale_set" "tertiary" {
  name                = azurerm_linux_virtual_machine_scale_set.tertiary.name
  resource_group_name = azurerm_resource_group.tertiary.name
  depends_on         = [azurerm_linux_virtual_machine_scale_set.tertiary]
}

# =============================================================================
# TRAFFIC MANAGER PROFILE
# =============================================================================

# Traffic Manager profile for global load balancing
resource "azurerm_traffic_manager_profile" "main" {
  name                         = "tm-${local.name_prefix}-${local.name_suffix}"
  resource_group_name          = azurerm_resource_group.primary.name
  traffic_routing_method       = var.traffic_manager_routing_method
  max_return                   = 3
  tags                         = local.common_tags

  dns_config {
    relative_name = "tm-${local.name_prefix}-${local.name_suffix}"
    ttl          = var.traffic_manager_ttl
  }

  monitor_config {
    protocol                     = var.traffic_manager_monitor_protocol
    port                        = var.traffic_manager_monitor_port
    path                        = var.traffic_manager_monitor_path
    interval_in_seconds         = var.traffic_manager_monitor_interval
    timeout_in_seconds          = var.traffic_manager_monitor_timeout
    tolerated_number_of_failures = var.traffic_manager_monitor_tolerated_failures
  }
}

# =============================================================================
# TRAFFIC MANAGER ENDPOINTS
# =============================================================================

# Primary region Traffic Manager endpoint
resource "azurerm_traffic_manager_external_endpoint" "primary" {
  name               = "endpoint-primary"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target             = azurerm_public_ip.appgw_primary.ip_address
  endpoint_location  = var.primary_region
  priority           = var.endpoint_priorities.primary
  weight             = var.endpoint_weights.primary
  
  depends_on = [
    azurerm_application_gateway.primary,
    azurerm_public_ip.appgw_primary
  ]
}

# Secondary region Traffic Manager endpoint
resource "azurerm_traffic_manager_external_endpoint" "secondary" {
  name               = "endpoint-secondary"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target             = azurerm_public_ip.appgw_secondary.ip_address
  endpoint_location  = var.secondary_region
  priority           = var.endpoint_priorities.secondary
  weight             = var.endpoint_weights.secondary
  
  depends_on = [
    azurerm_application_gateway.secondary,
    azurerm_public_ip.appgw_secondary
  ]
}

# Tertiary region Traffic Manager endpoint
resource "azurerm_traffic_manager_external_endpoint" "tertiary" {
  name               = "endpoint-tertiary"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target             = azurerm_public_ip.appgw_tertiary.ip_address
  endpoint_location  = var.tertiary_region
  priority           = var.endpoint_priorities.tertiary
  weight             = var.endpoint_weights.tertiary
  
  depends_on = [
    azurerm_application_gateway.tertiary,
    azurerm_public_ip.appgw_tertiary
  ]
}

# =============================================================================
# MONITORING AND DIAGNOSTICS (Optional)
# =============================================================================

# Log Analytics workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "law-${local.name_prefix}-${local.name_suffix}"
  location                   = azurerm_resource_group.primary.location
  resource_group_name        = azurerm_resource_group.primary.name
  sku                        = var.log_analytics_sku
  retention_in_days          = var.log_retention_days
  tags                       = local.common_tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "ai-${local.name_prefix}-${local.name_suffix}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name
  workspace_id        = azurerm_log_analytics_workspace.main[0].id
  application_type    = "web"
  tags                = local.common_tags
}

# Diagnostic settings for Traffic Manager
resource "azurerm_monitor_diagnostic_setting" "traffic_manager" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "diag-traffic-manager"
  target_resource_id         = azurerm_traffic_manager_profile.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ProbeHealthStatusEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Application Gateway - Primary
resource "azurerm_monitor_diagnostic_setting" "appgw_primary" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "diag-appgw-primary"
  target_resource_id         = azurerm_application_gateway.primary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Application Gateway - Secondary
resource "azurerm_monitor_diagnostic_setting" "appgw_secondary" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "diag-appgw-secondary"
  target_resource_id         = azurerm_application_gateway.secondary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Application Gateway - Tertiary
resource "azurerm_monitor_diagnostic_setting" "appgw_tertiary" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "diag-appgw-tertiary"
  target_resource_id         = azurerm_application_gateway.tertiary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}