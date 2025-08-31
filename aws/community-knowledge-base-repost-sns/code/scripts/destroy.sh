#!/bin/bash

# Community Knowledge Base with re:Post Private and SNS - Cleanup Script
# This script removes all AWS resources created by the deployment script
# Author: AWS Recipes Generator
# Version: 1.0

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Configuration variables
DRY_RUN=false
VERBOSE=false
FORCE=false
SKIP_CONFIRMATION=false

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "${LOG_FILE}"
}

debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*${NC}" | tee -a "${LOG_FILE}"
    fi
}

# Cleanup function for script interruption
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Script interrupted or failed with exit code: $exit_code"
        error "Check the log file for details: ${LOG_FILE}"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Community Knowledge Base resources (SNS topics and subscriptions).

OPTIONS:
    -n, --dry-run                Run in dry-run mode (show what would be deleted)
    -f, --force                  Force deletion without confirmation prompts
    -y, --yes                    Skip all confirmation prompts (assume yes)
    -v, --verbose                Enable verbose logging
    -h, --help                   Show this help message

EXAMPLES:
    $0                          Interactive cleanup with confirmations
    $0 --dry-run                Show what would be deleted
    $0 --force --yes            Force cleanup without any prompts
    $0 --verbose                Cleanup with detailed logging

WARNING:
    This script will permanently delete:
    - SNS topics and all subscriptions
    - Email notification configurations
    - Generated configuration files
    
    re:Post Private instances must be deactivated manually through AWS Support.

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Load deployment configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Configuration file not found: ${CONFIG_FILE}"
        error "This script requires the configuration file created during deployment."
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    # Verify required variables are set
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "SNS_TOPIC_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required configuration variable not found: $var"
            return 1
        fi
    done
    
    debug "Configuration loaded successfully:"
    debug "  AWS_REGION: ${AWS_REGION}"
    debug "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    debug "  SNS_TOPIC_NAME: ${SNS_TOPIC_NAME}"
    debug "  TOPIC_ARN: ${TOPIC_ARN:-"Not set"}"
    
    log "Configuration loaded from: ${CONFIG_FILE}"
    return 0
}

# Check prerequisites
check_prerequisites() {
    log "Checking cleanup prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Cannot proceed with cleanup."
        return 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        return 1
    fi
    
    # Verify we're in the correct AWS account
    local current_account
    current_account=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ "${current_account}" != "${AWS_ACCOUNT_ID}" ]]; then
        error "AWS account mismatch!"
        error "Expected: ${AWS_ACCOUNT_ID}"
        error "Current:  ${current_account}"
        error "Please configure AWS CLI for the correct account."
        return 1
    fi
    
    log "Prerequisites check completed successfully"
    return 0
}

# Get confirmation from user
confirm_deletion() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]] || [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn ""
    warn "This script will permanently delete the following resources:"
    warn "  - SNS Topic: ${SNS_TOPIC_NAME}"
    warn "  - All email subscriptions associated with the topic"
    warn "  - Configuration files and deployment artifacts"
    warn ""
    warn "re:Post Private instances cannot be deleted by this script."
    warn "Contact AWS Support to deactivate your re:Post Private instance."
    warn ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ $REPLY != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    return 0
}

# List resources that will be deleted
list_resources() {
    log "Identifying resources to be deleted..."
    
    local resources_found=false
    
    # Check if SNS topic exists
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        debug "Checking SNS topic: ${TOPIC_ARN}"
        
        if aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &> /dev/null; then
            log "Found SNS topic: ${SNS_TOPIC_NAME}"
            resources_found=true
            
            # List subscriptions
            local subscriptions
            subscriptions=$(aws sns list-subscriptions-by-topic \
                --topic-arn "${TOPIC_ARN}" \
                --query 'Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint}' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${subscriptions}" ]]; then
                log "Found email subscriptions:"
                while IFS=$'\t' read -r protocol endpoint; do
                    log "  - ${protocol}: ${endpoint}"
                done <<< "${subscriptions}"
            fi
        else
            debug "SNS topic not found or already deleted: ${TOPIC_ARN}"
        fi
    else
        # Try to find topic by name if ARN is not available
        debug "Searching for SNS topic by name: ${SNS_TOPIC_NAME}"
        
        local found_arn
        found_arn=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${found_arn}" ]]; then
            export TOPIC_ARN="${found_arn}"
            log "Found SNS topic: ${SNS_TOPIC_NAME}"
            resources_found=true
        fi
    fi
    
    # Check for configuration files
    local config_files=(
        "${CONFIG_FILE}"
        "${SCRIPT_DIR}/repost-config-checklist.txt"
        "${SCRIPT_DIR}/content-creation-guide.txt"
        "${SCRIPT_DIR}/deployment-summary.txt"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "${file}" ]]; then
            log "Found configuration file: $(basename "${file}")"
            resources_found=true
        fi
    done
    
    if [[ "${resources_found}" == "false" ]]; then
        warn "No resources found to delete. Cleanup may have already been completed."
        return 1
    fi
    
    return 0
}

# Delete SNS topic and subscriptions
delete_sns_resources() {
    log "Deleting SNS topic and subscriptions..."
    
    if [[ -z "${TOPIC_ARN:-}" ]]; then
        warn "SNS topic ARN not available. Attempting to find by name..."
        
        local found_arn
        found_arn=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${found_arn}" ]]; then
            export TOPIC_ARN="${found_arn}"
            debug "Found topic ARN: ${TOPIC_ARN}"
        else
            warn "SNS topic not found: ${SNS_TOPIC_NAME}"
            return 0
        fi
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Would delete SNS topic: ${TOPIC_ARN}"
        return 0
    fi
    
    # Verify topic exists before attempting deletion
    if ! aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &> /dev/null; then
        warn "SNS topic does not exist or was already deleted: ${TOPIC_ARN}"
        return 0
    fi
    
    # Delete the topic (this automatically removes all subscriptions)
    debug "Deleting SNS topic: ${TOPIC_ARN}"
    
    if aws sns delete-topic --topic-arn "${TOPIC_ARN}" 2>/dev/null; then
        log "✅ SNS topic deleted successfully: ${SNS_TOPIC_NAME}"
        
        # Wait a moment for deletion to propagate
        sleep 2
        
        # Verify deletion
        if aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &> /dev/null; then
            warn "SNS topic still exists after deletion attempt"
            return 1
        else
            debug "SNS topic deletion verified"
        fi
    else
        error "Failed to delete SNS topic: ${TOPIC_ARN}"
        return 1
    fi
    
    return 0
}

# Clean up configuration files
cleanup_files() {
    log "Cleaning up configuration files and temporary artifacts..."
    
    local files_to_remove=(
        "${CONFIG_FILE}"
        "${SCRIPT_DIR}/repost-config-checklist.txt"
        "${SCRIPT_DIR}/content-creation-guide.txt"
        "${SCRIPT_DIR}/deployment-summary.txt"
    )
    
    local removed_count=0
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log "[DRY-RUN] Would remove file: $(basename "${file}")"
                ((removed_count++))
            else
                debug "Removing file: ${file}"
                if rm -f "${file}"; then
                    log "✅ Removed: $(basename "${file}")"
                    ((removed_count++))
                else
                    warn "Failed to remove: $(basename "${file}")"
                fi
            fi
        else
            debug "File not found (already removed): ${file}"
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        log "✅ Cleaned up ${removed_count} configuration files"
    else
        log "No configuration files found to clean up"
    fi
    
    return 0
}

# Display re:Post Private cleanup instructions
repost_cleanup_instructions() {
    log "Displaying re:Post Private cleanup instructions..."
    
    cat << 'EOF'

📦 re:Post Private Cleanup Instructions:

IMPORTANT: re:Post Private instances cannot be deleted automatically by this script.
You must contact AWS Support to deactivate your re:Post Private instance.

Steps to deactivate re:Post Private:
1. Open AWS Support Center: https://console.aws.amazon.com/support/
2. Create a new support case
3. Select "Account and billing support"
4. Request deactivation of your re:Post Private instance
5. Provide your organization details and reason for deactivation

Before deactivating, consider:
- Export valuable discussions and knowledge articles
- Save custom configurations and branding assets
- Document lessons learned and usage metrics
- Notify team members about the upcoming deactivation

Alternative: If you plan to use re:Post Private again in the future,
you can simply stop using it without deactivating. There are no
additional charges for inactive re:Post Private instances.

EOF

    return 0
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    local summary_file="${SCRIPT_DIR}/cleanup-summary.txt"
    
    cat > "${summary_file}" << EOF
Community Knowledge Base Cleanup Summary
Generated: $(date)

CLEANUP CONFIGURATION:
- AWS Region: ${AWS_REGION}
- AWS Account ID: ${AWS_ACCOUNT_ID}
- SNS Topic Name: ${SNS_TOPIC_NAME}
- SNS Topic ARN: ${TOPIC_ARN:-"Not found"}

RESOURCES CLEANED:
✅ SNS topic and all subscriptions deleted
✅ Configuration files removed
✅ Temporary artifacts cleaned up

REMAINING ACTIONS:
⚠️  re:Post Private instance must be deactivated manually
   - Contact AWS Support to request deactivation
   - Export valuable content before deactivation
   - Consider documenting lessons learned

CLEANUP COMPLETED: $(date)

EOF
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        log "✅ Cleanup summary saved to: ${summary_file}"
    else
        rm -f "${summary_file}"
        log "[DRY-RUN] Cleanup summary not saved in dry-run mode"
    fi
}

# Main cleanup function
main() {
    log "Starting Community Knowledge Base cleanup..."
    log "Script version: 1.0"
    log "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "🧪 Running in DRY-RUN mode - no resources will be deleted"
    fi
    
    # Load configuration and check prerequisites
    load_configuration || exit 1
    check_prerequisites || exit 1
    
    # List resources and get confirmation
    list_resources || {
        log "No resources found to clean up. Exiting."
        exit 0
    }
    
    confirm_deletion
    
    # Execute cleanup steps
    delete_sns_resources || {
        error "Failed to delete SNS resources"
        exit 1
    }
    
    cleanup_files || {
        warn "Some configuration files could not be removed"
    }
    
    repost_cleanup_instructions
    generate_cleanup_summary
    
    log "🎉 Community Knowledge Base cleanup completed successfully!"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        log ""
        log "REMAINING MANUAL STEPS:"
        log "1. Contact AWS Support to deactivate re:Post Private instance"
        log "2. Export any valuable content before deactivation"
        log "3. Remove this cleanup summary when no longer needed"
        log ""
    fi
}

# Run main function with all arguments
main "$@"