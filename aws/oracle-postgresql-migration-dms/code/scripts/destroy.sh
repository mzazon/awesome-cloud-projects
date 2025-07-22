#!/bin/bash

# Database Migration from Oracle to PostgreSQL - Cleanup Script
# This script removes all AWS resources created for the migration infrastructure

set -euo pipefail

# Color codes for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_DIR}/cleanup.log"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "Starting Oracle to PostgreSQL migration infrastructure cleanup"

# Load environment variables
load_environment() {
    if [[ -f "${PROJECT_DIR}/.env" ]]; then
        log "Loading environment variables from .env file..."
        source "${PROJECT_DIR}/.env"
        success "Environment variables loaded"
    else
        error ".env file not found. Cannot proceed with cleanup."
        echo "Please ensure the deploy.sh script was run successfully first."
        exit 1
    fi
}

# Confirmation prompt
confirm_cleanup() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will DELETE ALL resources for the migration project:"
    echo "  - Project: ${MIGRATION_PROJECT_NAME:-unknown}"
    echo "  - Aurora PostgreSQL cluster and instance"
    echo "  - DMS replication instance"
    echo "  - DMS endpoints and tasks"
    echo "  - VPC and all networking components"
    echo "  - CloudWatch dashboard and alarms"
    echo "  - Configuration files and logs"
    echo ""
    echo "💰 This will stop all billing for these resources."
    echo ""
    
    if [[ "${FORCE_CLEANUP:-}" == "true" ]]; then
        warning "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Cleanup confirmed. Starting resource deletion..."
}

# Stop and delete DMS tasks
cleanup_dms_tasks() {
    log "Cleaning up DMS migration tasks..."
    
    local task_name="${MIGRATION_PROJECT_NAME}-task"
    
    # Check if task exists
    if aws dms describe-replication-tasks \
        --replication-task-identifier "$task_name" &>/dev/null; then
        
        log "Found migration task: $task_name"
        
        # Get task ARN
        local task_arn=$(aws dms describe-replication-tasks \
            --replication-task-identifier "$task_name" \
            --query 'ReplicationTasks[0].ReplicationTaskArn' --output text)
        
        # Stop task if running
        local task_status=$(aws dms describe-replication-tasks \
            --replication-task-identifier "$task_name" \
            --query 'ReplicationTasks[0].Status' --output text)
        
        if [[ "$task_status" == "running" ]]; then
            log "Stopping migration task..."
            aws dms stop-replication-task --replication-task-arn "$task_arn"
            
            # Wait for task to stop
            log "Waiting for task to stop..."
            while true; do
                task_status=$(aws dms describe-replication-tasks \
                    --replication-task-identifier "$task_name" \
                    --query 'ReplicationTasks[0].Status' --output text)
                
                if [[ "$task_status" == "stopped" ]] || [[ "$task_status" == "failed" ]]; then
                    break
                fi
                
                sleep 10
            done
        fi
        
        # Delete task
        log "Deleting migration task..."
        aws dms delete-replication-task --replication-task-arn "$task_arn"
        success "Migration task deleted"
    else
        log "No migration task found to delete"
    fi
}

# Delete DMS endpoints
cleanup_dms_endpoints() {
    log "Cleaning up DMS endpoints..."
    
    # Delete Oracle source endpoint
    if aws dms describe-endpoints \
        --endpoint-identifier oracle-source-endpoint &>/dev/null; then
        
        local endpoint_arn=$(aws dms describe-endpoints \
            --endpoint-identifier oracle-source-endpoint \
            --query 'Endpoints[0].EndpointArn' --output text)
        
        log "Deleting Oracle source endpoint..."
        aws dms delete-endpoint --endpoint-arn "$endpoint_arn"
        success "Oracle source endpoint deleted"
    else
        log "Oracle source endpoint not found"
    fi
    
    # Delete PostgreSQL target endpoint
    if aws dms describe-endpoints \
        --endpoint-identifier postgresql-target-endpoint &>/dev/null; then
        
        local endpoint_arn=$(aws dms describe-endpoints \
            --endpoint-identifier postgresql-target-endpoint \
            --query 'Endpoints[0].EndpointArn' --output text)
        
        log "Deleting PostgreSQL target endpoint..."
        aws dms delete-endpoint --endpoint-arn "$endpoint_arn"
        success "PostgreSQL target endpoint deleted"
    else
        log "PostgreSQL target endpoint not found"
    fi
}

# Delete DMS replication instance
cleanup_dms_instance() {
    log "Cleaning up DMS replication instance..."
    
    if aws dms describe-replication-instances \
        --replication-instance-identifier "${REPLICATION_INSTANCE_ID}" &>/dev/null; then
        
        local instance_arn=$(aws dms describe-replication-instances \
            --replication-instance-identifier "${REPLICATION_INSTANCE_ID}" \
            --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)
        
        log "Deleting DMS replication instance..."
        aws dms delete-replication-instance --replication-instance-arn "$instance_arn"
        
        # Wait for deletion
        log "Waiting for DMS instance deletion (this may take several minutes)..."
        while aws dms describe-replication-instances \
            --replication-instance-identifier "${REPLICATION_INSTANCE_ID}" &>/dev/null; do
            sleep 30
        done
        
        success "DMS replication instance deleted"
    else
        log "DMS replication instance not found"
    fi
}

# Delete Aurora cluster and instance
cleanup_aurora_cluster() {
    log "Cleaning up Aurora PostgreSQL cluster..."
    
    # Delete Aurora instance first
    if aws rds describe-db-instances \
        --db-instance-identifier "${AURORA_CLUSTER_ID}-instance-1" &>/dev/null; then
        
        log "Deleting Aurora instance..."
        aws rds delete-db-instance \
            --db-instance-identifier "${AURORA_CLUSTER_ID}-instance-1" \
            --skip-final-snapshot
        
        # Wait for instance deletion
        log "Waiting for Aurora instance deletion..."
        aws rds wait db-instance-deleted \
            --db-instance-identifier "${AURORA_CLUSTER_ID}-instance-1"
        
        success "Aurora instance deleted"
    else
        log "Aurora instance not found"
    fi
    
    # Delete Aurora cluster
    if aws rds describe-db-clusters \
        --db-cluster-identifier "${AURORA_CLUSTER_ID}" &>/dev/null; then
        
        log "Deleting Aurora cluster..."
        aws rds delete-db-cluster \
            --db-cluster-identifier "${AURORA_CLUSTER_ID}" \
            --skip-final-snapshot
        
        # Wait for cluster deletion
        log "Waiting for Aurora cluster deletion..."
        aws rds wait db-cluster-deleted \
            --db-cluster-identifier "${AURORA_CLUSTER_ID}"
        
        success "Aurora cluster deleted"
    else
        log "Aurora cluster not found"
    fi
}

# Delete subnet groups
cleanup_subnet_groups() {
    log "Cleaning up subnet groups..."
    
    # Delete DMS subnet group
    if aws dms describe-replication-subnet-groups \
        --replication-subnet-group-identifier "${DMS_SUBNET_GROUP_NAME}" &>/dev/null; then
        
        log "Deleting DMS subnet group..."
        aws dms delete-replication-subnet-group \
            --replication-subnet-group-identifier "${DMS_SUBNET_GROUP_NAME}"
        success "DMS subnet group deleted"
    else
        log "DMS subnet group not found"
    fi
    
    # Delete RDS subnet group
    if aws rds describe-db-subnet-groups \
        --db-subnet-group-name "${AURORA_CLUSTER_ID}-subnet-group" &>/dev/null; then
        
        log "Deleting RDS subnet group..."
        aws rds delete-db-subnet-group \
            --db-subnet-group-name "${AURORA_CLUSTER_ID}-subnet-group"
        success "RDS subnet group deleted"
    else
        log "RDS subnet group not found"
    fi
}

# Delete networking components
cleanup_networking() {
    log "Cleaning up networking components..."
    
    # Delete security group
    if [[ -n "${VPC_SECURITY_GROUP_ID:-}" ]]; then
        if aws ec2 describe-security-groups \
            --group-ids "${VPC_SECURITY_GROUP_ID}" &>/dev/null; then
            
            log "Deleting security group..."
            aws ec2 delete-security-group --group-id "${VPC_SECURITY_GROUP_ID}"
            success "Security group deleted"
        else
            log "Security group not found"
        fi
    fi
    
    # Disassociate and delete route table
    if [[ -n "${ROUTE_TABLE_ID:-}" ]]; then
        if aws ec2 describe-route-tables \
            --route-table-ids "${ROUTE_TABLE_ID}" &>/dev/null; then
            
            log "Deleting route table..."
            aws ec2 delete-route-table --route-table-id "${ROUTE_TABLE_ID}"
            success "Route table deleted"
        else
            log "Route table not found"
        fi
    fi
    
    # Delete subnets
    for subnet_id in "${SUBNET_1_ID:-}" "${SUBNET_2_ID:-}"; do
        if [[ -n "$subnet_id" ]]; then
            if aws ec2 describe-subnets --subnet-ids "$subnet_id" &>/dev/null; then
                log "Deleting subnet: $subnet_id"
                aws ec2 delete-subnet --subnet-id "$subnet_id"
                success "Subnet $subnet_id deleted"
            else
                log "Subnet $subnet_id not found"
            fi
        fi
    done
    
    # Detach and delete internet gateway
    if [[ -n "${IGW_ID:-}" ]] && [[ -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-internet-gateways \
            --internet-gateway-ids "${IGW_ID}" &>/dev/null; then
            
            log "Detaching internet gateway..."
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "${IGW_ID}" \
                --vpc-id "${VPC_ID}" || true
            
            log "Deleting internet gateway..."
            aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}"
            success "Internet gateway deleted"
        else
            log "Internet gateway not found"
        fi
    fi
    
    # Delete VPC
    if [[ -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" &>/dev/null; then
            log "Deleting VPC..."
            aws ec2 delete-vpc --vpc-id "${VPC_ID}"
            success "VPC deleted"
        else
            log "VPC not found"
        fi
    fi
}

# Delete CloudWatch resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # Delete CloudWatch dashboard
    if aws cloudwatch list-dashboards \
        --query "DashboardEntries[?DashboardName=='${MIGRATION_PROJECT_NAME}-dashboard']" \
        --output text | grep -q "${MIGRATION_PROJECT_NAME}-dashboard"; then
        
        log "Deleting CloudWatch dashboard..."
        aws cloudwatch delete-dashboards \
            --dashboard-names "${MIGRATION_PROJECT_NAME}-dashboard"
        success "CloudWatch dashboard deleted"
    else
        log "CloudWatch dashboard not found"
    fi
    
    # Delete CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "${MIGRATION_PROJECT_NAME}" \
        --query 'MetricAlarms[].AlarmName' --output text)
    
    if [[ -n "$alarms" ]]; then
        log "Deleting CloudWatch alarms..."
        aws cloudwatch delete-alarms --alarm-names $alarms
        success "CloudWatch alarms deleted"
    else
        log "No CloudWatch alarms found"
    fi
}

# Clean up IAM roles (optional - only if created specifically for this project)
cleanup_iam_roles() {
    log "Cleaning up IAM roles..."
    
    warning "Note: DMS service roles (dms-vpc-role, dms-cloudwatch-logs-role) are shared resources"
    warning "They will not be deleted to avoid affecting other DMS instances"
    
    # Only delete if they were tagged with our project
    for role in "dms-vpc-role" "dms-cloudwatch-logs-role"; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            local project_tag=$(aws iam list-role-tags --role-name "$role" \
                --query "Tags[?Key=='Project'].Value" --output text 2>/dev/null || echo "")
            
            if [[ "$project_tag" == "${MIGRATION_PROJECT_NAME}" ]]; then
                log "Deleting project-specific IAM role: $role"
                aws iam detach-role-policy --role-name "$role" \
                    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole" 2>/dev/null || true
                aws iam detach-role-policy --role-name "$role" \
                    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole" 2>/dev/null || true
                aws iam delete-role --role-name "$role"
                success "IAM role $role deleted"
            else
                log "IAM role $role is shared, not deleting"
            fi
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove configuration directory
    if [[ -d "${PROJECT_DIR}/config" ]]; then
        log "Removing configuration directory..."
        rm -rf "${PROJECT_DIR}/config"
        success "Configuration directory removed"
    fi
    
    # Remove AWS SCT directory
    if [[ -d "${PROJECT_DIR}/aws-sct" ]]; then
        log "Removing AWS SCT directory..."
        rm -rf "${PROJECT_DIR}/aws-sct"
        success "AWS SCT directory removed"
    fi
    
    # Remove helper scripts (but keep deploy.sh and destroy.sh)
    for script in "create-endpoints.sh" "create-migration-task.sh"; do
        if [[ -f "${SCRIPT_DIR}/$script" ]]; then
            log "Removing helper script: $script"
            rm -f "${SCRIPT_DIR}/$script"
        fi
    done
    
    # Remove log files
    for log_file in "deployment.log" "cleanup.log"; do
        if [[ -f "${PROJECT_DIR}/$log_file" ]]; then
            log "Archiving log file: $log_file"
            mv "${PROJECT_DIR}/$log_file" "${PROJECT_DIR}/${log_file}.$(date +%Y%m%d_%H%M%S)"
        fi
    done
    
    # Remove environment file (but make a backup)
    if [[ -f "${PROJECT_DIR}/.env" ]]; then
        log "Backing up and removing environment file..."
        mv "${PROJECT_DIR}/.env" "${PROJECT_DIR}/.env.backup.$(date +%Y%m%d_%H%M%S)"
        success "Environment file backed up and removed"
    fi
    
    success "Local files cleaned up"
}

# Wait for resource deletion with timeout
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local timeout="${3:-300}"  # Default 5 minutes
    local interval="${4:-10}"  # Default 10 seconds
    
    log "Waiting for $resource_type deletion (timeout: ${timeout}s)..."
    
    local elapsed=0
    while eval "$check_command" &>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            warning "$resource_type deletion timed out after ${timeout} seconds"
            return 1
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    success "$resource_type deletion completed"
}

# Main cleanup function
main() {
    log "=== Oracle to PostgreSQL Migration Infrastructure Cleanup ==="
    log "Cleanup started at $(date)"
    
    load_environment
    confirm_cleanup
    
    # Clean up in reverse order of creation
    log "Starting resource cleanup (this may take 10-15 minutes)..."
    
    cleanup_dms_tasks
    cleanup_dms_endpoints
    cleanup_dms_instance
    cleanup_aurora_cluster
    cleanup_subnet_groups
    cleanup_networking
    cleanup_monitoring
    cleanup_iam_roles
    cleanup_local_files
    
    success "=== Cleanup completed successfully! ==="
    log "Cleanup finished at $(date)"
    
    echo ""
    echo "🧹 All migration infrastructure has been removed"
    echo "💰 Billing for these resources has stopped"
    echo "📁 Log files have been archived with timestamps"
    echo "🔄 You can run deploy.sh again to recreate the infrastructure"
    echo ""
    warning "Note: Any data in the Aurora cluster has been permanently deleted"
    warning "Ensure you have backups if you need to recover the data later"
}

# Error handling
handle_error() {
    error "Cleanup failed at line $LINENO"
    echo ""
    echo "🔧 TROUBLESHOOTING:"
    echo "1. Check the cleanup log: ${LOG_FILE}"
    echo "2. Some resources may still exist - check AWS console"
    echo "3. You may need to manually delete remaining resources"
    echo "4. Re-run this script to continue cleanup: $0"
    echo ""
    echo "💡 To force cleanup without confirmation: FORCE_CLEANUP=true $0"
}

trap 'handle_error' ERR

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--help]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompt"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Run main function
main "$@"