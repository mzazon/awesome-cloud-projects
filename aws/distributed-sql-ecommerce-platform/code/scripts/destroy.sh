#!/bin/bash

# Destroy script for Global E-commerce Platform with Aurora DSQL
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    if ! command_exists jq; then
        log_error "jq is required but not installed."
        exit 1
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials are not configured."
        exit 1
    fi
    
    # Check AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log_error "AWS_REGION is not set."
            exit 1
        fi
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_success "Prerequisites validated"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo
    echo "==================== WARNING ===================="
    echo "This script will PERMANENTLY DELETE all resources"
    echo "created for the Global E-commerce Platform."
    echo
    echo "Resources that will be deleted:"
    echo "• Aurora DSQL cluster and all data"
    echo "• Lambda functions"
    echo "• API Gateway"
    echo "• CloudFront distribution"
    echo "• IAM roles and policies"
    echo
    echo "This action CANNOT be undone!"
    echo "=================================================="
    echo
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    echo
    if [[ ! "$REPLY" == "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Look for deployment info files
    local deployment_files=(ecommerce-deployment-*.json)
    
    if [[ ! -e "${deployment_files[0]}" ]]; then
        log_warning "No deployment info file found. Will attempt to discover resources by suffix."
        
        # Prompt for suffix if not provided
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            read -p "Enter the resource suffix (6 characters): " -r RANDOM_SUFFIX
            if [[ ${#RANDOM_SUFFIX} -ne 6 ]]; then
                log_error "Invalid suffix length. Expected 6 characters."
                exit 1
            fi
        fi
        
        # Set resource names based on suffix
        export DSQL_CLUSTER_NAME="ecommerce-cluster-${RANDOM_SUFFIX}"
        export LAMBDA_ROLE_NAME="ecommerce-lambda-role-${RANDOM_SUFFIX}"
        export LAMBDA_POLICY_NAME="aurora-dsql-access-${RANDOM_SUFFIX}"
        export PRODUCTS_LAMBDA_NAME="ecommerce-products-${RANDOM_SUFFIX}"
        export ORDERS_LAMBDA_NAME="ecommerce-orders-${RANDOM_SUFFIX}"
        export API_NAME="ecommerce-api-${RANDOM_SUFFIX}"
        
        log_info "Using resource suffix: $RANDOM_SUFFIX"
        return 0
    fi
    
    # Use the first deployment file found
    local deployment_file="${deployment_files[0]}"
    log_info "Found deployment file: $deployment_file"
    
    # Extract resource information
    export DSQL_CLUSTER_NAME=$(jq -r '.resources.aurora_dsql_cluster // empty' "$deployment_file")
    export LAMBDA_ROLE_NAME=$(jq -r '.resources.lambda_role // empty' "$deployment_file")
    export LAMBDA_POLICY_NAME=$(jq -r '.resources.lambda_policy // empty' "$deployment_file")
    export PRODUCTS_LAMBDA_NAME=$(jq -r '.resources.products_lambda // empty' "$deployment_file")
    export ORDERS_LAMBDA_NAME=$(jq -r '.resources.orders_lambda // empty' "$deployment_file")
    export API_ID=$(jq -r '.resources.api_gateway // empty' "$deployment_file")
    export DISTRIBUTION_ID=$(jq -r '.resources.cloudfront_distribution // empty' "$deployment_file")
    
    # Extract suffix from cluster name for fallback
    if [[ -n "$DSQL_CLUSTER_NAME" ]]; then
        export RANDOM_SUFFIX="${DSQL_CLUSTER_NAME##*-}"
    fi
    
    log_success "Deployment information loaded"
}

# Function to discover API Gateway ID if not provided
discover_api_gateway() {
    if [[ -z "${API_ID:-}" ]] && [[ -n "${API_NAME:-}" ]]; then
        log_info "Discovering API Gateway ID..."
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='${API_NAME}'].id" \
            --output text | head -n1)
        
        if [[ -n "$API_ID" && "$API_ID" != "None" ]]; then
            log_info "Found API Gateway: $API_ID"
            export API_ID
        fi
    fi
}

# Function to discover CloudFront distribution ID
discover_cloudfront_distribution() {
    if [[ -z "${DISTRIBUTION_ID:-}" ]]; then
        log_info "Discovering CloudFront distribution..."
        
        # Look for distributions with our comment pattern
        local distributions=$(aws cloudfront list-distributions \
            --query "DistributionList.Items[?Comment=='E-commerce API distribution'].Id" \
            --output text)
        
        if [[ -n "$distributions" && "$distributions" != "None" ]]; then
            export DISTRIBUTION_ID=$(echo "$distributions" | head -n1)
            log_info "Found CloudFront distribution: $DISTRIBUTION_ID"
        fi
    fi
}

# Function to delete CloudFront distribution
delete_cloudfront_distribution() {
    if [[ -z "${DISTRIBUTION_ID:-}" ]]; then
        log_warning "CloudFront distribution ID not found, skipping"
        return 0
    fi
    
    log_info "Deleting CloudFront distribution: $DISTRIBUTION_ID"
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$DISTRIBUTION_ID" >/dev/null 2>&1; then
        log_warning "CloudFront distribution $DISTRIBUTION_ID not found"
        return 0
    fi
    
    # Get current distribution config
    aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --output json > /tmp/dist-config.json
    
    local current_etag=$(jq -r '.ETag' /tmp/dist-config.json)
    local current_enabled=$(jq -r '.DistributionConfig.Enabled' /tmp/dist-config.json)
    
    # Disable distribution if it's enabled
    if [[ "$current_enabled" == "true" ]]; then
        log_info "Disabling CloudFront distribution..."
        
        # Update enabled status to false
        jq '.DistributionConfig.Enabled = false' /tmp/dist-config.json > /tmp/dist-config-disabled.json
        
        # Update distribution
        aws cloudfront update-distribution \
            --id "$DISTRIBUTION_ID" \
            --if-match "$current_etag" \
            --distribution-config file:///tmp/dist-config-disabled.json \
            --output json > /tmp/update-response.json
        
        # Wait for distribution to be deployed
        log_info "Waiting for CloudFront distribution to be disabled..."
        aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
        
        # Get new ETag after update
        current_etag=$(jq -r '.ETag' /tmp/update-response.json)
    fi
    
    # Delete distribution
    log_info "Deleting CloudFront distribution..."
    aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$current_etag"
    
    # Clean up temp files
    rm -f /tmp/dist-config.json /tmp/dist-config-disabled.json /tmp/update-response.json
    
    log_success "CloudFront distribution deleted"
}

# Function to delete API Gateway
delete_api_gateway() {
    if [[ -z "${API_ID:-}" ]]; then
        log_warning "API Gateway ID not found, skipping"
        return 0
    fi
    
    log_info "Deleting API Gateway: $API_ID"
    
    # Check if API exists
    if ! aws apigateway get-rest-api --rest-api-id "$API_ID" >/dev/null 2>&1; then
        log_warning "API Gateway $API_ID not found"
        return 0
    fi
    
    # Delete API Gateway
    aws apigateway delete-rest-api --rest-api-id "$API_ID"
    
    log_success "API Gateway deleted"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    local lambda_functions=("$PRODUCTS_LAMBDA_NAME" "$ORDERS_LAMBDA_NAME")
    
    for function_name in "${lambda_functions[@]}"; do
        if [[ -z "$function_name" ]]; then
            continue
        fi
        
        log_info "Deleting Lambda function: $function_name"
        
        # Check if function exists
        if ! aws lambda get-function --function-name "$function_name" >/dev/null 2>&1; then
            log_warning "Lambda function $function_name not found"
            continue
        fi
        
        # Delete function
        aws lambda delete-function --function-name "$function_name"
        
        log_success "Lambda function $function_name deleted"
    done
}

# Function to delete Aurora DSQL cluster
delete_aurora_dsql_cluster() {
    if [[ -z "${DSQL_CLUSTER_NAME:-}" ]]; then
        log_warning "Aurora DSQL cluster name not found, skipping"
        return 0
    fi
    
    log_info "Deleting Aurora DSQL cluster: $DSQL_CLUSTER_NAME"
    
    # Check if cluster exists
    if ! aws dsql describe-cluster --cluster-name "$DSQL_CLUSTER_NAME" >/dev/null 2>&1; then
        log_warning "Aurora DSQL cluster $DSQL_CLUSTER_NAME not found"
        return 0
    fi
    
    # Disable deletion protection first
    log_info "Disabling deletion protection for Aurora DSQL cluster..."
    aws dsql modify-cluster \
        --cluster-name "$DSQL_CLUSTER_NAME" \
        --deletion-protection-enabled false >/dev/null 2>&1 || true
    
    # Delete cluster
    aws dsql delete-cluster --cluster-name "$DSQL_CLUSTER_NAME"
    
    log_info "Aurora DSQL cluster deletion initiated..."
    log_success "Aurora DSQL cluster deletion requested"
}

# Function to delete IAM resources
delete_iam_resources() {
    if [[ -z "${LAMBDA_ROLE_NAME:-}" ]]; then
        log_warning "Lambda role name not found, skipping IAM cleanup"
        return 0
    fi
    
    log_info "Deleting IAM resources..."
    
    # Detach policies from role
    log_info "Detaching policies from role: $LAMBDA_ROLE_NAME"
    
    # Detach AWS managed policy
    aws iam detach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        >/dev/null 2>&1 || log_warning "Failed to detach AWSLambdaBasicExecutionRole policy"
    
    # Detach custom policy
    if [[ -n "${LAMBDA_POLICY_NAME:-}" ]]; then
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}" \
            >/dev/null 2>&1 || log_warning "Failed to detach custom Aurora DSQL policy"
        
        # Delete custom policy
        log_info "Deleting custom policy: $LAMBDA_POLICY_NAME"
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}" \
            >/dev/null 2>&1 || log_warning "Failed to delete custom policy"
    fi
    
    # Delete role
    log_info "Deleting IAM role: $LAMBDA_ROLE_NAME"
    aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" \
        >/dev/null 2>&1 || log_warning "Failed to delete IAM role"
    
    log_success "IAM resources deleted"
}

# Function to cleanup deployment files
cleanup_deployment_files() {
    log_info "Cleaning up deployment files..."
    
    # Remove deployment info files
    local deployment_files=(ecommerce-deployment-*.json)
    for file in "${deployment_files[@]}"; do
        if [[ -e "$file" ]]; then
            rm -f "$file"
            log_info "Removed deployment file: $file"
        fi
    done
    
    log_success "Deployment files cleaned up"
}

# Function to verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local errors=0
    
    # Check Aurora DSQL cluster
    if [[ -n "${DSQL_CLUSTER_NAME:-}" ]]; then
        if aws dsql describe-cluster --cluster-name "$DSQL_CLUSTER_NAME" >/dev/null 2>&1; then
            local status=$(aws dsql describe-cluster --cluster-name "$DSQL_CLUSTER_NAME" \
                --query 'Cluster.Status' --output text)
            if [[ "$status" != "DELETING" ]]; then
                log_warning "Aurora DSQL cluster $DSQL_CLUSTER_NAME still exists (status: $status)"
                errors=$((errors + 1))
            else
                log_info "Aurora DSQL cluster $DSQL_CLUSTER_NAME is being deleted"
            fi
        fi
    fi
    
    # Check Lambda functions
    for function_name in "$PRODUCTS_LAMBDA_NAME" "$ORDERS_LAMBDA_NAME"; do
        if [[ -n "$function_name" ]] && aws lambda get-function --function-name "$function_name" >/dev/null 2>&1; then
            log_warning "Lambda function $function_name still exists"
            errors=$((errors + 1))
        fi
    done
    
    # Check API Gateway
    if [[ -n "${API_ID:-}" ]] && aws apigateway get-rest-api --rest-api-id "$API_ID" >/dev/null 2>&1; then
        log_warning "API Gateway $API_ID still exists"
        errors=$((errors + 1))
    fi
    
    # Check CloudFront distribution
    if [[ -n "${DISTRIBUTION_ID:-}" ]] && aws cloudfront get-distribution --id "$DISTRIBUTION_ID" >/dev/null 2>&1; then
        local dist_status=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" \
            --query 'Distribution.Status' --output text)
        log_info "CloudFront distribution $DISTRIBUTION_ID status: $dist_status"
    fi
    
    # Check IAM role
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]] && aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
        log_warning "IAM role $LAMBDA_ROLE_NAME still exists"
        errors=$((errors + 1))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All resources successfully deleted or are being deleted"
    else
        log_warning "$errors resources may not have been fully deleted"
    fi
}

# Function to display destruction summary
display_summary() {
    echo
    echo "================================"
    echo "  DESTRUCTION COMPLETED"
    echo "================================"
    echo
    
    if [[ -n "${DSQL_CLUSTER_NAME:-}" ]]; then
        log_info "Aurora DSQL Cluster: $DSQL_CLUSTER_NAME (deletion in progress)"
    fi
    
    if [[ -n "${API_ID:-}" ]]; then
        log_info "API Gateway: $API_ID (deleted)"
    fi
    
    if [[ -n "${DISTRIBUTION_ID:-}" ]]; then
        log_info "CloudFront Distribution: $DISTRIBUTION_ID (deleted)"
    fi
    
    echo
    log_warning "Note: Aurora DSQL cluster deletion may take several minutes to complete"
    log_info "You can monitor the deletion status in the AWS Console"
    echo
}

# Main destruction function
main() {
    log_info "Starting Global E-commerce Platform destruction"
    
    # Run all destruction steps
    validate_prerequisites
    load_deployment_info
    confirm_destruction
    discover_api_gateway
    discover_cloudfront_distribution
    
    # Delete resources in reverse order of creation
    delete_cloudfront_distribution
    delete_api_gateway
    delete_lambda_functions
    delete_aurora_dsql_cluster
    delete_iam_resources
    cleanup_deployment_files
    
    # Verify deletion
    verify_deletion
    display_summary
    
    log_success "Destruction completed successfully!"
}

# Handle script interruption
trap 'log_error "Destruction interrupted. Some resources may still exist."; exit 1' INT TERM

# Check for help flag
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Destroy the Global E-commerce Platform with Aurora DSQL"
    echo
    echo "Options:"
    echo "  --force           Skip confirmation prompt"
    echo "  --suffix SUFFIX   Specify resource suffix manually"
    echo "  -h, --help       Show this help message"
    echo
    echo "Environment Variables:"
    echo "  FORCE_DESTROY=true    Skip confirmation prompt"
    echo "  RANDOM_SUFFIX=suffix  Resource suffix to use"
    echo "  AWS_REGION=region     AWS region to use"
    echo
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --suffix)
            export RANDOM_SUFFIX="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"