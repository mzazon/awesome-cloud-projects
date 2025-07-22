#!/bin/bash

# Destroy Email Marketing Campaigns with Amazon SES
# This script removes all resources created by the deployment script

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            log_warning "Force delete enabled - will skip confirmation prompts"
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run  Show what would be deleted without actually deleting"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN: Would execute: $cmd"
        log "DRY-RUN: $description"
        return 0
    else
        log "$description"
        if [ "$ignore_errors" = true ]; then
            eval "$cmd" || true
        else
            eval "$cmd"
        fi
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment info
load_deployment_info() {
    log "Loading deployment information..."
    
    if [ -f ".deployment_info.sh" ]; then
        source .deployment_info.sh
        log_success "Deployment information loaded from .deployment_info.sh"
    else
        log_warning "No deployment info file found. Will prompt for resource information."
        
        # Prompt for necessary information
        if [ -z "${AWS_REGION:-}" ]; then
            export AWS_REGION=$(aws configure get region)
            if [ -z "$AWS_REGION" ]; then
                echo -n "Enter AWS region: "
                read AWS_REGION
                export AWS_REGION
            fi
        fi
        
        if [ -z "${BUCKET_NAME:-}" ]; then
            echo -n "Enter S3 bucket name to delete: "
            read BUCKET_NAME
            export BUCKET_NAME
        fi
        
        if [ -z "${CONFIG_SET_NAME:-}" ]; then
            echo -n "Enter SES configuration set name to delete: "
            read CONFIG_SET_NAME
            export CONFIG_SET_NAME
        fi
        
        if [ -z "${SNS_TOPIC_NAME:-}" ]; then
            echo -n "Enter SNS topic name to delete: "
            read SNS_TOPIC_NAME
            export SNS_TOPIC_NAME
        fi
        
        # Construct SNS topic ARN
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    fi
    
    log "Resource information:"
    log "  AWS_REGION: ${AWS_REGION:-Not set}"
    log "  BUCKET_NAME: ${BUCKET_NAME:-Not set}"
    log "  CONFIG_SET_NAME: ${CONFIG_SET_NAME:-Not set}"
    log "  SNS_TOPIC_ARN: ${SNS_TOPIC_ARN:-Not set}"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$FORCE_DELETE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This will permanently delete the following resources:"
    echo "  - S3 Bucket: ${BUCKET_NAME:-Not set}"
    echo "  - SES Configuration Set: ${CONFIG_SET_NAME:-Not set}"
    echo "  - SNS Topic: ${SNS_TOPIC_ARN:-Not set}"
    echo "  - Email Templates: welcome-campaign, product-promotion"
    echo "  - CloudWatch Dashboard: EmailMarketingDashboard"
    echo "  - CloudWatch Alarm: HighBounceRate"
    echo "  - EventBridge Rule: WeeklyEmailCampaign"
    echo
    echo "⚠️  DATA WILL BE PERMANENTLY LOST ⚠️"
    echo
    echo -n "Are you sure you want to continue? (type 'yes' to confirm): "
    read confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Deletion cancelled by user."
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to delete email templates
delete_email_templates() {
    log "Deleting email templates..."
    
    # Delete welcome campaign template
    local welcome_delete_cmd="aws sesv2 delete-email-template --template-name 'welcome-campaign'"
    if execute_cmd "$welcome_delete_cmd" "Deleting welcome campaign template" true; then
        log_success "Welcome campaign template deleted"
    else
        log_warning "Welcome campaign template may not exist or failed to delete"
    fi
    
    # Delete promotional campaign template
    local promo_delete_cmd="aws sesv2 delete-email-template --template-name 'product-promotion'"
    if execute_cmd "$promo_delete_cmd" "Deleting promotional campaign template" true; then
        log_success "Promotional campaign template deleted"
    else
        log_warning "Promotional campaign template may not exist or failed to delete"
    fi
}

# Function to delete configuration set
delete_configuration_set() {
    log "Deleting SES configuration set..."
    
    if [ -n "${CONFIG_SET_NAME:-}" ]; then
        # Delete configuration set (this removes associated event destinations)
        local config_delete_cmd="aws sesv2 delete-configuration-set --configuration-set-name ${CONFIG_SET_NAME}"
        if execute_cmd "$config_delete_cmd" "Deleting configuration set" true; then
            log_success "Configuration set deleted: $CONFIG_SET_NAME"
        else
            log_warning "Configuration set may not exist or failed to delete"
        fi
    else
        log_warning "Configuration set name not provided, skipping deletion"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic and subscriptions..."
    
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        # Delete SNS topic (this removes all subscriptions)
        local sns_delete_cmd="aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}"
        if execute_cmd "$sns_delete_cmd" "Deleting SNS topic" true; then
            log_success "SNS topic deleted: $SNS_TOPIC_ARN"
        else
            log_warning "SNS topic may not exist or failed to delete"
        fi
    else
        log_warning "SNS topic ARN not provided, skipping deletion"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        # Check if bucket exists
        if [ "$DRY_RUN" = false ]; then
            if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
                log_warning "S3 bucket ${BUCKET_NAME} does not exist, skipping deletion"
                return 0
            fi
        fi
        
        # Delete all objects in bucket (including versions)
        local objects_delete_cmd="aws s3api delete-objects --bucket ${BUCKET_NAME} --delete \"\\$(aws s3api list-object-versions --bucket ${BUCKET_NAME} --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' --output json)\" 2>/dev/null || true"
        execute_cmd "$objects_delete_cmd" "Deleting all object versions from S3 bucket" true
        
        # Delete all delete markers
        local markers_delete_cmd="aws s3api delete-objects --bucket ${BUCKET_NAME} --delete \"\\$(aws s3api list-object-versions --bucket ${BUCKET_NAME} --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' --output json)\" 2>/dev/null || true"
        execute_cmd "$markers_delete_cmd" "Deleting all delete markers from S3 bucket" true
        
        # Delete all objects using S3 CLI (fallback)
        local s3_objects_delete_cmd="aws s3 rm s3://${BUCKET_NAME} --recursive"
        execute_cmd "$s3_objects_delete_cmd" "Deleting all objects from S3 bucket (fallback)" true
        
        # Delete bucket
        local bucket_delete_cmd="aws s3 rb s3://${BUCKET_NAME} --force"
        if execute_cmd "$bucket_delete_cmd" "Deleting S3 bucket" true; then
            log_success "S3 bucket deleted: $BUCKET_NAME"
        else
            log_warning "S3 bucket may not exist or failed to delete"
        fi
    else
        log_warning "S3 bucket name not provided, skipping deletion"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    local dashboard_delete_cmd="aws cloudwatch delete-dashboards --dashboard-names 'EmailMarketingDashboard'"
    if execute_cmd "$dashboard_delete_cmd" "Deleting CloudWatch dashboard" true; then
        log_success "CloudWatch dashboard deleted"
    else
        log_warning "CloudWatch dashboard may not exist or failed to delete"
    fi
    
    # Delete CloudWatch alarms
    local alarm_delete_cmd="aws cloudwatch delete-alarms --alarm-names 'HighBounceRate'"
    if execute_cmd "$alarm_delete_cmd" "Deleting CloudWatch alarm" true; then
        log_success "CloudWatch alarm deleted"
    else
        log_warning "CloudWatch alarm may not exist or failed to delete"
    fi
}

# Function to delete EventBridge resources
delete_eventbridge_resources() {
    log "Deleting EventBridge resources..."
    
    # Delete EventBridge rule
    local rule_delete_cmd="aws events delete-rule --name 'WeeklyEmailCampaign'"
    if execute_cmd "$rule_delete_cmd" "Deleting EventBridge rule" true; then
        log_success "EventBridge rule deleted"
    else
        log_warning "EventBridge rule may not exist or failed to delete"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # List of temporary files to remove
    local temp_files=(
        "/tmp/subscribers.json"
        "/tmp/destinations.json"
        "/tmp/bounce-handler.py"
        "/tmp/campaign-role-policy.json"
        "/tmp/dashboard.json"
        "/tmp/bucket-policy.json"
        ".deployment_info.sh"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            local delete_cmd="rm -f $file"
            execute_cmd "$delete_cmd" "Deleting temporary file: $file" true
        fi
    done
    
    log_success "Temporary files cleaned up"
}

# Function to verify resource deletion
verify_deletion() {
    if [ "$DRY_RUN" = true ]; then
        log "Skipping deletion verification in dry-run mode"
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    local deletion_errors=0
    
    # Check S3 bucket deletion
    if [ -n "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            log_error "S3 bucket still exists: $BUCKET_NAME"
            deletion_errors=$((deletion_errors + 1))
        else
            log_success "S3 bucket successfully deleted: $BUCKET_NAME"
        fi
    fi
    
    # Check configuration set deletion
    if [ -n "${CONFIG_SET_NAME:-}" ]; then
        if aws sesv2 get-configuration-set --configuration-set-name "${CONFIG_SET_NAME}" &>/dev/null; then
            log_error "Configuration set still exists: $CONFIG_SET_NAME"
            deletion_errors=$((deletion_errors + 1))
        else
            log_success "Configuration set successfully deleted: $CONFIG_SET_NAME"
        fi
    fi
    
    # Check SNS topic deletion
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
            log_error "SNS topic still exists: $SNS_TOPIC_ARN"
            deletion_errors=$((deletion_errors + 1))
        else
            log_success "SNS topic successfully deleted: $SNS_TOPIC_ARN"
        fi
    fi
    
    # Check email templates deletion
    if aws sesv2 get-email-template --template-name "welcome-campaign" &>/dev/null; then
        log_error "Email template still exists: welcome-campaign"
        deletion_errors=$((deletion_errors + 1))
    else
        log_success "Email template successfully deleted: welcome-campaign"
    fi
    
    if aws sesv2 get-email-template --template-name "product-promotion" &>/dev/null; then
        log_error "Email template still exists: product-promotion"
        deletion_errors=$((deletion_errors + 1))
    else
        log_success "Email template successfully deleted: product-promotion"
    fi
    
    if [ $deletion_errors -gt 0 ]; then
        log_error "Some resources failed to delete. Manual cleanup may be required."
        return 1
    else
        log_success "All resources successfully deleted"
        return 0
    fi
}

# Function to display manual cleanup instructions
display_manual_cleanup() {
    log "📋 Manual cleanup instructions for remaining resources:"
    echo
    echo "If some resources failed to delete automatically, you can clean them up manually:"
    echo
    echo "1. Delete remaining S3 objects:"
    echo "   aws s3 rm s3://${BUCKET_NAME:-your-bucket-name} --recursive"
    echo "   aws s3 rb s3://${BUCKET_NAME:-your-bucket-name}"
    echo
    echo "2. Delete SES configuration set:"
    echo "   aws sesv2 delete-configuration-set --configuration-set-name ${CONFIG_SET_NAME:-your-config-set}"
    echo
    echo "3. Delete SNS topic:"
    echo "   aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN:-your-topic-arn}"
    echo
    echo "4. Delete email templates:"
    echo "   aws sesv2 delete-email-template --template-name welcome-campaign"
    echo "   aws sesv2 delete-email-template --template-name product-promotion"
    echo
    echo "5. Delete CloudWatch resources:"
    echo "   aws cloudwatch delete-dashboards --dashboard-names EmailMarketingDashboard"
    echo "   aws cloudwatch delete-alarms --alarm-names HighBounceRate"
    echo
    echo "6. Delete EventBridge rule:"
    echo "   aws events delete-rule --name WeeklyEmailCampaign"
    echo
    echo "7. Review and delete any remaining email identities in SES console if no longer needed"
    echo
}

# Main destruction function
main() {
    log "Starting Email Marketing Campaign resource cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment info
    load_deployment_info
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_eventbridge_resources
    delete_cloudwatch_resources
    delete_email_templates
    delete_configuration_set
    delete_sns_topic
    delete_s3_bucket
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Verify deletion
    if verify_deletion; then
        log_success "Email Marketing Campaign resources successfully cleaned up!"
    else
        log_warning "Some resources may require manual cleanup"
        display_manual_cleanup
    fi
    
    echo
    log "🎉 Cleanup process completed!"
    echo
    log "💡 Note: Email identities in SES were not deleted automatically."
    echo "If you no longer need them, delete them manually in the SES console:"
    echo "https://console.aws.amazon.com/sesv2/home?region=${AWS_REGION:-us-east-1}#/identities"
    echo
    log "📊 For cost optimization, also consider:"
    echo "- Reviewing CloudWatch log groups for any remaining log data"
    echo "- Checking for any unused IAM roles or policies"
    echo "- Reviewing any remaining Lambda functions if automation was implemented"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"