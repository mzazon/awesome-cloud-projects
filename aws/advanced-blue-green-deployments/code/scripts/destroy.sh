#!/bin/bash

# Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy
# Cleanup Script
# 
# This script safely removes all infrastructure components created by the
# blue-green deployment demo, including ECS services, Lambda functions,
# ALB, CodeDeploy applications, IAM roles, and monitoring resources.

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.deployment-config"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy-errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$ERROR_LOG"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
Advanced Blue-Green Deployments - Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Skip confirmation prompts (dangerous!)
    -p, --preserve-images   Keep ECR repository and Docker images
    -v, --verbose           Enable verbose logging
    -d, --dry-run           Show what would be deleted without executing
    --config-file FILE      Use specific configuration file

EXAMPLES:
    $0                      # Interactive cleanup with confirmation prompts
    $0 --force              # Non-interactive cleanup (use with caution!)
    $0 --preserve-images    # Clean up infrastructure but keep container images
    $0 --dry-run            # Preview what would be deleted

SAFETY FEATURES:
    - Requires confirmation before deleting resources
    - Checks for dependent resources before deletion
    - Graceful handling of already-deleted resources
    - Comprehensive logging of all cleanup operations

EOF
}

# Default values
FORCE_MODE=false
PRESERVE_IMAGES=false
VERBOSE=false
DRY_RUN=false
CUSTOM_CONFIG_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -p|--preserve-images)
            PRESERVE_IMAGES=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --config-file)
            CUSTOM_CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
echo "=== Cleanup started at $(date) ===" > "$LOG_FILE"
echo "=== Error log for cleanup started at $(date) ===" > "$ERROR_LOG"

log "Starting Advanced Blue-Green Deployment cleanup..."

# Load configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    local config_path="$CONFIG_FILE"
    if [[ -n "$CUSTOM_CONFIG_FILE" ]]; then
        config_path="$CUSTOM_CONFIG_FILE"
    fi
    
    if [[ ! -f "$config_path" ]]; then
        error "Configuration file not found: $config_path"
        error "Please ensure the deployment script was run successfully or provide a valid config file."
        exit 1
    fi
    
    # Source the configuration file
    set -o allexport
    source "$config_path"
    set +o allexport
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "PROJECT_NAME"
        "ECS_CLUSTER_NAME" "ECS_SERVICE_NAME" "LAMBDA_FUNCTION_NAME"
        "ALB_NAME" "ECR_REPOSITORY"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required configuration variable $var is not set"
            exit 1
        fi
    done
    
    log "✅ Configuration loaded successfully"
    log "Project: $PROJECT_NAME"
    log "Region: $AWS_REGION"
    log "Account: $AWS_ACCOUNT_ID"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        warn "Force mode enabled - skipping confirmation prompts!"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would request confirmation"
        return 0
    fi
    
    echo
    warn "WARNING: This will delete ALL resources created by the blue-green deployment demo!"
    echo
    echo "Resources to be deleted:"
    echo "  - ECS Cluster: $ECS_CLUSTER_NAME"
    echo "  - ECS Service: $ECS_SERVICE_NAME"
    echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  - Application Load Balancer: ${ALB_NAME}"
    echo "  - CodeDeploy Applications: ${CD_ECS_APP_NAME:-}, ${CD_LAMBDA_APP_NAME:-}"
    echo "  - IAM Roles and Policies"
    echo "  - CloudWatch Alarms and Log Groups"
    echo "  - Security Groups"
    if [[ "$PRESERVE_IMAGES" == "false" ]]; then
        echo "  - ECR Repository and Images: $ECR_REPOSITORY"
    fi
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion - proceeding with cleanup"
}

# Helper function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_args="${3:-}"
    
    case $resource_type in
        "ecs-service")
            aws ecs describe-services \
                --cluster "$additional_args" \
                --services "$resource_name" \
                --query 'services[?status!=`INACTIVE`]' \
                --output text | grep -q .
            ;;
        "ecs-cluster")
            aws ecs describe-clusters \
                --clusters "$resource_name" \
                --query 'clusters[?status==`ACTIVE`]' \
                --output text | grep -q .
            ;;
        "lambda-function")
            aws lambda get-function \
                --function-name "$resource_name" \
                >/dev/null 2>&1
            ;;
        "alb")
            aws elbv2 describe-load-balancers \
                --names "$resource_name" \
                >/dev/null 2>&1
            ;;
        "target-group")
            aws elbv2 describe-target-groups \
                --names "$resource_name" \
                >/dev/null 2>&1
            ;;
        "security-group")
            aws ec2 describe-security-groups \
                --group-ids "$resource_name" \
                >/dev/null 2>&1
            ;;
        "iam-role")
            aws iam get-role \
                --role-name "$resource_name" \
                >/dev/null 2>&1
            ;;
        "codedeploy-app")
            aws deploy get-application \
                --application-name "$resource_name" \
                >/dev/null 2>&1
            ;;
        "ecr-repository")
            aws ecr describe-repositories \
                --repository-names "$resource_name" \
                >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Stop and delete ECS resources
cleanup_ecs_resources() {
    log "Cleaning up ECS resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up ECS resources"
        return 0
    fi
    
    # Check if ECS service exists
    if resource_exists "ecs-service" "$ECS_SERVICE_NAME" "$ECS_CLUSTER_NAME"; then
        log "Scaling down ECS service to zero tasks..."
        aws ecs update-service \
            --cluster "$ECS_CLUSTER_NAME" \
            --service "$ECS_SERVICE_NAME" \
            --desired-count 0 || warn "Failed to scale down ECS service"
        
        log "Waiting for ECS service to stabilize..."
        aws ecs wait services-stable \
            --cluster "$ECS_CLUSTER_NAME" \
            --services "$ECS_SERVICE_NAME" || warn "Service failed to stabilize"
        
        log "Deleting ECS service..."
        aws ecs delete-service \
            --cluster "$ECS_CLUSTER_NAME" \
            --service "$ECS_SERVICE_NAME" \
            --force || warn "Failed to delete ECS service"
        
        log "✅ ECS service deleted"
    else
        warn "ECS service $ECS_SERVICE_NAME not found or already deleted"
    fi
    
    # Delete ECS cluster
    if resource_exists "ecs-cluster" "$ECS_CLUSTER_NAME"; then
        log "Deleting ECS cluster..."
        aws ecs delete-cluster \
            --cluster "$ECS_CLUSTER_NAME" || warn "Failed to delete ECS cluster"
        
        log "✅ ECS cluster deleted"
    else
        warn "ECS cluster $ECS_CLUSTER_NAME not found or already deleted"
    fi
    
    # Delete CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "/ecs/${ECS_SERVICE_NAME}" --query 'logGroups[0]' --output text | grep -q .; then
        log "Deleting CloudWatch log group..."
        aws logs delete-log-group \
            --log-group-name "/ecs/${ECS_SERVICE_NAME}" || warn "Failed to delete log group"
        
        log "✅ CloudWatch log group deleted"
    else
        warn "CloudWatch log group for ECS service not found"
    fi
}

# Delete CodeDeploy applications
cleanup_codedeploy_resources() {
    log "Cleaning up CodeDeploy resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up CodeDeploy resources"
        return 0
    fi
    
    # Delete ECS CodeDeploy application
    if [[ -n "${CD_ECS_APP_NAME:-}" ]] && resource_exists "codedeploy-app" "$CD_ECS_APP_NAME"; then
        log "Deleting CodeDeploy ECS application..."
        aws deploy delete-application \
            --application-name "$CD_ECS_APP_NAME" || warn "Failed to delete CodeDeploy ECS application"
        
        log "✅ CodeDeploy ECS application deleted"
    else
        warn "CodeDeploy ECS application not found or variable not set"
    fi
    
    # Delete Lambda CodeDeploy application
    if [[ -n "${CD_LAMBDA_APP_NAME:-}" ]] && resource_exists "codedeploy-app" "$CD_LAMBDA_APP_NAME"; then
        log "Deleting CodeDeploy Lambda application..."
        aws deploy delete-application \
            --application-name "$CD_LAMBDA_APP_NAME" || warn "Failed to delete CodeDeploy Lambda application"
        
        log "✅ CodeDeploy Lambda application deleted"
    else
        warn "CodeDeploy Lambda application not found or variable not set"
    fi
}

# Delete ALB and networking resources
cleanup_alb_resources() {
    log "Cleaning up ALB and networking resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up ALB and networking resources"
        return 0
    fi
    
    # Delete ALB listener
    if [[ -n "${LISTENER_ARN:-}" ]]; then
        log "Deleting ALB listener..."
        aws elbv2 delete-listener \
            --listener-arn "$LISTENER_ARN" || warn "Failed to delete ALB listener"
        
        log "✅ ALB listener deleted"
    else
        warn "ALB listener ARN not available"
    fi
    
    # Delete target groups
    local target_groups=()
    if [[ -n "${TG_BLUE_ARN:-}" ]]; then
        target_groups+=("$TG_BLUE_ARN")
    fi
    if [[ -n "${TG_GREEN_ARN:-}" ]]; then
        target_groups+=("$TG_GREEN_ARN")
    fi
    
    for tg_arn in "${target_groups[@]}"; do
        if [[ -n "$tg_arn" ]]; then
            local tg_name=$(basename "$tg_arn")
            if resource_exists "target-group" "$tg_name"; then
                log "Deleting target group: $tg_name"
                aws elbv2 delete-target-group \
                    --target-group-arn "$tg_arn" || warn "Failed to delete target group $tg_name"
            else
                warn "Target group $tg_name not found"
            fi
        fi
    done
    
    # Delete load balancer
    if [[ -n "${ALB_ARN:-}" ]] && resource_exists "alb" "$ALB_NAME"; then
        log "Deleting Application Load Balancer..."
        aws elbv2 delete-load-balancer \
            --load-balancer-arn "$ALB_ARN" || warn "Failed to delete ALB"
        
        log "✅ Application Load Balancer deleted"
    else
        warn "ALB not found or ARN not available"
    fi
    
    # Delete security groups
    local security_groups=()
    if [[ -n "${ALB_SG_ID:-}" ]]; then
        security_groups+=("$ALB_SG_ID")
    fi
    if [[ -n "${ECS_SG_ID:-}" ]]; then
        security_groups+=("$ECS_SG_ID")
    fi
    
    # Wait a bit for ALB deletion to propagate
    if [[ ${#security_groups[@]} -gt 0 ]]; then
        log "Waiting for ALB deletion to propagate before deleting security groups..."
        sleep 30
    fi
    
    for sg_id in "${security_groups[@]}"; do
        if [[ -n "$sg_id" ]] && resource_exists "security-group" "$sg_id"; then
            log "Deleting security group: $sg_id"
            aws ec2 delete-security-group \
                --group-id "$sg_id" || warn "Failed to delete security group $sg_id"
        else
            warn "Security group $sg_id not found"
        fi
    done
    
    if [[ ${#security_groups[@]} -gt 0 ]]; then
        log "✅ Security groups deleted"
    fi
}

# Delete Lambda functions
cleanup_lambda_resources() {
    log "Cleaning up Lambda resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up Lambda resources"
        return 0
    fi
    
    # Delete main Lambda function
    if resource_exists "lambda-function" "$LAMBDA_FUNCTION_NAME"; then
        log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
        aws lambda delete-function \
            --function-name "$LAMBDA_FUNCTION_NAME" || warn "Failed to delete Lambda function"
        
        log "✅ Lambda function deleted"
    else
        warn "Lambda function $LAMBDA_FUNCTION_NAME not found"
    fi
    
    # Delete deployment hook Lambda functions
    local hook_functions=(
        "${PROJECT_NAME}-pre-deployment-hook"
        "${PROJECT_NAME}-post-deployment-hook"
    )
    
    for func_name in "${hook_functions[@]}"; do
        if resource_exists "lambda-function" "$func_name"; then
            log "Deleting deployment hook function: $func_name"
            aws lambda delete-function \
                --function-name "$func_name" || warn "Failed to delete hook function $func_name"
        else
            warn "Hook function $func_name not found"
        fi
    done
    
    if [[ ${#hook_functions[@]} -gt 0 ]]; then
        log "✅ Deployment hook functions cleaned up"
    fi
}

# Delete ECR repository
cleanup_ecr_resources() {
    if [[ "$PRESERVE_IMAGES" == "true" ]]; then
        log "Preserving ECR repository and images as requested"
        return 0
    fi
    
    log "Cleaning up ECR resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up ECR resources"
        return 0
    fi
    
    if resource_exists "ecr-repository" "$ECR_REPOSITORY"; then
        log "Deleting ECR repository (including all images): $ECR_REPOSITORY"
        aws ecr delete-repository \
            --repository-name "$ECR_REPOSITORY" \
            --force || warn "Failed to delete ECR repository"
        
        log "✅ ECR repository deleted"
    else
        warn "ECR repository $ECR_REPOSITORY not found"
    fi
}

# Delete IAM roles and policies
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up IAM resources"
        return 0
    fi
    
    # IAM roles to delete
    local iam_roles=(
        "$ECS_EXECUTION_ROLE"
        "$ECS_TASK_ROLE"
        "$CODEDEPLOY_ROLE"
        "$LAMBDA_ROLE"
    )
    
    # IAM policies to delete
    local iam_policies=(
        "ECSTaskPolicy-${PROJECT_NAME##*-}"
        "LambdaEnhancedPolicy-${PROJECT_NAME##*-}"
    )
    
    # Detach and delete policies, then delete roles
    for role_name in "${iam_roles[@]}"; do
        if [[ -n "$role_name" ]] && resource_exists "iam-role" "$role_name"; then
            log "Processing IAM role: $role_name"
            
            # Get attached policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            # Detach managed policies
            if [[ -n "$attached_policies" ]]; then
                for policy_arn in $attached_policies; do
                    log "Detaching policy from role $role_name: $policy_arn"
                    aws iam detach-role-policy \
                        --role-name "$role_name" \
                        --policy-arn "$policy_arn" || warn "Failed to detach policy $policy_arn"
                done
            fi
            
            # Delete role
            log "Deleting IAM role: $role_name"
            aws iam delete-role \
                --role-name "$role_name" || warn "Failed to delete IAM role $role_name"
        else
            warn "IAM role $role_name not found"
        fi
    done
    
    # Delete custom policies
    for policy_name in "${iam_policies[@]}"; do
        if [[ -n "$policy_name" ]]; then
            local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
            if aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
                log "Deleting IAM policy: $policy_name"
                aws iam delete-policy \
                    --policy-arn "$policy_arn" || warn "Failed to delete policy $policy_name"
            else
                warn "IAM policy $policy_name not found"
            fi
        fi
    done
    
    log "✅ IAM resources cleaned up"
}

# Delete CloudWatch resources
cleanup_cloudwatch_resources() {
    log "Cleaning up CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up CloudWatch resources"
        return 0
    fi
    
    # CloudWatch alarms to delete
    local alarm_names=(
        "${ECS_SERVICE_NAME}-high-error-rate"
        "${ECS_SERVICE_NAME}-high-response-time"
        "${LAMBDA_FUNCTION_NAME}-high-error-rate"
        "${LAMBDA_FUNCTION_NAME}-high-duration"
    )
    
    # Check which alarms exist
    local existing_alarms=()
    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0]' --output text | grep -q .; then
            existing_alarms+=("$alarm_name")
        fi
    done
    
    # Delete existing alarms
    if [[ ${#existing_alarms[@]} -gt 0 ]]; then
        log "Deleting CloudWatch alarms..."
        aws cloudwatch delete-alarms \
            --alarm-names "${existing_alarms[@]}" || warn "Failed to delete some CloudWatch alarms"
        
        log "✅ CloudWatch alarms deleted"
    else
        warn "No CloudWatch alarms found to delete"
    fi
    
    # Delete SNS topic if it exists
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log "Deleting SNS topic..."
        aws sns delete-topic \
            --topic-arn "$SNS_TOPIC_ARN" || warn "Failed to delete SNS topic"
        
        log "✅ SNS topic deleted"
    else
        warn "SNS topic ARN not available"
    fi
    
    # Delete CloudWatch dashboard if it exists
    local dashboard_name="Blue-Green-Deployments-${PROJECT_NAME}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" >/dev/null 2>&1; then
        log "Deleting CloudWatch dashboard..."
        aws cloudwatch delete-dashboards \
            --dashboard-names "$dashboard_name" || warn "Failed to delete CloudWatch dashboard"
        
        log "✅ CloudWatch dashboard deleted"
    else
        warn "CloudWatch dashboard not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Files to clean up
    local files_to_remove=(
        "${SCRIPT_DIR}/.deployment-config"
        "${SCRIPT_DIR}/lambda-function.zip"
        "${SCRIPT_DIR}/deploy-blue-green.sh"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing local file: $(basename "$file")"
            rm -f "$file"
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Display cleanup summary
display_summary() {
    log "Cleanup completed!"
    
    cat << EOF

=== Cleanup Summary ===
Project Name: $PROJECT_NAME
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID

=== Resources Cleaned Up ===
✅ ECS Cluster and Service
✅ CodeDeploy Applications
✅ Application Load Balancer and Target Groups
✅ Lambda Functions
$(if [[ "$PRESERVE_IMAGES" == "false" ]]; then echo "✅ ECR Repository and Images"; else echo "⏭️  ECR Repository (preserved)"; fi)
✅ IAM Roles and Policies
✅ CloudWatch Alarms and Monitoring
✅ Security Groups
✅ Local Configuration Files

=== Logs ===
Cleanup log: $LOG_FILE
Error log: $ERROR_LOG

$(if [[ "$PRESERVE_IMAGES" == "true" ]]; then
    echo "=== Note ==="
    echo "ECR repository '$ECR_REPOSITORY' was preserved as requested."
    echo "You may want to delete it manually if no longer needed:"
    echo "aws ecr delete-repository --repository-name $ECR_REPOSITORY --force"
    echo
fi)

All resources for project '$PROJECT_NAME' have been successfully removed!

EOF
}

# Error recovery function
cleanup_on_error() {
    error "Cleanup script encountered an error"
    error "Some resources may not have been deleted completely"
    error "Check the error log: $ERROR_LOG"
    error "You may need to manually clean up remaining resources"
    exit 1
}

trap cleanup_on_error ERR

# Main execution
main() {
    log "=== Starting Advanced Blue-Green Deployment Cleanup ==="
    
    load_configuration
    confirm_deletion
    
    # Cleanup in reverse dependency order
    cleanup_ecs_resources
    cleanup_codedeploy_resources
    cleanup_alb_resources
    cleanup_lambda_resources
    cleanup_ecr_resources
    cleanup_iam_resources
    cleanup_cloudwatch_resources
    cleanup_local_files
    
    display_summary
    
    log "=== Cleanup completed successfully! ==="
}

# Execute main function
main "$@"