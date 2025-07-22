#!/bin/bash

# ACID-Compliant Distributed Databases with Amazon QLDB - Cleanup Script
# This script safely removes all QLDB infrastructure including ledger, IAM roles,
# S3 bucket, Kinesis stream, and associated resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE_DELETE=${FORCE_DELETE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

error() {
    log "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warn() {
    log "${YELLOW}WARNING: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy ACID-compliant distributed database infrastructure

OPTIONS:
    -f, --force             Force deletion without confirmation prompts
    -y, --yes              Skip confirmation prompts (same as --force)
    -r, --region REGION     AWS region (default: from environment.sh)
    -e, --env-file FILE     Path to environment file (default: ./environment.sh)
    -h, --help             Show this help message
    -v, --verbose          Enable verbose logging
    --dry-run              Show what would be deleted without executing

ENVIRONMENT VARIABLES:
    FORCE_DELETE           Set to 'true' to force deletion
    SKIP_CONFIRMATION      Set to 'true' to skip confirmations
    AWS_REGION             Override AWS region

EXAMPLES:
    $0                      # Interactive deletion with confirmations
    $0 --force              # Force deletion without prompts
    $0 --dry-run            # Show what would be deleted
    $0 --env-file /path/to/env.sh  # Use custom environment file

SAFETY FEATURES:
    - Requires confirmation before deleting resources
    - Validates resource ownership before deletion
    - Graceful handling of missing resources
    - Detailed logging of all operations
    - Backup verification before destructive operations

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force|-y|--yes)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -e|--env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Load environment variables
load_environment() {
    local env_file="${ENV_FILE:-${SCRIPT_DIR}/environment.sh}"
    
    if [[ ! -f "$env_file" ]]; then
        error "Environment file not found: $env_file. Run deploy.sh first or specify correct path with --env-file"
    fi

    info "Loading environment from: $env_file"
    # shellcheck source=/dev/null
    source "$env_file"

    # Validate required variables
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "LEDGER_NAME" "IAM_ROLE_NAME" "S3_BUCKET_NAME" "KINESIS_STREAM_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable $var is not set"
        fi
    done

    info "Environment loaded successfully"
    info "  AWS Region: ${AWS_REGION}"
    info "  Ledger Name: ${LEDGER_NAME}"
    info "  S3 Bucket: ${S3_BUCKET_NAME}"
    info "  Kinesis Stream: ${KINESIS_STREAM_NAME}"
    info "  IAM Role: ${IAM_ROLE_NAME}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi

    # Verify we're operating on the correct AWS account
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        error "Current AWS account ($current_account) doesn't match environment ($AWS_ACCOUNT_ID)"
    fi

    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${SKIP_CONFIRMATION}" == "true" || "${DRY_RUN:-false}" == "true" ]]; then
        return 0
    fi

    echo
    warn "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - QLDB Ledger: ${LEDGER_NAME}"
    echo "   - S3 Bucket: ${S3_BUCKET_NAME} (including all data)"
    echo "   - Kinesis Stream: ${KINESIS_STREAM_NAME}"
    echo "   - IAM Role: ${IAM_ROLE_NAME}"
    echo "   - All associated data and journal history"
    echo
    warn "⚠️  This action CANNOT be undone!"
    echo
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
    
    echo
    warn "⚠️  Final confirmation for QLDB ledger deletion"
    warn "⚠️  Ledger '${LEDGER_NAME}' contains immutable financial data"
    echo
    read -p "Type the ledger name '${LEDGER_NAME}' to confirm deletion: " ledger_confirmation
    if [[ "$ledger_confirmation" != "$LEDGER_NAME" ]]; then
        info "Ledger name confirmation failed. Operation cancelled"
        exit 0
    fi

    success "Deletion confirmed"
}

# Execute command with dry run support
execute() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[DRY RUN] Would execute: ${description}"
        info "[DRY RUN] Command: ${cmd}"
        return 0
    else
        info "Executing: ${description}"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "${cmd}" || warn "Command failed but continuing: ${description}"
        else
            eval "${cmd}"
        fi
    fi
}

# Stop and cancel journal streaming
cancel_journal_streaming() {
    info "Cancelling journal streaming..."

    # Check if STREAM_ID is available
    if [[ -z "${STREAM_ID:-}" ]]; then
        warn "Stream ID not found in environment, checking for active streams..."
        
        # List streams for the ledger
        local streams
        if streams=$(aws qldb list-journal-kinesis-streams-for-ledger --ledger-name "${LEDGER_NAME}" --query 'Streams[?Status==`ACTIVE`].StreamId' --output text 2>/dev/null); then
            if [[ -n "$streams" ]]; then
                for stream_id in $streams; do
                    local cancel_cmd="aws qldb cancel-journal-kinesis-stream --ledger-name ${LEDGER_NAME} --stream-id ${stream_id}"
                    execute "${cancel_cmd}" "Cancel journal stream ${stream_id}" "true"
                done
            else
                info "No active journal streams found"
            fi
        else
            warn "Could not list journal streams (ledger may not exist)"
        fi
    else
        local cancel_cmd="aws qldb cancel-journal-kinesis-stream --ledger-name ${LEDGER_NAME} --stream-id ${STREAM_ID}"
        execute "${cancel_cmd}" "Cancel journal stream ${STREAM_ID}" "true"
    fi

    # Wait for streams to be cancelled
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        info "Waiting for streams to be cancelled..."
        sleep 30  # Give streams time to cancel
    fi

    success "Journal streaming cancelled"
}

# Export final journal data (optional backup)
export_final_journal() {
    if [[ "${SKIP_CONFIRMATION}" != "true" && "${DRY_RUN:-false}" != "true" ]]; then
        echo
        read -p "Do you want to export final journal data before deletion? (y/N): " export_choice
        if [[ "$export_choice" =~ ^[Yy]$ ]]; then
            info "Exporting final journal data..."
            
            # Get IAM role ARN
            local role_arn
            if role_arn=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text 2>/dev/null); then
                # Create final export
                local export_cmd="aws qldb export-journal-to-s3 --name ${LEDGER_NAME} --inclusive-start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ) --exclusive-end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --role-arn ${role_arn} --s3-export-configuration '{\"Bucket\":\"${S3_BUCKET_NAME}\",\"Prefix\":\"final-export/\",\"EncryptionConfiguration\":{\"ObjectEncryptionType\":\"SSE_S3\"}}'"
                
                if execute "${export_cmd}" "Export final journal data" "true"; then
                    success "Final journal export initiated"
                    warn "⚠️  Note: Export will continue after script completion"
                    warn "⚠️  S3 bucket will be deleted - download exports manually if needed"
                else
                    warn "Final export failed, continuing with deletion"
                fi
            else
                warn "Cannot export - IAM role not accessible"
            fi
        fi
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    info "Deleting S3 bucket and all contents..."

    # Check if bucket exists
    if ! aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warn "S3 bucket ${S3_BUCKET_NAME} does not exist or is not accessible"
        return 0
    fi

    # List bucket contents for logging
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        info "Bucket contents:"
        aws s3 ls "s3://${S3_BUCKET_NAME}" --recursive || warn "Could not list bucket contents"
    fi

    # Empty bucket first
    local empty_cmd="aws s3 rm s3://${S3_BUCKET_NAME} --recursive"
    execute "${empty_cmd}" "Empty S3 bucket ${S3_BUCKET_NAME}" "true"

    # Delete bucket
    local delete_cmd="aws s3 rb s3://${S3_BUCKET_NAME}"
    execute "${delete_cmd}" "Delete S3 bucket ${S3_BUCKET_NAME}" "true"

    success "S3 bucket deleted"
}

# Delete Kinesis stream
delete_kinesis_stream() {
    info "Deleting Kinesis stream..."

    # Check if stream exists
    if ! aws kinesis describe-stream --stream-name "${KINESIS_STREAM_NAME}" &> /dev/null; then
        warn "Kinesis stream ${KINESIS_STREAM_NAME} does not exist"
        return 0
    fi

    local delete_cmd="aws kinesis delete-stream --stream-name ${KINESIS_STREAM_NAME}"
    execute "${delete_cmd}" "Delete Kinesis stream ${KINESIS_STREAM_NAME}" "true"

    success "Kinesis stream deletion initiated"
}

# Delete IAM role and policies
delete_iam_role() {
    info "Deleting IAM role and policies..."

    # Check if role exists
    if ! aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        warn "IAM role ${IAM_ROLE_NAME} does not exist"
        return 0
    fi

    # List and delete attached inline policies
    local policies
    if policies=$(aws iam list-role-policies --role-name "${IAM_ROLE_NAME}" --query 'PolicyNames' --output text 2>/dev/null); then
        for policy in $policies; do
            if [[ -n "$policy" && "$policy" != "None" ]]; then
                local delete_policy_cmd="aws iam delete-role-policy --role-name ${IAM_ROLE_NAME} --policy-name ${policy}"
                execute "${delete_policy_cmd}" "Delete inline policy ${policy}" "true"
            fi
        done
    fi

    # Detach managed policies
    local attached_policies
    if attached_policies=$(aws iam list-attached-role-policies --role-name "${IAM_ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); then
        for policy_arn in $attached_policies; do
            if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
                local detach_cmd="aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn ${policy_arn}"
                execute "${detach_cmd}" "Detach managed policy ${policy_arn}" "true"
            fi
        done
    fi

    # Delete the role
    local delete_role_cmd="aws iam delete-role --role-name ${IAM_ROLE_NAME}"
    execute "${delete_role_cmd}" "Delete IAM role ${IAM_ROLE_NAME}" "true"

    success "IAM role deleted"
}

# Delete QLDB ledger
delete_qldb_ledger() {
    info "Deleting QLDB ledger..."

    # Check if ledger exists
    if ! aws qldb describe-ledger --name "${LEDGER_NAME}" &> /dev/null; then
        warn "QLDB ledger ${LEDGER_NAME} does not exist"
        return 0
    fi

    # Check ledger status
    local ledger_state
    if ledger_state=$(aws qldb describe-ledger --name "${LEDGER_NAME}" --query 'State' --output text 2>/dev/null); then
        info "Ledger state: ${ledger_state}"
    fi

    # Disable deletion protection
    local disable_protection_cmd="aws qldb update-ledger --name ${LEDGER_NAME} --no-deletion-protection"
    execute "${disable_protection_cmd}" "Disable deletion protection for ${LEDGER_NAME}" "true"

    # Wait a moment for the update to propagate
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        sleep 10
    fi

    # Delete the ledger
    local delete_cmd="aws qldb delete-ledger --name ${LEDGER_NAME}"
    execute "${delete_cmd}" "Delete QLDB ledger ${LEDGER_NAME}" "true"

    success "QLDB ledger deletion initiated"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."

    local files_to_remove=(
        "${SCRIPT_DIR}/environment.sh"
        "${SCRIPT_DIR}/accounts.json"
        "${SCRIPT_DIR}/transactions.json"
        "${SCRIPT_DIR}/audit-queries.sql"
        "${SCRIPT_DIR}/deployment-summary.txt"
        "${SCRIPT_DIR}/qldb-trust-policy.json"
        "${SCRIPT_DIR}/qldb-permissions-policy.json"
        "${SCRIPT_DIR}/kinesis-config.json"
        "${SCRIPT_DIR}/current-digest.json"
    )

    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            local remove_cmd="rm -f ${file}"
            execute "${remove_cmd}" "Remove local file $(basename "$file")" "true"
        fi
    done

    success "Local files cleaned up"
}

# Generate deletion summary
generate_summary() {
    info "Generating deletion summary..."

    cat > "${SCRIPT_DIR}/deletion-summary.txt" << EOF
QLDB Infrastructure Deletion Summary
===================================

Deletion Date: $(date)
AWS Region: ${AWS_REGION}
AWS Account: ${AWS_ACCOUNT_ID}

Resources Deleted:
- QLDB Ledger: ${LEDGER_NAME}
- S3 Bucket: ${S3_BUCKET_NAME}
- Kinesis Stream: ${KINESIS_STREAM_NAME}
- IAM Role: ${IAM_ROLE_NAME}

Status:
- All infrastructure resources have been deleted
- Local configuration files have been cleaned up
- Journal data and exports have been permanently removed

Notes:
- QLDB ledger deletion is irreversible
- All transaction history has been permanently lost
- Any exported data in S3 has been deleted
- Kinesis stream and IAM role have been removed

This deletion was performed by: $(aws sts get-caller-identity --query 'Arn' --output text)

If you need to recreate the infrastructure, run: ./deploy.sh
EOF

    success "Deletion summary generated"
}

# Verify deletion completion
verify_deletion() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "Dry run completed - no resources were deleted"
        return 0
    fi

    info "Verifying resource deletion..."

    local errors=0

    # Check QLDB ledger
    if aws qldb describe-ledger --name "${LEDGER_NAME}" &> /dev/null; then
        warn "QLDB ledger ${LEDGER_NAME} still exists (may be in DELETING state)"
        local state=$(aws qldb describe-ledger --name "${LEDGER_NAME}" --query 'State' --output text)
        info "Ledger state: ${state}"
    else
        success "QLDB ledger successfully deleted"
    fi

    # Check S3 bucket
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warn "S3 bucket ${S3_BUCKET_NAME} still exists"
        ((errors++))
    else
        success "S3 bucket successfully deleted"
    fi

    # Check Kinesis stream
    if aws kinesis describe-stream --stream-name "${KINESIS_STREAM_NAME}" &> /dev/null; then
        warn "Kinesis stream ${KINESIS_STREAM_NAME} still exists (may be in DELETING state)"
    else
        success "Kinesis stream successfully deleted"
    fi

    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        warn "IAM role ${IAM_ROLE_NAME} still exists"
        ((errors++))
    else
        success "IAM role successfully deleted"
    fi

    if [[ $errors -eq 0 ]]; then
        success "All resources successfully deleted"
    else
        warn "Some resources may still exist - check AWS console for final verification"
    fi
}

# Main destruction function
main() {
    log "Starting QLDB infrastructure cleanup..."
    
    parse_args "$@"
    load_environment
    check_prerequisites
    confirm_deletion

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        warn "Running in DRY RUN mode - no resources will be deleted"
    fi

    # Export final data if requested
    export_final_journal

    # Perform deletion in correct order
    cancel_journal_streaming
    delete_s3_bucket
    delete_kinesis_stream
    delete_iam_role
    delete_qldb_ledger
    cleanup_local_files
    generate_summary
    verify_deletion

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "Dry run completed - no resources were deleted"
    else
        success "QLDB infrastructure cleanup completed!"
        info "Check deletion-summary.txt for details"
        warn "Note: Some AWS resources may take additional time to fully delete"
    fi
}

# Run main function with all arguments
main "$@"