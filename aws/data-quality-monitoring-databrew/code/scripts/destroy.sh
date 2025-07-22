#!/bin/bash

# AWS Glue DataBrew Data Quality Monitoring - Cleanup Script
# This script removes all resources created by the deployment script
# including DataBrew datasets, profile jobs, rulesets, S3 buckets, and IAM roles

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            log "Force delete mode enabled - skipping confirmation prompts"
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run   Show what would be deleted without actually deleting"
            echo "  --force     Skip confirmation prompts"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log "$description"
    
    if [[ "$ignore_errors" == "true" ]]; then
        eval "$cmd" 2>/dev/null || {
            warning "Command failed (ignoring): $cmd"
            return 0
        }
    else
        eval "$cmd"
    fi
    
    return $?
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f ".env" ]]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found, attempting to discover resources..."
        
        # Try to get AWS region and account ID
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            error "Unable to determine AWS account ID. Please ensure AWS CLI is configured."
            exit 1
        fi
        
        warning "Some resources may not be found without the original .env file"
    fi
    
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "This will permanently delete the following resources:"
    echo "- DataBrew dataset: ${DATASET_NAME:-'<auto-discovered>'}"
    echo "- DataBrew profile job: ${PROFILE_JOB_NAME:-'<auto-discovered>'}"
    echo "- DataBrew ruleset: ${RULESET_NAME:-'<auto-discovered>'}"
    echo "- S3 bucket and all contents: ${S3_BUCKET_NAME:-'<auto-discovered>'}"
    echo "- SNS topic: ${SNS_TOPIC_NAME:-'<auto-discovered>'}"
    echo "- EventBridge rule: ${EVENTBRIDGE_RULE_NAME:-'<auto-discovered>'}"
    echo "- IAM role: ${DATABREW_ROLE_NAME:-'<auto-discovered>'}"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Auto-discover resources if not in environment
discover_resources() {
    log "Discovering AWS Glue DataBrew resources..."
    
    # Discover DataBrew datasets
    if [[ -z "$DATASET_NAME" ]]; then
        DATASETS=$(aws databrew list-datasets --query 'Datasets[?contains(Name, `customer-data`)].Name' --output text)
        if [[ -n "$DATASETS" ]]; then
            DATASET_NAME=$(echo "$DATASETS" | head -1)
            log "Discovered dataset: $DATASET_NAME"
        fi
    fi
    
    # Discover DataBrew profile jobs
    if [[ -z "$PROFILE_JOB_NAME" ]]; then
        PROFILE_JOBS=$(aws databrew list-jobs --query 'Jobs[?contains(Name, `customer-profile-job`)].Name' --output text)
        if [[ -n "$PROFILE_JOBS" ]]; then
            PROFILE_JOB_NAME=$(echo "$PROFILE_JOBS" | head -1)
            log "Discovered profile job: $PROFILE_JOB_NAME"
        fi
    fi
    
    # Discover DataBrew rulesets
    if [[ -z "$RULESET_NAME" ]]; then
        RULESETS=$(aws databrew list-rulesets --query 'Rulesets[?contains(Name, `customer-quality-rules`)].Name' --output text)
        if [[ -n "$RULESETS" ]]; then
            RULESET_NAME=$(echo "$RULESETS" | head -1)
            log "Discovered ruleset: $RULESET_NAME"
        fi
    fi
    
    # Discover S3 buckets
    if [[ -z "$S3_BUCKET_NAME" ]]; then
        S3_BUCKETS=$(aws s3 ls | grep "databrew-results" | awk '{print $3}' | head -1)
        if [[ -n "$S3_BUCKETS" ]]; then
            S3_BUCKET_NAME="$S3_BUCKETS"
            log "Discovered S3 bucket: $S3_BUCKET_NAME"
        fi
    fi
    
    # Discover SNS topics
    if [[ -z "$SNS_TOPIC_NAME" ]]; then
        SNS_TOPICS=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `data-quality-alerts`)].TopicArn' --output text)
        if [[ -n "$SNS_TOPICS" ]]; then
            SNS_TOPIC_ARN=$(echo "$SNS_TOPICS" | head -1)
            SNS_TOPIC_NAME=$(basename "$SNS_TOPIC_ARN")
            log "Discovered SNS topic: $SNS_TOPIC_NAME"
        fi
    fi
    
    # Discover EventBridge rules
    if [[ -z "$EVENTBRIDGE_RULE_NAME" ]]; then
        EVENTBRIDGE_RULES=$(aws events list-rules --query 'Rules[?contains(Name, `DataBrewQualityValidation`)].Name' --output text)
        if [[ -n "$EVENTBRIDGE_RULES" ]]; then
            EVENTBRIDGE_RULE_NAME=$(echo "$EVENTBRIDGE_RULES" | head -1)
            log "Discovered EventBridge rule: $EVENTBRIDGE_RULE_NAME"
        fi
    fi
    
    # Discover IAM roles
    if [[ -z "$DATABREW_ROLE_NAME" ]]; then
        IAM_ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `DataBrewServiceRole`)].RoleName' --output text)
        if [[ -n "$IAM_ROLES" ]]; then
            DATABREW_ROLE_NAME=$(echo "$IAM_ROLES" | head -1)
            log "Discovered IAM role: $DATABREW_ROLE_NAME"
        fi
    fi
}

# Stop running profile jobs
stop_profile_jobs() {
    log "Stopping any running profile jobs..."
    
    if [[ -n "$PROFILE_JOB_NAME" ]]; then
        # Get running job runs
        RUNNING_JOBS=$(aws databrew list-job-runs \
            --name "$PROFILE_JOB_NAME" \
            --query 'JobRuns[?State==`RUNNING`].RunId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$RUNNING_JOBS" ]]; then
            for job_run_id in $RUNNING_JOBS; do
                execute_command "aws databrew stop-job-run \
                    --name $PROFILE_JOB_NAME \
                    --run-id $job_run_id" \
                    "Stopping job run: $job_run_id" \
                    "true"
            done
        else
            log "No running profile jobs found"
        fi
    fi
}

# Delete DataBrew resources
delete_databrew_resources() {
    log "Deleting DataBrew resources..."
    
    # Delete profile job
    if [[ -n "$PROFILE_JOB_NAME" ]]; then
        execute_command "aws databrew delete-job --name $PROFILE_JOB_NAME" \
            "Deleting profile job: $PROFILE_JOB_NAME" \
            "true"
    fi
    
    # Delete ruleset
    if [[ -n "$RULESET_NAME" ]]; then
        execute_command "aws databrew delete-ruleset --name $RULESET_NAME" \
            "Deleting ruleset: $RULESET_NAME" \
            "true"
    fi
    
    # Delete dataset
    if [[ -n "$DATASET_NAME" ]]; then
        execute_command "aws databrew delete-dataset --name $DATASET_NAME" \
            "Deleting dataset: $DATASET_NAME" \
            "true"
    fi
    
    success "DataBrew resources deleted"
}

# Delete EventBridge resources
delete_eventbridge_resources() {
    log "Deleting EventBridge resources..."
    
    if [[ -n "$EVENTBRIDGE_RULE_NAME" ]]; then
        # Remove targets first
        execute_command "aws events remove-targets \
            --rule $EVENTBRIDGE_RULE_NAME \
            --ids \"1\"" \
            "Removing EventBridge rule targets" \
            "true"
        
        # Delete rule
        execute_command "aws events delete-rule --name $EVENTBRIDGE_RULE_NAME" \
            "Deleting EventBridge rule: $EVENTBRIDGE_RULE_NAME" \
            "true"
    fi
    
    success "EventBridge resources deleted"
}

# Delete SNS resources
delete_sns_resources() {
    log "Deleting SNS resources..."
    
    if [[ -n "$SNS_TOPIC_NAME" ]]; then
        if [[ -z "$SNS_TOPIC_ARN" ]]; then
            SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        fi
        
        execute_command "aws sns delete-topic --topic-arn $SNS_TOPIC_ARN" \
            "Deleting SNS topic: $SNS_TOPIC_NAME" \
            "true"
    fi
    
    success "SNS resources deleted"
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ -n "$DATABREW_ROLE_NAME" ]]; then
        # Detach managed policy
        execute_command "aws iam detach-role-policy \
            --role-name $DATABREW_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueDataBrewServiceRole" \
            "Detaching DataBrew service policy" \
            "true"
        
        # Delete inline policy
        execute_command "aws iam delete-role-policy \
            --role-name $DATABREW_ROLE_NAME \
            --policy-name S3Access" \
            "Deleting S3 access policy" \
            "true"
        
        # Delete role
        execute_command "aws iam delete-role --role-name $DATABREW_ROLE_NAME" \
            "Deleting IAM role: $DATABREW_ROLE_NAME" \
            "true"
    fi
    
    success "IAM resources deleted"
}

# Delete S3 resources
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    if [[ -n "$S3_BUCKET_NAME" ]]; then
        # Check if bucket exists
        if aws s3 ls "s3://$S3_BUCKET_NAME" &>/dev/null; then
            # Delete all objects in bucket
            execute_command "aws s3 rm s3://$S3_BUCKET_NAME --recursive" \
                "Deleting all objects in S3 bucket: $S3_BUCKET_NAME" \
                "true"
            
            # Delete bucket
            execute_command "aws s3 rb s3://$S3_BUCKET_NAME" \
                "Deleting S3 bucket: $S3_BUCKET_NAME" \
                "true"
        else
            log "S3 bucket $S3_BUCKET_NAME not found or already deleted"
        fi
    fi
    
    success "S3 resources deleted"
}

# Clean up CloudWatch logs
cleanup_cloudwatch_logs() {
    log "Cleaning up CloudWatch logs..."
    
    # Delete log groups related to DataBrew
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/databrew" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$LOG_GROUPS" ]]; then
        for log_group in $LOG_GROUPS; do
            execute_command "aws logs delete-log-group --log-group-name $log_group" \
                "Deleting CloudWatch log group: $log_group" \
                "true"
        done
    fi
    
    # Delete EventBridge log groups
    if [[ -n "$EVENTBRIDGE_RULE_NAME" ]]; then
        execute_command "aws logs delete-log-group \
            --log-group-name /aws/events/rule/$EVENTBRIDGE_RULE_NAME" \
            "Deleting EventBridge log group" \
            "true"
    fi
    
    success "CloudWatch logs cleaned up"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    execute_command "rm -f customer_data.csv" \
        "Removing customer data file" \
        "true"
    
    execute_command "rm -f databrew-trust-policy.json" \
        "Removing trust policy file" \
        "true"
    
    execute_command "rm -f databrew-s3-policy.json" \
        "Removing S3 policy file" \
        "true"
    
    execute_command "rm -f validation-report.json" \
        "Removing validation report file" \
        "true"
    
    execute_command "rm -rf ./results/" \
        "Removing results directory" \
        "true"
    
    execute_command "rm -f .env" \
        "Removing environment file" \
        "true"
    
    success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check DataBrew resources
    if [[ -n "$DATASET_NAME" ]]; then
        if aws databrew describe-dataset --name "$DATASET_NAME" &>/dev/null; then
            error "Dataset $DATASET_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ -n "$PROFILE_JOB_NAME" ]]; then
        if aws databrew describe-job --name "$PROFILE_JOB_NAME" &>/dev/null; then
            error "Profile job $PROFILE_JOB_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ -n "$RULESET_NAME" ]]; then
        if aws databrew describe-ruleset --name "$RULESET_NAME" &>/dev/null; then
            error "Ruleset $RULESET_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check S3 bucket
    if [[ -n "$S3_BUCKET_NAME" ]]; then
        if aws s3 ls "s3://$S3_BUCKET_NAME" &>/dev/null; then
            error "S3 bucket $S3_BUCKET_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check IAM role
    if [[ -n "$DATABREW_ROLE_NAME" ]]; then
        if aws iam get-role --role-name "$DATABREW_ROLE_NAME" &>/dev/null; then
            error "IAM role $DATABREW_ROLE_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "All resources successfully cleaned up"
    else
        warning "$cleanup_issues resource(s) may still exist. Please check manually."
    fi
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "The following resources have been deleted:"
    echo "- DataBrew dataset: ${DATASET_NAME:-'N/A'}"
    echo "- DataBrew profile job: ${PROFILE_JOB_NAME:-'N/A'}"
    echo "- DataBrew ruleset: ${RULESET_NAME:-'N/A'}"
    echo "- S3 bucket: ${S3_BUCKET_NAME:-'N/A'}"
    echo "- SNS topic: ${SNS_TOPIC_NAME:-'N/A'}"
    echo "- EventBridge rule: ${EVENTBRIDGE_RULE_NAME:-'N/A'}"
    echo "- IAM role: ${DATABREW_ROLE_NAME:-'N/A'}"
    echo "- CloudWatch logs: Various log groups"
    echo "- Local files: Temporary files and .env"
    echo ""
    echo "All AWS Glue DataBrew Data Quality Monitoring resources have been removed."
}

# Main execution
main() {
    log "Starting AWS Glue DataBrew Data Quality Monitoring cleanup..."
    
    # Load environment and discover resources
    load_environment
    discover_resources
    
    # Confirm deletion
    confirm_deletion
    
    # Execute cleanup steps
    stop_profile_jobs
    delete_databrew_resources
    delete_eventbridge_resources
    delete_sns_resources
    delete_iam_resources
    delete_s3_resources
    cleanup_cloudwatch_logs
    cleanup_local_files
    
    # Verify and summarize
    verify_cleanup
    display_summary
    
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"