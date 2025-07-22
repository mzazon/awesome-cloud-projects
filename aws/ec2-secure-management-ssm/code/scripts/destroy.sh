#!/bin/bash

# Destroy script for Secure EC2 Management with Systems Manager
# This script safely removes all resources created by the deploy.sh script

set -e

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Some resources may still exist. Please check AWS Console manually."
    exit 1
}

# Set up error handling (but continue on errors during cleanup)
trap 'handle_error $LINENO' ERR

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env_vars" ]; then
        source .env_vars
        log_success "Environment variables loaded from .env_vars"
    else
        log_warning "No .env_vars file found. Attempting interactive cleanup..."
        
        # Try to get region from AWS CLI
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
        if [ -z "$AWS_REGION" ]; then
            read -p "Enter AWS region: " AWS_REGION
            export AWS_REGION
        fi
        
        log "Using region: ${AWS_REGION}"
        return 1
    fi
    
    return 0
}

# Function to confirm destruction
confirm_destruction() {
    echo
    log_warning "This will permanently delete the following resources:"
    echo "- EC2 Instance: ${EC2_INSTANCE_NAME:-'(unknown)'}"
    echo "- IAM Role: ${IAM_ROLE_NAME:-'(unknown)'}"
    echo "- IAM Instance Profile: ${IAM_PROFILE_NAME:-'(unknown)'}"
    echo "- Security Group: ${SG_NAME:-'(unknown)'}"
    echo "- CloudWatch Log Group: ${LOG_GROUP_NAME:-'(unknown)'}"
    echo
    
    if [ "${FORCE_DESTROY:-false}" != "true" ]; then
        read -p "Are you sure you want to proceed? (yes/no): " confirmation
        if [ "$confirmation" != "yes" ] && [ "$confirmation" != "y" ]; then
            log "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    log "Proceeding with resource destruction..."
}

# Function to find and terminate EC2 instances
cleanup_ec2_instances() {
    log "Cleaning up EC2 instances..."
    
    # If we have the instance ID, use it directly
    if [ -n "$INSTANCE_ID" ]; then
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids ${INSTANCE_ID} \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$instance_state" != "not-found" ] && [ "$instance_state" != "terminated" ]; then
            log "Terminating instance: ${INSTANCE_ID}"
            aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} || true
            
            log "Waiting for instance to terminate..."
            aws ec2 wait instance-terminated --instance-ids ${INSTANCE_ID} || true
            log_success "Instance ${INSTANCE_ID} terminated"
        else
            log "Instance ${INSTANCE_ID} already terminated or not found"
        fi
    else
        # Try to find instances by name tag
        if [ -n "$EC2_INSTANCE_NAME" ]; then
            log "Searching for instances with name: ${EC2_INSTANCE_NAME}"
            local instance_ids=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=${EC2_INSTANCE_NAME}" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
                --query "Reservations[].Instances[].InstanceId" \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$instance_ids" ] && [ "$instance_ids" != "None" ]; then
                for id in $instance_ids; do
                    log "Terminating instance: ${id}"
                    aws ec2 terminate-instances --instance-ids ${id} || true
                done
                
                log "Waiting for instances to terminate..."
                for id in $instance_ids; do
                    aws ec2 wait instance-terminated --instance-ids ${id} || true
                done
                log_success "All matching instances terminated"
            else
                log "No running instances found with name: ${EC2_INSTANCE_NAME}"
            fi
        fi
    fi
}

# Function to cleanup security group
cleanup_security_group() {
    log "Cleaning up security group..."
    
    # If we have the security group ID, use it directly
    if [ -n "$SG_ID" ]; then
        local sg_exists=$(aws ec2 describe-security-groups \
            --group-ids ${SG_ID} \
            --query "SecurityGroups[0].GroupId" \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$sg_exists" != "not-found" ]; then
            log "Deleting security group: ${SG_ID}"
            aws ec2 delete-security-group --group-id ${SG_ID} || true
            log_success "Security group ${SG_ID} deleted"
        else
            log "Security group ${SG_ID} not found"
        fi
    else
        # Try to find security group by name
        if [ -n "$SG_NAME" ]; then
            log "Searching for security group with name: ${SG_NAME}"
            local sg_id=$(aws ec2 describe-security-groups \
                --filters "Name=group-name,Values=${SG_NAME}" \
                --query "SecurityGroups[0].GroupId" \
                --output text 2>/dev/null || echo "None")
            
            if [ "$sg_id" != "None" ] && [ -n "$sg_id" ]; then
                log "Deleting security group: ${sg_id}"
                aws ec2 delete-security-group --group-id ${sg_id} || true
                log_success "Security group ${sg_id} deleted"
            else
                log "No security group found with name: ${SG_NAME}"
            fi
        fi
    fi
}

# Function to cleanup IAM resources
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Cleanup IAM instance profile and role
    if [ -n "$IAM_PROFILE_NAME" ] && [ -n "$IAM_ROLE_NAME" ]; then
        # Check if instance profile exists
        local profile_exists=$(aws iam get-instance-profile \
            --instance-profile-name ${IAM_PROFILE_NAME} \
            --query "InstanceProfile.InstanceProfileName" \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$profile_exists" != "not-found" ]; then
            log "Removing role from instance profile..."
            aws iam remove-role-from-instance-profile \
                --instance-profile-name ${IAM_PROFILE_NAME} \
                --role-name ${IAM_ROLE_NAME} 2>/dev/null || true
            
            log "Deleting instance profile..."
            aws iam delete-instance-profile \
                --instance-profile-name ${IAM_PROFILE_NAME} || true
            log_success "Instance profile ${IAM_PROFILE_NAME} deleted"
        else
            log "Instance profile ${IAM_PROFILE_NAME} not found"
        fi
        
        # Check if role exists
        local role_exists=$(aws iam get-role \
            --role-name ${IAM_ROLE_NAME} \
            --query "Role.RoleName" \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$role_exists" != "not-found" ]; then
            log "Detaching policies from role..."
            aws iam detach-role-policy \
                --role-name ${IAM_ROLE_NAME} \
                --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
            
            log "Deleting IAM role..."
            aws iam delete-role --role-name ${IAM_ROLE_NAME} || true
            log_success "IAM role ${IAM_ROLE_NAME} deleted"
        else
            log "IAM role ${IAM_ROLE_NAME} not found"
        fi
    else
        log "No IAM resource names found in environment variables"
    fi
}

# Function to cleanup CloudWatch Log Group
cleanup_cloudwatch_logs() {
    log "Cleaning up CloudWatch Log Group..."
    
    if [ -n "$LOG_GROUP_NAME" ]; then
        local log_group_exists=$(aws logs describe-log-groups \
            --log-group-name-prefix "${LOG_GROUP_NAME}" \
            --query "logGroups[0].logGroupName" \
            --output text 2>/dev/null || echo "None")
        
        if [ "$log_group_exists" != "None" ] && [ -n "$log_group_exists" ]; then
            log "Deleting CloudWatch Log Group: ${LOG_GROUP_NAME}"
            aws logs delete-log-group --log-group-name "${LOG_GROUP_NAME}" || true
            log_success "CloudWatch Log Group deleted"
        else
            log "CloudWatch Log Group ${LOG_GROUP_NAME} not found"
        fi
    else
        log "No CloudWatch Log Group name found in environment variables"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment variables file
    if [ -f ".env_vars" ]; then
        rm -f .env_vars
        log_success "Removed .env_vars file"
    fi
    
    # Remove any temporary files that might have been created
    rm -f .deploy_state .instance_id .sg_id 2>/dev/null || true
}

# Function to find resources interactively if env vars are missing
interactive_cleanup() {
    log "Performing interactive cleanup..."
    
    # Find instances by project tag
    log "Searching for EC2 instances with Project=SSM-SecureServer..."
    local instance_ids=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=SSM-SecureServer" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
        --query "Reservations[].Instances[].[InstanceId,Tags[?Key=='Name'].Value|[0]]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$instance_ids" ] && [ "$instance_ids" != "None" ]; then
        echo "Found instances:"
        echo "$instance_ids"
        read -p "Terminate these instances? (yes/no): " confirm_instances
        if [ "$confirm_instances" = "yes" ] || [ "$confirm_instances" = "y" ]; then
            echo "$instance_ids" | while read -r instance_id instance_name; do
                if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                    log "Terminating instance: ${instance_id} (${instance_name})"
                    aws ec2 terminate-instances --instance-ids ${instance_id} || true
                fi
            done
        fi
    fi
    
    # Find security groups by project tag
    log "Searching for security groups with Project=SSM-SecureServer..."
    local security_groups=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Project,Values=SSM-SecureServer" \
        --query "SecurityGroups[].[GroupId,GroupName]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$security_groups" ] && [ "$security_groups" != "None" ]; then
        echo "Found security groups:"
        echo "$security_groups"
        read -p "Delete these security groups? (yes/no): " confirm_sgs
        if [ "$confirm_sgs" = "yes" ] || [ "$confirm_sgs" = "y" ]; then
            echo "$security_groups" | while read -r sg_id sg_name; do
                if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
                    log "Deleting security group: ${sg_id} (${sg_name})"
                    aws ec2 delete-security-group --group-id ${sg_id} || true
                fi
            done
        fi
    fi
    
    # Find IAM roles by name pattern
    log "Searching for IAM roles with SSMInstanceRole prefix..."
    local iam_roles=$(aws iam list-roles \
        --query "Roles[?starts_with(RoleName, 'SSMInstanceRole-')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$iam_roles" ] && [ "$iam_roles" != "None" ]; then
        echo "Found IAM roles:"
        echo "$iam_roles"
        read -p "Delete these IAM roles and their instance profiles? (yes/no): " confirm_iam
        if [ "$confirm_iam" = "yes" ] || [ "$confirm_iam" = "y" ]; then
            for role_name in $iam_roles; do
                # Find corresponding instance profile
                local profile_name=$(echo $role_name | sed 's/SSMInstanceRole-/SSMInstanceProfile-/')
                
                log "Cleaning up IAM role: ${role_name} and profile: ${profile_name}"
                
                # Remove role from instance profile
                aws iam remove-role-from-instance-profile \
                    --instance-profile-name ${profile_name} \
                    --role-name ${role_name} 2>/dev/null || true
                
                # Delete instance profile
                aws iam delete-instance-profile \
                    --instance-profile-name ${profile_name} 2>/dev/null || true
                
                # Detach policies and delete role
                aws iam detach-role-policy \
                    --role-name ${role_name} \
                    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
                
                aws iam delete-role --role-name ${role_name} || true
            done
        fi
    fi
    
    # Find CloudWatch Log Groups
    log "Searching for CloudWatch Log Groups with /aws/ssm/sessions/ prefix..."
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/ssm/sessions/" \
        --query "logGroups[].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$log_groups" ] && [ "$log_groups" != "None" ]; then
        echo "Found log groups:"
        echo "$log_groups"
        read -p "Delete these log groups? (yes/no): " confirm_logs
        if [ "$confirm_logs" = "yes" ] || [ "$confirm_logs" = "y" ]; then
            for log_group in $log_groups; do
                log "Deleting log group: ${log_group}"
                aws logs delete-log-group --log-group-name "${log_group}" || true
            done
        fi
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check for remaining instances
    if [ -n "$INSTANCE_ID" ]; then
        local instance_state=$(aws ec2 describe-instances \
            --instance-ids ${INSTANCE_ID} \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text 2>/dev/null || echo "terminated")
        
        if [ "$instance_state" != "terminated" ]; then
            log_warning "Instance ${INSTANCE_ID} is still in state: ${instance_state}"
            issues_found=true
        fi
    fi
    
    # Check for remaining security groups
    if [ -n "$SG_ID" ]; then
        local sg_exists=$(aws ec2 describe-security-groups \
            --group-ids ${SG_ID} \
            --query "SecurityGroups[0].GroupId" \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$sg_exists" != "not-found" ]; then
            log_warning "Security group ${SG_ID} still exists"
            issues_found=true
        fi
    fi
    
    # Check for remaining IAM resources
    if [ -n "$IAM_ROLE_NAME" ]; then
        local role_exists=$(aws iam get-role \
            --role-name ${IAM_ROLE_NAME} \
            --query "Role.RoleName" \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$role_exists" != "not-found" ]; then
            log_warning "IAM role ${IAM_ROLE_NAME} still exists"
            issues_found=true
        fi
    fi
    
    if [ "$issues_found" = "false" ]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check AWS Console manually."
    fi
}

# Function to display final summary
display_summary() {
    echo
    log "Cleanup Summary:"
    echo "- EC2 Instances: Terminated"
    echo "- Security Groups: Deleted"
    echo "- IAM Roles and Profiles: Deleted"
    echo "- CloudWatch Log Groups: Deleted"
    echo "- Local files: Cleaned up"
    echo
    log_success "Destruction completed successfully!"
    echo
    log "Remember to check your AWS bill to ensure no unexpected charges"
    log "If you need to deploy again, run: ./deploy.sh"
}

# Main destruction function
main() {
    log "Starting destruction of AWS Systems Manager secure EC2 infrastructure"
    echo
    
    # Check if script is being run from correct directory
    if [ ! -f "destroy.sh" ]; then
        log_error "Please run this script from the scripts directory"
        exit 1
    fi
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Load environment variables
    if load_environment; then
        # Normal cleanup with environment variables
        confirm_destruction
        
        # Disable error handling for cleanup operations
        set +e
        
        cleanup_ec2_instances
        sleep 5  # Wait a bit for instances to start terminating
        cleanup_security_group
        cleanup_iam_resources
        cleanup_cloudwatch_logs
        cleanup_local_files
        
        # Re-enable error handling
        set -e
        
        verify_cleanup
    else
        # Interactive cleanup without environment variables
        log_warning "Environment file not found. Switching to interactive mode."
        echo
        log_warning "This will search for resources by tags and name patterns."
        read -p "Continue with interactive cleanup? (yes/no): " continue_interactive
        
        if [ "$continue_interactive" = "yes" ] || [ "$continue_interactive" = "y" ]; then
            set +e
            interactive_cleanup
            cleanup_local_files
            set -e
        else
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    display_summary
}

# Run main function
main "$@"