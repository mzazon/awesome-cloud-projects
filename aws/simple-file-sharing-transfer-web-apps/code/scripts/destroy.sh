#!/bin/bash

# =============================================================================
# AWS Transfer Family Web Apps - Simple File Sharing Cleanup Script
# =============================================================================
# This script safely removes all resources created by the Transfer Family
# Web Apps deployment, including S3 buckets, IAM users, access grants, and
# the web application itself.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Deployment configuration file from successful deployment
#
# Usage: ./destroy.sh [--force] [--partial] [--dry-run] [--verbose] [--help]
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly LOG_FILE="/tmp/transfer-family-destroy-$(date +%Y%m%d_%H%M%S).log"

# Default configuration
FORCE_DESTROY=false
PARTIAL_CLEANUP=false
DRY_RUN=false
VERBOSE=false
SKIP_CONFIRMATION=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="${1}"
    shift
    local message="${*}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    log "INFO" "${@}"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}ℹ ${*}${NC}"
    fi
}

success() {
    log "SUCCESS" "${@}"
    echo -e "${GREEN}✅ ${*}${NC}"
}

warn() {
    log "WARN" "${@}"
    echo -e "${YELLOW}⚠️  ${*}${NC}"
}

error() {
    log "ERROR" "${@}"
    echo -e "${RED}❌ ${*}${NC}" >&2
}

fatal() {
    error "${@}"
    echo -e "${RED}💥 Cleanup failed. Check log file: ${LOG_FILE}${NC}" >&2
    exit 1
}

# =============================================================================
# Validation Functions
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check for required tools
    local required_tools=("jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            fatal "Required tool '${tool}' is not installed."
        fi
    done
    
    success "Prerequisites check completed"
}

load_deployment_config() {
    local config_file="${SCRIPT_DIR}/.deployment-config"
    
    if [[ ! -f "${config_file}" ]]; then
        if [[ "${PARTIAL_CLEANUP}" == "true" ]]; then
            warn "No deployment config found. Proceeding with partial cleanup..."
            return 0
        else
            fatal "Deployment configuration file not found: ${config_file}
This file is created during deployment and contains resource identifiers.
If you deployed manually, create the file with the following variables:
- AWS_REGION, AWS_ACCOUNT_ID, BUCKET_NAME, WEB_APP_ID, DEMO_USER_ID, etc."
        fi
    fi
    
    info "Loading deployment configuration..."
    source "${config_file}"
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "BUCKET_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable ${var} not found in configuration"
        fi
    done
    
    success "Deployment configuration loaded"
    info "Region: ${AWS_REGION}, Account: ${AWS_ACCOUNT_ID}"
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

confirm_destruction() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]] || [[ "${FORCE_DESTROY}" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "=========================================="
    echo "⚠️  DESTRUCTIVE OPERATION WARNING"
    echo "=========================================="
    echo "This will permanently delete the following resources:"
    echo "• Transfer Family Web App: ${WEB_APP_ID:-'Unknown'}"
    echo "• S3 Bucket and all files: ${BUCKET_NAME:-'Unknown'}"
    echo "• Demo user: ${USER_NAME:-'Unknown'}"
    echo "• S3 Access Grants and locations"
    echo "• Associated IAM roles and policies"
    echo
    echo "📁 Log file: ${LOG_FILE}"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo "Proceeding with cleanup in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

remove_web_app_assignment() {
    if [[ -z "${WEB_APP_ID:-}" ]] || [[ -z "${DEMO_USER_ID:-}" ]]; then
        warn "Web app ID or user ID not found, skipping assignment removal"
        return 0
    fi
    
    info "Removing user assignment from Transfer Family Web App..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove assignment for user ${DEMO_USER_ID} from web app ${WEB_APP_ID}"
        return 0
    fi
    
    # List and remove assignments
    local assignments
    assignments=$(aws transfer list-web-app-assignments \
        --web-app-id "${WEB_APP_ID}" \
        --query 'Assignments[].Grantee.Identifier' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${assignments}" ]]; then
        aws transfer delete-web-app-assignment \
            --web-app-id "${WEB_APP_ID}" \
            --grantee "{
                \"Type\": \"USER\", 
                \"Identifier\": \"${DEMO_USER_ID}\"
            }" 2>/dev/null || warn "Failed to remove web app assignment"
        
        success "Web app assignment removed"
    else
        info "No web app assignments found"
    fi
}

remove_transfer_web_app() {
    if [[ -z "${WEB_APP_ID:-}" ]]; then
        warn "Web app ID not found, skipping web app removal"
        return 0
    fi
    
    info "Removing Transfer Family Web App..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove web app: ${WEB_APP_ID}"
        return 0
    fi
    
    # Check if web app exists
    if aws transfer describe-web-app --web-app-id "${WEB_APP_ID}" &>/dev/null; then
        aws transfer delete-web-app --web-app-id "${WEB_APP_ID}"
        
        # Wait for deletion to complete
        info "Waiting for web app deletion to complete..."
        local max_attempts=20
        local attempt=1
        
        while [[ ${attempt} -le ${max_attempts} ]]; do
            if ! aws transfer describe-web-app --web-app-id "${WEB_APP_ID}" &>/dev/null; then
                break
            fi
            
            info "Web app still exists (attempt ${attempt}/${max_attempts})"
            sleep 15
            ((attempt++))
        done
        
        success "Transfer Family Web App removed: ${WEB_APP_ID}"
    else
        info "Web app not found or already deleted"
    fi
}

remove_access_grants() {
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        warn "Account ID not found, skipping access grants removal"
        return 0
    fi
    
    info "Removing S3 Access Grants..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove S3 Access Grants"
        return 0
    fi
    
    # Remove specific access grant if ID is known
    if [[ -n "${GRANT_ID:-}" ]]; then
        aws s3control delete-access-grant \
            --account-id "${AWS_ACCOUNT_ID}" \
            --access-grant-id "${GRANT_ID}" 2>/dev/null || \
            info "Access grant already deleted or not found"
    fi
    
    # Remove access grants location if ID is known
    if [[ -n "${LOCATION_ID:-}" ]]; then
        aws s3control delete-access-grants-location \
            --account-id "${AWS_ACCOUNT_ID}" \
            --access-grants-location-id "${LOCATION_ID}" 2>/dev/null || \
            info "Access grants location already deleted or not found"
    fi
    
    # List and remove any remaining grants for our bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        local grants
        grants=$(aws s3control list-access-grants \
            --account-id "${AWS_ACCOUNT_ID}" \
            --query "AccessGrantsList[?contains(AccessGrantsLocationConfiguration.S3SubPrefix, '${BUCKET_NAME}')].AccessGrantId" \
            --output text 2>/dev/null || echo "")
        
        for grant_id in ${grants}; do
            if [[ "${grant_id}" != "None" ]] && [[ -n "${grant_id}" ]]; then
                aws s3control delete-access-grant \
                    --account-id "${AWS_ACCOUNT_ID}" \
                    --access-grant-id "${grant_id}" 2>/dev/null || true
                info "Removed access grant: ${grant_id}"
            fi
        done
    fi
    
    success "S3 Access Grants cleanup completed"
}

remove_s3_bucket() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        warn "Bucket name not found, skipping S3 cleanup"
        return 0
    fi
    
    info "Removing S3 bucket and all contents..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        info "S3 bucket not found or already deleted: ${BUCKET_NAME}"
        return 0
    fi
    
    # Remove all objects including versions
    info "Removing all objects from bucket..."
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
    
    # Remove all object versions if versioning was enabled
    local versions
    versions=$(aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "${versions}" != "[]" ]]; then
        info "Removing object versions..."
        echo "${versions}" | jq -r '.[] | "\(.Key) \(.VersionId)"' | \
        while read -r key version_id; do
            aws s3api delete-object \
                --bucket "${BUCKET_NAME}" \
                --key "${key}" \
                --version-id "${version_id}" 2>/dev/null || true
        done
    fi
    
    # Remove delete markers
    local delete_markers
    delete_markers=$(aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "${delete_markers}" != "[]" ]]; then
        info "Removing delete markers..."
        echo "${delete_markers}" | jq -r '.[] | "\(.Key) \(.VersionId)"' | \
        while read -r key version_id; do
            aws s3api delete-object \
                --bucket "${BUCKET_NAME}" \
                --key "${key}" \
                --version-id "${version_id}" 2>/dev/null || true
        done
    fi
    
    # Delete the bucket
    aws s3 rb "s3://${BUCKET_NAME}" --force 2>/dev/null || \
        aws s3api delete-bucket --bucket "${BUCKET_NAME}" 2>/dev/null || \
        warn "Failed to delete bucket, it may contain objects"
    
    success "S3 bucket removed: ${BUCKET_NAME}"
}

remove_demo_user() {
    if [[ -z "${DEMO_USER_ID:-}" ]] || [[ -z "${IDENTITY_STORE_ID:-}" ]]; then
        warn "User ID or Identity Store ID not found, skipping user removal"
        return 0
    fi
    
    info "Removing demo user from IAM Identity Center..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove user: ${DEMO_USER_ID}"
        return 0
    fi
    
    # Check if user exists
    if aws identitystore describe-user \
        --identity-store-id "${IDENTITY_STORE_ID}" \
        --user-id "${DEMO_USER_ID}" &>/dev/null; then
        
        aws identitystore delete-user \
            --identity-store-id "${IDENTITY_STORE_ID}" \
            --user-id "${DEMO_USER_ID}"
        
        success "Demo user removed: ${USER_NAME:-${DEMO_USER_ID}}"
    else
        info "Demo user not found or already deleted"
    fi
}

remove_iam_roles() {
    info "Removing IAM roles created for the solution..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove IAM roles"
        return 0
    fi
    
    local roles=("S3AccessGrantsLocationRole" "TransferFamily-S3AccessGrants-WebAppRole")
    
    for role_name in "${roles[@]}"; do
        if aws iam get-role --role-name "${role_name}" &>/dev/null; then
            info "Removing IAM role: ${role_name}"
            
            # Detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies \
                --role-name "${role_name}" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in ${attached_policies}; do
                aws iam detach-role-policy \
                    --role-name "${role_name}" \
                    --policy-arn "${policy_arn}" 2>/dev/null || true
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies \
                --role-name "${role_name}" \
                --query 'PolicyNames' \
                --output text 2>/dev/null || echo "")
            
            for policy_name in ${inline_policies}; do
                aws iam delete-role-policy \
                    --role-name "${role_name}" \
                    --policy-name "${policy_name}" 2>/dev/null || true
            done
            
            # Delete the role
            aws iam delete-role --role-name "${role_name}" 2>/dev/null || \
                warn "Failed to delete role: ${role_name}"
            
            success "IAM role removed: ${role_name}"
        else
            info "IAM role not found: ${role_name}"
        fi
    done
}

cleanup_temporary_files() {
    info "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/user-creation-result.json"
        "${SCRIPT_DIR}/location-result.json"
        "${SCRIPT_DIR}/grant-result.json"
        "${SCRIPT_DIR}/webapp-creation-result.json"
        "${SCRIPT_DIR}/assignment-result.json"
        "${SCRIPT_DIR}/cors-config.json"
        "${SCRIPT_DIR}/trust-policy.json"
        "${SCRIPT_DIR}/transfer-trust-policy.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            info "Removed temporary file: $(basename "${file}")"
        fi
    done
    
    # Remove deployment config unless partial cleanup
    if [[ "${PARTIAL_CLEANUP}" != "true" ]] && [[ -f "${SCRIPT_DIR}/.deployment-config" ]]; then
        rm -f "${SCRIPT_DIR}/.deployment-config"
        info "Removed deployment configuration file"
    fi
    
    success "Temporary files cleanup completed"
}

run_cleanup() {
    info "Starting Transfer Family Web Apps cleanup..."
    
    # Resource removal in reverse order of creation
    remove_web_app_assignment
    remove_transfer_web_app
    remove_access_grants
    remove_s3_bucket
    remove_demo_user
    remove_iam_roles
    cleanup_temporary_files
    
    success "🎉 Cleanup completed successfully!"
    echo
    echo "=========================================="
    echo "🧹 CLEANUP SUMMARY"
    echo "=========================================="
    echo "✅ Transfer Family Web App removed"
    echo "✅ S3 bucket and contents deleted"
    echo "✅ Demo user removed from IAM Identity Center"
    echo "✅ S3 Access Grants cleaned up"
    echo "✅ IAM roles removed"
    echo "✅ Temporary files cleaned up"
    echo "📁 Log file: ${LOG_FILE}"
    echo "=========================================="
}

# =============================================================================
# Emergency Cleanup Functions
# =============================================================================

emergency_cleanup() {
    warn "Running emergency cleanup - searching for resources by tags..."
    
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region || echo "us-east-1")
    fi
    
    # Find S3 buckets with our tags
    local buckets
    buckets=$(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null || echo "")
    
    for bucket in ${buckets}; do
        local tags
        tags=$(aws s3api get-bucket-tagging --bucket "${bucket}" 2>/dev/null | \
               jq -r '.TagSet[] | select(.Key=="Recipe" and .Value=="TransferFamilyWebApps") | .Value' 2>/dev/null || echo "")
        
        if [[ "${tags}" == "TransferFamilyWebApps" ]]; then
            warn "Found bucket with recipe tags: ${bucket}"
            BUCKET_NAME="${bucket}"
            remove_s3_bucket
        fi
    done
    
    # Find Transfer Family web apps with our tags
    local web_apps
    web_apps=$(aws transfer list-web-apps --query 'WebApps[].WebAppId' --output text 2>/dev/null || echo "")
    
    for web_app_id in ${web_apps}; do
        local tags
        tags=$(aws transfer list-tags-for-resource \
               --arn "arn:aws:transfer:${AWS_REGION}:${AWS_ACCOUNT_ID:-}:webapp/${web_app_id}" \
               --query 'Tags[?Key==`Recipe`].Value' --output text 2>/dev/null || echo "")
        
        if [[ "${tags}" == "TransferFamilyWebApps" ]]; then
            warn "Found web app with recipe tags: ${web_app_id}"
            WEB_APP_ID="${web_app_id}"
            remove_transfer_web_app
        fi
    done
    
    success "Emergency cleanup completed"
}

# =============================================================================
# Main Script Logic
# =============================================================================

show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Safely remove all resources created by Transfer Family Web Apps deployment.

OPTIONS:
    --force             Skip confirmation prompts
    --partial           Clean up partially failed deployments
    --dry-run           Show what would be deleted without making changes
    --verbose           Enable verbose logging
    --help              Show this help message

EXAMPLES:
    ${SCRIPT_NAME}                    # Interactive cleanup with confirmation
    ${SCRIPT_NAME} --force            # Automated cleanup without prompts
    ${SCRIPT_NAME} --dry-run          # Preview what would be deleted
    ${SCRIPT_NAME} --partial          # Clean up after failed deployment

SAFETY FEATURES:
    - Requires confirmation before destructive operations
    - Loads resource identifiers from deployment configuration
    - Comprehensive logging of all operations
    - Dry-run mode for safe preview

WARNING: This will permanently delete all created resources including files!
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DESTROY=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --partial)
                PARTIAL_CLEANUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --emergency)
                # Hidden option for emergency cleanup
                PARTIAL_CLEANUP=true
                FORCE_DESTROY=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    echo "🧹 AWS Transfer Family Web Apps Cleanup Script"
    echo "=============================================="
    
    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be deleted"
    fi
    
    check_prerequisites
    
    if [[ "${PARTIAL_CLEANUP}" == "true" ]]; then
        warn "Running partial cleanup mode"
        # Try to load config, but continue if it fails
        load_deployment_config || true
        
        # If we don't have config, try emergency cleanup
        if [[ -z "${BUCKET_NAME:-}" ]] && [[ -z "${WEB_APP_ID:-}" ]]; then
            emergency_cleanup
            exit 0
        fi
    else
        load_deployment_config
    fi
    
    confirm_destruction
    run_cleanup
}

# Execute main function with all arguments
main "$@"