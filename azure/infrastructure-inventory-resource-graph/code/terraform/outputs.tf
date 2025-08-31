# Outputs for Azure Infrastructure Inventory with Resource Graph
# This file defines output values for the deployed infrastructure

# Resource Group Information
output "primary_resource_group" {
  description = "Details of the primary resource group created for inventory demonstration"
  value = {
    id       = azurerm_resource_group.main.id
    name     = azurerm_resource_group.main.name
    location = azurerm_resource_group.main.location
    tags     = azurerm_resource_group.main.tags
  }
}

output "secondary_resource_group" {
  description = "Details of the secondary resource group (if created)"
  value = var.create_sample_resources ? {
    id       = azurerm_resource_group.secondary[0].id
    name     = azurerm_resource_group.secondary[0].name
    location = azurerm_resource_group.secondary[0].location
    tags     = azurerm_resource_group.secondary[0].tags
  } : null
}

# Storage Account for Inventory Reports
output "inventory_storage_account" {
  description = "Storage account details for inventory report exports"
  value = {
    id                   = azurerm_storage_account.inventory_storage.id
    name                 = azurerm_storage_account.inventory_storage.name
    primary_blob_endpoint = azurerm_storage_account.inventory_storage.primary_blob_endpoint
    container_name       = azurerm_storage_container.inventory_reports.name
  }
  sensitive = false
}

# Subscription and Tenant Information
output "azure_environment_info" {
  description = "Azure environment information for Resource Graph queries"
  value = {
    subscription_id     = data.azurerm_subscription.current.subscription_id
    subscription_name   = data.azurerm_subscription.current.display_name
    tenant_id          = data.azurerm_client_config.current.tenant_id
    current_location   = var.location
  }
}

# Sample Virtual Machine Details (if created)
output "sample_vm_details" {
  description = "Details of the sample virtual machine created for inventory demonstration"
  value = var.create_sample_resources ? {
    vm_id           = azurerm_linux_virtual_machine.sample_vm[0].id
    vm_name         = azurerm_linux_virtual_machine.sample_vm[0].name
    public_ip       = azurerm_public_ip.sample_vm_pip[0].ip_address
    private_ip      = azurerm_network_interface.sample_vm_nic[0].private_ip_address
    resource_group  = azurerm_linux_virtual_machine.sample_vm[0].resource_group_name
    size           = azurerm_linux_virtual_machine.sample_vm[0].size
  } : null
}

# Networking Resources
output "networking_resources" {
  description = "Details of networking resources created for inventory demonstration"
  value = var.create_sample_resources ? {
    vnet_id             = azurerm_virtual_network.sample_vnet[0].id
    vnet_name           = azurerm_virtual_network.sample_vnet[0].name
    subnet_id           = azurerm_subnet.sample_subnet[0].id
    subnet_name         = azurerm_subnet.sample_subnet[0].name
    nsg_id              = azurerm_network_security_group.sample_nsg[0].id
    nsg_name            = azurerm_network_security_group.sample_nsg[0].name
    public_ip_id        = azurerm_public_ip.sample_vm_pip[0].id
    public_ip_address   = azurerm_public_ip.sample_vm_pip[0].ip_address
  } : null
}

# Database Resources
output "database_resources" {
  description = "Details of database resources created for inventory demonstration"
  value = var.create_sample_resources ? {
    sql_server_id       = azurerm_mssql_server.sample_sql_server[0].id
    sql_server_name     = azurerm_mssql_server.sample_sql_server[0].name
    sql_server_fqdn     = azurerm_mssql_server.sample_sql_server[0].fully_qualified_domain_name
    database_id         = azurerm_mssql_database.sample_database[0].id
    database_name       = azurerm_mssql_database.sample_database[0].name
  } : null
}

# Monitoring Resources
output "monitoring_resources" {
  description = "Details of monitoring resources created for governance and compliance"
  value = var.enable_monitoring ? {
    log_analytics_workspace_id   = azurerm_log_analytics_workspace.inventory_workspace[0].id
    log_analytics_workspace_name = azurerm_log_analytics_workspace.inventory_workspace[0].name
    application_insights_id      = azurerm_application_insights.sample_appinsights[0].id
    application_insights_name    = azurerm_application_insights.sample_appinsights[0].name
    instrumentation_key         = azurerm_application_insights.sample_appinsights[0].instrumentation_key
  } : null
  sensitive = true
}

# Automation Resources
output "automation_resources" {
  description = "Details of automation resources for scheduled inventory queries"
  value = var.inventory_schedule.enabled ? {
    automation_account_id   = azurerm_automation_account.inventory_automation[0].id
    automation_account_name = azurerm_automation_account.inventory_automation[0].name
    logic_app_id           = azurerm_logic_app_workflow.inventory_workflow[0].id
    logic_app_name         = azurerm_logic_app_workflow.inventory_workflow[0].name
  } : null
}

# Resource Graph Sample Queries
output "sample_resource_graph_queries" {
  description = "Sample KQL queries for Azure Resource Graph inventory and compliance reporting"
  value = var.enable_resource_graph_queries ? {
    basic_inventory_query = "az graph query -q \"${local.sample_queries.basic_inventory}\" --output table"
    resource_count_query  = "az graph query -q \"${local.sample_queries.resource_counts}\" --output table"
    location_analysis_query = "az graph query -q \"${local.sample_queries.location_analysis}\" --output table"
    tagging_compliance_query = "az graph query -q \"${local.sample_queries.tagging_compliance}\" --output table"
    untagged_resources_query = "az graph query -q \"${local.sample_queries.untagged_resources}\" --output table"
    security_analysis_query = "az graph query -q \"${local.sample_queries.security_analysis}\" --output table"
    
    # Export query for comprehensive reporting
    export_inventory_query = "az graph query -q \"Resources | project ResourceName=name, ResourceType=type, Location=location, ResourceGroup=resourceGroup, SubscriptionId=subscriptionId, Tags=tags, ResourceId=id, Kind=kind | order by ResourceType asc, ResourceName asc\" --output json > infrastructure-inventory-$(date +%Y%m%d).json"
    
    # Subscription-specific query
    current_subscription_query = "az graph query -q \"Resources | where subscriptionId == '${data.azurerm_subscription.current.subscription_id}' | summarize TotalResources=count(), UniqueTypes=dcount(type), UniqueLocations=dcount(location), TaggedResources=countif(array_length(todynamic(tags)) > 0)\" --output table"
  } : null
}

# Resource Inventory Summary
output "deployed_resource_summary" {
  description = "Summary of all resources deployed for inventory demonstration"
  value = {
    total_resource_groups     = var.create_sample_resources ? 2 : 1
    sample_resources_created  = var.create_sample_resources
    monitoring_enabled       = var.enable_monitoring
    automation_enabled      = var.inventory_schedule.enabled
    primary_location        = var.location
    environment            = var.environment
    project_name          = var.project_name
    
    # Resource type counts for this deployment
    resource_types_deployed = var.create_sample_resources ? [
      "Microsoft.Resources/resourceGroups",
      "Microsoft.Storage/storageAccounts",
      "Microsoft.Network/virtualNetworks",
      "Microsoft.Network/networkSecurityGroups",
      "Microsoft.Network/publicIPAddresses",
      "Microsoft.Network/networkInterfaces",
      "Microsoft.Compute/virtualMachines",
      "Microsoft.KeyVault/vaults",
      "Microsoft.Sql/servers",
      "Microsoft.Sql/servers/databases"
    ] : [
      "Microsoft.Resources/resourceGroups",  
      "Microsoft.Storage/storageAccounts"
    ]
  }
}

# CLI Commands for Resource Graph Testing
output "resource_graph_cli_commands" {
  description = "Ready-to-use Azure CLI commands for testing Resource Graph queries"
  value = {
    install_extension = "az extension add --name resource-graph"
    verify_extension  = "az extension list --query \"[?name=='resource-graph']\" --output table"
    test_connectivity = "az graph query -q \"Resources | limit 5\" --output table"
    
    # Inventory commands targeting deployed resources
    count_deployed_resources = "az graph query -q \"Resources | where resourceGroup startswith '${local.resource_prefix}' | count\" --output table"
    list_deployed_resources  = "az graph query -q \"Resources | where resourceGroup startswith '${local.resource_prefix}' | project name, type, location, resourceGroup\" --output table"
    analyze_deployed_tags    = "az graph query -q \"Resources | where resourceGroup startswith '${local.resource_prefix}' | extend TagCount = array_length(todynamic(tags)) | project name, type, TagCount, tags\" --output table"
    
    # Governance queries for deployed infrastructure
    check_governance = "az graph query -q \"Resources | where resourceGroup startswith '${local.resource_prefix}' | extend HasEnvironmentTag = case(tags has 'Environment', 'Yes', 'No'), HasOwnerTag = case(tags has 'Owner', 'Yes', 'No') | project name, type, HasEnvironmentTag, HasOwnerTag\" --output table"
  }
}

# Storage Account Access Information
output "storage_access_info" {
  description = "Information for accessing the storage account for report exports"
  value = {
    storage_account_name = azurerm_storage_account.inventory_storage.name
    container_name      = azurerm_storage_container.inventory_reports.name
    resource_group      = azurerm_resource_group.main.name
    
    # CLI command to list reports
    list_reports_command = "az storage blob list --account-name ${azurerm_storage_account.inventory_storage.name} --container-name ${azurerm_storage_container.inventory_reports.name} --output table"
  }
  sensitive = false
}

# Governance Configuration Summary
output "governance_configuration" {
  description = "Summary of governance and compliance configuration"
  value = {
    governance_policies    = var.governance_policies
    inventory_schedule    = var.inventory_schedule
    retention_days       = var.retention_days
    monitoring_enabled   = var.enable_monitoring
    common_tags_applied  = local.common_tags
    
    # Compliance checks for deployed resources
    compliance_status = {
      tagging_enforced     = var.governance_policies.require_tags
      encryption_required  = var.governance_policies.require_encryption
      location_restricted  = length(var.governance_policies.allowed_locations) > 0
      audit_enabled       = var.governance_policies.audit_public_access
    }
  }
}