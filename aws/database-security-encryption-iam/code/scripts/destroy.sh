#!/bin/bash

# Cleanup script for Database Security with Encryption and IAM Authentication
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY RUN mode - no resources will be deleted"
elif [[ "${1:-}" == "--force" ]]; then
    FORCE_DELETE=true
    warn "Running in FORCE mode - will skip confirmation prompts"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: $description"
        info "Would execute: $cmd"
        return 0
    else
        log "$description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || true
        else
            eval "$cmd"
        fi
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    info "Prerequisites check passed ✅"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if state directory exists
    local state_dir="./deployment-state"
    if [[ ! -d "$state_dir" ]]; then
        error "State directory not found: $state_dir"
        error "Please run this script from the same directory where you ran deploy.sh"
        exit 1
    fi
    
    # Load environment variables
    if [[ -f "$state_dir/env_vars.sh" ]]; then
        source "$state_dir/env_vars.sh"
        info "Environment variables loaded from $state_dir/env_vars.sh"
    else
        error "Environment variables file not found: $state_dir/env_vars.sh"
        error "Please ensure the deployment completed successfully"
        exit 1
    fi
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "DB_INSTANCE_ID" "DB_PROXY_NAME"
        "KMS_KEY_ALIAS" "DB_SUBNET_GROUP_NAME" "SECURITY_GROUP_NAME"
        "IAM_ROLE_NAME" "IAM_POLICY_NAME" "DB_PARAMETER_GROUP_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var is not set"
            exit 1
        fi
    done
    
    info "Environment configured for region: $AWS_REGION"
    info "Database instance ID: $DB_INSTANCE_ID"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$DRY_RUN" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - RDS Instance: $DB_INSTANCE_ID"
    echo "   - RDS Proxy: $DB_PROXY_NAME"
    echo "   - KMS Key: $KMS_KEY_ALIAS (scheduled for deletion)"
    echo "   - Security Group: $SECURITY_GROUP_NAME"
    echo "   - IAM Role: $IAM_ROLE_NAME"
    echo "   - IAM Policy: $IAM_POLICY_NAME"
    echo "   - CloudWatch Alarms and Log Groups"
    echo "   - All associated data will be permanently lost!"
    echo
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    warn "Final confirmation: This action cannot be undone!"
    read -p "Proceed with deletion? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local max_wait="${3:-300}"  # 5 minutes default
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    info "Waiting for $resource_type deletion to complete..."
    local wait_time=0
    while [[ $wait_time -lt $max_wait ]]; do
        case "$resource_type" in
            "rds-instance")
                if ! aws rds describe-db-instances --db-instance-identifier "$resource_id" &>/dev/null; then
                    info "$resource_type deletion completed ✅"
                    return 0
                fi
                ;;
            "rds-proxy")
                if ! aws rds describe-db-proxies --db-proxy-name "$resource_id" &>/dev/null; then
                    info "$resource_type deletion completed ✅"
                    return 0
                fi
                ;;
        esac
        
        sleep 30
        wait_time=$((wait_time + 30))
        info "Still waiting for $resource_type deletion... ($wait_time/${max_wait}s)"
    done
    
    warn "$resource_type deletion timed out after $max_wait seconds"
    return 1
}

# Function to delete RDS proxy
delete_rds_proxy() {
    log "Deleting RDS proxy..."
    
    # Check if proxy exists
    if aws rds describe-db-proxies --db-proxy-name "$DB_PROXY_NAME" &>/dev/null; then
        # Deregister targets first
        execute_cmd "aws rds deregister-db-proxy-targets \
            --db-proxy-name '$DB_PROXY_NAME' \
            --db-instance-identifiers '$DB_INSTANCE_ID'" \
            "Deregistering proxy targets" true
        
        # Delete proxy
        execute_cmd "aws rds delete-db-proxy \
            --db-proxy-name '$DB_PROXY_NAME'" \
            "Deleting RDS proxy"
        
        # Wait for proxy deletion
        wait_for_deletion "rds-proxy" "$DB_PROXY_NAME"
        
        info "RDS proxy deleted: $DB_PROXY_NAME ✅"
    else
        info "RDS proxy not found, skipping deletion"
    fi
}

# Function to delete RDS instance
delete_rds_instance() {
    log "Deleting RDS instance..."
    
    # Check if instance exists
    if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" &>/dev/null; then
        # Disable deletion protection first
        execute_cmd "aws rds modify-db-instance \
            --db-instance-identifier '$DB_INSTANCE_ID' \
            --no-deletion-protection \
            --apply-immediately" \
            "Disabling deletion protection"
        
        # Wait for modification to complete
        if [[ "$DRY_RUN" == "false" ]]; then
            sleep 60
        fi
        
        # Delete instance without final snapshot
        execute_cmd "aws rds delete-db-instance \
            --db-instance-identifier '$DB_INSTANCE_ID' \
            --skip-final-snapshot" \
            "Deleting RDS instance"
        
        # Wait for instance deletion
        wait_for_deletion "rds-instance" "$DB_INSTANCE_ID" 600  # 10 minutes
        
        info "RDS instance deleted: $DB_INSTANCE_ID ✅"
    else
        info "RDS instance not found, skipping deletion"
    fi
}

# Function to delete RDS supporting resources
delete_rds_supporting_resources() {
    log "Deleting RDS supporting resources..."
    
    # Delete parameter group
    execute_cmd "aws rds delete-db-parameter-group \
        --db-parameter-group-name '$DB_PARAMETER_GROUP_NAME'" \
        "Deleting parameter group" true
    
    # Delete subnet group
    execute_cmd "aws rds delete-db-subnet-group \
        --db-subnet-group-name '$DB_SUBNET_GROUP_NAME'" \
        "Deleting subnet group" true
    
    # Delete security group
    if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
        execute_cmd "aws ec2 delete-security-group \
            --group-id '$SECURITY_GROUP_ID'" \
            "Deleting security group" true
    else
        # Try to find security group by name
        local sg_id
        sg_id=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "None")
        
        if [[ "$sg_id" != "None" && -n "$sg_id" ]]; then
            execute_cmd "aws ec2 delete-security-group \
                --group-id '$sg_id'" \
                "Deleting security group" true
        else
            info "Security group not found, skipping deletion"
        fi
    fi
    
    info "RDS supporting resources cleanup completed ✅"
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Detach and delete IAM policy
    if [[ -n "${POLICY_ARN:-}" ]]; then
        execute_cmd "aws iam detach-role-policy \
            --role-name '$IAM_ROLE_NAME' \
            --policy-arn '$POLICY_ARN'" \
            "Detaching IAM policy" true
        
        execute_cmd "aws iam delete-policy \
            --policy-arn '$POLICY_ARN'" \
            "Deleting IAM policy" true
    else
        # Try to find policy by name
        local policy_arn
        policy_arn=$(aws iam list-policies \
            --scope Local \
            --query "Policies[?PolicyName=='$IAM_POLICY_NAME'].Arn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$policy_arn" ]]; then
            execute_cmd "aws iam detach-role-policy \
                --role-name '$IAM_ROLE_NAME' \
                --policy-arn '$policy_arn'" \
                "Detaching IAM policy" true
            
            execute_cmd "aws iam delete-policy \
                --policy-arn '$policy_arn'" \
                "Deleting IAM policy" true
        fi
    fi
    
    # Delete IAM role
    execute_cmd "aws iam delete-role \
        --role-name '$IAM_ROLE_NAME'" \
        "Deleting IAM role" true
    
    # Delete monitoring role (only if no other RDS instances are using it)
    if aws iam get-role --role-name "rds-monitoring-role" &>/dev/null; then
        local other_instances
        other_instances=$(aws rds describe-db-instances \
            --query 'DBInstances[?MonitoringRoleArn!=`null`] | length(@)' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$other_instances" == "0" ]]; then
            execute_cmd "aws iam detach-role-policy \
                --role-name 'rds-monitoring-role' \
                --policy-arn 'arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole'" \
                "Detaching monitoring role policy" true
            
            execute_cmd "aws iam delete-role \
                --role-name 'rds-monitoring-role'" \
                "Deleting monitoring role" true
        else
            info "Monitoring role is in use by other RDS instances, skipping deletion"
        fi
    fi
    
    info "IAM resources deleted ✅"
}

# Function to delete KMS key
delete_kms_key() {
    log "Deleting KMS key..."
    
    # Get KMS key ID from alias
    local kms_key_id
    if [[ -n "${KMS_KEY_ID:-}" ]]; then
        kms_key_id="$KMS_KEY_ID"
    else
        kms_key_id=$(aws kms describe-key \
            --key-id "$KMS_KEY_ALIAS" \
            --query 'KeyMetadata.KeyId' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "$kms_key_id" && "$kms_key_id" != "None" ]]; then
        # Delete alias first
        execute_cmd "aws kms delete-alias \
            --alias-name '$KMS_KEY_ALIAS'" \
            "Deleting KMS key alias" true
        
        # Schedule key deletion
        execute_cmd "aws kms schedule-key-deletion \
            --key-id '$kms_key_id' \
            --pending-window-in-days 7" \
            "Scheduling KMS key deletion"
        
        info "KMS key scheduled for deletion (7 days): $kms_key_id ✅"
    else
        info "KMS key not found, skipping deletion"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    execute_cmd "aws cloudwatch delete-alarms \
        --alarm-names 'RDS-HighCPU-$DB_INSTANCE_ID' 'RDS-AuthFailures-$DB_INSTANCE_ID'" \
        "Deleting CloudWatch alarms" true
    
    # Delete CloudWatch log group
    execute_cmd "aws logs delete-log-group \
        --log-group-name '/aws/rds/instance/$DB_INSTANCE_ID/postgresql'" \
        "Deleting CloudWatch log group" true
    
    info "CloudWatch resources deleted ✅"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local state_dir="./deployment-state"
    if [[ -d "$state_dir" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            # Create backup of important files
            local backup_dir="./deployment-backup-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir"
            
            # Copy important files to backup
            cp "$state_dir/env_vars.sh" "$backup_dir/" 2>/dev/null || true
            cp "$state_dir/security-compliance-report.json" "$backup_dir/" 2>/dev/null || true
            cp "$state_dir/encryption_validation.txt" "$backup_dir/" 2>/dev/null || true
            
            # Remove state directory
            rm -rf "$state_dir"
            
            info "Temporary files cleaned up ✅"
            info "Backup created at: $backup_dir"
        else
            info "DRY RUN: Would clean up temporary files in $state_dir"
        fi
    else
        info "No temporary files to clean up"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would verify cleanup completion"
        return 0
    fi
    
    local cleanup_issues=()
    
    # Check if RDS instance still exists
    if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" &>/dev/null; then
        cleanup_issues+=("RDS instance still exists: $DB_INSTANCE_ID")
    fi
    
    # Check if RDS proxy still exists
    if aws rds describe-db-proxies --db-proxy-name "$DB_PROXY_NAME" &>/dev/null; then
        cleanup_issues+=("RDS proxy still exists: $DB_PROXY_NAME")
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        cleanup_issues+=("IAM role still exists: $IAM_ROLE_NAME")
    fi
    
    # Check if security group still exists
    if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
        if aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" &>/dev/null; then
            cleanup_issues+=("Security group still exists: $SECURITY_GROUP_ID")
        fi
    fi
    
    # Report results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        info "Cleanup verification passed ✅"
        return 0
    else
        warn "Cleanup verification found issues:"
        for issue in "${cleanup_issues[@]}"; do
            warn "  - $issue"
        done
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo "Database Instance ID: $DB_INSTANCE_ID"
    echo "Database Proxy Name: $DB_PROXY_NAME"
    echo "KMS Key Alias: $KMS_KEY_ALIAS"
    echo "IAM Role: $IAM_ROLE_NAME"
    echo
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "✅ Cleanup completed successfully!"
        echo "⚠️  KMS key is scheduled for deletion in 7 days"
        echo "💰 Monthly charges should stop within 24 hours"
    else
        echo "🔍 Dry run completed - no resources were deleted"
    fi
}

# Main execution
main() {
    log "Starting Database Security Cleanup..."
    
    # Check for help
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Usage: $0 [--dry-run] [--force] [--help]"
        echo "Options:"
        echo "  --dry-run   Show what would be done without making changes"
        echo "  --force     Skip confirmation prompts"
        echo "  --help      Show this help message"
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_rds_proxy
    delete_rds_instance
    delete_rds_supporting_resources
    delete_iam_resources
    delete_kms_key
    delete_cloudwatch_resources
    cleanup_temp_files
    verify_cleanup
    display_summary
    
    log "Cleanup process completed!"
}

# Execute main function
main "$@"