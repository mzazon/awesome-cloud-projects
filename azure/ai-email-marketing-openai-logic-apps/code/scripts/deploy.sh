#!/bin/bash

# AI-Powered Email Marketing Campaigns with OpenAI and Logic Apps - Deployment Script
# This script deploys the complete Azure infrastructure for the email marketing solution
# Usage: ./deploy.sh [--resource-group <name>] [--location <location>] [--dry-run]

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-email-marketing"
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR" "Deployment failed: $1"
    log "ERROR" "Check log file at: $LOG_FILE"
    cleanup_on_error
    exit 1
}

# Cleanup function for failed deployments
cleanup_on_error() {
    log "WARN" "Performing emergency cleanup due to deployment failure"
    
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE" 2>/dev/null || true
        
        # Clean up partially created resources
        if [[ -n "${RESOURCE_GROUP:-}" ]]; then
            log "INFO" "Cleaning up resource group: $RESOURCE_GROUP"
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
        fi
    fi
}

# Trap errors
trap 'error_exit "Unexpected error occurred at line $LINENO"' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AI-Powered Email Marketing infrastructure on Azure

OPTIONS:
    -g, --resource-group PREFIX    Resource group prefix (default: $DEFAULT_RESOURCE_GROUP_PREFIX)
    -l, --location LOCATION       Azure region (default: $DEFAULT_LOCATION)
    -d, --dry-run                 Show what would be deployed without actually deploying
    -v, --verbose                 Enable verbose logging
    -h, --help                    Show this help message

EXAMPLES:
    $0                                          # Deploy with defaults
    $0 -g my-marketing -l westus2              # Custom resource group and location
    $0 --dry-run                               # Preview deployment
    $0 --verbose                               # Enable detailed logging

PREREQUISITES:
    - Azure CLI installed and configured (az --version)
    - Azure subscription with Contributor access
    - OpenAI service approval (if not already approved)

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP_PREFIX="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "DEBUG" "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get and validate subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log "INFO" "Using Azure subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Check if location is valid
    if ! az account list-locations --query "[?name=='$LOCATION']" | grep -q "$LOCATION"; then
        error_exit "Invalid Azure location: $LOCATION"
    fi
    
    # Check OpenAI availability in region
    local openai_available=$(az cognitiveservices account list-skus --location "$LOCATION" --query "[?kind=='OpenAI'].kind" -o tsv 2>/dev/null || echo "")
    if [[ -z "$openai_available" ]]; then
        log "WARN" "OpenAI service may not be available in $LOCATION. Consider using eastus, westus2, or northcentralus."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Generate unique resource names
generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    # Generate random suffix for uniqueness
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    OPENAI_SERVICE_NAME="openai-marketing-${RANDOM_SUFFIX}"
    LOGIC_APP_NAME="logicapp-marketing-${RANDOM_SUFFIX}"
    COMMUNICATION_SERVICE_NAME="comms-marketing-${RANDOM_SUFFIX}"
    EMAIL_SERVICE_NAME="email-marketing-${RANDOM_SUFFIX}"
    STORAGE_ACCOUNT_NAME="storage${RANDOM_SUFFIX}"
    
    log "DEBUG" "Resource Group: $RESOURCE_GROUP"
    log "DEBUG" "OpenAI Service: $OPENAI_SERVICE_NAME"
    log "DEBUG" "Logic App: $LOGIC_APP_NAME"
    log "DEBUG" "Communication Service: $COMMUNICATION_SERVICE_NAME"
    log "DEBUG" "Email Service: $EMAIL_SERVICE_NAME"
    log "DEBUG" "Storage Account: $STORAGE_ACCOUNT_NAME"
}

# Save deployment state
save_deployment_state() {
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
# Deployment state file - DO NOT EDIT MANUALLY
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
OPENAI_SERVICE_NAME="$OPENAI_SERVICE_NAME"
LOGIC_APP_NAME="$LOGIC_APP_NAME"
COMMUNICATION_SERVICE_NAME="$COMMUNICATION_SERVICE_NAME"
EMAIL_SERVICE_NAME="$EMAIL_SERVICE_NAME"
STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
DEPLOYMENT_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
    log "DEBUG" "Deployment state saved to: $DEPLOYMENT_STATE_FILE"
}

# Deploy resource group
deploy_resource_group() {
    log "INFO" "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo recipe=ai-email-marketing \
        --output none
    
    log "INFO" "✅ Resource group created successfully"
}

# Deploy Azure OpenAI Service
deploy_openai_service() {
    log "INFO" "Creating Azure OpenAI service: $OPENAI_SERVICE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create OpenAI service: $OPENAI_SERVICE_NAME"
        return 0
    fi
    
    # Create OpenAI service
    az cognitiveservices account create \
        --name "$OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind OpenAI \
        --sku S0 \
        --output none
    
    # Wait for service to be ready
    log "INFO" "Waiting for OpenAI service to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local state=$(az cognitiveservices account show \
            --name "$OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        elif [[ "$state" == "Failed" ]]; then
            error_exit "OpenAI service deployment failed"
        fi
        
        log "DEBUG" "OpenAI service state: $state (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error_exit "Timeout waiting for OpenAI service to be ready"
    fi
    
    # Get service endpoint and key
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log "INFO" "✅ Azure OpenAI service created with endpoint: $OPENAI_ENDPOINT"
}

# Deploy GPT-4o model
deploy_gpt_model() {
    log "INFO" "Deploying GPT-4o model for content generation"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would deploy GPT-4o model: gpt-4o-marketing"
        return 0
    fi
    
    # Deploy GPT-4o model
    az cognitiveservices account deployment create \
        --name "$OPENAI_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name gpt-4o-marketing \
        --model-name gpt-4o \
        --model-version "2024-11-20" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name "Standard" \
        --output none
    
    # Wait for deployment to complete
    log "INFO" "Waiting for model deployment to complete..."
    local max_attempts=20
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local state=$(az cognitiveservices account deployment show \
            --name "$OPENAI_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name gpt-4o-marketing \
            --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        elif [[ "$state" == "Failed" ]]; then
            error_exit "GPT-4o model deployment failed"
        fi
        
        log "DEBUG" "Model deployment state: $state (attempt $attempt/$max_attempts)"
        sleep 15
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error_exit "Timeout waiting for model deployment to complete"
    fi
    
    log "INFO" "✅ GPT-4o model deployed successfully"
}

# Deploy Communication Services
deploy_communication_services() {
    log "INFO" "Creating Azure Communication Services"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create Communication Services: $COMMUNICATION_SERVICE_NAME"
        log "INFO" "[DRY-RUN] Would create Email Service: $EMAIL_SERVICE_NAME"
        return 0
    fi
    
    # Create Communication Services resource
    az communication create \
        --name "$COMMUNICATION_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "Global" \
        --output none
    
    # Create Email Communication Services resource
    az communication email create \
        --name "$EMAIL_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "Global" \
        --data-location "United States" \
        --output none
    
    # Get connection string
    COMMUNICATION_STRING=$(az communication list-key \
        --name "$COMMUNICATION_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    log "INFO" "✅ Communication Services created successfully"
}

# Configure email domain
configure_email_domain() {
    log "INFO" "Configuring email domain and sender address"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would configure Azure Managed Domain"
        return 0
    fi
    
    # Add AzureManagedDomain to Email Communication Service
    az communication email domain create \
        --domain-name "AzureManagedDomain" \
        --resource-group "$RESOURCE_GROUP" \
        --email-service-name "$EMAIL_SERVICE_NAME" \
        --domain-management "AzureManaged" \
        --output none
    
    # Wait for domain to be ready
    log "INFO" "Waiting for email domain to be ready..."
    sleep 30
    
    # Get sender email address
    SENDER_EMAIL="DoNotReply@$(az communication email domain show \
        --domain-name "AzureManagedDomain" \
        --resource-group "$RESOURCE_GROUP" \
        --email-service-name "$EMAIL_SERVICE_NAME" \
        --query mailFromSenderDomain --output tsv)"
    
    # Connect Communication Services with Email Service
    az communication email domain connect \
        --domain-name "AzureManagedDomain" \
        --resource-group "$RESOURCE_GROUP" \
        --email-service-name "$EMAIL_SERVICE_NAME" \
        --communication-service-name "$COMMUNICATION_SERVICE_NAME" \
        --output none
    
    log "INFO" "✅ Email domain configured with sender: $SENDER_EMAIL"
}

# Deploy storage account
deploy_storage_account() {
    log "INFO" "Creating storage account for Logic Apps runtime"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create storage account: $STORAGE_ACCOUNT_NAME"
        return 0
    fi
    
    # Create storage account
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    # Get storage connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    log "INFO" "✅ Storage account created successfully"
}

# Deploy Logic Apps
deploy_logic_apps() {
    log "INFO" "Creating Logic Apps Standard resource"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create Logic App: $LOGIC_APP_NAME"
        return 0
    fi
    
    # Create Logic Apps Standard resource (using Function App)
    az functionapp create \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT_NAME" \
        --consumption-plan-location "$LOCATION" \
        --runtime node \
        --functions-version 4 \
        --os-type Linux \
        --output none
    
    # Configure Logic App settings for AI integration
    az functionapp config appsettings set \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
            "OPENAI_KEY=$OPENAI_KEY" \
            "COMMUNICATION_STRING=$COMMUNICATION_STRING" \
            "SENDER_EMAIL=$SENDER_EMAIL" \
        --output none
    
    log "INFO" "✅ Logic Apps resource created and configured"
}

# Create and deploy workflow
deploy_workflow() {
    log "INFO" "Creating AI agent workflow definition"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create and deploy marketing workflow"
        return 0
    fi
    
    # Create temporary directory for workflow files
    local temp_dir=$(mktemp -d)
    local workflows_dir="$temp_dir/workflows"
    mkdir -p "$workflows_dir"
    
    # Create workflow definition
    cat > "$workflows_dir/EmailMarketingWorkflow.json" << 'EOF'
{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
      "OPENAI_ENDPOINT": {
        "type": "string"
      },
      "OPENAI_KEY": {
        "type": "securestring"
      },
      "SENDER_EMAIL": {
        "type": "string"
      }
    },
    "triggers": {
      "Recurrence": {
        "type": "Recurrence",
        "recurrence": {
          "frequency": "Day",
          "interval": 1,
          "startTime": "2025-01-01T09:00:00Z"
        }
      }
    },
    "actions": {
      "Generate_Email_Content": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "@concat(parameters('OPENAI_ENDPOINT'), 'openai/deployments/gpt-4o-marketing/chat/completions?api-version=2024-08-01-preview')",
          "headers": {
            "Content-Type": "application/json",
            "api-key": "@parameters('OPENAI_KEY')"
          },
          "body": {
            "messages": [
              {
                "role": "system",
                "content": "You are an expert email marketing copywriter. Generate professional email marketing content with engaging subject lines and HTML body content."
              },
              {
                "role": "user",
                "content": "Create a personalized email marketing campaign for a technology company. Include subject line and HTML body content that is engaging and professional. Target audience: software developers and IT professionals. Format as JSON with 'subject' and 'body' fields."
              }
            ],
            "max_tokens": 800,
            "temperature": 0.7,
            "response_format": { "type": "json_object" }
          }
        }
      },
      "Parse_AI_Response": {
        "type": "ParseJson",
        "inputs": {
          "content": "@body('Generate_Email_Content')['choices'][0]['message']['content']",
          "schema": {
            "type": "object",
            "properties": {
              "subject": { "type": "string" },
              "body": { "type": "string" }
            }
          }
        },
        "runAfter": {
          "Generate_Email_Content": ["Succeeded"]
        }
      }
    }
  }
}
EOF
    
    # Create deployment package
    cd "$temp_dir"
    zip -r workflow-package.zip workflows/ > /dev/null
    
    # Deploy the workflow
    az functionapp deployment source config-zip \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --src workflow-package.zip \
        --output none
    
    # Cleanup temporary files
    rm -rf "$temp_dir"
    
    log "INFO" "✅ AI-powered email marketing workflow deployed successfully"
}

# Display deployment summary
display_summary() {
    log "INFO" "Deployment completed successfully!"
    
    echo ""
    echo "=================================="
    echo "     DEPLOYMENT SUMMARY"
    echo "=================================="
    echo "Subscription ID:       $SUBSCRIPTION_ID"
    echo "Resource Group:        $RESOURCE_GROUP"
    echo "Location:              $LOCATION"
    echo "OpenAI Service:        $OPENAI_SERVICE_NAME"
    echo "Logic App:             $LOGIC_APP_NAME"
    echo "Communication Service: $COMMUNICATION_SERVICE_NAME"
    echo "Email Service:         $EMAIL_SERVICE_NAME"
    echo "Storage Account:       $STORAGE_ACCOUNT_NAME"
    echo "Sender Email:          ${SENDER_EMAIL:-'Not configured'}"
    echo "=================================="
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Access your resources in the Azure Portal:"
        log "INFO" "https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
        
        echo ""
        log "INFO" "To test the OpenAI integration:"
        echo "export OPENAI_ENDPOINT=\"$OPENAI_ENDPOINT\""
        echo "export OPENAI_KEY=\"$OPENAI_KEY\""
        echo ""
        
        log "INFO" "To clean up resources, run: ./destroy.sh"
    fi
}

# Main execution
main() {
    echo "AI-Powered Email Marketing Campaigns - Deployment Script"
    echo "======================================================="
    echo ""
    
    # Initialize logging
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Set defaults
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    RESOURCE_GROUP_PREFIX="${RESOURCE_GROUP_PREFIX:-$DEFAULT_RESOURCE_GROUP_PREFIX}"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    
    if [[ "$DRY_RUN" == "false" ]]; then
        save_deployment_state
    fi
    
    deploy_resource_group
    deploy_openai_service
    deploy_gpt_model
    deploy_communication_services
    configure_email_domain
    deploy_storage_account
    deploy_logic_apps
    deploy_workflow
    
    display_summary
    
    log "INFO" "Deployment completed successfully at $(date)"
}

# Execute main function with all arguments
main "$@"