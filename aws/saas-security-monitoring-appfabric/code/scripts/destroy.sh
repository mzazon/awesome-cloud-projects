#!/bin/bash

# Destroy script for Centralized SaaS Security Monitoring with AWS AppFabric and EventBridge
# This script safely removes all resources created by the deploy script

set -euo pipefail

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${SCRIPT_DIR}/../temp"
DRY_RUN=false
SKIP_CONFIRMATION=false
AUTO_CONFIRM=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --auto-confirm)
            AUTO_CONFIRM=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run          Show what would be deleted without making changes"
            echo "  --yes, -y          Skip confirmation prompts"
            echo "  --auto-confirm     Skip all confirmations (used by deploy script on error)"
            echo "  --force            Force delete resources even if they have dependencies"
            echo "  --help, -h         Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY RUN mode - no resources will be deleted"
    AWS_CLI="echo aws"
else
    AWS_CLI="aws"
fi

# Load deployment variables
load_deployment_vars() {
    if [[ -f "$TEMP_DIR/deployment_vars.sh" ]]; then
        log "Loading deployment variables..."
        source "$TEMP_DIR/deployment_vars.sh"
        log_success "Deployment variables loaded"
    else
        log_error "Deployment variables file not found at $TEMP_DIR/deployment_vars.sh"
        log "This script requires the deployment variables from the deploy script."
        log "Please ensure the deploy script has been run and the temp directory exists."
        exit 1
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Verify we're in the same account
    CURRENT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$CURRENT_ACCOUNT_ID" != "$AWS_ACCOUNT_ID" ]]; then
        log_error "Current AWS account ($CURRENT_ACCOUNT_ID) doesn't match deployment account ($AWS_ACCOUNT_ID)"
        exit 1
    fi
    
    # Verify we're in the same region
    CURRENT_REGION=$(aws configure get region)
    if [[ "$CURRENT_REGION" != "$AWS_REGION" ]]; then
        log_error "Current AWS region ($CURRENT_REGION) doesn't match deployment region ($AWS_REGION)"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    log_warning "This will permanently delete the following resources:"
    echo "• S3 Bucket: $S3_BUCKET (including all objects)"
    echo "• EventBridge Bus: $EVENTBRIDGE_BUS"
    echo "• Lambda Function: $LAMBDA_FUNCTION"
    echo "• SNS Topic: $SNS_TOPIC"
    echo "• AppFabric App Bundle: $APP_BUNDLE_ARN"
    echo "• IAM Roles: AppFabricServiceRole-${RANDOM_SUFFIX}, LambdaSecurityProcessorRole-${RANDOM_SUFFIX}"
    echo
    log_warning "This action cannot be undone!"
    echo
    echo -n "Are you sure you want to continue? Type 'DELETE' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_identifier="$2"
    
    case "$resource_type" in
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_identifier" 2>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_identifier" 2>/dev/null >/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_identifier" 2>/dev/null >/dev/null
            ;;
        "eventbridge-bus")
            aws events describe-event-bus --name "$resource_identifier" 2>/dev/null >/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_identifier" 2>/dev/null >/dev/null
            ;;
        "appfabric-bundle")
            aws appfabric get-app-bundle --app-bundle-identifier "$resource_identifier" 2>/dev/null >/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Delete AppFabric resources
delete_appfabric_resources() {
    log "Removing AppFabric resources..."
    
    if [[ -z "${APP_BUNDLE_ARN:-}" ]]; then
        log_warning "APP_BUNDLE_ARN not set, skipping AppFabric cleanup"
        return 0
    fi
    
    if ! resource_exists "appfabric-bundle" "$APP_BUNDLE_ARN"; then
        log_warning "AppFabric app bundle not found, skipping"
        return 0
    fi
    
    # Delete all ingestions first
    local ingestions=$($AWS_CLI appfabric list-ingestions \
        --app-bundle-identifier "$APP_BUNDLE_ARN" \
        --query 'ingestions[].arn' --output text 2>/dev/null || echo "")
    
    if [[ -n "$ingestions" ]]; then
        log "Deleting AppFabric ingestions..."
        for ingestion_arn in $ingestions; do
            log "Deleting ingestion: $ingestion_arn"
            $AWS_CLI appfabric delete-ingestion \
                --app-bundle-identifier "$APP_BUNDLE_ARN" \
                --ingestion-identifier "$ingestion_arn" || true
            
            # Wait for ingestion deletion
            log "Waiting for ingestion deletion..."
            sleep 5
        done
    fi
    
    # Delete ingestion destinations
    local destinations=$($AWS_CLI appfabric list-ingestion-destinations \
        --app-bundle-identifier "$APP_BUNDLE_ARN" \
        --ingestion-identifier "$APP_BUNDLE_ARN" \
        --query 'ingestionDestinations[].arn' --output text 2>/dev/null || echo "")
    
    if [[ -n "$destinations" ]]; then
        log "Deleting AppFabric ingestion destinations..."
        for destination_arn in $destinations; do
            log "Deleting destination: $destination_arn"
            $AWS_CLI appfabric delete-ingestion-destination \
                --app-bundle-identifier "$APP_BUNDLE_ARN" \
                --ingestion-identifier "$APP_BUNDLE_ARN" \
                --ingestion-destination-identifier "$destination_arn" || true
        done
    fi
    
    # Wait for cleanup before deleting app bundle
    log "Waiting for AppFabric resource cleanup..."
    sleep 10
    
    # Delete AppFabric app bundle
    log "Deleting AppFabric app bundle..."
    $AWS_CLI appfabric delete-app-bundle \
        --app-bundle-identifier "$APP_BUNDLE_ARN" || true
    
    log_success "AppFabric resources deleted"
}

# Delete EventBridge resources
delete_eventbridge_resources() {
    log "Removing EventBridge resources..."
    
    local rule_name="SecurityLogProcessingRule-${RANDOM_SUFFIX}"
    
    # Remove EventBridge rule targets
    if aws events list-targets-by-rule --rule "$rule_name" --event-bus-name "$EVENTBRIDGE_BUS" 2>/dev/null | grep -q "Targets"; then
        log "Removing EventBridge rule targets..."
        $AWS_CLI events remove-targets \
            --rule "$rule_name" \
            --event-bus-name "$EVENTBRIDGE_BUS" \
            --ids "1" || true
    fi
    
    # Delete EventBridge rule
    if aws events describe-rule --name "$rule_name" --event-bus-name "$EVENTBRIDGE_BUS" 2>/dev/null >/dev/null; then
        log "Deleting EventBridge rule..."
        $AWS_CLI events delete-rule \
            --name "$rule_name" \
            --event-bus-name "$EVENTBRIDGE_BUS" || true
    fi
    
    # Delete custom event bus
    if resource_exists "eventbridge-bus" "$EVENTBRIDGE_BUS"; then
        log "Deleting EventBridge custom bus..."
        $AWS_CLI events delete-event-bus \
            --name "$EVENTBRIDGE_BUS" || true
    fi
    
    log_success "EventBridge resources deleted"
}

# Delete Lambda function
delete_lambda_function() {
    log "Removing Lambda function..."
    
    if ! resource_exists "lambda-function" "$LAMBDA_FUNCTION"; then
        log_warning "Lambda function not found, skipping"
        return 0
    fi
    
    # Remove Lambda permission for EventBridge
    $AWS_CLI lambda remove-permission \
        --function-name "$LAMBDA_FUNCTION" \
        --statement-id "eventbridge-invoke-${RANDOM_SUFFIX}" 2>/dev/null || true
    
    # Delete Lambda function
    $AWS_CLI lambda delete-function \
        --function-name "$LAMBDA_FUNCTION" || true
    
    log_success "Lambda function deleted"
}

# Delete SNS topic and subscriptions
delete_sns_resources() {
    log "Removing SNS resources..."
    
    if [[ -z "${SNS_TOPIC_ARN:-}" ]]; then
        log_warning "SNS_TOPIC_ARN not set, skipping SNS cleanup"
        return 0
    fi
    
    if ! resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
        log_warning "SNS topic not found, skipping"
        return 0
    fi
    
    # List and delete all subscriptions
    local subscriptions=$($AWS_CLI sns list-subscriptions-by-topic \
        --topic-arn "$SNS_TOPIC_ARN" \
        --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null || echo "")
    
    if [[ -n "$subscriptions" ]]; then
        log "Deleting SNS subscriptions..."
        for sub_arn in $subscriptions; do
            if [[ "$sub_arn" != "PendingConfirmation" ]]; then
                log "Deleting subscription: $sub_arn"
                $AWS_CLI sns unsubscribe --subscription-arn "$sub_arn" || true
            fi
        done
    fi
    
    # Delete SNS topic
    log "Deleting SNS topic..."
    $AWS_CLI sns delete-topic --topic-arn "$SNS_TOPIC_ARN" || true
    
    log_success "SNS resources deleted"
}

# Empty and delete S3 bucket
delete_s3_bucket() {
    log "Removing S3 bucket..."
    
    if ! resource_exists "s3-bucket" "$S3_BUCKET"; then
        log_warning "S3 bucket not found, skipping"
        return 0
    fi
    
    # Remove bucket notification configuration
    log "Removing S3 bucket notifications..."
    $AWS_CLI s3api put-bucket-notification-configuration \
        --bucket "$S3_BUCKET" \
        --notification-configuration '{}' 2>/dev/null || true
    
    # Empty bucket (including versioned objects)
    log "Emptying S3 bucket (this may take a while for large buckets)..."
    
    # Delete all object versions
    local versions=$($AWS_CLI s3api list-object-versions \
        --bucket "$S3_BUCKET" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$versions" != "[]" ]]; then
        echo "$versions" | jq -c '.[]' | while read -r version; do
            local key=$(echo "$version" | jq -r '.Key')
            local version_id=$(echo "$version" | jq -r '.VersionId')
            $AWS_CLI s3api delete-object \
                --bucket "$S3_BUCKET" \
                --key "$key" \
                --version-id "$version_id" 2>/dev/null || true
        done
    fi
    
    # Delete all delete markers
    local delete_markers=$($AWS_CLI s3api list-object-versions \
        --bucket "$S3_BUCKET" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$delete_markers" != "[]" ]]; then
        echo "$delete_markers" | jq -c '.[]' | while read -r marker; do
            local key=$(echo "$marker" | jq -r '.Key')
            local version_id=$(echo "$marker" | jq -r '.VersionId')
            $AWS_CLI s3api delete-object \
                --bucket "$S3_BUCKET" \
                --key "$key" \
                --version-id "$version_id" 2>/dev/null || true
        done
    fi
    
    # Alternative: Use s3 rm to empty bucket
    $AWS_CLI s3 rm s3://"$S3_BUCKET" --recursive --quiet 2>/dev/null || true
    
    # Delete bucket
    log "Deleting S3 bucket..."
    $AWS_CLI s3api delete-bucket --bucket "$S3_BUCKET" || true
    
    log_success "S3 bucket deleted"
}

# Delete IAM roles and policies
delete_iam_roles() {
    log "Removing IAM roles..."
    
    local appfabric_role="AppFabricServiceRole-${RANDOM_SUFFIX}"
    local lambda_role="LambdaSecurityProcessorRole-${RANDOM_SUFFIX}"
    
    # Delete AppFabric service role
    if resource_exists "iam-role" "$appfabric_role"; then
        log "Deleting AppFabric service role..."
        
        # Delete inline policies
        local policies=$($AWS_CLI iam list-role-policies \
            --role-name "$appfabric_role" \
            --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
        
        for policy in $policies; do
            log "Deleting policy: $policy"
            $AWS_CLI iam delete-role-policy \
                --role-name "$appfabric_role" \
                --policy-name "$policy" || true
        done
        
        # Delete the role
        $AWS_CLI iam delete-role --role-name "$appfabric_role" || true
    fi
    
    # Delete Lambda execution role
    if resource_exists "iam-role" "$lambda_role"; then
        log "Deleting Lambda execution role..."
        
        # Detach managed policies
        local attached_policies=$($AWS_CLI iam list-attached-role-policies \
            --role-name "$lambda_role" \
            --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            log "Detaching policy: $policy_arn"
            $AWS_CLI iam detach-role-policy \
                --role-name "$lambda_role" \
                --policy-arn "$policy_arn" || true
        done
        
        # Delete inline policies
        local policies=$($AWS_CLI iam list-role-policies \
            --role-name "$lambda_role" \
            --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
        
        for policy in $policies; do
            log "Deleting policy: $policy"
            $AWS_CLI iam delete-role-policy \
                --role-name "$lambda_role" \
                --policy-name "$policy" || true
        done
        
        # Delete the role
        $AWS_CLI iam delete-role --role-name "$lambda_role" || true
    fi
    
    log_success "IAM roles deleted"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    if [[ -d "$TEMP_DIR" ]]; then
        # Remove all files in temp directory
        rm -rf "${TEMP_DIR:?}"/*
        
        # Remove deployment vars file
        if [[ -f "$TEMP_DIR/deployment_vars.sh" ]]; then
            rm -f "$TEMP_DIR/deployment_vars.sh"
        fi
        
        # Remove temp directory if empty
        rmdir "$TEMP_DIR" 2>/dev/null || true
    fi
    
    log_success "Local files cleaned up"
}

# Verify destruction
verify_destruction() {
    log "Verifying resource destruction..."
    
    local errors=0
    
    # Check if resources still exist
    if resource_exists "s3-bucket" "$S3_BUCKET"; then
        log_error "S3 bucket still exists: $S3_BUCKET"
        ((errors++))
    fi
    
    if resource_exists "lambda-function" "$LAMBDA_FUNCTION"; then
        log_error "Lambda function still exists: $LAMBDA_FUNCTION"
        ((errors++))
    fi
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]] && resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
        log_error "SNS topic still exists: $SNS_TOPIC_ARN"
        ((errors++))
    fi
    
    if resource_exists "eventbridge-bus" "$EVENTBRIDGE_BUS"; then
        log_error "EventBridge bus still exists: $EVENTBRIDGE_BUS"
        ((errors++))
    fi
    
    if resource_exists "iam-role" "AppFabricServiceRole-${RANDOM_SUFFIX}"; then
        log_error "AppFabric IAM role still exists"
        ((errors++))
    fi
    
    if resource_exists "iam-role" "LambdaSecurityProcessorRole-${RANDOM_SUFFIX}"; then
        log_error "Lambda IAM role still exists"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All resources successfully destroyed"
    else
        log_warning "Some resources may still exist. Please check AWS Console manually."
        log_warning "This is normal for recently deleted resources due to eventual consistency."
    fi
    
    return $errors
}

# Display destruction summary
display_summary() {
    log_success "Resource destruction completed!"
    echo
    echo "=== DESTRUCTION SUMMARY ==="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "Deployment ID: $RANDOM_SUFFIX"
    echo
    echo "=== RESOURCES REMOVED ==="
    echo "• S3 Bucket: $S3_BUCKET"
    echo "• EventBridge Bus: $EVENTBRIDGE_BUS"
    echo "• Lambda Function: $LAMBDA_FUNCTION"
    echo "• SNS Topic: $SNS_TOPIC"
    echo "• AppFabric App Bundle: ${APP_BUNDLE_ARN:-'N/A'}"
    echo "• IAM Roles: AppFabricServiceRole-${RANDOM_SUFFIX}, LambdaSecurityProcessorRole-${RANDOM_SUFFIX}"
    echo
    echo "=== POST-CLEANUP NOTES ==="
    echo "• All temporary files have been removed"
    echo "• All AWS resources have been deleted"
    echo "• No ongoing costs should be incurred"
    echo "• Email subscriptions may need manual unsubscription"
    echo
    log_warning "Note: Due to AWS eventual consistency, some resources may still appear in the console for a few minutes."
    echo
}

# Main destruction function
main() {
    log "Starting destruction of Centralized SaaS Security Monitoring resources..."
    
    # Load deployment variables first
    load_deployment_vars
    
    # Run prerequisite checks
    check_prerequisites
    
    # Show what will be deleted and confirm
    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        confirm_destruction
    fi
    
    # Delete resources in reverse order of creation
    delete_appfabric_resources
    delete_eventbridge_resources
    delete_lambda_function
    delete_sns_resources
    delete_s3_bucket
    delete_iam_roles
    cleanup_local_files
    
    # Verify destruction
    verify_destruction
    
    # Display summary
    display_summary
    
    log_success "Destruction completed successfully!"
}

# Error handling
trap 'log_error "An error occurred during destruction. Some resources may not have been deleted."' ERR

# Run main function
main "$@"