#!/bin/bash

# =============================================================================
# AWS Proactive Application Resilience Monitoring Cleanup Script
# 
# This script removes all resources created by the deployment script for
# AWS Resilience Hub with EventBridge integration monitoring solution.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Valid AWS credentials configured
# - .deployment_vars file from deployment script
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check for deployment variables file
    if [[ ! -f ".deployment_vars" ]]; then
        error "Deployment variables file (.deployment_vars) not found!"
        error "This file is created during deployment and contains resource identifiers."
        error "Please ensure you're running this script from the same directory as the deployment."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# =============================================================================
# Load Deployment Variables
# =============================================================================

load_deployment_vars() {
    log "Loading deployment variables..."
    
    # Source the deployment variables
    source .deployment_vars
    
    # Verify required variables are loaded
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "APP_NAME" "POLICY_NAME" 
        "AUTOMATION_ROLE_NAME" "LAMBDA_FUNCTION_NAME" "RANDOM_SUFFIX"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var is not set in .deployment_vars"
            exit 1
        fi
    done
    
    info "Loaded variables for cleanup with suffix: $RANDOM_SUFFIX"
    log "Deployment variables loaded successfully"
}

# =============================================================================
# Confirmation Prompt
# =============================================================================

confirm_cleanup() {
    echo ""
    echo "=========================================="
    echo "CLEANUP CONFIRMATION"
    echo "=========================================="
    echo "This will permanently delete the following resources:"
    echo "- Application: ${APP_NAME}"
    echo "- Region: ${AWS_REGION}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "- All associated infrastructure and data"
    echo ""
    warn "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed cleanup. Proceeding with resource deletion..."
}

# =============================================================================
# CloudWatch Resources Cleanup
# =============================================================================

cleanup_cloudwatch() {
    log "Cleaning up CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarms_to_delete=(
        "Critical-Low-Resilience-Score-${RANDOM_SUFFIX}"
        "Warning-Low-Resilience-Score-${RANDOM_SUFFIX}"
        "Resilience-Assessment-Failures-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${alarms_to_delete[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" &> /dev/null; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            info "Deleted CloudWatch alarm: $alarm"
        else
            warn "CloudWatch alarm not found: $alarm"
        fi
    done
    
    # Delete CloudWatch dashboard
    local dashboard_name="Application-Resilience-Monitoring-${RANDOM_SUFFIX}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &> /dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        info "Deleted CloudWatch dashboard: $dashboard_name"
    else
        warn "CloudWatch dashboard not found: $dashboard_name"
    fi
    
    # Delete SNS topic if it exists
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &> /dev/null; then
            aws sns delete-topic --topic-arn "$TOPIC_ARN"
            info "Deleted SNS topic: $TOPIC_ARN"
        else
            warn "SNS topic not found: $TOPIC_ARN"
        fi
    fi
    
    log "CloudWatch resources cleanup completed"
}

# =============================================================================
# EventBridge and Lambda Cleanup
# =============================================================================

cleanup_eventbridge_lambda() {
    log "Cleaning up EventBridge and Lambda resources..."
    
    # Remove EventBridge rule targets
    local rule_name="ResilienceHubAssessmentRule-${RANDOM_SUFFIX}"
    if aws events describe-rule --name "$rule_name" &> /dev/null; then
        # Remove targets first
        local targets=$(aws events list-targets-by-rule --rule "$rule_name" --query 'Targets[].Id' --output text)
        if [[ -n "$targets" ]]; then
            aws events remove-targets --rule "$rule_name" --ids $targets
            info "Removed targets from EventBridge rule: $rule_name"
        fi
        
        # Delete the rule
        aws events delete-rule --name "$rule_name"
        info "Deleted EventBridge rule: $rule_name"
    else
        warn "EventBridge rule not found: $rule_name"
    fi
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        # Remove EventBridge permission first
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id "AllowEventBridgeInvoke" 2>/dev/null || true
        
        # Delete the function
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        info "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
    else
        warn "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
    
    log "EventBridge and Lambda cleanup completed"
}

# =============================================================================
# Resilience Hub Cleanup
# =============================================================================

cleanup_resilience_hub() {
    log "Cleaning up Resilience Hub resources..."
    
    # Delete application if it exists
    if [[ -n "${APP_ARN:-}" ]]; then
        if aws resiliencehub describe-app --app-arn "$APP_ARN" &> /dev/null; then
            aws resiliencehub delete-app --app-arn "$APP_ARN" --force-delete
            info "Deleted Resilience Hub application: $APP_NAME"
        else
            warn "Resilience Hub application not found: $APP_ARN"
        fi
    fi
    
    # Delete resilience policy if it exists
    if [[ -n "${POLICY_ARN:-}" ]]; then
        if aws resiliencehub describe-resiliency-policy --policy-arn "$POLICY_ARN" &> /dev/null; then
            aws resiliencehub delete-resiliency-policy --policy-arn "$POLICY_ARN"
            info "Deleted resilience policy: $POLICY_NAME"
        else
            warn "Resilience policy not found: $POLICY_ARN"
        fi
    fi
    
    log "Resilience Hub cleanup completed"
}

# =============================================================================
# Application Infrastructure Cleanup
# =============================================================================

cleanup_application_infrastructure() {
    log "Cleaning up application infrastructure..."
    
    # Terminate EC2 instance
    if [[ -n "${INSTANCE_ID:-}" ]]; then
        if aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null | grep -qv "terminated"; then
            info "Terminating EC2 instance: $INSTANCE_ID"
            aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
            
            # Wait for termination
            info "Waiting for EC2 instance to terminate..."
            aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
            info "EC2 instance terminated: $INSTANCE_ID"
        else
            warn "EC2 instance not found or already terminated: $INSTANCE_ID"
        fi
    fi
    
    # Delete RDS instance
    local db_identifier="resilience-demo-db-${RANDOM_SUFFIX}"
    if aws rds describe-db-instances --db-instance-identifier "$db_identifier" &> /dev/null; then
        info "Deleting RDS database: $db_identifier (this may take several minutes)"
        aws rds delete-db-instance \
            --db-instance-identifier "$db_identifier" \
            --skip-final-snapshot \
            --delete-automated-backups
        
        # Wait for deletion
        info "Waiting for RDS database deletion to complete..."
        aws rds wait db-instance-deleted --db-instance-identifier "$db_identifier"
        info "RDS database deleted: $db_identifier"
    else
        warn "RDS database not found: $db_identifier"
    fi
    
    # Delete DB subnet group
    local subnet_group_name="resilience-demo-subnet-group-${RANDOM_SUFFIX}"
    if aws rds describe-db-subnet-groups --db-subnet-group-name "$subnet_group_name" &> /dev/null; then
        aws rds delete-db-subnet-group --db-subnet-group-name "$subnet_group_name"
        info "Deleted DB subnet group: $subnet_group_name"
    else
        warn "DB subnet group not found: $subnet_group_name"
    fi
    
    log "Application infrastructure cleanup completed"
}

# =============================================================================
# VPC Resources Cleanup
# =============================================================================

cleanup_vpc_resources() {
    log "Cleaning up VPC resources..."
    
    # Delete security group
    if [[ -n "${SG_ID:-}" ]]; then
        if aws ec2 describe-security-groups --group-ids "$SG_ID" &> /dev/null; then
            aws ec2 delete-security-group --group-id "$SG_ID"
            info "Deleted security group: $SG_ID"
        else
            warn "Security group not found: $SG_ID"
        fi
    fi
    
    # Detach and delete internet gateway
    if [[ -n "${IGW_ID:-}" && -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-internet-gateways --internet-gateway-ids "$IGW_ID" &> /dev/null; then
            # Detach from VPC
            aws ec2 detach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" 2>/dev/null || true
            
            # Delete internet gateway
            aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
            info "Deleted internet gateway: $IGW_ID"
        else
            warn "Internet gateway not found: $IGW_ID"
        fi
    fi
    
    # Delete subnets
    for subnet_var in "SUBNET_ID_1" "SUBNET_ID_2"; do
        local subnet_id="${!subnet_var:-}"
        if [[ -n "$subnet_id" ]]; then
            if aws ec2 describe-subnets --subnet-ids "$subnet_id" &> /dev/null; then
                aws ec2 delete-subnet --subnet-id "$subnet_id"
                info "Deleted subnet: $subnet_id"
            else
                warn "Subnet not found: $subnet_id"
            fi
        fi
    done
    
    # Delete VPC
    if [[ -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &> /dev/null; then
            aws ec2 delete-vpc --vpc-id "$VPC_ID"
            info "Deleted VPC: $VPC_ID"
        else
            warn "VPC not found: $VPC_ID"
        fi
    fi
    
    log "VPC resources cleanup completed"
}

# =============================================================================
# IAM Resources Cleanup
# =============================================================================

cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Detach policies and delete IAM role
    if aws iam get-role --role-name "$AUTOMATION_ROLE_NAME" &> /dev/null; then
        # Detach policies
        local policies=(
            "arn:aws:iam::aws:policy/AmazonSSMAutomationRole"
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        )
        
        for policy in "${policies[@]}"; do
            aws iam detach-role-policy --role-name "$AUTOMATION_ROLE_NAME" --policy-arn "$policy" 2>/dev/null || true
        done
        
        # Delete role
        aws iam delete-role --role-name "$AUTOMATION_ROLE_NAME"
        info "Deleted IAM role: $AUTOMATION_ROLE_NAME"
    else
        warn "IAM role not found: $AUTOMATION_ROLE_NAME"
    fi
    
    log "IAM resources cleanup completed"
}

# =============================================================================
# Final Cleanup
# =============================================================================

final_cleanup() {
    log "Performing final cleanup..."
    
    # Clean up local files
    local files_to_remove=(
        ".deployment_vars"
        "resilience-policy.json"
        "app-template.json"
        "dashboard-config.json"
        "lambda_function.py"
        "lambda_function.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed local file: $file"
        fi
    done
    
    log "Final cleanup completed"
}

# =============================================================================
# Error Handling for Cleanup
# =============================================================================

cleanup_with_error_handling() {
    local step_name="$1"
    local cleanup_function="$2"
    
    info "Starting: $step_name"
    
    if $cleanup_function; then
        log "Completed: $step_name"
    else
        error "Failed: $step_name"
        warn "Continuing with remaining cleanup steps..."
    fi
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    log "Starting AWS Proactive Application Resilience Monitoring cleanup..."
    
    check_prerequisites
    load_deployment_vars
    confirm_cleanup
    
    # Perform cleanup in reverse order of creation
    cleanup_with_error_handling "CloudWatch Resources" cleanup_cloudwatch
    cleanup_with_error_handling "EventBridge and Lambda" cleanup_eventbridge_lambda
    cleanup_with_error_handling "Resilience Hub Resources" cleanup_resilience_hub
    cleanup_with_error_handling "Application Infrastructure" cleanup_application_infrastructure
    cleanup_with_error_handling "VPC Resources" cleanup_vpc_resources
    cleanup_with_error_handling "IAM Resources" cleanup_iam_resources
    cleanup_with_error_handling "Final Cleanup" final_cleanup
    
    log "Cleanup completed successfully!"
    echo ""
    echo "=========================================="
    echo "CLEANUP SUMMARY"
    echo "=========================================="
    echo "All resources for the resilience monitoring solution have been removed:"
    echo "- Application: ${APP_NAME}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "- IAM Role: ${AUTOMATION_ROLE_NAME}"
    echo "- VPC and associated resources"
    echo "- CloudWatch alarms and dashboard"
    echo "- EventBridge rules and targets"
    echo "- Resilience Hub application and policy"
    echo ""
    echo "Cleanup completed in region: ${AWS_REGION}"
    echo "=========================================="
}

# Execute main function
main "$@"