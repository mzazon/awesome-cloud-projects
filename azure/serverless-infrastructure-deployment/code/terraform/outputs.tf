# Output Values for Azure Container Apps Jobs Deployment Automation
# These outputs provide important resource information for verification and integration

# Resource Group Information
output "resource_group_name" {
  description = "Name of the resource group containing all deployment automation resources"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "Full resource ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = azurerm_resource_group.main.location
}

# Container Apps Environment Information
output "container_apps_environment_name" {
  description = "Name of the Container Apps environment hosting the deployment jobs"
  value       = azurerm_container_app_environment.deployment_env.name
}

output "container_apps_environment_id" {
  description = "Full resource ID of the Container Apps environment"
  value       = azurerm_container_app_environment.deployment_env.id
}

output "container_apps_environment_fqdn" {
  description = "Fully qualified domain name of the Container Apps environment"
  value       = azurerm_container_app_environment.deployment_env.default_domain
}

# Container Apps Jobs Information
output "manual_deployment_job_name" {
  description = "Name of the manual deployment job"
  value       = azurerm_container_app_job.deployment_job.name
}

output "manual_deployment_job_id" {
  description = "Full resource ID of the manual deployment job"
  value       = azurerm_container_app_job.deployment_job.id
}

output "scheduled_deployment_job_name" {
  description = "Name of the scheduled deployment job"
  value       = azurerm_container_app_job.scheduled_deployment_job.name
}

output "scheduled_deployment_job_id" {
  description = "Full resource ID of the scheduled deployment job"
  value       = azurerm_container_app_job.scheduled_deployment_job.id
}

output "schedule_cron_expression" {
  description = "Cron expression for the scheduled deployment job"
  value       = var.schedule_cron_expression
}

# Managed Identity Information
output "managed_identity_name" {
  description = "Name of the user-assigned managed identity for deployment jobs"
  value       = azurerm_user_assigned_identity.deployment_job.name
}

output "managed_identity_id" {
  description = "Full resource ID of the managed identity"
  value       = azurerm_user_assigned_identity.deployment_job.id
}

output "managed_identity_principal_id" {
  description = "Principal (object) ID of the managed identity for RBAC assignments"
  value       = azurerm_user_assigned_identity.deployment_job.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID (application ID) of the managed identity"
  value       = azurerm_user_assigned_identity.deployment_job.client_id
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the storage account for deployment artifacts"
  value       = azurerm_storage_account.deployment_artifacts.name
}

output "storage_account_id" {
  description = "Full resource ID of the storage account"
  value       = azurerm_storage_account.deployment_artifacts.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.deployment_artifacts.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.deployment_artifacts.primary_access_key
  sensitive   = true
}

# Storage Container Information
output "arm_templates_container_name" {
  description = "Name of the storage container for ARM templates"
  value       = azurerm_storage_container.arm_templates.name
}

output "deployment_logs_container_name" {
  description = "Name of the storage container for deployment logs"
  value       = azurerm_storage_container.deployment_logs.name
}

output "deployment_scripts_container_name" {
  description = "Name of the storage container for deployment scripts"
  value       = azurerm_storage_container.deployment_scripts.name
}

# Key Vault Information
output "key_vault_name" {
  description = "Name of the Key Vault for deployment secrets"
  value       = azurerm_key_vault.deployment_secrets.name
}

output "key_vault_id" {
  description = "Full resource ID of the Key Vault"
  value       = azurerm_key_vault.deployment_secrets.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault for accessing secrets"
  value       = azurerm_key_vault.deployment_secrets.vault_uri
}

# Log Analytics Workspace Information (if enabled)
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace (if enabled)"
  value       = var.enable_container_apps_logs ? azurerm_log_analytics_workspace.container_apps[0].name : null
}

output "log_analytics_workspace_id" {
  description = "Full resource ID of the Log Analytics workspace (if enabled)"
  value       = var.enable_container_apps_logs ? azurerm_log_analytics_workspace.container_apps[0].id : null
}

output "log_analytics_workspace_customer_id" {
  description = "Customer ID (workspace ID) of the Log Analytics workspace (if enabled)"
  value       = var.enable_container_apps_logs ? azurerm_log_analytics_workspace.container_apps[0].workspace_id : null
}

# Sample Resources Information
output "sample_arm_template_url" {
  description = "URL of the sample ARM template for testing deployments"
  value       = "${azurerm_storage_account.deployment_artifacts.primary_blob_endpoint}${azurerm_storage_container.arm_templates.name}/${azurerm_storage_blob.sample_arm_template.name}"
}

output "deployment_script_url" {
  description = "URL of the deployment script for Container Apps Jobs"
  value       = "${azurerm_storage_account.deployment_artifacts.primary_blob_endpoint}${azurerm_storage_container.deployment_scripts.name}/${azurerm_storage_blob.deployment_script.name}"
}

# RBAC Information
output "rbac_assignments" {
  description = "Summary of RBAC role assignments for the managed identity"
  value = {
    contributor_scope       = azurerm_role_assignment.deployment_contributor.scope
    storage_contributor_scope = azurerm_role_assignment.storage_contributor.scope
    keyvault_secrets_scope    = azurerm_role_assignment.keyvault_secrets_user.scope
  }
}

# Deployment Commands and Examples
output "deployment_commands" {
  description = "Commands to execute and manage deployment jobs"
  value = {
    # Manual job execution command
    start_manual_job = "az containerapp job start --name ${azurerm_container_app_job.deployment_job.name} --resource-group ${azurerm_resource_group.main.name}"
    
    # Job status monitoring commands
    list_job_executions = "az containerapp job execution list --name ${azurerm_container_app_job.deployment_job.name} --resource-group ${azurerm_resource_group.main.name}"
    
    # Storage access commands
    list_arm_templates = "az storage blob list --container-name ${azurerm_storage_container.arm_templates.name} --account-name ${azurerm_storage_account.deployment_artifacts.name} --auth-mode login"
    list_deployment_logs = "az storage blob list --container-name ${azurerm_storage_container.deployment_logs.name} --account-name ${azurerm_storage_account.deployment_artifacts.name} --auth-mode login"
    
    # Template upload command example
    upload_template_example = "az storage blob upload --file your-template.json --container-name ${azurerm_storage_container.arm_templates.name} --name your-template.json --account-name ${azurerm_storage_account.deployment_artifacts.name} --auth-mode login"
  }
}

# Configuration Summary
output "deployment_configuration" {
  description = "Summary of deployment automation configuration"
  value = {
    environment                = var.environment
    project_name              = var.project_name
    job_cpu_allocation        = var.job_cpu_allocation
    job_memory_allocation     = var.job_memory_allocation
    job_replica_timeout       = var.job_replica_timeout
    job_replica_retry_limit   = var.job_replica_retry_limit
    scheduled_job_cron        = var.schedule_cron_expression
    storage_account_tier      = var.storage_account_tier
    storage_replication_type  = var.storage_account_replication_type
    key_vault_sku            = var.key_vault_sku_name
    rbac_enabled             = var.enable_key_vault_rbac
    logs_enabled             = var.enable_container_apps_logs
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled in the deployment automation"
  value = {
    managed_identity_authentication = true
    key_vault_rbac_authorization    = var.enable_key_vault_rbac
    storage_https_only             = true
    storage_min_tls_version        = "TLS1_2"
    storage_public_access_disabled = !var.enable_storage_public_access
    key_vault_soft_delete_enabled  = true
    storage_blob_versioning        = true
    storage_change_feed           = true
  }
}

# Resource Tags Applied
output "applied_tags" {
  description = "Tags applied to all resources for governance and cost tracking"
  value       = var.tags
}

# Unique Suffix for Global Resources
output "unique_suffix" {
  description = "Random suffix used for globally unique resource names"
  value       = random_string.suffix.result
}

# Next Steps and Recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload your ARM templates to the arm-templates container",
    "2. Test the deployment workflow by starting the manual job",
    "3. Monitor job execution logs in the deployment-logs container",
    "4. Configure Key Vault secrets for any required deployment credentials",
    "5. Customize the deployment script for your specific requirements",
    "6. Set up monitoring and alerting for production deployments",
    "7. Consider enabling private endpoints for enhanced security in production"
  ]
}

# Cost Optimization Recommendations
output "cost_optimization_tips" {
  description = "Tips for optimizing costs in the deployment automation infrastructure"
  value = [
    "1. Container Apps Jobs use consumption-based pricing - you only pay for execution time",
    "2. Use 'Cool' access tier for infrequently accessed ARM templates",
    "3. Enable lifecycle management policies on storage containers for log retention",
    "4. Consider using Azure DevOps or GitHub Actions for more complex CI/CD scenarios",
    "5. Monitor resource usage with Azure Cost Management + Billing",
    "6. Use resource tagging for detailed cost tracking and allocation"
  ]
}