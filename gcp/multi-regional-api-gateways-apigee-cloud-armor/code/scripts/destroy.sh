#!/bin/bash

# Multi-Regional API Gateways with Apigee and Cloud Armor - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ -f ".deploy_config" ]]; then
        source .deploy_config
        success "Configuration loaded from .deploy_config"
        log "Project ID: ${PROJECT_ID}"
        log "Cloud Armor Policy: ${ARMOR_POLICY_NAME}"
        log "Load Balancer: ${LB_NAME}"
        log "Network: ${NETWORK_NAME}"
    else
        warning "No .deploy_config found. Using environment variables or defaults."
        
        # Set defaults if not provided
        export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
        export REGION_US=${REGION_US:-"us-central1"}
        export REGION_EU=${REGION_EU:-"europe-west1"}
        export NETWORK_NAME=${NETWORK_NAME:-"apigee-network"}
        export SUBNET_US=${SUBNET_US:-"apigee-subnet-us"}
        export SUBNET_EU=${SUBNET_EU:-"apigee-subnet-eu"}
        
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            warning "RANDOM_SUFFIX not set. Some resources may not be found."
            export RANDOM_SUFFIX="unknown"
        fi
        
        export ARMOR_POLICY_NAME=${ARMOR_POLICY_NAME:-"api-security-policy-${RANDOM_SUFFIX}"}
        export LB_NAME=${LB_NAME:-"global-api-lb-${RANDOM_SUFFIX}"}
        export DOMAIN_NAME=${DOMAIN_NAME:-"api-${RANDOM_SUFFIX}.example.com"}
        
        if [[ -z "$PROJECT_ID" ]]; then
            error "PROJECT_ID not found. Please set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    warning "This will permanently delete all Multi-Regional API Gateway resources!"
    echo "Resources to be deleted:"
    echo "  - Apigee organization and instances"
    echo "  - Cloud Armor security policies"
    echo "  - Global Load Balancer components"
    echo "  - VPC network and subnets"
    echo "  - SSL certificates"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Cloud Armor Policy: ${ARMOR_POLICY_NAME}"
    echo "Load Balancer: ${LB_NAME}"
    echo "Network: ${NETWORK_NAME}"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Starting cleanup process..."
}

# Remove global load balancer components
cleanup_load_balancer() {
    log "Cleaning up global load balancer components..."
    
    # Delete forwarding rule
    log "Deleting forwarding rule: ${LB_NAME}-rule"
    if gcloud compute forwarding-rules delete "${LB_NAME}-rule" \
        --global --quiet 2>/dev/null; then
        success "Forwarding rule deleted"
    else
        warning "Failed to delete forwarding rule or it doesn't exist"
    fi
    
    # Delete target HTTPS proxy
    log "Deleting target HTTPS proxy: ${LB_NAME}-proxy"
    if gcloud compute target-https-proxies delete "${LB_NAME}-proxy" \
        --global --quiet 2>/dev/null; then
        success "Target HTTPS proxy deleted"
    else
        warning "Failed to delete target HTTPS proxy or it doesn't exist"
    fi
    
    # Delete SSL certificate
    log "Deleting SSL certificate: api-ssl-cert"
    if gcloud compute ssl-certificates delete api-ssl-cert \
        --global --quiet 2>/dev/null; then
        success "SSL certificate deleted"
    else
        warning "Failed to delete SSL certificate or it doesn't exist"
    fi
    
    # Delete URL map
    log "Deleting URL map: ${LB_NAME}-url-map"
    if gcloud compute url-maps delete "${LB_NAME}-url-map" \
        --global --quiet 2>/dev/null; then
        success "URL map deleted"
    else
        warning "Failed to delete URL map or it doesn't exist"
    fi
    
    success "Load balancer components cleanup completed"
}

# Remove backend services and Cloud Armor
cleanup_backend_services() {
    log "Cleaning up backend services and Cloud Armor..."
    
    # Delete backend services
    log "Deleting US backend service: apigee-backend-us"
    if gcloud compute backend-services delete apigee-backend-us \
        --global --quiet 2>/dev/null; then
        success "US backend service deleted"
    else
        warning "Failed to delete US backend service or it doesn't exist"
    fi
    
    log "Deleting EU backend service: apigee-backend-eu"
    if gcloud compute backend-services delete apigee-backend-eu \
        --global --quiet 2>/dev/null; then
        success "EU backend service deleted"
    else
        warning "Failed to delete EU backend service or it doesn't exist"
    fi
    
    # Delete health check
    log "Deleting health check: api-health-check"
    if gcloud compute health-checks delete api-health-check \
        --quiet 2>/dev/null; then
        success "Health check deleted"
    else
        warning "Failed to delete health check or it doesn't exist"
    fi
    
    # Delete Cloud Armor security policy
    log "Deleting Cloud Armor policy: ${ARMOR_POLICY_NAME}"
    if gcloud compute security-policies delete "${ARMOR_POLICY_NAME}" \
        --quiet 2>/dev/null; then
        success "Cloud Armor security policy deleted"
    else
        warning "Failed to delete Cloud Armor policy or it doesn't exist"
    fi
    
    # Delete global IP address
    log "Deleting global IP address: ${LB_NAME}-ip"
    if gcloud compute addresses delete "${LB_NAME}-ip" \
        --global --quiet 2>/dev/null; then
        success "Global IP address deleted"
    else
        warning "Failed to delete global IP address or it doesn't exist"
    fi
    
    success "Backend services and Cloud Armor cleanup completed"
}

# Remove Apigee resources
cleanup_apigee() {
    log "Cleaning up Apigee resources..."
    warning "This process can take 10-15 minutes to complete"
    
    # Delete environment attachments first
    log "Detaching environments from instances..."
    
    if gcloud apigee environments describe production-us \
        --organization="${PROJECT_ID}" &>/dev/null; then
        log "Detaching US environment from instance..."
        gcloud apigee environments detach "${PROJECT_ID}" \
            --environment=production-us \
            --quiet 2>/dev/null || warning "Failed to detach US environment"
    fi
    
    if gcloud apigee environments describe production-eu \
        --organization="${PROJECT_ID}" &>/dev/null; then
        log "Detaching EU environment from instance..."
        gcloud apigee environments detach "${PROJECT_ID}" \
            --environment=production-eu \
            --quiet 2>/dev/null || warning "Failed to detach EU environment"
    fi
    
    # Delete Apigee instances
    log "Deleting US Apigee instance: us-instance"
    if gcloud apigee instances delete us-instance \
        --organization="${PROJECT_ID}" --quiet 2>/dev/null; then
        success "US Apigee instance deletion initiated"
    else
        warning "Failed to delete US Apigee instance or it doesn't exist"
    fi
    
    log "Deleting EU Apigee instance: eu-instance"
    if gcloud apigee instances delete eu-instance \
        --organization="${PROJECT_ID}" --quiet 2>/dev/null; then
        success "EU Apigee instance deletion initiated"
    else
        warning "Failed to delete EU Apigee instance or it doesn't exist"
    fi
    
    # Wait for instance deletion to complete
    log "Waiting for Apigee instances to be deleted..."
    local max_attempts=30  # 15 minutes with 30-second intervals
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local us_exists=false
        local eu_exists=false
        
        if gcloud apigee instances describe us-instance \
            --organization="${PROJECT_ID}" &>/dev/null; then
            us_exists=true
        fi
        
        if gcloud apigee instances describe eu-instance \
            --organization="${PROJECT_ID}" &>/dev/null; then
            eu_exists=true
        fi
        
        if [[ "$us_exists" == false && "$eu_exists" == false ]]; then
            success "All Apigee instances deleted"
            break
        fi
        
        log "Waiting for instances to be deleted... (attempt $((attempt + 1))/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warning "Timeout waiting for instance deletion. Some instances may still be deleting."
    fi
    
    # Delete environments
    log "Deleting environments..."
    if gcloud apigee environments delete production-us \
        --organization="${PROJECT_ID}" --quiet 2>/dev/null; then
        success "US environment deleted"
    else
        warning "Failed to delete US environment or it doesn't exist"
    fi
    
    if gcloud apigee environments delete production-eu \
        --organization="${PROJECT_ID}" --quiet 2>/dev/null; then
        success "EU environment deleted"
    else
        warning "Failed to delete EU environment or it doesn't exist"
    fi
    
    # Delete environment groups
    log "Deleting environment groups..."
    if gcloud apigee envgroups delete prod-us \
        --organization="${PROJECT_ID}" --quiet 2>/dev/null; then
        success "US environment group deleted"
    else
        warning "Failed to delete US environment group or it doesn't exist"
    fi
    
    if gcloud apigee envgroups delete prod-eu \
        --organization="${PROJECT_ID}" --quiet 2>/dev/null; then
        success "EU environment group deleted"
    else
        warning "Failed to delete EU environment group or it doesn't exist"
    fi
    
    success "Apigee resources cleanup completed"
    warning "Note: Apigee organization requires manual deletion through the console"
    log "Visit: https://console.cloud.google.com/apigee/organizations"
}

# Remove network resources
cleanup_network() {
    log "Cleaning up network resources..."
    
    # Delete VPC subnets
    log "Deleting US subnet: ${SUBNET_US}"
    if gcloud compute networks subnets delete "${SUBNET_US}" \
        --region="${REGION_US}" --quiet 2>/dev/null; then
        success "US subnet deleted"
    else
        warning "Failed to delete US subnet or it doesn't exist"
    fi
    
    log "Deleting EU subnet: ${SUBNET_EU}"
    if gcloud compute networks subnets delete "${SUBNET_EU}" \
        --region="${REGION_EU}" --quiet 2>/dev/null; then
        success "EU subnet deleted"
    else
        warning "Failed to delete EU subnet or it doesn't exist"
    fi
    
    # Delete VPC network
    log "Deleting VPC network: ${NETWORK_NAME}"
    if gcloud compute networks delete "${NETWORK_NAME}" \
        --quiet 2>/dev/null; then
        success "VPC network deleted"
    else
        warning "Failed to delete VPC network or it doesn't exist"
    fi
    
    success "Network resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    if [[ -f ".deploy_config" ]]; then
        rm -f .deploy_config
        success "Local configuration file removed"
    fi
    
    success "Local cleanup completed"
}

# Run final validation
run_final_validation() {
    log "Running final validation checks..."
    
    local issues_found=0
    
    # Check if Cloud Armor policy still exists
    if gcloud compute security-policies describe "${ARMOR_POLICY_NAME}" &>/dev/null; then
        warning "Cloud Armor policy still exists: ${ARMOR_POLICY_NAME}"
        ((issues_found++))
    fi
    
    # Check if load balancer components still exist
    if gcloud compute forwarding-rules describe "${LB_NAME}-rule" --global &>/dev/null; then
        warning "Forwarding rule still exists: ${LB_NAME}-rule"
        ((issues_found++))
    fi
    
    # Check if backend services still exist
    if gcloud compute backend-services describe apigee-backend-us --global &>/dev/null; then
        warning "US backend service still exists: apigee-backend-us"
        ((issues_found++))
    fi
    
    if gcloud compute backend-services describe apigee-backend-eu --global &>/dev/null; then
        warning "EU backend service still exists: apigee-backend-eu"
        ((issues_found++))
    fi
    
    # Check if Apigee instances still exist
    if gcloud apigee instances describe us-instance --organization="${PROJECT_ID}" &>/dev/null; then
        warning "US Apigee instance still exists: us-instance"
        ((issues_found++))
    fi
    
    if gcloud apigee instances describe eu-instance --organization="${PROJECT_ID}" &>/dev/null; then
        warning "EU Apigee instance still exists: eu-instance"
        ((issues_found++))
    fi
    
    # Check if network still exists
    if gcloud compute networks describe "${NETWORK_NAME}" &>/dev/null; then
        warning "VPC network still exists: ${NETWORK_NAME}"
        ((issues_found++))
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        success "All resources successfully removed"
    else
        warning "$issues_found resource(s) may still exist or be in deletion process"
    fi
    
    success "Final validation completed"
}

# Print cleanup summary
print_summary() {
    log "Cleanup Summary"
    echo "=================================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Cleaned up resources:"
    echo "  ✓ Global Load Balancer components"
    echo "  ✓ Backend services and health checks"
    echo "  ✓ Cloud Armor security policies"
    echo "  ✓ SSL certificates"
    echo "  ✓ Apigee instances and environments"
    echo "  ✓ VPC network and subnets"
    echo "  ✓ Global IP addresses"
    echo "  ✓ Local configuration files"
    echo "=================================================="
    echo ""
    success "Multi-Regional API Gateway cleanup completed!"
    echo ""
    warning "Important Notes:"
    echo "1. Apigee organization requires manual deletion through console"
    echo "2. Check billing to ensure no unexpected charges"
    echo "3. Some resources may take additional time to fully delete"
    echo "4. Monitor Cloud Console for any remaining resources"
    echo ""
    log "Visit Google Cloud Console to verify complete cleanup"
}

# Main cleanup function
main() {
    log "Starting Multi-Regional API Gateways cleanup..."
    
    check_prerequisites
    load_configuration
    confirm_destruction
    
    cleanup_load_balancer
    cleanup_backend_services
    cleanup_apigee
    cleanup_network
    cleanup_local_files
    
    run_final_validation
    print_summary
    
    success "Cleanup script completed!"
}

# Execute main function
main "$@"