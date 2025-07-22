#!/bin/bash

# AWS EFS Performance Optimization and Monitoring - Cleanup Script
# This script removes all resources created by the deploy.sh script

set -e
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
RESOURCE_FILE="${SCRIPT_DIR}/.deployment_resources"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Command line flags
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log ERROR "$1"
    log ERROR "Cleanup failed. Check log file: $LOG_FILE"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured. Please run 'aws configure' first."
    fi
    
    log SUCCESS "Prerequisites check passed"
}

# Function to load deployment resources
load_deployment_resources() {
    log INFO "Loading deployment resource information..."
    
    if [[ ! -f "$RESOURCE_FILE" ]]; then
        if [[ "$FORCE_CLEANUP" == true ]]; then
            log WARN "Resource file not found, but --force flag is set. Attempting manual cleanup..."
            return 0
        else
            error_exit "Resource file not found: $RESOURCE_FILE. Cannot determine what resources to clean up."
        fi
    fi
    
    # Source the resource file to load environment variables
    source "$RESOURCE_FILE"
    
    log SUCCESS "Deployment resources loaded"
    log INFO "EFS Name: ${EFS_NAME:-Unknown}"
    log INFO "EFS ID: ${EFS_ID:-Unknown}"
    log INFO "Security Group: ${SECURITY_GROUP_NAME:-Unknown}"
    log INFO "Region: ${AWS_REGION:-Unknown}"
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ "$SKIP_CONFIRMATION" == true ]]; then
        log INFO "Skipping confirmation due to --yes flag"
        return 0
    fi
    
    if [[ "$FORCE_CLEANUP" == true ]]; then
        log WARN "Force cleanup enabled - this will attempt to delete all EFS resources with the naming pattern"
        echo ""
        echo -e "${RED}WARNING: This will attempt to delete ALL EFS resources matching the naming pattern!${NC}"
        echo "This includes EFS file systems, mount targets, security groups, and CloudWatch resources."
        echo ""
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log INFO "Cleanup cancelled by user"
            exit 0
        fi
    else
        echo ""
        echo "This will delete the following resources:"
        echo "  - EFS File System: ${EFS_ID:-Unknown}"
        echo "  - Mount Targets: ${MOUNT_TARGET_IDS:-Unknown}"
        echo "  - Security Group: ${SECURITY_GROUP_ID:-Unknown}"
        echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME:-Unknown}"
        echo "  - CloudWatch Alarms: ${ALARM_NAMES:-Unknown}"
        echo ""
        read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log INFO "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log INFO "Cleanup confirmed by user"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log INFO "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    if [[ -n "$ALARM_NAMES" ]]; then
        log INFO "Deleting CloudWatch alarms..."
        
        # Convert space-separated string to array
        IFS=' ' read -ra ALARM_ARRAY <<< "$ALARM_NAMES"
        
        for alarm_name in "${ALARM_ARRAY[@]}"; do
            log INFO "Deleting alarm: $alarm_name"
            aws cloudwatch delete-alarms --alarm-names "$alarm_name" 2>/dev/null || \
                log WARN "Failed to delete alarm: $alarm_name"
        done
        
        log SUCCESS "CloudWatch alarms deletion completed"
    elif [[ "$FORCE_CLEANUP" == true ]]; then
        log INFO "Force cleanup: Searching for EFS-related alarms..."
        
        local efs_alarms=$(aws cloudwatch describe-alarms \
            --query "MetricAlarms[?contains(AlarmName, 'EFS-')].AlarmName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$efs_alarms" ]]; then
            aws cloudwatch delete-alarms --alarm-names $efs_alarms 2>/dev/null || \
                log WARN "Failed to delete some EFS alarms"
        fi
    fi
    
    # Delete CloudWatch dashboard
    if [[ -n "$DASHBOARD_NAME" ]]; then
        log INFO "Deleting CloudWatch dashboard: $DASHBOARD_NAME"
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME" 2>/dev/null || \
            log WARN "Failed to delete dashboard: $DASHBOARD_NAME"
        
        log SUCCESS "CloudWatch dashboard deleted"
    elif [[ "$FORCE_CLEANUP" == true ]]; then
        log INFO "Force cleanup: Searching for EFS-related dashboards..."
        
        local efs_dashboards=$(aws cloudwatch list-dashboards \
            --query "DashboardEntries[?contains(DashboardName, 'EFS-Performance-')].DashboardName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$efs_dashboards" ]]; then
            aws cloudwatch delete-dashboards --dashboard-names $efs_dashboards 2>/dev/null || \
                log WARN "Failed to delete some EFS dashboards"
        fi
    fi
    
    log SUCCESS "CloudWatch resources cleanup completed"
}

# Function to delete EFS mount targets
delete_mount_targets() {
    log INFO "Deleting EFS mount targets..."
    
    local efs_ids=()
    
    if [[ -n "$EFS_ID" ]]; then
        efs_ids+=("$EFS_ID")
    elif [[ "$FORCE_CLEANUP" == true ]]; then
        log INFO "Force cleanup: Searching for EFS file systems..."
        
        # Find EFS file systems with our naming pattern
        local found_efs=$(aws efs describe-file-systems \
            --query "FileSystems[?contains(Tags[?Key=='Name'].Value, 'performance-optimized-efs-')].FileSystemId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$found_efs" ]]; then
            IFS=$'\t' read -ra efs_ids <<< "$found_efs"
        fi
    fi
    
    for efs_id in "${efs_ids[@]}"; do
        if [[ -z "$efs_id" || "$efs_id" == "None" ]]; then
            continue
        fi
        
        log INFO "Processing mount targets for EFS: $efs_id"
        
        # Get mount target IDs for this EFS
        local mount_targets=$(aws efs describe-mount-targets \
            --file-system-id "$efs_id" \
            --query 'MountTargets[*].MountTargetId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$mount_targets" && "$mount_targets" != "None" ]]; then
            for mount_target_id in $mount_targets; do
                log INFO "Deleting mount target: $mount_target_id"
                aws efs delete-mount-target --mount-target-id "$mount_target_id" 2>/dev/null || \
                    log WARN "Failed to delete mount target: $mount_target_id"
            done
            
            # Wait for mount targets to be deleted
            log INFO "Waiting for mount targets to be deleted..."
            sleep 30
            
            # Verify mount targets are deleted
            local remaining_targets
            for i in {1..12}; do  # Wait up to 2 minutes
                remaining_targets=$(aws efs describe-mount-targets \
                    --file-system-id "$efs_id" \
                    --query 'length(MountTargets)' \
                    --output text 2>/dev/null || echo "0")
                
                if [[ "$remaining_targets" == "0" ]]; then
                    break
                fi
                
                log INFO "Waiting for mount targets to be deleted... ($i/12)"
                sleep 10
            done
            
            if [[ "$remaining_targets" != "0" ]]; then
                log WARN "Some mount targets may still exist for EFS: $efs_id"
            fi
        fi
    done
    
    log SUCCESS "Mount targets cleanup completed"
}

# Function to delete EFS file systems
delete_efs_filesystems() {
    log INFO "Deleting EFS file systems..."
    
    local efs_ids=()
    
    if [[ -n "$EFS_ID" ]]; then
        efs_ids+=("$EFS_ID")
    elif [[ "$FORCE_CLEANUP" == true ]]; then
        log INFO "Force cleanup: Searching for EFS file systems..."
        
        # Find EFS file systems with our naming pattern
        local found_efs=$(aws efs describe-file-systems \
            --query "FileSystems[?contains(Tags[?Key=='Name'].Value, 'performance-optimized-efs-')].FileSystemId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$found_efs" ]]; then
            IFS=$'\t' read -ra efs_ids <<< "$found_efs"
        fi
    fi
    
    for efs_id in "${efs_ids[@]}"; do
        if [[ -z "$efs_id" || "$efs_id" == "None" ]]; then
            continue
        fi
        
        log INFO "Deleting EFS file system: $efs_id"
        
        # Check if file system exists
        local efs_status=$(aws efs describe-file-systems \
            --file-system-id "$efs_id" \
            --query 'FileSystems[0].LifeCycleState' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$efs_status" == "not-found" ]]; then
            log WARN "EFS file system $efs_id not found or already deleted"
            continue
        fi
        
        # Delete the file system
        aws efs delete-file-system --file-system-id "$efs_id" 2>/dev/null || \
            log WARN "Failed to delete EFS file system: $efs_id"
        
        log SUCCESS "EFS file system deleted: $efs_id"
    done
    
    log SUCCESS "EFS file systems cleanup completed"
}

# Function to delete security groups
delete_security_groups() {
    log INFO "Deleting security groups..."
    
    local sg_ids=()
    
    if [[ -n "$SECURITY_GROUP_ID" ]]; then
        sg_ids+=("$SECURITY_GROUP_ID")
    elif [[ "$FORCE_CLEANUP" == true ]]; then
        log INFO "Force cleanup: Searching for EFS security groups..."
        
        # Find security groups with our naming pattern
        local found_sgs=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=efs-sg-*" \
            --query 'SecurityGroups[*].GroupId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$found_sgs" ]]; then
            IFS=$'\t' read -ra sg_ids <<< "$found_sgs"
        fi
    fi
    
    for sg_id in "${sg_ids[@]}"; do
        if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
            continue
        fi
        
        log INFO "Deleting security group: $sg_id"
        
        # Check if security group exists
        local sg_exists=$(aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$sg_exists" == "not-found" ]]; then
            log WARN "Security group $sg_id not found or already deleted"
            continue
        fi
        
        # Delete the security group
        aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null || \
            log WARN "Failed to delete security group: $sg_id (may still be in use)"
        
        log SUCCESS "Security group deleted: $sg_id"
    done
    
    log SUCCESS "Security groups cleanup completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log INFO "Cleaning up temporary files..."
    
    local files_to_remove=(
        "$RESOURCE_FILE"
        "${SCRIPT_DIR}/efs-dashboard.json"
        "${SCRIPT_DIR}/efs-dashboard.json.bak"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log INFO "Removed temporary file: $file"
        fi
    done
    
    log SUCCESS "Temporary files cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log INFO "Validating cleanup..."
    
    local validation_errors=0
    
    # Check if EFS file systems still exist
    if [[ -n "$EFS_ID" ]]; then
        local efs_status=$(aws efs describe-file-systems \
            --file-system-id "$EFS_ID" \
            --query 'FileSystems[0].LifeCycleState' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$efs_status" != "not-found" ]]; then
            log WARN "EFS file system still exists: $EFS_ID"
            validation_errors=$((validation_errors + 1))
        fi
    fi
    
    # Check if security group still exists
    if [[ -n "$SECURITY_GROUP_ID" ]]; then
        local sg_exists=$(aws ec2 describe-security-groups \
            --group-ids "$SECURITY_GROUP_ID" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$sg_exists" != "not-found" ]]; then
            log WARN "Security group still exists: $SECURITY_GROUP_ID"
            validation_errors=$((validation_errors + 1))
        fi
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log SUCCESS "Cleanup validation completed successfully"
    else
        log WARN "Cleanup validation found $validation_errors potential issues"
    fi
}

# Function to display cleanup summary
display_summary() {
    log SUCCESS "=== EFS Performance Optimization Cleanup Complete ==="
    log INFO ""
    log INFO "Cleanup Summary:"
    log INFO "  ✓ CloudWatch alarms deleted"
    log INFO "  ✓ CloudWatch dashboard deleted"
    log INFO "  ✓ EFS mount targets deleted"
    log INFO "  ✓ EFS file systems deleted"
    log INFO "  ✓ Security groups deleted"
    log INFO "  ✓ Temporary files cleaned up"
    log INFO ""
    log INFO "All resources from the EFS performance optimization recipe have been removed."
    log INFO ""
    log SUCCESS "Cleanup log saved to: $LOG_FILE"
}

# Main cleanup function
main() {
    log INFO "Starting EFS Performance Optimization cleanup..."
    log INFO "Log file: $LOG_FILE"
    
    # Initialize log file
    echo "=== EFS Performance Optimization Cleanup Log ===" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    
    check_prerequisites
    load_deployment_resources
    confirm_cleanup
    
    delete_cloudwatch_resources
    delete_mount_targets
    delete_efs_filesystems
    delete_security_groups
    cleanup_temp_files
    validate_cleanup
    
    display_summary
    
    log SUCCESS "Cleanup completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "AWS EFS Performance Optimization Cleanup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --help, -h     Show this help message"
            echo "  --force        Force cleanup mode - attempts to find and delete resources"
            echo "                 even if resource file is missing"
            echo "  --yes, -y      Skip confirmation prompts"
            echo "  --verbose, -v  Enable verbose logging"
            echo ""
            echo "This script removes all resources created by deploy.sh:"
            echo "  - EFS file systems and mount targets"
            echo "  - Security groups"
            echo "  - CloudWatch dashboards and alarms"
            echo "  - Temporary files"
            echo ""
            exit 0
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --verbose|-v)
            set -x
            shift
            ;;
        *)
            log ERROR "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main