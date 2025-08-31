#!/bin/bash

# Service Catalog Portfolio CloudFormation Cleanup Script
# This script removes all AWS Service Catalog resources, IAM roles, S3 buckets,
# and CloudFormation templates created by the deployment script.

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warning "Force delete mode enabled - will skip confirmation prompts"
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force]"
            exit 1
            ;;
    esac
done

# Function to execute commands (respects dry-run mode)
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || true
        else
            eval "$cmd"
        fi
    fi
}

# Load deployment environment if it exists
load_deployment_env() {
    if [[ -f "deployment.env" ]]; then
        log "Loading deployment environment from deployment.env..."
        source deployment.env
        success "Deployment environment loaded"
    else
        warning "deployment.env not found. Will attempt cleanup using AWS CLI queries."
        return 1
    fi
}

# Interactive confirmation
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete the following resources:"
    echo "  - Service Catalog Portfolio and Products"
    echo "  - IAM Launch Role and Policies"
    echo "  - S3 Bucket with CloudFormation Templates"
    echo "  - Local template and policy files"
    echo ""
    
    if [[ -f "deployment.env" ]]; then
        source deployment.env
        echo "Deployment details:"
        echo "  Portfolio: ${PORTFOLIO_NAME:-'Unknown'}"
        echo "  S3 Bucket: ${TEMPLATE_BUCKET:-'Unknown'}"
        echo "  AWS Region: ${AWS_REGION:-'Unknown'}"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Find and load resources if deployment.env doesn't exist
discover_resources() {
    log "Attempting to discover Service Catalog resources..."
    
    # Try to find portfolios with enterprise-infrastructure prefix
    DISCOVERED_PORTFOLIOS=$(aws servicecatalog list-portfolios \
        --query "PortfolioDetails[?starts_with(DisplayName, 'enterprise-infrastructure-')].{Id:Id,Name:DisplayName}" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$DISCOVERED_PORTFOLIOS" != "[]" ]]; then
        log "Found Service Catalog portfolios:"
        echo "$DISCOVERED_PORTFOLIOS" | jq -r '.[] | "  - \(.Name) (\(.Id))"'
        
        if [[ "$FORCE_DELETE" != "true" ]]; then
            warning "Multiple portfolios found. This script will attempt to clean up all of them."
            read -p "Continue? (y/N): " continue_cleanup
            if [[ "$continue_cleanup" != "y" && "$continue_cleanup" != "Y" ]]; then
                log "Cleanup cancelled"
                exit 0
            fi
        fi
    else
        log "No matching Service Catalog portfolios found"
    fi
    
    # Try to find template buckets
    DISCOVERED_BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'service-catalog-templates-')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$DISCOVERED_BUCKETS" ]]; then
        log "Found template buckets: $DISCOVERED_BUCKETS"
    fi
    
    # Try to find launch roles
    DISCOVERED_ROLES=$(aws iam list-roles \
        --query "Roles[?starts_with(RoleName, 'ServiceCatalogLaunchRole-')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$DISCOVERED_ROLES" ]]; then
        log "Found launch roles: $DISCOVERED_ROLES"
    fi
}

# Remove portfolio access
remove_portfolio_access() {
    log "Removing portfolio access..."
    
    if [[ -n "${PORTFOLIO_ID:-}" && -n "${CURRENT_USER_ARN:-}" ]]; then
        execute_command "aws servicecatalog disassociate-principal-from-portfolio \
            --portfolio-id ${PORTFOLIO_ID} \
            --principal-arn ${CURRENT_USER_ARN}" \
            "Removing current user access from portfolio" true
    else
        warning "Portfolio ID or User ARN not available, skipping access removal"
    fi
    
    success "Portfolio access removed"
}

# Remove launch constraints
remove_launch_constraints() {
    log "Removing launch constraints..."
    
    if [[ -n "${PORTFOLIO_ID:-}" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            # Get all constraints for the portfolio
            CONSTRAINT_IDS=$(aws servicecatalog list-constraints-for-portfolio \
                --portfolio-id "${PORTFOLIO_ID}" \
                --query 'ConstraintDetails[].ConstraintId' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$CONSTRAINT_IDS" ]]; then
                for CONSTRAINT_ID in $CONSTRAINT_IDS; do
                    execute_command "aws servicecatalog delete-constraint --id ${CONSTRAINT_ID}" \
                        "Deleting constraint ${CONSTRAINT_ID}" true
                done
            else
                log "No constraints found for portfolio"
            fi
        else
            log "[DRY-RUN] Would remove launch constraints"
        fi
    else
        warning "Portfolio ID not available, skipping constraint removal"
    fi
    
    success "Launch constraints removed"
}

# Remove products from portfolio
remove_products_from_portfolio() {
    log "Removing products from portfolio..."
    
    if [[ -n "${PORTFOLIO_ID:-}" ]]; then
        if [[ -n "${S3_PRODUCT_ID:-}" ]]; then
            execute_command "aws servicecatalog disassociate-product-from-portfolio \
                --product-id ${S3_PRODUCT_ID} \
                --portfolio-id ${PORTFOLIO_ID}" \
                "Disassociating S3 product from portfolio" true
        fi
        
        if [[ -n "${LAMBDA_PRODUCT_ID:-}" ]]; then
            execute_command "aws servicecatalog disassociate-product-from-portfolio \
                --product-id ${LAMBDA_PRODUCT_ID} \
                --portfolio-id ${PORTFOLIO_ID}" \
                "Disassociating Lambda product from portfolio" true
        fi
    else
        warning "Portfolio ID not available, skipping product disassociation"
    fi
    
    success "Products removed from portfolio"
}

# Delete products and portfolio
delete_products_and_portfolio() {
    log "Deleting Service Catalog products and portfolio..."
    
    # Delete products
    if [[ -n "${S3_PRODUCT_ID:-}" ]]; then
        execute_command "aws servicecatalog delete-product --id ${S3_PRODUCT_ID}" \
            "Deleting S3 product" true
    fi
    
    if [[ -n "${LAMBDA_PRODUCT_ID:-}" ]]; then
        execute_command "aws servicecatalog delete-product --id ${LAMBDA_PRODUCT_ID}" \
            "Deleting Lambda product" true
    fi
    
    # Delete portfolio
    if [[ -n "${PORTFOLIO_ID:-}" ]]; then
        execute_command "aws servicecatalog delete-portfolio --id ${PORTFOLIO_ID}" \
            "Deleting portfolio" true
    fi
    
    # Clean up discovered resources if deployment.env wasn't available
    if [[ ! -f "deployment.env" ]]; then
        cleanup_discovered_resources
    fi
    
    success "Products and portfolio deleted"
}

# Clean up discovered resources
cleanup_discovered_resources() {
    log "Cleaning up discovered resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Clean up discovered portfolios
        DISCOVERED_PORTFOLIOS=$(aws servicecatalog list-portfolios \
            --query "PortfolioDetails[?starts_with(DisplayName, 'enterprise-infrastructure-')]" \
            --output json 2>/dev/null || echo "[]")
        
        if [[ "$DISCOVERED_PORTFOLIOS" != "[]" ]]; then
            echo "$DISCOVERED_PORTFOLIOS" | jq -r '.[].Id' | while read -r portfolio_id; do
                if [[ -n "$portfolio_id" ]]; then
                    # Remove constraints
                    CONSTRAINT_IDS=$(aws servicecatalog list-constraints-for-portfolio \
                        --portfolio-id "$portfolio_id" \
                        --query 'ConstraintDetails[].ConstraintId' \
                        --output text 2>/dev/null || echo "")
                    
                    for constraint_id in $CONSTRAINT_IDS; do
                        aws servicecatalog delete-constraint --id "$constraint_id" 2>/dev/null || true
                    done
                    
                    # Get and disassociate products
                    PRODUCT_IDS=$(aws servicecatalog search-products-as-admin \
                        --portfolio-id "$portfolio_id" \
                        --query 'ProductViewDetails[].ProductViewSummary.ProductId' \
                        --output text 2>/dev/null || echo "")
                    
                    for product_id in $PRODUCT_IDS; do
                        aws servicecatalog disassociate-product-from-portfolio \
                            --product-id "$product_id" \
                            --portfolio-id "$portfolio_id" 2>/dev/null || true
                        aws servicecatalog delete-product --id "$product_id" 2>/dev/null || true
                    done
                    
                    # Delete portfolio
                    aws servicecatalog delete-portfolio --id "$portfolio_id" 2>/dev/null || true
                    log "Cleaned up portfolio: $portfolio_id"
                fi
            done
        fi
    else
        log "[DRY-RUN] Would clean up discovered Service Catalog resources"
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ -n "${LAUNCH_ROLE_NAME:-}" ]]; then
        # Delete role policy
        execute_command "aws iam delete-role-policy \
            --role-name ${LAUNCH_ROLE_NAME} \
            --policy-name ServiceCatalogLaunchPolicy" \
            "Deleting IAM role policy" true
        
        # Delete role
        execute_command "aws iam delete-role --role-name ${LAUNCH_ROLE_NAME}" \
            "Deleting IAM role" true
    else
        warning "Launch role name not available, attempting to find and clean up roles..."
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Find and delete launch roles
            DISCOVERED_ROLES=$(aws iam list-roles \
                --query "Roles[?starts_with(RoleName, 'ServiceCatalogLaunchRole-')].RoleName" \
                --output text 2>/dev/null || echo "")
            
            for role_name in $DISCOVERED_ROLES; do
                if [[ -n "$role_name" ]]; then
                    aws iam delete-role-policy \
                        --role-name "$role_name" \
                        --policy-name "ServiceCatalogLaunchPolicy" 2>/dev/null || true
                    aws iam delete-role --role-name "$role_name" 2>/dev/null || true
                    log "Cleaned up IAM role: $role_name"
                fi
            done
        else
            log "[DRY-RUN] Would clean up discovered IAM roles"
        fi
    fi
    
    success "IAM resources deleted"
}

# Delete S3 resources
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    if [[ -n "${TEMPLATE_BUCKET:-}" ]]; then
        # Delete bucket contents
        execute_command "aws s3 rm s3://${TEMPLATE_BUCKET} --recursive" \
            "Removing S3 bucket contents" true
        
        # Delete bucket
        execute_command "aws s3 rb s3://${TEMPLATE_BUCKET}" \
            "Deleting S3 bucket" true
    else
        warning "Template bucket name not available, attempting to find and clean up buckets..."
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Find and delete template buckets
            DISCOVERED_BUCKETS=$(aws s3api list-buckets \
                --query "Buckets[?starts_with(Name, 'service-catalog-templates-')].Name" \
                --output text 2>/dev/null || echo "")
            
            for bucket_name in $DISCOVERED_BUCKETS; do
                if [[ -n "$bucket_name" ]]; then
                    aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || true
                    aws s3 rb "s3://$bucket_name" 2>/dev/null || true
                    log "Cleaned up S3 bucket: $bucket_name"
                fi
            done
        else
            log "[DRY-RUN] Would clean up discovered S3 buckets"
        fi
    fi
    
    success "S3 resources deleted"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "s3-bucket-template.yaml"
        "lambda-function-template.yaml"
        "servicecatalog-trust-policy.json"
        "servicecatalog-launch-policy.json"
        "deployment.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            execute_command "rm -f $file" "Removing $file" true
        fi
    done
    
    success "Local files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check for remaining portfolios
        REMAINING_PORTFOLIOS=$(aws servicecatalog list-portfolios \
            --query "length(PortfolioDetails[?starts_with(DisplayName, 'enterprise-infrastructure-')])" \
            --output text 2>/dev/null || echo "0")
        
        # Check for remaining buckets
        REMAINING_BUCKETS=$(aws s3api list-buckets \
            --query "length(Buckets[?starts_with(Name, 'service-catalog-templates-')])" \
            --output text 2>/dev/null || echo "0")
        
        # Check for remaining roles
        REMAINING_ROLES=$(aws iam list-roles \
            --query "length(Roles[?starts_with(RoleName, 'ServiceCatalogLaunchRole-')])" \
            --output text 2>/dev/null || echo "0")
        
        log "Cleanup validation results:"
        log "  Remaining portfolios: ${REMAINING_PORTFOLIOS}"
        log "  Remaining template buckets: ${REMAINING_BUCKETS}"
        log "  Remaining launch roles: ${REMAINING_ROLES}"
        
        if [[ "$REMAINING_PORTFOLIOS" == "0" && "$REMAINING_BUCKETS" == "0" && "$REMAINING_ROLES" == "0" ]]; then
            success "All resources successfully cleaned up"
        else
            warning "Some resources may still exist. Check AWS console for manual cleanup if needed."
        fi
    else
        log "[DRY-RUN] Would validate cleanup completion"
    fi
}

# Main cleanup function
main() {
    log "Starting AWS Service Catalog Portfolio cleanup..."
    
    # Try to load deployment environment
    load_deployment_env || discover_resources
    
    # Get user confirmation (unless --force is used)
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    remove_portfolio_access
    remove_launch_constraints
    remove_products_from_portfolio
    delete_products_and_portfolio
    delete_iam_resources
    delete_s3_resources
    cleanup_local_files
    validate_cleanup
    
    success "===========================================" 
    success "AWS Service Catalog Portfolio Cleanup Complete!"
    success "==========================================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log ""
        log "Cleanup Summary:"
        log "  ✅ Service Catalog portfolio and products removed"
        log "  ✅ IAM launch role and policies deleted"
        log "  ✅ S3 template bucket and contents removed"
        log "  ✅ Local template and configuration files cleaned up"
        log ""
        log "All AWS Service Catalog resources have been successfully removed."
    else
        log ""
        log "DRY-RUN completed successfully. No resources were deleted."
        log "Run without --dry-run to perform actual cleanup."
    fi
}

# Handle script interruption
cleanup_on_interrupt() {
    warning "Script interrupted by user"
    log "Cleanup may be incomplete. Re-run the script to continue cleanup."
    exit 130
}

trap cleanup_on_interrupt INT

# Run main function
main "$@"