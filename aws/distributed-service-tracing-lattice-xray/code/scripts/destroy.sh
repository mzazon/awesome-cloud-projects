#!/bin/bash

# Distributed Service Tracing with VPC Lattice and X-Ray - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -e

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
FORCE_CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--force] [--help]"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Find the most recent state file
    STATE_FILE=$(find "${SCRIPT_DIR}" -name ".deployment-state-*" -type f -exec ls -t {} + | head -n 1)
    
    if [ -z "${STATE_FILE}" ] || [ ! -f "${STATE_FILE}" ]; then
        warn "No deployment state file found. Attempting cleanup using discovery..."
        discover_resources
        return
    fi
    
    info "Loading state from: ${STATE_FILE}"
    source "${STATE_FILE}"
    
    # Verify required variables are set
    if [ -z "${RANDOM_SUFFIX}" ]; then
        error "Invalid state file: RANDOM_SUFFIX not found"
        exit 1
    fi
    
    info "State loaded successfully. Resource suffix: ${RANDOM_SUFFIX}"
}

# Discover resources when no state file exists
discover_resources() {
    warn "Attempting to discover resources created by this recipe..."
    
    # Try to find resources by tags or naming patterns
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # This is a fallback - may not catch all resources
    warn "Discovery mode has limitations. Some resources may need manual cleanup."
}

# Confirmation prompt
confirm_cleanup() {
    if [ "${FORCE_CLEANUP}" = true ]; then
        log "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    info "This script will permanently delete the following resources:"
    info "  • VPC Lattice service network and services"
    info "  • Lambda functions (order, payment, inventory services)"
    info "  • Lambda layer (X-Ray SDK)"
    info "  • IAM roles and policies"
    info "  • CloudWatch log groups and dashboard"
    info "  • VPC, subnets, and networking components"
    info "  • All associated tags and configurations"
    echo ""
    warn "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "${confirmation}" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed. Proceeding with resource deletion..."
}

# Clean up VPC Lattice resources
cleanup_vpc_lattice() {
    log "Cleaning up VPC Lattice resources..."
    
    if [ -n "${SERVICE_NETWORK_ID}" ]; then
        # Delete service network service associations
        info "Removing service network service associations..."
        aws vpc-lattice list-service-network-service-associations \
            --service-network-identifier "${SERVICE_NETWORK_ID}" \
            --query 'items[].id' --output text | \
        while read -r association_id; do
            if [ -n "${association_id}" ] && [ "${association_id}" != "None" ]; then
                aws vpc-lattice delete-service-network-service-association \
                    --service-network-service-association-identifier "${association_id}" || warn "Failed to delete service association ${association_id}"
            fi
        done
        
        # Delete VPC associations
        info "Removing VPC associations..."
        if [ -n "${VPC_ASSOCIATION_ID}" ]; then
            aws vpc-lattice delete-service-network-vpc-association \
                --service-network-vpc-association-identifier "${VPC_ASSOCIATION_ID}" || warn "Failed to delete VPC association"
        fi
        
        # Wait for associations to be removed
        sleep 10
        
        # Delete service network
        info "Deleting service network..."
        aws vpc-lattice delete-service-network \
            --service-network-identifier "${SERVICE_NETWORK_ID}" || warn "Failed to delete service network"
    fi
    
    # Delete services
    if [ -n "${ORDER_SERVICE_ID}" ]; then
        info "Deleting Lattice service..."
        aws vpc-lattice delete-service \
            --service-identifier "${ORDER_SERVICE_ID}" || warn "Failed to delete service"
    fi
    
    # Delete target groups
    if [ -n "${ORDER_TG_ID}" ]; then
        info "Deleting target group..."
        aws vpc-lattice delete-target-group \
            --target-group-identifier "${ORDER_TG_ID}" || warn "Failed to delete target group"
    fi
    
    log "✅ VPC Lattice resources cleanup completed"
}

# Clean up Lambda functions and layers
cleanup_lambda_resources() {
    log "Cleaning up Lambda resources..."
    
    # Delete Lambda functions
    if [ -n "${RANDOM_SUFFIX}" ]; then
        for function_name in "order-service-${RANDOM_SUFFIX}" "payment-service-${RANDOM_SUFFIX}" "inventory-service-${RANDOM_SUFFIX}"; do
            info "Deleting Lambda function: ${function_name}"
            aws lambda delete-function \
                --function-name "${function_name}" 2>/dev/null || warn "Failed to delete function ${function_name}"
        done
        
        # Delete Lambda layer
        info "Deleting Lambda layer: xray-sdk-${RANDOM_SUFFIX}"
        aws lambda delete-layer-version \
            --layer-name "xray-sdk-${RANDOM_SUFFIX}" \
            --version-number 1 2>/dev/null || warn "Failed to delete Lambda layer"
    else
        # Discovery mode - find and delete functions by pattern
        warn "Using discovery mode for Lambda functions..."
        aws lambda list-functions \
            --query 'Functions[?contains(FunctionName, `order-service-`) || contains(FunctionName, `payment-service-`) || contains(FunctionName, `inventory-service-`)].FunctionName' \
            --output text | \
        while read -r function_name; do
            if [ -n "${function_name}" ] && [ "${function_name}" != "None" ]; then
                info "Deleting discovered function: ${function_name}"
                aws lambda delete-function --function-name "${function_name}" || warn "Failed to delete ${function_name}"
            fi
        done
    fi
    
    log "✅ Lambda resources cleanup completed"
}

# Clean up IAM resources
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    if [ -n "${RANDOM_SUFFIX}" ]; then
        ROLE_NAME="lattice-lambda-xray-role-${RANDOM_SUFFIX}"
        
        info "Detaching policies from role: ${ROLE_NAME}"
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || warn "Failed to detach basic execution policy"
        
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess 2>/dev/null || warn "Failed to detach X-Ray policy"
        
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole 2>/dev/null || warn "Failed to detach VPC access policy"
        
        # Wait for policy detachments to propagate
        sleep 5
        
        info "Deleting IAM role: ${ROLE_NAME}"
        aws iam delete-role \
            --role-name "${ROLE_NAME}" 2>/dev/null || warn "Failed to delete IAM role"
    else
        # Discovery mode
        warn "Using discovery mode for IAM roles..."
        aws iam list-roles \
            --query 'Roles[?contains(RoleName, `lattice-lambda-xray-role-`)].RoleName' \
            --output text | \
        while read -r role_name; do
            if [ -n "${role_name}" ] && [ "${role_name}" != "None" ]; then
                info "Deleting discovered role: ${role_name}"
                # Detach all policies first
                aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text | \
                while read -r policy_arn; do
                    aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}" 2>/dev/null || true
                done
                sleep 2
                aws iam delete-role --role-name "${role_name}" || warn "Failed to delete ${role_name}"
            fi
        done
    fi
    
    log "✅ IAM resources cleanup completed"
}

# Clean up CloudWatch resources
cleanup_cloudwatch_resources() {
    log "Cleaning up CloudWatch resources..."
    
    if [ -n "${RANDOM_SUFFIX}" ]; then
        # Delete CloudWatch dashboard
        info "Deleting CloudWatch dashboard: Lattice-XRay-Observability-${RANDOM_SUFFIX}"
        aws cloudwatch delete-dashboards \
            --dashboard-names "Lattice-XRay-Observability-${RANDOM_SUFFIX}" 2>/dev/null || warn "Failed to delete dashboard"
        
        # Delete log groups
        for log_group in "/aws/lambda/order-service-${RANDOM_SUFFIX}" "/aws/lambda/payment-service-${RANDOM_SUFFIX}" "/aws/lambda/inventory-service-${RANDOM_SUFFIX}" "/aws/vpclattice/servicenetwork-${RANDOM_SUFFIX}"; do
            info "Deleting log group: ${log_group}"
            aws logs delete-log-group \
                --log-group-name "${log_group}" 2>/dev/null || warn "Failed to delete log group ${log_group}"
        done
    else
        # Discovery mode
        warn "Using discovery mode for CloudWatch resources..."
        aws logs describe-log-groups \
            --query 'logGroups[?contains(logGroupName, `order-service-`) || contains(logGroupName, `payment-service-`) || contains(logGroupName, `inventory-service-`) || contains(logGroupName, `servicenetwork-`)].logGroupName' \
            --output text | \
        while read -r log_group; do
            if [ -n "${log_group}" ] && [ "${log_group}" != "None" ]; then
                info "Deleting discovered log group: ${log_group}"
                aws logs delete-log-group --log-group-name "${log_group}" || warn "Failed to delete ${log_group}"
            fi
        done
    fi
    
    log "✅ CloudWatch resources cleanup completed"
}

# Clean up VPC and networking resources
cleanup_vpc_resources() {
    log "Cleaning up VPC and networking resources..."
    
    if [ -n "${VPC_ID}" ]; then
        # Delete subnets
        if [ -n "${SUBNET_ID}" ]; then
            info "Deleting subnet: ${SUBNET_ID}"
            aws ec2 delete-subnet --subnet-id "${SUBNET_ID}" || warn "Failed to delete subnet"
        fi
        
        # Delete route table associations and routes
        if [ -n "${ROUTE_TABLE_ID}" ]; then
            info "Cleaning up route table: ${ROUTE_TABLE_ID}"
            # Delete custom routes (keep local route)
            aws ec2 describe-route-tables --route-table-ids "${ROUTE_TABLE_ID}" \
                --query 'RouteTables[0].Routes[?DestinationCidrBlock!=`10.0.0.0/16`].DestinationCidrBlock' \
                --output text | \
            while read -r cidr; do
                if [ -n "${cidr}" ] && [ "${cidr}" != "None" ]; then
                    aws ec2 delete-route --route-table-id "${ROUTE_TABLE_ID}" --destination-cidr-block "${cidr}" || true
                fi
            done
            
            # Delete route table
            aws ec2 delete-route-table --route-table-id "${ROUTE_TABLE_ID}" || warn "Failed to delete route table"
        fi
        
        # Detach and delete internet gateway
        if [ -n "${IGW_ID}" ]; then
            info "Detaching and deleting internet gateway: ${IGW_ID}"
            aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" || warn "Failed to detach IGW"
            aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" || warn "Failed to delete IGW"
        fi
        
        # Wait for resources to be cleaned up
        sleep 10
        
        # Delete VPC
        info "Deleting VPC: ${VPC_ID}"
        aws ec2 delete-vpc --vpc-id "${VPC_ID}" || warn "Failed to delete VPC"
    else
        # Discovery mode for VPC resources
        warn "Using discovery mode for VPC resources..."
        aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=lattice-tracing-vpc-*" \
            --query 'Vpcs[].VpcId' --output text | \
        while read -r vpc_id; do
            if [ -n "${vpc_id}" ] && [ "${vpc_id}" != "None" ]; then
                info "Deleting discovered VPC: ${vpc_id}"
                # Clean up subnets first
                aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpc_id}" --query 'Subnets[].SubnetId' --output text | \
                while read -r subnet_id; do
                    aws ec2 delete-subnet --subnet-id "${subnet_id}" || true
                done
                # Clean up internet gateways
                aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${vpc_id}" --query 'InternetGateways[].InternetGatewayId' --output text | \
                while read -r igw_id; do
                    aws ec2 detach-internet-gateway --internet-gateway-id "${igw_id}" --vpc-id "${vpc_id}" || true
                    aws ec2 delete-internet-gateway --internet-gateway-id "${igw_id}" || true
                done
                sleep 5
                aws ec2 delete-vpc --vpc-id "${vpc_id}" || warn "Failed to delete VPC ${vpc_id}"
            fi
        done
    fi
    
    log "✅ VPC resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove test generator
    if [ -f "${SCRIPT_DIR}/test-distributed-tracing.py" ]; then
        info "Removing test generator script"
        rm -f "${SCRIPT_DIR}/test-distributed-tracing.py"
    fi
    
    # Remove response files
    rm -f "${SCRIPT_DIR}/response.json" 2>/dev/null || true
    
    # Remove state files (with confirmation)
    if [ "${FORCE_CLEANUP}" = true ]; then
        info "Removing deployment state files"
        rm -f "${SCRIPT_DIR}/.deployment-state-"* 2>/dev/null || true
    else
        if [ -n "${STATE_FILE}" ] && [ -f "${STATE_FILE}" ]; then
            read -p "Remove deployment state file ${STATE_FILE}? (y/N): " remove_state
            if [ "${remove_state}" = "y" ] || [ "${remove_state}" = "Y" ]; then
                rm -f "${STATE_FILE}"
                info "State file removed"
            else
                info "State file preserved"
            fi
        fi
    fi
    
    log "✅ Local files cleanup completed"
}

# Resource verification
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    # Check for remaining Lambda functions
    REMAINING_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `order-service-`) || contains(FunctionName, `payment-service-`) || contains(FunctionName, `inventory-service-`)].FunctionName' \
        --output text)
    
    if [ -n "${REMAINING_FUNCTIONS}" ] && [ "${REMAINING_FUNCTIONS}" != "None" ]; then
        warn "Some Lambda functions may still exist: ${REMAINING_FUNCTIONS}"
    else
        info "✅ All Lambda functions cleaned up"
    fi
    
    # Check for remaining VPC Lattice service networks
    if [ -n "${RANDOM_SUFFIX}" ]; then
        REMAINING_NETWORKS=$(aws vpc-lattice list-service-networks \
            --query "items[?contains(name, '${RANDOM_SUFFIX}')].name" \
            --output text)
        
        if [ -n "${REMAINING_NETWORKS}" ] && [ "${REMAINING_NETWORKS}" != "None" ]; then
            warn "Some VPC Lattice networks may still exist: ${REMAINING_NETWORKS}"
        else
            info "✅ All VPC Lattice networks cleaned up"
        fi
    fi
    
    # Check for remaining IAM roles
    if [ -n "${RANDOM_SUFFIX}" ]; then
        REMAINING_ROLES=$(aws iam list-roles \
            --query "Roles[?contains(RoleName, '${RANDOM_SUFFIX}')].RoleName" \
            --output text)
        
        if [ -n "${REMAINING_ROLES}" ] && [ "${REMAINING_ROLES}" != "None" ]; then
            warn "Some IAM roles may still exist: ${REMAINING_ROLES}"
        else
            info "✅ All IAM roles cleaned up"
        fi
    fi
    
    log "Cleanup verification completed"
}

# Main cleanup function
main() {
    log "Starting distributed service tracing cleanup..."
    
    # Load state and confirm
    load_deployment_state
    confirm_cleanup
    
    # Execute cleanup in reverse order of creation
    cleanup_vpc_lattice
    cleanup_lambda_resources
    cleanup_iam_resources
    cleanup_cloudwatch_resources
    cleanup_vpc_resources
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Success message
    log "🎉 Cleanup completed successfully!"
    echo ""
    info "📋 Cleanup Summary:"
    info "  • All VPC Lattice resources removed"
    info "  • All Lambda functions and layers deleted"
    info "  • All IAM roles and policies cleaned up"
    info "  • All CloudWatch resources removed"
    info "  • All VPC and networking resources deleted"
    info "  • Local files cleaned up"
    echo ""
    warn "💡 Note: X-Ray traces have a retention period and will be automatically deleted by AWS."
    warn "💡 Note: If any resources remain, they may need manual cleanup in the AWS Console."
    echo ""
    log "Cleanup process completed at $(date)"
}

# Handle script interruption
cleanup_on_interrupt() {
    echo ""
    warn "Cleanup interrupted by user"
    warn "Some resources may remain and need manual cleanup"
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Script execution
if [ "${1}" = "--dry-run" ]; then
    log "Dry run mode - would execute cleanup steps"
    load_deployment_state
    echo ""
    info "Would clean up the following resources:"
    info "  • VPC Lattice Service Network: ${SERVICE_NETWORK_ID:-'(to be discovered)'}"
    info "  • Lambda Functions: order-service-${RANDOM_SUFFIX:-'*'}, payment-service-${RANDOM_SUFFIX:-'*'}, inventory-service-${RANDOM_SUFFIX:-'*'}"
    info "  • IAM Role: lattice-lambda-xray-role-${RANDOM_SUFFIX:-'*'}"
    info "  • VPC: ${VPC_ID:-'(to be discovered)'}"
    info "  • CloudWatch Dashboard: Lattice-XRay-Observability-${RANDOM_SUFFIX:-'*'}"
    exit 0
fi

main "$@"