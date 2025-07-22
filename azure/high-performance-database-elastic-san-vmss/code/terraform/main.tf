# Main Terraform configuration for Azure Elastic SAN and VMSS Database Infrastructure
# This file defines all the Azure resources needed for a high-performance database workload

# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Generate SSH key pair for VM access
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Create Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-vnet-${random_string.suffix.result}"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Create Subnet for Database Resources
resource "azurerm_subnet" "database" {
  name                 = "${var.project_name}-subnet-${random_string.suffix.result}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_address_prefixes

  # Enable service endpoints for PostgreSQL
  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

# Create Network Security Group for Database Subnet
resource "azurerm_network_security_group" "database" {
  name                = "${var.project_name}-nsg-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow SSH access
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow PostgreSQL access
  security_rule {
    name                       = "PostgreSQL"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow iSCSI access for Elastic SAN
  security_rule {
    name                       = "iSCSI"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3260"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Associate NSG with Database Subnet
resource "azurerm_subnet_network_security_group_association" "database" {
  subnet_id                 = azurerm_subnet.database.id
  network_security_group_id = azurerm_network_security_group.database.id
}

# Create Azure Elastic SAN
resource "azurerm_elastic_san" "main" {
  name                        = "${var.project_name}-esan-${random_string.suffix.result}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  base_size_tib              = var.elastic_san_base_size_tib
  extended_capacity_size_tib = var.elastic_san_extended_capacity_tib
  
  sku {
    name = var.elastic_san_sku
  }

  tags = var.tags
}

# Create Volume Group for Database Storage
resource "azurerm_elastic_san_volume_group" "database" {
  name           = "vg-database-storage"
  elastic_san_id = azurerm_elastic_san.main.id
  protocol_type  = "Iscsi"
  
  # Configure network access rules for the subnet
  network_rule {
    subnet_id = azurerm_subnet.database.id
    action    = "Allow"
  }

  tags = var.tags
}

# Create Data Volume for PostgreSQL
resource "azurerm_elastic_san_volume" "data" {
  name                = "vol-pg-data"
  volume_group_id     = azurerm_elastic_san_volume_group.database.id
  size_in_gib         = var.data_volume_size_gb
  creation_data {
    source_type = "None"
  }
  
  tags = var.tags
}

# Create Log Volume for PostgreSQL
resource "azurerm_elastic_san_volume" "logs" {
  name                = "vol-pg-logs"
  volume_group_id     = azurerm_elastic_san_volume_group.database.id
  size_in_gib         = var.log_volume_size_gb
  creation_data {
    source_type = "None"
  }
  
  tags = var.tags
}

# Create Public IP for Load Balancer
resource "azurerm_public_ip" "lb" {
  name                = "${var.project_name}-lb-pip-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.project_name}-lb-${random_string.suffix.result}"
  tags                = var.tags
}

# Create Load Balancer
resource "azurerm_lb" "main" {
  name                = "${var.project_name}-lb-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.load_balancer_sku

  frontend_ip_configuration {
    name                 = "LoadBalancerFrontEnd"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = var.tags
}

# Create Backend Pool for Load Balancer
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "db-backend-pool"
}

# Create Health Probe for PostgreSQL
resource "azurerm_lb_probe" "postgresql" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "postgresql-health-probe"
  port            = 5432
  protocol        = "Tcp"
  interval_in_seconds = 15
  number_of_probes = 2
}

# Create Load Balancer Rule for PostgreSQL
resource "azurerm_lb_rule" "postgresql" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "postgresql-rule"
  protocol                       = "Tcp"
  frontend_port                  = 5432
  backend_port                   = 5432
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.postgresql.id
  enable_floating_ip             = false
  idle_timeout_in_minutes        = 4
}

# Create custom script for PostgreSQL setup
locals {
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    
    # Update system packages
    sudo apt-get update
    
    # Install PostgreSQL
    sudo apt-get install -y postgresql postgresql-contrib
    
    # Install iSCSI utilities for Elastic SAN
    sudo apt-get install -y open-iscsi
    
    # Configure PostgreSQL for high performance
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
    
    # Configure PostgreSQL for remote connections
    sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/*/main/postgresql.conf
    echo "host all all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
    
    # Create database user and database
    sudo -u postgres psql -c "CREATE USER dbadmin WITH PASSWORD 'SecurePass123!';"
    sudo -u postgres psql -c "CREATE DATABASE appdb OWNER dbadmin;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE appdb TO dbadmin;"
    
    # Configure PostgreSQL for high performance
    sudo -u postgres psql -c "ALTER SYSTEM SET shared_buffers = '256MB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET effective_cache_size = '1GB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET maintenance_work_mem = '64MB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET checkpoint_completion_target = 0.9;"
    sudo -u postgres psql -c "ALTER SYSTEM SET wal_buffers = '16MB';"
    sudo -u postgres psql -c "ALTER SYSTEM SET default_statistics_target = 100;"
    sudo -u postgres psql -c "SELECT pg_reload_conf();"
    
    # Restart PostgreSQL to apply configuration changes
    sudo systemctl restart postgresql
    
    # Install Azure CLI for monitoring integration
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    
    # Create application directories
    sudo mkdir -p /app/data /app/logs
    sudo chown -R $USER:$USER /app
    
    # Install monitoring tools
    sudo apt-get install -y htop iotop sysstat
    
    echo "PostgreSQL setup completed successfully"
    
    # Log setup completion
    echo "$(date): PostgreSQL setup completed" | sudo tee -a /var/log/setup.log
    EOF
  )
}

# Create Virtual Machine Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                = "${var.project_name}-vmss-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.vmss_sku
  instances           = var.vmss_instances
  admin_username      = var.admin_username
  custom_data         = local.custom_data

  # Disable password authentication and use SSH keys
  disable_password_authentication = var.disable_password_authentication

  # Configure SSH key
  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  # Configure OS disk
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  # Configure source image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Configure network interface
  network_interface {
    name    = "internal"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.database.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
    }
  }

  # Configure upgrade policy
  upgrade_mode = var.vmss_upgrade_policy

  # Configure boot diagnostics
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.diagnostics.primary_blob_endpoint
  }

  tags = var.tags

  depends_on = [
    azurerm_lb_rule.postgresql,
    azurerm_elastic_san_volume_group.database
  ]
}

# Create Storage Account for Boot Diagnostics
resource "azurerm_storage_account" "diagnostics" {
  name                     = "${substr(var.project_name, 0, 8)}diag${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

# Create PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${var.project_name}-pg-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = var.postgresql_version
  delegated_subnet_id    = azurerm_subnet.database.id
  administrator_login    = var.postgresql_administrator_login
  administrator_password = var.postgresql_administrator_password
  zone                   = var.postgresql_zone
  
  storage_mb   = var.postgresql_storage_mb
  storage_tier = var.postgresql_storage_tier
  
  sku_name = var.postgresql_sku_name

  # Configure high availability if enabled
  dynamic "high_availability" {
    for_each = var.postgresql_high_availability ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = var.postgresql_standby_zone
    }
  }

  # Configure backup retention
  backup_retention_days = 7
  
  # Configure maintenance window
  maintenance_window {
    day_of_week  = 0
    start_hour   = 2
    start_minute = 0
  }

  tags = var.tags
}

# Create PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = "appdb"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Create Log Analytics Workspace for Monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-law-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# Create Action Group for Alerts
resource "azurerm_monitor_action_group" "main" {
  name                = "${var.project_name}-ag-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "DBAlerts"

  # Add email notifications if email addresses are provided
  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }

  tags = var.tags
}

# Create Autoscale Setting for VMSS
resource "azurerm_monitor_autoscale_setting" "vmss" {
  name                = "${var.project_name}-autoscale-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.main.id

  profile {
    name = "default"

    capacity {
      default = var.autoscale_default_instances
      minimum = var.autoscale_minimum_instances
      maximum = var.autoscale_maximum_instances
    }

    # Scale out rule
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.cpu_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in rule
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  tags = var.tags
}

# Create CPU Usage Alert
resource "azurerm_monitor_metric_alert" "cpu_usage" {
  name                = "${var.project_name}-cpu-alert-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.main.id]
  description         = "Alert when CPU usage exceeds ${var.cpu_alert_threshold}%"
  
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  frequency   = "PT1M"
  window_size = "PT5M"
  severity    = 2

  tags = var.tags
}

# Create Elastic SAN Storage Usage Alert
resource "azurerm_monitor_metric_alert" "storage_usage" {
  name                = "${var.project_name}-storage-alert-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_elastic_san.main.id]
  description         = "Alert when Elastic SAN storage usage exceeds 80%"
  
  criteria {
    metric_namespace = "Microsoft.ElasticSan/elasticSans"
    metric_name      = "VolumeConsumedSizeBytes"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = (azurerm_elastic_san.main.total_size_tib * 1024 * 1024 * 1024 * 1024) * 0.8
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }

  frequency   = "PT5M"
  window_size = "PT15M"
  severity    = 1

  tags = var.tags
}

# Create Diagnostic Settings for VMSS
resource "azurerm_monitor_diagnostic_setting" "vmss" {
  name                       = "${var.project_name}-vmss-diag-${random_string.suffix.result}"
  target_resource_id         = azurerm_linux_virtual_machine_scale_set.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "AutoscaleEvaluations"
  }

  enabled_log {
    category = "AutoscaleScaleActions"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Diagnostic Settings for PostgreSQL
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "${var.project_name}-pg-diag-${random_string.suffix.result}"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Create Diagnostic Settings for Load Balancer
resource "azurerm_monitor_diagnostic_setting" "load_balancer" {
  name                       = "${var.project_name}-lb-diag-${random_string.suffix.result}"
  target_resource_id         = azurerm_lb.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "LoadBalancerAlertEvent"
  }

  enabled_log {
    category = "LoadBalancerProbeHealthStatus"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}