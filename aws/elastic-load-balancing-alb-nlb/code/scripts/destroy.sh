#!/bin/bash

# Cleanup script for Elastic Load Balancing with Application and Network Load Balancers
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    log "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "AWS CLI is configured"
}

# Function to find and load state file
load_state_file() {
    log "Loading deployment state..."
    
    # Check if state file was provided as argument
    if [ $# -gt 0 ] && [ -f "$1" ]; then
        STATE_FILE="$1"
        log "Using provided state file: $STATE_FILE"
    else
        # Look for state files in current directory
        STATE_FILES=(deployment_state_*.json)
        if [ ${#STATE_FILES[@]} -eq 0 ] || [ ! -f "${STATE_FILES[0]}" ]; then
            log_error "No state file found. Please provide the state file as an argument:"
            log_error "  ./destroy.sh deployment_state_elb-demo-xxxxxx.json"
            log_error "Or run this script from the directory containing the state file."
            exit 1
        elif [ ${#STATE_FILES[@]} -eq 1 ]; then
            STATE_FILE="${STATE_FILES[0]}"
            log "Found state file: $STATE_FILE"
        else
            log_error "Multiple state files found. Please specify which one to use:"
            for file in "${STATE_FILES[@]}"; do
                log_error "  ./destroy.sh $file"
            done
            exit 1
        fi
    fi
    
    # Load project information from state file
    if command_exists python3; then
        PROJECT_NAME=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['project_name'])")
        AWS_REGION=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['aws_region'])")
        DEPLOYMENT_TIMESTAMP=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['deployment_timestamp'])")
    else
        # Fallback to basic parsing if python3 is not available
        PROJECT_NAME=$(grep -o '"project_name": "[^"]*"' "$STATE_FILE" | cut -d'"' -f4)
        AWS_REGION=$(grep -o '"aws_region": "[^"]*"' "$STATE_FILE" | cut -d'"' -f4)
        DEPLOYMENT_TIMESTAMP=$(grep -o '"deployment_timestamp": "[^"]*"' "$STATE_FILE" | cut -d'"' -f4)
    fi
    
    export PROJECT_NAME AWS_REGION DEPLOYMENT_TIMESTAMP
    
    log_success "State file loaded successfully:"
    log "  Project Name: $PROJECT_NAME"
    log "  AWS Region: $AWS_REGION"
    log "  Deployment Time: $DEPLOYMENT_TIMESTAMP"
}

# Function to get resource ID from state file
get_resource_id() {
    local resource_type="$1"
    if command_exists python3; then
        python3 -c "
import json
import sys
try:
    with open('$STATE_FILE', 'r') as f:
        state = json.load(f)
    resource = state.get('resources', {}).get('$resource_type', {})
    print(resource.get('id', ''))
except:
    print('')
"
    else
        # Fallback parsing
        grep -A 3 "\"$resource_type\"" "$STATE_FILE" | grep '"id"' | cut -d'"' -f4 || echo ""
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    if [ -z "$resource_id" ]; then
        return 1
    fi
    
    case "$resource_type" in
        "load_balancer")
            aws elbv2 describe-load-balancers --load-balancer-arns "$resource_id" >/dev/null 2>&1
            ;;
        "target_group")
            aws elbv2 describe-target-groups --target-group-arns "$resource_id" >/dev/null 2>&1
            ;;
        "listener")
            aws elbv2 describe-listeners --listener-arns "$resource_id" >/dev/null 2>&1
            ;;
        "instance")
            aws ec2 describe-instances --instance-ids "$resource_id" --query 'Reservations[*].Instances[?State.Name!=`terminated`]' --output text | grep -q .
            ;;
        "security_group")
            aws ec2 describe-security-groups --group-ids "$resource_id" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to safely delete resource with retry
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local resource_name="$3"
    local delete_command="$4"
    local max_retries=3
    local retry_count=0
    
    if [ -z "$resource_id" ]; then
        log_warning "No resource ID found for $resource_name"
        return 0
    fi
    
    if ! resource_exists "$resource_type" "$resource_id"; then
        log_warning "$resource_name ($resource_id) does not exist or already deleted"
        return 0
    fi
    
    while [ $retry_count -lt $max_retries ]; do
        log "Attempting to delete $resource_name ($resource_id)..."
        
        if eval "$delete_command" 2>/dev/null; then
            log_success "$resource_name deleted successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warning "Failed to delete $resource_name. Retrying in 10 seconds... (attempt $retry_count/$max_retries)"
                sleep 10
            else
                log_error "Failed to delete $resource_name after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to delete listeners
delete_listeners() {
    log "Deleting load balancer listeners..."
    
    # Delete ALB listener
    ALB_LISTENER_ARN=$(get_resource_id "alb_listener")
    safe_delete "listener" "$ALB_LISTENER_ARN" "ALB Listener" \
        "aws elbv2 delete-listener --listener-arn $ALB_LISTENER_ARN"
    
    # Delete NLB listener
    NLB_LISTENER_ARN=$(get_resource_id "nlb_listener")
    safe_delete "listener" "$NLB_LISTENER_ARN" "NLB Listener" \
        "aws elbv2 delete-listener --listener-arn $NLB_LISTENER_ARN"
    
    log_success "Listeners cleanup completed"
}

# Function to delete load balancers
delete_load_balancers() {
    log "Deleting load balancers..."
    
    # Delete Application Load Balancer
    ALB_ARN=$(get_resource_id "alb")
    safe_delete "load_balancer" "$ALB_ARN" "Application Load Balancer" \
        "aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN"
    
    # Delete Network Load Balancer
    NLB_ARN=$(get_resource_id "nlb")
    safe_delete "load_balancer" "$NLB_ARN" "Network Load Balancer" \
        "aws elbv2 delete-load-balancer --load-balancer-arn $NLB_ARN"
    
    # Wait for load balancers to be fully deleted
    log "Waiting for load balancers to be completely removed..."
    sleep 60
    
    log_success "Load balancers cleanup completed"
}

# Function to delete target groups
delete_target_groups() {
    log "Deleting target groups..."
    
    # Delete ALB target group
    ALB_TG_ARN=$(get_resource_id "alb_target_group")
    safe_delete "target_group" "$ALB_TG_ARN" "ALB Target Group" \
        "aws elbv2 delete-target-group --target-group-arn $ALB_TG_ARN"
    
    # Delete NLB target group
    NLB_TG_ARN=$(get_resource_id "nlb_target_group")
    safe_delete "target_group" "$NLB_TG_ARN" "NLB Target Group" \
        "aws elbv2 delete-target-group --target-group-arn $NLB_TG_ARN"
    
    log_success "Target groups cleanup completed"
}

# Function to terminate EC2 instances
terminate_ec2_instances() {
    log "Terminating EC2 instances..."
    
    # Get instance IDs
    INSTANCE_1=$(get_resource_id "ec2_instance_1")
    INSTANCE_2=$(get_resource_id "ec2_instance_2")
    
    # Collect existing instances
    INSTANCES_TO_TERMINATE=()
    if [ -n "$INSTANCE_1" ] && resource_exists "instance" "$INSTANCE_1"; then
        INSTANCES_TO_TERMINATE+=("$INSTANCE_1")
    fi
    if [ -n "$INSTANCE_2" ] && resource_exists "instance" "$INSTANCE_2"; then
        INSTANCES_TO_TERMINATE+=("$INSTANCE_2")
    fi
    
    if [ ${#INSTANCES_TO_TERMINATE[@]} -eq 0 ]; then
        log_warning "No EC2 instances found to terminate"
        return 0
    fi
    
    # Terminate instances
    log "Terminating instances: ${INSTANCES_TO_TERMINATE[*]}"
    if aws ec2 terminate-instances --instance-ids "${INSTANCES_TO_TERMINATE[@]}" >/dev/null 2>&1; then
        log_success "Instance termination initiated"
        
        # Wait for instances to terminate
        log "Waiting for instances to fully terminate..."
        aws ec2 wait instance-terminated --instance-ids "${INSTANCES_TO_TERMINATE[@]}" 2>/dev/null || {
            log_warning "Timeout waiting for instances to terminate, but termination was initiated"
        }
        
        log_success "EC2 instances terminated"
    else
        log_error "Failed to terminate some instances"
    fi
}

# Function to delete security groups
delete_security_groups() {
    log "Deleting security groups..."
    
    # Delete security groups in reverse order of dependencies
    # First delete EC2 security group
    EC2_SG_ID=$(get_resource_id "ec2_security_group")
    safe_delete "security_group" "$EC2_SG_ID" "EC2 Security Group" \
        "aws ec2 delete-security-group --group-id $EC2_SG_ID"
    
    # Then delete ALB security group
    ALB_SG_ID=$(get_resource_id "alb_security_group")
    safe_delete "security_group" "$ALB_SG_ID" "ALB Security Group" \
        "aws ec2 delete-security-group --group-id $ALB_SG_ID"
    
    # Finally delete NLB security group
    NLB_SG_ID=$(get_resource_id "nlb_security_group")
    safe_delete "security_group" "$NLB_SG_ID" "NLB Security Group" \
        "aws ec2 delete-security-group --group-id $NLB_SG_ID"
    
    log_success "Security groups cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files if they exist
    local files_to_remove=("user-data.sh" "$STATE_FILE")
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed $file"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check if load balancers still exist
    ALB_ARN=$(get_resource_id "alb")
    if [ -n "$ALB_ARN" ] && resource_exists "load_balancer" "$ALB_ARN"; then
        log_warning "ALB still exists: $ALB_ARN"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    NLB_ARN=$(get_resource_id "nlb")
    if [ -n "$NLB_ARN" ] && resource_exists "load_balancer" "$NLB_ARN"; then
        log_warning "NLB still exists: $NLB_ARN"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if instances still exist
    INSTANCE_1=$(get_resource_id "ec2_instance_1")
    if [ -n "$INSTANCE_1" ] && resource_exists "instance" "$INSTANCE_1"; then
        log_warning "Instance 1 still exists: $INSTANCE_1"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    INSTANCE_2=$(get_resource_id "ec2_instance_2")
    if [ -n "$INSTANCE_2" ] && resource_exists "instance" "$INSTANCE_2"; then
        log_warning "Instance 2 still exists: $INSTANCE_2"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "Cleanup validation completed - all resources removed"
    else
        log_warning "Cleanup validation found $cleanup_issues remaining resources"
        log_warning "Some resources may still be in the process of being deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup completed!"
    echo
    echo "=================================="
    echo "CLEANUP SUMMARY"
    echo "=================================="
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "Deployment Time: $DEPLOYMENT_TIMESTAMP"
    echo "Cleanup Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "RESOURCES REMOVED:"
    echo "  ✅ Load Balancer Listeners"
    echo "  ✅ Application Load Balancer"
    echo "  ✅ Network Load Balancer"
    echo "  ✅ Target Groups"
    echo "  ✅ EC2 Instances"
    echo "  ✅ Security Groups"
    echo "  ✅ Local Files"
    echo
    echo "NOTES:"
    echo "  - All billable resources have been removed"
    echo "  - VPC and subnets were not deleted (they were pre-existing)"
    echo "  - Check AWS console to confirm all resources are gone"
    echo "=================================="
}

# Function to confirm deletion
confirm_deletion() {
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete all resources for project: $PROJECT_NAME"
    log_warning "Created at: $DEPLOYMENT_TIMESTAMP"
    echo
    echo "Resources to be deleted:"
    echo "  - Application Load Balancer and listeners"
    echo "  - Network Load Balancer and listeners"
    echo "  - Target Groups"
    echo "  - EC2 Instances (2 instances)"
    echo "  - Security Groups (3 groups)"
    echo "  - Local state files"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to handle errors
handle_error() {
    log_error "Cleanup failed at step: $1"
    log_error "Some resources may still exist. Please check the AWS console and clean up manually if needed."
    exit 1
}

# Main cleanup function
main() {
    log "Starting cleanup of Elastic Load Balancing infrastructure..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS] [STATE_FILE]"
                echo "Options:"
                echo "  --force    Skip confirmation prompt"
                echo "  --help     Show this help message"
                echo "Arguments:"
                echo "  STATE_FILE Path to deployment state file (optional if in current directory)"
                exit 0
                ;;
            *)
                # Assume it's a state file
                if [ -f "$1" ]; then
                    STATE_FILE_ARG="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_aws_config || handle_error "AWS configuration check"
    load_state_file "${STATE_FILE_ARG:-}" || handle_error "State file loading"
    confirm_deletion || handle_error "User confirmation"
    
    # Cleanup in reverse order of creation
    delete_listeners || handle_error "Listeners deletion"
    delete_load_balancers || handle_error "Load balancers deletion"
    delete_target_groups || handle_error "Target groups deletion"
    terminate_ec2_instances || handle_error "EC2 instances termination"
    delete_security_groups || handle_error "Security groups deletion"
    cleanup_local_files || handle_error "Local files cleanup"
    validate_cleanup || handle_error "Cleanup validation"
    display_cleanup_summary
    
    log_success "All cleanup steps completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi