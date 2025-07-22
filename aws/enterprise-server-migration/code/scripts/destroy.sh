#!/bin/bash

# AWS Application Migration Service - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Confirmation function
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-N}"
    
    while true; do
        read -p "${prompt} [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        elif [[ $REPLY =~ ^[Nn]$ ]] || [[ -z $REPLY ]]; then
            return 1
        else
            echo "Please answer yes (y) or no (n)."
        fi
    done
}

# Load environment variables
load_environment() {
    if [ -f "${ENV_FILE}" ]; then
        info "Loading environment variables from ${ENV_FILE}"
        source "${ENV_FILE}"
        
        # Verify required variables are set
        if [ -z "${AWS_REGION:-}" ] || [ -z "${AWS_ACCOUNT_ID:-}" ]; then
            error_exit "Required environment variables not found. Please check ${ENV_FILE}"
        fi
        
        success "Environment variables loaded successfully"
    else
        warning "Environment file not found: ${ENV_FILE}"
        warning "Attempting to load from AWS CLI configuration..."
        
        # Try to get from AWS CLI
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [ -z "${AWS_ACCOUNT_ID}" ]; then
            error_exit "Cannot determine AWS account ID. Please ensure AWS CLI is configured."
        fi
        
        info "Using AWS Region: ${AWS_REGION}"
        info "Using AWS Account ID: ${AWS_ACCOUNT_ID}"
    fi
}

# List source servers function
list_source_servers() {
    info "Listing source servers in MGN..."
    
    local servers=$(aws mgn describe-source-servers \
        --region "${AWS_REGION}" \
        --query 'items[*].{ServerID:sourceServerID,Hostname:sourceProperties.identificationHints.hostname,Status:lifeCycle.state}' \
        --output table 2>/dev/null || echo "")
    
    if [ -n "${servers}" ]; then
        log "${servers}"
        return 0
    else
        info "No source servers found in MGN"
        return 1
    fi
}

# Disconnect source servers function
disconnect_source_servers() {
    info "Disconnecting source servers from MGN..."
    
    # Get list of source server IDs
    local server_ids=$(aws mgn describe-source-servers \
        --region "${AWS_REGION}" \
        --query 'items[*].sourceServerID' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "${server_ids}" ]; then
        info "No source servers to disconnect"
        return 0
    fi
    
    # Disconnect each server
    for server_id in ${server_ids}; do
        if [ "${server_id}" != "None" ] && [ "${server_id}" != "null" ]; then
            info "Disconnecting server: ${server_id}"
            
            # First, finalize cutover if needed
            aws mgn finalize-cutover \
                --source-server-id "${server_id}" \
                --region "${AWS_REGION}" 2>/dev/null || true
            
            # Then disconnect from service
            aws mgn disconnect-from-service \
                --source-server-id "${server_id}" \
                --region "${AWS_REGION}" 2>/dev/null || true
            
            success "Disconnected server: ${server_id}"
        fi
    done
    
    success "All source servers disconnected from MGN"
}

# Terminate instances function
terminate_instances() {
    info "Terminating MGN-related instances..."
    
    # Get test instances
    local test_instances=$(aws mgn describe-source-servers \
        --region "${AWS_REGION}" \
        --query 'items[*].lifeCycle.lastTest.initiated.ec2InstanceID' \
        --output text 2>/dev/null || echo "")
    
    # Get production instances
    local prod_instances=$(aws mgn describe-source-servers \
        --region "${AWS_REGION}" \
        --query 'items[*].lifeCycle.lastCutover.initiated.ec2InstanceID' \
        --output text 2>/dev/null || echo "")
    
    # Combine and deduplicate instance IDs
    local all_instances="${test_instances} ${prod_instances}"
    local instances_to_terminate=""
    
    for instance_id in ${all_instances}; do
        if [ "${instance_id}" != "None" ] && [ "${instance_id}" != "null" ] && [ -n "${instance_id}" ]; then
            instances_to_terminate="${instances_to_terminate} ${instance_id}"
        fi
    done
    
    if [ -n "${instances_to_terminate}" ]; then
        info "Terminating instances: ${instances_to_terminate}"
        
        if confirm "Terminate these EC2 instances?"; then
            for instance_id in ${instances_to_terminate}; do
                aws ec2 terminate-instances \
                    --instance-ids "${instance_id}" \
                    --region "${AWS_REGION}" > /dev/null 2>&1 || true
                success "Terminated instance: ${instance_id}"
            done
            
            # Wait for termination
            info "Waiting for instances to terminate..."
            sleep 30
        else
            warning "Skipping instance termination"
        fi
    else
        info "No instances to terminate"
    fi
}

# Clean up replication infrastructure
cleanup_replication_infrastructure() {
    info "Cleaning up replication infrastructure..."
    
    # Delete replication configuration templates
    local template_ids=$(aws mgn describe-replication-configuration-templates \
        --region "${AWS_REGION}" \
        --query 'items[*].replicationConfigurationTemplateID' \
        --output text 2>/dev/null || echo "")
    
    for template_id in ${template_ids}; do
        if [ "${template_id}" != "None" ] && [ "${template_id}" != "null" ]; then
            info "Deleting replication configuration template: ${template_id}"
            aws mgn delete-replication-configuration-template \
                --replication-configuration-template-id "${template_id}" \
                --region "${AWS_REGION}" 2>/dev/null || true
            success "Deleted replication configuration template: ${template_id}"
        fi
    done
    
    # Clean up EBS snapshots with MGN tags
    info "Cleaning up MGN-related EBS snapshots..."
    local snapshot_ids=$(aws ec2 describe-snapshots \
        --owner-ids "${AWS_ACCOUNT_ID}" \
        --filters "Name=tag:Application,Values=MGN" \
        --query 'Snapshots[*].SnapshotId' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null || echo "")
    
    for snapshot_id in ${snapshot_ids}; do
        if [ "${snapshot_id}" != "None" ] && [ "${snapshot_id}" != "null" ]; then
            info "Deleting EBS snapshot: ${snapshot_id}"
            aws ec2 delete-snapshot \
                --snapshot-id "${snapshot_id}" \
                --region "${AWS_REGION}" 2>/dev/null || true
            success "Deleted EBS snapshot: ${snapshot_id}"
        fi
    done
}

# Delete migration waves function
delete_migration_waves() {
    info "Deleting migration waves..."
    
    # Get wave IDs
    local wave_ids=$(aws mgn list-waves \
        --region "${AWS_REGION}" \
        --query 'items[*].waveID' \
        --output text 2>/dev/null || echo "")
    
    for wave_id in ${wave_ids}; do
        if [ "${wave_id}" != "None" ] && [ "${wave_id}" != "null" ]; then
            info "Deleting migration wave: ${wave_id}"
            aws mgn delete-wave \
                --wave-id "${wave_id}" \
                --region "${AWS_REGION}" 2>/dev/null || true
            success "Deleted migration wave: ${wave_id}"
        fi
    done
}

# Delete IAM resources function
delete_iam_resources() {
    info "Deleting IAM resources..."
    
    # Delete service role if it exists
    if [ -n "${MGN_SERVICE_ROLE_NAME:-}" ]; then
        info "Deleting IAM service role: ${MGN_SERVICE_ROLE_NAME}"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${MGN_SERVICE_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::aws:policy/AWSApplicationMigrationServiceRolePolicy" \
            2>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name "${MGN_SERVICE_ROLE_NAME}" \
            2>/dev/null || true
        
        success "Deleted IAM service role: ${MGN_SERVICE_ROLE_NAME}"
    fi
    
    # Clean up any MGN-related instance profiles
    local instance_profiles=$(aws iam list-instance-profiles \
        --query 'InstanceProfiles[?contains(InstanceProfileName, `MGN`)].InstanceProfileName' \
        --output text 2>/dev/null || echo "")
    
    for profile in ${instance_profiles}; do
        if [ "${profile}" != "None" ] && [ "${profile}" != "null" ]; then
            info "Deleting instance profile: ${profile}"
            
            # Remove roles from instance profile
            local roles=$(aws iam get-instance-profile \
                --instance-profile-name "${profile}" \
                --query 'InstanceProfile.Roles[*].RoleName' \
                --output text 2>/dev/null || echo "")
            
            for role in ${roles}; do
                aws iam remove-role-from-instance-profile \
                    --instance-profile-name "${profile}" \
                    --role-name "${role}" 2>/dev/null || true
            done
            
            # Delete instance profile
            aws iam delete-instance-profile \
                --instance-profile-name "${profile}" 2>/dev/null || true
            
            success "Deleted instance profile: ${profile}"
        fi
    done
}

# Cleanup local files function
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove MGN agent files
    if [ -d "${SCRIPT_DIR}/mgn-agent" ]; then
        rm -rf "${SCRIPT_DIR}/mgn-agent"
        success "Removed MGN agent files"
    fi
    
    # Remove post-deployment instructions
    if [ -f "${SCRIPT_DIR}/post-deployment-instructions.md" ]; then
        rm -f "${SCRIPT_DIR}/post-deployment-instructions.md"
        success "Removed post-deployment instructions"
    fi
    
    # Remove environment file
    if [ -f "${ENV_FILE}" ]; then
        rm -f "${ENV_FILE}"
        success "Removed environment file"
    fi
    
    # Keep log files for reference
    info "Log files preserved for reference"
}

# Generate cleanup report
generate_cleanup_report() {
    info "Generating cleanup report..."
    
    cat > "${SCRIPT_DIR}/cleanup-report.md" << EOF
# AWS Application Migration Service - Cleanup Report

## Cleanup Summary
- **Date**: $(date)
- **AWS Region**: ${AWS_REGION}
- **AWS Account ID**: ${AWS_ACCOUNT_ID}

## Resources Cleaned Up

### Source Servers
- All source servers disconnected from MGN service
- Replication stopped and agents decommissioned

### EC2 Instances
- Test instances terminated
- Production instances terminated (if confirmed)
- Related EBS volumes and snapshots removed

### MGN Infrastructure
- Replication configuration templates deleted
- Migration waves removed
- Service initialization artifacts cleaned up

### IAM Resources
- Service roles deleted
- Instance profiles removed
- Policy attachments cleaned up

### Local Files
- MGN agent installation files removed
- Post-deployment instructions removed
- Environment configuration files removed

## Important Notes

1. **Production Instances**: If you chose not to terminate production instances, 
   they will continue running and incurring costs.

2. **Source Servers**: MGN agents on source servers have been disconnected but 
   may still be installed. Consider uninstalling them if no longer needed.

3. **Custom Configurations**: Any custom security groups, VPCs, or other resources 
   created manually were not automatically removed.

4. **Cost Monitoring**: Continue monitoring your AWS bill to ensure all migration-related 
   costs have stopped.

## Verification Steps

Run these commands to verify cleanup:

\`\`\`bash
# Check for remaining source servers
aws mgn describe-source-servers --region ${AWS_REGION}

# Check for running instances with MGN tags
aws ec2 describe-instances --filters "Name=tag:Application,Values=MGN" --region ${AWS_REGION}

# Check for remaining EBS snapshots
aws ec2 describe-snapshots --owner-ids ${AWS_ACCOUNT_ID} --filters "Name=tag:Application,Values=MGN" --region ${AWS_REGION}
\`\`\`

## Support
If you encounter any issues or have remaining resources, please:
1. Check the AWS Console for any remaining resources
2. Review the cleanup log: ${LOG_FILE}
3. Contact AWS Support if needed

## Cleanup Completed
Date: $(date)
EOF
    
    success "Cleanup report generated: ${SCRIPT_DIR}/cleanup-report.md"
}

# Main cleanup function
main() {
    # Initialize logging
    echo "Starting AWS Application Migration Service cleanup at $(date)" > "${LOG_FILE}"
    
    info "Starting AWS Application Migration Service cleanup..."
    warning "This will remove all MGN-related resources!"
    
    # Load environment
    load_environment
    
    # Show what will be cleaned up
    info "Cleanup will remove:"
    info "  - All source servers from MGN"
    info "  - Test and production instances (with confirmation)"
    info "  - Replication configuration templates"
    info "  - Migration waves"
    info "  - IAM service roles"
    info "  - Local files and configurations"
    
    # Final confirmation
    if ! confirm "Are you sure you want to proceed with cleanup?"; then
        warning "Cleanup cancelled by user"
        exit 0
    fi
    
    # Show current source servers
    if list_source_servers; then
        if ! confirm "Proceed with disconnecting these source servers?"; then
            warning "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    disconnect_source_servers
    terminate_instances
    cleanup_replication_infrastructure
    delete_migration_waves
    delete_iam_resources
    cleanup_local_files
    generate_cleanup_report
    
    success "Cleanup completed successfully!"
    info "Cleanup report: ${SCRIPT_DIR}/cleanup-report.md"
    info "Cleanup log: ${LOG_FILE}"
    
    warning "IMPORTANT: Verify all resources have been removed by checking the AWS Console"
    warning "Some resources may take several minutes to fully terminate"
    
    return 0
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi