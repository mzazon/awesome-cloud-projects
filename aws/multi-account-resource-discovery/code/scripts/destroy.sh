#!/bin/bash

# Multi-Account Resource Discovery Cleanup Script
# Removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
AWS_REGION_DEFAULT="us-east-1"
FORCE_DELETE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

# Help function
show_help() {
    cat << EOF
Multi-Account Resource Discovery Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region for cleanup (default: $AWS_REGION_DEFAULT)
    -f, --force             Force delete without confirmation prompts
    -n, --dry-run           Show what would be deleted without making changes
    -y, --yes               Skip confirmation prompts (automatic yes)
    -v, --verbose           Enable verbose logging

EXAMPLES:
    $0                           # Interactive cleanup with confirmations
    $0 -f                       # Force cleanup without prompts
    $0 --dry-run                # Preview cleanup without changes
    $0 -r eu-west-1 --yes       # Cleanup in specific region with auto-confirm

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Administrator privileges in AWS account
    - deployment-info.json file from successful deployment

WARNING:
    This script will permanently delete all resources created by the
    multi-account resource discovery solution. This action cannot be undone.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Set default region if not provided
AWS_REGION="${AWS_REGION:-$AWS_REGION_DEFAULT}"

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "$PROJECT_DIR/deployment-info.json" ]]; then
        export PROJECT_NAME=$(jq -r '.project_name' "$PROJECT_DIR/deployment-info.json")
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$PROJECT_DIR/deployment-info.json")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name' "$PROJECT_DIR/deployment-info.json")
        export CONFIG_AGGREGATOR_NAME=$(jq -r '.config_aggregator_name' "$PROJECT_DIR/deployment-info.json")
        export CONFIG_BUCKET_NAME=$(jq -r '.config_bucket_name' "$PROJECT_DIR/deployment-info.json")
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$PROJECT_DIR/deployment-info.json")
        
        log "Loaded project: $PROJECT_NAME"
        success "Deployment information loaded successfully"
    else
        warning "deployment-info.json not found. Using manual detection..."
        
        # Try to get account ID from AWS CLI
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
        
        # Ask user for project name if not available
        if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
            echo -n "Enter project name (or press Enter to search): "
            read -r PROJECT_NAME
        fi
        
        if [[ -z "$PROJECT_NAME" ]]; then
            log "Searching for multi-account discovery resources..."
            # Try to find Lambda functions with the pattern
            LAMBDA_FUNCTIONS=$(aws lambda list-functions \
                --region "$AWS_REGION" \
                --query 'Functions[?contains(FunctionName, `multi-account-discovery`)].FunctionName' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
                log "Found Lambda functions: $LAMBDA_FUNCTIONS"
                LAMBDA_FUNCTION_NAME=$(echo "$LAMBDA_FUNCTIONS" | head -1)
                PROJECT_NAME=$(echo "$LAMBDA_FUNCTION_NAME" | sed 's/-processor$//')
            fi
        fi
        
        # Set defaults if still not found
        if [[ -z "$PROJECT_NAME" ]]; then
            warning "Could not automatically detect project. Manual cleanup may be required."
            export PROJECT_NAME="multi-account-discovery"
            export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-processor"
            export CONFIG_AGGREGATOR_NAME="${PROJECT_NAME}-aggregator"
            export CONFIG_BUCKET_NAME="aws-config-bucket-${AWS_ACCOUNT_ID}-${AWS_REGION}"
        else
            export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-processor"
            export CONFIG_AGGREGATOR_NAME="${PROJECT_NAME}-aggregator"  
            export CONFIG_BUCKET_NAME="aws-config-bucket-${AWS_ACCOUNT_ID}-${AWS_REGION}"
        fi
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null && [[ -f "$PROJECT_DIR/deployment-info.json" ]]; then
        warning "jq not installed. Using fallback method for deployment info."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    success "Prerequisites check passed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "This will permanently delete ALL resources for the multi-account resource discovery solution:"
    echo "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  • Config Aggregator: $CONFIG_AGGREGATOR_NAME"
    echo "  • S3 Bucket: $CONFIG_BUCKET_NAME (and all contents)"
    echo "  • EventBridge Rules and Targets"
    echo "  • Config Rules and Configuration Recorder"
    echo "  • IAM Roles and Policies"
    echo "  • Resource Explorer Index and Views"
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    success "Deletion confirmed. Proceeding with cleanup..."
}

# Remove test resources first
remove_test_resources() {
    log "Removing test resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove any test S3 buckets created during validation"
        return 0
    fi
    
    # Look for test buckets with compliance pattern
    TEST_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `test-compliance-bucket`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$TEST_BUCKETS" ]]; then
        for bucket in $TEST_BUCKETS; do
            log "Removing test bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
            aws s3 rb "s3://$bucket" 2>/dev/null || true
        done
        success "Test resources cleaned up"
    else
        log "No test resources found"
    fi
}

# Remove EventBridge rules and targets
remove_eventbridge_resources() {
    log "Removing EventBridge rules and targets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove EventBridge rules: ${PROJECT_NAME}-config-rule, ${PROJECT_NAME}-discovery-schedule"
        return 0
    fi
    
    # List of rules to remove
    RULES=(
        "${PROJECT_NAME}-config-rule"
        "${PROJECT_NAME}-discovery-schedule"
    )
    
    for rule in "${RULES[@]}"; do
        # Remove targets first
        TARGET_IDS=$(aws events list-targets-by-rule \
            --rule "$rule" \
            --region "$AWS_REGION" \
            --query 'Targets[].Id' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$TARGET_IDS" ]]; then
            log "Removing targets for rule: $rule"
            aws events remove-targets \
                --rule "$rule" \
                --ids $TARGET_IDS \
                --region "$AWS_REGION" 2>/dev/null || warning "Failed to remove targets for $rule"
        fi
        
        # Remove the rule
        aws events delete-rule \
            --name "$rule" \
            --region "$AWS_REGION" 2>/dev/null && \
            log "Deleted EventBridge rule: $rule" || \
            warning "Failed to delete rule: $rule (may not exist)"
    done
    
    success "EventBridge resources removed"
}

# Remove Lambda function and IAM role
remove_lambda_resources() {
    log "Removing Lambda function and IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Lambda function: $LAMBDA_FUNCTION_NAME"
        log "[DRY RUN] Would remove IAM role: ${PROJECT_NAME}-lambda-role"
        return 0
    fi
    
    # Delete Lambda function
    aws lambda delete-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --region "$AWS_REGION" 2>/dev/null && \
        success "Lambda function deleted: $LAMBDA_FUNCTION_NAME" || \
        warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    
    # Remove IAM role policies and role
    ROLE_NAME="${PROJECT_NAME}-lambda-role"
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        2>/dev/null || warning "Basic execution policy already detached or role not found"
    
    # Delete inline policies
    aws iam delete-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "${PROJECT_NAME}-lambda-policy" \
        2>/dev/null || warning "Inline policy already deleted or role not found"
    
    # Delete IAM role
    aws iam delete-role \
        --role-name "$ROLE_NAME" \
        2>/dev/null && \
        success "IAM role deleted: $ROLE_NAME" || \
        warning "IAM role not found: $ROLE_NAME"
}

# Remove Config rules and aggregator
remove_config_resources() {
    log "Removing Config rules and aggregator..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Config rules and aggregator: $CONFIG_AGGREGATOR_NAME"
        return 0
    fi
    
    # Stop configuration recorder first
    aws configservice stop-configuration-recorder \
        --configuration-recorder-name "${PROJECT_NAME}-recorder" \
        --region "$AWS_REGION" 2>/dev/null || warning "Configuration recorder not found or already stopped"
    
    # Delete Config rules
    RULES=(
        "${PROJECT_NAME}-s3-bucket-public-access-prohibited"
        "${PROJECT_NAME}-ec2-security-group-attached-to-eni"
        "${PROJECT_NAME}-root-access-key-check"
        "${PROJECT_NAME}-encrypted-volumes"
    )
    
    for rule in "${RULES[@]}"; do
        aws configservice delete-config-rule \
            --config-rule-name "$rule" \
            --region "$AWS_REGION" 2>/dev/null && \
            log "Deleted Config rule: $rule" || \
            warning "Config rule not found: $rule"
    done
    
    # Delete aggregator
    aws configservice delete-configuration-aggregator \
        --configuration-aggregator-name "$CONFIG_AGGREGATOR_NAME" \
        --region "$AWS_REGION" 2>/dev/null && \
        success "Config aggregator deleted: $CONFIG_AGGREGATOR_NAME" || \
        warning "Config aggregator not found: $CONFIG_AGGREGATOR_NAME"
    
    # Delete delivery channel and configuration recorder
    aws configservice delete-delivery-channel \
        --delivery-channel-name "${PROJECT_NAME}-channel" \
        --region "$AWS_REGION" 2>/dev/null || warning "Delivery channel not found"
    
    aws configservice delete-configuration-recorder \
        --configuration-recorder-name "${PROJECT_NAME}-recorder" \
        --region "$AWS_REGION" 2>/dev/null || warning "Configuration recorder not found"
    
    success "Config resources removed"
}

# Remove Resource Explorer resources
remove_resource_explorer() {
    log "Removing Resource Explorer resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove Resource Explorer index and views"
        return 0
    fi
    
    # List and delete views first
    VIEWS=$(aws resource-explorer-2 list-views \
        --region "$AWS_REGION" \
        --query 'Views[?contains(ViewName, `organization-view`)].ViewArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$VIEWS" ]]; then
        for view_arn in $VIEWS; do
            # Get view name from ARN
            VIEW_NAME=$(echo "$view_arn" | awk -F'/' '{print $NF}')
            
            aws resource-explorer-2 delete-view \
                --view-arn "$view_arn" \
                --region "$AWS_REGION" 2>/dev/null && \
                log "Deleted Resource Explorer view: $VIEW_NAME" || \
                warning "Failed to delete view: $VIEW_NAME"
        done
    fi
    
    # Delete the index (this may take time)
    aws resource-explorer-2 delete-index \
        --region "$AWS_REGION" 2>/dev/null && \
        success "Resource Explorer index deletion initiated" || \
        warning "Resource Explorer index not found or already deleted"
    
    log "Note: Resource Explorer index deletion may take several minutes to complete"
}

# Remove S3 bucket and contents
remove_s3_resources() {
    log "Removing S3 bucket and contents..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove S3 bucket: $CONFIG_BUCKET_NAME and all contents"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET_NAME" 2>/dev/null; then
        log "Emptying S3 bucket: $CONFIG_BUCKET_NAME"
        
        # Remove all objects and versions
        aws s3 rm "s3://$CONFIG_BUCKET_NAME" --recursive 2>/dev/null || warning "Failed to empty bucket"
        
        # Remove versioned objects if versioning is enabled
        aws s3api delete-objects \
            --bucket "$CONFIG_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$CONFIG_BUCKET_NAME" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --max-keys 1000)" 2>/dev/null || true
        
        # Remove delete markers
        aws s3api delete-objects \
            --bucket "$CONFIG_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$CONFIG_BUCKET_NAME" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --max-keys 1000)" 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb "s3://$CONFIG_BUCKET_NAME" 2>/dev/null && \
            success "S3 bucket deleted: $CONFIG_BUCKET_NAME" || \
            error "Failed to delete S3 bucket: $CONFIG_BUCKET_NAME"
    else
        log "S3 bucket not found: $CONFIG_BUCKET_NAME"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove local files: deployment-info.json, lambda_function.py, etc."
        return 0
    fi
    
    # List of files to remove
    LOCAL_FILES=(
        "$PROJECT_DIR/deployment-info.json"
        "$PROJECT_DIR/lambda_function.py"
        "$PROJECT_DIR/lambda-deployment.zip"
        "$PROJECT_DIR/trust-policy.json"
        "$PROJECT_DIR/lambda-policy.json"
        "$PROJECT_DIR/config-bucket-policy.json"
        "$PROJECT_DIR/member-account-template.yaml"
    )
    
    for file in "${LOCAL_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" && log "Removed file: $(basename "$file")" || warning "Failed to remove: $(basename "$file")"
        fi
    done
    
    success "Local files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would validate that all resources have been removed"
        return 0
    fi
    
    ISSUES=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
        warning "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        ((ISSUES++))
    fi
    
    # Check Config aggregator
    if aws configservice describe-configuration-aggregators \
        --configuration-aggregator-names "$CONFIG_AGGREGATOR_NAME" \
        --region "$AWS_REGION" &>/dev/null; then
        warning "Config aggregator still exists: $CONFIG_AGGREGATOR_NAME"
        ((ISSUES++))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET_NAME" &>/dev/null; then
        warning "S3 bucket still exists: $CONFIG_BUCKET_NAME"
        ((ISSUES++))
    fi
    
    # Check EventBridge rules
    if aws events describe-rule --name "${PROJECT_NAME}-config-rule" --region "$AWS_REGION" &>/dev/null; then
        warning "EventBridge rule still exists: ${PROJECT_NAME}-config-rule"
        ((ISSUES++))
    fi
    
    if [[ $ISSUES -eq 0 ]]; then
        success "Cleanup validation passed - all resources removed"
    else
        warning "$ISSUES resources may still exist. Manual cleanup may be required."
    fi
}

# Main execution
main() {
    log "=========================================="
    log "Multi-Account Resource Discovery Cleanup"
    log "=========================================="
    log "Region: $AWS_REGION"
    log "Dry run: $DRY_RUN"
    log "Force delete: $FORCE_DELETE"
    
    check_prerequisites
    load_deployment_info
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "========== DRY RUN MODE =========="
        log "The following resources would be deleted:"
        log "1. Test resources (if any)"
        log "2. EventBridge rules and targets"
        log "3. Lambda function and IAM role"
        log "4. Config rules, aggregator, and recorder"
        log "5. Resource Explorer index and views"
        log "6. S3 bucket and all contents"
        log "7. Local temporary files"
        log "=================================="
    else
        confirm_deletion
    fi
    
    remove_test_resources
    remove_eventbridge_resources
    remove_lambda_resources
    remove_config_resources
    remove_resource_explorer
    remove_s3_resources
    cleanup_local_files
    validate_cleanup
    
    log "=========================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN COMPLETED - No resources were deleted"
    else
        success "CLEANUP COMPLETED SUCCESSFULLY!"
        log ""
        warning "Note: Resource Explorer index deletion may take several minutes to complete"
        warning "Service-linked roles were not deleted as they may be used by other services"
        log ""
        log "If you need to disable trusted access for AWS Organizations:"
        log "aws organizations disable-aws-service-access --service-principal resource-explorer-2.amazonaws.com"
        log "aws organizations disable-aws-service-access --service-principal config.amazonaws.com"
    fi
    log "=========================================="
}

# Execute main function
main "$@"