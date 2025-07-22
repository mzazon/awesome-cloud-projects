# Control plane outputs
output "control_plane_resource_group_name" {
  description = "Name of the control plane resource group"
  value       = azurerm_resource_group.control_plane.name
}

output "control_plane_resource_group_id" {
  description = "ID of the control plane resource group"
  value       = azurerm_resource_group.control_plane.id
}

output "key_vault_name" {
  description = "Name of the Key Vault for secret management"
  value       = azurerm_key_vault.saas_platform.name
}

output "key_vault_id" {
  description = "ID of the Key Vault for secret management"
  value       = azurerm_key_vault.saas_platform.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault for secret management"
  value       = azurerm_key_vault.saas_platform.vault_uri
}

# Workload identity outputs
output "workload_identity_application_id" {
  description = "Application ID of the workload identity"
  value       = azuread_application.workload_identity.application_id
}

output "workload_identity_client_id" {
  description = "Client ID of the workload identity"
  value       = azuread_application.workload_identity.application_id
}

output "workload_identity_object_id" {
  description = "Object ID of the workload identity service principal"
  value       = azuread_service_principal.workload_identity.object_id
}

output "workload_identity_principal_id" {
  description = "Principal ID of the workload identity service principal"
  value       = azuread_service_principal.workload_identity.object_id
}

# Managed identity outputs
output "deployment_identity_id" {
  description = "ID of the deployment managed identity"
  value       = azurerm_user_assigned_identity.deployment_identity.id
}

output "deployment_identity_principal_id" {
  description = "Principal ID of the deployment managed identity"
  value       = azurerm_user_assigned_identity.deployment_identity.principal_id
}

output "deployment_identity_client_id" {
  description = "Client ID of the deployment managed identity"
  value       = azurerm_user_assigned_identity.deployment_identity.client_id
}

# Monitoring outputs
output "log_analytics_workspace_name" {
  description = "Name of the platform Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.platform_workspace.name
}

output "log_analytics_workspace_id" {
  description = "ID of the platform Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.platform_workspace.id
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID of the platform Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.platform_workspace.workspace_id
}

output "application_insights_name" {
  description = "Name of the Application Insights component"
  value       = azurerm_application_insights.platform_insights.name
}

output "application_insights_id" {
  description = "ID of the Application Insights component"
  value       = azurerm_application_insights.platform_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.platform_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.platform_insights.connection_string
  sensitive   = true
}

# Custom role definition outputs
output "tenant_admin_role_id" {
  description = "ID of the custom tenant administrator role"
  value       = azurerm_role_definition.tenant_admin.id
}

output "tenant_user_role_id" {
  description = "ID of the custom tenant user role"
  value       = azurerm_role_definition.tenant_user.id
}

# Policy definition outputs
output "tenant_tagging_policy_id" {
  description = "ID of the tenant tagging policy definition"
  value       = azurerm_policy_definition.tenant_tagging.id
}

output "network_security_groups_policy_id" {
  description = "ID of the network security groups policy definition"
  value       = azurerm_policy_definition.network_security_groups.id
}

# Tenant resource outputs
output "tenant_resource_groups" {
  description = "Information about tenant resource groups"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      name     = azurerm_resource_group.tenant[tenant_id].name
      id       = azurerm_resource_group.tenant[tenant_id].id
      location = azurerm_resource_group.tenant[tenant_id].location
    }
  }
}

output "tenant_storage_accounts" {
  description = "Information about tenant storage accounts"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      name                = azurerm_storage_account.tenant[tenant_id].name
      id                  = azurerm_storage_account.tenant[tenant_id].id
      primary_endpoint    = azurerm_storage_account.tenant[tenant_id].primary_blob_endpoint
      primary_access_key  = azurerm_storage_account.tenant[tenant_id].primary_access_key
    }
  }
  sensitive = true
}

output "tenant_virtual_networks" {
  description = "Information about tenant virtual networks"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      name          = azurerm_virtual_network.tenant[tenant_id].name
      id            = azurerm_virtual_network.tenant[tenant_id].id
      address_space = azurerm_virtual_network.tenant[tenant_id].address_space
    }
  }
}

output "tenant_subnets" {
  description = "Information about tenant subnets"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      name             = azurerm_subnet.tenant[tenant_id].name
      id               = azurerm_subnet.tenant[tenant_id].id
      address_prefixes = azurerm_subnet.tenant[tenant_id].address_prefixes
    }
  }
}

output "tenant_network_security_groups" {
  description = "Information about tenant network security groups"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      name = azurerm_network_security_group.tenant[tenant_id].name
      id   = azurerm_network_security_group.tenant[tenant_id].id
    }
  }
}

output "tenant_log_analytics_workspaces" {
  description = "Information about tenant Log Analytics workspaces"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      name         = azurerm_log_analytics_workspace.tenant[tenant_id].name
      id           = azurerm_log_analytics_workspace.tenant[tenant_id].id
      workspace_id = azurerm_log_analytics_workspace.tenant[tenant_id].workspace_id
    }
  }
}

# Tenant configuration secrets
output "tenant_config_secret_names" {
  description = "Names of tenant configuration secrets in Key Vault"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => azurerm_key_vault_secret.tenant_config[tenant_id].name
  }
}

# Policy assignment outputs
output "tenant_policy_assignments" {
  description = "Information about tenant policy assignments"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      tagging_policy_assignment_id = azurerm_resource_group_policy_assignment.tenant_tagging[tenant_id].id
      network_security_policy_assignment_id = azurerm_resource_group_policy_assignment.tenant_network_security[tenant_id].id
    }
  }
}

# Summary information
output "platform_summary" {
  description = "Summary information about the multi-tenant SaaS platform"
  value = {
    control_plane_resource_group = azurerm_resource_group.control_plane.name
    key_vault_name              = azurerm_key_vault.saas_platform.name
    workload_identity_app_id    = azuread_application.workload_identity.application_id
    tenant_count                = length(var.sample_tenants)
    tenant_list                 = keys(var.sample_tenants)
    environment                 = var.environment
    location                    = var.location
  }
}

# Tenant onboarding information
output "tenant_onboarding_info" {
  description = "Information needed for tenant onboarding and management"
  value = {
    for tenant_id, tenant in var.sample_tenants : tenant_id => {
      tenant_name         = tenant.name
      resource_group_name = azurerm_resource_group.tenant[tenant_id].name
      storage_account_name = azurerm_storage_account.tenant[tenant_id].name
      virtual_network_name = azurerm_virtual_network.tenant[tenant_id].name
      log_workspace_name   = azurerm_log_analytics_workspace.tenant[tenant_id].name
      admin_email         = tenant.admin_email
      environment         = tenant.environment
    }
  }
}

# Resource counts for monitoring and governance
output "resource_counts" {
  description = "Count of resources created by category"
  value = {
    resource_groups            = length(azurerm_resource_group.tenant) + 1 # +1 for control plane
    storage_accounts          = length(azurerm_storage_account.tenant)
    virtual_networks          = length(azurerm_virtual_network.tenant)
    network_security_groups   = length(azurerm_network_security_group.tenant)
    log_analytics_workspaces  = length(azurerm_log_analytics_workspace.tenant) + 1 # +1 for platform
    policy_definitions        = 2 # tagging and network security
    policy_assignments        = length(var.sample_tenants) * 2 # 2 policies per tenant
    custom_roles             = 2 # tenant admin and user roles
    key_vault_secrets        = length(azurerm_key_vault_secret.tenant_config)
  }
}