#!/bin/bash

# Interactive Data Analytics with Bedrock AgentCore Code Interpreter - Cleanup Script
# This script destroys all infrastructure created by the deploy.sh script including
# S3 buckets, Lambda functions, Bedrock Code Interpreter, IAM roles, and CloudWatch resources.

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE_DESTROY=false
SKIP_CONFIRMATION=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Interactive Data Analytics with Bedrock AgentCore Code Interpreter Infrastructure

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be destroyed without making changes
    -f, --force             Force destruction without confirmation prompts
    -y, --yes               Skip confirmation prompts (same as --force)
    --region REGION         AWS region (default: from AWS CLI config)
    --suffix SUFFIX         Resource suffix to target for deletion (required)
    --deployment-file FILE  Load resource names from deployment info file
    --debug                 Enable debug logging

EXAMPLES:
    $0 --suffix abc123                          # Destroy resources with suffix
    $0 --deployment-file deployment_info_abc123.json  # Load from deployment file
    $0 --suffix abc123 --dry-run               # Preview destruction
    $0 --suffix abc123 --force                 # Destroy without prompts

SAFETY:
    - This script requires explicit confirmation before destroying resources
    - Use --dry-run to preview what would be destroyed
    - Backup important data before running this script
    - All S3 data will be permanently deleted

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force|-y|--yes)
                FORCE_DESTROY=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --suffix)
                RESOURCE_SUFFIX="$2"
                shift 2
                ;;
            --deployment-file)
                DEPLOYMENT_FILE="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "${RESOURCE_SUFFIX:-}" && -z "${DEPLOYMENT_FILE:-}" ]]; then
        log ERROR "Either --suffix or --deployment-file must be specified"
        usage
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log ERROR "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    log INFO "Prerequisites check completed successfully"
}

# Load deployment information
load_deployment_info() {
    log INFO "Loading deployment information..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            log WARN "No region configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Load from deployment file if provided
    if [[ -n "${DEPLOYMENT_FILE:-}" ]]; then
        if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
            log ERROR "Deployment file not found: $DEPLOYMENT_FILE"
            exit 1
        fi
        
        log INFO "Loading resource names from: $DEPLOYMENT_FILE"
        
        RESOURCE_SUFFIX=$(jq -r '.deployment_id' "$DEPLOYMENT_FILE")
        export BUCKET_RAW_DATA=$(jq -r '.resources.s3_buckets.raw_data' "$DEPLOYMENT_FILE")
        export BUCKET_RESULTS=$(jq -r '.resources.s3_buckets.results' "$DEPLOYMENT_FILE")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function' "$DEPLOYMENT_FILE")
        export CODE_INTERPRETER_ID=$(jq -r '.resources.code_interpreter' "$DEPLOYMENT_FILE")
        export IAM_ROLE_NAME=$(jq -r '.resources.iam_role' "$DEPLOYMENT_FILE")
        export DLQ_NAME=$(jq -r '.resources.sqs_dlq' "$DEPLOYMENT_FILE")
        
        # Extract API Gateway ID from endpoint if present
        local api_endpoint=$(jq -r '.resources.api_endpoint // empty' "$DEPLOYMENT_FILE")
        if [[ -n "$api_endpoint" && "$api_endpoint" != "null" ]]; then
            export API_ID=$(echo "$api_endpoint" | sed -n 's/.*\/\/\([^.]*\)\.execute-api\..*/\1/p')
        fi
    else
        # Generate resource names from suffix
        log INFO "Generating resource names from suffix: $RESOURCE_SUFFIX"
        
        export BUCKET_RAW_DATA="analytics-raw-data-${RESOURCE_SUFFIX}"
        export BUCKET_RESULTS="analytics-results-${RESOURCE_SUFFIX}"
        export LAMBDA_FUNCTION_NAME="analytics-orchestrator-${RESOURCE_SUFFIX}"
        export CODE_INTERPRETER_NAME="analytics-interpreter-${RESOURCE_SUFFIX}"
        export IAM_ROLE_NAME="analytics-execution-role-${RESOURCE_SUFFIX}"
        export API_GATEWAY_NAME="analytics-api-${RESOURCE_SUFFIX}"
        export DLQ_NAME="analytics-dlq-${RESOURCE_SUFFIX}"
    fi
    
    log INFO "Target resources for deletion:"
    log INFO "  Region: $AWS_REGION"
    log INFO "  Suffix: $RESOURCE_SUFFIX"
    log DEBUG "  S3 Raw Data Bucket: $BUCKET_RAW_DATA"
    log DEBUG "  S3 Results Bucket: $BUCKET_RESULTS"
    log DEBUG "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log DEBUG "  IAM Role: $IAM_ROLE_NAME"
    log DEBUG "  SQS DLQ: $DLQ_NAME"
}

# Discover existing resources
discover_resources() {
    log INFO "Discovering existing resources..."
    
    RESOURCES_TO_DELETE=()
    
    # Check S3 buckets
    if aws s3 ls "s3://$BUCKET_RAW_DATA" &> /dev/null; then
        RESOURCES_TO_DELETE+=("S3 Bucket: $BUCKET_RAW_DATA")
        log DEBUG "Found S3 bucket: $BUCKET_RAW_DATA"
    fi
    
    if aws s3 ls "s3://$BUCKET_RESULTS" &> /dev/null; then
        RESOURCES_TO_DELETE+=("S3 Bucket: $BUCKET_RESULTS")
        log DEBUG "Found S3 bucket: $BUCKET_RESULTS"
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        RESOURCES_TO_DELETE+=("Lambda Function: $LAMBDA_FUNCTION_NAME")
        log DEBUG "Found Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Check Code Interpreter
    if [[ -n "${CODE_INTERPRETER_ID:-}" ]] && \
       aws bedrock-agentcore get-code-interpreter --code-interpreter-identifier "$CODE_INTERPRETER_ID" &> /dev/null; then
        RESOURCES_TO_DELETE+=("Bedrock Code Interpreter: $CODE_INTERPRETER_ID")
        log DEBUG "Found Code Interpreter: $CODE_INTERPRETER_ID"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        RESOURCES_TO_DELETE+=("IAM Role: $IAM_ROLE_NAME")
        log DEBUG "Found IAM role: $IAM_ROLE_NAME"
    fi
    
    # Check SQS queue
    local queue_url=$(aws sqs get-queue-url --queue-name "$DLQ_NAME" --query 'QueueUrl' --output text 2>/dev/null || echo "")
    if [[ -n "$queue_url" ]]; then
        RESOURCES_TO_DELETE+=("SQS Queue: $DLQ_NAME")
        export DLQ_URL="$queue_url"
        log DEBUG "Found SQS queue: $DLQ_NAME"
    fi
    
    # Check API Gateway (if API_ID is available)
    if [[ -n "${API_ID:-}" ]] && aws apigateway get-rest-api --rest-api-id "$API_ID" &> /dev/null; then
        RESOURCES_TO_DELETE+=("API Gateway: $API_ID")
        log DEBUG "Found API Gateway: $API_ID"
    fi
    
    # Check CloudWatch resources
    local log_groups=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$LAMBDA_FUNCTION_NAME" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
    if [[ -n "$log_groups" ]]; then
        RESOURCES_TO_DELETE+=("CloudWatch Log Groups: Lambda")
        log DEBUG "Found CloudWatch log groups for Lambda"
    fi
    
    local alarms=$(aws cloudwatch describe-alarms --alarm-name-prefix "Analytics-" --query 'MetricAlarms[?ends_with(AlarmName, `-'$RESOURCE_SUFFIX'`)].AlarmName' --output text 2>/dev/null || echo "")
    if [[ -n "$alarms" ]]; then
        RESOURCES_TO_DELETE+=("CloudWatch Alarms: ${alarms}")
        export CLOUDWATCH_ALARMS="$alarms"
        log DEBUG "Found CloudWatch alarms: $alarms"
    fi
    
    local dashboard=$(aws cloudwatch list-dashboards --dashboard-name-prefix "Analytics-Dashboard-$RESOURCE_SUFFIX" --query 'DashboardEntries[0].DashboardName' --output text 2>/dev/null || echo "")
    if [[ -n "$dashboard" && "$dashboard" != "None" ]]; then
        RESOURCES_TO_DELETE+=("CloudWatch Dashboard: $dashboard")
        export CLOUDWATCH_DASHBOARD="$dashboard"
        log DEBUG "Found CloudWatch dashboard: $dashboard"
    fi
    
    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        log WARN "No resources found with suffix: $RESOURCE_SUFFIX"
        log INFO "Resources may have already been deleted or never existed"
        exit 0
    fi
    
    log INFO "Found ${#RESOURCES_TO_DELETE[@]} resource(s) to delete"
}

# Show confirmation prompt
confirm_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would destroy the following resources:"
        for resource in "${RESOURCES_TO_DELETE[@]}"; do
            echo "  - $resource"
        done
        return 0
    fi
    
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log WARN "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo -e "${RED}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo ""
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        echo "  - $resource"
    done
    echo ""
    echo -e "${RED}⚠️  All data in S3 buckets will be permanently lost!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log INFO "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log INFO "Confirmation received. Starting destruction process..."
}

# Delete API Gateway
delete_api_gateway() {
    if [[ -z "${API_ID:-}" ]]; then
        log DEBUG "No API Gateway to delete"
        return 0
    fi
    
    log INFO "Deleting API Gateway..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete API Gateway: $API_ID"
        return 0
    fi
    
    aws apigateway delete-rest-api --rest-api-id "$API_ID" || {
        log WARN "Failed to delete API Gateway: $API_ID"
    }
    
    log INFO "API Gateway deleted: $API_ID"
}

# Delete Lambda function
delete_lambda_function() {
    log INFO "Deleting Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Remove API Gateway permission if it exists
    aws lambda remove-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id analytics-api-permission 2>/dev/null || true
    
    # Delete function
    aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" || {
        log WARN "Failed to delete Lambda function: $LAMBDA_FUNCTION_NAME"
        return 1
    }
    
    log INFO "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
}

# Delete Bedrock Code Interpreter
delete_code_interpreter() {
    if [[ -z "${CODE_INTERPRETER_ID:-}" ]]; then
        log DEBUG "No Code Interpreter to delete"
        return 0
    fi
    
    log INFO "Deleting Bedrock Code Interpreter..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete Code Interpreter: $CODE_INTERPRETER_ID"
        return 0
    fi
    
    aws bedrock-agentcore delete-code-interpreter \
        --code-interpreter-identifier "$CODE_INTERPRETER_ID" || {
        log WARN "Failed to delete Code Interpreter: $CODE_INTERPRETER_ID"
    }
    
    log INFO "Code Interpreter deleted: $CODE_INTERPRETER_ID"
}

# Delete S3 buckets
delete_s3_buckets() {
    log INFO "Deleting S3 buckets and all contents..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete S3 buckets and contents:"
        log INFO "[DRY RUN]   - $BUCKET_RAW_DATA"
        log INFO "[DRY RUN]   - $BUCKET_RESULTS"
        return 0
    fi
    
    # Delete raw data bucket
    if aws s3 ls "s3://$BUCKET_RAW_DATA" &> /dev/null; then
        log INFO "Emptying bucket: $BUCKET_RAW_DATA"
        aws s3 rm "s3://$BUCKET_RAW_DATA" --recursive || true
        
        log INFO "Deleting bucket: $BUCKET_RAW_DATA"
        aws s3 rb "s3://$BUCKET_RAW_DATA" || {
            log WARN "Failed to delete bucket: $BUCKET_RAW_DATA"
        }
    fi
    
    # Delete results bucket
    if aws s3 ls "s3://$BUCKET_RESULTS" &> /dev/null; then
        log INFO "Emptying bucket: $BUCKET_RESULTS"
        aws s3 rm "s3://$BUCKET_RESULTS" --recursive || true
        
        log INFO "Deleting bucket: $BUCKET_RESULTS"
        aws s3 rb "s3://$BUCKET_RESULTS" || {
            log WARN "Failed to delete bucket: $BUCKET_RESULTS"
        }
    fi
    
    log INFO "S3 buckets deleted"
}

# Delete SQS queue
delete_sqs_queue() {
    if [[ -z "${DLQ_URL:-}" ]]; then
        log DEBUG "No SQS queue to delete"
        return 0
    fi
    
    log INFO "Deleting SQS Dead Letter Queue..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete SQS queue: $DLQ_NAME"
        return 0
    fi
    
    aws sqs delete-queue --queue-url "$DLQ_URL" || {
        log WARN "Failed to delete SQS queue: $DLQ_NAME"
    }
    
    log INFO "SQS queue deleted: $DLQ_NAME"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log INFO "Deleting CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete CloudWatch log groups, alarms, and dashboard"
        return 0
    fi
    
    # Delete log groups
    local log_groups=(
        "/aws/lambda/$LAMBDA_FUNCTION_NAME"
        "/aws/bedrock/agentcore/$CODE_INTERPRETER_NAME"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            log DEBUG "Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" || {
                log WARN "Failed to delete log group: $log_group"
            }
        fi
    done
    
    # Delete CloudWatch alarms
    if [[ -n "${CLOUDWATCH_ALARMS:-}" ]]; then
        log DEBUG "Deleting CloudWatch alarms: $CLOUDWATCH_ALARMS"
        aws cloudwatch delete-alarms --alarm-names $CLOUDWATCH_ALARMS || {
            log WARN "Failed to delete CloudWatch alarms"
        }
    fi
    
    # Delete CloudWatch dashboard
    if [[ -n "${CLOUDWATCH_DASHBOARD:-}" ]]; then
        log DEBUG "Deleting CloudWatch dashboard: $CLOUDWATCH_DASHBOARD"
        aws cloudwatch delete-dashboards --dashboard-names "$CLOUDWATCH_DASHBOARD" || {
            log WARN "Failed to delete CloudWatch dashboard: $CLOUDWATCH_DASHBOARD"
        }
    fi
    
    log INFO "CloudWatch resources deleted"
}

# Delete IAM resources
delete_iam_resources() {
    log INFO "Deleting IAM role and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete IAM role and policies: $IAM_ROLE_NAME"
        return 0
    fi
    
    # Detach managed policies
    local managed_policies=(
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    )
    
    for policy_arn in "${managed_policies[@]}"; do
        aws iam detach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn "$policy_arn" 2>/dev/null || true
    done
    
    # Detach and delete custom policy
    local custom_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AnalyticsEnhancedPolicy-${RESOURCE_SUFFIX}"
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "$custom_policy_arn" 2>/dev/null || true
    
    aws iam delete-policy --policy-arn "$custom_policy_arn" 2>/dev/null || true
    
    # Delete IAM role
    aws iam delete-role --role-name "$IAM_ROLE_NAME" || {
        log WARN "Failed to delete IAM role: $IAM_ROLE_NAME"
    }
    
    log INFO "IAM resources deleted"
}

# Clean up deployment files
cleanup_deployment_files() {
    log INFO "Cleaning up deployment files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would clean up deployment files"
        return 0
    fi
    
    # Remove deployment info file if it exists
    local deployment_file="${SCRIPT_DIR}/deployment_info_${RESOURCE_SUFFIX}.json"
    if [[ -f "$deployment_file" ]]; then
        rm -f "$deployment_file"
        log DEBUG "Removed deployment file: $deployment_file"
    fi
    
    # Remove any temporary files
    rm -f /tmp/analytics_policy.json /tmp/lambda_function.py /tmp/lambda_function.zip
    rm -f /tmp/sample_*.csv /tmp/sample_*.json /tmp/test_event.json /tmp/response.json
    rm -f /tmp/dashboard_config.json
    
    log INFO "Deployment files cleaned up"
}

# Verify destruction
verify_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log INFO "Verifying resource deletion..."
    
    local remaining_resources=()
    
    # Check if any resources still exist
    if aws s3 ls "s3://$BUCKET_RAW_DATA" &> /dev/null; then
        remaining_resources+=("S3 Bucket: $BUCKET_RAW_DATA")
    fi
    
    if aws s3 ls "s3://$BUCKET_RESULTS" &> /dev/null; then
        remaining_resources+=("S3 Bucket: $BUCKET_RESULTS")
    fi
    
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        remaining_resources+=("Lambda Function: $LAMBDA_FUNCTION_NAME")
    fi
    
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        remaining_resources+=("IAM Role: $IAM_ROLE_NAME")
    fi
    
    if [[ ${#remaining_resources[@]} -gt 0 ]]; then
        log WARN "Some resources were not successfully deleted:"
        for resource in "${remaining_resources[@]}"; do
            log WARN "  - $resource"
        done
        log WARN "You may need to delete these manually or retry the destruction"
    else
        log INFO "All resources successfully deleted"
    fi
}

# Main destruction function
main() {
    echo "🧹 Starting Interactive Data Analytics Infrastructure Destruction"
    echo "📋 Log file: $LOG_FILE"
    echo ""
    
    # Parse arguments
    parse_args "$@"
    
    # Execute destruction steps
    check_prerequisites
    load_deployment_info
    discover_resources
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_api_gateway
    delete_cloudwatch_resources
    delete_lambda_function
    delete_code_interpreter
    delete_sqs_queue
    delete_s3_buckets
    delete_iam_resources
    cleanup_deployment_files
    verify_destruction
    
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "✅ Dry run completed successfully!"
        echo "   Run without --dry-run to perform actual deletion"
    else
        echo "✅ Destruction completed successfully!"
        echo "   All resources with suffix '$RESOURCE_SUFFIX' have been removed"
    fi
    echo ""
    
    log INFO "Destruction process completed for suffix: $RESOURCE_SUFFIX"
}

# Error handling
trap 'log ERROR "Script failed on line $LINENO"' ERR

# Run main function with all arguments
main "$@"