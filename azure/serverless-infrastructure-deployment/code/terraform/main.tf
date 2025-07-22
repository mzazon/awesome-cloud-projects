# Azure Container Apps Jobs Deployment Automation Infrastructure
# This Terraform configuration creates a complete automated deployment workflow
# using Azure Container Apps Jobs, Storage Account, Key Vault, and Managed Identity

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Generate random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

# Resource Group for all deployment automation resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(var.tags, {
    CreatedBy = "terraform"
    Purpose   = "deployment-automation"
  })
}

# User-Assigned Managed Identity for Container Apps Jobs
# This identity will be used by jobs to authenticate to Azure services
resource "azurerm_user_assigned_identity" "deployment_job" {
  name                = var.managed_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

# Storage Account for ARM templates, scripts, and deployment logs
# Provides secure, durable storage for deployment artifacts
resource "azurerm_storage_account" "deployment_artifacts" {
  name                = "st${var.project_name}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Storage configuration
  account_tier                    = var.storage_account_tier
  account_replication_type        = var.storage_account_replication_type
  access_tier                     = var.storage_account_access_tier
  account_kind                    = "StorageV2"
  enable_https_traffic_only       = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = var.enable_storage_public_access

  # Security features
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled      = true
    change_feed_retention_in_days = 7
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  # Network access rules
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  tags = merge(var.tags, {
    Purpose = "deployment-artifacts"
  })
}

# Storage containers for organized artifact management
resource "azurerm_storage_container" "arm_templates" {
  name                  = "arm-templates"
  storage_account_name  = azurerm_storage_account.deployment_artifacts.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.deployment_artifacts]
}

resource "azurerm_storage_container" "deployment_logs" {
  name                  = "deployment-logs"
  storage_account_name  = azurerm_storage_account.deployment_artifacts.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.deployment_artifacts]
}

resource "azurerm_storage_container" "deployment_scripts" {
  name                  = "deployment-scripts"
  storage_account_name  = azurerm_storage_account.deployment_artifacts.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.deployment_artifacts]
}

# Key Vault for secure credential and secret management
# Provides enterprise-grade security for deployment secrets
resource "azurerm_key_vault" "deployment_secrets" {
  name                = "kv-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  # Azure AD tenant configuration
  tenant_id = data.azurerm_client_config.current.tenant_id
  
  # Key Vault configuration
  sku_name                       = var.key_vault_sku_name
  enabled_for_template_deployment = true
  enabled_for_deployment         = true
  enabled_for_disk_encryption    = true
  enable_rbac_authorization      = var.enable_key_vault_rbac
  soft_delete_retention_days     = var.key_vault_soft_delete_retention_days
  purge_protection_enabled       = false

  # Network access configuration
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = merge(var.tags, {
    Purpose = "deployment-secrets"
  })
}

# Container Apps Environment for hosting deployment jobs
# Provides serverless compute environment with monitoring capabilities
resource "azurerm_container_app_environment" "deployment_env" {
  name                = var.container_apps_environment_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Disable logs destination for cost optimization in demo environment
  # In production, consider enabling Log Analytics workspace
  log_analytics_workspace_id = var.enable_container_apps_logs ? azurerm_log_analytics_workspace.container_apps[0].id : null

  tags = merge(var.tags, {
    Purpose = "deployment-environment"
  })
}

# Optional Log Analytics Workspace for Container Apps monitoring
resource "azurerm_log_analytics_workspace" "container_apps" {
  count = var.enable_container_apps_logs ? 1 : 0

  name                = "law-${var.project_name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(var.tags, {
    Purpose = "container-apps-monitoring"
  })
}

# Manual trigger Container Apps Job for on-demand deployments
# Executes ARM template deployments with managed identity authentication
resource "azurerm_container_app_job" "deployment_job" {
  name                         = var.deployment_job_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.deployment_env.id

  # Job execution configuration
  replica_timeout_in_seconds = var.job_replica_timeout
  replica_retry_limit         = var.job_replica_retry_limit
  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  # Container template configuration
  template {
    container {
      name   = "deployment-executor"
      image  = var.container_image
      cpu    = var.job_cpu_allocation
      memory = var.job_memory_allocation

      # Environment variables for deployment context
      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.deployment_artifacts.name
      }

      env {
        name  = "LOCATION"
        value = var.location
      }

      env {
        name  = "KEY_VAULT_NAME"
        value = azurerm_key_vault.deployment_secrets.name
      }

      env {
        name  = "RESOURCE_GROUP_NAME"
        value = azurerm_resource_group.main.name
      }

      env {
        name  = "DEPLOYMENT_TIMEOUT"
        value = tostring(var.deployment_script_timeout)
      }

      # Deployment execution command
      command = ["/bin/bash"]
      args = [
        "-c",
        <<-EOT
        set -e
        echo "Starting deployment workflow..."
        echo "Authenticating with managed identity..."
        az login --identity
        echo "Downloading deployment script..."
        az storage blob download \
          --container-name deployment-scripts \
          --name deploy-script.sh \
          --file /tmp/deploy-script.sh \
          --account-name $STORAGE_ACCOUNT_NAME \
          --auth-mode login
        chmod +x /tmp/deploy-script.sh
        echo "Executing deployment..."
        /tmp/deploy-script.sh
        echo "Deployment workflow completed successfully"
        EOT
      ]
    }
  }

  # Managed identity configuration for secure authentication
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.deployment_job.id]
  }

  tags = merge(var.tags, {
    Purpose   = "manual-deployment"
    JobType   = "on-demand"
    Trigger   = "manual"
  })

  depends_on = [
    azurerm_role_assignment.deployment_contributor,
    azurerm_role_assignment.storage_contributor,
    azurerm_role_assignment.keyvault_secrets_user
  ]
}

# Scheduled Container Apps Job for automated deployments
# Executes deployments based on cron schedule
resource "azurerm_container_app_job" "scheduled_deployment_job" {
  name                         = var.scheduled_job_name
  location                     = azurerm_resource_group.main.location
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.deployment_env.id

  # Job execution configuration
  replica_timeout_in_seconds = var.job_replica_timeout
  replica_retry_limit         = var.job_replica_retry_limit
  
  # Schedule trigger configuration
  schedule_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
    cron_expression         = var.schedule_cron_expression
  }

  # Container template configuration (identical to manual job)
  template {
    container {
      name   = "scheduled-deployment-executor"
      image  = var.container_image
      cpu    = var.job_cpu_allocation
      memory = var.job_memory_allocation

      # Environment variables for deployment context
      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.deployment_artifacts.name
      }

      env {
        name  = "LOCATION"
        value = var.location
      }

      env {
        name  = "KEY_VAULT_NAME"
        value = azurerm_key_vault.deployment_secrets.name
      }

      env {
        name  = "RESOURCE_GROUP_NAME"
        value = azurerm_resource_group.main.name
      }

      env {
        name  = "DEPLOYMENT_TIMEOUT"
        value = tostring(var.deployment_script_timeout)
      }

      env {
        name  = "SCHEDULE_TYPE"
        value = "automated"
      }

      # Deployment execution command with scheduling context
      command = ["/bin/bash"]
      args = [
        "-c",
        <<-EOT
        set -e
        echo "Starting scheduled deployment workflow..."
        echo "Schedule: ${var.schedule_cron_expression}"
        echo "Authenticating with managed identity..."
        az login --identity
        echo "Downloading deployment script..."
        az storage blob download \
          --container-name deployment-scripts \
          --name deploy-script.sh \
          --file /tmp/deploy-script.sh \
          --account-name $STORAGE_ACCOUNT_NAME \
          --auth-mode login
        chmod +x /tmp/deploy-script.sh
        echo "Executing scheduled deployment..."
        /tmp/deploy-script.sh
        echo "Scheduled deployment workflow completed successfully"
        EOT
      ]
    }
  }

  # Managed identity configuration for secure authentication
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.deployment_job.id]
  }

  tags = merge(var.tags, {
    Purpose      = "scheduled-deployment"
    JobType      = "scheduled"
    Trigger      = "cron"
    Schedule     = var.schedule_cron_expression
  })

  depends_on = [
    azurerm_role_assignment.deployment_contributor,
    azurerm_role_assignment.storage_contributor,
    azurerm_role_assignment.keyvault_secrets_user
  ]
}

# RBAC Role Assignments for Managed Identity

# Contributor role for ARM template deployments
resource "azurerm_role_assignment" "deployment_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.deployment_job.principal_id

  depends_on = [azurerm_user_assigned_identity.deployment_job]
}

# Storage Blob Data Contributor for artifact access
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.deployment_artifacts.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.deployment_job.principal_id

  depends_on = [
    azurerm_user_assigned_identity.deployment_job,
    azurerm_storage_account.deployment_artifacts
  ]
}

# Key Vault Secrets User for secure credential access
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = azurerm_key_vault.deployment_secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.deployment_job.principal_id

  depends_on = [
    azurerm_user_assigned_identity.deployment_job,
    azurerm_key_vault.deployment_secrets
  ]
}

# Sample ARM Template for testing deployment workflow
# This template creates a storage account to validate the deployment process
resource "azurerm_storage_blob" "sample_arm_template" {
  name                   = "sample-template.json"
  storage_account_name   = azurerm_storage_account.deployment_artifacts.name
  storage_container_name = azurerm_storage_container.arm_templates.name
  type                   = "Block"
  content_type           = "application/json"

  source_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      storageAccountName = {
        type = "string"
        metadata = {
          description = "Name of the storage account to create"
        }
      }
      location = {
        type         = "string"
        defaultValue = "[resourceGroup().location]"
        metadata = {
          description = "Location for all resources"
        }
      }
    }
    variables = {
      storageAccountType = "Standard_LRS"
    }
    resources = [
      {
        type       = "Microsoft.Storage/storageAccounts"
        apiVersion = "2023-01-01"
        name       = "[parameters('storageAccountName')]"
        location   = "[parameters('location')]"
        sku = {
          name = "[variables('storageAccountType')]"
        }
        kind = "StorageV2"
        properties = {
          accessTier              = "Hot"
          allowBlobPublicAccess   = false
          minimumTlsVersion      = "TLS1_2"
          supportsHttpsTrafficOnly = true
        }
        tags = {
          Purpose     = "deployment-test"
          DeployedBy  = "automated-deployment"
          Environment = var.environment
        }
      }
    ]
    outputs = {
      storageAccountId = {
        type  = "string"
        value = "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]"
      }
      storageAccountName = {
        type  = "string"
        value = "[parameters('storageAccountName')]"
      }
    }
  })

  depends_on = [
    azurerm_storage_container.arm_templates
  ]
}

# Deployment script for Container Apps Jobs
# This script orchestrates ARM template deployment with proper error handling
resource "azurerm_storage_blob" "deployment_script" {
  name                   = "deploy-script.sh"
  storage_account_name   = azurerm_storage_account.deployment_artifacts.name
  storage_container_name = azurerm_storage_container.deployment_scripts.name
  type                   = "Block"
  content_type           = "application/x-sh"

  source_content = <<-EOF
#!/bin/bash
set -e

# Deployment script for Azure Container Apps Jobs
# This script downloads and deploys ARM templates with comprehensive logging

# Script parameters with defaults
TEMPLATE_NAME=$${1:-"sample-template.json"}
DEPLOYMENT_NAME=$${2:-"deployment-$(date +%Y%m%d-%H%M%S)"}
TARGET_RESOURCE_GROUP=$${3:-"rg-deployment-target-$${RANDOM}"}

# Script configuration
SCRIPT_START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
LOG_FILE="/tmp/deployment-$${DEPLOYMENT_NAME}.log"

# Logging function
log_message() {
    echo "[$$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $1" | tee -a "$${LOG_FILE}"
}

# Error handling function
handle_error() {
    log_message "ERROR: $1"
    log_message "Deployment failed. Check logs for details."
    exit 1
}

# Main deployment workflow
log_message "============================================"
log_message "Azure ARM Template Deployment Workflow"
log_message "============================================"
log_message "Started: $${SCRIPT_START_TIME}"
log_message "Template: $${TEMPLATE_NAME}"
log_message "Deployment: $${DEPLOYMENT_NAME}"
log_message "Target RG: $${TARGET_RESOURCE_GROUP}"
log_message "Storage Account: $${STORAGE_ACCOUNT_NAME}"
log_message "Location: $${LOCATION}"

# Authenticate using managed identity
log_message "Authenticating with Azure using managed identity..."
if ! az login --identity; then
    handle_error "Failed to authenticate with managed identity"
fi
log_message "Authentication successful"

# Verify environment variables
log_message "Verifying environment configuration..."
if [[ -z "$${STORAGE_ACCOUNT_NAME}" ]]; then
    handle_error "STORAGE_ACCOUNT_NAME environment variable not set"
fi
if [[ -z "$${LOCATION}" ]]; then
    handle_error "LOCATION environment variable not set"
fi

# Download ARM template from storage
log_message "Downloading ARM template: $${TEMPLATE_NAME}..."
if ! az storage blob download \
    --container-name "arm-templates" \
    --name "$${TEMPLATE_NAME}" \
    --file "/tmp/$${TEMPLATE_NAME}" \
    --account-name "$${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login; then
    handle_error "Failed to download ARM template: $${TEMPLATE_NAME}"
fi
log_message "ARM template downloaded successfully"

# Validate ARM template syntax
log_message "Validating ARM template syntax..."
if ! az deployment group validate \
    --resource-group "$${RESOURCE_GROUP_NAME}" \
    --template-file "/tmp/$${TEMPLATE_NAME}" \
    --parameters storageAccountName="st$${DEPLOYMENT_NAME}test" \
    --output none; then
    log_message "Template validation failed, but proceeding with deployment..."
fi

# Create target resource group if it doesn't exist
log_message "Creating target resource group: $${TARGET_RESOURCE_GROUP}..."
if ! az group create \
    --name "$${TARGET_RESOURCE_GROUP}" \
    --location "$${LOCATION}" \
    --tags \
        deployedBy="automated-deployment" \
        deploymentName="$${DEPLOYMENT_NAME}" \
        timestamp="$$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        purpose="deployment-test"; then
    handle_error "Failed to create target resource group: $${TARGET_RESOURCE_GROUP}"
fi
log_message "Target resource group created successfully"

# Deploy ARM template with error handling
log_message "Starting ARM template deployment..."
DEPLOYMENT_OUTPUT=""
if DEPLOYMENT_OUTPUT=$$(az deployment group create \
    --resource-group "$${TARGET_RESOURCE_GROUP}" \
    --template-file "/tmp/$${TEMPLATE_NAME}" \
    --name "$${DEPLOYMENT_NAME}" \
    --parameters storageAccountName="st$${DEPLOYMENT_NAME}test" \
    --output json 2>&1); then
    log_message "ARM template deployment completed successfully"
    log_message "Deployment output: $${DEPLOYMENT_OUTPUT}"
else
    handle_error "ARM template deployment failed: $${DEPLOYMENT_OUTPUT}"
fi

# Extract deployment results
DEPLOYMENT_ID=$$(echo "$${DEPLOYMENT_OUTPUT}" | jq -r '.id // "unknown"')
DEPLOYMENT_STATE=$$(echo "$${DEPLOYMENT_OUTPUT}" | jq -r '.properties.provisioningState // "unknown"')
STORAGE_ACCOUNT_ID=$$(echo "$${DEPLOYMENT_OUTPUT}" | jq -r '.properties.outputs.storageAccountId.value // "unknown"')

log_message "Deployment Results:"
log_message "  Deployment ID: $${DEPLOYMENT_ID}"
log_message "  Provisioning State: $${DEPLOYMENT_STATE}"
log_message "  Storage Account ID: $${STORAGE_ACCOUNT_ID}"

# Create comprehensive deployment log
DEPLOYMENT_LOG_JSON=$$(cat <<-EOJ
{
  "deploymentName": "$${DEPLOYMENT_NAME}",
  "templateName": "$${TEMPLATE_NAME}",
  "targetResourceGroup": "$${TARGET_RESOURCE_GROUP}",
  "startTime": "$${SCRIPT_START_TIME}",
  "endTime": "$$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
  "status": "success",
  "deploymentId": "$${DEPLOYMENT_ID}",
  "provisioningState": "$${DEPLOYMENT_STATE}",
  "outputs": $${DEPLOYMENT_OUTPUT},
  "environment": {
    "storageAccount": "$${STORAGE_ACCOUNT_NAME}",
    "location": "$${LOCATION}",
    "resourceGroup": "$${RESOURCE_GROUP_NAME}"
  }
}
EOJ
)

# Save deployment log to storage
log_message "Uploading deployment log to storage..."
echo "$${DEPLOYMENT_LOG_JSON}" > "/tmp/deployment-log-$${DEPLOYMENT_NAME}.json"
if ! az storage blob upload \
    --file "/tmp/deployment-log-$${DEPLOYMENT_NAME}.json" \
    --container-name "deployment-logs" \
    --name "deployment-log-$${DEPLOYMENT_NAME}.json" \
    --account-name "$${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login \
    --overwrite; then
    log_message "WARNING: Failed to upload deployment log to storage"
else
    log_message "Deployment log uploaded successfully"
fi

# Upload execution log
if ! az storage blob upload \
    --file "$${LOG_FILE}" \
    --container-name "deployment-logs" \
    --name "execution-log-$${DEPLOYMENT_NAME}.txt" \
    --account-name "$${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login \
    --overwrite; then
    log_message "WARNING: Failed to upload execution log to storage"
else
    log_message "Execution log uploaded successfully"
fi

log_message "============================================"
log_message "✅ Deployment workflow completed successfully"
log_message "Deployment Name: $${DEPLOYMENT_NAME}"
log_message "Target Resource Group: $${TARGET_RESOURCE_GROUP}"
log_message "Duration: $$(date -u '+%Y-%m-%d %H:%M:%S UTC') (started $${SCRIPT_START_TIME})"
log_message "============================================"

exit 0
EOF

  depends_on = [
    azurerm_storage_container.deployment_scripts
  ]
}

# Wait for RBAC assignments to propagate before jobs can be executed
resource "time_sleep" "rbac_propagation" {
  depends_on = [
    azurerm_role_assignment.deployment_contributor,
    azurerm_role_assignment.storage_contributor,
    azurerm_role_assignment.keyvault_secrets_user
  ]

  create_duration = "60s"
}