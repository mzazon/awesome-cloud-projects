#!/bin/bash

#
# Destroy Script for Auto Scaling with Application Load Balancers and Target Groups
# This script safely removes all infrastructure created by the deploy.sh script
# with proper confirmation prompts and dependency handling
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    log_info "✅ Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment-info.txt" ]]; then
        log_info "Found deployment-info.txt, loading resource identifiers..."
        source deployment-info.txt
        
        log_info "Loaded deployment information:"
        log_info "  ASG Name: ${ASG_NAME:-not found}"
        log_info "  ALB Name: ${ALB_NAME:-not found}"
        log_info "  Target Group: ${TG_NAME:-not found}"
        log_info "  Launch Template: ${LT_NAME:-not found}"
        log_info "  Security Group: ${SG_NAME:-not found}"
        
    else
        log_warn "deployment-info.txt not found. You'll need to specify resource names manually."
        log_info "Please provide the resource suffix used during deployment:"
        read -p "Resource suffix (6-character string): " SUFFIX
        
        if [[ -z "$SUFFIX" ]]; then
            log_error "Resource suffix is required for cleanup"
            exit 1
        fi
        
        export ASG_NAME="web-app-asg-${SUFFIX}"
        export ALB_NAME="web-app-alb-${SUFFIX}"
        export TG_NAME="web-app-targets-${SUFFIX}"
        export LT_NAME="web-app-template-${SUFFIX}"
        export SG_NAME="web-app-sg-${SUFFIX}"
    fi
}

# Discover resources if deployment info is incomplete
discover_resources() {
    log_info "Discovering AWS resources for cleanup..."
    
    # Discover Auto Scaling Group
    if [[ -n "${ASG_NAME:-}" ]]; then
        ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --query 'AutoScalingGroups[0].AutoScalingGroupName' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$ASG_EXISTS" != "None" && "$ASG_EXISTS" != "null" ]]; then
            log_info "Found Auto Scaling Group: $ASG_NAME"
            export ASG_ARN="$ASG_EXISTS"
        else
            log_warn "Auto Scaling Group $ASG_NAME not found"
            export ASG_NAME=""
        fi
    fi
    
    # Discover Application Load Balancer
    if [[ -n "${ALB_NAME:-}" ]]; then
        ALB_ARN=$(aws elbv2 describe-load-balancers \
            --names "$ALB_NAME" \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$ALB_ARN" != "None" && "$ALB_ARN" != "null" ]]; then
            log_info "Found Application Load Balancer: $ALB_NAME"
            export ALB_ARN
        else
            log_warn "Application Load Balancer $ALB_NAME not found"
            export ALB_NAME=""
            export ALB_ARN=""
        fi
    fi
    
    # Discover Target Group
    if [[ -n "${TG_NAME:-}" ]]; then
        TG_ARN=$(aws elbv2 describe-target-groups \
            --names "$TG_NAME" \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$TG_ARN" != "None" && "$TG_ARN" != "null" ]]; then
            log_info "Found Target Group: $TG_NAME"
            export TG_ARN
        else
            log_warn "Target Group $TG_NAME not found"
            export TG_NAME=""
            export TG_ARN=""
        fi
    fi
    
    # Discover Launch Template
    if [[ -n "${LT_NAME:-}" ]]; then
        LT_EXISTS=$(aws ec2 describe-launch-templates \
            --launch-template-names "$LT_NAME" \
            --query 'LaunchTemplates[0].LaunchTemplateName' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$LT_EXISTS" != "None" && "$LT_EXISTS" != "null" ]]; then
            log_info "Found Launch Template: $LT_NAME"
        else
            log_warn "Launch Template $LT_NAME not found"
            export LT_NAME=""
        fi
    fi
    
    # Discover Security Group
    if [[ -n "${SG_NAME:-}" ]]; then
        SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=$SG_NAME" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$SG_ID" != "None" && "$SG_ID" != "null" ]]; then
            log_info "Found Security Group: $SG_NAME ($SG_ID)"
            export SG_ID
        else
            log_warn "Security Group $SG_NAME not found"
            export SG_NAME=""
            export SG_ID=""
        fi
    fi
}

# Display resources to be deleted
display_resources() {
    log_info "The following resources will be deleted:"
    echo
    echo "🏗️  Infrastructure Resources:"
    [[ -n "${ASG_NAME:-}" ]] && echo "   • Auto Scaling Group: $ASG_NAME"
    [[ -n "${ALB_NAME:-}" ]] && echo "   • Application Load Balancer: $ALB_NAME"
    [[ -n "${TG_NAME:-}" ]] && echo "   • Target Group: $TG_NAME"
    [[ -n "${LT_NAME:-}" ]] && echo "   • Launch Template: $LT_NAME"
    [[ -n "${SG_NAME:-}" ]] && echo "   • Security Group: $SG_NAME"
    echo
    echo "📊 Monitoring Resources:"
    [[ -n "${ASG_NAME:-}" ]] && echo "   • CloudWatch Alarms: ${ASG_NAME}-high-cpu, ${ASG_NAME}-unhealthy-targets"
    [[ -n "${ASG_NAME:-}" ]] && echo "   • Scheduled Scaling Actions: scale-up-business-hours, scale-down-after-hours"
    [[ -n "${ASG_NAME:-}" ]] && echo "   • Auto Scaling Policies: cpu-target-tracking-policy, alb-request-count-policy"
    echo
    echo "💾 Files:"
    echo "   • deployment-info.txt (if exists)"
    echo "   • Temporary files (*.json)"
    echo
}

# Confirmation prompt
confirm_deletion() {
    log_warn "⚠️  WARNING: This action will permanently delete all listed resources!"
    log_warn "⚠️  This action cannot be undone and may result in data loss!"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    log_warn "Starting destruction in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
}

# Delete Auto Scaling Group and related resources
delete_auto_scaling_group() {
    if [[ -z "${ASG_NAME:-}" ]]; then
        log_info "No Auto Scaling Group to delete"
        return 0
    fi
    
    log_step "Deleting Auto Scaling Group and related resources..."
    
    # Delete scheduled actions first
    log_info "Deleting scheduled scaling actions..."
    aws autoscaling delete-scheduled-action \
        --auto-scaling-group-name "$ASG_NAME" \
        --scheduled-action-name "scale-up-business-hours" 2>/dev/null || log_warn "Failed to delete scale-up-business-hours action"
    
    aws autoscaling delete-scheduled-action \
        --auto-scaling-group-name "$ASG_NAME" \
        --scheduled-action-name "scale-down-after-hours" 2>/dev/null || log_warn "Failed to delete scale-down-after-hours action"
    
    # Set desired capacity to 0
    log_info "Scaling down Auto Scaling Group to 0 instances..."
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$ASG_NAME" \
        --min-size 0 \
        --desired-capacity 0
    
    # Wait for instances to terminate
    log_info "Waiting for instances to terminate (this may take several minutes)..."
    
    # Check instance count every 30 seconds
    local max_wait=600  # 10 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local instance_count=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --query 'AutoScalingGroups[0].Instances | length(@)' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$instance_count" == "0" ]]; then
            log_info "All instances have been terminated"
            break
        fi
        
        log_info "Waiting for $instance_count instances to terminate..."
        sleep 30
        wait_time=$((wait_time + 30))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log_warn "Timeout waiting for instances to terminate. Forcing deletion..."
    fi
    
    # Delete Auto Scaling Group
    log_info "Deleting Auto Scaling Group: $ASG_NAME"
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name "$ASG_NAME" \
        --force-delete
    
    log_info "✅ Auto Scaling Group deleted successfully"
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    if [[ -z "${ASG_NAME:-}" ]]; then
        log_info "No CloudWatch alarms to delete"
        return 0
    fi
    
    log_step "Deleting CloudWatch alarms..."
    
    local alarm_names=(
        "${ASG_NAME}-high-cpu"
        "${ASG_NAME}-unhealthy-targets"
    )
    
    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0]' --output text &>/dev/null; then
            log_info "Deleting CloudWatch alarm: $alarm_name"
            aws cloudwatch delete-alarms --alarm-names "$alarm_name"
        else
            log_warn "CloudWatch alarm $alarm_name not found"
        fi
    done
    
    log_info "✅ CloudWatch alarms deleted"
}

# Delete Application Load Balancer
delete_load_balancer() {
    if [[ -z "${ALB_ARN:-}" ]]; then
        log_info "No Application Load Balancer to delete"
        return 0
    fi
    
    log_step "Deleting Application Load Balancer..."
    
    log_info "Deleting Application Load Balancer: $ALB_NAME"
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
    
    # Wait for load balancer deletion
    log_info "Waiting for load balancer to be deleted..."
    aws elbv2 wait load-balancer-deleted --load-balancer-arns "$ALB_ARN"
    
    log_info "✅ Application Load Balancer deleted successfully"
}

# Delete Target Group
delete_target_group() {
    if [[ -z "${TG_ARN:-}" ]]; then
        log_info "No Target Group to delete"
        return 0
    fi
    
    log_step "Deleting Target Group..."
    
    log_info "Deleting Target Group: $TG_NAME"
    aws elbv2 delete-target-group --target-group-arn "$TG_ARN"
    
    log_info "✅ Target Group deleted successfully"
}

# Delete Launch Template
delete_launch_template() {
    if [[ -z "${LT_NAME:-}" ]]; then
        log_info "No Launch Template to delete"
        return 0
    fi
    
    log_step "Deleting Launch Template..."
    
    log_info "Deleting Launch Template: $LT_NAME"
    aws ec2 delete-launch-template --launch-template-name "$LT_NAME"
    
    log_info "✅ Launch Template deleted successfully"
}

# Delete Security Group
delete_security_group() {
    if [[ -z "${SG_ID:-}" ]]; then
        log_info "No Security Group to delete"
        return 0
    fi
    
    log_step "Deleting Security Group..."
    
    # Wait a moment for resources to fully detach
    log_info "Waiting for resources to detach from security group..."
    sleep 30
    
    # Check if security group is still in use
    local max_retries=5
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null; then
            log_info "✅ Security Group deleted successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            log_warn "Failed to delete security group (attempt $retry_count/$max_retries). Retrying in 30 seconds..."
            sleep 30
        fi
    done
    
    log_error "Failed to delete security group $SG_ID after $max_retries attempts"
    log_error "The security group may still be in use. Please delete it manually later."
}

# Clean up local files
cleanup_local_files() {
    log_step "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.txt"
        "user-data.sh"
        "cpu-target-tracking.json"
        "alb-target-tracking.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    log_info "✅ Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_step "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Auto Scaling Group
    if [[ -n "${ASG_NAME:-}" ]]; then
        if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --query 'AutoScalingGroups[0]' --output text &>/dev/null; then
            log_error "Auto Scaling Group $ASG_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Application Load Balancer
    if [[ -n "${ALB_ARN:-}" ]]; then
        if aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0]' --output text &>/dev/null; then
            log_error "Application Load Balancer $ALB_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Target Group
    if [[ -n "${TG_ARN:-}" ]]; then
        if aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" --query 'TargetGroups[0]' --output text &>/dev/null; then
            log_error "Target Group $TG_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Launch Template
    if [[ -n "${LT_NAME:-}" ]]; then
        if aws ec2 describe-launch-templates --launch-template-names "$LT_NAME" --query 'LaunchTemplates[0]' --output text &>/dev/null; then
            log_error "Launch Template $LT_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Security Group
    if [[ -n "${SG_ID:-}" ]]; then
        if aws ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0]' --output text &>/dev/null; then
            log_warn "Security Group $SG_ID still exists (may require manual cleanup)"
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_info "✅ Cleanup verification completed successfully"
    else
        log_error "❌ Cleanup verification found $cleanup_issues issues"
        log_error "Some resources may require manual cleanup"
    fi
}

# Main destruction function
main() {
    log_info "🧹 Starting Auto Scaling infrastructure cleanup..."
    
    check_prerequisites
    load_deployment_info
    discover_resources
    display_resources
    confirm_deletion
    
    # Execute cleanup in correct order (reverse of creation)
    delete_auto_scaling_group
    delete_cloudwatch_alarms
    delete_load_balancer
    delete_target_group
    delete_launch_template
    delete_security_group
    cleanup_local_files
    verify_cleanup
    
    log_info "🎉 Cleanup completed!"
    log_info ""
    log_info "All resources have been successfully deleted."
    log_info "Your AWS account should no longer be charged for these resources."
    log_info ""
    log_warn "Note: If you see any warnings about remaining resources,"
    log_warn "      please check the AWS Console and delete them manually."
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warn ""
    log_warn "Script interrupted by user"
    log_warn "Some resources may have been partially deleted"
    log_warn "Run the script again to complete cleanup"
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Check if running in non-interactive mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi