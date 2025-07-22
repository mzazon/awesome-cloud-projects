#!/bin/bash

# Cleanup script for AWS Carbon Footprint Optimization Recipe
# This script safely removes all infrastructure created by the deployment script
# including S3 buckets, Lambda functions, DynamoDB tables, and related resources

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
    warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_PROJECT_NAME=""

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy AWS Carbon Footprint Optimization infrastructure

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: $DEFAULT_REGION)
    -p, --project PROJECT   Project name prefix (required if not using Terraform state)
    -d, --dry-run          Perform a dry run without deleting resources
    -f, --force            Force destruction without confirmation prompts
    --terraform-only       Only destroy resources managed by Terraform
    --manual-only          Only destroy resources not managed by Terraform
    --skip-s3-empty        Skip emptying S3 buckets (faster but may fail if buckets have objects)

EXAMPLES:
    $0 -p carbon-optimizer-abc123
    $0 -r us-west-2 --terraform-only
    $0 --dry-run -p my-carbon-optimizer

ENVIRONMENT VARIABLES:
    AWS_REGION              AWS region (overrides -r flag)
    PROJECT_NAME            Project name (overrides -p flag)
    DRY_RUN                Set to 'true' for dry-run mode

EOF
}

# Parse command line arguments
parse_args() {
    REGION="$DEFAULT_REGION"
    PROJECT_NAME="$DEFAULT_PROJECT_NAME"
    FORCE_DESTROY=false
    TERRAFORM_ONLY=false
    MANUAL_ONLY=false
    SKIP_S3_EMPTY=false

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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DESTROY=true
                shift
                ;;
            --terraform-only)
                TERRAFORM_ONLY=true
                shift
                ;;
            --manual-only)
                MANUAL_ONLY=true
                shift
                ;;
            --skip-s3-empty)
                SKIP_S3_EMPTY=true
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
}

# Validate parameters
validate_params() {
    log "Validating cleanup parameters..."

    # Check if we can get project name from Terraform state
    if [[ -z "$PROJECT_NAME" && -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
        log "Attempting to extract project name from Terraform state..."
        if command -v jq &> /dev/null; then
            PROJECT_NAME=$(jq -r '.outputs.project_name.value // empty' "$TERRAFORM_DIR/terraform.tfstate" 2>/dev/null || echo "")
        fi
        
        if [[ -z "$PROJECT_NAME" ]] && command -v terraform &> /dev/null; then
            cd "$TERRAFORM_DIR"
            PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null || echo "")
        fi
    fi

    if [[ -z "$PROJECT_NAME" && "$TERRAFORM_ONLY" != "true" ]]; then
        error "Project name is required for manual cleanup. Use -p flag or ensure Terraform state is available."
        usage
        exit 1
    fi

    success "Parameters validated successfully"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi

    # Validate AWS region
    if ! aws ec2 describe-regions --region-names "$REGION" &> /dev/null; then
        error "Invalid AWS region: $REGION"
        exit 1
    fi

    success "Prerequisites check completed"
}

# Set project variables
set_project_variables() {
    if [[ -n "$PROJECT_NAME" ]]; then
        export AWS_REGION="$REGION"
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export PROJECT_NAME_FULL="$PROJECT_NAME"
        export S3_BUCKET="${PROJECT_NAME}-data"
        export LAMBDA_FUNCTION="${PROJECT_NAME}-analyzer"
        export DYNAMODB_TABLE="${PROJECT_NAME}-metrics"
        export SNS_TOPIC_NAME="${PROJECT_NAME}-notifications"

        log "Target resources:"
        log "  - Region: $AWS_REGION"
        log "  - Project Name: $PROJECT_NAME_FULL"
        log "  - S3 Bucket: $S3_BUCKET"
        log "  - Lambda Function: $LAMBDA_FUNCTION"
        log "  - DynamoDB Table: $DYNAMODB_TABLE"
        log "  - SNS Topic: $SNS_TOPIC_NAME"
    fi
}

# List existing resources
list_existing_resources() {
    log "Scanning for existing resources..."

    local resources_found=false

    if [[ -n "$PROJECT_NAME" ]]; then
        # Check S3 bucket
        if aws s3 ls "s3://$S3_BUCKET" --region "$REGION" &> /dev/null; then
            log "Found S3 bucket: $S3_BUCKET"
            resources_found=true
        fi

        # Check Lambda function
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION" --region "$REGION" &> /dev/null; then
            log "Found Lambda function: $LAMBDA_FUNCTION"
            resources_found=true
        fi

        # Check DynamoDB table
        if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &> /dev/null; then
            log "Found DynamoDB table: $DYNAMODB_TABLE"
            resources_found=true
        fi

        # Check SNS topic
        local sns_topic_arn=$(aws sns list-topics --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
        if [[ -n "$sns_topic_arn" && "$sns_topic_arn" != "None" ]]; then
            log "Found SNS topic: $sns_topic_arn"
            resources_found=true
        fi

        # Check EventBridge schedules
        local schedules=$(aws scheduler list-schedules --region "$REGION" --query "Schedules[?contains(Name, '$PROJECT_NAME')].Name" --output text 2>/dev/null || echo "")
        if [[ -n "$schedules" && "$schedules" != "None" ]]; then
            log "Found EventBridge schedules: $schedules"
            resources_found=true
        fi

        # Check IAM roles
        local iam_roles=$(aws iam list-roles --query "Roles[?contains(RoleName, '$PROJECT_NAME')].RoleName" --output text 2>/dev/null || echo "")
        if [[ -n "$iam_roles" && "$iam_roles" != "None" ]]; then
            log "Found IAM roles: $iam_roles"
            resources_found=true
        fi

        # Check Cost and Usage Reports
        local cur_reports=$(aws cur describe-report-definitions --region us-east-1 --query "ReportDefinitions[?contains(ReportName, 'carbon-optimization')].ReportName" --output text 2>/dev/null || echo "")
        if [[ -n "$cur_reports" && "$cur_reports" != "None" ]]; then
            log "Found CUR reports: $cur_reports"
            resources_found=true
        fi
    fi

    # Check Terraform state
    if [[ -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
        log "Found Terraform state file"
        resources_found=true
    fi

    if [[ "$resources_found" == "false" ]]; then
        warning "No resources found to delete"
        exit 0
    fi
}

# Confirm destruction
confirm_destruction() {
    if [[ "$FORCE_DESTROY" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    warning "WARNING: This will permanently delete all carbon footprint optimization resources!"
    echo
    echo "This action cannot be undone. All data will be lost."
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation

    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi

    echo
    read -p "Please type the project name '$PROJECT_NAME' to confirm: " project_confirmation

    if [[ "$project_confirmation" != "$PROJECT_NAME" ]]; then
        error "Project name confirmation failed. Destruction cancelled."
        exit 1
    fi

    log "Destruction confirmed. Proceeding..."
}

# Destroy resources with Terraform
destroy_terraform() {
    if [[ "$MANUAL_ONLY" == "true" ]]; then
        log "Skipping Terraform destruction (manual-only mode)"
        return 0
    fi

    log "Destroying infrastructure with Terraform..."

    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        warning "Terraform directory not found: $TERRAFORM_DIR"
        return 0
    fi

    cd "$TERRAFORM_DIR"

    if [[ ! -f "terraform.tfstate" ]]; then
        warning "No Terraform state file found. Skipping Terraform destruction."
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Would execute Terraform destroy"
        terraform plan -destroy -no-color
        return 0
    fi

    # Initialize Terraform (in case modules have changed)
    log "Initializing Terraform..."
    terraform init -no-color

    # Plan destruction
    log "Planning Terraform destruction..."
    terraform plan -destroy -no-color -out=destroy-plan

    # Apply destruction
    log "Applying Terraform destruction..."
    terraform apply -no-color -auto-approve destroy-plan

    # Clean up plan file
    rm -f destroy-plan

    success "Terraform destruction completed"
}

# Empty S3 buckets
empty_s3_buckets() {
    if [[ "$TERRAFORM_ONLY" == "true" || "$SKIP_S3_EMPTY" == "true" ]]; then
        return 0
    fi

    if [[ -z "$S3_BUCKET" ]]; then
        return 0
    fi

    log "Emptying S3 bucket: $S3_BUCKET"

    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Would empty S3 bucket $S3_BUCKET"
        return 0
    fi

    if aws s3 ls "s3://$S3_BUCKET" --region "$REGION" &> /dev/null; then
        # Delete all objects and versions
        aws s3 rm "s3://$S3_BUCKET" --recursive --region "$REGION" 2>/dev/null || true
        
        # Delete versioned objects if versioning is enabled
        aws s3api delete-objects \
            --bucket "$S3_BUCKET" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$S3_BUCKET" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true

        # Delete delete markers
        aws s3api delete-objects \
            --bucket "$S3_BUCKET" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$S3_BUCKET" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true

        success "S3 bucket emptied: $S3_BUCKET"
    else
        warning "S3 bucket not found: $S3_BUCKET"
    fi
}

# Clean up manual resources
cleanup_manual_resources() {
    if [[ "$TERRAFORM_ONLY" == "true" ]]; then
        log "Skipping manual resource cleanup (terraform-only mode)"
        return 0
    fi

    if [[ -z "$PROJECT_NAME" ]]; then
        warning "Project name not available for manual cleanup"
        return 0
    fi

    log "Cleaning up manual resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Would clean up manual resources"
        return 0
    fi

    # Delete EventBridge schedules
    local schedules=$(aws scheduler list-schedules --region "$REGION" --query "Schedules[?contains(Name, '$PROJECT_NAME')].Name" --output text 2>/dev/null || echo "")
    if [[ -n "$schedules" && "$schedules" != "None" ]]; then
        for schedule in $schedules; do
            log "Deleting EventBridge schedule: $schedule"
            aws scheduler delete-schedule --name "$schedule" --region "$REGION" 2>/dev/null || warning "Failed to delete schedule: $schedule"
        done
    fi

    # Delete Lambda function (if not managed by Terraform)
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION" --region "$REGION" &> /dev/null; then
        log "Deleting Lambda function: $LAMBDA_FUNCTION"
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION" --region "$REGION" 2>/dev/null || warning "Failed to delete Lambda function"
    fi

    # Delete DynamoDB table (if not managed by Terraform)
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &> /dev/null; then
        log "Deleting DynamoDB table: $DYNAMODB_TABLE"
        aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --region "$REGION" 2>/dev/null || warning "Failed to delete DynamoDB table"
    fi

    # Delete SNS topic
    local sns_topic_arn=$(aws sns list-topics --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
    if [[ -n "$sns_topic_arn" && "$sns_topic_arn" != "None" ]]; then
        log "Deleting SNS topic: $sns_topic_arn"
        aws sns delete-topic --topic-arn "$sns_topic_arn" --region "$REGION" 2>/dev/null || warning "Failed to delete SNS topic"
    fi

    # Delete IAM roles and policies
    local iam_roles=$(aws iam list-roles --query "Roles[?contains(RoleName, '$PROJECT_NAME')].RoleName" --output text 2>/dev/null || echo "")
    if [[ -n "$iam_roles" && "$iam_roles" != "None" ]]; then
        for role in $iam_roles; do
            log "Deleting IAM role: $role"
            
            # Delete attached policies
            local policies=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames" --output text 2>/dev/null || echo "")
            if [[ -n "$policies" && "$policies" != "None" ]]; then
                for policy in $policies; do
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
                done
            fi
            
            # Delete role
            aws iam delete-role --role-name "$role" 2>/dev/null || warning "Failed to delete IAM role: $role"
        done
    fi

    # Delete Cost and Usage Reports
    local cur_reports=$(aws cur describe-report-definitions --region us-east-1 --query "ReportDefinitions[?contains(ReportName, 'carbon-optimization')].ReportName" --output text 2>/dev/null || echo "")
    if [[ -n "$cur_reports" && "$cur_reports" != "None" ]]; then
        for report in $cur_reports; do
            log "Deleting CUR report: $report"
            aws cur delete-report-definition --report-name "$report" --region us-east-1 2>/dev/null || warning "Failed to delete CUR report: $report"
        done
    fi

    # Clean up Systems Manager parameters
    local ssm_params=$(aws ssm get-parameters-by-path --path "/$PROJECT_NAME" --region "$REGION" --query "Parameters[].Name" --output text 2>/dev/null || echo "")
    if [[ -n "$ssm_params" && "$ssm_params" != "None" ]]; then
        for param in $ssm_params; do
            log "Deleting SSM parameter: $param"
            aws ssm delete-parameter --name "$param" --region "$REGION" 2>/dev/null || warning "Failed to delete SSM parameter: $param"
        done
    fi

    success "Manual resource cleanup completed"
}

# Final cleanup and validation
final_cleanup() {
    log "Performing final cleanup..."

    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Would perform final cleanup"
        return 0
    fi

    # Remove local files
    rm -f "$TERRAFORM_DIR/terraform.tfvars" 2>/dev/null || true
    rm -f "$TERRAFORM_DIR/terraform.tfplan" 2>/dev/null || true
    rm -f "$TERRAFORM_DIR/destroy-plan" 2>/dev/null || true

    # Clean up any remaining temporary files
    rm -f /tmp/lambda-test-response.json 2>/dev/null || true

    success "Final cleanup completed"
}

# Validate destruction
validate_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Skipping destruction validation"
        return 0
    fi

    log "Validating resource destruction..."

    local remaining_resources=false

    if [[ -n "$PROJECT_NAME" ]]; then
        # Check if S3 bucket still exists
        if aws s3 ls "s3://$S3_BUCKET" --region "$REGION" &> /dev/null; then
            warning "S3 bucket still exists: $S3_BUCKET"
            remaining_resources=true
        fi

        # Check if Lambda function still exists
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION" --region "$REGION" &> /dev/null; then
            warning "Lambda function still exists: $LAMBDA_FUNCTION"
            remaining_resources=true
        fi

        # Check if DynamoDB table still exists
        if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &> /dev/null; then
            warning "DynamoDB table still exists: $DYNAMODB_TABLE"
            remaining_resources=true
        fi
    fi

    if [[ "$remaining_resources" == "true" ]]; then
        warning "Some resources may still exist. This is normal for resources with deletion protection or dependencies."
        warning "Check the AWS console to verify complete cleanup if needed."
    else
        success "All target resources have been successfully removed"
    fi
}

# Display destruction summary
display_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: No resources were actually deleted"
        return 0
    fi

    log "Destruction Summary"
    echo "==================="
    echo
    echo "AWS Region: $AWS_REGION"
    if [[ -n "$PROJECT_NAME" ]]; then
        echo "Project Name: $PROJECT_NAME"
    fi
    echo
    echo "Cleanup actions performed:"
    echo "- Terraform-managed resources: $([ "$MANUAL_ONLY" == "true" ] && echo "SKIPPED" || echo "DELETED")"
    echo "- Manual resources: $([ "$TERRAFORM_ONLY" == "true" ] && echo "SKIPPED" || echo "DELETED")"
    echo "- S3 bucket contents: $([ "$SKIP_S3_EMPTY" == "true" ] && echo "SKIPPED" || echo "EMPTIED")"
    echo
    success "Carbon footprint optimization infrastructure has been removed!"
}

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Destruction failed with exit code $exit_code"
        warning "Some resources may not have been deleted. Check the AWS console for any remaining resources."
    fi
    exit $exit_code
}

# Set trap for cleanup on error
trap cleanup_on_error EXIT

# Main execution flow
main() {
    log "Starting AWS Carbon Footprint Optimization cleanup"
    echo "=================================================="
    
    parse_args "$@"
    validate_params
    check_prerequisites
    set_project_variables
    list_existing_resources
    confirm_destruction
    empty_s3_buckets
    destroy_terraform
    cleanup_manual_resources
    final_cleanup
    validate_destruction
    display_summary
}

# Execute main function with all arguments
main "$@"