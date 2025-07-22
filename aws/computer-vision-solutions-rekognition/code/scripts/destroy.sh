#!/bin/bash

# Destroy script for Computer Vision Solutions with Amazon Rekognition
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Computer Vision Solutions with Amazon Rekognition - Destroy Script

Usage: $0 [OPTIONS]

OPTIONS:
    -c, --config FILE      Use specific configuration file (default: deployment-config.json)
    -f, --force            Skip confirmation prompts
    -r, --region REGION    AWS region (default: current configured region)
    --bucket BUCKET        Specific S3 bucket name to delete
    --collection COLLECTION Specific collection name to delete
    --role ROLE            Specific IAM role name to delete
    --table TABLE          Specific DynamoDB table name to delete
    --dry-run              Show what would be deleted without making changes
    -h, --help             Show this help message

EXAMPLES:
    $0                               # Interactive cleanup using config file
    $0 --force                       # Skip confirmations
    $0 --dry-run                     # Preview what would be deleted
    $0 --bucket my-bucket            # Delete specific bucket only
    $0 --config my-config.json       # Use custom config file

SAFETY FEATURES:
    • Confirmation prompts for destructive actions
    • Dry-run mode to preview deletions
    • Graceful handling of missing resources
    • Detailed logging of all operations

EOF
}

# Parse command line arguments
CONFIG_FILE="deployment-config.json"
FORCE=false
DRY_RUN=false
SPECIFIC_BUCKET=""
SPECIFIC_COLLECTION=""
SPECIFIC_ROLE=""
SPECIFIC_TABLE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --bucket)
            SPECIFIC_BUCKET="$2"
            shift 2
            ;;
        --collection)
            SPECIFIC_COLLECTION="$2"
            shift 2
            ;;
        --role)
            SPECIFIC_ROLE="$2"
            shift 2
            ;;
        --table)
            SPECIFIC_TABLE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
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

# Prerequisite checks
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load configuration
load_configuration() {
    log "Loading configuration..."
    
    # Set AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            AWS_REGION="us-east-1"
        fi
    fi
    export AWS_REGION
    
    # Load from config file if it exists and no specific resources provided
    if [[ -f "$CONFIG_FILE" ]] && [[ -z "$SPECIFIC_BUCKET" && -z "$SPECIFIC_COLLECTION" && -z "$SPECIFIC_ROLE" && -z "$SPECIFIC_TABLE" ]]; then
        log "Loading configuration from $CONFIG_FILE"
        
        export BUCKET_NAME=$(jq -r '.resources.s3_bucket // empty' "$CONFIG_FILE")
        export COLLECTION_NAME=$(jq -r '.resources.face_collection // empty' "$CONFIG_FILE")
        export ROLE_NAME=$(jq -r '.resources.iam_role // empty' "$CONFIG_FILE")
        export DYNAMODB_TABLE_NAME=$(jq -r '.resources.dynamodb_table // empty' "$CONFIG_FILE")
        
        if [[ -z "$BUCKET_NAME" && -z "$COLLECTION_NAME" && -z "$ROLE_NAME" && -z "$DYNAMODB_TABLE_NAME" ]]; then
            warning "No valid resources found in configuration file"
        fi
    else
        # Use specific resource names if provided
        export BUCKET_NAME="$SPECIFIC_BUCKET"
        export COLLECTION_NAME="$SPECIFIC_COLLECTION"
        export ROLE_NAME="$SPECIFIC_ROLE"
        export DYNAMODB_TABLE_NAME="$SPECIFIC_TABLE"
        
        if [[ ! -f "$CONFIG_FILE" ]]; then
            warning "Configuration file $CONFIG_FILE not found, using command line parameters only"
        fi
    fi
    
    log "Configuration loaded:"
    [[ -n "$BUCKET_NAME" ]] && log "  S3 Bucket: $BUCKET_NAME"
    [[ -n "$COLLECTION_NAME" ]] && log "  Face Collection: $COLLECTION_NAME"
    [[ -n "$ROLE_NAME" ]] && log "  IAM Role: $ROLE_NAME"
    [[ -n "$DYNAMODB_TABLE_NAME" ]] && log "  DynamoDB Table: $DYNAMODB_TABLE_NAME"
}

# Confirm destruction
confirm_destruction() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following resources:"
    [[ -n "$BUCKET_NAME" ]] && echo "  🗑️  S3 Bucket: $BUCKET_NAME (and ALL contents)"
    [[ -n "$COLLECTION_NAME" ]] && echo "  🗑️  Face Collection: $COLLECTION_NAME (and ALL indexed faces)"
    [[ -n "$ROLE_NAME" ]] && echo "  🗑️  IAM Role: $ROLE_NAME"
    [[ -n "$DYNAMODB_TABLE_NAME" ]] && echo "  🗑️  DynamoDB Table: $DYNAMODB_TABLE_NAME (and ALL data)"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Check what resources exist
check_existing_resources() {
    log "Checking which resources exist..."
    
    BUCKET_EXISTS=false
    COLLECTION_EXISTS=false
    ROLE_EXISTS=false
    TABLE_EXISTS=false
    
    # Check S3 bucket
    if [[ -n "$BUCKET_NAME" ]] && aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        BUCKET_EXISTS=true
        log "✅ S3 bucket exists: $BUCKET_NAME"
    fi
    
    # Check Rekognition collection
    if [[ -n "$COLLECTION_NAME" ]] && aws rekognition describe-collection --collection-id "$COLLECTION_NAME" &> /dev/null; then
        COLLECTION_EXISTS=true
        log "✅ Rekognition collection exists: $COLLECTION_NAME"
    fi
    
    # Check IAM role
    if [[ -n "$ROLE_NAME" ]] && aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        ROLE_EXISTS=true
        log "✅ IAM role exists: $ROLE_NAME"
    fi
    
    # Check DynamoDB table
    if [[ -n "$DYNAMODB_TABLE_NAME" ]] && aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" &> /dev/null; then
        TABLE_EXISTS=true
        log "✅ DynamoDB table exists: $DYNAMODB_TABLE_NAME"
    fi
    
    # Summary
    TOTAL_RESOURCES=0
    [[ "$BUCKET_EXISTS" == "true" ]] && ((TOTAL_RESOURCES++))
    [[ "$COLLECTION_EXISTS" == "true" ]] && ((TOTAL_RESOURCES++))
    [[ "$ROLE_EXISTS" == "true" ]] && ((TOTAL_RESOURCES++))
    [[ "$TABLE_EXISTS" == "true" ]] && ((TOTAL_RESOURCES++))
    
    if [[ $TOTAL_RESOURCES -eq 0 ]]; then
        log "No resources found to delete"
        exit 0
    fi
    
    log "Found $TOTAL_RESOURCES resource(s) to delete"
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    if [[ "$BUCKET_EXISTS" != "true" ]]; then
        return
    fi
    
    log "Deleting S3 bucket: $BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete S3 bucket: $BUCKET_NAME"
        return
    fi
    
    # Delete all objects including versions
    log "Deleting all objects and versions in bucket..."
    aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$BUCKET_NAME" \
            --output json \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
        2>/dev/null || true
    
    # Delete all delete markers
    aws s3api delete-objects \
        --bucket "$BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$BUCKET_NAME" \
            --output json \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
        2>/dev/null || true
    
    # Delete the bucket
    aws s3 rb "s3://$BUCKET_NAME" --force
    
    success "S3 bucket deleted successfully"
}

# Delete Rekognition face collection
delete_face_collection() {
    if [[ "$COLLECTION_EXISTS" != "true" ]]; then
        return
    fi
    
    log "Deleting Rekognition face collection: $COLLECTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete face collection: $COLLECTION_NAME"
        return
    fi
    
    # Get face count before deletion
    FACE_COUNT=$(aws rekognition describe-collection \
        --collection-id "$COLLECTION_NAME" \
        --query 'FaceCount' --output text 2>/dev/null || echo "0")
    
    log "Collection contains $FACE_COUNT indexed faces"
    
    # Delete the collection
    aws rekognition delete-collection --collection-id "$COLLECTION_NAME"
    
    success "Face collection deleted successfully"
}

# Delete DynamoDB table
delete_dynamodb_table() {
    if [[ "$TABLE_EXISTS" != "true" ]]; then
        return
    fi
    
    log "Deleting DynamoDB table: $DYNAMODB_TABLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete DynamoDB table: $DYNAMODB_TABLE_NAME"
        return
    fi
    
    # Get item count before deletion
    ITEM_COUNT=$(aws dynamodb describe-table \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --query 'Table.ItemCount' --output text 2>/dev/null || echo "0")
    
    log "Table contains $ITEM_COUNT items"
    
    # Delete the table
    aws dynamodb delete-table --table-name "$DYNAMODB_TABLE_NAME"
    
    # Wait for table to be deleted
    log "Waiting for table deletion to complete..."
    aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE_NAME"
    
    success "DynamoDB table deleted successfully"
}

# Delete IAM role
delete_iam_role() {
    if [[ "$ROLE_EXISTS" != "true" ]]; then
        return
    fi
    
    log "Deleting IAM role: $ROLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete IAM role: $ROLE_NAME"
        return
    fi
    
    # List attached policies
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name "$ROLE_NAME" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    # Detach all managed policies
    if [[ -n "$ATTACHED_POLICIES" ]]; then
        log "Detaching managed policies..."
        for policy_arn in $ATTACHED_POLICIES; do
            aws iam detach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "$policy_arn"
        done
    fi
    
    # Delete any inline policies
    INLINE_POLICIES=$(aws iam list-role-policies \
        --role-name "$ROLE_NAME" \
        --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
    
    if [[ -n "$INLINE_POLICIES" ]]; then
        log "Deleting inline policies..."
        for policy_name in $INLINE_POLICIES; do
            aws iam delete-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-name "$policy_name"
        done
    fi
    
    # Delete the role
    aws iam delete-role --role-name "$ROLE_NAME"
    
    success "IAM role deleted successfully"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up local files"
        return
    fi
    
    # Remove generated files
    files_to_remove=(
        "comprehensive-analysis.py"
        "deployment-config.json"
        "face-detection-results.json"
        "indexed-face-results.json"
        "object-detection-results.json"
        "text-detection-results.json"
        "moderation-results.json"
        "face-search-results.json"
        "analysis-*.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    # Remove sample images directory if empty or contains only README
    if [[ -d "sample-images" ]]; then
        if [[ -z "$(ls -A sample-images/ 2>/dev/null | grep -v README.txt)" ]]; then
            rm -rf sample-images/
            log "Removed: sample-images/ directory"
        else
            warning "sample-images/ directory contains user files, not removing"
        fi
    fi
    
    success "Local files cleaned up"
}

# Show destruction summary
show_destruction_summary() {
    log "Destruction Summary:"
    echo ""
    echo "🗑️ Resources Deleted:"
    [[ "$BUCKET_EXISTS" == "true" ]] && echo "   • S3 Bucket: $BUCKET_NAME"
    [[ "$COLLECTION_EXISTS" == "true" ]] && echo "   • Face Collection: $COLLECTION_NAME"
    [[ "$ROLE_EXISTS" == "true" ]] && echo "   • IAM Role: $ROLE_NAME"
    [[ "$TABLE_EXISTS" == "true" ]] && echo "   • DynamoDB Table: $DYNAMODB_TABLE_NAME"
    echo ""
    echo "✅ All resources have been successfully removed"
    echo "💰 No further charges will be incurred for these resources"
    echo ""
}

# Main destruction function
main() {
    log "Starting Computer Vision Solutions cleanup..."
    
    check_prerequisites
    load_configuration
    check_existing_resources
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_s3_bucket
    delete_face_collection
    delete_dynamodb_table
    delete_iam_role
    cleanup_local_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "Cleanup completed successfully!"
        show_destruction_summary
    else
        log "Dry run completed. No resources were deleted."
    fi
}

# Trap errors
trap 'error "Cleanup failed! Some resources may still exist. Check the logs above for details."' ERR

# Run main function
main "$@"