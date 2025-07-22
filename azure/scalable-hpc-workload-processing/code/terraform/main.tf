# Azure HPC Workload Processing with Elastic SAN and Azure Batch
# This configuration creates a scalable HPC environment with high-performance shared storage

# Resource Group
resource "azurerm_resource_group" "hpc" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "compute-intensive"
  }
}

# Storage Account for Batch application packages and logs
resource "azurerm_storage_account" "batch_storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.hpc.name
  location                 = azurerm_resource_group.hpc.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  access_tier              = "Hot"

  https_traffic_only_enabled = true

  blob_properties {
    versioning_enabled = true
    
    delete_retention_policy {
      days = 30
    }
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "batch-storage"
  }
}

# Storage Container for HPC scripts and applications
resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.batch_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "results" {
  name                  = "results"
  storage_account_name  = azurerm_storage_account.batch_storage.name
  container_access_type = "private"
}

# Virtual Network for HPC communication
resource "azurerm_virtual_network" "hpc_vnet" {
  name                = var.virtual_network_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "network"
  }
}

# Subnet for Batch compute nodes
resource "azurerm_subnet" "batch_subnet" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.hpc.name
  virtual_network_name = azurerm_virtual_network.hpc_vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  # Delegate subnet to Microsoft.Batch for exclusive use
  delegation {
    name = "batch-delegation"
    
    service_delegation {
      name    = "Microsoft.Batch/batchAccounts"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

# Network Security Group for HPC traffic
resource "azurerm_network_security_group" "hpc_nsg" {
  name                = var.network_security_group_name
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name

  # Allow internal HPC communication
  security_rule {
    name                       = "AllowHPCCommunication"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1024-65535"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "10.0.0.0/16"
  }

  # Allow SSH access for management
  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow iSCSI traffic for Elastic SAN
  security_rule {
    name                       = "AllowiSCSI"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3260"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "10.0.0.0/16"
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "security"
  }
}

# Associate NSG with Batch subnet
resource "azurerm_subnet_network_security_group_association" "batch_nsg_association" {
  subnet_id                 = azurerm_subnet.batch_subnet.id
  network_security_group_id = azurerm_network_security_group.hpc_nsg.id
}

# Azure Elastic SAN for high-performance shared storage
resource "azurerm_elastic_san" "hpc_esan" {
  name                = var.elastic_san_name
  resource_group_name = azurerm_resource_group.hpc.name
  location            = azurerm_resource_group.hpc.location

  # Storage capacity configuration
  base_size_in_tib            = var.elastic_san_base_size_tib
  extended_capacity_size_tib  = var.elastic_san_extended_capacity_tib

  # Performance SKU for high IOPS and throughput
  sku {
    name = "Premium_LRS"
    tier = "Premium"
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "shared-storage"
  }
}

# Volume Group for organizing HPC storage
resource "azurerm_elastic_san_volume_group" "hpc_volume_group" {
  name            = "hpc-volumes"
  elastic_san_id  = azurerm_elastic_san.hpc_esan.id
  protocol_type   = "Iscsi"
  
  # Network access control for secure connectivity
  network_rule {
    subnet_id = azurerm_subnet.batch_subnet.id
    action    = "Allow"
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "volume-group"
  }
}

# Data input volume for HPC workloads
resource "azurerm_elastic_san_volume" "data_input" {
  name              = "data-input"
  volume_group_id   = azurerm_elastic_san_volume_group.hpc_volume_group.id
  size_in_gib       = var.data_input_volume_size_gib

  tags = {
    Purpose     = "input-data"
    Environment = var.environment
    Workload    = "hpc"
  }
}

# Results output volume for processed data
resource "azurerm_elastic_san_volume" "results_output" {
  name              = "results-output"
  volume_group_id   = azurerm_elastic_san_volume_group.hpc_volume_group.id
  size_in_gib       = var.results_output_volume_size_gib

  tags = {
    Purpose     = "output-data"
    Environment = var.environment
    Workload    = "hpc"
  }
}

# Shared libraries volume for application binaries
resource "azurerm_elastic_san_volume" "shared_libraries" {
  name              = "shared-libraries"
  volume_group_id   = azurerm_elastic_san_volume_group.hpc_volume_group.id
  size_in_gib       = var.shared_libraries_volume_size_gib

  tags = {
    Purpose     = "shared-libs"
    Environment = var.environment
    Workload    = "hpc"
  }
}

# Azure Batch Account for HPC workload orchestration
resource "azurerm_batch_account" "hpc_batch" {
  name                                = var.batch_account_name
  resource_group_name                 = azurerm_resource_group.hpc.name
  location                            = azurerm_resource_group.hpc.location
  pool_allocation_mode                = "BatchService"
  storage_account_id                  = azurerm_storage_account.batch_storage.id
  storage_account_authentication_mode = "StorageKeys"

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "batch"
  }
}

# Batch Pool for HPC compute nodes
resource "azurerm_batch_pool" "hpc_pool" {
  name                = var.batch_pool_name
  resource_group_name = azurerm_resource_group.hpc.name
  account_name        = azurerm_batch_account.hpc_batch.name
  display_name        = "HPC Compute Pool"
  vm_size             = var.batch_vm_size
  
  # Node agent configuration for Ubuntu
  node_agent_sku_id = "batch.node.ubuntu 20.04"

  # Auto-scaling configuration
  auto_scale {
    evaluation_interval = "PT5M"
    formula = <<-EOT
      startingNumberOfVMs = 1;
      maxNumberofVMs = ${var.batch_pool_max_nodes};
      pendingTaskSamplePercent = $PendingTasks.GetSamplePercent(180 * TimeInterval_Second);
      pendingTaskSamples = pendingTaskSamplePercent < 70 ? startingNumberOfVMs : 
                          avg($PendingTasks.GetSample(180 * TimeInterval_Second));
      $TargetDedicatedNodes = min(maxNumberofVMs, pendingTaskSamples);
      $NodeDeallocationOption = taskcompletion;
    EOT
  }

  # VM image configuration
  storage_image_reference {
    publisher = "canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  # Network configuration for subnet placement
  network_configuration {
    subnet_id = azurerm_subnet.batch_subnet.id
  }

  # Start task for node initialization
  start_task {
    command_line = "/bin/bash -c 'apt-get update && apt-get install -y open-iscsi multipath-tools python3-pip && pip3 install numpy'"
    
    # Run with administrative privileges
    user_identity {
      auto_user {
        scope           = "pool"
        elevation_level = "admin"
      }
    }
    
    wait_for_success = true
    max_task_retry_count = 3
  }

  # User account for HPC workloads
  user_account {
    name            = "hpcuser"
    password        = var.hpc_user_password
    elevation_level = "admin"
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "compute-pool"
  }
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "hpc_monitoring" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "monitoring"
  }
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "hpc_insights" {
  name                = var.application_insights_name
  location            = azurerm_resource_group.hpc.location
  resource_group_name = azurerm_resource_group.hpc.name
  workspace_id        = azurerm_log_analytics_workspace.hpc_monitoring.id
  application_type    = "web"

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "insights"
  }
}

# Diagnostic settings for Batch account
resource "azurerm_monitor_diagnostic_setting" "batch_diagnostics" {
  name                       = "batch-diagnostics"
  target_resource_id         = azurerm_batch_account.hpc_batch.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.hpc_monitoring.id

  enabled_log {
    category = "ServiceLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Action Group for alerting
resource "azurerm_monitor_action_group" "hpc_alerts" {
  name                = var.action_group_name
  resource_group_name = azurerm_resource_group.hpc.name
  short_name          = "hpc-alerts"

  # Email notification (configure based on requirements)
  email_receiver {
    name          = "admin-email"
    email_address = var.alert_email_address
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "alerting"
  }
}

# CPU Usage Alert
resource "azurerm_monitor_metric_alert" "cpu_usage_alert" {
  name                = "hpc-high-cpu-usage"
  resource_group_name = azurerm_resource_group.hpc.name
  scopes              = [azurerm_batch_account.hpc_batch.id]
  description         = "HPC pool CPU usage is above 80%"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Batch/batchAccounts"
    metric_name      = "PoolCpuUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.hpc_alerts.id
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "monitoring"
  }
}

# Cost Alert for node count threshold
resource "azurerm_monitor_metric_alert" "cost_threshold_alert" {
  name                = "hpc-cost-threshold"
  resource_group_name = azurerm_resource_group.hpc.name
  scopes              = [azurerm_batch_account.hpc_batch.id]
  description         = "HPC pool node count exceeds cost threshold"
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Batch/batchAccounts"
    metric_name      = "PoolDedicatedNodes"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cost_threshold_node_count
  }

  action {
    action_group_id = azurerm_monitor_action_group.hpc_alerts.id
  }

  tags = {
    Purpose     = "HPC"
    Environment = var.environment
    Workload    = "cost-monitoring"
  }
}