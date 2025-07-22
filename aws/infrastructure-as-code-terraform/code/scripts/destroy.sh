#!/bin/bash

# =============================================================================
# Infrastructure as Code with Terraform and AWS - Cleanup Script
# =============================================================================
# This script safely destroys Terraform infrastructure and cleans up
# backend resources to avoid ongoing AWS charges.
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/cleanup.log"

# Default values
ENVIRONMENT="${1:-dev}"
FORCE_CLEANUP="${FORCE_CLEANUP:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
CLEANUP_BACKEND="${CLEANUP_BACKEND:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# =============================================================================
# Helper Functions
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [ENVIRONMENT] [OPTIONS]

ARGUMENTS:
    ENVIRONMENT    Target environment (dev, staging, prod) [default: dev]

ENVIRONMENT VARIABLES:
    FORCE_CLEANUP=true      Skip all confirmation prompts (DANGEROUS)
    SKIP_CONFIRMATION=true  Skip infrastructure confirmation only
    CLEANUP_BACKEND=false   Skip backend resource cleanup

EXAMPLES:
    $0                      # Destroy dev environment with confirmations
    $0 staging              # Destroy staging environment
    FORCE_CLEANUP=true $0   # Destroy everything without confirmations (DANGEROUS)
    CLEANUP_BACKEND=false $0 # Keep S3 bucket and DynamoDB table

WARNING: This script will permanently delete AWS resources and cannot be undone!

EOF
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running from correct directory
    if [[ ! -f "$PROJECT_ROOT/main.tf" ]]; then
        log_error "main.tf not found. Please run this script from the project root or scripts directory."
        exit 1
    fi
    
    # Check required tools
    local tools=("terraform" "aws")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured or invalid."
        log "Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

load_deployment_info() {
    log "Loading deployment information..."
    
    # Try to load from deployment_info.txt
    if [[ -f "$PROJECT_ROOT/deployment_info.txt" ]]; then
        log "Found deployment_info.txt, loading variables..."
        
        # Source the deployment info (if it contains shell variables)
        while IFS=': ' read -r key value; do
            case "$key" in
                "AWS Region")
                    export AWS_REGION="$value"
                    ;;
                "AWS Account")
                    export AWS_ACCOUNT_ID="$value"
                    ;;
                "S3 Bucket")
                    export BUCKET_NAME="$value"
                    ;;
                "DynamoDB Table")
                    export LOCK_TABLE_NAME="$value"
                    ;;
            esac
        done < "$PROJECT_ROOT/deployment_info.txt"
    fi
    
    # Set defaults if not loaded
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    export PROJECT_NAME="${PROJECT_NAME:-terraform-iac-demo}"
    
    # If bucket name is not loaded, try to find it
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log "Attempting to find S3 bucket..."
        local bucket_list
        bucket_list=$(aws s3api list-buckets --query "Buckets[?contains(Name, '${PROJECT_NAME}-state')].Name" --output text)
        
        if [[ -n "$bucket_list" ]]; then
            BUCKET_NAME=$(echo "$bucket_list" | head -n1)
            log "Found S3 bucket: $BUCKET_NAME"
        else
            log_warning "S3 bucket not found - backend cleanup will be skipped"
            CLEANUP_BACKEND="false"
        fi
    fi
    
    # If table name is not set, use default
    export LOCK_TABLE_NAME="${LOCK_TABLE_NAME:-${PROJECT_NAME}-locks}"
    
    log "Environment: $ENVIRONMENT"
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "S3 Bucket: ${BUCKET_NAME:-Not found}"
    log "DynamoDB Table: $LOCK_TABLE_NAME"
}

show_destruction_warning() {
    echo
    echo "=============================================================================="
    echo "🚨 DANGER: RESOURCE DESTRUCTION WARNING 🚨"
    echo "=============================================================================="
    echo
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo
    echo "Infrastructure Resources:"
    echo "  • VPC and all networking components"
    echo "  • EC2 instances and Auto Scaling Groups"
    echo "  • Application Load Balancer"
    echo "  • Security Groups and related resources"
    echo
    if [[ "$CLEANUP_BACKEND" == "true" ]]; then
        echo "Backend Resources:"
        echo "  • S3 bucket: ${BUCKET_NAME:-Unknown}"
        echo "  • DynamoDB table: $LOCK_TABLE_NAME"
        echo "  • All Terraform state files"
        echo
    fi
    echo "Environment: $ENVIRONMENT"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo "AWS Region: $AWS_REGION"
    echo
    echo "⚠️  THIS ACTION CANNOT BE UNDONE! ⚠️"
    echo
    echo "=============================================================================="
}

confirm_destruction() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        log_warning "FORCE_CLEANUP enabled - skipping all confirmations"
        return 0
    fi
    
    show_destruction_warning
    
    echo
    read -p "Do you understand that this will permanently delete resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Type the environment name '$ENVIRONMENT' to confirm: " -r
    if [[ "$REPLY" != "$ENVIRONMENT" ]]; then
        log_error "Environment name mismatch. Cleanup cancelled."
        exit 1
    fi
    
    if [[ "$CLEANUP_BACKEND" == "true" ]]; then
        echo
        read -p "This will also delete backend resources. Continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Backend cleanup cancelled. Setting CLEANUP_BACKEND=false"
            CLEANUP_BACKEND="false"
        fi
    fi
    
    log_success "Destruction confirmed by user"
}

initialize_terraform() {
    log "Initializing Terraform..."
    
    cd "$PROJECT_ROOT"
    
    # Only initialize if backend resources exist
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        # Initialize with backend configuration
        terraform init \
            -backend-config="bucket=$BUCKET_NAME" \
            -backend-config="key=terraform.tfstate" \
            -backend-config="region=$AWS_REGION" \
            -backend-config="dynamodb_table=$LOCK_TABLE_NAME" \
            -backend-config="encrypt=true" \
            -reconfigure 2>/dev/null || {
                log_warning "Failed to initialize with remote backend"
                log "Attempting local initialization..."
                terraform init -reconfigure
            }
    else
        log "No backend configuration available, using local state"
        terraform init -reconfigure
    fi
    
    log_success "Terraform initialized"
}

plan_destruction() {
    log "Creating Terraform destruction plan..."
    
    cd "$PROJECT_ROOT"
    
    # Check if tfvars file exists
    if [[ ! -f "environments/$ENVIRONMENT/terraform.tfvars" ]]; then
        log_warning "Environment configuration not found: environments/$ENVIRONMENT/terraform.tfvars"
        log "Attempting destruction without var file..."
        terraform plan -destroy -out="destroy-$ENVIRONMENT.tfplan"
    else
        terraform plan -destroy \
            -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
            -out="destroy-$ENVIRONMENT.tfplan"
    fi
    
    log_success "Destruction plan created"
}

destroy_infrastructure() {
    log "Destroying Terraform infrastructure..."
    
    cd "$PROJECT_ROOT"
    
    # Final confirmation for infrastructure
    if [[ "$SKIP_CONFIRMATION" != "true" && "$FORCE_CLEANUP" != "true" ]]; then
        echo
        read -p "Proceed with infrastructure destruction? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Infrastructure destruction cancelled by user"
            exit 0
        fi
    fi
    
    # Apply destruction plan
    terraform apply "destroy-$ENVIRONMENT.tfplan"
    
    log_success "Infrastructure destroyed"
}

cleanup_terraform_files() {
    log "Cleaning up Terraform files..."
    
    cd "$PROJECT_ROOT"
    
    # Remove plan files
    rm -f "destroy-$ENVIRONMENT.tfplan"
    rm -f "$ENVIRONMENT.tfplan"
    
    # Remove terraform directory (contains state and provider files)
    if [[ -d ".terraform" ]]; then
        rm -rf ".terraform"
        log "Removed .terraform directory"
    fi
    
    # Remove lock file
    if [[ -f ".terraform.lock.hcl" ]]; then
        rm -f ".terraform.lock.hcl"
        log "Removed Terraform lock file"
    fi
    
    # Remove deployment info
    if [[ -f "deployment_info.txt" ]]; then
        rm -f "deployment_info.txt"
        log "Removed deployment info file"
    fi
    
    log_success "Terraform files cleaned up"
}

cleanup_backend_resources() {
    if [[ "$CLEANUP_BACKEND" != "true" ]]; then
        log "Skipping backend resource cleanup (CLEANUP_BACKEND=false)"
        return 0
    fi
    
    log "Cleaning up backend resources..."
    
    # Clean up S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "Checking S3 bucket: $BUCKET_NAME"
        
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            log "Emptying S3 bucket..."
            
            # Delete all versions and delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
                --output json | \
            jq -r '.Objects[]? | select(.VersionId != null) | "--delete " + .Key + " --version-id " + .VersionId' | \
            while read -r line; do
                if [[ -n "$line" ]]; then
                    aws s3api delete-object --bucket "$BUCKET_NAME" $line
                fi
            done
            
            # Delete delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
                --output json | \
            jq -r '.Objects[]? | select(.VersionId != null) | "--delete " + .Key + " --version-id " + .VersionId' | \
            while read -r line; do
                if [[ -n "$line" ]]; then
                    aws s3api delete-object --bucket "$BUCKET_NAME" $line
                fi
            done
            
            # Final cleanup of any remaining objects
            aws s3 rm "s3://$BUCKET_NAME" --recursive || true
            
            # Delete the bucket
            aws s3api delete-bucket --bucket "$BUCKET_NAME"
            log_success "S3 bucket deleted: $BUCKET_NAME"
        else
            log_warning "S3 bucket not found or already deleted: $BUCKET_NAME"
        fi
    fi
    
    # Clean up DynamoDB table
    log "Checking DynamoDB table: $LOCK_TABLE_NAME"
    
    if aws dynamodb describe-table --table-name "$LOCK_TABLE_NAME" &>/dev/null; then
        log "Deleting DynamoDB table..."
        aws dynamodb delete-table --table-name "$LOCK_TABLE_NAME"
        
        # Wait for deletion (with timeout)
        log "Waiting for table deletion..."
        local timeout=300  # 5 minutes
        local elapsed=0
        local interval=10
        
        while [[ $elapsed -lt $timeout ]]; do
            if ! aws dynamodb describe-table --table-name "$LOCK_TABLE_NAME" &>/dev/null; then
                log_success "DynamoDB table deleted: $LOCK_TABLE_NAME"
                break
            fi
            
            sleep $interval
            elapsed=$((elapsed + interval))
            log "Still waiting for table deletion... (${elapsed}s)"
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            log_warning "Timeout waiting for table deletion - may still be in progress"
        fi
    else
        log_warning "DynamoDB table not found or already deleted: $LOCK_TABLE_NAME"
    fi
}

verify_cleanup() {
    log "Verifying cleanup completion..."
    
    cd "$PROJECT_ROOT"
    
    # Check if any resources remain in state
    if terraform state list &>/dev/null; then
        local remaining_resources
        remaining_resources=$(terraform state list | wc -l)
        if [[ $remaining_resources -gt 0 ]]; then
            log_warning "$remaining_resources resources remain in Terraform state"
            terraform state list
        else
            log_success "No resources remain in Terraform state"
        fi
    fi
    
    # Verify backend resources are gone
    if [[ "$CLEANUP_BACKEND" == "true" ]]; then
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
                log_warning "S3 bucket still exists: $BUCKET_NAME"
            else
                log_success "S3 bucket successfully deleted"
            fi
        fi
        
        if aws dynamodb describe-table --table-name "$LOCK_TABLE_NAME" &>/dev/null; then
            log_warning "DynamoDB table still exists: $LOCK_TABLE_NAME"
        else
            log_success "DynamoDB table successfully deleted"
        fi
    fi
    
    log_success "Cleanup verification completed"
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    # Initialize log file
    echo "==============================================================================" > "$LOG_FILE"
    echo "Terraform AWS Infrastructure Cleanup - $(date)" >> "$LOG_FILE"
    echo "==============================================================================" >> "$LOG_FILE"
    
    log "Starting cleanup for environment: $ENVIRONMENT"
    
    # Validate arguments
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log "Valid environments: dev, staging, prod"
        show_usage
        exit 1
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    # Infrastructure cleanup
    initialize_terraform
    plan_destruction
    destroy_infrastructure
    
    # Backend and file cleanup
    cleanup_terraform_files
    cleanup_backend_resources
    
    # Final verification
    verify_cleanup
    
    echo
    log_success "Cleanup completed successfully!"
    log "Environment: $ENVIRONMENT"
    log "Log file: $LOG_FILE"
    
    if [[ "$CLEANUP_BACKEND" == "true" ]]; then
        log "✅ All infrastructure and backend resources have been removed"
        log "✅ No ongoing AWS charges should occur from this deployment"
    else
        log_warning "Backend resources were preserved (S3 bucket and DynamoDB table)"
        log "⚠️  These resources may incur minimal ongoing charges"
    fi
}

# =============================================================================
# Script Entry Point
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi