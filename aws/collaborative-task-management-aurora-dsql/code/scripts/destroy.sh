#!/bin/bash

# Real-Time Collaborative Task Management with Aurora DSQL and EventBridge
# Cleanup/Destroy Script
#
# This script safely removes all infrastructure created by the deployment script
# for the real-time collaborative task management system.

set -e  # Exit on any error
set -o pipefail  # Exit if any command in a pipeline fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ -f ".deployment_config" ]]; then
        source .deployment_config
        success "Configuration loaded from .deployment_config"
    else
        warning "No deployment configuration found. Using environment variables or defaults."
        
        # Set default values or use environment variables
        export AWS_REGION=${AWS_REGION:-"us-east-1"}
        export SECONDARY_REGION=${SECONDARY_REGION:-"us-west-2"}
        export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")}
        
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            error "Could not determine AWS Account ID. Please ensure AWS CLI is configured."
            exit 1
        fi
        
        # Try to detect resource names from AWS resources
        detect_resources
    fi
    
    log "Configuration loaded:"
    log "  Primary Region: ${AWS_REGION}"
    log "  Secondary Region: ${SECONDARY_REGION}"
    log "  Account ID: ${AWS_ACCOUNT_ID}"
    if [[ -n "${DSQL_CLUSTER_NAME:-}" ]]; then
        log "  DSQL Cluster: ${DSQL_CLUSTER_NAME}"
    fi
    if [[ -n "${EVENT_BUS_NAME:-}" ]]; then
        log "  Event Bus: ${EVENT_BUS_NAME}"
    fi
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    fi
}

# Function to detect resources if configuration is missing
detect_resources() {
    log "Attempting to detect deployed resources..."
    
    # Try to find DSQL clusters with task-mgmt prefix
    DSQL_CLUSTERS=$(aws dsql list-clusters --region "${AWS_REGION}" --query 'Clusters[?contains(ClusterIdentifier, `task-mgmt-cluster`)].ClusterIdentifier' --output text 2>/dev/null || echo "")
    if [[ -n "$DSQL_CLUSTERS" ]]; then
        # Get the first cluster and extract the base name
        FIRST_CLUSTER=$(echo "$DSQL_CLUSTERS" | awk '{print $1}')
        export DSQL_CLUSTER_NAME=${FIRST_CLUSTER%-primary}
        log "Detected DSQL cluster: ${DSQL_CLUSTER_NAME}"
    fi
    
    # Try to find EventBridge buses with task-events prefix
    EVENT_BUSES=$(aws events list-event-buses --region "${AWS_REGION}" --query 'EventBuses[?contains(Name, `task-events`)].Name' --output text 2>/dev/null || echo "")
    if [[ -n "$EVENT_BUSES" ]]; then
        export EVENT_BUS_NAME=$(echo "$EVENT_BUSES" | awk '{print $1}')
        log "Detected event bus: ${EVENT_BUS_NAME}"
    fi
    
    # Try to find Lambda functions with task-processor prefix
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --region "${AWS_REGION}" --query 'Functions[?contains(FunctionName, `task-processor`)].FunctionName' --output text 2>/dev/null || echo "")
    if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
        export LAMBDA_FUNCTION_NAME=$(echo "$LAMBDA_FUNCTIONS" | awk '{print $1}')
        export LOG_GROUP_NAME="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        export LAMBDA_ROLE_NAME="${LAMBDA_FUNCTION_NAME}-role"
        export LAMBDA_POLICY_NAME="${LAMBDA_FUNCTION_NAME}-policy"
        log "Detected Lambda function: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    if [[ -z "${DSQL_CLUSTER_NAME:-}" && -z "${EVENT_BUS_NAME:-}" && -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        warning "No resources detected automatically. You may need to specify resource names manually."
    fi
}

# Function to confirm destructive action
confirm_destruction() {
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    warning "This will permanently delete all resources for the Real-Time Task Management system!"
    echo ""
    echo "Resources to be deleted:"
    
    if [[ -n "${DSQL_CLUSTER_NAME:-}" ]]; then
        echo "  🗃️  Aurora DSQL Clusters:"
        echo "      - ${DSQL_CLUSTER_NAME}-primary (${AWS_REGION})"
        echo "      - ${DSQL_CLUSTER_NAME}-secondary (${SECONDARY_REGION})"
    fi
    
    if [[ -n "${EVENT_BUS_NAME:-}" ]]; then
        echo "  📨 EventBridge Event Buses:"
        echo "      - ${EVENT_BUS_NAME} (${AWS_REGION})"
        echo "      - ${EVENT_BUS_NAME} (${SECONDARY_REGION})"
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        echo "  ⚡ Lambda Functions:"
        echo "      - ${LAMBDA_FUNCTION_NAME} (${AWS_REGION})"
        echo "      - ${LAMBDA_FUNCTION_NAME} (${SECONDARY_REGION})"
        echo "  📊 CloudWatch Log Groups:"
        echo "      - ${LOG_GROUP_NAME} (${AWS_REGION})"
        echo "      - ${LOG_GROUP_NAME} (${SECONDARY_REGION})"
    fi
    
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        echo "  🔐 IAM Resources:"
        echo "      - Role: ${LAMBDA_ROLE_NAME}"
        echo "      - Policy: ${LAMBDA_POLICY_NAME}"
    fi
    
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed, proceeding..."
}

# Function to delete Aurora DSQL clusters
delete_dsql_clusters() {
    if [[ -z "${DSQL_CLUSTER_NAME:-}" ]]; then
        log "No DSQL cluster name specified, skipping DSQL cleanup"
        return 0
    fi
    
    log "Deleting Aurora DSQL clusters..."
    
    # Delete primary cluster
    if aws dsql describe-cluster --cluster-identifier "${DSQL_CLUSTER_NAME}-primary" --region "${AWS_REGION}" &> /dev/null; then
        log "Deleting primary DSQL cluster: ${DSQL_CLUSTER_NAME}-primary"
        aws dsql delete-cluster \
            --cluster-identifier "${DSQL_CLUSTER_NAME}-primary" \
            --region "${AWS_REGION}" \
            --skip-final-backup 2>/dev/null || {
            warning "Failed to delete primary DSQL cluster or cluster doesn't exist"
        }
        
        # Wait for cluster deletion
        log "Waiting for primary cluster deletion to complete..."
        local max_wait=600  # 10 minutes
        local wait_time=0
        while [[ $wait_time -lt $max_wait ]]; do
            if ! aws dsql describe-cluster --cluster-identifier "${DSQL_CLUSTER_NAME}-primary" --region "${AWS_REGION}" &> /dev/null; then
                success "Primary DSQL cluster deleted successfully"
                break
            fi
            sleep 30
            wait_time=$((wait_time + 30))
            log "Still waiting for primary cluster deletion... (${wait_time}s)"
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            warning "Timeout waiting for primary cluster deletion"
        fi
    else
        log "Primary DSQL cluster not found: ${DSQL_CLUSTER_NAME}-primary"
    fi
    
    # Delete secondary cluster
    if aws dsql describe-cluster --cluster-identifier "${DSQL_CLUSTER_NAME}-secondary" --region "${SECONDARY_REGION}" &> /dev/null; then
        log "Deleting secondary DSQL cluster: ${DSQL_CLUSTER_NAME}-secondary"
        aws dsql delete-cluster \
            --cluster-identifier "${DSQL_CLUSTER_NAME}-secondary" \
            --region "${SECONDARY_REGION}" \
            --skip-final-backup 2>/dev/null || {
            warning "Failed to delete secondary DSQL cluster or cluster doesn't exist"
        }
        
        # Wait for cluster deletion
        log "Waiting for secondary cluster deletion to complete..."
        local max_wait=600  # 10 minutes
        local wait_time=0
        while [[ $wait_time -lt $max_wait ]]; do
            if ! aws dsql describe-cluster --cluster-identifier "${DSQL_CLUSTER_NAME}-secondary" --region "${SECONDARY_REGION}" &> /dev/null; then
                success "Secondary DSQL cluster deleted successfully"
                break
            fi
            sleep 30
            wait_time=$((wait_time + 30))
            log "Still waiting for secondary cluster deletion... (${wait_time}s)"
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            warning "Timeout waiting for secondary cluster deletion"
        fi
    else
        log "Secondary DSQL cluster not found: ${DSQL_CLUSTER_NAME}-secondary"
    fi
    
    success "DSQL cluster cleanup completed"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log "No Lambda function name specified, skipping Lambda cleanup"
        return 0
    fi
    
    log "Deleting Lambda functions..."
    
    # Delete Lambda function in primary region
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        log "Deleting Lambda function in primary region: ${LAMBDA_FUNCTION_NAME}"
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --region "${AWS_REGION}" || {
            warning "Failed to delete Lambda function in primary region"
        }
        success "Lambda function deleted in primary region"
    else
        log "Lambda function not found in primary region: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Delete Lambda function in secondary region
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${SECONDARY_REGION}" &> /dev/null; then
        log "Deleting Lambda function in secondary region: ${LAMBDA_FUNCTION_NAME}"
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --region "${SECONDARY_REGION}" || {
            warning "Failed to delete Lambda function in secondary region"
        }
        success "Lambda function deleted in secondary region"
    else
        log "Lambda function not found in secondary region: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    success "Lambda function cleanup completed"
}

# Function to delete EventBridge resources
delete_eventbridge_resources() {
    if [[ -z "${EVENT_BUS_NAME:-}" ]]; then
        log "No event bus name specified, skipping EventBridge cleanup"
        return 0
    fi
    
    log "Deleting EventBridge resources..."
    
    # Clean up primary region EventBridge resources
    log "Cleaning up EventBridge resources in primary region..."
    
    # Remove targets from rule
    if aws events describe-rule --name "task-processing-rule" --event-bus-name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        aws events remove-targets \
            --rule "task-processing-rule" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --ids "1" \
            --region "${AWS_REGION}" 2>/dev/null || {
            log "No targets to remove from rule in primary region"
        }
        
        # Delete rule
        aws events delete-rule \
            --name "task-processing-rule" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --region "${AWS_REGION}" || {
            warning "Failed to delete EventBridge rule in primary region"
        }
        log "EventBridge rule deleted in primary region"
    fi
    
    # Delete event bus in primary region
    if aws events describe-event-bus --name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        aws events delete-event-bus \
            --name "${EVENT_BUS_NAME}" \
            --region "${AWS_REGION}" || {
            warning "Failed to delete event bus in primary region"
        }
        success "Event bus deleted in primary region"
    else
        log "Event bus not found in primary region: ${EVENT_BUS_NAME}"
    fi
    
    # Clean up secondary region EventBridge resources
    log "Cleaning up EventBridge resources in secondary region..."
    
    # Remove targets from rule
    if aws events describe-rule --name "task-processing-rule" --event-bus-name "${EVENT_BUS_NAME}" --region "${SECONDARY_REGION}" &> /dev/null; then
        aws events remove-targets \
            --rule "task-processing-rule" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --ids "1" \
            --region "${SECONDARY_REGION}" 2>/dev/null || {
            log "No targets to remove from rule in secondary region"
        }
        
        # Delete rule
        aws events delete-rule \
            --name "task-processing-rule" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --region "${SECONDARY_REGION}" || {
            warning "Failed to delete EventBridge rule in secondary region"
        }
        log "EventBridge rule deleted in secondary region"
    fi
    
    # Delete event bus in secondary region
    if aws events describe-event-bus --name "${EVENT_BUS_NAME}" --region "${SECONDARY_REGION}" &> /dev/null; then
        aws events delete-event-bus \
            --name "${EVENT_BUS_NAME}" \
            --region "${SECONDARY_REGION}" || {
            warning "Failed to delete event bus in secondary region"
        }
        success "Event bus deleted in secondary region"
    else
        log "Event bus not found in secondary region: ${EVENT_BUS_NAME}"
    fi
    
    success "EventBridge resource cleanup completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    if [[ -z "${LAMBDA_ROLE_NAME:-}" ]]; then
        log "No IAM role name specified, skipping IAM cleanup"
        return 0
    fi
    
    log "Deleting IAM resources..."
    
    # Detach and delete policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}" &> /dev/null; then
        log "Detaching policy from role: ${LAMBDA_POLICY_NAME}"
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}" 2>/dev/null || {
            log "Policy may not be attached to role"
        }
        
        log "Deleting IAM policy: ${LAMBDA_POLICY_NAME}"
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}" || {
            warning "Failed to delete IAM policy"
        }
        success "IAM policy deleted"
    else
        log "IAM policy not found: ${LAMBDA_POLICY_NAME}"
    fi
    
    # Delete IAM role
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        log "Deleting IAM role: ${LAMBDA_ROLE_NAME}"
        
        # Remove any remaining attached policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "${LAMBDA_ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        if [[ -n "$ATTACHED_POLICIES" ]]; then
            log "Detaching remaining policies from role..."
            for policy_arn in $ATTACHED_POLICIES; do
                aws iam detach-role-policy --role-name "${LAMBDA_ROLE_NAME}" --policy-arn "$policy_arn" 2>/dev/null || true
            done
        fi
        
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE_NAME}" || {
            warning "Failed to delete IAM role"
        }
        success "IAM role deleted"
    else
        log "IAM role not found: ${LAMBDA_ROLE_NAME}"
    fi
    
    success "IAM resource cleanup completed"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log "No Lambda function name specified, skipping CloudWatch cleanup"
        return 0
    fi
    
    log "Deleting CloudWatch resources..."
    
    # Delete log groups
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --region "${AWS_REGION}" --query 'logGroups' --output text | grep -q "${LOG_GROUP_NAME}"; then
        log "Deleting log group in primary region: ${LOG_GROUP_NAME}"
        aws logs delete-log-group \
            --log-group-name "${LOG_GROUP_NAME}" \
            --region "${AWS_REGION}" || {
            warning "Failed to delete log group in primary region"
        }
        success "Log group deleted in primary region"
    else
        log "Log group not found in primary region: ${LOG_GROUP_NAME}"
    fi
    
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --region "${SECONDARY_REGION}" --query 'logGroups' --output text | grep -q "${LOG_GROUP_NAME}"; then
        log "Deleting log group in secondary region: ${LOG_GROUP_NAME}"
        aws logs delete-log-group \
            --log-group-name "${LOG_GROUP_NAME}" \
            --region "${SECONDARY_REGION}" || {
            warning "Failed to delete log group in secondary region"
        }
        success "Log group deleted in secondary region"
    else
        log "Log group not found in secondary region: ${LOG_GROUP_NAME}"
    fi
    
    # Delete CloudWatch alarms
    if aws cloudwatch describe-alarms --alarm-names "${LAMBDA_FUNCTION_NAME}-errors" --region "${AWS_REGION}" --query 'MetricAlarms' --output text | grep -q "${LAMBDA_FUNCTION_NAME}-errors"; then
        log "Deleting CloudWatch alarm: ${LAMBDA_FUNCTION_NAME}-errors"
        aws cloudwatch delete-alarms \
            --alarm-names "${LAMBDA_FUNCTION_NAME}-errors" \
            --region "${AWS_REGION}" || {
            warning "Failed to delete CloudWatch alarm"
        }
        success "CloudWatch alarm deleted"
    else
        log "CloudWatch alarm not found: ${LAMBDA_FUNCTION_NAME}-errors"
    fi
    
    # Delete dashboard if it exists
    if aws cloudwatch list-dashboards --region "${AWS_REGION}" --query 'DashboardEntries[?DashboardName==`TaskManagementDashboard`]' --output text | grep -q "TaskManagementDashboard"; then
        log "Deleting CloudWatch dashboard: TaskManagementDashboard"
        aws cloudwatch delete-dashboards \
            --dashboard-names "TaskManagementDashboard" \
            --region "${AWS_REGION}" || {
            warning "Failed to delete CloudWatch dashboard"
        }
        success "CloudWatch dashboard deleted"
    else
        log "CloudWatch dashboard not found: TaskManagementDashboard"
    fi
    
    success "CloudWatch resource cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of files that might exist from deployment
    local files_to_clean=(
        ".deployment_config"
        "lambda_trust_policy.json"
        "lambda_permissions.json"
        "task_schema.sql"
        "task_processor.py"
        "requirements.txt"
        "task_processor.zip"
        "health_check_event.json"
        "health_response.json"
        "sample_task_event.json"
        "response.json"
        "direct_task_request.json"
        "direct_response.json"
        "get_tasks_request.json"
        "get_tasks_response.json"
    )
    
    local directories_to_clean=(
        "lambda_package"
        "__pycache__"
    )
    
    # Remove files
    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" && log "Removed file: $file"
        fi
    done
    
    # Remove directories
    for dir in "${directories_to_clean[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir" && log "Removed directory: $dir"
        fi
    done
    
    success "Local file cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating resource cleanup..."
    local cleanup_issues=0
    
    # Check DSQL clusters
    if [[ -n "${DSQL_CLUSTER_NAME:-}" ]]; then
        if aws dsql describe-cluster --cluster-identifier "${DSQL_CLUSTER_NAME}-primary" --region "${AWS_REGION}" &> /dev/null; then
            warning "DSQL primary cluster still exists: ${DSQL_CLUSTER_NAME}-primary"
            cleanup_issues=$((cleanup_issues + 1))
        fi
        
        if aws dsql describe-cluster --cluster-identifier "${DSQL_CLUSTER_NAME}-secondary" --region "${SECONDARY_REGION}" &> /dev/null; then
            warning "DSQL secondary cluster still exists: ${DSQL_CLUSTER_NAME}-secondary"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Lambda functions
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${AWS_REGION}" &> /dev/null; then
            warning "Lambda function still exists in primary region: ${LAMBDA_FUNCTION_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
        
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${SECONDARY_REGION}" &> /dev/null; then
            warning "Lambda function still exists in secondary region: ${LAMBDA_FUNCTION_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check EventBridge buses
    if [[ -n "${EVENT_BUS_NAME:-}" ]]; then
        if aws events describe-event-bus --name "${EVENT_BUS_NAME}" --region "${AWS_REGION}" &> /dev/null; then
            warning "Event bus still exists in primary region: ${EVENT_BUS_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
        
        if aws events describe-event-bus --name "${EVENT_BUS_NAME}" --region "${SECONDARY_REGION}" &> /dev/null; then
            warning "Event bus still exists in secondary region: ${EVENT_BUS_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check IAM resources
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
            warning "IAM role still exists: ${LAMBDA_ROLE_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "All resources cleaned up successfully"
    else
        warning "Found $cleanup_issues resources that may not have been cleaned up properly"
        log "Some resources might take time to fully delete or may have dependencies"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=========================================="
    echo "Real-Time Task Management Cleanup Summary"
    echo "=========================================="
    echo ""
    success "Infrastructure cleanup completed!"
    echo ""
    echo "🗑️  Resources Removed:"
    
    if [[ -n "${DSQL_CLUSTER_NAME:-}" ]]; then
        echo "   ✅ Aurora DSQL Clusters"
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        echo "   ✅ Lambda Functions"
        echo "   ✅ CloudWatch Log Groups"
        echo "   ✅ CloudWatch Alarms"
    fi
    
    if [[ -n "${EVENT_BUS_NAME:-}" ]]; then
        echo "   ✅ EventBridge Event Buses"
        echo "   ✅ EventBridge Rules and Targets"
    fi
    
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        echo "   ✅ IAM Roles and Policies"
    fi
    
    echo "   ✅ Local Files and Configuration"
    echo ""
    echo "💡 Note: Some AWS resources may take additional time to fully delete"
    echo "   from the AWS console due to eventual consistency."
    echo ""
    success "Cleanup process completed successfully!"
}

# Function to show help
show_help() {
    echo "Real-Time Collaborative Task Management - Destroy Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h              Show this help message"
    echo "  --force                 Skip confirmation prompts"
    echo "  --region <region>       Override primary AWS region"
    echo "  --secondary <region>    Override secondary AWS region"
    echo "  --cluster <name>        Override DSQL cluster base name"
    echo "  --event-bus <name>      Override EventBridge bus name"
    echo "  --lambda <name>         Override Lambda function name"
    echo "  --skip-validation       Skip cleanup validation"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_DESTROY           Skip confirmation prompts (true/false)"
    echo "  AWS_REGION              Primary AWS region"
    echo "  SECONDARY_REGION        Secondary AWS region"
    echo ""
    echo "Examples:"
    echo "  $0                      # Interactive cleanup"
    echo "  $0 --force              # Skip confirmation"
    echo "  $0 --cluster task-mgmt-cluster-abc123    # Specify cluster name"
    echo ""
}

# Main cleanup function
main() {
    echo "======================================================"
    echo "Real-Time Collaborative Task Management - Cleanup"
    echo "======================================================"
    echo ""
    
    # Parse command line arguments
    SKIP_VALIDATION=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --force)
                export FORCE_DESTROY=true
                shift
                ;;
            --region)
                export AWS_REGION="$2"
                shift 2
                ;;
            --secondary)
                export SECONDARY_REGION="$2"
                shift 2
                ;;
            --cluster)
                export DSQL_CLUSTER_NAME="$2"
                shift 2
                ;;
            --event-bus)
                export EVENT_BUS_NAME="$2"
                shift 2
                ;;
            --lambda)
                export LAMBDA_FUNCTION_NAME="$2"
                export LOG_GROUP_NAME="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
                export LAMBDA_ROLE_NAME="${LAMBDA_FUNCTION_NAME}-role"
                export LAMBDA_POLICY_NAME="${LAMBDA_FUNCTION_NAME}-policy"
                shift 2
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Check AWS CLI availability
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Load configuration
    load_configuration
    
    # Confirm destruction
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    log "Starting infrastructure cleanup..."
    
    # Step 1: Delete CloudWatch resources (monitoring/logging)
    delete_cloudwatch_resources
    
    # Step 2: Delete EventBridge resources (rules, targets, buses)
    delete_eventbridge_resources
    
    # Step 3: Delete Lambda functions
    delete_lambda_functions
    
    # Step 4: Delete IAM resources (roles and policies)
    delete_iam_resources
    
    # Step 5: Delete Aurora DSQL clusters (takes the longest)
    delete_dsql_clusters
    
    # Step 6: Clean up local files
    cleanup_local_files
    
    # Step 7: Validate cleanup
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        validate_cleanup
    else
        log "Skipping cleanup validation as requested"
    fi
    
    # Display summary
    display_cleanup_summary
}

# Run main function with all arguments
main "$@"