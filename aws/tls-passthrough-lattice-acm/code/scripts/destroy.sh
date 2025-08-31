#!/bin/bash
set -euo pipefail

# ========================================================================
# VPC Lattice TLS Passthrough Cleanup Script
# 
# This script safely removes all resources created by the deployment script.
# Resources are deleted in reverse order to handle dependencies properly.
# ========================================================================

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }
warn() { log "WARNING" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }

# Load resource ID from state file
load_resource() {
    local key=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Remove resource from state file
remove_resource() {
    local key=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
        info "Removed from state: $key"
    fi
}

# Confirmation prompt
confirm_destruction() {
    echo
    warn "⚠️  WARNING: This will permanently delete all VPC Lattice TLS Passthrough resources!"
    warn "This action cannot be undone."
    echo
    
    if [[ -f "$STATE_FILE" ]]; then
        info "Resources to be deleted:"
        while IFS='=' read -r key value; do
            [[ -n "$key" && -n "$value" ]] && echo "  - $key: $value"
        done < "$STATE_FILE"
    else
        warn "No state file found. Will attempt to clean up by resource tags."
    fi
    
    echo
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Safe resource deletion with error handling
safe_delete() {
    local resource_type=$1
    local resource_id=$2
    local delete_command=$3
    
    if [[ -n "$resource_id" && "$resource_id" != "None" && "$resource_id" != "manual" ]]; then
        info "Deleting $resource_type: $resource_id"
        if eval "$delete_command" 2>/dev/null; then
            success "Deleted $resource_type: $resource_id"
            return 0
        else
            warn "Failed to delete $resource_type: $resource_id (may not exist)"
            return 1
        fi
    else
        info "No $resource_type to delete"
        return 0
    fi
}

# Remove Route 53 DNS records
remove_dns_records() {
    info "Removing Route 53 DNS records..."
    
    local hosted_zone_id=$(load_resource "HOSTED_ZONE_ID")
    local custom_domain=$(load_resource "CUSTOM_DOMAIN")
    local service_dns=$(load_resource "SERVICE_DNS")
    
    if [[ -n "$hosted_zone_id" && "$hosted_zone_id" != "manual" && "$hosted_zone_id" != "None" ]]; then
        if [[ -n "$custom_domain" && -n "$service_dns" ]]; then
            # Create DNS delete record
            cat > "${SCRIPT_DIR}/dns-delete.json" << EOF
{
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "${custom_domain}",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "${service_dns}"
                    }
                ]
            }
        }
    ]
}
EOF
            
            if aws route53 change-resource-record-sets \
                --hosted-zone-id "$hosted_zone_id" \
                --change-batch "file://${SCRIPT_DIR}/dns-delete.json" &>/dev/null; then
                success "DNS records removed"
            else
                warn "Failed to remove DNS records (may not exist)"
            fi
            
            # Clean up temp file
            rm -f "${SCRIPT_DIR}/dns-delete.json"
        fi
    else
        info "No Route 53 records to remove"
    fi
    
    remove_resource "CHANGE_ID"
    remove_resource "HOSTED_ZONE_ID"
}

# Delete VPC Lattice resources
delete_lattice_resources() {
    info "Deleting VPC Lattice resources..."
    
    local listener_arn=$(load_resource "LISTENER_ARN")
    local service_arn=$(load_resource "SERVICE_ARN")
    local service_network_id=$(load_resource "SERVICE_NETWORK_ID")
    local target_group_arn=$(load_resource "TARGET_GROUP_ARN")
    local vpc_id=$(load_resource "VPC_ID")
    
    # Delete listener
    if safe_delete "listener" "$listener_arn" \
        "aws vpc-lattice delete-listener --service-identifier '$service_arn' --listener-identifier '$listener_arn'"; then
        remove_resource "LISTENER_ARN"
    fi
    
    # Wait for listener deletion
    if [[ -n "$listener_arn" ]]; then
        info "Waiting for listener deletion..."
        sleep 10
    fi
    
    # Delete service network associations
    if [[ -n "$service_network_id" && -n "$service_arn" ]]; then
        info "Deleting service network service association..."
        aws vpc-lattice delete-service-network-service-association \
            --service-network-identifier "$service_network_id" \
            --service-identifier "$service_arn" &>/dev/null || warn "Service association may not exist"
    fi
    
    if [[ -n "$service_network_id" && -n "$vpc_id" ]]; then
        info "Deleting service network VPC association..."
        aws vpc-lattice delete-service-network-vpc-association \
            --service-network-identifier "$service_network_id" \
            --vpc-identifier "$vpc_id" &>/dev/null || warn "VPC association may not exist"
    fi
    
    # Wait for associations to be deleted
    if [[ -n "$service_network_id" ]]; then
        info "Waiting for associations to be deleted..."
        sleep 15
    fi
    
    # Delete service
    if safe_delete "service" "$service_arn" \
        "aws vpc-lattice delete-service --service-identifier '$service_arn'"; then
        remove_resource "SERVICE_ARN"
    fi
    
    # Delete target group
    if safe_delete "target group" "$target_group_arn" \
        "aws vpc-lattice delete-target-group --target-group-identifier '$target_group_arn'"; then
        remove_resource "TARGET_GROUP_ARN"
    fi
    
    # Delete service network
    if safe_delete "service network" "$service_network_id" \
        "aws vpc-lattice delete-service-network --service-network-identifier '$service_network_id'"; then
        remove_resource "SERVICE_NETWORK_ID"
    fi
}

# Terminate EC2 instances
terminate_ec2_instances() {
    info "Terminating EC2 instances..."
    
    local instance_1=$(load_resource "INSTANCE_1")
    local instance_2=$(load_resource "INSTANCE_2")
    
    local instances_to_terminate=()
    [[ -n "$instance_1" ]] && instances_to_terminate+=("$instance_1")
    [[ -n "$instance_2" ]] && instances_to_terminate+=("$instance_2")
    
    if [[ ${#instances_to_terminate[@]} -gt 0 ]]; then
        info "Terminating instances: ${instances_to_terminate[*]}"
        if aws ec2 terminate-instances --instance-ids "${instances_to_terminate[@]}" &>/dev/null; then
            success "Instance termination initiated"
            
            # Wait for termination
            info "Waiting for instances to terminate (this may take a few minutes)..."
            aws ec2 wait instance-terminated --instance-ids "${instances_to_terminate[@]}" || warn "Timeout waiting for termination"
            success "Instances terminated"
        else
            warn "Failed to terminate instances (may not exist)"
        fi
    else
        info "No instances to terminate"
    fi
    
    remove_resource "INSTANCE_1"
    remove_resource "INSTANCE_2"
}

# Delete VPC infrastructure
delete_vpc_infrastructure() {
    info "Deleting VPC infrastructure..."
    
    local vpc_id=$(load_resource "VPC_ID")
    local subnet_id=$(load_resource "SUBNET_ID")
    local igw_id=$(load_resource "IGW_ID")
    local route_table_id=$(load_resource "ROUTE_TABLE_ID")
    local security_group_id=$(load_resource "SECURITY_GROUP_ID")
    
    # Detach and delete internet gateway
    if [[ -n "$igw_id" && -n "$vpc_id" ]]; then
        info "Detaching internet gateway..."
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" &>/dev/null || warn "IGW may not be attached"
        
        if safe_delete "internet gateway" "$igw_id" \
            "aws ec2 delete-internet-gateway --internet-gateway-id '$igw_id'"; then
            remove_resource "IGW_ID"
        fi
    fi
    
    # Delete subnet
    if safe_delete "subnet" "$subnet_id" \
        "aws ec2 delete-subnet --subnet-id '$subnet_id'"; then
        remove_resource "SUBNET_ID"
    fi
    
    # Delete security group
    if safe_delete "security group" "$security_group_id" \
        "aws ec2 delete-security-group --group-id '$security_group_id'"; then
        remove_resource "SECURITY_GROUP_ID"
    fi
    
    # Delete route table (VPC default route table will remain)
    if [[ -n "$route_table_id" ]]; then
        # Check if it's not the main route table
        local is_main=$(aws ec2 describe-route-tables --route-table-ids "$route_table_id" \
            --query 'RouteTables[0].Associations[?Main==`true`]' --output text 2>/dev/null || echo "")
        
        if [[ -z "$is_main" ]]; then
            if safe_delete "route table" "$route_table_id" \
                "aws ec2 delete-route-table --route-table-id '$route_table_id'"; then
                remove_resource "ROUTE_TABLE_ID"
            fi
        else
            info "Skipping main route table deletion"
            remove_resource "ROUTE_TABLE_ID"
        fi
    fi
    
    # Delete VPC (last)
    if safe_delete "VPC" "$vpc_id" \
        "aws ec2 delete-vpc --vpc-id '$vpc_id'"; then
        remove_resource "VPC_ID"
    fi
}

# Delete SSL certificate (optional)
delete_ssl_certificate() {
    local cert_arn=$(load_resource "CERT_ARN")
    
    if [[ -n "$cert_arn" ]]; then
        warn "SSL Certificate found: $cert_arn"
        read -p "Do you want to delete the SSL certificate? (yes/no): " delete_cert
        
        if [[ "$delete_cert" == "yes" ]]; then
            if safe_delete "SSL certificate" "$cert_arn" \
                "aws acm delete-certificate --certificate-arn '$cert_arn'"; then
                remove_resource "CERT_ARN"
                success "SSL certificate deleted"
            fi
        else
            info "SSL certificate retained"
            remove_resource "CERT_ARN"
        fi
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/user-data.sh"
        "${SCRIPT_DIR}/dns-change.json"
        "${SCRIPT_DIR}/dns-delete.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed: $(basename "$file")"
        fi
    done
}

# Cleanup by tags (fallback method)
cleanup_by_tags() {
    info "Attempting cleanup by resource tags..."
    
    # Find and terminate instances with project tag
    local tagged_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=tls-passthrough" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$tagged_instances" ]]; then
        warn "Found tagged instances: $tagged_instances"
        read -p "Terminate these instances? (yes/no): " terminate_tagged
        if [[ "$terminate_tagged" == "yes" ]]; then
            aws ec2 terminate-instances --instance-ids $tagged_instances
            info "Terminating tagged instances..."
        fi
    fi
    
    # Find and delete security groups with project tag
    local tagged_sgs=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Project,Values=tls-passthrough" \
        --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$tagged_sgs" ]]; then
        for sg in $tagged_sgs; do
            info "Attempting to delete security group: $sg"
            aws ec2 delete-security-group --group-id "$sg" &>/dev/null || warn "Could not delete SG: $sg"
        done
    fi
    
    warn "Manual cleanup may be required for remaining resources"
    warn "Check VPC Lattice console for any remaining services or networks"
}

# Main cleanup function
main() {
    info "Starting VPC Lattice TLS Passthrough cleanup..."
    info "Log file: $LOG_FILE"
    
    # Initialize log file
    echo "=== VPC Lattice TLS Passthrough Cleanup ===" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    
    # Check if state file exists
    if [[ ! -f "$STATE_FILE" ]]; then
        warn "No deployment state file found at: $STATE_FILE"
        warn "Will attempt cleanup by resource tags"
        
        read -p "Continue with tag-based cleanup? (yes/no): " continue_cleanup
        if [[ "$continue_cleanup" != "yes" ]]; then
            info "Cleanup cancelled"
            exit 0
        fi
        
        cleanup_by_tags
        exit 0
    fi
    
    confirm_destruction
    
    # Delete resources in reverse order
    info "Starting resource cleanup..."
    
    remove_dns_records
    delete_lattice_resources
    terminate_ec2_instances
    delete_vpc_infrastructure
    delete_ssl_certificate
    cleanup_temp_files
    
    # Remove state file if empty
    if [[ -f "$STATE_FILE" ]] && [[ ! -s "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        success "State file removed"
    elif [[ -f "$STATE_FILE" ]]; then
        warn "Some resources may not have been deleted. Check state file: $STATE_FILE"
        info "Remaining resources:"
        cat "$STATE_FILE"
    fi
    
    success "Cleanup completed!"
    success "Log file: $LOG_FILE"
    
    info "Please verify in AWS console that all resources have been removed:"
    info "- VPC Lattice services and networks"
    info "- EC2 instances and VPC infrastructure" 
    info "- Route 53 DNS records"
    info "- ACM certificates (if selected for deletion)"
}

# Handle script interruption
cleanup_on_interrupt() {
    warn "Cleanup interrupted by user"
    warn "Some resources may still exist"
    warn "Re-run this script to continue cleanup"
    exit 1
}
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"