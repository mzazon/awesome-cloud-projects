#!/bin/bash

# Aurora Serverless v2 Cost Optimization Patterns - Cleanup Script
# This script safely removes all Aurora Serverless v2 infrastructure
# including clusters, Lambda functions, monitoring, and cost resources

set -e  # Exit on any error

# Color codes for output formatting
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or authentication failed."
        error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Look for deployment info file
    local deployment_file
    deployment_file=$(find . -name "aurora-sv2-deployment-*.json" -type f 2>/dev/null | head -1)
    
    if [[ -n "$deployment_file" && -f "$deployment_file" ]]; then
        log "Found deployment file: $deployment_file"
        
        # Extract resource information using jq if available
        if command -v jq &> /dev/null; then
            CLUSTER_NAME=$(jq -r '.cluster_name' "$deployment_file" 2>/dev/null)
            LAMBDA_ROLE_NAME=$(jq -r '.lambda_role_name' "$deployment_file" 2>/dev/null)
            CLUSTER_PARAMETER_GROUP=$(jq -r '.parameter_group_name' "$deployment_file" 2>/dev/null)
            AWS_REGION=$(jq -r '.aws_region' "$deployment_file" 2>/dev/null)
            AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$deployment_file" 2>/dev/null)
        else
            warning "jq not found. Manual resource identification required."
            return 1
        fi
        
        if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "null" ]]; then
            log "Loaded cluster name: $CLUSTER_NAME"
            return 0
        fi
    fi
    
    return 1
}

# Function to prompt for resource identification
prompt_for_resources() {
    warning "Could not automatically identify resources."
    echo
    echo "Please provide the Aurora Serverless v2 cluster name to delete:"
    echo "You can find this in the AWS RDS console or by running:"
    echo "  aws rds describe-db-clusters --query 'DBClusters[?contains(DBClusterIdentifier, \`aurora-sv2-cost-opt\`)].DBClusterIdentifier' --output table"
    echo
    read -p "Aurora cluster name: " CLUSTER_NAME
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        error "Cluster name is required for cleanup"
        exit 1
    fi
    
    # Extract suffix from cluster name for other resources
    if [[ "$CLUSTER_NAME" =~ aurora-sv2-cost-opt-(.*)$ ]]; then
        local suffix="${BASH_REMATCH[1]}"
        LAMBDA_ROLE_NAME="aurora-sv2-lambda-role-${suffix}"
        CLUSTER_PARAMETER_GROUP="aurora-sv2-params-${suffix}"
    else
        warning "Could not determine resource naming pattern. Some resources may need manual cleanup."
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo
    echo "================================"
    echo "   DESTRUCTION CONFIRMATION"
    echo "================================"
    echo
    echo "The following resources will be PERMANENTLY DELETED:"
    echo
    echo "Aurora Serverless v2 Resources:"
    echo "  ✗ Cluster: $CLUSTER_NAME"
    echo "  ✗ Writer Instance: ${CLUSTER_NAME}-writer"
    echo "  ✗ Reader Instances: ${CLUSTER_NAME}-reader-1, ${CLUSTER_NAME}-reader-2"
    echo "  ✗ Parameter Group: $CLUSTER_PARAMETER_GROUP"
    echo
    echo "Lambda Functions:"
    echo "  ✗ Cost-aware scaler: ${CLUSTER_NAME}-cost-aware-scaler"
    echo "  ✗ Auto-pause/resume: ${CLUSTER_NAME}-auto-pause-resume"
    echo
    echo "Monitoring & Cost Resources:"
    echo "  ✗ EventBridge rules and schedules"
    echo "  ✗ CloudWatch alarms"
    echo "  ✗ SNS topic for cost alerts"
    echo "  ✗ AWS Budget: Aurora-Serverless-v2-Monthly"
    echo
    echo "IAM Resources:"
    echo "  ✗ Lambda role: $LAMBDA_ROLE_NAME"
    echo "  ✗ Lambda policy: aurora-sv2-lambda-policy"
    echo
    warning "This action CANNOT be undone. All data will be lost."
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Function to remove EventBridge rules and Lambda functions
remove_lambda_and_eventbridge() {
    log "Removing EventBridge rules and Lambda functions..."
    
    # Remove EventBridge rules
    for rule_name in "${CLUSTER_NAME}-cost-aware-scaling" "${CLUSTER_NAME}-auto-pause-resume"; do
        if aws events describe-rule --name "$rule_name" &> /dev/null; then
            # Remove targets first
            aws events remove-targets --rule "$rule_name" --ids "1" 2>/dev/null || true
            # Delete rule
            aws events delete-rule --name "$rule_name"
            success "Deleted EventBridge rule: $rule_name"
        else
            log "EventBridge rule $rule_name not found, skipping"
        fi
    done
    
    # Remove Lambda functions
    for function_name in "${CLUSTER_NAME}-cost-aware-scaler" "${CLUSTER_NAME}-auto-pause-resume"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            aws lambda delete-function --function-name "$function_name"
            success "Deleted Lambda function: $function_name"
        else
            log "Lambda function $function_name not found, skipping"
        fi
    done
}

# Function to remove Aurora database instances
remove_db_instances() {
    log "Removing Aurora database instances..."
    
    local instances=("${CLUSTER_NAME}-writer" "${CLUSTER_NAME}-reader-1" "${CLUSTER_NAME}-reader-2")
    local deleted_instances=()
    
    # Delete all instances
    for instance in "${instances[@]}"; do
        if aws rds describe-db-instances --db-instance-identifier "$instance" &> /dev/null; then
            log "Deleting DB instance: $instance"
            aws rds delete-db-instance \
                --db-instance-identifier "$instance" \
                --skip-final-snapshot
            deleted_instances+=("$instance")
            success "Initiated deletion of DB instance: $instance"
        else
            log "DB instance $instance not found, skipping"
        fi
    done
    
    # Wait for instances to be deleted
    if [[ ${#deleted_instances[@]} -gt 0 ]]; then
        log "Waiting for DB instances to be deleted..."
        for instance in "${deleted_instances[@]}"; do
            log "Waiting for $instance to be deleted..."
            aws rds wait db-instance-deleted --db-instance-identifier "$instance"
            success "DB instance $instance deleted successfully"
        done
    fi
}

# Function to remove Aurora cluster
remove_aurora_cluster() {
    log "Removing Aurora Serverless v2 cluster..."
    
    if aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_NAME" &> /dev/null; then
        log "Deleting Aurora cluster: $CLUSTER_NAME"
        aws rds delete-db-cluster \
            --db-cluster-identifier "$CLUSTER_NAME" \
            --skip-final-snapshot
        
        log "Waiting for cluster to be deleted..."
        aws rds wait db-cluster-deleted --db-cluster-identifier "$CLUSTER_NAME"
        success "Aurora cluster deleted successfully"
    else
        log "Aurora cluster $CLUSTER_NAME not found, skipping"
    fi
}

# Function to remove CloudWatch alarms
remove_cloudwatch_alarms() {
    log "Removing CloudWatch alarms..."
    
    local alarms=("${CLUSTER_NAME}-high-acu-usage" "${CLUSTER_NAME}-sustained-high-capacity")
    local existing_alarms=()
    
    # Check which alarms exist
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" &> /dev/null; then
            existing_alarms+=("$alarm")
        fi
    done
    
    # Delete existing alarms
    if [[ ${#existing_alarms[@]} -gt 0 ]]; then
        aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}"
        success "Deleted CloudWatch alarms: ${existing_alarms[*]}"
    else
        log "No CloudWatch alarms found, skipping"
    fi
}

# Function to remove cost monitoring resources
remove_cost_monitoring() {
    log "Removing cost monitoring resources..."
    
    # Delete budget
    if aws budgets describe-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "Aurora-Serverless-v2-Monthly" &> /dev/null; then
        aws budgets delete-budget \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget-name "Aurora-Serverless-v2-Monthly"
        success "Deleted AWS Budget: Aurora-Serverless-v2-Monthly"
    else
        log "Budget Aurora-Serverless-v2-Monthly not found, skipping"
    fi
    
    # Delete SNS topic
    local topic_arn
    topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'aurora-sv2-cost-alerts')].TopicArn" --output text 2>/dev/null)
    if [[ -n "$topic_arn" && "$topic_arn" != "None" ]]; then
        aws sns delete-topic --topic-arn "$topic_arn"
        success "Deleted SNS topic: $topic_arn"
    else
        log "SNS topic aurora-sv2-cost-alerts not found, skipping"
    fi
}

# Function to remove parameter group
remove_parameter_group() {
    log "Removing Aurora cluster parameter group..."
    
    if [[ -n "$CLUSTER_PARAMETER_GROUP" ]]; then
        if aws rds describe-db-cluster-parameter-groups --db-cluster-parameter-group-name "$CLUSTER_PARAMETER_GROUP" &> /dev/null; then
            aws rds delete-db-cluster-parameter-group \
                --db-cluster-parameter-group-name "$CLUSTER_PARAMETER_GROUP"
            success "Deleted parameter group: $CLUSTER_PARAMETER_GROUP"
        else
            log "Parameter group $CLUSTER_PARAMETER_GROUP not found, skipping"
        fi
    else
        warning "Parameter group name not available, skipping"
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM resources..."
    
    if [[ -n "$LAMBDA_ROLE_NAME" ]]; then
        local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/aurora-sv2-lambda-policy"
        
        # Detach policy from role
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "$policy_arn" 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
            success "Deleted IAM role: $LAMBDA_ROLE_NAME"
        else
            log "IAM role $LAMBDA_ROLE_NAME not found, skipping"
        fi
        
        # Delete policy
        if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
            aws iam delete-policy --policy-arn "$policy_arn"
            success "Deleted IAM policy: aurora-sv2-lambda-policy"
        else
            log "IAM policy aurora-sv2-lambda-policy not found, skipping"
        fi
    else
        warning "Lambda role name not available, skipping IAM cleanup"
    fi
}

# Function to clean up deployment files
cleanup_deployment_files() {
    log "Cleaning up deployment files..."
    
    # Remove deployment info files
    local deployment_files
    deployment_files=$(find . -name "aurora-sv2-deployment-*.json" -type f 2>/dev/null)
    
    if [[ -n "$deployment_files" ]]; then
        for file in $deployment_files; do
            rm -f "$file"
            success "Removed deployment file: $file"
        done
    else
        log "No deployment files found"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check Aurora cluster
    if aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_NAME" &> /dev/null; then
        cleanup_issues+=("Aurora cluster $CLUSTER_NAME still exists")
    fi
    
    # Check Lambda functions
    for function_name in "${CLUSTER_NAME}-cost-aware-scaler" "${CLUSTER_NAME}-auto-pause-resume"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            cleanup_issues+=("Lambda function $function_name still exists")
        fi
    done
    
    # Check EventBridge rules
    for rule_name in "${CLUSTER_NAME}-cost-aware-scaling" "${CLUSTER_NAME}-auto-pause-resume"; do
        if aws events describe-rule --name "$rule_name" &> /dev/null; then
            cleanup_issues+=("EventBridge rule $rule_name still exists")
        fi
    done
    
    # Check IAM role
    if [[ -n "$LAMBDA_ROLE_NAME" ]] && aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        cleanup_issues+=("IAM role $LAMBDA_ROLE_NAME still exists")
    fi
    
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        success "Cleanup verification completed successfully"
        return 0
    else
        warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            warning "  - $issue"
        done
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    echo "================================"
    echo "   CLEANUP COMPLETED"
    echo "================================"
    echo
    echo "The following resources have been removed:"
    echo
    echo "✓ Aurora Serverless v2 cluster and instances"
    echo "✓ Lambda functions for cost optimization"
    echo "✓ EventBridge scheduling rules"
    echo "✓ CloudWatch alarms"
    echo "✓ SNS topic for cost alerts"
    echo "✓ AWS Budget for cost monitoring"
    echo "✓ IAM roles and policies"
    echo "✓ Parameter groups"
    echo "✓ Deployment tracking files"
    echo
    echo "Cost Impact:"
    echo "  All billable resources have been removed"
    echo "  No further charges will be incurred for this infrastructure"
    echo
    echo "Note:"
    echo "  CloudWatch log groups may be retained and continue to incur minimal charges"
    echo "  You can manually delete them from the CloudWatch console if desired"
    echo
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local exit_code=$?
    error "Cleanup encountered an error (exit code: $exit_code)"
    echo
    echo "Partial cleanup may have occurred. Please:"
    echo "1. Check the AWS console for remaining resources"
    echo "2. Manually remove any lingering resources to avoid charges"
    echo "3. Re-run this script to attempt cleanup again"
    echo
    echo "Common resources to check manually:"
    echo "  - RDS clusters and instances"
    echo "  - Lambda functions"
    echo "  - EventBridge rules"
    echo "  - CloudWatch alarms"
    echo "  - IAM roles and policies"
    echo
    exit $exit_code
}

# Main cleanup function
main() {
    log "Starting Aurora Serverless v2 Cost Optimization cleanup..."
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    # Load or prompt for resource information
    if ! load_deployment_info; then
        prompt_for_resources
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Execute cleanup steps in proper order
    remove_lambda_and_eventbridge
    remove_db_instances
    remove_aurora_cluster
    remove_cloudwatch_alarms
    remove_cost_monitoring
    remove_parameter_group
    remove_iam_resources
    cleanup_deployment_files
    
    # Verify cleanup
    if verify_cleanup; then
        display_cleanup_summary
        success "Aurora Serverless v2 Cost Optimization cleanup completed successfully!"
    else
        warning "Cleanup completed with some issues. Please check manually."
        echo "Run 'aws rds describe-db-clusters' to check for remaining clusters"
    fi
    
    echo
    log "Total cleanup time: $SECONDS seconds"
}

# Handle script interruption
trap 'handle_cleanup_error' ERR
trap 'error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Validate script is not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_prerequisites
    main "$@"
else
    error "This script should be executed, not sourced"
    exit 1
fi