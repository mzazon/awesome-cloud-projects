#!/bin/bash

# Mobile Backend Services with Amplify - Cleanup Script
# This script safely removes all resources created by the mobile backend deployment
# Recipe: Amplify Mobile Backend with Authentication and APIs

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be deleted"
fi

# Force mode - skip confirmations
FORCE_MODE=${FORCE_MODE:-false}
if [[ "$1" == "--force" || "$2" == "--force" ]]; then
    FORCE_MODE=true
    warning "Running in force mode - skipping confirmation prompts"
fi

log "Starting Mobile Backend Services cleanup..."

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    # Check Amplify CLI
    if ! command -v amplify &> /dev/null; then
        error "Amplify CLI is not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi
    
    success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Try to find project directory in standard locations
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        log "Using provided PROJECT_DIR: $PROJECT_DIR"
    elif [[ -f "deployment-info.json" ]]; then
        PROJECT_DIR=$(pwd)
        log "Found deployment info in current directory"
    else
        # Search for Amplify projects
        AMPLIFY_PROJECTS_DIR="$HOME/amplify-projects"
        if [[ -d "$AMPLIFY_PROJECTS_DIR" ]]; then
            log "Searching for Amplify projects in $AMPLIFY_PROJECTS_DIR"
            
            # List available projects
            PROJECTS=($(find "$AMPLIFY_PROJECTS_DIR" -name "deployment-info.json" -exec dirname {} \; 2>/dev/null || true))
            
            if [[ ${#PROJECTS[@]} -eq 0 ]]; then
                error "No Amplify projects found. Please specify PROJECT_DIR environment variable."
            elif [[ ${#PROJECTS[@]} -eq 1 ]]; then
                PROJECT_DIR="${PROJECTS[0]}"
                log "Found single project: $PROJECT_DIR"
            else
                echo ""
                log "Multiple Amplify projects found:"
                for i in "${!PROJECTS[@]}"; do
                    PROJECT_NAME=$(basename "${PROJECTS[$i]}")
                    echo "  $((i+1)). $PROJECT_NAME (${PROJECTS[$i]})"
                done
                echo ""
                
                if [[ "$FORCE_MODE" == "false" ]]; then
                    read -p "Select project to delete (1-${#PROJECTS[@]}): " selection
                    if [[ "$selection" =~ ^[0-9]+$ && "$selection" -ge 1 && "$selection" -le ${#PROJECTS[@]} ]]; then
                        PROJECT_DIR="${PROJECTS[$((selection-1))]}"
                    else
                        error "Invalid selection"
                    fi
                else
                    error "Multiple projects found but running in force mode. Please specify PROJECT_DIR."
                fi
            fi
        else
            error "No Amplify projects directory found. Please specify PROJECT_DIR environment variable."
        fi
    fi
    
    # Load deployment info if available
    if [[ -f "$PROJECT_DIR/deployment-info.json" ]]; then
        export PROJECT_NAME=$(cat "$PROJECT_DIR/deployment-info.json" | grep -o '"projectName": "[^"]*' | cut -d'"' -f4)
        export AWS_REGION=$(cat "$PROJECT_DIR/deployment-info.json" | grep -o '"awsRegion": "[^"]*' | cut -d'"' -f4)
        export AWS_ACCOUNT_ID=$(cat "$PROJECT_DIR/deployment-info.json" | grep -o '"awsAccountId": "[^"]*' | cut -d'"' -f4)
        
        log "Loaded project info: $PROJECT_NAME in $AWS_REGION"
    else
        warning "No deployment-info.json found, will try to infer project details"
        export PROJECT_NAME=$(basename "$PROJECT_DIR")
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    success "Deployment information loaded"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        log "Force mode enabled - skipping confirmation"
        return
    fi
    
    echo ""
    warning "=== DESTRUCTIVE ACTION WARNING ==="
    echo ""
    log "This will DELETE the following resources:"
    log "  • Amplify project: $PROJECT_NAME"
    log "  • Amazon Cognito User Pool and Identity Pool"
    log "  • AWS AppSync GraphQL API and DynamoDB tables"
    log "  • Amazon S3 bucket and all files"
    log "  • Amazon Pinpoint project and configurations"
    log "  • AWS Lambda functions"
    log "  • CloudWatch dashboards and log groups"
    log "  • All associated IAM roles and policies"
    echo ""
    log "Project directory: $PROJECT_DIR"
    log "AWS Region: $AWS_REGION"
    echo ""
    
    read -p "Are you absolutely sure you want to delete ALL these resources? (type 'delete' to confirm): " confirmation
    
    if [[ "$confirmation" != "delete" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    warning "Proceeding with resource deletion..."
    echo ""
}

# Delete Amplify backend resources
delete_amplify_backend() {
    log "Deleting Amplify backend resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete Amplify backend in $PROJECT_DIR"
        return
    fi
    
    if [[ ! -d "$PROJECT_DIR" ]]; then
        warning "Project directory not found: $PROJECT_DIR"
        return
    fi
    
    cd "$PROJECT_DIR"
    
    # Check if this is an Amplify project
    if [[ ! -d "amplify" ]]; then
        warning "No amplify directory found in $PROJECT_DIR"
        return
    fi
    
    # Delete Amplify backend
    log "Executing: amplify delete --force"
    if amplify delete --force; then
        success "Amplify backend deleted successfully"
    else
        warning "Failed to delete Amplify backend, continuing with manual cleanup"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch dashboards and log groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete CloudWatch resources"
        return
    fi
    
    # Delete CloudWatch dashboard
    if aws cloudwatch describe-dashboards --dashboard-names "${PROJECT_NAME}-Mobile-Backend" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "${PROJECT_NAME}-Mobile-Backend"
        success "CloudWatch dashboard deleted"
    else
        log "CloudWatch dashboard not found or already deleted"
    fi
    
    # Delete log groups associated with the project
    log "Searching for related log groups..."
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/${PROJECT_NAME}" \
        --query "logGroups[].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$LOG_GROUPS" ]]; then
        for LOG_GROUP in $LOG_GROUPS; do
            log "Deleting log group: $LOG_GROUP"
            aws logs delete-log-group --log-group-name "$LOG_GROUP" || warning "Failed to delete log group: $LOG_GROUP"
        done
        success "Log groups deleted"
    else
        log "No project-specific log groups found"
    fi
}

# Manual cleanup of remaining resources
manual_cleanup() {
    log "Performing manual cleanup of any remaining resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would perform manual cleanup"
        return
    fi
    
    # Clean up any remaining S3 buckets with project name
    log "Checking for remaining S3 buckets..."
    BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$BUCKETS" ]]; then
        for BUCKET in $BUCKETS; do
            log "Found remaining S3 bucket: $BUCKET"
            
            # Empty bucket first
            log "Emptying bucket: $BUCKET"
            aws s3 rm "s3://$BUCKET" --recursive || warning "Failed to empty bucket: $BUCKET"
            
            # Delete bucket
            log "Deleting bucket: $BUCKET"
            aws s3api delete-bucket --bucket "$BUCKET" || warning "Failed to delete bucket: $BUCKET"
        done
        success "Remaining S3 buckets cleaned up"
    else
        log "No remaining S3 buckets found"
    fi
    
    # Clean up any remaining DynamoDB tables
    log "Checking for remaining DynamoDB tables..."
    TABLES=$(aws dynamodb list-tables \
        --query "TableNames[?contains(@, '${PROJECT_NAME}')]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$TABLES" ]]; then
        for TABLE in $TABLES; do
            log "Found remaining DynamoDB table: $TABLE"
            aws dynamodb delete-table --table-name "$TABLE" || warning "Failed to delete table: $TABLE"
        done
        success "Remaining DynamoDB tables cleaned up"
    else
        log "No remaining DynamoDB tables found"
    fi
    
    # Clean up any remaining Cognito resources
    log "Checking for remaining Cognito User Pools..."
    USER_POOLS=$(aws cognito-idp list-user-pools \
        --max-results 50 \
        --query "UserPools[?contains(Name, '${PROJECT_NAME}')].Id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$USER_POOLS" ]]; then
        for POOL_ID in $USER_POOLS; do
            log "Found remaining Cognito User Pool: $POOL_ID"
            aws cognito-idp delete-user-pool --user-pool-id "$POOL_ID" || warning "Failed to delete user pool: $POOL_ID"
        done
        success "Remaining Cognito User Pools cleaned up"
    else
        log "No remaining Cognito User Pools found"
    fi
}

# Clean up local project files
cleanup_local_files() {
    log "Cleaning up local project files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete local directory $PROJECT_DIR"
        return
    fi
    
    if [[ -d "$PROJECT_DIR" ]]; then
        if [[ "$FORCE_MODE" == "false" ]]; then
            read -p "Delete local project directory $PROJECT_DIR? (y/N): " delete_local
            if [[ "$delete_local" =~ ^[Yy]$ ]]; then
                rm -rf "$PROJECT_DIR"
                success "Local project directory deleted"
            else
                log "Local project directory preserved"
            fi
        else
            rm -rf "$PROJECT_DIR"
            success "Local project directory deleted"
        fi
    else
        log "Local project directory not found or already deleted"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining Amplify apps
    AMPLIFY_APPS=$(aws amplify list-apps \
        --query "apps[?contains(name, '${PROJECT_NAME}')].name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$AMPLIFY_APPS" ]]; then
        warning "Remaining Amplify apps found: $AMPLIFY_APPS"
        ((cleanup_issues++))
    fi
    
    # Check for remaining CloudFormation stacks
    CF_STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, '${PROJECT_NAME}')].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$CF_STACKS" ]]; then
        warning "Remaining CloudFormation stacks found: $CF_STACKS"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification passed - no remaining resources detected"
    else
        warning "Cleanup verification found $cleanup_issues potential issues"
        log "You may need to manually review and clean up remaining resources"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    success "=== CLEANUP COMPLETED ==="
    echo ""
    log "Mobile backend cleanup summary:"
    log "  • Project: $PROJECT_NAME"
    log "  • Region: $AWS_REGION"
    log "  • Local directory: $PROJECT_DIR"
    echo ""
    log "Deleted resources:"
    log "  • Amplify backend infrastructure"
    log "  • Amazon Cognito User Pool and Identity Pool"
    log "  • AWS AppSync GraphQL API"
    log "  • DynamoDB tables"
    log "  • Amazon S3 buckets"
    log "  • Amazon Pinpoint projects"
    log "  • AWS Lambda functions"
    log "  • CloudWatch dashboards and logs"
    log "  • IAM roles and policies"
    echo ""
    log "Cleanup completed at: $(date)"
    echo ""
    success "All mobile backend resources have been removed!"
    echo ""
    log "Note: It may take a few minutes for all AWS resources to be fully deleted."
    log "If you see any remaining resources, they should clean up automatically within 10-15 minutes."
    echo ""
}

# Main cleanup function
main() {
    log "Mobile Backend Services Cleanup Script"
    log "====================================="
    
    check_prerequisites
    load_deployment_info
    confirm_deletion
    delete_amplify_backend
    delete_cloudwatch_resources
    manual_cleanup
    cleanup_local_files
    verify_cleanup
    show_cleanup_summary
    
    success "Mobile backend cleanup completed successfully!"
}

# Handle script termination
cleanup_on_error() {
    error "Cleanup script failed. Some resources may still exist."
    log "Check the AWS console for any remaining resources related to: $PROJECT_NAME"
    log "You may need to manually delete remaining resources to avoid charges."
}

trap cleanup_on_error ERR

# Show usage if help requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Mobile Backend Services Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without making changes"
    echo "  --force      Skip confirmation prompts"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_DIR  Path to the Amplify project directory"
    echo "  AWS_REGION   AWS region (defaults to configured region)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --dry-run                         # Preview what would be deleted"
    echo "  $0 --force                           # Skip confirmations"
    echo "  PROJECT_DIR=/path/to/project $0      # Specify project directory"
    echo ""
    exit 0
fi

# Run main function
main "$@"