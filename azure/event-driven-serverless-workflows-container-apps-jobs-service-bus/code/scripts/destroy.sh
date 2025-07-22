#!/bin/bash

# Azure Event-Driven Serverless Workflows Cleanup Script
# Recipe: Event-Driven Serverless Workflows with Azure Container Apps Jobs and Azure Service Bus
# Description: Safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# ANSI color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup-$(date +%Y%m%d-%H%M%S).log"
readonly INFO_FILE="${SCRIPT_DIR}/deployment-info.env"

# Global variables
FORCE_DELETE=false
DRY_RUN=false

# Cleanup function for script itself
script_cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 && ${exit_code} -ne 130 ]]; then
        echo -e "${RED}❌ Cleanup script failed. Check ${LOG_FILE} for details.${NC}"
    fi
    exit ${exit_code}
}

trap script_cleanup EXIT

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

print_status() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -f, --force          Skip confirmation prompts (use with caution)
    -d, --dry-run        Show what would be deleted without actually deleting
    -h, --help           Show this help message

Environment Variables (can be set before running):
    RESOURCE_GROUP       Name of the resource group to delete (required)
    SERVICE_BUS_NAMESPACE Service Bus namespace name
    CONTAINER_REGISTRY_NAME Container registry name
    JOB_NAME            Container Apps job name
    ENVIRONMENT_NAME    Container Apps environment name

Examples:
    $0                   # Interactive cleanup with confirmations
    $0 --dry-run         # Show what would be deleted
    $0 --force           # Delete without confirmation prompts
    
    # With environment variables:
    RESOURCE_GROUP=my-rg $0

Note: If deployment-info.env exists, it will be loaded automatically.
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    print_status "Azure CLI version: ${az_version}"
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    print_status "Loading deployment information..."
    
    # Try to load from deployment-info.env file first
    if [[ -f "${INFO_FILE}" ]]; then
        print_status "Loading configuration from ${INFO_FILE}"
        # shellcheck source=/dev/null
        source "${INFO_FILE}"
        print_success "Configuration loaded from deployment info file"
    else
        print_warning "No deployment info file found at ${INFO_FILE}"
    fi
    
    # Set defaults for any missing variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    export LOCATION="${LOCATION:-eastus}"
    export ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-env-container-jobs}"
    export SERVICE_BUS_NAMESPACE="${SERVICE_BUS_NAMESPACE:-}"
    export QUEUE_NAME="${QUEUE_NAME:-message-processing-queue}"
    export CONTAINER_REGISTRY_NAME="${CONTAINER_REGISTRY_NAME:-}"
    export JOB_NAME="${JOB_NAME:-message-processor-job}"
    export CONTAINER_IMAGE_NAME="${CONTAINER_IMAGE_NAME:-message-processor:1.0}"
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        print_error "RESOURCE_GROUP is required but not set."
        echo -e "${YELLOW}Set it as an environment variable or ensure deployment-info.env exists.${NC}"
        echo -e "${YELLOW}Example: RESOURCE_GROUP=my-resource-group $0${NC}"
        exit 1
    fi
    
    # Display current configuration
    cat << EOF | tee -a "${LOG_FILE}"

📋 Cleanup Configuration:
   Resource Group: ${RESOURCE_GROUP}
   Location: ${LOCATION}
   Container Environment: ${ENVIRONMENT_NAME}
   Service Bus Namespace: ${SERVICE_BUS_NAMESPACE:-<auto-detect>}
   Queue Name: ${QUEUE_NAME}
   Container Registry: ${CONTAINER_REGISTRY_NAME:-<auto-detect>}
   Job Name: ${JOB_NAME}
   Container Image: ${CONTAINER_IMAGE_NAME}

EOF
}

# Check if resource group exists
check_resource_group() {
    print_status "Checking if resource group exists..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        print_success "Resource group '${RESOURCE_GROUP}' found"
        return 0
    else
        print_warning "Resource group '${RESOURCE_GROUP}' not found"
        return 1
    fi
}

# Get list of resources in the resource group
list_resources() {
    print_status "Discovering resources in resource group..."
    
    if ! check_resource_group; then
        print_warning "Cannot list resources - resource group does not exist"
        return 1
    fi
    
    local resources
    if resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type, Location:location}' --output table 2>> "${LOG_FILE}"); then
        if [[ -n "${resources}" ]]; then
            echo -e "${BLUE}📦 Resources found in '${RESOURCE_GROUP}':${NC}"
            echo "${resources}" | tee -a "${LOG_FILE}"
        else
            print_warning "No resources found in resource group '${RESOURCE_GROUP}'"
        fi
    else
        print_error "Failed to list resources in resource group"
        return 1
    fi
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == true ]]; then
        print_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${YELLOW}"
    cat << 'EOF'
⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️

This will permanently delete all resources in the specified resource group.
This action cannot be undone and may result in data loss.

Resources that will be deleted include:
• Azure Container Apps Jobs and Environment
• Azure Service Bus Namespace and Queues  
• Azure Container Registry and Images
• Log Analytics Workspace
• All monitoring and alert rules
• Any other resources in the resource group

EOF
    echo -e "${NC}"
    
    echo -n "Are you sure you want to proceed? (Type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        print_status "Cleanup canceled by user"
        exit 0
    fi
    
    print_warning "User confirmed deletion"
}

# Delete specific Container Apps job
delete_container_apps_job() {
    if [[ -z "${JOB_NAME}" ]]; then
        print_warning "Job name not specified, skipping Container Apps job deletion"
        return 0
    fi
    
    print_status "Deleting Container Apps job: ${JOB_NAME}"
    
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "[DRY RUN] Would delete Container Apps job: ${JOB_NAME}"
        return 0
    fi
    
    # Check if job exists
    if az containerapp job show --name "${JOB_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        if az containerapp job delete \
            --name "${JOB_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            &>> "${LOG_FILE}"; then
            print_success "Container Apps job deleted: ${JOB_NAME}"
        else
            print_warning "Failed to delete Container Apps job: ${JOB_NAME}"
        fi
    else
        print_warning "Container Apps job not found: ${JOB_NAME}"
    fi
}

# Delete Container Apps environment
delete_container_apps_environment() {
    if [[ -z "${ENVIRONMENT_NAME}" ]]; then
        print_warning "Environment name not specified, skipping Container Apps environment deletion"
        return 0
    fi
    
    print_status "Deleting Container Apps environment: ${ENVIRONMENT_NAME}"
    
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "[DRY RUN] Would delete Container Apps environment: ${ENVIRONMENT_NAME}"
        return 0
    fi
    
    # Check if environment exists
    if az containerapp env show --name "${ENVIRONMENT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        if az containerapp env delete \
            --name "${ENVIRONMENT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            &>> "${LOG_FILE}"; then
            print_success "Container Apps environment deleted: ${ENVIRONMENT_NAME}"
        else
            print_warning "Failed to delete Container Apps environment: ${ENVIRONMENT_NAME}"
        fi
    else
        print_warning "Container Apps environment not found: ${ENVIRONMENT_NAME}"
    fi
}

# Delete Service Bus namespace
delete_service_bus() {
    if [[ -z "${SERVICE_BUS_NAMESPACE}" ]]; then
        print_warning "Service Bus namespace not specified, checking for any Service Bus resources..."
        
        # Try to find Service Bus namespaces in the resource group
        local namespaces
        if namespaces=$(az servicebus namespace list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv 2>> "${LOG_FILE}"); then
            if [[ -n "${namespaces}" ]]; then
                print_status "Found Service Bus namespaces: ${namespaces}"
                for ns in ${namespaces}; do
                    print_status "Deleting Service Bus namespace: ${ns}"
                    if [[ "${DRY_RUN}" == true ]]; then
                        print_status "[DRY RUN] Would delete Service Bus namespace: ${ns}"
                    else
                        if az servicebus namespace delete --name "${ns}" --resource-group "${RESOURCE_GROUP}" &>> "${LOG_FILE}"; then
                            print_success "Service Bus namespace deleted: ${ns}"
                        else
                            print_warning "Failed to delete Service Bus namespace: ${ns}"
                        fi
                    fi
                done
            else
                print_warning "No Service Bus namespaces found in resource group"
            fi
        fi
        return 0
    fi
    
    print_status "Deleting Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
    
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "[DRY RUN] Would delete Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
        return 0
    fi
    
    # Check if namespace exists
    if az servicebus namespace show --name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        if az servicebus namespace delete \
            --name "${SERVICE_BUS_NAMESPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            &>> "${LOG_FILE}"; then
            print_success "Service Bus namespace deleted: ${SERVICE_BUS_NAMESPACE}"
        else
            print_warning "Failed to delete Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
        fi
    else
        print_warning "Service Bus namespace not found: ${SERVICE_BUS_NAMESPACE}"
    fi
}

# Delete Container Registry
delete_container_registry() {
    if [[ -z "${CONTAINER_REGISTRY_NAME}" ]]; then
        print_warning "Container Registry name not specified, checking for any ACR resources..."
        
        # Try to find Container Registries in the resource group
        local registries
        if registries=$(az acr list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv 2>> "${LOG_FILE}"); then
            if [[ -n "${registries}" ]]; then
                print_status "Found Container Registries: ${registries}"
                for registry in ${registries}; do
                    print_status "Deleting Container Registry: ${registry}"
                    if [[ "${DRY_RUN}" == true ]]; then
                        print_status "[DRY RUN] Would delete Container Registry: ${registry}"
                    else
                        if az acr delete --name "${registry}" --resource-group "${RESOURCE_GROUP}" --yes &>> "${LOG_FILE}"; then
                            print_success "Container Registry deleted: ${registry}"
                        else
                            print_warning "Failed to delete Container Registry: ${registry}"
                        fi
                    fi
                done
            else
                print_warning "No Container Registries found in resource group"
            fi
        fi
        return 0
    fi
    
    print_status "Deleting Container Registry: ${CONTAINER_REGISTRY_NAME}"
    
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "[DRY RUN] Would delete Container Registry: ${CONTAINER_REGISTRY_NAME}"
        return 0
    fi
    
    # Check if registry exists
    if az acr show --name "${CONTAINER_REGISTRY_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        if az acr delete \
            --name "${CONTAINER_REGISTRY_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            &>> "${LOG_FILE}"; then
            print_success "Container Registry deleted: ${CONTAINER_REGISTRY_NAME}"
        else
            print_warning "Failed to delete Container Registry: ${CONTAINER_REGISTRY_NAME}"
        fi
    else
        print_warning "Container Registry not found: ${CONTAINER_REGISTRY_NAME}"
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    print_status "Deleting monitoring and alert resources..."
    
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "[DRY RUN] Would delete monitoring and alert resources"
        return 0
    fi
    
    # Delete metric alerts
    local alerts
    if alerts=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query '[].name' --output tsv 2>> "${LOG_FILE}"); then
        if [[ -n "${alerts}" ]]; then
            for alert in ${alerts}; do
                print_status "Deleting metric alert: ${alert}"
                if az monitor metrics alert delete --name "${alert}" --resource-group "${RESOURCE_GROUP}" &>> "${LOG_FILE}"; then
                    print_success "Metric alert deleted: ${alert}"
                else
                    print_warning "Failed to delete metric alert: ${alert}"
                fi
            done
        else
            print_warning "No metric alerts found"
        fi
    fi
}

# Delete the entire resource group
delete_resource_group() {
    print_status "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == true ]]; then
        print_status "[DRY RUN] Would delete resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    if ! check_resource_group; then
        print_warning "Resource group already deleted or does not exist"
        return 0
    fi
    
    # Final confirmation for resource group deletion
    if [[ "${FORCE_DELETE}" != true ]]; then
        echo -e "${RED}"
        echo "🚨 FINAL WARNING: About to delete ENTIRE resource group '${RESOURCE_GROUP}'"
        echo "This will delete ALL resources in the group, not just the ones created by this recipe."
        echo -e "${NC}"
        echo -n "Type 'DELETE' to confirm resource group deletion: "
        read -r final_confirmation
        
        if [[ "${final_confirmation}" != "DELETE" ]]; then
            print_status "Resource group deletion canceled by user"
            print_status "Individual resources may have been deleted"
            return 0
        fi
    fi
    
    print_status "Initiating resource group deletion (this may take several minutes)..."
    if az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        &>> "${LOG_FILE}"; then
        print_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        print_status "Note: Deletion continues in the background and may take several minutes to complete"
    else
        print_error "Failed to initiate resource group deletion"
        return 1
    fi
}

# Clean up local files
cleanup_local_files() {
    print_status "Cleaning up local files..."
    
    if [[ "${DRY_RUN}" == true ]]; then
        if [[ -f "${INFO_FILE}" ]]; then
            print_status "[DRY RUN] Would delete deployment info file: ${INFO_FILE}"
        fi
        return 0
    fi
    
    # Remove deployment info file
    if [[ -f "${INFO_FILE}" ]]; then
        if rm -f "${INFO_FILE}"; then
            print_success "Deployment info file deleted: ${INFO_FILE}"
        else
            print_warning "Failed to delete deployment info file: ${INFO_FILE}"
        fi
    else
        print_warning "Deployment info file not found: ${INFO_FILE}"
    fi
    
    # Clean up any temporary deployment logs (keep current cleanup log)
    local log_pattern="${SCRIPT_DIR}/deployment-*.log"
    if compgen -G "${log_pattern}" > /dev/null; then
        print_status "Cleaning up old deployment logs..."
        find "${SCRIPT_DIR}" -name "deployment-*.log" -type f -mtime +7 -delete 2>/dev/null || true
        print_success "Old deployment logs cleaned up"
    fi
}

# Show cleanup summary
show_cleanup_summary() {
    local end_time
    end_time=$(date)
    
    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "${BLUE}"
        cat << EOF

🔍 DRY RUN SUMMARY

The following actions would be performed:

✓ Container Apps Job: ${JOB_NAME:-<not specified>}
✓ Container Apps Environment: ${ENVIRONMENT_NAME:-<not specified>}
✓ Service Bus Namespace: ${SERVICE_BUS_NAMESPACE:-<auto-detect>}
✓ Container Registry: ${CONTAINER_REGISTRY_NAME:-<auto-detect>}
✓ Monitoring and Alert Resources
✓ Resource Group: ${RESOURCE_GROUP}
✓ Local deployment files

To perform the actual cleanup, run without --dry-run flag.

EOF
        echo -e "${NC}"
        return 0
    fi
    
    echo -e "${GREEN}"
    cat << EOF

🧹 CLEANUP COMPLETED

Summary of actions taken:
✅ Container Apps resources removed
✅ Service Bus resources removed  
✅ Container Registry resources removed
✅ Monitoring and alert resources removed
✅ Resource group deletion initiated: ${RESOURCE_GROUP}
✅ Local deployment files cleaned up

📋 Important Notes:
• Resource group deletion continues in background
• It may take 5-15 minutes for complete removal
• You can verify completion in the Azure portal
• All associated costs should stop accruing

🔗 Verification:
   Check deletion status: az group show --name ${RESOURCE_GROUP}
   (Should return "ResourceGroupNotFound" when complete)

📝 Cleanup log: ${LOG_FILE}
⏰ Cleanup completed at: ${end_time}

✨ Environment successfully cleaned up!

EOF
    echo -e "${NC}"
}

# Main cleanup function
main() {
    log "Starting Azure Event-Driven Serverless Workflows cleanup..."
    
    echo -e "${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║    Azure Event-Driven Serverless Workflows Cleanup             ║
║                                                                  ║
║    This script will remove:                                     ║
║    • Azure Container Apps Jobs and Environment                  ║
║    • Azure Service Bus Namespace and Queues                     ║
║    • Azure Container Registry and Images                        ║
║    • Monitoring and Alert Resources                             ║
║    • Resource Group and all contained resources                 ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    parse_arguments "$@"
    check_prerequisites
    load_deployment_info
    list_resources
    
    if [[ "${DRY_RUN}" != true ]]; then
        confirm_deletion
    fi
    
    # Individual resource cleanup (in reverse order of creation)
    delete_monitoring_resources
    delete_container_apps_job
    delete_container_apps_environment
    delete_service_bus
    delete_container_registry
    
    # Complete cleanup
    delete_resource_group
    cleanup_local_files
    
    show_cleanup_summary
    log "Cleanup process completed"
}

# Run main function with all arguments
main "$@"