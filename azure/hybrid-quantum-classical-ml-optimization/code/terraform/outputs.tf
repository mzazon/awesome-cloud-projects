# Outputs for Azure Quantum-Enhanced Machine Learning Infrastructure

# Resource Group Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Azure Quantum Workspace Outputs
output "quantum_workspace_name" {
  description = "Name of the Azure Quantum workspace"
  value       = azurerm_quantum_workspace.main.name
}

output "quantum_workspace_id" {
  description = "ID of the Azure Quantum workspace"
  value       = azurerm_quantum_workspace.main.id
}

output "quantum_workspace_endpoint" {
  description = "Endpoint URL for the Azure Quantum workspace"
  value       = "https://quantum.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Quantum/Workspaces/${azurerm_quantum_workspace.main.name}"
}

output "quantum_workspace_identity_principal_id" {
  description = "Principal ID of the Quantum workspace managed identity"
  value       = azurerm_quantum_workspace.main.identity[0].principal_id
}

# Azure Machine Learning Workspace Outputs
output "ml_workspace_name" {
  description = "Name of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  description = "ID of the Azure Machine Learning workspace"
  value       = azurerm_machine_learning_workspace.main.id
}

output "ml_workspace_discovery_url" {
  description = "Discovery URL for the Azure ML workspace"
  value       = azurerm_machine_learning_workspace.main.discovery_url
}

output "ml_workspace_identity_principal_id" {
  description = "Principal ID of the ML workspace managed identity"
  value       = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Machine Learning Compute Resources
output "ml_compute_instance_name" {
  description = "Name of the ML compute instance"
  value       = azurerm_machine_learning_compute_instance.quantum_ml_compute.name
}

output "ml_compute_cluster_name" {
  description = "Name of the ML compute cluster"
  value       = azurerm_machine_learning_compute_cluster.quantum_ml_cluster.name
}

output "ml_compute_cluster_id" {
  description = "ID of the ML compute cluster"
  value       = azurerm_machine_learning_compute_cluster.quantum_ml_cluster.id
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_dfs_endpoint" {
  description = "Primary Data Lake Storage Gen2 endpoint"
  value       = azurerm_storage_account.main.primary_dfs_endpoint
}

output "storage_containers" {
  description = "List of created storage containers"
  value = {
    quantum_ml_data = azurerm_storage_container.quantum_ml_data.name
    quantum_results = azurerm_storage_container.quantum_results.name
    ml_models       = azurerm_storage_container.ml_models.name
  }
}

# Azure Batch Outputs
output "batch_account_name" {
  description = "Name of the Azure Batch account"
  value       = azurerm_batch_account.main.name
}

output "batch_account_id" {
  description = "ID of the Azure Batch account"
  value       = azurerm_batch_account.main.id
}

output "batch_account_endpoint" {
  description = "Endpoint URL for the Azure Batch account"
  value       = azurerm_batch_account.main.account_endpoint
}

# Key Vault Outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Container Registry Outputs (conditional)
output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = var.enable_container_registry ? azurerm_container_registry.main[0].name : null
}

output "container_registry_id" {
  description = "ID of the Azure Container Registry"
  value       = var.enable_container_registry ? azurerm_container_registry.main[0].id : null
}

output "container_registry_login_server" {
  description = "Login server URL for the Container Registry"
  value       = var.enable_container_registry ? azurerm_container_registry.main[0].login_server : null
}

# Application Insights Outputs (conditional)
output "application_insights_name" {
  description = "Name of Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].name : null
}

output "application_insights_id" {
  description = "ID of Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = var.enable_application_insights ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Networking Outputs (conditional)
output "virtual_network_name" {
  description = "Name of the virtual network"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : null
}

output "virtual_network_id" {
  description = "ID of the virtual network"
  value       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].id : null
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = var.enable_private_endpoints ? azurerm_subnet.private[0].id : null
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = var.enable_private_endpoints ? azurerm_subnet.public[0].id : null
}

# Authentication and Connection Information
output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

# Environment Configuration
output "environment_variables" {
  description = "Environment variables for connecting to the deployed resources"
  value = {
    AZURE_SUBSCRIPTION_ID        = data.azurerm_client_config.current.subscription_id
    AZURE_TENANT_ID             = data.azurerm_client_config.current.tenant_id
    AZURE_RESOURCE_GROUP        = azurerm_resource_group.main.name
    AZURE_REGION               = azurerm_resource_group.main.location
    AZURE_QUANTUM_WORKSPACE     = azurerm_quantum_workspace.main.name
    AZURE_ML_WORKSPACE          = azurerm_machine_learning_workspace.main.name
    AZURE_STORAGE_ACCOUNT       = azurerm_storage_account.main.name
    AZURE_BATCH_ACCOUNT         = azurerm_batch_account.main.name
    AZURE_KEY_VAULT             = azurerm_key_vault.main.name
    AZURE_CONTAINER_REGISTRY    = var.enable_container_registry ? azurerm_container_registry.main[0].name : ""
    AZURE_APPLICATION_INSIGHTS  = var.enable_application_insights ? azurerm_application_insights.main[0].name : ""
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (informational)"
  value = {
    note = "Actual costs depend on usage patterns and selected regions"
    components = {
      quantum_workspace     = "Free tier available, charges for premium quantum hardware usage"
      ml_workspace         = "No charge for workspace, compute charges based on usage"
      ml_compute_instance  = "~$200-400/month when running (${var.ml_compute_instance_size})"
      ml_compute_cluster   = "Charges only when scaled up, ~$50-200/month typical usage"
      storage_account      = "$5-50/month depending on data volume"
      batch_account        = "No charge for account, compute charges based on usage"
      key_vault           = "$1-5/month for standard operations"
      container_registry   = var.enable_container_registry ? "$5-20/month for Basic SKU" : "Not deployed"
      application_insights = var.enable_application_insights ? "$1-50/month based on data ingestion" : "Not deployed"
      networking          = var.enable_private_endpoints ? "$5-20/month for VNet and private endpoints" : "Not deployed"
    }
    cost_optimization = {
      auto_shutdown_enabled = var.enable_auto_shutdown
      min_cluster_nodes    = var.ml_compute_cluster_min_nodes
      storage_tier         = "Standard"
      recommendations     = [
        "Enable auto-shutdown for compute instances when not in use",
        "Use spot instances for batch workloads when possible",
        "Monitor storage usage and implement lifecycle policies",
        "Use free tier quantum simulators for development and testing"
      ]
    }
  }
}

# Connection Strings and URLs (for development use)
output "connection_info" {
  description = "Connection information for accessing deployed services"
  value = {
    quantum_workspace_url = "https://quantum.azure.com/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Quantum/Workspaces/${azurerm_quantum_workspace.main.name}"
    ml_studio_url        = "https://ml.azure.com/?wsid=/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.MachineLearningServices/workspaces/${azurerm_machine_learning_workspace.main.name}"
    storage_explorer_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Storage/storageAccounts/${azurerm_storage_account.main.name}/storageExplorer"
    azure_portal_rg_url = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/overview"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Quick start commands for using the deployed infrastructure"
  value = {
    set_env_vars = <<-EOT
      # Set environment variables for Azure CLI
      export AZURE_SUBSCRIPTION_ID="${data.azurerm_client_config.current.subscription_id}"
      export AZURE_RESOURCE_GROUP="${azurerm_resource_group.main.name}"
      export AZURE_QUANTUM_WORKSPACE="${azurerm_quantum_workspace.main.name}"
      export AZURE_ML_WORKSPACE="${azurerm_machine_learning_workspace.main.name}"
      export AZURE_STORAGE_ACCOUNT="${azurerm_storage_account.main.name}"
    EOT
    
    connect_quantum = <<-EOT
      # Connect to Azure Quantum workspace
      az quantum workspace set \\
        --resource-group ${azurerm_resource_group.main.name} \\
        --workspace-name ${azurerm_quantum_workspace.main.name} \\
        --location ${azurerm_resource_group.main.location}
    EOT
    
    connect_ml = <<-EOT
      # Connect to Azure ML workspace
      az ml workspace show \\
        --name ${azurerm_machine_learning_workspace.main.name} \\
        --resource-group ${azurerm_resource_group.main.name}
    EOT
    
    upload_data = <<-EOT
      # Upload data to storage account
      az storage blob upload-batch \\
        --destination quantum-ml-data \\
        --source ./data \\
        --account-name ${azurerm_storage_account.main.name}
    EOT
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    managed_identities = {
      quantum_workspace = azurerm_quantum_workspace.main.identity[0].principal_id
      ml_workspace     = azurerm_machine_learning_workspace.main.identity[0].principal_id
    }
    rbac_assignments = [
      "ML Workspace → Storage Blob Data Contributor on Storage Account",
      "ML Workspace → Key Vault Crypto User on Key Vault",
      "Quantum Workspace → Storage Blob Data Contributor on Storage Account"
    ]
    private_endpoints_enabled = var.enable_private_endpoints
    key_vault_access_policies = "Configured for current user/service principal"
    network_security = {
      storage_account = "Allow Azure services, specific IP ranges"
      key_vault      = "Allow Azure services, specific IP ranges"
      default_action = "Allow (can be restricted post-deployment)"
    }
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    deployed_resources = {
      resource_group          = azurerm_resource_group.main.name
      quantum_workspace       = azurerm_quantum_workspace.main.name
      ml_workspace           = azurerm_machine_learning_workspace.main.name
      ml_compute_instance    = azurerm_machine_learning_compute_instance.quantum_ml_compute.name
      ml_compute_cluster     = azurerm_machine_learning_compute_cluster.quantum_ml_cluster.name
      storage_account        = azurerm_storage_account.main.name
      batch_account          = azurerm_batch_account.main.name
      key_vault             = azurerm_key_vault.main.name
      container_registry     = var.enable_container_registry ? azurerm_container_registry.main[0].name : "Not deployed"
      application_insights   = var.enable_application_insights ? azurerm_application_insights.main[0].name : "Not deployed"
      virtual_network       = var.enable_private_endpoints ? azurerm_virtual_network.main[0].name : "Not deployed"
    }
    next_steps = [
      "1. Access Azure Quantum Studio to explore quantum development environment",
      "2. Open Azure ML Studio to configure your ML pipeline",
      "3. Upload training data to the quantum-ml-data storage container",
      "4. Create and run your first quantum-enhanced ML experiment",
      "5. Monitor costs and resource usage through Azure Portal",
      "6. Review security settings and apply any additional restrictions needed"
    ]
    documentation_links = {
      azure_quantum = "https://docs.microsoft.com/en-us/azure/quantum/"
      azure_ml      = "https://docs.microsoft.com/en-us/azure/machine-learning/"
      cost_management = "https://docs.microsoft.com/en-us/azure/cost-management-billing/"
    }
  }
}