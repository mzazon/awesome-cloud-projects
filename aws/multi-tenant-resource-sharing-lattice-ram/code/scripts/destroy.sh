#!/bin/bash

# Multi-Tenant Resource Sharing with VPC Lattice and RAM - Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper dependency ordering and confirmation prompts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Script metadata
SCRIPT_NAME="Multi-Tenant VPC Lattice Cleanup"
SCRIPT_VERSION="1.0"
RECIPE_ID="f7e9d2a8"

log "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION} (Recipe ID: ${RECIPE_ID})"

# Global variables for tracking resources
DEPLOYMENT_ID=""
AWS_REGION=""
AWS_ACCOUNT_ID=""
VPC_ID=""
SERVICE_NETWORK_ID=""
SERVICE_NETWORK_ARN=""
RDS_INSTANCE_ID=""
RDS_ENDPOINT=""
RAM_SHARE_NAME=""
RESOURCE_SHARE_ARN=""
RESOURCE_CONFIG_ID=""
SG_ID=""
VPC_ASSOCIATION_ARN=""
RESOURCE_ASSOC_ARN=""
CLEANUP_MODE="interactive"  # interactive, auto, or dry-run

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --deployment-id)
                DEPLOYMENT_ID="$2"
                shift 2
                ;;
            --auto)
                CLEANUP_MODE="auto"
                shift
                ;;
            --dry-run)
                CLEANUP_MODE="dry-run"
                shift
                ;;
            --state-file)
                STATE_FILE="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --deployment-id ID     Specify deployment ID to clean up"
    echo "  --auto                 Run in automatic mode (no prompts)"
    echo "  --dry-run             Show what would be deleted without actually deleting"
    echo "  --state-file FILE     Load deployment state from specific file"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --deployment-id abc123            # Clean specific deployment"
    echo "  $0 --auto                           # Automatic cleanup"
    echo "  $0 --dry-run                        # Preview cleanup actions"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    # Set AWS region and account
    AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION="us-east-1"
        warning "No AWS region configured, defaulting to us-east-1"
    fi
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Check for state file
    local state_files=()
    
    if [[ -n "${STATE_FILE:-}" ]] && [[ -f "${STATE_FILE}" ]]; then
        state_files+=("${STATE_FILE}")
    elif [[ -n "${DEPLOYMENT_ID}" ]]; then
        # Look for state file with specific deployment ID
        local potential_file="/tmp/lattice-deployment-state-${DEPLOYMENT_ID}.json"
        if [[ -f "${potential_file}" ]]; then
            state_files+=("${potential_file}")
        fi
    else
        # Look for any deployment state files
        while IFS= read -r -d '' file; do
            state_files+=("$file")
        done < <(find /tmp -name "lattice-deployment-state-*.json" -print0 2>/dev/null || true)
    fi
    
    if [[ ${#state_files[@]} -eq 0 ]]; then
        warning "No deployment state files found. Will attempt to discover resources."
        return 1
    elif [[ ${#state_files[@]} -gt 1 ]] && [[ "${CLEANUP_MODE}" == "interactive" ]]; then
        log "Multiple deployment state files found:"
        for i in "${!state_files[@]}"; do
            echo "  $((i+1)). ${state_files[i]}"
        done
        
        read -p "Select state file (1-${#state_files[@]}): " selection
        if [[ "${selection}" =~ ^[0-9]+$ ]] && [[ "${selection}" -ge 1 ]] && [[ "${selection}" -le ${#state_files[@]} ]]; then
            STATE_FILE="${state_files[$((selection-1))]}"
        else
            error "Invalid selection"
        fi
    else
        STATE_FILE="${state_files[0]}"
    fi
    
    # Load state from file
    if [[ -f "${STATE_FILE}" ]]; then
        log "Loading state from: ${STATE_FILE}"
        
        if ! command -v jq &> /dev/null; then
            error "jq is required to parse state file. Please install jq."
        fi
        
        DEPLOYMENT_ID=$(jq -r '.deployment_id // empty' "${STATE_FILE}")
        VPC_ID=$(jq -r '.vpc_id // empty' "${STATE_FILE}")
        SERVICE_NETWORK_ID=$(jq -r '.service_network_id // empty' "${STATE_FILE}")
        SERVICE_NETWORK_ARN=$(jq -r '.service_network_arn // empty' "${STATE_FILE}")
        RDS_INSTANCE_ID=$(jq -r '.rds_instance_id // empty' "${STATE_FILE}")
        RDS_ENDPOINT=$(jq -r '.rds_endpoint // empty' "${STATE_FILE}")
        RAM_SHARE_NAME=$(jq -r '.ram_share_name // empty' "${STATE_FILE}")
        RESOURCE_SHARE_ARN=$(jq -r '.resource_share_arn // empty' "${STATE_FILE}")
        RESOURCE_CONFIG_ID=$(jq -r '.resource_config_id // empty' "${STATE_FILE}")
        SG_ID=$(jq -r '.security_group_id // empty' "${STATE_FILE}")
        VPC_ASSOCIATION_ARN=$(jq -r '.vpc_association_arn // empty' "${STATE_FILE}")
        RESOURCE_ASSOC_ARN=$(jq -r '.resource_assoc_arn // empty' "${STATE_FILE}")
        
        success "Deployment state loaded (ID: ${DEPLOYMENT_ID})"
        return 0
    else
        error "State file not found: ${STATE_FILE}"
    fi
}

# Discover resources if no state file
discover_resources() {
    log "Attempting to discover resources..."
    
    if [[ -z "${DEPLOYMENT_ID}" ]]; then
        if [[ "${CLEANUP_MODE}" == "interactive" ]]; then
            read -p "Enter deployment ID (6-character suffix): " DEPLOYMENT_ID
            if [[ -z "${DEPLOYMENT_ID}" ]]; then
                error "Deployment ID is required for resource discovery"
            fi
        else
            error "Deployment ID is required for resource discovery in non-interactive mode"
        fi
    fi
    
    # Discover service networks
    local networks=$(aws vpc-lattice list-service-networks \
        --query "items[?contains(name, '${DEPLOYMENT_ID}')].{name:name,id:id}" \
        --output json 2>/dev/null || echo '[]')
    
    if [[ "${networks}" != "[]" ]] && [[ $(echo "${networks}" | jq length) -gt 0 ]]; then
        SERVICE_NETWORK_ID=$(echo "${networks}" | jq -r '.[0].id')
        local network_name=$(echo "${networks}" | jq -r '.[0].name')
        SERVICE_NETWORK_ARN="arn:aws:vpc-lattice:${AWS_REGION}:${AWS_ACCOUNT_ID}:servicenetwork/${SERVICE_NETWORK_ID}"
        log "Found service network: ${network_name} (${SERVICE_NETWORK_ID})"
    fi
    
    # Discover RDS instances
    local rds_instances=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${DEPLOYMENT_ID}')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${rds_instances}" ]]; then
        RDS_INSTANCE_ID=$(echo "${rds_instances}" | head -n1)
        log "Found RDS instance: ${RDS_INSTANCE_ID}"
    fi
    
    # Discover RAM shares
    local ram_shares=$(aws ram get-resource-shares \
        --resource-owner SELF \
        --query "resourceShares[?contains(name, '${DEPLOYMENT_ID}')].{name:name,arn:resourceShareArn}" \
        --output json 2>/dev/null || echo '[]')
    
    if [[ "${ram_shares}" != "[]" ]] && [[ $(echo "${ram_shares}" | jq length) -gt 0 ]]; then
        RESOURCE_SHARE_ARN=$(echo "${ram_shares}" | jq -r '.[0].arn')
        RAM_SHARE_NAME=$(echo "${ram_shares}" | jq -r '.[0].name')
        log "Found RAM share: ${RAM_SHARE_NAME}"
    fi
    
    success "Resource discovery completed"
}

# Confirm cleanup
confirm_cleanup() {
    if [[ "${CLEANUP_MODE}" == "dry-run" ]]; then
        info "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    if [[ "${CLEANUP_MODE}" == "auto" ]]; then
        warning "Running in automatic mode - no confirmation prompts"
        return 0
    fi
    
    echo
    warning "This will delete the following resources:"
    echo "  - Service Network: ${SERVICE_NETWORK_ID:-not found}"
    echo "  - RDS Instance: ${RDS_INSTANCE_ID:-not found}"
    echo "  - RAM Share: ${RAM_SHARE_NAME:-not found}"
    echo "  - IAM Roles: TeamA/TeamB-DatabaseAccess-${DEPLOYMENT_ID:-unknown}"
    echo "  - CloudTrail: VPCLatticeAuditTrail-${DEPLOYMENT_ID:-unknown}"
    echo "  - Security Groups and other supporting resources"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    if [[ "${confirmation,,}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "${CLEANUP_MODE}" == "dry-run" ]]; then
        info "[DRY RUN] Would execute: ${description}"
        echo "  Command: ${cmd}"
    else
        log "${description}"
        eval "${cmd}" || warning "Command failed: ${cmd}"
    fi
}

# Remove CloudTrail and S3 bucket
cleanup_cloudtrail() {
    log "Cleaning up CloudTrail resources..."
    
    local trail_name="VPCLatticeAuditTrail-${DEPLOYMENT_ID}"
    local bucket_name="lattice-audit-logs-${DEPLOYMENT_ID}"
    
    # Check if trail exists
    if aws cloudtrail describe-trails --trail-name-list "${trail_name}" &> /dev/null; then
        execute_cmd "aws cloudtrail stop-logging --name '${trail_name}'" \
                   "Stopping CloudTrail logging"
        
        execute_cmd "aws cloudtrail delete-trail --name '${trail_name}'" \
                   "Deleting CloudTrail"
        
        success "CloudTrail deleted: ${trail_name}"
    else
        info "CloudTrail not found: ${trail_name}"
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "${bucket_name}" &> /dev/null; then
        execute_cmd "aws s3 rm s3://${bucket_name} --recursive" \
                   "Emptying S3 bucket"
        
        execute_cmd "aws s3api delete-bucket --bucket '${bucket_name}'" \
                   "Deleting S3 bucket"
        
        success "S3 bucket deleted: ${bucket_name}"
    else
        info "S3 bucket not found: ${bucket_name}"
    fi
}

# Remove IAM roles
cleanup_iam_roles() {
    log "Cleaning up IAM roles..."
    
    local roles=("TeamA-DatabaseAccess-${DEPLOYMENT_ID}" 
                 "TeamB-DatabaseAccess-${DEPLOYMENT_ID}" 
                 "VPCLatticeServiceRole-${DEPLOYMENT_ID}")
    
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "${role}" &> /dev/null; then
            # Detach managed policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "${role}" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${attached_policies}" ]]; then
                for policy in ${attached_policies}; do
                    execute_cmd "aws iam detach-role-policy --role-name '${role}' --policy-arn '${policy}'" \
                               "Detaching policy from role ${role}"
                done
            fi
            
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies \
                --role-name "${role}" \
                --query 'PolicyNames' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "${inline_policies}" ]] && [[ "${inline_policies}" != "None" ]]; then
                for policy in ${inline_policies}; do
                    execute_cmd "aws iam delete-role-policy --role-name '${role}' --policy-name '${policy}'" \
                               "Deleting inline policy from role ${role}"
                done
            fi
            
            execute_cmd "aws iam delete-role --role-name '${role}'" \
                       "Deleting IAM role"
            
            success "IAM role deleted: ${role}"
        else
            info "IAM role not found: ${role}"
        fi
    done
}

# Remove AWS RAM resource share
cleanup_ram_share() {
    log "Cleaning up AWS RAM resource share..."
    
    if [[ -n "${RESOURCE_SHARE_ARN}" ]]; then
        execute_cmd "aws ram delete-resource-share --resource-share-arn '${RESOURCE_SHARE_ARN}'" \
                   "Deleting RAM resource share"
        
        success "AWS RAM resource share deleted"
    else
        info "No RAM resource share ARN found"
    fi
}

# Remove VPC Lattice resources
cleanup_vpc_lattice() {
    log "Cleaning up VPC Lattice resources..."
    
    if [[ -z "${SERVICE_NETWORK_ID}" ]]; then
        info "No service network ID found, skipping VPC Lattice cleanup"
        return
    fi
    
    # Remove auth policy
    execute_cmd "aws vpc-lattice delete-auth-policy --resource-identifier '${SERVICE_NETWORK_ID}' || true" \
               "Removing authentication policy"
    
    # Remove resource configuration association
    if [[ -n "${RESOURCE_CONFIG_ID}" ]]; then
        execute_cmd "aws vpc-lattice delete-resource-configuration-association \
                    --resource-configuration-identifier '${RESOURCE_CONFIG_ID}' \
                    --service-network-identifier '${SERVICE_NETWORK_ID}' || true" \
                   "Removing resource configuration association"
        
        # Wait for disassociation
        if [[ "${CLEANUP_MODE}" != "dry-run" ]]; then
            log "Waiting for resource configuration disassociation..."
            sleep 30
        fi
        
        # Delete resource configuration
        execute_cmd "aws vpc-lattice delete-resource-configuration \
                    --resource-configuration-identifier '${RESOURCE_CONFIG_ID}' || true" \
                   "Deleting resource configuration"
    fi
    
    # Remove VPC association
    if [[ -n "${VPC_ASSOCIATION_ARN}" ]]; then
        execute_cmd "aws vpc-lattice delete-service-network-vpc-association \
                    --service-network-vpc-association-identifier '${VPC_ASSOCIATION_ARN}' || true" \
                   "Removing VPC association"
        
        # Wait for VPC disassociation
        if [[ "${CLEANUP_MODE}" != "dry-run" ]]; then
            log "Waiting for VPC disassociation..."
            sleep 30
        fi
    fi
    
    # Delete service network
    execute_cmd "aws vpc-lattice delete-service-network \
                --service-network-identifier '${SERVICE_NETWORK_ID}' || true" \
               "Deleting service network"
    
    success "VPC Lattice resources cleaned up"
}

# Remove RDS and related resources
cleanup_rds_resources() {
    log "Cleaning up RDS and related resources..."
    
    if [[ -n "${RDS_INSTANCE_ID}" ]]; then
        # Check if RDS instance exists
        if aws rds describe-db-instances --db-instance-identifier "${RDS_INSTANCE_ID}" &> /dev/null; then
            execute_cmd "aws rds delete-db-instance \
                        --db-instance-identifier '${RDS_INSTANCE_ID}' \
                        --skip-final-snapshot" \
                       "Deleting RDS instance"
            
            # Wait for RDS deletion in non-dry-run mode
            if [[ "${CLEANUP_MODE}" != "dry-run" ]]; then
                log "Waiting for RDS instance deletion (this may take 5-10 minutes)..."
                aws rds wait db-instance-deleted --db-instance-identifier "${RDS_INSTANCE_ID}" || warning "RDS deletion wait failed"
            fi
            
            success "RDS instance deleted: ${RDS_INSTANCE_ID}"
        else
            info "RDS instance not found: ${RDS_INSTANCE_ID}"
        fi
    fi
    
    # Delete security group
    if [[ -n "${SG_ID}" ]]; then
        execute_cmd "aws ec2 delete-security-group --group-id '${SG_ID}' || true" \
                   "Deleting security group"
        success "Security group deleted: ${SG_ID}"
    fi
    
    # Delete DB subnet group
    local subnet_group_name="shared-db-subnet-${DEPLOYMENT_ID}"
    if aws rds describe-db-subnet-groups --db-subnet-group-name "${subnet_group_name}" &> /dev/null; then
        execute_cmd "aws rds delete-db-subnet-group \
                    --db-subnet-group-name '${subnet_group_name}'" \
                   "Deleting DB subnet group"
        success "DB subnet group deleted: ${subnet_group_name}"
    else
        info "DB subnet group not found: ${subnet_group_name}"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/auth-policy.json"
        "/tmp/bucket-policy.json"
        "/tmp/lattice-deployment-state-${DEPLOYMENT_ID}.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            execute_cmd "rm -f '${file}'" "Removing temporary file: ${file}"
        fi
    done
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "${CLEANUP_MODE}" == "dry-run" ]]; then
        return 0
    fi
    
    log "Verifying cleanup completion..."
    
    local remaining_resources=()
    
    # Check service network
    if [[ -n "${SERVICE_NETWORK_ID}" ]]; then
        if aws vpc-lattice get-service-network --service-network-identifier "${SERVICE_NETWORK_ID}" &> /dev/null; then
            remaining_resources+=("Service Network: ${SERVICE_NETWORK_ID}")
        fi
    fi
    
    # Check RDS instance
    if [[ -n "${RDS_INSTANCE_ID}" ]]; then
        if aws rds describe-db-instances --db-instance-identifier "${RDS_INSTANCE_ID}" &> /dev/null; then
            remaining_resources+=("RDS Instance: ${RDS_INSTANCE_ID}")
        fi
    fi
    
    # Check RAM share
    if [[ -n "${RESOURCE_SHARE_ARN}" ]]; then
        if aws ram get-resource-share --resource-share-arn "${RESOURCE_SHARE_ARN}" &> /dev/null; then
            remaining_resources+=("RAM Share: ${RAM_SHARE_NAME}")
        fi
    fi
    
    if [[ ${#remaining_resources[@]} -gt 0 ]]; then
        warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            echo "  - ${resource}"
        done
        warning "These resources may take additional time to delete or may require manual cleanup."
    else
        success "All tracked resources have been successfully deleted"
    fi
}

# Cleanup summary
cleanup_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Deployment ID: ${DEPLOYMENT_ID}"
    echo "Cleanup Mode: ${CLEANUP_MODE}"
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account: ${AWS_ACCOUNT_ID}"
    echo "===================="
    
    if [[ "${CLEANUP_MODE}" == "dry-run" ]]; then
        info "DRY RUN completed - no resources were actually deleted"
    else
        success "Multi-tenant resource sharing architecture cleanup completed!"
    fi
    
    if [[ -f "${STATE_FILE:-}" ]]; then
        log "Consider removing state file: ${STATE_FILE}"
    fi
}

# Main cleanup function
main() {
    parse_args "$@"
    
    log "Starting multi-tenant resource sharing cleanup..."
    
    check_prerequisites
    
    # Try to load deployment state, fallback to discovery
    if ! load_deployment_state; then
        discover_resources
    fi
    
    confirm_cleanup
    
    # Execute cleanup in proper order (reverse of deployment)
    cleanup_cloudtrail
    cleanup_iam_roles
    cleanup_ram_share
    cleanup_vpc_lattice
    cleanup_rds_resources
    cleanup_temp_files
    
    verify_cleanup
    cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may still exist. Re-run the script to continue cleanup."' INT TERM

# Run main function
main "$@"