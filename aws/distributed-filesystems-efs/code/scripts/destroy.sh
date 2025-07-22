#!/bin/bash

# Destroy script for Building Distributed File Systems with Amazon EFS
# This script safely removes all resources created by the deploy script

set -e

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Global variables for tracking resources
RESOURCES_TO_DELETE=()
FAILED_DELETIONS=()

# Function to add resource to deletion list
add_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local resource_name="$3"
    
    RESOURCES_TO_DELETE+=("$resource_type:$resource_id:$resource_name")
}

# Function to confirm destructive action
confirm_destruction() {
    if [ "$1" = "--force" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This will permanently delete all EFS resources and data!${NC}"
    echo "The following resources will be deleted:"
    
    if [ -f "./efs-deployment-info.txt" ]; then
        echo ""
        grep -E "^- " ./efs-deployment-info.txt | head -20
    else
        echo "- All EFS file systems with 'distributed-efs' prefix"
        echo "- All associated EC2 instances"
        echo "- All security groups"
        echo "- All key pairs"
        echo "- All backup resources"
        echo "- All CloudWatch resources"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Function to load deployment info
load_deployment_info() {
    log "Loading deployment information..."
    
    if [ -f "./efs-deployment-info.txt" ]; then
        # Extract resource IDs from deployment info file
        export EFS_ID=$(grep "EFS File System ID:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export EFS_NAME=$(grep "EFS Name:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export KEY_PAIR_NAME=$(grep "Key Pair:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export EFS_SG_ID=$(grep "EFS Security Group:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export EC2_SG_ID=$(grep "EC2 Security Group:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export AP1_ID=$(grep "Access Point 1" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export AP2_ID=$(grep "Access Point 2" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export MT1_ID=$(grep "Mount Target 1:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export MT2_ID=$(grep "Mount Target 2:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export MT3_ID=$(grep "Mount Target 3:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export INSTANCE1_ID=$(grep "EC2 Instance 1:" ./efs-deployment-info.txt | cut -d':' -f2 | cut -d'(' -f1 | xargs)
        export INSTANCE2_ID=$(grep "EC2 Instance 2:" ./efs-deployment-info.txt | cut -d':' -f2 | cut -d'(' -f1 | xargs)
        export BACKUP_VAULT_NAME=$(grep "Backup Vault:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        export BACKUP_PLAN_ID=$(grep "Backup Plan:" ./efs-deployment-info.txt | cut -d':' -f2 | xargs)
        
        success "Deployment information loaded from file"
    else
        warning "No deployment info file found, will attempt to discover resources"
        discover_resources
    fi
}

# Function to discover resources if no deployment info available
discover_resources() {
    log "Discovering EFS resources..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
    fi
    
    # Find EFS file systems with our naming pattern
    EFS_SYSTEMS=$(aws efs describe-file-systems \
        --query 'FileSystems[?starts_with(Name, `distributed-efs`)].{Id:FileSystemId,Name:Name}' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$EFS_SYSTEMS" ]; then
        export EFS_ID=$(echo "$EFS_SYSTEMS" | head -1 | cut -f1)
        export EFS_NAME=$(echo "$EFS_SYSTEMS" | head -1 | cut -f2)
        log "Found EFS file system: $EFS_ID ($EFS_NAME)"
        
        # Find associated resources
        discover_associated_resources
    else
        log "No EFS file systems found with 'distributed-efs' prefix"
    fi
}

# Function to discover associated resources
discover_associated_resources() {
    log "Discovering associated resources..."
    
    # Find mount targets
    if [ -n "$EFS_ID" ]; then
        MOUNT_TARGETS=$(aws efs describe-mount-targets \
            --file-system-id $EFS_ID \
            --query 'MountTargets[].MountTargetId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$MOUNT_TARGETS" ]; then
            export MT1_ID=$(echo $MOUNT_TARGETS | cut -d' ' -f1)
            export MT2_ID=$(echo $MOUNT_TARGETS | cut -d' ' -f2)
            export MT3_ID=$(echo $MOUNT_TARGETS | cut -d' ' -f3)
        fi
        
        # Find access points
        ACCESS_POINTS=$(aws efs describe-access-points \
            --file-system-id $EFS_ID \
            --query 'AccessPoints[].AccessPointId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ACCESS_POINTS" ]; then
            export AP1_ID=$(echo $ACCESS_POINTS | cut -d' ' -f1)
            export AP2_ID=$(echo $ACCESS_POINTS | cut -d' ' -f2)
        fi
    fi
    
    # Find EC2 instances with our naming pattern
    EC2_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=*distributed-efs*" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$EC2_INSTANCES" ]; then
        export INSTANCE1_ID=$(echo $EC2_INSTANCES | cut -d' ' -f1)
        export INSTANCE2_ID=$(echo $EC2_INSTANCES | cut -d' ' -f2)
    fi
    
    # Find security groups
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=*efs*" \
        --query 'SecurityGroups[].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$SECURITY_GROUPS" ]; then
        export EFS_SG_ID=$(echo $SECURITY_GROUPS | cut -d' ' -f1)
        export EC2_SG_ID=$(echo $SECURITY_GROUPS | cut -d' ' -f2)
    fi
    
    # Find key pairs
    KEY_PAIRS=$(aws ec2 describe-key-pairs \
        --filters "Name=key-name,Values=*efs-demo*" \
        --query 'KeyPairs[].KeyName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$KEY_PAIRS" ]; then
        export KEY_PAIR_NAME=$(echo $KEY_PAIRS | cut -d' ' -f1)
    fi
}

# Function to safely unmount EFS from instances
unmount_efs_from_instances() {
    log "Unmounting EFS from EC2 instances..."
    
    # Get IP addresses of instances
    if [ -n "$INSTANCE1_ID" ]; then
        IP1=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE1_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$INSTANCE2_ID" ]; then
        IP2=$(aws ec2 describe-instances \
            --instance-ids $INSTANCE2_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text 2>/dev/null || echo "")
    fi
    
    # Unmount from first instance
    if [ -n "$IP1" ] && [ "$IP1" != "None" ] && [ -n "$KEY_PAIR_NAME" ]; then
        log "Unmounting EFS from instance 1..."
        ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            ec2-user@$IP1 "sudo umount /mnt/efs /mnt/web-content /mnt/shared-data 2>/dev/null || true" 2>/dev/null || true
    fi
    
    # Unmount from second instance
    if [ -n "$IP2" ] && [ "$IP2" != "None" ] && [ -n "$KEY_PAIR_NAME" ]; then
        log "Unmounting EFS from instance 2..."
        ssh -i ~/.ssh/${KEY_PAIR_NAME}.pem \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 \
            ec2-user@$IP2 "sudo umount /mnt/efs /mnt/web-content /mnt/shared-data 2>/dev/null || true" 2>/dev/null || true
    fi
    
    success "EFS unmount completed"
}

# Function to terminate EC2 instances
terminate_ec2_instances() {
    log "Terminating EC2 instances..."
    
    local instances_to_terminate=()
    
    if [ -n "$INSTANCE1_ID" ]; then
        instances_to_terminate+=("$INSTANCE1_ID")
    fi
    
    if [ -n "$INSTANCE2_ID" ]; then
        instances_to_terminate+=("$INSTANCE2_ID")
    fi
    
    if [ ${#instances_to_terminate[@]} -gt 0 ]; then
        aws ec2 terminate-instances \
            --instance-ids "${instances_to_terminate[@]}" >/dev/null 2>&1 || true
        
        # Wait for instances to terminate
        log "Waiting for instances to terminate..."
        for instance_id in "${instances_to_terminate[@]}"; do
            aws ec2 wait instance-terminated --instance-ids "$instance_id" 2>/dev/null || true
        done
        
        success "EC2 instances terminated"
        add_resource "EC2" "${instances_to_terminate[*]}" "Instances"
    else
        log "No EC2 instances to terminate"
    fi
}

# Function to remove backup resources
remove_backup_resources() {
    log "Removing backup resources..."
    
    # Find backup plans with our naming pattern
    if [ -z "$BACKUP_PLAN_ID" ]; then
        BACKUP_PLANS=$(aws backup list-backup-plans \
            --query 'BackupPlansList[?contains(BackupPlanName, `EFS-Daily-Backup`)].BackupPlanId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$BACKUP_PLANS" ]; then
            export BACKUP_PLAN_ID=$(echo $BACKUP_PLANS | cut -d' ' -f1)
        fi
    fi
    
    if [ -n "$BACKUP_PLAN_ID" ]; then
        # Delete backup selections
        BACKUP_SELECTIONS=$(aws backup list-backup-selections \
            --backup-plan-id $BACKUP_PLAN_ID \
            --query 'BackupSelectionsList[].SelectionId' \
            --output text 2>/dev/null || echo "")
        
        for selection_id in $BACKUP_SELECTIONS; do
            if [ -n "$selection_id" ]; then
                aws backup delete-backup-selection \
                    --backup-plan-id $BACKUP_PLAN_ID \
                    --selection-id $selection_id 2>/dev/null || true
            fi
        done
        
        # Delete backup plan
        aws backup delete-backup-plan \
            --backup-plan-id $BACKUP_PLAN_ID 2>/dev/null || true
        
        add_resource "Backup" "$BACKUP_PLAN_ID" "Plan"
        success "Backup plan removed"
    fi
    
    # Find and delete backup vault
    if [ -z "$BACKUP_VAULT_NAME" ]; then
        BACKUP_VAULTS=$(aws backup list-backup-vaults \
            --query 'BackupVaultList[?contains(BackupVaultName, `efs-backup`)].BackupVaultName' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$BACKUP_VAULTS" ]; then
            export BACKUP_VAULT_NAME=$(echo $BACKUP_VAULTS | cut -d' ' -f1)
        fi
    fi
    
    if [ -n "$BACKUP_VAULT_NAME" ]; then
        # Delete recovery points first
        RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
            --backup-vault-name $BACKUP_VAULT_NAME \
            --query 'RecoveryPoints[].RecoveryPointArn' \
            --output text 2>/dev/null || echo "")
        
        for recovery_point in $RECOVERY_POINTS; do
            if [ -n "$recovery_point" ]; then
                aws backup delete-recovery-point \
                    --backup-vault-name $BACKUP_VAULT_NAME \
                    --recovery-point-arn $recovery_point 2>/dev/null || true
            fi
        done
        
        # Wait a bit for recovery points to be deleted
        sleep 10
        
        # Delete backup vault
        aws backup delete-backup-vault \
            --backup-vault-name $BACKUP_VAULT_NAME 2>/dev/null || true
        
        add_resource "Backup" "$BACKUP_VAULT_NAME" "Vault"
        success "Backup vault removed"
    fi
}

# Function to remove access points
remove_access_points() {
    log "Removing EFS access points..."
    
    local access_points_to_delete=()
    
    if [ -n "$AP1_ID" ]; then
        access_points_to_delete+=("$AP1_ID")
    fi
    
    if [ -n "$AP2_ID" ]; then
        access_points_to_delete+=("$AP2_ID")
    fi
    
    # If no specific access points, find all for the EFS
    if [ ${#access_points_to_delete[@]} -eq 0 ] && [ -n "$EFS_ID" ]; then
        ALL_ACCESS_POINTS=$(aws efs describe-access-points \
            --file-system-id $EFS_ID \
            --query 'AccessPoints[].AccessPointId' \
            --output text 2>/dev/null || echo "")
        
        for ap_id in $ALL_ACCESS_POINTS; do
            if [ -n "$ap_id" ]; then
                access_points_to_delete+=("$ap_id")
            fi
        done
    fi
    
    for ap_id in "${access_points_to_delete[@]}"; do
        if [ -n "$ap_id" ]; then
            aws efs delete-access-point --access-point-id $ap_id 2>/dev/null || true
            add_resource "EFS" "$ap_id" "Access Point"
        fi
    done
    
    if [ ${#access_points_to_delete[@]} -gt 0 ]; then
        success "Access points removed"
    else
        log "No access points to remove"
    fi
}

# Function to remove mount targets
remove_mount_targets() {
    log "Removing EFS mount targets..."
    
    local mount_targets_to_delete=()
    
    if [ -n "$MT1_ID" ]; then
        mount_targets_to_delete+=("$MT1_ID")
    fi
    
    if [ -n "$MT2_ID" ]; then
        mount_targets_to_delete+=("$MT2_ID")
    fi
    
    if [ -n "$MT3_ID" ]; then
        mount_targets_to_delete+=("$MT3_ID")
    fi
    
    # If no specific mount targets, find all for the EFS
    if [ ${#mount_targets_to_delete[@]} -eq 0 ] && [ -n "$EFS_ID" ]; then
        ALL_MOUNT_TARGETS=$(aws efs describe-mount-targets \
            --file-system-id $EFS_ID \
            --query 'MountTargets[].MountTargetId' \
            --output text 2>/dev/null || echo "")
        
        for mt_id in $ALL_MOUNT_TARGETS; do
            if [ -n "$mt_id" ]; then
                mount_targets_to_delete+=("$mt_id")
            fi
        done
    fi
    
    for mt_id in "${mount_targets_to_delete[@]}"; do
        if [ -n "$mt_id" ]; then
            aws efs delete-mount-target --mount-target-id $mt_id 2>/dev/null || true
            add_resource "EFS" "$mt_id" "Mount Target"
        fi
    done
    
    if [ ${#mount_targets_to_delete[@]} -gt 0 ]; then
        # Wait for mount targets to be deleted
        log "Waiting for mount targets to be deleted..."
        sleep 60
        success "Mount targets removed"
    else
        log "No mount targets to remove"
    fi
}

# Function to remove EFS file system
remove_efs_filesystem() {
    log "Removing EFS file system..."
    
    if [ -n "$EFS_ID" ]; then
        # Remove lifecycle policy
        aws efs delete-lifecycle-policy \
            --file-system-id $EFS_ID 2>/dev/null || true
        
        # Remove file system policy
        aws efs delete-file-system-policy \
            --file-system-id $EFS_ID 2>/dev/null || true
        
        # Delete EFS file system
        aws efs delete-file-system --file-system-id $EFS_ID 2>/dev/null || true
        
        add_resource "EFS" "$EFS_ID" "File System"
        success "EFS file system removed"
    else
        log "No EFS file system to remove"
    fi
}

# Function to remove security groups
remove_security_groups() {
    log "Removing security groups..."
    
    local security_groups_to_delete=()
    
    if [ -n "$EFS_SG_ID" ]; then
        security_groups_to_delete+=("$EFS_SG_ID")
    fi
    
    if [ -n "$EC2_SG_ID" ]; then
        security_groups_to_delete+=("$EC2_SG_ID")
    fi
    
    # If no specific security groups, find all with our naming pattern
    if [ ${#security_groups_to_delete[@]} -eq 0 ]; then
        ALL_SECURITY_GROUPS=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=*efs*" \
            --query 'SecurityGroups[].GroupId' \
            --output text 2>/dev/null || echo "")
        
        for sg_id in $ALL_SECURITY_GROUPS; do
            if [ -n "$sg_id" ]; then
                security_groups_to_delete+=("$sg_id")
            fi
        done
    fi
    
    for sg_id in "${security_groups_to_delete[@]}"; do
        if [ -n "$sg_id" ]; then
            aws ec2 delete-security-group --group-id $sg_id 2>/dev/null || true
            add_resource "EC2" "$sg_id" "Security Group"
        fi
    done
    
    if [ ${#security_groups_to_delete[@]} -gt 0 ]; then
        success "Security groups removed"
    else
        log "No security groups to remove"
    fi
}

# Function to remove key pair
remove_key_pair() {
    log "Removing key pair..."
    
    if [ -n "$KEY_PAIR_NAME" ]; then
        aws ec2 delete-key-pair --key-name $KEY_PAIR_NAME 2>/dev/null || true
        rm -f ~/.ssh/${KEY_PAIR_NAME}.pem 2>/dev/null || true
        
        add_resource "EC2" "$KEY_PAIR_NAME" "Key Pair"
        success "Key pair removed"
    else
        log "No key pair to remove"
    fi
}

# Function to remove CloudWatch resources
remove_cloudwatch_resources() {
    log "Removing CloudWatch resources..."
    
    # Remove CloudWatch dashboard
    if [ -n "$EFS_NAME" ]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "EFS-${EFS_NAME}" 2>/dev/null || true
        
        # Remove CloudWatch log group
        aws logs delete-log-group \
            --log-group-name "/aws/efs/${EFS_NAME}" 2>/dev/null || true
        
        add_resource "CloudWatch" "EFS-${EFS_NAME}" "Dashboard and Logs"
        success "CloudWatch resources removed"
    else
        # Try to find and remove any EFS-related dashboards
        DASHBOARDS=$(aws cloudwatch list-dashboards \
            --query 'DashboardEntries[?contains(DashboardName, `EFS-`)].DashboardName' \
            --output text 2>/dev/null || echo "")
        
        for dashboard in $DASHBOARDS; do
            if [ -n "$dashboard" ]; then
                aws cloudwatch delete-dashboards \
                    --dashboard-names "$dashboard" 2>/dev/null || true
            fi
        done
        
        log "CloudWatch cleanup completed"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    rm -f /tmp/user-data.sh 2>/dev/null || true
    rm -f /tmp/dashboard.json 2>/dev/null || true
    rm -f /tmp/backup-plan.json 2>/dev/null || true
    rm -f /tmp/backup-selection.json 2>/dev/null || true
    rm -f /tmp/file-system-policy.json 2>/dev/null || true
    rm -f /tmp/efs-deployment-info.txt 2>/dev/null || true
    
    success "Temporary files cleaned up"
}

# Function to display summary
display_summary() {
    log "Destruction Summary:"
    
    if [ ${#RESOURCES_TO_DELETE[@]} -gt 0 ]; then
        echo "Resources successfully deleted:"
        for resource in "${RESOURCES_TO_DELETE[@]}"; do
            IFS=':' read -r type id name <<< "$resource"
            echo "  ✅ $type: $name ($id)"
        done
    fi
    
    if [ ${#FAILED_DELETIONS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Resources that failed to delete:${NC}"
        for resource in "${FAILED_DELETIONS[@]}"; do
            echo "  ❌ $resource"
        done
        echo -e "\n${YELLOW}You may need to manually delete these resources from the AWS console${NC}"
    fi
    
    # Remove deployment info file
    if [ -f "./efs-deployment-info.txt" ]; then
        rm -f "./efs-deployment-info.txt"
        success "Deployment info file removed"
    fi
    
    echo ""
    success "EFS infrastructure destruction completed!"
    
    if [ ${#FAILED_DELETIONS[@]} -eq 0 ]; then
        log "All resources were successfully deleted"
    else
        warning "Some resources may require manual cleanup"
    fi
}

# Main execution
main() {
    log "Starting EFS infrastructure destruction..."
    
    # Check if force flag is provided
    confirm_destruction "$1"
    
    # Load deployment information
    load_deployment_info
    
    # Execute destruction in proper order
    unmount_efs_from_instances
    terminate_ec2_instances
    remove_backup_resources
    remove_access_points
    remove_mount_targets
    remove_efs_filesystem
    remove_security_groups
    remove_key_pair
    remove_cloudwatch_resources
    cleanup_temp_files
    
    # Display summary
    display_summary
}

# Run main function
main "$@"