#!/bin/bash

# Aurora Global Database Cleanup Script
# This script safely removes all resources created by the deployment script
# across three regions: us-east-1, eu-west-1, and ap-southeast-1

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_cli() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "AWS CLI is properly configured"
}

# Function to load configuration from deployment
load_deployment_config() {
    if [ ! -f "./.deployment-config" ]; then
        error "Deployment configuration file not found!"
        error "Please ensure you're running this script from the same directory as the deployment script."
        error "If you've lost the configuration file, you'll need to manually clean up resources."
        exit 1
    fi
    
    # Source the configuration file
    source ./.deployment-config
    
    log "Loaded deployment configuration:"
    info "Global DB ID: ${GLOBAL_DB_IDENTIFIER}"
    info "Primary Cluster: ${PRIMARY_CLUSTER_ID}"
    info "Secondary Clusters: ${SECONDARY_CLUSTER_1_ID}, ${SECONDARY_CLUSTER_2_ID}"
    info "Regions: ${PRIMARY_REGION}, ${SECONDARY_REGION_1}, ${SECONDARY_REGION_2}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This will permanently delete the following resources:"
    warn "- Global Database: ${GLOBAL_DB_IDENTIFIER}"
    warn "- Primary Cluster: ${PRIMARY_CLUSTER_ID} (${PRIMARY_REGION})"
    warn "- Secondary Cluster 1: ${SECONDARY_CLUSTER_1_ID} (${SECONDARY_REGION_1})"
    warn "- Secondary Cluster 2: ${SECONDARY_CLUSTER_2_ID} (${SECONDARY_REGION_2})"
    warn "- All database instances and data"
    warn "- CloudWatch dashboard"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource deletion..."
}

# Function to delete database instances
delete_database_instances() {
    local cluster_id=$1
    local region=$2
    local cluster_type=$3
    
    log "Deleting database instances for ${cluster_type} cluster..."
    
    # Delete writer instance
    if aws rds describe-db-instances \
        --db-instance-identifier "${cluster_id}-writer" \
        --region "${region}" >/dev/null 2>&1; then
        
        log "Deleting writer instance: ${cluster_id}-writer"
        aws rds delete-db-instance \
            --db-instance-identifier "${cluster_id}-writer" \
            --skip-final-snapshot \
            --region "${region}" >/dev/null 2>&1
    else
        warn "Writer instance ${cluster_id}-writer not found or already deleted"
    fi
    
    # Delete reader instance
    if aws rds describe-db-instances \
        --db-instance-identifier "${cluster_id}-reader" \
        --region "${region}" >/dev/null 2>&1; then
        
        log "Deleting reader instance: ${cluster_id}-reader"
        aws rds delete-db-instance \
            --db-instance-identifier "${cluster_id}-reader" \
            --skip-final-snapshot \
            --region "${region}" >/dev/null 2>&1
    else
        warn "Reader instance ${cluster_id}-reader not found or already deleted"
    fi
    
    log "✅ Instance deletion initiated for ${cluster_type} cluster"
}

# Function to wait for instances to be deleted
wait_for_instances_deletion() {
    local cluster_id=$1
    local region=$2
    local cluster_type=$3
    
    log "Waiting for ${cluster_type} instances to be deleted..."
    
    local max_wait=600  # 10 minutes
    local wait_time=0
    local check_interval=30
    
    while [ $wait_time -lt $max_wait ]; do
        local writer_exists=false
        local reader_exists=false
        
        # Check if writer instance still exists
        if aws rds describe-db-instances \
            --db-instance-identifier "${cluster_id}-writer" \
            --region "${region}" >/dev/null 2>&1; then
            writer_exists=true
        fi
        
        # Check if reader instance still exists
        if aws rds describe-db-instances \
            --db-instance-identifier "${cluster_id}-reader" \
            --region "${region}" >/dev/null 2>&1; then
            reader_exists=true
        fi
        
        if [ "$writer_exists" = false ] && [ "$reader_exists" = false ]; then
            log "✅ All instances deleted for ${cluster_type} cluster"
            return 0
        fi
        
        info "Waiting for instances to be deleted... (${wait_time}s/${max_wait}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warn "Timeout waiting for instances to be deleted for ${cluster_type} cluster"
    warn "Proceeding with cluster deletion anyway..."
}

# Function to delete cluster
delete_cluster() {
    local cluster_id=$1
    local region=$2
    local cluster_type=$3
    
    log "Deleting ${cluster_type} cluster: ${cluster_id}"
    
    if aws rds describe-db-clusters \
        --db-cluster-identifier "${cluster_id}" \
        --region "${region}" >/dev/null 2>&1; then
        
        aws rds delete-db-cluster \
            --db-cluster-identifier "${cluster_id}" \
            --skip-final-snapshot \
            --region "${region}" >/dev/null 2>&1
        
        log "✅ ${cluster_type} cluster deletion initiated"
    else
        warn "${cluster_type} cluster ${cluster_id} not found or already deleted"
    fi
}

# Function to wait for cluster deletion
wait_for_cluster_deletion() {
    local cluster_id=$1
    local region=$2
    local cluster_type=$3
    
    log "Waiting for ${cluster_type} cluster to be deleted..."
    
    local max_wait=600  # 10 minutes
    local wait_time=0
    local check_interval=30
    
    while [ $wait_time -lt $max_wait ]; do
        if ! aws rds describe-db-clusters \
            --db-cluster-identifier "${cluster_id}" \
            --region "${region}" >/dev/null 2>&1; then
            log "✅ ${cluster_type} cluster deleted successfully"
            return 0
        fi
        
        info "Waiting for ${cluster_type} cluster to be deleted... (${wait_time}s/${max_wait}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warn "Timeout waiting for ${cluster_type} cluster to be deleted"
    return 1
}

# Function to delete global database
delete_global_database() {
    log "Deleting global database: ${GLOBAL_DB_IDENTIFIER}"
    
    if aws rds describe-global-clusters \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        
        aws rds delete-global-cluster \
            --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
            --region "${PRIMARY_REGION}" >/dev/null 2>&1
        
        log "✅ Global database deletion initiated"
    else
        warn "Global database ${GLOBAL_DB_IDENTIFIER} not found or already deleted"
    fi
}

# Function to wait for global database deletion
wait_for_global_database_deletion() {
    log "Waiting for global database to be deleted..."
    
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=30
    
    while [ $wait_time -lt $max_wait ]; do
        if ! aws rds describe-global-clusters \
            --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
            --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
            log "✅ Global database deleted successfully"
            return 0
        fi
        
        info "Waiting for global database to be deleted... (${wait_time}s/${max_wait}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warn "Timeout waiting for global database to be deleted"
    return 1
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    if [ -n "${DASHBOARD_NAME}" ]; then
        if aws cloudwatch delete-dashboards \
            --dashboard-names "${DASHBOARD_NAME}" \
            --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
            log "✅ CloudWatch dashboard '${DASHBOARD_NAME}' deleted"
        else
            warn "Failed to delete CloudWatch dashboard or dashboard not found"
        fi
    else
        warn "Dashboard name not found in configuration, skipping dashboard deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment configuration file
    if [ -f "./.deployment-config" ]; then
        rm -f ./.deployment-config
        log "✅ Deployment configuration file removed"
    fi
    
    # Remove any temporary files
    rm -f ./global-db-dashboard.json
    
    # Unset environment variables
    unset GLOBAL_DB_IDENTIFIER
    unset PRIMARY_CLUSTER_ID
    unset SECONDARY_CLUSTER_1_ID
    unset SECONDARY_CLUSTER_2_ID
    unset PRIMARY_REGION
    unset SECONDARY_REGION_1
    unset SECONDARY_REGION_2
    unset MASTER_USERNAME
    unset MASTER_PASSWORD
    unset DASHBOARD_NAME
    
    log "✅ Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_complete=true
    
    # Check if global database exists
    if aws rds describe-global-clusters \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        warn "Global database still exists: ${GLOBAL_DB_IDENTIFIER}"
        cleanup_complete=false
    fi
    
    # Check if primary cluster exists
    if aws rds describe-db-clusters \
        --db-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        warn "Primary cluster still exists: ${PRIMARY_CLUSTER_ID}"
        cleanup_complete=false
    fi
    
    # Check if secondary clusters exist
    if aws rds describe-db-clusters \
        --db-cluster-identifier "${SECONDARY_CLUSTER_1_ID}" \
        --region "${SECONDARY_REGION_1}" >/dev/null 2>&1; then
        warn "Secondary cluster 1 still exists: ${SECONDARY_CLUSTER_1_ID}"
        cleanup_complete=false
    fi
    
    if aws rds describe-db-clusters \
        --db-cluster-identifier "${SECONDARY_CLUSTER_2_ID}" \
        --region "${SECONDARY_REGION_2}" >/dev/null 2>&1; then
        warn "Secondary cluster 2 still exists: ${SECONDARY_CLUSTER_2_ID}"
        cleanup_complete=false
    fi
    
    if [ "$cleanup_complete" = true ]; then
        log "✅ All resources have been successfully cleaned up"
        return 0
    else
        error "Some resources may still exist. Please check the AWS console."
        return 1
    fi
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    warn "Attempting to clean up any remaining resources..."
    
    # Try to delete any remaining instances
    for cluster_id in "${PRIMARY_CLUSTER_ID}" "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_CLUSTER_2_ID}"; do
        for region in "${PRIMARY_REGION}" "${SECONDARY_REGION_1}" "${SECONDARY_REGION_2}"; do
            # Skip combinations that don't match
            if [[ ${cluster_id} == *"primary"* && ${region} != ${PRIMARY_REGION} ]]; then
                continue
            elif [[ ${cluster_id} == *"eu"* && ${region} != ${SECONDARY_REGION_1} ]]; then
                continue
            elif [[ ${cluster_id} == *"asia"* && ${region} != ${SECONDARY_REGION_2} ]]; then
                continue
            fi
            
            # Delete instances if they exist
            for instance_type in "writer" "reader"; do
                local instance_id="${cluster_id}-${instance_type}"
                if aws rds describe-db-instances \
                    --db-instance-identifier "${instance_id}" \
                    --region "${region}" >/dev/null 2>&1; then
                    
                    log "Force deleting instance: ${instance_id}"
                    aws rds delete-db-instance \
                        --db-instance-identifier "${instance_id}" \
                        --skip-final-snapshot \
                        --region "${region}" >/dev/null 2>&1 || true
                fi
            done
        done
    done
    
    # Wait a bit and try to delete clusters
    log "Waiting for instances to be deleted before cleaning up clusters..."
    sleep 180
    
    # Delete clusters
    for cluster_id in "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_CLUSTER_2_ID}" "${PRIMARY_CLUSTER_ID}"; do
        for region in "${SECONDARY_REGION_1}" "${SECONDARY_REGION_2}" "${PRIMARY_REGION}"; do
            # Skip combinations that don't match
            if [[ ${cluster_id} == *"primary"* && ${region} != ${PRIMARY_REGION} ]]; then
                continue
            elif [[ ${cluster_id} == *"eu"* && ${region} != ${SECONDARY_REGION_1} ]]; then
                continue
            elif [[ ${cluster_id} == *"asia"* && ${region} != ${SECONDARY_REGION_2} ]]; then
                continue
            fi
            
            if aws rds describe-db-clusters \
                --db-cluster-identifier "${cluster_id}" \
                --region "${region}" >/dev/null 2>&1; then
                
                log "Force deleting cluster: ${cluster_id}"
                aws rds delete-db-cluster \
                    --db-cluster-identifier "${cluster_id}" \
                    --skip-final-snapshot \
                    --region "${region}" >/dev/null 2>&1 || true
            fi
        done
    done
    
    # Wait and try to delete global database
    sleep 300
    if aws rds describe-global-clusters \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        
        log "Force deleting global database: ${GLOBAL_DB_IDENTIFIER}"
        aws rds delete-global-cluster \
            --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
            --region "${PRIMARY_REGION}" >/dev/null 2>&1 || true
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "==================="
    info "✅ Database instances deleted from all regions"
    info "✅ Aurora clusters deleted from all regions"
    info "✅ Global database deleted"
    info "✅ CloudWatch dashboard deleted"
    info "✅ Local configuration files cleaned up"
    echo ""
    log "All Aurora Global Database resources have been successfully removed."
    log "Please verify in the AWS console that no unexpected charges will occur."
}

# Main cleanup function
main() {
    log "Starting Aurora Global Database cleanup..."
    
    # Check prerequisites
    check_aws_cli
    
    # Load configuration and confirm deletion
    load_deployment_config
    confirm_deletion
    
    # Delete database instances first (in parallel for efficiency)
    log "Phase 1: Deleting database instances..."
    delete_database_instances "${SECONDARY_CLUSTER_2_ID}" "${SECONDARY_REGION_2}" "Asian secondary"
    delete_database_instances "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_REGION_1}" "European secondary"
    delete_database_instances "${PRIMARY_CLUSTER_ID}" "${PRIMARY_REGION}" "primary"
    
    # Wait for instances to be deleted
    wait_for_instances_deletion "${SECONDARY_CLUSTER_2_ID}" "${SECONDARY_REGION_2}" "Asian secondary"
    wait_for_instances_deletion "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_REGION_1}" "European secondary"
    wait_for_instances_deletion "${PRIMARY_CLUSTER_ID}" "${PRIMARY_REGION}" "primary"
    
    # Delete clusters in reverse order (secondary first, then primary)
    log "Phase 2: Deleting Aurora clusters..."
    delete_cluster "${SECONDARY_CLUSTER_2_ID}" "${SECONDARY_REGION_2}" "Asian secondary"
    delete_cluster "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_REGION_1}" "European secondary"
    delete_cluster "${PRIMARY_CLUSTER_ID}" "${PRIMARY_REGION}" "primary"
    
    # Wait for clusters to be deleted
    wait_for_cluster_deletion "${SECONDARY_CLUSTER_2_ID}" "${SECONDARY_REGION_2}" "Asian secondary"
    wait_for_cluster_deletion "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_REGION_1}" "European secondary"
    wait_for_cluster_deletion "${PRIMARY_CLUSTER_ID}" "${PRIMARY_REGION}" "primary"
    
    # Delete global database
    log "Phase 3: Deleting global database..."
    delete_global_database
    wait_for_global_database_deletion
    
    # Delete CloudWatch dashboard
    log "Phase 4: Cleaning up monitoring resources..."
    delete_cloudwatch_dashboard
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    if ! verify_cleanup; then
        error "Cleanup verification failed. Attempting forced cleanup..."
        handle_partial_cleanup
        
        # Try verification again
        if ! verify_cleanup; then
            error "Some resources may still exist. Please check the AWS console manually."
            exit 1
        fi
    fi
    
    display_cleanup_summary
    log "✅ Aurora Global Database cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist. Please run the script again or check the AWS console."; exit 1' INT TERM

# Run main cleanup
main "$@"