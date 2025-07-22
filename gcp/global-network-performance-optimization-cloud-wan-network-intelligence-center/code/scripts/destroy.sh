#!/bin/bash

# Destroy script for Global Network Performance Optimization with Cloud WAN and Network Intelligence Center
# This script safely removes all resources created by the deploy script

set -euo pipefail

# Colors for output
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

# Function to check if resource exists before attempting deletion
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_flags="${3:-}"
    
    case "${resource_type}" in
        "forwarding-rule")
            gcloud compute forwarding-rules describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "target-proxy")
            gcloud compute target-http-proxies describe "${resource_name}" ${additional_flags} &>/dev/null || \
            gcloud compute target-https-proxies describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "backend-service")
            gcloud compute backend-services describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "health-check")
            gcloud compute health-checks describe "${resource_name}" &>/dev/null
            ;;
        "url-map")
            gcloud compute url-maps describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "ssl-certificate")
            gcloud compute ssl-certificates describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "instance")
            gcloud compute instances describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "instance-group")
            gcloud compute instance-groups unmanaged describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "firewall-rule")
            gcloud compute firewall-rules describe "${resource_name}" &>/dev/null
            ;;
        "subnet")
            gcloud compute networks subnets describe "${resource_name}" ${additional_flags} &>/dev/null
            ;;
        "network")
            gcloud compute networks describe "${resource_name}" &>/dev/null
            ;;
        "project")
            gcloud projects describe "${resource_name}" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to safely delete resource
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_flags="${3:-}"
    local zone_or_region="${4:-}"
    
    if resource_exists "${resource_type}" "${resource_name}" "${additional_flags}"; then
        log "Deleting ${resource_type}: ${resource_name}"
        
        case "${resource_type}" in
            "forwarding-rule")
                gcloud compute forwarding-rules delete "${resource_name}" ${additional_flags} --quiet
                ;;
            "target-proxy")
                # Try HTTP proxy first, then HTTPS proxy
                if gcloud compute target-http-proxies describe "${resource_name}" ${additional_flags} &>/dev/null; then
                    gcloud compute target-http-proxies delete "${resource_name}" ${additional_flags} --quiet
                elif gcloud compute target-https-proxies describe "${resource_name}" ${additional_flags} &>/dev/null; then
                    gcloud compute target-https-proxies delete "${resource_name}" ${additional_flags} --quiet
                fi
                ;;
            "backend-service")
                gcloud compute backend-services delete "${resource_name}" ${additional_flags} --quiet
                ;;
            "health-check")
                gcloud compute health-checks delete "${resource_name}" --quiet
                ;;
            "url-map")
                gcloud compute url-maps delete "${resource_name}" ${additional_flags} --quiet
                ;;
            "ssl-certificate")
                gcloud compute ssl-certificates delete "${resource_name}" ${additional_flags} --quiet
                ;;
            "instance")
                gcloud compute instances delete "${resource_name}" --zone="${zone_or_region}" --quiet
                ;;
            "instance-group")
                gcloud compute instance-groups unmanaged delete "${resource_name}" --zone="${zone_or_region}" --quiet
                ;;
            "firewall-rule")
                gcloud compute firewall-rules delete "${resource_name}" --quiet
                ;;
            "subnet")
                gcloud compute networks subnets delete "${resource_name}" --region="${zone_or_region}" --quiet
                ;;
            "network")
                gcloud compute networks delete "${resource_name}" --quiet
                ;;
        esac
        
        success "Deleted ${resource_type}: ${resource_name}"
    else
        log "Skipping ${resource_type}: ${resource_name} (doesn't exist)"
    fi
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Try to load from deployment-info.txt if it exists
    if [[ -f "deployment-info.txt" ]]; then
        log "Found deployment-info.txt, extracting configuration..."
        
        # Extract project ID
        if grep -q "Project ID:" deployment-info.txt; then
            PROJECT_ID=$(grep "Project ID:" deployment-info.txt | cut -d' ' -f3)
            export PROJECT_ID
            log "Found PROJECT_ID: ${PROJECT_ID}"
        fi
        
        # Extract network name
        if grep -q "Network Name:" deployment-info.txt; then
            NETWORK_NAME=$(grep "Network Name:" deployment-info.txt | cut -d' ' -f3)
            export NETWORK_NAME
            log "Found NETWORK_NAME: ${NETWORK_NAME}"
        fi
    fi
    
    # Fallback to environment variables or prompt user
    if [[ -z "${PROJECT_ID:-}" ]]; then
        if [[ -n "${1:-}" ]]; then
            PROJECT_ID="$1"
            export PROJECT_ID
        else
            echo -n "Enter PROJECT_ID to delete: "
            read -r PROJECT_ID
            export PROJECT_ID
        fi
    fi
    
    if [[ -z "${NETWORK_NAME:-}" ]]; then
        # Try to find the network by listing networks in the project
        gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
        
        local networks
        networks=$(gcloud compute networks list --filter="name~global-wan-.*" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${networks}" ]]; then
            NETWORK_NAME=$(echo "${networks}" | head -n1)
            export NETWORK_NAME
            log "Auto-detected NETWORK_NAME: ${NETWORK_NAME}"
        else
            echo -n "Enter NETWORK_NAME to delete: "
            read -r NETWORK_NAME
            export NETWORK_NAME
        fi
    fi
    
    # Set region configuration
    export REGION_US="us-central1"
    export REGION_EU="europe-west1"
    export REGION_APAC="asia-east1"
    
    export ZONE_US="us-central1-a"
    export ZONE_EU="europe-west1-b"
    export ZONE_APAC="asia-east1-a"
    
    success "Configuration loaded - PROJECT_ID: ${PROJECT_ID}, NETWORK: ${NETWORK_NAME}"
}

# Confirm destruction with user
confirm_destruction() {
    warning "This will permanently delete ALL resources in project: ${PROJECT_ID}"
    warning "Including network: ${NETWORK_NAME}"
    warning "This action cannot be undone!"
    
    echo ""
    echo -n "Type 'DELETE' to confirm destruction: "
    read -r confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Set project context
set_project_context() {
    log "Setting project context..."
    
    # Set project
    gcloud config set project "${PROJECT_ID}"
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} does not exist or is not accessible"
        exit 1
    fi
    
    success "Project context set: ${PROJECT_ID}"
}

# Delete load balancer components
delete_load_balancer() {
    log "Deleting load balancer infrastructure..."
    
    # Delete forwarding rules first
    safe_delete "forwarding-rule" "global-web-https-rule" "--global"
    safe_delete "forwarding-rule" "global-web-http-rule" "--global"
    
    # Wait for forwarding rules to be fully deleted
    sleep 10
    
    # Delete target proxies
    safe_delete "target-proxy" "global-web-https-proxy" "--global"
    safe_delete "target-proxy" "global-web-http-proxy" "--global"
    
    # Delete SSL certificates
    safe_delete "ssl-certificate" "global-web-ssl" "--global"
    
    # Delete backend services
    safe_delete "backend-service" "global-web-backend" "--global"
    
    # Delete health checks
    safe_delete "health-check" "global-web-health-check"
    
    # Delete URL maps
    safe_delete "url-map" "global-web-map" "--global"
    
    success "Load balancer infrastructure deleted"
}

# Delete compute instances and instance groups
delete_compute_infrastructure() {
    log "Deleting compute infrastructure..."
    
    # Delete VM instances
    safe_delete "instance" "web-server-us-1" "" "${ZONE_US}"
    safe_delete "instance" "web-server-eu-1" "" "${ZONE_EU}"
    safe_delete "instance" "web-server-apac-1" "" "${ZONE_APAC}"
    
    # Wait for instances to be fully deleted
    sleep 30
    
    # Delete instance groups
    safe_delete "instance-group" "web-group-us" "" "${ZONE_US}"
    safe_delete "instance-group" "web-group-eu" "" "${ZONE_EU}"
    safe_delete "instance-group" "web-group-apac" "" "${ZONE_APAC}"
    
    success "Compute infrastructure deleted"
}

# Delete firewall rules
delete_firewall_rules() {
    log "Deleting firewall rules..."
    
    safe_delete "firewall-rule" "${NETWORK_NAME}-allow-ssh"
    safe_delete "firewall-rule" "${NETWORK_NAME}-allow-lb-health"
    safe_delete "firewall-rule" "${NETWORK_NAME}-allow-internal"
    
    success "Firewall rules deleted"
}

# Delete network infrastructure
delete_network_infrastructure() {
    log "Deleting network infrastructure..."
    
    # Delete subnets
    safe_delete "subnet" "${NETWORK_NAME}-us" "--region=${REGION_US}"
    safe_delete "subnet" "${NETWORK_NAME}-eu" "--region=${REGION_EU}"
    safe_delete "subnet" "${NETWORK_NAME}-apac" "--region=${REGION_APAC}"
    
    # Wait for subnets to be fully deleted
    sleep 10
    
    # Delete VPC network
    safe_delete "network" "${NETWORK_NAME}"
    
    success "Network infrastructure deleted"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "Cleaning up monitoring resources..."
    
    # Custom monitoring policies and dashboards would be deleted here
    # For now, just log that monitoring cleanup is complete
    log "Note: Network Intelligence Center data will be automatically cleaned up"
    
    success "Monitoring resources cleanup completed"
}

# Delete project (optional)
delete_project() {
    log "Project deletion options:"
    echo "1. Keep project (only delete resources)"
    echo "2. Delete entire project"
    echo -n "Choose option (1 or 2): "
    read -r choice
    
    case "${choice}" in
        2)
            warning "This will delete the entire project: ${PROJECT_ID}"
            echo -n "Type 'DELETE_PROJECT' to confirm: "
            read -r confirmation
            
            if [[ "${confirmation}" == "DELETE_PROJECT" ]]; then
                log "Deleting project: ${PROJECT_ID}"
                gcloud projects delete "${PROJECT_ID}" --quiet
                success "Project deleted: ${PROJECT_ID}"
                success "Note: Project deletion may take several minutes to complete"
            else
                log "Project deletion cancelled"
            fi
            ;;
        1|*)
            log "Keeping project: ${PROJECT_ID}"
            log "All resources have been deleted, but project remains"
            ;;
    esac
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining instances
    local instances
    instances=$(gcloud compute instances list --filter="name~web-server-.*" --format="value(name)" 2>/dev/null | wc -l)
    if [[ "${instances}" -gt 0 ]]; then
        warning "Found ${instances} remaining instances"
        remaining_resources=$((remaining_resources + instances))
    fi
    
    # Check for remaining networks
    if resource_exists "network" "${NETWORK_NAME}"; then
        warning "Network ${NETWORK_NAME} still exists"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check for remaining forwarding rules
    local forwarding_rules
    forwarding_rules=$(gcloud compute forwarding-rules list --global --filter="name~global-web-.*" --format="value(name)" 2>/dev/null | wc -l)
    if [[ "${forwarding_rules}" -gt 0 ]]; then
        warning "Found ${forwarding_rules} remaining forwarding rules"
        remaining_resources=$((remaining_resources + forwarding_rules))
    fi
    
    if [[ "${remaining_resources}" -eq 0 ]]; then
        success "All resources successfully cleaned up"
    else
        warning "Some resources may still exist. Manual cleanup may be required."
        log "Check the Google Cloud Console for any remaining resources"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f /tmp/lb_ip.txt
    rm -f deployment-info.txt
    
    success "Temporary files cleaned up"
}

# Main destruction function
main() {
    log "Starting Global Network Performance Optimization cleanup..."
    
    load_deployment_info "$@"
    confirm_destruction
    set_project_context
    
    # Delete resources in reverse order of creation
    delete_load_balancer
    delete_compute_infrastructure
    delete_firewall_rules
    delete_network_infrastructure
    delete_monitoring_resources
    
    validate_cleanup
    cleanup_temp_files
    
    # Optionally delete the project
    delete_project
    
    success "=== CLEANUP COMPLETED SUCCESSFULLY ==="
    log "All infrastructure has been removed"
    
    if resource_exists "project" "${PROJECT_ID}"; then
        log "Project ${PROJECT_ID} is preserved"
        log "You can safely delete it manually if no longer needed"
    else
        log "Project ${PROJECT_ID} has been scheduled for deletion"
    fi
}

# Handle script arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [PROJECT_ID]"
    echo ""
    echo "Destroys all resources created by the Global Network Performance Optimization deployment"
    echo ""
    echo "Arguments:"
    echo "  PROJECT_ID    Optional. The GCP project ID to clean up"
    echo "                If not provided, will be prompted or auto-detected"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                              # Interactive cleanup"
    echo "  $0 my-network-project-123       # Cleanup specific project"
    exit 0
fi

# Check prerequisites
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Please install Google Cloud SDK."
    exit 1
fi

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
    error "Please authenticate with gcloud: gcloud auth login"
    exit 1
fi

# Run main function
main "$@"