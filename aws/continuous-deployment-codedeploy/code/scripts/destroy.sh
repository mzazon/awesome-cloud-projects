#!/bin/bash

# Destroy script for Continuous Deployment with CodeDeploy
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Confirmation prompt
confirm_destroy() {
    echo ""
    echo "=== DESTROY CONFIRMATION ==="
    echo "This script will permanently delete ALL resources created by the deployment script."
    echo "This action cannot be undone!"
    echo ""
    
    if [ -f ".env" ]; then
        source .env
        echo "Resources to be deleted:"
        echo "- Application: ${APP_NAME:-Unknown}"
        echo "- Repository: ${REPO_NAME:-Unknown}"
        echo "- Build Project: ${BUILD_PROJECT_NAME:-Unknown}"
        echo "- S3 Bucket: ${ARTIFACTS_BUCKET_NAME:-Unknown}"
        echo "- Region: ${AWS_REGION:-Unknown}"
        echo ""
    else
        warning "Environment file (.env) not found. Some cleanup may be incomplete."
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destroy operation cancelled"
        exit 0
    fi
    echo ""
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env" ]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        error "Environment file (.env) not found. Cannot proceed with cleanup."
        error "This file should contain resource identifiers from the deployment."
        exit 1
    fi
    
    # Verify required variables
    if [ -z "${APP_NAME:-}" ] || [ -z "${AWS_REGION:-}" ]; then
        error "Required environment variables missing. Cannot proceed safely."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Stop any running deployments
stop_deployments() {
    log "Stopping any running deployments..."
    
    # Get list of deployments for the application
    DEPLOYMENT_IDS=$(aws deploy list-deployments \
        --application-name "$APP_NAME" \
        --deployment-group-name "$DEPLOYMENT_GROUP_NAME" \
        --include-only-statuses "Created,Queued,InProgress,Ready" \
        --query 'deployments' --output text 2>/dev/null || echo "")
    
    if [ -n "$DEPLOYMENT_IDS" ] && [ "$DEPLOYMENT_IDS" != "None" ]; then
        for deployment_id in $DEPLOYMENT_IDS; do
            log "Stopping deployment: $deployment_id"
            aws deploy stop-deployment \
                --deployment-id "$deployment_id" \
                --auto-rollback-enabled 2>/dev/null || warning "Failed to stop deployment $deployment_id"
        done
        
        log "Waiting for deployments to stop..."
        sleep 30
    else
        log "No active deployments found"
    fi
    
    success "Deployment cleanup completed"
}

# Remove CodeDeploy resources
remove_codedeploy_resources() {
    log "Removing CodeDeploy resources..."
    
    # Delete deployment group
    if aws deploy get-deployment-group \
        --application-name "$APP_NAME" \
        --deployment-group-name "$DEPLOYMENT_GROUP_NAME" &>/dev/null; then
        
        aws deploy delete-deployment-group \
            --application-name "$APP_NAME" \
            --deployment-group-name "$DEPLOYMENT_GROUP_NAME" 2>/dev/null || \
            warning "Failed to delete deployment group"
        log "Deployment group deleted"
    else
        log "Deployment group not found or already deleted"
    fi
    
    # Delete CodeDeploy application
    if aws deploy get-application --application-name "$APP_NAME" &>/dev/null; then
        aws deploy delete-application \
            --application-name "$APP_NAME" 2>/dev/null || \
            warning "Failed to delete CodeDeploy application"
        log "CodeDeploy application deleted"
    else
        log "CodeDeploy application not found or already deleted"
    fi
    
    success "CodeDeploy resources removed"
}

# Remove CodeBuild and CodeCommit resources
remove_codebuild_codecommit() {
    log "Removing CodeBuild and CodeCommit resources..."
    
    # Delete CodeBuild project
    if aws codebuild batch-get-projects --names "$BUILD_PROJECT_NAME" &>/dev/null; then
        aws codebuild delete-project --name "$BUILD_PROJECT_NAME" 2>/dev/null || \
            warning "Failed to delete CodeBuild project"
        log "CodeBuild project deleted"
    else
        log "CodeBuild project not found or already deleted"
    fi
    
    # Delete CodeCommit repository
    if aws codecommit get-repository --repository-name "$REPO_NAME" &>/dev/null; then
        aws codecommit delete-repository --repository-name "$REPO_NAME" 2>/dev/null || \
            warning "Failed to delete CodeCommit repository"
        log "CodeCommit repository deleted"
    else
        log "CodeCommit repository not found or already deleted"
    fi
    
    # Delete S3 artifacts bucket
    if aws s3api head-bucket --bucket "$ARTIFACTS_BUCKET_NAME" &>/dev/null; then
        log "Emptying S3 bucket..."
        aws s3 rm s3://"$ARTIFACTS_BUCKET_NAME" --recursive 2>/dev/null || \
            warning "Failed to empty S3 bucket"
        
        aws s3 rb s3://"$ARTIFACTS_BUCKET_NAME" 2>/dev/null || \
            warning "Failed to delete S3 bucket"
        log "S3 artifacts bucket deleted"
    else
        log "S3 bucket not found or already deleted"
    fi
    
    success "CodeBuild and CodeCommit resources removed"
}

# Remove Auto Scaling Group and Launch Template
remove_autoscaling_resources() {
    log "Removing Auto Scaling Group and Launch Template..."
    
    # Delete Auto Scaling Group
    if aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${APP_NAME}-asg" &>/dev/null; then
        
        log "Deleting Auto Scaling Group (this may take a few minutes)..."
        aws autoscaling delete-auto-scaling-group \
            --auto-scaling-group-name "${APP_NAME}-asg" \
            --force-delete 2>/dev/null || warning "Failed to delete Auto Scaling Group"
        
        # Wait for ASG deletion
        log "Waiting for Auto Scaling Group to be deleted..."
        timeout=300  # 5 minutes timeout
        while [ $timeout -gt 0 ] && aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "${APP_NAME}-asg" &>/dev/null; do
            sleep 10
            timeout=$((timeout - 10))
            echo -n "."
        done
        echo ""
        
        if [ $timeout -le 0 ]; then
            warning "Timeout waiting for Auto Scaling Group deletion"
        else
            log "Auto Scaling Group deleted"
        fi
    else
        log "Auto Scaling Group not found or already deleted"
    fi
    
    # Delete Launch Template
    if aws ec2 describe-launch-templates \
        --launch-template-names "${APP_NAME}-launch-template" &>/dev/null; then
        
        aws ec2 delete-launch-template \
            --launch-template-name "${APP_NAME}-launch-template" 2>/dev/null || \
            warning "Failed to delete launch template"
        log "Launch template deleted"
    else
        log "Launch template not found or already deleted"
    fi
    
    success "Auto Scaling resources removed"
}

# Remove Load Balancer resources
remove_load_balancer() {
    log "Removing Load Balancer resources..."
    
    # Delete Application Load Balancer
    if [ -n "${ALB_ARN:-}" ]; then
        if aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" &>/dev/null; then
            aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" 2>/dev/null || \
                warning "Failed to delete Application Load Balancer"
            log "Application Load Balancer deletion initiated"
            
            # Wait for ALB deletion
            log "Waiting for Load Balancer to be deleted..."
            timeout=300  # 5 minutes timeout
            while [ $timeout -gt 0 ] && aws elbv2 describe-load-balancers \
                --load-balancer-arns "$ALB_ARN" &>/dev/null; do
                sleep 10
                timeout=$((timeout - 10))
                echo -n "."
            done
            echo ""
        else
            log "Application Load Balancer not found or already deleted"
        fi
    fi
    
    # Delete Target Groups
    for tg_arn in "${TG_BLUE_ARN:-}" "${TG_GREEN_ARN:-}"; do
        if [ -n "$tg_arn" ]; then
            if aws elbv2 describe-target-groups --target-group-arns "$tg_arn" &>/dev/null; then
                aws elbv2 delete-target-group --target-group-arn "$tg_arn" 2>/dev/null || \
                    warning "Failed to delete target group $tg_arn"
                log "Target group $(basename $tg_arn) deleted"
            fi
        fi
    done
    
    success "Load Balancer resources removed"
}

# Remove Security Groups
remove_security_groups() {
    log "Removing Security Groups..."
    
    # Wait a bit for resources to be fully detached
    log "Waiting for resources to detach from security groups..."
    sleep 30
    
    # Delete EC2 security group
    if [ -n "${EC2_SG_ID:-}" ]; then
        if aws ec2 describe-security-groups --group-ids "$EC2_SG_ID" &>/dev/null; then
            aws ec2 delete-security-group --group-id "$EC2_SG_ID" 2>/dev/null || \
                warning "Failed to delete EC2 security group $EC2_SG_ID"
            log "EC2 security group deleted"
        else
            log "EC2 security group not found or already deleted"
        fi
    fi
    
    # Delete ALB security group
    if [ -n "${ALB_SG_ID:-}" ]; then
        if aws ec2 describe-security-groups --group-ids "$ALB_SG_ID" &>/dev/null; then
            aws ec2 delete-security-group --group-id "$ALB_SG_ID" 2>/dev/null || \
                warning "Failed to delete ALB security group $ALB_SG_ID"
            log "ALB security group deleted"
        else
            log "ALB security group not found or already deleted"
        fi
    fi
    
    success "Security groups removed"
}

# Remove EC2 Key Pair
remove_key_pair() {
    log "Removing EC2 Key Pair..."
    
    # Delete EC2 key pair
    if [ -n "${KEY_PAIR_NAME:-}" ]; then
        if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" &>/dev/null; then
            aws ec2 delete-key-pair --key-name "$KEY_PAIR_NAME" 2>/dev/null || \
                warning "Failed to delete key pair"
            log "EC2 key pair deleted"
        else
            log "Key pair not found or already deleted"
        fi
        
        # Remove local key file
        if [ -f "${KEY_PAIR_NAME}.pem" ]; then
            rm -f "${KEY_PAIR_NAME}.pem"
            log "Local key file removed"
        fi
    fi
    
    success "Key pair removed"
}

# Remove IAM Roles and Policies
remove_iam_roles() {
    log "Removing IAM roles and policies..."
    
    # Remove CodeDeploy service role
    if aws iam get-role --role-name CodeDeployServiceRole &>/dev/null; then
        aws iam detach-role-policy \
            --role-name CodeDeployServiceRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole 2>/dev/null || \
            warning "Failed to detach policy from CodeDeployServiceRole"
        
        aws iam delete-role --role-name CodeDeployServiceRole 2>/dev/null || \
            warning "Failed to delete CodeDeployServiceRole"
        log "CodeDeployServiceRole deleted"
    else
        log "CodeDeployServiceRole not found or already deleted"
    fi
    
    # Remove EC2 role from instance profile and delete
    if aws iam get-instance-profile --instance-profile-name CodeDeployEC2InstanceProfile &>/dev/null; then
        aws iam remove-role-from-instance-profile \
            --instance-profile-name CodeDeployEC2InstanceProfile \
            --role-name CodeDeployEC2Role 2>/dev/null || \
            warning "Failed to remove role from instance profile"
        
        aws iam delete-instance-profile \
            --instance-profile-name CodeDeployEC2InstanceProfile 2>/dev/null || \
            warning "Failed to delete instance profile"
        log "Instance profile deleted"
    fi
    
    # Delete EC2 role
    if aws iam get-role --role-name CodeDeployEC2Role &>/dev/null; then
        aws iam detach-role-policy \
            --role-name CodeDeployEC2Role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy 2>/dev/null || \
            warning "Failed to detach EC2 policy"
        
        aws iam detach-role-policy \
            --role-name CodeDeployEC2Role \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null || \
            warning "Failed to detach CloudWatch policy"
        
        aws iam delete-role --role-name CodeDeployEC2Role 2>/dev/null || \
            warning "Failed to delete CodeDeployEC2Role"
        log "CodeDeployEC2Role deleted"
    fi
    
    # Delete CodeBuild role
    if aws iam get-role --role-name CodeBuildServiceRole &>/dev/null; then
        aws iam delete-role-policy \
            --role-name CodeBuildServiceRole \
            --policy-name CodeBuildServicePolicy 2>/dev/null || \
            warning "Failed to delete CodeBuild policy"
        
        aws iam delete-role --role-name CodeBuildServiceRole 2>/dev/null || \
            warning "Failed to delete CodeBuildServiceRole"
        log "CodeBuildServiceRole deleted"
    fi
    
    success "IAM roles and policies removed"
}

# Remove CloudWatch Alarms
remove_cloudwatch_alarms() {
    log "Removing CloudWatch alarms..."
    
    # Delete CloudWatch alarms if they exist
    ALARM_NAMES=("${APP_NAME}-deployment-failure" "${APP_NAME}-target-health")
    
    for alarm_name in "${ALARM_NAMES[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "$alarm_name"; then
            aws cloudwatch delete-alarms --alarm-names "$alarm_name" 2>/dev/null || \
                warning "Failed to delete alarm $alarm_name"
            log "CloudWatch alarm $alarm_name deleted"
        fi
    done
    
    success "CloudWatch alarms removed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove cloned repository
    if [ -n "${REPO_NAME:-}" ] && [ -d "$REPO_NAME" ]; then
        rm -rf "$REPO_NAME"
        log "Local repository directory removed"
    fi
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f ".env"
        log "Environment file removed"
    fi
    
    # Remove any temporary files
    rm -f codebuild-policy.json 2>/dev/null || true
    
    success "Local files cleaned up"
}

# Main destroy function
main() {
    log "Starting destruction of Continuous Deployment with CodeDeploy resources..."
    
    confirm_destroy
    load_environment
    check_prerequisites
    
    # Remove resources in reverse order of creation
    stop_deployments
    remove_codedeploy_resources
    remove_codebuild_codecommit
    remove_autoscaling_resources
    remove_load_balancer
    remove_security_groups
    remove_key_pair
    remove_cloudwatch_alarms
    remove_iam_roles
    cleanup_local_files
    
    success "All resources have been successfully removed!"
    log "Cleanup completed. AWS resources should no longer incur charges."
    
    echo ""
    echo "=== Cleanup Summary ==="
    echo "✅ CodeDeploy application and deployment groups"
    echo "✅ CodeBuild project and artifacts"
    echo "✅ CodeCommit repository"
    echo "✅ Auto Scaling Group and Launch Template"
    echo "✅ Application Load Balancer and Target Groups"
    echo "✅ Security Groups"
    echo "✅ EC2 Key Pair"
    echo "✅ IAM Roles and Policies"
    echo "✅ CloudWatch Alarms"
    echo "✅ Local files and directories"
    echo ""
    warning "Please verify in the AWS Console that all resources have been removed."
    warning "Some resources might take additional time to be fully deleted."
}

# Run main function
main "$@"