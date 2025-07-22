#!/bin/bash

# Distributed Edge Computing Networks Cleanup Script
# Removes all infrastructure created by the deployment script
# Author: Generated from recipe distributed-edge-computing-networks-cloud-cdn-compute-engine
# Version: 1.0

set -euo pipefail

# Color codes for output
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

# Error handling
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Command that failed: $BASH_COMMAND"
    log_warning "Some resources may not have been deleted. Please check manually."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Default configuration
REGIONS=("us-central1" "europe-west1" "asia-southeast1")
ZONES=("us-central1-a" "europe-west1-b" "asia-southeast1-a")

# Script banner
echo -e "${RED}"
echo "================================================================"
echo "     Distributed Edge Computing Networks Cleanup"
echo "================================================================"
echo -e "${NC}"

# Safety confirmation
safety_confirmation() {
    log_warning "This script will delete ALL resources created by the deployment script."
    log_warning "This action cannot be undone and will result in data loss."
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Starting cleanup in 10 seconds... Press Ctrl+C to cancel"
    sleep 10
}

# Get current project
get_project_info() {
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No active Google Cloud project found. Please set a project first:"
        log_error "gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    log_info "Cleaning up resources in project: ${PROJECT_ID}"
    
    # Try to detect resource naming pattern
    log_info "Detecting existing edge computing resources..."
    
    # Look for networks with edge-network pattern
    NETWORKS=$(gcloud compute networks list --filter="name~edge-network-.*" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$NETWORKS" ]]; then
        log_warning "No edge computing networks found. Attempting broader cleanup..."
        return
    fi
    
    # Extract suffix from first network found
    FIRST_NETWORK=$(echo "$NETWORKS" | head -n1)
    if [[ "$FIRST_NETWORK" =~ edge-network-([a-f0-9]+)$ ]]; then
        RANDOM_SUFFIX="${BASH_REMATCH[1]}"
        log_info "Detected resource suffix: ${RANDOM_SUFFIX}"
    else
        log_warning "Could not detect resource suffix. Will attempt cleanup by pattern matching."
        RANDOM_SUFFIX=""
    fi
    
    export PROJECT_ID RANDOM_SUFFIX
}

# Function to safely delete resource if it exists
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_flags="${3:-}"
    
    if gcloud "$resource_type" describe "$resource_name" $additional_flags &>/dev/null; then
        log_info "Deleting $resource_type: $resource_name"
        gcloud "$resource_type" delete "$resource_name" $additional_flags --quiet
        return 0
    else
        log_warning "$resource_type '$resource_name' not found, skipping"
        return 1
    fi
}

# Clean up DNS configuration
cleanup_dns() {
    log_info "Cleaning up DNS configuration..."
    
    # Find and delete DNS zones with edge pattern
    DNS_ZONES=$(gcloud dns managed-zones list --filter="name~edge-zone.*" --format="value(name)" 2>/dev/null || echo "")
    
    for zone in $DNS_ZONES; do
        log_info "Cleaning up DNS zone: $zone"
        
        # Get domain name from zone
        DOMAIN=$(gcloud dns managed-zones describe "$zone" --format="value(dnsName)" | sed 's/\.$//')
        
        # Delete A record
        if gcloud dns record-sets describe "$DOMAIN." --zone="$zone" --type=A &>/dev/null; then
            log_info "Deleting A record for $DOMAIN"
            gcloud dns record-sets delete "$DOMAIN." --zone="$zone" --type=A --quiet
        fi
        
        # Delete CNAME record
        if gcloud dns record-sets describe "www.$DOMAIN." --zone="$zone" --type=CNAME &>/dev/null; then
            log_info "Deleting CNAME record for www.$DOMAIN"
            gcloud dns record-sets delete "www.$DOMAIN." --zone="$zone" --type=CNAME --quiet
        fi
        
        # Delete the zone
        gcloud dns managed-zones delete "$zone" --quiet
    done
    
    log_success "DNS cleanup completed"
}

# Clean up load balancer and CDN
cleanup_load_balancer() {
    log_info "Cleaning up load balancer and CDN components..."
    
    # Delete forwarding rules
    FORWARDING_RULES=$(gcloud compute forwarding-rules list --global --filter="name~edge-forwarding-rule.*" --format="value(name)" 2>/dev/null || echo "")
    for rule in $FORWARDING_RULES; do
        safe_delete "compute forwarding-rules" "$rule" "--global"
    done
    
    # Delete target HTTP proxies
    HTTP_PROXIES=$(gcloud compute target-http-proxies list --filter="name~edge-http-proxy.*" --format="value(name)" 2>/dev/null || echo "")
    for proxy in $HTTP_PROXIES; do
        safe_delete "compute target-http-proxies" "$proxy" "--global"
    done
    
    # Delete URL maps
    URL_MAPS=$(gcloud compute url-maps list --filter="name~edge-url-map.*" --format="value(name)" 2>/dev/null || echo "")
    for map in $URL_MAPS; do
        safe_delete "compute url-maps" "$map" "--global"
    done
    
    # Delete backend services (this also disables CDN)
    BACKEND_SERVICES=$(gcloud compute backend-services list --filter="name~edge-backend-.*" --format="value(name)" 2>/dev/null || echo "")
    for service in $BACKEND_SERVICES; do
        safe_delete "compute backend-services" "$service" "--global"
    done
    
    # Delete health checks
    HEALTH_CHECKS=$(gcloud compute health-checks list --filter="name~edge-health-check.*" --format="value(name)" 2>/dev/null || echo "")
    for check in $HEALTH_CHECKS; do
        safe_delete "compute health-checks" "$check"
    done
    
    # Release global IP addresses
    GLOBAL_IPS=$(gcloud compute addresses list --global --filter="name~edge-global-ip.*" --format="value(name)" 2>/dev/null || echo "")
    for ip in $GLOBAL_IPS; do
        safe_delete "compute addresses" "$ip" "--global"
    done
    
    log_success "Load balancer and CDN cleanup completed"
}

# Clean up compute resources
cleanup_compute_resources() {
    log_info "Cleaning up Compute Engine resources..."
    
    # Delete managed instance groups in all regions
    for i in "${!REGIONS[@]}"; do
        REGION=${REGIONS[$i]}
        ZONE=${ZONES[$i]}
        
        log_info "Cleaning up compute resources in ${REGION}..."
        
        # Find and delete managed instance groups
        INSTANCE_GROUPS=$(gcloud compute instance-groups managed list --zones="$ZONE" --filter="name~edge-group-.*" --format="value(name)" 2>/dev/null || echo "")
        for group in $INSTANCE_GROUPS; do
            log_info "Deleting instance group: $group in $ZONE"
            # Set size to 0 first to gracefully terminate instances
            gcloud compute instance-groups managed resize "$group" --size=0 --zone="$ZONE" --quiet
            # Wait a moment for instances to terminate
            sleep 10
            # Delete the group
            gcloud compute instance-groups managed delete "$group" --zone="$ZONE" --quiet
        done
        
        # Delete instance templates
        INSTANCE_TEMPLATES=$(gcloud compute instance-templates list --filter="name~edge-template-${REGION}-.*" --format="value(name)" 2>/dev/null || echo "")
        for template in $INSTANCE_TEMPLATES; do
            safe_delete "compute instance-templates" "$template"
        done
    done
    
    log_success "Compute resources cleanup completed"
}

# Clean up storage resources
cleanup_storage() {
    log_info "Cleaning up Cloud Storage resources..."
    
    # Find and delete storage buckets
    for region in "${REGIONS[@]}"; do
        if [[ -n "$RANDOM_SUFFIX" ]]; then
            BUCKET_NAME="edge-origin-${region}-${RANDOM_SUFFIX}"
        else
            # If no suffix detected, try to find buckets by pattern
            BUCKET_PATTERN="edge-origin-${region}-"
            BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "gs://${BUCKET_PATTERN}" | sed 's|gs://||' | sed 's|/||' || echo "")
            
            for bucket in $BUCKETS; do
                log_info "Deleting bucket: $bucket"
                gsutil -m rm -r "gs://$bucket" 2>/dev/null || log_warning "Failed to delete bucket: $bucket"
            done
            continue
        fi
        
        # Check if bucket exists and delete it
        if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" &>/dev/null; then
            log_info "Deleting bucket: $BUCKET_NAME"
            gsutil -m rm -r "gs://$BUCKET_NAME"
        else
            log_warning "Bucket $BUCKET_NAME not found, skipping"
        fi
    done
    
    log_success "Storage cleanup completed"
}

# Clean up network infrastructure
cleanup_network() {
    log_info "Cleaning up network infrastructure..."
    
    # Find networks with edge pattern
    NETWORKS=$(gcloud compute networks list --filter="name~edge-network-.*" --format="value(name)" 2>/dev/null || echo "")
    
    for network in $NETWORKS; do
        log_info "Cleaning up network: $network"
        
        # Delete firewall rules for this network
        FIREWALL_RULES=$(gcloud compute firewall-rules list --filter="network:$network" --format="value(name)" 2>/dev/null || echo "")
        for rule in $FIREWALL_RULES; do
            safe_delete "compute firewall-rules" "$rule"
        done
        
        # Delete subnets
        for region in "${REGIONS[@]}"; do
            SUBNET_NAME="$network-$region"
            safe_delete "compute networks subnets" "$SUBNET_NAME" "--region=$region"
        done
        
        # Delete the network
        safe_delete "compute networks" "$network"
    done
    
    log_success "Network cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining networks
    REMAINING_NETWORKS=$(gcloud compute networks list --filter="name~edge-network-.*" --format="value(name)" 2>/dev/null | wc -l)
    if [[ $REMAINING_NETWORKS -gt 0 ]]; then
        log_warning "Found $REMAINING_NETWORKS remaining networks"
        ((remaining_resources++))
    fi
    
    # Check for remaining instance groups
    for zone in "${ZONES[@]}"; do
        REMAINING_GROUPS=$(gcloud compute instance-groups managed list --zones="$zone" --filter="name~edge-group-.*" --format="value(name)" 2>/dev/null | wc -l)
        if [[ $REMAINING_GROUPS -gt 0 ]]; then
            log_warning "Found $REMAINING_GROUPS remaining instance groups in $zone"
            ((remaining_resources++))
        fi
    done
    
    # Check for remaining backend services
    REMAINING_BACKENDS=$(gcloud compute backend-services list --filter="name~edge-backend-.*" --format="value(name)" 2>/dev/null | wc -l)
    if [[ $REMAINING_BACKENDS -gt 0 ]]; then
        log_warning "Found $REMAINING_BACKENDS remaining backend services"
        ((remaining_resources++))
    fi
    
    # Check for remaining DNS zones
    REMAINING_DNS=$(gcloud dns managed-zones list --filter="name~edge-zone.*" --format="value(name)" 2>/dev/null | wc -l)
    if [[ $REMAINING_DNS -gt 0 ]]; then
        log_warning "Found $REMAINING_DNS remaining DNS zones"
        ((remaining_resources++))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All edge computing resources have been successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check the Google Cloud Console for any remaining resources."
        log_info "You can also run this script again to attempt cleanup of any remaining resources."
    fi
    
    log_info "Cleanup verification completed"
}

# Final cleanup summary
cleanup_summary() {
    echo -e "${GREEN}"
    echo "================================================================"
    echo "                CLEANUP COMPLETED"
    echo "================================================================"
    echo -e "${NC}"
    echo "The following resources have been removed:"
    echo "  ✓ DNS zones and records"
    echo "  ✓ Load balancer and CDN components"
    echo "  ✓ Compute Engine instances and templates"
    echo "  ✓ Cloud Storage buckets"
    echo "  ✓ VPC networks and subnets"
    echo "  ✓ Firewall rules"
    echo "  ✓ Global IP addresses"
    echo ""
    echo "Important Notes:"
    echo "  • Monitor your Google Cloud billing to ensure no unexpected charges"
    echo "  • Some resources may take a few minutes to be fully removed"
    echo "  • If you see any remaining resources, you can run this script again"
    echo "  • Check the Google Cloud Console to verify all resources are deleted"
    echo ""
    log_success "Edge computing infrastructure cleanup completed successfully!"
}

# Main cleanup flow
main() {
    log_info "Starting distributed edge computing networks cleanup..."
    
    safety_confirmation
    get_project_info
    cleanup_dns
    cleanup_load_balancer
    cleanup_compute_resources
    cleanup_storage
    cleanup_network
    verify_cleanup
    cleanup_summary
    
    log_success "Cleanup script completed successfully!"
}

# Run main function
main "$@"