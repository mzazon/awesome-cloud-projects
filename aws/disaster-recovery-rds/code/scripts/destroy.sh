#!/bin/bash

# =============================================================================
# AWS RDS Disaster Recovery Cleanup Script
# =============================================================================
# This script safely removes the disaster recovery infrastructure for Amazon
# RDS databases including read replicas, monitoring, and automation resources.
# =============================================================================

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Check if state file exists
    if [[ ! -f "rds-dr-deployment-state.json" ]]; then
        warn "Deployment state file 'rds-dr-deployment-state.json' not found."
        warn "You will need to provide the resource information manually."
        return 1
    fi
    
    # Load state using jq if available, otherwise use manual parsing
    if command -v jq &> /dev/null; then
        PRIMARY_REGION=$(jq -r '.primary_region' rds-dr-deployment-state.json)
        SECONDARY_REGION=$(jq -r '.secondary_region' rds-dr-deployment-state.json)
        DB_IDENTIFIER=$(jq -r '.source_db_identifier' rds-dr-deployment-state.json)
        REPLICA_NAME=$(jq -r '.replica_name' rds-dr-deployment-state.json)
        TOPIC_NAME=$(jq -r '.topic_name' rds-dr-deployment-state.json)
        LAMBDA_NAME=$(jq -r '.lambda_name' rds-dr-deployment-state.json)
        DASHBOARD_NAME=$(jq -r '.dashboard_name' rds-dr-deployment-state.json)
        PRIMARY_TOPIC_ARN=$(jq -r '.primary_topic_arn' rds-dr-deployment-state.json)
        SECONDARY_TOPIC_ARN=$(jq -r '.secondary_topic_arn' rds-dr-deployment-state.json)
        RANDOM_SUFFIX=$(jq -r '.random_suffix' rds-dr-deployment-state.json)
    else
        warn "jq not available. Using basic parsing."
        PRIMARY_REGION=$(grep '"primary_region"' rds-dr-deployment-state.json | cut -d'"' -f4)
        SECONDARY_REGION=$(grep '"secondary_region"' rds-dr-deployment-state.json | cut -d'"' -f4)
        DB_IDENTIFIER=$(grep '"source_db_identifier"' rds-dr-deployment-state.json | cut -d'"' -f4)
        REPLICA_NAME=$(grep '"replica_name"' rds-dr-deployment-state.json | cut -d'"' -f4)
        TOPIC_NAME=$(grep '"topic_name"' rds-dr-deployment-state.json | cut -d'"' -f4)
        LAMBDA_NAME=$(grep '"lambda_name"' rds-dr-deployment-state.json | cut -d'"' -f4)
        DASHBOARD_NAME=$(grep '"dashboard_name"' rds-dr-deployment-state.json | cut -d'"' -f4)
        PRIMARY_TOPIC_ARN=$(grep '"primary_topic_arn"' rds-dr-deployment-state.json | cut -d'"' -f4)
        SECONDARY_TOPIC_ARN=$(grep '"secondary_topic_arn"' rds-dr-deployment-state.json | cut -d'"' -f4)
        RANDOM_SUFFIX=$(grep '"random_suffix"' rds-dr-deployment-state.json | cut -d'"' -f4)
    fi
    
    # Export variables for use in cleanup functions
    export PRIMARY_REGION SECONDARY_REGION DB_IDENTIFIER REPLICA_NAME
    export TOPIC_NAME LAMBDA_NAME DASHBOARD_NAME
    export PRIMARY_TOPIC_ARN SECONDARY_TOPIC_ARN RANDOM_SUFFIX
    
    log "Deployment state loaded successfully"
    info "Primary Region: $PRIMARY_REGION"
    info "Secondary Region: $SECONDARY_REGION"
    info "Source Database: $DB_IDENTIFIER"
    info "Read Replica: $REPLICA_NAME"
    
    return 0
}

# Function to get user input for missing information
get_manual_input() {
    log "Getting manual input for cleanup..."
    
    # Get primary region
    if [[ -z "${PRIMARY_REGION:-}" ]]; then
        PRIMARY_REGION=$(aws configure get region)
        if [[ -z "$PRIMARY_REGION" ]]; then
            read -p "Enter primary AWS region: " PRIMARY_REGION
        else
            warn "Using default region from AWS CLI: $PRIMARY_REGION"
        fi
    fi
    
    # Get secondary region
    if [[ -z "${SECONDARY_REGION:-}" ]]; then
        read -p "Enter secondary AWS region: " SECONDARY_REGION
    fi
    
    # Get database identifier
    if [[ -z "${DB_IDENTIFIER:-}" ]]; then
        read -p "Enter source database identifier: " DB_IDENTIFIER
    fi
    
    # Generate resource names based on pattern
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        read -p "Enter random suffix used in deployment (6 characters): " RANDOM_SUFFIX
    fi
    
    # Reconstruct resource names
    REPLICA_NAME="${DB_IDENTIFIER}-replica-${RANDOM_SUFFIX}"
    TOPIC_NAME="rds-dr-notifications-${RANDOM_SUFFIX}"
    LAMBDA_NAME="rds-dr-manager-${RANDOM_SUFFIX}"
    DASHBOARD_NAME="rds-dr-dashboard-${RANDOM_SUFFIX}"
    
    # Construct topic ARNs
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    PRIMARY_TOPIC_ARN="arn:aws:sns:${PRIMARY_REGION}:${ACCOUNT_ID}:${TOPIC_NAME}"
    SECONDARY_TOPIC_ARN="arn:aws:sns:${SECONDARY_REGION}:${ACCOUNT_ID}:${TOPIC_NAME}"
    
    export PRIMARY_REGION SECONDARY_REGION DB_IDENTIFIER REPLICA_NAME
    export TOPIC_NAME LAMBDA_NAME DASHBOARD_NAME
    export PRIMARY_TOPIC_ARN SECONDARY_TOPIC_ARN RANDOM_SUFFIX
    
    log "Manual input completed"
}

# Function to confirm destructive actions
confirm_destruction() {
    log "Preparing to destroy RDS Disaster Recovery infrastructure..."
    
    info "The following resources will be PERMANENTLY DELETED:"
    info "- Read Replica: $REPLICA_NAME (in $SECONDARY_REGION)"
    info "- Lambda Function: $LAMBDA_NAME"
    info "- CloudWatch Alarms and Dashboard"
    info "- SNS Topics in both regions"
    info "- IAM Role and Policies"
    
    warn "This action CANNOT be undone!"
    warn "The read replica and all its data will be permanently lost."
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        warn "FORCE_DESTROY is set - skipping confirmation"
        return 0
    fi
    
    echo ""
    read -p "Type 'yes' to confirm deletion of ALL disaster recovery resources: " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed - proceeding with cleanup"
}

# Function to remove read replica
remove_read_replica() {
    log "Removing read replica..."
    
    # Check if replica exists
    if ! aws rds describe-db-instances \
        --db-instance-identifier "$REPLICA_NAME" \
        --region "$SECONDARY_REGION" &> /dev/null; then
        warn "Read replica $REPLICA_NAME not found in $SECONDARY_REGION"
        return 0
    fi
    
    # Check replica status
    REPLICA_STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "$REPLICA_NAME" \
        --region "$SECONDARY_REGION" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text)
    
    info "Current replica status: $REPLICA_STATUS"
    
    # Delete read replica without final snapshot
    log "Deleting read replica (this may take several minutes)..."
    
    if aws rds delete-db-instance \
        --db-instance-identifier "$REPLICA_NAME" \
        --skip-final-snapshot \
        --region "$SECONDARY_REGION" &> /dev/null; then
        
        log "Read replica deletion initiated"
        
        # Wait for deletion to complete if requested
        if [[ "${WAIT_FOR_DELETION:-}" == "true" ]]; then
            info "Waiting for read replica deletion to complete..."
            aws rds wait db-instance-deleted \
                --db-instance-identifier "$REPLICA_NAME" \
                --region "$SECONDARY_REGION" \
                --cli-read-timeout 3600 || warn "Timeout waiting for replica deletion"
        fi
    else
        error "Failed to initiate read replica deletion"
    fi
}

# Function to remove CloudWatch alarms
remove_cloudwatch_alarms() {
    log "Removing CloudWatch alarms..."
    
    # Define alarm names to delete
    local alarms_to_delete=(
        "${DB_IDENTIFIER}-HighCPU"
        "${DB_IDENTIFIER}-DatabaseConnections"
        "${REPLICA_NAME}-ReplicaLag"
        "${DB_IDENTIFIER}-HighCPU-Test"  # Include test alarm if it exists
    )
    
    # Delete alarms in primary region
    for alarm in "${alarms_to_delete[@]}"; do
        if aws cloudwatch describe-alarms \
            --alarm-names "$alarm" \
            --region "$PRIMARY_REGION" \
            --query "MetricAlarms[0].AlarmName" \
            --output text &> /dev/null; then
            
            aws cloudwatch delete-alarms \
                --alarm-names "$alarm" \
                --region "$PRIMARY_REGION" &> /dev/null
            info "Deleted alarm: $alarm (primary region)"
        fi
    done
    
    # Delete replica lag alarm in secondary region
    if aws cloudwatch describe-alarms \
        --alarm-names "${REPLICA_NAME}-ReplicaLag" \
        --region "$SECONDARY_REGION" \
        --query "MetricAlarms[0].AlarmName" \
        --output text &> /dev/null; then
        
        aws cloudwatch delete-alarms \
            --alarm-names "${REPLICA_NAME}-ReplicaLag" \
            --region "$SECONDARY_REGION" &> /dev/null
        info "Deleted replica lag alarm (secondary region)"
    fi
    
    log "CloudWatch alarms removal completed"
}

# Function to remove Lambda function and related resources
remove_lambda_function() {
    log "Removing Lambda function and permissions..."
    
    # Remove Lambda permission for SNS trigger
    if aws lambda get-policy \
        --function-name "$LAMBDA_NAME" \
        --region "$PRIMARY_REGION" &> /dev/null; then
        
        aws lambda remove-permission \
            --function-name "$LAMBDA_NAME" \
            --statement-id sns-trigger \
            --region "$PRIMARY_REGION" &> /dev/null || warn "Failed to remove Lambda permission"
    fi
    
    # Delete Lambda function
    if aws lambda get-function \
        --function-name "$LAMBDA_NAME" \
        --region "$PRIMARY_REGION" &> /dev/null; then
        
        aws lambda delete-function \
            --function-name "$LAMBDA_NAME" \
            --region "$PRIMARY_REGION" &> /dev/null
        log "Lambda function deleted successfully"
    else
        warn "Lambda function $LAMBDA_NAME not found"
    fi
}

# Function to remove IAM role and policies
remove_iam_resources() {
    log "Removing IAM role and policies..."
    
    local role_name="${LAMBDA_NAME}-role"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
        warn "IAM role $role_name not found"
        return 0
    fi
    
    # Delete role policy
    if aws iam get-role-policy \
        --role-name "$role_name" \
        --policy-name "DrLambdaExecutionPolicy" &> /dev/null; then
        
        aws iam delete-role-policy \
            --role-name "$role_name" \
            --policy-name "DrLambdaExecutionPolicy" &> /dev/null
        info "Deleted role policy: DrLambdaExecutionPolicy"
    fi
    
    # Delete IAM role
    aws iam delete-role --role-name "$role_name" &> /dev/null
    log "IAM role deleted successfully"
}

# Function to remove SNS topics and subscriptions
remove_sns_topics() {
    log "Removing SNS topics and subscriptions..."
    
    # Remove primary SNS topic
    if aws sns get-topic-attributes \
        --topic-arn "$PRIMARY_TOPIC_ARN" \
        --region "$PRIMARY_REGION" &> /dev/null; then
        
        # First, list and remove all subscriptions
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$PRIMARY_TOPIC_ARN" \
            --region "$PRIMARY_REGION" \
            --query "Subscriptions[].SubscriptionArn" \
            --output text 2>/dev/null || echo "")
        
        for sub_arn in $SUBSCRIPTIONS; do
            if [[ "$sub_arn" != "None" && "$sub_arn" != "null" ]]; then
                aws sns unsubscribe \
                    --subscription-arn "$sub_arn" \
                    --region "$PRIMARY_REGION" &> /dev/null || warn "Failed to unsubscribe $sub_arn"
            fi
        done
        
        # Delete the topic
        aws sns delete-topic \
            --topic-arn "$PRIMARY_TOPIC_ARN" \
            --region "$PRIMARY_REGION" &> /dev/null
        log "Primary SNS topic deleted"
    else
        warn "Primary SNS topic not found"
    fi
    
    # Remove secondary SNS topic
    if aws sns get-topic-attributes \
        --topic-arn "$SECONDARY_TOPIC_ARN" \
        --region "$SECONDARY_REGION" &> /dev/null; then
        
        # First, list and remove all subscriptions
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SECONDARY_TOPIC_ARN" \
            --region "$SECONDARY_REGION" \
            --query "Subscriptions[].SubscriptionArn" \
            --output text 2>/dev/null || echo "")
        
        for sub_arn in $SUBSCRIPTIONS; do
            if [[ "$sub_arn" != "None" && "$sub_arn" != "null" ]]; then
                aws sns unsubscribe \
                    --subscription-arn "$sub_arn" \
                    --region "$SECONDARY_REGION" &> /dev/null || warn "Failed to unsubscribe $sub_arn"
            fi
        done
        
        # Delete the topic
        aws sns delete-topic \
            --topic-arn "$SECONDARY_TOPIC_ARN" \
            --region "$SECONDARY_REGION" &> /dev/null
        log "Secondary SNS topic deleted"
    else
        warn "Secondary SNS topic not found"
    fi
}

# Function to remove CloudWatch dashboard
remove_dashboard() {
    log "Removing CloudWatch dashboard..."
    
    if aws cloudwatch get-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --region "$PRIMARY_REGION" &> /dev/null; then
        
        aws cloudwatch delete-dashboards \
            --dashboard-names "$DASHBOARD_NAME" \
            --region "$PRIMARY_REGION" &> /dev/null
        log "CloudWatch dashboard deleted successfully"
    else
        warn "CloudWatch dashboard $DASHBOARD_NAME not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f "rds-dr-deployment-state.json" ]]; then
        if [[ "${KEEP_STATE_FILE:-}" != "true" ]]; then
            rm -f "rds-dr-deployment-state.json"
            log "Deployment state file removed"
        else
            info "Keeping deployment state file as requested"
        fi
    fi
    
    # Clean up any temporary files from deployment
    if [[ -f "lambda-trust-policy.json" ]]; then
        rm -f "lambda-trust-policy.json"
    fi
    
    if [[ -f "lambda-execution-policy.json" ]]; then
        rm -f "lambda-execution-policy.json"
    fi
    
    if [[ -f "dr_manager.py" ]]; then
        rm -f "dr_manager.py"
    fi
    
    if [[ -f "dr_manager.zip" ]]; then
        rm -f "dr_manager.zip"
    fi
    
    if [[ -f "dashboard-config.json" ]]; then
        rm -f "dashboard-config.json"
    fi
    
    log "Local file cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check if read replica still exists
    if aws rds describe-db-instances \
        --db-instance-identifier "$REPLICA_NAME" \
        --region "$SECONDARY_REGION" &> /dev/null; then
        warn "Read replica still exists (deletion may still be in progress)"
    fi
    
    # Check if Lambda function still exists
    if aws lambda get-function \
        --function-name "$LAMBDA_NAME" \
        --region "$PRIMARY_REGION" &> /dev/null; then
        error "Lambda function still exists"
        ((cleanup_errors++))
    fi
    
    # Check if SNS topics still exist
    if aws sns get-topic-attributes \
        --topic-arn "$PRIMARY_TOPIC_ARN" \
        --region "$PRIMARY_REGION" &> /dev/null; then
        error "Primary SNS topic still exists"
        ((cleanup_errors++))
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name "${LAMBDA_NAME}-role" &> /dev/null; then
        error "IAM role still exists"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log "Cleanup validation completed successfully"
        return 0
    else
        warn "Cleanup validation found $cleanup_errors potential issues"
        return 1
    fi
}

# Main cleanup function
main() {
    log "Starting AWS RDS Disaster Recovery cleanup..."
    
    check_prerequisites
    
    # Try to load deployment state, fall back to manual input if needed
    if ! load_deployment_state; then
        get_manual_input
    fi
    
    confirm_destruction
    
    # Execute cleanup in reverse order of creation
    remove_dashboard
    remove_cloudwatch_alarms
    remove_lambda_function
    remove_iam_resources
    remove_sns_topics
    remove_read_replica
    
    cleanup_local_files
    
    if validate_cleanup; then
        log "=============================================="
        log "AWS RDS Disaster Recovery cleanup completed successfully!"
        log "=============================================="
        info "All disaster recovery resources have been removed"
        info "Your primary database ($DB_IDENTIFIER) remains untouched"
        log ""
        log "Note: Read replica deletion may take several minutes to complete."
        log "You can verify completion in the AWS RDS console."
    else
        warn "Cleanup completed with some validation warnings. Please review the logs."
        warn "Some resources may still be in the process of being deleted."
    fi
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script removes the RDS disaster recovery infrastructure."
    echo ""
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompts"
    echo "  -w, --wait            Wait for read replica deletion to complete"
    echo "  -k, --keep-state      Keep the deployment state file"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  FORCE_DESTROY=true    Skip confirmation (same as --force)"
    echo "  WAIT_FOR_DELETION=true Wait for deletion (same as --wait)"
    echo "  KEEP_STATE_FILE=true  Keep state file (same as --keep-state)"
    echo ""
    echo "Examples:"
    echo "  ./destroy.sh                    # Interactive cleanup"
    echo "  ./destroy.sh --force --wait     # Non-interactive with wait"
    echo "  FORCE_DESTROY=true ./destroy.sh # Using environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            export FORCE_DESTROY=true
            shift
            ;;
        -w|--wait)
            export WAIT_FOR_DELETION=true
            shift
            ;;
        -k|--keep-state)
            export KEEP_STATE_FILE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main