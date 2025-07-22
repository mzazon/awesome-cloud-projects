#!/bin/bash

# AWS FSx High-Performance File Systems Cleanup Script
# This script removes all resources created by the FSx deployment
# Recipe: High-Throughput Shared Storage System

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_NAME="FSx Cleanup"
LOG_FILE="/tmp/fsx-destroy-$(date +%Y%m%d-%H%M%S).log"
CLEANUP_START_TIME=$(date +%s)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log ERROR "Script failed at line $line_number with exit code $exit_code"
    log ERROR "Check log file: $LOG_FILE"
    log ERROR "Some resources may still exist and need manual cleanup"
    exit $exit_code
}

# Trap errors
trap 'handle_error $LINENO' ERR

# Prerequisites check function
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured or invalid"
        exit 1
    fi
    
    log SUCCESS "Prerequisites check completed"
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_id=$2
    local timeout=${3:-1800}  # 30 minutes default
    local start_time=$(date +%s)
    
    log INFO "Waiting for $resource_type $resource_id to be deleted (timeout: ${timeout}s)..."
    
    case $resource_type in
        "file-system")
            while true; do
                local current_time=$(date +%s)
                if [[ $((current_time - start_time)) -gt $timeout ]]; then
                    log WARNING "Timeout waiting for file system $resource_id deletion"
                    return 1
                fi
                
                local status
                status=$(aws fsx describe-file-systems \
                    --file-system-ids "$resource_id" \
                    --query 'FileSystems[0].Lifecycle' \
                    --output text 2>/dev/null || echo "DELETED")
                
                if [[ "$status" == "DELETED" || "$status" == "None" ]]; then
                    break
                fi
                
                log INFO "File system $resource_id status: $status, waiting..."
                sleep 30
            done
            ;;
        "storage-virtual-machine")
            while true; do
                local current_time=$(date +%s)
                if [[ $((current_time - start_time)) -gt $timeout ]]; then
                    log WARNING "Timeout waiting for SVM $resource_id deletion"
                    return 1
                fi
                
                local status
                status=$(aws fsx describe-storage-virtual-machines \
                    --storage-virtual-machine-ids "$resource_id" \
                    --query 'StorageVirtualMachines[0].Lifecycle' \
                    --output text 2>/dev/null || echo "DELETED")
                
                if [[ "$status" == "DELETED" || "$status" == "None" ]]; then
                    break
                fi
                
                log INFO "SVM $resource_id status: $status, waiting..."
                sleep 30
            done
            ;;
        "volume")
            while true; do
                local current_time=$(date +%s)
                if [[ $((current_time - start_time)) -gt $timeout ]]; then
                    log WARNING "Timeout waiting for volume $resource_id deletion"
                    return 1
                fi
                
                local status
                status=$(aws fsx describe-volumes \
                    --volume-ids "$resource_id" \
                    --query 'Volumes[0].Lifecycle' \
                    --output text 2>/dev/null || echo "DELETED")
                
                if [[ "$status" == "DELETED" || "$status" == "None" ]]; then
                    break
                fi
                
                log INFO "Volume $resource_id status: $status, waiting..."
                sleep 15
            done
            ;;
    esac
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log SUCCESS "$resource_type $resource_id deleted successfully (waited ${duration}s)"
}

# Function to get resource IDs by prefix
get_resources_by_prefix() {
    local prefix=$1
    log INFO "Discovering resources with prefix: $prefix"
    
    # Get FSx file systems
    LUSTRE_FS_IDS=$(aws fsx describe-file-systems \
        --query "FileSystems[?contains(Tags[?Key=='Name'].Value, '$prefix-lustre')].FileSystemId" \
        --output text)
    
    WINDOWS_FS_IDS=$(aws fsx describe-file-systems \
        --query "FileSystems[?contains(Tags[?Key=='Name'].Value, '$prefix-windows')].FileSystemId" \
        --output text)
    
    ONTAP_FS_IDS=$(aws fsx describe-file-systems \
        --query "FileSystems[?contains(Tags[?Key=='Name'].Value, '$prefix-ontap')].FileSystemId" \
        --output text)
    
    # Get SVMs
    SVM_IDS=$(aws fsx describe-storage-virtual-machines \
        --query "StorageVirtualMachines[?contains(Tags[?Key=='Name'].Value, '$prefix-svm')].StorageVirtualMachineId" \
        --output text)
    
    # Get volumes
    NFS_VOLUME_IDS=$(aws fsx describe-volumes \
        --query "Volumes[?contains(Tags[?Key=='Name'].Value, '$prefix-nfs-volume')].VolumeId" \
        --output text)
    
    SMB_VOLUME_IDS=$(aws fsx describe-volumes \
        --query "Volumes[?contains(Tags[?Key=='Name'].Value, '$prefix-smb-volume')].VolumeId" \
        --output text)
    
    # Get security groups
    FSX_SG_IDS=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${prefix}-sg" \
        --query 'SecurityGroups[].GroupId' --output text)
    
    # Get S3 buckets
    S3_BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '$prefix-lustre-data')].Name" \
        --output text)
    
    # Get CloudWatch alarms
    CW_ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$prefix" \
        --query 'MetricAlarms[].AlarmName' --output text)
    
    # Get IAM roles
    IAM_ROLES=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '$prefix-service-role')].RoleName" \
        --output text)
}

# Function to delete volumes
delete_volumes() {
    # Delete NFS volumes
    if [[ -n "$NFS_VOLUME_IDS" && "$NFS_VOLUME_IDS" != "None" ]]; then
        for volume_id in $NFS_VOLUME_IDS; do
            log INFO "Deleting NFS volume: $volume_id"
            aws fsx delete-volume --volume-id "$volume_id" || log WARNING "Failed to delete NFS volume $volume_id"
        done
        
        # Wait for NFS volumes to be deleted
        for volume_id in $NFS_VOLUME_IDS; do
            wait_for_deletion "volume" "$volume_id" 600 || log WARNING "Volume $volume_id may still exist"
        done
    fi
    
    # Delete SMB volumes
    if [[ -n "$SMB_VOLUME_IDS" && "$SMB_VOLUME_IDS" != "None" ]]; then
        for volume_id in $SMB_VOLUME_IDS; do
            log INFO "Deleting SMB volume: $volume_id"
            aws fsx delete-volume --volume-id "$volume_id" || log WARNING "Failed to delete SMB volume $volume_id"
        done
        
        # Wait for SMB volumes to be deleted
        for volume_id in $SMB_VOLUME_IDS; do
            wait_for_deletion "volume" "$volume_id" 600 || log WARNING "Volume $volume_id may still exist"
        done
    fi
    
    log SUCCESS "Volume deletion completed"
}

# Function to delete SVMs
delete_svms() {
    if [[ -n "$SVM_IDS" && "$SVM_IDS" != "None" ]]; then
        for svm_id in $SVM_IDS; do
            log INFO "Deleting Storage Virtual Machine: $svm_id"
            aws fsx delete-storage-virtual-machine \
                --storage-virtual-machine-id "$svm_id" || log WARNING "Failed to delete SVM $svm_id"
        done
        
        # Wait for SVMs to be deleted
        for svm_id in $SVM_IDS; do
            wait_for_deletion "storage-virtual-machine" "$svm_id" 900 || log WARNING "SVM $svm_id may still exist"
        done
        
        log SUCCESS "SVM deletion completed"
    fi
}

# Function to delete file systems
delete_file_systems() {
    # Delete Lustre file systems
    if [[ -n "$LUSTRE_FS_IDS" && "$LUSTRE_FS_IDS" != "None" ]]; then
        for fs_id in $LUSTRE_FS_IDS; do
            log INFO "Deleting Lustre file system: $fs_id"
            aws fsx delete-file-system --file-system-id "$fs_id" || log WARNING "Failed to delete Lustre FS $fs_id"
        done
    fi
    
    # Delete Windows file systems
    if [[ -n "$WINDOWS_FS_IDS" && "$WINDOWS_FS_IDS" != "None" ]]; then
        for fs_id in $WINDOWS_FS_IDS; do
            log INFO "Deleting Windows file system: $fs_id"
            aws fsx delete-file-system --file-system-id "$fs_id" || log WARNING "Failed to delete Windows FS $fs_id"
        done
    fi
    
    # Delete ONTAP file systems
    if [[ -n "$ONTAP_FS_IDS" && "$ONTAP_FS_IDS" != "None" ]]; then
        for fs_id in $ONTAP_FS_IDS; do
            log INFO "Deleting ONTAP file system: $fs_id"
            aws fsx delete-file-system --file-system-id "$fs_id" || log WARNING "Failed to delete ONTAP FS $fs_id"
        done
    fi
    
    # Wait for all file systems to be deleted
    for fs_id in $LUSTRE_FS_IDS $WINDOWS_FS_IDS $ONTAP_FS_IDS; do
        if [[ -n "$fs_id" && "$fs_id" != "None" ]]; then
            wait_for_deletion "file-system" "$fs_id" 1800 || log WARNING "File system $fs_id may still exist"
        fi
    done
    
    log SUCCESS "File system deletion completed"
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    if [[ -n "$CW_ALARMS" && "$CW_ALARMS" != "None" ]]; then
        log INFO "Deleting CloudWatch alarms..."
        for alarm in $CW_ALARMS; do
            log INFO "Deleting alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm" || log WARNING "Failed to delete alarm $alarm"
        done
        log SUCCESS "CloudWatch alarms deleted"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    if [[ -n "$IAM_ROLES" && "$IAM_ROLES" != "None" ]]; then
        for role in $IAM_ROLES; do
            log INFO "Deleting IAM role: $role"
            
            # Detach policies
            aws iam detach-role-policy \
                --role-name "$role" \
                --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$role" || log WARNING "Failed to delete IAM role $role"
        done
        log SUCCESS "IAM roles deleted"
    fi
}

# Function to delete security groups
delete_security_groups() {
    if [[ -n "$FSX_SG_IDS" && "$FSX_SG_IDS" != "None" ]]; then
        for sg_id in $FSX_SG_IDS; do
            log INFO "Deleting security group: $sg_id"
            
            # Wait a bit to ensure all resources using SG are gone
            sleep 30
            
            # Try to delete security group multiple times
            local retry_count=0
            while [[ $retry_count -lt 5 ]]; do
                if aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null; then
                    log SUCCESS "Security group $sg_id deleted"
                    break
                else
                    retry_count=$((retry_count + 1))
                    log WARNING "Attempt $retry_count failed to delete security group $sg_id, retrying in 30s..."
                    sleep 30
                fi
            done
            
            if [[ $retry_count -eq 5 ]]; then
                log ERROR "Failed to delete security group $sg_id after 5 attempts"
            fi
        done
    fi
}

# Function to delete S3 buckets
delete_s3_buckets() {
    if [[ -n "$S3_BUCKETS" && "$S3_BUCKETS" != "None" ]]; then
        for bucket in $S3_BUCKETS; do
            log INFO "Deleting S3 bucket: $bucket"
            
            # Delete all objects first
            aws s3 rm "s3://$bucket" --recursive || log WARNING "Failed to empty bucket $bucket"
            
            # Delete bucket
            aws s3 rb "s3://$bucket" --force || log WARNING "Failed to delete bucket $bucket"
        done
        log SUCCESS "S3 buckets deleted"
    fi
}

# Function to display summary
display_cleanup_summary() {
    echo ""
    echo "=== Cleanup Summary ==="
    echo "Resources processed:"
    echo "  Lustre File Systems: ${LUSTRE_FS_IDS:-None}"
    echo "  Windows File Systems: ${WINDOWS_FS_IDS:-None}"
    echo "  ONTAP File Systems: ${ONTAP_FS_IDS:-None}"
    echo "  Storage Virtual Machines: ${SVM_IDS:-None}"
    echo "  NFS Volumes: ${NFS_VOLUME_IDS:-None}"
    echo "  SMB Volumes: ${SMB_VOLUME_IDS:-None}"
    echo "  Security Groups: ${FSX_SG_IDS:-None}"
    echo "  S3 Buckets: ${S3_BUCKETS:-None}"
    echo "  CloudWatch Alarms: ${CW_ALARMS:-None}"
    echo "  IAM Roles: ${IAM_ROLES:-None}"
    echo ""
}

# Function to confirm deletion
confirm_deletion() {
    local prefix=$1
    
    echo ""
    echo "=========================================================="
    echo "    AWS FSx High-Performance File Systems Cleanup"
    echo "=========================================================="
    echo ""
    
    if [[ -n "$prefix" ]]; then
        log INFO "Resources to be deleted with prefix: $prefix"
    else
        log INFO "Scanning for all FSx demo resources..."
    fi
    
    get_resources_by_prefix "${prefix:-fsx-demo}"
    display_cleanup_summary
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete all resources shown above!"
    echo ""
    echo "This action cannot be undone. All data will be lost."
    echo ""
    
    # Require explicit confirmation
    read -p "Type 'DELETE' to confirm resource deletion: " -r
    echo
    
    if [[ $REPLY != "DELETE" ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Are you absolutely sure? Type 'YES' to proceed: " -r
    echo
    
    if [[ $REPLY != "YES" ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
}

# Main script execution
main() {
    local prefix=""
    local force_cleanup=false
    local deployment_info_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --prefix)
                prefix="$2"
                shift 2
                ;;
            --force)
                force_cleanup=true
                shift
                ;;
            --deployment-info)
                deployment_info_file="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --prefix PREFIX          Specify resource prefix to delete"
                echo "  --force                   Skip confirmation prompts"
                echo "  --deployment-info FILE    Load deployment info from file"
                echo "  --help                    Show this help message"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log INFO "Starting $SCRIPT_NAME at $(date)"
    log INFO "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment info if provided
    if [[ -n "$deployment_info_file" && -f "$deployment_info_file" ]]; then
        log INFO "Loading deployment info from: $deployment_info_file"
        # shellcheck source=/dev/null
        source "$deployment_info_file"
        prefix="$FSX_PREFIX"
    fi
    
    # If no prefix provided, look for recent deployment info files
    if [[ -z "$prefix" ]]; then
        local latest_info_file
        latest_info_file=$(find /tmp -name "fsx-deployment-*.info" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [[ -n "$latest_info_file" && -f "$latest_info_file" ]]; then
            log INFO "Found recent deployment info: $latest_info_file"
            read -p "Use this deployment info? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # shellcheck source=/dev/null
                source "$latest_info_file"
                prefix="$FSX_PREFIX"
            fi
        fi
    fi
    
    # Confirm deletion unless force is specified
    if [[ "$force_cleanup" != "true" ]]; then
        confirm_deletion "$prefix"
    fi
    
    # Set default prefix if none provided
    if [[ -z "$prefix" ]]; then
        prefix="fsx-demo"
        log WARNING "No prefix specified, using default: $prefix"
    fi
    
    # Get all resources
    get_resources_by_prefix "$prefix"
    
    # Start cleanup process
    log INFO "Starting cleanup process..."
    
    # Delete resources in reverse order of creation
    delete_volumes
    delete_svms
    delete_file_systems
    delete_cloudwatch_alarms
    delete_iam_roles
    delete_security_groups
    delete_s3_buckets
    
    # Calculate cleanup time
    CLEANUP_END_TIME=$(date +%s)
    CLEANUP_DURATION=$((CLEANUP_END_TIME - CLEANUP_START_TIME))
    
    log SUCCESS "Cleanup completed successfully!"
    log INFO "Total cleanup time: ${CLEANUP_DURATION} seconds"
    log INFO "Log file available at: $LOG_FILE"
    
    echo ""
    echo "==========================================================="
    echo "    AWS FSx Resources Cleanup Completed!"
    echo "==========================================================="
    echo ""
    echo "All FSx resources have been deleted."
    echo "Please verify in the AWS Console that all resources are gone."
    echo ""
}

# Run main function with all arguments
main "$@"