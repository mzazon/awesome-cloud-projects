#!/bin/bash

# Cloud Operations Automation with Gemini Cloud Assist and Hyperdisk ML - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

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
}

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        warning "kubectl is not installed. Some Kubernetes resources may not be cleaned up."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        warning "gsutil is not installed. Storage buckets may not be cleaned up."
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    success "Prerequisites checked"
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to detect project ID from gcloud config
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error "PROJECT_ID not set and cannot be detected from gcloud config"
            echo "Please set PROJECT_ID environment variable or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    log "Using environment variables:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
}

# Display warning and get confirmation
confirm_deletion() {
    log "⚠️  WARNING: This script will delete ALL resources in project ${PROJECT_ID}"
    echo ""
    echo "Resources to be deleted:"
    echo "  • All GKE clusters and workloads"
    echo "  • All Hyperdisk ML volumes"
    echo "  • All Cloud Functions"
    echo "  • All Cloud Scheduler jobs"
    echo "  • All Storage buckets and data"
    echo "  • All custom monitoring metrics and alerts"
    echo "  • All IAM service accounts"
    echo "  • All associated data will be permanently lost"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        warning "FORCE_DELETE=true, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed, proceeding with cleanup"
}

# List and delete GKE clusters
cleanup_gke_clusters() {
    log "Cleaning up GKE clusters and workloads..."
    
    # Get list of clusters in the zone
    local clusters
    clusters=$(gcloud container clusters list \
        --filter="location:${ZONE}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${clusters}" ]]; then
        for cluster in ${clusters}; do
            log "Processing cluster: ${cluster}"
            
            # Try to get credentials and clean up Kubernetes resources
            if gcloud container clusters get-credentials "${cluster}" --zone="${ZONE}" --quiet 2>/dev/null; then
                
                # Clean up ML training jobs
                if kubectl get jobs ml-training-hyperdisk &> /dev/null; then
                    log "Deleting ML training job..."
                    kubectl delete job ml-training-hyperdisk --ignore-not-found=true
                fi
                
                # Clean up PVCs
                if kubectl get pvc hyperdisk-ml-pvc &> /dev/null; then
                    log "Deleting Hyperdisk ML PVC..."
                    kubectl delete pvc hyperdisk-ml-pvc --ignore-not-found=true
                fi
                
                # Clean up storage classes
                if kubectl get storageclass hyperdisk-ml-storage &> /dev/null; then
                    log "Deleting Hyperdisk ML storage class..."
                    kubectl delete storageclass hyperdisk-ml-storage --ignore-not-found=true
                fi
                
                # Clean up ConfigMaps
                if kubectl get configmap vertex-ai-config &> /dev/null; then
                    log "Deleting Vertex AI config..."
                    kubectl delete configmap vertex-ai-config --ignore-not-found=true
                fi
                
                success "Kubernetes resources cleaned up for cluster: ${cluster}"
            else
                warning "Could not get credentials for cluster: ${cluster}"
            fi
            
            # Delete the cluster
            log "Deleting GKE cluster: ${cluster}"
            gcloud container clusters delete "${cluster}" \
                --zone="${ZONE}" \
                --quiet &
            
            # Store the process ID for later waiting
            cluster_pids+=($!)
        done
        
        # Wait for all cluster deletions to complete
        if [[ ${#cluster_pids[@]} -gt 0 ]]; then
            log "Waiting for ${#cluster_pids[@]} cluster(s) to be deleted..."
            for pid in "${cluster_pids[@]}"; do
                wait "$pid"
            done
        fi
        
        success "All GKE clusters deleted"
    else
        log "No GKE clusters found in zone ${ZONE}"
    fi
}

# Delete Hyperdisk ML volumes
cleanup_hyperdisk_volumes() {
    log "Cleaning up Hyperdisk ML volumes..."
    
    # Get list of hyperdisk-ml disks
    local disks
    disks=$(gcloud compute disks list \
        --filter="zone:${ZONE} AND type:hyperdisk-ml" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${disks}" ]]; then
        for disk in ${disks}; do
            log "Deleting Hyperdisk ML volume: ${disk}"
            gcloud compute disks delete "${disk}" \
                --zone="${ZONE}" \
                --quiet &
            
            # Store the process ID for later waiting
            disk_pids+=($!)
        done
        
        # Wait for all disk deletions to complete
        if [[ ${#disk_pids[@]} -gt 0 ]]; then
            log "Waiting for ${#disk_pids[@]} disk(s) to be deleted..."
            for pid in "${disk_pids[@]}"; do
                wait "$pid"
            done
        fi
        
        success "All Hyperdisk ML volumes deleted"
    else
        log "No Hyperdisk ML volumes found in zone ${ZONE}"
    fi
}

# Delete Cloud Functions
cleanup_cloud_functions() {
    log "Cleaning up Cloud Functions..."
    
    # Get list of functions in the region
    local functions
    functions=$(gcloud functions list \
        --regions="${REGION}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        for func in ${functions}; do
            # Extract just the function name from the full resource path
            local func_name
            func_name=$(basename "${func}")
            
            log "Deleting Cloud Function: ${func_name}"
            gcloud functions delete "${func_name}" \
                --region="${REGION}" \
                --quiet &
            
            # Store the process ID for later waiting
            function_pids+=($!)
        done
        
        # Wait for all function deletions to complete
        if [[ ${#function_pids[@]} -gt 0 ]]; then
            log "Waiting for ${#function_pids[@]} function(s) to be deleted..."
            for pid in "${function_pids[@]}"; do
                wait "$pid"
            done
        fi
        
        success "All Cloud Functions deleted"
    else
        log "No Cloud Functions found in region ${REGION}"
    fi
}

# Delete Cloud Scheduler jobs
cleanup_scheduler_jobs() {
    log "Cleaning up Cloud Scheduler jobs..."
    
    # Get list of scheduler jobs in the region
    local jobs
    jobs=$(gcloud scheduler jobs list \
        --location="${REGION}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${jobs}" ]]; then
        for job in ${jobs}; do
            # Extract just the job name from the full resource path
            local job_name
            job_name=$(basename "${job}")
            
            log "Deleting Cloud Scheduler job: ${job_name}"
            gcloud scheduler jobs delete "${job_name}" \
                --location="${REGION}" \
                --quiet
        done
        
        success "All Cloud Scheduler jobs deleted"
    else
        log "No Cloud Scheduler jobs found in region ${REGION}"
    fi
}

# Delete Storage buckets
cleanup_storage_buckets() {
    log "Cleaning up Storage buckets..."
    
    # Get list of buckets in the project
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | sed 's|gs://||g' | sed 's|/||g' || echo "")
    
    if [[ -n "${buckets}" ]]; then
        for bucket in ${buckets}; do
            # Only delete buckets that look like they're from this recipe
            if [[ "${bucket}" == *"ml-datasets-${PROJECT_ID}"* ]] || \
               [[ "${bucket}" == *"ml-ops"* ]] || \
               [[ "${bucket}" == *"vertex-ai"* ]]; then
                
                log "Deleting Storage bucket: gs://${bucket}"
                gsutil -m rm -r "gs://${bucket}" &
                
                # Store the process ID for later waiting
                bucket_pids+=($!)
            else
                log "Skipping bucket (not from this recipe): gs://${bucket}"
            fi
        done
        
        # Wait for all bucket deletions to complete
        if [[ ${#bucket_pids[@]} -gt 0 ]]; then
            log "Waiting for ${#bucket_pids[@]} bucket(s) to be deleted..."
            for pid in "${bucket_pids[@]}"; do
                wait "$pid"
            done
        fi
        
        success "Recipe-related Storage buckets deleted"
    else
        log "No Storage buckets found in project ${PROJECT_ID}"
    fi
}

# Delete monitoring metrics and alerts
cleanup_monitoring() {
    log "Cleaning up monitoring metrics and alerts..."
    
    # Delete custom logging metrics
    local metrics=("ml_training_duration" "storage_throughput")
    
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "${metric}" &> /dev/null; then
            log "Deleting logging metric: ${metric}"
            gcloud logging metrics delete "${metric}" --quiet
        fi
    done
    
    # Delete alerting policies
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:('ML Workload Performance Alert' OR 'ml' OR 'ML')" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${policies}" ]]; then
        for policy in ${policies}; do
            log "Deleting alerting policy: ${policy}"
            gcloud alpha monitoring policies delete "${policy}" --quiet
        done
    fi
    
    success "Monitoring metrics and alerts cleaned up"
}

# Delete IAM service accounts
cleanup_service_accounts() {
    log "Cleaning up IAM service accounts..."
    
    # Delete Vertex AI service account
    local sa_email="vertex-ai-agent@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        log "Deleting service account: ${sa_email}"
        gcloud iam service-accounts delete "${sa_email}" --quiet
        success "Service account deleted"
    else
        log "Service account not found: ${sa_email}"
    fi
}

# Clean up any remaining compute instances
cleanup_compute_instances() {
    log "Cleaning up any remaining compute instances..."
    
    # Get list of instances in the zone
    local instances
    instances=$(gcloud compute instances list \
        --filter="zone:${ZONE}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${instances}" ]]; then
        for instance in ${instances}; do
            # Only delete instances that look like they're from this recipe
            if [[ "${instance}" == *"ml-ops"* ]] || \
               [[ "${instance}" == *"vertex-ai"* ]] || \
               [[ "${instance}" == *"gke-"* ]]; then
                
                log "Deleting compute instance: ${instance}"
                gcloud compute instances delete "${instance}" \
                    --zone="${ZONE}" \
                    --quiet &
                
                # Store the process ID for later waiting
                instance_pids+=($!)
            else
                log "Skipping instance (not from this recipe): ${instance}"
            fi
        done
        
        # Wait for all instance deletions to complete
        if [[ ${#instance_pids[@]} -gt 0 ]]; then
            log "Waiting for ${#instance_pids[@]} instance(s) to be deleted..."
            for pid in "${instance_pids[@]}"; do
                wait "$pid"
            done
        fi
        
        success "Recipe-related compute instances deleted"
    else
        log "No compute instances found in zone ${ZONE}"
    fi
}

# Clean up local files and kubectl context
cleanup_local_files() {
    log "Cleaning up local files and kubectl context..."
    
    # Remove any temporary files that might have been created
    rm -f ml-alerting-policy.json lifecycle-policy.json 2>/dev/null || true
    rm -f vertex-ai-agent.yaml ml-training-job.yaml 2>/dev/null || true
    rm -f hyperdisk-ml-storage-class.yaml 2>/dev/null || true
    rm -rf ml-ops-functions/ 2>/dev/null || true
    
    # Try to clean up kubectl contexts for deleted clusters
    if command -v kubectl &> /dev/null; then
        # Get current contexts
        local contexts
        contexts=$(kubectl config get-contexts -o name 2>/dev/null | grep -E "gke_${PROJECT_ID}_" || echo "")
        
        if [[ -n "${contexts}" ]]; then
            for context in ${contexts}; do
                log "Removing kubectl context: ${context}"
                kubectl config delete-context "${context}" 2>/dev/null || true
            done
        fi
    fi
    
    success "Local files and kubectl contexts cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local issues=0
    
    # Check for remaining clusters
    local remaining_clusters
    remaining_clusters=$(gcloud container clusters list \
        --filter="location:${ZONE}" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ ${remaining_clusters} -gt 0 ]]; then
        warning "⚠️  ${remaining_clusters} GKE cluster(s) still exist"
        ((issues++))
    else
        success "✅ No GKE clusters remaining"
    fi
    
    # Check for remaining disks
    local remaining_disks
    remaining_disks=$(gcloud compute disks list \
        --filter="zone:${ZONE} AND type:hyperdisk-ml" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ ${remaining_disks} -gt 0 ]]; then
        warning "⚠️  ${remaining_disks} Hyperdisk ML volume(s) still exist"
        ((issues++))
    else
        success "✅ No Hyperdisk ML volumes remaining"
    fi
    
    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --regions="${REGION}" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ ${remaining_functions} -gt 0 ]]; then
        warning "⚠️  ${remaining_functions} Cloud Function(s) still exist"
        ((issues++))
    else
        success "✅ No Cloud Functions remaining"
    fi
    
    # Check for remaining scheduler jobs
    local remaining_jobs
    remaining_jobs=$(gcloud scheduler jobs list \
        --location="${REGION}" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ ${remaining_jobs} -gt 0 ]]; then
        warning "⚠️  ${remaining_jobs} Cloud Scheduler job(s) still exist"
        ((issues++))
    else
        success "✅ No Cloud Scheduler jobs remaining"
    fi
    
    if [[ ${issues} -eq 0 ]]; then
        success "🎉 Cleanup validation completed successfully!"
    else
        warning "⚠️  ${issues} issue(s) found during cleanup validation"
        warning "Some resources may need manual deletion"
    fi
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "================"
    echo ""
    echo "🧹 Resources Cleaned Up:"
    echo "  • GKE clusters and workloads"
    echo "  • Hyperdisk ML volumes"
    echo "  • Cloud Functions"
    echo "  • Cloud Scheduler jobs"
    echo "  • Storage buckets (recipe-related)"
    echo "  • Monitoring metrics and alerts"
    echo "  • IAM service accounts"
    echo "  • Local files and kubectl contexts"
    echo ""
    echo "📝 Notes:"
    echo "  • Project ${PROJECT_ID} still exists (not deleted)"
    echo "  • Non-recipe resources were preserved"
    echo "  • APIs remain enabled for future use"
    echo ""
    echo "⚠️  Manual Steps (if needed):"
    echo "  • Check Google Cloud Console for any remaining resources"
    echo "  • Review billing to ensure no unexpected charges"
    echo "  • Delete the project entirely if no longer needed:"
    echo "    gcloud projects delete ${PROJECT_ID}"
    echo ""
}

# Main cleanup function
main() {
    log "Starting Cloud Operations Automation cleanup..."
    
    # Initialize arrays for background process tracking
    cluster_pids=()
    disk_pids=()
    function_pids=()
    bucket_pids=()
    instance_pids=()
    
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Clean up resources in reverse order of dependency
    cleanup_scheduler_jobs
    cleanup_cloud_functions
    cleanup_gke_clusters
    cleanup_hyperdisk_volumes
    cleanup_storage_buckets
    cleanup_monitoring
    cleanup_service_accounts
    cleanup_compute_instances
    cleanup_local_files
    
    validate_cleanup
    display_summary
    
    success "🎉 Cloud Operations Automation cleanup completed!"
    log "All recipe resources have been removed from project ${PROJECT_ID}"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Run main function
main "$@"