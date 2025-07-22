#!/bin/bash

# Deployment script for AWS Carbon Footprint Optimization Recipe
# This script deploys the complete infrastructure for automated carbon footprint
# optimization using AWS Sustainability Scanner and Cost Explorer

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
LAMBDA_CODE_DIR="$TERRAFORM_DIR/lambda_code"

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_PROJECT_NAME="carbon-optimizer"
DEFAULT_EMAIL=""

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Carbon Footprint Optimization infrastructure

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: $DEFAULT_REGION)
    -p, --project PROJECT   Project name prefix (default: $DEFAULT_PROJECT_NAME)
    -e, --email EMAIL       Email address for notifications (required)
    -d, --dry-run          Perform a dry run without creating resources
    -f, --force            Force deployment even if resources exist
    --skip-prereq          Skip prerequisite checks

EXAMPLES:
    $0 -e user@example.com
    $0 -r us-west-2 -p my-carbon-optimizer -e admin@company.com
    $0 --dry-run -e test@example.com

ENVIRONMENT VARIABLES:
    AWS_REGION              AWS region (overrides -r flag)
    PROJECT_NAME            Project name (overrides -p flag)
    NOTIFICATION_EMAIL      Email for notifications (overrides -e flag)
    DRY_RUN                Set to 'true' for dry-run mode

EOF
}

# Parse command line arguments
parse_args() {
    REGION="$DEFAULT_REGION"
    PROJECT_NAME="$DEFAULT_PROJECT_NAME"
    EMAIL="$DEFAULT_EMAIL"
    FORCE_DEPLOY=false
    SKIP_PREREQ=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            --skip-prereq)
                SKIP_PREREQ=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Override with environment variables if set
    REGION="${AWS_REGION:-$REGION}"
    PROJECT_NAME="${PROJECT_NAME:-$PROJECT_NAME}"
    EMAIL="${NOTIFICATION_EMAIL:-$EMAIL}"
}

# Validate required parameters
validate_params() {
    log "Validating deployment parameters..."

    if [[ -z "$EMAIL" ]]; then
        error "Email address is required for notifications. Use -e flag or set NOTIFICATION_EMAIL environment variable."
        usage
        exit 1
    fi

    if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email address format: $EMAIL"
        exit 1
    fi

    if [[ ${#PROJECT_NAME} -gt 20 ]]; then
        error "Project name must be 20 characters or less"
        exit 1
    fi

    if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
        error "Project name can only contain alphanumeric characters and hyphens"
        exit 1
    fi

    success "Parameters validated successfully"
}

# Check prerequisites
check_prerequisites() {
    if [[ "$SKIP_PREREQ" == "true" ]]; then
        warning "Skipping prerequisite checks"
        return 0
    fi

    log "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi

    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some features may be limited."
    fi

    # Validate AWS region
    if ! aws ec2 describe-regions --region-names "$REGION" &> /dev/null; then
        error "Invalid AWS region: $REGION"
        exit 1
    fi

    # Check if Customer Carbon Footprint Tool is available
    log "Checking Customer Carbon Footprint Tool access..."
    if ! aws ce get-cost-and-usage --time-period Start=2023-01-01,End=2023-01-02 --granularity MONTHLY --metrics BlendedCost --region "$REGION" &> /dev/null; then
        warning "Cannot access Cost Explorer API. Ensure proper permissions are configured."
    fi

    success "Prerequisites check completed"
}

# Generate unique project identifiers
generate_identifiers() {
    log "Generating unique project identifiers..."

    # Generate random suffix for uniqueness
    if command -v aws &> /dev/null; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        RANDOM_SUFFIX="$(date +%s | tail -c 6)"
    fi

    # Set global variables
    export AWS_REGION="$REGION"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export PROJECT_NAME_FULL="${PROJECT_NAME}-${RANDOM_SUFFIX}"
    export S3_BUCKET="${PROJECT_NAME_FULL}-data"
    export LAMBDA_FUNCTION="${PROJECT_NAME_FULL}-analyzer"
    export DYNAMODB_TABLE="${PROJECT_NAME_FULL}-metrics"
    export NOTIFICATION_EMAIL="$EMAIL"

    log "Project identifiers:"
    log "  - Region: $AWS_REGION"
    log "  - Account ID: $AWS_ACCOUNT_ID"
    log "  - Project Name: $PROJECT_NAME_FULL"
    log "  - S3 Bucket: $S3_BUCKET"
    log "  - Lambda Function: $LAMBDA_FUNCTION"
    log "  - DynamoDB Table: $DYNAMODB_TABLE"
    log "  - Notification Email: $NOTIFICATION_EMAIL"
}

# Check if resources already exist
check_existing_resources() {
    log "Checking for existing resources..."

    local resources_exist=false

    # Check S3 bucket
    if aws s3 ls "s3://$S3_BUCKET" &> /dev/null; then
        warning "S3 bucket $S3_BUCKET already exists"
        resources_exist=true
    fi

    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION" --region "$AWS_REGION" &> /dev/null; then
        warning "Lambda function $LAMBDA_FUNCTION already exists"
        resources_exist=true
    fi

    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &> /dev/null; then
        warning "DynamoDB table $DYNAMODB_TABLE already exists"
        resources_exist=true
    fi

    if [[ "$resources_exist" == "true" && "$FORCE_DEPLOY" != "true" ]]; then
        error "Resources already exist. Use --force to proceed with deployment or choose a different project name."
        exit 1
    fi

    if [[ "$resources_exist" == "true" && "$FORCE_DEPLOY" == "true" ]]; then
        warning "Forcing deployment with existing resources. This may cause conflicts."
    fi
}

# Prepare Terraform variables
prepare_terraform() {
    log "Preparing Terraform configuration..."

    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        error "Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi

    # Create terraform.tfvars file
    cat > "$TERRAFORM_DIR/terraform.tfvars" << EOF
# Auto-generated Terraform variables
aws_region = "$AWS_REGION"
project_name = "$PROJECT_NAME_FULL"
s3_bucket_name = "$S3_BUCKET"
lambda_function_name = "$LAMBDA_FUNCTION"
dynamodb_table_name = "$DYNAMODB_TABLE"
notification_email = "$NOTIFICATION_EMAIL"

# Additional configuration
enable_cost_usage_reports = true
enable_sustainability_scanner = true
lambda_timeout = 300
lambda_memory_size = 512

# Tags
tags = {
  Project = "$PROJECT_NAME_FULL"
  Environment = "production"
  Purpose = "CarbonFootprintOptimization"
  ManagedBy = "Terraform"
  DeployedBy = "$USER"
  DeploymentDate = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    success "Terraform variables file created"
}

# Initialize and deploy with Terraform
deploy_terraform() {
    log "Deploying infrastructure with Terraform..."

    cd "$TERRAFORM_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Would execute Terraform deployment"
        terraform init -no-color
        terraform plan -no-color -var-file=terraform.tfvars
        return 0
    fi

    # Initialize Terraform
    log "Initializing Terraform..."
    terraform init -no-color

    # Plan deployment
    log "Planning Terraform deployment..."
    terraform plan -no-color -var-file=terraform.tfvars -out=tfplan

    # Apply deployment
    log "Applying Terraform deployment..."
    terraform apply -no-color -auto-approve tfplan

    # Clean up plan file
    rm -f tfplan

    success "Terraform deployment completed"
}

# Validate deployment
validate_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Skipping deployment validation"
        return 0
    fi

    log "Validating deployment..."

    local validation_failed=false

    # Check S3 bucket
    if ! aws s3 ls "s3://$S3_BUCKET" &> /dev/null; then
        error "S3 bucket validation failed: $S3_BUCKET"
        validation_failed=true
    fi

    # Check Lambda function
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION" --region "$AWS_REGION" &> /dev/null; then
        error "Lambda function validation failed: $LAMBDA_FUNCTION"
        validation_failed=true
    fi

    # Check DynamoDB table
    if ! aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" &> /dev/null; then
        error "DynamoDB table validation failed: $DYNAMODB_TABLE"
        validation_failed=true
    fi

    # Test Lambda function
    log "Testing Lambda function..."
    local test_result
    test_result=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION" \
        --region "$AWS_REGION" \
        --payload '{}' \
        --output json \
        /tmp/lambda-test-response.json 2>&1)

    if [[ $? -eq 0 ]]; then
        success "Lambda function test completed"
        if command -v jq &> /dev/null && [[ -f /tmp/lambda-test-response.json ]]; then
            local status_code=$(jq -r '.StatusCode' /tmp/lambda-test-response.json 2>/dev/null || echo "unknown")
            log "Lambda status code: $status_code"
        fi
    else
        warning "Lambda function test failed: $test_result"
    fi

    # Clean up test file
    rm -f /tmp/lambda-test-response.json

    if [[ "$validation_failed" == "true" ]]; then
        error "Deployment validation failed"
        exit 1
    fi

    success "Deployment validation completed successfully"
}

# Display deployment summary
display_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: No resources were actually created"
        return 0
    fi

    log "Deployment Summary"
    echo "===================="
    echo
    echo "AWS Region: $AWS_REGION"
    echo "Project Name: $PROJECT_NAME_FULL"
    echo "S3 Bucket: $S3_BUCKET"
    echo "Lambda Function: $LAMBDA_FUNCTION"
    echo "DynamoDB Table: $DYNAMODB_TABLE"
    echo "Notification Email: $NOTIFICATION_EMAIL"
    echo
    echo "Next Steps:"
    echo "1. Check your email ($EMAIL) for SNS subscription confirmation"
    echo "2. Monitor the DynamoDB table for carbon footprint metrics"
    echo "3. Review Lambda function logs in CloudWatch"
    echo "4. Access Cost Explorer to view detailed cost analysis"
    echo
    echo "Resources can be removed using the destroy.sh script"
    echo
    success "Deployment completed successfully!"
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            warning "You may need to manually clean up any partially created resources"
            log "Use the destroy.sh script or manually remove resources from the AWS console"
        fi
    fi
    exit $exit_code
}

# Set trap for cleanup on error
trap cleanup_on_error EXIT

# Main execution flow
main() {
    log "Starting AWS Carbon Footprint Optimization deployment"
    echo "======================================================"
    
    parse_args "$@"
    validate_params
    check_prerequisites
    generate_identifiers
    check_existing_resources
    prepare_terraform
    deploy_terraform
    validate_deployment
    display_summary
}

# Execute main function with all arguments
main "$@"