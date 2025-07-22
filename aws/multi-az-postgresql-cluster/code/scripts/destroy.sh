#!/bin/bash

#####################################################################
# AWS High-Availability PostgreSQL Cluster Cleanup Script         #
# Recipe: Building High-Availability PostgreSQL Clusters with RDS  #
# Version: 1.1                                                     #
# Last Updated: 2025-07-12                                         #
#####################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Banner
show_banner() {
    echo "================================================================="
    echo "  AWS High-Availability PostgreSQL Cluster Cleanup"
    echo "================================================================="
    echo ""
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Set AWS_REGION if not set
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            error_exit "AWS_REGION is not set and no default region configured."
        fi
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    local info_file="postgresql-ha-deployment.txt"
    
    if [[ -f "$info_file" ]]; then
        log_info "Loading deployment information from $info_file"
        
        # Extract cluster name from file
        export CLUSTER_NAME=$(grep "Cluster Name:" "$info_file" | cut -d' ' -f3)
        export SUBNET_GROUP_NAME=$(grep "Subnet Group:" "$info_file" | cut -d' ' -f3)
        export PARAMETER_GROUP_NAME=$(grep "Parameter Group:" "$info_file" | cut -d' ' -f3)
        export SECURITY_GROUP_ID=$(grep "Security Group:" "$info_file" | cut -d' ' -f3)
        export SNS_TOPIC_ARN=$(grep "SNS Topic:" "$info_file" | cut -d' ' -f3)
        
        log_success "Deployment information loaded"
    else
        log_warning "Deployment info file not found. You'll need to provide resource identifiers."
        
        read -p "Enter cluster name (e.g., postgresql-ha-abc123): " CLUSTER_NAME
        if [[ -z "$CLUSTER_NAME" ]]; then
            error_exit "Cluster name is required for cleanup"
        fi
        
        # Derive other names from cluster name
        local suffix=$(echo "$CLUSTER_NAME" | cut -d'-' -f3)
        export SUBNET_GROUP_NAME="postgresql-subnet-group-${suffix}"
        export PARAMETER_GROUP_NAME="postgresql-params-${suffix}"
        export SNS_TOPIC_NAME="postgresql-alerts-${suffix}"
    fi
}

# Confirm deletion
confirm_deletion() {
    echo ""
    log_warning "DESTRUCTIVE OPERATION WARNING"
    log_warning "This will permanently delete the following resources:"
    log_warning "  - PostgreSQL cluster: $CLUSTER_NAME"
    log_warning "  - All read replicas and cross-region replicas"
    log_warning "  - RDS Proxy and associated configurations"
    log_warning "  - All automated and manual snapshots"
    log_warning "  - CloudWatch alarms and SNS topics"
    log_warning "  - Security groups and parameter groups"
    echo ""
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    # First confirmation
    read -p "Are you absolutely sure you want to delete ALL resources? (yes/no): " confirm1
    if [[ ! "$confirm1" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Second confirmation
    read -p "Type 'DELETE' to confirm permanent deletion: " confirm2
    if [[ "$confirm2" != "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation text did not match"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Check if resource exists
resource_exists() {
    local check_command="$1"
    local resource_name="$2"
    
    if eval "$check_command" &> /dev/null; then
        return 0  # Resource exists
    else
        log_info "$resource_name not found or already deleted"
        return 1  # Resource doesn't exist
    fi
}

# Delete RDS Proxy
delete_rds_proxy() {
    log_info "Deleting RDS Proxy..."
    
    local proxy_name="${CLUSTER_NAME}-proxy"
    local proxy_role="rds-proxy-role-$(echo $CLUSTER_NAME | cut -d'-' -f3)"
    
    # Delete RDS Proxy
    if resource_exists "aws rds describe-db-proxies --db-proxy-name $proxy_name" "RDS Proxy"; then
        aws rds delete-db-proxy --db-proxy-name "$proxy_name" &> /dev/null
        log_success "RDS Proxy deletion initiated"
        
        # Wait for proxy deletion
        log_info "Waiting for RDS Proxy to be deleted..."
        while aws rds describe-db-proxies --db-proxy-name "$proxy_name" &> /dev/null; do
            sleep 30
        done
        log_success "RDS Proxy deleted"
    fi
    
    # Delete associated secret
    local secret_name="${CLUSTER_NAME}-credentials"
    if resource_exists "aws secretsmanager describe-secret --secret-id $secret_name" "Secrets Manager secret"; then
        aws secretsmanager delete-secret \
            --secret-id "$secret_name" \
            --force-delete-without-recovery &> /dev/null
        log_success "Secrets Manager secret deleted"
    fi
    
    # Delete IAM role
    if resource_exists "aws iam get-role --role-name $proxy_role" "IAM role"; then
        aws iam detach-role-policy \
            --role-name "$proxy_role" \
            --policy-arn "arn:aws:iam::aws:policy/SecretsManagerReadWrite" &> /dev/null
        
        aws iam delete-role --role-name "$proxy_role" &> /dev/null
        log_success "IAM role deleted: $proxy_role"
    fi
}

# Stop automated backup replication
stop_backup_replication() {
    log_info "Stopping automated backup replication..."
    
    local source_arn="arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${CLUSTER_NAME}-primary"
    
    if aws rds describe-db-instance-automated-backups \
        --region us-west-2 \
        --query "DBInstanceAutomatedBackups[?SourceDBInstanceArn=='$source_arn']" \
        --output text | grep -q .; then
        
        aws rds stop-db-instance-automated-backups-replication \
            --source-db-instance-arn "$source_arn" \
            --region us-west-2 &> /dev/null
        
        log_success "Automated backup replication stopped"
    else
        log_info "No automated backup replication found"
    fi
}

# Delete cross-region read replica
delete_cross_region_replica() {
    log_info "Deleting cross-region read replica..."
    
    local replica_id="${CLUSTER_NAME}-dr-replica"
    
    if resource_exists "aws rds describe-db-instances --db-instance-identifier $replica_id --region us-west-2" "Cross-region replica"; then
        aws rds delete-db-instance \
            --db-instance-identifier "$replica_id" \
            --region us-west-2 \
            --skip-final-snapshot &> /dev/null
        
        log_success "Cross-region replica deletion initiated"
        
        # Wait for deletion
        log_info "Waiting for cross-region replica to be deleted..."
        while aws rds describe-db-instances --db-instance-identifier "$replica_id" --region us-west-2 &> /dev/null; do
            sleep 30
        done
        log_success "Cross-region replica deleted"
    fi
}

# Delete read replica
delete_read_replica() {
    log_info "Deleting read replica..."
    
    local replica_id="${CLUSTER_NAME}-read-replica-1"
    
    if resource_exists "aws rds describe-db-instances --db-instance-identifier $replica_id" "Read replica"; then
        aws rds delete-db-instance \
            --db-instance-identifier "$replica_id" \
            --skip-final-snapshot &> /dev/null
        
        log_success "Read replica deletion initiated"
        
        # Wait for deletion
        log_info "Waiting for read replica to be deleted..."
        while aws rds describe-db-instances --db-instance-identifier "$replica_id" &> /dev/null; do
            sleep 30
        done
        log_success "Read replica deleted"
    fi
}

# Delete primary instance
delete_primary_instance() {
    log_info "Deleting primary PostgreSQL instance..."
    
    local primary_id="${CLUSTER_NAME}-primary"
    
    if resource_exists "aws rds describe-db-instances --db-instance-identifier $primary_id" "Primary instance"; then
        # Disable deletion protection first
        log_info "Disabling deletion protection..."
        aws rds modify-db-instance \
            --db-instance-identifier "$primary_id" \
            --no-deletion-protection \
            --apply-immediately &> /dev/null
        
        # Wait for modification
        aws rds wait db-instance-available --db-instance-identifier "$primary_id"
        
        # Delete the instance
        aws rds delete-db-instance \
            --db-instance-identifier "$primary_id" \
            --skip-final-snapshot \
            --delete-automated-backups &> /dev/null
        
        log_success "Primary instance deletion initiated"
        
        # Wait for deletion (this takes time)
        log_info "Waiting for primary instance to be deleted (this may take 10-15 minutes)..."
        while aws rds describe-db-instances --db-instance-identifier "$primary_id" &> /dev/null; do
            sleep 60
        done
        log_success "Primary instance deleted"
    fi
}

# Delete manual snapshots
delete_manual_snapshots() {
    log_info "Deleting manual snapshots..."
    
    local snapshots=$(aws rds describe-db-snapshots \
        --db-instance-identifier "${CLUSTER_NAME}-primary" \
        --snapshot-type manual \
        --query 'DBSnapshots[].DBSnapshotIdentifier' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$snapshots" ]]; then
        for snapshot in $snapshots; do
            if [[ "$snapshot" == *"$CLUSTER_NAME"* ]]; then
                aws rds delete-db-snapshot --db-snapshot-identifier "$snapshot" &> /dev/null
                log_success "Deleted snapshot: $snapshot"
            fi
        done
    else
        log_info "No manual snapshots found"
    fi
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    local alarms=(
        "${CLUSTER_NAME}-cpu-high"
        "${CLUSTER_NAME}-connections-high"
        "${CLUSTER_NAME}-replica-lag-high"
    )
    
    local existing_alarms=()
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --output text | grep -q "$alarm"; then
            existing_alarms+=("$alarm")
        fi
    done
    
    if [[ ${#existing_alarms[@]} -gt 0 ]]; then
        aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}" &> /dev/null
        log_success "CloudWatch alarms deleted"
    else
        log_info "No CloudWatch alarms found"
    fi
}

# Delete event subscription
delete_event_subscription() {
    log_info "Deleting event subscription..."
    
    local subscription_name="${CLUSTER_NAME}-events"
    
    if resource_exists "aws rds describe-event-subscriptions --subscription-name $subscription_name" "Event subscription"; then
        aws rds delete-event-subscription --subscription-name "$subscription_name" &> /dev/null
        log_success "Event subscription deleted"
    fi
}

# Delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if resource_exists "aws sns get-topic-attributes --topic-arn $SNS_TOPIC_ARN" "SNS topic"; then
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" &> /dev/null
            log_success "SNS topic deleted"
        fi
    else
        # Try to find topic by name
        local topic_name="${SNS_TOPIC_NAME:-postgresql-alerts-$(echo $CLUSTER_NAME | cut -d'-' -f3)}"
        local topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$topic_name')].TopicArn" --output text 2>/dev/null || echo "")
        
        if [[ -n "$topic_arn" ]]; then
            aws sns delete-topic --topic-arn "$topic_arn" &> /dev/null
            log_success "SNS topic deleted"
        else
            log_info "SNS topic not found"
        fi
    fi
}

# Delete parameter group
delete_parameter_group() {
    log_info "Deleting parameter group..."
    
    if resource_exists "aws rds describe-db-parameter-groups --db-parameter-group-name $PARAMETER_GROUP_NAME" "Parameter group"; then
        aws rds delete-db-parameter-group --db-parameter-group-name "$PARAMETER_GROUP_NAME" &> /dev/null
        log_success "Parameter group deleted: $PARAMETER_GROUP_NAME"
    fi
}

# Delete subnet group
delete_subnet_group() {
    log_info "Deleting subnet group..."
    
    if resource_exists "aws rds describe-db-subnet-groups --db-subnet-group-name $SUBNET_GROUP_NAME" "Subnet group"; then
        aws rds delete-db-subnet-group --db-subnet-group-name "$SUBNET_GROUP_NAME" &> /dev/null
        log_success "Subnet group deleted: $SUBNET_GROUP_NAME"
    fi
}

# Delete security group
delete_security_group() {
    log_info "Deleting security group..."
    
    if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
        if resource_exists "aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID" "Security group"; then
            aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" &> /dev/null
            log_success "Security group deleted: $SECURITY_GROUP_ID"
        fi
    else
        # Try to find security group by name
        local sg_name="${SECURITY_GROUP_NAME:-postgresql-sg-$(echo $CLUSTER_NAME | cut -d'-' -f3)}"
        local sg_id=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=$sg_name" \
            --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
        
        if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
            aws ec2 delete-security-group --group-id "$sg_id" &> /dev/null
            log_success "Security group deleted: $sg_id"
        else
            log_info "Security group not found"
        fi
    fi
}

# Delete RDS monitoring role (only if not used by other instances)
delete_monitoring_role() {
    log_info "Checking RDS monitoring role..."
    
    local role_name="rds-monitoring-role"
    
    # Check if any other RDS instances are using this role
    local instances_using_role=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(MonitoringRoleArn, '$role_name')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$instances_using_role" ]]; then
        if resource_exists "aws iam get-role --role-name $role_name" "RDS monitoring role"; then
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole" &> /dev/null
            
            aws iam delete-role --role-name "$role_name" &> /dev/null
            log_success "RDS monitoring role deleted"
        fi
    else
        log_info "RDS monitoring role is still in use by other instances, skipping deletion"
    fi
}

# Clean up deployment files
cleanup_deployment_files() {
    log_info "Cleaning up deployment files..."
    
    local files=(
        "postgresql-ha-deployment.txt"
        "postgresql-cluster-info.txt"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Deleted file: $file"
        fi
    done
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining instances
    if aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, '$CLUSTER_NAME')]" --output text | grep -q .; then
        log_warning "Some RDS instances may still exist"
        ((cleanup_issues++))
    fi
    
    # Check for remaining snapshots
    if aws rds describe-db-snapshots --query "DBSnapshots[?contains(DBSnapshotIdentifier, '$CLUSTER_NAME')]" --output text | grep -q .; then
        log_warning "Some snapshots may still exist"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
    else
        log_warning "Cleanup completed with $cleanup_issues potential issues"
        log_info "Some resources may take additional time to be fully deleted"
    fi
}

# Show cleanup summary
show_cleanup_summary() {
    echo ""
    echo "================================================================="
    echo "  Cleanup Summary"
    echo "================================================================="
    echo "The following resources have been deleted:"
    echo "  ✓ PostgreSQL cluster instances"
    echo "  ✓ Read replicas (local and cross-region)"
    echo "  ✓ RDS Proxy and connection pooling"
    echo "  ✓ Manual and automated snapshots"
    echo "  ✓ CloudWatch alarms and monitoring"
    echo "  ✓ SNS topics and event subscriptions"
    echo "  ✓ Security groups and parameter groups"
    echo "  ✓ IAM roles and Secrets Manager secrets"
    echo ""
    echo "Cleanup completed for cluster: $CLUSTER_NAME"
    echo "================================================================="
}

# Main cleanup function
main() {
    show_banner
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    log_info "Starting PostgreSQL HA cluster cleanup..."
    
    # Delete in reverse order of creation
    delete_rds_proxy
    stop_backup_replication
    delete_cross_region_replica
    delete_read_replica
    delete_primary_instance
    delete_manual_snapshots
    delete_cloudwatch_alarms
    delete_event_subscription
    delete_sns_topic
    delete_parameter_group
    delete_subnet_group
    delete_security_group
    delete_monitoring_role
    cleanup_deployment_files
    
    # Final verification
    verify_cleanup
    show_cleanup_summary
    
    log_success "PostgreSQL HA cluster cleanup completed successfully!"
    log_info "All resources associated with cluster '$CLUSTER_NAME' have been removed"
}

# Run main function
main "$@"