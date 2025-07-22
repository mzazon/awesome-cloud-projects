#!/bin/bash

# Cleanup script for Network Micro-Segmentation with NACLs and Advanced Security Groups
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/microseg-destroy-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR="/tmp/microseg-destroy-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
FORCE_CLEANUP=false
DRY_RUN=false

# Logging function
log() {
    echo -e "${2:-$NC}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

# Success message
success() {
    log "SUCCESS: $1" "$GREEN"
}

# Warning message
warn() {
    log "WARNING: $1" "$YELLOW"
}

# Info message
info() {
    log "INFO: $1" "$BLUE"
}

# Confirmation function
confirm() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        return 0
    fi
    
    local message="$1"
    local default="${2:-n}"
    
    echo -e "${YELLOW}$message${NC}"
    if [[ "$default" == "y" ]]; then
        read -p "Continue? [Y/n]: " -n 1 -r
    else
        read -p "Continue? [y/N]: " -n 1 -r
    fi
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "vpc")
            aws ec2 describe-vpcs --vpc-ids "$resource_id" &>/dev/null
            ;;
        "subnet")
            aws ec2 describe-subnets --subnet-ids "$resource_id" &>/dev/null
            ;;
        "nacl")
            aws ec2 describe-network-acls --network-acl-ids "$resource_id" &>/dev/null
            ;;
        "sg")
            aws ec2 describe-security-groups --group-ids "$resource_id" &>/dev/null
            ;;
        "igw")
            aws ec2 describe-internet-gateways --internet-gateway-ids "$resource_id" &>/dev/null
            ;;
        "route-table")
            aws ec2 describe-route-tables --route-table-ids "$resource_id" &>/dev/null
            ;;
        "flow-logs")
            aws ec2 describe-flow-logs --flow-log-ids "$resource_id" &>/dev/null
            ;;
        "key-pair")
            aws ec2 describe-key-pairs --key-names "$resource_id" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_id" &>/dev/null
            ;;
        "log-group")
            aws logs describe-log-groups --log-group-name-prefix "$resource_id" --query 'logGroups[?logGroupName==`'"$resource_id"'`]' --output text | grep -q .
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_id" &>/dev/null
            ;;
        *)
            error_exit "Unknown resource type: $resource_type"
            ;;
    esac
}

# Load environment variables
load_environment() {
    info "Loading environment variables..."
    
    # Try to load from saved environment file
    if [[ -f "$SCRIPT_DIR/microseg-environment.sh" ]]; then
        source "$SCRIPT_DIR/microseg-environment.sh"
        info "Loaded environment from $SCRIPT_DIR/microseg-environment.sh"
    else
        warn "Environment file not found. Attempting to discover resources..."
        
        # Try to discover VPC by tags
        export VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Purpose,Values=microsegmentation" \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
        
        if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
            error_exit "Could not find VPC. Please ensure the deployment was completed or provide the VPC ID manually."
        fi
        
        info "Found VPC: $VPC_ID"
        
        # Set basic environment variables
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to discover other resources
        discover_resources
    fi
    
    # Verify required variables
    if [[ -z "${VPC_ID:-}" ]]; then
        error_exit "VPC_ID is not set. Cannot proceed with cleanup."
    fi
    
    success "Environment variables loaded successfully"
}

# Discover resources when environment file is not available
discover_resources() {
    info "Discovering resources by tags and relationships..."
    
    # Discover subnets
    export DMZ_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=dmz" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
    
    export WEB_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=web" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
    
    export APP_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=app" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
    
    export DB_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=database" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
    
    export MGMT_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=management" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
    
    export MON_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=monitoring" \
        --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
    
    # Discover NACLs
    export DMZ_NACL_ID=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=dmz" \
        --query 'NetworkAcls[0].NetworkAclId' --output text 2>/dev/null || echo "")
    
    export WEB_NACL_ID=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=web" \
        --query 'NetworkAcls[0].NetworkAclId' --output text 2>/dev/null || echo "")
    
    export APP_NACL_ID=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=app" \
        --query 'NetworkAcls[0].NetworkAclId' --output text 2>/dev/null || echo "")
    
    export DB_NACL_ID=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=database" \
        --query 'NetworkAcls[0].NetworkAclId' --output text 2>/dev/null || echo "")
    
    export MGMT_NACL_ID=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=management" \
        --query 'NetworkAcls[0].NetworkAclId' --output text 2>/dev/null || echo "")
    
    export MON_NACL_ID=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=monitoring" \
        --query 'NetworkAcls[0].NetworkAclId' --output text 2>/dev/null || echo "")
    
    # Discover Security Groups
    export DMZ_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=dmz" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    export WEB_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=web" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    export APP_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=app" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    export DB_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=database" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    export MGMT_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Zone,Values=management" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    
    # Discover Internet Gateway
    export IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
    
    # Discover Route Tables
    export PUBLIC_RT_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=public-rt" \
        --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "")
    
    # Discover Flow Logs
    export FLOW_LOG_ID=$(aws ec2 describe-flow-logs \
        --filters "Name=resource-id,Values=$VPC_ID" \
        --query 'FlowLogs[0].FlowLogId' --output text 2>/dev/null || echo "")
    
    # Discover Key Pairs (this is more difficult, so we'll skip it)
    export KEY_PAIR_NAME=""
    
    info "Resource discovery completed"
}

# Create temporary directory
create_temp_dir() {
    mkdir -p "$TEMP_DIR"
    info "Created temporary directory: $TEMP_DIR"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check passed"
}

# Remove VPC Flow Logs and CloudWatch resources
remove_flow_logs_and_monitoring() {
    info "Removing VPC Flow Logs and CloudWatch monitoring resources..."
    
    # Delete Flow Logs
    if [[ -n "${FLOW_LOG_ID:-}" && "$FLOW_LOG_ID" != "None" ]]; then
        if resource_exists "flow-logs" "$FLOW_LOG_ID"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete Flow Logs: $FLOW_LOG_ID"
            else
                aws ec2 delete-flow-logs --flow-log-ids "$FLOW_LOG_ID" || warn "Failed to delete Flow Logs"
                info "Deleted Flow Logs: $FLOW_LOG_ID"
            fi
        else
            warn "Flow Logs $FLOW_LOG_ID not found"
        fi
    fi
    
    # Delete CloudWatch alarms
    if resource_exists "cloudwatch-alarm" "VPC-Rejected-Traffic-High"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete CloudWatch alarm: VPC-Rejected-Traffic-High"
        else
            aws cloudwatch delete-alarms --alarm-names "VPC-Rejected-Traffic-High" || warn "Failed to delete CloudWatch alarm"
            info "Deleted CloudWatch alarm: VPC-Rejected-Traffic-High"
        fi
    fi
    
    # Delete CloudWatch Log Group
    if resource_exists "log-group" "/aws/vpc/microsegmentation/flowlogs"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete CloudWatch Log Group: /aws/vpc/microsegmentation/flowlogs"
        else
            aws logs delete-log-group --log-group-name "/aws/vpc/microsegmentation/flowlogs" || warn "Failed to delete CloudWatch Log Group"
            info "Deleted CloudWatch Log Group: /aws/vpc/microsegmentation/flowlogs"
        fi
    fi
    
    # Delete IAM role and policies
    if resource_exists "iam-role" "VPCFlowLogsRole"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete IAM role: VPCFlowLogsRole"
        else
            aws iam detach-role-policy \
                --role-name VPCFlowLogsRole \
                --policy-arn arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy || warn "Failed to detach IAM policy"
            
            aws iam delete-role --role-name VPCFlowLogsRole || warn "Failed to delete IAM role"
            info "Deleted IAM role: VPCFlowLogsRole"
        fi
    fi
    
    success "Monitoring and logging resources removed"
}

# Remove security groups
remove_security_groups() {
    info "Removing security groups..."
    
    # List of security group IDs to delete (order matters due to dependencies)
    local security_groups=(
        "$DB_SG_ID"
        "$APP_SG_ID"
        "$WEB_SG_ID"
        "$DMZ_SG_ID"
        "$MGMT_SG_ID"
    )
    
    local security_group_names=(
        "Database Security Group"
        "Application Security Group"
        "Web Security Group"
        "DMZ Security Group"
        "Management Security Group"
    )
    
    for i in "${!security_groups[@]}"; do
        local sg_id="${security_groups[$i]}"
        local sg_name="${security_group_names[$i]}"
        
        if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
            if resource_exists "sg" "$sg_id"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY RUN] Would delete $sg_name: $sg_id"
                else
                    # Remove all rules first to avoid dependency issues
                    aws ec2 describe-security-groups --group-ids "$sg_id" --query 'SecurityGroups[0].IpPermissions' --output json > "$TEMP_DIR/sg-rules-$sg_id.json" 2>/dev/null || true
                    
                    if [[ -s "$TEMP_DIR/sg-rules-$sg_id.json" ]]; then
                        aws ec2 revoke-security-group-ingress --group-id "$sg_id" --ip-permissions file://"$TEMP_DIR/sg-rules-$sg_id.json" 2>/dev/null || true
                    fi
                    
                    aws ec2 delete-security-group --group-id "$sg_id" || warn "Failed to delete $sg_name"
                    info "Deleted $sg_name: $sg_id"
                fi
            else
                warn "$sg_name $sg_id not found"
            fi
        fi
    done
    
    success "Security groups removed"
}

# Remove NACL associations and delete custom NACLs
remove_nacls() {
    info "Removing NACL associations and deleting custom NACLs..."
    
    # Get default NACL ID for re-association
    local default_nacl_id=$(aws ec2 describe-network-acls \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
        --query 'NetworkAcls[0].NetworkAclId' --output text 2>/dev/null || echo "")
    
    if [[ -z "$default_nacl_id" || "$default_nacl_id" == "None" ]]; then
        warn "Could not find default NACL. Skipping NACL re-association."
    else
        # Re-associate subnets with default NACL
        local subnets=(
            "$DMZ_SUBNET_ID"
            "$WEB_SUBNET_ID"
            "$APP_SUBNET_ID"
            "$DB_SUBNET_ID"
            "$MGMT_SUBNET_ID"
            "$MON_SUBNET_ID"
        )
        
        for subnet_id in "${subnets[@]}"; do
            if [[ -n "$subnet_id" && "$subnet_id" != "None" ]]; then
                if resource_exists "subnet" "$subnet_id"; then
                    if [[ "$DRY_RUN" == "true" ]]; then
                        info "[DRY RUN] Would re-associate subnet $subnet_id with default NACL"
                    else
                        aws ec2 associate-network-acl \
                            --network-acl-id "$default_nacl_id" \
                            --subnet-id "$subnet_id" 2>/dev/null || warn "Failed to re-associate subnet $subnet_id"
                        info "Re-associated subnet $subnet_id with default NACL"
                    fi
                fi
            fi
        done
    fi
    
    # Delete custom NACLs
    local nacls=(
        "$DMZ_NACL_ID"
        "$WEB_NACL_ID"
        "$APP_NACL_ID"
        "$DB_NACL_ID"
        "$MGMT_NACL_ID"
        "$MON_NACL_ID"
    )
    
    local nacl_names=(
        "DMZ NACL"
        "Web NACL"
        "App NACL"
        "Database NACL"
        "Management NACL"
        "Monitoring NACL"
    )
    
    for i in "${!nacls[@]}"; do
        local nacl_id="${nacls[$i]}"
        local nacl_name="${nacl_names[$i]}"
        
        if [[ -n "$nacl_id" && "$nacl_id" != "None" ]]; then
            if resource_exists "nacl" "$nacl_id"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY RUN] Would delete $nacl_name: $nacl_id"
                else
                    aws ec2 delete-network-acl --network-acl-id "$nacl_id" || warn "Failed to delete $nacl_name"
                    info "Deleted $nacl_name: $nacl_id"
                fi
            else
                warn "$nacl_name $nacl_id not found"
            fi
        fi
    done
    
    success "Custom NACLs removed and default associations restored"
}

# Remove subnets
remove_subnets() {
    info "Removing subnets..."
    
    local subnets=(
        "$DMZ_SUBNET_ID"
        "$WEB_SUBNET_ID"
        "$APP_SUBNET_ID"
        "$DB_SUBNET_ID"
        "$MGMT_SUBNET_ID"
        "$MON_SUBNET_ID"
    )
    
    local subnet_names=(
        "DMZ Subnet"
        "Web Subnet"
        "App Subnet"
        "Database Subnet"
        "Management Subnet"
        "Monitoring Subnet"
    )
    
    for i in "${!subnets[@]}"; do
        local subnet_id="${subnets[$i]}"
        local subnet_name="${subnet_names[$i]}"
        
        if [[ -n "$subnet_id" && "$subnet_id" != "None" ]]; then
            if resource_exists "subnet" "$subnet_id"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY RUN] Would delete $subnet_name: $subnet_id"
                else
                    aws ec2 delete-subnet --subnet-id "$subnet_id" || warn "Failed to delete $subnet_name"
                    info "Deleted $subnet_name: $subnet_id"
                fi
            else
                warn "$subnet_name $subnet_id not found"
            fi
        fi
    done
    
    success "Subnets removed"
}

# Remove route tables
remove_route_tables() {
    info "Removing route tables..."
    
    if [[ -n "${PUBLIC_RT_ID:-}" && "$PUBLIC_RT_ID" != "None" ]]; then
        if resource_exists "route-table" "$PUBLIC_RT_ID"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete public route table: $PUBLIC_RT_ID"
            else
                aws ec2 delete-route-table --route-table-id "$PUBLIC_RT_ID" || warn "Failed to delete public route table"
                info "Deleted public route table: $PUBLIC_RT_ID"
            fi
        else
            warn "Public route table $PUBLIC_RT_ID not found"
        fi
    fi
    
    success "Route tables removed"
}

# Remove Internet Gateway
remove_internet_gateway() {
    info "Removing Internet Gateway..."
    
    if [[ -n "${IGW_ID:-}" && "$IGW_ID" != "None" ]]; then
        if resource_exists "igw" "$IGW_ID"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would detach and delete Internet Gateway: $IGW_ID"
            else
                # Detach Internet Gateway from VPC
                aws ec2 detach-internet-gateway \
                    --internet-gateway-id "$IGW_ID" \
                    --vpc-id "$VPC_ID" 2>/dev/null || warn "Failed to detach Internet Gateway"
                
                # Delete Internet Gateway
                aws ec2 delete-internet-gateway \
                    --internet-gateway-id "$IGW_ID" || warn "Failed to delete Internet Gateway"
                
                info "Deleted Internet Gateway: $IGW_ID"
            fi
        else
            warn "Internet Gateway $IGW_ID not found"
        fi
    fi
    
    success "Internet Gateway removed"
}

# Remove VPC
remove_vpc() {
    info "Removing VPC..."
    
    if [[ -n "${VPC_ID:-}" && "$VPC_ID" != "None" ]]; then
        if resource_exists "vpc" "$VPC_ID"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete VPC: $VPC_ID"
            else
                aws ec2 delete-vpc --vpc-id "$VPC_ID" || warn "Failed to delete VPC"
                info "Deleted VPC: $VPC_ID"
            fi
        else
            warn "VPC $VPC_ID not found"
        fi
    fi
    
    success "VPC removed"
}

# Remove key pair
remove_key_pair() {
    info "Removing key pair..."
    
    if [[ -n "${KEY_PAIR_NAME:-}" && "$KEY_PAIR_NAME" != "None" ]]; then
        if resource_exists "key-pair" "$KEY_PAIR_NAME"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete key pair: $KEY_PAIR_NAME"
            else
                aws ec2 delete-key-pair --key-name "$KEY_PAIR_NAME" || warn "Failed to delete key pair"
                info "Deleted key pair: $KEY_PAIR_NAME"
            fi
        else
            warn "Key pair $KEY_PAIR_NAME not found"
        fi
    fi
    
    success "Key pair removed"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would remove local files"
        return
    fi
    
    # Remove environment file
    if [[ -f "$SCRIPT_DIR/microseg-environment.sh" ]]; then
        rm -f "$SCRIPT_DIR/microseg-environment.sh"
        info "Removed environment file"
    fi
    
    # Remove deployment summary
    if [[ -f "$SCRIPT_DIR/deployment-summary.txt" ]]; then
        rm -f "$SCRIPT_DIR/deployment-summary.txt"
        info "Removed deployment summary"
    fi
    
    # Remove temporary directory
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        info "Removed temporary directory"
    fi
    
    success "Local files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    info "Validating cleanup..."
    
    local errors=0
    
    # Check if VPC still exists
    if [[ -n "${VPC_ID:-}" ]] && resource_exists "vpc" "$VPC_ID"; then
        warn "VPC $VPC_ID still exists"
        ((errors++))
    fi
    
    # Check if key pair still exists
    if [[ -n "${KEY_PAIR_NAME:-}" ]] && resource_exists "key-pair" "$KEY_PAIR_NAME"; then
        warn "Key pair $KEY_PAIR_NAME still exists"
        ((errors++))
    fi
    
    # Check if IAM role still exists
    if resource_exists "iam-role" "VPCFlowLogsRole"; then
        warn "IAM role VPCFlowLogsRole still exists"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        warn "Cleanup validation found $errors issue(s). Some resources may still exist."
        return 1
    else
        success "Cleanup validation passed"
        return 0
    fi
}

# Show cleanup summary
show_cleanup_summary() {
    info "Cleanup Summary:"
    echo "=================="
    echo "The following resources have been removed:"
    echo "- VPC and all associated networking components"
    echo "- Security Groups and NACLs"
    echo "- Subnets across all security zones"
    echo "- Internet Gateway and route tables"
    echo "- VPC Flow Logs and CloudWatch resources"
    echo "- IAM roles and policies"
    echo "- Key pairs (if configured)"
    echo "- Local configuration files"
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    success "Network Micro-Segmentation cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Network Micro-Segmentation cleanup..." "$GREEN"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_CLEANUP=true
                info "Force cleanup enabled - no confirmation prompts"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                info "Dry run mode enabled - no resources will be deleted"
                shift
                ;;
            --help)
                echo "Usage: $0 [--force] [--dry-run] [--help]"
                echo "  --force      Skip confirmation prompts"
                echo "  --dry-run    Show what would be deleted without actually deleting"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Safety confirmation
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! confirm "This will permanently delete all Network Micro-Segmentation resources. This action cannot be undone."; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    check_prerequisites
    create_temp_dir
    load_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "=== DRY RUN MODE - NO RESOURCES WILL BE DELETED ==="
    fi
    
    # Remove resources in reverse order of creation
    remove_flow_logs_and_monitoring
    remove_security_groups
    remove_nacls
    remove_subnets
    remove_route_tables
    remove_internet_gateway
    remove_vpc
    remove_key_pair
    cleanup_local_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_cleanup
        show_cleanup_summary
    else
        info "Dry run completed - no resources were deleted"
    fi
    
    log "Cleanup completed successfully!" "$GREEN"
}

# Set trap for cleanup on script exit
trap 'rm -rf "$TEMP_DIR" 2>/dev/null || true' EXIT

# Run main function
main "$@"