#!/bin/bash

# Destroy Secure File Sharing with AWS Transfer Family Web Apps
# This script removes all infrastructure created by the deployment

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Default configuration
DRY_RUN=false
FORCE_DESTROY=false
SKIP_CONFIRMATION=false

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Destroy Secure File Sharing with AWS Transfer Family Web Apps"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run           Show what would be destroyed without making changes"
    echo "  -f, --force             Force destruction without confirmation prompts"
    echo "  -y, --yes               Skip all confirmation prompts"
    echo "  -h, --help              Display this help message"
    echo ""
    echo "Environment Variables:"
    echo "  CONFIG_FILE             Path to deployment config file (default: .deployment-config)"
    echo ""
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DESTROY=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Load deployment configuration
load_configuration() {
    CONFIG_FILE=${CONFIG_FILE:-.deployment-config}
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warning "Configuration file not found: $CONFIG_FILE"
        log "Attempting to discover resources manually..."
        return 1
    fi
    
    log "Loading configuration from: $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "BUCKET_NAME" "ROLE_NAME" 
        "TRAIL_NAME" "SERVER_ID" "WEBAPP_ID" "USER_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            warning "Missing configuration variable: $var"
        fi
    done
    
    log "Configuration loaded successfully"
    return 0
}

# Discover resources if configuration is missing
discover_resources() {
    log "Attempting to discover resources automatically..."
    
    # Try to find resources by tags or naming patterns
    warning "Resource discovery is limited without configuration file"
    warning "Some resources may not be found and will need manual cleanup"
    
    # Look for S3 buckets with prefix
    if [[ -z "$BUCKET_NAME" ]]; then
        BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'secure-files')].Name" --output text | head -1)
        if [[ -n "$BUCKET_NAME" ]]; then
            log "Discovered S3 bucket: $BUCKET_NAME"
        fi
    fi
    
    # Look for Transfer servers
    if [[ -z "$SERVER_ID" ]]; then
        SERVER_ID=$(aws transfer list-servers --query "Servers[0].ServerId" --output text 2>/dev/null || echo "")
        if [[ -n "$SERVER_ID" && "$SERVER_ID" != "None" ]]; then
            log "Discovered Transfer server: $SERVER_ID"
        fi
    fi
    
    # Look for web apps
    if [[ -z "$WEBAPP_ID" ]]; then
        WEBAPP_ID=$(aws transfer list-web-apps --query "WebApps[0].WebAppId" --output text 2>/dev/null || echo "")
        if [[ -n "$WEBAPP_ID" && "$WEBAPP_ID" != "None" ]]; then
            log "Discovered web app: $WEBAPP_ID"
        fi
    fi
}

# Confirmation function
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "This will permanently destroy the following resources:"
    [[ -n "$BUCKET_NAME" ]] && echo "  - S3 Bucket: $BUCKET_NAME (and all contents)"
    [[ -n "$ROLE_NAME" ]] && echo "  - IAM Role: $ROLE_NAME"
    [[ -n "$TRAIL_NAME" ]] && echo "  - CloudTrail: $TRAIL_NAME"
    [[ -n "$SERVER_ID" ]] && echo "  - Transfer Server: $SERVER_ID"
    [[ -n "$WEBAPP_ID" ]] && echo "  - Web App: $WEBAPP_ID"
    [[ -n "$USER_NAME" ]] && echo "  - Transfer User: $USER_NAME"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    # Double confirmation for production-looking resources
    if [[ "$BUCKET_NAME" =~ (prod|production) ]] || [[ "$ROLE_NAME" =~ (prod|production) ]]; then
        warning "Resources appear to be production-related!"
        read -p "Type 'DESTROY' to confirm destruction of production resources: " prod_confirmation
        
        if [[ "$prod_confirmation" != "DESTROY" ]]; then
            log "Destruction cancelled - production safety check failed"
            exit 0
        fi
    fi
}

# Delete Transfer Family user
delete_transfer_user() {
    if [[ -z "$SERVER_ID" || -z "$USER_NAME" ]]; then
        warning "Missing SERVER_ID or USER_NAME, skipping user deletion"
        return 0
    fi
    
    log "Deleting Transfer Family user: $USER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Transfer user: $USER_NAME"
        return 0
    fi
    
    # Check if user exists
    if aws transfer describe-user --server-id ${SERVER_ID} --user-name ${USER_NAME} &>/dev/null; then
        aws transfer delete-user \
            --server-id ${SERVER_ID} \
            --user-name ${USER_NAME}
        success "Transfer user deleted: $USER_NAME"
    else
        log "Transfer user not found or already deleted: $USER_NAME"
    fi
}

# Delete Transfer Family web app
delete_web_app() {
    if [[ -z "$WEBAPP_ID" ]]; then
        warning "Missing WEBAPP_ID, skipping web app deletion"
        return 0
    fi
    
    log "Deleting Transfer Family web app: $WEBAPP_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete web app: $WEBAPP_ID"
        return 0
    fi
    
    # Check if web app exists
    if aws transfer describe-web-app --web-app-id ${WEBAPP_ID} &>/dev/null; then
        aws transfer delete-web-app --web-app-id ${WEBAPP_ID}
        
        log "Waiting for web app deletion to complete..."
        # Wait for deletion (with timeout)
        for i in {1..30}; do
            if ! aws transfer describe-web-app --web-app-id ${WEBAPP_ID} &>/dev/null; then
                break
            fi
            log "Waiting for web app deletion... (attempt $i/30)"
            sleep 10
        done
        
        success "Web app deleted: $WEBAPP_ID"
    else
        log "Web app not found or already deleted: $WEBAPP_ID"
    fi
}

# Delete Transfer Family server
delete_transfer_server() {
    if [[ -z "$SERVER_ID" ]]; then
        warning "Missing SERVER_ID, skipping server deletion"
        return 0
    fi
    
    log "Deleting Transfer Family server: $SERVER_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Transfer server: $SERVER_ID"
        return 0
    fi
    
    # Check if server exists
    if aws transfer describe-server --server-id ${SERVER_ID} &>/dev/null; then
        aws transfer delete-server --server-id ${SERVER_ID}
        
        log "Waiting for server deletion to complete..."
        # Wait for deletion (with timeout)
        for i in {1..30}; do
            if ! aws transfer describe-server --server-id ${SERVER_ID} &>/dev/null; then
                break
            fi
            log "Waiting for server deletion... (attempt $i/30)"
            sleep 10
        done
        
        success "Transfer server deleted: $SERVER_ID"
    else
        log "Transfer server not found or already deleted: $SERVER_ID"
    fi
}

# Delete CloudTrail
delete_cloudtrail() {
    if [[ -z "$TRAIL_NAME" ]]; then
        warning "Missing TRAIL_NAME, skipping CloudTrail deletion"
        return 0
    fi
    
    log "Deleting CloudTrail: $TRAIL_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete CloudTrail: $TRAIL_NAME"
        return 0
    fi
    
    # Check if trail exists
    if aws cloudtrail describe-trails --trail-name-list ${TRAIL_NAME} --query 'trailList[0]' --output text &>/dev/null; then
        # Stop logging first
        aws cloudtrail stop-logging --name ${TRAIL_NAME} || log "CloudTrail logging already stopped"
        
        # Delete the trail
        aws cloudtrail delete-trail --name ${TRAIL_NAME}
        success "CloudTrail deleted: $TRAIL_NAME"
    else
        log "CloudTrail not found or already deleted: $TRAIL_NAME"
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    if [[ -z "$ROLE_NAME" ]]; then
        warning "Missing ROLE_NAME, skipping IAM role deletion"
        return 0
    fi
    
    log "Deleting IAM role: $ROLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete IAM role: $ROLE_NAME"
        return 0
    fi
    
    # Check if role exists
    if aws iam get-role --role-name ${ROLE_NAME} &>/dev/null; then
        # Delete inline policies
        POLICY_NAMES=$(aws iam list-role-policies --role-name ${ROLE_NAME} --query 'PolicyNames[]' --output text)
        for policy in $POLICY_NAMES; do
            log "Deleting inline policy: $policy"
            aws iam delete-role-policy --role-name ${ROLE_NAME} --policy-name $policy
        done
        
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name ${ROLE_NAME} --query 'AttachedPolicies[].PolicyArn' --output text)
        for policy_arn in $ATTACHED_POLICIES; do
            log "Detaching managed policy: $policy_arn"
            aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn $policy_arn
        done
        
        # Delete the role
        aws iam delete-role --role-name ${ROLE_NAME}
        success "IAM role deleted: $ROLE_NAME"
    else
        log "IAM role not found or already deleted: $ROLE_NAME"
    fi
}

# Delete Identity Center test user (optional)
delete_identity_center_user() {
    if [[ -z "$IDENTITY_STORE_ID" || -z "$USER_ID" ]]; then
        log "Identity Center user information not available, skipping deletion"
        return 0
    fi
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        read -p "Delete Identity Center test user? This may affect other applications (y/N): " delete_user
        if [[ "$delete_user" != "y" && "$delete_user" != "Y" ]]; then
            log "Skipping Identity Center user deletion"
            return 0
        fi
    fi
    
    log "Deleting Identity Center user: $USER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Identity Center user: $USER_NAME"
        return 0
    fi
    
    # Delete the user
    aws identitystore delete-user \
        --identity-store-id ${IDENTITY_STORE_ID} \
        --user-id ${USER_ID} 2>/dev/null || log "Identity Center user deletion failed or user already deleted"
    
    success "Identity Center user deletion attempted"
}

# Delete S3 bucket and all contents
delete_s3_bucket() {
    if [[ -z "$BUCKET_NAME" ]]; then
        warning "Missing BUCKET_NAME, skipping S3 bucket deletion"
        return 0
    fi
    
    log "Deleting S3 bucket: $BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete S3 bucket and all contents: $BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${BUCKET_NAME} &>/dev/null; then
        # Delete all objects including versions
        log "Deleting all objects in bucket..."
        aws s3api delete-objects --bucket ${BUCKET_NAME} \
            --delete "$(aws s3api list-object-versions --bucket ${BUCKET_NAME} \
            --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
            --max-items 1000)" 2>/dev/null || true
        
        # Delete all delete markers
        aws s3api delete-objects --bucket ${BUCKET_NAME} \
            --delete "$(aws s3api list-object-versions --bucket ${BUCKET_NAME} \
            --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
            --max-items 1000)" 2>/dev/null || true
        
        # Remove all remaining objects (fallback)
        aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null || true
        
        # Delete bucket lifecycle configuration
        aws s3api delete-bucket-lifecycle --bucket ${BUCKET_NAME} 2>/dev/null || true
        
        # Delete bucket encryption
        aws s3api delete-bucket-encryption --bucket ${BUCKET_NAME} 2>/dev/null || true
        
        # Delete bucket policy if exists
        aws s3api delete-bucket-policy --bucket ${BUCKET_NAME} 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb s3://${BUCKET_NAME} --force
        success "S3 bucket deleted: $BUCKET_NAME"
    else
        log "S3 bucket not found or already deleted: $BUCKET_NAME"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove configuration files
    [[ -f ".deployment-config" ]] && rm -f .deployment-config
    [[ -f "deployment-summary.txt" ]] && rm -f deployment-summary.txt
    
    # Remove any temporary files
    rm -f /tmp/transfer-trust-policy.json
    rm -f /tmp/s3-access-policy.json
    rm -f /tmp/lifecycle-policy.json
    rm -rf /tmp/test-files
    
    success "Local files cleaned up"
}

# Verify destruction
verify_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would verify resource destruction"
        return 0
    fi
    
    log "Verifying resource destruction..."
    
    local remaining_resources=0
    
    # Check S3 bucket
    if [[ -n "$BUCKET_NAME" ]] && aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        warning "S3 bucket still exists: $BUCKET_NAME"
        ((remaining_resources++))
    fi
    
    # Check IAM role
    if [[ -n "$ROLE_NAME" ]] && aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        warning "IAM role still exists: $ROLE_NAME"
        ((remaining_resources++))
    fi
    
    # Check CloudTrail
    if [[ -n "$TRAIL_NAME" ]] && aws cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" &>/dev/null; then
        warning "CloudTrail still exists: $TRAIL_NAME"
        ((remaining_resources++))
    fi
    
    # Check Transfer server
    if [[ -n "$SERVER_ID" ]] && aws transfer describe-server --server-id "$SERVER_ID" &>/dev/null; then
        warning "Transfer server still exists: $SERVER_ID"
        ((remaining_resources++))
    fi
    
    # Check web app
    if [[ -n "$WEBAPP_ID" ]] && aws transfer describe-web-app --web-app-id "$WEBAPP_ID" &>/dev/null; then
        warning "Web app still exists: $WEBAPP_ID"
        ((remaining_resources++))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        success "All resources successfully destroyed"
    else
        warning "$remaining_resources resources may still exist and require manual cleanup"
    fi
}

# Display destruction summary
show_summary() {
    log "Destruction Summary:"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 Dry run completed - no resources were actually destroyed"
    else
        echo "🗑️  Resources destroyed:"
        [[ -n "$BUCKET_NAME" ]] && echo "  - S3 Bucket: $BUCKET_NAME"
        [[ -n "$ROLE_NAME" ]] && echo "  - IAM Role: $ROLE_NAME"
        [[ -n "$TRAIL_NAME" ]] && echo "  - CloudTrail: $TRAIL_NAME"
        [[ -n "$SERVER_ID" ]] && echo "  - Transfer Server: $SERVER_ID"
        [[ -n "$WEBAPP_ID" ]] && echo "  - Web App: $WEBAPP_ID"
        [[ -n "$USER_NAME" ]] && echo "  - Transfer User: $USER_NAME"
    fi
    echo ""
    echo "🧹 Local configuration files cleaned up"
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "✅ Secure File Sharing infrastructure destruction completed"
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Secure File Sharing with AWS Transfer Family Web Apps"
    
    # Load configuration or discover resources
    if ! load_configuration; then
        discover_resources
    fi
    
    # Show what will be destroyed and get confirmation
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_transfer_user
    delete_web_app
    delete_transfer_server
    delete_cloudtrail
    delete_iam_role
    delete_identity_center_user
    delete_s3_bucket
    cleanup_local_files
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_destruction
    fi
    
    show_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run completed successfully"
    else
        success "Destruction completed successfully!"
    fi
}

# Error handling
handle_error() {
    local line_no=$1
    error "Destruction failed at line $line_no"
    log "Some resources may still exist and require manual cleanup"
    log "Check the AWS console to verify resource states"
}

trap 'handle_error $LINENO' ERR

# Run main function
main "$@"