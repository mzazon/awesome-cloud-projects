#!/bin/bash

# =============================================================================
# Destroy Script for Mixed Instance Auto Scaling Groups
# 
# This script safely removes all resources created by the deployment script
# for the Mixed Instance Auto Scaling Group demonstration.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for resource deletion
# - Deployment info file (optional, for automatic resource discovery)
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to prompt for confirmation
confirm_destruction() {
    echo ""
    echo "================================================================================================"
    warn "DESTRUCTIVE OPERATION WARNING"
    echo "================================================================================================"
    echo ""
    warn "This script will permanently delete ALL resources created by the Mixed Instance Auto Scaling"
    warn "Group deployment, including:"
    echo ""
    echo "  • Auto Scaling Groups and all running instances"
    echo "  • Application Load Balancers and Target Groups"
    echo "  • Launch Templates"
    echo "  • Security Groups"
    echo "  • IAM Roles and Instance Profiles"
    echo "  • SNS Topics and subscriptions"
    echo "  • CloudWatch Scaling Policies"
    echo ""
    warn "This action CANNOT be undone!"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        warn "Force delete mode enabled. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    echo ""
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    warn "Proceeding with resource destruction in 5 seconds..."
    warn "Press Ctrl+C to cancel now!"
    sleep 5
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for resource destruction..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check basic permissions
    if ! aws autoscaling describe-auto-scaling-groups --max-items 1 &> /dev/null; then
        error "Insufficient Auto Scaling permissions. Check your IAM credentials."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Set default values
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    
    # Look for deployment info file
    DEPLOYMENT_FILE=""
    if [[ -n "${DEPLOYMENT_ID:-}" ]]; then
        DEPLOYMENT_FILE="mixed-instances-deployment-${DEPLOYMENT_ID}.json"
    else
        # Find the most recent deployment file
        DEPLOYMENT_FILE=$(ls -t mixed-instances-deployment-*.json 2>/dev/null | head -1 || echo "")
    fi
    
    if [[ -f "$DEPLOYMENT_FILE" ]]; then
        log "Found deployment file: $DEPLOYMENT_FILE"
        
        # Extract resource information from deployment file
        export ASG_NAME=$(cat "$DEPLOYMENT_FILE" | grep -o '"auto_scaling_group": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        export LAUNCH_TEMPLATE_NAME=$(cat "$DEPLOYMENT_FILE" | grep -o '"launch_template": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        export SECURITY_GROUP_ID=$(cat "$DEPLOYMENT_FILE" | grep -o '"security_group": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        export IAM_ROLE_NAME=$(cat "$DEPLOYMENT_FILE" | grep -o '"iam_role": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        export ALB_ARN=$(cat "$DEPLOYMENT_FILE" | grep -o '"load_balancer": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        export TARGET_GROUP_ARN=$(cat "$DEPLOYMENT_FILE" | grep -o '"target_group": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        export SNS_TOPIC_ARN=$(cat "$DEPLOYMENT_FILE" | grep -o '"sns_topic": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
        
        # Extract deployment ID from filename
        DEPLOYMENT_SUFFIX=$(echo "$DEPLOYMENT_FILE" | sed 's/mixed-instances-deployment-//' | sed 's/\.json//')
        
        info "Loaded resource information from deployment file"
    else
        warn "No deployment file found. Will attempt to discover resources..."
        
        # Try to discover resources based on naming patterns or tags
        discover_resources
    fi
    
    # Validate we have at least some resource identifiers
    if [[ -z "${ASG_NAME:-}" && -z "${LAUNCH_TEMPLATE_NAME:-}" && -z "${SECURITY_GROUP_ID:-}" ]]; then
        error "Could not find any resources to destroy. Please provide resource names manually."
        error "Usage: DEPLOYMENT_ID=<suffix> $0"
        error "   or: ASG_NAME=<name> LAUNCH_TEMPLATE_NAME=<name> $0"
        exit 1
    fi
}

# Function to discover resources if no deployment file exists
discover_resources() {
    log "Attempting to discover Mixed Instance ASG resources..."
    
    # Try to find Auto Scaling groups with mixed instance policies
    DISCOVERED_ASGS=$(aws autoscaling describe-auto-scaling-groups \
        --query 'AutoScalingGroups[?MixedInstancesPolicy!=null].AutoScalingGroupName' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -E "mixed-instances-asg|MixedInstance" || echo "")
    
    if [[ -n "$DISCOVERED_ASGS" ]]; then
        info "Found potential Mixed Instance Auto Scaling Groups:"
        for asg in $DISCOVERED_ASGS; do
            echo "  • $asg"
        done
        echo ""
        
        if [[ "${AUTO_DISCOVER:-}" == "true" ]]; then
            export ASG_NAME=$(echo "$DISCOVERED_ASGS" | head -1)
            warn "Auto-discovery enabled. Using ASG: $ASG_NAME"
        else
            warn "Multiple Auto Scaling groups found. Please specify DEPLOYMENT_ID or ASG_NAME."
            exit 1
        fi
    fi
    
    # Try to discover related resources based on tags
    if [[ -n "${ASG_NAME:-}" ]]; then
        # Get ASG tags to find related resources
        ASG_TAGS=$(aws autoscaling describe-tags \
            --filters "Name=auto-scaling-group,Values=${ASG_NAME}" \
            --query 'Tags[?Key==`Project`].Value' --output text 2>/dev/null || echo "")
        
        if [[ -n "$ASG_TAGS" ]]; then
            info "Discovered ASG with project tag: $ASG_TAGS"
        fi
    fi
}

# Function to delete Auto Scaling group and instances
delete_auto_scaling_group() {
    if [[ -z "${ASG_NAME:-}" ]]; then
        warn "No Auto Scaling group name provided, skipping..."
        return 0
    fi
    
    log "Deleting Auto Scaling group: $ASG_NAME"
    
    # Check if ASG exists
    ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --query 'AutoScalingGroups[0].AutoScalingGroupName' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$ASG_EXISTS" == "None" || "$ASG_EXISTS" == "null" ]]; then
        info "Auto Scaling group $ASG_NAME not found, might already be deleted"
        return 0
    fi
    
    # Get current instance count for information
    INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$ASG_NAME" \
        --query 'AutoScalingGroups[0].Instances | length(@)' \
        --output text 2>/dev/null || echo "0")
    
    info "Found $INSTANCE_COUNT instances in Auto Scaling group"
    
    # Delete scaling policies first
    log "Removing scaling policies..."
    SCALING_POLICIES=$(aws autoscaling describe-policies \
        --auto-scaling-group-name "$ASG_NAME" \
        --query 'ScalingPolicies[].PolicyName' \
        --output text 2>/dev/null || echo "")
    
    for policy in $SCALING_POLICIES; do
        if [[ -n "$policy" && "$policy" != "None" ]]; then
            aws autoscaling delete-policy \
                --auto-scaling-group-name "$ASG_NAME" \
                --policy-name "$policy" 2>/dev/null || true
            info "Deleted scaling policy: $policy"
        fi
    done
    
    # Remove notification configurations
    log "Removing notification configurations..."
    aws autoscaling delete-notification-configuration \
        --auto-scaling-group-name "$ASG_NAME" \
        --topic-arn "${SNS_TOPIC_ARN}" 2>/dev/null || true
    
    # Detach load balancer target groups
    if [[ -n "${TARGET_GROUP_ARN:-}" ]]; then
        log "Detaching load balancer target groups..."
        aws autoscaling detach-load-balancer-target-groups \
            --auto-scaling-group-name "$ASG_NAME" \
            --target-group-arns "$TARGET_GROUP_ARN" 2>/dev/null || true
    fi
    
    # Scale down to zero and delete
    log "Scaling down Auto Scaling group to zero instances..."
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$ASG_NAME" \
        --min-size 0 \
        --max-size 0 \
        --desired-capacity 0
    
    # Wait for instances to terminate
    if [[ "$INSTANCE_COUNT" -gt 0 ]]; then
        info "Waiting for $INSTANCE_COUNT instances to terminate..."
        
        # Wait up to 10 minutes for instances to terminate
        for i in {1..40}; do
            CURRENT_COUNT=$(aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names "$ASG_NAME" \
                --query 'AutoScalingGroups[0].Instances | length(@)' \
                --output text 2>/dev/null || echo "0")
            
            if [[ "$CURRENT_COUNT" == "0" ]]; then
                break
            fi
            
            info "Still terminating instances ($CURRENT_COUNT remaining)..."
            sleep 15
        done
    fi
    
    # Force delete the Auto Scaling group
    log "Force deleting Auto Scaling group..."
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name "$ASG_NAME" \
        --force-delete
    
    log "Successfully deleted Auto Scaling group: $ASG_NAME"
}

# Function to delete Application Load Balancer
delete_load_balancer() {
    if [[ -z "${ALB_ARN:-}" ]]; then
        warn "No Application Load Balancer ARN provided, attempting discovery..."
        
        # Try to find ALB by name pattern
        if [[ -n "${ASG_NAME:-}" ]]; then
            ALB_SUFFIX=$(echo "$ASG_NAME" | sed 's/mixed-instances-asg-//')
            ALB_NAME="mixed-instances-alb-${ALB_SUFFIX}"
            
            ALB_ARN=$(aws elbv2 describe-load-balancers \
                --names "$ALB_NAME" \
                --query 'LoadBalancers[0].LoadBalancerArn' \
                --output text 2>/dev/null || echo "None")
            
            if [[ "$ALB_ARN" == "None" || "$ALB_ARN" == "null" ]]; then
                warn "Could not find Application Load Balancer"
                return 0
            fi
        else
            warn "No ALB information available, skipping..."
            return 0
        fi
    fi
    
    log "Deleting Application Load Balancer resources..."
    
    # Get listeners and delete them
    LISTENERS=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$ALB_ARN" \
        --query 'Listeners[].ListenerArn' \
        --output text 2>/dev/null || echo "")
    
    for listener in $LISTENERS; do
        if [[ -n "$listener" && "$listener" != "None" ]]; then
            aws elbv2 delete-listener --listener-arn "$listener" 2>/dev/null || true
            info "Deleted listener: $(basename $listener)"
        fi
    done
    
    # Delete target group if not already specified
    if [[ -z "${TARGET_GROUP_ARN:-}" ]]; then
        # Try to find target group by name pattern
        if [[ -n "${ASG_NAME:-}" ]]; then
            TG_SUFFIX=$(echo "$ASG_NAME" | sed 's/mixed-instances-asg-//')
            TG_NAME="mixed-instances-tg-${TG_SUFFIX}"
            
            TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
                --names "$TG_NAME" \
                --query 'TargetGroups[0].TargetGroupArn' \
                --output text 2>/dev/null || echo "None")
        fi
    fi
    
    # Delete target group
    if [[ -n "${TARGET_GROUP_ARN:-}" && "$TARGET_GROUP_ARN" != "None" ]]; then
        aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN" 2>/dev/null || true
        log "Deleted target group: $(basename $TARGET_GROUP_ARN)"
    fi
    
    # Delete load balancer
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
    log "Deleted Application Load Balancer: $(basename $ALB_ARN)"
    
    # Wait for load balancer to be deleted
    info "Waiting for load balancer deletion to complete..."
    sleep 30
}

# Function to delete launch template
delete_launch_template() {
    if [[ -z "${LAUNCH_TEMPLATE_NAME:-}" ]]; then
        warn "No launch template name provided, attempting discovery..."
        
        # Try to find launch template by name pattern
        if [[ -n "${ASG_NAME:-}" ]]; then
            LT_SUFFIX=$(echo "$ASG_NAME" | sed 's/mixed-instances-asg-//')
            LAUNCH_TEMPLATE_NAME="mixed-instances-template-${LT_SUFFIX}"
        else
            warn "No launch template information available, skipping..."
            return 0
        fi
    fi
    
    log "Deleting launch template: $LAUNCH_TEMPLATE_NAME"
    
    # Check if launch template exists
    LT_EXISTS=$(aws ec2 describe-launch-templates \
        --launch-template-names "$LAUNCH_TEMPLATE_NAME" \
        --query 'LaunchTemplates[0].LaunchTemplateName' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$LT_EXISTS" == "None" || "$LT_EXISTS" == "null" ]]; then
        info "Launch template $LAUNCH_TEMPLATE_NAME not found, might already be deleted"
        return 0
    fi
    
    # Delete launch template
    aws ec2 delete-launch-template --launch-template-name "$LAUNCH_TEMPLATE_NAME"
    log "Successfully deleted launch template: $LAUNCH_TEMPLATE_NAME"
}

# Function to delete security group
delete_security_group() {
    if [[ -z "${SECURITY_GROUP_ID:-}" ]]; then
        warn "No security group ID provided, attempting discovery..."
        
        # Try to find security group by name pattern
        if [[ -n "${ASG_NAME:-}" ]]; then
            SG_SUFFIX=$(echo "$ASG_NAME" | sed 's/mixed-instances-asg-//')
            SG_NAME="mixed-instances-sg-${SG_SUFFIX}"
            
            SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
                --filters "Name=group-name,Values=$SG_NAME" \
                --query 'SecurityGroups[0].GroupId' \
                --output text 2>/dev/null || echo "None")
            
            if [[ "$SECURITY_GROUP_ID" == "None" || "$SECURITY_GROUP_ID" == "null" ]]; then
                warn "Could not find security group"
                return 0
            fi
        else
            warn "No security group information available, skipping..."
            return 0
        fi
    fi
    
    log "Deleting security group: $SECURITY_GROUP_ID"
    
    # Wait a bit for any remaining dependencies to clear
    sleep 30
    
    # Try to delete security group with retries
    for i in {1..5}; do
        if aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" 2>/dev/null; then
            log "Successfully deleted security group: $SECURITY_GROUP_ID"
            return 0
        else
            warn "Attempt $i: Security group deletion failed, retrying in 30 seconds..."
            sleep 30
        fi
    done
    
    error "Failed to delete security group after 5 attempts. It may have dependencies."
    error "Please manually delete security group: $SECURITY_GROUP_ID"
}

# Function to delete IAM resources
delete_iam_resources() {
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        warn "No IAM role name provided, attempting discovery..."
        
        # Try to find IAM role by name pattern
        if [[ -n "${ASG_NAME:-}" ]]; then
            ROLE_SUFFIX=$(echo "$ASG_NAME" | sed 's/mixed-instances-asg-//')
            IAM_ROLE_NAME="EC2InstanceRole-${ROLE_SUFFIX}"
        else
            warn "No IAM role information available, skipping..."
            return 0
        fi
    fi
    
    log "Deleting IAM resources: $IAM_ROLE_NAME"
    
    # Remove role from instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name "$IAM_ROLE_NAME" \
        --role-name "$IAM_ROLE_NAME" 2>/dev/null || true
    
    # Delete instance profile
    aws iam delete-instance-profile \
        --instance-profile-name "$IAM_ROLE_NAME" 2>/dev/null || true
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null || true
    
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
    
    # Delete IAM role
    aws iam delete-role --role-name "$IAM_ROLE_NAME" 2>/dev/null || true
    
    log "Successfully deleted IAM resources: $IAM_ROLE_NAME"
}

# Function to delete SNS topic
delete_sns_topic() {
    if [[ -z "${SNS_TOPIC_ARN:-}" ]]; then
        warn "No SNS topic ARN provided, attempting discovery..."
        
        # Try to find SNS topic by name pattern
        if [[ -n "${ASG_NAME:-}" ]]; then
            TOPIC_SUFFIX=$(echo "$ASG_NAME" | sed 's/mixed-instances-asg-//')
            TOPIC_NAME="autoscaling-notifications-${TOPIC_SUFFIX}"
            
            SNS_TOPIC_ARN=$(aws sns list-topics \
                --query "Topics[?contains(TopicArn, '$TOPIC_NAME')].TopicArn" \
                --output text 2>/dev/null || echo "")
            
            if [[ -z "$SNS_TOPIC_ARN" ]]; then
                warn "Could not find SNS topic"
                return 0
            fi
        else
            warn "No SNS topic information available, skipping..."
            return 0
        fi
    fi
    
    log "Deleting SNS topic: $SNS_TOPIC_ARN"
    
    # Delete SNS topic
    aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null || true
    log "Successfully deleted SNS topic: $(basename $SNS_TOPIC_ARN)"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info files
    if [[ -n "${DEPLOYMENT_SUFFIX:-}" ]]; then
        if [[ -f "mixed-instances-deployment-${DEPLOYMENT_SUFFIX}.json" ]]; then
            rm -f "mixed-instances-deployment-${DEPLOYMENT_SUFFIX}.json"
            info "Removed deployment file: mixed-instances-deployment-${DEPLOYMENT_SUFFIX}.json"
        fi
    else
        # Remove all deployment files if no specific suffix
        DEPLOYMENT_FILES=$(ls mixed-instances-deployment-*.json 2>/dev/null || echo "")
        for file in $DEPLOYMENT_FILES; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                info "Removed deployment file: $file"
            fi
        done
    fi
    
    # Remove any temporary files
    rm -f /tmp/ec2-trust-policy.json
    rm -f /tmp/launch-template.json
    rm -f /tmp/asg-mixed-instances.json
    rm -f /tmp/user-data.sh
    rm -f /tmp/mixed-instances-deployment.json
    
    log "Local file cleanup completed"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local issues_found=false
    
    # Check Auto Scaling group
    if [[ -n "${ASG_NAME:-}" ]]; then
        ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --query 'AutoScalingGroups[0].AutoScalingGroupName' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$ASG_EXISTS" != "None" && "$ASG_EXISTS" != "null" ]]; then
            warn "Auto Scaling group still exists: $ASG_NAME"
            issues_found=true
        else
            info "✓ Auto Scaling group deleted: $ASG_NAME"
        fi
    fi
    
    # Check Launch Template
    if [[ -n "${LAUNCH_TEMPLATE_NAME:-}" ]]; then
        LT_EXISTS=$(aws ec2 describe-launch-templates \
            --launch-template-names "$LAUNCH_TEMPLATE_NAME" \
            --query 'LaunchTemplates[0].LaunchTemplateName' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$LT_EXISTS" != "None" && "$LT_EXISTS" != "null" ]]; then
            warn "Launch template still exists: $LAUNCH_TEMPLATE_NAME"
            issues_found=true
        else
            info "✓ Launch template deleted: $LAUNCH_TEMPLATE_NAME"
        fi
    fi
    
    # Check Security Group
    if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
        SG_EXISTS=$(aws ec2 describe-security-groups \
            --group-ids "$SECURITY_GROUP_ID" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$SG_EXISTS" != "None" && "$SG_EXISTS" != "null" ]]; then
            warn "Security group still exists: $SECURITY_GROUP_ID"
            issues_found=true
        else
            info "✓ Security group deleted: $SECURITY_GROUP_ID"
        fi
    fi
    
    # Check IAM Role
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        ROLE_EXISTS=$(aws iam get-role \
            --role-name "$IAM_ROLE_NAME" \
            --query 'Role.RoleName' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$ROLE_EXISTS" != "None" && "$ROLE_EXISTS" != "null" ]]; then
            warn "IAM role still exists: $IAM_ROLE_NAME"
            issues_found=true
        else
            info "✓ IAM role deleted: $IAM_ROLE_NAME"
        fi
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        warn "Some resources may still exist. Check the AWS Console manually."
        warn "You may need to wait a few minutes and run this script again."
    else
        log "All resources have been successfully deleted!"
    fi
}

# Function to display destruction summary
display_summary() {
    echo ""
    echo "================================================================================================"
    log "Mixed Instance Auto Scaling Group Destruction Completed!"
    echo "================================================================================================"
    echo ""
    info "Resources Removed:"
    echo "  • Auto Scaling Group: ${ASG_NAME:-'N/A'}"
    echo "  • Launch Template: ${LAUNCH_TEMPLATE_NAME:-'N/A'}"
    echo "  • Security Group: ${SECURITY_GROUP_ID:-'N/A'}"
    echo "  • IAM Role: ${IAM_ROLE_NAME:-'N/A'}"
    echo "  • Load Balancer: ${ALB_ARN:-'N/A'}"
    echo "  • Target Group: ${TARGET_GROUP_ARN:-'N/A'}"
    echo "  • SNS Topic: ${SNS_TOPIC_ARN:-'N/A'}"
    echo ""
    info "Cost Impact:"
    echo "  • All billable resources have been terminated"
    echo "  • No further charges should occur for this deployment"
    echo "  • Check AWS Cost Explorer to verify charge cessation"
    echo ""
    info "Next Steps:"
    echo "  • Verify deletion in AWS Console if needed"
    echo "  • Review AWS billing to confirm cost savings"
    echo "  • Consider setting up billing alerts for future deployments"
    echo ""
    warn "Important Notes:"
    echo "  • Some resources may take up to 15 minutes to fully disappear from console"
    echo "  • CloudWatch logs and metrics are retained based on their retention settings"
    echo "  • Any data stored in instances has been permanently lost"
    echo ""
    echo "================================================================================================"
    log "Destruction completed at $(date)"
    echo "================================================================================================"
}

# Main destruction function
main() {
    log "Starting Mixed Instance Auto Scaling Group destruction..."
    
    # Load deployment information
    check_prerequisites
    load_deployment_info
    
    # Show confirmation dialog
    confirm_destruction
    
    # Delete resources in reverse order of creation
    log "Beginning resource deletion process..."
    
    delete_auto_scaling_group
    delete_load_balancer
    delete_launch_template
    delete_security_group
    delete_iam_resources
    delete_sns_topic
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    display_summary
    
    log "Destruction script completed successfully!"
}

# Cleanup function for script interruption
cleanup_on_error() {
    error "Script interrupted. Some resources may not have been deleted."
    error "Check the AWS Console and re-run this script to complete cleanup."
    exit 1
}

# Function to show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force              Skip confirmation prompt"
    echo "  --auto-discover      Automatically discover resources to delete"
    echo "  --deployment-id ID   Use specific deployment ID"
    echo "  --help               Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  DEPLOYMENT_ID        Specific deployment suffix to target"
    echo "  ASG_NAME            Auto Scaling Group name to delete"
    echo "  LAUNCH_TEMPLATE_NAME Launch Template name to delete"
    echo "  SECURITY_GROUP_ID   Security Group ID to delete"
    echo "  IAM_ROLE_NAME       IAM Role name to delete"
    echo "  ALB_ARN             Application Load Balancer ARN to delete"
    echo "  TARGET_GROUP_ARN    Target Group ARN to delete"
    echo "  SNS_TOPIC_ARN       SNS Topic ARN to delete"
    echo "  FORCE_DELETE        Set to 'true' to skip confirmation"
    echo "  AUTO_DISCOVER       Set to 'true' to auto-discover resources"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode with auto-discovery"
    echo "  $0 --force                           # Force delete without confirmation"
    echo "  DEPLOYMENT_ID=abc123 $0              # Delete specific deployment"
    echo "  ASG_NAME=my-asg $0                   # Delete specific ASG and related resources"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --auto-discover)
            export AUTO_DISCOVER="true"
            shift
            ;;
        --deployment-id)
            export DEPLOYMENT_ID="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Set trap for cleanup on script interruption
trap cleanup_on_error INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi