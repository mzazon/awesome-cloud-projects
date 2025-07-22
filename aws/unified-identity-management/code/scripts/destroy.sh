#!/bin/bash

# =============================================================================
# AWS Hybrid Identity Management with Directory Service - Cleanup Script
# =============================================================================
# This script removes all resources created by the deploy.sh script including:
# - Amazon WorkSpaces and directory registration
# - RDS SQL Server instance and subnet groups
# - AWS Managed Microsoft AD
# - EC2 admin instance
# - VPC, subnets, security groups, and networking components
# - IAM roles and policies
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION AND LOGGING
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="cleanup-$(date +%Y%m%d-%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    log "INFO" "${message}"
}

print_error() {
    local message=$1
    echo -e "${RED}❌ ERROR: ${message}${NC}" >&2
    log "ERROR" "${message}"
}

print_warning() {
    local message=$1
    echo -e "${YELLOW}⚠️  WARNING: ${message}${NC}"
    log "WARN" "${message}"
}

print_info() {
    local message=$1
    echo -e "${BLUE}ℹ️  ${message}${NC}"
    log "INFO" "${message}"
}

print_success() {
    local message=$1
    echo -e "${GREEN}✅ ${message}${NC}"
    log "SUCCESS" "${message}"
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Display current AWS configuration
    local aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Unknown")
    local aws_region=$(aws configure get region 2>/dev/null || echo "Not set")
    local aws_user=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "Unknown")
    
    print_info "AWS Account: ${aws_account}"
    print_info "AWS Region: ${aws_region}"
    print_info "AWS User/Role: ${aws_user}"
    
    print_success "Prerequisites check completed"
}

# =============================================================================
# ENVIRONMENT LOADING
# =============================================================================

load_environment() {
    print_info "Loading deployment environment..."
    
    # Check if deployment.env file exists
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        print_info "Found deployment.env file, loading variables..."
        source "${SCRIPT_DIR}/deployment.env"
        print_success "Environment variables loaded from deployment.env"
    else
        print_warning "deployment.env file not found. Attempting to discover resources..."
        
        # Try to discover resources by tags
        discover_resources
    fi
    
    # Validate required variables
    if [[ -z "${AWS_REGION:-}" ]] || [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        print_error "Required environment variables not set. Cannot proceed with cleanup."
        exit 1
    fi
    
    print_info "AWS Region: ${AWS_REGION}"
    print_info "AWS Account: ${AWS_ACCOUNT_ID}"
}

discover_resources() {
    print_info "Discovering resources by tags..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Discover Directory Service resources
    local directories=$(aws ds describe-directories \
        --query 'DirectoryDescriptions[?contains(Name, `corp-hybrid-ad`)].{Id:DirectoryId,Name:Name}' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${directories}" ]]; then
        export DIRECTORY_ID=$(echo "${directories}" | head -n1 | cut -f1)
        export DIRECTORY_DOMAIN=$(echo "${directories}" | head -n1 | cut -f2)
        export DIRECTORY_NAME=$(echo "${DIRECTORY_DOMAIN}" | cut -d'.' -f1)
        print_info "Found Directory: ${DIRECTORY_ID} (${DIRECTORY_DOMAIN})"
    fi
    
    # Discover VPC resources
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Purpose,Values=HybridIdentity" \
        --query 'Vpcs[0].{Id:VpcId,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${vpcs}" ]] && [[ "${vpcs}" != "None" ]]; then
        export VPC_ID=$(echo "${vpcs}" | cut -f1)
        export VPC_NAME=$(echo "${vpcs}" | cut -f2)
        print_info "Found VPC: ${VPC_ID} (${VPC_NAME})"
    fi
    
    # Discover RDS instances
    local rds_instances=$(aws rds describe-db-instances \
        --query 'DBInstances[?contains(DBInstanceIdentifier, `hybrid-sql`)].DBInstanceIdentifier' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${rds_instances}" ]]; then
        export RDS_INSTANCE_ID=$(echo "${rds_instances}" | head -n1)
        print_info "Found RDS Instance: ${RDS_INSTANCE_ID}"
    fi
    
    # Discover EC2 instances
    local ec2_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Purpose,Values=HybridIdentity" "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${ec2_instances}" ]] && [[ "${ec2_instances}" != "None" ]]; then
        export ADMIN_INSTANCE_ID=$(echo "${ec2_instances}" | head -n1 | cut -f1)
        export ADMIN_INSTANCE_NAME=$(echo "${ec2_instances}" | head -n1 | cut -f2)
        print_info "Found Admin Instance: ${ADMIN_INSTANCE_ID} (${ADMIN_INSTANCE_NAME})"
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_id=$2
    local max_attempts=${3:-30}
    local sleep_interval=${4:-30}
    
    print_info "Waiting for ${resource_type} ${resource_id} to be deleted..."
    
    local attempts=0
    while [ ${attempts} -lt ${max_attempts} ]; do
        local exists=false
        
        case ${resource_type} in
            "directory")
                if aws ds describe-directories --directory-ids ${resource_id} &>/dev/null; then
                    exists=true
                fi
                ;;
            "rds-instance")
                if aws rds describe-db-instances --db-instance-identifier ${resource_id} &>/dev/null; then
                    exists=true
                fi
                ;;
            "ec2-instance")
                local state=$(aws ec2 describe-instances --instance-ids ${resource_id} \
                    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "terminated")
                if [[ "${state}" != "terminated" ]]; then
                    exists=true
                fi
                ;;
            "vpc")
                if aws ec2 describe-vpcs --vpc-ids ${resource_id} &>/dev/null; then
                    exists=true
                fi
                ;;
        esac
        
        if [[ "${exists}" == "false" ]]; then
            print_success "${resource_type} ${resource_id} has been deleted"
            return 0
        fi
        
        print_info "Still deleting, waiting..."
        sleep ${sleep_interval}
        ((attempts++))
    done
    
    print_warning "Timeout waiting for ${resource_type} ${resource_id} deletion"
    return 1
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_identifier=$2
    
    case ${resource_type} in
        "vpc")
            aws ec2 describe-vpcs --vpc-ids ${resource_identifier} &>/dev/null
            ;;
        "directory")
            aws ds describe-directories --directory-ids ${resource_identifier} &>/dev/null
            ;;
        "rds-instance")
            aws rds describe-db-instances --db-instance-identifier ${resource_identifier} &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name ${resource_identifier} &>/dev/null
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids ${resource_identifier} &>/dev/null
            ;;
        "ec2-instance")
            aws ec2 describe-instances --instance-ids ${resource_identifier} &>/dev/null
            ;;
    esac
}

# Function to safely delete resource with error handling
safe_delete() {
    local resource_type=$1
    local resource_id=$2
    local description=${3:-"${resource_type}"}
    
    if resource_exists "${resource_type}" "${resource_id}"; then
        print_info "Deleting ${description}: ${resource_id}"
        return 0
    else
        print_info "${description} ${resource_id} does not exist or already deleted"
        return 1
    fi
}

# =============================================================================
# CONFIRMATION PROMPT
# =============================================================================

confirm_deletion() {
    print_warning "This will DELETE ALL RESOURCES created by the deployment script!"
    print_warning "This action is IRREVERSIBLE!"
    print_info ""
    print_info "Resources that will be deleted:"
    
    # List discovered resources
    if [[ -n "${DIRECTORY_ID:-}" ]]; then
        print_info "  - Directory Service: ${DIRECTORY_ID} (${DIRECTORY_DOMAIN:-Unknown})"
    fi
    
    if [[ -n "${VPC_ID:-}" ]]; then
        print_info "  - VPC and networking: ${VPC_ID} (${VPC_NAME:-Unknown})"
    fi
    
    if [[ -n "${RDS_INSTANCE_ID:-}" ]]; then
        print_info "  - RDS Instance: ${RDS_INSTANCE_ID}"
    fi
    
    if [[ -n "${ADMIN_INSTANCE_ID:-}" ]]; then
        print_info "  - EC2 Instance: ${ADMIN_INSTANCE_ID} (${ADMIN_INSTANCE_NAME:-Unknown})"
    fi
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        print_info "  - IAM Role: ${IAM_ROLE_NAME}"
    fi
    
    print_info ""
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        print_warning "Force flag provided, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete all these resources? (type 'DELETE' to confirm): " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        print_info "Deletion cancelled by user"
        exit 0
    fi
    
    print_warning "Starting resource deletion in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# =============================================================================
# WORKSPACES CLEANUP
# =============================================================================

cleanup_workspaces() {
    print_info "Cleaning up WorkSpaces resources..."
    
    if [[ -z "${DIRECTORY_ID:-}" ]]; then
        print_info "No directory ID found, skipping WorkSpaces cleanup"
        return 0
    fi
    
    # List and terminate all WorkSpaces for this directory
    local workspaces=$(aws workspaces describe-workspaces \
        --directory-id ${DIRECTORY_ID} \
        --query 'Workspaces[].{Id:WorkspaceId,State:State,User:UserName}' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${workspaces}" ]] && [[ "${workspaces}" != "None" ]]; then
        print_info "Found WorkSpaces to terminate:"
        echo "${workspaces}" | while read -r workspace_info; do
            local workspace_id=$(echo "${workspace_info}" | cut -f1)
            local workspace_state=$(echo "${workspace_info}" | cut -f2)
            local workspace_user=$(echo "${workspace_info}" | cut -f3)
            
            if [[ "${workspace_state}" != "TERMINATED" ]] && [[ "${workspace_state}" != "TERMINATING" ]]; then
                print_info "Terminating WorkSpace: ${workspace_id} (${workspace_user})"
                aws workspaces terminate-workspaces \
                    --terminate-workspace-requests "WorkspaceId=${workspace_id}" || \
                    print_warning "Failed to terminate WorkSpace ${workspace_id}"
            fi
        done
        
        # Wait for WorkSpaces to terminate
        print_info "Waiting for WorkSpaces termination to complete..."
        sleep 120
    fi
    
    # Deregister directory from WorkSpaces
    local registration_status=$(aws workspaces describe-workspace-directories \
        --directory-ids ${DIRECTORY_ID} \
        --query 'Directories[0].State' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${registration_status}" == "REGISTERED" ]]; then
        print_info "Deregistering directory from WorkSpaces..."
        aws workspaces deregister-workspace-directory \
            --directory-id ${DIRECTORY_ID} || \
            print_warning "Failed to deregister directory from WorkSpaces"
        
        # Wait for deregistration
        sleep 60
    fi
    
    print_success "WorkSpaces cleanup completed"
}

# =============================================================================
# RDS CLEANUP
# =============================================================================

cleanup_rds() {
    print_info "Cleaning up RDS resources..."
    
    if [[ -n "${RDS_INSTANCE_ID:-}" ]] && resource_exists "rds-instance" "${RDS_INSTANCE_ID}"; then
        print_info "Deleting RDS instance: ${RDS_INSTANCE_ID}"
        
        # Check if instance is in a state that allows deletion
        local rds_status=$(aws rds describe-db-instances \
            --db-instance-identifier ${RDS_INSTANCE_ID} \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "unknown")
        
        if [[ "${rds_status}" != "deleting" ]]; then
            aws rds delete-db-instance \
                --db-instance-identifier ${RDS_INSTANCE_ID} \
                --skip-final-snapshot \
                --delete-automated-backups || \
                print_warning "Failed to initiate RDS instance deletion"
            
            # Wait for RDS deletion
            wait_for_deletion "rds-instance" "${RDS_INSTANCE_ID}" 40 60
        else
            print_info "RDS instance already in deleting state"
        fi
    else
        print_info "No RDS instance found to delete"
    fi
    
    # Clean up DB subnet groups
    local subnet_groups=$(aws rds describe-db-subnet-groups \
        --query 'DBSubnetGroups[?contains(DBSubnetGroupName, `hybrid-db-subnet-group`)].DBSubnetGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${subnet_groups}" ]]; then
        echo "${subnet_groups}" | tr '\t' '\n' | while read -r subnet_group; do
            if [[ -n "${subnet_group}" ]]; then
                print_info "Deleting DB subnet group: ${subnet_group}"
                aws rds delete-db-subnet-group \
                    --db-subnet-group-name ${subnet_group} || \
                    print_warning "Failed to delete DB subnet group ${subnet_group}"
            fi
        done
    fi
    
    print_success "RDS cleanup completed"
}

# =============================================================================
# DIRECTORY SERVICE CLEANUP
# =============================================================================

cleanup_directory_service() {
    print_info "Cleaning up Directory Service resources..."
    
    if [[ -z "${DIRECTORY_ID:-}" ]]; then
        print_info "No directory ID found, skipping directory cleanup"
        return 0
    fi
    
    if resource_exists "directory" "${DIRECTORY_ID}"; then
        # Delete trust relationships first
        local trusts=$(aws ds describe-trusts \
            --directory-id ${DIRECTORY_ID} \
            --query 'Trusts[].TrustId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${trusts}" ]] && [[ "${trusts}" != "None" ]]; then
            echo "${trusts}" | tr '\t' '\n' | while read -r trust_id; do
                if [[ -n "${trust_id}" ]]; then
                    print_info "Deleting trust relationship: ${trust_id}"
                    aws ds delete-trust \
                        --directory-id ${DIRECTORY_ID} \
                        --trust-id ${trust_id} \
                        --delete-associated-conditional-forwarder || \
                        print_warning "Failed to delete trust ${trust_id}"
                fi
            done
            
            # Wait for trust deletion
            sleep 30
        fi
        
        # Delete the directory
        print_info "Deleting Directory Service: ${DIRECTORY_ID}"
        aws ds delete-directory --directory-id ${DIRECTORY_ID} || \
            print_warning "Failed to delete directory"
        
        # Wait for directory deletion
        wait_for_deletion "directory" "${DIRECTORY_ID}" 20 60
    else
        print_info "Directory Service not found or already deleted"
    fi
    
    print_success "Directory Service cleanup completed"
}

# =============================================================================
# EC2 INSTANCE CLEANUP
# =============================================================================

cleanup_ec2_instances() {
    print_info "Cleaning up EC2 instances..."
    
    # Find and terminate admin instances
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Purpose,Values=HybridIdentity" "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${instances}" ]] && [[ "${instances}" != "None" ]]; then
        echo "${instances}" | while read -r instance_info; do
            local instance_id=$(echo "${instance_info}" | cut -f1)
            local instance_name=$(echo "${instance_info}" | cut -f2)
            
            if [[ -n "${instance_id}" ]]; then
                print_info "Terminating EC2 instance: ${instance_id} (${instance_name:-Unknown})"
                aws ec2 terminate-instances --instance-ids ${instance_id} || \
                    print_warning "Failed to terminate instance ${instance_id}"
            fi
        done
        
        # Wait for instances to terminate
        if [[ -n "${ADMIN_INSTANCE_ID:-}" ]]; then
            wait_for_deletion "ec2-instance" "${ADMIN_INSTANCE_ID}" 15 30
        fi
    else
        print_info "No EC2 instances found to terminate"
    fi
    
    print_success "EC2 instances cleanup completed"
}

# =============================================================================
# IAM ROLE CLEANUP
# =============================================================================

cleanup_iam_roles() {
    print_info "Cleaning up IAM roles..."
    
    # Find and delete RDS directory service roles
    local roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `rds-directoryservice-role`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${roles}" ]]; then
        echo "${roles}" | tr '\t' '\n' | while read -r role_name; do
            if [[ -n "${role_name}" ]]; then
                print_info "Cleaning up IAM role: ${role_name}"
                
                # Detach policies
                aws iam detach-role-policy \
                    --role-name ${role_name} \
                    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSDirectoryServiceAccess 2>/dev/null || \
                    print_info "Policy already detached or not found"
                
                # Delete role
                aws iam delete-role --role-name ${role_name} || \
                    print_warning "Failed to delete IAM role ${role_name}"
            fi
        done
    else
        print_info "No IAM roles found to delete"
    fi
    
    print_success "IAM roles cleanup completed"
}

# =============================================================================
# NETWORKING CLEANUP
# =============================================================================

cleanup_networking() {
    print_info "Cleaning up networking resources..."
    
    if [[ -z "${VPC_ID:-}" ]]; then
        print_info "No VPC ID found, attempting to discover VPC..."
        local vpcs=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Purpose,Values=HybridIdentity" \
            --query 'Vpcs[0].VpcId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${vpcs}" ]] && [[ "${vpcs}" != "None" ]]; then
            export VPC_ID="${vpcs}"
        else
            print_info "No VPC found to clean up"
            return 0
        fi
    fi
    
    if resource_exists "vpc" "${VPC_ID}"; then
        # Delete security groups (except default)
        local security_groups=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${security_groups}" ]]; then
            echo "${security_groups}" | tr '\t' '\n' | while read -r sg_id; do
                if [[ -n "${sg_id}" ]]; then
                    print_info "Deleting security group: ${sg_id}"
                    aws ec2 delete-security-group --group-id ${sg_id} || \
                        print_warning "Failed to delete security group ${sg_id} (may have dependencies)"
                fi
            done
        fi
        
        # Delete subnets
        local subnets=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'Subnets[].SubnetId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${subnets}" ]]; then
            echo "${subnets}" | tr '\t' '\n' | while read -r subnet_id; do
                if [[ -n "${subnet_id}" ]]; then
                    print_info "Deleting subnet: ${subnet_id}"
                    aws ec2 delete-subnet --subnet-id ${subnet_id} || \
                        print_warning "Failed to delete subnet ${subnet_id}"
                fi
            done
        fi
        
        # Delete route tables (except main/default)
        local route_tables=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${route_tables}" ]]; then
            echo "${route_tables}" | tr '\t' '\n' | while read -r rt_id; do
                if [[ -n "${rt_id}" ]]; then
                    print_info "Deleting route table: ${rt_id}"
                    aws ec2 delete-route-table --route-table-id ${rt_id} || \
                        print_warning "Failed to delete route table ${rt_id}"
                fi
            done
        fi
        
        # Detach and delete internet gateway
        local igw_id=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
            --query 'InternetGateways[0].InternetGatewayId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${igw_id}" ]] && [[ "${igw_id}" != "None" ]]; then
            print_info "Detaching and deleting Internet Gateway: ${igw_id}"
            aws ec2 detach-internet-gateway --internet-gateway-id ${igw_id} --vpc-id ${VPC_ID} || \
                print_warning "Failed to detach internet gateway"
            aws ec2 delete-internet-gateway --internet-gateway-id ${igw_id} || \
                print_warning "Failed to delete internet gateway"
        fi
        
        # Delete VPC
        print_info "Deleting VPC: ${VPC_ID}"
        aws ec2 delete-vpc --vpc-id ${VPC_ID} || \
            print_warning "Failed to delete VPC (may have remaining dependencies)"
        
        # Wait for VPC deletion
        wait_for_deletion "vpc" "${VPC_ID}" 10 15
    else
        print_info "VPC not found or already deleted"
    fi
    
    print_success "Networking cleanup completed"
}

# =============================================================================
# MAIN CLEANUP FUNCTION
# =============================================================================

cleanup_hybrid_identity() {
    local force_flag=${1:-""}
    
    print_info "Starting AWS Hybrid Identity Management cleanup..."
    print_info "Log file: ${LOG_FILE}"
    
    # Record start time
    local start_time=$(date)
    
    # Load environment and confirm deletion
    check_prerequisites
    load_environment
    confirm_deletion "${force_flag}"
    
    # Execute cleanup in reverse order of deployment
    print_info "Beginning resource cleanup..."
    
    # Clean up in order of dependencies
    cleanup_workspaces
    cleanup_rds
    cleanup_directory_service
    cleanup_ec2_instances
    cleanup_iam_roles
    
    # Wait a bit for AWS eventual consistency
    print_info "Waiting for AWS eventual consistency..."
    sleep 30
    
    # Clean up networking last
    cleanup_networking
    
    # Clean up environment file
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        print_info "Removing deployment environment file..."
        rm -f "${SCRIPT_DIR}/deployment.env"
    fi
    
    # Record end time
    local end_time=$(date)
    
    print_success "=== CLEANUP COMPLETED ==="
    print_info "Started: ${start_time}"
    print_info "Completed: ${end_time}"
    print_warning ""
    print_warning "IMPORTANT NOTES:"
    print_warning "1. Some resources may take additional time to fully delete"
    print_warning "2. Check AWS Console to verify all resources are removed"
    print_warning "3. You may need to manually clean up any remaining resources"
    print_warning "4. DNS propagation may take up to 48 hours to clear"
    print_info ""
    print_info "Cleanup log saved to: ${LOG_FILE}"
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Trap errors and provide guidance
trap 'print_error "Cleanup failed on line $LINENO. Check ${LOG_FILE} for details. Some resources may need manual cleanup."' ERR

# =============================================================================
# USAGE INFORMATION
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --force     Skip confirmation prompt and proceed with deletion
    --help      Show this help message

DESCRIPTION:
    This script removes all AWS resources created by the deploy.sh script
    for the Hybrid Identity Management solution. This includes:
    
    - Amazon WorkSpaces and directory registration
    - RDS SQL Server instances and related resources
    - AWS Managed Microsoft AD
    - EC2 admin instances
    - VPC, subnets, security groups, and networking
    - IAM roles and policies
    
    WARNING: This operation is IRREVERSIBLE!
    
EXAMPLES:
    $0                  # Interactive cleanup with confirmation
    $0 --force          # Skip confirmation and proceed immediately
    $0 --help           # Show this help message

EOF
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_usage
        exit 0
        ;;
    --force)
        cleanup_hybrid_identity "--force"
        ;;
    "")
        cleanup_hybrid_identity
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac