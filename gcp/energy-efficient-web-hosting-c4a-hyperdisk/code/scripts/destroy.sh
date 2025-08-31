#!/bin/bash

# Energy-Efficient Web Hosting with C4A and Hyperdisk - Cleanup Script
# This script safely removes all infrastructure created for the energy-efficient web hosting solution

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [RESOURCE_SUFFIX]"
    echo
    echo "This script destroys the energy-efficient web hosting infrastructure."
    echo
    echo "Arguments:"
    echo "  RESOURCE_SUFFIX    The random suffix used during deployment (required)"
    echo
    echo "Examples:"
    echo "  $0 a1b2c3           # Destroy resources with suffix a1b2c3"
    echo "  $0 --help           # Show this help message"
    echo
    echo "Safety Features:"
    echo "  - Interactive confirmation prompts"
    echo "  - Resource existence verification"
    echo "  - Graceful error handling"
    echo "  - Detailed logging of all operations"
    echo
    exit 0
}

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud CLI first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project is set
    local PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        error "No active Google Cloud project set. Please run 'gcloud config set project PROJECT_ID' first."
        exit 1
    fi
    
    export PROJECT_ID
    export REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    export ZONE=$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")
    
    success "Prerequisites check passed"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
}

# Resource verification function
verify_resources_exist() {
    local suffix=$1
    log "Verifying resources exist for suffix: ${suffix}"
    
    local found_resources=0
    
    # Check for instances
    if gcloud compute instances list --filter="name~web-server.*${suffix}" --format="value(name)" | grep -q .; then
        local instance_count=$(gcloud compute instances list --filter="name~web-server.*${suffix}" --format="value(name)" | wc -l)
        log "Found ${instance_count} instances"
        found_resources=$((found_resources + instance_count))
    fi
    
    # Check for disks
    if gcloud compute disks list --filter="name~web-data-disk.*${suffix}" --format="value(name)" | grep -q .; then
        local disk_count=$(gcloud compute disks list --filter="name~web-data-disk.*${suffix}" --format="value(name)" | wc -l)
        log "Found ${disk_count} disks"
        found_resources=$((found_resources + disk_count))
    fi
    
    # Check for network
    if gcloud compute networks describe "energy-web-vpc-${suffix}" &>/dev/null; then
        log "Found VPC network"
        found_resources=$((found_resources + 1))
    fi
    
    if [[ $found_resources -eq 0 ]]; then
        warning "No resources found with suffix '${suffix}'"
        echo "This could mean:"
        echo "  1. Resources were already deleted"
        echo "  2. Wrong suffix provided"
        echo "  3. Resources were created in a different project"
        echo
        read -p "Continue with cleanup anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    else
        success "Found ${found_resources} resources to clean up"
    fi
}

# Confirmation function
confirm_destruction() {
    local suffix=$1
    
    echo
    echo "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
    echo "======================================"
    echo
    echo "This will permanently delete ALL resources with suffix: ${suffix}"
    echo
    echo "Resources to be deleted:"
    echo "  • Load balancer and forwarding rules"
    echo "  • Backend services and health checks"
    echo "  • C4A compute instances (3 instances)"
    echo "  • Hyperdisk volumes (3 volumes)"
    echo "  • Instance groups"
    echo "  • Firewall rules"
    echo "  • VPC network and subnet"
    echo "  • Monitoring dashboards"
    echo
    echo "⚠️  This action CANNOT be undone!"
    echo "⚠️  All data on the instances and disks will be permanently lost!"
    echo
    
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " -r
    echo
    if [[ "$REPLY" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Final confirmation - type 'DELETE' to proceed: " -r
    echo
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Confirmation received - proceeding with cleanup"
}

# Delete load balancer components function
delete_load_balancer() {
    local suffix=$1
    log "Removing load balancer components..."
    
    # Delete forwarding rule
    log "Deleting forwarding rule..."
    if gcloud compute forwarding-rules delete "web-forwarding-rule-${suffix}" \
        --global \
        --quiet 2>/dev/null; then
        success "Forwarding rule deleted"
    else
        warning "Forwarding rule not found or already deleted"
    fi
    
    # Delete HTTP proxy
    log "Deleting HTTP proxy..."
    if gcloud compute target-http-proxies delete "web-http-proxy-${suffix}" \
        --quiet 2>/dev/null; then
        success "HTTP proxy deleted"
    else
        warning "HTTP proxy not found or already deleted"
    fi
    
    # Delete URL map
    log "Deleting URL map..."
    if gcloud compute url-maps delete "web-url-map-${suffix}" \
        --quiet 2>/dev/null; then
        success "URL map deleted"
    else
        warning "URL map not found or already deleted"
    fi
    
    # Delete backend service
    log "Deleting backend service..."
    if gcloud compute backend-services delete "web-backend-service-${suffix}" \
        --global \
        --quiet 2>/dev/null; then
        success "Backend service deleted"
    else
        warning "Backend service not found or already deleted"
    fi
    
    success "Load balancer components removed"
}

# Delete compute resources function
delete_compute_resources() {
    local suffix=$1
    log "Removing compute resources..."
    
    # Delete instance group
    log "Deleting instance group..."
    if gcloud compute instance-groups unmanaged delete "web-instance-group-${suffix}" \
        --zone "${ZONE}" \
        --quiet 2>/dev/null; then
        success "Instance group deleted"
    else
        warning "Instance group not found or already deleted"
    fi
    
    # Delete instances
    log "Deleting C4A instances..."
    for i in {1..3}; do
        if gcloud compute instances delete "web-server-${i}-${suffix}" \
            --zone "${ZONE}" \
            --quiet 2>/dev/null; then
            success "Instance ${i} deleted"
        else
            warning "Instance ${i} not found or already deleted"
        fi
    done
    
    # Wait for instances to be fully deleted before deleting disks
    log "Waiting for instances to be fully deleted..."
    sleep 30
    
    # Delete Hyperdisk volumes
    log "Deleting Hyperdisk volumes..."
    for i in {1..3}; do
        if gcloud compute disks delete "web-data-disk-${i}-${suffix}" \
            --zone "${ZONE}" \
            --quiet 2>/dev/null; then
            success "Hyperdisk volume ${i} deleted"
        else
            warning "Hyperdisk volume ${i} not found or already deleted"
        fi
    done
    
    success "Compute resources removed"
}

# Delete health check function
delete_health_check() {
    local suffix=$1
    log "Removing health check..."
    
    if gcloud compute health-checks delete "web-health-check-${suffix}" \
        --quiet 2>/dev/null; then
        success "Health check deleted"
    else
        warning "Health check not found or already deleted"
    fi
}

# Delete firewall rules function
delete_firewall_rules() {
    local suffix=$1
    log "Removing firewall rules..."
    
    local firewall_rules=(
        "allow-http-${suffix}"
        "allow-https-${suffix}"
        "allow-health-checks-${suffix}"
    )
    
    for rule in "${firewall_rules[@]}"; do
        if gcloud compute firewall-rules delete "$rule" \
            --quiet 2>/dev/null; then
            success "Firewall rule '${rule}' deleted"
        else
            warning "Firewall rule '${rule}' not found or already deleted"
        fi
    done
    
    success "Firewall rules removed"
}

# Delete network infrastructure function
delete_network_infrastructure() {
    local suffix=$1
    log "Removing network infrastructure..."
    
    # Delete subnet
    log "Deleting subnet..."
    if gcloud compute networks subnets delete "energy-web-subnet-${suffix}" \
        --region "${REGION}" \
        --quiet 2>/dev/null; then
        success "Subnet deleted"
    else
        warning "Subnet not found or already deleted"
    fi
    
    # Delete VPC network
    log "Deleting VPC network..."
    if gcloud compute networks delete "energy-web-vpc-${suffix}" \
        --quiet 2>/dev/null; then
        success "VPC network deleted"
    else
        warning "VPC network not found or already deleted"
    fi
    
    success "Network infrastructure removed"
}

# Delete monitoring resources function
delete_monitoring_resources() {
    local suffix=$1
    log "Removing monitoring resources..."
    
    # List and delete dashboards related to this deployment
    local dashboard_filter="displayName:Energy-Efficient Web Hosting Dashboard"
    local dashboards=$(gcloud monitoring dashboards list --filter="$dashboard_filter" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        echo "$dashboards" | while read -r dashboard; do
            if [[ -n "$dashboard" ]]; then
                if gcloud monitoring dashboards delete "$dashboard" --quiet 2>/dev/null; then
                    success "Monitoring dashboard deleted"
                else
                    warning "Failed to delete monitoring dashboard"
                fi
            fi
        done
    else
        warning "No monitoring dashboards found"
    fi
}

# Clean up temporary files function
cleanup_temp_files() {
    local suffix=$1
    log "Cleaning up temporary files..."
    
    # Remove any temporary files that might have been left behind
    rm -f "/tmp/startup-script-${suffix}.sh" 2>/dev/null || true
    rm -f "/tmp/dashboard-config-${suffix}.json" 2>/dev/null || true
    rm -f "/tmp/deployment-info-${suffix}.txt" 2>/dev/null || true
    
    success "Temporary files cleaned up"
}

# Verify cleanup function
verify_cleanup() {
    local suffix=$1
    log "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining instances
    local remaining_instances=$(gcloud compute instances list --filter="name~web-server.*${suffix}" --format="value(name)" | wc -l)
    if [[ $remaining_instances -gt 0 ]]; then
        warning "${remaining_instances} instances still exist"
        remaining_resources=$((remaining_resources + remaining_instances))
    fi
    
    # Check for remaining disks
    local remaining_disks=$(gcloud compute disks list --filter="name~web-data-disk.*${suffix}" --format="value(name)" | wc -l)
    if [[ $remaining_disks -gt 0 ]]; then
        warning "${remaining_disks} disks still exist"
        remaining_resources=$((remaining_resources + remaining_disks))
    fi
    
    # Check for remaining network
    if gcloud compute networks describe "energy-web-vpc-${suffix}" &>/dev/null; then
        warning "VPC network still exists"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        success "All resources successfully removed"
    else
        warning "${remaining_resources} resources may still exist"
        echo
        echo "Some resources might still be in the process of deletion."
        echo "You can manually check and remove any remaining resources in the Google Cloud Console."
    fi
}

# Main cleanup function
main() {
    local suffix=""
    
    # Parse command line arguments
    case "${1:-}" in
        --help|-h)
            show_usage
            ;;
        "")
            error "Resource suffix is required. Use --help for usage information."
            exit 1
            ;;
        *)
            suffix="$1"
            ;;
    esac
    
    echo "🧹 Energy-Efficient Web Hosting - Cleanup Script"
    echo "==============================================="
    echo
    echo "Cleaning up resources with suffix: ${suffix}"
    echo
    
    check_prerequisites
    verify_resources_exist "$suffix"
    confirm_destruction "$suffix"
    
    echo
    log "Starting cleanup process..."
    
    # Delete resources in reverse order of creation
    delete_load_balancer "$suffix"
    delete_compute_resources "$suffix"
    delete_health_check "$suffix"
    delete_firewall_rules "$suffix"
    delete_network_infrastructure "$suffix"
    delete_monitoring_resources "$suffix"
    cleanup_temp_files "$suffix"
    verify_cleanup "$suffix"
    
    echo
    echo "🎉 Cleanup completed successfully!"
    echo
    echo "Summary:"
    echo "• All compute instances and storage removed"
    echo "• Network infrastructure deleted"
    echo "• Load balancer components removed"
    echo "• Firewall rules cleaned up"
    echo "• Monitoring resources removed"
    echo
    echo "💰 Your Google Cloud costs for this infrastructure should now be $0"
    echo "🌱 Thank you for testing energy-efficient cloud computing!"
}

# Error handling with graceful degradation
set +e  # Don't exit on individual command failures during cleanup

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi