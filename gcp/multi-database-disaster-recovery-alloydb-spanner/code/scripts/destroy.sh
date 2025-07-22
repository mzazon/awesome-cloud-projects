#!/bin/bash

# Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner - Cleanup Script
# This script safely removes all resources created by the disaster recovery deployment
# with proper confirmation prompts and dependency handling

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
handle_error() {
    log_error "An error occurred during cleanup. Some resources may need manual removal."
    log_info "Check the Google Cloud Console for any remaining resources."
    exit 1
}

trap handle_error ERR

# Load deployment configuration
load_config() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "deployment_config.env" ]]; then
        # Load configuration from deployment
        source deployment_config.env
        log_success "Configuration loaded from deployment_config.env"
    else
        log_warning "deployment_config.env not found. Using environment variables or defaults."
        
        # Use environment variables or prompt for required values
        export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
        export PRIMARY_REGION="${PRIMARY_REGION:-us-central1}"
        export SECONDARY_REGION="${SECONDARY_REGION:-us-east1}"
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project configured. Please run 'gcloud config set project PROJECT_ID' or provide PROJECT_ID environment variable."
            exit 1
        fi
        
        # Try to detect resource names by listing existing resources
        log_info "Attempting to detect existing resources..."
        detect_resources
    fi
    
    log_info "Using configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Primary Region: ${PRIMARY_REGION}"
    log_info "  Secondary Region: ${SECONDARY_REGION}"
}

# Detect existing resources when config file is not available
detect_resources() {
    log_info "Detecting existing disaster recovery resources..."
    
    # Detect AlloyDB clusters
    local alloydb_clusters=$(gcloud alloydb clusters list \
        --format="value(name)" \
        --filter="labels.purpose=disaster-recovery" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    if [[ -n "$alloydb_clusters" ]]; then
        # Extract cluster names
        while IFS= read -r cluster_path; do
            if [[ -n "$cluster_path" ]]; then
                local cluster_name=$(basename "$cluster_path")
                if [[ "$cluster_name" =~ ^alloydb-dr-.*$ ]]; then
                    if [[ "$cluster_path" =~ /${PRIMARY_REGION}/ ]]; then
                        export CLUSTER_ID="$cluster_name"
                    fi
                fi
            fi
        done <<< "$alloydb_clusters"
    fi
    
    # Detect Spanner instances
    local spanner_instances=$(gcloud spanner instances list \
        --format="value(name)" \
        --filter="labels.purpose=disaster-recovery" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    if [[ -n "$spanner_instances" ]]; then
        while IFS= read -r instance_path; do
            if [[ -n "$instance_path" ]]; then
                local instance_name=$(basename "$instance_path")
                if [[ "$instance_name" =~ ^spanner-dr-.*$ ]]; then
                    export SPANNER_INSTANCE_ID="$instance_name"
                fi
            fi
        done <<< "$spanner_instances"
    fi
    
    # Detect storage buckets
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(backup-primary-|backup-secondary-)" || echo "")
    if [[ -n "$buckets" ]]; then
        while IFS= read -r bucket_url; do
            if [[ -n "$bucket_url" ]]; then
                local bucket_name=$(basename "$bucket_url" | sed 's/\/$//')
                if [[ "$bucket_name" =~ ^backup-primary-.*$ ]]; then
                    export BACKUP_BUCKET_PRIMARY="$bucket_name"
                elif [[ "$bucket_name" =~ ^backup-secondary-.*$ ]]; then
                    export BACKUP_BUCKET_SECONDARY="$bucket_name"
                fi
            fi
        done <<< "$buckets"
    fi
    
    # Set network name
    export NETWORK_NAME="${NETWORK_NAME:-alloydb-dr-network}"
    
    log_info "Detected resources:"
    log_info "  AlloyDB Cluster: ${CLUSTER_ID:-not found}"
    log_info "  Spanner Instance: ${SPANNER_INSTANCE_ID:-not found}"
    log_info "  Primary Bucket: ${BACKUP_BUCKET_PRIMARY:-not found}"
    log_info "  Secondary Bucket: ${BACKUP_BUCKET_SECONDARY:-not found}"
    log_info "  Network: ${NETWORK_NAME}"
}

# Confirmation prompt
confirm_deletion() {
    echo
    echo -e "${RED}⚠️  WARNING: This will permanently delete all disaster recovery resources!${NC}"
    echo
    echo "Resources to be deleted:"
    echo "• Project: ${PROJECT_ID}"
    echo "• AlloyDB Primary Cluster: ${CLUSTER_ID:-not configured}"
    echo "• AlloyDB Secondary Cluster: ${CLUSTER_ID:-not configured}-secondary"
    echo "• Cloud Spanner Instance: ${SPANNER_INSTANCE_ID:-not configured}"
    echo "• Primary Backup Bucket: ${BACKUP_BUCKET_PRIMARY:-not configured}"
    echo "• Secondary Backup Bucket: ${BACKUP_BUCKET_SECONDARY:-not configured}"
    echo "• Network Infrastructure: ${NETWORK_NAME}"
    echo "• Cloud Functions and Scheduler Jobs"
    echo "• Monitoring Dashboards and Alerting"
    echo
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warning "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Please type 'DELETE' in capital letters to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation text did not match"
        exit 0
    fi
    
    log_info "Confirmation received. Starting cleanup..."
}

# Remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."
    
    local jobs=(
        "disaster-recovery-backup-job"
        "disaster-recovery-validation-job"
        "disaster-recovery-failover-job"
    )
    
    for job in "${jobs[@]}"; do
        if gcloud scheduler jobs describe "$job" \
            --location="${PRIMARY_REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            log_info "Deleting scheduler job: $job"
            gcloud scheduler jobs delete "$job" \
                --location="${PRIMARY_REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
        else
            log_warning "Scheduler job not found: $job"
        fi
    done
    
    log_success "Cloud Scheduler jobs removed"
}

# Remove Cloud Functions
remove_cloud_functions() {
    log_info "Removing Cloud Functions..."
    
    local functions=(
        "disaster-recovery-orchestrator"
        "data-synchronization"
    )
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" \
            --region="${PRIMARY_REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            log_info "Deleting Cloud Function: $func"
            gcloud functions delete "$func" \
                --region="${PRIMARY_REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
        else
            log_warning "Cloud Function not found: $func"
        fi
    done
    
    log_success "Cloud Functions removed"
}

# Remove Pub/Sub resources
remove_pubsub() {
    log_info "Removing Pub/Sub resources..."
    
    # Remove subscription first
    if gcloud pubsub subscriptions describe "database-sync-monitoring" --project="${PROJECT_ID}" &>/dev/null; then
        log_info "Deleting Pub/Sub subscription: database-sync-monitoring"
        gcloud pubsub subscriptions delete "database-sync-monitoring" \
            --project="${PROJECT_ID}" \
            --quiet
    fi
    
    # Remove topic
    if gcloud pubsub topics describe "database-sync-events" --project="${PROJECT_ID}" &>/dev/null; then
        log_info "Deleting Pub/Sub topic: database-sync-events"
        gcloud pubsub topics delete "database-sync-events" \
            --project="${PROJECT_ID}" \
            --quiet
    fi
    
    log_success "Pub/Sub resources removed"
}

# Remove monitoring dashboards
remove_monitoring() {
    log_info "Removing monitoring dashboards and alerting policies..."
    
    # Remove dashboards with disaster recovery in the name
    local dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:Multi-Database Disaster Recovery Dashboard" \
        --format="value(name)" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "$dashboard" ]]; then
                log_info "Deleting monitoring dashboard: $(basename "$dashboard")"
                gcloud monitoring dashboards delete "$dashboard" \
                    --project="${PROJECT_ID}" \
                    --quiet
            fi
        done <<< "$dashboards"
    fi
    
    # Remove alerting policies
    local policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:AlloyDB Cluster Availability Alert" \
        --format="value(name)" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    if [[ -n "$policies" ]]; then
        while IFS= read -r policy; do
            if [[ -n "$policy" ]]; then
                log_info "Deleting alerting policy: $(basename "$policy")"
                gcloud alpha monitoring policies delete "$policy" \
                    --project="${PROJECT_ID}" \
                    --quiet
            fi
        done <<< "$policies"
    fi
    
    log_success "Monitoring resources removed"
}

# Remove AlloyDB clusters
remove_alloydb_clusters() {
    log_info "Removing AlloyDB clusters..."
    
    # Remove secondary cluster first
    if [[ -n "${CLUSTER_ID:-}" ]]; then
        local secondary_cluster="${CLUSTER_ID}-secondary"
        
        if gcloud alloydb clusters describe "$secondary_cluster" \
            --region="${SECONDARY_REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            log_info "Deleting AlloyDB secondary cluster: $secondary_cluster"
            
            # First delete instances in the secondary cluster
            local secondary_instances=$(gcloud alloydb instances list \
                --cluster="$secondary_cluster" \
                --region="${SECONDARY_REGION}" \
                --format="value(name)" \
                --project="${PROJECT_ID}" 2>/dev/null || echo "")
            
            if [[ -n "$secondary_instances" ]]; then
                while IFS= read -r instance; do
                    if [[ -n "$instance" ]]; then
                        local instance_name=$(basename "$instance")
                        log_info "Deleting secondary instance: $instance_name"
                        gcloud alloydb instances delete "$instance_name" \
                            --cluster="$secondary_cluster" \
                            --region="${SECONDARY_REGION}" \
                            --project="${PROJECT_ID}" \
                            --quiet
                    fi
                done <<< "$secondary_instances"
            fi
            
            # Wait for instances to be deleted
            log_info "Waiting for secondary instances to be deleted..."
            sleep 30
            
            # Delete the secondary cluster
            gcloud alloydb clusters delete "$secondary_cluster" \
                --region="${SECONDARY_REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
            
            log_success "AlloyDB secondary cluster deleted"
        else
            log_warning "AlloyDB secondary cluster not found: $secondary_cluster"
        fi
        
        # Remove primary cluster
        if gcloud alloydb clusters describe "${CLUSTER_ID}" \
            --region="${PRIMARY_REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            log_info "Deleting AlloyDB primary cluster: ${CLUSTER_ID}"
            
            # First delete instances in the primary cluster
            local primary_instances=$(gcloud alloydb instances list \
                --cluster="${CLUSTER_ID}" \
                --region="${PRIMARY_REGION}" \
                --format="value(name)" \
                --project="${PROJECT_ID}" 2>/dev/null || echo "")
            
            if [[ -n "$primary_instances" ]]; then
                while IFS= read -r instance; do
                    if [[ -n "$instance" ]]; then
                        local instance_name=$(basename "$instance")
                        log_info "Deleting primary instance: $instance_name"
                        gcloud alloydb instances delete "$instance_name" \
                            --cluster="${CLUSTER_ID}" \
                            --region="${PRIMARY_REGION}" \
                            --project="${PROJECT_ID}" \
                            --quiet
                    fi
                done <<< "$primary_instances"
            fi
            
            # Wait for instances to be deleted
            log_info "Waiting for primary instances to be deleted..."
            sleep 30
            
            # Delete the primary cluster
            gcloud alloydb clusters delete "${CLUSTER_ID}" \
                --region="${PRIMARY_REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
            
            log_success "AlloyDB primary cluster deleted"
        else
            log_warning "AlloyDB primary cluster not found: ${CLUSTER_ID}"
        fi
    else
        log_warning "No AlloyDB cluster ID configured"
    fi
}

# Remove Cloud Spanner instance
remove_cloud_spanner() {
    log_info "Removing Cloud Spanner instance..."
    
    if [[ -n "${SPANNER_INSTANCE_ID:-}" ]]; then
        if gcloud spanner instances describe "${SPANNER_INSTANCE_ID}" --project="${PROJECT_ID}" &>/dev/null; then
            log_info "Deleting Cloud Spanner instance: ${SPANNER_INSTANCE_ID}"
            
            # First delete databases
            local databases=$(gcloud spanner databases list \
                --instance="${SPANNER_INSTANCE_ID}" \
                --format="value(name)" \
                --project="${PROJECT_ID}" 2>/dev/null || echo "")
            
            if [[ -n "$databases" ]]; then
                while IFS= read -r database; do
                    if [[ -n "$database" ]]; then
                        local db_name=$(basename "$database")
                        log_info "Deleting Spanner database: $db_name"
                        gcloud spanner databases delete "$db_name" \
                            --instance="${SPANNER_INSTANCE_ID}" \
                            --project="${PROJECT_ID}" \
                            --quiet
                    fi
                done <<< "$databases"
            fi
            
            # Delete the instance
            gcloud spanner instances delete "${SPANNER_INSTANCE_ID}" \
                --project="${PROJECT_ID}" \
                --quiet
            
            log_success "Cloud Spanner instance deleted"
        else
            log_warning "Cloud Spanner instance not found: ${SPANNER_INSTANCE_ID}"
        fi
    else
        log_warning "No Spanner instance ID configured"
    fi
}

# Remove Cloud Storage buckets
remove_storage_buckets() {
    log_info "Removing Cloud Storage buckets..."
    
    local buckets=(
        "${BACKUP_BUCKET_PRIMARY:-}"
        "${BACKUP_BUCKET_SECONDARY:-}"
    )
    
    for bucket in "${buckets[@]}"; do
        if [[ -n "$bucket" ]]; then
            if gsutil ls -b "gs://$bucket" &>/dev/null; then
                log_info "Deleting storage bucket: $bucket"
                
                # Remove all objects first (including versions)
                log_info "Removing all objects from bucket: $bucket"
                gsutil -m rm -r "gs://$bucket/**" 2>/dev/null || log_warning "No objects to delete in $bucket"
                
                # Remove versioned objects
                gsutil -m rm -a "gs://$bucket/**" 2>/dev/null || log_warning "No versioned objects to delete in $bucket"
                
                # Delete the bucket
                gsutil rb "gs://$bucket"
                
                log_success "Storage bucket deleted: $bucket"
            else
                log_warning "Storage bucket not found: $bucket"
            fi
        fi
    done
}

# Remove network infrastructure
remove_network() {
    log_info "Removing network infrastructure..."
    
    # Remove VPC peering connection
    log_info "Removing VPC peering connection..."
    gcloud services vpc-peerings disconnect \
        --service=servicenetworking.googleapis.com \
        --network="${NETWORK_NAME}" \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null || log_warning "VPC peering may not exist or already removed"
    
    # Remove allocated IP range
    if gcloud compute addresses describe "alloydb-ip-range" \
        --global --project="${PROJECT_ID}" &>/dev/null; then
        log_info "Deleting allocated IP range: alloydb-ip-range"
        gcloud compute addresses delete "alloydb-ip-range" \
            --global \
            --project="${PROJECT_ID}" \
            --quiet
    fi
    
    # Remove subnets
    local subnets=(
        "alloydb-primary-subnet:${PRIMARY_REGION}"
        "alloydb-secondary-subnet:${SECONDARY_REGION}"
    )
    
    for subnet_info in "${subnets[@]}"; do
        local subnet_name=$(echo "$subnet_info" | cut -d: -f1)
        local region=$(echo "$subnet_info" | cut -d: -f2)
        
        if gcloud compute networks subnets describe "$subnet_name" \
            --region="$region" --project="${PROJECT_ID}" &>/dev/null; then
            log_info "Deleting subnet: $subnet_name"
            gcloud compute networks subnets delete "$subnet_name" \
                --region="$region" \
                --project="${PROJECT_ID}" \
                --quiet
        else
            log_warning "Subnet not found: $subnet_name"
        fi
    done
    
    # Remove VPC network
    if gcloud compute networks describe "${NETWORK_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
        log_info "Deleting VPC network: ${NETWORK_NAME}"
        gcloud compute networks delete "${NETWORK_NAME}" \
            --project="${PROJECT_ID}" \
            --quiet
        log_success "VPC network deleted"
    else
        log_warning "VPC network not found: ${NETWORK_NAME}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment_config.env"
        "disaster-recovery-dashboard.json"
        "spanner_schema.sql"
        "alloydb-alert-policy.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing local file: $file"
            rm -f "$file"
        fi
    done
    
    # Remove any temporary directories
    if [[ -d "disaster-recovery-functions" ]]; then
        log_info "Removing temporary directory: disaster-recovery-functions"
        rm -rf "disaster-recovery-functions"
    fi
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check AlloyDB clusters
    if [[ -n "${CLUSTER_ID:-}" ]]; then
        if gcloud alloydb clusters describe "${CLUSTER_ID}" \
            --region="${PRIMARY_REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            log_error "AlloyDB primary cluster still exists: ${CLUSTER_ID}"
            ((cleanup_issues++))
        fi
        
        if gcloud alloydb clusters describe "${CLUSTER_ID}-secondary" \
            --region="${SECONDARY_REGION}" --project="${PROJECT_ID}" &>/dev/null; then
            log_error "AlloyDB secondary cluster still exists: ${CLUSTER_ID}-secondary"
            ((cleanup_issues++))
        fi
    fi
    
    # Check Cloud Spanner
    if [[ -n "${SPANNER_INSTANCE_ID:-}" ]]; then
        if gcloud spanner instances describe "${SPANNER_INSTANCE_ID}" --project="${PROJECT_ID}" &>/dev/null; then
            log_error "Cloud Spanner instance still exists: ${SPANNER_INSTANCE_ID}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check storage buckets
    for bucket in "${BACKUP_BUCKET_PRIMARY:-}" "${BACKUP_BUCKET_SECONDARY:-}"; do
        if [[ -n "$bucket" ]] && gsutil ls -b "gs://$bucket" &>/dev/null; then
            log_error "Storage bucket still exists: $bucket"
            ((cleanup_issues++))
        fi
    done
    
    # Check network
    if gcloud compute networks describe "${NETWORK_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
        log_error "VPC network still exists: ${NETWORK_NAME}"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification completed successfully - all resources removed"
    else
        log_warning "Cleanup verification found $cleanup_issues issues - manual intervention may be required"
        log_info "Please check the Google Cloud Console for any remaining resources"
    fi
}

# Print cleanup summary
print_cleanup_summary() {
    log_info "=== CLEANUP SUMMARY ==="
    echo
    echo -e "${GREEN}✅ Multi-Database Disaster Recovery Cleanup Completed${NC}"
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Primary Region: ${PRIMARY_REGION}"
    echo "Secondary Region: ${SECONDARY_REGION}"
    echo
    echo "Resources Removed:"
    echo "• AlloyDB Clusters (primary and secondary)"
    echo "• Cloud Spanner Instance and databases"
    echo "• Cloud Storage backup buckets"
    echo "• VPC network and subnets"
    echo "• Cloud Functions and Scheduler jobs"
    echo "• Pub/Sub topics and subscriptions"
    echo "• Monitoring dashboards and alerting policies"
    echo "• Local configuration files"
    echo
    echo "All disaster recovery resources have been cleaned up."
    echo "Please verify in the Google Cloud Console that no unexpected charges will occur."
    echo
}

# Main execution
main() {
    log_info "Starting Multi-Database Disaster Recovery cleanup..."
    
    load_config
    confirm_deletion
    
    # Remove resources in reverse dependency order
    remove_scheduler_jobs
    remove_cloud_functions
    remove_pubsub
    remove_monitoring
    remove_alloydb_clusters
    remove_cloud_spanner
    remove_storage_buckets
    remove_network
    cleanup_local_files
    
    verify_cleanup
    print_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--help]"
            echo "  --force  Skip confirmation prompts"
            echo "  --help   Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"