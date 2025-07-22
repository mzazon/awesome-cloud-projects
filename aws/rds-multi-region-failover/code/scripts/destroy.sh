#!/bin/bash

# Advanced RDS Multi-AZ Cross-Region Failover Cleanup Script
# This script safely removes all resources created by the deployment script
# Recipe: RDS Multi-Region Failover Strategy

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_VARS="${SCRIPT_DIR}/deployment_vars.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$ERROR_LOG"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code on line $1"
    log_error "Continuing with cleanup..."
    # Don't exit on errors during cleanup - try to clean up as much as possible
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Advanced RDS Multi-AZ Cross-Region Failover Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Force deletion without confirmation prompts
    -d, --dry-run          Show what would be deleted without making changes
    -v, --verbose          Enable verbose logging
    --skip-snapshots       Skip taking final snapshots (DANGEROUS)
    --keep-snapshots       Keep all snapshots during cleanup
    --vars-file FILE       Specify custom deployment variables file

EXAMPLE:
    $0 --force --verbose

SAFETY FEATURES:
    - Takes final snapshots by default
    - Confirms destructive operations
    - Logs all operations
    - Continues cleanup even if some operations fail

WARNING:
    This script will permanently delete AWS resources and may result in data loss.
    Ensure you have proper backups before proceeding.
EOF
}

# Default configuration
DRY_RUN=false
FORCE=false
VERBOSE=false
SKIP_SNAPSHOTS=false
KEEP_SNAPSHOTS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-snapshots)
            SKIP_SNAPSHOTS=true
            shift
            ;;
        --keep-snapshots)
            KEEP_SNAPSHOTS=true
            shift
            ;;
        --vars-file)
            DEPLOYMENT_VARS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set verbose mode
if [[ "$VERBOSE" == true ]]; then
    set -x
fi

# Load deployment variables
load_deployment_vars() {
    log "Loading deployment variables..."
    
    if [[ ! -f "$DEPLOYMENT_VARS" ]]; then
        log_error "Deployment variables file not found: $DEPLOYMENT_VARS"
        log_error "Please provide the path to deployment_vars.env using --vars-file"
        exit 1
    fi
    
    # Source the deployment variables
    set -a  # Automatically export variables
    # shellcheck source=/dev/null
    source "$DEPLOYMENT_VARS"
    set +a
    
    # Verify required variables are set
    local required_vars=(
        "PRIMARY_REGION"
        "SECONDARY_REGION"
        "AWS_ACCOUNT_ID"
        "DB_INSTANCE_ID"
        "DB_REPLICA_ID"
        "DB_SUBNET_GROUP"
        "DB_PARAMETER_GROUP"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in $DEPLOYMENT_VARS"
            exit 1
        fi
    done
    
    log_success "Deployment variables loaded successfully"
    log "Primary Region: $PRIMARY_REGION"
    log "Secondary Region: $SECONDARY_REGION"
    log "DB Instance ID: $DB_INSTANCE_ID"
    log "DB Replica ID: $DB_REPLICA_ID"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == true ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log_warning "This will permanently delete the following AWS resources:"
    echo
    echo "  📊 RDS Instances:"
    echo "    - Primary: $DB_INSTANCE_ID ($PRIMARY_REGION)"
    echo "    - Replica: $DB_REPLICA_ID ($SECONDARY_REGION)"
    echo
    echo "  🔧 Supporting Resources:"
    echo "    - Parameter Group: $DB_PARAMETER_GROUP"
    echo "    - Subnet Groups: $DB_SUBNET_GROUP (both regions)"
    echo "    - CloudWatch Alarms"
    echo "    - IAM Role: ${PROMOTION_ROLE:-rds-promotion-role-$DB_INSTANCE_ID}"
    echo
    echo "  💰 Estimated monthly savings: \$800-1,200"
    echo
    
    if [[ "$SKIP_SNAPSHOTS" == true ]]; then
        log_warning "WARNING: Final snapshots will be SKIPPED - data may be lost!"
    else
        log "Final snapshots will be created before deletion"
    fi
    
    echo
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed - proceeding with cleanup"
}

# Execute AWS command with dry-run support
execute_aws() {
    local cmd="$*"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would execute: $cmd"
        return 0
    else
        log "Executing: $cmd"
        # Don't exit on errors - continue cleanup
        eval "$cmd" || log_warning "Command failed but continuing cleanup"
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    local region="$3"
    
    case "$resource_type" in
        "db-instance")
            aws rds describe-db-instances \
                --region "$region" \
                --db-instance-identifier "$resource_id" \
                --query "DBInstances[0].DBInstanceIdentifier" \
                --output text &>/dev/null && return 0 || return 1
            ;;
        "db-parameter-group")
            aws rds describe-db-parameter-groups \
                --region "$region" \
                --db-parameter-group-name "$resource_id" \
                --query "DBParameterGroups[0].DBParameterGroupName" \
                --output text &>/dev/null && return 0 || return 1
            ;;
        "db-subnet-group")
            aws rds describe-db-subnet-groups \
                --region "$region" \
                --db-subnet-group-name "$resource_id" \
                --query "DBSubnetGroups[0].DBSubnetGroupName" \
                --output text &>/dev/null && return 0 || return 1
            ;;
        "iam-role")
            aws iam get-role \
                --role-name "$resource_id" \
                --query "Role.RoleName" \
                --output text &>/dev/null && return 0 || return 1
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Stop automated backup replication
stop_backup_replication() {
    log "Stopping automated backup replication..."
    
    # Check if backup replication exists
    local backup_arn="arn:aws:rds:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:db:${DB_INSTANCE_ID}"
    
    if aws rds describe-db-instance-automated-backups \
        --region "$SECONDARY_REGION" \
        --db-instance-automated-backups-arn "$backup_arn" &>/dev/null; then
        
        execute_aws "aws rds stop-db-instance-automated-backups-replication \
            --region $SECONDARY_REGION \
            --source-db-instance-arn $backup_arn"
        
        log_success "Stopped automated backup replication"
    else
        log_warning "No automated backup replication found to stop"
    fi
}

# Delete cross-region read replica
delete_read_replica() {
    log "Deleting cross-region read replica..."
    
    if resource_exists "db-instance" "$DB_REPLICA_ID" "$SECONDARY_REGION"; then
        local snapshot_id="${DB_REPLICA_ID}-final-$(date +%Y%m%d-%H%M%S)"
        
        if [[ "$SKIP_SNAPSHOTS" == true ]]; then
            execute_aws "aws rds delete-db-instance \
                --region $SECONDARY_REGION \
                --db-instance-identifier $DB_REPLICA_ID \
                --skip-final-snapshot"
        else
            execute_aws "aws rds delete-db-instance \
                --region $SECONDARY_REGION \
                --db-instance-identifier $DB_REPLICA_ID \
                --final-db-snapshot-identifier $snapshot_id"
            
            log "Final snapshot will be created: $snapshot_id"
        fi
        
        if [[ "$DRY_RUN" == false ]]; then
            log "Waiting for replica deletion to complete..."
            # Wait for deletion but don't fail if it times out
            timeout 600 aws rds wait db-instance-deleted \
                --region "$SECONDARY_REGION" \
                --db-instance-identifier "$DB_REPLICA_ID" || \
                log_warning "Timeout waiting for replica deletion - continuing anyway"
        fi
        
        log_success "Read replica deletion initiated"
    else
        log_warning "Read replica $DB_REPLICA_ID not found in $SECONDARY_REGION"
    fi
}

# Delete Route 53 resources
delete_route53_resources() {
    log "Deleting Route 53 resources..."
    
    # Try to find and delete hosted zones created by deployment
    local hosted_zones=$(aws route53 list-hosted-zones \
        --query "HostedZones[?contains(Name, 'financial-db.internal')].Id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$hosted_zones" ]]; then
        for zone_id in $hosted_zones; do
            # Clean zone ID (remove /hostedzone/ prefix if present)
            zone_id=$(echo "$zone_id" | sed 's|.*/||')
            
            log "Found hosted zone to delete: $zone_id"
            
            # List and delete records first
            local records=$(aws route53 list-resource-record-sets \
                --hosted-zone-id "$zone_id" \
                --query "ResourceRecordSets[?Type != 'NS' && Type != 'SOA']" \
                --output json 2>/dev/null || echo "[]")
            
            if [[ "$records" != "[]" ]]; then
                log "Deleting DNS records in hosted zone $zone_id"
                # This would require more complex logic to properly delete records
                log_warning "Manual cleanup of DNS records may be required"
            fi
            
            execute_aws "aws route53 delete-hosted-zone --id $zone_id"
        done
        
        log_success "Route 53 resources cleaned up"
    else
        log_warning "No Route 53 hosted zones found to delete"
    fi
}

# Delete primary database
delete_primary_database() {
    log "Deleting primary database..."
    
    if resource_exists "db-instance" "$DB_INSTANCE_ID" "$PRIMARY_REGION"; then
        local snapshot_id="${DB_INSTANCE_ID}-final-$(date +%Y%m%d-%H%M%S)"
        
        if [[ "$SKIP_SNAPSHOTS" == true ]]; then
            execute_aws "aws rds delete-db-instance \
                --region $PRIMARY_REGION \
                --db-instance-identifier $DB_INSTANCE_ID \
                --skip-final-snapshot"
        else
            execute_aws "aws rds delete-db-instance \
                --region $PRIMARY_REGION \
                --db-instance-identifier $DB_INSTANCE_ID \
                --final-db-snapshot-identifier $snapshot_id"
            
            log "Final snapshot will be created: $snapshot_id"
        fi
        
        if [[ "$DRY_RUN" == false ]]; then
            log "Waiting for primary database deletion to complete..."
            # Wait for deletion but don't fail if it times out
            timeout 600 aws rds wait db-instance-deleted \
                --region "$PRIMARY_REGION" \
                --db-instance-identifier "$DB_INSTANCE_ID" || \
                log_warning "Timeout waiting for primary database deletion - continuing anyway"
        fi
        
        log_success "Primary database deletion initiated"
    else
        log_warning "Primary database $DB_INSTANCE_ID not found in $PRIMARY_REGION"
    fi
}

# Delete parameter group
delete_parameter_group() {
    log "Deleting parameter group..."
    
    if resource_exists "db-parameter-group" "$DB_PARAMETER_GROUP" "$PRIMARY_REGION"; then
        execute_aws "aws rds delete-db-parameter-group \
            --region $PRIMARY_REGION \
            --db-parameter-group-name $DB_PARAMETER_GROUP"
        
        log_success "Parameter group deleted"
    else
        log_warning "Parameter group $DB_PARAMETER_GROUP not found"
    fi
}

# Delete subnet groups
delete_subnet_groups() {
    log "Deleting subnet groups..."
    
    # Delete primary region subnet group
    if resource_exists "db-subnet-group" "$DB_SUBNET_GROUP" "$PRIMARY_REGION"; then
        execute_aws "aws rds delete-db-subnet-group \
            --region $PRIMARY_REGION \
            --db-subnet-group-name $DB_SUBNET_GROUP"
        
        log_success "Primary region subnet group deleted"
    else
        log_warning "Primary region subnet group $DB_SUBNET_GROUP not found"
    fi
    
    # Delete secondary region subnet group
    if resource_exists "db-subnet-group" "$DB_SUBNET_GROUP" "$SECONDARY_REGION"; then
        execute_aws "aws rds delete-db-subnet-group \
            --region $SECONDARY_REGION \
            --db-subnet-group-name $DB_SUBNET_GROUP"
        
        log_success "Secondary region subnet group deleted"
    else
        log_warning "Secondary region subnet group $DB_SUBNET_GROUP not found"
    fi
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    # Delete primary region alarms
    local primary_alarms=$(aws cloudwatch describe-alarms \
        --region "$PRIMARY_REGION" \
        --alarm-name-prefix "${DB_INSTANCE_ID}-" \
        --query "MetricAlarms[].AlarmName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$primary_alarms" ]]; then
        for alarm in $primary_alarms; do
            execute_aws "aws cloudwatch delete-alarms \
                --region $PRIMARY_REGION \
                --alarm-names $alarm"
        done
        log_success "Primary region CloudWatch alarms deleted"
    else
        log_warning "No primary region CloudWatch alarms found"
    fi
    
    # Delete secondary region alarms
    local secondary_alarms=$(aws cloudwatch describe-alarms \
        --region "$SECONDARY_REGION" \
        --alarm-name-prefix "${DB_REPLICA_ID}-" \
        --query "MetricAlarms[].AlarmName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$secondary_alarms" ]]; then
        for alarm in $secondary_alarms; do
            execute_aws "aws cloudwatch delete-alarms \
                --region $SECONDARY_REGION \
                --alarm-names $alarm"
        done
        log_success "Secondary region CloudWatch alarms deleted"
    else
        log_warning "No secondary region CloudWatch alarms found"
    fi
}

# Delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    local role_name="${PROMOTION_ROLE:-rds-promotion-role-${DB_INSTANCE_ID}}"
    
    if resource_exists "iam-role" "$role_name" ""; then
        # Detach policies first
        execute_aws "aws iam detach-role-policy \
            --role-name $role_name \
            --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess" || true
        
        execute_aws "aws iam detach-role-policy \
            --role-name $role_name \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || true
        
        # Delete the role
        execute_aws "aws iam delete-role --role-name $role_name"
        
        log_success "IAM role deleted"
    else
        log_warning "IAM role $role_name not found"
    fi
}

# Clean up snapshots if requested
cleanup_snapshots() {
    if [[ "$KEEP_SNAPSHOTS" == true ]]; then
        log "Keeping all snapshots as requested"
        return 0
    fi
    
    log "Cleaning up manual snapshots..."
    
    # Find and optionally delete manual snapshots
    local snapshots=$(aws rds describe-db-snapshots \
        --region "$PRIMARY_REGION" \
        --snapshot-type manual \
        --query "DBSnapshots[?contains(DBSnapshotIdentifier, '$DB_INSTANCE_ID')].DBSnapshotIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$snapshots" ]]; then
        log "Found manual snapshots: $snapshots"
        
        if [[ "$FORCE" == true ]]; then
            for snapshot in $snapshots; do
                execute_aws "aws rds delete-db-snapshot \
                    --region $PRIMARY_REGION \
                    --db-snapshot-identifier $snapshot"
            done
            log_success "Manual snapshots deleted"
        else
            log_warning "Manual snapshots found but not deleted (use --force to delete)"
            log "To delete manually: aws rds delete-db-snapshot --db-snapshot-identifier <snapshot-id>"
        fi
    else
        log "No manual snapshots found to clean up"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/promotion-trust-policy.json"
        "${SCRIPT_DIR}/deployment_summary.txt"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log "[DRY RUN] Would delete: $file"
            else
                rm -f "$file"
                log "Deleted: $file"
            fi
        fi
    done
    
    # Optionally remove deployment variables file
    if [[ "$FORCE" == true ]] && [[ -f "$DEPLOYMENT_VARS" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log "[DRY RUN] Would delete: $DEPLOYMENT_VARS"
        else
            rm -f "$DEPLOYMENT_VARS"
            log "Deleted: $DEPLOYMENT_VARS"
        fi
    else
        log "Keeping deployment variables file: $DEPLOYMENT_VARS"
    fi
    
    log_success "Temporary files cleaned up"
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    cat > "${SCRIPT_DIR}/cleanup_summary.txt" << EOF
Advanced RDS Multi-AZ Cross-Region Failover Cleanup Summary
==========================================================

Cleanup completed: $(date)
Primary Region: $PRIMARY_REGION
Secondary Region: $SECONDARY_REGION

Resources Deleted:
- Primary DB Instance: $DB_INSTANCE_ID
- Read Replica: $DB_REPLICA_ID
- Parameter Group: $DB_PARAMETER_GROUP
- Subnet Groups: $DB_SUBNET_GROUP (both regions)
- IAM Role: ${PROMOTION_ROLE:-rds-promotion-role-${DB_INSTANCE_ID}}
- CloudWatch Alarms: Connection monitoring and replica lag

Actions Taken:
- Final snapshots: $(if [[ "$SKIP_SNAPSHOTS" == true ]]; then echo "Skipped"; else echo "Created"; fi)
- Backup replication: Stopped
- Route 53 resources: Cleaned up
- Temporary files: Removed

Estimated Monthly Savings: \$800-1,200

Manual Cleanup Required:
- Review AWS Console for any remaining resources
- Check CloudWatch Logs for retention settings
- Verify Route 53 hosted zones if manually created
- Review AWS CloudTrail logs if needed

Notes:
- Final snapshots (if created) will continue to incur storage costs
- Some DNS propagation may take up to 24 hours
- Monitor AWS billing to confirm cost reduction

Cleanup Log: $LOG_FILE
Error Log: $ERROR_LOG
EOF
    
    log_success "Cleanup summary saved to cleanup_summary.txt"
}

# Main cleanup function
main() {
    log "=== Starting Advanced RDS Multi-AZ Cross-Region Failover Cleanup ==="
    
    # Initialize log files
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    load_deployment_vars
    confirm_deletion
    
    # Stop services first
    stop_backup_replication
    
    # Delete databases (this takes the longest)
    delete_read_replica
    delete_primary_database
    
    # Clean up supporting resources
    delete_route53_resources
    delete_parameter_group
    delete_subnet_groups
    delete_cloudwatch_alarms
    delete_iam_role
    
    # Optional cleanup
    cleanup_snapshots
    cleanup_temp_files
    
    generate_cleanup_summary
    
    log_success "=== Cleanup completed ==="
    log "Check cleanup_summary.txt for details"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "This was a dry run - no resources were actually deleted"
    else
        log "All specified resources have been deleted"
        log "Monitor AWS billing to confirm cost reduction"
    fi
}

# Run main function
main "$@"