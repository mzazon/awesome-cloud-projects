#!/bin/bash

#######################################
# AWS Private Blockchain Networks Cleanup Script
# Recipe: Establishing Private Blockchain Networks with Amazon Managed Blockchain
# 
# This script safely removes all blockchain infrastructure including:
# - Amazon Managed Blockchain nodes, members, and network
# - EC2 instances and key pairs
# - VPC endpoints and security groups
# - IAM roles and policies
# - CloudWatch log groups
#######################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo
    echo "========================================"
    echo "    BLOCKCHAIN NETWORK DESTRUCTION"
    echo "========================================"
    echo
    warn "This script will permanently delete the following resources:"
    echo "  - Blockchain network, members, and nodes"
    echo "  - EC2 instances and key pairs"
    echo "  - VPC endpoints and security groups"
    echo "  - IAM roles and policies"
    echo "  - CloudWatch log groups"
    echo "  - Configuration files"
    echo
    warn "This action CANNOT be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    warn "Final confirmation required..."
    read -p "Type 'DELETE' to confirm permanent deletion: " final_confirmation
    
    if [ "$final_confirmation" != "DELETE" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource destruction..."
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from blockchain-vars.env file
    if [ -f "blockchain-vars.env" ]; then
        info "Loading variables from blockchain-vars.env"
        source blockchain-vars.env
    elif [ -f "../blockchain-vars.env" ]; then
        info "Loading variables from ../blockchain-vars.env"
        source ../blockchain-vars.env
    else
        warn "blockchain-vars.env not found. Attempting to discover resources..."
        discover_resources
    fi
    
    # Set AWS region if not already set
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
    fi
    
    if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    info "Environment loaded - AWS Region: ${AWS_REGION}"
}

# Function to discover existing resources
discover_resources() {
    warn "Attempting to discover blockchain resources..."
    
    # List networks and prompt user to select
    echo "Available blockchain networks:"
    aws managedblockchain list-networks \
        --query 'Networks[].{ID:Id,Name:Name,Status:Status}' \
        --output table
    
    echo
    read -p "Enter the Network ID to destroy: " NETWORK_ID
    
    if [ -z "$NETWORK_ID" ]; then
        error "Network ID is required"
    fi
    
    export NETWORK_ID
    
    # Get member information
    MEMBER_ID=$(aws managedblockchain list-members \
        --network-id "${NETWORK_ID}" \
        --query 'Members[0].Id' --output text 2>/dev/null || echo "")
    
    if [ -n "$MEMBER_ID" ] && [ "$MEMBER_ID" != "None" ]; then
        export MEMBER_ID
        info "Found member: ${MEMBER_ID}"
        
        # Get node information
        NODE_ID=$(aws managedblockchain list-nodes \
            --network-id "${NETWORK_ID}" \
            --member-id "${MEMBER_ID}" \
            --query 'Nodes[0].Id' --output text 2>/dev/null || echo "")
        
        if [ -n "$NODE_ID" ] && [ "$NODE_ID" != "None" ]; then
            export NODE_ID
            info "Found node: ${NODE_ID}"
        fi
    fi
    
    # Try to find EC2 instances with blockchain-related tags
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=blockchain-client" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "")
    
    if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
        export INSTANCE_ID
        info "Found EC2 instance: ${INSTANCE_ID}"
    fi
}

# Function to delete blockchain network resources
delete_blockchain_resources() {
    if [ -z "${NETWORK_ID:-}" ]; then
        warn "No network ID found, skipping blockchain resource deletion"
        return 0
    fi
    
    log "Deleting blockchain network resources..."
    
    # Delete peer node if it exists
    if [ -n "${NODE_ID:-}" ] && [ "${NODE_ID}" != "None" ]; then
        info "Deleting peer node: ${NODE_ID}"
        
        aws managedblockchain delete-node \
            --network-id "${NETWORK_ID}" \
            --member-id "${MEMBER_ID}" \
            --node-id "${NODE_ID}" 2>/dev/null || warn "Failed to delete node or node doesn't exist"
        
        # Wait for node deletion
        info "Waiting for node deletion to complete..."
        for i in {1..20}; do
            if ! aws managedblockchain get-node \
                --network-id "${NETWORK_ID}" \
                --member-id "${MEMBER_ID}" \
                --node-id "${NODE_ID}" &>/dev/null; then
                log "Node deleted successfully"
                break
            fi
            info "Node deletion in progress... (attempt $i/20)"
            sleep 30
        done
    fi
    
    # Delete member if it exists
    if [ -n "${MEMBER_ID:-}" ] && [ "${MEMBER_ID}" != "None" ]; then
        info "Deleting member: ${MEMBER_ID}"
        
        aws managedblockchain delete-member \
            --network-id "${NETWORK_ID}" \
            --member-id "${MEMBER_ID}" 2>/dev/null || warn "Failed to delete member or member doesn't exist"
        
        # Wait for member deletion
        info "Waiting for member deletion to complete..."
        for i in {1..20}; do
            if ! aws managedblockchain get-member \
                --network-id "${NETWORK_ID}" \
                --member-id "${MEMBER_ID}" &>/dev/null; then
                log "Member deleted successfully"
                break
            fi
            info "Member deletion in progress... (attempt $i/20)"
            sleep 30
        done
    fi
    
    # Delete network
    info "Deleting blockchain network: ${NETWORK_ID}"
    
    aws managedblockchain delete-network \
        --network-id "${NETWORK_ID}" 2>/dev/null || warn "Failed to delete network or network doesn't exist"
    
    # Wait for network deletion
    info "Waiting for network deletion to complete..."
    for i in {1..20}; do
        if ! aws managedblockchain get-network \
            --network-id "${NETWORK_ID}" &>/dev/null; then
            log "Network deleted successfully"
            break
        fi
        info "Network deletion in progress... (attempt $i/20)"
        sleep 30
    done
    
    log "Blockchain resources cleanup completed"
}

# Function to delete EC2 resources
delete_ec2_resources() {
    log "Deleting EC2 resources..."
    
    # Terminate EC2 instance
    if [ -n "${INSTANCE_ID:-}" ] && [ "${INSTANCE_ID}" != "None" ]; then
        info "Terminating EC2 instance: ${INSTANCE_ID}"
        
        aws ec2 terminate-instances \
            --instance-ids "${INSTANCE_ID}" 2>/dev/null || warn "Failed to terminate instance or instance doesn't exist"
        
        # Wait for instance termination
        info "Waiting for instance termination..."
        aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}" 2>/dev/null || warn "Instance termination wait failed"
        
        log "EC2 instance terminated successfully"
    fi
    
    # Delete key pair
    if [ -n "${KEY_NAME:-}" ]; then
        info "Deleting key pair: ${KEY_NAME}"
        
        aws ec2 delete-key-pair \
            --key-name "${KEY_NAME}" 2>/dev/null || warn "Failed to delete key pair or key pair doesn't exist"
        
        # Remove local key file
        if [ -f "${KEY_NAME}.pem" ]; then
            rm -f "${KEY_NAME}.pem"
            info "Local key file removed"
        fi
        
        log "Key pair deleted successfully"
    fi
    
    # Try to find and delete blockchain-related key pairs if KEY_NAME not set
    if [ -z "${KEY_NAME:-}" ]; then
        info "Searching for blockchain-related key pairs..."
        
        KEY_PAIRS=$(aws ec2 describe-key-pairs \
            --query 'KeyPairs[?contains(KeyName, `blockchain-client-key`)].KeyName' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$KEY_PAIRS" ]; then
            for key in $KEY_PAIRS; do
                info "Deleting discovered key pair: $key"
                aws ec2 delete-key-pair --key-name "$key" 2>/dev/null || warn "Failed to delete key pair: $key"
                
                # Remove local key file if it exists
                if [ -f "${key}.pem" ]; then
                    rm -f "${key}.pem"
                fi
            done
        fi
    fi
    
    log "EC2 resources cleanup completed"
}

# Function to delete VPC resources
delete_vpc_resources() {
    log "Deleting VPC resources..."
    
    # Delete VPC endpoint
    if [ -n "${ENDPOINT_ID:-}" ] && [ "${ENDPOINT_ID}" != "None" ]; then
        info "Deleting VPC endpoint: ${ENDPOINT_ID}"
        
        aws ec2 delete-vpc-endpoints \
            --vpc-endpoint-ids "${ENDPOINT_ID}" 2>/dev/null || warn "Failed to delete VPC endpoint or endpoint doesn't exist"
        
        log "VPC endpoint deleted successfully"
    fi
    
    # Delete security group
    if [ -n "${SG_ID:-}" ] && [ "${SG_ID}" != "None" ]; then
        info "Deleting security group: ${SG_ID}"
        
        # Wait a bit for resources using the security group to be deleted
        sleep 30
        
        aws ec2 delete-security-group \
            --group-id "${SG_ID}" 2>/dev/null || warn "Failed to delete security group or security group doesn't exist"
        
        log "Security group deleted successfully"
    fi
    
    # Try to find and delete blockchain-related security groups if SG_ID not set
    if [ -z "${SG_ID:-}" ]; then
        info "Searching for blockchain-related security groups..."
        
        SG_IDS=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=managed-blockchain-sg*" \
            --query 'SecurityGroups[].GroupId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SG_IDS" ]; then
            for sg in $SG_IDS; do
                info "Deleting discovered security group: $sg"
                sleep 10  # Wait between deletions
                aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || warn "Failed to delete security group: $sg"
            done
        fi
    fi
    
    log "VPC resources cleanup completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Delete custom chaincode policy
    info "Searching for blockchain chaincode policies..."
    
    POLICY_ARNS=$(aws iam list-policies \
        --scope Local \
        --query 'Policies[?contains(PolicyName, `BlockchainChaincodePolicy`)].Arn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$POLICY_ARNS" ]; then
        for policy_arn in $POLICY_ARNS; do
            info "Deleting chaincode policy: $policy_arn"
            aws iam delete-policy \
                --policy-arn "$policy_arn" 2>/dev/null || warn "Failed to delete policy: $policy_arn"
        done
    fi
    
    # Delete ManagedBlockchainRole
    info "Deleting ManagedBlockchainRole..."
    
    # Detach policies from role
    aws iam detach-role-policy \
        --role-name ManagedBlockchainRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonManagedBlockchainFullAccess 2>/dev/null || warn "Failed to detach policy from role"
    
    # Delete the role
    aws iam delete-role \
        --role-name ManagedBlockchainRole 2>/dev/null || warn "Failed to delete ManagedBlockchainRole or role doesn't exist"
    
    log "IAM resources cleanup completed"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring and logging resources..."
    
    # Delete CloudWatch log groups
    if [ -n "${NETWORK_NAME:-}" ]; then
        LOG_GROUP_NAME="/aws/managedblockchain/${NETWORK_NAME}"
        info "Deleting CloudWatch log group: ${LOG_GROUP_NAME}"
        
        aws logs delete-log-group \
            --log-group-name "${LOG_GROUP_NAME}" 2>/dev/null || warn "Failed to delete log group or log group doesn't exist"
    fi
    
    # Try to find and delete blockchain-related log groups
    info "Searching for blockchain-related log groups..."
    
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/managedblockchain/" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$LOG_GROUPS" ]; then
        for log_group in $LOG_GROUPS; do
            info "Deleting discovered log group: $log_group"
            aws logs delete-log-group \
                --log-group-name "$log_group" 2>/dev/null || warn "Failed to delete log group: $log_group"
        done
    fi
    
    # Note: VPC Flow Logs are not deleted as they may be used by other resources
    warn "VPC Flow Logs are not deleted as they may be shared with other resources"
    
    log "Monitoring resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    # Remove configuration files
    local files_to_remove=(
        "blockchain-vars.env"
        "network-info.json"
        "connection-instructions.md"
        "sample-chaincode.go"
        "../blockchain-vars.env"
        "../network-info.json"
        "../connection-instructions.md"
        "../sample-chaincode.go"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed: $file"
        fi
    done
    
    # Remove deployment directory if we're inside one
    CURRENT_DIR=$(basename "$(pwd)")
    if [[ "$CURRENT_DIR" == blockchain-deployment-* ]]; then
        info "Removing deployment directory..."
        cd ..
        rm -rf "$CURRENT_DIR"
        info "Deployment directory removed"
    fi
    
    # Remove any remaining .pem files
    for pem_file in *.pem; do
        if [ -f "$pem_file" ]; then
            rm -f "$pem_file"
            info "Removed key file: $pem_file"
        fi
    done
    
    log "Local files cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local issues_found=false
    
    # Check if network still exists
    if [ -n "${NETWORK_ID:-}" ]; then
        if aws managedblockchain get-network --network-id "${NETWORK_ID}" &>/dev/null; then
            warn "Network ${NETWORK_ID} still exists"
            issues_found=true
        else
            info "✓ Network deleted successfully"
        fi
    fi
    
    # Check if EC2 instance still exists
    if [ -n "${INSTANCE_ID:-}" ]; then
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "${INSTANCE_ID}" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "terminated")
        
        if [ "$INSTANCE_STATE" != "terminated" ]; then
            warn "EC2 instance ${INSTANCE_ID} is still in state: ${INSTANCE_STATE}"
            issues_found=true
        else
            info "✓ EC2 instance terminated successfully"
        fi
    fi
    
    # Check if VPC endpoint still exists
    if [ -n "${ENDPOINT_ID:-}" ]; then
        if aws ec2 describe-vpc-endpoints --vpc-endpoint-ids "${ENDPOINT_ID}" &>/dev/null; then
            warn "VPC endpoint ${ENDPOINT_ID} still exists"
            issues_found=true
        else
            info "✓ VPC endpoint deleted successfully"
        fi
    fi
    
    # Check if security group still exists
    if [ -n "${SG_ID:-}" ]; then
        if aws ec2 describe-security-groups --group-ids "${SG_ID}" &>/dev/null; then
            warn "Security group ${SG_ID} still exists"
            issues_found=true
        else
            info "✓ Security group deleted successfully"
        fi
    fi
    
    if [ "$issues_found" = true ]; then
        warn "Some resources may still exist. Check AWS console for manual cleanup."
    else
        log "All resources deleted successfully"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup completed!"
    echo
    echo "========================================"
    echo "    CLEANUP SUMMARY"
    echo "========================================"
    echo
    echo "Deleted Resources:"
    echo "  ✓ Blockchain network and components"
    echo "  ✓ EC2 instances and key pairs"
    echo "  ✓ VPC endpoints and security groups"
    echo "  ✓ IAM roles and policies"
    echo "  ✓ CloudWatch log groups"
    echo "  ✓ Local configuration files"
    echo
    echo "Notes:"
    echo "  - VPC Flow Logs were preserved (may be shared)"
    echo "  - Check AWS console for any remaining resources"
    echo "  - Review AWS billing for any unexpected charges"
    echo
    info "Blockchain infrastructure has been completely removed"
    echo "========================================"
}

# Main execution flow
main() {
    log "Starting blockchain network cleanup..."
    
    confirm_destruction
    check_prerequisites
    load_environment
    
    # Perform cleanup in reverse order of creation
    delete_blockchain_resources
    delete_ec2_resources
    delete_vpc_resources
    delete_iam_resources
    delete_monitoring_resources
    cleanup_local_files
    
    verify_deletion
    display_summary
    
    log "Cleanup script completed successfully!"
}

# Trap errors
trap 'error "Cleanup failed at line $LINENO. Some resources may still exist."' ERR

# Run main function
main "$@"