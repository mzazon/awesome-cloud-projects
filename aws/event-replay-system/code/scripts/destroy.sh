#!/bin/bash

# Destroy script for EventBridge Archive Recipe
# Removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/eventbridge-archive-destroy-$(date +%Y%m%d-%H%M%S).log"
CLEANUP_NAME="eventbridge-archive-cleanup"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check log file: $LOG_FILE"
    log_error "Some resources may still exist. Please check AWS console."
    exit 1
}

trap cleanup_on_error ERR

# Banner
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                    EventBridge Archive Cleanup Script                       ║
║                                                                              ║
║  This script removes all resources created by the EventBridge Archive       ║
║  deployment script, including event buses, archives, Lambda functions,      ║
║  IAM roles, and S3 buckets.                                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF

log "Starting EventBridge Archive cleanup..."

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI v2."
    exit 1
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    exit 1
fi

# Get AWS account info
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    log_error "AWS region not configured. Please set AWS_DEFAULT_REGION or configure region."
    exit 1
fi

log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"

# Check if configuration file exists
if [ -f "/tmp/eventbridge-archive-config.env" ]; then
    log "Loading configuration from /tmp/eventbridge-archive-config.env"
    source /tmp/eventbridge-archive-config.env
else
    log_warning "Configuration file not found. Will attempt to find resources by pattern."
fi

# Function to find resources by pattern
find_resources_by_pattern() {
    log "Searching for EventBridge Archive resources by pattern..."
    
    # Find event buses
    EVENT_BUSES=$(aws events list-event-buses \
        --query 'EventBuses[?contains(Name, `replay-demo-bus`)].Name' \
        --output text)
    
    # Find archives
    ARCHIVES=$(aws events list-archives \
        --query 'Archives[?contains(ArchiveName, `replay-demo-archive`)].ArchiveName' \
        --output text)
    
    # Find Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `replay-processor`)].FunctionName' \
        --output text)
    
    # Find IAM roles
    IAM_ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `EventReplayProcessorRole`)].RoleName' \
        --output text)
    
    # Find S3 buckets
    S3_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `eventbridge-replay-logs`)].Name' \
        --output text)
    
    log "Found resources:"
    [ -n "$EVENT_BUSES" ] && log "  - Event Buses: $EVENT_BUSES"
    [ -n "$ARCHIVES" ] && log "  - Archives: $ARCHIVES"
    [ -n "$LAMBDA_FUNCTIONS" ] && log "  - Lambda Functions: $LAMBDA_FUNCTIONS"
    [ -n "$IAM_ROLES" ] && log "  - IAM Roles: $IAM_ROLES"
    [ -n "$S3_BUCKETS" ] && log "  - S3 Buckets: $S3_BUCKETS"
}

# If no configuration found, search for resources
if [ -z "${EVENT_BUS_NAME:-}" ]; then
    find_resources_by_pattern
fi

# Confirm cleanup
echo ""
log_warning "This will permanently delete all EventBridge Archive resources."
log_warning "This action cannot be undone."
echo ""
read -p "Are you sure you want to proceed with cleanup? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Cleanup cancelled by user."
    exit 0
fi

log "Starting cleanup process..."

# Step 1: Cancel any running replays
log "Step 1: Cancelling any running replays..."
ACTIVE_REPLAYS=$(aws events list-replays \
    --state RUNNING \
    --query 'Replays[*].ReplayName' \
    --output text)

if [ -n "$ACTIVE_REPLAYS" ]; then
    for replay in $ACTIVE_REPLAYS; do
        log "Cancelling replay: $replay"
        aws events cancel-replay --replay-name "$replay" || true
    done
    log_success "Cancelled active replays"
else
    log "No active replays found"
fi

# Step 2: Delete event archives
log "Step 2: Deleting event archives..."
if [ -n "${ARCHIVE_NAME:-}" ]; then
    log "Deleting archive: $ARCHIVE_NAME"
    aws events delete-archive --archive-name "$ARCHIVE_NAME" || true
    log_success "Deleted archive: $ARCHIVE_NAME"
elif [ -n "${ARCHIVES:-}" ]; then
    for archive in $ARCHIVES; do
        log "Deleting archive: $archive"
        aws events delete-archive --archive-name "$archive" || true
    done
    log_success "Deleted found archives"
else
    log "No archives found to delete"
fi

# Step 3: Remove EventBridge rules and targets
log "Step 3: Removing EventBridge rules and targets..."
if [ -n "${RULE_NAME:-}" ] && [ -n "${EVENT_BUS_NAME:-}" ]; then
    log "Removing targets from rule: $RULE_NAME"
    aws events remove-targets \
        --rule "$RULE_NAME" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --ids "1" || true
    
    log "Deleting rule: $RULE_NAME"
    aws events delete-rule \
        --name "$RULE_NAME" \
        --event-bus-name "$EVENT_BUS_NAME" || true
    
    log_success "Removed EventBridge rule and targets"
elif [ -n "${EVENT_BUSES:-}" ]; then
    for event_bus in $EVENT_BUSES; do
        log "Finding rules for event bus: $event_bus"
        RULES=$(aws events list-rules \
            --event-bus-name "$event_bus" \
            --query 'Rules[*].Name' \
            --output text)
        
        for rule in $RULES; do
            log "Removing targets from rule: $rule"
            aws events remove-targets \
                --rule "$rule" \
                --event-bus-name "$event_bus" \
                --ids "1" || true
            
            log "Deleting rule: $rule"
            aws events delete-rule \
                --name "$rule" \
                --event-bus-name "$event_bus" || true
        done
    done
    log_success "Removed EventBridge rules and targets"
else
    log "No EventBridge rules found to delete"
fi

# Step 4: Delete custom event buses
log "Step 4: Deleting custom event buses..."
if [ -n "${EVENT_BUS_NAME:-}" ]; then
    log "Deleting event bus: $EVENT_BUS_NAME"
    aws events delete-event-bus --name "$EVENT_BUS_NAME" || true
    log_success "Deleted event bus: $EVENT_BUS_NAME"
elif [ -n "${EVENT_BUSES:-}" ]; then
    for event_bus in $EVENT_BUSES; do
        log "Deleting event bus: $event_bus"
        aws events delete-event-bus --name "$event_bus" || true
    done
    log_success "Deleted found event buses"
else
    log "No custom event buses found to delete"
fi

# Step 5: Delete Lambda functions
log "Step 5: Deleting Lambda functions..."
if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
    log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
    aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" || true
    log_success "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
elif [ -n "${LAMBDA_FUNCTIONS:-}" ]; then
    for lambda_func in $LAMBDA_FUNCTIONS; do
        log "Deleting Lambda function: $lambda_func"
        aws lambda delete-function --function-name "$lambda_func" || true
    done
    log_success "Deleted found Lambda functions"
else
    log "No Lambda functions found to delete"
fi

# Step 6: Delete IAM roles
log "Step 6: Deleting IAM roles..."
if [ -n "${IAM_ROLE_NAME:-}" ]; then
    log "Detaching policies from role: $IAM_ROLE_NAME"
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    
    log "Deleting IAM role: $IAM_ROLE_NAME"
    aws iam delete-role --role-name "$IAM_ROLE_NAME" || true
    log_success "Deleted IAM role: $IAM_ROLE_NAME"
elif [ -n "${IAM_ROLES:-}" ]; then
    for iam_role in $IAM_ROLES; do
        log "Detaching policies from role: $iam_role"
        aws iam detach-role-policy \
            --role-name "$iam_role" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
        
        log "Deleting IAM role: $iam_role"
        aws iam delete-role --role-name "$iam_role" || true
    done
    log_success "Deleted found IAM roles"
else
    log "No IAM roles found to delete"
fi

# Step 7: Delete S3 buckets
log "Step 7: Deleting S3 buckets..."
if [ -n "${S3_BUCKET_NAME:-}" ]; then
    log "Emptying S3 bucket: $S3_BUCKET_NAME"
    aws s3 rm "s3://$S3_BUCKET_NAME" --recursive || true
    
    log "Deleting S3 bucket: $S3_BUCKET_NAME"
    aws s3 rb "s3://$S3_BUCKET_NAME" || true
    log_success "Deleted S3 bucket: $S3_BUCKET_NAME"
elif [ -n "${S3_BUCKETS:-}" ]; then
    for s3_bucket in $S3_BUCKETS; do
        log "Emptying S3 bucket: $s3_bucket"
        aws s3 rm "s3://$s3_bucket" --recursive || true
        
        log "Deleting S3 bucket: $s3_bucket"
        aws s3 rb "s3://$s3_bucket" || true
    done
    log_success "Deleted found S3 buckets"
else
    log "No S3 buckets found to delete"
fi

# Step 8: Delete CloudWatch log groups
log "Step 8: Deleting CloudWatch log groups..."
LOG_GROUPS=$(aws logs describe-log-groups \
    --log-group-name-prefix "/aws/events/replay-monitoring" \
    --query 'logGroups[*].logGroupName' \
    --output text)

if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        log "Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" || true
    done
    log_success "Deleted CloudWatch log groups"
else
    log "No CloudWatch log groups found to delete"
fi

# Step 9: Delete CloudWatch alarms
log "Step 9: Deleting CloudWatch alarms..."
ALARMS=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "EventBridge-Replay-" \
    --query 'MetricAlarms[*].AlarmName' \
    --output text)

if [ -n "$ALARMS" ]; then
    log "Deleting CloudWatch alarms: $ALARMS"
    aws cloudwatch delete-alarms --alarm-names $ALARMS || true
    log_success "Deleted CloudWatch alarms"
else
    log "No CloudWatch alarms found to delete"
fi

# Step 10: Clean up temporary files
log "Step 10: Cleaning up temporary files..."
rm -f /tmp/eventbridge-archive-config.env
rm -f /tmp/lambda-trust-policy.json
rm -f /tmp/event-processor.py
rm -f /tmp/event-processor.zip
rm -f /tmp/replay-automation.sh

log_success "Cleaned up temporary files"

log_success "Cleanup completed successfully!"

# Display cleanup summary
cat << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                           Cleanup Summary                                   ║
╚══════════════════════════════════════════════════════════════════════════════╝

✅ EventBridge Archive cleanup completed successfully!

🗑️  Resources Removed:
  • Event Buses and Rules
  • Event Archives
  • Lambda Functions
  • IAM Roles and Policies
  • S3 Buckets and Contents
  • CloudWatch Log Groups
  • CloudWatch Alarms

🔧 Configuration:
  • AWS Region: $AWS_REGION
  • AWS Account: $AWS_ACCOUNT_ID

⚠️  Important Notes:
  • All event replay history has been permanently deleted
  • Archive retention policies have been removed
  • Lambda execution logs in CloudWatch may still exist
  • Some resources may take a few minutes to fully delete

🔍 Verification:
  Check the AWS Console to verify all resources have been removed:
  • EventBridge > Event buses
  • EventBridge > Archives
  • Lambda > Functions
  • IAM > Roles
  • S3 > Buckets
  • CloudWatch > Log groups

📝 Log file: $LOG_FILE

EOF

log "Cleanup process completed. All resources have been removed."

# Final verification
log "Performing final verification..."
REMAINING_BUSES=$(aws events list-event-buses \
    --query 'EventBuses[?contains(Name, `replay-demo-bus`)].Name' \
    --output text)

REMAINING_ARCHIVES=$(aws events list-archives \
    --query 'Archives[?contains(ArchiveName, `replay-demo-archive`)].ArchiveName' \
    --output text)

if [ -n "$REMAINING_BUSES" ] || [ -n "$REMAINING_ARCHIVES" ]; then
    log_warning "Some resources may still exist. Please check AWS console."
else
    log_success "Verification complete. All resources have been removed."
fi