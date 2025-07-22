#!/bin/bash

# Destroy Cost Allocation and Chargeback Systems
# This script removes all infrastructure created by the deploy.sh script
# for the Cost Allocation and Chargeback Systems recipe

set -euo pipefail

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "=== DESTRUCTION WARNING ==="
    echo "This script will permanently delete the following resources:"
    echo "• S3 bucket and all cost reports"
    echo "• Lambda function and IAM role"
    echo "• SNS topic and subscriptions"
    echo "• AWS Budgets and notifications"
    echo "• EventBridge rules and targets"
    echo "• Cost anomaly detection configuration"
    echo "• Cost and Usage Reports configuration"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding..."
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env" ]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found. Attempting to derive values..."
        
        # Try to derive values from existing resources
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to find resources by pattern
        COST_BUCKETS=$(aws s3 ls | grep "cost-allocation-reports-" | awk '{print $3}' || echo "")
        SNS_TOPICS=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `cost-allocation-alerts`)].TopicArn' --output text || echo "")
        LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `cost-allocation-processor`)].FunctionName' --output text || echo "")
        
        if [ -n "$COST_BUCKETS" ]; then
            export COST_BUCKET_NAME=$(echo "$COST_BUCKETS" | head -n1)
        fi
        
        if [ -n "$SNS_TOPICS" ]; then
            export SNS_TOPIC_ARN=$(echo "$SNS_TOPICS" | head -n1)
            export SNS_TOPIC_NAME=$(echo "$SNS_TOPIC_ARN" | awk -F: '{print $6}')
        fi
        
        if [ -n "$LAMBDA_FUNCTIONS" ]; then
            export LAMBDA_FUNCTION_NAME=$(echo "$LAMBDA_FUNCTIONS" | head -n1)
        fi
        
        warning "Some environment variables may be missing. Cleanup will be best-effort."
    fi
    
    log "Current configuration:"
    log "Region: ${AWS_REGION:-'Not set'}"
    log "Account ID: ${AWS_ACCOUNT_ID:-'Not set'}"
    log "S3 Bucket: ${COST_BUCKET_NAME:-'Not set'}"
    log "SNS Topic: ${SNS_TOPIC_NAME:-'Not set'}"
    log "Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Not set'}"
}

# Function to remove EventBridge schedule
remove_eventbridge_schedule() {
    log "Removing EventBridge schedule..."
    
    # Remove targets from rule
    if aws events describe-rule --name cost-allocation-schedule > /dev/null 2>&1; then
        aws events remove-targets \
            --rule cost-allocation-schedule \
            --ids "1" > /dev/null 2>&1 || true
        
        # Delete rule
        aws events delete-rule \
            --name cost-allocation-schedule > /dev/null 2>&1 || true
        
        success "EventBridge schedule removed"
    else
        warning "EventBridge schedule not found"
    fi
}

# Function to remove Lambda function and role
remove_lambda_resources() {
    log "Removing Lambda function and IAM role..."
    
    # Remove Lambda permission
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id cost-allocation-schedule > /dev/null 2>&1 || true
        
        # Delete Lambda function
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" > /dev/null 2>&1; then
            aws lambda delete-function \
                --function-name "$LAMBDA_FUNCTION_NAME" > /dev/null
            success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        else
            warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        fi
        
        # Delete IAM role and policies
        ROLE_NAME="${LAMBDA_FUNCTION_NAME}-role"
        
        # Remove inline policy
        aws iam delete-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-name CostAllocationPolicy > /dev/null 2>&1 || true
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null 2>&1 || true
        
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess > /dev/null 2>&1 || true
        
        # Delete role
        if aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
            aws iam delete-role --role-name "$ROLE_NAME" > /dev/null
            success "IAM role deleted: $ROLE_NAME"
        else
            warning "IAM role not found: $ROLE_NAME"
        fi
    else
        warning "Lambda function name not set, skipping Lambda cleanup"
    fi
}

# Function to remove budgets
remove_budgets() {
    log "Removing AWS Budgets..."
    
    # List of budget names to remove
    BUDGET_NAMES=("Engineering-Monthly-Budget" "Marketing-Monthly-Budget")
    
    for budget_name in "${BUDGET_NAMES[@]}"; do
        if aws budgets describe-budget \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget-name "$budget_name" > /dev/null 2>&1; then
            
            aws budgets delete-budget \
                --account-id "$AWS_ACCOUNT_ID" \
                --budget-name "$budget_name" > /dev/null
            
            success "Budget deleted: $budget_name"
        else
            warning "Budget not found: $budget_name"
        fi
    done
}

# Function to remove cost anomaly detection
remove_anomaly_detection() {
    log "Removing cost anomaly detection..."
    
    # Get anomaly detectors
    DETECTOR_ARNS=$(aws ce get-anomaly-detectors \
        --query 'AnomalyDetectors[?DetectorName==`DepartmentCostAnomalyDetector`].DetectorArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$DETECTOR_ARNS" ] && [ "$DETECTOR_ARNS" != "None" ]; then
        # Get and delete anomaly subscriptions first
        SUBSCRIPTION_ARNS=$(aws ce get-anomaly-subscriptions \
            --query 'AnomalySubscriptions[?SubscriptionName==`CostAnomalyAlerts`].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SUBSCRIPTION_ARNS" ] && [ "$SUBSCRIPTION_ARNS" != "None" ]; then
            for subscription_arn in $SUBSCRIPTION_ARNS; do
                aws ce delete-anomaly-subscription \
                    --subscription-arn "$subscription_arn" > /dev/null 2>&1 || true
            done
            success "Anomaly subscriptions deleted"
        fi
        
        # Delete anomaly detectors
        for detector_arn in $DETECTOR_ARNS; do
            aws ce delete-anomaly-detector \
                --detector-arn "$detector_arn" > /dev/null 2>&1 || true
        done
        success "Anomaly detectors deleted"
    else
        warning "No anomaly detectors found"
    fi
}

# Function to remove SNS topic
remove_sns_topic() {
    log "Removing SNS topic..."
    
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" > /dev/null 2>&1; then
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" > /dev/null
            success "SNS topic deleted: $SNS_TOPIC_ARN"
        else
            warning "SNS topic not found: $SNS_TOPIC_ARN"
        fi
    else
        warning "SNS topic ARN not set, attempting to find and delete topics..."
        
        # Try to find and delete topics by name pattern
        TOPIC_ARNS=$(aws sns list-topics \
            --query 'Topics[?contains(TopicArn, `cost-allocation-alerts`)].TopicArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$TOPIC_ARNS" ]; then
            for topic_arn in $TOPIC_ARNS; do
                aws sns delete-topic --topic-arn "$topic_arn" > /dev/null 2>&1 || true
                success "SNS topic deleted: $topic_arn"
            done
        else
            warning "No SNS topics found matching pattern"
        fi
    fi
}

# Function to remove Cost and Usage Report
remove_cur_report() {
    log "Removing Cost and Usage Report..."
    
    # Check if CUR report exists
    if aws cur describe-report-definitions \
        --query 'ReportDefinitions[?ReportName==`cost-allocation-report`]' \
        --output text | grep -q "cost-allocation-report" 2>/dev/null; then
        
        aws cur delete-report-definition \
            --report-name "cost-allocation-report" > /dev/null 2>&1 || true
        
        success "Cost and Usage Report deleted"
    else
        warning "Cost and Usage Report not found"
    fi
}

# Function to remove cost categories
remove_cost_categories() {
    log "Removing cost categories..."
    
    # Get cost category ARNs
    CATEGORY_ARNS=$(aws ce list-cost-category-definitions \
        --query 'CostCategoryReferences[?Name==`CostCenter`].CostCategoryArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$CATEGORY_ARNS" ] && [ "$CATEGORY_ARNS" != "None" ]; then
        for category_arn in $CATEGORY_ARNS; do
            aws ce delete-cost-category-definition \
                --cost-category-arn "$category_arn" > /dev/null 2>&1 || true
        done
        success "Cost categories deleted"
    else
        warning "No cost categories found"
    fi
}

# Function to remove S3 bucket
remove_s3_bucket() {
    log "Removing S3 bucket and contents..."
    
    if [ -n "${COST_BUCKET_NAME:-}" ]; then
        if aws s3 ls "s3://${COST_BUCKET_NAME}" > /dev/null 2>&1; then
            # Remove all objects first
            log "Emptying S3 bucket..."
            aws s3 rm "s3://${COST_BUCKET_NAME}" --recursive > /dev/null 2>&1 || true
            
            # Remove bucket
            aws s3 rb "s3://${COST_BUCKET_NAME}" > /dev/null 2>&1 || true
            success "S3 bucket deleted: $COST_BUCKET_NAME"
        else
            warning "S3 bucket not found: $COST_BUCKET_NAME"
        fi
    else
        warning "S3 bucket name not set, attempting to find and delete buckets..."
        
        # Try to find and delete buckets by name pattern
        BUCKET_NAMES=$(aws s3 ls | grep "cost-allocation-reports-" | awk '{print $3}' || echo "")
        
        if [ -n "$BUCKET_NAMES" ]; then
            for bucket_name in $BUCKET_NAMES; do
                log "Found bucket: $bucket_name"
                aws s3 rm "s3://${bucket_name}" --recursive > /dev/null 2>&1 || true
                aws s3 rb "s3://${bucket_name}" > /dev/null 2>&1 || true
                success "S3 bucket deleted: $bucket_name"
            done
        else
            warning "No S3 buckets found matching pattern"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f .env
        success "Environment file removed"
    fi
    
    # Remove any temporary files that might remain
    rm -f /tmp/bucket-policy.json
    rm -f /tmp/cost-category.json
    rm -f /tmp/cur-definition.json
    rm -f /tmp/sns-policy.json
    rm -f /tmp/engineering-budget.json
    rm -f /tmp/marketing-budget.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-inline-policy.json
    rm -f /tmp/cost_processor.py
    rm -f /tmp/cost_processor.zip
    rm -f /tmp/anomaly-detector.json
    rm -f /tmp/anomaly-subscription.json
    
    success "Local files cleaned up"
}

# Function to validate destruction
validate_destruction() {
    log "Validating resource destruction..."
    
    # Check if major resources still exist
    resources_remaining=0
    
    if [ -n "${COST_BUCKET_NAME:-}" ] && aws s3 ls "s3://${COST_BUCKET_NAME}" > /dev/null 2>&1; then
        warning "S3 bucket still exists: $COST_BUCKET_NAME"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" > /dev/null 2>&1; then
        warning "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    if [ -n "${SNS_TOPIC_ARN:-}" ] && aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" > /dev/null 2>&1; then
        warning "SNS topic still exists: $SNS_TOPIC_ARN"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    if [ $resources_remaining -eq 0 ]; then
        success "All major resources have been successfully destroyed"
    else
        warning "$resources_remaining major resources may still exist"
        warning "Some resources may take time to fully delete or require manual intervention"
    fi
}

# Main destruction function
main() {
    log "Starting Cost Allocation and Chargeback Systems destruction..."
    
    confirm_destruction
    load_environment
    
    # Remove resources in reverse order of creation
    remove_eventbridge_schedule
    remove_lambda_resources
    remove_budgets
    remove_anomaly_detection
    remove_sns_topic
    remove_cur_report
    remove_cost_categories
    remove_s3_bucket
    cleanup_local_files
    validate_destruction
    
    success "Destruction completed!"
    
    echo ""
    echo "=== Destruction Summary ==="
    echo "• EventBridge schedules removed"
    echo "• Lambda function and IAM role deleted"
    echo "• AWS Budgets removed"
    echo "• Cost anomaly detection disabled"
    echo "• SNS topics deleted"
    echo "• Cost and Usage Reports removed"
    echo "• Cost categories deleted"
    echo "• S3 buckets and contents removed"
    echo "• Local configuration files cleaned up"
    echo ""
    echo "Note: Some AWS billing features may take additional time to fully"
    echo "remove from your account. Cost and Usage Reports, in particular,"
    echo "may continue to appear in the billing console for a short period."
    echo ""
    success "All resources have been cleaned up successfully!"
}

# Check if running in interactive mode
if [ -t 0 ]; then
    # Interactive mode - run main function
    main "$@"
else
    # Non-interactive mode - require explicit confirmation
    echo "Error: This script requires interactive confirmation."
    echo "Please run this script in an interactive terminal."
    exit 1
fi