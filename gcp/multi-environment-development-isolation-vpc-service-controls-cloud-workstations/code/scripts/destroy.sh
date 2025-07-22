#!/bin/bash

#############################################################################
# Cleanup Script for Multi-Environment Development Isolation
# with VPC Service Controls and Cloud Workstations
#
# This script removes all resources created by the deployment script:
# - Sample workstations
# - Cloud Workstations clusters and configurations
# - Cloud Filestore instances
# - Cloud Source Repositories
# - VPC Service Controls perimeters
# - VPC networks and subnets
# - Google Cloud projects
# - Access Context Manager policies
#############################################################################

set -euo pipefail

# Colors for output
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

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup_$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment_info.txt"

# Check if running in interactive mode
if [[ -t 0 ]]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

echo "================================================"
echo "Multi-Environment Development Isolation Cleanup"
echo "================================================"
echo

# Function to ask for confirmation
confirm_action() {
    local message="$1"
    if [[ "$INTERACTIVE" == true ]]; then
        echo -e "${YELLOW}$message${NC}"
        read -p "Do you want to continue? (yes/no): " response
        if [[ "$response" != "yes" && "$response" != "y" ]]; then
            log_info "Operation cancelled by user."
            exit 0
        fi
    else
        log_info "$message - Auto-confirmed (non-interactive mode)"
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Please authenticate with 'gcloud auth login' first."
    fi
    
    log_success "Prerequisites check completed."
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log_warn "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        log_info "You will need to provide configuration manually."
        get_manual_configuration
        return
    fi
    
    # Extract information from deployment info file
    DEV_PROJECT_ID=$(grep "Development:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    TEST_PROJECT_ID=$(grep "Testing:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    PROD_PROJECT_ID=$(grep "Production:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    POLICY_ID=$(grep "Policy ID:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    REGION=$(grep "Region:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
    ZONE=$(grep "Zone:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
    
    if [[ -z "$DEV_PROJECT_ID" || -z "$TEST_PROJECT_ID" || -z "$PROD_PROJECT_ID" ]]; then
        log_warn "Could not extract project information from deployment info file."
        get_manual_configuration
        return
    fi
    
    log_info "Loaded deployment information:"
    log_info "  Development Project: $DEV_PROJECT_ID"
    log_info "  Testing Project: $TEST_PROJECT_ID"
    log_info "  Production Project: $PROD_PROJECT_ID"
    log_info "  Policy ID: $POLICY_ID"
    log_info "  Region: $REGION"
    log_info "  Zone: $ZONE"
    
    export DEV_PROJECT_ID TEST_PROJECT_ID PROD_PROJECT_ID POLICY_ID REGION ZONE
}

# Get manual configuration if deployment info is not available
get_manual_configuration() {
    log_info "Gathering configuration manually..."
    
    if [[ "$INTERACTIVE" == true ]]; then
        echo "Please provide the project IDs for cleanup:"
        read -p "Development Project ID: " DEV_PROJECT_ID
        read -p "Testing Project ID: " TEST_PROJECT_ID
        read -p "Production Project ID: " PROD_PROJECT_ID
        read -p "Policy ID (optional): " POLICY_ID
        read -p "Region [us-central1]: " REGION
        read -p "Zone [us-central1-a]: " ZONE
        
        # Set defaults
        REGION=${REGION:-us-central1}
        ZONE=${ZONE:-us-central1-a}
        
        if [[ -z "$DEV_PROJECT_ID" || -z "$TEST_PROJECT_ID" || -z "$PROD_PROJECT_ID" ]]; then
            error_exit "Project IDs are required for cleanup."
        fi
    else
        error_exit "Deployment info not available and running in non-interactive mode. Cannot proceed."
    fi
    
    export DEV_PROJECT_ID TEST_PROJECT_ID PROD_PROJECT_ID POLICY_ID REGION ZONE
}

# Delete sample workstations
delete_sample_workstations() {
    log_info "Deleting sample workstations..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        case $PROJECT_ENV in
            "dev") PROJECT_NAME="$DEV_PROJECT_ID" ;;
            "test") PROJECT_NAME="$TEST_PROJECT_ID" ;;
            "prod") PROJECT_NAME="$PROD_PROJECT_ID" ;;
        esac
        
        WORKSTATION_NAME="${PROJECT_ENV}-workstation-1"
        CLUSTER_NAME="${PROJECT_ENV}-cluster"
        
        log_info "Deleting workstation: $WORKSTATION_NAME from $PROJECT_NAME"
        if gcloud workstations delete "$WORKSTATION_NAME" \
            --location="$REGION" \
            --cluster="$CLUSTER_NAME" \
            --project="$PROJECT_NAME" \
            --quiet 2>> "$LOG_FILE"; then
            log_success "Deleted workstation: $WORKSTATION_NAME"
        else
            log_warn "Failed to delete workstation: $WORKSTATION_NAME (may not exist)"
        fi
    done
    
    log_success "Sample workstations deletion completed."
}

# Delete Cloud Workstations configurations and clusters
delete_workstation_infrastructure() {
    log_info "Deleting Cloud Workstations configurations and clusters..."
    
    # First delete configurations
    for PROJECT_ENV in "dev" "test" "prod"; do
        case $PROJECT_ENV in
            "dev") PROJECT_NAME="$DEV_PROJECT_ID" ;;
            "test") PROJECT_NAME="$TEST_PROJECT_ID" ;;
            "prod") PROJECT_NAME="$PROD_PROJECT_ID" ;;
        esac
        
        CONFIG_NAME="${PROJECT_ENV}-workstation-config"
        CLUSTER_NAME="${PROJECT_ENV}-cluster"
        
        log_info "Deleting workstation configuration: $CONFIG_NAME"
        if gcloud workstations configs delete "$CONFIG_NAME" \
            --location="$REGION" \
            --cluster="$CLUSTER_NAME" \
            --project="$PROJECT_NAME" \
            --quiet 2>> "$LOG_FILE"; then
            log_success "Deleted workstation configuration: $CONFIG_NAME"
        else
            log_warn "Failed to delete workstation configuration: $CONFIG_NAME (may not exist)"
        fi
    done
    
    # Wait for configurations to be deleted
    log_info "Waiting for configurations to be deleted..."
    sleep 30
    
    # Then delete clusters
    for PROJECT_ENV in "dev" "test" "prod"; do
        case $PROJECT_ENV in
            "dev") PROJECT_NAME="$DEV_PROJECT_ID" ;;
            "test") PROJECT_NAME="$TEST_PROJECT_ID" ;;
            "prod") PROJECT_NAME="$PROD_PROJECT_ID" ;;
        esac
        
        CLUSTER_NAME="${PROJECT_ENV}-cluster"
        
        log_info "Deleting workstation cluster: $CLUSTER_NAME"
        if gcloud workstations clusters delete "$CLUSTER_NAME" \
            --location="$REGION" \
            --project="$PROJECT_NAME" \
            --quiet 2>> "$LOG_FILE"; then
            log_success "Deleted workstation cluster: $CLUSTER_NAME"
        else
            log_warn "Failed to delete workstation cluster: $CLUSTER_NAME (may not exist)"
        fi
    done
    
    log_success "Workstation infrastructure deletion completed."
}

# Delete Cloud Filestore instances
delete_filestore_instances() {
    log_info "Deleting Cloud Filestore instances..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        case $PROJECT_ENV in
            "dev") PROJECT_NAME="$DEV_PROJECT_ID" ;;
            "test") PROJECT_NAME="$TEST_PROJECT_ID" ;;
            "prod") PROJECT_NAME="$PROD_PROJECT_ID" ;;
        esac
        
        FILESTORE_NAME="${PROJECT_ENV}-filestore"
        
        log_info "Deleting Filestore instance: $FILESTORE_NAME"
        if gcloud filestore instances delete "$FILESTORE_NAME" \
            --location="$ZONE" \
            --project="$PROJECT_NAME" \
            --quiet 2>> "$LOG_FILE"; then
            log_success "Deleted Filestore instance: $FILESTORE_NAME"
        else
            log_warn "Failed to delete Filestore instance: $FILESTORE_NAME (may not exist)"
        fi
    done
    
    log_success "Cloud Filestore instances deletion completed."
}

# Delete Cloud Source Repositories
delete_source_repositories() {
    log_info "Deleting Cloud Source Repositories..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        case $PROJECT_ENV in
            "dev") PROJECT_NAME="$DEV_PROJECT_ID" ;;
            "test") PROJECT_NAME="$TEST_PROJECT_ID" ;;
            "prod") PROJECT_NAME="$PROD_PROJECT_ID" ;;
        esac
        
        REPO_NAME="${PROJECT_ENV}-repo"
        
        log_info "Deleting source repository: $REPO_NAME"
        if gcloud source repos delete "$REPO_NAME" \
            --project="$PROJECT_NAME" \
            --quiet 2>> "$LOG_FILE"; then
            log_success "Deleted source repository: $REPO_NAME"
        else
            log_warn "Failed to delete source repository: $REPO_NAME (may not exist)"
        fi
    done
    
    log_success "Cloud Source Repositories deletion completed."
}

# Delete VPC Service Controls perimeters
delete_service_perimeters() {
    if [[ -z "$POLICY_ID" ]]; then
        log_warn "Policy ID not available, skipping VPC Service Controls cleanup"
        return
    fi
    
    log_info "Deleting VPC Service Controls perimeters..."
    
    for PROJECT_ENV in "dev" "test" "prod"; do
        PERIMETER_NAME="${PROJECT_ENV}-perimeter"
        
        log_info "Deleting service perimeter: $PERIMETER_NAME"
        if gcloud access-context-manager perimeters delete "$PERIMETER_NAME" \
            --policy="$POLICY_ID" \
            --quiet 2>> "$LOG_FILE"; then
            log_success "Deleted service perimeter: $PERIMETER_NAME"
        else
            log_warn "Failed to delete service perimeter: $PERIMETER_NAME (may not exist)"
        fi
    done
    
    log_success "VPC Service Controls perimeters deletion completed."
}

# Delete Access Context Manager resources
delete_access_context_resources() {
    if [[ -z "$POLICY_ID" ]]; then
        log_warn "Policy ID not available, skipping Access Context Manager cleanup"
        return
    fi
    
    log_info "Deleting Access Context Manager resources..."
    
    # Delete access levels
    log_info "Deleting access level: internal_users"
    if gcloud access-context-manager levels delete internal_users \
        --policy="$POLICY_ID" \
        --quiet 2>> "$LOG_FILE"; then
        log_success "Deleted access level: internal_users"
    else
        log_warn "Failed to delete access level: internal_users (may not exist)"
    fi
    
    # Delete access context manager policy
    log_info "Deleting Access Context Manager policy"
    if gcloud access-context-manager policies delete "$POLICY_ID" \
        --quiet 2>> "$LOG_FILE"; then
        log_success "Deleted Access Context Manager policy"
    else
        log_warn "Failed to delete Access Context Manager policy (may not exist)"
    fi
    
    log_success "Access Context Manager resources deletion completed."
}

# Delete projects
delete_projects() {
    log_info "Deleting Google Cloud projects..."
    
    local projects=("$DEV_PROJECT_ID" "$TEST_PROJECT_ID" "$PROD_PROJECT_ID")
    local env_names=("Development" "Testing" "Production")
    
    for i in "${!projects[@]}"; do
        PROJECT_NAME="${projects[$i]}"
        ENV_NAME="${env_names[$i]}"
        
        log_info "Deleting project: $PROJECT_NAME ($ENV_NAME)"
        if gcloud projects delete "$PROJECT_NAME" \
            --quiet 2>> "$LOG_FILE"; then
            log_success "Deleted project: $PROJECT_NAME"
        else
            log_warn "Failed to delete project: $PROJECT_NAME (may not exist or may require manual deletion)"
        fi
    done
    
    log_success "Project deletion initiated."
    log_info "Note: Project deletion may take several minutes to complete fully."
}

# Clean up deployment artifacts
cleanup_deployment_artifacts() {
    log_info "Cleaning up deployment artifacts..."
    
    # Remove deployment info file
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Removed deployment info file"
    fi
    
    # Remove any temporary configuration files
    for file in "internal_users_spec.yaml" "dev-workstation-config.yaml" "test-workstation-config.yaml" "prod-workstation-config.yaml"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed temporary file: $file"
        fi
    done
    
    log_success "Deployment artifacts cleanup completed."
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_complete=true
    
    # Check if projects still exist
    for PROJECT in "$DEV_PROJECT_ID" "$TEST_PROJECT_ID" "$PROD_PROJECT_ID"; do
        if gcloud projects describe "$PROJECT" &> /dev/null; then
            log_warn "Project $PROJECT still exists (deletion may be in progress)"
            cleanup_complete=false
        else
            log_info "Project $PROJECT successfully deleted"
        fi
    done
    
    if [[ "$cleanup_complete" == true ]]; then
        log_success "All resources have been successfully deleted."
    else
        log_warn "Some resources may still be in the process of being deleted."
        log_info "Please check the Google Cloud Console to verify complete cleanup."
    fi
}

# Main execution
main() {
    echo "Starting cleanup at $(date)" >> "$LOG_FILE"
    
    check_prerequisites
    load_deployment_info
    
    confirm_action "This will permanently delete all resources created by the deployment script."
    
    log_info "Starting cleanup of multi-environment development isolation..."
    
    # Delete resources in reverse order of creation
    delete_sample_workstations
    delete_workstation_infrastructure
    delete_filestore_instances
    delete_source_repositories
    delete_service_perimeters
    delete_access_context_resources
    
    confirm_action "Ready to delete the Google Cloud projects. This action cannot be undone."
    delete_projects
    
    cleanup_deployment_artifacts
    verify_cleanup
    
    echo
    log_success "============================================"
    log_success "Cleanup completed!"
    log_success "============================================"
    echo
    log_info "Summary:"
    log_info "  - All workstations and clusters deleted"
    log_info "  - All Filestore instances deleted"
    log_info "  - All source repositories deleted"
    log_info "  - VPC Service Controls perimeters deleted"
    log_info "  - Access Context Manager resources deleted"
    log_info "  - Google Cloud projects deletion initiated"
    echo
    log_info "Note: Project deletion may take several minutes to complete."
    log_info "You can verify completion in the Google Cloud Console."
    log_info "Cleanup log: $LOG_FILE"
    
    if [[ "$INTERACTIVE" == true ]]; then
        echo
        read -p "Press Enter to exit..."
    fi
}

# Run main function
main "$@"