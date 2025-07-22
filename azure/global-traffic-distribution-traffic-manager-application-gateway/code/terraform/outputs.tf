# Output values for global traffic distribution infrastructure

# Random suffix for unique naming
output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Resource Group Information
output "resource_groups" {
  description = "Information about created resource groups"
  value = {
    primary = {
      name     = azurerm_resource_group.primary.name
      location = azurerm_resource_group.primary.location
      id       = azurerm_resource_group.primary.id
    }
    secondary = {
      name     = azurerm_resource_group.secondary.name
      location = azurerm_resource_group.secondary.location
      id       = azurerm_resource_group.secondary.id
    }
    tertiary = {
      name     = azurerm_resource_group.tertiary.name
      location = azurerm_resource_group.tertiary.location
      id       = azurerm_resource_group.tertiary.id
    }
  }
}

# Virtual Network Information
output "virtual_networks" {
  description = "Information about created virtual networks"
  value = {
    primary = {
      name          = azurerm_virtual_network.primary.name
      address_space = azurerm_virtual_network.primary.address_space
      id            = azurerm_virtual_network.primary.id
    }
    secondary = {
      name          = azurerm_virtual_network.secondary.name
      address_space = azurerm_virtual_network.secondary.address_space
      id            = azurerm_virtual_network.secondary.id
    }
    tertiary = {
      name          = azurerm_virtual_network.tertiary.name
      address_space = azurerm_virtual_network.tertiary.address_space
      id            = azurerm_virtual_network.tertiary.id
    }
  }
}

# Subnet Information
output "subnets" {
  description = "Information about created subnets"
  value = {
    primary = {
      appgw_subnet = {
        name           = azurerm_subnet.appgw_primary.name
        address_prefix = azurerm_subnet.appgw_primary.address_prefixes[0]
        id             = azurerm_subnet.appgw_primary.id
      }
      backend_subnet = {
        name           = azurerm_subnet.backend_primary.name
        address_prefix = azurerm_subnet.backend_primary.address_prefixes[0]
        id             = azurerm_subnet.backend_primary.id
      }
    }
    secondary = {
      appgw_subnet = {
        name           = azurerm_subnet.appgw_secondary.name
        address_prefix = azurerm_subnet.appgw_secondary.address_prefixes[0]
        id             = azurerm_subnet.appgw_secondary.id
      }
      backend_subnet = {
        name           = azurerm_subnet.backend_secondary.name
        address_prefix = azurerm_subnet.backend_secondary.address_prefixes[0]
        id             = azurerm_subnet.backend_secondary.id
      }
    }
    tertiary = {
      appgw_subnet = {
        name           = azurerm_subnet.appgw_tertiary.name
        address_prefix = azurerm_subnet.appgw_tertiary.address_prefixes[0]
        id             = azurerm_subnet.appgw_tertiary.id
      }
      backend_subnet = {
        name           = azurerm_subnet.backend_tertiary.name
        address_prefix = azurerm_subnet.backend_tertiary.address_prefixes[0]
        id             = azurerm_subnet.backend_tertiary.id
      }
    }
  }
}

# Public IP Information
output "public_ips" {
  description = "Information about created public IP addresses"
  value = {
    primary = {
      name       = azurerm_public_ip.appgw_primary.name
      ip_address = azurerm_public_ip.appgw_primary.ip_address
      fqdn       = azurerm_public_ip.appgw_primary.fqdn
      id         = azurerm_public_ip.appgw_primary.id
    }
    secondary = {
      name       = azurerm_public_ip.appgw_secondary.name
      ip_address = azurerm_public_ip.appgw_secondary.ip_address
      fqdn       = azurerm_public_ip.appgw_secondary.fqdn
      id         = azurerm_public_ip.appgw_secondary.id
    }
    tertiary = {
      name       = azurerm_public_ip.appgw_tertiary.name
      ip_address = azurerm_public_ip.appgw_tertiary.ip_address
      fqdn       = azurerm_public_ip.appgw_tertiary.fqdn
      id         = azurerm_public_ip.appgw_tertiary.id
    }
  }
}

# Application Gateway Information
output "application_gateways" {
  description = "Information about created Application Gateways"
  value = {
    primary = {
      name     = azurerm_application_gateway.primary.name
      id       = azurerm_application_gateway.primary.id
      location = azurerm_application_gateway.primary.location
      sku_name = azurerm_application_gateway.primary.sku[0].name
      sku_tier = azurerm_application_gateway.primary.sku[0].tier
    }
    secondary = {
      name     = azurerm_application_gateway.secondary.name
      id       = azurerm_application_gateway.secondary.id
      location = azurerm_application_gateway.secondary.location
      sku_name = azurerm_application_gateway.secondary.sku[0].name
      sku_tier = azurerm_application_gateway.secondary.sku[0].tier
    }
    tertiary = {
      name     = azurerm_application_gateway.tertiary.name
      id       = azurerm_application_gateway.tertiary.id
      location = azurerm_application_gateway.tertiary.location
      sku_name = azurerm_application_gateway.tertiary.sku[0].name
      sku_tier = azurerm_application_gateway.tertiary.sku[0].tier
    }
  }
}

# WAF Policy Information
output "waf_policies" {
  description = "Information about created WAF policies"
  value = {
    primary = {
      name = azurerm_web_application_firewall_policy.primary.name
      id   = azurerm_web_application_firewall_policy.primary.id
    }
    secondary = {
      name = azurerm_web_application_firewall_policy.secondary.name
      id   = azurerm_web_application_firewall_policy.secondary.id
    }
    tertiary = {
      name = azurerm_web_application_firewall_policy.tertiary.name
      id   = azurerm_web_application_firewall_policy.tertiary.id
    }
  }
}

# Virtual Machine Scale Set Information
output "virtual_machine_scale_sets" {
  description = "Information about created Virtual Machine Scale Sets"
  value = {
    primary = {
      name          = azurerm_linux_virtual_machine_scale_set.primary.name
      id            = azurerm_linux_virtual_machine_scale_set.primary.id
      location      = azurerm_linux_virtual_machine_scale_set.primary.location
      sku           = azurerm_linux_virtual_machine_scale_set.primary.sku
      instances     = azurerm_linux_virtual_machine_scale_set.primary.instances
      unique_id     = azurerm_linux_virtual_machine_scale_set.primary.unique_id
    }
    secondary = {
      name          = azurerm_linux_virtual_machine_scale_set.secondary.name
      id            = azurerm_linux_virtual_machine_scale_set.secondary.id
      location      = azurerm_linux_virtual_machine_scale_set.secondary.location
      sku           = azurerm_linux_virtual_machine_scale_set.secondary.sku
      instances     = azurerm_linux_virtual_machine_scale_set.secondary.instances
      unique_id     = azurerm_linux_virtual_machine_scale_set.secondary.unique_id
    }
    tertiary = {
      name          = azurerm_linux_virtual_machine_scale_set.tertiary.name
      id            = azurerm_linux_virtual_machine_scale_set.tertiary.id
      location      = azurerm_linux_virtual_machine_scale_set.tertiary.location
      sku           = azurerm_linux_virtual_machine_scale_set.tertiary.sku
      instances     = azurerm_linux_virtual_machine_scale_set.tertiary.instances
      unique_id     = azurerm_linux_virtual_machine_scale_set.tertiary.unique_id
    }
  }
}

# Traffic Manager Information
output "traffic_manager" {
  description = "Information about the Traffic Manager profile"
  value = {
    name                = azurerm_traffic_manager_profile.main.name
    id                  = azurerm_traffic_manager_profile.main.id
    fqdn                = azurerm_traffic_manager_profile.main.fqdn
    traffic_routing_method = azurerm_traffic_manager_profile.main.traffic_routing_method
    dns_config = {
      relative_name = azurerm_traffic_manager_profile.main.dns_config[0].relative_name
      ttl          = azurerm_traffic_manager_profile.main.dns_config[0].ttl
    }
    monitor_config = {
      protocol                    = azurerm_traffic_manager_profile.main.monitor_config[0].protocol
      port                       = azurerm_traffic_manager_profile.main.monitor_config[0].port
      path                       = azurerm_traffic_manager_profile.main.monitor_config[0].path
      interval_in_seconds        = azurerm_traffic_manager_profile.main.monitor_config[0].interval_in_seconds
      timeout_in_seconds         = azurerm_traffic_manager_profile.main.monitor_config[0].timeout_in_seconds
      tolerated_number_of_failures = azurerm_traffic_manager_profile.main.monitor_config[0].tolerated_number_of_failures
    }
  }
}

# Traffic Manager Endpoints Information
output "traffic_manager_endpoints" {
  description = "Information about Traffic Manager endpoints"
  value = {
    primary = {
      name              = azurerm_traffic_manager_external_endpoint.primary.name
      id                = azurerm_traffic_manager_external_endpoint.primary.id
      target            = azurerm_traffic_manager_external_endpoint.primary.target
      endpoint_location = azurerm_traffic_manager_external_endpoint.primary.endpoint_location
      priority          = azurerm_traffic_manager_external_endpoint.primary.priority
      weight            = azurerm_traffic_manager_external_endpoint.primary.weight
    }
    secondary = {
      name              = azurerm_traffic_manager_external_endpoint.secondary.name
      id                = azurerm_traffic_manager_external_endpoint.secondary.id
      target            = azurerm_traffic_manager_external_endpoint.secondary.target
      endpoint_location = azurerm_traffic_manager_external_endpoint.secondary.endpoint_location
      priority          = azurerm_traffic_manager_external_endpoint.secondary.priority
      weight            = azurerm_traffic_manager_external_endpoint.secondary.weight
    }
    tertiary = {
      name              = azurerm_traffic_manager_external_endpoint.tertiary.name
      id                = azurerm_traffic_manager_external_endpoint.tertiary.id
      target            = azurerm_traffic_manager_external_endpoint.tertiary.target
      endpoint_location = azurerm_traffic_manager_external_endpoint.tertiary.endpoint_location
      priority          = azurerm_traffic_manager_external_endpoint.tertiary.priority
      weight            = azurerm_traffic_manager_external_endpoint.tertiary.weight
    }
  }
}

# Monitoring Information (conditional)
output "monitoring" {
  description = "Information about monitoring resources"
  value = var.enable_monitoring ? {
    log_analytics_workspace = {
      name                = azurerm_log_analytics_workspace.main[0].name
      id                  = azurerm_log_analytics_workspace.main[0].id
      workspace_id        = azurerm_log_analytics_workspace.main[0].workspace_id
      primary_shared_key  = azurerm_log_analytics_workspace.main[0].primary_shared_key
      location            = azurerm_log_analytics_workspace.main[0].location
      sku                 = azurerm_log_analytics_workspace.main[0].sku
      retention_in_days   = azurerm_log_analytics_workspace.main[0].retention_in_days
    }
    application_insights = {
      name                = azurerm_application_insights.main[0].name
      id                  = azurerm_application_insights.main[0].id
      app_id              = azurerm_application_insights.main[0].app_id
      instrumentation_key = azurerm_application_insights.main[0].instrumentation_key
      connection_string   = azurerm_application_insights.main[0].connection_string
    }
  } : null
}

# Connection Information
output "connection_endpoints" {
  description = "Connection endpoints for testing and access"
  value = {
    traffic_manager_fqdn = azurerm_traffic_manager_profile.main.fqdn
    traffic_manager_url  = "http://${azurerm_traffic_manager_profile.main.fqdn}"
    regional_endpoints = {
      primary = {
        ip_address = azurerm_public_ip.appgw_primary.ip_address
        url        = "http://${azurerm_public_ip.appgw_primary.ip_address}"
        location   = var.primary_region
      }
      secondary = {
        ip_address = azurerm_public_ip.appgw_secondary.ip_address
        url        = "http://${azurerm_public_ip.appgw_secondary.ip_address}"
        location   = var.secondary_region
      }
      tertiary = {
        ip_address = azurerm_public_ip.appgw_tertiary.ip_address
        url        = "http://${azurerm_public_ip.appgw_tertiary.ip_address}"
        location   = var.tertiary_region
      }
    }
  }
}

# Health Check Information
output "health_check_urls" {
  description = "URLs for health check monitoring"
  value = {
    traffic_manager_health = "http://${azurerm_traffic_manager_profile.main.fqdn}${var.traffic_manager_monitor_path}"
    regional_health_checks = {
      primary   = "http://${azurerm_public_ip.appgw_primary.ip_address}${var.traffic_manager_monitor_path}"
      secondary = "http://${azurerm_public_ip.appgw_secondary.ip_address}${var.traffic_manager_monitor_path}"
      tertiary  = "http://${azurerm_public_ip.appgw_tertiary.ip_address}${var.traffic_manager_monitor_path}"
    }
  }
}

# SSH Connection Information
output "ssh_connections" {
  description = "SSH connection information for VMSS instances"
  value = {
    primary = {
      command = "Connect to instances via Azure Portal or use Azure CLI: az vmss list-instance-connection-info"
      note    = "VMSS instances are in private subnets and require Azure Bastion or VPN for direct SSH access"
    }
    secondary = {
      command = "Connect to instances via Azure Portal or use Azure CLI: az vmss list-instance-connection-info"
      note    = "VMSS instances are in private subnets and require Azure Bastion or VPN for direct SSH access"
    }
    tertiary = {
      command = "Connect to instances via Azure Portal or use Azure CLI: az vmss list-instance-connection-info"
      note    = "VMSS instances are in private subnets and require Azure Bastion or VPN for direct SSH access"
    }
  }
}

# Cost Information
output "cost_information" {
  description = "Estimated cost information for deployed resources"
  value = {
    note = "Costs vary by region and usage patterns. Review Azure pricing calculator for detailed estimates."
    major_cost_components = [
      "Traffic Manager profile and DNS queries",
      "Application Gateway (3 instances with WAF_v2 SKU)",
      "Virtual Machine Scale Sets (6 instances total across regions)",
      "Public IP addresses (3 standard static IPs)",
      "Data transfer between regions and to internet",
      "Log Analytics workspace (if monitoring enabled)",
      "Application Insights (if monitoring enabled)"
    ]
    cost_optimization_tips = [
      "Use Azure Reserved Instances for predictable VMSS workloads",
      "Implement auto-scaling to optimize VMSS instance count",
      "Monitor data transfer costs between regions",
      "Use Azure Cost Management for ongoing cost monitoring",
      "Consider Traffic Manager alternatives for cost-sensitive scenarios"
    ]
  }
}

# Security Information
output "security_information" {
  description = "Security configuration and recommendations"
  value = {
    waf_protection = {
      enabled = var.appgw_sku == "WAF_v2"
      mode    = var.waf_mode
      rule_set = {
        type    = var.waf_rule_set_type
        version = var.waf_rule_set_version
      }
    }
    network_security = {
      private_subnets = "VMSS instances deployed in private subnets"
      public_access   = "Only Application Gateway has public IP addresses"
      zone_redundancy = "Resources deployed across availability zones"
    }
    recommendations = [
      "Implement Azure Key Vault for certificate management",
      "Enable Azure Security Center for additional security monitoring",
      "Configure Network Security Groups for additional network isolation",
      "Implement Azure Bastion for secure administrative access",
      "Enable Azure DDoS Protection for enhanced protection",
      "Configure Azure Firewall for additional network security"
    ]
  }
}

# Management Information
output "management_information" {
  description = "Management and operational information"
  value = {
    resource_groups = {
      primary   = azurerm_resource_group.primary.name
      secondary = azurerm_resource_group.secondary.name
      tertiary  = azurerm_resource_group.tertiary.name
    }
    tags_applied = var.tags
    monitoring_enabled = var.enable_monitoring
    management_recommendations = [
      "Use Azure Resource Manager templates for consistent deployments",
      "Implement Azure Policy for governance and compliance",
      "Configure Azure Backup for disaster recovery",
      "Set up Azure Monitor alerts for proactive monitoring",
      "Use Azure Automation for routine management tasks"
    ]
  }
}