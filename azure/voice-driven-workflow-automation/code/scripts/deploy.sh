#!/bin/bash

# Voice-Driven Workflow Automation with Speech Recognition
# Deployment Script
# 
# This script deploys all Azure resources needed for voice-enabled business process automation
# including Azure AI Speech Services, Logic Apps, Storage Account, and supporting infrastructure.
#
# Prerequisites:
# - Azure CLI v2.0 or later
# - Active Azure subscription with appropriate permissions
# - Power Platform environment (manual setup required)
#
# Usage: ./deploy.sh [--resource-group <name>] [--location <region>] [--dry-run]

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_FILE="${SCRIPT_DIR}/deploy_errors.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP=""
DRY_RUN=false
RANDOM_SUFFIX=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}ERROR: $1${NC}" | tee -a "$ERROR_FILE" >&2
}

log_warning() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${BLUE}INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    cleanup_on_error
    exit 1
}

cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partially created resources..."
    if [[ -f "$STATE_FILE" ]]; then
        log_info "State file found. Review $STATE_FILE for created resources."
    fi
}

# Save deployment state
save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "$STATE_FILE"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI and try again."
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure CLI. Please run 'az login' and try again."
    fi
    
    # Check for required permissions
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    if [[ -z "$subscription_id" ]]; then
        error_exit "Unable to get subscription ID. Please check your Azure CLI login."
    fi
    
    log_success "Prerequisites check completed"
    log_info "Using subscription: $subscription_id"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Voice-Enabled Business Process Automation infrastructure.

OPTIONS:
    --resource-group <name>    Resource group name (will be created if not exists)
    --location <region>        Azure region (default: $DEFAULT_LOCATION)
    --dry-run                  Show what would be deployed without making changes
    --help, -h                 Show this help message

EXAMPLES:
    $0 --resource-group rg-voice-automation --location eastus
    $0 --dry-run
    $0 --resource-group my-rg --location westus2

EOF
}

# Generate unique resource names
generate_resource_names() {
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource group name if not provided
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP="rg-voice-automation-${RANDOM_SUFFIX}"
    fi
    
    # Set location if not provided
    if [[ -z "$LOCATION" ]]; then
        LOCATION="$DEFAULT_LOCATION"
    fi
    
    # Generate resource names
    SPEECH_SERVICE_NAME="speech-voice-automation-${RANDOM_SUFFIX}"
    LOGIC_APP_NAME="logic-voice-processor-${RANDOM_SUFFIX}"
    STORAGE_ACCOUNT_NAME="stvoiceauto${RANDOM_SUFFIX}"
    
    log_info "Generated resource names:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Speech Service: $SPEECH_SERVICE_NAME"
    log_info "  Logic App: $LOGIC_APP_NAME"
    log_info "  Storage Account: $STORAGE_ACCOUNT_NAME"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=voice-automation environment=demo project=recipe || \
            error_exit "Failed to create resource group"
        
        save_state "RESOURCE_GROUP" "$RESOURCE_GROUP"
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT_NAME"
        return 0
    fi
    
    # Check if storage account name is available
    if ! az storage account check-name --name "$STORAGE_ACCOUNT_NAME" --query nameAvailable --output tsv | grep -q true; then
        error_exit "Storage account name $STORAGE_ACCOUNT_NAME is not available"
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        --tags purpose=voice-automation environment=demo || \
        error_exit "Failed to create storage account"
    
    save_state "STORAGE_ACCOUNT_NAME" "$STORAGE_ACCOUNT_NAME"
    log_success "Storage account created: $STORAGE_ACCOUNT_NAME"
}

# Create Azure AI Speech Service
create_speech_service() {
    log_info "Creating Azure AI Speech Service: $SPEECH_SERVICE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Speech Service: $SPEECH_SERVICE_NAME"
        return 0
    fi
    
    az cognitiveservices account create \
        --name "$SPEECH_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind SpeechServices \
        --sku S0 \
        --custom-domain "$SPEECH_SERVICE_NAME" \
        --tags purpose=voice-automation environment=demo \
        --yes || \
        error_exit "Failed to create Speech Service"
    
    # Get Speech Service details
    local speech_key
    local speech_endpoint
    
    speech_key=$(az cognitiveservices account keys list \
        --name "$SPEECH_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv) || \
        error_exit "Failed to get Speech Service key"
    
    speech_endpoint=$(az cognitiveservices account show \
        --name "$SPEECH_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv) || \
        error_exit "Failed to get Speech Service endpoint"
    
    save_state "SPEECH_SERVICE_NAME" "$SPEECH_SERVICE_NAME"
    save_state "SPEECH_KEY" "$speech_key"
    save_state "SPEECH_ENDPOINT" "$speech_endpoint"
    
    log_success "Speech Service created: $SPEECH_SERVICE_NAME"
    log_info "Speech Service endpoint: $speech_endpoint"
}

# Create Logic App
create_logic_app() {
    log_info "Creating Logic App: $LOGIC_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Logic App: $LOGIC_APP_NAME"
        return 0
    fi
    
    # Create Logic App
    az logic workflow create \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --storage-account "$STORAGE_ACCOUNT_NAME" \
        --tags purpose=voice-automation environment=demo || \
        error_exit "Failed to create Logic App"
    
    # Get Logic App details
    local logic_app_id
    logic_app_id=$(az logic workflow show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv) || \
        error_exit "Failed to get Logic App ID"
    
    save_state "LOGIC_APP_NAME" "$LOGIC_APP_NAME"
    save_state "LOGIC_APP_ID" "$logic_app_id"
    
    log_success "Logic App created: $LOGIC_APP_NAME"
    log_info "Logic App ID: $logic_app_id"
}

# Create configuration files
create_configuration_files() {
    log_info "Creating configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create configuration files"
        return 0
    fi
    
    local config_dir="${SCRIPT_DIR}/../config"
    mkdir -p "$config_dir"
    
    # Create Speech Commands configuration
    cat > "${config_dir}/speech-commands-config.json" << 'EOF'
{
  "name": "VoiceBusinessAutomation",
  "description": "Voice commands for business process automation",
  "language": "en-US",
  "commands": [
    {
      "name": "ApproveRequest",
      "patterns": [
        "approve request {requestId}",
        "approve {requestId}",
        "yes approve request number {requestId}"
      ],
      "parameters": [
        {
          "name": "requestId",
          "type": "string",
          "required": true
        }
      ]
    },
    {
      "name": "RejectRequest",
      "patterns": [
        "reject request {requestId}",
        "deny {requestId}",
        "no reject request number {requestId}"
      ],
      "parameters": [
        {
          "name": "requestId",
          "type": "string",
          "required": true
        }
      ]
    },
    {
      "name": "UpdateRecord",
      "patterns": [
        "update record {recordId} with {fieldName} {value}",
        "set {fieldName} to {value} for record {recordId}"
      ],
      "parameters": [
        {
          "name": "recordId",
          "type": "string",
          "required": true
        },
        {
          "name": "fieldName",
          "type": "string",
          "required": true
        },
        {
          "name": "value",
          "type": "string",
          "required": true
        }
      ]
    }
  ]
}
EOF
    
    # Create Power Automate Flow definition
    cat > "${config_dir}/power-automate-flow.json" << 'EOF'
{
  "definition": {
    "triggers": {
      "manual": {
        "type": "Request",
        "kind": "Http",
        "inputs": {
          "schema": {
            "type": "object",
            "properties": {
              "command": {
                "type": "string"
              },
              "parameters": {
                "type": "object"
              },
              "userId": {
                "type": "string"
              },
              "timestamp": {
                "type": "string"
              }
            }
          }
        }
      }
    },
    "actions": {
      "Switch_Command": {
        "type": "Switch",
        "expression": "@triggerBody()?['command']",
        "cases": {
          "ApproveRequest": {
            "case": "ApproveRequest",
            "actions": {
              "Update_Approval_Status": {
                "type": "ApiConnection",
                "inputs": {
                  "host": {
                    "connectionName": "shared_commondataserviceforapps",
                    "operationId": "UpdateRecord"
                  },
                  "parameters": {
                    "entityName": "approvals",
                    "recordId": "@triggerBody()?['parameters']?['requestId']",
                    "item": {
                      "status": "approved",
                      "approvedBy": "@triggerBody()?['userId']",
                      "approvedDate": "@utcnow()"
                    }
                  }
                }
              }
            }
          },
          "RejectRequest": {
            "case": "RejectRequest",
            "actions": {
              "Update_Rejection_Status": {
                "type": "ApiConnection",
                "inputs": {
                  "host": {
                    "connectionName": "shared_commondataserviceforapps",
                    "operationId": "UpdateRecord"
                  },
                  "parameters": {
                    "entityName": "approvals",
                    "recordId": "@triggerBody()?['parameters']?['requestId']",
                    "item": {
                      "status": "rejected",
                      "rejectedBy": "@triggerBody()?['userId']",
                      "rejectedDate": "@utcnow()"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF
    
    # Create Dataverse table definitions
    cat > "${config_dir}/dataverse-tables.json" << 'EOF'
{
  "tables": [
    {
      "name": "voice_automation_approvals",
      "displayName": "Voice Automation Approvals",
      "description": "Tracks approval requests processed through voice commands",
      "columns": [
        {
          "name": "request_id",
          "type": "string",
          "displayName": "Request ID",
          "required": true
        },
        {
          "name": "status",
          "type": "choice",
          "displayName": "Status",
          "choices": ["pending", "approved", "rejected"],
          "required": true
        },
        {
          "name": "approved_by",
          "type": "string",
          "displayName": "Approved By"
        },
        {
          "name": "approved_date",
          "type": "datetime",
          "displayName": "Approved Date"
        },
        {
          "name": "voice_command_text",
          "type": "string",
          "displayName": "Voice Command Text"
        }
      ]
    },
    {
      "name": "voice_automation_audit",
      "displayName": "Voice Automation Audit",
      "description": "Audit trail for all voice automation activities",
      "columns": [
        {
          "name": "user_id",
          "type": "string",
          "displayName": "User ID",
          "required": true
        },
        {
          "name": "command",
          "type": "string",
          "displayName": "Command",
          "required": true
        },
        {
          "name": "timestamp",
          "type": "datetime",
          "displayName": "Timestamp",
          "required": true
        },
        {
          "name": "success",
          "type": "boolean",
          "displayName": "Success"
        }
      ]
    }
  ]
}
EOF
    
    log_success "Configuration files created in $config_dir"
}

# Display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    
    if [[ -f "$STATE_FILE" ]]; then
        while IFS='=' read -r key value; do
            [[ -n "$key" && -n "$value" ]] && log_info "$key: $value"
        done < "$STATE_FILE"
    fi
    
    log_info ""
    log_info "Next Steps:"
    log_info "1. Navigate to Speech Studio to configure custom commands using the configuration file"
    log_info "2. Import the Power Automate flow definition into your Power Platform environment"
    log_info "3. Create Dataverse tables using the provided table definitions"
    log_info "4. Configure the Logic App workflow to connect Speech Services with Power Platform"
    log_info "5. Test the voice automation system using the validation commands"
    log_info ""
    log_info "Configuration files are available in: ${SCRIPT_DIR}/../config/"
    log_info "Deployment logs are available in: $LOG_FILE"
}

# Main deployment function
main() {
    # Initialize log files
    : > "$LOG_FILE"
    : > "$ERROR_FILE"
    : > "$STATE_FILE"
    
    log_info "Starting Voice-Enabled Business Process Automation deployment"
    log_info "Script version: 1.0"
    log_info "Timestamp: $(date)"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Generate resource names
    generate_resource_names
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        log_info "Would deploy the following resources:"
        log_info "  Resource Group: $RESOURCE_GROUP in $LOCATION"
        log_info "  Storage Account: $STORAGE_ACCOUNT_NAME"
        log_info "  Speech Service: $SPEECH_SERVICE_NAME"
        log_info "  Logic App: $LOGIC_APP_NAME"
        exit 0
    fi
    
    # Deploy resources
    create_resource_group
    create_storage_account
    create_speech_service
    create_logic_app
    create_configuration_files
    
    # Show summary
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
    log_info "Total deployment time: $SECONDS seconds"
}

# Set script permissions and run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi