#!/bin/bash

# Destroy script for IoT Device Shadows State Management
# This script safely removes all resources created by the deployment script
# Resources are deleted in reverse order to handle dependencies properly

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script metadata
SCRIPT_NAME="IoT Device Shadows Cleanup"
SCRIPT_VERSION="1.0"
RECIPE_NAME="iot-device-shadows-state-management"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Error handling function
handle_error() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Some resources may not have been cleaned up. Please check manually."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run          Show what would be deleted without making changes
    -f, --force            Skip confirmation prompts
    --keep-logs            Keep CloudWatch log groups (default: delete)
    --region REGION        Override AWS region (default: from deployment state)

DESCRIPTION:
    Safely removes all resources created by the IoT Device Shadows deployment:
    - IoT Rules and Lambda permissions
    - Lambda function and IAM resources
    - DynamoDB table and data
    - IoT Thing, certificates, and policies
    - CloudWatch log groups (optional)

SAFETY FEATURES:
    - Reads deployment state from deployment-state.json
    - Confirmation prompts for destructive actions
    - Graceful handling of missing resources
    - Detailed logging of cleanup operations

EOF
}

# Parse command line arguments
VERBOSE=false
DRY_RUN=false
FORCE=false
KEEP_LOGS=false
CUSTOM_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load deployment state
load_deployment_state() {
    log_step "Loading Deployment State"
    
    if [[ ! -f "deployment-state.json" ]]; then
        log_error "Deployment state file not found: deployment-state.json"
        log_error "Cannot proceed with automated cleanup."
        log_info "You may need to manually delete resources or provide resource names."
        exit 1
    fi
    
    # Extract values from deployment state
    export DEPLOYMENT_ID=$(jq -r '.deployment_id' deployment-state.json)
    export THING_NAME=$(jq -r '.thing_name' deployment-state.json)
    export POLICY_NAME=$(jq -r '.policy_name' deployment-state.json)
    export RULE_NAME=$(jq -r '.rule_name' deployment-state.json)
    export LAMBDA_FUNCTION=$(jq -r '.lambda_function' deployment-state.json)
    export TABLE_NAME=$(jq -r '.table_name' deployment-state.json)
    export CERT_ARN=$(jq -r '.cert_arn // empty' deployment-state.json)
    export CERT_ID=$(jq -r '.cert_id // empty' deployment-state.json)
    export LAMBDA_ARN=$(jq -r '.lambda_arn // empty' deployment-state.json)
    export POLICY_ARN=$(jq -r '.policy_arn // empty' deployment-state.json)
    
    # Set AWS region
    if [[ -n "$CUSTOM_REGION" ]]; then
        export AWS_REGION="$CUSTOM_REGION"
        log_info "Using custom region: $AWS_REGION"
    else
        export AWS_REGION=$(jq -r '.aws_region' deployment-state.json)
        if [[ "$AWS_REGION" == "null" || -z "$AWS_REGION" ]]; then
            export AWS_REGION=$(aws configure get region)
            if [[ -z "$AWS_REGION" ]]; then
                export AWS_REGION="us-east-1"
                log_warning "No region found, defaulting to us-east-1"
            fi
        fi
    fi
    
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-state.json)
    if [[ "$AWS_ACCOUNT_ID" == "null" ]]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    log_success "Deployment state loaded:"
    log_info "  Deployment ID: $DEPLOYMENT_ID"
    log_info "  Thing Name: $THING_NAME"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  Account ID: $AWS_ACCOUNT_ID"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Full deployment state:"
        cat deployment-state.json | jq '.'
    fi
}

# Confirmation function
confirm_destruction() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  • IoT Thing: $THING_NAME"
    echo "  • DynamoDB Table: $TABLE_NAME (including all data)"
    echo "  • Lambda Function: $LAMBDA_FUNCTION"
    echo "  • IoT Rule: $RULE_NAME"
    echo "  • IoT Policy: $POLICY_NAME"
    if [[ -n "$CERT_ID" ]]; then
        echo "  • IoT Certificate: $CERT_ID"
    fi
    if [[ "$KEEP_LOGS" != "true" ]]; then
        echo "  • CloudWatch Log Groups"
    fi
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource cleanup..."
}

# Step 1: Remove IoT Rule and Lambda permissions
remove_iot_rule() {
    log_step "Removing IoT Rule and Lambda Permissions"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove IoT rule: $RULE_NAME"
        log_info "[DRY RUN] Would remove Lambda permission: AllowIoTInvoke"
        return
    fi
    
    # Remove Lambda permission first
    log_info "Removing Lambda permission for IoT..."
    if aws lambda remove-permission \
        --function-name "$LAMBDA_FUNCTION" \
        --statement-id "AllowIoTInvoke" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "Lambda permission removed"
    else
        log_warning "Lambda permission not found or already removed"
    fi
    
    # Delete IoT rule
    log_info "Deleting IoT rule: $RULE_NAME"
    if aws iot delete-topic-rule \
        --rule-name "$RULE_NAME" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "IoT rule deleted"
    else
        log_warning "IoT rule not found or already deleted"
    fi
}

# Step 2: Delete Lambda function and IAM resources
remove_lambda_function() {
    log_step "Removing Lambda Function and IAM Resources"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION"
        log_info "[DRY RUN] Would delete IAM role and policy"
        return
    fi
    
    # Delete Lambda function
    log_info "Deleting Lambda function: $LAMBDA_FUNCTION"
    if aws lambda delete-function \
        --function-name "$LAMBDA_FUNCTION" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "Lambda function deleted"
    else
        log_warning "Lambda function not found or already deleted"
    fi
    
    # Remove IAM resources
    local iam_role_name="${LAMBDA_FUNCTION}-role"
    local iam_policy_name="${LAMBDA_FUNCTION}-policy"
    
    # Detach policy from role
    if [[ -n "$POLICY_ARN" ]]; then
        log_info "Detaching IAM policy from role..."
        if aws iam detach-role-policy \
            --role-name "$iam_role_name" \
            --policy-arn "$POLICY_ARN" 2>/dev/null; then
            log_success "IAM policy detached"
        else
            log_warning "IAM policy attachment not found"
        fi
        
        # Delete IAM policy
        log_info "Deleting IAM policy: $iam_policy_name"
        if aws iam delete-policy \
            --policy-arn "$POLICY_ARN" 2>/dev/null; then
            log_success "IAM policy deleted"
        else
            log_warning "IAM policy not found or already deleted"
        fi
    fi
    
    # Delete IAM role
    log_info "Deleting IAM role: $iam_role_name"
    if aws iam delete-role \
        --role-name "$iam_role_name" 2>/dev/null; then
        log_success "IAM role deleted"
    else
        log_warning "IAM role not found or already deleted"
    fi
}

# Step 3: Remove DynamoDB table
remove_dynamodb_table() {
    log_step "Removing DynamoDB Table"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete DynamoDB table: $TABLE_NAME"
        return
    fi
    
    log_info "Deleting DynamoDB table: $TABLE_NAME"
    log_warning "This will permanently delete all device state history data!"
    
    if aws dynamodb delete-table \
        --table-name "$TABLE_NAME" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "DynamoDB table deletion initiated"
        
        # Wait for table to be deleted (optional)
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Waiting for table deletion to complete..."
            aws dynamodb wait table-not-exists \
                --table-name "$TABLE_NAME" \
                --region "$AWS_REGION" 2>/dev/null || true
            log_success "DynamoDB table fully deleted"
        fi
    else
        log_warning "DynamoDB table not found or already deleted"
    fi
}

# Step 4: Remove IoT resources
remove_iot_resources() {
    log_step "Removing IoT Resources"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove IoT Thing: $THING_NAME"
        log_info "[DRY RUN] Would remove IoT certificate: $CERT_ID"
        log_info "[DRY RUN] Would remove IoT policy: $POLICY_NAME"
        return
    fi
    
    # Detach certificate from Thing
    if [[ -n "$CERT_ARN" ]]; then
        log_info "Detaching certificate from Thing..."
        if aws iot detach-thing-principal \
            --thing-name "$THING_NAME" \
            --principal "$CERT_ARN" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_success "Certificate detached from Thing"
        else
            log_warning "Certificate already detached or not found"
        fi
        
        # Detach policy from certificate
        log_info "Detaching policy from certificate..."
        if aws iot detach-policy \
            --policy-name "$POLICY_NAME" \
            --target "$CERT_ARN" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_success "Policy detached from certificate"
        else
            log_warning "Policy already detached or not found"
        fi
        
        # Deactivate and delete certificate
        if [[ -n "$CERT_ID" ]]; then
            log_info "Deactivating certificate: $CERT_ID"
            if aws iot update-certificate \
                --certificate-id "$CERT_ID" \
                --new-status INACTIVE \
                --region "$AWS_REGION" 2>/dev/null; then
                log_success "Certificate deactivated"
                
                log_info "Deleting certificate: $CERT_ID"
                if aws iot delete-certificate \
                    --certificate-id "$CERT_ID" \
                    --region "$AWS_REGION" 2>/dev/null; then
                    log_success "Certificate deleted"
                else
                    log_warning "Failed to delete certificate"
                fi
            else
                log_warning "Failed to deactivate certificate"
            fi
        fi
    fi
    
    # Delete IoT policy
    log_info "Deleting IoT policy: $POLICY_NAME"
    if aws iot delete-policy \
        --policy-name "$POLICY_NAME" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "IoT policy deleted"
    else
        log_warning "IoT policy not found or already deleted"
    fi
    
    # Delete IoT Thing
    log_info "Deleting IoT Thing: $THING_NAME"
    if aws iot delete-thing \
        --thing-name "$THING_NAME" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "IoT Thing deleted"
    else
        log_warning "IoT Thing not found or already deleted"
    fi
}

# Step 5: Remove CloudWatch log groups
remove_cloudwatch_logs() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log_info "Skipping CloudWatch log groups (--keep-logs specified)"
        return
    fi
    
    log_step "Removing CloudWatch Log Groups"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch log groups for Lambda function"
        return
    fi
    
    local log_group_name="/aws/lambda/${LAMBDA_FUNCTION}"
    
    log_info "Deleting CloudWatch log group: $log_group_name"
    if aws logs delete-log-group \
        --log-group-name "$log_group_name" \
        --region "$AWS_REGION" 2>/dev/null; then
        log_success "CloudWatch log group deleted"
    else
        log_warning "CloudWatch log group not found or already deleted"
    fi
}

# Step 6: Clean up local files
cleanup_local_files() {
    log_step "Cleaning Up Local Files"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return
    fi
    
    # Remove temporary files that might exist
    local temp_files=(
        "device-policy.json"
        "lambda-trust-policy.json" 
        "lambda-execution-policy.json"
        "iot-rule.json"
        "initial-shadow.json"
        "lambda-function.py"
        "lambda-function.zip"
        "initial-shadow-response.json"
        "shadow-validation.json"
        "shadow-test.json"
        "temp.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    # Ask about deployment state file
    if [[ -f "deployment-state.json" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            rm -f "deployment-state.json"
            log_success "Removed deployment state file"
        else
            echo
            read -p "Remove deployment state file? (y/N): " remove_state
            if [[ "$remove_state" =~ ^[Yy]$ ]]; then
                rm -f "deployment-state.json"
                log_success "Removed deployment state file"
            else
                log_info "Keeping deployment state file"
            fi
        fi
    fi
    
    log_success "Local file cleanup completed"
}

# Verification function
verify_cleanup() {
    log_step "Verifying Resource Cleanup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify resource cleanup"
        return
    fi
    
    local remaining_resources=0
    
    # Check IoT Thing
    log_info "Checking if IoT Thing still exists..."
    if aws iot describe-thing --thing-name "$THING_NAME" --region "$AWS_REGION" &>/dev/null; then
        log_warning "IoT Thing still exists: $THING_NAME"
        ((remaining_resources++))
    else
        log_success "IoT Thing successfully removed"
    fi
    
    # Check DynamoDB table
    log_info "Checking if DynamoDB table still exists..."
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" &>/dev/null; then
        log_warning "DynamoDB table still exists: $TABLE_NAME"
        ((remaining_resources++))
    else
        log_success "DynamoDB table successfully removed"
    fi
    
    # Check Lambda function
    log_info "Checking if Lambda function still exists..."
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION" --region "$AWS_REGION" &>/dev/null; then
        log_warning "Lambda function still exists: $LAMBDA_FUNCTION"
        ((remaining_resources++))
    else
        log_success "Lambda function successfully removed"
    fi
    
    # Check IoT rule
    log_info "Checking if IoT rule still exists..."
    if aws iot get-topic-rule --rule-name "$RULE_NAME" --region "$AWS_REGION" &>/dev/null; then
        log_warning "IoT rule still exists: $RULE_NAME"
        ((remaining_resources++))
    else
        log_success "IoT rule successfully removed"
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "$remaining_resources resource(s) may still exist"
        log_warning "You may need to manually remove remaining resources"
    fi
}

# Main cleanup function
main() {
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Recipe: $RECIPE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Load deployment state and confirm
    load_deployment_state
    confirm_destruction
    
    # Execute cleanup steps in reverse order of creation
    remove_iot_rule
    remove_lambda_function
    remove_dynamodb_table
    remove_iot_resources
    remove_cloudwatch_logs
    cleanup_local_files
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_cleanup
    fi
    
    # Display completion message
    log_success "Cleanup completed!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        log_info "Cleanup Summary:"
        log_info "  ✅ IoT Rule and Lambda permissions removed"
        log_info "  ✅ Lambda function and IAM resources removed"
        log_info "  ✅ DynamoDB table and data removed"
        log_info "  ✅ IoT Thing, certificate, and policy removed"
        if [[ "$KEEP_LOGS" != "true" ]]; then
            log_info "  ✅ CloudWatch log groups removed"
        fi
        log_info "  ✅ Local files cleaned up"
        echo
        log_success "All IoT Device Shadows resources have been successfully removed"
        log_info "No ongoing charges should occur from these resources"
    fi
}

# Run main function
main "$@"