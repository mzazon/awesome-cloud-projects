# Azure Private 5G Network Infrastructure with Operator Nexus
# This Terraform configuration deploys a complete private 5G network solution
# using Azure Operator Nexus and Azure Private 5G Core services

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Create resource group for all Private 5G resources
resource "azurerm_resource_group" "private_5g" {
  name     = "rg-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Component = "ResourceGroup"
    CreatedBy = "Terraform"
  })

  lifecycle {
    ignore_changes = [
      tags["CreatedDate"]
    ]
  }
}

# Register required resource providers
resource "azurerm_resource_provider_registration" "mobile_network" {
  name = "Microsoft.MobileNetwork"
}

resource "azurerm_resource_provider_registration" "extended_location" {
  name = "Microsoft.ExtendedLocation"
}

resource "azurerm_resource_provider_registration" "kubernetes" {
  name = "Microsoft.Kubernetes"
}

resource "azurerm_resource_provider_registration" "kubernetes_configuration" {
  name = "Microsoft.KubernetesConfiguration"
}

# Wait for resource providers to be registered
resource "time_sleep" "wait_for_providers" {
  depends_on = [
    azurerm_resource_provider_registration.mobile_network,
    azurerm_resource_provider_registration.extended_location,
    azurerm_resource_provider_registration.kubernetes,
    azurerm_resource_provider_registration.kubernetes_configuration
  ]

  create_duration = "60s"
}

#
# MOBILE NETWORK CORE INFRASTRUCTURE
#

# Create the mobile network resource (top-level 5G network definition)
resource "azurerm_mobile_network" "main" {
  name                = var.mobile_network_name
  location            = azurerm_resource_group.private_5g.location
  resource_group_name = azurerm_resource_group.private_5g.name

  # Public Land Mobile Network (PLMN) identifier
  mobile_country_code = var.plmn_mcc
  mobile_network_code = var.plmn_mnc

  tags = merge(var.tags, {
    Component = "MobileNetwork"
    PLMN      = "${var.plmn_mcc}-${var.plmn_mnc}"
  })

  depends_on = [time_sleep.wait_for_providers]
}

# Create network slices for different use cases
resource "azurerm_mobile_network_slice" "slices" {
  count = var.enable_network_slices ? length(var.network_slices) : 0

  name              = var.network_slices[count.index].name
  mobile_network_id = azurerm_mobile_network.main.id
  location          = azurerm_resource_group.private_5g.location

  # Single Network Slice Selection Assistance Information (S-NSSAI)
  single_network_slice_selection_assistance_information {
    slice_service_type = var.network_slices[count.index].sst
    slice_differentiator = var.network_slices[count.index].sd
  }

  description = var.network_slices[count.index].description

  tags = merge(var.tags, {
    Component = "NetworkSlice"
    UseCase   = var.network_slices[count.index].name
    SST       = tostring(var.network_slices[count.index].sst)
  })
}

#
# DATA NETWORKS FOR TRAFFIC SEGMENTATION
#

# Data network for OT (Operational Technology) systems
resource "azurerm_mobile_network_data_network" "ot_systems" {
  name              = "dn-ot-systems"
  mobile_network_id = azurerm_mobile_network.main.id
  location          = azurerm_resource_group.private_5g.location
  description       = "Data network for operational technology systems and industrial control"

  tags = merge(var.tags, {
    Component = "DataNetwork"
    Purpose   = "OT-Systems"
    Security  = "High"
  })
}

# Data network for IT systems
resource "azurerm_mobile_network_data_network" "it_systems" {
  name              = "dn-it-systems"
  mobile_network_id = azurerm_mobile_network.main.id
  location          = azurerm_resource_group.private_5g.location
  description       = "Data network for information technology systems and enterprise applications"

  tags = merge(var.tags, {
    Component = "DataNetwork"
    Purpose   = "IT-Systems"
    Security  = "Medium"
  })
}

#
# SITE INFRASTRUCTURE
#

# Create site resource for physical deployment location
resource "azurerm_mobile_network_site" "main" {
  name              = var.site_name
  mobile_network_id = azurerm_mobile_network.main.id
  location          = azurerm_resource_group.private_5g.location
  description       = "Manufacturing site deployment for private 5G network"

  tags = merge(var.tags, {
    Component = "Site"
    SiteType  = "Manufacturing"
    Location  = var.site_name
  })
}

# Note: Custom location and packet core control plane would be created here
# However, these resources require pre-existing Azure Stack Edge devices and
# Arc-enabled Kubernetes clusters, which are not manageable via Terraform.
# In a real deployment, these would be created manually or via Azure CLI
# after the Azure Stack Edge hardware is provisioned and configured.

#
# SERVICES AND POLICIES
#

# Service for real-time control systems (URLLC)
resource "azurerm_mobile_network_service" "realtime_control" {
  name              = "svc-realtime-control"
  mobile_network_id = azurerm_mobile_network.main.id
  location          = azurerm_resource_group.private_5g.location
  
  # Quality of Service (QoS) settings for ultra-reliable low-latency
  service_qos_policy {
    qos_indicator                = 82  # Real-time gaming/control applications
    allocation_and_retention_priority_level = 1
    preemption_capability       = "MayPreempt"
    preemption_vulnerability   = "NotPreemptable"
    maximum_bit_rate {
      downlink = "50 Mbps"
      uplink   = "50 Mbps"
    }
  }

  # Packet Core Control Protocol (PCCP) rules for traffic flow
  pcc_rule {
    name               = "rule-control"
    precedence         = 100
    qos_policy         = azurerm_mobile_network_service.realtime_control.service_qos_policy[0].qos_indicator
    traffic_control    = "Enabled"
    
    service_data_flow_template {
      template_name = "control-traffic"
      direction     = "Bidirectional"
      protocol      = ["TCP"]
      remote_ip_list = ["10.1.0.0/16"]
    }
  }

  tags = merge(var.tags, {
    Component   = "Service"
    ServiceType = "URLLC"
    Priority    = "Critical"
  })
}

# Service for video surveillance
resource "azurerm_mobile_network_service" "video_surveillance" {
  name              = "svc-video-surveillance"
  mobile_network_id = azurerm_mobile_network.main.id
  location          = azurerm_resource_group.private_5g.location
  
  # QoS settings for video streaming
  service_qos_policy {
    qos_indicator                = 4   # Video streaming
    allocation_and_retention_priority_level = 5
    preemption_capability       = "MayPreempt"
    preemption_vulnerability   = "Preemptable"
    maximum_bit_rate {
      downlink = "100 Mbps"
      uplink   = "100 Mbps"
    }
  }

  # PCCP rules for video traffic
  pcc_rule {
    name               = "rule-video"
    precedence         = 200
    qos_policy         = azurerm_mobile_network_service.video_surveillance.service_qos_policy[0].qos_indicator
    traffic_control    = "Enabled"
    
    service_data_flow_template {
      template_name = "video-streams"
      direction     = "Uplink"
      protocol      = ["UDP"]
      remote_ip_list = ["10.2.0.0/16"]
      ports         = ["554"]
    }
  }

  tags = merge(var.tags, {
    Component   = "Service"
    ServiceType = "eMBB"
    Priority    = "High"
  })
}

# SIM policy for industrial IoT devices
resource "azurerm_mobile_network_sim_policy" "industrial_iot" {
  name              = "policy-industrial-iot"
  mobile_network_id = azurerm_mobile_network.main.id
  location          = azurerm_resource_group.private_5g.location

  # User Equipment Aggregate Maximum Bit Rate (UE-AMBR)
  ue_ambr {
    downlink = "10 Mbps"
    uplink   = "10 Mbps"
  }

  # Default slice assignment (use first slice if available)
  default_slice_id = var.enable_network_slices && length(azurerm_mobile_network_slice.slices) > 0 ? azurerm_mobile_network_slice.slices[0].id : null

  # Slice configurations
  dynamic "slice" {
    for_each = var.enable_network_slices ? [azurerm_mobile_network_slice.slices[0]] : []
    content {
      slice_id = slice.value.id
      
      # Default data network for this slice
      default_data_network_id = azurerm_mobile_network_data_network.ot_systems.id
      
      data_network {
        data_network_id = azurerm_mobile_network_data_network.ot_systems.id
        
        # Session AMBR for this data network
        session_ambr {
          downlink = "10 Mbps"
          uplink   = "10 Mbps"
        }
        
        # QoS configuration
        qos_indicator = 82
        allocation_and_retention_priority_level = 1
      }
    }
  }

  registration_timer = 3240  # Registration timer in seconds

  tags = merge(var.tags, {
    Component = "SIMPolicy"
    DeviceType = "Industrial-IoT"
    SecurityLevel = "High"
  })
}

#
# MONITORING AND ANALYTICS
#

# Log Analytics workspace for 5G network monitoring
resource "azurerm_log_analytics_workspace" "private_5g" {
  count = var.enable_analytics ? 1 : 0

  name                = "law-private5g-${random_string.suffix.result}"
  location            = azurerm_resource_group.private_5g.location
  resource_group_name = azurerm_resource_group.private_5g.name
  sku                 = "PerGB2018"
  retention_in_days   = var.backup_retention_days

  tags = merge(var.tags, {
    Component = "LogAnalytics"
    Purpose   = "5G-Monitoring"
  })
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "private_5g" {
  count = var.enable_analytics ? 1 : 0

  name                = "appi-private5g-${random_string.suffix.result}"
  location            = azurerm_resource_group.private_5g.location
  resource_group_name = azurerm_resource_group.private_5g.name
  workspace_id        = azurerm_log_analytics_workspace.private_5g[0].id
  application_type    = "web"

  tags = merge(var.tags, {
    Component = "ApplicationInsights"
    Purpose   = "5G-ApplicationMonitoring"
  })
}

#
# IOT INTEGRATION
#

# IoT Hub for device management and data ingestion
resource "azurerm_iothub" "private_5g" {
  count = var.enable_iot_integration ? 1 : 0

  name                = "iothub-5g-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.private_5g.name
  location            = azurerm_resource_group.private_5g.location

  sku {
    name     = var.iot_hub_sku
    capacity = var.iot_hub_sku == "F1" ? 1 : 2
  }

  # Enable file upload for device diagnostics
  file_upload {
    connection_string  = azurerm_storage_account.private_5g[0].primary_blob_connection_string
    container_name     = azurerm_storage_container.iot_uploads[0].name
    sas_ttl            = "PT1H"
    authentication_type = "keyBased"
    lock_duration      = "PT1M"
    default_ttl        = "PT1H"
    max_delivery_count = 10
  }

  tags = merge(var.tags, {
    Component = "IoTHub"
    Purpose   = "DeviceManagement"
  })
}

# IoT Hub Device Provisioning Service
resource "azurerm_iothub_dps" "private_5g" {
  count = var.enable_iot_integration ? 1 : 0

  name                = "dps-5g-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.private_5g.name
  location            = azurerm_resource_group.private_5g.location
  allocation_policy   = "Hashed"

  sku {
    name     = "S1"
    capacity = 1
  }

  linked_hub {
    connection_string = azurerm_iothub.private_5g[0].shared_access_policy[0].connection_string
    location          = azurerm_resource_group.private_5g.location
  }

  tags = merge(var.tags, {
    Component = "DeviceProvisioningService"
    Purpose   = "DeviceProvisioning"
  })
}

# Storage account for IoT data and diagnostics
resource "azurerm_storage_account" "private_5g" {
  count = var.enable_iot_integration ? 1 : 0

  name                     = "st5g${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.private_5g.name
  location                 = azurerm_resource_group.private_5g.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable blob versioning and soft delete
  blob_properties {
    versioning_enabled  = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = merge(var.tags, {
    Component = "Storage"
    Purpose   = "IoT-Data"
  })
}

# Storage container for IoT Hub file uploads
resource "azurerm_storage_container" "iot_uploads" {
  count = var.enable_iot_integration ? 1 : 0

  name                  = "iot-uploads"
  storage_account_name  = azurerm_storage_account.private_5g[0].name
  container_access_type = "private"
}

#
# CONTAINER REGISTRY FOR EDGE WORKLOADS
#

# Azure Container Registry for edge applications
resource "azurerm_container_registry" "private_5g" {
  count = var.enable_container_registry ? 1 : 0

  name                = "acr5g${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.private_5g.name
  location            = azurerm_resource_group.private_5g.location
  sku                 = var.container_registry_sku
  admin_enabled       = true

  # Enable geo-replication for Premium SKU
  dynamic "georeplications" {
    for_each = var.container_registry_sku == "Premium" ? ["eastus2"] : []
    content {
      location = georeplications.value
      tags     = var.tags
    }
  }

  # Configure network access rules if IP ranges are specified
  dynamic "network_rule_set" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"
      
      dynamic "ip_rule" {
        for_each = var.allowed_ip_ranges
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }
    }
  }

  tags = merge(var.tags, {
    Component = "ContainerRegistry"
    Purpose   = "EdgeWorkloads"
  })
}

#
# SECURITY AND IDENTITY
#

# Key Vault for storing secrets and certificates
resource "azurerm_key_vault" "private_5g" {
  name                        = "kv-5g-${random_string.suffix.result}"
  location                    = azurerm_resource_group.private_5g.location
  resource_group_name         = azurerm_resource_group.private_5g.name
  enabled_for_disk_encryption = true
  enabled_for_deployment      = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"

  # Configure network access rules
  network_acls {
    default_action = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"
    bypass         = "AzureServices"
    
    dynamic "ip_rules" {
      for_each = var.allowed_ip_ranges
      content {
        value = ip_rules.value
      }
    }
  }

  tags = merge(var.tags, {
    Component = "KeyVault"
    Purpose   = "SecretManagement"
  })
}

# Access policy for current deployment principal
resource "azurerm_key_vault_access_policy" "deployment" {
  key_vault_id = azurerm_key_vault.private_5g.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]

  certificate_permissions = [
    "Get", "List", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]

  key_permissions = [
    "Get", "List", "Create", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]
}

#
# DIAGNOSTIC SETTINGS
#

# Diagnostic settings for mobile network (when packet core is available)
# Note: This would be configured after packet core deployment
resource "azurerm_monitor_diagnostic_setting" "mobile_network" {
  count = var.enable_analytics ? 1 : 0

  name                       = "diag-mobile-network"
  target_resource_id         = azurerm_mobile_network.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.private_5g[0].id

  # Note: Actual log categories depend on available diagnostic logs for mobile network
  # These would be configured based on available telemetry from the packet core

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = var.backup_retention_days
    }
  }
}

# Diagnostic settings for IoT Hub
resource "azurerm_monitor_diagnostic_setting" "iot_hub" {
  count = var.enable_iot_integration && var.enable_analytics ? 1 : 0

  name                       = "diag-iot-hub"
  target_resource_id         = azurerm_iothub.private_5g[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.private_5g[0].id

  enabled_log {
    category = "Connections"

    retention_policy {
      enabled = true
      days    = var.backup_retention_days
    }
  }

  enabled_log {
    category = "DeviceTelemetry"

    retention_policy {
      enabled = true
      days    = var.backup_retention_days
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = true
      days    = var.backup_retention_days
    }
  }
}