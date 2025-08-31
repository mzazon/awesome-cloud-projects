#!/bin/bash

# =============================================================================
# Azure Automated Content Moderation with Content Safety and Logic Apps
# Deployment Script
# =============================================================================
# This script deploys Azure resources for automated content moderation using
# Azure AI Content Safety and Logic Apps workflow orchestration.
#
# Prerequisites:
# - Azure CLI installed and logged in
# - Appropriate Azure subscription permissions
# - bash shell environment
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION AND VARIABLES
# =============================================================================

# Script metadata
readonly SCRIPT_NAME="deploy.sh"
readonly SCRIPT_VERSION="1.0"
readonly DEPLOYMENT_NAME="azure-content-moderation"

# Logging configuration
readonly LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Default Azure configuration
readonly DEFAULT_LOCATION="eastus"
readonly DEFAULT_SKU="S0"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Check log file: $LOG_FILE"
        log_info "Run './destroy.sh' to clean up any partially created resources"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

prompt_for_config() {
    log_info "Configuration setup..."
    
    # Get current subscription info
    local current_subscription=$(az account show --query name -o tsv 2>/dev/null || echo "Not available")
    log_info "Current Azure subscription: $current_subscription"
    
    # Prompt for location
    read -p "Enter Azure region (default: $DEFAULT_LOCATION): " user_location
    export LOCATION="${user_location:-$DEFAULT_LOCATION}"
    
    # Generate unique suffix
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export RESOURCE_GROUP="rg-content-moderation-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stcontentmod${RANDOM_SUFFIX}"
    export CONTENT_SAFETY_NAME="cs-content-safety-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-content-workflow-${RANDOM_SUFFIX}"
    export CONTAINER_NAME="content-uploads"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_info "Configuration:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Content Safety: $CONTENT_SAFETY_NAME"
    log_info "  Logic App: $LOGIC_APP_NAME"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
    
    # Confirm deployment
    echo
    read -p "Continue with deployment? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local sleep_interval="${4:-10}"
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if check_resource_ready "$resource_type" "$resource_name"; then
            log_success "$resource_type '$resource_name' is ready"
            return 0
        fi
        
        log_info "Attempt $i/$max_attempts - waiting ${sleep_interval}s..."
        sleep "$sleep_interval"
    done
    
    log_error "$resource_type '$resource_name' failed to become ready within expected time"
    return 1
}

check_resource_ready() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "cognitive-service")
            az cognitiveservices account show \
                --name "$resource_name" \
                --resource-group "$RESOURCE_GROUP" \
                --query "properties.provisioningState" \
                --output tsv 2>/dev/null | grep -q "Succeeded"
            ;;
        "storage-account")
            az storage account show \
                --name "$resource_name" \
                --resource-group "$RESOURCE_GROUP" \
                --query "provisioningState" \
                --output tsv 2>/dev/null | grep -q "Succeeded"
            ;;
        "logic-app")
            az logic workflow show \
                --resource-group "$RESOURCE_GROUP" \
                --name "$resource_name" \
                --query "state" \
                --output tsv 2>/dev/null | grep -q "Enabled"
            ;;
        *)
            log_warning "Unknown resource type for readiness check: $resource_type"
            return 1
            ;;
    esac
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=content-moderation environment=demo deployment-script="$SCRIPT_NAME" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log_success "Resource group created: $RESOURCE_GROUP"
        
        # Store resource group info for cleanup
        echo "RESOURCE_GROUP=\"$RESOURCE_GROUP\"" > .deployment_state
        echo "LOCATION=\"$LOCATION\"" >> .deployment_state
        echo "RANDOM_SUFFIX=\"$RANDOM_SUFFIX\"" >> .deployment_state
    else
        log_error "Failed to create resource group"
        exit 1
    fi
}

create_content_safety_service() {
    log_info "Creating Azure AI Content Safety service: $CONTENT_SAFETY_NAME"
    
    # Check if resource already exists
    if az cognitiveservices account show --name "$CONTENT_SAFETY_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Content Safety service '$CONTENT_SAFETY_NAME' already exists"
    else
        az cognitiveservices account create \
            --name "$CONTENT_SAFETY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind ContentSafety \
            --sku "$DEFAULT_SKU" \
            --custom-domain "$CONTENT_SAFETY_NAME" \
            --tags purpose=content-moderation deployment-script="$SCRIPT_NAME" \
            --output none
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create Content Safety service"
            exit 1
        fi
    fi
    
    # Wait for service to be ready
    wait_for_resource "cognitive-service" "$CONTENT_SAFETY_NAME"
    
    # Get endpoint and key
    export CONTENT_SAFETY_ENDPOINT=$(az cognitiveservices account show \
        --name "$CONTENT_SAFETY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint \
        --output tsv)
    
    export CONTENT_SAFETY_KEY=$(az cognitiveservices account keys list \
        --name "$CONTENT_SAFETY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv)
    
    if [[ -z "$CONTENT_SAFETY_ENDPOINT" || -z "$CONTENT_SAFETY_KEY" ]]; then
        log_error "Failed to retrieve Content Safety endpoint or key"
        exit 1
    fi
    
    log_success "Content Safety service created with endpoint: $CONTENT_SAFETY_ENDPOINT"
    
    # Store in deployment state
    echo "CONTENT_SAFETY_NAME=\"$CONTENT_SAFETY_NAME\"" >> .deployment_state
    echo "CONTENT_SAFETY_ENDPOINT=\"$CONTENT_SAFETY_ENDPOINT\"" >> .deployment_state
}

create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Storage account '$STORAGE_ACCOUNT' already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --allow-blob-public-access false \
            --tags purpose=content-storage deployment-script="$SCRIPT_NAME" \
            --output none
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create storage account"
            exit 1
        fi
    fi
    
    # Wait for storage account to be ready
    wait_for_resource "storage-account" "$STORAGE_ACCOUNT"
    
    # Create container
    log_info "Creating storage container: $CONTAINER_NAME"
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --public-access off \
        --auth-mode login \
        --output none
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create storage container"
        exit 1
    fi
    
    # Get connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    if [[ -z "$STORAGE_CONNECTION_STRING" ]]; then
        log_error "Failed to retrieve storage connection string"
        exit 1
    fi
    
    log_success "Storage account and container created: $STORAGE_ACCOUNT"
    
    # Store in deployment state
    echo "STORAGE_ACCOUNT=\"$STORAGE_ACCOUNT\"" >> .deployment_state
    echo "CONTAINER_NAME=\"$CONTAINER_NAME\"" >> .deployment_state
}

create_logic_app() {
    log_info "Creating Logic App: $LOGIC_APP_NAME"
    
    # Create initial workflow definition
    cat > initial-workflow.json << 'EOF'
{
  "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},
  "triggers": {},
  "actions": {},
  "outputs": {}
}
EOF
    
    # Check if Logic App already exists
    if az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" &>/dev/null; then
        log_warning "Logic App '$LOGIC_APP_NAME' already exists"
    else
        az logic workflow create \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --name "$LOGIC_APP_NAME" \
            --definition @initial-workflow.json \
            --tags purpose=content-moderation-workflow deployment-script="$SCRIPT_NAME" \
            --output none
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create Logic App"
            exit 1
        fi
    fi
    
    # Get Logic App resource ID
    export LOGIC_APP_RESOURCE_ID=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query id \
        --output tsv)
    
    log_success "Logic App created: $LOGIC_APP_NAME"
    
    # Store in deployment state
    echo "LOGIC_APP_NAME=\"$LOGIC_APP_NAME\"" >> .deployment_state
}

create_storage_connection() {
    log_info "Creating storage connection for Logic App"
    
    # Check if connection already exists
    if az resource show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name azureblob-connection &>/dev/null; then
        log_warning "Storage connection 'azureblob-connection' already exists"
    else
        az resource create \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type Microsoft.Web/connections \
            --name azureblob-connection \
            --location "$LOCATION" \
            --properties "{
              \"displayName\": \"Azure Blob Storage Connection\",
              \"api\": {
                \"id\": \"/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Web/locations/${LOCATION}/managedApis/azureblob\"
              },
              \"parameterValues\": {
                \"connectionString\": \"${STORAGE_CONNECTION_STRING}\"
              }
            }" \
            --tags purpose=logic-app-connector deployment-script="$SCRIPT_NAME" \
            --output none
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create storage connection"
            exit 1
        fi
    fi
    
    # Get connection resource ID
    export BLOB_CONNECTION_ID=$(az resource show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name azureblob-connection \
        --query id \
        --output tsv)
    
    log_success "Storage connection created for Logic App"
}

configure_workflow() {
    log_info "Configuring Logic App workflow with content moderation logic"
    
    # Create comprehensive workflow definition
    cat > content-moderation-workflow.json << EOF
{
  "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "\$connections": {
      "defaultValue": {},
      "type": "Object"
    }
  },
  "triggers": {
    "When_a_blob_is_added_or_modified": {
      "recurrence": {
        "frequency": "Minute",
        "interval": 1
      },
      "splitOn": "@triggerBody()",
      "type": "ApiConnection",
      "inputs": {
        "host": {
          "connection": {
            "name": "@parameters('\$connections')['azureblob']['connectionId']"
          }
        },
        "method": "get",
        "path": "/datasets/default/triggers/batch/onupdatedfile",
        "queries": {
          "folderId": "${CONTAINER_NAME}",
          "maxFileCount": 10
        }
      }
    }
  },
  "actions": {
    "Get_blob_content": {
      "runAfter": {},
      "type": "ApiConnection",
      "inputs": {
        "host": {
          "connection": {
            "name": "@parameters('\$connections')['azureblob']['connectionId']"
          }
        },
        "method": "get",
        "path": "/datasets/default/files/@{encodeURIComponent(encodeURIComponent(triggerBody()?['Path']))}/content",
        "queries": {
          "inferContentType": true
        }
      }
    },
    "Analyze_content_with_AI": {
      "runAfter": {
        "Get_blob_content": [
          "Succeeded"
        ]
      },
      "type": "Http",
      "inputs": {
        "body": {
          "text": "@{base64ToString(body('Get_blob_content')?\\\$content)}",
          "outputType": "FourSeverityLevels"
        },
        "headers": {
          "Content-Type": "application/json",
          "Ocp-Apim-Subscription-Key": "${CONTENT_SAFETY_KEY}"
        },
        "method": "POST",
        "uri": "${CONTENT_SAFETY_ENDPOINT}/contentsafety/text:analyze?api-version=2024-09-01"
      }
    },
    "Process_moderation_results": {
      "runAfter": {
        "Analyze_content_with_AI": [
          "Succeeded"
        ]
      },
      "cases": {
        "Low_Risk_Auto_Approve": {
          "case": 0,
          "actions": {
            "Log_approval": {
              "type": "Compose",
              "inputs": {
                "message": "Content approved automatically",
                "file": "@triggerBody()?['Name']",
                "timestamp": "@utcnow()",
                "moderationResult": "@body('Analyze_content_with_AI')",
                "decision": "approved"
              }
            }
          }
        },
        "Medium_Risk_Needs_Review": {
          "case": 2,
          "actions": {
            "Flag_for_review": {
              "type": "Compose",
              "inputs": {
                "message": "Content flagged for human review",
                "file": "@triggerBody()?['Name']",
                "timestamp": "@utcnow()",
                "moderationResult": "@body('Analyze_content_with_AI')",
                "decision": "review_needed"
              }
            }
          }
        },
        "High_Risk_Auto_Reject": {
          "case": 4,
          "actions": {
            "Log_rejection": {
              "type": "Compose",
              "inputs": {
                "message": "Content rejected automatically",
                "file": "@triggerBody()?['Name']",
                "timestamp": "@utcnow()",
                "moderationResult": "@body('Analyze_content_with_AI')",
                "decision": "rejected"
              }
            }
          }
        }
      },
      "default": {
        "actions": {
          "Flag_for_review_high": {
            "type": "Compose",
            "inputs": {
              "message": "Content flagged for urgent human review",
              "file": "@triggerBody()?['Name']",
              "timestamp": "@utcnow()",
              "moderationResult": "@body('Analyze_content_with_AI')",
              "decision": "urgent_review"
            }
          }
        }
      },
      "expression": "@max(body('Analyze_content_with_AI')?['categoriesAnalysis']?[0]?['severity'], body('Analyze_content_with_AI')?['categoriesAnalysis']?[1]?['severity'], body('Analyze_content_with_AI')?['categoriesAnalysis']?[2]?['severity'], body('Analyze_content_with_AI')?['categoriesAnalysis']?[3]?['severity'])",
      "type": "Switch"
    }
  }
}
EOF
    
    # Update Logic App with workflow and connections
    az logic workflow update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --definition @content-moderation-workflow.json \
        --connections azureblob="$BLOB_CONNECTION_ID" \
        --output none
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to update Logic App workflow"
        exit 1
    fi
    
    # Enable the Logic App
    az logic workflow update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --state Enabled \
        --output none
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to enable Logic App workflow"
        exit 1
    fi
    
    # Wait for Logic App to be ready
    wait_for_resource "logic-app" "$LOGIC_APP_NAME"
    
    log_success "Logic App workflow configured and enabled"
    
    # Clean up temporary files
    rm -f initial-workflow.json content-moderation-workflow.json
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    # Test Content Safety API
    log_info "Testing Content Safety API connectivity..."
    local test_response=$(curl -s -X POST "${CONTENT_SAFETY_ENDPOINT}/contentsafety/text:analyze?api-version=2024-09-01" \
        -H "Ocp-Apim-Subscription-Key: ${CONTENT_SAFETY_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
          "text": "This is a test message for content safety validation.",
          "outputType": "FourSeverityLevels"
        }' || echo "")
    
    if [[ -n "$test_response" ]] && echo "$test_response" | grep -q "categoriesAnalysis"; then
        log_success "Content Safety API is responding correctly"
    else
        log_warning "Content Safety API test failed or returned unexpected response"
    fi
    
    # Verify storage container
    log_info "Verifying storage container..."
    if az storage container show \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login &>/dev/null; then
        log_success "Storage container is accessible"
    else
        log_warning "Storage container verification failed"
    fi
    
    # Check Logic App status
    log_info "Checking Logic App status..."
    local logic_app_state=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query "state" \
        --output tsv)
    
    if [[ "$logic_app_state" == "Enabled" ]]; then
        log_success "Logic App is enabled and ready"
    else
        log_warning "Logic App state is: $logic_app_state"
    fi
    
    log_success "Deployment validation completed"
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

main() {
    log_info "Starting Azure Content Moderation deployment"
    log_info "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Timestamp: $(date)"
    
    # Check prerequisites
    check_prerequisites
    
    # Get configuration
    prompt_for_config
    
    # Deploy resources
    log_info "Starting resource deployment..."
    
    create_resource_group
    create_content_safety_service
    create_storage_account
    create_logic_app
    create_storage_connection
    configure_workflow
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    log_success "Deployment completed successfully!"
    log_info ""
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Content Safety Service: $CONTENT_SAFETY_NAME"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Logic App: $LOGIC_APP_NAME"
    log_info "Container: $CONTAINER_NAME"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Upload test content to the storage container to trigger the workflow"
    log_info "2. Monitor Logic App runs in the Azure portal"
    log_info "3. Review content moderation results in the workflow execution history"
    log_info ""
    log_info "To test the system:"
    log_info "  az storage blob upload --file your-test-file.txt --name test-content.txt \\"
    log_info "    --container-name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT --auth-mode login"
    log_info ""
    log_info "To clean up resources:"
    log_info "  ./destroy.sh"
    log_info ""
    log_info "Log file: $LOG_FILE"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi