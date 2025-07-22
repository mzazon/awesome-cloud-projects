#!/bin/bash

# EC2 Fleet Management Cleanup Script
# This script removes all resources created by the deploy.sh script

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly TEMP_DIR="${SCRIPT_DIR}/temp"
readonly STATE_FILE="${TEMP_DIR}/deployment-state.json"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code: ${exit_code}"
    log_error "Check ${LOG_FILE} for details"
    exit "${exit_code}"
}

trap cleanup_on_error ERR

# Confirmation prompt
confirm_cleanup() {
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will delete ALL resources created by the EC2 Fleet Management demo."
    log_warning "This action is IRREVERSIBLE and will terminate all running instances."
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    
    if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_error "Deployment state file not found: ${STATE_FILE}"
        log_error "Cannot proceed with cleanup without state information"
        exit 1
    fi
    
    # Load variables from state file
    FLEET_NAME=$(jq -r '.fleet_name // empty' "${STATE_FILE}")
    LAUNCH_TEMPLATE_NAME=$(jq -r '.launch_template_name // empty' "${STATE_FILE}")
    KEY_PAIR_NAME=$(jq -r '.key_pair_name // empty' "${STATE_FILE}")
    SECURITY_GROUP_NAME=$(jq -r '.security_group_name // empty' "${STATE_FILE}")
    IAM_ROLE_NAME=$(jq -r '.iam_role_name // empty' "${STATE_FILE}")
    DASHBOARD_NAME=$(jq -r '.dashboard_name // empty' "${STATE_FILE}")
    
    FLEET_ID=$(jq -r '.fleet_id // empty' "${STATE_FILE}")
    SPOT_FLEET_ID=$(jq -r '.spot_fleet_id // empty' "${STATE_FILE}")
    LAUNCH_TEMPLATE_ID=$(jq -r '.launch_template_id // empty' "${STATE_FILE}")
    SECURITY_GROUP_ID=$(jq -r '.security_group_id // empty' "${STATE_FILE}")
    SPOT_FLEET_ROLE_ARN=$(jq -r '.spot_fleet_role_arn // empty' "${STATE_FILE}")
    
    AWS_REGION=$(jq -r '.aws_region // empty' "${STATE_FILE}")
    
    export AWS_REGION
    export FLEET_NAME LAUNCH_TEMPLATE_NAME KEY_PAIR_NAME SECURITY_GROUP_NAME IAM_ROLE_NAME DASHBOARD_NAME
    export FLEET_ID SPOT_FLEET_ID LAUNCH_TEMPLATE_ID SECURITY_GROUP_ID SPOT_FLEET_ROLE_ARN
    
    log_success "Deployment state loaded successfully"
}

# Wait for resource deletion with timeout
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local max_attempts=30
    local attempt=0
    
    log_info "Waiting for ${resource_type} deletion..."
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if ! eval "${check_command}" &>/dev/null; then
            log_success "${resource_type} deleted successfully"
            return 0
        fi
        
        sleep 10
        ((attempt++))
        log_info "Still waiting for ${resource_type} deletion (attempt ${attempt}/${max_attempts})"
    done
    
    log_warning "Timeout waiting for ${resource_type} deletion"
    return 1
}

# Delete EC2 Fleet
delete_ec2_fleet() {
    if [[ -n "${FLEET_ID}" ]]; then
        log_info "Deleting EC2 Fleet: ${FLEET_ID}"
        
        # Check if fleet exists
        if aws ec2 describe-fleets --fleet-ids "${FLEET_ID}" &>/dev/null; then
            # Delete fleet and terminate instances
            aws ec2 delete-fleets \
                --fleet-ids "${FLEET_ID}" \
                --terminate-instances
            
            # Wait for fleet deletion
            wait_for_deletion "EC2 Fleet" "aws ec2 describe-fleets --fleet-ids ${FLEET_ID}"
            
            log_success "Deleted EC2 Fleet: ${FLEET_ID}"
        else
            log_warning "EC2 Fleet ${FLEET_ID} not found (may already be deleted)"
        fi
    else
        log_warning "No EC2 Fleet ID found in state file"
    fi
}

# Delete Spot Fleet
delete_spot_fleet() {
    if [[ -n "${SPOT_FLEET_ID}" ]]; then
        log_info "Deleting Spot Fleet: ${SPOT_FLEET_ID}"
        
        # Check if spot fleet exists
        if aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids "${SPOT_FLEET_ID}" &>/dev/null; then
            # Cancel spot fleet and terminate instances
            aws ec2 cancel-spot-fleet-requests \
                --spot-fleet-request-ids "${SPOT_FLEET_ID}" \
                --terminate-instances
            
            # Wait for spot fleet cancellation
            wait_for_deletion "Spot Fleet" "aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids ${SPOT_FLEET_ID} --query 'SpotFleetRequestConfigs[0].SpotFleetRequestState' --output text | grep -v cancelled"
            
            log_success "Deleted Spot Fleet: ${SPOT_FLEET_ID}"
        else
            log_warning "Spot Fleet ${SPOT_FLEET_ID} not found (may already be deleted)"
        fi
    else
        log_warning "No Spot Fleet ID found in state file"
    fi
}

# Wait for all instances to terminate
wait_for_instance_termination() {
    log_info "Waiting for all instances to terminate..."
    
    local max_attempts=60
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local running_instances=0
        
        # Check for running instances with our tags
        if [[ -n "${FLEET_NAME}" ]]; then
            running_instances=$(aws ec2 describe-instances \
                --filters "Name=tag:Project,Values=EC2-Fleet-Demo" \
                         "Name=instance-state-name,Values=running,pending" \
                --query 'length(Reservations[].Instances[])' \
                --output text 2>/dev/null || echo "0")
        fi
        
        if [[ "${running_instances}" -eq 0 ]]; then
            log_success "All instances terminated"
            return 0
        fi
        
        sleep 10
        ((attempt++))
        log_info "Still waiting for ${running_instances} instances to terminate (attempt ${attempt}/${max_attempts})"
    done
    
    log_warning "Timeout waiting for instance termination"
    return 1
}

# Delete launch template
delete_launch_template() {
    if [[ -n "${LAUNCH_TEMPLATE_ID}" ]]; then
        log_info "Deleting launch template: ${LAUNCH_TEMPLATE_ID}"
        
        # Check if launch template exists
        if aws ec2 describe-launch-templates --launch-template-ids "${LAUNCH_TEMPLATE_ID}" &>/dev/null; then
            aws ec2 delete-launch-template \
                --launch-template-id "${LAUNCH_TEMPLATE_ID}"
            
            log_success "Deleted launch template: ${LAUNCH_TEMPLATE_ID}"
        else
            log_warning "Launch template ${LAUNCH_TEMPLATE_ID} not found (may already be deleted)"
        fi
    else
        log_warning "No launch template ID found in state file"
    fi
}

# Delete IAM role
delete_iam_role() {
    if [[ -n "${IAM_ROLE_NAME}" ]]; then
        log_info "Deleting IAM role: ${IAM_ROLE_NAME}"
        
        # Check if role exists
        if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
            # Detach policies first
            aws iam detach-role-policy \
                --role-name "${IAM_ROLE_NAME}" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRequestRole" \
                2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "${IAM_ROLE_NAME}"
            
            log_success "Deleted IAM role: ${IAM_ROLE_NAME}"
        else
            log_warning "IAM role ${IAM_ROLE_NAME} not found (may already be deleted)"
        fi
    else
        log_warning "No IAM role name found in state file"
    fi
}

# Delete security group
delete_security_group() {
    if [[ -n "${SECURITY_GROUP_ID}" ]]; then
        log_info "Deleting security group: ${SECURITY_GROUP_ID}"
        
        # Check if security group exists
        if aws ec2 describe-security-groups --group-ids "${SECURITY_GROUP_ID}" &>/dev/null; then
            # Wait a bit for instances to fully terminate
            sleep 30
            
            # Retry deletion with exponential backoff
            local max_attempts=5
            local attempt=0
            local delay=5
            
            while [[ ${attempt} -lt ${max_attempts} ]]; do
                if aws ec2 delete-security-group --group-id "${SECURITY_GROUP_ID}" 2>/dev/null; then
                    log_success "Deleted security group: ${SECURITY_GROUP_ID}"
                    return 0
                fi
                
                ((attempt++))
                log_info "Retrying security group deletion (attempt ${attempt}/${max_attempts})"
                sleep ${delay}
                delay=$((delay * 2))
            done
            
            log_warning "Failed to delete security group after ${max_attempts} attempts"
            log_warning "Security group may still have dependent resources"
        else
            log_warning "Security group ${SECURITY_GROUP_ID} not found (may already be deleted)"
        fi
    else
        log_warning "No security group ID found in state file"
    fi
}

# Delete key pair
delete_key_pair() {
    if [[ -n "${KEY_PAIR_NAME}" ]]; then
        log_info "Deleting key pair: ${KEY_PAIR_NAME}"
        
        # Check if key pair exists
        if aws ec2 describe-key-pairs --key-names "${KEY_PAIR_NAME}" &>/dev/null; then
            aws ec2 delete-key-pair --key-name "${KEY_PAIR_NAME}"
            log_success "Deleted key pair: ${KEY_PAIR_NAME}"
        else
            log_warning "Key pair ${KEY_PAIR_NAME} not found (may already be deleted)"
        fi
        
        # Remove local key file
        if [[ -f "${TEMP_DIR}/${KEY_PAIR_NAME}.pem" ]]; then
            rm -f "${TEMP_DIR}/${KEY_PAIR_NAME}.pem"
            log_success "Removed local key file: ${KEY_PAIR_NAME}.pem"
        fi
    else
        log_warning "No key pair name found in state file"
    fi
}

# Delete CloudWatch dashboard
delete_dashboard() {
    if [[ -n "${DASHBOARD_NAME}" ]]; then
        log_info "Deleting CloudWatch dashboard: ${DASHBOARD_NAME}"
        
        # Check if dashboard exists
        if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &>/dev/null; then
            aws cloudwatch delete-dashboards --dashboard-names "${DASHBOARD_NAME}"
            log_success "Deleted CloudWatch dashboard: ${DASHBOARD_NAME}"
        else
            log_warning "CloudWatch dashboard ${DASHBOARD_NAME} not found (may already be deleted)"
        fi
    else
        log_warning "No dashboard name found in state file"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ -d "${TEMP_DIR}" ]]; then
        # Remove all temporary files
        find "${TEMP_DIR}" -type f -name "*.json" -delete 2>/dev/null || true
        find "${TEMP_DIR}" -type f -name "*.sh" -delete 2>/dev/null || true
        find "${TEMP_DIR}" -type f -name "*.pem" -delete 2>/dev/null || true
        
        # Remove temp directory if empty
        rmdir "${TEMP_DIR}" 2>/dev/null || true
        
        log_success "Cleaned up temporary files"
    fi
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check if EC2 Fleet still exists
    if [[ -n "${FLEET_ID}" ]] && aws ec2 describe-fleets --fleet-ids "${FLEET_ID}" &>/dev/null; then
        log_error "EC2 Fleet ${FLEET_ID} still exists"
        ((cleanup_errors++))
    fi
    
    # Check if Spot Fleet still exists
    if [[ -n "${SPOT_FLEET_ID}" ]] && aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids "${SPOT_FLEET_ID}" &>/dev/null; then
        local spot_state=$(aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids "${SPOT_FLEET_ID}" --query 'SpotFleetRequestConfigs[0].SpotFleetRequestState' --output text)
        if [[ "${spot_state}" != "cancelled_terminating" ]] && [[ "${spot_state}" != "cancelled_running" ]]; then
            log_error "Spot Fleet ${SPOT_FLEET_ID} still active (state: ${spot_state})"
            ((cleanup_errors++))
        fi
    fi
    
    # Check for running instances
    local running_instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=EC2-Fleet-Demo" \
                 "Name=instance-state-name,Values=running,pending" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "${running_instances}" -gt 0 ]]; then
        log_error "${running_instances} instances still running"
        ((cleanup_errors++))
    fi
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        log_success "Cleanup validation passed"
    else
        log_error "Cleanup validation failed with ${cleanup_errors} errors"
        return 1
    fi
}

# Main cleanup function
main() {
    log_info "Starting EC2 Fleet Management cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_CLEANUP=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--force] [--help]"
                echo "  --force  Skip confirmation prompt"
                echo "  --help   Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    confirm_cleanup
    load_deployment_state
    
    # Delete resources in reverse order of creation
    delete_ec2_fleet
    delete_spot_fleet
    wait_for_instance_termination
    delete_launch_template
    delete_iam_role
    delete_security_group
    delete_key_pair
    delete_dashboard
    cleanup_temp_files
    
    validate_cleanup
    
    log_success "Cleanup completed successfully!"
    
    echo
    echo "=================================="
    echo "CLEANUP SUMMARY"
    echo "=================================="
    echo "✅ EC2 Fleet deleted"
    echo "✅ Spot Fleet deleted"
    echo "✅ Launch Template deleted"
    echo "✅ IAM Role deleted"
    echo "✅ Security Group deleted"
    echo "✅ Key Pair deleted"
    echo "✅ CloudWatch Dashboard deleted"
    echo "✅ Temporary files cleaned up"
    echo "=================================="
    echo
    echo "All resources have been successfully removed."
    echo "Check ${LOG_FILE} for detailed cleanup logs."
}

# Execute main function
main "$@"