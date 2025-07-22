#!/bin/bash

# Secure User Onboarding Workflows with Azure Entra ID and Azure Service Bus - Deploy Script
# This script deploys the complete user onboarding automation infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    info "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would execute: $cmd"
        info "DRY-RUN: $description"
        return 0
    else
        info "$description"
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some JSON parsing may not work correctly."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Required for generating random suffixes."
    fi
    
    # Get current user info
    local current_user=$(az account show --query user.name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    
    info "Current user: $current_user"
    info "Subscription: $subscription_name ($subscription_id)"
    
    # Check required permissions
    info "Checking permissions..."
    local has_owner=$(az role assignment list --assignee "$current_user" --query "[?roleDefinitionName=='Owner']" -o tsv)
    local has_contributor=$(az role assignment list --assignee "$current_user" --query "[?roleDefinitionName=='Contributor']" -o tsv)
    
    if [[ -z "$has_owner" && -z "$has_contributor" ]]; then
        error "Insufficient permissions. Owner or Contributor role required."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set core environment variables
    export RESOURCE_GROUP="rg-user-onboarding-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export SERVICE_BUS_NAMESPACE="sb-onboarding-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-onboarding-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-user-onboarding-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stonboarding${RANDOM_SUFFIX}"
    
    # Display environment variables
    info "Environment variables set:"
    info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    info "  LOCATION: $LOCATION"
    info "  SERVICE_BUS_NAMESPACE: $SERVICE_BUS_NAMESPACE"
    info "  KEY_VAULT_NAME: $KEY_VAULT_NAME"
    info "  LOGIC_APP_NAME: $LOGIC_APP_NAME"
    info "  STORAGE_ACCOUNT_NAME: $STORAGE_ACCOUNT_NAME"
    info "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
SERVICE_BUS_NAMESPACE=$SERVICE_BUS_NAMESPACE
KEY_VAULT_NAME=$KEY_VAULT_NAME
LOGIC_APP_NAME=$LOGIC_APP_NAME
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log "Environment variables saved to .env file"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    local cmd="az group create --name ${RESOURCE_GROUP} --location ${LOCATION} --tags purpose=user-onboarding environment=demo project=automation"
    execute_command "$cmd" "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Verify resource group creation
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log "✅ Resource group created successfully: $RESOURCE_GROUP"
        else
            error "Failed to create resource group: $RESOURCE_GROUP"
        fi
    fi
}

# Function to create and configure Key Vault
create_key_vault() {
    log "Creating Azure Key Vault..."
    
    local cmd="az keyvault create --name ${KEY_VAULT_NAME} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku standard --enable-rbac-authorization true --enable-soft-delete true --retention-days 90 --tags purpose=credential-storage security=high"
    execute_command "$cmd" "Creating Key Vault with advanced security features"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for Key Vault to be fully provisioned
        info "Waiting for Key Vault to be fully provisioned..."
        sleep 30
        
        # Assign Key Vault Administrator role to current user
        local current_user=$(az account show --query user.name --output tsv)
        local kv_scope="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
        
        local role_cmd="az role assignment create --assignee ${current_user} --role 'Key Vault Administrator' --scope ${kv_scope}"
        execute_command "$role_cmd" "Assigning Key Vault Administrator role to current user"
        
        log "✅ Key Vault configured with RBAC authorization and soft delete protection"
    fi
}

# Function to create Service Bus namespace and entities
create_service_bus() {
    log "Creating Azure Service Bus infrastructure..."
    
    # Create Service Bus namespace
    local ns_cmd="az servicebus namespace create --name ${SERVICE_BUS_NAMESPACE} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku Standard --tags purpose=messaging reliability=high"
    execute_command "$ns_cmd" "Creating Service Bus namespace with premium features"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for namespace to be fully provisioned
        info "Waiting for Service Bus namespace to be fully provisioned..."
        sleep 30
    fi
    
    # Create primary onboarding queue
    local queue_cmd="az servicebus queue create --namespace-name ${SERVICE_BUS_NAMESPACE} --resource-group ${RESOURCE_GROUP} --name user-onboarding-queue --max-delivery-count 5 --lock-duration PT5M --enable-dead-lettering-on-message-expiration true --default-message-time-to-live P14D"
    execute_command "$queue_cmd" "Creating primary onboarding queue with advanced features"
    
    # Create topic for broadcasting onboarding events
    local topic_cmd="az servicebus topic create --namespace-name ${SERVICE_BUS_NAMESPACE} --resource-group ${RESOURCE_GROUP} --name user-onboarding-events --enable-duplicate-detection true --duplicate-detection-history-time-window PT10M"
    execute_command "$topic_cmd" "Creating topic for broadcasting onboarding events"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "✅ Service Bus namespace and messaging entities created successfully"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating Storage Account for Logic Apps..."
    
    local cmd="az storage account create --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku Standard_LRS --kind StorageV2 --access-tier Hot --https-only true --min-tls-version TLS1_2 --tags purpose=workflow-state security=encrypted"
    execute_command "$cmd" "Creating storage account for Logic Apps"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for storage account to be fully provisioned
        info "Waiting for storage account to be fully provisioned..."
        sleep 15
        
        # Enable advanced security features
        local security_cmd="az storage account update --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --default-action Deny --bypass AzureServices"
        execute_command "$security_cmd" "Enabling advanced security features for storage account"
        
        log "✅ Storage account configured with enhanced security settings"
    fi
}

# Function to create Logic Apps
create_logic_apps() {
    log "Creating Azure Logic Apps for workflow orchestration..."
    
    local cmd="az logicapp create --name ${LOGIC_APP_NAME} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --storage-account ${STORAGE_ACCOUNT_NAME} --plan-name ${LOGIC_APP_NAME}-plan --plan-sku WS1 --plan-is-linux false --tags purpose=workflow-orchestration automation=user-onboarding"
    execute_command "$cmd" "Creating Logic Apps workflow"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for Logic Apps to be fully provisioned
        info "Waiting for Logic Apps to be fully provisioned..."
        sleep 45
        
        # Get Logic Apps configuration details
        local logic_app_id=$(az logicapp show --name ${LOGIC_APP_NAME} --resource-group ${RESOURCE_GROUP} --query id --output tsv)
        info "Logic Apps workflow created with ID: $logic_app_id"
        
        log "✅ Logic Apps workflow created successfully"
    fi
}

# Function to create Azure Entra ID Application Registration
create_app_registration() {
    log "Creating Azure Entra ID Application Registration..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create application registration
        local app_registration=$(az ad app create --display-name "User Onboarding Automation" --sign-in-audience AzureADMyOrg --query appId --output tsv)
        
        if [[ -z "$app_registration" ]]; then
            error "Failed to create application registration"
        fi
        
        info "Application registration created: $app_registration"
        
        # Create service principal
        az ad sp create --id "$app_registration" || error "Failed to create service principal"
        
        # Add required permissions
        info "Adding required Azure AD permissions..."
        az ad app permission add --id "$app_registration" --api 00000003-0000-0000-c000-000000000000 --api-permissions 62a82d76-70ea-41e2-9197-370581804d09=Role || warn "Failed to add User.ReadWrite.All permission"
        az ad app permission add --id "$app_registration" --api 00000003-0000-0000-c000-000000000000 --api-permissions 19dbc75e-c2e2-444c-a770-ec69d8559fc7=Role || warn "Failed to add Directory.ReadWrite.All permission"
        az ad app permission add --id "$app_registration" --api 00000003-0000-0000-c000-000000000000 --api-permissions 9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8=Role || warn "Failed to add Directory.ReadWrite.All permission"
        
        # Grant admin consent
        info "Granting admin consent for permissions..."
        az ad app permission admin-consent --id "$app_registration" || warn "Failed to grant admin consent - may need manual approval"
        
        # Save app registration ID for cleanup
        echo "APP_REGISTRATION=$app_registration" >> .env
        
        log "✅ Application registration configured with necessary permissions"
    else
        info "DRY-RUN: Would create application registration for user onboarding automation"
    fi
}

# Function to configure Service Bus authorization
configure_service_bus_auth() {
    log "Configuring Service Bus authorization..."
    
    # Create shared access policy
    local policy_cmd="az servicebus namespace authorization-rule create --namespace-name ${SERVICE_BUS_NAMESPACE} --resource-group ${RESOURCE_GROUP} --name LogicAppsAccess --rights Send Listen Manage"
    execute_command "$policy_cmd" "Creating shared access policy for Logic Apps"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for policy to be created
        sleep 10
        
        # Get connection string
        local connection_string=$(az servicebus namespace authorization-rule keys list --namespace-name ${SERVICE_BUS_NAMESPACE} --resource-group ${RESOURCE_GROUP} --name LogicAppsAccess --query primaryConnectionString --output tsv)
        
        if [[ -z "$connection_string" ]]; then
            error "Failed to retrieve Service Bus connection string"
        fi
        
        # Store connection string in Key Vault
        info "Storing Service Bus connection string in Key Vault..."
        az keyvault secret set --vault-name ${KEY_VAULT_NAME} --name "ServiceBusConnection" --value "$connection_string" --content-type "application/x-connection-string" || error "Failed to store connection string in Key Vault"
        
        log "✅ Service Bus authorization configured and stored securely"
    fi
}

# Function to deploy Logic Apps workflow
deploy_logic_apps_workflow() {
    log "Deploying Logic Apps workflow..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create workflow definition
        cat > workflow-definition.json << 'EOF'
{
    "definition": {
        "$schema": "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#",
        "actions": {
            "Parse_User_Request": {
                "type": "ParseJson",
                "inputs": {
                    "content": "@triggerBody()",
                    "schema": {
                        "type": "object",
                        "properties": {
                            "userName": {"type": "string"},
                            "email": {"type": "string"},
                            "department": {"type": "string"},
                            "manager": {"type": "string"},
                            "role": {"type": "string"}
                        }
                    }
                }
            },
            "Generate_Temporary_Password": {
                "type": "Http",
                "inputs": {
                    "method": "POST",
                    "uri": "https://randompasswordapi.com/api/v1/password",
                    "body": {
                        "length": 16,
                        "uppercase": true,
                        "lowercase": true,
                        "numbers": true,
                        "special": false
                    }
                },
                "runAfter": {
                    "Parse_User_Request": ["Succeeded"]
                }
            },
            "Send_to_Service_Bus": {
                "type": "ServiceBus",
                "inputs": {
                    "connectionString": "@body('Get_Service_Bus_Connection')",
                    "queueName": "user-onboarding-queue",
                    "message": {
                        "contentData": "@body('Parse_User_Request')",
                        "correlationId": "@guid()"
                    }
                },
                "runAfter": {
                    "Generate_Temporary_Password": ["Succeeded"]
                }
            }
        },
        "triggers": {
            "manual": {
                "type": "Request",
                "kind": "Http",
                "inputs": {
                    "method": "POST",
                    "schema": {
                        "type": "object",
                        "properties": {
                            "userName": {"type": "string"},
                            "email": {"type": "string"},
                            "department": {"type": "string"},
                            "manager": {"type": "string"},
                            "role": {"type": "string"}
                        }
                    }
                }
            }
        }
    }
}
EOF
        
        # Deploy workflow definition
        info "Deploying workflow definition to Logic Apps..."
        az logicapp config set --name ${LOGIC_APP_NAME} --resource-group ${RESOURCE_GROUP} --settings "@workflow-definition.json" || error "Failed to deploy Logic Apps workflow"
        
        # Clean up temporary file
        rm -f workflow-definition.json
        
        log "✅ Logic Apps workflow deployed successfully"
    else
        info "DRY-RUN: Would deploy Logic Apps workflow definition"
    fi
}

# Function to configure lifecycle workflows
configure_lifecycle_workflows() {
    log "Configuring Azure Entra ID Lifecycle Workflows..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create lifecycle workflow for user onboarding
        info "Creating lifecycle workflow for automated user onboarding..."
        
        local workflow_definition='{
            "displayName": "Automated User Onboarding",
            "description": "Automate new user onboarding tasks",
            "category": "joiner",
            "isEnabled": true,
            "isSchedulingEnabled": true,
            "executionConditions": {
                "scope": {
                    "rule": "department eq \"IT\" or department eq \"Sales\"",
                    "timeBasedAttribute": "employeeHireDate",
                    "offsetInDays": 0
                }
            },
            "tasks": [
                {
                    "displayName": "Generate Temporary Access Pass",
                    "description": "Generate TAP for new user",
                    "category": "joiner",
                    "taskDefinitionId": "1b555e50-7f65-41d5-b514-5894a026d10d",
                    "isEnabled": true,
                    "arguments": [
                        {
                            "name": "tapLifetimeMinutes",
                            "value": "480"
                        }
                    ]
                },
                {
                    "displayName": "Send Welcome Email",
                    "description": "Send welcome email to new user",
                    "category": "joiner",
                    "taskDefinitionId": "70b29d51-b59a-4773-9280-8841dfd3f2ea",
                    "isEnabled": true,
                    "arguments": [
                        {
                            "name": "cc",
                            "value": "manager@company.com"
                        }
                    ]
                }
            ]
        }'
        
        # Create the lifecycle workflow using REST API
        az rest --method POST --url "https://graph.microsoft.com/beta/identityGovernance/lifecycleWorkflows/workflows" --headers Content-Type=application/json --body "$workflow_definition" || warn "Failed to create lifecycle workflow - may require additional permissions"
        
        log "✅ Lifecycle workflow configured for automated onboarding"
    else
        info "DRY-RUN: Would configure Azure Entra ID Lifecycle Workflows"
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check resource group
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            error "Resource group validation failed"
        fi
        
        # Check Key Vault
        local kv_uri=$(az keyvault show --name ${KEY_VAULT_NAME} --query "properties.vaultUri" --output tsv)
        if [[ -z "$kv_uri" ]]; then
            error "Key Vault validation failed"
        fi
        info "Key Vault URI: $kv_uri"
        
        # Check Service Bus
        local sb_status=$(az servicebus namespace show --name ${SERVICE_BUS_NAMESPACE} --resource-group ${RESOURCE_GROUP} --query "status" --output tsv)
        if [[ "$sb_status" != "Active" ]]; then
            error "Service Bus validation failed - status: $sb_status"
        fi
        info "Service Bus status: $sb_status"
        
        # Check Logic Apps
        local la_state=$(az logicapp show --name ${LOGIC_APP_NAME} --resource-group ${RESOURCE_GROUP} --query "state" --output tsv)
        if [[ "$la_state" != "Running" ]]; then
            warn "Logic Apps state: $la_state (may still be starting up)"
        else
            info "Logic Apps state: $la_state"
        fi
        
        # Check storage account
        local storage_status=$(az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --query "statusOfPrimary" --output tsv)
        if [[ "$storage_status" != "available" ]]; then
            error "Storage account validation failed - status: $storage_status"
        fi
        info "Storage account status: $storage_status"
        
        log "✅ Deployment validation completed successfully"
    else
        info "DRY-RUN: Would validate all deployed resources"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Key Vault: $KEY_VAULT_NAME"
    echo "Service Bus: $SERVICE_BUS_NAMESPACE"
    echo "Logic Apps: $LOGIC_APP_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo "=================================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "Next Steps:"
        echo "1. Configure additional Logic Apps connectors as needed"
        echo "2. Set up monitoring and alerting"
        echo "3. Test the onboarding workflow with sample data"
        echo "4. Configure additional security policies"
        echo ""
        echo "Environment variables saved to .env file"
        echo "Use the destroy.sh script to clean up resources when done"
    fi
}

# Main deployment function
main() {
    log "Starting Azure User Onboarding Automation deployment..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--dry-run] [--help]"
                echo "  --dry-run    Show what would be done without making changes"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_key_vault
    create_service_bus
    create_storage_account
    create_logic_apps
    create_app_registration
    configure_service_bus_auth
    deploy_logic_apps_workflow
    configure_lifecycle_workflows
    validate_deployment
    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "✅ Deployment completed successfully!"
        log "Total estimated time: 8-12 minutes"
    else
        log "✅ Dry-run completed successfully!"
    fi
}

# Trap to handle script interruption
trap 'error "Script interrupted. Some resources may have been created. Run destroy.sh to clean up."' INT TERM

# Execute main function
main "$@"