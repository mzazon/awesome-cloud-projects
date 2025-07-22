#!/bin/bash

# Weather-Aware Infrastructure Scaling with Google Maps Platform Weather API and Cluster Toolkit
# Cleanup/Destroy Script for GCP Recipe
# 
# This script safely removes all resources created by the weather-aware HPC infrastructure
# deployment, including the HPC cluster, Cloud Functions, storage, and monitoring resources.

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for confirmation
confirm_destruction() {
    log_warning "⚠️  This script will permanently delete all weather-aware HPC infrastructure resources."
    log_warning "⚠️  This action cannot be undone!"
    echo
    
    if [ "${FORCE_DESTROY:-false}" = "true" ]; then
        log_warning "FORCE_DESTROY is set - skipping confirmation"
        return 0
    fi
    
    while true; do
        read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
        case $confirm in
            yes|YES)
                log_info "Proceeding with resource destruction..."
                break
                ;;
            no|NO)
                log_info "Destruction cancelled by user"
                exit 0
                ;;
            *)
                log_error "Please type 'yes' or 'no'"
                ;;
        esac
    done
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command_exists terraform; then
        log_error "terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from environment file if it exists
    local info_files=(/tmp/weather-hpc-deployment-*.env)
    
    if [ -f "${info_files[0]}" ]; then
        log_info "Loading deployment info from: ${info_files[0]}"
        source "${info_files[0]}"
        log_success "Deployment information loaded"
    else
        log_warning "No deployment info file found, using environment variables or defaults"
    fi
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    if [ -z "${PROJECT_ID}" ]; then
        log_error "PROJECT_ID is not set. Please export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Set default resource names (may not match actual deployment if custom names were used)
    export CLUSTER_NAME="${CLUSTER_NAME:-weather-cluster}"
    export BUCKET_NAME="${BUCKET_NAME:-weather-data-${PROJECT_ID}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-weather-processor}"
    export TOPIC_NAME="${TOPIC_NAME:-weather-scaling}"
    export SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-weather-scaling-sub}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Cluster Name: ${CLUSTER_NAME}"
    log_info "Function Name: ${FUNCTION_NAME}"
    log_info "Bucket Name: ${BUCKET_NAME}"
}

# Function to set project context
setup_project_context() {
    log_info "Setting up project context..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project context configured"
}

# Function to destroy HPC cluster infrastructure
destroy_hpc_cluster() {
    log_info "Destroying HPC cluster infrastructure..."
    
    # Look for toolkit directory
    local toolkit_dirs=(/tmp/cluster-toolkit-*)
    local cluster_deployed=false
    
    if [ -d "${toolkit_dirs[0]}" ]; then
        local toolkit_dir="${toolkit_dirs[0]}"
        log_info "Found toolkit directory: ${toolkit_dir}"
        
        # Look for cluster deployment directory
        local cluster_dirs=("${toolkit_dir}"/weather-cluster-*)
        
        if [ -d "${cluster_dirs[0]}" ]; then
            local cluster_dir="${cluster_dirs[0]}"
            log_info "Found cluster directory: ${cluster_dir}"
            
            cd "${cluster_dir}"
            
            # Check if terraform state exists
            if [ -f "terraform.tfstate" ] || [ -f ".terraform/terraform.tfstate" ]; then
                log_info "Destroying cluster with Terraform..."
                
                # Initialize terraform if needed
                if [ ! -d ".terraform" ]; then
                    terraform init
                fi
                
                # Destroy cluster infrastructure
                if terraform destroy -auto-approve; then
                    log_success "HPC cluster destroyed successfully"
                    cluster_deployed=true
                else
                    log_error "Failed to destroy HPC cluster with Terraform"
                fi
            else
                log_warning "No Terraform state found for cluster"
            fi
            
            cd - > /dev/null
        else
            log_warning "No cluster deployment directory found"
        fi
    else
        log_warning "No toolkit directory found"
    fi
    
    # Clean up any remaining cluster resources manually
    if ! $cluster_deployed; then
        log_info "Attempting to clean up cluster resources manually..."
        
        # Try to find and delete cluster instances
        local instances=$(gcloud compute instances list --filter="name~'${CLUSTER_NAME}' OR name~'weather-cluster'" --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$instances" ]; then
            log_info "Found cluster instances to delete: $instances"
            for instance in $instances; do
                log_info "Deleting instance: $instance"
                gcloud compute instances delete "$instance" --zone="${ZONE}" --quiet || log_warning "Failed to delete instance $instance"
            done
        fi
        
        # Try to delete managed instance groups
        local migs=$(gcloud compute instance-groups managed list --filter="name~'${CLUSTER_NAME}' OR name~'weather-cluster'" --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$migs" ]; then
            log_info "Found managed instance groups to delete: $migs"
            for mig in $migs; do
                log_info "Deleting managed instance group: $mig"
                gcloud compute instance-groups managed delete "$mig" --region="${REGION}" --quiet || log_warning "Failed to delete MIG $mig"
            done
        fi
        
        # Try to delete filestore instances
        local filestores=$(gcloud filestore instances list --filter="name~'${CLUSTER_NAME}' OR name~'weather-cluster'" --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$filestores" ]; then
            log_info "Found filestore instances to delete: $filestores"
            for filestore in $filestores; do
                log_info "Deleting filestore instance: $filestore"
                gcloud filestore instances delete "$filestore" --location="${REGION}" --quiet || log_warning "Failed to delete filestore $filestore"
            done
        fi
        
        # Try to delete VPCs and networks
        local networks=$(gcloud compute networks list --filter="name~'${CLUSTER_NAME}' OR name~'weather-cluster'" --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$networks" ]; then
            log_info "Found networks to delete: $networks"
            for network in $networks; do
                # First delete subnets
                local subnets=$(gcloud compute networks subnets list --filter="network:$network" --format="value(name,region)" 2>/dev/null || echo "")
                
                if [ -n "$subnets" ]; then
                    while IFS=$'\t' read -r subnet_name subnet_region; do
                        log_info "Deleting subnet: $subnet_name in $subnet_region"
                        gcloud compute networks subnets delete "$subnet_name" --region="$subnet_region" --quiet || log_warning "Failed to delete subnet $subnet_name"
                    done <<< "$subnets"
                fi
                
                # Then delete the network
                log_info "Deleting network: $network"
                gcloud compute networks delete "$network" --quiet || log_warning "Failed to delete network $network"
            done
        fi
    fi
    
    log_success "HPC cluster cleanup completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Try to delete the specific function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet; then
            log_success "Cloud Function ${FUNCTION_NAME} deleted"
        else
            log_error "Failed to delete Cloud Function ${FUNCTION_NAME}"
        fi
    else
        log_warning "Cloud Function ${FUNCTION_NAME} not found"
    fi
    
    # Look for any weather-related functions
    local weather_functions=$(gcloud functions list --filter="name~'weather-processor'" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$weather_functions" ]; then
        log_info "Found additional weather functions to delete: $weather_functions"
        for func in $weather_functions; do
            log_info "Deleting function: $func"
            gcloud functions delete "$func" --region="${REGION}" --quiet || log_warning "Failed to delete function $func"
        done
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    # Delete weather check job
    if gcloud scheduler jobs describe weather-check-job --location="${REGION}" >/dev/null 2>&1; then
        log_info "Deleting scheduler job: weather-check-job"
        if gcloud scheduler jobs delete weather-check-job --location="${REGION}" --quiet; then
            log_success "Scheduler job weather-check-job deleted"
        else
            log_error "Failed to delete scheduler job weather-check-job"
        fi
    else
        log_warning "Scheduler job weather-check-job not found"
    fi
    
    # Delete storm monitor job
    if gcloud scheduler jobs describe weather-storm-monitor --location="${REGION}" >/dev/null 2>&1; then
        log_info "Deleting scheduler job: weather-storm-monitor"
        if gcloud scheduler jobs delete weather-storm-monitor --location="${REGION}" --quiet; then
            log_success "Scheduler job weather-storm-monitor deleted"
        else
            log_error "Failed to delete scheduler job weather-storm-monitor"
        fi
    else
        log_warning "Scheduler job weather-storm-monitor not found"
    fi
    
    # Look for any weather-related scheduler jobs
    local weather_jobs=$(gcloud scheduler jobs list --filter="name~'weather'" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$weather_jobs" ]; then
        log_info "Found additional weather scheduler jobs to delete: $weather_jobs"
        for job in $weather_jobs; do
            log_info "Deleting scheduler job: $job"
            gcloud scheduler jobs delete "$job" --location="${REGION}" --quiet || log_warning "Failed to delete scheduler job $job"
        done
    fi
    
    log_success "Cloud Scheduler cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" >/dev/null 2>&1; then
        log_info "Deleting Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
        if gcloud pubsub subscriptions delete "${SUBSCRIPTION_NAME}" --quiet; then
            log_success "Pub/Sub subscription ${SUBSCRIPTION_NAME} deleted"
        else
            log_error "Failed to delete Pub/Sub subscription ${SUBSCRIPTION_NAME}"
        fi
    else
        log_warning "Pub/Sub subscription ${SUBSCRIPTION_NAME} not found"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_info "Deleting Pub/Sub topic: ${TOPIC_NAME}"
        if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
            log_success "Pub/Sub topic ${TOPIC_NAME} deleted"
        else
            log_error "Failed to delete Pub/Sub topic ${TOPIC_NAME}"
        fi
    else
        log_warning "Pub/Sub topic ${TOPIC_NAME} not found"
    fi
    
    # Look for any weather-related Pub/Sub resources
    local weather_topics=$(gcloud pubsub topics list --filter="name~'weather-scaling'" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$weather_topics" ]; then
        log_info "Found additional weather topics to delete: $weather_topics"
        for topic in $weather_topics; do
            # Delete subscriptions for this topic first
            local topic_subs=$(gcloud pubsub subscriptions list --filter="topic:$topic" --format="value(name)" 2>/dev/null || echo "")
            
            if [ -n "$topic_subs" ]; then
                for sub in $topic_subs; do
                    log_info "Deleting subscription: $sub"
                    gcloud pubsub subscriptions delete "$sub" --quiet || log_warning "Failed to delete subscription $sub"
                done
            fi
            
            # Delete the topic
            log_info "Deleting topic: $topic"
            gcloud pubsub topics delete "$topic" --quiet || log_warning "Failed to delete topic $topic"
        done
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Function to delete Cloud Storage resources
delete_storage_resources() {
    log_info "Deleting Cloud Storage resources..."
    
    # Check if bucket exists and delete it
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_info "Deleting Cloud Storage bucket: ${BUCKET_NAME}"
        log_info "Removing all objects from bucket..."
        
        # Remove all objects and versions
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null; then
            log_info "All objects removed from bucket"
        else
            log_warning "Some objects may not have been removed"
        fi
        
        # Remove the bucket
        if gsutil rb "gs://${BUCKET_NAME}"; then
            log_success "Cloud Storage bucket ${BUCKET_NAME} deleted"
        else
            log_error "Failed to delete Cloud Storage bucket ${BUCKET_NAME}"
        fi
    else
        log_warning "Cloud Storage bucket ${BUCKET_NAME} not found"
    fi
    
    # Look for any weather-related buckets
    local weather_buckets=$(gsutil ls | grep -E "weather-data|weather-hpc" | sed 's|gs://||g' | sed 's|/||g' 2>/dev/null || echo "")
    
    if [ -n "$weather_buckets" ]; then
        log_info "Found additional weather buckets to delete: $weather_buckets"
        for bucket in $weather_buckets; do
            log_info "Deleting bucket: $bucket"
            gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || log_warning "Failed to remove objects from bucket $bucket"
            gsutil rb "gs://${bucket}" || log_warning "Failed to delete bucket $bucket"
        done
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # Delete weather-aware dashboards
    local weather_dashboards=$(gcloud monitoring dashboards list --filter="displayName~'Weather-Aware'" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$weather_dashboards" ]; then
        log_info "Found weather dashboards to delete: $weather_dashboards"
        for dashboard in $weather_dashboards; do
            log_info "Deleting monitoring dashboard: $dashboard"
            if gcloud monitoring dashboards delete "$dashboard" --quiet; then
                log_success "Dashboard deleted: $dashboard"
            else
                log_error "Failed to delete dashboard: $dashboard"
            fi
        done
    else
        log_warning "No weather-aware dashboards found"
    fi
    
    # Note: Custom metrics will be automatically cleaned up when they stop receiving data
    log_info "Custom metrics will be automatically cleaned up when they stop receiving data"
    
    log_success "Monitoring resources cleanup completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Clean up toolkit directories
    local toolkit_dirs=(/tmp/cluster-toolkit-*)
    for dir in "${toolkit_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Removing toolkit directory: $dir"
            rm -rf "$dir" || log_warning "Failed to remove directory $dir"
        fi
    done
    
    # Clean up deployment info files
    local info_files=(/tmp/weather-hpc-deployment-*.env)
    for file in "${info_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing deployment info file: $file"
            rm -f "$file" || log_warning "Failed to remove file $file"
        fi
    done
    
    # Clean up scaling agent files
    local scaling_files=(/tmp/scaling-agent-*.py)
    for file in "${scaling_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing scaling agent file: $file"
            rm -f "$file" || log_warning "Failed to remove file $file"
        fi
    done
    
    # Clean up sample job files
    local job_files=(/tmp/climate-model-job-*.sh /tmp/energy-forecast-job-*.sh)
    for file in "${job_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing job file: $file"
            rm -f "$file" || log_warning "Failed to remove file $file"
        fi
    done
    
    # Clean up temporary dashboard files
    local dashboard_files=(/tmp/weather-dashboard-*.json)
    for file in "${dashboard_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing dashboard file: $file"
            rm -f "$file" || log_warning "Failed to remove file $file"
        fi
    done
    
    # Clean up toolkit directory tracking files
    local toolkit_tracking_files=(/tmp/toolkit_dir_*)
    for file in "${toolkit_tracking_files[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing toolkit tracking file: $file"
            rm -f "$file" || log_warning "Failed to remove file $file"
        fi
    done
    
    log_success "Temporary files cleanup completed"
}

# Function to run final validation
run_final_validation() {
    log_info "Running final validation..."
    
    local cleanup_issues=0
    
    # Check if Cloud Function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_error "❌ Cloud Function ${FUNCTION_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log_success "✅ Cloud Function ${FUNCTION_NAME} removed"
    fi
    
    # Check if Pub/Sub resources still exist
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_error "❌ Pub/Sub topic ${TOPIC_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log_success "✅ Pub/Sub topic ${TOPIC_NAME} removed"
    fi
    
    # Check if Storage bucket still exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_error "❌ Storage bucket ${BUCKET_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log_success "✅ Storage bucket ${BUCKET_NAME} removed"
    fi
    
    # Check if scheduler jobs still exist
    if gcloud scheduler jobs describe weather-check-job --location="${REGION}" >/dev/null 2>&1; then
        log_error "❌ Scheduler job weather-check-job still exists"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log_success "✅ Scheduler jobs removed"
    fi
    
    # Check for any remaining cluster resources
    local remaining_instances=$(gcloud compute instances list --filter="name~'${CLUSTER_NAME}' OR name~'weather-cluster'" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$remaining_instances" ]; then
        log_error "❌ Cluster instances still exist: $remaining_instances"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log_success "✅ Cluster instances removed"
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "✅ All resources appear to be cleaned up successfully"
    else
        log_warning "⚠️  $cleanup_issues issue(s) detected during cleanup validation"
        log_warning "⚠️  Some resources may still exist and could incur charges"
        log_warning "⚠️  Please check the GCP Console manually"
    fi
    
    log_info "Final validation completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "🧹 Weather-Aware HPC Infrastructure cleanup completed!"
    
    echo
    echo "========================================="
    echo "CLEANUP SUMMARY"
    echo "========================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo
    echo "Resources cleaned up:"
    echo "- HPC Cluster infrastructure"
    echo "- Cloud Functions"
    echo "- Cloud Scheduler jobs"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Cloud Storage buckets"
    echo "- Monitoring dashboards"
    echo "- Temporary files"
    echo
    echo "========================================="
    echo "IMPORTANT NOTES"
    echo "========================================="
    echo "- Please verify in GCP Console that all resources are deleted"
    echo "- Some resources may take a few minutes to fully disappear"
    echo "- Custom metrics will automatically expire after 7 days"
    echo "- Check billing to ensure no unexpected charges"
    echo
    echo "If you encounter any issues:"
    echo "1. Check the GCP Console for remaining resources"
    echo "2. Manually delete any remaining resources"
    echo "3. Verify billing is not showing ongoing charges"
    echo
    log_success "Cleanup completed successfully! 🌦️ 🧹"
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    log_info "Performing partial cleanup based on available information..."
    
    # Try to find and clean up resources by pattern matching
    log_info "Searching for weather-related resources..."
    
    # Find weather-related Cloud Functions
    local weather_functions=$(gcloud functions list --filter="name~'weather'" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$weather_functions" ]; then
        log_info "Found weather functions: $weather_functions"
        for func in $weather_functions; do
            gcloud functions delete "$func" --region="${REGION}" --quiet || log_warning "Failed to delete function $func"
        done
    fi
    
    # Find weather-related scheduler jobs
    local weather_jobs=$(gcloud scheduler jobs list --filter="name~'weather'" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$weather_jobs" ]; then
        log_info "Found weather jobs: $weather_jobs"
        for job in $weather_jobs; do
            gcloud scheduler jobs delete "$job" --location="${REGION}" --quiet || log_warning "Failed to delete job $job"
        done
    fi
    
    # Find weather-related Pub/Sub topics
    local weather_topics=$(gcloud pubsub topics list --filter="name~'weather'" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$weather_topics" ]; then
        log_info "Found weather topics: $weather_topics"
        for topic in $weather_topics; do
            # Delete subscriptions first
            local subs=$(gcloud pubsub subscriptions list --filter="topic:$topic" --format="value(name)" 2>/dev/null || echo "")
            for sub in $subs; do
                gcloud pubsub subscriptions delete "$sub" --quiet || log_warning "Failed to delete subscription $sub"
            done
            # Delete topic
            gcloud pubsub topics delete "$topic" --quiet || log_warning "Failed to delete topic $topic"
        done
    fi
    
    # Find weather-related storage buckets
    local weather_buckets=$(gsutil ls | grep -E "weather" | sed 's|gs://||g' | sed 's|/||g' 2>/dev/null || echo "")
    if [ -n "$weather_buckets" ]; then
        log_info "Found weather buckets: $weather_buckets"
        for bucket in $weather_buckets; do
            gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || log_warning "Failed to remove objects from bucket $bucket"
            gsutil rb "gs://${bucket}" || log_warning "Failed to delete bucket $bucket"
        done
    fi
    
    # Find weather-related compute instances
    local weather_instances=$(gcloud compute instances list --filter="name~'weather'" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$weather_instances" ]; then
        log_info "Found weather instances: $weather_instances"
        for instance in $weather_instances; do
            gcloud compute instances delete "$instance" --zone="${ZONE}" --quiet || log_warning "Failed to delete instance $instance"
        done
    fi
    
    log_success "Partial cleanup completed"
}

# Main cleanup function
main() {
    log_info "Starting Weather-Aware HPC Infrastructure cleanup..."
    
    # Check if running in dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "Running in DRY RUN mode - no actual resources will be deleted"
        return 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    confirm_destruction
    load_deployment_info
    setup_project_context
    
    # Try full cleanup first
    if [ -n "${CLUSTER_NAME:-}" ] && [ -n "${FUNCTION_NAME:-}" ]; then
        log_info "Performing full cleanup with known resource names..."
        destroy_hpc_cluster
        delete_cloud_functions
        delete_scheduler_jobs
        delete_pubsub_resources
        delete_storage_resources
        delete_monitoring_resources
        cleanup_temp_files
        run_final_validation
    else
        log_warning "Missing some resource names, performing partial cleanup..."
        handle_partial_cleanup
        cleanup_temp_files
    fi
    
    display_cleanup_summary
    log_success "All cleanup steps completed!"
}

# Script execution with error handling
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Set trap for cleanup on exit
    trap 'log_error "Script interrupted or failed. Some resources may still exist."' ERR
    
    main "$@"
fi