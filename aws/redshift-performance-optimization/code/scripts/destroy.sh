#!/bin/bash

# Redshift Performance Optimization Cleanup Script
# This script removes all resources created by the deployment script
# including monitoring, alerting, and automated maintenance components

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_DIR}/cleanup.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Configuration variables with defaults
CLUSTER_IDENTIFIER="${CLUSTER_IDENTIFIER:-my-redshift-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Colored output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    error "Script failed at line $line_number with exit code $exit_code"
    error "Check the log file at: $LOG_FILE"
    echo ""
    warning "Partial cleanup may have occurred. You may need to manually remove some resources."
    warning "Check AWS console for any remaining resources."
    exit $exit_code
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        error "AWS credentials not configured or invalid. Please configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_ACCOUNT_ID
    
    success "Prerequisites check completed"
}

# Function to confirm destructive action
confirm_destruction() {
    if [ "$FORCE_DELETE" = "true" ]; then
        info "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "           WARNING"
    echo "=========================================="
    echo ""
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo ""
    echo "  • CloudWatch Alarms (4 alarms for performance monitoring)"
    echo "  • CloudWatch Dashboard (Redshift-Performance-Dashboard)"
    echo "  • CloudWatch Log Group (/aws/redshift/performance-metrics)"
    echo "  • Lambda Function (redshift-maintenance)"
    echo "  • IAM Role (RedshiftMaintenanceLambdaRole)"
    echo "  • EventBridge Rule (redshift-nightly-maintenance)"
    echo "  • SNS Topic (redshift-performance-alerts)"
    echo "  • Redshift Parameter Group (if not attached to cluster)"
    echo ""
    echo "The following will NOT be deleted (manual action required):"
    echo "  • Redshift Cluster ($CLUSTER_IDENTIFIER)"
    echo "  • Any data in the cluster"
    echo "  • SNS subscriptions (email subscriptions)"
    echo ""
    echo "Configuration:"
    echo "  • Cluster: $CLUSTER_IDENTIFIER"
    echo "  • Region: $AWS_REGION"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm: " -r
    echo ""
    
    if [[ $REPLY != "DELETE" ]]; then
        info "Cleanup cancelled - confirmation not received"
        exit 0
    fi
    
    info "Confirmation received, proceeding with cleanup..."
}

# Function to remove EventBridge rule and targets
remove_eventbridge_rule() {
    info "Removing EventBridge rule and targets..."
    
    # Remove targets first
    if aws events list-targets-by-rule \
        --rule "redshift-nightly-maintenance" \
        --region "$AWS_REGION" &> /dev/null; then
        
        TARGET_IDS=$(aws events list-targets-by-rule \
            --rule "redshift-nightly-maintenance" \
            --region "$AWS_REGION" \
            --query 'Targets[].Id' \
            --output text)
        
        if [ -n "$TARGET_IDS" ]; then
            aws events remove-targets \
                --rule "redshift-nightly-maintenance" \
                --ids $TARGET_IDS \
                --region "$AWS_REGION"
            success "EventBridge targets removed"
        fi
    fi
    
    # Remove the rule
    if aws events describe-rule \
        --name "redshift-nightly-maintenance" \
        --region "$AWS_REGION" &> /dev/null; then
        
        aws events delete-rule \
            --name "redshift-nightly-maintenance" \
            --region "$AWS_REGION"
        success "EventBridge rule removed"
    else
        info "EventBridge rule not found, skipping"
    fi
}

# Function to remove Lambda function and permissions
remove_lambda_function() {
    info "Removing Lambda function..."
    
    if aws lambda get-function \
        --function-name redshift-maintenance \
        --region "$AWS_REGION" &> /dev/null; then
        
        # Remove Lambda permissions first
        info "Removing Lambda permissions..."
        
        # Get all permission statements
        POLICY=$(aws lambda get-policy \
            --function-name redshift-maintenance \
            --region "$AWS_REGION" \
            --query 'Policy' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$POLICY" ]; then
            # Extract statement IDs and remove them
            echo "$POLICY" | jq -r '.Statement[].Sid' 2>/dev/null | while read -r sid; do
                if [ -n "$sid" ] && [ "$sid" != "null" ]; then
                    aws lambda remove-permission \
                        --function-name redshift-maintenance \
                        --statement-id "$sid" \
                        --region "$AWS_REGION" 2>/dev/null || true
                fi
            done
        fi
        
        # Delete the function
        aws lambda delete-function \
            --function-name redshift-maintenance \
            --region "$AWS_REGION"
        success "Lambda function removed"
    else
        info "Lambda function not found, skipping"
    fi
}

# Function to remove IAM role and policies
remove_iam_role() {
    info "Removing IAM role..."
    
    if aws iam get-role \
        --role-name RedshiftMaintenanceLambdaRole \
        --region "$AWS_REGION" &> /dev/null; then
        
        # Detach all managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name RedshiftMaintenanceLambdaRole \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text)
        
        for policy_arn in $ATTACHED_POLICIES; do
            if [ -n "$policy_arn" ]; then
                aws iam detach-role-policy \
                    --role-name RedshiftMaintenanceLambdaRole \
                    --policy-arn "$policy_arn"
                info "Detached policy: $policy_arn"
            fi
        done
        
        # Delete inline policies if any exist
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name RedshiftMaintenanceLambdaRole \
            --query 'PolicyNames' \
            --output text)
        
        for policy_name in $INLINE_POLICIES; do
            if [ -n "$policy_name" ]; then
                aws iam delete-role-policy \
                    --role-name RedshiftMaintenanceLambdaRole \
                    --policy-name "$policy_name"
                info "Deleted inline policy: $policy_name"
            fi
        done
        
        # Delete the role
        aws iam delete-role \
            --role-name RedshiftMaintenanceLambdaRole
        success "IAM role removed"
    else
        info "IAM role not found, skipping"
    fi
}

# Function to remove CloudWatch alarms
remove_cloudwatch_alarms() {
    info "Removing CloudWatch alarms..."
    
    ALARM_NAMES=(
        "Redshift-High-CPU-Usage"
        "Redshift-High-Queue-Length"
        "Redshift-Health-Check"
        "Redshift-Maintenance-Failures"
    )
    
    # Check which alarms exist
    EXISTING_ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "Redshift-" \
        --region "$AWS_REGION" \
        --query 'MetricAlarms[].AlarmName' \
        --output text)
    
    if [ -n "$EXISTING_ALARMS" ]; then
        aws cloudwatch delete-alarms \
            --alarm-names $EXISTING_ALARMS \
            --region "$AWS_REGION"
        success "CloudWatch alarms removed: $EXISTING_ALARMS"
    else
        info "No CloudWatch alarms found, skipping"
    fi
}

# Function to remove CloudWatch dashboard
remove_cloudwatch_dashboard() {
    info "Removing CloudWatch dashboard..."
    
    if aws cloudwatch get-dashboard \
        --dashboard-name "Redshift-Performance-Dashboard" \
        --region "$AWS_REGION" &> /dev/null; then
        
        aws cloudwatch delete-dashboards \
            --dashboard-names "Redshift-Performance-Dashboard" \
            --region "$AWS_REGION"
        success "CloudWatch dashboard removed"
    else
        info "CloudWatch dashboard not found, skipping"
    fi
}

# Function to remove CloudWatch log group
remove_cloudwatch_log_group() {
    info "Removing CloudWatch log group..."
    
    if aws logs describe-log-groups \
        --log-group-name-prefix "/aws/redshift/performance-metrics" \
        --region "$AWS_REGION" \
        --query 'logGroups[?logGroupName==`/aws/redshift/performance-metrics`]' \
        --output text | grep -q "/aws/redshift/performance-metrics"; then
        
        aws logs delete-log-group \
            --log-group-name /aws/redshift/performance-metrics \
            --region "$AWS_REGION"
        success "CloudWatch log group removed"
    else
        info "CloudWatch log group not found, skipping"
    fi
}

# Function to remove SNS topic
remove_sns_topic() {
    info "Removing SNS topic..."
    
    # Find the topic ARN
    TOPIC_ARN=$(aws sns list-topics \
        --region "$AWS_REGION" \
        --query "Topics[?contains(TopicArn, 'redshift-performance-alerts')].TopicArn" \
        --output text)
    
    if [ -n "$TOPIC_ARN" ]; then
        # List subscriptions before deleting
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$TOPIC_ARN" \
            --region "$AWS_REGION" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text)
        
        if [ -n "$SUBSCRIPTIONS" ]; then
            warning "The following SNS subscriptions will be deleted:"
            aws sns list-subscriptions-by-topic \
                --topic-arn "$TOPIC_ARN" \
                --region "$AWS_REGION" \
                --query 'Subscriptions[].[Protocol,Endpoint]' \
                --output table
            echo ""
        fi
        
        aws sns delete-topic \
            --topic-arn "$TOPIC_ARN" \
            --region "$AWS_REGION"
        success "SNS topic removed: $TOPIC_ARN"
    else
        info "SNS topic not found, skipping"
    fi
}

# Function to handle parameter group removal
remove_parameter_group() {
    info "Checking parameter group status..."
    
    # Get current cluster parameter group
    CURRENT_PARAM_GROUP=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER_IDENTIFIER" \
        --region "$AWS_REGION" \
        --query 'Clusters[0].ClusterParameterGroups[0].ParameterGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$CURRENT_PARAM_GROUP" ] && [[ "$CURRENT_PARAM_GROUP" == *"optimized-wlm-config"* ]]; then
        warning "Cluster is still using custom parameter group: $CURRENT_PARAM_GROUP"
        warning "Resetting cluster to default parameter group..."
        
        # Reset to default parameter group
        aws redshift modify-cluster \
            --cluster-identifier "$CLUSTER_IDENTIFIER" \
            --cluster-parameter-group-name default.redshift-1.0 \
            --apply-immediately \
            --region "$AWS_REGION"
        
        info "Cluster parameter group reset to default"
        info "Waiting for parameter group change to complete..."
        
        # Wait for the parameter group change to be applied
        for i in {1..30}; do
            CURRENT_STATUS=$(aws redshift describe-clusters \
                --cluster-identifier "$CLUSTER_IDENTIFIER" \
                --region "$AWS_REGION" \
                --query 'Clusters[0].ClusterParameterGroups[0].ParameterApplyStatus' \
                --output text)
            
            if [ "$CURRENT_STATUS" = "in-sync" ]; then
                break
            fi
            
            if [ $i -eq 30 ]; then
                warning "Timeout waiting for parameter group change. You may need to manually delete the parameter group later."
                return
            fi
            
            sleep 10
        done
        
        success "Parameter group change completed"
    fi
    
    # Find and remove custom parameter groups
    CUSTOM_PARAM_GROUPS=$(aws redshift describe-cluster-parameter-groups \
        --region "$AWS_REGION" \
        --query "ParameterGroups[?contains(ParameterGroupName, 'optimized-wlm-config')].ParameterGroupName" \
        --output text)
    
    for param_group in $CUSTOM_PARAM_GROUPS; do
        if [ -n "$param_group" ]; then
            info "Removing parameter group: $param_group"
            aws redshift delete-cluster-parameter-group \
                --parameter-group-name "$param_group" \
                --region "$AWS_REGION"
            success "Parameter group removed: $param_group"
        fi
    done
    
    if [ -z "$CUSTOM_PARAM_GROUPS" ]; then
        info "No custom parameter groups found, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    FILES_TO_REMOVE=(
        "${PROJECT_DIR}/analyze_performance.sql"
        "${PROJECT_DIR}/dashboard_config.json"
        "${PROJECT_DIR}/lambda_test_response.json"
        "${PROJECT_DIR}/maintenance_function.py"
        "${PROJECT_DIR}/maintenance_function.zip"
    )
    
    for file in "${FILES_TO_REMOVE[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed: $(basename "$file")"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check for remaining alarms
    REMAINING_ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "Redshift-" \
        --region "$AWS_REGION" \
        --query 'MetricAlarms[].AlarmName' \
        --output text)
    
    if [ -n "$REMAINING_ALARMS" ]; then
        warning "Remaining CloudWatch alarms found: $REMAINING_ALARMS"
        issues_found=true
    fi
    
    # Check for Lambda function
    if aws lambda get-function \
        --function-name redshift-maintenance \
        --region "$AWS_REGION" &> /dev/null; then
        warning "Lambda function still exists: redshift-maintenance"
        issues_found=true
    fi
    
    # Check for IAM role
    if aws iam get-role \
        --role-name RedshiftMaintenanceLambdaRole \
        --region "$AWS_REGION" &> /dev/null; then
        warning "IAM role still exists: RedshiftMaintenanceLambdaRole"
        issues_found=true
    fi
    
    # Check for EventBridge rule
    if aws events describe-rule \
        --name "redshift-nightly-maintenance" \
        --region "$AWS_REGION" &> /dev/null; then
        warning "EventBridge rule still exists: redshift-nightly-maintenance"
        issues_found=true
    fi
    
    if [ "$issues_found" = false ]; then
        success "Cleanup verification completed - all resources removed successfully"
    else
        warning "Some resources may still exist. Check AWS console for manual cleanup."
        warning "You may need to wait a few minutes for some deletions to propagate."
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo ""
    echo "=========================================="
    echo "    CLEANUP COMPLETED"
    echo "=========================================="
    echo ""
    echo "Resources removed:"
    echo "  ✓ CloudWatch Alarms (4 performance monitoring alarms)"
    echo "  ✓ CloudWatch Dashboard (Redshift-Performance-Dashboard)"
    echo "  ✓ CloudWatch Log Group (/aws/redshift/performance-metrics)"
    echo "  ✓ Lambda Function (redshift-maintenance)"
    echo "  ✓ IAM Role (RedshiftMaintenanceLambdaRole)"
    echo "  ✓ EventBridge Rule (redshift-nightly-maintenance)"
    echo "  ✓ SNS Topic (redshift-performance-alerts)"
    echo "  ✓ Custom Parameter Groups"
    echo "  ✓ Local temporary files"
    echo ""
    echo "Resources NOT removed (require manual action if desired):"
    echo "  • Redshift Cluster ($CLUSTER_IDENTIFIER)"
    echo "  • Cluster data and databases"
    echo "  • Default parameter group (default.redshift-1.0)"
    echo ""
    echo "Configuration:"
    echo "  • Cluster: $CLUSTER_IDENTIFIER"
    echo "  • Region: $AWS_REGION"
    echo "  • Cluster parameter group reset to: default.redshift-1.0"
    echo ""
    echo "Important notes:"
    echo "  • Your Redshift cluster is still running and accessible"
    echo "  • Automatic workload management has been disabled"
    echo "  • Performance monitoring and alerts have been removed"
    echo "  • Automated maintenance tasks have been stopped"
    echo ""
    echo "To re-enable performance optimization, run: ${SCRIPT_DIR}/deploy.sh"
    echo ""
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "  Redshift Performance Optimization"
    echo "        Cleanup Script"
    echo "=========================================="
    echo ""
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    info "Starting cleanup with configuration:"
    info "  Cluster: $CLUSTER_IDENTIFIER"
    info "  Region: $AWS_REGION"
    info "  Force Delete: $FORCE_DELETE"
    info "  Log File: $LOG_FILE"
    echo ""
    
    # Execute cleanup steps
    check_prerequisites
    confirm_destruction
    
    info "Beginning resource cleanup..."
    echo ""
    
    # Remove resources in reverse order of creation
    remove_eventbridge_rule
    remove_lambda_function
    remove_iam_role
    remove_cloudwatch_alarms
    remove_cloudwatch_dashboard
    remove_cloudwatch_log_group
    remove_sns_topic
    remove_parameter_group
    cleanup_local_files
    
    echo ""
    verify_cleanup
    
    # Show cleanup summary
    show_cleanup_summary
    
    success "Cleanup completed successfully!"
    echo "Check the cleanup log at: $LOG_FILE"
}

# Help function
show_help() {
    echo "Redshift Performance Optimization Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompts (use with caution)"
    echo "  -c, --cluster NAME    Specify cluster identifier (default: my-redshift-cluster)"
    echo "  -r, --region REGION   Specify AWS region (default: us-east-1)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  CLUSTER_IDENTIFIER    Redshift cluster identifier"
    echo "  AWS_REGION           AWS region"
    echo "  FORCE_DELETE         Set to 'true' to skip confirmations"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --force                           # Skip confirmations"
    echo "  $0 --cluster my-cluster --region us-west-2"
    echo "  FORCE_DELETE=true $0                 # Using environment variable"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_DELETE="true"
            shift
            ;;
        -c|--cluster)
            CLUSTER_IDENTIFIER="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

# Script entry point
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi