#!/bin/bash

#=============================================================================
# AWS Cross-Account Database Sharing with VPC Lattice and RDS
# Cleanup/Destroy Script
#
# This script safely removes all resources created by the deployment script:
# - AWS RAM resource shares
# - VPC Lattice resource configurations and service networks
# - VPC Lattice resource gateways
# - RDS databases and related resources
# - IAM roles and policies
# - CloudWatch dashboards and log groups
# - VPC and networking infrastructure
#
# Prerequisites:
# - deployment_state.env file from the deployment script
# - AWS CLI v2 installed and configured
# - Administrative permissions in Account A (database owner)
#=============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/deployment_state.env"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"

# Start logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log_info "Starting AWS Cross-Account Database Sharing cleanup..."
log_info "Log file: ${LOG_FILE}"

#=============================================================================
# Load Deployment State
#=============================================================================

load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_error "Deployment state file not found: ${STATE_FILE}"
        log_error "Cannot proceed with cleanup without deployment state."
        log_info "If you need to clean up manually, check the AWS Console for resources with the pattern:"
        log_info "- VPC Lattice service networks: database-sharing-network-*"
        log_info "- RDS instances: shared-database-*"
        log_info "- IAM roles: DatabaseAccessRole-*"
        exit 1
    fi
    
    # Source the state file
    source "${STATE_FILE}"
    
    # Verify required variables are set
    REQUIRED_VARS=(
        "AWS_REGION" "AWS_ACCOUNT_A" "AWS_ACCOUNT_B" 
        "DB_INSTANCE_ID" "SERVICE_NETWORK_NAME" 
        "RESOURCE_CONFIG_NAME" "RESOURCE_GATEWAY_NAME"
        "RANDOM_SUFFIX"
    )
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable ${var} not found in state file"
            exit 1
        fi
    done
    
    log_success "Deployment state loaded successfully"
    log_info "Account A: ${AWS_ACCOUNT_A}"
    log_info "Account B: ${AWS_ACCOUNT_B}"
    log_info "Region: ${AWS_REGION}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

#=============================================================================
# Prerequisites Check
#=============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Verify we're in the correct account
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [[ "${CURRENT_ACCOUNT}" != "${AWS_ACCOUNT_A}" ]]; then
        log_error "Currently authenticated to account ${CURRENT_ACCOUNT}, but deployment was in account ${AWS_ACCOUNT_A}"
        log_error "Please configure AWS CLI for the correct account before running cleanup."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

#=============================================================================
# Confirmation Prompt
#=============================================================================

confirm_cleanup() {
    echo
    log_warn "==================================================================="
    log_warn "DESTRUCTIVE OPERATION WARNING"
    log_warn "==================================================================="
    log_warn "This script will permanently delete the following resources:"
    log_warn "- RDS Database: ${DB_INSTANCE_ID}"
    log_warn "- VPC Lattice Service Network: ${SERVICE_NETWORK_NAME}"
    log_warn "- VPC Lattice Resource Gateway: ${RESOURCE_GATEWAY_NAME}"
    log_warn "- AWS RAM Resource Share: ${RESOURCE_SHARE_NAME:-DatabaseResourceShare-${RANDOM_SUFFIX}}"
    log_warn "- IAM Role: ${ROLE_NAME:-DatabaseAccessRole-${RANDOM_SUFFIX}}"
    log_warn "- VPC: ${VPC_ID:-database-owner-vpc-${RANDOM_SUFFIX}}"
    log_warn "- CloudWatch Dashboard and Logs"
    log_warn "==================================================================="
    echo
    
    if [[ "${FORCE_CLEANUP:-}" == "true" ]]; then
        log_info "Force cleanup enabled, proceeding without confirmation..."
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r CONFIRMATION
    
    if [[ "${CONFIRMATION,,}" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Cleanup confirmed, proceeding..."
}

#=============================================================================
# Resource Cleanup Functions
#=============================================================================

cleanup_aws_ram_share() {
    log_info "Removing AWS RAM resource share..."
    
    if [[ -n "${RESOURCE_SHARE_ARN:-}" ]]; then
        aws ram delete-resource-share \
            --resource-share-arn "${RESOURCE_SHARE_ARN}" &> /dev/null || {
            log_warn "Failed to delete resource share or it may already be deleted"
        }
        log_success "Resource share deletion initiated"
    else
        log_warn "Resource share ARN not found in state, skipping..."
    fi
}

cleanup_resource_configuration() {
    log_info "Removing VPC Lattice resource configuration..."
    
    if [[ -n "${RESOURCE_CONFIG_ID:-}" && -n "${SERVICE_NETWORK_ID:-}" ]]; then
        # Delete resource configuration association
        aws vpc-lattice delete-resource-configuration-association \
            --resource-configuration-identifier "${RESOURCE_CONFIG_ID}" \
            --service-network-identifier "${SERVICE_NETWORK_ID}" &> /dev/null || {
            log_warn "Failed to delete resource configuration association or it may already be deleted"
        }
        
        # Wait a moment for the association to be deleted
        sleep 10
        
        # Delete resource configuration
        aws vpc-lattice delete-resource-configuration \
            --resource-configuration-identifier "${RESOURCE_CONFIG_ID}" &> /dev/null || {
            log_warn "Failed to delete resource configuration or it may already be deleted"
        }
        
        log_success "Resource configuration and association deleted"
    else
        log_warn "Resource configuration ID or Service Network ID not found, skipping..."
    fi
}

cleanup_service_network() {
    log_info "Removing VPC Lattice service network..."
    
    if [[ -n "${SERVICE_NETWORK_ID:-}" && -n "${VPC_ID:-}" ]]; then
        # Delete service network VPC association
        aws vpc-lattice delete-service-network-vpc-association \
            --service-network-identifier "${SERVICE_NETWORK_ID}" \
            --vpc-identifier "${VPC_ID}" &> /dev/null || {
            log_warn "Failed to delete service network VPC association or it may already be deleted"
        }
        
        # Wait for association deletion
        sleep 10
        
        # Delete service network
        aws vpc-lattice delete-service-network \
            --service-network-identifier "${SERVICE_NETWORK_ID}" &> /dev/null || {
            log_warn "Failed to delete service network or it may already be deleted"
        }
        
        log_success "Service network and VPC association deleted"
    else
        log_warn "Service Network ID or VPC ID not found, skipping..."
    fi
}

cleanup_resource_gateway() {
    log_info "Removing VPC Lattice resource gateway..."
    
    if [[ -n "${RESOURCE_GATEWAY_ID:-}" ]]; then
        aws vpc-lattice delete-resource-gateway \
            --resource-gateway-identifier "${RESOURCE_GATEWAY_ID}" &> /dev/null || {
            log_warn "Failed to delete resource gateway or it may already be deleted"
        }
        log_success "Resource gateway deleted"
    else
        log_warn "Resource Gateway ID not found, skipping..."
    fi
}

cleanup_rds_database() {
    log_info "Removing RDS database and related resources..."
    
    if [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        # Delete RDS database
        log_info "Deleting RDS database (this may take several minutes)..."
        aws rds delete-db-instance \
            --db-instance-identifier "${DB_INSTANCE_ID}" \
            --skip-final-snapshot \
            --delete-automated-backups &> /dev/null || {
            log_warn "Failed to delete RDS database or it may already be deleted"
        }
        
        # Wait for deletion (with timeout)
        log_info "Waiting for RDS database deletion to complete..."
        timeout 1200 aws rds wait db-instance-deleted \
            --db-instance-identifier "${DB_INSTANCE_ID}" || {
            log_warn "Timeout waiting for RDS deletion or database may already be deleted"
        }
        
        # Delete DB subnet group
        aws rds delete-db-subnet-group \
            --db-subnet-group-name "${DB_INSTANCE_ID}-subnet-group" &> /dev/null || {
            log_warn "Failed to delete DB subnet group or it may already be deleted"
        }
        
        log_success "RDS database and subnet group deleted"
    else
        log_warn "Database Instance ID not found, skipping..."
    fi
}

cleanup_iam_resources() {
    log_info "Removing IAM roles and policies..."
    
    ROLE_NAME="${ROLE_NAME:-DatabaseAccessRole-${RANDOM_SUFFIX}}"
    
    # Delete IAM role policy
    aws iam delete-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name DatabaseAccessPolicy &> /dev/null || {
        log_warn "Failed to delete IAM role policy or it may already be deleted"
    }
    
    # Delete IAM role
    aws iam delete-role \
        --role-name "${ROLE_NAME}" &> /dev/null || {
        log_warn "Failed to delete IAM role or it may already be deleted"
    }
    
    log_success "IAM resources deleted"
}

cleanup_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    DASHBOARD_NAME="${DASHBOARD_NAME:-DatabaseSharingMonitoring-${RANDOM_SUFFIX}}"
    aws cloudwatch delete-dashboards \
        --dashboard-names "${DASHBOARD_NAME}" &> /dev/null || {
        log_warn "Failed to delete CloudWatch dashboard or it may already be deleted"
    }
    
    # Delete log group
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
        aws logs delete-log-group \
            --log-group-name "/aws/vpc-lattice/servicenetwork/${SERVICE_NETWORK_ID}" &> /dev/null || {
            log_warn "Failed to delete CloudWatch log group or it may already be deleted"
        }
    fi
    
    log_success "CloudWatch resources deleted"
}

cleanup_security_groups() {
    log_info "Removing security groups..."
    
    # Delete RDS security group
    if [[ -n "${DB_SECURITY_GROUP:-}" ]]; then
        aws ec2 delete-security-group \
            --group-id "${DB_SECURITY_GROUP}" &> /dev/null || {
            log_warn "Failed to delete RDS security group or it may already be deleted"
        }
    fi
    
    # Delete gateway security group
    if [[ -n "${GATEWAY_SECURITY_GROUP:-}" ]]; then
        aws ec2 delete-security-group \
            --group-id "${GATEWAY_SECURITY_GROUP}" &> /dev/null || {
            log_warn "Failed to delete gateway security group or it may already be deleted"
        }
    fi
    
    log_success "Security groups deleted"
}

cleanup_vpc_resources() {
    log_info "Removing VPC and networking resources..."
    
    if [[ -n "${VPC_ID:-}" ]]; then
        # Delete subnets
        for subnet in "${SUBNET_A:-}" "${SUBNET_B:-}" "${GATEWAY_SUBNET:-}"; do
            if [[ -n "${subnet}" ]]; then
                aws ec2 delete-subnet --subnet-id "${subnet}" &> /dev/null || {
                    log_warn "Failed to delete subnet ${subnet} or it may already be deleted"
                }
            fi
        done
        
        # Detach and delete internet gateway
        if [[ -n "${IGW_ID:-}" ]]; then
            aws ec2 detach-internet-gateway \
                --vpc-id "${VPC_ID}" \
                --internet-gateway-id "${IGW_ID}" &> /dev/null || {
                log_warn "Failed to detach internet gateway or it may already be detached"
            }
            
            aws ec2 delete-internet-gateway \
                --internet-gateway-id "${IGW_ID}" &> /dev/null || {
                log_warn "Failed to delete internet gateway or it may already be deleted"
            }
        fi
        
        # Delete VPC
        aws ec2 delete-vpc --vpc-id "${VPC_ID}" &> /dev/null || {
            log_warn "Failed to delete VPC or it may already be deleted"
        }
        
        log_success "VPC and networking resources deleted"
    else
        log_warn "VPC ID not found, skipping VPC cleanup..."
    fi
}

cleanup_temporary_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary JSON files
    rm -f "${SCRIPT_DIR}"/*.json
    
    # Ask user if they want to remove state file
    if [[ "${FORCE_CLEANUP:-}" != "true" ]]; then
        echo
        echo -n "Remove deployment state file? (yes/no): "
        read -r REMOVE_STATE
        
        if [[ "${REMOVE_STATE,,}" == "yes" ]]; then
            rm -f "${STATE_FILE}"
            log_success "Deployment state file removed"
        else
            log_info "Deployment state file preserved: ${STATE_FILE}"
        fi
    fi
    
    log_success "Temporary files cleaned up"
}

#=============================================================================
# Verification
#=============================================================================

verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local failed_cleanups=()
    
    # Check if service network still exists
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
        if aws vpc-lattice get-service-network \
            --service-network-identifier "${SERVICE_NETWORK_ID}" &> /dev/null; then
            failed_cleanups+=("Service Network: ${SERVICE_NETWORK_ID}")
        fi
    fi
    
    # Check if RDS instance still exists
    if [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        if aws rds describe-db-instances \
            --db-instance-identifier "${DB_INSTANCE_ID}" &> /dev/null; then
            failed_cleanups+=("RDS Instance: ${DB_INSTANCE_ID}")
        fi
    fi
    
    # Check if IAM role still exists
    ROLE_NAME="${ROLE_NAME:-DatabaseAccessRole-${RANDOM_SUFFIX}}"
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        failed_cleanups+=("IAM Role: ${ROLE_NAME}")
    fi
    
    # Check if VPC still exists
    if [[ -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" &> /dev/null; then
            failed_cleanups+=("VPC: ${VPC_ID}")
        fi
    fi
    
    if [[ ${#failed_cleanups[@]} -eq 0 ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warn "Some resources may not have been fully cleaned up:"
        for resource in "${failed_cleanups[@]}"; do
            log_warn "- ${resource}"
        done
        log_warn "Please check the AWS Console and clean up manually if needed"
    fi
}

#=============================================================================
# Main Cleanup Function
#=============================================================================

main() {
    log_info "==================================================================="
    log_info "AWS Cross-Account Database Sharing with VPC Lattice and RDS"
    log_info "Cleanup started at: $(date)"
    log_info "==================================================================="
    
    load_deployment_state
    check_prerequisites
    confirm_cleanup
    
    log_info "Starting resource cleanup (this may take 15-20 minutes)..."
    
    # Cleanup in reverse order of creation
    cleanup_aws_ram_share
    cleanup_resource_configuration
    cleanup_service_network
    cleanup_resource_gateway
    cleanup_rds_database
    cleanup_iam_resources
    cleanup_cloudwatch_resources
    cleanup_security_groups
    cleanup_vpc_resources
    cleanup_temporary_files
    
    verify_cleanup
    
    log_info "==================================================================="
    log_success "Cleanup completed!"
    log_info "==================================================================="
    
    echo
    log_info "Cleanup Summary:"
    log_info "- All VPC Lattice resources have been removed"
    log_info "- RDS database has been deleted"
    log_info "- IAM roles and policies have been removed"
    log_info "- VPC and networking resources have been cleaned up"
    log_info "- CloudWatch monitoring resources have been removed"
    echo
    log_info "Next Steps:"
    log_info "- Verify that Account B no longer has access to shared resources"
    log_info "- Check AWS billing to ensure resources are no longer incurring charges"
    log_info "- Review CloudTrail logs for audit purposes if needed"
    echo
    log_info "Log file saved to: ${LOG_FILE}"
}

# Handle script arguments
case "${1:-}" in
    --force)
        export FORCE_CLEANUP="true"
        log_info "Force cleanup mode enabled"
        ;;
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts and force cleanup"
        echo "  --help     Show this help message"
        echo ""
        echo "This script removes all resources created by the deployment script."
        echo "It requires the deployment_state.env file to be present."
        exit 0
        ;;
esac

# Execute main function
main "$@"