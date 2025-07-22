#!/bin/bash

# Cleanup script for Scheduled Email Reports with App Runner and SES
# Recipe: Delivering Scheduled Reports with App Runner and SES
# Version: 1.0

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' is not installed"
        return 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        echo "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required commands
    check_command aws || exit 1
    check_command jq || exit 1
    
    # Validate AWS credentials
    validate_aws_credentials
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Check if deployment-info.json exists
    if [ -f "deployment-info.json" ]; then
        log "Loading from deployment-info.json..."
        
        export AWS_REGION=$(jq -r '.aws_region' deployment-info.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-info.json)
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' deployment-info.json)
        export APP_RUNNER_SERVICE_NAME=$(jq -r '.app_runner_service_name' deployment-info.json)
        export SES_VERIFIED_EMAIL=$(jq -r '.ses_verified_email' deployment-info.json)
        export GITHUB_REPO_URL=$(jq -r '.github_repo_url' deployment-info.json)
        export SCHEDULE_NAME=$(jq -r '.schedule_name' deployment-info.json)
        export ROLE_NAME=$(jq -r '.role_name' deployment-info.json)
        export SCHEDULER_ROLE_NAME=$(jq -r '.scheduler_role_name' deployment-info.json)
        export CLOUDWATCH_ALARM=$(jq -r '.cloudwatch_alarm' deployment-info.json)
        export CLOUDWATCH_DASHBOARD=$(jq -r '.cloudwatch_dashboard' deployment-info.json)
        
        success "Deployment information loaded from file"
    else
        log "deployment-info.json not found, prompting for information..."
        prompt_for_info
    fi
    
    log "Using configuration:"
    log "  AWS Region: $AWS_REGION"
    log "  Service Name: $APP_RUNNER_SERVICE_NAME"
    log "  Schedule Name: $SCHEDULE_NAME"
}

# Function to prompt for deployment information if file not found
prompt_for_info() {
    warning "Deployment information file not found. Please provide the following information:"
    
    # Set AWS region if not already set
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            echo -n "Enter AWS region (default: us-east-1): "
            read user_region
            export AWS_REGION=${user_region:-us-east-1}
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Prompt for resource names or suffix
    echo -n "Enter the random suffix used during deployment (6 characters): "
    read RANDOM_SUFFIX
    export RANDOM_SUFFIX
    
    # Set resource names based on suffix
    export APP_RUNNER_SERVICE_NAME="email-reports-service-${RANDOM_SUFFIX}"
    export SCHEDULE_NAME="daily-report-schedule-${RANDOM_SUFFIX}"
    export ROLE_NAME="AppRunnerEmailReportsRole-${RANDOM_SUFFIX}"
    export SCHEDULER_ROLE_NAME="EventBridgeSchedulerRole-${RANDOM_SUFFIX}"
    export CLOUDWATCH_ALARM="EmailReports-GenerationFailures-${RANDOM_SUFFIX}"
    export CLOUDWATCH_DASHBOARD="EmailReports-Dashboard-${RANDOM_SUFFIX}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "This script will DELETE the following resources:"
    echo ""
    echo "  🗂️  App Runner Service: $APP_RUNNER_SERVICE_NAME"
    echo "  📅 EventBridge Schedule: $SCHEDULE_NAME"
    echo "  🔐 IAM Role: $ROLE_NAME"
    echo "  🔐 IAM Role: $SCHEDULER_ROLE_NAME"
    echo "  📊 CloudWatch Alarm: $CLOUDWATCH_ALARM"
    echo "  📈 CloudWatch Dashboard: $CLOUDWATCH_DASHBOARD"
    echo "  📁 Local project files (if present)"
    echo ""
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        echo -n "Are you sure you want to proceed? Type 'DELETE' to confirm: "
        read confirmation
        
        if [ "$confirmation" != "DELETE" ]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    else
        log "Force delete enabled, skipping confirmation"
    fi
    
    echo ""
    success "Confirmation received, proceeding with cleanup..."
}

# Function to delete EventBridge Schedule
delete_eventbridge_schedule() {
    log "Deleting EventBridge Schedule..."
    
    # Check if schedule exists
    if aws scheduler get-schedule --name "$SCHEDULE_NAME" &>/dev/null; then
        aws scheduler delete-schedule --name "$SCHEDULE_NAME"
        success "EventBridge Schedule deleted: $SCHEDULE_NAME"
    else
        log "EventBridge Schedule $SCHEDULE_NAME not found, skipping"
    fi
}

# Function to delete App Runner service
delete_app_runner_service() {
    log "Deleting App Runner service..."
    
    # Check if service exists
    if aws apprunner describe-service --service-name "$APP_RUNNER_SERVICE_NAME" &>/dev/null; then
        # Delete App Runner service
        aws apprunner delete-service --service-name "$APP_RUNNER_SERVICE_NAME"
        
        log "Waiting for App Runner service to be deleted (this may take several minutes)..."
        
        # Wait for service deletion with timeout
        local timeout=900  # 15 minutes
        local elapsed=0
        local interval=30
        
        while [ $elapsed -lt $timeout ]; do
            if ! aws apprunner describe-service --service-name "$APP_RUNNER_SERVICE_NAME" &>/dev/null; then
                success "App Runner service deleted successfully"
                return 0
            fi
            
            log "Still waiting for service deletion... (${elapsed}s elapsed)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        error "Timeout waiting for App Runner service deletion"
        log "Service may still be deleting in the background"
    else
        log "App Runner service $APP_RUNNER_SERVICE_NAME not found, skipping"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete App Runner IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        # Delete attached policies first
        aws iam delete-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name EmailReportsPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME"
        success "IAM role deleted: $ROLE_NAME"
    else
        log "IAM role $ROLE_NAME not found, skipping"
    fi
    
    # Delete EventBridge Scheduler IAM role
    if aws iam get-role --role-name "$SCHEDULER_ROLE_NAME" &>/dev/null; then
        # Delete attached policies first
        aws iam delete-role-policy \
            --role-name "$SCHEDULER_ROLE_NAME" \
            --policy-name SchedulerHttpPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name "$SCHEDULER_ROLE_NAME"
        success "IAM role deleted: $SCHEDULER_ROLE_NAME"
    else
        log "IAM role $SCHEDULER_ROLE_NAME not found, skipping"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names "$CLOUDWATCH_ALARM" 2>/dev/null | grep -q "MetricAlarms"; then
        aws cloudwatch delete-alarms --alarm-names "$CLOUDWATCH_ALARM"
        success "CloudWatch alarm deleted: $CLOUDWATCH_ALARM"
    else
        log "CloudWatch alarm $CLOUDWATCH_ALARM not found, skipping"
    fi
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "$CLOUDWATCH_DASHBOARD" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$CLOUDWATCH_DASHBOARD"
        success "CloudWatch dashboard deleted: $CLOUDWATCH_DASHBOARD"
    else
        log "CloudWatch dashboard $CLOUDWATCH_DASHBOARD not found, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove project directory if it exists
    if [ -d "email-reports-app" ]; then
        if [ "${SKIP_LOCAL_CLEANUP:-false}" != "true" ]; then
            echo -n "Delete local project directory 'email-reports-app'? (y/n): "
            read delete_local
            if [ "$delete_local" = "y" ] || [ "$delete_local" = "Y" ]; then
                rm -rf email-reports-app
                success "Local project directory removed"
            else
                log "Local project directory preserved"
            fi
        else
            log "Skipping local cleanup (SKIP_LOCAL_CLEANUP=true)"
        fi
    else
        log "Local project directory not found, skipping"
    fi
    
    # Remove deployment info file
    if [ -f "deployment-info.json" ]; then
        if [ "${KEEP_DEPLOYMENT_INFO:-false}" != "true" ]; then
            rm -f deployment-info.json
            success "Deployment info file removed"
        else
            log "Keeping deployment info file (KEEP_DEPLOYMENT_INFO=true)"
        fi
    fi
    
    # Clean up temporary files
    rm -f *.json 2>/dev/null || true
    
    # Clean up environment variables
    unset AWS_REGION AWS_ACCOUNT_ID RANDOM_SUFFIX APP_RUNNER_SERVICE_NAME
    unset SES_VERIFIED_EMAIL GITHUB_REPO_URL SCHEDULE_NAME ROLE_NAME
    unset SCHEDULER_ROLE_NAME CLOUDWATCH_ALARM CLOUDWATCH_DASHBOARD
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    log "Cleanup Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✅ Successfully cleaned up Scheduled Email Reports infrastructure${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Resources Removed:${NC}"
    echo "  🗂️  App Runner Service"
    echo "  📅 EventBridge Schedule"
    echo "  🔐 IAM Roles (2)"
    echo "  📊 CloudWatch Alarm"
    echo "  📈 CloudWatch Dashboard"
    echo ""
    echo -e "${BLUE}Notes:${NC}"
    echo "  • SES email verification is preserved (not deleted)"
    echo "  • GitHub repository is preserved (not deleted)"
    echo "  • CloudWatch logs are preserved (will expire automatically)"
    echo ""
    echo -e "${YELLOW}Cost Impact:${NC}"
    echo "  • All billable resources have been removed"
    echo "  • No further charges should be incurred"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check if App Runner service is gone
    if aws apprunner describe-service --service-name "$APP_RUNNER_SERVICE_NAME" &>/dev/null; then
        error "App Runner service still exists: $APP_RUNNER_SERVICE_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if schedule is gone
    if aws scheduler get-schedule --name "$SCHEDULE_NAME" &>/dev/null; then
        error "EventBridge Schedule still exists: $SCHEDULE_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if IAM roles are gone
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        error "IAM role still exists: $ROLE_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if aws iam get-role --role-name "$SCHEDULER_ROLE_NAME" &>/dev/null; then
        error "IAM role still exists: $SCHEDULER_ROLE_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        success "Cleanup verification completed successfully"
        return 0
    else
        error "Cleanup verification found $cleanup_errors issues"
        return 1
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Scheduled Email Reports infrastructure..."
    
    # Check if this is a dry run
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "DRY RUN MODE - No resources will be deleted"
        
        # Show what would be deleted
        log "Resources that would be deleted:"
        echo "  - App Runner Service: $APP_RUNNER_SERVICE_NAME"
        echo "  - EventBridge Schedule: $SCHEDULE_NAME"
        echo "  - IAM Roles: $ROLE_NAME, $SCHEDULER_ROLE_NAME"
        echo "  - CloudWatch Alarm: $CLOUDWATCH_ALARM"
        echo "  - CloudWatch Dashboard: $CLOUDWATCH_DASHBOARD"
        
        return 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    log "Beginning resource deletion..."
    
    delete_eventbridge_schedule
    delete_app_runner_service
    delete_iam_roles
    delete_cloudwatch_resources
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        display_cleanup_summary
        success "Cleanup completed successfully!"
    else
        warning "Cleanup completed with some issues. Please check the errors above."
        return 1
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Cleanup failed or was interrupted"
        log "Some resources may not have been deleted"
        log "You may need to manually clean up remaining resources"
    fi
}
trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --skip-local-cleanup)
            export SKIP_LOCAL_CLEANUP=true
            shift
            ;;
        --keep-deployment-info)
            export KEEP_DEPLOYMENT_INFO=true
            shift
            ;;
        --suffix)
            export RANDOM_SUFFIX="$2"
            shift 2
            ;;
        --region)
            export AWS_REGION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Clean up Scheduled Email Reports infrastructure"
            echo ""
            echo "Options:"
            echo "  --dry-run                  Show what would be deleted without deleting"
            echo "  --force                    Skip confirmation prompt"
            echo "  --skip-local-cleanup       Don't delete local project files"
            echo "  --keep-deployment-info     Keep deployment-info.json file"
            echo "  --suffix SUFFIX            Specify resource suffix (6 characters)"
            echo "  --region REGION            AWS region (default: from AWS CLI config)"
            echo "  --help, -h                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                         Interactive cleanup"
            echo "  $0 --dry-run               Preview what would be deleted"
            echo "  $0 --force                 Skip confirmation prompt"
            echo "  $0 --suffix abc123         Cleanup resources with specific suffix"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"