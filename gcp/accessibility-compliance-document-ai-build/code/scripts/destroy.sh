#!/bin/bash

# Accessibility Compliance with Document AI and Build - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="accessibility_compliance_destroy_$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/processor-config.env"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup script encountered an error. Check ${LOG_FILE} for details."
    log_warning "Some resources may not have been deleted. Please check manually."
    exit 1
}

trap cleanup_on_error ERR

# Load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "Cannot proceed with cleanup without deployment configuration."
        exit 1
    fi
    
    # Source the configuration file
    set -a  # Export all variables
    source "${CONFIG_FILE}"
    set +a  # Stop exporting
    
    log_info "Configuration loaded:"
    log_info "  PROJECT_ID: ${PROJECT_ID:-not set}"
    log_info "  PROCESSOR_ID: ${PROCESSOR_ID:-not set}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME:-not set}"
    log_info "  TOPIC_NAME: ${TOPIC_NAME:-not set}"
    log_info "  ORG_ID: ${ORG_ID:-not set}"
    log_info "  SOURCE_ID: ${SOURCE_ID:-not set}"
    log_info "  REGION: ${REGION:-not set}"
}

# Confirmation prompt
confirm_deletion() {
    log_warning "⚠️  This will permanently delete all accessibility compliance resources!"
    log_warning "Resources to be deleted:"
    log_warning "  - Document AI Processor: ${PROCESSOR_ID:-unknown}"
    log_warning "  - Storage Bucket: gs://${BUCKET_NAME:-unknown} (and all contents)"
    log_warning "  - Pub/Sub Topic: ${TOPIC_NAME:-unknown}"
    log_warning "  - Cloud Function: compliance-notifier"
    log_warning "  - Security Command Center Source: ${SOURCE_ID:-unknown}"
    log_warning "  - Build Triggers"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm permanent deletion: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Cleanup cancelled. Type 'DELETE' exactly to confirm."
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Set gcloud configuration
configure_gcloud() {
    log_info "Configuring gcloud for cleanup..."
    
    if [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud config set project "${PROJECT_ID}"
        log_success "✓ gcloud project set to ${PROJECT_ID}"
    else
        log_error "PROJECT_ID not found in configuration"
        exit 1
    fi
    
    if [[ -n "${REGION:-}" ]]; then
        gcloud config set compute/region "${REGION}"
        log_success "✓ gcloud region set to ${REGION}"
    fi
}

# Delete Security Command Center configurations
delete_scc_resources() {
    log_info "Deleting Security Command Center resources..."
    
    if [[ -n "${ORG_ID:-}" ]]; then
        # Delete notification configuration
        if gcloud scc notifications delete accessibility-alerts \
            --organization="${ORG_ID}" \
            --quiet 2>/dev/null; then
            log_success "✓ Security Command Center notification deleted"
        else
            log_warning "⚠ Failed to delete SCC notification (may not exist)"
        fi
        
        # Delete Security Command Center source
        if [[ -n "${SOURCE_ID:-}" ]]; then
            if gcloud scc sources delete \
                "organizations/${ORG_ID}/sources/${SOURCE_ID}" \
                --quiet 2>/dev/null; then
                log_success "✓ Security Command Center source deleted"
            else
                log_warning "⚠ Failed to delete SCC source (may not exist)"
            fi
        else
            log_warning "⚠ SOURCE_ID not found, skipping SCC source deletion"
        fi
    else
        log_warning "⚠ ORG_ID not found, skipping SCC resource deletion"
    fi
}

# Delete Cloud Build resources
delete_build_resources() {
    log_info "Deleting Cloud Build resources..."
    
    # Delete build triggers
    local trigger_ids
    trigger_ids=$(gcloud builds triggers list \
        --filter="description:accessibility" \
        --format="value(id)" 2>/dev/null || true)
    
    if [[ -n "${trigger_ids}" ]]; then
        while IFS= read -r trigger_id; do
            if [[ -n "${trigger_id}" ]]; then
                if gcloud builds triggers delete "${trigger_id}" --quiet 2>/dev/null; then
                    log_success "✓ Build trigger deleted: ${trigger_id}"
                else
                    log_warning "⚠ Failed to delete build trigger: ${trigger_id}"
                fi
            fi
        done <<< "${trigger_ids}"
    else
        log_warning "⚠ No accessibility build triggers found"
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if [[ -n "${REGION:-}" ]]; then
        if gcloud functions delete compliance-notifier \
            --region="${REGION}" \
            --quiet 2>/dev/null; then
            log_success "✓ Cloud Function deleted"
        else
            log_warning "⚠ Failed to delete Cloud Function (may not exist)"
        fi
    else
        log_warning "⚠ REGION not found, skipping Cloud Function deletion"
    fi
}

# Delete Document AI processor
delete_document_ai_processor() {
    log_info "Deleting Document AI processor..."
    
    if [[ -n "${PROJECT_ID:-}" && -n "${REGION:-}" && -n "${PROCESSOR_ID:-}" ]]; then
        if gcloud documentai processors delete \
            "projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}" \
            --quiet 2>/dev/null; then
            log_success "✓ Document AI processor deleted"
        else
            log_warning "⚠ Failed to delete Document AI processor (may not exist)"
        fi
    else
        log_warning "⚠ Missing processor configuration, skipping Document AI deletion"
    fi
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Removing all objects from bucket..."
            # Remove all objects and versions
            if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true; then
                log_success "✓ Bucket contents removed"
            fi
            
            # Delete the bucket
            if gsutil rb "gs://${BUCKET_NAME}" 2>/dev/null; then
                log_success "✓ Storage bucket deleted: gs://${BUCKET_NAME}"
            else
                log_warning "⚠ Failed to delete storage bucket"
            fi
        else
            log_warning "⚠ Storage bucket not found: gs://${BUCKET_NAME}"
        fi
    else
        log_warning "⚠ BUCKET_NAME not found, skipping storage deletion"
    fi
}

# Delete Pub/Sub topic
delete_pubsub_topic() {
    log_info "Deleting Pub/Sub topic..."
    
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet 2>/dev/null; then
            log_success "✓ Pub/Sub topic deleted: ${TOPIC_NAME}"
        else
            log_warning "⚠ Failed to delete Pub/Sub topic (may not exist)"
        fi
    else
        log_warning "⚠ TOPIC_NAME not found, skipping Pub/Sub deletion"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/accessibility_analyzer.py"
        "${SCRIPT_DIR}/compliance_notifier.py"
        "${SCRIPT_DIR}/cloudbuild.yaml"
        "${SCRIPT_DIR}/requirements.txt"
        "${SCRIPT_DIR}/deployment_summary.md"
        "${SCRIPT_DIR}/sample.html"
        "${SCRIPT_DIR}/dashboard.html"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "✓ Removed: $(basename "${file}")"
        fi
    done
    
    # Remove test content directory
    if [[ -d "${SCRIPT_DIR}/test-content" ]]; then
        rm -rf "${SCRIPT_DIR}/test-content"
        log_success "✓ Removed test-content directory"
    fi
    
    # Remove any accessibility report files
    find "${SCRIPT_DIR}" -name "*.accessibility.json" -delete 2>/dev/null || true
    log_success "✓ Removed accessibility report files"
}

# Verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local resources_remaining=0
    
    # Check Document AI processor
    if [[ -n "${PROJECT_ID:-}" && -n "${REGION:-}" && -n "${PROCESSOR_ID:-}" ]]; then
        if gcloud documentai processors describe \
            "projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}" \
            --quiet &>/dev/null; then
            log_warning "⚠ Document AI processor still exists"
            ((resources_remaining++))
        fi
    fi
    
    # Check storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_warning "⚠ Storage bucket still exists"
            ((resources_remaining++))
        fi
    fi
    
    # Check Pub/Sub topic
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "${TOPIC_NAME}" --quiet &>/dev/null; then
            log_warning "⚠ Pub/Sub topic still exists"
            ((resources_remaining++))
        fi
    fi
    
    # Check Cloud Function
    if [[ -n "${REGION:-}" ]]; then
        if gcloud functions describe compliance-notifier \
            --region="${REGION}" --quiet &>/dev/null; then
            log_warning "⚠ Cloud Function still exists"
            ((resources_remaining++))
        fi
    fi
    
    if [[ ${resources_remaining} -eq 0 ]]; then
        log_success "✓ All resources successfully deleted"
    else
        log_warning "⚠ ${resources_remaining} resource(s) may still exist"
        log_warning "Please check the Google Cloud Console manually"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    cat > "${SCRIPT_DIR}/cleanup_summary.md" << EOF
# Accessibility Compliance Cleanup Summary

## Cleanup Details
- **Project ID**: ${PROJECT_ID:-unknown}
- **Cleanup Date**: $(date)
- **Log File**: ${LOG_FILE}

## Resources Deleted
- Document AI Processor: ${PROCESSOR_ID:-unknown}
- Storage Bucket: gs://${BUCKET_NAME:-unknown}
- Pub/Sub Topic: ${TOPIC_NAME:-unknown}
- Security Command Center Source: ${SOURCE_ID:-unknown}
- Cloud Function: compliance-notifier
- Build Triggers: accessibility-related triggers

## Files Removed
- accessibility_analyzer.py
- compliance_notifier.py
- cloudbuild.yaml
- deployment_summary.md
- test-content directory
- Configuration files

## Next Steps
1. Verify all resources are deleted in the Google Cloud Console
2. Check for any remaining charges in Cloud Billing
3. Remove the project entirely if no longer needed:
   \`gcloud projects delete ${PROJECT_ID:-PROJECT_ID}\`

## Notes
- Some resources may take a few minutes to be fully deleted
- IAM permissions may still exist and require manual cleanup
- Check Cloud Billing for any unexpected charges

## Manual Verification
Visit these console pages to verify deletion:
- Document AI: https://console.cloud.google.com/ai/document-ai
- Cloud Storage: https://console.cloud.google.com/storage
- Pub/Sub: https://console.cloud.google.com/cloudpubsub
- Cloud Functions: https://console.cloud.google.com/functions
- Security Command Center: https://console.cloud.google.com/security/command-center
EOF
    
    log_success "✓ Cleanup summary generated: cleanup_summary.md"
}

# Main cleanup function
main() {
    log_info "Starting Accessibility Compliance cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    load_configuration
    confirm_deletion
    configure_gcloud
    
    # Delete resources in reverse order of creation
    delete_scc_resources
    delete_build_resources
    delete_cloud_function
    delete_document_ai_processor
    delete_storage_bucket
    delete_pubsub_topic
    
    cleanup_local_files
    verify_deletion
    generate_cleanup_summary
    
    log_success "🧹 Accessibility Compliance cleanup completed!"
    log_info "Check ${SCRIPT_DIR}/cleanup_summary.md for details"
    
    # Ask about configuration file deletion
    echo
    read -p "Delete configuration file (processor-config.env)? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "${CONFIG_FILE}"
        log_success "✓ Configuration file deleted"
    else
        log_info "Configuration file preserved for reference"
    fi
}

# Handle dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log_info "DRY RUN MODE - No resources will be deleted"
    set +e  # Don't exit on errors in dry-run mode
    
    load_configuration
    
    log_info "Resources that would be deleted:"
    log_info "  - Document AI Processor: ${PROCESSOR_ID:-unknown}"
    log_info "  - Storage Bucket: gs://${BUCKET_NAME:-unknown}"
    log_info "  - Pub/Sub Topic: ${TOPIC_NAME:-unknown}"
    log_info "  - Cloud Function: compliance-notifier"
    log_info "  - Security Command Center Source: ${SOURCE_ID:-unknown}"
    log_info "  - Build Triggers: accessibility-related"
    
    log_info "To actually delete resources, run: $0"
    exit 0
fi

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi