#!/bin/bash

# =============================================================================
# Azure Autonomous Database Scaling - Deployment Script
# =============================================================================
# Deploys Azure SQL Database Hyperscale with autonomous scaling capabilities
# using Logic Apps and Azure Monitor for intelligent resource management.
#
# Recipe: Implementing Autonomous Database Scaling with Azure SQL Database 
#         Hyperscale and Azure Logic Apps
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_START_TIME=$(date)

# Default values (can be overridden by environment variables)
RESOURCE_GROUP_PREFIX="${RESOURCE_GROUP_PREFIX:-rg-autonomous-scaling}"
LOCATION="${LOCATION:-eastus}"
SQL_ADMIN_USERNAME="${SQL_ADMIN_USERNAME:-sqladmin}"
SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-ComplexP@ssw0rd123!}"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.60.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating random values. Please install OpenSSL."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

confirm_deployment() {
    echo
    log_warning "=== DEPLOYMENT CONFIRMATION ==="
    log_info "This script will deploy the following resources:"
    log_info "  • Resource Group: ${RESOURCE_GROUP}"
    log_info "  • Location: ${LOCATION}"
    log_info "  • SQL Server: ${SQL_SERVER_NAME}"
    log_info "  • Hyperscale Database: ${SQL_DATABASE_NAME}"
    log_info "  • Logic App: ${LOGIC_APP_NAME}"
    log_info "  • Key Vault: ${KEY_VAULT_NAME}"
    log_info "  • Log Analytics: ${LOG_ANALYTICS_NAME}"
    echo
    log_warning "Estimated cost: \$50-100 per month for development/testing"
    echo
    
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_warning "Some resources may have been created. Check the Azure portal and clean up if necessary."
        log_info "You can also run the destroy.sh script to clean up resources."
    fi
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=database-scaling environment=demo \
            >> "${LOG_FILE}" 2>&1
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

create_log_analytics_workspace() {
    log_info "Creating Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
    
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
}

create_key_vault() {
    log_info "Creating Key Vault: ${KEY_VAULT_NAME}"
    
    # Create Key Vault with RBAC authorization
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --enable-rbac-authorization true \
        >> "${LOG_FILE}" 2>&1
    
    # Store database credentials securely
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "sql-admin-username" \
        --value "${SQL_ADMIN_USERNAME}" \
        >> "${LOG_FILE}" 2>&1
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "sql-admin-password" \
        --value "${SQL_ADMIN_PASSWORD}" \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Key Vault created with database credentials stored securely"
}

create_sql_server_and_database() {
    log_info "Creating SQL Server: ${SQL_SERVER_NAME}"
    
    # Create SQL Server
    az sql server create \
        --name "${SQL_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --admin-user "${SQL_ADMIN_USERNAME}" \
        --admin-password "${SQL_ADMIN_PASSWORD}" \
        --enable-public-network true \
        >> "${LOG_FILE}" 2>&1
    
    # Configure firewall to allow Azure services
    az sql server firewall-rule create \
        --resource-group "${RESOURCE_GROUP}" \
        --server "${SQL_SERVER_NAME}" \
        --name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        >> "${LOG_FILE}" 2>&1
    
    log_info "Creating Hyperscale database: ${SQL_DATABASE_NAME}"
    
    # Create Hyperscale database
    az sql db create \
        --resource-group "${RESOURCE_GROUP}" \
        --server "${SQL_SERVER_NAME}" \
        --name "${SQL_DATABASE_NAME}" \
        --service-objective HS_Gen5_2 \
        --edition Hyperscale \
        --family Gen5 \
        --capacity 2 \
        --zone-redundant false \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Hyperscale database created with 2 vCores baseline configuration"
}

create_monitoring_alerts() {
    log_info "Configuring Azure Monitor metrics and alert rules"
    
    # Get SQL Database resource ID
    local db_resource_id=$(az sql db show \
        --resource-group "${RESOURCE_GROUP}" \
        --server "${SQL_SERVER_NAME}" \
        --name "${SQL_DATABASE_NAME}" \
        --query id --output tsv)
    
    # Create action group
    az monitor action-group create \
        --name "${ACTION_GROUP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "ScaleAlert" \
        >> "${LOG_FILE}" 2>&1
    
    # Create CPU scale-up alert rule
    az monitor metrics alert create \
        --name "CPU-Scale-Up-Alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${db_resource_id}" \
        --condition "avg cpu_percent > 80" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action "${ACTION_GROUP_NAME}" \
        --description "Trigger scale-up when CPU exceeds 80% for 5 minutes" \
        >> "${LOG_FILE}" 2>&1
    
    # Create CPU scale-down alert rule
    az monitor metrics alert create \
        --name "CPU-Scale-Down-Alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${db_resource_id}" \
        --condition "avg cpu_percent < 30" \
        --window-size 15m \
        --evaluation-frequency 5m \
        --action "${ACTION_GROUP_NAME}" \
        --description "Trigger scale-down when CPU below 30% for 15 minutes" \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Azure Monitor alerts configured for autonomous scaling triggers"
}

create_logic_app() {
    log_info "Creating Logic Apps workflow: ${LOGIC_APP_NAME}"
    
    # Create initial Logic App with basic definition
    az logic workflow create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${LOGIC_APP_NAME}" \
        --location "${LOCATION}" \
        --definition '{
          "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
          "contentVersion": "1.0.0.0",
          "parameters": {},
          "triggers": {
            "manual": {
              "type": "Request",
              "kind": "Http",
              "inputs": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "alertType": {"type": "string"},
                    "resourceId": {"type": "string"},
                    "metricValue": {"type": "number"}
                  }
                }
              }
            }
          },
          "actions": {
            "Initialize_scaling_logic": {
              "type": "Compose",
              "inputs": {
                "message": "Scaling workflow triggered",
                "timestamp": "@utcnow()"
              }
            }
          },
          "outputs": {}
        }' \
        >> "${LOG_FILE}" 2>&1
    
    # Enable system-assigned managed identity
    az logic workflow identity assign \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${LOGIC_APP_NAME}" \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Logic Apps workflow created with managed identity"
}

configure_scaling_logic() {
    log_info "Configuring comprehensive scaling logic with safety controls"
    
    # Create temporary file for scaling workflow definition
    local workflow_file=$(mktemp)
    
    cat > "${workflow_file}" << EOF
{
  "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroup": {
      "type": "string",
      "defaultValue": "${RESOURCE_GROUP}"
    },
    "serverName": {
      "type": "string", 
      "defaultValue": "${SQL_SERVER_NAME}"
    },
    "databaseName": {
      "type": "string",
      "defaultValue": "${SQL_DATABASE_NAME}"
    }
  },
  "triggers": {
    "When_a_HTTP_request_is_received": {
      "type": "Request",
      "kind": "Http",
      "inputs": {
        "schema": {
          "type": "object",
          "properties": {
            "alertType": {"type": "string"},
            "resourceId": {"type": "string"},
            "metricValue": {"type": "number"}
          }
        }
      }
    }
  },
  "actions": {
    "Get_current_database_configuration": {
      "type": "Http",
      "inputs": {
        "method": "GET",
        "uri": "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/@{parameters('resourceGroup')}/providers/Microsoft.Sql/servers/@{parameters('serverName')}/databases/@{parameters('databaseName')}",
        "queries": {
          "api-version": "2021-11-01"
        },
        "authentication": {
          "type": "ManagedServiceIdentity"
        }
      }
    },
    "Determine_scaling_action": {
      "type": "Switch",
      "expression": "@triggerBody()['alertType']",
      "cases": {
        "scale-up": {
          "case": "CPU-Scale-Up-Alert",
          "actions": {
            "Calculate_new_capacity": {
              "type": "Compose",
              "inputs": "@min(add(int(body('Get_current_database_configuration')['properties']['currentSku']['capacity']), 2), 40)"
            },
            "Scale_up_database": {
              "type": "Http",
              "inputs": {
                "method": "PATCH",
                "uri": "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/@{parameters('resourceGroup')}/providers/Microsoft.Sql/servers/@{parameters('serverName')}/databases/@{parameters('databaseName')}",
                "queries": {
                  "api-version": "2021-11-01"
                },
                "body": {
                  "properties": {
                    "requestedServiceObjectiveName": "@concat('HS_Gen5_', outputs('Calculate_new_capacity'))"
                  }
                },
                "authentication": {
                  "type": "ManagedServiceIdentity"
                }
              }
            }
          }
        },
        "scale-down": {
          "case": "CPU-Scale-Down-Alert", 
          "actions": {
            "Calculate_reduced_capacity": {
              "type": "Compose",
              "inputs": "@max(sub(int(body('Get_current_database_configuration')['properties']['currentSku']['capacity']), 2), 2)"
            },
            "Scale_down_database": {
              "type": "Http",
              "inputs": {
                "method": "PATCH",
                "uri": "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/@{parameters('resourceGroup')}/providers/Microsoft.Sql/servers/@{parameters('serverName')}/databases/@{parameters('databaseName')}",
                "queries": {
                  "api-version": "2021-11-01"
                },
                "body": {
                  "properties": {
                    "requestedServiceObjectiveName": "@concat('HS_Gen5_', outputs('Calculate_reduced_capacity'))"
                  }
                },
                "authentication": {
                  "type": "ManagedServiceIdentity"
                }
              }
            }
          }
        }
      }
    },
    "Log_scaling_operation": {
      "type": "Compose",
      "inputs": {
        "timestamp": "@utcnow()",
        "alertType": "@triggerBody()['alertType']",
        "metricValue": "@triggerBody()['metricValue']",
        "scalingAction": "completed"
      }
    }
  }
}
EOF
    
    # Update Logic App with scaling workflow
    az logic workflow update \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${LOGIC_APP_NAME}" \
        --definition "@${workflow_file}" \
        >> "${LOG_FILE}" 2>&1
    
    # Clean up temporary file
    rm -f "${workflow_file}"
    
    log_success "Comprehensive scaling logic implemented with safety controls and logging"
}

configure_rbac_permissions() {
    log_info "Configuring RBAC permissions for autonomous operations"
    
    # Get Logic App managed identity
    local logic_app_principal_id=$(az logic workflow identity show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${LOGIC_APP_NAME}" \
        --query principalId --output tsv)
    
    # Grant SQL DB Contributor role for database scaling
    az role assignment create \
        --assignee "${logic_app_principal_id}" \
        --role "SQL DB Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        >> "${LOG_FILE}" 2>&1
    
    # Grant Key Vault Secrets User role
    az role assignment create \
        --assignee "${logic_app_principal_id}" \
        --role "Key Vault Secrets User" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        >> "${LOG_FILE}" 2>&1
    
    # Grant Log Analytics Contributor for logging
    az role assignment create \
        --assignee "${logic_app_principal_id}" \
        --role "Log Analytics Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_NAME}" \
        >> "${LOG_FILE}" 2>&1
    
    log_success "RBAC permissions configured for autonomous scaling operations"
}

connect_alerts_to_logic_app() {
    log_info "Connecting Monitor alerts to Logic Apps scaling workflow"
    
    # Get Logic App trigger URL
    local logic_app_trigger_url=$(az logic workflow trigger list-callback-url \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${LOGIC_APP_NAME}" \
        --trigger-name "When_a_HTTP_request_is_received" \
        --query value --output tsv)
    
    # Update action group with Logic App webhook
    az monitor action-group update \
        --name "${ACTION_GROUP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --add-action webhook \
            name="TriggerScaling" \
            service-uri="${logic_app_trigger_url}" \
            use-common-alert-schema=true \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Autonomous scaling pipeline activated - alerts connected to Logic Apps workflow"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log_info "Starting Azure Autonomous Database Scaling deployment"
    log_info "Deployment started at: ${DEPLOYMENT_START_TIME}"
    
    # Set trap for cleanup on error
    trap cleanup_on_error EXIT
    
    # Generate unique suffix for resource names
    local random_suffix=$(openssl rand -hex 3)
    
    # Set environment variables for resource names
    export RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${random_suffix}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export SQL_SERVER_NAME="sql-hyperscale-${random_suffix}"
    export SQL_DATABASE_NAME="hyperscale-db"
    export LOGIC_APP_NAME="scaling-logic-app-${random_suffix}"
    export KEY_VAULT_NAME="kv-scaling-${random_suffix}"
    export LOG_ANALYTICS_NAME="la-scaling-${random_suffix}"
    export ACTION_GROUP_NAME="ag-scaling-${random_suffix}"
    
    # Run prerequisite checks
    check_prerequisites
    
    # Confirm deployment with user
    confirm_deployment
    
    # Start deployment
    log_info "Beginning resource deployment..."
    
    # Step 1: Create foundational resources
    create_resource_group
    create_log_analytics_workspace
    
    # Step 2: Create security infrastructure
    create_key_vault
    
    # Step 3: Create database infrastructure
    create_sql_server_and_database
    
    # Step 4: Configure monitoring and alerts
    create_monitoring_alerts
    
    # Step 5: Create Logic Apps workflow
    create_logic_app
    
    # Step 6: Configure scaling logic
    configure_scaling_logic
    
    # Step 7: Configure permissions
    configure_rbac_permissions
    
    # Step 8: Connect alerts to Logic App
    connect_alerts_to_logic_app
    
    # Remove error trap since deployment completed successfully
    trap - EXIT
    
    # Display deployment summary
    echo
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    log_success "Deployment completed at: $(date)"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "SQL Server: ${SQL_SERVER_NAME}"
    log_info "Database: ${SQL_DATABASE_NAME}"
    log_info "Logic App: ${LOGIC_APP_NAME}"
    log_info "Key Vault: ${KEY_VAULT_NAME}"
    echo
    log_info "You can now test the autonomous scaling system by:"
    log_info "1. Connecting to the database and running CPU-intensive queries"
    log_info "2. Monitoring the scaling actions in the Logic App run history"
    log_info "3. Checking Azure Monitor alerts and metrics"
    echo
    log_info "Deployment logs saved to: ${LOG_FILE}"
    log_warning "Remember to run destroy.sh when finished to avoid ongoing charges"
}

# =============================================================================
# Script Execution
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi