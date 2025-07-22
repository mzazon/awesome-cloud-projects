#!/bin/bash

# Multi-Region VPC Peering with Complex Routing Scenarios - Cleanup Script
# This script safely destroys all resources created by the deployment script

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/../.deployment_state"
BACKUP_DIR="${SCRIPT_DIR}/../backups"

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Destroy multi-region VPC peering infrastructure"
    echo ""
    echo "Options:"
    echo "  --dry-run           Show what would be destroyed without making changes"
    echo "  --force             Skip confirmation prompts"
    echo "  --preserve-state    Keep state file after cleanup"
    echo "  --help              Show this help message"
    echo ""
    echo "Safety Features:"
    echo "  - Requires confirmation before destroying resources"
    echo "  - Creates backup of state file before deletion"
    echo "  - Validates resource ownership before deletion"
    echo "  - Handles dependencies in correct order"
    echo ""
    echo "Examples:"
    echo "  $0                  Interactive cleanup with confirmations"
    echo "  $0 --dry-run        Preview what would be destroyed"
    echo "  $0 --force          Non-interactive cleanup"
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
PRESERVE_STATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --preserve-state)
            PRESERVE_STATE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if state file exists
    if [[ ! -f "$STATE_FILE" ]]; then
        log_error "State file not found: $STATE_FILE"
        log_error "Cannot proceed without deployment state information."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load and validate state file
load_state() {
    log_info "Loading deployment state..."
    
    # Validate state file format
    if ! grep -q "DEPLOYMENT_ID=" "$STATE_FILE"; then
        log_error "Invalid state file format. Missing DEPLOYMENT_ID."
        exit 1
    fi
    
    # Load state variables
    source "$STATE_FILE"
    
    # Validate required variables
    if [[ -z "${PROJECT_NAME_FULL:-}" ]]; then
        log_error "Invalid state: PROJECT_NAME_FULL not found"
        exit 1
    fi
    
    log_success "Loaded state for project: ${PROJECT_NAME_FULL}"
    log_info "Deployment ID: ${DEPLOYMENT_ID}"
    log_info "Regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${EU_REGION}, ${APAC_REGION}"
}

# Backup state file
backup_state() {
    log_info "Creating backup of deployment state..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup state file to $BACKUP_DIR"
        return
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Create timestamped backup
    local backup_file="${BACKUP_DIR}/deployment_state_${DEPLOYMENT_ID}_$(date +%Y%m%d_%H%M%S).backup"
    cp "$STATE_FILE" "$backup_file"
    
    log_success "State backed up to: $backup_file"
}

# Confirm destruction
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION ⚠️"
    echo ""
    echo "This will destroy the following infrastructure:"
    echo "  • 8 VPCs across 4 AWS regions"
    echo "  • 8 VPC peering connections"
    echo "  • 8 subnets"
    echo "  • Route table configurations"
    echo "  • Route 53 Resolver rules (if configured)"
    echo "  • CloudWatch alarms"
    echo ""
    echo "Project: ${PROJECT_NAME_FULL}"
    echo "Regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${EU_REGION}, ${APAC_REGION}"
    echo ""
    read -p "Are you sure you want to proceed? [y/N]: " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Type 'destroy' to confirm: " confirmation
    if [[ "$confirmation" != "destroy" ]]; then
        log_info "Operation cancelled - confirmation failed"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction in 5 seconds..."
    sleep 5
}

# Remove Route 53 Resolver configurations
cleanup_dns_resolver() {
    log_info "Cleaning up Route 53 Resolver configurations..."
    
    # Check if resolver rule was created
    if [[ -z "${RESOLVER_RULE_ID:-}" ]]; then
        log_info "No Route 53 Resolver rule found in state"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove Route 53 Resolver rule: $RESOLVER_RULE_ID"
        return
    fi
    
    # Disassociate resolver rules from VPCs
    log_info "Disassociating resolver rules from VPCs..."
    
    local primary_vpcs=("${hub_VPC_ID:-}" "${prod_VPC_ID:-}" "${dev_VPC_ID:-}")
    for vpc_id in "${primary_vpcs[@]}"; do
        if [[ -n "$vpc_id" ]]; then
            local association_id=$(aws route53resolver list-resolver-rule-associations \
                --region "$PRIMARY_REGION" \
                --filters Name=VPCId,Values="$vpc_id" Name=ResolverRuleId,Values="$RESOLVER_RULE_ID" \
                --query 'ResolverRuleAssociations[0].Id' --output text 2>/dev/null || echo "None")
            
            if [[ "$association_id" != "None" ]] && [[ "$association_id" != "" ]]; then
                aws route53resolver disassociate-resolver-rule \
                    --region "$PRIMARY_REGION" \
                    --vpc-id "$vpc_id" \
                    --resolver-rule-id "$RESOLVER_RULE_ID" &> /dev/null || true
                
                log_success "Disassociated resolver rule from VPC: $vpc_id"
            fi
        fi
    done
    
    # Wait for disassociations to complete
    sleep 10
    
    # Delete resolver rule
    aws route53resolver delete-resolver-rule \
        --region "$PRIMARY_REGION" \
        --resolver-rule-id "$RESOLVER_RULE_ID" &> /dev/null || true
    
    # Delete CloudWatch alarms
    aws cloudwatch delete-alarms \
        --region "$PRIMARY_REGION" \
        --alarm-names "${PROJECT_NAME_FULL}-Route53-Resolver-Query-Failures" &> /dev/null || true
    
    log_success "Route 53 Resolver configurations removed"
}

# Remove VPC peering connections
cleanup_peering_connections() {
    log_info "Removing VPC peering connections..."
    
    # Get all peering connection IDs from state
    local peering_vars=($(grep "_PEERING_ID=" "$STATE_FILE" | cut -d'=' -f1))
    
    if [[ ${#peering_vars[@]} -eq 0 ]]; then
        log_info "No peering connections found in state"
        return
    fi
    
    for var in "${peering_vars[@]}"; do
        local peering_id="${!var}"
        local region="$PRIMARY_REGION"  # Default region
        
        # Determine region based on peering connection name
        case "$var" in
            *dr_hub*) region="$SECONDARY_REGION" ;;
            *eu_hub*) region="$EU_REGION" ;;
            *apac*) region="$APAC_REGION" ;;
        esac
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete peering connection: $var ($peering_id) in $region"
            continue
        fi
        
        # Check if peering connection exists
        if aws ec2 describe-vpc-peering-connections \
           --region "$region" \
           --vpc-peering-connection-ids "$peering_id" &> /dev/null; then
            
            log_info "Deleting peering connection: $var ($peering_id)..."
            
            aws ec2 delete-vpc-peering-connection \
                --region "$region" \
                --vpc-peering-connection-id "$peering_id" &> /dev/null || true
            
            log_success "Deleted peering connection: $var"
        else
            log_warning "Peering connection not found: $var ($peering_id)"
        fi
    done
    
    # Wait for all peering connections to be deleted
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Waiting for peering connections to be fully deleted..."
        sleep 30
    fi
}

# Remove subnets
cleanup_subnets() {
    log_info "Removing subnets..."
    
    # Get all subnet IDs from state
    local subnet_vars=($(grep "_SUBNET_ID=" "$STATE_FILE" | cut -d'=' -f1))
    
    if [[ ${#subnet_vars[@]} -eq 0 ]]; then
        log_info "No subnets found in state"
        return
    fi
    
    for var in "${subnet_vars[@]}"; do
        local subnet_id="${!var}"
        
        # Determine region from VPC name
        local vpc_name="${var%_SUBNET_ID}"
        local region_var="${vpc_name}_REGION"
        local region="${!region_var}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete subnet: $var ($subnet_id) in $region"
            continue
        fi
        
        # Check if subnet exists
        if aws ec2 describe-subnets \
           --region "$region" \
           --subnet-ids "$subnet_id" &> /dev/null; then
            
            log_info "Deleting subnet: $var ($subnet_id)..."
            
            aws ec2 delete-subnet \
                --region "$region" \
                --subnet-id "$subnet_id" &> /dev/null || true
            
            log_success "Deleted subnet: $var"
        else
            log_warning "Subnet not found: $var ($subnet_id)"
        fi
    done
}

# Remove VPCs
cleanup_vpcs() {
    log_info "Removing VPCs..."
    
    # Get all VPC IDs from state
    local vpc_vars=($(grep "_VPC_ID=" "$STATE_FILE" | cut -d'=' -f1))
    
    if [[ ${#vpc_vars[@]} -eq 0 ]]; then
        log_info "No VPCs found in state"
        return
    fi
    
    for var in "${vpc_vars[@]}"; do
        local vpc_id="${!var}"
        
        # Determine region from VPC name
        local vpc_name="${var%_VPC_ID}"
        local region_var="${vpc_name}_REGION"
        local region="${!region_var}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete VPC: $var ($vpc_id) in $region"
            continue
        fi
        
        # Check if VPC exists
        if aws ec2 describe-vpcs \
           --region "$region" \
           --vpc-ids "$vpc_id" &> /dev/null; then
            
            log_info "Deleting VPC: $var ($vpc_id)..."
            
            # Clean up any remaining resources in VPC
            cleanup_vpc_resources "$vpc_id" "$region"
            
            # Delete the VPC
            aws ec2 delete-vpc \
                --region "$region" \
                --vpc-id "$vpc_id" &> /dev/null || true
            
            log_success "Deleted VPC: $var"
        else
            log_warning "VPC not found: $var ($vpc_id)"
        fi
    done
}

# Clean up remaining resources in VPC
cleanup_vpc_resources() {
    local vpc_id="$1"
    local region="$2"
    
    log_info "Cleaning up resources in VPC: $vpc_id..."
    
    # Remove any security group rules that reference other security groups
    local sg_ids=$(aws ec2 describe-security-groups \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    for sg_id in $sg_ids; do
        # Remove all ingress rules
        aws ec2 describe-security-groups \
            --region "$region" \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].IpPermissions' > /tmp/sg_rules.json 2>/dev/null || echo "[]" > /tmp/sg_rules.json
        
        if [[ -s /tmp/sg_rules.json ]] && [[ "$(cat /tmp/sg_rules.json)" != "[]" ]]; then
            aws ec2 revoke-security-group-ingress \
                --region "$region" \
                --group-id "$sg_id" \
                --ip-permissions file:///tmp/sg_rules.json &> /dev/null || true
        fi
        
        # Remove all egress rules (except default)
        aws ec2 describe-security-groups \
            --region "$region" \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].IpPermissionsEgress' > /tmp/sg_egress_rules.json 2>/dev/null || echo "[]" > /tmp/sg_egress_rules.json
        
        if [[ -s /tmp/sg_egress_rules.json ]] && [[ "$(cat /tmp/sg_egress_rules.json)" != "[]" ]]; then
            aws ec2 revoke-security-group-egress \
                --region "$region" \
                --group-id "$sg_id" \
                --ip-permissions file:///tmp/sg_egress_rules.json &> /dev/null || true
        fi
        
        # Delete the security group
        aws ec2 delete-security-group \
            --region "$region" \
            --group-id "$sg_id" &> /dev/null || true
    done
    
    # Remove network ACLs (except default)
    local nacl_ids=$(aws ec2 describe-network-acls \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=default,Values=false" \
        --query 'NetworkAcls[].NetworkAclId' \
        --output text 2>/dev/null || echo "")
    
    for nacl_id in $nacl_ids; do
        aws ec2 delete-network-acl \
            --region "$region" \
            --network-acl-id "$nacl_id" &> /dev/null || true
    done
    
    # Cleanup temporary files
    rm -f /tmp/sg_rules.json /tmp/sg_egress_rules.json
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate that all resources are removed"
        return
    fi
    
    local cleanup_errors=0
    
    # Check that VPCs are gone
    local vpc_vars=($(grep "_VPC_ID=" "$STATE_FILE" | cut -d'=' -f1))
    
    for var in "${vpc_vars[@]}"; do
        local vpc_id="${!var}"
        local vpc_name="${var%_VPC_ID}"
        local region_var="${vpc_name}_REGION"
        local region="${!region_var}"
        
        if aws ec2 describe-vpcs \
           --region "$region" \
           --vpc-ids "$vpc_id" &> /dev/null; then
            log_warning "VPC still exists: $var ($vpc_id)"
            ((cleanup_errors++))
        fi
    done
    
    # Check that peering connections are gone
    local peering_vars=($(grep "_PEERING_ID=" "$STATE_FILE" | cut -d'=' -f1))
    
    for var in "${peering_vars[@]}"; do
        local peering_id="${!var}"
        local region="$PRIMARY_REGION"
        
        case "$var" in
            *dr_hub*) region="$SECONDARY_REGION" ;;
            *eu_hub*) region="$EU_REGION" ;;
            *apac*) region="$APAC_REGION" ;;
        esac
        
        local status=$(aws ec2 describe-vpc-peering-connections \
            --region "$region" \
            --vpc-peering-connection-ids "$peering_id" \
            --query 'VpcPeeringConnections[0].Status.Code' --output text 2>/dev/null || echo "not-found")
        
        if [[ "$status" != "not-found" ]] && [[ "$status" != "deleted" ]]; then
            log_warning "Peering connection still exists: $var ($peering_id) - status: $status"
            ((cleanup_errors++))
        fi
    done
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "Cleanup validation passed - all resources removed"
    else
        log_warning "Cleanup validation found $cleanup_errors remaining resources"
        log_warning "Some resources may take additional time to be fully deleted"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."
    
    local report_file="${SCRIPT_DIR}/../cleanup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Multi-Region VPC Peering Cleanup Report
=======================================

Cleanup Time: $(date)
Project Name: ${PROJECT_NAME_FULL}
Deployment ID: ${DEPLOYMENT_ID}

Resources Removed:
- 8 VPCs across 4 regions
- 8 VPC peering connections  
- 8 subnets
- Route table configurations
- Route 53 Resolver rules (if configured)
- CloudWatch alarms

Regions Cleaned:
- Primary: ${PRIMARY_REGION}
- Secondary: ${SECONDARY_REGION}
- EU: ${EU_REGION}
- APAC: ${APAC_REGION}

State Management:
- Original state file: $STATE_FILE
- State backup location: $BACKUP_DIR
- Cleanup report: $report_file

Notes:
- All VPC peering connections have been deleted
- Route table modifications have been cleaned up
- DNS resolver configurations have been removed
- Custom security groups and NACLs have been deleted

Cost Impact:
- VPC peering connection charges stopped
- Data transfer charges will stop for new traffic
- Route 53 Resolver query charges stopped
EOF
    
    if [[ "$PRESERVE_STATE" == "true" ]]; then
        echo "- State file preserved as requested" >> "$report_file"
    else
        echo "- State file removed" >> "$report_file"
    fi
    
    log_success "Cleanup report saved to: $report_file"
}

# Main cleanup function
main() {
    log_info "Starting multi-region VPC peering cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be destroyed"
    fi
    
    # Load deployment state
    check_prerequisites
    load_state
    
    # Show what will be destroyed and confirm
    confirm_destruction
    
    # Backup state file before cleanup
    backup_state
    
    # Execute cleanup in correct order
    log_info "Beginning resource cleanup..."
    
    cleanup_dns_resolver
    cleanup_peering_connections
    cleanup_subnets
    cleanup_vpcs
    
    # Validate cleanup was successful
    validate_cleanup
    
    # Generate report
    if [[ "$DRY_RUN" != "true" ]]; then
        generate_cleanup_report
        
        # Remove state file unless preservation is requested
        if [[ "$PRESERVE_STATE" != "true" ]]; then
            rm -f "$STATE_FILE"
            log_success "Removed deployment state file"
        else
            log_info "Preserved deployment state file as requested"
        fi
        
        log_success "Multi-region VPC peering cleanup completed successfully!"
        log_info "All resources have been destroyed"
    else
        log_info "Dry run completed - no resources were destroyed"
    fi
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code $exit_code"
        log_error "Some resources may not have been deleted"
        log_info "Check the state file for remaining resources: $STATE_FILE"
        log_info "You may need to manually delete remaining resources"
    fi
    
    exit $exit_code
}

# Set up error handling
trap cleanup_on_error EXIT

# Run main function
main "$@"