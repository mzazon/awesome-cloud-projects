#!/bin/bash

# =============================================================================
# Azure Serverless AI Prompt Workflow Cleanup Script
# Recipe: Orchestrating Serverless AI Prompt Workflows with Azure AI Studio 
#         Prompt Flow and Azure Container Apps
# =============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line ${line_number}. Some resources may not have been cleaned up."
    log_warning "Please check the Azure portal for any remaining resources."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Configuration variables
RESOURCE_GROUP=""
LOCATION=""
DELETE_RESOURCE_GROUP=""
FORCE_DELETE=""
DRY_RUN="false"

# Function to load deployment information
load_deployment_info() {
    local info_file="${PWD}/deployment-info.txt"
    
    if [[ -f "${info_file}" ]]; then
        log_info "Loading deployment information from ${info_file}..."
        
        # Source the deployment info file
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Export the variable
            export "$key"="$value"
        done < <(grep -E '^[A-Z_]+=.*' "${info_file}")
        
        # Set main variables from deployment info
        RESOURCE_GROUP="${RESOURCE_GROUP:-}"
        LOCATION="${LOCATION:-}"
        
        if [[ -n "${RESOURCE_GROUP}" ]]; then
            log_success "Loaded deployment information for resource group: ${RESOURCE_GROUP}"
        else
            log_warning "Could not load resource group from deployment info"
        fi
    else
        log_warning "Deployment info file not found: ${info_file}"
        log_info "You will need to specify the resource group manually"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate resource group
validate_resource_group() {
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "Resource group not specified. Please provide it as an argument or ensure deployment-info.txt exists."
        echo "Usage: $0 --resource-group <resource-group-name>"
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
        if [[ "${FORCE_DELETE}" != "true" ]]; then
            exit 1
        fi
    else
        log_info "Found resource group: ${RESOURCE_GROUP}"
    fi
}

# Function to list resources in the resource group
list_resources() {
    log_info "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    local resources
    resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type, Location:location}' --output table 2>/dev/null || echo "")
    
    if [[ -n "${resources}" ]]; then
        echo "Resources to be deleted:"
        echo "${resources}"
        echo
    else
        log_warning "No resources found in resource group ${RESOURCE_GROUP}"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    echo "======================================================================"
    log_warning "WARNING: This will permanently delete all resources in the resource group!"
    log_warning "Resource Group: ${RESOURCE_GROUP}"
    echo "======================================================================"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r response
    case "$response" in
        [yY][eE][sS])
            log_info "Proceeding with resource deletion..."
            ;;
        *)
            log_info "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# Function to delete Container Apps resources
delete_container_apps() {
    log_info "Deleting Container Apps resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Container Apps and environment"
        return 0
    fi
    
    # Get all container apps in the resource group
    local container_apps
    container_apps=$(az containerapp list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${container_apps}" ]]; then
        for app in ${container_apps}; do
            log_info "Deleting Container App: ${app}"
            az containerapp delete \
                --name "${app}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || log_warning "Failed to delete Container App ${app}"
        done
        log_success "Container Apps deletion initiated"
    else
        log_info "No Container Apps found to delete"
    fi
    
    # Wait a bit for container apps to be deleted before deleting environments
    if [[ -n "${container_apps}" ]]; then
        log_info "Waiting for Container Apps to be deleted..."
        sleep 30
    fi
    
    # Get all container app environments in the resource group
    local environments
    environments=$(az containerapp env list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${environments}" ]]; then
        for env in ${environments}; do
            log_info "Deleting Container Apps Environment: ${env}"
            az containerapp env delete \
                --name "${env}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || log_warning "Failed to delete Container Apps Environment ${env}"
        done
        log_success "Container Apps Environments deletion initiated"
    else
        log_info "No Container Apps Environments found to delete"
    fi
}

# Function to delete AI/ML resources
delete_ai_resources() {
    log_info "Deleting AI/ML resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete AI Hub, Projects, and Azure OpenAI resources"
        return 0
    fi
    
    # Delete AI projects first (they depend on hubs)
    local ai_projects
    ai_projects=$(az ml workspace list --resource-group "${RESOURCE_GROUP}" --query '[?kind==`project`].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${ai_projects}" ]]; then
        for project in ${ai_projects}; do
            log_info "Deleting AI Project: ${project}"
            az ml workspace delete \
                --name "${project}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || log_warning "Failed to delete AI Project ${project}"
        done
        log_success "AI Projects deletion initiated"
    else
        log_info "No AI Projects found to delete"
    fi
    
    # Delete AI hubs
    local ai_hubs
    ai_hubs=$(az ml workspace list --resource-group "${RESOURCE_GROUP}" --query '[?kind==`hub`].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${ai_hubs}" ]]; then
        for hub in ${ai_hubs}; do
            log_info "Deleting AI Hub: ${hub}"
            az ml workspace delete \
                --name "${hub}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || log_warning "Failed to delete AI Hub ${hub}"
        done
        log_success "AI Hubs deletion initiated"
    else
        log_info "No AI Hubs found to delete"
    fi
    
    # Delete Azure OpenAI resources
    local openai_accounts
    openai_accounts=$(az cognitiveservices account list --resource-group "${RESOURCE_GROUP}" --query '[?kind==`OpenAI`].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${openai_accounts}" ]]; then
        for account in ${openai_accounts}; do
            log_info "Deleting Azure OpenAI account: ${account}"
            az cognitiveservices account delete \
                --name "${account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log_warning "Failed to delete Azure OpenAI account ${account}"
        done
        log_success "Azure OpenAI accounts deleted"
    else
        log_info "No Azure OpenAI accounts found to delete"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Application Insights and Log Analytics workspaces"
        return 0
    fi
    
    # Delete Application Insights components
    local app_insights
    app_insights=$(az monitor app-insights component list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${app_insights}" ]]; then
        for component in ${app_insights}; do
            log_info "Deleting Application Insights: ${component}"
            az monitor app-insights component delete \
                --app "${component}" \
                --resource-group "${RESOURCE_GROUP}" || log_warning "Failed to delete Application Insights ${component}"
        done
        log_success "Application Insights components deleted"
    else
        log_info "No Application Insights components found to delete"
    fi
    
    # Delete metric alerts
    local alerts
    alerts=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${alerts}" ]]; then
        for alert in ${alerts}; do
            log_info "Deleting metric alert: ${alert}"
            az monitor metrics alert delete \
                --name "${alert}" \
                --resource-group "${RESOURCE_GROUP}" || log_warning "Failed to delete alert ${alert}"
        done
        log_success "Metric alerts deleted"
    else
        log_info "No metric alerts found to delete"
    fi
    
    # Delete Log Analytics workspaces
    local workspaces
    workspaces=$(az monitor log-analytics workspace list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${workspaces}" ]]; then
        for workspace in ${workspaces}; do
            log_info "Deleting Log Analytics workspace: ${workspace}"
            az monitor log-analytics workspace delete \
                --workspace-name "${workspace}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --force || log_warning "Failed to delete Log Analytics workspace ${workspace}"
        done
        log_success "Log Analytics workspaces deleted"
    else
        log_info "No Log Analytics workspaces found to delete"
    fi
}

# Function to delete storage and registry resources
delete_storage_resources() {
    log_info "Deleting storage and registry resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Container Registries and Storage Accounts"
        return 0
    fi
    
    # Delete Container Registries
    local registries
    registries=$(az acr list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${registries}" ]]; then
        for registry in ${registries}; do
            log_info "Deleting Container Registry: ${registry}"
            az acr delete \
                --name "${registry}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log_warning "Failed to delete Container Registry ${registry}"
        done
        log_success "Container Registries deleted"
    else
        log_info "No Container Registries found to delete"
    fi
    
    # Delete Storage Accounts
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${storage_accounts}" ]]; then
        for account in ${storage_accounts}; do
            log_info "Deleting Storage Account: ${account}"
            az storage account delete \
                --name "${account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log_warning "Failed to delete Storage Account ${account}"
        done
        log_success "Storage Accounts deleted"
    else
        log_info "No Storage Accounts found to delete"
    fi
}

# Function to delete the entire resource group
delete_resource_group() {
    if [[ "${DELETE_RESOURCE_GROUP}" != "true" ]]; then
        log_info "Skipping resource group deletion (use --delete-resource-group to enable)"
        return 0
    fi
    
    log_info "Deleting entire resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Complete deletion may take several minutes"
}

# Function to wait for deletions to complete
wait_for_deletions() {
    if [[ "${DRY_RUN}" == "true" ]] || [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        return 0
    fi
    
    log_info "Waiting for resource deletions to complete..."
    
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=30
    
    while [[ $wait_time -lt $max_wait ]]; do
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length([])' -o tsv 2>/dev/null || echo "0")
        
        if [[ "${remaining_resources}" == "0" ]]; then
            log_success "All resources have been deleted"
            break
        fi
        
        log_info "Still waiting... ${remaining_resources} resources remaining"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log_warning "Timeout waiting for deletions to complete. Some resources may still be deleting."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=("deployment-info.txt")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove ${file}"
            else
                rm -f "${file}"
                log_success "Removed ${file}"
            fi
        fi
    done
    
    # Clean up any Docker images
    if command -v docker &> /dev/null; then
        local images
        images=$(docker images --filter=reference="promptflow-app*" --format "table {{.Repository}}:{{.Tag}}" --no-trunc 2>/dev/null | tail -n +2 || echo "")
        
        if [[ -n "${images}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove Docker images: ${images}"
            else
                echo "${images}" | xargs -r docker rmi -f 2>/dev/null || log_warning "Could not remove some Docker images"
                log_success "Removed local Docker images"
            fi
        fi
    fi
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Cleanup verification skipped"
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_success "Resource group successfully deleted"
        else
            log_warning "Resource group still exists (deletion may be in progress)"
        fi
    else
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length([])' -o tsv 2>/dev/null || echo "0")
        
        if [[ "${remaining_resources}" == "0" ]]; then
            log_success "All resources successfully deleted from resource group"
        else
            log_warning "${remaining_resources} resources still remain in the resource group"
            az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type}' --output table 2>/dev/null || true
        fi
    fi
}

# Main cleanup function
main() {
    echo "======================================================================"
    echo "Azure Serverless AI Prompt Workflow Cleanup"
    echo "======================================================================"
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --delete-resource-group)
                DELETE_RESOURCE_GROUP="true"
                shift
                ;;
            --force)
                FORCE_DELETE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --resource-group NAME      Resource group to clean up (required)"
                echo "  --delete-resource-group    Delete the entire resource group"
                echo "  --force                    Skip confirmation prompts"
                echo "  --dry-run                  Show what would be deleted without doing it"
                echo "  --help                     Show this help message"
                echo
                echo "Examples:"
                echo "  $0 --resource-group my-rg"
                echo "  $0 --resource-group my-rg --delete-resource-group"
                echo "  $0 --dry-run --resource-group my-rg"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Load deployment info if no resource group specified
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        load_deployment_info
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
        echo
    fi
    
    # Execute cleanup steps
    check_prerequisites
    validate_resource_group
    list_resources
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        confirm_deletion
        delete_resource_group
    else
        confirm_deletion
        delete_container_apps
        delete_ai_resources
        delete_monitoring_resources
        delete_storage_resources
        wait_for_deletions
    fi
    
    cleanup_local_files
    verify_cleanup
    
    echo
    echo "======================================================================"
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "DRY RUN COMPLETED - No resources were deleted"
    else
        log_success "CLEANUP COMPLETED!"
        echo
        if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
            log_info "🗑️  Resource group deletion initiated"
            log_info "⏳ Complete deletion may take several minutes"
        else
            log_info "🧹 Individual resources have been cleaned up"
            log_info "💡 Use --delete-resource-group to remove the resource group entirely"
        fi
        echo
        log_info "📋 Check the Azure portal to verify all resources are deleted"
    fi
    echo "======================================================================"
}

# Execute main function with all arguments
main "$@"