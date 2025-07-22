#!/bin/bash

# Disaster Recovery Orchestration with Service Extensions and Backup and DR Service
# Cleanup Script for GCP Recipe
# 
# This script safely removes all resources created by the deployment script
# in the correct order to avoid dependency conflicts.

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE=false
DELETE_PROJECT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_info "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE=true
            log_warning "Running in FORCE mode - skipping confirmation prompts"
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            log_warning "Will delete the entire project after cleanup"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run         Show what would be deleted without actually deleting"
            echo "  --force           Skip confirmation prompts"
            echo "  --delete-project  Delete the entire project after cleanup"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to execute commands (respects dry-run mode)
execute_command() {
    local cmd="$1"
    local description="${2:-}"
    local ignore_errors="${3:-false}"
    
    if [[ -n "$description" ]]; then
        log_info "$description"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" 2>/dev/null || log_warning "Command failed (continuing): $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to detect environment variables
detect_environment() {
    log_info "Detecting environment variables..."
    
    # Try to get current project ID
    PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID not set and cannot detect current project."
        log_error "Please set PROJECT_ID environment variable or set a default project with:"
        log_error "gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    # Set default values for other variables
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    DR_REGION="${DR_REGION:-us-east1}"
    DR_ZONE="${DR_ZONE:-us-east1-a}"
    
    # Try to detect RANDOM_SUFFIX from existing resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log_info "Attempting to detect RANDOM_SUFFIX from existing resources..."
        
        # Look for instance groups with the expected pattern
        local instance_groups
        instance_groups=$(gcloud compute instance-groups managed list \
            --filter="name~'primary-app-group-.*'" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$instance_groups" ]]; then
            # Extract suffix from first matching instance group
            RANDOM_SUFFIX=$(echo "$instance_groups" | head -n1 | sed 's/primary-app-group-//')
            log_info "Detected RANDOM_SUFFIX: $RANDOM_SUFFIX"
        else
            log_warning "Could not auto-detect RANDOM_SUFFIX. Some resources may not be found."
            RANDOM_SUFFIX="unknown"
        fi
    fi
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Primary Region: $REGION"
    log_info "DR Region: $DR_REGION"
    log_info "Resource Suffix: $RANDOM_SUFFIX"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will DELETE all Disaster Recovery Orchestration resources in project: $PROJECT_ID"
    echo "Resources to be deleted include:"
    echo "- Load balancer and networking components"
    echo "- Compute Engine instances and instance groups"
    echo "- Cloud Functions"
    echo "- Backup vaults and plans"
    echo "- Monitoring and alerting configurations"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "- THE ENTIRE PROJECT: $PROJECT_ID"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to remove load balancer components
remove_load_balancer() {
    log_info "Removing load balancer components..."
    
    # Delete forwarding rule
    execute_command "gcloud compute forwarding-rules delete dr-orchestration-forwarding-rule-$RANDOM_SUFFIX \
        --global \
        --quiet" \
        "Deleting forwarding rule" \
        true
    
    # Delete HTTP proxy
    execute_command "gcloud compute target-http-proxies delete dr-orchestration-proxy-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting HTTP proxy" \
        true
    
    # Delete URL map
    execute_command "gcloud compute url-maps delete dr-orchestration-urlmap-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting URL map" \
        true
    
    log_success "Load balancer components removed"
}

# Function to remove backend services
remove_backend_services() {
    log_info "Removing backend services..."
    
    # Delete backend services
    execute_command "gcloud compute backend-services delete primary-backend-service-$RANDOM_SUFFIX \
        --global \
        --quiet" \
        "Deleting primary backend service" \
        true
    
    execute_command "gcloud compute backend-services delete dr-backend-service-$RANDOM_SUFFIX \
        --global \
        --quiet" \
        "Deleting DR backend service" \
        true
    
    log_success "Backend services removed"
}

# Function to remove instance groups and templates
remove_compute_resources() {
    log_info "Removing compute resources..."
    
    # Delete instance groups
    execute_command "gcloud compute instance-groups managed delete primary-app-group-$RANDOM_SUFFIX \
        --zone=$ZONE \
        --quiet" \
        "Deleting primary instance group" \
        true
    
    execute_command "gcloud compute instance-groups managed delete dr-app-group-$RANDOM_SUFFIX \
        --zone=$DR_ZONE \
        --quiet" \
        "Deleting DR instance group" \
        true
    
    # Wait for instance group deletion to complete
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for instance groups to be fully deleted..."
        sleep 30
    fi
    
    # Delete instance templates
    execute_command "gcloud compute instance-templates delete primary-app-template-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting primary instance template" \
        true
    
    execute_command "gcloud compute instance-templates delete dr-app-template-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting DR instance template" \
        true
    
    # Delete health checks
    execute_command "gcloud compute health-checks delete primary-app-health-check-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting primary health check" \
        true
    
    execute_command "gcloud compute health-checks delete dr-app-health-check-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting DR health check" \
        true
    
    log_success "Compute resources removed"
}

# Function to remove Cloud Functions
remove_functions() {
    log_info "Removing Cloud Functions..."
    
    # Delete DR orchestration function
    execute_command "gcloud functions delete dr-orchestrator-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting DR orchestration function" \
        true
    
    log_success "Cloud Functions removed"
}

# Function to remove backup and DR resources
remove_backup_dr() {
    log_info "Removing Backup and DR resources..."
    
    # Delete backup plan first (it depends on the vault)
    execute_command "gcloud backup-dr backup-plans delete primary-backup-plan-$RANDOM_SUFFIX \
        --location=$REGION \
        --quiet" \
        "Deleting backup plan" \
        true
    
    # Wait for backup plan deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for backup plan deletion..."
        sleep 30
    fi
    
    # Delete backup vault
    execute_command "gcloud backup-dr backup-vaults delete primary-backup-vault-$RANDOM_SUFFIX \
        --location=$REGION \
        --quiet" \
        "Deleting backup vault" \
        true
    
    log_success "Backup and DR resources removed"
}

# Function to remove monitoring and alerting
remove_monitoring() {
    log_info "Removing monitoring and alerting..."
    
    # Delete custom log metrics
    execute_command "gcloud logging metrics delete dr-failure-detection-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting failure detection metric" \
        true
    
    execute_command "gcloud logging metrics delete dr-orchestration-success-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting orchestration success metric" \
        true
    
    # List and delete alert policies (they contain the random suffix in display name)
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Finding and deleting alert policies..."
        local policy_names
        policy_names=$(gcloud alpha monitoring policies list \
            --filter="displayName~'.*$RANDOM_SUFFIX.*'" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$policy_names" ]]; then
            while IFS= read -r policy_name; do
                if [[ -n "$policy_name" ]]; then
                    execute_command "gcloud alpha monitoring policies delete '$policy_name' --quiet" \
                        "Deleting alert policy: $policy_name" \
                        true
                fi
            done <<< "$policy_names"
        fi
    fi
    
    # List and delete dashboards
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Finding and deleting dashboards..."
        local dashboard_names
        dashboard_names=$(gcloud monitoring dashboards list \
            --filter="displayName~'.*$RANDOM_SUFFIX.*'" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$dashboard_names" ]]; then
            while IFS= read -r dashboard_name; do
                if [[ -n "$dashboard_name" ]]; then
                    execute_command "gcloud monitoring dashboards delete '$dashboard_name' --quiet" \
                        "Deleting dashboard: $dashboard_name" \
                        true
                fi
            done <<< "$dashboard_names"
        fi
    fi
    
    log_success "Monitoring and alerting removed"
}

# Function to remove networking components
remove_networking() {
    log_info "Removing networking components..."
    
    # Delete firewall rules
    execute_command "gcloud compute firewall-rules delete allow-http-$RANDOM_SUFFIX \
        --quiet" \
        "Deleting firewall rule" \
        true
    
    log_success "Networking components removed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove any temporary files that might have been created
    execute_command "rm -f /tmp/dr-alert-policy-*.json" \
        "Removing temporary alert policy files" \
        true
    
    execute_command "rm -f /tmp/dr-dashboard-*.json" \
        "Removing temporary dashboard files" \
        true
    
    execute_command "rm -rf /tmp/dr-orchestrator-function-*" \
        "Removing temporary function directories" \
        true
    
    log_success "Temporary files cleaned up"
}

# Function to delete the entire project
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log_info "Deleting entire project..."
    
    if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log_warning "FINAL CONFIRMATION: This will DELETE the ENTIRE project: $PROJECT_ID"
        log_warning "This action is IRREVERSIBLE!"
        echo ""
        read -p "Type the project ID to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_info "Project deletion cancelled - confirmation did not match"
            return 0
        fi
    fi
    
    execute_command "gcloud projects delete $PROJECT_ID --quiet" \
        "Deleting project: $PROJECT_ID"
    
    log_success "Project deletion initiated"
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]] || [[ "$DELETE_PROJECT" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    # Check for remaining instance groups
    local remaining_groups
    remaining_groups=$(gcloud compute instance-groups managed list \
        --filter="name~'.*-$RANDOM_SUFFIX'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_groups" ]]; then
        log_warning "Some instance groups may still exist:"
        echo "$remaining_groups"
    fi
    
    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --filter="name~'.*-$RANDOM_SUFFIX'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Some Cloud Functions may still exist:"
        echo "$remaining_functions"
    fi
    
    # Check for remaining load balancer components
    local remaining_lb
    remaining_lb=$(gcloud compute forwarding-rules list \
        --filter="name~'.*-$RANDOM_SUFFIX'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_lb" ]]; then
        log_warning "Some load balancer components may still exist:"
        echo "$remaining_lb"
    fi
    
    if [[ -z "$remaining_groups" ]] && [[ -z "$remaining_functions" ]] && [[ -z "$remaining_lb" ]]; then
        log_success "Cleanup verification passed - no obvious remaining resources found"
    else
        log_warning "Some resources may still exist. Check the Google Cloud Console for any remaining resources."
    fi
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN completed - no resources were actually deleted"
    elif [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "Project deletion initiated: $PROJECT_ID"
        echo "It may take several minutes for the project to be fully deleted."
    else
        echo "Resource cleanup completed"
        echo "Project $PROJECT_ID still exists but DR resources have been removed"
    fi
    
    echo "=================================="
}

# Main cleanup function
main() {
    log_info "Starting Disaster Recovery Orchestration cleanup..."
    
    check_prerequisites
    detect_environment
    confirm_deletion
    
    # Remove resources in reverse order of creation to handle dependencies
    remove_load_balancer
    remove_backend_services
    remove_compute_resources
    remove_functions
    remove_backup_dr
    remove_monitoring
    remove_networking
    cleanup_temp_files
    delete_project
    verify_cleanup
    display_summary
    
    log_success "Disaster Recovery Orchestration cleanup completed!"
}

# Error handling
trap 'log_error "Cleanup failed. Some resources may still exist. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"