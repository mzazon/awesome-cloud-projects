# Outputs for Azure Private 5G Network deployment
# These outputs provide essential information for connecting devices,
# managing the network, and integrating with other systems

#
# RESOURCE GROUP AND BASIC INFO
#

output "resource_group_name" {
  description = "Name of the resource group containing all Private 5G resources"
  value       = azurerm_resource_group.private_5g.name
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.private_5g.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.private_5g.location
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

#
# MOBILE NETWORK CORE INFORMATION
#

output "mobile_network_id" {
  description = "Resource ID of the mobile network"
  value       = azurerm_mobile_network.main.id
}

output "mobile_network_name" {
  description = "Name of the mobile network"
  value       = azurerm_mobile_network.main.name
}

output "plmn_identifier" {
  description = "Public Land Mobile Network (PLMN) identifier in MCC-MNC format"
  value       = "${azurerm_mobile_network.main.mobile_country_code}-${azurerm_mobile_network.main.mobile_network_code}"
}

output "mobile_country_code" {
  description = "Mobile Country Code (MCC) for the network"
  value       = azurerm_mobile_network.main.mobile_country_code
}

output "mobile_network_code" {
  description = "Mobile Network Code (MNC) for the network"
  value       = azurerm_mobile_network.main.mobile_network_code
}

#
# NETWORK SLICES INFORMATION
#

output "network_slices" {
  description = "Information about configured network slices"
  value = var.enable_network_slices ? {
    for slice in azurerm_mobile_network_slice.slices : slice.name => {
      id          = slice.id
      name        = slice.name
      description = slice.description
      sst         = slice.single_network_slice_selection_assistance_information[0].slice_service_type
      sd          = slice.single_network_slice_selection_assistance_information[0].slice_differentiator
    }
  } : {}
}

output "network_slice_count" {
  description = "Number of network slices configured"
  value       = var.enable_network_slices ? length(azurerm_mobile_network_slice.slices) : 0
}

#
# DATA NETWORKS INFORMATION
#

output "data_networks" {
  description = "Information about configured data networks"
  value = {
    ot_systems = {
      id          = azurerm_mobile_network_data_network.ot_systems.id
      name        = azurerm_mobile_network_data_network.ot_systems.name
      description = azurerm_mobile_network_data_network.ot_systems.description
    }
    it_systems = {
      id          = azurerm_mobile_network_data_network.it_systems.id
      name        = azurerm_mobile_network_data_network.it_systems.name
      description = azurerm_mobile_network_data_network.it_systems.description
    }
  }
}

#
# SITE INFORMATION
#

output "site_id" {
  description = "Resource ID of the mobile network site"
  value       = azurerm_mobile_network_site.main.id
}

output "site_name" {
  description = "Name of the mobile network site"
  value       = azurerm_mobile_network_site.main.name
}

#
# SERVICES AND POLICIES
#

output "services" {
  description = "Information about configured 5G services"
  value = {
    realtime_control = {
      id          = azurerm_mobile_network_service.realtime_control.id
      name        = azurerm_mobile_network_service.realtime_control.name
      qos_indicator = azurerm_mobile_network_service.realtime_control.service_qos_policy[0].qos_indicator
      priority_level = azurerm_mobile_network_service.realtime_control.service_qos_policy[0].allocation_and_retention_priority_level
    }
    video_surveillance = {
      id          = azurerm_mobile_network_service.video_surveillance.id
      name        = azurerm_mobile_network_service.video_surveillance.name
      qos_indicator = azurerm_mobile_network_service.video_surveillance.service_qos_policy[0].qos_indicator
      priority_level = azurerm_mobile_network_service.video_surveillance.service_qos_policy[0].allocation_and_retention_priority_level
    }
  }
}

output "sim_policy_id" {
  description = "Resource ID of the SIM policy for industrial IoT devices"
  value       = azurerm_mobile_network_sim_policy.industrial_iot.id
}

output "sim_policy_name" {
  description = "Name of the SIM policy for industrial IoT devices"
  value       = azurerm_mobile_network_sim_policy.industrial_iot.name
}

#
# MONITORING AND ANALYTICS
#

output "log_analytics_workspace" {
  description = "Log Analytics workspace information"
  value = var.enable_analytics ? {
    id                = azurerm_log_analytics_workspace.private_5g[0].id
    name              = azurerm_log_analytics_workspace.private_5g[0].name
    workspace_id      = azurerm_log_analytics_workspace.private_5g[0].workspace_id
    primary_shared_key = azurerm_log_analytics_workspace.private_5g[0].primary_shared_key
  } : null
  sensitive = true
}

output "application_insights" {
  description = "Application Insights information"
  value = var.enable_analytics ? {
    id                = azurerm_application_insights.private_5g[0].id
    name              = azurerm_application_insights.private_5g[0].name
    instrumentation_key = azurerm_application_insights.private_5g[0].instrumentation_key
    connection_string = azurerm_application_insights.private_5g[0].connection_string
  } : null
  sensitive = true
}

#
# IOT INTEGRATION
#

output "iot_hub" {
  description = "IoT Hub information for device management"
  value = var.enable_iot_integration ? {
    id       = azurerm_iothub.private_5g[0].id
    name     = azurerm_iothub.private_5g[0].name
    hostname = azurerm_iothub.private_5g[0].hostname
    sku_name = azurerm_iothub.private_5g[0].sku[0].name
    sku_capacity = azurerm_iothub.private_5g[0].sku[0].capacity
  } : null
}

output "iot_hub_connection_strings" {
  description = "IoT Hub connection strings for different access policies"
  value = var.enable_iot_integration ? {
    for policy in azurerm_iothub.private_5g[0].shared_access_policy :
    policy.name => {
      connection_string = policy.connection_string
      permissions      = policy.permissions
    }
  } : {}
  sensitive = true
}

output "device_provisioning_service" {
  description = "Device Provisioning Service information"
  value = var.enable_iot_integration ? {
    id                = azurerm_iothub_dps.private_5g[0].id
    name              = azurerm_iothub_dps.private_5g[0].name
    id_scope          = azurerm_iothub_dps.private_5g[0].id_scope
    service_operations_host_name = azurerm_iothub_dps.private_5g[0].service_operations_host_name
    device_provisioning_host_name = azurerm_iothub_dps.private_5g[0].device_provisioning_host_name
  } : null
}

output "storage_account" {
  description = "Storage account information for IoT data"
  value = var.enable_iot_integration ? {
    id                = azurerm_storage_account.private_5g[0].id
    name              = azurerm_storage_account.private_5g[0].name
    primary_blob_endpoint = azurerm_storage_account.private_5g[0].primary_blob_endpoint
    primary_access_key = azurerm_storage_account.private_5g[0].primary_access_key
  } : null
  sensitive = true
}

#
# CONTAINER REGISTRY
#

output "container_registry" {
  description = "Azure Container Registry information for edge workloads"
  value = var.enable_container_registry ? {
    id           = azurerm_container_registry.private_5g[0].id
    name         = azurerm_container_registry.private_5g[0].name
    login_server = azurerm_container_registry.private_5g[0].login_server
    admin_username = azurerm_container_registry.private_5g[0].admin_username
    sku         = azurerm_container_registry.private_5g[0].sku
  } : null
}

output "container_registry_credentials" {
  description = "Container registry admin credentials"
  value = var.enable_container_registry ? {
    username = azurerm_container_registry.private_5g[0].admin_username
    password = azurerm_container_registry.private_5g[0].admin_password
  } : null
  sensitive = true
}

#
# SECURITY AND KEY VAULT
#

output "key_vault" {
  description = "Key Vault information for secret management"
  value = {
    id                = azurerm_key_vault.private_5g.id
    name              = azurerm_key_vault.private_5g.name
    vault_uri         = azurerm_key_vault.private_5g.vault_uri
    tenant_id         = azurerm_key_vault.private_5g.tenant_id
  }
}

#
# NETWORK CONFIGURATION
#

output "network_configuration" {
  description = "Network interface configuration for radio equipment integration"
  value = {
    access_interface = {
      ip_address = var.access_interface_ip
      subnet     = var.access_interface_subnet
      gateway    = var.access_interface_gateway
    }
    ot_systems = {
      dns_servers      = var.ot_systems_dns_servers
      user_plane_ip    = var.ot_user_plane_ip
    }
    it_systems = {
      dns_servers      = var.it_systems_dns_servers
      user_plane_ip    = var.it_user_plane_ip
    }
  }
}

#
# NEXT STEPS AND DEPLOYMENT GUIDANCE
#

output "deployment_next_steps" {
  description = "Next steps for completing the Private 5G deployment"
  value = {
    message = "Mobile network resources created successfully. To complete deployment:"
    steps = [
      "1. Deploy and configure Azure Stack Edge Pro GPU devices at the site location",
      "2. Connect Azure Stack Edge to Azure Arc and enable Kubernetes",
      "3. Create custom location resource pointing to the Arc-enabled cluster",
      "4. Deploy packet core control plane using Azure CLI or portal",
      "5. Configure and connect 5G radio equipment (gNodeB) to the N2/N3 interfaces",
      "6. Provision SIM cards and register devices using the SIM policy",
      "7. Deploy edge workloads to the Azure Container Registry",
      "8. Configure monitoring dashboards in Log Analytics workspace"
    ]
    documentation = [
      "Azure Private 5G Core: https://docs.microsoft.com/azure/private-5g-core/",
      "Azure Stack Edge: https://docs.microsoft.com/azure/databox-online/",
      "Azure Arc-enabled Kubernetes: https://docs.microsoft.com/azure/azure-arc/kubernetes/"
    ]
  }
}

#
# COST OPTIMIZATION RECOMMENDATIONS
#

output "cost_optimization" {
  description = "Recommendations for optimizing costs"
  value = {
    recommendations = [
      "Monitor IoT Hub message usage and adjust SKU based on actual device telemetry volume",
      "Configure Log Analytics data retention based on compliance requirements",
      "Use Azure Cost Management to set up budgets and alerts for 5G infrastructure",
      "Consider Reserved Instances for long-term deployments",
      "Review and optimize container registry storage for unused images"
    ]
    monitoring = {
      log_analytics_workspace = var.enable_analytics ? azurerm_log_analytics_workspace.private_5g[0].name : null
      cost_management_scope = azurerm_resource_group.private_5g.id
    }
  }
}

#
# COMPLIANCE AND SECURITY NOTES
#

output "security_considerations" {
  description = "Security and compliance considerations for the deployment"
  value = {
    recommendations = [
      "Enable Azure Security Center for the resource group",
      "Configure network security groups for Azure Stack Edge interfaces",
      "Implement Azure Private Endpoints for management traffic (if required)",
      "Regular security assessment of 5G devices and SIM provisioning",
      "Monitor for anomalous device behavior using Azure Sentinel"
    ]
    key_vault = azurerm_key_vault.private_5g.vault_uri
    diagnostic_logs = var.enable_analytics ? azurerm_log_analytics_workspace.private_5g[0].workspace_id : null
  }
}