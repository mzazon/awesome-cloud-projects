#!/bin/bash

# Service Discovery with Traffic Director and Cloud DNS - Cleanup Script
# This script safely removes all resources created by the deployment script
# to avoid ongoing charges and clean up the environment

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo -e "${RED}WARNING: This will delete all resources created for the service discovery deployment.${NC}"
    echo "This action cannot be undone!"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud SDK (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
    fi
    
    success "Prerequisites check completed"
}

# Function to detect environment variables
detect_environment() {
    log "Detecting environment variables..."
    
    # Try to get current project
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error "PROJECT_ID not set and no default project configured. Please set PROJECT_ID environment variable."
        fi
    fi
    
    # Set default values for other variables if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE_A="${ZONE_A:-us-central1-a}"
    export ZONE_B="${ZONE_B:-us-central1-b}"
    export ZONE_C="${ZONE_C:-us-central1-c}"
    
    # Try to detect resource names by listing existing resources
    if [[ -z "${SERVICE_NAME:-}" ]]; then
        log "Attempting to detect service name from existing resources..."
        
        # Look for instance templates with microservice prefix
        SERVICE_NAME=$(gcloud compute instance-templates list \
            --filter="name~microservice-.*" \
            --format="value(name)" \
            --limit=1 2>/dev/null | sed 's/-template$//' || echo "")
        
        if [[ -z "${SERVICE_NAME}" ]]; then
            warning "Could not auto-detect SERVICE_NAME. Please set it manually."
            read -p "Enter SERVICE_NAME (e.g., microservice-abc123): " SERVICE_NAME
            if [[ -z "${SERVICE_NAME}" ]]; then
                error "SERVICE_NAME is required"
            fi
        fi
    fi
    
    # Derive other names from SERVICE_NAME
    export DNS_ZONE_NAME="${DNS_ZONE_NAME:-discovery-zone-${SERVICE_NAME#microservice-}}"
    export DOMAIN_NAME="${DOMAIN_NAME:-${SERVICE_NAME}.example.com}"
    
    # Extract random suffix for firewall rules
    RANDOM_SUFFIX="${SERVICE_NAME#microservice-}"
    export RANDOM_SUFFIX
    export TEST_INSTANCE="test-client-${RANDOM_SUFFIX}"
    
    log "Project ID: ${PROJECT_ID}"
    log "Service Name: ${SERVICE_NAME}"
    log "DNS Zone: ${DNS_ZONE_NAME}"
    log "Domain: ${DOMAIN_NAME}"
    
    success "Environment variables detected"
}

# Function to delete DNS records and zones
delete_dns_resources() {
    log "Deleting DNS records and zones..."
    
    # Delete DNS records first
    if gcloud dns managed-zones describe "${DNS_ZONE_NAME}" &>/dev/null; then
        log "Deleting DNS records from zone: ${DNS_ZONE_NAME}"
        
        # Delete A record
        if gcloud dns record-sets describe "${DOMAIN_NAME}." --zone="${DNS_ZONE_NAME}" --type=A &>/dev/null; then
            gcloud dns record-sets delete "${DOMAIN_NAME}." \
                --zone="${DNS_ZONE_NAME}" \
                --type=A \
                --quiet || warning "Failed to delete A record"
            log "A record deleted"
        fi
        
        # Delete SRV record
        if gcloud dns record-sets describe "_http._tcp.${DOMAIN_NAME}." --zone="${DNS_ZONE_NAME}" --type=SRV &>/dev/null; then
            gcloud dns record-sets delete "_http._tcp.${DOMAIN_NAME}." \
                --zone="${DNS_ZONE_NAME}" \
                --type=SRV \
                --quiet || warning "Failed to delete SRV record"
            log "SRV record deleted"
        fi
        
        # Delete health record
        if gcloud dns record-sets describe "health.${DOMAIN_NAME}." --zone="${DNS_ZONE_NAME}" --type=A &>/dev/null; then
            gcloud dns record-sets delete "health.${DOMAIN_NAME}." \
                --zone="${DNS_ZONE_NAME}" \
                --type=A \
                --quiet || warning "Failed to delete health record"
            log "Health record deleted"
        fi
        
        # Delete private DNS zone
        gcloud dns managed-zones delete "${DNS_ZONE_NAME}" --quiet || warning "Failed to delete private DNS zone"
        log "Private DNS zone deleted"
    else
        log "Private DNS zone ${DNS_ZONE_NAME} not found"
    fi
    
    # Delete public DNS zone
    if gcloud dns managed-zones describe "${DNS_ZONE_NAME}-public" &>/dev/null; then
        gcloud dns managed-zones delete "${DNS_ZONE_NAME}-public" --quiet || warning "Failed to delete public DNS zone"
        log "Public DNS zone deleted"
    else
        log "Public DNS zone ${DNS_ZONE_NAME}-public not found"
    fi
    
    success "DNS resources cleaned up"
}

# Function to delete Traffic Director configuration
delete_traffic_director_resources() {
    log "Deleting Traffic Director configuration..."
    
    # Delete forwarding rule
    if gcloud compute forwarding-rules describe "${SERVICE_NAME}-forwarding-rule" --global &>/dev/null; then
        gcloud compute forwarding-rules delete "${SERVICE_NAME}-forwarding-rule" \
            --global --quiet || warning "Failed to delete forwarding rule"
        log "Forwarding rule deleted"
    fi
    
    # Delete target HTTP proxy
    if gcloud compute target-http-proxies describe "${SERVICE_NAME}-proxy" &>/dev/null; then
        gcloud compute target-http-proxies delete "${SERVICE_NAME}-proxy" --quiet || warning "Failed to delete HTTP proxy"
        log "HTTP proxy deleted"
    fi
    
    # Delete URL map
    if gcloud compute url-maps describe "${SERVICE_NAME}-url-map" &>/dev/null; then
        gcloud compute url-maps delete "${SERVICE_NAME}-url-map" --quiet || warning "Failed to delete URL map"
        log "URL map deleted"
    fi
    
    # Delete backend service
    if gcloud compute backend-services describe "${SERVICE_NAME}-backend" --global &>/dev/null; then
        gcloud compute backend-services delete "${SERVICE_NAME}-backend" \
            --global --quiet || warning "Failed to delete backend service"
        log "Backend service deleted"
    fi
    
    success "Traffic Director resources cleaned up"
}

# Function to delete compute resources
delete_compute_resources() {
    log "Deleting compute resources..."
    
    # Delete test instance
    if gcloud compute instances describe "${TEST_INSTANCE}" --zone="${ZONE_A}" &>/dev/null; then
        gcloud compute instances delete "${TEST_INSTANCE}" \
            --zone="${ZONE_A}" --quiet || warning "Failed to delete test instance"
        log "Test instance deleted"
    fi
    
    # Delete service instances
    for zone in "${ZONE_A}" "${ZONE_B}" "${ZONE_C}"; do
        for instance_num in 1 2; do
            instance_name="${SERVICE_NAME}-${zone}-${instance_num}"
            if gcloud compute instances describe "${instance_name}" --zone="${zone}" &>/dev/null; then
                gcloud compute instances delete "${instance_name}" \
                    --zone="${zone}" --quiet || warning "Failed to delete instance ${instance_name}"
                log "Instance ${instance_name} deleted"
            fi
        done
    done
    
    # Delete instance template
    if gcloud compute instance-templates describe "${SERVICE_NAME}-template" &>/dev/null; then
        gcloud compute instance-templates delete "${SERVICE_NAME}-template" --quiet || warning "Failed to delete instance template"
        log "Instance template deleted"
    fi
    
    success "Compute instances cleaned up"
}

# Function to delete networking resources
delete_networking_resources() {
    log "Deleting networking resources..."
    
    # Delete NEGs
    for zone in "${ZONE_A}" "${ZONE_B}" "${ZONE_C}"; do
        neg_name="${SERVICE_NAME}-neg-${zone}"
        if gcloud compute network-endpoint-groups describe "${neg_name}" --zone="${zone}" &>/dev/null; then
            gcloud compute network-endpoint-groups delete "${neg_name}" \
                --zone="${zone}" --quiet || warning "Failed to delete NEG ${neg_name}"
            log "NEG ${neg_name} deleted"
        fi
    done
    
    # Delete health check
    if gcloud compute health-checks describe "${SERVICE_NAME}-health-check" &>/dev/null; then
        gcloud compute health-checks delete "${SERVICE_NAME}-health-check" --quiet || warning "Failed to delete health check"
        log "Health check deleted"
    fi
    
    # Delete firewall rule
    if gcloud compute firewall-rules describe "allow-health-check-${RANDOM_SUFFIX}" &>/dev/null; then
        gcloud compute firewall-rules delete "allow-health-check-${RANDOM_SUFFIX}" --quiet || warning "Failed to delete firewall rule"
        log "Firewall rule deleted"
    fi
    
    success "Networking resources cleaned up"
}

# Function to delete VPC network (optional)
delete_vpc_network() {
    log "Deleting VPC network..."
    
    # Check if we should delete VPC (only if it's not being used by other resources)
    if [[ "${DELETE_VPC:-}" == "true" ]]; then
        # Delete subnet
        if gcloud compute networks subnets describe service-mesh-subnet --region="${REGION}" &>/dev/null; then
            gcloud compute networks subnets delete service-mesh-subnet \
                --region="${REGION}" --quiet || warning "Failed to delete subnet"
            log "Subnet deleted"
        fi
        
        # Delete VPC network
        if gcloud compute networks describe service-mesh-vpc &>/dev/null; then
            gcloud compute networks delete service-mesh-vpc --quiet || warning "Failed to delete VPC network"
            log "VPC network deleted"
        fi
        
        success "VPC network cleaned up"
    else
        log "Skipping VPC deletion (set DELETE_VPC=true to delete)"
    fi
}

# Function to delete entire project (optional and dangerous)
delete_project() {
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        log "Deleting entire project: ${PROJECT_ID}"
        echo ""
        echo -e "${RED}FINAL WARNING: This will delete the ENTIRE project and ALL resources within it!${NC}"
        echo "This action is IRREVERSIBLE!"
        echo ""
        
        if [[ "${FORCE_DELETE:-}" != "true" ]]; then
            read -p "Type the project ID '${PROJECT_ID}' to confirm deletion: " -r
            if [[ $REPLY != "${PROJECT_ID}" ]]; then
                log "Project deletion cancelled - project ID mismatch"
                return 0
            fi
        fi
        
        gcloud projects delete "${PROJECT_ID}" --quiet || error "Failed to delete project"
        success "Project ${PROJECT_ID} deletion initiated"
    else
        log "Skipping project deletion (set DELETE_PROJECT=true to delete)"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local resources_found=false
    
    # Check for remaining instances
    if gcloud compute instances list --filter="name~${SERVICE_NAME}.*" --format="value(name)" | grep -q .; then
        warning "Some instances still exist"
        resources_found=true
    fi
    
    # Check for remaining NEGs
    for zone in "${ZONE_A}" "${ZONE_B}" "${ZONE_C}"; do
        if gcloud compute network-endpoint-groups describe "${SERVICE_NAME}-neg-${zone}" --zone="${zone}" &>/dev/null; then
            warning "NEG ${SERVICE_NAME}-neg-${zone} still exists"
            resources_found=true
        fi
    done
    
    # Check for backend service
    if gcloud compute backend-services describe "${SERVICE_NAME}-backend" --global &>/dev/null; then
        warning "Backend service still exists"
        resources_found=true
    fi
    
    # Check for DNS zone
    if gcloud dns managed-zones describe "${DNS_ZONE_NAME}" &>/dev/null; then
        warning "DNS zone still exists"
        resources_found=true
    fi
    
    if [[ "${resources_found}" == "true" ]]; then
        warning "Some resources may still exist. Please verify manually."
    else
        success "All resources appear to be cleaned up successfully"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Service Name: ${SERVICE_NAME}"
    echo "DNS Zone: ${DNS_ZONE_NAME}"
    echo ""
    echo "Resources cleaned up:"
    echo "- DNS records and zones"
    echo "- Traffic Director configuration"
    echo "- Compute instances and templates"
    echo "- Network Endpoint Groups"
    echo "- Health checks and firewall rules"
    if [[ "${DELETE_VPC:-}" == "true" ]]; then
        echo "- VPC network and subnet"
    fi
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        echo "- Entire project (deletion initiated)"
    fi
    echo ""
    success "Cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Service Discovery cleanup..."
    
    check_prerequisites
    detect_environment
    confirm_destruction
    
    log "Beginning resource cleanup in reverse order..."
    
    delete_dns_resources
    delete_traffic_director_resources
    delete_compute_resources
    delete_networking_resources
    delete_vpc_network
    delete_project
    
    verify_cleanup
    display_cleanup_summary
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --delete-vpc)
            export DELETE_VPC="true"
            shift
            ;;
        --delete-project)
            export DELETE_PROJECT="true"
            shift
            ;;
        --project-id)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --service-name)
            export SERVICE_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force            Skip confirmation prompts"
            echo "  --delete-vpc       Also delete VPC network"
            echo "  --delete-project   Delete entire project (DANGEROUS)"
            echo "  --project-id ID    Specify project ID"
            echo "  --service-name NAME Specify service name"
            echo "  --help            Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID         Google Cloud project ID"
            echo "  SERVICE_NAME       Service name (e.g., microservice-abc123)"
            echo "  DELETE_VPC         Set to 'true' to delete VPC"
            echo "  DELETE_PROJECT     Set to 'true' to delete project"
            echo "  FORCE_DELETE       Set to 'true' to skip confirmations"
            exit 0
            ;;
        *)
            warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Run main function
main "$@"