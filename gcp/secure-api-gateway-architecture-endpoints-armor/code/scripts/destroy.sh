#!/bin/bash

# Secure API Gateway Architecture with Cloud Endpoints and Cloud Armor - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1. Exit code: $2"
    log_warning "Some resources may still exist. Please check manually."
}

# Set trap for error handling (non-fatal during cleanup)
trap 'handle_error ${LINENO} $?' ERR

# Banner
echo "=================================================="
echo "Secure API Gateway Architecture Cleanup"
echo "Removing Cloud Endpoints + Cloud Armor + Load Balancing"
echo "=================================================="
echo

# Load configuration from deployment
load_config() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "deployment-config.env" ]]; then
        # shellcheck source=/dev/null
        source deployment-config.env
        log_success "Configuration loaded from deployment-config.env"
    else
        log_warning "deployment-config.env not found. Using defaults or prompting for values."
        
        # Prompt for essential values if config file is missing
        if [[ -z "${PROJECT_ID:-}" ]]; then
            echo -n "Enter Project ID to clean up: "
            read -r PROJECT_ID
            export PROJECT_ID
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="us-central1"
            export ZONE="us-central1-a"
        fi
    fi
    
    # Set project context
    if [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud config set project "${PROJECT_ID}"
        log_info "Using project: ${PROJECT_ID}"
    else
        log_error "PROJECT_ID is required for cleanup"
        exit 1
    fi
}

# Confirm destructive action
confirm_cleanup() {
    echo
    log_warning "This will DELETE ALL resources created by the secure API gateway deployment."
    log_warning "Project: ${PROJECT_ID}"
    log_warning "This action CANNOT be undone."
    echo
    
    # Allow bypass for automated cleanup
    if [[ "${FORCE_CLEANUP:-}" == "true" ]]; then
        log_info "Force cleanup mode enabled. Proceeding without confirmation."
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r confirmation
    
    case $confirmation in
        yes|YES|y|Y)
            log_info "Proceeding with cleanup..."
            ;;
        *)
            log_info "Cleanup cancelled by user."
            exit 0
            ;;
    esac
}

# Generic resource deletion with error handling
delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local zone_flag="${3:-}"
    local extra_flags="${4:-}"
    
    if [[ -n "${zone_flag}" ]]; then
        zone_flag="--zone=${zone_flag}"
    fi
    
    log_info "Deleting ${resource_type}: ${resource_name}"
    
    # Check if resource exists before attempting deletion
    if gcloud compute "${resource_type}" describe "${resource_name}" ${zone_flag} ${extra_flags} &>/dev/null; then
        if gcloud compute "${resource_type}" delete "${resource_name}" ${zone_flag} ${extra_flags} --quiet; then
            log_success "Deleted ${resource_type}: ${resource_name}"
        else
            log_warning "Failed to delete ${resource_type}: ${resource_name} (may not exist or have dependencies)"
        fi
    else
        log_info "${resource_type} ${resource_name} does not exist or already deleted"
    fi
}

# Remove load balancer and networking resources
cleanup_load_balancer() {
    log_info "Cleaning up load balancer and networking resources..."
    
    # Delete forwarding rule
    delete_resource "forwarding-rules" "esp-forwarding-rule" "" "--global"
    
    # Delete target proxy
    delete_resource "target-http-proxies" "esp-http-proxy" "" "--global"
    
    # Delete URL map
    delete_resource "url-maps" "esp-url-map" "" "--global"
    
    # Delete backend service
    delete_resource "backend-services" "esp-backend-service" "" "--global"
    
    # Delete health check
    delete_resource "health-checks" "esp-health-check" "" ""
    
    # Delete instance group
    if [[ -n "${ZONE:-}" ]]; then
        delete_resource "instance-groups" "esp-proxy-group" "${ZONE}" "--type=unmanaged"
    fi
    
    log_success "Load balancer resources cleanup completed"
}

# Remove security and compute resources
cleanup_security_compute() {
    log_info "Cleaning up security and compute resources..."
    
    # Delete Cloud Armor security policy
    if [[ -n "${SECURITY_POLICY_NAME:-}" ]]; then
        log_info "Deleting Cloud Armor security policy: ${SECURITY_POLICY_NAME}"
        if gcloud compute security-policies describe "${SECURITY_POLICY_NAME}" &>/dev/null; then
            if gcloud compute security-policies delete "${SECURITY_POLICY_NAME}" --quiet; then
                log_success "Deleted security policy: ${SECURITY_POLICY_NAME}"
            else
                log_warning "Failed to delete security policy: ${SECURITY_POLICY_NAME}"
            fi
        else
            log_info "Security policy ${SECURITY_POLICY_NAME} does not exist"
        fi
    fi
    
    # Delete compute instances
    if [[ -n "${RANDOM_SUFFIX:-}" && -n "${ZONE:-}" ]]; then
        delete_resource "instances" "esp-proxy-${RANDOM_SUFFIX}" "${ZONE}" ""
    fi
    
    if [[ -n "${BACKEND_SERVICE_NAME:-}" && -n "${ZONE:-}" ]]; then
        delete_resource "instances" "${BACKEND_SERVICE_NAME}" "${ZONE}" ""
    fi
    
    # Delete firewall rules
    delete_resource "firewall-rules" "allow-esp-proxy" "" ""
    
    log_success "Security and compute resources cleanup completed"
}

# Remove API configuration and related resources
cleanup_api_config() {
    log_info "Cleaning up API configuration and related resources..."
    
    # Delete API key
    if [[ -n "${API_KEY:-}" ]] || gcloud services api-keys list --filter="displayName:'Secure API Gateway Key'" --format="value(name)" | head -n1 > /dev/null; then
        log_info "Deleting API key..."
        local api_key_name
        api_key_name=$(gcloud services api-keys list --filter="displayName:'Secure API Gateway Key'" --format="value(name)" | head -n1)
        if [[ -n "${api_key_name}" ]]; then
            if gcloud services api-keys delete "${api_key_name}" --quiet; then
                log_success "Deleted API key"
            else
                log_warning "Failed to delete API key"
            fi
        else
            log_info "API key not found or already deleted"
        fi
    fi
    
    # Delete static IP address
    delete_resource "addresses" "esp-gateway-ip" "" "--global"
    
    # Note: Cloud Endpoints services are managed and don't need explicit deletion
    # They will be cleaned up when the project is deleted
    
    log_success "API configuration cleanup completed"
}

# Optional: Delete the entire project
cleanup_project() {
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        log_warning "Project deletion requested..."
        echo
        log_warning "This will DELETE the entire project: ${PROJECT_ID}"
        log_warning "ALL resources in this project will be permanently lost!"
        echo
        
        if [[ "${FORCE_CLEANUP:-}" != "true" ]]; then
            echo -n "Are you absolutely sure you want to delete the project? (DELETE/no): "
            read -r project_confirmation
            
            if [[ "${project_confirmation}" != "DELETE" ]]; then
                log_info "Project deletion cancelled."
                return 0
            fi
        fi
        
        log_info "Deleting project: ${PROJECT_ID}"
        if gcloud projects delete "${PROJECT_ID}" --quiet; then
            log_success "Project deletion initiated: ${PROJECT_ID}"
            log_info "Project deletion may take several minutes to complete."
        else
            log_error "Failed to delete project: ${PROJECT_ID}"
        fi
    else
        log_info "Project deletion not requested. Resources in ${PROJECT_ID} have been cleaned up."
        log_info "To delete the entire project, run: gcloud projects delete ${PROJECT_ID}"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining compute instances
    if [[ -n "${ZONE:-}" ]]; then
        local instances
        instances=$(gcloud compute instances list --zones="${ZONE}" --format="value(name)" --filter="name~(esp-proxy|api-backend)" | wc -l)
        if [[ "${instances}" -gt 0 ]]; then
            log_warning "Found ${instances} remaining compute instances"
            remaining_resources=$((remaining_resources + instances))
        fi
    fi
    
    # Check for remaining load balancer resources
    local lb_resources
    lb_resources=$(gcloud compute forwarding-rules list --global --format="value(name)" --filter="name~esp" | wc -l)
    if [[ "${lb_resources}" -gt 0 ]]; then
        log_warning "Found ${lb_resources} remaining load balancer resources"
        remaining_resources=$((remaining_resources + lb_resources))
    fi
    
    # Check for remaining security policies
    if [[ -n "${SECURITY_POLICY_NAME:-}" ]]; then
        if gcloud compute security-policies describe "${SECURITY_POLICY_NAME}" &>/dev/null; then
            log_warning "Security policy ${SECURITY_POLICY_NAME} still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
    fi
    
    if [[ "${remaining_resources}" -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
        log_success "All resources have been removed"
    else
        log_warning "Cleanup verification found ${remaining_resources} remaining resources"
        log_warning "You may need to manually clean up remaining resources"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    local temp_files=(
        "openapi-spec.yaml"
        "startup-script.sh"
        "deployment-config.env"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed temporary file: ${file}"
        fi
    done
    
    log_success "Temporary files cleanup completed"
}

# Display cleanup summary
display_summary() {
    echo
    echo "=================================================="
    echo "Cleanup Summary"
    echo "=================================================="
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION:-N/A}"
    echo "Zone: ${ZONE:-N/A}"
    
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        echo "Project deletion: Initiated"
    else
        echo "Project deletion: Not requested"
    fi
    
    echo
    echo "Resources cleaned up:"
    echo "- Load balancer and networking components"
    echo "- Cloud Armor security policies"
    echo "- Compute Engine instances"
    echo "- Firewall rules"
    echo "- API keys and static IP addresses"
    echo "- Temporary configuration files"
    echo
    
    if [[ "${DELETE_PROJECT:-}" != "true" ]]; then
        echo "Note: To completely remove all resources, delete the project:"
        echo "gcloud projects delete ${PROJECT_ID}"
    fi
    
    echo "=================================================="
}

# Main cleanup function
main() {
    log_info "Starting secure API gateway cleanup..."
    
    load_config
    confirm_cleanup
    
    # Cleanup in reverse order of creation to respect dependencies
    cleanup_load_balancer
    cleanup_security_compute
    cleanup_api_config
    cleanup_project
    
    verify_cleanup
    cleanup_temp_files
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted. Some resources may still exist."
    log_info "You can re-run this script to continue cleanup."
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Check for command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_CLEANUP="true"
            log_info "Force cleanup mode enabled"
            shift
            ;;
        --delete-project)
            export DELETE_PROJECT="true"
            log_info "Project deletion mode enabled"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force           Skip confirmation prompts"
            echo "  --delete-project  Delete the entire project"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"