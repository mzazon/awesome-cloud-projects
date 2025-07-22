#!/bin/bash

# =============================================================================
# Infrastructure as Code with Terraform and AWS - Deployment Script
# =============================================================================
# This script deploys a complete Terraform infrastructure demonstration
# including VPC, compute resources, and load balancer configuration.
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
LOG_FILE="$PROJECT_ROOT/deployment.log"

# Default values
ENVIRONMENT="${1:-dev}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

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
    DRY_RUN=true           Show what would be deployed without applying
    SKIP_CONFIRMATION=true Skip confirmation prompts (use with caution)

EXAMPLES:
    $0                     # Deploy to dev environment
    $0 staging             # Deploy to staging environment
    DRY_RUN=true $0        # Show deployment plan without applying
    $0 prod                # Deploy to production environment

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
    local tools=("terraform" "aws" "curl")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed."
            exit 1
        fi
    done
    
    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
    log "Terraform version: $tf_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured or invalid."
        log "Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    # Check AWS region
    local aws_region
    aws_region=$(aws configure get region)
    if [[ -z "$aws_region" ]]; then
        log_error "AWS region not configured."
        log "Please set AWS_DEFAULT_REGION environment variable or run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set project variables
    export PROJECT_NAME="terraform-iac-demo"
    export BUCKET_NAME="${PROJECT_NAME}-state-${random_suffix}"
    export LOCK_TABLE_NAME="${PROJECT_NAME}-locks"
    
    log "Environment: $ENVIRONMENT"
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "S3 Bucket: $BUCKET_NAME"
    log "DynamoDB Table: $LOCK_TABLE_NAME"
    
    log_success "Environment setup completed"
}

create_backend_resources() {
    log "Creating Terraform backend resources..."
    
    # Check if S3 bucket exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "S3 bucket $BUCKET_NAME already exists"
    else
        log "Creating S3 bucket for Terraform state..."
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "$BUCKET_NAME"
        else
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$BUCKET_NAME" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        
        log_success "S3 bucket created and configured"
    fi
    
    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "$LOCK_TABLE_NAME" &>/dev/null; then
        log_warning "DynamoDB table $LOCK_TABLE_NAME already exists"
    else
        log "Creating DynamoDB table for state locking..."
        aws dynamodb create-table \
            --table-name "$LOCK_TABLE_NAME" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "$AWS_REGION"
        
        # Wait for table to be active
        log "Waiting for DynamoDB table to become active..."
        aws dynamodb wait table-exists \
            --table-name "$LOCK_TABLE_NAME" \
            --region "$AWS_REGION"
        
        log_success "DynamoDB table created and active"
    fi
}

initialize_terraform() {
    log "Initializing Terraform..."
    
    cd "$PROJECT_ROOT"
    
    # Initialize with backend configuration
    terraform init \
        -backend-config="bucket=$BUCKET_NAME" \
        -backend-config="key=terraform.tfstate" \
        -backend-config="region=$AWS_REGION" \
        -backend-config="dynamodb_table=$LOCK_TABLE_NAME" \
        -backend-config="encrypt=true" \
        -reconfigure
    
    # Validate configuration
    terraform validate
    
    log_success "Terraform initialized successfully"
}

plan_deployment() {
    log "Creating Terraform deployment plan..."
    
    cd "$PROJECT_ROOT"
    
    # Create plan
    terraform plan \
        -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
        -out="$ENVIRONMENT.tfplan" \
        -detailed-exitcode
    
    local plan_exit_code=$?
    
    case $plan_exit_code in
        0)
            log_warning "No changes detected in Terraform plan"
            return 1
            ;;
        1)
            log_error "Terraform plan failed"
            exit 1
            ;;
        2)
            log_success "Terraform plan created successfully with changes"
            return 0
            ;;
    esac
}

apply_deployment() {
    log "Applying Terraform deployment..."
    
    cd "$PROJECT_ROOT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY_RUN mode - skipping apply"
        return 0
    fi
    
    # Confirmation prompt
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo
        read -p "Are you sure you want to apply these changes? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Apply the plan
    terraform apply "$ENVIRONMENT.tfplan"
    
    log_success "Terraform deployment completed"
}

display_outputs() {
    log "Retrieving deployment outputs..."
    
    cd "$PROJECT_ROOT"
    
    echo
    echo "==============================================================================" 
    echo "DEPLOYMENT OUTPUTS"
    echo "=============================================================================="
    
    # Get and display outputs
    if terraform output &>/dev/null; then
        terraform output
        
        # Store specific outputs for verification
        local alb_dns
        alb_dns=$(terraform output -raw alb_dns_name 2>/dev/null || echo "Not available")
        
        local vpc_id
        vpc_id=$(terraform output -raw vpc_id 2>/dev/null || echo "Not available")
        
        echo
        echo "Quick verification commands:"
        if [[ "$alb_dns" != "Not available" ]]; then
            echo "Test application: curl http://$alb_dns"
        fi
        if [[ "$vpc_id" != "Not available" ]]; then
            echo "Verify VPC: aws ec2 describe-vpcs --vpc-ids $vpc_id"
        fi
    else
        log_warning "No outputs available"
    fi
    
    echo "=============================================================================="
}

verify_deployment() {
    log "Verifying deployment..."
    
    cd "$PROJECT_ROOT"
    
    # Check if resources exist in state
    local resource_count
    resource_count=$(terraform state list | wc -l)
    log "Resources in state: $resource_count"
    
    # Basic connectivity test
    local alb_dns
    alb_dns=$(terraform output -raw alb_dns_name 2>/dev/null)
    
    if [[ -n "$alb_dns" && "$alb_dns" != "Not available" ]]; then
        log "Testing application connectivity..."
        local max_attempts=10
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            log "Attempt $attempt/$max_attempts: Testing http://$alb_dns"
            
            if curl -sf "http://$alb_dns" | grep -q "Hello from Terraform"; then
                log_success "Application is responding correctly"
                break
            fi
            
            if [[ $attempt -eq $max_attempts ]]; then
                log_warning "Application not responding after $max_attempts attempts"
                log "This might be normal for new deployments - resources may still be initializing"
            else
                log "Waiting 30 seconds before next attempt..."
                sleep 30
            fi
            
            ((attempt++))
        done
    fi
    
    log_success "Deployment verification completed"
}

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log "Check the log file at: $LOG_FILE"
        
        # Cleanup temporary files
        cd "$PROJECT_ROOT" 2>/dev/null || true
        rm -f "$ENVIRONMENT.tfplan" 2>/dev/null || true
    fi
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    # Setup error handling
    trap cleanup_on_error EXIT
    
    # Initialize log file
    echo "==============================================================================" > "$LOG_FILE"
    echo "Terraform AWS Infrastructure Deployment - $(date)" >> "$LOG_FILE"
    echo "==============================================================================" >> "$LOG_FILE"
    
    log "Starting deployment for environment: $ENVIRONMENT"
    
    # Validate arguments
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log "Valid environments: dev, staging, prod"
        show_usage
        exit 1
    fi
    
    # Check if environment config exists
    if [[ ! -f "$PROJECT_ROOT/environments/$ENVIRONMENT/terraform.tfvars" ]]; then
        log_error "Environment configuration not found: environments/$ENVIRONMENT/terraform.tfvars"
        exit 1
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_backend_resources
    initialize_terraform
    
    if plan_deployment; then
        apply_deployment
        display_outputs
        verify_deployment
        
        echo
        log_success "Deployment completed successfully!"
        log "Environment: $ENVIRONMENT"
        log "Log file: $LOG_FILE"
        
        # Save deployment info
        cat > "$PROJECT_ROOT/deployment_info.txt" << EOF
Deployment Date: $(date)
Environment: $ENVIRONMENT
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID
S3 Bucket: $BUCKET_NAME
DynamoDB Table: $LOCK_TABLE_NAME
Log File: $LOG_FILE
EOF
        
    else
        log "No changes to apply"
    fi
    
    # Remove trap on successful completion
    trap - EXIT
}

# =============================================================================
# Script Entry Point
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi