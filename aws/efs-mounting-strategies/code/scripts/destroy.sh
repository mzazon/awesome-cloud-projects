#!/bin/bash

# Destroy script for EFS Mounting Strategies Recipe
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/deployment.state"
CONFIG_FILE="${SCRIPT_DIR}/deployment.config"
MOUNT_SCRIPTS_DIR="${SCRIPT_DIR}/mount-scripts"

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warn "Running in FORCE mode - skipping confirmation prompts"
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run: Show what would be deleted without actually deleting"
            echo "  --force: Skip confirmation prompts"
            echo "  --help: Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Function to load state
load_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2- || true
    fi
}

# Function to remove state entry
remove_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "efs")
            aws efs describe-file-systems --file-system-id "$resource_id" &>/dev/null
            ;;
        "instance")
            local state=$(aws ec2 describe-instances --instance-ids "$resource_id" \
                --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null || echo "not-found")
            [[ "$state" != "not-found" && "$state" != "terminated" ]]
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" &>/dev/null
            ;;
        "mount-target")
            aws efs describe-mount-targets --mount-target-id "$resource_id" &>/dev/null
            ;;
        "access-point")
            aws efs describe-access-points --access-point-id "$resource_id" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_id" &>/dev/null
            ;;
        "iam-instance-profile")
            aws iam get-instance-profile --instance-profile-name "$resource_id" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to confirm deletion
confirm_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Are you sure you want to delete $resource_type: $resource_id? (y/N)${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to load configuration
load_configuration() {
    log "Loading configuration..."
    
    # Check if state file exists
    if [[ ! -f "$STATE_FILE" ]]; then
        warn "State file not found: $STATE_FILE"
        warn "No deployment state found. Nothing to clean up."
        return 1
    fi
    
    # Load configuration if available
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log "Configuration loaded from $CONFIG_FILE"
    else
        warn "Configuration file not found: $CONFIG_FILE"
    fi
    
    # Load state variables
    export EFS_ID=$(load_state "EFS_ID")
    export SG_ID=$(load_state "SG_ID")
    export MT_A=$(load_state "MT_A")
    export MT_B=$(load_state "MT_B")
    export MT_C=$(load_state "MT_C")
    export AP_APP=$(load_state "AP_APP")
    export AP_USER=$(load_state "AP_USER")
    export AP_LOGS=$(load_state "AP_LOGS")
    export INSTANCE_ID=$(load_state "INSTANCE_ID")
    export IAM_ROLE=$(load_state "IAM_ROLE")
    export IAM_PROFILE=$(load_state "IAM_PROFILE")
    
    log "State loaded successfully ✅"
    return 0
}

# Function to display resources to be deleted
display_resources() {
    log "Resources to be deleted:"
    echo "======================="
    
    [[ -n "${INSTANCE_ID:-}" ]] && echo "EC2 Instance: ${INSTANCE_ID}"
    [[ -n "${AP_APP:-}" ]] && echo "Access Point (App): ${AP_APP}"
    [[ -n "${AP_USER:-}" ]] && echo "Access Point (User): ${AP_USER}"
    [[ -n "${AP_LOGS:-}" ]] && echo "Access Point (Logs): ${AP_LOGS}"
    [[ -n "${MT_A:-}" ]] && echo "Mount Target A: ${MT_A}"
    [[ -n "${MT_B:-}" ]] && echo "Mount Target B: ${MT_B}"
    [[ -n "${MT_C:-}" ]] && echo "Mount Target C: ${MT_C}"
    [[ -n "${EFS_ID:-}" ]] && echo "EFS File System: ${EFS_ID}"
    [[ -n "${IAM_PROFILE:-}" ]] && echo "IAM Instance Profile: ${IAM_PROFILE}"
    [[ -n "${IAM_ROLE:-}" ]] && echo "IAM Role: ${IAM_ROLE}"
    [[ -n "${SG_ID:-}" ]] && echo "Security Group: ${SG_ID}"
    
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN mode: No resources will actually be deleted"
        return 0
    fi
    
    if [[ "$FORCE_DELETE" != "true" ]]; then
        echo -e "${YELLOW}Do you want to proceed with deletion? (y/N)${NC}"
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                log "Proceeding with deletion..."
                ;;
            *)
                log "Deletion cancelled by user"
                exit 0
                ;;
        esac
    fi
}

# Function to terminate EC2 instance
terminate_ec2_instance() {
    if [[ -z "${INSTANCE_ID:-}" ]]; then
        info "No EC2 instance to terminate"
        return 0
    fi
    
    log "Terminating EC2 instance: ${INSTANCE_ID}"
    
    if ! resource_exists "instance" "$INSTANCE_ID"; then
        info "EC2 instance $INSTANCE_ID does not exist or is already terminated"
        remove_state "INSTANCE_ID"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would terminate EC2 instance: $INSTANCE_ID"
        return 0
    fi
    
    if confirm_deletion "EC2 instance" "$INSTANCE_ID"; then
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null
        
        # Wait for termination with timeout
        log "Waiting for EC2 instance to terminate..."
        local timeout=300
        local elapsed=0
        
        while [[ $elapsed -lt $timeout ]]; do
            local state=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query "Reservations[0].Instances[0].State.Name" --output text 2>/dev/null || echo "terminated")
            
            if [[ "$state" == "terminated" ]]; then
                break
            fi
            
            sleep 10
            elapsed=$((elapsed + 10))
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            warn "Timeout waiting for EC2 instance termination"
        else
            log "EC2 instance terminated successfully ✅"
        fi
        
        remove_state "INSTANCE_ID"
    else
        info "Skipping EC2 instance termination"
    fi
}

# Function to delete EFS access points
delete_access_points() {
    log "Deleting EFS access points..."
    
    local access_points=("$AP_APP" "$AP_USER" "$AP_LOGS")
    local access_point_names=("App" "User" "Logs")
    
    for i in "${!access_points[@]}"; do
        local ap_id="${access_points[$i]}"
        local ap_name="${access_point_names[$i]}"
        
        if [[ -z "$ap_id" ]]; then
            continue
        fi
        
        if ! resource_exists "access-point" "$ap_id"; then
            info "Access point $ap_name ($ap_id) does not exist"
            continue
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would delete access point $ap_name: $ap_id"
            continue
        fi
        
        if confirm_deletion "access point $ap_name" "$ap_id"; then
            aws efs delete-access-point --access-point-id "$ap_id"
            log "Access point $ap_name deleted successfully ✅"
        else
            info "Skipping access point $ap_name deletion"
        fi
    done
    
    # Clean up state
    remove_state "AP_APP"
    remove_state "AP_USER"
    remove_state "AP_LOGS"
}

# Function to delete EFS mount targets
delete_mount_targets() {
    log "Deleting EFS mount targets..."
    
    local mount_targets=("$MT_A" "$MT_B" "$MT_C")
    local mount_target_names=("A" "B" "C")
    
    for i in "${!mount_targets[@]}"; do
        local mt_id="${mount_targets[$i]}"
        local mt_name="${mount_target_names[$i]}"
        
        if [[ -z "$mt_id" ]]; then
            continue
        fi
        
        if ! resource_exists "mount-target" "$mt_id"; then
            info "Mount target $mt_name ($mt_id) does not exist"
            continue
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would delete mount target $mt_name: $mt_id"
            continue
        fi
        
        if confirm_deletion "mount target $mt_name" "$mt_id"; then
            aws efs delete-mount-target --mount-target-id "$mt_id"
            log "Mount target $mt_name deleted successfully ✅"
        else
            info "Skipping mount target $mt_name deletion"
        fi
    done
    
    # Wait for mount targets to be deleted
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Waiting for mount targets to be deleted..."
        sleep 30
    fi
    
    # Clean up state
    remove_state "MT_A"
    remove_state "MT_B"
    remove_state "MT_C"
}

# Function to delete EFS file system
delete_efs_filesystem() {
    if [[ -z "${EFS_ID:-}" ]]; then
        info "No EFS file system to delete"
        return 0
    fi
    
    log "Deleting EFS file system: ${EFS_ID}"
    
    if ! resource_exists "efs" "$EFS_ID"; then
        info "EFS file system $EFS_ID does not exist"
        remove_state "EFS_ID"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete EFS file system: $EFS_ID"
        return 0
    fi
    
    if confirm_deletion "EFS file system" "$EFS_ID"; then
        aws efs delete-file-system --file-system-id "$EFS_ID"
        log "EFS file system deleted successfully ✅"
        remove_state "EFS_ID"
    else
        info "Skipping EFS file system deletion"
    fi
}

# Function to clean up IAM resources
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Clean up instance profile
    if [[ -n "${IAM_PROFILE:-}" ]] && [[ -n "${IAM_ROLE:-}" ]]; then
        if resource_exists "iam-instance-profile" "$IAM_PROFILE"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY-RUN: Would clean up IAM instance profile: $IAM_PROFILE"
            else
                if confirm_deletion "IAM instance profile" "$IAM_PROFILE"; then
                    # Remove role from instance profile
                    aws iam remove-role-from-instance-profile \
                        --instance-profile-name "$IAM_PROFILE" \
                        --role-name "$IAM_ROLE" 2>/dev/null || true
                    
                    # Delete instance profile
                    aws iam delete-instance-profile \
                        --instance-profile-name "$IAM_PROFILE"
                    
                    log "IAM instance profile deleted successfully ✅"
                else
                    info "Skipping IAM instance profile deletion"
                fi
            fi
        else
            info "IAM instance profile $IAM_PROFILE does not exist"
        fi
    fi
    
    # Clean up IAM role
    if [[ -n "${IAM_ROLE:-}" ]]; then
        if resource_exists "iam-role" "$IAM_ROLE"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY-RUN: Would clean up IAM role: $IAM_ROLE"
            else
                if confirm_deletion "IAM role" "$IAM_ROLE"; then
                    # Delete role policy
                    aws iam delete-role-policy \
                        --role-name "$IAM_ROLE" \
                        --policy-name "EFS-Access-Policy" 2>/dev/null || true
                    
                    # Delete role
                    aws iam delete-role --role-name "$IAM_ROLE"
                    
                    log "IAM role deleted successfully ✅"
                else
                    info "Skipping IAM role deletion"
                fi
            fi
        else
            info "IAM role $IAM_ROLE does not exist"
        fi
    fi
    
    # Clean up state
    remove_state "IAM_ROLE"
    remove_state "IAM_PROFILE"
}

# Function to delete security group
delete_security_group() {
    if [[ -z "${SG_ID:-}" ]]; then
        info "No security group to delete"
        return 0
    fi
    
    log "Deleting security group: ${SG_ID}"
    
    if ! resource_exists "security-group" "$SG_ID"; then
        info "Security group $SG_ID does not exist"
        remove_state "SG_ID"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete security group: $SG_ID"
        return 0
    fi
    
    if confirm_deletion "security group" "$SG_ID"; then
        # Wait a bit for any resources using the security group to be cleaned up
        sleep 10
        
        aws ec2 delete-security-group --group-id "$SG_ID"
        log "Security group deleted successfully ✅"
        remove_state "SG_ID"
    else
        info "Skipping security group deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would clean up local files"
        return 0
    fi
    
    # Clean up mount scripts directory
    if [[ -d "$MOUNT_SCRIPTS_DIR" ]]; then
        rm -rf "$MOUNT_SCRIPTS_DIR"
        log "Mount scripts directory cleaned up ✅"
    fi
    
    # Clean up state and config files
    [[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE"
    [[ -f "$CONFIG_FILE" ]] && rm -f "$CONFIG_FILE"
    
    log "State and configuration files cleaned up ✅"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN mode: No resources were actually deleted"
    else
        echo "All resources have been cleaned up successfully"
    fi
    
    echo ""
    echo "The following resources were processed:"
    echo "• EC2 Instance"
    echo "• EFS Access Points"
    echo "• EFS Mount Targets"
    echo "• EFS File System"
    echo "• IAM Role and Instance Profile"
    echo "• Security Group"
    echo "• Local configuration files"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        info "Cleanup completed successfully! All AWS resources have been removed."
    fi
}

# Main execution
main() {
    log "Starting EFS Mounting Strategies cleanup..."
    
    # Load configuration and state
    if ! load_configuration; then
        exit 0
    fi
    
    # Display resources to be deleted
    display_resources
    
    # Execute cleanup in reverse order of creation
    terminate_ec2_instance
    delete_access_points
    delete_mount_targets
    delete_efs_filesystem
    cleanup_iam_resources
    delete_security_group
    cleanup_local_files
    
    # Display summary
    display_cleanup_summary
    
    log "Cleanup completed successfully! ✅"
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"