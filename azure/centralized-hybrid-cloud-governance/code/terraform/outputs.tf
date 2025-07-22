# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.arc_governance.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.arc_governance.id
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.arc_governance.location
}

# Log Analytics Workspace Information
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.arc_workspace.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.arc_workspace.id
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.arc_workspace.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (Workspace ID) of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.arc_workspace.workspace_id
}

output "log_analytics_workspace_primary_shared_key" {
  description = "Primary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.arc_workspace.primary_shared_key
  sensitive   = true
}

output "log_analytics_workspace_secondary_shared_key" {
  description = "Secondary shared key of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.arc_workspace.secondary_shared_key
  sensitive   = true
}

# Service Principal Information
output "service_principal_application_id" {
  description = "Application ID of the service principal for Arc onboarding"
  value       = azuread_application.arc_onboarding.application_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal for Arc onboarding"
  value       = azuread_service_principal.arc_onboarding.object_id
}

output "service_principal_client_secret" {
  description = "Client secret of the service principal for Arc onboarding"
  value       = azuread_service_principal_password.arc_onboarding.value
  sensitive   = true
}

output "service_principal_tenant_id" {
  description = "Tenant ID for the service principal"
  value       = data.azurerm_client_config.current.tenant_id
}

# Azure Subscription Information
output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Data Collection Rule Information
output "data_collection_rule_id" {
  description = "ID of the data collection rule for Arc-enabled servers"
  value       = var.enable_performance_monitoring ? azurerm_monitor_data_collection_rule.arc_servers[0].id : null
}

output "data_collection_rule_name" {
  description = "Name of the data collection rule for Arc-enabled servers"
  value       = var.enable_performance_monitoring ? azurerm_monitor_data_collection_rule.arc_servers[0].name : null
}

# Policy Assignment Information
output "arc_servers_baseline_policy_assignment_id" {
  description = "ID of the Arc servers baseline policy assignment"
  value       = var.enable_arc_servers_baseline ? azurerm_resource_policy_assignment.arc_servers_baseline[0].id : null
}

output "arc_servers_baseline_policy_assignment_name" {
  description = "Name of the Arc servers baseline policy assignment"
  value       = var.enable_arc_servers_baseline ? azurerm_resource_policy_assignment.arc_servers_baseline[0].name : null
}

output "k8s_container_security_policy_assignment_id" {
  description = "ID of the Kubernetes container security policy assignment"
  value       = var.enable_k8s_container_security ? azurerm_resource_policy_assignment.k8s_container_security[0].id : null
}

output "k8s_container_security_policy_assignment_name" {
  description = "Name of the Kubernetes container security policy assignment"
  value       = var.enable_k8s_container_security ? azurerm_resource_policy_assignment.k8s_container_security[0].name : null
}

# Resource Graph Shared Queries
output "arc_compliance_query_id" {
  description = "ID of the Arc compliance status Resource Graph shared query"
  value       = var.create_shared_queries ? azurerm_resource_graph_shared_query.arc_compliance_status[0].id : null
}

output "arc_inventory_query_id" {
  description = "ID of the Arc resource inventory Resource Graph shared query"
  value       = var.create_shared_queries ? azurerm_resource_graph_shared_query.arc_resource_inventory[0].id : null
}

# Policy Remediation Information
output "arc_servers_remediation_id" {
  description = "ID of the Arc servers baseline remediation task"
  value       = var.enable_arc_servers_baseline ? azurerm_resource_policy_remediation.arc_servers_baseline[0].id : null
}

# Custom Role Definition
output "custom_role_definition_id" {
  description = "ID of the custom Arc Manager role definition"
  value       = var.create_custom_role_definitions ? azurerm_role_definition.arc_manager[0].id : null
}

# Action Group Information
output "action_group_id" {
  description = "ID of the action group for Arc alerts"
  value       = azurerm_monitor_action_group.arc_alerts.id
}

output "action_group_name" {
  description = "Name of the action group for Arc alerts"
  value       = azurerm_monitor_action_group.arc_alerts.name
}

# Alert Information
output "connectivity_alert_id" {
  description = "ID of the Arc connectivity alert"
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.arc_connectivity.id
}

# Connection Commands for Arc Resources
output "arc_server_connection_command" {
  description = "Command to connect servers to Azure Arc"
  value = <<-EOT
    # For Linux servers:
    wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh
    bash ~/install_linux_azcmagent.sh
    azcmagent connect \
        --service-principal-id '${azuread_application.arc_onboarding.application_id}' \
        --service-principal-secret '${azuread_service_principal_password.arc_onboarding.value}' \
        --tenant-id '${data.azurerm_client_config.current.tenant_id}' \
        --subscription-id '${data.azurerm_subscription.current.subscription_id}' \
        --resource-group '${azurerm_resource_group.arc_governance.name}' \
        --location '${azurerm_resource_group.arc_governance.location}'
    
    # For Windows servers:
    # Download and run: https://aka.ms/AzureConnectedMachineAgent
    # Then run the same azcmagent connect command above
  EOT
  sensitive = true
}

output "arc_k8s_connection_command" {
  description = "Command to connect Kubernetes clusters to Azure Arc"
  value = <<-EOT
    # Connect Kubernetes cluster to Azure Arc
    az connectedk8s connect \
        --name '${local.arc_k8s_cluster_name}' \
        --resource-group '${azurerm_resource_group.arc_governance.name}' \
        --location '${azurerm_resource_group.arc_governance.location}' \
        --tags environment=${var.environment} type=kubernetes
    
    # Enable Azure Policy extension
    az k8s-extension create \
        --name azurepolicy \
        --cluster-name '${local.arc_k8s_cluster_name}' \
        --resource-group '${azurerm_resource_group.arc_governance.name}' \
        --cluster-type connectedClusters \
        --extension-type Microsoft.PolicyInsights
    
    # Enable Azure Monitor extension
    az k8s-extension create \
        --name azuremonitor-containers \
        --cluster-name '${local.arc_k8s_cluster_name}' \
        --resource-group '${azurerm_resource_group.arc_governance.name}' \
        --cluster-type connectedClusters \
        --extension-type Microsoft.AzureMonitor.Containers \
        --configuration-settings logAnalyticsWorkspaceResourceID='${azurerm_log_analytics_workspace.arc_workspace.id}'
  EOT
}

# Resource Graph Queries
output "resource_graph_queries" {
  description = "Useful Resource Graph queries for Arc governance"
  value = {
    arc_resources = "Resources | where type =~ 'microsoft.hybridcompute/machines' or type =~ 'microsoft.kubernetes/connectedclusters' | project name, type, location, resourceGroup, subscriptionId | order by type asc"
    
    compliance_status = "PolicyResources | where type =~ 'microsoft.policyinsights/policystates' | where properties.resourceType contains 'microsoft.hybridcompute' or properties.resourceType contains 'microsoft.kubernetes' | summarize count() by tostring(properties.complianceState)"
    
    compliance_percentage = "PolicyResources | where type =~ 'microsoft.policyinsights/policystates' | where properties.resourceType contains 'arc' | summarize Total = count(), Compliant = countif(properties.complianceState =~ 'Compliant') | project CompliancePercentage = (todouble(Compliant) / todouble(Total)) * 100"
    
    server_heartbeats = "Heartbeat | where ResourceProvider == 'Microsoft.HybridCompute' | summarize LastHeartbeat = max(TimeGenerated) by Computer | order by LastHeartbeat desc | take 10"
  }
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    resource_group     = azurerm_resource_group.arc_governance.name
    location          = azurerm_resource_group.arc_governance.location
    workspace_name    = azurerm_log_analytics_workspace.arc_workspace.name
    service_principal = azuread_application.arc_onboarding.display_name
    policies_enabled  = {
      arc_servers_baseline      = var.enable_arc_servers_baseline
      k8s_container_security   = var.enable_k8s_container_security
    }
    monitoring_enabled = {
      performance_counters     = var.enable_performance_monitoring
      azure_monitor_containers = var.enable_azure_monitor_containers
      azure_policy_addon      = var.enable_azure_policy_addon
    }
    shared_queries_created = var.create_shared_queries
  }
}