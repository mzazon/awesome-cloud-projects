#!/bin/bash

# Quantum-Safe Security Posture Management Cleanup Script
# This script safely removes all resources created by the quantum-safe security deployment
# including KMS keys, monitoring dashboards, compliance functions, and the project

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/../terraform/terraform.tfvars"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Banner
echo "=========================================="
echo "  Quantum-Safe Security Posture Cleanup"
echo "=========================================="
echo ""

# Load configuration from terraform vars if available
load_configuration() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        info "Loading configuration from ${CONFIG_FILE}"
        
        # Parse terraform vars file
        export PROJECT_ID=$(grep -E '^project_id' "${CONFIG_FILE}" | cut -d'"' -f2 2>/dev/null || echo "")
        export ORGANIZATION_ID=$(grep -E '^organization_id' "${CONFIG_FILE}" | cut -d'"' -f2 2>/dev/null || echo "")
        export REGION=$(grep -E '^region' "${CONFIG_FILE}" | cut -d'"' -f2 2>/dev/null || echo "us-central1")
        export KMS_KEYRING_NAME=$(grep -E '^kms_keyring_name' "${CONFIG_FILE}" | cut -d'"' -f2 2>/dev/null || echo "")
        export KMS_KEY_NAME=$(grep -E '^kms_key_name' "${CONFIG_FILE}" | cut -d'"' -f2 2>/dev/null || echo "")
        
        if [[ -n "${PROJECT_ID}" ]]; then
            info "Loaded project: ${PROJECT_ID}"
        else
            warn "Could not load project ID from configuration"
        fi
    else
        warn "Configuration file not found. Will prompt for project details."
    fi
}

# Interactive project selection
select_project() {
    if [[ -z "${PROJECT_ID:-}" ]]; then
        echo ""
        echo "Available projects with 'quantum-security' in the name:"
        gcloud projects list --filter="projectId:quantum-security*" --format="table(projectId,name,projectNumber)" 2>/dev/null || true
        echo ""
        
        read -p "Enter the project ID to cleanup: " PROJECT_ID
        
        if [[ -z "${PROJECT_ID}" ]]; then
            error "Project ID is required"
            exit 1
        fi
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} not found or not accessible"
        exit 1
    fi
    
    # Auto-detect other resources if not loaded from config
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
    fi
    
    gcloud config set project "${PROJECT_ID}"
    info "Selected project: ${PROJECT_ID}"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    warn "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   • Project: ${PROJECT_ID}"
    echo "   • All KMS keys and keyrings"
    echo "   • Monitoring dashboards and alerts"
    echo "   • Cloud Functions"
    echo "   • Storage buckets"
    echo "   • Asset inventory feeds"
    echo "   • Security Command Center configurations"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warn "Final confirmation required!"
    read -p "Type the project ID '${PROJECT_ID}' to confirm destruction: " project_confirmation
    
    if [[ "${project_confirmation}" != "${PROJECT_ID}" ]]; then
        error "Project ID confirmation failed. Cleanup cancelled."
        exit 1
    fi
    
    info "Destruction confirmed. Starting cleanup..."
}

# Destroy Cloud Functions and Scheduler jobs
cleanup_functions() {
    info "Cleaning up Cloud Functions and Scheduler jobs..."
    
    # List and delete scheduler jobs
    local scheduler_jobs=$(gcloud scheduler jobs list --location="${REGION}" \
        --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -E "(quantum|compliance)" || true)
    
    for job in ${scheduler_jobs}; do
        if [[ -n "${job}" ]]; then
            info "Deleting scheduler job: ${job}"
            gcloud scheduler jobs delete "${job##*/}" \
                --location="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null || warn "Failed to delete scheduler job: ${job}"
        fi
    done
    
    # List and delete cloud functions
    local functions=$(gcloud functions list --regions="${REGION}" \
        --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -E "(quantum|compliance)" || true)
    
    for func in ${functions}; do
        if [[ -n "${func}" ]]; then
            info "Deleting Cloud Function: ${func}"
            gcloud functions delete "${func##*/}" \
                --region="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null || warn "Failed to delete function: ${func}"
        fi
    done
    
    success "Functions and scheduler jobs cleanup completed"
}

# Destroy monitoring resources
cleanup_monitoring() {
    info "Cleaning up Cloud Monitoring resources..."
    
    # Delete monitoring dashboards
    local dashboards=$(gcloud monitoring dashboards list \
        --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -i quantum || true)
    
    for dashboard in ${dashboards}; do
        if [[ -n "${dashboard}" ]]; then
            info "Deleting monitoring dashboard: ${dashboard}"
            gcloud monitoring dashboards delete "${dashboard}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null || warn "Failed to delete dashboard: ${dashboard}"
        fi
    done
    
    # Delete alerting policies
    local policies=$(gcloud alpha monitoring policies list \
        --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -i quantum || true)
    
    for policy in ${policies}; do
        if [[ -n "${policy}" ]]; then
            info "Deleting alerting policy: ${policy}"
            gcloud alpha monitoring policies delete "${policy}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null || warn "Failed to delete policy: ${policy}"
        fi
    done
    
    success "Monitoring resources cleanup completed"
}

# Destroy Security Command Center configurations
cleanup_security_center() {
    info "Cleaning up Security Command Center configurations..."
    
    if [[ -n "${ORGANIZATION_ID:-}" ]]; then
        # Delete security postures
        local postures=$(gcloud scc postures list \
            --organization="${ORGANIZATION_ID}" \
            --location=global --format="value(name)" 2>/dev/null | grep -i quantum || true)
        
        for posture in ${postures}; do
            if [[ -n "${posture}" ]]; then
                info "Deleting security posture: ${posture}"
                gcloud scc postures delete "${posture##*/}" \
                    --organization="${ORGANIZATION_ID}" \
                    --location=global \
                    --quiet 2>/dev/null || warn "Failed to delete posture: ${posture}"
            fi
        done
        
        # Delete asset inventory feeds
        local feeds=$(gcloud asset feeds list \
            --organization="${ORGANIZATION_ID}" --format="value(name)" 2>/dev/null | grep -i quantum || true)
        
        for feed in ${feeds}; do
            if [[ -n "${feed}" ]]; then
                info "Deleting asset inventory feed: ${feed}"
                gcloud asset feeds delete "${feed##*/}" \
                    --organization="${ORGANIZATION_ID}" \
                    --quiet 2>/dev/null || warn "Failed to delete feed: ${feed}"
            fi
        done
    else
        warn "Organization ID not found. Skipping org-level Security Command Center cleanup."
    fi
    
    success "Security Command Center cleanup completed"
}

# Destroy KMS resources
cleanup_kms() {
    info "Cleaning up Cloud KMS resources..."
    
    # List all keyrings in the project
    local keyrings=$(gcloud kms keyrings list --location="${REGION}" \
        --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
    
    for keyring in ${keyrings}; do
        if [[ -n "${keyring}" ]]; then
            local keyring_name="${keyring##*/}"
            info "Processing keyring: ${keyring_name}"
            
            # List all keys in the keyring
            local keys=$(gcloud kms keys list --keyring="${keyring_name}" \
                --location="${REGION}" --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
            
            for key in ${keys}; do
                if [[ -n "${key}" ]]; then
                    local key_name="${key##*/}"
                    info "Processing key: ${key_name}"
                    
                    # List all key versions
                    local versions=$(gcloud kms keys versions list --key="${key_name}" \
                        --keyring="${keyring_name}" --location="${REGION}" \
                        --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
                    
                    for version in ${versions}; do
                        if [[ -n "${version}" ]]; then
                            local version_id="${version##*/}"
                            local current_state=$(gcloud kms keys versions describe "${version_id}" \
                                --key="${key_name}" --keyring="${keyring_name}" \
                                --location="${REGION}" --project="${PROJECT_ID}" \
                                --format="value(state)" 2>/dev/null || true)
                            
                            if [[ "${current_state}" != "DESTROY_SCHEDULED" && "${current_state}" != "DESTROYED" ]]; then
                                info "Scheduling key version ${version_id} for destruction"
                                gcloud kms keys versions destroy "${version_id}" \
                                    --key="${key_name}" \
                                    --keyring="${keyring_name}" \
                                    --location="${REGION}" \
                                    --project="${PROJECT_ID}" \
                                    --quiet 2>/dev/null || warn "Failed to schedule destruction for ${version_id}"
                            else
                                info "Key version ${version_id} already scheduled for destruction or destroyed"
                            fi
                        fi
                    done
                fi
            done
        fi
    done
    
    warn "KMS keys have been scheduled for destruction (30-day delay for security)"
    success "KMS resources cleanup completed"
}

# Destroy storage resources
cleanup_storage() {
    info "Cleaning up Cloud Storage resources..."
    
    # List buckets with project prefix
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(crypto-inventory|quantum)" || true)
    
    for bucket in ${buckets}; do
        if [[ -n "${bucket}" ]]; then
            info "Deleting storage bucket: ${bucket}"
            gsutil -m rm -r "${bucket}" 2>/dev/null || warn "Failed to delete bucket: ${bucket}"
        fi
    done
    
    success "Storage resources cleanup completed"
}

# Destroy Pub/Sub resources
cleanup_pubsub() {
    info "Cleaning up Pub/Sub resources..."
    
    # Delete topics
    local topics=$(gcloud pubsub topics list --project="${PROJECT_ID}" \
        --format="value(name)" 2>/dev/null | grep -E "(crypto|quantum)" || true)
    
    for topic in ${topics}; do
        if [[ -n "${topic}" ]]; then
            local topic_name="${topic##*/}"
            info "Deleting Pub/Sub topic: ${topic_name}"
            gcloud pubsub topics delete "${topic_name}" \
                --project="${PROJECT_ID}" \
                --quiet 2>/dev/null || warn "Failed to delete topic: ${topic_name}"
        fi
    done
    
    success "Pub/Sub resources cleanup completed"
}

# Option to delete entire project
delete_project() {
    echo ""
    warn "Would you like to delete the entire project?"
    echo "This will remove ALL resources in the project, not just quantum-security related ones."
    echo ""
    
    read -p "Delete entire project '${PROJECT_ID}'? (y/N): " delete_project_choice
    
    if [[ "${delete_project_choice}" =~ ^[Yy]$ ]]; then
        echo ""
        warn "⚠️  FINAL WARNING: This will permanently delete the entire project!"
        read -p "Type 'DELETE PROJECT' to confirm: " final_confirmation
        
        if [[ "${final_confirmation}" == "DELETE PROJECT" ]]; then
            info "Deleting project ${PROJECT_ID}..."
            gcloud projects delete "${PROJECT_ID}" --quiet
            success "Project ${PROJECT_ID} deletion initiated"
        else
            warn "Project deletion cancelled"
        fi
    else
        info "Project ${PROJECT_ID} preserved"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/quantum-security-policy.yaml"
        "${SCRIPT_DIR}/quantum-metrics-dashboard.json"
        "${SCRIPT_DIR}/quantum-alert-policy.yaml"
        "${SCRIPT_DIR}/compliance-function"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -e "${file}" ]]; then
            rm -rf "${file}"
            info "Removed: ${file}"
        fi
    done
    
    success "Temporary files cleanup completed"
}

# Validation function
validate_cleanup() {
    info "Validating cleanup completion..."
    
    local validation_errors=0
    
    # Check if project still exists (only if we didn't delete it)
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        # Check for remaining Cloud Functions
        local remaining_functions=$(gcloud functions list --project="${PROJECT_ID}" \
            --format="value(name)" 2>/dev/null | grep -E "(quantum|compliance)" | wc -l || echo "0")
        
        if [[ ${remaining_functions} -gt 0 ]]; then
            warn "⚠️  ${remaining_functions} Cloud Functions still exist"
            ((validation_errors++))
        else
            success "✅ Cloud Functions cleaned up"
        fi
        
        # Check for remaining storage buckets
        local remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(crypto|quantum)" | wc -l || echo "0")
        
        if [[ ${remaining_buckets} -gt 0 ]]; then
            warn "⚠️  ${remaining_buckets} Storage buckets still exist"
            ((validation_errors++))
        else
            success "✅ Storage buckets cleaned up"
        fi
        
        # Check for KMS keys (they should be scheduled for destruction)
        local kms_keys=$(gcloud kms keys list --location="${REGION}" \
            --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | wc -l || echo "0")
        
        if [[ ${kms_keys} -gt 0 ]]; then
            info "ℹ️  ${kms_keys} KMS keys found (scheduled for 30-day destruction)"
        else
            success "✅ No KMS keys found"
        fi
    else
        success "✅ Project deleted completely"
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        success "Cleanup validation passed"
    else
        warn "Cleanup validation found ${validation_errors} issues"
    fi
}

# Display cleanup summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "         CLEANUP COMPLETED"
    echo "=========================================="
    echo ""
    echo "🧹 Cleanup Summary:"
    echo "   • Project: ${PROJECT_ID}"
    echo "   • Cloud Functions and Schedulers: Removed"
    echo "   • Monitoring Dashboards and Alerts: Removed"
    echo "   • Security Command Center Configs: Removed"
    echo "   • KMS Keys: Scheduled for destruction (30 days)"
    echo "   • Storage Buckets: Removed"
    echo "   • Pub/Sub Topics: Removed"
    echo "   • Temporary Files: Removed"
    echo ""
    echo "📋 Important Notes:"
    echo "   • KMS keys are scheduled for destruction with a 30-day delay"
    echo "   • Organization-level policies may still be active"
    echo "   • Billing will stop for most resources immediately"
    echo "   • Some logs may be retained based on retention policies"
    echo ""
    echo "📁 Log Files:"
    echo "   • Cleanup log: ${LOG_FILE}"
    echo ""
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        echo "🔗 Remaining Project:"
        echo "   • Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
        echo ""
    fi
}

# Main cleanup function
main() {
    local start_time=$(date +%s)
    
    info "Starting quantum-safe security posture cleanup..."
    
    load_configuration
    select_project
    confirm_destruction
    
    cleanup_functions
    cleanup_monitoring
    cleanup_security_center
    cleanup_pubsub
    cleanup_storage
    cleanup_kms
    cleanup_temp_files
    
    # Option to delete entire project
    delete_project
    
    validate_cleanup
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    success "Cleanup completed successfully in ${duration} seconds"
    display_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi