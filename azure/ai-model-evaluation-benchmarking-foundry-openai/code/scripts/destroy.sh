#!/bin/bash

# AI Model Evaluation and Benchmarking with Azure AI Foundry - Cleanup Script
# This script removes all infrastructure created for AI model evaluation and benchmarking
# Recipe: ai-model-evaluation-benchmarking-foundry-openai

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CLEANUP_LOG="$PROJECT_ROOT/cleanup.log"

# Global variables for resource tracking
declare -a RESOURCES_TO_DELETE=()
declare -a FAILED_DELETIONS=()

# Default confirmation behavior
CONFIRM_DELETION=${CONFIRM_DELETION:-true}
FORCE_DELETE=${FORCE_DELETE:-false}

# Validation functions
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Resource discovery functions
discover_resource_groups() {
    log "Discovering AI evaluation resource groups..."
    
    local rgs=$(az group list --query "[?tags.recipe=='ai-model-evaluation-benchmarking-foundry-openai'].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$rgs" ]]; then
        while IFS= read -r rg; do
            [[ -n "$rg" ]] && RESOURCES_TO_DELETE+=("RESOURCE_GROUP:$rg")
        done <<< "$rgs"
        log "Found tagged resource groups: $(echo "$rgs" | tr '\n' ' ')"
    fi
    
    # Also check for common naming patterns if no tagged RGs found
    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        local pattern_rgs=$(az group list --query "[?starts_with(name, 'rg-ai-evaluation')].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$pattern_rgs" ]]; then
            while IFS= read -r rg; do
                [[ -n "$rg" ]] && RESOURCES_TO_DELETE+=("RESOURCE_GROUP:$rg")
            done <<< "$pattern_rgs"
            log "Found pattern-matched resource groups: $(echo "$pattern_rgs" | tr '\n' ' ')"
        fi
    fi
}

discover_individual_resources() {
    log "Discovering individual AI evaluation resources..."
    
    local subscription_id=$(az account show --query id --output tsv)
    
    # Find OpenAI resources
    local openai_resources=$(az cognitiveservices account list --query "[?kind=='OpenAI' && contains(name, 'eval')].{name:name,resourceGroup:resourceGroup}" -o json 2>/dev/null || echo "[]")
    if [[ "$openai_resources" != "[]" ]]; then
        echo "$openai_resources" | jq -r '.[] | "OPENAI:\(.resourceGroup):\(.name)"' | while read -r resource; do
            RESOURCES_TO_DELETE+=("$resource")
        done
    fi
    
    # Find ML workspaces (AI Foundry projects)
    local ml_workspaces=$(az ml workspace list --query "[?contains(name, 'ai-eval')].{name:name,resourceGroup:resourceGroup}" -o json 2>/dev/null || echo "[]")
    if [[ "$ml_workspaces" != "[]" ]]; then
        echo "$ml_workspaces" | jq -r '.[] | "ML_WORKSPACE:\(.resourceGroup):\(.name)"' | while read -r resource; do
            RESOURCES_TO_DELETE+=("$resource")
        done
    fi
    
    # Find storage accounts
    local storage_accounts=$(az storage account list --query "[?contains(name, 'storage') && contains(name, 'eval')] | [?length(name) <= 24].{name:name,resourceGroup:resourceGroup}" -o json 2>/dev/null || echo "[]")
    if [[ "$storage_accounts" != "[]" ]]; then
        echo "$storage_accounts" | jq -r '.[] | "STORAGE:\(.resourceGroup):\(.name)"' | while read -r resource; do
            RESOURCES_TO_DELETE+=("$resource")
        done
    fi
}

list_resources_for_confirmation() {
    echo
    echo "======================================"
    echo "RESOURCES TO BE DELETED"
    echo "======================================"
    
    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        echo "No AI evaluation resources found."
        return 0
    fi
    
    local rg_count=0
    local resource_count=0
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        case "$resource" in
            RESOURCE_GROUP:*)
                local rg_name="${resource#RESOURCE_GROUP:}"
                echo "🗂️  Resource Group: $rg_name"
                
                # List resources in this RG
                local rg_resources=$(az resource list --resource-group "$rg_name" --query "[].{type:type,name:name}" -o json 2>/dev/null || echo "[]")
                if [[ "$rg_resources" != "[]" ]]; then
                    echo "$rg_resources" | jq -r '.[] | "   ├── \(.type): \(.name)"'
                fi
                ((rg_count++))
                ;;
            OPENAI:*)
                local parts=(${resource//:/ })
                echo "🧠 OpenAI Resource: ${parts[2]} (in ${parts[1]})"
                ((resource_count++))
                ;;
            ML_WORKSPACE:*)
                local parts=(${resource//:/ })
                echo "🤖 ML Workspace: ${parts[2]} (in ${parts[1]})"
                ((resource_count++))
                ;;
            STORAGE:*)
                local parts=(${resource//:/ })
                echo "💾 Storage Account: ${parts[2]} (in ${parts[1]})"
                ((resource_count++))
                ;;
        esac
    done
    
    echo "======================================"
    echo "Total: $rg_count resource group(s), $resource_count individual resource(s)"
    echo "======================================"
    echo
}

confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        log "No resources found to delete."
        return 1
    fi
    
    list_resources_for_confirmation
    
    if [[ "$CONFIRM_DELETION" == "false" ]]; then
        return 0
    fi
    
    echo -e "${RED}⚠️  WARNING: This action cannot be undone!${NC}"
    echo -e "${RED}⚠️  All data in these resources will be permanently lost!${NC}"
    echo
    read -p "Are you absolutely sure you want to delete these resources? (type 'DELETE' to confirm): " -r
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Last chance - proceed with deletion? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

delete_model_deployments() {
    local openai_resource_name="$1"
    local resource_group="$2"
    
    log "Deleting model deployments from $openai_resource_name..."
    
    local deployments=("gpt-4o-eval" "gpt-35-turbo-eval" "gpt-4o-mini-eval")
    
    for deployment in "${deployments[@]}"; do
        if az cognitiveservices account deployment show --name "$openai_resource_name" --resource-group "$resource_group" --deployment-name "$deployment" &> /dev/null; then
            log "Deleting deployment: $deployment"
            if az cognitiveservices account deployment delete --name "$openai_resource_name" --resource-group "$resource_group" --deployment-name "$deployment" --output none 2>/dev/null; then
                log_success "Deleted deployment: $deployment"
            else
                log_warning "Failed to delete deployment: $deployment"
            fi
        else
            log "Deployment $deployment not found, skipping"
        fi
    done
}

delete_ml_workspace_contents() {
    local workspace_name="$1"
    local resource_group="$2"
    
    log "Cleaning up ML workspace contents: $workspace_name"
    
    # Set workspace context
    az configure --defaults workspace="$workspace_name" group="$resource_group" &> /dev/null || true
    
    # Delete datasets
    log "Deleting datasets..."
    local datasets=$(az ml data list --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$datasets" ]]; then
        while IFS= read -r dataset; do
            if [[ -n "$dataset" ]]; then
                log "Deleting dataset: $dataset"
                az ml data delete --name "$dataset" --version 1 --yes &> /dev/null || true
            fi
        done <<< "$datasets"
    fi
    
    # Delete environments
    log "Deleting environments..."
    local environments=$(az ml environment list --query "[?starts_with(name, 'evaluation')].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$environments" ]]; then
        while IFS= read -r env; do
            if [[ -n "$env" ]]; then
                log "Deleting environment: $env"
                az ml environment delete --name "$env" --version 1 --yes &> /dev/null || true
            fi
        done <<< "$environments"
    fi
    
    # Delete code assets
    log "Deleting code assets..."
    local code_assets=$(az ml code list --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$code_assets" ]]; then
        while IFS= read -r code; do
            if [[ -n "$code" ]]; then
                log "Deleting code asset: $code"
                az ml code delete --name "$code" --version 1 --yes &> /dev/null || true
            fi
        done <<< "$code_assets"
    fi
    
    # Reset defaults
    az configure --defaults workspace= group= &> /dev/null || true
}

delete_individual_resources() {
    log "Deleting individual resources..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        case "$resource" in
            OPENAI:*)
                local parts=(${resource//:/ })
                local resource_group="${parts[1]}"
                local openai_name="${parts[2]}"
                
                log "Deleting OpenAI resource: $openai_name"
                
                # First, delete model deployments
                delete_model_deployments "$openai_name" "$resource_group"
                
                # Then delete the OpenAI resource
                if az cognitiveservices account delete --name "$openai_name" --resource-group "$resource_group" --yes &> /dev/null; then
                    log_success "Deleted OpenAI resource: $openai_name"
                else
                    log_error "Failed to delete OpenAI resource: $openai_name"
                    FAILED_DELETIONS+=("OpenAI:$openai_name")
                fi
                ;;
                
            ML_WORKSPACE:*)
                local parts=(${resource//:/ })
                local resource_group="${parts[1]}"
                local workspace_name="${parts[2]}"
                
                log "Deleting ML workspace: $workspace_name"
                
                # Clean up workspace contents first
                delete_ml_workspace_contents "$workspace_name" "$resource_group"
                
                # Delete the workspace
                if az ml workspace delete --name "$workspace_name" --resource-group "$resource_group" --yes --no-wait &> /dev/null; then
                    log_success "Deletion initiated for ML workspace: $workspace_name"
                else
                    log_error "Failed to delete ML workspace: $workspace_name"
                    FAILED_DELETIONS+=("ML_Workspace:$workspace_name")
                fi
                ;;
                
            STORAGE:*)
                local parts=(${resource//:/ })
                local resource_group="${parts[1]}"
                local storage_name="${parts[2]}"
                
                log "Deleting storage account: $storage_name"
                if az storage account delete --name "$storage_name" --resource-group "$resource_group" --yes &> /dev/null; then
                    log_success "Deleted storage account: $storage_name"
                else
                    log_error "Failed to delete storage account: $storage_name"
                    FAILED_DELETIONS+=("Storage:$storage_name")
                fi
                ;;
        esac
        
        # Add small delay between deletions
        sleep 2
    done
}

delete_resource_groups() {
    log "Deleting resource groups..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        case "$resource" in
            RESOURCE_GROUP:*)
                local rg_name="${resource#RESOURCE_GROUP:}"
                
                log "Deleting resource group: $rg_name"
                if az group delete --name "$rg_name" --yes --no-wait &> /dev/null; then
                    log_success "Deletion initiated for resource group: $rg_name"
                else
                    log_error "Failed to delete resource group: $rg_name"
                    FAILED_DELETIONS+=("ResourceGroup:$rg_name")
                fi
                ;;
        esac
    done
}

cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "$PROJECT_ROOT/evaluation_dataset.jsonl"
        "$PROJECT_ROOT/evaluation_environment.yml"
        "$PROJECT_ROOT/model_comparison_analysis.py"
        "$PROJECT_ROOT/custom_evaluation_flow"
        "$PROJECT_ROOT/model_evaluation_job.yml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]] || [[ -d "$file" ]]; then
            log "Removing: $file"
            rm -rf "$file" 2>/dev/null || log_warning "Could not remove: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

wait_for_deletions() {
    log "Waiting for long-running deletions to complete..."
    
    local max_wait=300  # 5 minutes
    local wait_interval=15
    local total_waited=0
    
    while [[ $total_waited -lt $max_wait ]]; do
        local still_running=false
        
        # Check if any resource groups are still being deleted
        for resource in "${RESOURCES_TO_DELETE[@]}"; do
            case "$resource" in
                RESOURCE_GROUP:*)
                    local rg_name="${resource#RESOURCE_GROUP:}"
                    if az group show --name "$rg_name" &> /dev/null; then
                        still_running=true
                        log "Still deleting resource group: $rg_name"
                    fi
                    ;;
            esac
        done
        
        if [[ "$still_running" == "false" ]]; then
            log_success "All deletions completed"
            break
        fi
        
        log "Waiting for deletions to complete... ($total_waited/$max_wait seconds)"
        sleep $wait_interval
        ((total_waited += wait_interval))
    done
    
    if [[ $total_waited -ge $max_wait ]]; then
        log_warning "Timeout waiting for deletions to complete. Some resources may still be deleting in the background."
    fi
}

display_summary() {
    echo
    echo "======================================"
    echo "CLEANUP SUMMARY"
    echo "======================================"
    
    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        echo "No resources were found to delete."
    else
        echo "Resources processed: ${#RESOURCES_TO_DELETE[@]}"
        
        if [[ ${#FAILED_DELETIONS[@]} -eq 0 ]]; then
            echo "✅ All resources deleted successfully"
        else
            echo "❌ Some deletions failed:"
            for failed in "${FAILED_DELETIONS[@]}"; do
                echo "  - $failed"
            done
            echo
            echo "You may need to manually delete these resources from the Azure portal."
        fi
    fi
    
    echo "======================================"
    
    if [[ ${#FAILED_DELETIONS[@]} -gt 0 ]]; then
        exit 1
    fi
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup script encountered an error"
    display_summary
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main execution
main() {
    log "Starting AI Model Evaluation cleanup..."
    log "Cleanup log: $CLEANUP_LOG"
    
    # Redirect all output to log file while still showing on console
    exec > >(tee -a "$CLEANUP_LOG")
    exec 2>&1
    
    check_prerequisites
    discover_resource_groups
    discover_individual_resources
    confirm_deletion
    
    if [[ ${#RESOURCES_TO_DELETE[@]} -gt 0 ]]; then
        delete_individual_resources
        delete_resource_groups
        cleanup_local_files
        wait_for_deletions
    fi
    
    display_summary
    log_success "Cleanup completed!"
}

# Help function
show_help() {
    cat << EOF
AI Model Evaluation and Benchmarking Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -y, --yes               Skip confirmation prompts
    -f, --force             Force deletion without any prompts
    --no-confirm            Disable confirmation (same as --yes)
    --list-only             Only list resources that would be deleted
    --dry-run               Show what would be deleted without actually deleting

ENVIRONMENT VARIABLES:
    CONFIRM_DELETION       Set to 'false' to skip confirmations (default: true)
    FORCE_DELETE          Set to 'true' to force deletion (default: false)

EXAMPLES:
    $0                      # Interactive cleanup with confirmations
    $0 --yes               # Skip confirmation prompts
    $0 --force             # Force delete everything without prompts
    $0 --list-only         # Only show what would be deleted
    $0 --dry-run           # Dry run mode
    FORCE_DELETE=true $0   # Force delete using environment variable

SAFETY FEATURES:
    - Requires typing 'DELETE' to confirm resource group deletion
    - Lists all resources before deletion
    - Provides multiple confirmation steps
    - Logs all operations
    - Graceful handling of missing resources

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--yes|--no-confirm)
            CONFIRM_DELETION=false
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            CONFIRM_DELETION=false
            shift
            ;;
        --list-only)
            check_prerequisites
            discover_resource_groups
            discover_individual_resources
            list_resources_for_confirmation
            exit 0
            ;;
        --dry-run)
            log "DRY RUN MODE - No resources will be deleted"
            check_prerequisites
            discover_resource_groups
            discover_individual_resources
            list_resources_for_confirmation
            echo "This is what would be deleted in a real run."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main