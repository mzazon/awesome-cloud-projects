#!/bin/bash
set -e

# AWS Cost Optimization Automation - Destruction Script
# This script safely removes all resources created by the deployment script

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DESTRUCTION_LOG="destruction_$(date +%Y%m%d_%H%M%S).log"
FORCE_DESTROY=false
QUIET_MODE=false

# Function to log messages
log_message() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$QUIET_MODE" == "false" ]]; then
        case $level in
            "INFO")
                echo -e "${GREEN}[INFO]${NC} $message"
                ;;
            "WARN")
                echo -e "${YELLOW}[WARN]${NC} $message"
                ;;
            "ERROR")
                echo -e "${RED}[ERROR]${NC} $message"
                ;;
            "DEBUG")
                echo -e "${BLUE}[DEBUG]${NC} $message"
                ;;
        esac
    fi
    
    echo "[$timestamp] [$level] $message" >> "$DESTRUCTION_LOG"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -f, --force     Force destruction without confirmation prompts
    -q, --quiet     Quiet mode - suppress output except errors
    -h, --help      Show this help message

Examples:
    $0              # Interactive destruction with prompts
    $0 --force      # Force destruction without prompts
    $0 --quiet      # Quiet destruction with minimal output

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DESTROY=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_message "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to load environment variables
load_environment() {
    log_message "INFO" "Loading environment variables..."
    
    # Try to load from deployment environment file
    if [[ -f "deployment_env.txt" ]]; then
        source deployment_env.txt
        log_message "INFO" "Environment variables loaded from deployment_env.txt"
    else
        log_message "WARN" "deployment_env.txt not found, using defaults or prompting"
        
        # Set default values or prompt for missing variables
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        fi
        
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        fi
        
        # Set default resource names if not provided
        if [[ -z "$COST_OPT_ROLE" ]]; then
            export COST_OPT_ROLE="CostOptimizationLambdaRole"
        fi
        
        if [[ -z "$COST_OPT_POLICY" ]]; then
            export COST_OPT_POLICY="CostOptimizationPolicy"
        fi
        
        # If we can't determine resource names, try to find them
        if [[ -z "$COST_OPT_BUCKET" ]]; then
            export COST_OPT_BUCKET=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `cost-optimization-reports-`)].Name' --output text | head -1)
        fi
        
        if [[ -z "$COST_OPT_TABLE" ]]; then
            export COST_OPT_TABLE=$(aws dynamodb list-tables --query 'TableNames[?starts_with(@, `cost-optimization-tracking-`)]' --output text | head -1)
        fi
        
        if [[ -z "$COST_OPT_TOPIC" ]]; then
            export COST_OPT_TOPIC=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `cost-optimization-alerts-`)].TopicArn' --output text | head -1 | sed 's/.*://')
        fi
        
        if [[ -z "$COST_OPT_TOPIC_ARN" ]]; then
            export COST_OPT_TOPIC_ARN=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `cost-optimization-alerts-`)].TopicArn' --output text | head -1)
        fi
    fi
    
    log_message "INFO" "Environment variables:"
    log_message "INFO" "  AWS_REGION: $AWS_REGION"
    log_message "INFO" "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log_message "INFO" "  COST_OPT_BUCKET: $COST_OPT_BUCKET"
    log_message "INFO" "  COST_OPT_TABLE: $COST_OPT_TABLE"
    log_message "INFO" "  COST_OPT_TOPIC: $COST_OPT_TOPIC"
    log_message "INFO" "  COST_OPT_ROLE: $COST_OPT_ROLE"
}

# Function to check prerequisites
check_prerequisites() {
    log_message "INFO" "Checking prerequisites..."
    
    # Check AWS CLI installation
    if ! command -v aws &> /dev/null; then
        log_message "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_message "ERROR" "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_message "ERROR" "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    log_message "INFO" "Prerequisites check completed successfully"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        log_message "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo
    echo "========================================="
    echo "         DESTRUCTION WARNING"
    echo "========================================="
    echo
    echo "This will permanently delete the following resources:"
    echo "  • Lambda Functions:"
    echo "    - cost-optimization-analysis"
    echo "    - cost-optimization-remediation"
    echo "  • EventBridge Schedules:"
    echo "    - daily-cost-analysis"
    echo "    - weekly-comprehensive-analysis"
    echo "  • CloudWatch Dashboard: CostOptimization"
    echo "  • DynamoDB Table: $COST_OPT_TABLE"
    echo "  • S3 Bucket: $COST_OPT_BUCKET (including all contents)"
    echo "  • SNS Topic: $COST_OPT_TOPIC (including all subscriptions)"
    echo "  • IAM Role: $COST_OPT_ROLE"
    echo
    echo "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_message "INFO" "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Please type 'DELETE' to confirm: " final_confirmation
    
    if [[ "$final_confirmation" != "DELETE" ]]; then
        log_message "INFO" "Destruction cancelled by user"
        exit 0
    fi
    
    log_message "INFO" "Destruction confirmed, proceeding..."
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log_message "INFO" "Deleting Lambda functions..."
    
    # Delete cost analysis function
    if aws lambda get-function --function-name cost-optimization-analysis &> /dev/null; then
        aws lambda delete-function --function-name cost-optimization-analysis
        log_message "INFO" "Cost analysis Lambda function deleted"
    else
        log_message "WARN" "Cost analysis Lambda function not found, skipping"
    fi
    
    # Delete remediation function
    if aws lambda get-function --function-name cost-optimization-remediation &> /dev/null; then
        aws lambda delete-function --function-name cost-optimization-remediation
        log_message "INFO" "Remediation Lambda function deleted"
    else
        log_message "WARN" "Remediation Lambda function not found, skipping"
    fi
}

# Function to delete EventBridge schedules
delete_eventbridge_schedules() {
    log_message "INFO" "Deleting EventBridge schedules..."
    
    # Delete daily cost analysis schedule
    if aws scheduler get-schedule --name daily-cost-analysis --group-name cost-optimization-schedules &> /dev/null; then
        aws scheduler delete-schedule \
            --name daily-cost-analysis \
            --group-name cost-optimization-schedules
        log_message "INFO" "Daily cost analysis schedule deleted"
    else
        log_message "WARN" "Daily cost analysis schedule not found, skipping"
    fi
    
    # Delete weekly comprehensive analysis schedule
    if aws scheduler get-schedule --name weekly-comprehensive-analysis --group-name cost-optimization-schedules &> /dev/null; then
        aws scheduler delete-schedule \
            --name weekly-comprehensive-analysis \
            --group-name cost-optimization-schedules
        log_message "INFO" "Weekly comprehensive analysis schedule deleted"
    else
        log_message "WARN" "Weekly comprehensive analysis schedule not found, skipping"
    fi
    
    # Delete schedule group
    if aws scheduler get-schedule-group --name cost-optimization-schedules &> /dev/null; then
        aws scheduler delete-schedule-group --name cost-optimization-schedules
        log_message "INFO" "EventBridge schedule group deleted"
    else
        log_message "WARN" "EventBridge schedule group not found, skipping"
    fi
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log_message "INFO" "Deleting CloudWatch dashboard..."
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name CostOptimization &> /dev/null; then
        aws cloudwatch delete-dashboard --dashboard-name CostOptimization
        log_message "INFO" "CloudWatch dashboard deleted"
    else
        log_message "WARN" "CloudWatch dashboard not found, skipping"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_message "INFO" "Deleting DynamoDB table..."
    
    if [[ -z "$COST_OPT_TABLE" ]]; then
        log_message "WARN" "DynamoDB table name not provided, skipping"
        return
    fi
    
    # Check if table exists
    if aws dynamodb describe-table --table-name "$COST_OPT_TABLE" &> /dev/null; then
        # Delete DynamoDB table
        aws dynamodb delete-table --table-name "$COST_OPT_TABLE"
        log_message "INFO" "DynamoDB table $COST_OPT_TABLE deletion initiated"
        
        # Wait for table to be deleted
        log_message "INFO" "Waiting for DynamoDB table to be deleted..."
        aws dynamodb wait table-not-exists --table-name "$COST_OPT_TABLE"
        log_message "INFO" "DynamoDB table $COST_OPT_TABLE deleted successfully"
    else
        log_message "WARN" "DynamoDB table $COST_OPT_TABLE not found, skipping"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log_message "INFO" "Deleting S3 bucket..."
    
    if [[ -z "$COST_OPT_BUCKET" ]]; then
        log_message "WARN" "S3 bucket name not provided, skipping"
        return
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$COST_OPT_BUCKET" &> /dev/null; then
        # Empty bucket first
        log_message "INFO" "Emptying S3 bucket $COST_OPT_BUCKET..."
        aws s3 rm "s3://$COST_OPT_BUCKET" --recursive
        
        # Delete bucket
        aws s3 rb "s3://$COST_OPT_BUCKET"
        log_message "INFO" "S3 bucket $COST_OPT_BUCKET deleted"
    else
        log_message "WARN" "S3 bucket $COST_OPT_BUCKET not found, skipping"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log_message "INFO" "Deleting SNS topic..."
    
    if [[ -z "$COST_OPT_TOPIC_ARN" ]]; then
        log_message "WARN" "SNS topic ARN not provided, skipping"
        return
    fi
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "$COST_OPT_TOPIC_ARN" &> /dev/null; then
        # Delete SNS topic (this will also delete all subscriptions)
        aws sns delete-topic --topic-arn "$COST_OPT_TOPIC_ARN"
        log_message "INFO" "SNS topic $COST_OPT_TOPIC deleted"
    else
        log_message "WARN" "SNS topic $COST_OPT_TOPIC_ARN not found, skipping"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log_message "INFO" "Deleting IAM resources..."
    
    # Delete IAM role policy
    if aws iam get-role-policy --role-name "$COST_OPT_ROLE" --policy-name "$COST_OPT_POLICY" &> /dev/null; then
        aws iam delete-role-policy \
            --role-name "$COST_OPT_ROLE" \
            --policy-name "$COST_OPT_POLICY"
        log_message "INFO" "IAM role policy $COST_OPT_POLICY deleted"
    else
        log_message "WARN" "IAM role policy $COST_OPT_POLICY not found, skipping"
    fi
    
    # Delete IAM role
    if aws iam get-role --role-name "$COST_OPT_ROLE" &> /dev/null; then
        aws iam delete-role --role-name "$COST_OPT_ROLE"
        log_message "INFO" "IAM role $COST_OPT_ROLE deleted"
    else
        log_message "WARN" "IAM role $COST_OPT_ROLE not found, skipping"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log_message "INFO" "Cleaning up local files..."
    
    # List of files to remove
    local files_to_remove=(
        "deployment_env.txt"
        "trust-policy.json"
        "cost-optimization-policy.json"
        "dashboard-config.json"
        "response.json"
        "test-response.json"
        "lambda-functions/"
        "temp_deployment/"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log_message "INFO" "Removed $file"
        fi
    done
    
    log_message "INFO" "Local files cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log_message "INFO" "Verifying resource deletion..."
    
    local failed_deletions=()
    
    # Check Lambda functions
    if aws lambda get-function --function-name cost-optimization-analysis &> /dev/null; then
        failed_deletions+=("Lambda function: cost-optimization-analysis")
    fi
    
    if aws lambda get-function --function-name cost-optimization-remediation &> /dev/null; then
        failed_deletions+=("Lambda function: cost-optimization-remediation")
    fi
    
    # Check EventBridge schedules
    if aws scheduler get-schedule-group --name cost-optimization-schedules &> /dev/null; then
        failed_deletions+=("EventBridge schedule group: cost-optimization-schedules")
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name CostOptimization &> /dev/null; then
        failed_deletions+=("CloudWatch dashboard: CostOptimization")
    fi
    
    # Check DynamoDB table
    if [[ -n "$COST_OPT_TABLE" ]] && aws dynamodb describe-table --table-name "$COST_OPT_TABLE" &> /dev/null; then
        failed_deletions+=("DynamoDB table: $COST_OPT_TABLE")
    fi
    
    # Check S3 bucket
    if [[ -n "$COST_OPT_BUCKET" ]] && aws s3api head-bucket --bucket "$COST_OPT_BUCKET" &> /dev/null; then
        failed_deletions+=("S3 bucket: $COST_OPT_BUCKET")
    fi
    
    # Check SNS topic
    if [[ -n "$COST_OPT_TOPIC_ARN" ]] && aws sns get-topic-attributes --topic-arn "$COST_OPT_TOPIC_ARN" &> /dev/null; then
        failed_deletions+=("SNS topic: $COST_OPT_TOPIC_ARN")
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$COST_OPT_ROLE" &> /dev/null; then
        failed_deletions+=("IAM role: $COST_OPT_ROLE")
    fi
    
    if [[ ${#failed_deletions[@]} -eq 0 ]]; then
        log_message "INFO" "All resources deleted successfully"
        return 0
    else
        log_message "WARN" "Some resources failed to delete:"
        for resource in "${failed_deletions[@]}"; do
            log_message "WARN" "  - $resource"
        done
        return 1
    fi
}

# Function to display destruction summary
display_destruction_summary() {
    echo
    echo "========================================="
    echo "         DESTRUCTION SUMMARY"
    echo "========================================="
    echo
    
    if verify_deletion; then
        echo "✅ All resources have been successfully deleted"
        echo
        echo "The following resources were removed:"
        echo "  • Lambda Functions"
        echo "  • EventBridge Schedules"
        echo "  • CloudWatch Dashboard"
        echo "  • DynamoDB Table"
        echo "  • S3 Bucket"
        echo "  • SNS Topic"
        echo "  • IAM Role and Policy"
        echo "  • Local files"
        echo
        echo "Cost optimization automation has been completely removed."
    else
        echo "⚠️  Some resources may still exist"
        echo "Please check the AWS console and remove any remaining resources manually."
        echo
        echo "Resources that might need manual cleanup:"
        echo "  • Lambda function logs in CloudWatch"
        echo "  • Any remaining EventBridge rules"
        echo "  • Snapshots created by the automation"
    fi
    
    echo
    echo "Destruction log saved to: $DESTRUCTION_LOG"
    echo "========================================="
}

# Function to handle errors
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_message "ERROR" "An error occurred on line $line_number (exit code: $exit_code)"
    log_message "ERROR" "Destruction process may be incomplete"
    log_message "ERROR" "Please check the log file: $DESTRUCTION_LOG"
    exit $exit_code
}

# Main destruction function
main() {
    log_message "INFO" "Starting AWS Cost Optimization Automation destruction..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run destruction steps
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_lambda_functions
    delete_eventbridge_schedules
    delete_cloudwatch_dashboard
    delete_dynamodb_table
    delete_s3_bucket
    delete_sns_topic
    delete_iam_resources
    cleanup_local_files
    
    # Display summary
    display_destruction_summary
    
    log_message "INFO" "Destruction completed!"
}

# Set up error handling
trap 'handle_error $? $LINENO' ERR

# Handle script interruption
trap 'log_message "ERROR" "Destruction interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"