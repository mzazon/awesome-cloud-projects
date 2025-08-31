# ==================================================================================
# OUTPUT DEFINITIONS FOR AZURE BASIC FILE STORAGE SOLUTION
# ==================================================================================
# These outputs provide essential information about the created resources
# for integration with other systems, verification, and user access.
# Outputs are organized by category for easy consumption by automation tools.
# ==================================================================================

# =============================================================================
# RESOURCE GROUP OUTPUTS
# =============================================================================

output "resource_group_name" {
  description = "The name of the created resource group containing all storage resources"
  value       = azurerm_resource_group.storage_rg.name
}

output "resource_group_id" {
  description = "The Azure resource ID of the created resource group"
  value       = azurerm_resource_group.storage_rg.id
}

output "resource_group_location" {
  description = "The Azure region where the resource group and all resources are deployed"
  value       = azurerm_resource_group.storage_rg.location
}

# =============================================================================
# STORAGE ACCOUNT OUTPUTS
# =============================================================================

output "storage_account_name" {
  description = "The name of the created Azure storage account (globally unique)"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "The Azure resource ID of the storage account for ARM template references"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_location" {
  description = "The primary Azure region where the storage account data is stored"
  value       = azurerm_storage_account.main.primary_location
}

output "storage_account_secondary_location" {
  description = "The secondary Azure region for geo-redundant storage (if applicable)"
  value       = azurerm_storage_account.main.secondary_location
}

output "storage_account_tier" {
  description = "The performance tier of the storage account (Standard or Premium)"
  value       = azurerm_storage_account.main.account_tier
}

output "storage_account_replication_type" {
  description = "The replication strategy configured for the storage account"
  value       = azurerm_storage_account.main.account_replication_type
}

output "storage_account_access_tier" {
  description = "The default access tier for blob storage (Hot or Cool)"
  value       = azurerm_storage_account.main.access_tier
}

# =============================================================================
# STORAGE ENDPOINTS OUTPUTS
# =============================================================================

output "blob_endpoint_primary" {
  description = "The primary blob service endpoint URL for programmatic access"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "blob_endpoint_secondary" {
  description = "The secondary blob service endpoint URL (for geo-redundant storage)"
  value       = azurerm_storage_account.main.secondary_blob_endpoint
}

output "blob_host_primary" {
  description = "The primary blob service hostname for direct API access"
  value       = azurerm_storage_account.main.primary_blob_host
}

output "dfs_endpoint_primary" {
  description = "The primary Data Lake Storage Gen2 endpoint URL (if hierarchical namespace is enabled)"
  value       = azurerm_storage_account.main.primary_dfs_endpoint
}

output "web_endpoint_primary" {
  description = "The primary static website endpoint URL (if static website is enabled)"
  value       = azurerm_storage_account.main.primary_web_endpoint
}

# =============================================================================
# CONTAINER OUTPUTS
# =============================================================================

output "blob_containers" {
  description = "Map of created blob containers with their properties and access information"
  value = {
    for name, container in azurerm_storage_container.containers :
    name => {
      name                  = container.name
      id                    = container.id
      container_access_type = container.container_access_type
      resource_manager_id   = container.resource_manager_id
      has_immutability_policy = container.has_immutability_policy
      has_legal_hold       = container.has_legal_hold
      metadata            = container.metadata
    }
  }
}

output "container_names" {
  description = "List of all created blob container names for iteration in scripts"
  value       = keys(azurerm_storage_container.containers)
}

output "container_urls" {
  description = "Map of container names to their direct access URLs for Azure CLI operations"
  value = {
    for name, container in azurerm_storage_container.containers :
    name => "${azurerm_storage_account.main.primary_blob_endpoint}${name}/"
  }
}

# =============================================================================
# RBAC AND SECURITY OUTPUTS
# =============================================================================

output "rbac_assignments" {
  description = "Information about configured RBAC role assignments for audit and compliance"
  value = {
    current_user_assignment = var.enable_rbac_for_current_user ? {
      role_definition_name = "Storage Blob Data Contributor"
      principal_id        = data.azurerm_client_config.current.object_id
      scope               = azurerm_storage_account.main.id
    } : null
    
    additional_assignments = {
      for key, assignment in var.additional_rbac_assignments :
      key => {
        role_definition_name = assignment.role_definition_name
        principal_id        = assignment.principal_id
        principal_type      = assignment.principal_type
        scope               = azurerm_storage_account.main.id
      }
    }
  }
}

output "security_configuration" {
  description = "Security settings and compliance information for the storage account"
  value = {
    min_tls_version              = azurerm_storage_account.main.min_tls_version
    https_traffic_only_enabled   = azurerm_storage_account.main.https_traffic_only_enabled
    allow_blob_public_access     = azurerm_storage_account.main.allow_nested_items_to_be_public
    shared_access_key_enabled    = azurerm_storage_account.main.shared_access_key_enabled
    public_network_access_enabled = azurerm_storage_account.main.public_network_access_enabled
    cross_tenant_replication_enabled = azurerm_storage_account.main.cross_tenant_replication_enabled
  }
}

# =============================================================================
# AZURE PORTAL ACCESS OUTPUTS
# =============================================================================

output "azure_portal_urls" {
  description = "Direct URLs to access storage resources in the Azure Portal for easy management"
  value = {
    storage_account_overview = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/overview"
    storage_browser         = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/storagebrowser"
    access_keys            = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/keys"
    networking             = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/networking"
    data_protection        = "https://portal.azure.com/#@/resource${azurerm_storage_account.main.id}/dataprotection"
    resource_group         = "https://portal.azure.com/#@/resource${azurerm_resource_group.storage_rg.id}/overview"
  }
}

# =============================================================================
# AZURE CLI COMMAND OUTPUTS
# =============================================================================

output "azure_cli_commands" {
  description = "Ready-to-use Azure CLI commands for common storage operations"
  value = {
    list_containers = "az storage container list --account-name ${azurerm_storage_account.main.name} --auth-mode login --output table"
    
    upload_blob = "az storage blob upload --account-name ${azurerm_storage_account.main.name} --container-name documents --name sample.txt --file ./sample.txt --auth-mode login"
    
    download_blob = "az storage blob download --account-name ${azurerm_storage_account.main.name} --container-name documents --name sample.txt --file ./downloaded-sample.txt --auth-mode login"
    
    list_blobs = "az storage blob list --account-name ${azurerm_storage_account.main.name} --container-name documents --auth-mode login --output table"
    
    account_info = "az storage account show --name ${azurerm_storage_account.main.name} --resource-group ${azurerm_resource_group.storage_rg.name} --output table"
  }
}

# =============================================================================
# COST AND CONFIGURATION OUTPUTS
# =============================================================================

output "cost_information" {
  description = "Cost-related information and optimization recommendations"
  value = {
    storage_tier              = azurerm_storage_account.main.account_tier
    replication_type         = azurerm_storage_account.main.account_replication_type
    access_tier             = azurerm_storage_account.main.access_tier
    estimated_monthly_cost   = "Varies based on usage - typically $0.02-0.05/month for standard usage within free tier"
    cost_optimization_tips  = [
      "Monitor storage usage with Azure Monitor metrics",
      "Consider lifecycle management policies for automated tier transitions",
      "Use appropriate access tiers (Hot/Cool/Archive) based on access patterns",
      "Review and optimize replication type based on durability requirements"
    ]
  }
}

output "configuration_summary" {
  description = "Summary of the deployed storage configuration for documentation and compliance"
  value = {
    resource_group_name      = azurerm_resource_group.storage_rg.name
    storage_account_name     = azurerm_storage_account.main.name
    location                = azurerm_resource_group.storage_rg.location
    account_kind            = azurerm_storage_account.main.account_kind
    performance_tier        = azurerm_storage_account.main.account_tier
    replication_strategy    = azurerm_storage_account.main.account_replication_type
    default_access_tier     = azurerm_storage_account.main.access_tier
    container_count        = length(azurerm_storage_container.containers)
    container_names        = keys(azurerm_storage_container.containers)
    rbac_enabled           = var.enable_rbac_for_current_user
    security_features      = {
      tls_enforcement      = azurerm_storage_account.main.min_tls_version
      https_only          = azurerm_storage_account.main.https_traffic_only_enabled
      public_access_disabled = !azurerm_storage_account.main.allow_nested_items_to_be_public
    }
    optional_features = {
      versioning_enabled   = var.enable_versioning
      soft_delete_enabled  = var.enable_soft_delete
      change_feed_enabled  = var.enable_change_feed
    }
  }
}

# =============================================================================
# INTEGRATION OUTPUTS
# =============================================================================

output "terraform_resource_references" {
  description = "Terraform resource references for use in other configurations or modules"
  value = {
    resource_group     = "azurerm_resource_group.storage_rg"
    storage_account    = "azurerm_storage_account.main"
    containers         = "azurerm_storage_container.containers"
    rbac_assignments   = "azurerm_role_assignment.current_user_blob_contributor"
  }
}

output "tags_applied" {
  description = "Tags applied to all resources for governance and cost tracking"
  value = merge(var.tags, {
    deployment_method = "terraform"
    recipe_version   = "1.0"
  })
}

# =============================================================================
# SENSITIVE OUTPUTS (Access Keys)
# =============================================================================
# Note: Access keys are marked as sensitive to prevent accidental exposure
# in logs or console output. Use with caution and prefer Azure AD authentication.

output "storage_account_primary_access_key" {
  description = "The primary access key for the storage account (use with caution - prefer Azure AD authentication)"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "The primary connection string for the storage account (sensitive - use Azure AD when possible)"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

output "primary_blob_connection_string" {
  description = "The primary blob service connection string (sensitive - use Azure AD when possible)"
  value       = azurerm_storage_account.main.primary_blob_connection_string
  sensitive   = true
}