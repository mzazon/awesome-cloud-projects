#!/bin/bash

# Destroy script for Monitoring Network Traffic with VPC Flow Logs
# This script safely removes all resources created by the VPC Flow Logs deployment
# with proper confirmation prompts and error handling.

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_NAME="destroy.sh"
LOG_FILE="/tmp/vpc-flow-logs-destroy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
FORCE=false
STATE_FILE="./vpc-flow-logs-deployment-state.json"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to handle errors
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Destruction failed. Check log file: $LOG_FILE"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or use AWS IAM roles."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON parsing."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Function to load deployment state
load_deployment_state() {
    log "INFO" "Loading deployment state..."
    
    if [ ! -f "$STATE_FILE" ]; then
        log "WARN" "Deployment state file not found: $STATE_FILE"
        log "WARN" "Will attempt to discover resources using environment variables or prompts"
        return 1
    fi
    
    # Load state from file
    export AWS_REGION=$(jq -r '.aws_region' "$STATE_FILE" 2>/dev/null || echo "")
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$STATE_FILE" 2>/dev/null || echo "")
    export VPC_ID=$(jq -r '.vpc_id' "$STATE_FILE" 2>/dev/null || echo "")
    export VPC_FLOW_LOGS_BUCKET=$(jq -r '.vpc_flow_logs_bucket' "$STATE_FILE" 2>/dev/null || echo "")
    export FLOW_LOGS_GROUP=$(jq -r '.flow_logs_group' "$STATE_FILE" 2>/dev/null || echo "")
    export FLOW_LOGS_ROLE_NAME=$(jq -r '.flow_logs_role_name' "$STATE_FILE" 2>/dev/null || echo "")
    export FLOW_LOGS_ROLE_ARN=$(jq -r '.flow_logs_role_arn' "$STATE_FILE" 2>/dev/null || echo "")
    export SNS_TOPIC_NAME=$(jq -r '.sns_topic_name' "$STATE_FILE" 2>/dev/null || echo "")
    export SNS_TOPIC_ARN=$(jq -r '.sns_topic_arn' "$STATE_FILE" 2>/dev/null || echo "")
    export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name' "$STATE_FILE" 2>/dev/null || echo "")
    export FLOW_LOG_CW_ID=$(jq -r '.flow_log_cw_id' "$STATE_FILE" 2>/dev/null || echo "")
    export FLOW_LOG_S3_ID=$(jq -r '.flow_log_s3_id' "$STATE_FILE" 2>/dev/null || echo "")
    export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$STATE_FILE" 2>/dev/null || echo "")
    
    log "INFO" "Deployment state loaded successfully"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "VPC ID: $VPC_ID"
    log "INFO" "S3 Bucket: $VPC_FLOW_LOGS_BUCKET"
    
    return 0
}

# Function to setup environment when state file is missing
setup_environment_fallback() {
    log "INFO" "Setting up environment variables (fallback mode)..."
    
    # Set AWS region
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            log "WARN" "AWS region not configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    log "INFO" "Environment configured"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to discover resources by pattern
discover_resources() {
    log "INFO" "Discovering VPC Flow Logs resources..."
    
    # Discover S3 buckets
    if [ -z "$VPC_FLOW_LOGS_BUCKET" ]; then
        local buckets=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'vpc-flow-logs-${AWS_ACCOUNT_ID}')].Name" --output text)
        if [ -n "$buckets" ]; then
            export VPC_FLOW_LOGS_BUCKET=$(echo "$buckets" | head -n1)
            log "INFO" "Discovered S3 bucket: $VPC_FLOW_LOGS_BUCKET"
        fi
    fi
    
    # Discover IAM roles
    if [ -z "$FLOW_LOGS_ROLE_NAME" ]; then
        local roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, 'VPCFlowLogsRole-')].RoleName" --output text)
        if [ -n "$roles" ]; then
            export FLOW_LOGS_ROLE_NAME=$(echo "$roles" | head -n1)
            log "INFO" "Discovered IAM role: $FLOW_LOGS_ROLE_NAME"
        fi
    fi
    
    # Discover SNS topics
    if [ -z "$SNS_TOPIC_ARN" ]; then
        local topics=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'network-monitoring-alerts-')].TopicArn" --output text)
        if [ -n "$topics" ]; then
            export SNS_TOPIC_ARN=$(echo "$topics" | head -n1)
            log "INFO" "Discovered SNS topic: $SNS_TOPIC_ARN"
        fi
    fi
    
    # Discover Lambda functions
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        local functions=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'network-anomaly-detector-')].FunctionName" --output text)
        if [ -n "$functions" ]; then
            export LAMBDA_FUNCTION_NAME=$(echo "$functions" | head -n1)
            log "INFO" "Discovered Lambda function: $LAMBDA_FUNCTION_NAME"
        fi
    fi
    
    # Set default CloudWatch log group
    if [ -z "$FLOW_LOGS_GROUP" ]; then
        export FLOW_LOGS_GROUP="/aws/vpc/flowlogs"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    if [ "$FORCE" = true ]; then
        log "INFO" "Force mode enabled, skipping confirmation"
        return
    fi
    
    echo
    echo -e "${RED}WARNING: This will permanently delete the following resources:${NC}"
    echo -e "${YELLOW}• VPC Flow Logs${NC}"
    echo -e "${YELLOW}• S3 Bucket: $VPC_FLOW_LOGS_BUCKET${NC}"
    echo -e "${YELLOW}• CloudWatch Log Group: $FLOW_LOGS_GROUP${NC}"
    echo -e "${YELLOW}• CloudWatch Alarms and Metrics${NC}"
    echo -e "${YELLOW}• CloudWatch Dashboard${NC}"
    echo -e "${YELLOW}• IAM Role: $FLOW_LOGS_ROLE_NAME${NC}"
    echo -e "${YELLOW}• SNS Topic: $SNS_TOPIC_ARN${NC}"
    echo -e "${YELLOW}• Lambda Function: $LAMBDA_FUNCTION_NAME${NC}"
    echo -e "${YELLOW}• Athena Workgroup: vpc-flow-logs-workgroup${NC}"
    echo
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "INFO" "Destruction cancelled by user"
        exit 0
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "INFO" "Deleting CloudWatch resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete CloudWatch resources"
        return
    fi
    
    # Delete alarms
    local alarms=("VPC-High-Rejected-Connections" "VPC-High-Data-Transfer" "VPC-External-Connections")
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log "INFO" "Deleted CloudWatch alarm: $alarm"
        else
            log "WARN" "CloudWatch alarm not found: $alarm"
        fi
    done
    
    # Delete dashboard
    if aws cloudwatch get-dashboard --dashboard-name "VPC-Flow-Logs-Monitoring" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "VPC-Flow-Logs-Monitoring"
        log "INFO" "Deleted CloudWatch dashboard: VPC-Flow-Logs-Monitoring"
    else
        log "WARN" "CloudWatch dashboard not found: VPC-Flow-Logs-Monitoring"
    fi
    
    # Delete metric filters
    local filters=("RejectedConnections" "HighDataTransfer" "ExternalConnections")
    for filter in "${filters[@]}"; do
        if aws logs describe-metric-filters --log-group-name "$FLOW_LOGS_GROUP" --filter-name-prefix "$filter" --query 'metricFilters[0].filterName' --output text 2>/dev/null | grep -q "$filter"; then
            aws logs delete-metric-filter --log-group-name "$FLOW_LOGS_GROUP" --filter-name "$filter"
            log "INFO" "Deleted metric filter: $filter"
        else
            log "WARN" "Metric filter not found: $filter"
        fi
    done
    
    log "INFO" "CloudWatch resources deleted successfully"
}

# Function to delete Lambda function
delete_lambda_function() {
    log "INFO" "Deleting Lambda function..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        return
    fi
    
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
            log "INFO" "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
        else
            log "WARN" "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        fi
    fi
    
    # Delete Lambda execution role
    if [ -n "$RANDOM_SUFFIX" ]; then
        local lambda_role_name="lambda-execution-role-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "$lambda_role_name" &>/dev/null; then
            aws iam delete-role-policy --role-name "$lambda_role_name" --policy-name "LambdaExecutionPolicy" 2>/dev/null || true
            aws iam delete-role --role-name "$lambda_role_name"
            log "INFO" "Deleted Lambda execution role: $lambda_role_name"
        fi
    fi
    
    log "INFO" "Lambda resources deleted successfully"
}

# Function to delete VPC Flow Logs
delete_flow_logs() {
    log "INFO" "Deleting VPC Flow Logs..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete VPC Flow Logs"
        return
    fi
    
    # Delete specific flow logs if IDs are available
    if [ -n "$FLOW_LOG_CW_ID" ] && [ "$FLOW_LOG_CW_ID" != "null" ]; then
        if aws ec2 describe-flow-logs --flow-log-ids "$FLOW_LOG_CW_ID" &>/dev/null; then
            aws ec2 delete-flow-logs --flow-log-ids "$FLOW_LOG_CW_ID"
            log "INFO" "Deleted CloudWatch flow log: $FLOW_LOG_CW_ID"
        fi
    fi
    
    if [ -n "$FLOW_LOG_S3_ID" ] && [ "$FLOW_LOG_S3_ID" != "null" ]; then
        if aws ec2 describe-flow-logs --flow-log-ids "$FLOW_LOG_S3_ID" &>/dev/null; then
            aws ec2 delete-flow-logs --flow-log-ids "$FLOW_LOG_S3_ID"
            log "INFO" "Deleted S3 flow log: $FLOW_LOG_S3_ID"
        fi
    fi
    
    # Find and delete any remaining flow logs for the VPC
    if [ -n "$VPC_ID" ]; then
        local remaining_flows=$(aws ec2 describe-flow-logs \
            --filter "Name=resource-id,Values=$VPC_ID" \
            --query 'FlowLogs[?FlowLogStatus==`ACTIVE`].FlowLogId' \
            --output text)
        
        if [ -n "$remaining_flows" ]; then
            aws ec2 delete-flow-logs --flow-log-ids $remaining_flows
            log "INFO" "Deleted remaining flow logs: $remaining_flows"
        fi
    fi
    
    log "INFO" "VPC Flow Logs deleted successfully"
}

# Function to delete Athena workgroup
delete_athena_workgroup() {
    log "INFO" "Deleting Athena workgroup..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete Athena workgroup"
        return
    fi
    
    if aws athena get-work-group --work-group "vpc-flow-logs-workgroup" &>/dev/null; then
        aws athena delete-work-group --work-group "vpc-flow-logs-workgroup" --recursive-delete-option
        log "INFO" "Deleted Athena workgroup: vpc-flow-logs-workgroup"
    else
        log "WARN" "Athena workgroup not found: vpc-flow-logs-workgroup"
    fi
    
    log "INFO" "Athena resources deleted successfully"
}

# Function to delete CloudWatch Log Group
delete_log_group() {
    log "INFO" "Deleting CloudWatch Log Group..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete CloudWatch Log Group: $FLOW_LOGS_GROUP"
        return
    fi
    
    if [ -n "$FLOW_LOGS_GROUP" ]; then
        if aws logs describe-log-groups --log-group-name-prefix "$FLOW_LOGS_GROUP" --query "logGroups[?logGroupName=='$FLOW_LOGS_GROUP']" --output text | grep -q "$FLOW_LOGS_GROUP"; then
            aws logs delete-log-group --log-group-name "$FLOW_LOGS_GROUP"
            log "INFO" "Deleted CloudWatch Log Group: $FLOW_LOGS_GROUP"
        else
            log "WARN" "CloudWatch Log Group not found: $FLOW_LOGS_GROUP"
        fi
    fi
    
    log "INFO" "CloudWatch Log Group deleted successfully"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "INFO" "Deleting SNS topic..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete SNS topic: $SNS_TOPIC_ARN"
        return
    fi
    
    if [ -n "$SNS_TOPIC_ARN" ]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
            log "INFO" "Deleted SNS topic: $SNS_TOPIC_ARN"
        else
            log "WARN" "SNS topic not found: $SNS_TOPIC_ARN"
        fi
    fi
    
    log "INFO" "SNS resources deleted successfully"
}

# Function to delete IAM role
delete_iam_role() {
    log "INFO" "Deleting IAM role..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete IAM role: $FLOW_LOGS_ROLE_NAME"
        return
    fi
    
    if [ -n "$FLOW_LOGS_ROLE_NAME" ]; then
        if aws iam get-role --role-name "$FLOW_LOGS_ROLE_NAME" &>/dev/null; then
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name "$FLOW_LOGS_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$FLOW_LOGS_ROLE_NAME"
            log "INFO" "Deleted IAM role: $FLOW_LOGS_ROLE_NAME"
        else
            log "WARN" "IAM role not found: $FLOW_LOGS_ROLE_NAME"
        fi
    fi
    
    log "INFO" "IAM resources deleted successfully"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "INFO" "Deleting S3 bucket..."
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "[DRY RUN] Would delete S3 bucket: $VPC_FLOW_LOGS_BUCKET"
        return
    fi
    
    if [ -n "$VPC_FLOW_LOGS_BUCKET" ]; then
        if aws s3api head-bucket --bucket "$VPC_FLOW_LOGS_BUCKET" 2>/dev/null; then
            # Empty bucket first
            log "INFO" "Emptying S3 bucket: $VPC_FLOW_LOGS_BUCKET"
            aws s3 rm "s3://$VPC_FLOW_LOGS_BUCKET" --recursive
            
            # Delete all versions and delete markers
            aws s3api delete-objects --bucket "$VPC_FLOW_LOGS_BUCKET" \
                --delete "$(aws s3api list-object-versions --bucket "$VPC_FLOW_LOGS_BUCKET" \
                --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' --output json)" \
                2>/dev/null || true
            
            aws s3api delete-objects --bucket "$VPC_FLOW_LOGS_BUCKET" \
                --delete "$(aws s3api list-object-versions --bucket "$VPC_FLOW_LOGS_BUCKET" \
                --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' --output json)" \
                2>/dev/null || true
            
            # Delete bucket
            aws s3api delete-bucket --bucket "$VPC_FLOW_LOGS_BUCKET"
            log "INFO" "Deleted S3 bucket: $VPC_FLOW_LOGS_BUCKET"
        else
            log "WARN" "S3 bucket not found: $VPC_FLOW_LOGS_BUCKET"
        fi
    fi
    
    log "INFO" "S3 resources deleted successfully"
}

# Function to verify deletion
verify_deletion() {
    log "INFO" "Verifying resource deletion..."
    
    local failed_deletions=()
    
    # Check S3 bucket
    if [ -n "$VPC_FLOW_LOGS_BUCKET" ] && aws s3api head-bucket --bucket "$VPC_FLOW_LOGS_BUCKET" 2>/dev/null; then
        failed_deletions+=("S3 bucket: $VPC_FLOW_LOGS_BUCKET")
    fi
    
    # Check IAM role
    if [ -n "$FLOW_LOGS_ROLE_NAME" ] && aws iam get-role --role-name "$FLOW_LOGS_ROLE_NAME" &>/dev/null; then
        failed_deletions+=("IAM role: $FLOW_LOGS_ROLE_NAME")
    fi
    
    # Check SNS topic
    if [ -n "$SNS_TOPIC_ARN" ] && aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
        failed_deletions+=("SNS topic: $SNS_TOPIC_ARN")
    fi
    
    # Check Lambda function
    if [ -n "$LAMBDA_FUNCTION_NAME" ] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        failed_deletions+=("Lambda function: $LAMBDA_FUNCTION_NAME")
    fi
    
    # Check CloudWatch Log Group
    if [ -n "$FLOW_LOGS_GROUP" ] && aws logs describe-log-groups --log-group-name-prefix "$FLOW_LOGS_GROUP" --query "logGroups[?logGroupName=='$FLOW_LOGS_GROUP']" --output text | grep -q "$FLOW_LOGS_GROUP"; then
        failed_deletions+=("CloudWatch Log Group: $FLOW_LOGS_GROUP")
    fi
    
    if [ ${#failed_deletions[@]} -eq 0 ]; then
        log "INFO" "All resources deleted successfully"
    else
        log "WARN" "Some resources failed to delete:"
        for resource in "${failed_deletions[@]}"; do
            log "WARN" "  - $resource"
        done
    fi
}

# Function to clean up deployment state
cleanup_state() {
    log "INFO" "Cleaning up deployment state..."
    
    if [ -f "$STATE_FILE" ]; then
        if [ "$DRY_RUN" = false ]; then
            rm -f "$STATE_FILE"
            log "INFO" "Removed deployment state file: $STATE_FILE"
        else
            log "INFO" "[DRY RUN] Would remove deployment state file: $STATE_FILE"
        fi
    fi
}

# Function to print destruction summary
print_summary() {
    log "INFO" "Destruction completed!"
    echo
    echo -e "${GREEN}=== VPC Flow Logs Network Monitoring Destruction Summary ===${NC}"
    echo -e "${BLUE}Region:${NC} $AWS_REGION"
    echo -e "${BLUE}Resources deleted:${NC}"
    echo -e "${YELLOW}• VPC Flow Logs${NC}"
    echo -e "${YELLOW}• S3 Bucket: $VPC_FLOW_LOGS_BUCKET${NC}"
    echo -e "${YELLOW}• CloudWatch Log Group: $FLOW_LOGS_GROUP${NC}"
    echo -e "${YELLOW}• CloudWatch Alarms and Metrics${NC}"
    echo -e "${YELLOW}• CloudWatch Dashboard${NC}"
    echo -e "${YELLOW}• IAM Role: $FLOW_LOGS_ROLE_NAME${NC}"
    echo -e "${YELLOW}• SNS Topic: $SNS_TOPIC_ARN${NC}"
    echo -e "${YELLOW}• Lambda Function: $LAMBDA_FUNCTION_NAME${NC}"
    echo -e "${YELLOW}• Athena Workgroup: vpc-flow-logs-workgroup${NC}"
    echo
    echo -e "${BLUE}Destruction log:${NC} $LOG_FILE"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Destroy VPC Flow Logs network monitoring infrastructure"
    echo
    echo "Options:"
    echo "  --dry-run          Show what would be deleted without making changes"
    echo "  --force            Skip confirmation prompts"
    echo "  --state-file FILE  Specify deployment state file (default: ./vpc-flow-logs-deployment-state.json)"
    echo "  --help             Show this help message"
    echo
    echo "Environment Variables (optional):"
    echo "  AWS_REGION         AWS region (default: from state file or AWS CLI config)"
    echo
}

# Main destruction function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --state-file)
                STATE_FILE="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    log "INFO" "Starting VPC Flow Logs network monitoring destruction"
    log "INFO" "Script: $SCRIPT_NAME"
    log "INFO" "Log file: $LOG_FILE"
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Execute destruction steps
    check_prerequisites
    
    # Try to load deployment state, fallback to discovery if not available
    if ! load_deployment_state; then
        setup_environment_fallback
        discover_resources
    fi
    
    # Show what will be deleted and confirm
    confirm_destruction
    
    # Execute deletion in reverse order of creation
    delete_cloudwatch_resources
    delete_lambda_function
    delete_flow_logs
    delete_athena_workgroup
    delete_log_group
    delete_sns_topic
    delete_iam_role
    delete_s3_bucket
    
    if [ "$DRY_RUN" = false ]; then
        verify_deletion
        cleanup_state
        print_summary
    else
        log "INFO" "DRY RUN completed - no resources were deleted"
    fi
}

# Cleanup on script exit
cleanup() {
    log "DEBUG" "Cleaning up temporary files..."
    # No temporary files to clean up in destroy script
}

# Set trap for cleanup
trap cleanup EXIT

# Run main function
main "$@"