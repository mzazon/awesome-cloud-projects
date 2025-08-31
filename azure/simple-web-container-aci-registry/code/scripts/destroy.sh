#!/bin/bash

# ==============================================================================
# Azure Container Instances Cleanup Script
# Recipe: Simple Web Container with Azure Container Instances
# 
# This script removes:
# - Azure Container Instance (ACI)
# - Azure Container Registry (ACR)
# - Resource Group (optional)
# - Local Docker images
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ==============================================================================
# CONFIGURATION AND VARIABLES
# ==============================================================================

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Default values (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
CONTAINER_REGISTRY_NAME="${CONTAINER_REGISTRY_NAME:-}"
CONTAINER_INSTANCE_NAME="${CONTAINER_INSTANCE_NAME:-}"
IMAGE_NAME="${IMAGE_NAME:-simple-nginx}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
FORCE_DELETE="${FORCE_DELETE:-false}"
KEEP_RESOURCE_GROUP="${KEEP_RESOURCE_GROUP:-false}"
DRY_RUN="${DRY_RUN:-false}"

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Logging function
log() {
    echo "[${TIMESTAMP}] $*" | tee -a "${LOG_FILE}"
}

# Error logging function
log_error() {
    echo "[${TIMESTAMP}] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Success logging function
log_success() {
    echo "[${TIMESTAMP}] ✅ $*" | tee -a "${LOG_FILE}"
}

# Warning logging function
log_warning() {
    echo "[${TIMESTAMP}] ⚠️  $*" | tee -a "${LOG_FILE}"
}

# Progress indicator
show_progress() {
    local message="$1"
    echo -n "[${TIMESTAMP}] ${message}... " | tee -a "${LOG_FILE}"
}

complete_progress() {
    echo "Done" | tee -a "${LOG_FILE}"
}

# ==============================================================================
# DISCOVERY FUNCTIONS
# ==============================================================================

discover_resources() {
    log "Discovering Azure resources to clean up..."
    
    # If resource group not specified, try to find it
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log "Searching for resource groups created by this recipe..."
        
        # Look for resource groups with the expected naming pattern
        local found_groups
        found_groups=$(az group list \
            --query "[?tags.purpose=='recipe' && tags.environment=='demo'].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${found_groups}" ]]; then
            echo "Found resource groups that appear to be created by this recipe:"
            echo "${found_groups}" | nl
            echo ""
            read -p "Enter the number of the resource group to delete (or 'all' for all groups): " choice
            
            if [[ "${choice}" == "all" ]]; then
                RESOURCE_GROUP="${found_groups}"
            else
                RESOURCE_GROUP=$(echo "${found_groups}" | sed -n "${choice}p")
            fi
        else
            log_error "No resource groups found. Please specify the resource group name."
            log "Usage: RESOURCE_GROUP=your-resource-group-name $0"
            return 1
        fi
    fi
    
    # Discover resources in the resource group
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        # Find container instances
        if [[ -z "${CONTAINER_INSTANCE_NAME}" ]]; then
            local found_instances
            found_instances=$(az container list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${found_instances}" ]]; then
                CONTAINER_INSTANCE_NAME="${found_instances}"
                log "Found container instances: ${CONTAINER_INSTANCE_NAME}"
            fi
        fi
        
        # Find container registries
        if [[ -z "${CONTAINER_REGISTRY_NAME}" ]]; then
            local found_registries
            found_registries=$(az acr list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${found_registries}" ]]; then
                CONTAINER_REGISTRY_NAME="${found_registries}"
                log "Found container registries: ${CONTAINER_REGISTRY_NAME}"
            fi
        fi
    fi
    
    log_success "Resource discovery completed"
}

# ==============================================================================
# CONFIRMATION FUNCTIONS
# ==============================================================================

confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "=================================================================="
    echo "🚨 RESOURCE DELETION CONFIRMATION"
    echo "=================================================================="
    echo "The following resources will be PERMANENTLY DELETED:"
    echo ""
    
    if [[ -n "${CONTAINER_INSTANCE_NAME}" ]]; then
        echo "📦 Container Instances:"
        echo "${CONTAINER_INSTANCE_NAME}" | sed 's/^/  - /'
    fi
    
    if [[ -n "${CONTAINER_REGISTRY_NAME}" ]]; then
        echo "🗃️  Container Registries:"
        echo "${CONTAINER_REGISTRY_NAME}" | sed 's/^/  - /'
    fi
    
    if [[ "${KEEP_RESOURCE_GROUP}" == "false" && -n "${RESOURCE_GROUP}" ]]; then
        echo "📁 Resource Groups:"
        echo "${RESOURCE_GROUP}" | sed 's/^/  - /'
    fi
    
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo "=================================================================="
    echo ""
    
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log_success "Deletion confirmed by user"
}

# ==============================================================================
# CLEANUP FUNCTIONS
# ==============================================================================

delete_container_instances() {
    if [[ -z "${CONTAINER_INSTANCE_NAME}" ]]; then
        log "No container instances to delete"
        return 0
    fi
    
    # Process each container instance
    while IFS= read -r instance_name; do
        [[ -n "${instance_name}" ]] || continue
        
        show_progress "Deleting container instance: ${instance_name}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "[DRY RUN] Would delete container instance: ${instance_name}"
            complete_progress
            continue
        fi
        
        # Check if container instance exists
        if ! az container show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${instance_name}" &> /dev/null; then
            log_warning "Container instance ${instance_name} does not exist"
            complete_progress
            continue
        fi
        
        # Delete container instance
        if az container delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${instance_name}" \
            --yes >> "${LOG_FILE}" 2>&1; then
            complete_progress
            log_success "Container instance deleted: ${instance_name}"
        else
            log_error "Failed to delete container instance: ${instance_name}"
            return 1
        fi
    done <<< "${CONTAINER_INSTANCE_NAME}"
}

delete_container_registries() {
    if [[ -z "${CONTAINER_REGISTRY_NAME}" ]]; then
        log "No container registries to delete"
        return 0
    fi
    
    # Process each container registry
    while IFS= read -r registry_name; do
        [[ -n "${registry_name}" ]] || continue
        
        show_progress "Deleting container registry: ${registry_name}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "[DRY RUN] Would delete container registry: ${registry_name}"
            complete_progress
            continue
        fi
        
        # Check if registry exists
        if ! az acr show \
            --name "${registry_name}" \
            --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_warning "Container registry ${registry_name} does not exist"
            complete_progress
            continue
        fi
        
        # Delete container registry
        if az acr delete \
            --name "${registry_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes >> "${LOG_FILE}" 2>&1; then
            complete_progress
            log_success "Container registry deleted: ${registry_name}"
        else
            log_error "Failed to delete container registry: ${registry_name}"
            return 1
        fi
    done <<< "${CONTAINER_REGISTRY_NAME}"
}

delete_resource_groups() {
    if [[ "${KEEP_RESOURCE_GROUP}" == "true" || -z "${RESOURCE_GROUP}" ]]; then
        log "Keeping resource group(s) as requested"
        return 0
    fi
    
    # Process each resource group
    while IFS= read -r group_name; do
        [[ -n "${group_name}" ]] || continue
        
        show_progress "Deleting resource group: ${group_name}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "[DRY RUN] Would delete resource group: ${group_name}"
            complete_progress
            continue
        fi
        
        # Check if resource group exists
        if ! az group show --name "${group_name}" &> /dev/null; then
            log_warning "Resource group ${group_name} does not exist"
            complete_progress
            continue
        fi
        
        # Delete resource group (no-wait for faster execution)
        if az group delete \
            --name "${group_name}" \
            --yes \
            --no-wait >> "${LOG_FILE}" 2>&1; then
            complete_progress
            log_success "Resource group deletion initiated: ${group_name}"
            log "Note: Deletion may take several minutes to complete"
        else
            log_error "Failed to delete resource group: ${group_name}"
            return 1
        fi
    done <<< "${RESOURCE_GROUP}"
}

cleanup_local_docker_images() {
    show_progress "Cleaning up local Docker images"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would clean up local Docker images"
        complete_progress
        return 0
    fi
    
    # Find and remove Docker images related to this deployment
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        # Get registry login server if available
        local registry_login_server=""
        if [[ -n "${CONTAINER_REGISTRY_NAME}" && -n "${RESOURCE_GROUP}" ]]; then
            registry_login_server=$(az acr show \
                --name "${CONTAINER_REGISTRY_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query loginServer \
                --output tsv 2>/dev/null || echo "")
        fi
        
        # Remove images matching our pattern
        local images_to_remove=""
        if [[ -n "${registry_login_server}" ]]; then
            images_to_remove=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^${registry_login_server}/${IMAGE_NAME}:" || echo "")
        fi
        
        # Also check for local images with the same name
        local local_images
        local_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^${IMAGE_NAME}:" || echo "")
        images_to_remove="${images_to_remove}${local_images:+$'\n'}${local_images}"
        
        if [[ -n "${images_to_remove}" ]]; then
            # Remove the images
            echo "${images_to_remove}" | while IFS= read -r image; do
                [[ -n "${image}" ]] || continue
                if docker rmi "${image}" >> "${LOG_FILE}" 2>&1; then
                    log "Removed Docker image: ${image}"
                else
                    log_warning "Could not remove Docker image: ${image} (may be in use)"
                fi
            done
        else
            log "No local Docker images found to remove"
        fi
    else
        log_warning "Docker not available or not running - skipping image cleanup"
    fi
    
    complete_progress
}

cleanup_local_files() {
    show_progress "Cleaning up temporary files"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would clean up temporary files"
        complete_progress
        return 0
    fi
    
    # Remove temporary nginx app directory if it exists
    local temp_dir="${SCRIPT_DIR}/temp_nginx_app"
    if [[ -d "${temp_dir}" ]]; then
        rm -rf "${temp_dir}"
        log "Removed temporary directory: ${temp_dir}"
    fi
    
    complete_progress
}

# ==============================================================================
# VERIFICATION FUNCTIONS
# ==============================================================================

verify_cleanup() {
    show_progress "Verifying resource cleanup"
    
    local cleanup_successful=true
    
    # Check container instances
    if [[ -n "${CONTAINER_INSTANCE_NAME}" && -n "${RESOURCE_GROUP}" ]]; then
        while IFS= read -r instance_name; do
            [[ -n "${instance_name}" ]] || continue
            if az container show \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${instance_name}" &> /dev/null; then
                log_warning "Container instance still exists: ${instance_name}"
                cleanup_successful=false
            fi
        done <<< "${CONTAINER_INSTANCE_NAME}"
    fi
    
    # Check container registries
    if [[ -n "${CONTAINER_REGISTRY_NAME}" && -n "${RESOURCE_GROUP}" ]]; then
        while IFS= read -r registry_name; do
            [[ -n "${registry_name}" ]] || continue
            if az acr show \
                --name "${registry_name}" \
                --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
                log_warning "Container registry still exists: ${registry_name}"
                cleanup_successful=false
            fi
        done <<< "${CONTAINER_REGISTRY_NAME}"
    fi
    
    # Check resource groups (only if we're deleting them)
    if [[ "${KEEP_RESOURCE_GROUP}" == "false" && -n "${RESOURCE_GROUP}" ]]; then
        while IFS= read -r group_name; do
            [[ -n "${group_name}" ]] || continue
            if az group show --name "${group_name}" &> /dev/null; then
                log_warning "Resource group still exists (deletion may be in progress): ${group_name}"
                # This is not necessarily an error as deletion can take time
            fi
        done <<< "${RESOURCE_GROUP}"
    fi
    
    complete_progress
    
    if [[ "${cleanup_successful}" == "true" ]]; then
        log_success "Resource cleanup verification completed successfully"
    else
        log_warning "Some resources may still exist - check Azure portal or run verification commands manually"
    fi
}

# ==============================================================================
# HELP FUNCTION
# ==============================================================================

show_help() {
    cat << EOF
Azure Container Instances Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deleted without actually deleting
    -f, --force            Delete resources without confirmation prompt
    -g, --resource-group   Specify resource group name
    -r, --registry         Specify container registry name
    -i, --instance         Specify container instance name
    -k, --keep-rg          Keep resource group (delete only contained resources)
    --image-name           Specify container image name for local cleanup
    --image-tag            Specify container image tag for local cleanup

ENVIRONMENT VARIABLES:
    RESOURCE_GROUP              Override resource group name
    CONTAINER_REGISTRY_NAME     Override container registry name
    CONTAINER_INSTANCE_NAME     Override container instance name
    IMAGE_NAME                  Override container image name for local cleanup
    IMAGE_TAG                   Override container image tag for local cleanup
    FORCE_DELETE                Set to 'true' to skip confirmation
    KEEP_RESOURCE_GROUP         Set to 'true' to keep resource group
    DRY_RUN                     Set to 'true' for dry run mode

EXAMPLES:
    # Interactive cleanup (discovers resources automatically)
    $0

    # Cleanup specific resource group
    $0 --resource-group my-rg

    # Dry run to see what would be deleted
    $0 --dry-run

    # Force cleanup without confirmation
    $0 --force

    # Keep resource group, delete only resources inside
    $0 --keep-rg --resource-group my-rg

VERIFICATION COMMANDS:
    After running this script, you can verify cleanup with:
    
    # List remaining container instances
    az container list --resource-group <resource-group>
    
    # List remaining container registries
    az acr list --resource-group <resource-group>
    
    # Check if resource group exists
    az group show --name <resource-group>
    
    # List local Docker images
    docker images

EOF
}

# ==============================================================================
# COMMAND LINE ARGUMENT PARSING
# ==============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -f|--force)
                FORCE_DELETE="true"
                shift
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -r|--registry)
                CONTAINER_REGISTRY_NAME="$2"
                shift 2
                ;;
            -i|--instance)
                CONTAINER_INSTANCE_NAME="$2"
                shift 2
                ;;
            -k|--keep-rg)
                KEEP_RESOURCE_GROUP="true"
                shift
                ;;
            --image-name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                log "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    # Initialize log file
    echo "===== Azure Container Instances Cleanup Log - ${TIMESTAMP} =====" > "${LOG_FILE}"
    
    log "Starting Azure Container Instances cleanup..."
    log "Script directory: ${SCRIPT_DIR}"
    log "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Display configuration
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "🔍 DRY RUN MODE - No resources will be deleted"
    fi
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log "🔥 FORCE DELETE MODE - Skipping confirmation prompts"
    fi
    
    # Check Azure CLI availability
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Execute cleanup steps
    discover_resources || exit 1
    confirm_deletion
    delete_container_instances || exit 1
    delete_container_registries || exit 1
    delete_resource_groups || exit 1
    cleanup_local_docker_images
    cleanup_local_files
    verify_cleanup
    
    # Display completion message
    echo ""
    echo "=================================================================="
    echo "🎯 CLEANUP COMPLETED!"
    echo "=================================================================="
    echo "The following actions were performed:"
    echo ""
    
    if [[ -n "${CONTAINER_INSTANCE_NAME}" ]]; then
        echo "✅ Deleted container instances: ${CONTAINER_INSTANCE_NAME}"
    fi
    
    if [[ -n "${CONTAINER_REGISTRY_NAME}" ]]; then
        echo "✅ Deleted container registries: ${CONTAINER_REGISTRY_NAME}"
    fi
    
    if [[ "${KEEP_RESOURCE_GROUP}" == "false" && -n "${RESOURCE_GROUP}" ]]; then
        echo "✅ Initiated deletion of resource groups: ${RESOURCE_GROUP}"
        echo "   Note: Resource group deletion may take several minutes to complete"
    fi
    
    echo "✅ Cleaned up local Docker images and temporary files"
    echo ""
    echo "💰 Resource cleanup helps avoid ongoing charges"
    echo "📋 Check ${LOG_FILE} for detailed cleanup logs"
    echo "=================================================================="
    
    log_success "Cleanup completed successfully!"
    log "Total cleanup time: $(($(date +%s) - $(date -d "${TIMESTAMP}" +%s 2>/dev/null || echo 0))) seconds"
}

# Execute main function with all arguments
main "$@"