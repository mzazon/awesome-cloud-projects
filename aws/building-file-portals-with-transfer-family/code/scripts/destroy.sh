#!/bin/bash

# Destroy script for Secure Self-Service File Portals with AWS Transfer Family Web Apps
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo -e "${YELLOW}"
    echo "WARNING: This script will permanently delete all resources created by the Transfer Family Web App deployment."
    echo "This action cannot be undone and will result in:"
    echo "  - Deletion of all files in the S3 bucket"
    echo "  - Removal of the Transfer Family Web App and all access"
    echo "  - Deletion of IAM Identity Center users and access grants"
    echo "  - Removal of all IAM roles and policies"
    echo -e "${NC}"
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Please type 'DESTROY' to confirm: " -r
    if [[ $REPLY != "DESTROY" ]]; then
        log "Destruction cancelled - confirmation text did not match"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or authentication failed"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment
initialize_environment() {
    log "Initializing environment for cleanup..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Create cleanup log file
    RANDOM_SUFFIX=$(date +%s)
    export CLEANUP_LOG="/tmp/transfer-family-cleanup-${RANDOM_SUFFIX}.log"
    
    log "Environment initialized for cleanup"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Cleanup Log: $CLEANUP_LOG"
}

# Discover resources to clean up
discover_resources() {
    log "Discovering resources to clean up..."
    
    # Find Transfer Family Web Apps with our naming pattern
    export WEBAPP_IDS=$(aws transfer list-web-apps \
        --query 'WebApps[?contains(Tags[?Key==`Name`].Value, `file-portal-webapp`)].WebAppId' \
        --output text)
    
    # Find S3 buckets with our naming pattern
    export BUCKET_NAMES=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `file-portal-bucket`)].Name' \
        --output text)
    
    # Find IAM Identity Center users with our naming pattern
    if aws sso-admin list-instances --query 'Instances[0].IdentityStoreId' --output text &> /dev/null; then
        export IDC_IDENTITY_STORE_ID=$(aws sso-admin list-instances \
            --query 'Instances[0].IdentityStoreId' --output text)
        
        export USER_IDS=$(aws identitystore list-users \
            --identity-store-id ${IDC_IDENTITY_STORE_ID} \
            --query 'Users[?contains(UserName, `portal-user`)].UserId' \
            --output text)
    fi
    
    # Find IAM roles with our naming patterns
    export WEBAPP_ROLES=$(aws iam list-roles \
        --query 'Roles[?RoleName==`AWSTransferFamilyWebAppIdentityBearerRole`].RoleName' \
        --output text)
    
    export LOCATION_ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `S3AccessGrantsLocationRole`)].RoleName' \
        --output text)
    
    log "Resource discovery completed"
    info "Found Web Apps: ${WEBAPP_IDS:-none}"
    info "Found S3 Buckets: ${BUCKET_NAMES:-none}"
    info "Found IAM Users: ${USER_IDS:-none}"
    info "Found IAM Roles: ${WEBAPP_ROLES:-none} ${LOCATION_ROLES:-none}"
}

# Remove access grants
remove_access_grants() {
    log "Removing S3 Access Grants..."
    
    # List and delete access grants
    local grant_ids=$(aws s3control list-access-grants \
        --account-id ${AWS_ACCOUNT_ID} \
        --query 'AccessGrantsList[].AccessGrantId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$grant_ids" ]]; then
        for grant_id in $grant_ids; do
            if [[ "$grant_id" != "None" && -n "$grant_id" ]]; then
                info "Deleting access grant: $grant_id"
                aws s3control delete-access-grant \
                    --account-id ${AWS_ACCOUNT_ID} \
                    --access-grant-id ${grant_id} \
                    2>> "$CLEANUP_LOG" || warning "Failed to delete access grant: $grant_id"
            fi
        done
        log "Access grants deletion completed"
    else
        info "No access grants found to delete"
    fi
}

# Remove S3 Access Grants locations
remove_access_grants_locations() {
    log "Removing S3 Access Grants locations..."
    
    # List and delete access grants locations
    local location_ids=$(aws s3control list-access-grants-locations \
        --account-id ${AWS_ACCOUNT_ID} \
        --query 'AccessGrantsLocationsList[].AccessGrantsLocationId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$location_ids" ]]; then
        for location_id in $location_ids; do
            if [[ "$location_id" != "None" && -n "$location_id" ]]; then
                info "Deleting access grants location: $location_id"
                aws s3control delete-access-grants-location \
                    --account-id ${AWS_ACCOUNT_ID} \
                    --access-grants-location-id ${location_id} \
                    2>> "$CLEANUP_LOG" || warning "Failed to delete location: $location_id"
            fi
        done
        log "Access grants locations deletion completed"
    else
        info "No access grants locations found to delete"
    fi
}

# Remove Transfer Family Web Apps
remove_web_apps() {
    log "Removing Transfer Family Web Apps..."
    
    if [[ -n "${WEBAPP_IDS:-}" ]]; then
        for webapp_id in $WEBAPP_IDS; do
            if [[ "$webapp_id" != "None" && -n "$webapp_id" ]]; then
                info "Deleting Transfer Family Web App: $webapp_id"
                
                # Get app details before deletion for logging
                local webapp_name=$(aws transfer describe-web-app \
                    --web-app-id ${webapp_id} \
                    --query 'WebApp.Tags[?Key==`Name`].Value' \
                    --output text 2>/dev/null || echo "unknown")
                
                aws transfer delete-web-app \
                    --web-app-id ${webapp_id} \
                    2>> "$CLEANUP_LOG" || warning "Failed to delete web app: $webapp_id"
                
                info "Deleted web app: $webapp_name ($webapp_id)"
            fi
        done
        log "Transfer Family Web Apps deletion completed"
    else
        info "No Transfer Family Web Apps found to delete"
    fi
}

# Remove IAM Identity Center users
remove_identity_center_users() {
    log "Removing IAM Identity Center users..."
    
    if [[ -n "${USER_IDS:-}" && -n "${IDC_IDENTITY_STORE_ID:-}" ]]; then
        for user_id in $USER_IDS; do
            if [[ "$user_id" != "None" && -n "$user_id" ]]; then
                # Get username before deletion
                local username=$(aws identitystore describe-user \
                    --identity-store-id ${IDC_IDENTITY_STORE_ID} \
                    --user-id ${user_id} \
                    --query 'UserName' --output text 2>/dev/null || echo "unknown")
                
                info "Deleting IAM Identity Center user: $username ($user_id)"
                aws identitystore delete-user \
                    --identity-store-id ${IDC_IDENTITY_STORE_ID} \
                    --user-id ${user_id} \
                    2>> "$CLEANUP_LOG" || warning "Failed to delete user: $user_id"
            fi
        done
        log "IAM Identity Center users deletion completed"
    else
        info "No IAM Identity Center users found to delete"
    fi
}

# Remove S3 buckets
remove_s3_buckets() {
    log "Removing S3 buckets and contents..."
    
    if [[ -n "${BUCKET_NAMES:-}" ]]; then
        for bucket_name in $BUCKET_NAMES; do
            if [[ "$bucket_name" != "None" && -n "$bucket_name" ]]; then
                info "Processing S3 bucket: $bucket_name"
                
                # Check if bucket exists
                if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
                    # Remove all objects and versions
                    info "Removing all objects from bucket: $bucket_name"
                    aws s3 rm s3://${bucket_name} --recursive 2>> "$CLEANUP_LOG" || warning "Failed to remove some objects from $bucket_name"
                    
                    # Remove all object versions (if versioning was enabled)
                    local versions=$(aws s3api list-object-versions \
                        --bucket ${bucket_name} \
                        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                        --output text 2>/dev/null || echo "")
                    
                    if [[ -n "$versions" ]]; then
                        info "Removing object versions from bucket: $bucket_name"
                        echo "$versions" | while read -r key version_id; do
                            if [[ -n "$key" && -n "$version_id" ]]; then
                                aws s3api delete-object \
                                    --bucket ${bucket_name} \
                                    --key "$key" \
                                    --version-id "$version_id" \
                                    2>> "$CLEANUP_LOG" || true
                            fi
                        done
                    fi
                    
                    # Remove delete markers
                    local delete_markers=$(aws s3api list-object-versions \
                        --bucket ${bucket_name} \
                        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                        --output text 2>/dev/null || echo "")
                    
                    if [[ -n "$delete_markers" ]]; then
                        info "Removing delete markers from bucket: $bucket_name"
                        echo "$delete_markers" | while read -r key version_id; do
                            if [[ -n "$key" && -n "$version_id" ]]; then
                                aws s3api delete-object \
                                    --bucket ${bucket_name} \
                                    --key "$key" \
                                    --version-id "$version_id" \
                                    2>> "$CLEANUP_LOG" || true
                            fi
                        done
                    fi
                    
                    # Delete the bucket
                    info "Deleting S3 bucket: $bucket_name"
                    aws s3 rb s3://${bucket_name} 2>> "$CLEANUP_LOG" || warning "Failed to delete bucket: $bucket_name"
                else
                    info "Bucket $bucket_name does not exist or is not accessible"
                fi
            fi
        done
        log "S3 buckets deletion completed"
    else
        info "No S3 buckets found to delete"
    fi
}

# Remove IAM roles
remove_iam_roles() {
    log "Removing IAM roles..."
    
    # Remove Transfer Family Web App role
    if [[ -n "${WEBAPP_ROLES:-}" ]]; then
        for role_name in $WEBAPP_ROLES; do
            if [[ "$role_name" != "None" && -n "$role_name" ]]; then
                info "Removing IAM role: $role_name"
                
                # Detach managed policies
                local attached_policies=$(aws iam list-attached-role-policies \
                    --role-name ${role_name} \
                    --query 'AttachedPolicies[].PolicyArn' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$attached_policies" ]]; then
                    for policy_arn in $attached_policies; do
                        if [[ "$policy_arn" != "None" && -n "$policy_arn" ]]; then
                            info "Detaching policy: $policy_arn from role: $role_name"
                            aws iam detach-role-policy \
                                --role-name ${role_name} \
                                --policy-arn ${policy_arn} \
                                2>> "$CLEANUP_LOG" || warning "Failed to detach policy: $policy_arn"
                        fi
                    done
                fi
                
                # Delete the role
                aws iam delete-role --role-name ${role_name} \
                    2>> "$CLEANUP_LOG" || warning "Failed to delete role: $role_name"
            fi
        done
    fi
    
    # Remove location roles
    if [[ -n "${LOCATION_ROLES:-}" ]]; then
        for role_name in $LOCATION_ROLES; do
            if [[ "$role_name" != "None" && -n "$role_name" ]]; then
                info "Removing IAM role: $role_name"
                
                # Detach managed policies
                local attached_policies=$(aws iam list-attached-role-policies \
                    --role-name ${role_name} \
                    --query 'AttachedPolicies[].PolicyArn' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$attached_policies" ]]; then
                    for policy_arn in $attached_policies; do
                        if [[ "$policy_arn" != "None" && -n "$policy_arn" ]]; then
                            info "Detaching policy: $policy_arn from role: $role_name"
                            aws iam detach-role-policy \
                                --role-name ${role_name} \
                                --policy-arn ${policy_arn} \
                                2>> "$CLEANUP_LOG" || warning "Failed to detach policy: $policy_arn"
                        fi
                    done
                fi
                
                # Delete the role
                aws iam delete-role --role-name ${role_name} \
                    2>> "$CLEANUP_LOG" || warning "Failed to delete role: $role_name"
            fi
        done
    fi
    
    log "IAM roles deletion completed"
}

# Remove S3 Access Grants instance
remove_access_grants_instance() {
    log "Removing S3 Access Grants instance..."
    
    # Check if Access Grants instance exists
    if aws s3control get-access-grants-instance \
        --account-id ${AWS_ACCOUNT_ID} &> /dev/null; then
        
        info "Deleting S3 Access Grants instance"
        aws s3control delete-access-grants-instance \
            --account-id ${AWS_ACCOUNT_ID} \
            2>> "$CLEANUP_LOG" || warning "Failed to delete Access Grants instance"
        
        log "S3 Access Grants instance deletion completed"
    else
        info "No S3 Access Grants instance found to delete"
    fi
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check for remaining web apps
    local remaining_webapps=$(aws transfer list-web-apps \
        --query 'WebApps[?contains(Tags[?Key==`Name`].Value, `file-portal-webapp`)]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_webapps" && "$remaining_webapps" != "None" ]]; then
        warning "Some Transfer Family Web Apps may still exist"
        ((cleanup_issues++))
    fi
    
    # Check for remaining S3 buckets
    if [[ -n "${BUCKET_NAMES:-}" ]]; then
        for bucket_name in $BUCKET_NAMES; do
            if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
                warning "S3 bucket still exists: $bucket_name"
                ((cleanup_issues++))
            fi
        done
    fi
    
    # Check for remaining IAM roles
    for role_name in ${WEBAPP_ROLES:-} ${LOCATION_ROLES:-}; do
        if [[ -n "$role_name" && "$role_name" != "None" ]]; then
            if aws iam get-role --role-name "$role_name" 2>/dev/null; then
                warning "IAM role still exists: $role_name"
                ((cleanup_issues++))
            fi
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "Cleanup validation completed successfully - no issues found"
    else
        warning "Cleanup validation found $cleanup_issues potential issues - check manually"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log "Generating cleanup report..."
    
    local cleanup_report_file="cleanup-report-$(date +%s).txt"
    
    cat > "$cleanup_report_file" << EOF
Transfer Family Web App Cleanup Report
=====================================

Cleanup Date: $(date)
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Processed for Deletion:
- Transfer Family Web Apps: ${WEBAPP_IDS:-none}
- S3 Buckets: ${BUCKET_NAMES:-none}
- IAM Identity Center Users: ${USER_IDS:-none}
- IAM Roles: ${WEBAPP_ROLES:-none} ${LOCATION_ROLES:-none}

Cleanup Log: ${CLEANUP_LOG}

Next Steps:
- Review the cleanup log for any errors or warnings
- Manually verify that all resources have been removed
- Check AWS billing to ensure charges have stopped
- Review IAM Identity Center for any remaining test users

Note: 
- S3 Access Grants instance was removed (if it existed)
- All access grants and locations were removed
- CORS configurations were removed with bucket deletion

EOF

    info "Cleanup report saved to: $cleanup_report_file"
}

# Main cleanup function
main() {
    log "Starting Transfer Family Web App cleanup..."
    
    confirm_destruction
    check_prerequisites
    initialize_environment
    discover_resources
    
    # Execute cleanup in reverse order of creation
    remove_access_grants
    remove_access_grants_locations
    remove_web_apps
    remove_identity_center_users
    remove_s3_buckets
    remove_iam_roles
    remove_access_grants_instance
    
    # Validate and report
    validate_cleanup
    generate_cleanup_report
    
    log "Cleanup completed successfully!"
    info "All Transfer Family Web App resources have been removed"
    warning "Please verify billing to ensure all charges have stopped"
}

# Handle script interruption
cleanup_on_error() {
    error "Cleanup interrupted. Some resources may not have been deleted."
    warning "Check the cleanup log for details: ${CLEANUP_LOG:-/tmp/cleanup.log}"
    warning "You may need to manually remove any remaining resources"
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error INT TERM

# Run main function
main "$@"