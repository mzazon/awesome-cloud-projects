#!/bin/bash

# Destroy script for AlloyDB AI Performance Automation Recipe
# This script removes all infrastructure created for the automated database performance optimization solution

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

# Global variables
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-cleanup)
                FORCE_CLEANUP=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force-cleanup    Force cleanup of resources even if some operations fail"
    echo "  --yes, -y         Skip confirmation prompts"
    echo "  --help, -h        Show this help message"
    echo ""
    echo "This script will remove all resources created by the AlloyDB AI Performance Automation deployment."
}

# Function to load deployment configuration
load_config() {
    if [[ -f ".deployment_config" ]]; then
        log_info "Loading deployment configuration..."
        source .deployment_config
        log_success "Configuration loaded successfully"
    else
        log_warning "No deployment configuration found. Will attempt to discover resources."
        # Try to get project from gcloud config
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project configured. Please set PROJECT_ID environment variable or run from deployment directory."
            exit 1
        fi
    fi
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}" 2>/dev/null || true
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "WARNING: This will permanently delete all AlloyDB AI Performance Automation resources!"
    echo ""
    echo "Resources to be deleted:"
    echo "- AlloyDB cluster and instances"
    echo "- VPC network and subnets"
    echo "- Cloud Functions"
    echo "- Pub/Sub topics"
    echo "- Cloud Scheduler jobs"
    echo "- Vertex AI datasets and models"
    echo "- Monitoring dashboards and policies"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Function to safely execute commands with error handling
safe_execute() {
    local command="$1"
    local description="$2"
    local allow_failure="${3:-false}"
    
    log_info "$description"
    
    if eval "$command" 2>/dev/null; then
        log_success "$description completed"
        return 0
    else
        if [[ "$allow_failure" == "true" || "$FORCE_CLEANUP" == "true" ]]; then
            log_warning "$description failed, but continuing cleanup"
            return 0
        else
            log_error "$description failed"
            return 1
        fi
    fi
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."
    
    # Delete performance analyzer job
    safe_execute \
        "gcloud scheduler jobs delete performance-analyzer --quiet" \
        "Deleting performance analyzer scheduler job" \
        true
    
    # Delete daily report job
    safe_execute \
        "gcloud scheduler jobs delete daily-performance-report --quiet" \
        "Deleting daily performance report scheduler job" \
        true
    
    log_success "Cloud Scheduler jobs cleanup completed"
}

# Function to delete Cloud Functions and related resources
delete_cloud_functions() {
    log_info "Removing Cloud Functions and related resources..."
    
    # Delete Cloud Function
    safe_execute \
        "gcloud functions delete alloydb-performance-optimizer --gen2 --region='${REGION}' --quiet" \
        "Deleting AlloyDB performance optimizer function" \
        true
    
    # Delete Pub/Sub topic
    safe_execute \
        "gcloud pubsub topics delete alloydb-performance-events --quiet" \
        "Deleting Pub/Sub topic for performance events" \
        true
    
    # Clean up function source code directory
    if [[ -d "alloydb-optimizer" ]]; then
        rm -rf alloydb-optimizer
        log_success "Cleaned up function source directory"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Vertex AI resources
delete_vertex_ai() {
    log_info "Removing Vertex AI resources..."
    
    # Delete AI models
    log_info "Searching for AlloyDB performance models..."
    MODEL_IDS=$(gcloud ai models list \
        --region="${REGION}" \
        --filter="displayName:alloydb-performance-model" \
        --format="value(name)" 2>/dev/null | cut -d'/' -f6 || echo "")
    
    if [[ -n "$MODEL_IDS" ]]; then
        for model_id in $MODEL_IDS; do
            safe_execute \
                "gcloud ai models delete '$model_id' --region='${REGION}' --quiet" \
                "Deleting AI model: $model_id" \
                true
        done
    else
        log_info "No AI models found to delete"
    fi
    
    # Delete AI datasets
    log_info "Searching for AlloyDB performance datasets..."
    if [[ -n "${DATASET_ID:-}" ]]; then
        safe_execute \
            "gcloud ai datasets delete '${DATASET_ID}' --region='${REGION}' --quiet" \
            "Deleting AI dataset: ${DATASET_ID}" \
            true
    else
        # Try to find datasets by name pattern
        DATASET_IDS=$(gcloud ai datasets list \
            --region="${REGION}" \
            --filter="displayName:alloydb-performance-dataset" \
            --format="value(name)" 2>/dev/null | cut -d'/' -f6 || echo "")
        
        if [[ -n "$DATASET_IDS" ]]; then
            for dataset_id in $DATASET_IDS; do
                safe_execute \
                    "gcloud ai datasets delete '$dataset_id' --region='${REGION}' --quiet" \
                    "Deleting AI dataset: $dataset_id" \
                    true
            done
        else
            log_info "No AI datasets found to delete"
        fi
    fi
    
    log_success "Vertex AI resources cleanup completed"
}

# Function to delete monitoring resources
delete_monitoring() {
    log_info "Removing Cloud Monitoring resources..."
    
    # Delete dashboards
    log_info "Searching for AlloyDB performance dashboards..."
    DASHBOARD_IDS=$(gcloud monitoring dashboards list \
        --filter="displayName:'AlloyDB AI Performance Dashboard'" \
        --format="value(name)" 2>/dev/null | cut -d'/' -f4 || echo "")
    
    if [[ -n "$DASHBOARD_IDS" ]]; then
        for dashboard_id in $DASHBOARD_IDS; do
            safe_execute \
                "gcloud monitoring dashboards delete '$dashboard_id' --quiet" \
                "Deleting monitoring dashboard: $dashboard_id" \
                true
        done
    else
        log_info "No monitoring dashboards found to delete"
    fi
    
    # Delete alerting policies
    log_info "Searching for AlloyDB performance alert policies..."
    POLICY_IDS=$(gcloud alpha monitoring policies list \
        --filter="displayName:'AlloyDB Performance Anomaly Alert'" \
        --format="value(name)" 2>/dev/null | cut -d'/' -f4 || echo "")
    
    if [[ -n "$POLICY_IDS" ]]; then
        for policy_id in $POLICY_IDS; do
            safe_execute \
                "gcloud alpha monitoring policies delete '$policy_id' --quiet" \
                "Deleting alert policy: $policy_id" \
                true
        done
    else
        log_info "No alert policies found to delete"
    fi
    
    # Clean up configuration files
    for file in custom_metrics.yaml alert_policy.yaml dashboard_config.json; do
        if [[ -f "$file" ]]; then
            rm "$file"
            log_success "Removed configuration file: $file"
        fi
    done
    
    log_success "Cloud Monitoring resources cleanup completed"
}

# Function to delete AlloyDB cluster and instances
delete_alloydb() {
    log_info "Removing AlloyDB cluster and instances..."
    
    # Delete AlloyDB instance
    if [[ -n "${INSTANCE_NAME:-}" && -n "${CLUSTER_NAME:-}" ]]; then
        safe_execute \
            "gcloud alloydb instances delete '${INSTANCE_NAME}' --cluster='${CLUSTER_NAME}' --region='${REGION}' --quiet" \
            "Deleting AlloyDB instance: ${INSTANCE_NAME}" \
            true
    else
        log_info "Searching for AlloyDB instances to delete..."
        # Try to find instances by pattern
        INSTANCES=$(gcloud alloydb instances list \
            --region="${REGION}" \
            --filter="name:alloydb-perf-primary" \
            --format="csv[no-heading](name,cluster)" 2>/dev/null || echo "")
        
        if [[ -n "$INSTANCES" ]]; then
            while IFS=',' read -r instance_name cluster_name; do
                safe_execute \
                    "gcloud alloydb instances delete '$instance_name' --cluster='$cluster_name' --region='${REGION}' --quiet" \
                    "Deleting AlloyDB instance: $instance_name" \
                    true
            done <<< "$INSTANCES"
        fi
    fi
    
    # Wait for instance deletion to complete
    log_info "Waiting for instance deletion to complete..."
    sleep 30
    
    # Delete AlloyDB cluster
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        safe_execute \
            "gcloud alloydb clusters delete '${CLUSTER_NAME}' --region='${REGION}' --quiet" \
            "Deleting AlloyDB cluster: ${CLUSTER_NAME}" \
            true
    else
        log_info "Searching for AlloyDB clusters to delete..."
        CLUSTERS=$(gcloud alloydb clusters list \
            --region="${REGION}" \
            --filter="name:alloydb-perf-cluster" \
            --format="value(name)" 2>/dev/null | cut -d'/' -f6 || echo "")
        
        if [[ -n "$CLUSTERS" ]]; then
            for cluster_name in $CLUSTERS; do
                safe_execute \
                    "gcloud alloydb clusters delete '$cluster_name' --region='${REGION}' --quiet" \
                    "Deleting AlloyDB cluster: $cluster_name" \
                    true
            done
        fi
    fi
    
    log_success "AlloyDB resources cleanup completed"
}

# Function to delete VPC network and related resources
delete_network() {
    log_info "Removing VPC network and related networking resources..."
    
    # Delete VPC peering connection
    if [[ -n "${VPC_NAME:-}" ]]; then
        safe_execute \
            "gcloud services vpc-peerings delete --service=servicenetworking.googleapis.com --network='${VPC_NAME}' --quiet" \
            "Deleting VPC peering connection" \
            true
    fi
    
    # Delete allocated IP range
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        safe_execute \
            "gcloud compute addresses delete 'alloydb-range-${RANDOM_SUFFIX}' --global --quiet" \
            "Deleting allocated IP range" \
            true
    else
        # Try to find and delete ranges by pattern
        IP_RANGES=$(gcloud compute addresses list \
            --global \
            --filter="name:alloydb-range" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$IP_RANGES" ]]; then
            for range_name in $IP_RANGES; do
                safe_execute \
                    "gcloud compute addresses delete '$range_name' --global --quiet" \
                    "Deleting IP range: $range_name" \
                    true
            done
        fi
    fi
    
    # Delete subnet
    if [[ -n "${SUBNET_NAME:-}" ]]; then
        safe_execute \
            "gcloud compute networks subnets delete '${SUBNET_NAME}' --region='${REGION}' --quiet" \
            "Deleting subnet: ${SUBNET_NAME}" \
            true
    else
        # Try to find subnets by pattern
        SUBNETS=$(gcloud compute networks subnets list \
            --filter="name:alloydb-perf-subnet" \
            --format="csv[no-heading](name,region)" 2>/dev/null || echo "")
        
        if [[ -n "$SUBNETS" ]]; then
            while IFS=',' read -r subnet_name subnet_region; do
                safe_execute \
                    "gcloud compute networks subnets delete '$subnet_name' --region='$subnet_region' --quiet" \
                    "Deleting subnet: $subnet_name" \
                    true
            done <<< "$SUBNETS"
        fi
    fi
    
    # Delete VPC network
    if [[ -n "${VPC_NAME:-}" ]]; then
        safe_execute \
            "gcloud compute networks delete '${VPC_NAME}' --quiet" \
            "Deleting VPC network: ${VPC_NAME}" \
            true
    else
        # Try to find networks by pattern
        NETWORKS=$(gcloud compute networks list \
            --filter="name:alloydb-perf-vpc" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$NETWORKS" ]]; then
            for network_name in $NETWORKS; do
                safe_execute \
                    "gcloud compute networks delete '$network_name' --quiet" \
                    "Deleting VPC network: $network_name" \
                    true
            done
        fi
    fi
    
    log_success "VPC network and networking resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        ".deployment_config"
        "setup_vector_search.sql"
        "custom_metrics.yaml"
        "alert_policy.yaml"
        "dashboard_config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm "$file"
            log_success "Removed file: $file"
        fi
    done
    
    # Remove function source directory if it exists
    if [[ -d "alloydb-optimizer" ]]; then
        rm -rf alloydb-optimizer
        log_success "Removed function source directory"
    fi
    
    log_success "Local files cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating resource cleanup..."
    
    local cleanup_issues=()
    
    # Check for remaining AlloyDB clusters
    REMAINING_CLUSTERS=$(gcloud alloydb clusters list \
        --region="${REGION}" \
        --filter="name:alloydb-perf-cluster" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$REMAINING_CLUSTERS" -gt 0 ]]; then
        cleanup_issues+=("AlloyDB clusters still exist")
    fi
    
    # Check for remaining VPC networks
    REMAINING_NETWORKS=$(gcloud compute networks list \
        --filter="name:alloydb-perf-vpc" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$REMAINING_NETWORKS" -gt 0 ]]; then
        cleanup_issues+=("VPC networks still exist")
    fi
    
    # Check for remaining Cloud Functions
    REMAINING_FUNCTIONS=$(gcloud functions list \
        --region="${REGION}" \
        --filter="name:alloydb-performance-optimizer" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$REMAINING_FUNCTIONS" -gt 0 ]]; then
        cleanup_issues+=("Cloud Functions still exist")
    fi
    
    # Check for remaining Pub/Sub topics
    if gcloud pubsub topics describe alloydb-performance-events &>/dev/null; then
        cleanup_issues+=("Pub/Sub topics still exist")
    fi
    
    # Check for remaining Scheduler jobs
    REMAINING_JOBS=$(gcloud scheduler jobs list \
        --filter="name:performance-analyzer OR name:daily-performance-report" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$REMAINING_JOBS" -gt 0 ]]; then
        cleanup_issues+=("Scheduler jobs still exist")
    fi
    
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            echo "  - $issue"
        done
        log_info "You may need to manually clean up remaining resources"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "===================="
    echo "The following resources have been removed:"
    echo "✓ AlloyDB clusters and instances"
    echo "✓ VPC networks and subnets"
    echo "✓ Private service connections"
    echo "✓ Cloud Functions"
    echo "✓ Pub/Sub topics"
    echo "✓ Cloud Scheduler jobs"
    echo "✓ Vertex AI datasets and models"
    echo "✓ Monitoring dashboards and policies"
    echo "✓ Local configuration files"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "===================="
}

# Main cleanup function
main() {
    log_info "Starting AlloyDB AI Performance Automation cleanup..."
    
    parse_args "$@"
    load_config
    confirm_destruction
    
    # Execute cleanup in order (reverse of deployment)
    delete_scheduler_jobs
    delete_cloud_functions
    delete_vertex_ai
    delete_monitoring
    delete_alloydb
    delete_network
    cleanup_local_files
    
    validate_cleanup
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"