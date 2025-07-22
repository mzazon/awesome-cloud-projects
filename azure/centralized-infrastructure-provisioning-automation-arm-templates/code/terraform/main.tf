# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Data source for current subscription
data "azurerm_subscription" "current" {}

# Main resource group for automation infrastructure
resource "azurerm_resource_group" "automation" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
}

# Target resource group for deployments
resource "azurerm_resource_group" "target" {
  name     = var.target_resource_group_name
  location = var.location
  
  tags = merge(var.common_tags, {
    deployment = "automated"
  })
}

# Log Analytics workspace for centralized monitoring
resource "azurerm_log_analytics_workspace" "automation" {
  name                = var.log_analytics_workspace_name
  location            = azurerm_resource_group.automation.location
  resource_group_name = azurerm_resource_group.automation.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  
  tags = merge(var.common_tags, {
    component = "monitoring"
  })
}

# Storage account for ARM templates with unique name
resource "azurerm_storage_account" "arm_templates" {
  name                     = "${var.storage_account_name_prefix}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.automation.name
  location                 = azurerm_resource_group.automation.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = var.storage_access_tier
  
  # Security configurations
  https_traffic_only_enabled   = var.enable_storage_https_only
  allow_nested_items_to_be_public = var.enable_storage_blob_public_access
  
  # Enable blob service properties
  blob_properties {
    # Enable versioning for better template management
    versioning_enabled = true
    
    # Configure delete retention
    delete_retention_policy {
      days = 30
    }
    
    # Configure container delete retention
    container_delete_retention_policy {
      days = 30
    }
  }
  
  # Network access rules
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
  
  tags = merge(var.common_tags, {
    component = "storage"
    purpose   = "arm-templates"
  })
}

# File share for ARM templates
resource "azurerm_storage_share" "arm_templates" {
  name                 = var.storage_file_share_name
  storage_account_name = azurerm_storage_account.arm_templates.name
  quota                = var.storage_file_share_quota
  
  depends_on = [azurerm_storage_account.arm_templates]
}

# Azure Automation Account with managed identity
resource "azurerm_automation_account" "main" {
  name                = var.automation_account_name
  location            = azurerm_resource_group.automation.location
  resource_group_name = azurerm_resource_group.automation.name
  sku_name            = var.automation_account_sku
  
  # Enable managed identity
  identity {
    type = var.enable_managed_identity ? "SystemAssigned" : null
  }
  
  # Security configurations
  public_network_access_enabled = var.enable_public_network_access
  
  tags = merge(var.common_tags, {
    component = "automation"
  })
}

# PowerShell runbook for infrastructure deployment
resource "azurerm_automation_runbook" "deploy_infrastructure" {
  name                    = var.runbook_name
  location                = azurerm_resource_group.automation.location
  resource_group_name     = azurerm_resource_group.automation.name
  automation_account_name = azurerm_automation_account.main.name
  log_verbose             = true
  log_progress            = true
  description             = var.runbook_description
  runbook_type            = var.runbook_type
  
  # PowerShell runbook content for automated ARM template deployment
  content = templatefile("${path.module}/runbook-content.ps1", {
    subscription_id = data.azurerm_subscription.current.subscription_id
  })
  
  tags = merge(var.common_tags, {
    component = "runbook"
    type      = "deployment"
  })
}

# Install required PowerShell modules
resource "azurerm_automation_module" "powershell_modules" {
  for_each = {
    for module in var.powershell_modules : module.name => module
  }
  
  name                    = each.value.name
  automation_account_name = azurerm_automation_account.main.name
  resource_group_name     = azurerm_resource_group.automation.name
  
  module_uri = "https://www.powershellgallery.com/packages/${each.value.name}/${each.value.version == "latest" ? "" : each.value.version}"
  
  depends_on = [azurerm_automation_account.main]
  
  tags = merge(var.common_tags, {
    component = "automation-module"
    module    = each.value.name
  })
}

# Role assignment: Contributor role for Automation Account on main resource group
resource "azurerm_role_assignment" "automation_contributor_main" {
  scope                = azurerm_resource_group.automation.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.main.identity[0].principal_id
  
  depends_on = [azurerm_automation_account.main]
}

# Role assignment: Contributor role for Automation Account on target resource group
resource "azurerm_role_assignment" "automation_contributor_target" {
  scope                = azurerm_resource_group.target.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.main.identity[0].principal_id
  
  depends_on = [azurerm_automation_account.main]
}

# Role assignment: Storage Blob Data Contributor for ARM template access
resource "azurerm_role_assignment" "automation_storage_contributor" {
  scope                = azurerm_storage_account.arm_templates.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_automation_account.main.identity[0].principal_id
  
  depends_on = [azurerm_automation_account.main]
}

# Storage account key for runbook access
data "azurerm_storage_account_sas" "arm_templates" {
  connection_string = azurerm_storage_account.arm_templates.primary_connection_string
  https_only        = true
  
  resource_types {
    service   = true
    container = true
    object    = true
  }
  
  services {
    blob  = true
    queue = false
    table = false
    file  = true
  }
  
  start  = formatdate("YYYY-MM-DD", timestamp())
  expiry = formatdate("YYYY-MM-DD", timeadd(timestamp(), "8760h")) # 1 year
  
  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true
    add     = true
    create  = true
    update  = true
    process = true
    tag     = true
    filter  = true
  }
}

# Create ARM template file in storage
resource "azurerm_storage_share_file" "infrastructure_template" {
  name             = "infrastructure-template.json"
  storage_share_id = azurerm_storage_share.arm_templates.id
  source           = "${path.module}/arm-template.json"
  
  depends_on = [azurerm_storage_share.arm_templates]
}

# Diagnostic settings for Automation Account
resource "azurerm_monitor_diagnostic_setting" "automation_account" {
  count                      = var.enable_diagnostics ? 1 : 0
  name                       = "automation-diagnostics"
  target_resource_id         = azurerm_automation_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.automation.id
  
  # Job logs
  enabled_log {
    category = "JobLogs"
  }
  
  # Job streams
  enabled_log {
    category = "JobStreams"
  }
  
  # Audit logs
  enabled_log {
    category = "AuditEvent"
  }
  
  # Metrics
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings for Storage Account
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  count                      = var.enable_diagnostics ? 1 : 0
  name                       = "storage-diagnostics"
  target_resource_id         = azurerm_storage_account.arm_templates.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.automation.id
  
  # Metrics
  metric {
    category = "Transaction"
    enabled  = true
  }
  
  metric {
    category = "Capacity"
    enabled  = true
  }
}

# Action Group for automation alerts
resource "azurerm_monitor_action_group" "automation_alerts" {
  name                = "automation-alerts"
  resource_group_name = azurerm_resource_group.automation.name
  short_name          = "auto-alert"
  
  # Email notification (can be configured with actual email addresses)
  email_receiver {
    name          = "automation-admin"
    email_address = "admin@example.com"
  }
  
  tags = merge(var.common_tags, {
    component = "monitoring"
    type      = "alerting"
  })
}

# Alert rule for failed runbook executions
resource "azurerm_monitor_metric_alert" "runbook_failures" {
  name                = "runbook-execution-failures"
  resource_group_name = azurerm_resource_group.automation.name
  scopes              = [azurerm_automation_account.main.id]
  description         = "Alert when runbook executions fail"
  
  criteria {
    metric_namespace = "Microsoft.Automation/automationAccounts"
    metric_name      = "TotalJob"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    
    dimension {
      name     = "Status"
      operator = "Include"
      values   = ["Failed"]
    }
  }
  
  action {
    action_group_id = azurerm_monitor_action_group.automation_alerts.id
  }
  
  frequency   = "PT5M"
  window_size = "PT5M"
  
  tags = merge(var.common_tags, {
    component = "monitoring"
    type      = "alert"
  })
}

# Local file for ARM template
resource "local_file" "arm_template" {
  filename = "${path.module}/arm-template.json"
  content = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    
    parameters = {
      storageAccountType = {
        type = "string"
        defaultValue = var.arm_template_storage_account_type
        allowedValues = ["Standard_LRS", "Standard_GRS", "Standard_ZRS", "Premium_LRS"]
        metadata = {
          description = "Storage Account type"
        }
      }
      location = {
        type = "string"
        defaultValue = "[resourceGroup().location]"
        metadata = {
          description = "Location for all resources"
        }
      }
      environment = {
        type = "string"
        defaultValue = var.arm_template_environment
        metadata = {
          description = "Environment tag"
        }
      }
    }
    
    variables = {
      storageAccountName = "[concat('st', uniqueString(resourceGroup().id))]"
      virtualNetworkName = "[concat('vnet-', parameters('environment'), '-', uniqueString(resourceGroup().id))]"
      subnetName = "default"
    }
    
    resources = [
      {
        type = "Microsoft.Storage/storageAccounts"
        apiVersion = "2021-09-01"
        name = "[variables('storageAccountName')]"
        location = "[parameters('location')]"
        tags = {
          environment = "[parameters('environment')]"
          deployment = "automated"
        }
        sku = {
          name = "[parameters('storageAccountType')]"
        }
        kind = "StorageV2"
        properties = {
          allowBlobPublicAccess = false
          supportsHttpsTrafficOnly = true
          minimumTlsVersion = "TLS1_2"
        }
      },
      {
        type = "Microsoft.Network/virtualNetworks"
        apiVersion = "2021-05-01"
        name = "[variables('virtualNetworkName')]"
        location = "[parameters('location')]"
        tags = {
          environment = "[parameters('environment')]"
          deployment = "automated"
        }
        properties = {
          addressSpace = {
            addressPrefixes = ["10.0.0.0/16"]
          }
          subnets = [
            {
              name = "[variables('subnetName')]"
              properties = {
                addressPrefix = "10.0.1.0/24"
              }
            }
          ]
        }
      }
    ]
    
    outputs = {
      storageAccountName = {
        type = "string"
        value = "[variables('storageAccountName')]"
      }
      virtualNetworkName = {
        type = "string"
        value = "[variables('virtualNetworkName')]"
      }
      deploymentTimestamp = {
        type = "string"
        value = "[utcNow()]"
      }
    }
  })
}

# Local file for PowerShell runbook content
resource "local_file" "runbook_content" {
  filename = "${path.module}/runbook-content.ps1"
  content = templatefile("${path.module}/runbook-template.ps1", {
    subscription_id = data.azurerm_subscription.current.subscription_id
  })
}

# Create the runbook template file
resource "local_file" "runbook_template" {
  filename = "${path.module}/runbook-template.ps1"
  content = <<-EOT
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$TemplateName,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "demo",
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountType = "Standard_LRS"
)

# Ensure no context inheritance
Disable-AzContextAutosave -Scope Process

try {
    # Connect using managed identity
    Write-Output "Connecting to Azure using managed identity..."
    $AzureContext = (Connect-AzAccount -Identity).context
    
    # Set subscription context
    Set-AzContext -SubscriptionId "${subscription_id}" -Force
    
    # Download ARM template from storage
    Write-Output "Downloading ARM template from storage..."
    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    $StorageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageKey
    
    # Create temp directory for template
    $TempPath = "C:\Temp"
    if (!(Test-Path $TempPath)) {
        New-Item -ItemType Directory -Path $TempPath -Force
    }
    
    # Download template file
    Get-AzStorageFileContent -ShareName "arm-templates" -Path $TemplateName -Destination $TempPath -Context $StorageContext -Force
    $TemplateFile = Join-Path $TempPath $TemplateName
    
    # Verify template file exists
    if (!(Test-Path $TemplateFile)) {
        throw "Template file not found: $TemplateFile"
    }
    
    # Set deployment parameters
    $DeploymentParams = @{
        storageAccountType = $StorageAccountType
        environment = $Environment
    }
    
    # Generate unique deployment name
    $DeploymentName = "deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-Output "Starting deployment: $DeploymentName"
    Write-Output "Target Resource Group: $ResourceGroupName"
    Write-Output "Template File: $TemplateFile"
    Write-Output "Parameters: $($DeploymentParams | ConvertTo-Json)"
    
    # Validate ARM template first
    Write-Output "Validating ARM template..."
    $ValidationResult = Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $TemplateFile -TemplateParameterObject $DeploymentParams
    
    if ($ValidationResult) {
        Write-Error "Template validation failed:"
        foreach ($error in $ValidationResult) {
            Write-Error "  - $($error.Message)"
        }
        throw "Template validation failed"
    }
    
    Write-Output "✅ Template validation passed"
    
    # Deploy ARM template
    Write-Output "Deploying ARM template..."
    $Deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFile -TemplateParameterObject $DeploymentParams -Verbose -Force
    
    if ($Deployment.ProvisioningState -eq "Succeeded") {
        Write-Output "✅ Deployment completed successfully"
        Write-Output "Deployment Name: $DeploymentName"
        Write-Output "Provisioning State: $($Deployment.ProvisioningState)"
        Write-Output "Deployment Mode: $($Deployment.Mode)"
        Write-Output "Correlation ID: $($Deployment.CorrelationId)"
        
        # Log deployment outputs
        if ($Deployment.Outputs) {
            Write-Output "Deployment Outputs:"
            foreach ($key in $Deployment.Outputs.Keys) {
                Write-Output "  $key: $($Deployment.Outputs[$key].Value)"
            }
        }
        
        # Log deployed resources
        Write-Output "Deployed Resources:"
        foreach ($resource in $Deployment.Dependencies) {
            Write-Output "  - $($resource.ResourceName) ($($resource.ResourceType))"
        }
        
    } else {
        Write-Error "Deployment failed with state: $($Deployment.ProvisioningState)"
        if ($Deployment.StatusMessage) {
            Write-Error "Status Message: $($Deployment.StatusMessage)"
        }
        throw "Deployment failed"
    }
    
} catch {
    Write-Error "Error during deployment: $($_.Exception.Message)"
    Write-Error "Stack Trace: $($_.Exception.StackTrace)"
    
    # Attempt to get more details about the error
    if ($_.Exception.InnerException) {
        Write-Error "Inner Exception: $($_.Exception.InnerException.Message)"
    }
    
    # Log deployment history for troubleshooting
    try {
        Write-Output "Recent deployment history:"
        $RecentDeployments = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName | Select-Object -First 5
        foreach ($dep in $RecentDeployments) {
            Write-Output "  - $($dep.DeploymentName): $($dep.ProvisioningState) ($($dep.Timestamp))"
        }
    } catch {
        Write-Warning "Could not retrieve deployment history: $($_.Exception.Message)"
    }
    
    # Attempt rollback if deployment exists and rollback is enabled
    try {
        Write-Output "Attempting rollback to previous successful deployment..."
        $PreviousDeployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName | Where-Object { $_.ProvisioningState -eq "Succeeded" } | Sort-Object Timestamp -Descending | Select-Object -First 1
        
        if ($PreviousDeployment) {
            Write-Output "Found previous successful deployment: $($PreviousDeployment.DeploymentName)"
            Write-Output "Rollback capability available but not implemented in this version"
            # Rollback implementation would go here
        } else {
            Write-Output "No previous successful deployment found for rollback"
        }
    } catch {
        Write-Error "Rollback failed: $($_.Exception.Message)"
    }
    
    throw $_.Exception
}
EOT
}

# Output values for verification and integration
locals {
  automation_outputs = {
    automation_account_id       = azurerm_automation_account.main.id
    automation_account_name     = azurerm_automation_account.main.name
    managed_identity_principal_id = azurerm_automation_account.main.identity[0].principal_id
    storage_account_name        = azurerm_storage_account.arm_templates.name
    storage_account_id          = azurerm_storage_account.arm_templates.id
    file_share_name             = azurerm_storage_share.arm_templates.name
    runbook_name                = azurerm_automation_runbook.deploy_infrastructure.name
    log_analytics_workspace_id  = azurerm_log_analytics_workspace.automation.id
    target_resource_group_id    = azurerm_resource_group.target.id
  }
}
EOT