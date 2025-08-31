#!/bin/bash

# Customer Support Assistant with OpenAI Assistants and Functions - Cleanup Script
# This script removes all Azure resources created during deployment
# Uses Azure CLI to safely delete resources in proper order

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CLEANUP_LOG="$SCRIPT_DIR/cleanup.log"
STATE_FILE="$SCRIPT_DIR/deployment-state.json"

# Initialize cleanup log
exec > >(tee -a "$CLEANUP_LOG")
exec 2>&1

log "Starting Customer Support Assistant cleanup..."
log "Script directory: $SCRIPT_DIR"
log "Project root: $PROJECT_ROOT"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing via package manager..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            error "Could not install jq. Please install it manually."
            exit 1
        fi
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state from previous deployment..."
    
    if [ ! -f "$STATE_FILE" ]; then
        error "Deployment state file not found: $STATE_FILE"
        echo "This usually means the deployment script was not run successfully."
        echo "You may need to manually identify and delete resources."
        exit 1
    fi
    
    # Extract variables from state file
    export RESOURCE_GROUP=$(jq -r '.resourceGroup' "$STATE_FILE")
    export STORAGE_ACCOUNT=$(jq -r '.storageAccount' "$STATE_FILE")
    export FUNCTION_APP=$(jq -r '.functionApp' "$STATE_FILE")
    export OPENAI_ACCOUNT=$(jq -r '.openaiAccount' "$STATE_FILE")
    export LOCATION=$(jq -r '.location' "$STATE_FILE")
    export SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$STATE_FILE")
    export RANDOM_SUFFIX=$(jq -r '.randomSuffix' "$STATE_FILE")
    
    # Try to get assistant ID if it exists
    ASSISTANT_ID=$(jq -r '.assistantId // empty' "$STATE_FILE")
    if [ -n "$ASSISTANT_ID" ] && [ "$ASSISTANT_ID" != "null" ]; then
        export ASSISTANT_ID
    fi
    
    log "Loaded deployment state:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Function App: $FUNCTION_APP"
    log "  OpenAI Account: $OPENAI_ACCOUNT"
    log "  Location: $LOCATION"
    
    if [ -n "${ASSISTANT_ID:-}" ]; then
        log "  Assistant ID: $ASSISTANT_ID"
    fi
}

# Function to prompt for confirmation
confirm_deletion() {
    echo ""
    warning "⚠️  WARNING: This will permanently delete all resources associated with the Customer Support Assistant deployment!"
    echo ""
    echo "Resources to be deleted:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • Storage Account: $STORAGE_ACCOUNT (including all data)"
    echo "  • Function App: $FUNCTION_APP"
    echo "  • OpenAI Account: $OPENAI_ACCOUNT (including deployed models)"
    if [ -n "${ASSISTANT_ID:-}" ]; then
        echo "  • OpenAI Assistant: $ASSISTANT_ID"
    fi
    echo ""
    
    # Check if running in non-interactive mode
    if [ "${FORCE_DELETE:-}" = "true" ]; then
        warning "FORCE_DELETE is set, skipping confirmation prompt"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion, proceeding with cleanup..."
}

# Function to delete OpenAI Assistant
delete_openai_assistant() {
    if [ -z "${ASSISTANT_ID:-}" ]; then
        log "No OpenAI Assistant ID found, skipping assistant deletion"
        return 0
    fi
    
    log "Deleting OpenAI Assistant: $ASSISTANT_ID"
    
    # Create temporary directory for assistant deletion
    TEMP_DIR="$SCRIPT_DIR/temp-cleanup"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Create package.json and install OpenAI SDK
    cat > package.json << 'EOF'
{
  "name": "support-assistant-cleanup",
  "version": "1.0.0",
  "description": "Deletes OpenAI Assistant for customer support",
  "main": "delete-assistant.js",
  "type": "module",
  "dependencies": {
    "openai": "^4.0.0"
  }
}
EOF

    npm install --silent

    # Get OpenAI credentials
    if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        OPENAI_ENDPOINT=$(az cognitiveservices account show \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query properties.endpoint --output tsv)
        
        OPENAI_KEY=$(az cognitiveservices account keys list \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query key1 --output tsv)
        
        # Create assistant deletion script
        cat > delete-assistant.js << EOF
import { OpenAI } from 'openai';

const client = new OpenAI({
    apiKey: process.env.OPENAI_KEY,
    baseURL: \`\${process.env.OPENAI_ENDPOINT}/openai/deployments/gpt-4o\`,
    defaultQuery: { 'api-version': '2024-10-21' },
    defaultHeaders: {
        'api-key': process.env.OPENAI_KEY,
    },
});

async function deleteAssistant() {
    try {
        await client.beta.assistants.del('$ASSISTANT_ID');
        console.log('Assistant deleted successfully');
    } catch (error) {
        console.error('Error deleting assistant:', error.message);
        // Don't fail the entire cleanup if assistant deletion fails
        console.log('Continuing with resource cleanup...');
    }
}

deleteAssistant();
EOF

        # Set environment variables and delete assistant
        export OPENAI_KEY="$OPENAI_KEY"
        export OPENAI_ENDPOINT="$OPENAI_ENDPOINT"
        
        node delete-assistant.js
        
        success "OpenAI Assistant deletion attempted"
    else
        warning "OpenAI account not found, skipping assistant deletion"
    fi
    
    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_DIR"
}

# Function to delete Function App
delete_function_app() {
    log "Deleting Function App: $FUNCTION_APP"
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        success "Function App deleted: $FUNCTION_APP"
    else
        warning "Function App $FUNCTION_APP not found, may have been already deleted"
    fi
}

# Function to delete OpenAI Service and models
delete_openai_service() {
    log "Deleting Azure OpenAI Service: $OPENAI_ACCOUNT"
    
    if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        # First, try to delete model deployments
        log "Deleting GPT-4o model deployment..."
        if az cognitiveservices account deployment show \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name gpt-4o &> /dev/null; then
            
            az cognitiveservices account deployment delete \
                --name "$OPENAI_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --deployment-name gpt-4o \
                --output none
            
            log "GPT-4o model deployment deleted"
        else
            log "GPT-4o model deployment not found"
        fi
        
        # Delete the OpenAI service
        az cognitiveservices account delete \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        success "Azure OpenAI Service deleted: $OPENAI_ACCOUNT"
    else
        warning "OpenAI Service $OPENAI_ACCOUNT not found, may have been already deleted"
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    log "Deleting Storage Account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
        
        success "Storage Account deleted: $STORAGE_ACCOUNT"
    else
        warning "Storage Account $STORAGE_ACCOUNT not found, may have been already deleted"
    fi
}

# Function to delete Resource Group
delete_resource_group() {
    log "Deleting Resource Group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        # Start resource group deletion (this is asynchronous)
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Resource group deletion may take several minutes to complete"
    else
        warning "Resource Group $RESOURCE_GROUP not found, may have been already deleted"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
        
        # List remaining resources in the resource group
        REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "$REMAINING_RESOURCES" ]; then
            warning "Remaining resources in $RESOURCE_GROUP:"
            echo "$REMAINING_RESOURCES" | while read -r resource; do
                echo "  - $resource"
            done
            echo ""
            log "These resources will be deleted when the resource group deletion completes"
        fi
    else
        success "Resource group $RESOURCE_GROUP has been successfully deleted"
    fi
    
    # Check individual resources if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        # Check Function App
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warning "Function App $FUNCTION_APP still exists"
        else
            success "Function App $FUNCTION_APP successfully deleted"
        fi
        
        # Check OpenAI Service
        if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warning "OpenAI Service $OPENAI_ACCOUNT still exists"
        else
            success "OpenAI Service $OPENAI_ACCOUNT successfully deleted"
        fi
        
        # Check Storage Account
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warning "Storage Account $STORAGE_ACCOUNT still exists"
        else
            success "Storage Account $STORAGE_ACCOUNT successfully deleted"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local deployment files..."
    
    # Remove deployment state file
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        log "Removed deployment state file: $STATE_FILE"
    fi
    
    # Remove any temporary directories that might still exist
    TEMP_DIRS=("$SCRIPT_DIR/temp-functions" "$SCRIPT_DIR/temp-assistant" "$SCRIPT_DIR/temp-cleanup")
    for temp_dir in "${TEMP_DIRS[@]}"; do
        if [ -d "$temp_dir" ]; then
            rm -rf "$temp_dir"
            log "Removed temporary directory: $temp_dir"
        fi
    done
    
    success "Local cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo ""
    echo "Resources Deleted:"
    echo "  ✓ OpenAI Assistant (if existed): ${ASSISTANT_ID:-"N/A"}"
    echo "  ✓ Function App: $FUNCTION_APP"
    echo "  ✓ OpenAI Service: $OPENAI_ACCOUNT"
    echo "  ✓ Storage Account: $STORAGE_ACCOUNT"
    echo "  ✓ Resource Group: $RESOURCE_GROUP (deletion initiated)"
    echo ""
    echo "Local Files Cleaned:"
    echo "  ✓ Deployment state file"
    echo "  ✓ Temporary directories"
    echo ""
    echo "Important Notes:"
    echo "  • Resource group deletion is asynchronous and may take several minutes"
    echo "  • You can monitor deletion progress in the Azure Portal"
    echo "  • All data in the storage account has been permanently deleted"
    echo "  • OpenAI models and assistant configurations have been removed"
    echo ""
    echo "Cleanup logs saved to: $CLEANUP_LOG"
}

# Function to handle partial cleanup on error
handle_cleanup_error() {
    error "Cleanup process encountered an error at line $1"
    echo ""
    warning "Partial cleanup may have occurred. Please check the Azure Portal to verify resource status."
    echo ""
    echo "You may need to manually delete remaining resources:"
    echo "  1. Check Resource Group: $RESOURCE_GROUP"
    echo "  2. Delete any remaining resources individually"
    echo "  3. Delete the resource group if it still exists"
    echo ""
    echo "Cleanup logs saved to: $CLEANUP_LOG"
    exit 1
}

# Function to wait for resource group deletion
wait_for_deletion() {
    local wait_time=${1:-300}  # Default 5 minutes
    local check_interval=30    # Check every 30 seconds
    local elapsed=0
    
    log "Waiting for resource group deletion to complete (max ${wait_time}s)..."
    
    while [ $elapsed -lt $wait_time ]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            success "Resource group $RESOURCE_GROUP has been completely deleted"
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        log "Still waiting... (${elapsed}s elapsed)"
    done
    
    warning "Resource group deletion is taking longer than expected"
    log "You can check the deletion status in the Azure Portal"
    return 1
}

# Main cleanup function
main() {
    log "Customer Support Assistant Cleanup Started"
    
    # Check if user wants to wait for complete deletion
    WAIT_FOR_DELETION="${WAIT_FOR_DELETION:-false}"
    
    # Run all cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_deletion
    delete_openai_assistant
    delete_function_app
    delete_openai_service
    delete_storage_account
    delete_resource_group
    
    # Wait for deletion if requested
    if [ "$WAIT_FOR_DELETION" = "true" ]; then
        wait_for_deletion 600  # Wait up to 10 minutes
    fi
    
    verify_cleanup
    cleanup_local_files
    display_summary
    
    success "Customer Support Assistant cleanup completed!"
    log "Total cleanup time: $SECONDS seconds"
    
    if [ "$WAIT_FOR_DELETION" != "true" ]; then
        echo ""
        log "To wait for complete resource group deletion, run:"
        log "  WAIT_FOR_DELETION=true ./destroy.sh"
    fi
}

# Error handling
trap 'handle_cleanup_error $LINENO' ERR

# Check for command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --wait)
            export WAIT_FOR_DELETION=true
            shift
            ;;
        --help|-h)
            echo "Customer Support Assistant Cleanup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --wait     Wait for resource group deletion to complete"
            echo "  --help     Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  FORCE_DELETE=true      Skip confirmation prompts"
            echo "  WAIT_FOR_DELETION=true Wait for complete deletion"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"