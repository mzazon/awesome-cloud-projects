#!/bin/bash

# Destroy script for Multi-Region Active-Active Applications with AWS Global Accelerator
# This script safely removes all resources created by the deploy.sh script
# Resources are deleted in reverse order of creation to handle dependencies

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${SCRIPT_DIR}/deployment_vars.env"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Check if deployment variables exist
check_deployment_exists() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Deployment variables file not found: $ENV_FILE"
        log_error "This indicates no deployment was found or environment file was removed."
        log_info "If resources still exist, you may need to delete them manually."
        exit 1
    fi
    
    log_info "Found deployment variables file: $ENV_FILE"
}

# Load deployment variables
load_deployment_vars() {
    log_info "Loading deployment variables..."
    
    # Source the environment file
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    
    # Verify required variables are set
    local required_vars=(
        "APP_NAME"
        "TABLE_NAME"
        "ACCELERATOR_NAME"
        "LAMBDA_ROLE_NAME"
        "PRIMARY_REGION"
        "SECONDARY_REGION_EU"
        "SECONDARY_REGION_ASIA"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var is not set in $ENV_FILE"
            exit 1
        fi
    done
    
    log_success "Deployment variables loaded successfully"
    log_info "Application Name: $APP_NAME"
    log_info "Table Name: $TABLE_NAME"
    log_info "Accelerator Name: $ACCELERATOR_NAME"
}

# Check AWS CLI and authentication
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirm destruction with user
confirm_destruction() {
    log_warning "This will permanently delete all resources created by the deployment!"
    log_warning "Resources to be deleted:"
    echo "  - Global Accelerator: $ACCELERATOR_NAME"
    echo "  - DynamoDB Global Table: $TABLE_NAME (in 3 regions)"
    echo "  - Lambda functions: ${APP_NAME}-us, ${APP_NAME}-eu, ${APP_NAME}-asia"
    echo "  - Application Load Balancers in 3 regions"
    echo "  - Target Groups in 3 regions"
    echo "  - IAM Role: $LAMBDA_ROLE_NAME"
    echo ""
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi
    
    # Double confirmation for safety
    log_warning "FINAL CONFIRMATION: This action cannot be undone!"
    read -p "Type 'DELETE' to confirm resource destruction: " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Destruction cancelled - confirmation text did not match"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Delete Global Accelerator resources
delete_global_accelerator() {
    log_info "Deleting Global Accelerator resources..."
    
    if [[ -n "${ACCELERATOR_ARN:-}" ]]; then
        # Delete endpoint groups first
        for endpoint_group in "${US_ENDPOINT_GROUP_ARN:-}" "${EU_ENDPOINT_GROUP_ARN:-}" "${ASIA_ENDPOINT_GROUP_ARN:-}"; do
            if [[ -n "$endpoint_group" ]]; then
                log_info "Deleting endpoint group: $endpoint_group"
                aws globalaccelerator delete-endpoint-group \
                    --region us-west-2 \
                    --endpoint-group-arn "$endpoint_group" 2>/dev/null || \
                    log_warning "Failed to delete endpoint group: $endpoint_group (may not exist)"
            fi
        done
        
        # Delete listener
        if [[ -n "${LISTENER_ARN:-}" ]]; then
            log_info "Deleting Global Accelerator listener..."
            aws globalaccelerator delete-listener \
                --region us-west-2 \
                --listener-arn "$LISTENER_ARN" 2>/dev/null || \
                log_warning "Failed to delete listener (may not exist)"
        fi
        
        # Disable accelerator before deletion
        log_info "Disabling Global Accelerator..."
        aws globalaccelerator update-accelerator \
            --region us-west-2 \
            --accelerator-arn "$ACCELERATOR_ARN" \
            --enabled false 2>/dev/null || \
            log_warning "Failed to disable accelerator (may not exist)"
        
        # Wait for accelerator to be disabled
        log_info "Waiting for accelerator to be disabled..."
        sleep 30
        
        # Delete accelerator
        log_info "Deleting Global Accelerator..."
        aws globalaccelerator delete-accelerator \
            --region us-west-2 \
            --accelerator-arn "$ACCELERATOR_ARN" 2>/dev/null || \
            log_warning "Failed to delete accelerator (may not exist)"
        
        log_success "Global Accelerator resources deleted"
    else
        log_warning "No Global Accelerator ARN found, skipping deletion"
    fi
}

# Delete Application Load Balancers and related resources
delete_load_balancers() {
    log_info "Deleting Application Load Balancers and related resources..."
    
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION_EU" "$SECONDARY_REGION_ASIA")
    local alb_names=("${APP_NAME}-us-alb" "${APP_NAME}-eu-alb" "${APP_NAME}-asia-alb")
    local alb_arns=("${US_ALB_ARN:-}" "${EU_ALB_ARN:-}" "${ASIA_ALB_ARN:-}")
    local tg_arns=("${US_TG_ARN:-}" "${EU_TG_ARN:-}" "${ASIA_TG_ARN:-}")
    
    for i in "${!regions[@]}"; do
        local region="${regions[$i]}"
        local alb_arn="${alb_arns[$i]}"
        local tg_arn="${tg_arns[$i]}"
        
        log_info "Processing region: $region"
        
        # Delete ALB (this will also delete listeners)
        if [[ -n "$alb_arn" ]]; then
            log_info "Deleting ALB in $region..."
            aws elbv2 delete-load-balancer \
                --region "$region" \
                --load-balancer-arn "$alb_arn" 2>/dev/null || \
                log_warning "Failed to delete ALB in $region (may not exist)"
        else
            # Try to find and delete ALB by name if ARN not available
            local found_alb_arn
            found_alb_arn=$(aws elbv2 describe-load-balancers \
                --region "$region" \
                --names "${alb_names[$i]}" \
                --query 'LoadBalancers[0].LoadBalancerArn' \
                --output text 2>/dev/null || echo "None")
            
            if [[ "$found_alb_arn" != "None" && "$found_alb_arn" != "null" ]]; then
                log_info "Found ALB by name, deleting in $region..."
                aws elbv2 delete-load-balancer \
                    --region "$region" \
                    --load-balancer-arn "$found_alb_arn" 2>/dev/null || \
                    log_warning "Failed to delete found ALB in $region"
            fi
        fi
    done
    
    # Wait for ALBs to be deleted before deleting target groups
    log_info "Waiting for ALBs to be deleted..."
    sleep 60
    
    # Delete target groups
    for i in "${!regions[@]}"; do
        local region="${regions[$i]}"
        local tg_arn="${tg_arns[$i]}"
        
        if [[ -n "$tg_arn" ]]; then
            log_info "Deleting target group in $region..."
            aws elbv2 delete-target-group \
                --region "$region" \
                --target-group-arn "$tg_arn" 2>/dev/null || \
                log_warning "Failed to delete target group in $region (may not exist)"
        else
            # Try to find and delete target group by name
            local tg_name="${APP_NAME}-${region//-/}-tg"
            if [[ "$region" == "$PRIMARY_REGION" ]]; then
                tg_name="${APP_NAME}-us-tg"
            elif [[ "$region" == "$SECONDARY_REGION_EU" ]]; then
                tg_name="${APP_NAME}-eu-tg"
            elif [[ "$region" == "$SECONDARY_REGION_ASIA" ]]; then
                tg_name="${APP_NAME}-asia-tg"
            fi
            
            local found_tg_arn
            found_tg_arn=$(aws elbv2 describe-target-groups \
                --region "$region" \
                --names "$tg_name" \
                --query 'TargetGroups[0].TargetGroupArn' \
                --output text 2>/dev/null || echo "None")
            
            if [[ "$found_tg_arn" != "None" && "$found_tg_arn" != "null" ]]; then
                log_info "Found target group by name, deleting in $region..."
                aws elbv2 delete-target-group \
                    --region "$region" \
                    --target-group-arn "$found_tg_arn" 2>/dev/null || \
                    log_warning "Failed to delete found target group in $region"
            fi
        fi
    done
    
    log_success "Load balancer resources deleted"
}

# Delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION_EU" "$SECONDARY_REGION_ASIA")
    local function_names=("${APP_NAME}-us" "${APP_NAME}-eu" "${APP_NAME}-asia")
    
    for i in "${!regions[@]}"; do
        local region="${regions[$i]}"
        local function_name="${function_names[$i]}"
        
        log_info "Deleting Lambda function: $function_name in $region"
        aws lambda delete-function \
            --region "$region" \
            --function-name "$function_name" 2>/dev/null || \
            log_warning "Failed to delete Lambda function: $function_name (may not exist)"
    done
    
    log_success "Lambda functions deleted"
}

# Delete DynamoDB Global Table
delete_dynamodb_tables() {
    log_info "Deleting DynamoDB Global Table and regional tables..."
    
    # Delete Global Table first (this removes replication)
    log_info "Deleting DynamoDB Global Table..."
    aws dynamodb delete-global-table \
        --region "$PRIMARY_REGION" \
        --global-table-name "$TABLE_NAME" 2>/dev/null || \
        log_warning "Failed to delete Global Table (may not exist or may not be a Global Table)"
    
    # Wait a bit for Global Table deletion to propagate
    sleep 15
    
    # Delete individual regional tables
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION_EU" "$SECONDARY_REGION_ASIA")
    
    for region in "${regions[@]}"; do
        log_info "Deleting DynamoDB table in $region..."
        aws dynamodb delete-table \
            --region "$region" \
            --table-name "$TABLE_NAME" 2>/dev/null || \
            log_warning "Failed to delete DynamoDB table in $region (may not exist)"
    done
    
    log_success "DynamoDB tables deleted"
}

# Delete IAM role and policies
delete_iam_role() {
    log_info "Deleting IAM role and attached policies..."
    
    # Delete attached inline policies
    log_info "Deleting inline policy: DynamoDBGlobalAccess"
    aws iam delete-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name DynamoDBGlobalAccess 2>/dev/null || \
        log_warning "Failed to delete inline policy (may not exist)"
    
    # Delete the role
    log_info "Deleting IAM role: $LAMBDA_ROLE_NAME"
    aws iam delete-role \
        --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || \
        log_warning "Failed to delete IAM role (may not exist)"
    
    log_success "IAM resources deleted"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "$ENV_FILE"
        "${SCRIPT_DIR}/deployment_summary.txt"
        "${SCRIPT_DIR}/deploy.log"
        "${SCRIPT_DIR}/destroy.log"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check Global Accelerator
    if [[ -n "${ACCELERATOR_ARN:-}" ]]; then
        if aws globalaccelerator describe-accelerator \
            --region us-west-2 \
            --accelerator-arn "$ACCELERATOR_ARN" >/dev/null 2>&1; then
            log_warning "Global Accelerator still exists: $ACCELERATOR_ARN"
            verification_failed=true
        fi
    fi
    
    # Check DynamoDB tables
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION_EU" "$SECONDARY_REGION_ASIA")
    for region in "${regions[@]}"; do
        if aws dynamodb describe-table \
            --region "$region" \
            --table-name "$TABLE_NAME" >/dev/null 2>&1; then
            log_warning "DynamoDB table still exists in $region: $TABLE_NAME"
            verification_failed=true
        fi
    done
    
    # Check Lambda functions
    local function_names=("${APP_NAME}-us" "${APP_NAME}-eu" "${APP_NAME}-asia")
    for i in "${!regions[@]}"; do
        local region="${regions[$i]}"
        local function_name="${function_names[$i]}"
        
        if aws lambda get-function \
            --region "$region" \
            --function-name "$function_name" >/dev/null 2>&1; then
            log_warning "Lambda function still exists: $function_name in $region"
            verification_failed=true
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
        log_warning "IAM role still exists: $LAMBDA_ROLE_NAME"
        verification_failed=true
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        log_warning "Some resources may still exist. Check the AWS console for manual cleanup."
        log_warning "Note: Some resources may take additional time to be fully deleted."
    else
        log_success "All resources appear to be successfully deleted"
    fi
}

# Print cleanup summary
print_cleanup_summary() {
    log_success "Resource destruction completed!"
    
    cat << EOF

Cleanup Summary
===============
✅ Global Accelerator: $ACCELERATOR_NAME
✅ DynamoDB Global Table: $TABLE_NAME (all regions)
✅ Lambda functions: ${APP_NAME}-us, ${APP_NAME}-eu, ${APP_NAME}-asia
✅ Application Load Balancers (all regions)
✅ Target Groups (all regions)
✅ IAM Role: $LAMBDA_ROLE_NAME
✅ Local deployment files

All resources have been removed from your AWS account.

If you encounter any issues or see resources that weren't deleted,
please check the AWS console and delete them manually.

Cost Impact: All billable resources have been removed.
No further charges should be incurred for this deployment.
EOF
}

# Main destruction function
main() {
    log_info "Starting destruction of Multi-Region Active-Active Applications"
    log_info "Script will clean up all resources created by deploy.sh"
    
    # Run destruction steps
    check_deployment_exists
    load_deployment_vars
    check_prerequisites
    confirm_destruction
    
    log_info "Beginning resource deletion in reverse order of creation..."
    
    # Delete resources in reverse order of creation
    delete_global_accelerator
    delete_load_balancers
    delete_lambda_functions
    delete_dynamodb_tables
    delete_iam_role
    
    # Verify deletion and clean up
    verify_deletion
    cleanup_local_files
    print_cleanup_summary
    
    log_success "Destruction process completed successfully!"
}

# Run main function
main "$@"