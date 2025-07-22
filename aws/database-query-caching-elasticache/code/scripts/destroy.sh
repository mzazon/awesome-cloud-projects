#!/bin/bash

# =============================================================================
# AWS ElastiCache Database Query Caching - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script,
# including ElastiCache clusters, RDS instances, security groups, and 
# supporting infrastructure components.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Environment variables from deployment (automatically loaded)
# - Appropriate IAM permissions for resource deletion
#
# Usage: ./destroy.sh [--force] [--keep-snapshots] [--cleanup-partial]
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration and Global Variables
# =============================================================================

# Script metadata
SCRIPT_NAME="ElastiCache Database Caching Cleanup"
SCRIPT_VERSION="1.0"
CLEANUP_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# Default configuration
DEFAULT_REGION="us-east-1"
AWS_REGION="${AWS_REGION:-$DEFAULT_REGION}"
FORCE_DELETE=false
KEEP_SNAPSHOTS=false
CLEANUP_PARTIAL=false
VERBOSE=false

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Environment variables file
ENV_FILE="/tmp/elasticache-deployment-vars.env"

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $1"
}

print_banner() {
    echo "============================================================================="
    echo "  $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "  Cleanup started: $CLEANUP_START_TIME"
    echo "  AWS Region: $AWS_REGION"
    echo "============================================================================="
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --force             Skip confirmation prompts (dangerous!)
    --keep-snapshots    Preserve final snapshots of databases
    --cleanup-partial   Clean up resources even if some are missing
    --verbose           Enable verbose logging
    --help              Show this help message

EXAMPLES:
    $0                      # Interactive cleanup with confirmations
    $0 --force              # Automated cleanup without prompts
    $0 --keep-snapshots     # Keep database snapshots for recovery
    $0 --cleanup-partial    # Clean up after failed deployment

SAFETY NOTES:
    - This script will DELETE all resources created by the deployment
    - Use --force carefully as it skips all safety confirmations
    - Database snapshots are deleted by default unless --keep-snapshots is used
    - Some resources may take several minutes to delete completely

EOF
}

confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" || "$CLEANUP_PARTIAL" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will DELETE the following resources:"
    echo "  - ElastiCache Redis Cluster: ${CACHE_CLUSTER_ID:-'N/A'}"
    echo "  - RDS Database Instance: ${DB_INSTANCE_ID:-'N/A'}"
    echo "  - Security Groups: ${CACHE_SG_ID:-'N/A'}"
    echo "  - Subnet Groups and Parameter Groups"
    echo "  - All associated snapshots and backups"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion. Proceeding with cleanup..."
}

load_environment_variables() {
    log_info "Loading environment variables..."
    
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Loading variables from: $ENV_FILE"
        source "$ENV_FILE"
        log_success "Environment variables loaded successfully"
    else
        log_warning "Environment file not found: $ENV_FILE"
        log_info "Attempting to discover resources automatically..."
        
        # Try to discover resources if environment file is missing
        discover_resources
    fi
    
    # Validate required variables
    if [[ -z "${CACHE_CLUSTER_ID:-}" && -z "${DB_INSTANCE_ID:-}" ]]; then
        if [[ "$CLEANUP_PARTIAL" != "true" ]]; then
            log_error "No resources found to cleanup. Use --cleanup-partial to force cleanup."
            exit 1
        fi
    fi
}

discover_resources() {
    log_info "Discovering ElastiCache and RDS resources..."
    
    # Discover ElastiCache clusters
    local cache_clusters=$(aws elasticache describe-replication-groups \
        --region "$AWS_REGION" \
        --query 'ReplicationGroups[?contains(ReplicationGroupId, `cache-cluster`)].ReplicationGroupId' \
        --output text 2>/dev/null || echo "")
    
    # Discover RDS instances
    local rds_instances=$(aws rds describe-db-instances \
        --region "$AWS_REGION" \
        --query 'DBInstances[?contains(DBInstanceIdentifier, `database`)].DBInstanceIdentifier' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$cache_clusters" ]]; then
        log_warning "Found ElastiCache clusters: $cache_clusters"
        export CACHE_CLUSTER_ID=$(echo "$cache_clusters" | head -n1)
    fi
    
    if [[ -n "$rds_instances" ]]; then
        log_warning "Found RDS instances: $rds_instances"
        export DB_INSTANCE_ID=$(echo "$rds_instances" | head -n1)
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first"
        exit 1
    fi
    
    # Verify region
    if ! aws ec2 describe-regions --region-names "$AWS_REGION" &> /dev/null; then
        log_error "Invalid AWS region: $AWS_REGION"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

delete_elasticache_cluster() {
    if [[ -z "${CACHE_CLUSTER_ID:-}" ]]; then
        log_warning "No ElastiCache cluster ID found, skipping"
        return
    fi
    
    log_info "Deleting ElastiCache Redis cluster: $CACHE_CLUSTER_ID"
    
    # Check if cluster exists
    local cluster_status=$(aws elasticache describe-replication-groups \
        --replication-group-id "$CACHE_CLUSTER_ID" \
        --region "$AWS_REGION" \
        --query 'ReplicationGroups[0].Status' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$cluster_status" == "not-found" ]]; then
        log_warning "ElastiCache cluster not found: $CACHE_CLUSTER_ID"
        return
    fi
    
    if [[ "$cluster_status" == "deleting" ]]; then
        log_info "ElastiCache cluster already being deleted"
    else
        # Delete replication group
        local snapshot_id=""
        if [[ "$KEEP_SNAPSHOTS" == "true" ]]; then
            snapshot_id="${CACHE_CLUSTER_ID}-final-$(date +%Y%m%d%H%M%S)"
            log_info "Creating final snapshot: $snapshot_id"
        fi
        
        if [[ -n "$snapshot_id" ]]; then
            aws elasticache delete-replication-group \
                --replication-group-id "$CACHE_CLUSTER_ID" \
                --final-snapshot-identifier "$snapshot_id" \
                --region "$AWS_REGION"
        else
            aws elasticache delete-replication-group \
                --replication-group-id "$CACHE_CLUSTER_ID" \
                --region "$AWS_REGION"
        fi
        
        log_success "ElastiCache cluster deletion initiated"
    fi
    
    # Wait for deletion to complete
    log_info "Waiting for ElastiCache cluster deletion (this may take 5-10 minutes)..."
    
    local timeout=900  # 15 minutes
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_warning "Timeout waiting for cluster deletion, continuing with cleanup"
            break
        fi
        
        local status=$(aws elasticache describe-replication-groups \
            --replication-group-id "$CACHE_CLUSTER_ID" \
            --region "$AWS_REGION" \
            --query 'ReplicationGroups[0].Status' \
            --output text 2>/dev/null || echo "deleted")
        
        if [[ "$status" == "deleted" ]]; then
            log_success "ElastiCache cluster successfully deleted"
            break
        fi
        
        log_info "ElastiCache cluster status: $status (waiting...)"
        sleep 30
    done
}

delete_rds_instance() {
    if [[ -z "${DB_INSTANCE_ID:-}" ]]; then
        log_warning "No RDS instance ID found, skipping"
        return
    fi
    
    log_info "Deleting RDS database instance: $DB_INSTANCE_ID"
    
    # Check if instance exists
    local db_status=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$db_status" == "not-found" ]]; then
        log_warning "RDS instance not found: $DB_INSTANCE_ID"
    elif [[ "$db_status" == "deleting" ]]; then
        log_info "RDS instance already being deleted"
    else
        # Delete RDS instance
        if [[ "$KEEP_SNAPSHOTS" == "true" ]]; then
            local final_snapshot_id="${DB_INSTANCE_ID}-final-$(date +%Y%m%d%H%M%S)"
            log_info "Creating final snapshot: $final_snapshot_id"
            
            aws rds delete-db-instance \
                --db-instance-identifier "$DB_INSTANCE_ID" \
                --final-db-snapshot-identifier "$final_snapshot_id" \
                --region "$AWS_REGION"
        else
            aws rds delete-db-instance \
                --db-instance-identifier "$DB_INSTANCE_ID" \
                --skip-final-snapshot \
                --region "$AWS_REGION"
        fi
        
        log_success "RDS instance deletion initiated"
    fi
    
    # Wait for deletion to complete
    log_info "Waiting for RDS instance deletion (this may take 5-10 minutes)..."
    
    local timeout=900  # 15 minutes
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_warning "Timeout waiting for RDS deletion, continuing with cleanup"
            break
        fi
        
        local status=$(aws rds describe-db-instances \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "deleted")
        
        if [[ "$status" == "deleted" ]]; then
            log_success "RDS instance successfully deleted"
            break
        fi
        
        log_info "RDS instance status: $status (waiting...)"
        sleep 30
    done
}

delete_cache_subnet_group() {
    if [[ -z "${SUBNET_GROUP_NAME:-}" ]]; then
        log_warning "No cache subnet group name found, skipping"
        return
    fi
    
    log_info "Deleting cache subnet group: $SUBNET_GROUP_NAME"
    
    # Check if subnet group exists
    local exists=$(aws elasticache describe-cache-subnet-groups \
        --cache-subnet-group-name "$SUBNET_GROUP_NAME" \
        --region "$AWS_REGION" \
        --query 'CacheSubnetGroups[0].CacheSubnetGroupName' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$exists" == "not-found" ]]; then
        log_warning "Cache subnet group not found: $SUBNET_GROUP_NAME"
        return
    fi
    
    aws elasticache delete-cache-subnet-group \
        --cache-subnet-group-name "$SUBNET_GROUP_NAME" \
        --region "$AWS_REGION"
    
    log_success "Cache subnet group deleted: $SUBNET_GROUP_NAME"
}

delete_db_subnet_group() {
    if [[ -z "${DB_SUBNET_GROUP_NAME:-}" ]]; then
        log_warning "No DB subnet group name found, attempting auto-discovery"
        
        # Try to find DB subnet group based on naming pattern
        if [[ -n "${CACHE_CLUSTER_ID:-}" ]]; then
            local suffix="${CACHE_CLUSTER_ID##*-}"
            DB_SUBNET_GROUP_NAME="db-subnet-group-${suffix}"
        else
            return
        fi
    fi
    
    log_info "Deleting DB subnet group: $DB_SUBNET_GROUP_NAME"
    
    # Check if DB subnet group exists
    local exists=$(aws rds describe-db-subnet-groups \
        --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
        --region "$AWS_REGION" \
        --query 'DBSubnetGroups[0].DBSubnetGroupName' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$exists" == "not-found" ]]; then
        log_warning "DB subnet group not found: $DB_SUBNET_GROUP_NAME"
        return
    fi
    
    aws rds delete-db-subnet-group \
        --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
        --region "$AWS_REGION"
    
    log_success "DB subnet group deleted: $DB_SUBNET_GROUP_NAME"
}

delete_cache_parameter_group() {
    if [[ -z "${PARAMETER_GROUP_NAME:-}" ]]; then
        log_warning "No cache parameter group name found, skipping"
        return
    fi
    
    log_info "Deleting cache parameter group: $PARAMETER_GROUP_NAME"
    
    # Check if parameter group exists
    local exists=$(aws elasticache describe-cache-parameter-groups \
        --cache-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --region "$AWS_REGION" \
        --query 'CacheParameterGroups[0].CacheParameterGroupName' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$exists" == "not-found" ]]; then
        log_warning "Cache parameter group not found: $PARAMETER_GROUP_NAME"
        return
    fi
    
    aws elasticache delete-cache-parameter-group \
        --cache-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --region "$AWS_REGION"
    
    log_success "Cache parameter group deleted: $PARAMETER_GROUP_NAME"
}

delete_security_groups() {
    if [[ -z "${CACHE_SG_ID:-}" ]]; then
        log_warning "No security group ID found, skipping"
        return
    fi
    
    log_info "Deleting security group: $CACHE_SG_ID"
    
    # Check if security group exists
    local exists=$(aws ec2 describe-security-groups \
        --group-ids "$CACHE_SG_ID" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$exists" == "not-found" ]]; then
        log_warning "Security group not found: $CACHE_SG_ID"
        return
    fi
    
    # Wait a bit for resources to detach from security group
    log_info "Waiting for resources to detach from security group..."
    sleep 30
    
    # Retry security group deletion with backoff
    local max_attempts=5
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if aws ec2 delete-security-group \
            --group-id "$CACHE_SG_ID" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_success "Security group deleted: $CACHE_SG_ID"
            return
        else
            log_warning "Attempt $attempt failed, retrying in 30 seconds..."
            sleep 30
            ((attempt++))
        fi
    done
    
    log_warning "Could not delete security group after $max_attempts attempts: $CACHE_SG_ID"
}

cleanup_environment_files() {
    log_info "Cleaning up environment files and temporary data..."
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        log_success "Environment file removed: $ENV_FILE"
    fi
    
    # Remove demo script if it exists
    local demo_script="$(dirname "$0")/../cache_demo.py"
    if [[ -f "$demo_script" ]]; then
        rm -f "$demo_script"
        log_success "Demo script removed: $demo_script"
    fi
    
    # Clean up any other temporary files
    rm -f /tmp/elasticache-*.tmp 2>/dev/null || true
    
    log_success "Cleanup of environment files completed"
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --keep-snapshots)
                KEEP_SNAPSHOTS=true
                shift
                ;;
            --cleanup-partial)
                CLEANUP_PARTIAL=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Main cleanup flow
    print_banner
    check_prerequisites
    load_environment_variables
    confirm_deletion
    
    # Delete resources in reverse order of creation
    log_info "Starting resource cleanup..."
    
    delete_elasticache_cluster
    delete_rds_instance
    delete_cache_subnet_group
    delete_db_subnet_group
    delete_cache_parameter_group
    delete_security_groups
    cleanup_environment_files
    
    # Final success message
    log_success "Cleanup completed successfully!"
    echo
    echo "============================================================================="
    echo "  CLEANUP SUMMARY"
    echo "============================================================================="
    echo "  All resources have been deleted or marked for deletion."
    echo "  Some resources may take additional time to be fully removed."
    echo
    if [[ "$KEEP_SNAPSHOTS" == "true" ]]; then
        echo "  Final snapshots were preserved and may incur storage costs."
        echo "  Remember to delete snapshots manually when no longer needed."
    else
        echo "  All snapshots and backups have been deleted."
    fi
    echo
    echo "  Cleanup completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================="
}

# Execute main function
main "$@"