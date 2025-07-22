#!/bin/bash

# deploy.sh - Deployment script for Proactive Disaster Recovery with Backup Center Automation
# This script automates the deployment of a comprehensive disaster recovery solution using Azure services

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    log "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Success indicator function
success() {
    log "✅ $1"
}

# Check prerequisites function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI v2.60.0 or later."
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: ${AZ_VERSION}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "OpenSSL is not available. Please install OpenSSL for random string generation."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables function
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Export environment variables for the deployment
    export PRIMARY_REGION="${PRIMARY_REGION:-eastus}"
    export SECONDARY_REGION="${SECONDARY_REGION:-westus2}"
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dr-orchestration}"
    export BACKUP_RESOURCE_GROUP="${BACKUP_RESOURCE_GROUP:-rg-dr-backup}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    log "Using random suffix: ${RANDOM_SUFFIX}"
    
    # Set resource names with proper Azure naming conventions
    export RSV_PRIMARY_NAME="rsv-dr-primary-${RANDOM_SUFFIX}"
    export RSV_SECONDARY_NAME="rsv-dr-secondary-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stdrbackup${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-dr-orchestration-${RANDOM_SUFFIX}"
    export MONITOR_WORKSPACE_NAME="law-dr-monitoring-${RANDOM_SUFFIX}"
    export ACTION_GROUP_NAME="ag-dr-alerts-${RANDOM_SUFFIX}"
    
    # Save variables to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.sh" << EOF
export PRIMARY_REGION="${PRIMARY_REGION}"
export SECONDARY_REGION="${SECONDARY_REGION}"
export RESOURCE_GROUP="${RESOURCE_GROUP}"
export BACKUP_RESOURCE_GROUP="${BACKUP_RESOURCE_GROUP}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export RSV_PRIMARY_NAME="${RSV_PRIMARY_NAME}"
export RSV_SECONDARY_NAME="${RSV_SECONDARY_NAME}"
export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME}"
export LOGIC_APP_NAME="${LOGIC_APP_NAME}"
export MONITOR_WORKSPACE_NAME="${MONITOR_WORKSPACE_NAME}"
export ACTION_GROUP_NAME="${ACTION_GROUP_NAME}"
EOF
    
    success "Environment variables configured"
}

# Create resource groups function
create_resource_groups() {
    log "Creating resource groups..."
    
    # Create primary resource group
    az group create \
        --name ${RESOURCE_GROUP} \
        --location ${PRIMARY_REGION} \
        --tags purpose=disaster-recovery environment=production \
        >> "${LOG_FILE}" 2>&1
    
    # Create backup resource group
    az group create \
        --name ${BACKUP_RESOURCE_GROUP} \
        --location ${PRIMARY_REGION} \
        --tags purpose=backup environment=production \
        >> "${LOG_FILE}" 2>&1
    
    success "Resource groups created successfully"
}

# Create Recovery Services Vaults function
create_recovery_vaults() {
    log "Creating Recovery Services Vaults..."
    
    # Create primary Recovery Services Vault
    az backup vault create \
        --name ${RSV_PRIMARY_NAME} \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --location ${PRIMARY_REGION} \
        --storage-model-type GeoRedundant \
        --tags environment=production purpose=backup region=primary \
        >> "${LOG_FILE}" 2>&1
    
    # Create secondary Recovery Services Vault
    az backup vault create \
        --name ${RSV_SECONDARY_NAME} \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --location ${SECONDARY_REGION} \
        --storage-model-type GeoRedundant \
        --tags environment=production purpose=backup region=secondary \
        >> "${LOG_FILE}" 2>&1
    
    success "Recovery Services Vaults created in both regions"
}

# Set up monitoring infrastructure function
setup_monitoring() {
    log "Setting up Log Analytics Workspace and monitoring..."
    
    # Create Log Analytics Workspace
    az monitor log-analytics workspace create \
        --workspace-name ${MONITOR_WORKSPACE_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --location ${PRIMARY_REGION} \
        --sku PerGB2018 \
        --tags purpose=monitoring environment=production \
        >> "${LOG_FILE}" 2>&1
    
    # Get workspace ID for later configuration
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --name ${MONITOR_WORKSPACE_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query customerId --output tsv)
    
    # Enable diagnostic settings for Recovery Services Vaults
    az monitor diagnostic-settings create \
        --name "DiagnosticSettings-${RSV_PRIMARY_NAME}" \
        --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${BACKUP_RESOURCE_GROUP}/providers/Microsoft.RecoveryServices/vaults/${RSV_PRIMARY_NAME}" \
        --workspace ${WORKSPACE_ID} \
        --logs '[{"category":"AddonAzureBackupJobs","enabled":true},{"category":"AddonAzureBackupAlerts","enabled":true}]' \
        --metrics '[{"category":"Health","enabled":true}]' \
        >> "${LOG_FILE}" 2>&1
    
    success "Log Analytics Workspace configured with diagnostic settings"
}

# Create action groups function
create_action_groups() {
    log "Creating Action Groups for alerting..."
    
    # Create Action Group for disaster recovery alerts
    az monitor action-group create \
        --name ${ACTION_GROUP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --short-name "DR-Alerts" \
        --action email admin-email admin@company.com \
        --action sms admin-sms +1234567890 \
        --tags purpose=alerting environment=production \
        >> "${LOG_FILE}" 2>&1
    
    # Add webhook action for Logic Apps integration
    az monitor action-group update \
        --name ${ACTION_GROUP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --add-action webhook dr-webhook https://placeholder-webhook-url.com/webhook \
        >> "${LOG_FILE}" 2>&1
    
    success "Action Group created with multi-channel notifications"
}

# Deploy Logic Apps function
deploy_logic_apps() {
    log "Deploying Logic Apps for orchestration..."
    
    # Create storage account for Logic Apps state management
    az storage account create \
        --name ${STORAGE_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --location ${PRIMARY_REGION} \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=orchestration environment=production \
        >> "${LOG_FILE}" 2>&1
    
    # Create Logic Apps workflow definition
    cat > "${SCRIPT_DIR}/logic-app-workflow.json" << 'EOF'
{
    "definition": {
        "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
        "actions": {
            "Check_Backup_Status": {
                "type": "Http",
                "inputs": {
                    "method": "GET",
                    "uri": "https://management.azure.com/subscriptions/@{variables('subscriptionId')}/resourceGroups/@{variables('resourceGroup')}/providers/Microsoft.RecoveryServices/vaults/@{variables('vaultName')}/backupJobs",
                    "authentication": {
                        "type": "ManagedServiceIdentity"
                    }
                },
                "runAfter": {
                    "Initialize_Variables": ["Succeeded"]
                }
            },
            "Initialize_Variables": {
                "type": "InitializeVariable",
                "inputs": {
                    "variables": [
                        {
                            "name": "subscriptionId",
                            "type": "string",
                            "value": "@{triggerBody()?['data']?['context']?['subscriptionId']}"
                        },
                        {
                            "name": "resourceGroup",
                            "type": "string",
                            "value": "@{triggerBody()?['data']?['context']?['resourceGroupName']}"
                        },
                        {
                            "name": "vaultName",
                            "type": "string",
                            "value": "@{triggerBody()?['data']?['context']?['resourceName']}"
                        }
                    ]
                },
                "runAfter": {}
            },
            "Send_Teams_Notification": {
                "type": "Http",
                "inputs": {
                    "method": "POST",
                    "uri": "https://placeholder-teams-webhook.webhook.office.com/webhookb2/placeholder",
                    "body": {
                        "text": "Disaster Recovery Alert: Backup failure detected. Initiating automated recovery procedures."
                    }
                },
                "runAfter": {
                    "Check_Backup_Status": ["Succeeded"]
                }
            },
            "Trigger_Cross_Region_Restore": {
                "type": "Http",
                "inputs": {
                    "method": "POST",
                    "uri": "https://management.azure.com/subscriptions/@{variables('subscriptionId')}/resourceGroups/@{variables('resourceGroup')}/providers/Microsoft.RecoveryServices/vaults/@{variables('vaultName')}/backupFabrics/Azure/protectionContainers/IaasVMContainer/protectedItems/VM/restore",
                    "authentication": {
                        "type": "ManagedServiceIdentity"
                    },
                    "body": {
                        "properties": {
                            "restoreType": "AlternateLocation",
                            "targetRegion": "westus2"
                        }
                    }
                },
                "runAfter": {
                    "Send_Teams_Notification": ["Succeeded"]
                }
            }
        },
        "triggers": {
            "manual": {
                "type": "Request",
                "kind": "Http",
                "inputs": {
                    "schema": {
                        "type": "object",
                        "properties": {
                            "data": {
                                "type": "object"
                            }
                        }
                    }
                }
            }
        },
        "contentVersion": "1.0.0.0",
        "outputs": {}
    }
}
EOF
    
    # Deploy the Logic Apps workflow
    az logic workflow create \
        --resource-group ${RESOURCE_GROUP} \
        --name ${LOGIC_APP_NAME} \
        --location ${PRIMARY_REGION} \
        --definition @"${SCRIPT_DIR}/logic-app-workflow.json" \
        --tags purpose=orchestration environment=production \
        >> "${LOG_FILE}" 2>&1
    
    # Enable managed identity for Logic Apps
    az logic workflow identity assign \
        --name ${LOGIC_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        >> "${LOG_FILE}" 2>&1
    
    success "Logic Apps infrastructure deployed successfully"
}

# Configure backup policies function
configure_backup_policies() {
    log "Configuring backup policies..."
    
    # Create backup policy for VMs with intelligent scheduling
    cat > "${SCRIPT_DIR}/vm-policy.json" << 'EOF'
{
    "name": "DRVMPolicy",
    "properties": {
        "backupManagementType": "AzureIaasVM",
        "schedulePolicy": {
            "schedulePolicyType": "SimpleSchedulePolicy",
            "scheduleRunFrequency": "Daily",
            "scheduleRunTimes": ["2024-01-01T02:00:00Z"],
            "scheduleWeeklyFrequency": 0
        },
        "retentionPolicy": {
            "retentionPolicyType": "LongTermRetentionPolicy",
            "dailySchedule": {
                "retentionTimes": ["2024-01-01T02:00:00Z"],
                "retentionDuration": {
                    "count": 30,
                    "durationType": "Days"
                }
            },
            "weeklySchedule": {
                "daysOfTheWeek": ["Sunday"],
                "retentionTimes": ["2024-01-01T02:00:00Z"],
                "retentionDuration": {
                    "count": 12,
                    "durationType": "Weeks"
                }
            }
        }
    }
}
EOF
    
    # Create backup policy for SQL databases
    cat > "${SCRIPT_DIR}/sql-policy.json" << 'EOF'
{
    "name": "DRSQLPolicy",
    "properties": {
        "backupManagementType": "AzureWorkload",
        "workLoadType": "SQLDataBase",
        "schedulePolicy": {
            "schedulePolicyType": "SimpleSchedulePolicy",
            "scheduleRunFrequency": "Daily",
            "scheduleRunTimes": ["2024-01-01T22:00:00Z"]
        },
        "retentionPolicy": {
            "retentionPolicyType": "LongTermRetentionPolicy",
            "dailySchedule": {
                "retentionTimes": ["2024-01-01T22:00:00Z"],
                "retentionDuration": {
                    "count": 30,
                    "durationType": "Days"
                }
            }
        }
    }
}
EOF
    
    # Deploy VM backup policy
    az backup policy create \
        --policy @"${SCRIPT_DIR}/vm-policy.json" \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --vault-name ${RSV_PRIMARY_NAME} \
        >> "${LOG_FILE}" 2>&1
    
    # Deploy SQL backup policy
    az backup policy create \
        --policy @"${SCRIPT_DIR}/sql-policy.json" \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --vault-name ${RSV_PRIMARY_NAME} \
        >> "${LOG_FILE}" 2>&1
    
    success "Intelligent backup policies configured for VMs and SQL databases"
}

# Setup alert rules function
setup_alert_rules() {
    log "Setting up Azure Monitor alert rules..."
    
    # Create alert rule for backup job failures
    az monitor metrics alert create \
        --name "BackupJobFailureAlert" \
        --resource-group ${RESOURCE_GROUP} \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${BACKUP_RESOURCE_GROUP}/providers/Microsoft.RecoveryServices/vaults/${RSV_PRIMARY_NAME}" \
        --condition "count 'Backup Health Events' > 0" \
        --description "Alert when backup jobs fail" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --severity 2 \
        --action ${ACTION_GROUP_NAME} \
        --tags purpose=monitoring environment=production \
        >> "${LOG_FILE}" 2>&1
    
    # Create alert rule for Recovery Services Vault health
    az monitor metrics alert create \
        --name "RecoveryVaultHealthAlert" \
        --resource-group ${RESOURCE_GROUP} \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${BACKUP_RESOURCE_GROUP}/providers/Microsoft.RecoveryServices/vaults/${RSV_PRIMARY_NAME}" \
        --condition "count 'Health' < 1" \
        --description "Alert when Recovery Services Vault becomes unhealthy" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --severity 1 \
        --action ${ACTION_GROUP_NAME} \
        --tags purpose=monitoring environment=production \
        >> "${LOG_FILE}" 2>&1
    
    success "Comprehensive monitoring alert rules configured"
}

# Configure cross-region replication function
configure_cross_region_replication() {
    log "Configuring cross-region replication..."
    
    # Enable cross-region restore for primary vault
    az backup vault backup-properties set \
        --name ${RSV_PRIMARY_NAME} \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --cross-region-restore-flag true \
        >> "${LOG_FILE}" 2>&1
    
    # Configure backup storage redundancy for geo-replication
    az backup vault backup-properties set \
        --name ${RSV_PRIMARY_NAME} \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --backup-storage-redundancy GeoRedundant \
        >> "${LOG_FILE}" 2>&1
    
    # Set up replication policy for secondary region
    az backup vault backup-properties set \
        --name ${RSV_SECONDARY_NAME} \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --backup-storage-redundancy GeoRedundant \
        --cross-region-restore-flag true \
        >> "${LOG_FILE}" 2>&1
    
    success "Cross-region replication configured for disaster recovery"
}

# Create monitoring workbook function
create_monitoring_workbook() {
    log "Creating Azure Monitor workbook..."
    
    # Create a workbook template for disaster recovery monitoring
    cat > "${SCRIPT_DIR}/dr-workbook-template.json" << 'EOF'
{
    "version": "Notebook/1.0",
    "items": [
        {
            "type": 1,
            "content": {
                "json": "# Disaster Recovery Dashboard\n\nThis dashboard provides comprehensive visibility into backup operations, recovery readiness, and disaster recovery metrics across all protected resources."
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "AzureBackupReport | where TimeGenerated > ago(24h) | summarize BackupJobs = count() by BackupItemType, JobStatus | render piechart",
                "size": 0,
                "title": "Backup Job Status by Resource Type",
                "queryType": 0,
                "resourceType": "microsoft.operationalinsights/workspaces"
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "AzureBackupReport | where TimeGenerated > ago(7d) | summarize TotalStorageGB = sum(StorageConsumedInMBs)/1024 by bin(TimeGenerated, 1d) | render timechart",
                "size": 0,
                "title": "Storage Consumption Trend",
                "queryType": 0,
                "resourceType": "microsoft.operationalinsights/workspaces"
            }
        }
    ]
}
EOF
    
    # Deploy the workbook template
    az resource create \
        --resource-group ${RESOURCE_GROUP} \
        --resource-type "microsoft.insights/workbooks" \
        --name "disaster-recovery-dashboard" \
        --properties @"${SCRIPT_DIR}/dr-workbook-template.json" \
        --location ${PRIMARY_REGION} \
        --tags purpose=monitoring environment=production \
        >> "${LOG_FILE}" 2>&1
    
    success "Disaster Recovery monitoring workbook deployed"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    # Check Recovery Services Vault
    RSV_STATUS=$(az backup vault show \
        --name ${RSV_PRIMARY_NAME} \
        --resource-group ${BACKUP_RESOURCE_GROUP} \
        --query 'name' --output tsv 2>/dev/null || echo "ERROR")
    
    if [ "${RSV_STATUS}" = "ERROR" ]; then
        error_exit "Recovery Services Vault validation failed"
    fi
    
    # Check Log Analytics Workspace
    LAW_STATUS=$(az monitor log-analytics workspace show \
        --workspace-name ${MONITOR_WORKSPACE_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query 'name' --output tsv 2>/dev/null || echo "ERROR")
    
    if [ "${LAW_STATUS}" = "ERROR" ]; then
        error_exit "Log Analytics Workspace validation failed"
    fi
    
    # Check Logic Apps
    LA_STATUS=$(az logic workflow show \
        --name ${LOGIC_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query 'state' --output tsv 2>/dev/null || echo "ERROR")
    
    if [ "${LA_STATUS}" = "ERROR" ]; then
        error_exit "Logic Apps validation failed"
    fi
    
    success "Deployment validation completed successfully"
}

# Main deployment function
main() {
    log "Starting Azure Disaster Recovery deployment..."
    log "Deployment started at: $(date)"
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_groups
    create_recovery_vaults
    setup_monitoring
    create_action_groups
    deploy_logic_apps
    configure_backup_policies
    setup_alert_rules
    configure_cross_region_replication
    create_monitoring_workbook
    validate_deployment
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/logic-app-workflow.json"
    rm -f "${SCRIPT_DIR}/vm-policy.json"
    rm -f "${SCRIPT_DIR}/sql-policy.json"
    rm -f "${SCRIPT_DIR}/dr-workbook-template.json"
    
    log "Deployment completed successfully!"
    log "Deployment finished at: $(date)"
    log ""
    log "=== DEPLOYMENT SUMMARY ==="
    log "Primary Region: ${PRIMARY_REGION}"
    log "Secondary Region: ${SECONDARY_REGION}"
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Backup Resource Group: ${BACKUP_RESOURCE_GROUP}"
    log "Primary Vault: ${RSV_PRIMARY_NAME}"
    log "Secondary Vault: ${RSV_SECONDARY_NAME}"
    log "Logic App: ${LOGIC_APP_NAME}"
    log "Monitor Workspace: ${MONITOR_WORKSPACE_NAME}"
    log "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log ""
    log "Next steps:"
    log "1. Configure backup protection for your resources"
    log "2. Test disaster recovery procedures"
    log "3. Customize alert notifications"
    log "4. Review backup policies and retention settings"
    log ""
    log "For cleanup, run: ./destroy.sh"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi