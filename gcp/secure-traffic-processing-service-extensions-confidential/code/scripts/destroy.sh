#!/bin/bash

# Secure Traffic Processing with Service Extensions and Confidential Computing - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to prompt for confirmation
confirm_cleanup() {
    echo ""
    warn "This script will DELETE ALL resources created by the deployment script."
    warn "This action is IRREVERSIBLE and will remove:"
    warn "  - Confidential VM instances"
    warn "  - Load balancer infrastructure"
    warn "  - Storage buckets and data"
    warn "  - KMS keys (will be scheduled for deletion)"
    warn "  - IAM service accounts"
    warn "  - Firewall rules"
    echo ""
    
    # Get project ID if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        echo "Please enter your GCP Project ID:"
        read -r PROJECT_ID
        export PROJECT_ID
    fi
    
    info "Target project: ${PROJECT_ID}"
    echo ""
    
    read -p "Are you ABSOLUTELY sure you want to delete all resources? Type 'DELETE' to confirm: " -r
    echo ""
    if [[ "$REPLY" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warn "Starting cleanup in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
}

# Function to setup environment
setup_environment() {
    log "Setting up environment..."
    
    # Set default project
    gcloud config set project "${PROJECT_ID}" || {
        error "Failed to set project ${PROJECT_ID}. Please check if project exists and you have access."
        exit 1
    }
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "Environment configured for cleanup"
    info "Project ID: ${PROJECT_ID}"
    info "Region: ${REGION}"
    info "Zone: ${ZONE}"
}

# Function to get existing resources dynamically
discover_resources() {
    log "Discovering existing resources..."
    
    # Find Confidential VMs with specific labels or patterns
    CONFIDENTIAL_VMS=($(gcloud compute instances list \
        --filter="name~'confidential-processor-.*'" \
        --format="value(name,zone)" 2>/dev/null | awk '{print $1":"$2}' || true))
    
    # Find traffic service backend services
    BACKEND_SERVICES=($(gcloud compute backend-services list \
        --filter="name~'traffic-service-.*'" \
        --format="value(name)" 2>/dev/null || true))
    
    # Find storage buckets with traffic data pattern
    STORAGE_BUCKETS=($(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
        grep "gs://secure-traffic-data-" | sed 's|gs://||' | sed 's|/||' || true))
    
    # Find KMS key rings with traffic pattern
    KMS_KEYRINGS=($(gcloud kms keyrings list \
        --location="${REGION}" \
        --filter="name~'.*traffic-keyring-.*'" \
        --format="value(name)" 2>/dev/null | \
        sed 's|.*/||' || true))
    
    # Find service accounts
    SERVICE_ACCOUNTS=($(gcloud iam service-accounts list \
        --filter="displayName:'Confidential Traffic Processor'" \
        --format="value(email)" 2>/dev/null || true))
    
    # Find instance groups
    INSTANCE_GROUPS=($(gcloud compute instance-groups unmanaged list \
        --filter="name~'traffic-processors.*'" \
        --format="value(name,zone)" 2>/dev/null | awk '{print $1":"$2}' || true))
    
    # Display discovered resources
    info "Discovered resources for cleanup:"
    info "  - Confidential VMs: ${#CONFIDENTIAL_VMS[@]}"
    info "  - Backend Services: ${#BACKEND_SERVICES[@]}"
    info "  - Storage Buckets: ${#STORAGE_BUCKETS[@]}"
    info "  - KMS Key Rings: ${#KMS_KEYRINGS[@]}"
    info "  - Service Accounts: ${#SERVICE_ACCOUNTS[@]}"
    info "  - Instance Groups: ${#INSTANCE_GROUPS[@]}"
}

# Function to delete load balancer resources
delete_load_balancer() {
    log "Removing load balancer infrastructure..."
    
    # Delete forwarding rules
    local forwarding_rules=($(gcloud compute forwarding-rules list \
        --filter="name~'secure-traffic.*'" \
        --format="value(name)" 2>/dev/null || true))
    
    for rule in "${forwarding_rules[@]}"; do
        if [[ -n "$rule" ]]; then
            info "Deleting forwarding rule: $rule"
            if gcloud compute forwarding-rules delete "$rule" --global --quiet 2>/dev/null; then
                log "Forwarding rule deleted: $rule"
            else
                warn "Failed to delete forwarding rule: $rule"
            fi
        fi
    done
    
    # Delete HTTPS proxies
    local https_proxies=($(gcloud compute target-https-proxies list \
        --filter="name~'secure-traffic.*'" \
        --format="value(name)" 2>/dev/null || true))
    
    for proxy in "${https_proxies[@]}"; do
        if [[ -n "$proxy" ]]; then
            info "Deleting HTTPS proxy: $proxy"
            if gcloud compute target-https-proxies delete "$proxy" --global --quiet 2>/dev/null; then
                log "HTTPS proxy deleted: $proxy"
            else
                warn "Failed to delete HTTPS proxy: $proxy"
            fi
        fi
    done
    
    # Delete SSL certificates
    local ssl_certs=($(gcloud compute ssl-certificates list \
        --filter="name~'secure-traffic.*'" \
        --format="value(name)" 2>/dev/null || true))
    
    for cert in "${ssl_certs[@]}"; do
        if [[ -n "$cert" ]]; then
            info "Deleting SSL certificate: $cert"
            if gcloud compute ssl-certificates delete "$cert" --global --quiet 2>/dev/null; then
                log "SSL certificate deleted: $cert"
            else
                warn "Failed to delete SSL certificate: $cert"
            fi
        fi
    done
    
    # Delete URL maps
    local url_maps=($(gcloud compute url-maps list \
        --filter="name~'secure-traffic.*'" \
        --format="value(name)" 2>/dev/null || true))
    
    for map in "${url_maps[@]}"; do
        if [[ -n "$map" ]]; then
            info "Deleting URL map: $map"
            if gcloud compute url-maps delete "$map" --global --quiet 2>/dev/null; then
                log "URL map deleted: $map"
            else
                warn "Failed to delete URL map: $map"
            fi
        fi
    done
    
    log "Load balancer resources cleanup completed"
}

# Function to delete backend services
delete_backend_services() {
    log "Removing backend services..."
    
    # Delete backend services
    for service in "${BACKEND_SERVICES[@]}"; do
        if [[ -n "$service" ]]; then
            info "Deleting backend service: $service"
            if gcloud compute backend-services delete "$service" --global --quiet 2>/dev/null; then
                log "Backend service deleted: $service"
            else
                warn "Failed to delete backend service: $service"
            fi
        fi
    done
    
    # Delete health checks
    local health_checks=($(gcloud compute health-checks list \
        --filter="name~'traffic-processor.*'" \
        --format="value(name)" 2>/dev/null || true))
    
    for hc in "${health_checks[@]}"; do
        if [[ -n "$hc" ]]; then
            info "Deleting health check: $hc"
            if gcloud compute health-checks delete "$hc" --global --quiet 2>/dev/null; then
                log "Health check deleted: $hc"
            else
                warn "Failed to delete health check: $hc"
            fi
        fi
    done
    
    log "Backend services cleanup completed"
}

# Function to delete instance groups and VMs
delete_compute_resources() {
    log "Removing compute resources..."
    
    # Delete instance groups (must be done before deleting VMs)
    for ig_info in "${INSTANCE_GROUPS[@]}"; do
        if [[ -n "$ig_info" ]]; then
            local ig_name=$(echo "$ig_info" | cut -d: -f1)
            local ig_zone=$(echo "$ig_info" | cut -d: -f2)
            
            info "Deleting instance group: $ig_name in zone $ig_zone"
            if gcloud compute instance-groups unmanaged delete "$ig_name" \
                --zone="$ig_zone" --quiet 2>/dev/null; then
                log "Instance group deleted: $ig_name"
            else
                warn "Failed to delete instance group: $ig_name"
            fi
        fi
    done
    
    # Delete Confidential VMs
    for vm_info in "${CONFIDENTIAL_VMS[@]}"; do
        if [[ -n "$vm_info" ]]; then
            local vm_name=$(echo "$vm_info" | cut -d: -f1)
            local vm_zone=$(echo "$vm_info" | cut -d: -f2)
            
            info "Deleting Confidential VM: $vm_name in zone $vm_zone"
            if gcloud compute instances delete "$vm_name" \
                --zone="$vm_zone" --quiet 2>/dev/null; then
                log "Confidential VM deleted: $vm_name"
            else
                warn "Failed to delete Confidential VM: $vm_name"
            fi
        fi
    done
    
    log "Compute resources cleanup completed"
}

# Function to delete storage resources
delete_storage_resources() {
    log "Removing storage resources..."
    
    for bucket in "${STORAGE_BUCKETS[@]}"; do
        if [[ -n "$bucket" ]]; then
            info "Deleting storage bucket: $bucket"
            
            # Remove all objects first
            if gsutil -m rm -r "gs://$bucket/**" 2>/dev/null || true; then
                info "Bucket contents removed: $bucket"
            fi
            
            # Delete the bucket
            if gsutil rb "gs://$bucket" 2>/dev/null; then
                log "Storage bucket deleted: $bucket"
            else
                warn "Failed to delete storage bucket: $bucket"
            fi
        fi
    done
    
    log "Storage resources cleanup completed"
}

# Function to delete firewall rules
delete_firewall_rules() {
    log "Removing firewall rules..."
    
    local firewall_rules=($(gcloud compute firewall-rules list \
        --filter="name~'.*traffic-processor.*'" \
        --format="value(name)" 2>/dev/null || true))
    
    for rule in "${firewall_rules[@]}"; do
        if [[ -n "$rule" ]]; then
            info "Deleting firewall rule: $rule"
            if gcloud compute firewall-rules delete "$rule" --quiet 2>/dev/null; then
                log "Firewall rule deleted: $rule"
            else
                warn "Failed to delete firewall rule: $rule"
            fi
        fi
    done
    
    log "Firewall rules cleanup completed"
}

# Function to delete KMS resources
delete_kms_resources() {
    log "Removing KMS resources..."
    
    for keyring in "${KMS_KEYRINGS[@]}"; do
        if [[ -n "$keyring" ]]; then
            info "Processing KMS keyring: $keyring"
            
            # List and schedule destruction of keys in the keyring
            local keys=($(gcloud kms keys list \
                --keyring="$keyring" \
                --location="${REGION}" \
                --format="value(name)" 2>/dev/null | \
                sed 's|.*/||' || true))
            
            for key in "${keys[@]}"; do
                if [[ -n "$key" ]]; then
                    info "Scheduling key destruction: $key"
                    
                    # Get the latest version of the key
                    local versions=($(gcloud kms keys versions list \
                        --key="$key" \
                        --keyring="$keyring" \
                        --location="${REGION}" \
                        --format="value(name)" 2>/dev/null | \
                        sed 's|.*/||' || true))
                    
                    for version in "${versions[@]}"; do
                        if [[ -n "$version" ]]; then
                            if gcloud kms keys versions destroy "$version" \
                                --key="$key" \
                                --keyring="$keyring" \
                                --location="${REGION}" \
                                --quiet 2>/dev/null; then
                                log "Key version scheduled for destruction: $key/$version"
                            else
                                warn "Failed to schedule key version destruction: $key/$version"
                            fi
                        fi
                    done
                fi
            done
            
            warn "KMS keyring '$keyring' cannot be deleted but keys are scheduled for destruction"
            warn "Keys will be permanently deleted after the retention period (24 hours minimum)"
        fi
    done
    
    log "KMS resources cleanup completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Removing IAM resources..."
    
    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        if [[ -n "$sa" ]]; then
            info "Deleting service account: $sa"
            
            # Remove IAM policy bindings first
            local bindings=($(gcloud projects get-iam-policy "${PROJECT_ID}" \
                --flatten="bindings[].members" \
                --filter="bindings.members:serviceAccount:$sa" \
                --format="value(bindings.role)" 2>/dev/null || true))
            
            for role in "${bindings[@]}"; do
                if [[ -n "$role" ]]; then
                    info "Removing IAM binding: $sa -> $role"
                    gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                        --member="serviceAccount:$sa" \
                        --role="$role" \
                        --quiet 2>/dev/null || warn "Failed to remove IAM binding: $role"
                fi
            done
            
            # Delete service account
            if gcloud iam service-accounts delete "$sa" --quiet 2>/dev/null; then
                log "Service account deleted: $sa"
            else
                warn "Failed to delete service account: $sa"
            fi
        fi
    done
    
    log "IAM resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "lifecycle.json"
        "test.encrypted"
        "*.log"
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        if ls $file_pattern 1> /dev/null 2>&1; then
            rm -f $file_pattern
            info "Removed local file(s): $file_pattern"
        fi
    done
    
    log "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local remaining_issues=0
    
    # Check for remaining VMs
    local remaining_vms=$(gcloud compute instances list \
        --filter="name~'confidential-processor-.*'" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ $remaining_vms -gt 0 ]]; then
        warn "Found $remaining_vms remaining Confidential VMs"
        ((remaining_issues++))
    fi
    
    # Check for remaining backend services
    local remaining_services=$(gcloud compute backend-services list \
        --filter="name~'traffic-service-.*'" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ $remaining_services -gt 0 ]]; then
        warn "Found $remaining_services remaining backend services"
        ((remaining_issues++))
    fi
    
    # Check for remaining storage buckets
    local remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
        grep -c "secure-traffic-data-" || echo "0")
    
    if [[ $remaining_buckets -gt 0 ]]; then
        warn "Found $remaining_buckets remaining storage buckets"
        ((remaining_issues++))
    fi
    
    # Check for remaining service accounts
    local remaining_sa=$(gcloud iam service-accounts list \
        --filter="displayName:'Confidential Traffic Processor'" \
        --format="value(email)" 2>/dev/null | wc -l)
    
    if [[ $remaining_sa -gt 0 ]]; then
        warn "Found $remaining_sa remaining service accounts"
        ((remaining_issues++))
    fi
    
    if [[ $remaining_issues -eq 0 ]]; then
        log "Cleanup verification completed successfully - no remaining resources found"
    else
        warn "Cleanup verification found $remaining_issues potential issues"
        warn "Some resources may need manual cleanup"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    log "🧹 Cleanup process completed!"
    echo ""
    info "Resources processed for deletion:"
    info "  - Confidential VMs: ${#CONFIDENTIAL_VMS[@]}"
    info "  - Backend Services: ${#BACKEND_SERVICES[@]}"
    info "  - Storage Buckets: ${#STORAGE_BUCKETS[@]}"
    info "  - KMS Key Rings: ${#KMS_KEYRINGS[@]} (keys scheduled for destruction)"
    info "  - Service Accounts: ${#SERVICE_ACCOUNTS[@]}"
    info "  - Instance Groups: ${#INSTANCE_GROUPS[@]}"
    echo ""
    
    warn "Important notes:"
    warn "  - KMS keys are scheduled for destruction but will be retained for 24+ hours"
    warn "  - Some resources may take a few minutes to be fully removed"
    warn "  - Check your GCP console to verify all resources are deleted"
    echo ""
    
    info "Project: ${PROJECT_ID}"
    info "If you need to verify cleanup, check the GCP Console or run:"
    info "  gcloud compute instances list"
    info "  gcloud compute backend-services list"
    info "  gsutil ls -p ${PROJECT_ID}"
    echo ""
}

# Main cleanup function
main() {
    echo ""
    log "Starting Secure Traffic Processing cleanup..."
    echo ""
    
    # Pre-cleanup checks and setup
    check_prerequisites
    confirm_cleanup
    setup_environment
    discover_resources
    
    # Core cleanup steps (order matters!)
    delete_load_balancer
    delete_backend_services
    delete_compute_resources
    delete_storage_resources
    delete_firewall_rules
    delete_kms_resources
    delete_iam_resources
    cleanup_local_files
    
    # Post-cleanup verification
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup process completed!"
}

# Handle script interruption
trap 'error "Cleanup interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"