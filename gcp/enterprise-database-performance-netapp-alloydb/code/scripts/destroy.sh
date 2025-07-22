#!/bin/bash

# Enterprise Database Performance with NetApp Volumes and AlloyDB - Cleanup Script
# This script removes all resources created by the deployment script
# Author: Generated from Cloud Recipe
# Version: 1.2

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
VPC_NAME="${VPC_NAME:-enterprise-db-vpc}"
SUBNET_NAME="${SUBNET_NAME:-enterprise-db-subnet}"

# Resource identifiers (will be detected or provided)
ALLOYDB_CLUSTER_ID="${ALLOYDB_CLUSTER_ID:-}"
NETAPP_STORAGE_POOL="${NETAPP_STORAGE_POOL:-}"
NETAPP_VOLUME="${NETAPP_VOLUME:-}"

# Force cleanup flag
FORCE_CLEANUP="${FORCE_CLEANUP:-false}"

# Display cleanup configuration
display_config() {
    log "Enterprise Database Performance Cleanup Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo "  VPC Name: ${VPC_NAME}"
    echo "  AlloyDB Cluster: ${ALLOYDB_CLUSTER_ID:-Auto-detect}"
    echo "  NetApp Storage Pool: ${NETAPP_STORAGE_POOL:-Auto-detect}"
    echo "  NetApp Volume: ${NETAPP_VOLUME:-Auto-detect}"
    echo "  Force Cleanup: ${FORCE_CLEANUP}"
    echo ""
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'."
    fi
    
    # Get current project if not set
    if [ -z "${PROJECT_ID}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "${PROJECT_ID}" ]; then
            error "No project ID specified and no default project set. Please set PROJECT_ID environment variable."
        fi
        log "Using current project: ${PROJECT_ID}"
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error "Project ${PROJECT_ID} does not exist or is not accessible."
    fi
    
    # Set project and region
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project"
    gcloud config set compute/region "${REGION}" || error "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error "Failed to set zone"
    
    success "Prerequisites check completed"
}

# Auto-detect resources if not specified
detect_resources() {
    log "Detecting enterprise database resources..."
    
    # Auto-detect AlloyDB clusters if not specified
    if [ -z "${ALLOYDB_CLUSTER_ID}" ]; then
        log "Auto-detecting AlloyDB clusters..."
        local clusters=$(gcloud alloydb clusters list --region="${REGION}" --format="value(name)" --filter="name~'enterprise-alloydb'" 2>/dev/null || echo "")
        if [ -n "$clusters" ]; then
            ALLOYDB_CLUSTER_ID=$(echo "$clusters" | head -n1 | sed 's|.*/||')
            log "Found AlloyDB cluster: ${ALLOYDB_CLUSTER_ID}"
        else
            warning "No AlloyDB clusters found matching 'enterprise-alloydb' pattern"
        fi
    fi
    
    # Auto-detect NetApp storage pools if not specified
    if [ -z "${NETAPP_STORAGE_POOL}" ]; then
        log "Auto-detecting NetApp storage pools..."
        local pools=$(gcloud netapp storage-pools list --location="${REGION}" --format="value(name)" --filter="name~'enterprise-storage-pool'" 2>/dev/null || echo "")
        if [ -n "$pools" ]; then
            NETAPP_STORAGE_POOL=$(echo "$pools" | head -n1 | sed 's|.*/||')
            log "Found NetApp storage pool: ${NETAPP_STORAGE_POOL}"
        else
            warning "No NetApp storage pools found matching 'enterprise-storage-pool' pattern"
        fi
    fi
    
    # Auto-detect NetApp volumes if not specified
    if [ -z "${NETAPP_VOLUME}" ]; then
        log "Auto-detecting NetApp volumes..."
        local volumes=$(gcloud netapp volumes list --location="${REGION}" --format="value(name)" --filter="name~'enterprise-db-volume'" 2>/dev/null || echo "")
        if [ -n "$volumes" ]; then
            NETAPP_VOLUME=$(echo "$volumes" | head -n1 | sed 's|.*/||')
            log "Found NetApp volume: ${NETAPP_VOLUME}"
        else
            warning "No NetApp volumes found matching 'enterprise-db-volume' pattern"
        fi
    fi
    
    success "Resource detection completed"
}

# Confirmation prompt
confirmation_prompt() {
    if [ "${FORCE_CLEANUP}" = "true" ]; then
        log "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    warning "🚨 DANGER: This will permanently delete all enterprise database resources!"
    echo ""
    echo "Resources to be deleted:"
    [ -n "${ALLOYDB_CLUSTER_ID}" ] && echo "  - AlloyDB Cluster: ${ALLOYDB_CLUSTER_ID}"
    [ -n "${NETAPP_STORAGE_POOL}" ] && echo "  - NetApp Storage Pool: ${NETAPP_STORAGE_POOL}"
    [ -n "${NETAPP_VOLUME}" ] && echo "  - NetApp Volume: ${NETAPP_VOLUME}"
    echo "  - Load balancers and networking components"
    echo "  - Monitoring dashboards and alerts"
    echo "  - Security resources (KMS keys will be scheduled for deletion)"
    echo ""
    
    read -p "Are you absolutely sure you want to continue? Type 'DELETE' to confirm: " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warning "Final confirmation required!"
    read -p "This action cannot be undone. Continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    local timeout="${4:-1800}"  # 30 minutes default
    
    log "Waiting for ${resource_type} '${resource_name}' deletion..."
    
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        if ! eval "$check_command" &> /dev/null; then
            success "${resource_type} '${resource_name}' deleted successfully"
            return 0
        fi
        
        log "${resource_type} still exists. Waiting ${interval} seconds..."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    warning "${resource_type} '${resource_name}' deletion timed out after ${timeout} seconds"
    return 1
}

# Delete AlloyDB resources
delete_alloydb_resources() {
    if [ -z "${ALLOYDB_CLUSTER_ID}" ]; then
        warning "No AlloyDB cluster specified, skipping AlloyDB cleanup"
        return 0
    fi
    
    log "Deleting AlloyDB resources..."
    
    # Get all instances in the cluster
    local instances=$(gcloud alloydb instances list --cluster="${ALLOYDB_CLUSTER_ID}" --region="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    # Delete instances first
    if [ -n "$instances" ]; then
        for instance_path in $instances; do
            local instance_name=$(echo "$instance_path" | sed 's|.*/||')
            log "Deleting AlloyDB instance: ${instance_name}"
            
            if gcloud alloydb instances describe "${instance_name}" --cluster="${ALLOYDB_CLUSTER_ID}" --region="${REGION}" &> /dev/null; then
                gcloud alloydb instances delete "${instance_name}" \
                    --cluster="${ALLOYDB_CLUSTER_ID}" \
                    --region="${REGION}" \
                    --quiet || warning "Failed to delete instance ${instance_name}"
                
                # Wait for instance deletion
                wait_for_deletion "Instance" "${instance_name}" \
                    "gcloud alloydb instances describe '${instance_name}' --cluster='${ALLOYDB_CLUSTER_ID}' --region='${REGION}'" \
                    900  # 15 minutes
            else
                warning "Instance ${instance_name} not found, skipping"
            fi
        done
    fi
    
    # Delete the cluster
    log "Deleting AlloyDB cluster: ${ALLOYDB_CLUSTER_ID}"
    if gcloud alloydb clusters describe "${ALLOYDB_CLUSTER_ID}" --region="${REGION}" &> /dev/null; then
        gcloud alloydb clusters delete "${ALLOYDB_CLUSTER_ID}" \
            --region="${REGION}" \
            --quiet || warning "Failed to delete AlloyDB cluster"
        
        # Wait for cluster deletion
        wait_for_deletion "Cluster" "${ALLOYDB_CLUSTER_ID}" \
            "gcloud alloydb clusters describe '${ALLOYDB_CLUSTER_ID}' --region='${REGION}'" \
            1800  # 30 minutes
    else
        warning "AlloyDB cluster ${ALLOYDB_CLUSTER_ID} not found, skipping"
    fi
    
    success "AlloyDB resources cleanup completed"
}

# Delete NetApp Volumes resources
delete_netapp_resources() {
    if [ -z "${NETAPP_VOLUME}" ] && [ -z "${NETAPP_STORAGE_POOL}" ]; then
        warning "No NetApp resources specified, skipping NetApp cleanup"
        return 0
    fi
    
    log "Deleting NetApp Volumes resources..."
    
    # Delete volume first
    if [ -n "${NETAPP_VOLUME}" ]; then
        log "Deleting NetApp volume: ${NETAPP_VOLUME}"
        if gcloud netapp volumes describe "${NETAPP_VOLUME}" --location="${REGION}" &> /dev/null; then
            gcloud netapp volumes delete "${NETAPP_VOLUME}" \
                --location="${REGION}" \
                --quiet || warning "Failed to delete NetApp volume"
            
            # Wait for volume deletion
            wait_for_deletion "Volume" "${NETAPP_VOLUME}" \
                "gcloud netapp volumes describe '${NETAPP_VOLUME}' --location='${REGION}'" \
                1800  # 30 minutes
        else
            warning "NetApp volume ${NETAPP_VOLUME} not found, skipping"
        fi
    fi
    
    # Delete storage pool
    if [ -n "${NETAPP_STORAGE_POOL}" ]; then
        log "Deleting NetApp storage pool: ${NETAPP_STORAGE_POOL}"
        if gcloud netapp storage-pools describe "${NETAPP_STORAGE_POOL}" --location="${REGION}" &> /dev/null; then
            gcloud netapp storage-pools delete "${NETAPP_STORAGE_POOL}" \
                --location="${REGION}" \
                --quiet || warning "Failed to delete NetApp storage pool"
            
            # Wait for storage pool deletion
            wait_for_deletion "Storage Pool" "${NETAPP_STORAGE_POOL}" \
                "gcloud netapp storage-pools describe '${NETAPP_STORAGE_POOL}' --location='${REGION}'" \
                1800  # 30 minutes
        else
            warning "NetApp storage pool ${NETAPP_STORAGE_POOL} not found, skipping"
        fi
    fi
    
    success "NetApp Volumes resources cleanup completed"
}

# Delete load balancer components
delete_load_balancer_resources() {
    log "Deleting load balancer resources..."
    
    # Delete forwarding rule
    if gcloud compute forwarding-rules describe alloydb-forwarding-rule --region="${REGION}" &> /dev/null; then
        log "Deleting forwarding rule: alloydb-forwarding-rule"
        gcloud compute forwarding-rules delete alloydb-forwarding-rule \
            --region="${REGION}" \
            --quiet || warning "Failed to delete forwarding rule"
    else
        warning "Forwarding rule alloydb-forwarding-rule not found, skipping"
    fi
    
    # Delete backend service
    if gcloud compute backend-services describe alloydb-backend --region="${REGION}" &> /dev/null; then
        log "Deleting backend service: alloydb-backend"
        gcloud compute backend-services delete alloydb-backend \
            --region="${REGION}" \
            --quiet || warning "Failed to delete backend service"
    else
        warning "Backend service alloydb-backend not found, skipping"
    fi
    
    # Delete health check
    if gcloud compute health-checks describe alloydb-health-check &> /dev/null; then
        log "Deleting health check: alloydb-health-check"
        gcloud compute health-checks delete alloydb-health-check \
            --quiet || warning "Failed to delete health check"
    else
        warning "Health check alloydb-health-check not found, skipping"
    fi
    
    success "Load balancer resources cleanup completed"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete monitoring dashboards
    local dashboards=$(gcloud monitoring dashboards list --filter="displayName:'Enterprise Database Performance Dashboard'" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$dashboards" ]; then
        for dashboard in $dashboards; do
            log "Deleting monitoring dashboard: ${dashboard}"
            gcloud monitoring dashboards delete "${dashboard}" --quiet || warning "Failed to delete dashboard"
        done
    else
        warning "No Enterprise Database Performance dashboards found"
    fi
    
    # Delete alert policies
    local policies=$(gcloud alpha monitoring policies list --filter="displayName:'AlloyDB High CPU Alert'" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$policies" ]; then
        for policy in $policies; do
            log "Deleting alert policy: ${policy}"
            gcloud alpha monitoring policies delete "${policy}" --quiet || warning "Failed to delete alert policy"
        done
    else
        warning "No AlloyDB High CPU Alert policies found"
    fi
    
    success "Monitoring resources cleanup completed"
}

# Delete networking resources
delete_networking_resources() {
    log "Deleting networking resources..."
    
    # Delete VPC peering
    if gcloud services vpc-peerings list --network="${VPC_NAME}" --format="value(network)" 2>/dev/null | grep -q "${VPC_NAME}"; then
        log "Deleting VPC peering for servicenetworking"
        gcloud services vpc-peerings delete \
            --service=servicenetworking.googleapis.com \
            --network="${VPC_NAME}" \
            --quiet || warning "Failed to delete VPC peering"
    else
        warning "VPC peering for ${VPC_NAME} not found, skipping"
    fi
    
    # Delete private IP range
    if gcloud compute addresses describe alloydb-private-range --global &> /dev/null; then
        log "Deleting private IP range: alloydb-private-range"
        gcloud compute addresses delete alloydb-private-range \
            --global \
            --quiet || warning "Failed to delete private IP range"
    else
        warning "Private IP range alloydb-private-range not found, skipping"
    fi
    
    # Delete subnet
    if gcloud compute networks subnets describe "${SUBNET_NAME}" --region="${REGION}" &> /dev/null; then
        log "Deleting subnet: ${SUBNET_NAME}"
        gcloud compute networks subnets delete "${SUBNET_NAME}" \
            --region="${REGION}" \
            --quiet || warning "Failed to delete subnet"
    else
        warning "Subnet ${SUBNET_NAME} not found, skipping"
    fi
    
    # Delete VPC network
    if gcloud compute networks describe "${VPC_NAME}" &> /dev/null; then
        log "Deleting VPC network: ${VPC_NAME}"
        gcloud compute networks delete "${VPC_NAME}" \
            --quiet || warning "Failed to delete VPC network"
    else
        warning "VPC network ${VPC_NAME} not found, skipping"
    fi
    
    success "Networking resources cleanup completed"
}

# Delete security resources
delete_security_resources() {
    log "Deleting security resources..."
    
    # Schedule KMS key for deletion (keys cannot be immediately deleted)
    if gcloud kms keys describe alloydb-key --location="${REGION}" --keyring=alloydb-keyring &> /dev/null; then
        log "Scheduling KMS key for deletion: alloydb-key"
        gcloud kms keys versions destroy 1 \
            --key=alloydb-key \
            --location="${REGION}" \
            --keyring=alloydb-keyring \
            --quiet || warning "Failed to destroy KMS key version"
    else
        warning "KMS key alloydb-key not found, skipping"
    fi
    
    # Note: KMS keyrings cannot be deleted, they remain but are not charged
    warning "KMS keyring 'alloydb-keyring' cannot be deleted but will remain inactive"
    
    success "Security resources cleanup completed"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove common temporary files
    rm -f /tmp/deployment-info.txt
    rm -f /tmp/dashboard-config.json
    rm -f /tmp/alert-policy.yaml
    
    success "Temporary files cleaned up"
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "=================="
    echo ""
    echo "The following resources have been deleted or scheduled for deletion:"
    echo ""
    [ -n "${ALLOYDB_CLUSTER_ID}" ] && echo "✅ AlloyDB Cluster: ${ALLOYDB_CLUSTER_ID}"
    [ -n "${NETAPP_STORAGE_POOL}" ] && echo "✅ NetApp Storage Pool: ${NETAPP_STORAGE_POOL}"
    [ -n "${NETAPP_VOLUME}" ] && echo "✅ NetApp Volume: ${NETAPP_VOLUME}"
    echo "✅ Load balancer components"
    echo "✅ Monitoring dashboards and alerts"
    echo "✅ VPC network and subnets"
    echo "⏳ KMS key scheduled for deletion (30-day waiting period)"
    echo ""
    echo "Cleanup completed at: $(date)"
    echo ""
    warning "Note: Some resources may take additional time to be fully deleted."
    warning "Check the Google Cloud Console to verify all resources are removed."
}

# Main cleanup function
main() {
    echo "=================================================="
    echo "Enterprise Database Performance Cleanup Script"
    echo "=================================================="
    echo ""
    
    display_config
    check_prerequisites
    detect_resources
    confirmation_prompt
    
    echo ""
    log "Starting cleanup process..."
    echo ""
    
    # Execute cleanup steps in reverse dependency order
    delete_monitoring_resources
    delete_load_balancer_resources
    delete_alloydb_resources
    delete_netapp_resources
    delete_networking_resources
    delete_security_resources
    cleanup_temp_files
    
    echo ""
    success "🎉 Enterprise database performance architecture cleanup completed!"
    echo ""
    
    display_summary
}

# Handle script interruption
trap 'echo ""; warning "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"