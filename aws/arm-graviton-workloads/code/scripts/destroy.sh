#!/bin/bash

# Destroy script for ARM-based Workloads with AWS Graviton Processors
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Function to confirm destructive action
confirm_destroy() {
    echo ""
    echo "=================================="
    echo "DANGER: RESOURCE DESTRUCTION"
    echo "=================================="
    echo ""
    echo "This script will permanently destroy all resources created by the Graviton demo deployment."
    echo ""
    echo "Resources that will be DELETED:"
    echo "  - EC2 instances (x86 and ARM)"
    echo "  - Application Load Balancer"
    echo "  - Auto Scaling Group and Launch Template"
    echo "  - Security Groups"
    echo "  - Key Pairs"
    echo "  - CloudWatch Dashboard"
    echo "  - CloudWatch Alarms"
    echo ""
    echo "This action CANNOT be undone."
    echo ""
    
    read -p "Are you sure you want to proceed? (Type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [ ! -f "deployment-state.json" ]; then
        error "deployment-state.json not found. Cannot proceed without deployment state information."
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        warn "jq not available. Using manual parsing."
        
        # Manual parsing for key values
        STACK_NAME=$(grep -o '"stack_name": *"[^"]*"' deployment-state.json | cut -d'"' -f4)
        KEY_PAIR_NAME=$(grep -o '"key_pair_name": *"[^"]*"' deployment-state.json | cut -d'"' -f4)
        AWS_REGION=$(grep -o '"aws_region": *"[^"]*"' deployment-state.json | cut -d'"' -f4)
        
        # Try to extract other values
        X86_INSTANCE_ID=$(grep -o '"x86_instance_id": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        ARM_INSTANCE_ID=$(grep -o '"arm_instance_id": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        SECURITY_GROUP_ID=$(grep -o '"security_group_id": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        ALB_ARN=$(grep -o '"alb_arn": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        TARGET_GROUP_ARN=$(grep -o '"target_group_arn": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        LISTENER_ARN=$(grep -o '"listener_arn": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        LAUNCH_TEMPLATE_ID=$(grep -o '"launch_template_id": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        ASG_NAME=$(grep -o '"asg_name": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        DASHBOARD_NAME=$(grep -o '"dashboard_name": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
        COST_ALARM_NAME=$(grep -o '"cost_alarm_name": *"[^"]*"' deployment-state.json | cut -d'"' -f4 || echo "")
    else
        # Using jq for parsing
        STACK_NAME=$(jq -r '.stack_name' deployment-state.json)
        KEY_PAIR_NAME=$(jq -r '.key_pair_name' deployment-state.json)
        AWS_REGION=$(jq -r '.aws_region' deployment-state.json)
        X86_INSTANCE_ID=$(jq -r '.x86_instance_id // empty' deployment-state.json)
        ARM_INSTANCE_ID=$(jq -r '.arm_instance_id // empty' deployment-state.json)
        SECURITY_GROUP_ID=$(jq -r '.security_group_id // empty' deployment-state.json)
        ALB_ARN=$(jq -r '.alb_arn // empty' deployment-state.json)
        TARGET_GROUP_ARN=$(jq -r '.target_group_arn // empty' deployment-state.json)
        LISTENER_ARN=$(jq -r '.listener_arn // empty' deployment-state.json)
        LAUNCH_TEMPLATE_ID=$(jq -r '.launch_template_id // empty' deployment-state.json)
        ASG_NAME=$(jq -r '.asg_name // empty' deployment-state.json)
        DASHBOARD_NAME=$(jq -r '.dashboard_name // empty' deployment-state.json)
        COST_ALARM_NAME=$(jq -r '.cost_alarm_name // empty' deployment-state.json)
    fi
    
    if [ -z "$STACK_NAME" ]; then
        error "Stack name not found in deployment state."
    fi
    
    log "Loaded deployment state for stack: $STACK_NAME"
    log "Region: $AWS_REGION"
    
    # Set AWS region
    export AWS_REGION="$AWS_REGION"
    
    success "Deployment state loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 before running this script."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set up credentials."
    fi
    
    success "Prerequisites check completed"
}

# Delete Auto Scaling Group and Launch Template
delete_auto_scaling_group() {
    log "Deleting Auto Scaling Group and Launch Template..."
    
    if [ -n "$ASG_NAME" ]; then
        log "Deleting Auto Scaling Group: $ASG_NAME"
        
        # Check if ASG exists
        if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" &> /dev/null; then
            # Set desired capacity to 0
            aws autoscaling update-auto-scaling-group \
                --auto-scaling-group-name "$ASG_NAME" \
                --desired-capacity 0 \
                --min-size 0 || warn "Failed to update ASG capacity"
            
            # Wait for instances to terminate
            log "Waiting for ASG instances to terminate..."
            sleep 30
            
            # Force delete the ASG
            aws autoscaling delete-auto-scaling-group \
                --auto-scaling-group-name "$ASG_NAME" \
                --force-delete || warn "Failed to delete ASG: $ASG_NAME"
            
            log "Auto Scaling Group deleted"
        else
            warn "Auto Scaling Group $ASG_NAME not found or already deleted"
        fi
    else
        warn "No Auto Scaling Group name found in deployment state"
    fi
    
    if [ -n "$LAUNCH_TEMPLATE_ID" ]; then
        log "Deleting Launch Template: $LAUNCH_TEMPLATE_ID"
        
        # Check if launch template exists
        if aws ec2 describe-launch-templates --launch-template-ids "$LAUNCH_TEMPLATE_ID" &> /dev/null; then
            aws ec2 delete-launch-template \
                --launch-template-id "$LAUNCH_TEMPLATE_ID" || warn "Failed to delete launch template: $LAUNCH_TEMPLATE_ID"
            
            log "Launch Template deleted"
        else
            warn "Launch Template $LAUNCH_TEMPLATE_ID not found or already deleted"
        fi
    else
        warn "No Launch Template ID found in deployment state"
    fi
    
    success "Auto Scaling Group and Launch Template cleanup completed"
}

# Delete Load Balancer resources
delete_load_balancer() {
    log "Deleting Load Balancer resources..."
    
    # Delete listener
    if [ -n "$LISTENER_ARN" ]; then
        log "Deleting ALB Listener: $LISTENER_ARN"
        
        if aws elbv2 describe-listeners --listener-arns "$LISTENER_ARN" &> /dev/null; then
            aws elbv2 delete-listener \
                --listener-arn "$LISTENER_ARN" || warn "Failed to delete listener: $LISTENER_ARN"
            
            log "ALB Listener deleted"
        else
            warn "Listener $LISTENER_ARN not found or already deleted"
        fi
    else
        warn "No Listener ARN found in deployment state"
    fi
    
    # Delete target group
    if [ -n "$TARGET_GROUP_ARN" ]; then
        log "Deleting Target Group: $TARGET_GROUP_ARN"
        
        if aws elbv2 describe-target-groups --target-group-arns "$TARGET_GROUP_ARN" &> /dev/null; then
            # Deregister all targets first
            aws elbv2 deregister-targets \
                --target-group-arn "$TARGET_GROUP_ARN" \
                --targets Id="$X86_INSTANCE_ID" Id="$ARM_INSTANCE_ID" || warn "Failed to deregister targets"
            
            # Wait a bit for deregistration
            sleep 10
            
            aws elbv2 delete-target-group \
                --target-group-arn "$TARGET_GROUP_ARN" || warn "Failed to delete target group: $TARGET_GROUP_ARN"
            
            log "Target Group deleted"
        else
            warn "Target Group $TARGET_GROUP_ARN not found or already deleted"
        fi
    else
        warn "No Target Group ARN found in deployment state"
    fi
    
    # Delete Application Load Balancer
    if [ -n "$ALB_ARN" ]; then
        log "Deleting Application Load Balancer: $ALB_ARN"
        
        if aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" &> /dev/null; then
            aws elbv2 delete-load-balancer \
                --load-balancer-arn "$ALB_ARN" || warn "Failed to delete ALB: $ALB_ARN"
            
            log "Application Load Balancer deleted"
            
            # Wait for ALB to be fully deleted
            log "Waiting for ALB to be fully deleted..."
            sleep 30
        else
            warn "ALB $ALB_ARN not found or already deleted"
        fi
    else
        warn "No ALB ARN found in deployment state"
    fi
    
    success "Load Balancer resources cleanup completed"
}

# Terminate EC2 instances
terminate_instances() {
    log "Terminating EC2 instances..."
    
    local instances_to_terminate=()
    
    # Add instances to termination list
    if [ -n "$X86_INSTANCE_ID" ]; then
        instances_to_terminate+=("$X86_INSTANCE_ID")
    fi
    
    if [ -n "$ARM_INSTANCE_ID" ]; then
        instances_to_terminate+=("$ARM_INSTANCE_ID")
    fi
    
    # Also find any instances created by the ASG
    if [ -n "$STACK_NAME" ]; then
        ASG_INSTANCES=$(aws ec2 describe-instances \
            --filters "Name=tag:StackName,Values=$STACK_NAME" "Name=instance-state-name,Values=running,pending,stopping" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text || echo "")
        
        if [ -n "$ASG_INSTANCES" ]; then
            for instance in $ASG_INSTANCES; do
                if [[ ! " ${instances_to_terminate[@]} " =~ " ${instance} " ]]; then
                    instances_to_terminate+=("$instance")
                fi
            done
        fi
    fi
    
    if [ ${#instances_to_terminate[@]} -gt 0 ]; then
        log "Terminating instances: ${instances_to_terminate[*]}"
        
        aws ec2 terminate-instances \
            --instance-ids "${instances_to_terminate[@]}" || warn "Failed to terminate some instances"
        
        log "Waiting for instances to terminate..."
        for instance in "${instances_to_terminate[@]}"; do
            aws ec2 wait instance-terminated --instance-ids "$instance" || warn "Failed to wait for instance $instance to terminate"
        done
        
        log "All instances terminated"
    else
        warn "No instances found to terminate"
    fi
    
    success "EC2 instances cleanup completed"
}

# Delete security group
delete_security_group() {
    log "Deleting security group..."
    
    if [ -n "$SECURITY_GROUP_ID" ]; then
        log "Deleting Security Group: $SECURITY_GROUP_ID"
        
        # Wait a bit to ensure instances are fully terminated
        sleep 10
        
        # Check if security group exists
        if aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" &> /dev/null; then
            aws ec2 delete-security-group \
                --group-id "$SECURITY_GROUP_ID" || warn "Failed to delete security group: $SECURITY_GROUP_ID"
            
            log "Security Group deleted"
        else
            warn "Security Group $SECURITY_GROUP_ID not found or already deleted"
        fi
    else
        warn "No Security Group ID found in deployment state"
    fi
    
    success "Security Group cleanup completed"
}

# Delete key pair
delete_key_pair() {
    log "Deleting key pair..."
    
    if [ -n "$KEY_PAIR_NAME" ]; then
        log "Deleting Key Pair: $KEY_PAIR_NAME"
        
        # Check if key pair exists
        if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &> /dev/null; then
            aws ec2 delete-key-pair \
                --key-name "$KEY_PAIR_NAME" || warn "Failed to delete key pair: $KEY_PAIR_NAME"
            
            log "Key Pair deleted from AWS"
        else
            warn "Key Pair $KEY_PAIR_NAME not found or already deleted"
        fi
        
        # Delete local key file
        if [ -f "${KEY_PAIR_NAME}.pem" ]; then
            rm -f "${KEY_PAIR_NAME}.pem"
            log "Local key file deleted"
        fi
    else
        warn "No Key Pair name found in deployment state"
    fi
    
    success "Key Pair cleanup completed"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if [ -n "$DASHBOARD_NAME" ]; then
        log "Deleting CloudWatch Dashboard: $DASHBOARD_NAME"
        
        if aws cloudwatch list-dashboards --dashboard-name-prefix "$DASHBOARD_NAME" | grep -q "$DASHBOARD_NAME"; then
            aws cloudwatch delete-dashboards \
                --dashboard-names "$DASHBOARD_NAME" || warn "Failed to delete dashboard: $DASHBOARD_NAME"
            
            log "CloudWatch Dashboard deleted"
        else
            warn "Dashboard $DASHBOARD_NAME not found or already deleted"
        fi
    else
        warn "No Dashboard name found in deployment state"
    fi
    
    # Delete CloudWatch alarm
    if [ -n "$COST_ALARM_NAME" ]; then
        log "Deleting CloudWatch Alarm: $COST_ALARM_NAME"
        
        if aws cloudwatch describe-alarms --alarm-names "$COST_ALARM_NAME" | grep -q "$COST_ALARM_NAME"; then
            aws cloudwatch delete-alarms \
                --alarm-names "$COST_ALARM_NAME" || warn "Failed to delete alarm: $COST_ALARM_NAME"
            
            log "CloudWatch Alarm deleted"
        else
            warn "Alarm $COST_ALARM_NAME not found or already deleted"
        fi
    else
        warn "No Alarm name found in deployment state"
    fi
    
    success "CloudWatch resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment state file
    if [ -f "deployment-state.json" ]; then
        rm -f deployment-state.json
        log "Removed deployment-state.json"
    fi
    
    # Remove user data scripts
    if [ -f "user-data-x86.sh" ]; then
        rm -f user-data-x86.sh
        log "Removed user-data-x86.sh"
    fi
    
    if [ -f "user-data-arm.sh" ]; then
        rm -f user-data-arm.sh
        log "Removed user-data-arm.sh"
    fi
    
    # Remove dashboard config
    if [ -f "dashboard-config.json" ]; then
        rm -f dashboard-config.json
        log "Removed dashboard-config.json"
    fi
    
    # Remove any temporary files
    rm -f tmp.json 2>/dev/null || true
    
    success "Local files cleanup completed"
}

# Display destruction summary
display_summary() {
    log "Destruction completed successfully!"
    
    echo ""
    echo "=================================="
    echo "DESTRUCTION SUMMARY"
    echo "=================================="
    echo ""
    echo "The following resources have been destroyed:"
    echo ""
    echo "✓ Auto Scaling Group and Launch Template"
    echo "✓ Application Load Balancer and Target Group"
    echo "✓ EC2 Instances (x86 and ARM)"
    echo "✓ Security Group"
    echo "✓ Key Pair"
    echo "✓ CloudWatch Dashboard and Alarms"
    echo "✓ Local configuration files"
    echo ""
    echo "Stack '$STACK_NAME' has been completely removed."
    echo ""
    echo "IMPORTANT NOTES:"
    echo "- Check AWS Cost Explorer for any remaining charges"
    echo "- Verify all resources are deleted in the AWS Console"
    echo "- Some AWS services may have delayed billing"
    echo ""
    echo "=================================="
    
    success "All resources have been successfully destroyed!"
}

# Main execution
main() {
    log "Starting destruction of ARM-based Workloads with AWS Graviton Processors"
    
    # Run destruction steps
    check_prerequisites
    confirm_destroy
    load_deployment_state
    delete_auto_scaling_group
    delete_load_balancer
    terminate_instances
    delete_security_group
    delete_key_pair
    delete_cloudwatch_resources
    cleanup_local_files
    display_summary
    
    log "Destruction process completed"
}

# Execute main function
main "$@"