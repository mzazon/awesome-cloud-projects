#!/bin/bash

# Destroy script for Aurora Serverless Database Scaling Recipe
# This script removes all resources created by the deploy script

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure' or set AWS credentials."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env" ]; then
        source .env
        log "Environment loaded from .env file"
        log "Cluster ID: ${CLUSTER_ID:-'Not set'}"
        log "Region: ${AWS_REGION:-'Not set'}"
    else
        warning ".env file not found. You may need to provide resource identifiers manually."
        
        # Try to get AWS region from CLI config
        export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
        if [ -z "$AWS_REGION" ]; then
            error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
            exit 1
        fi
        
        # If no .env file, try to prompt for cluster ID
        if [ -z "${CLUSTER_ID:-}" ]; then
            echo -n "Enter Aurora cluster identifier to delete: "
            read -r CLUSTER_ID
            if [ -z "$CLUSTER_ID" ]; then
                error "Cluster ID is required for cleanup"
                exit 1
            fi
        fi
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo -e "${RED}WARNING: This will permanently delete the following resources:${NC}"
    echo "- Aurora Serverless cluster: ${CLUSTER_ID:-'Unknown'}"
    echo "- All database instances in the cluster"
    echo "- CloudWatch alarms"
    echo "- Security groups"
    echo "- DB subnet groups"
    echo "- Parameter groups"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "User confirmed destruction. Proceeding with cleanup..."
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms=(
        "Aurora-${CLUSTER_ID}-High-ACU"
        "Aurora-${CLUSTER_ID}-Low-ACU"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" &>/dev/null; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            success "Deleted alarm: $alarm"
        else
            warning "Alarm not found: $alarm"
        fi
    done
}

# Function to delete DB instances
delete_db_instances() {
    log "Deleting Aurora DB instances..."
    
    local instances=(
        "${CLUSTER_ID}-reader"
        "${CLUSTER_ID}-writer"
    )
    
    # Delete read replica first
    for instance in "${instances[@]}"; do
        if aws rds describe-db-instances --db-instance-identifier "$instance" &>/dev/null; then
            log "Deleting DB instance: $instance"
            aws rds delete-db-instance \
                --db-instance-identifier "$instance" \
                --skip-final-snapshot
            
            log "Waiting for instance $instance to be deleted..."
            aws rds wait db-instance-deleted --db-instance-identifier "$instance"
            success "DB instance deleted: $instance"
        else
            warning "DB instance not found: $instance"
        fi
    done
}

# Function to delete Aurora cluster
delete_aurora_cluster() {
    log "Deleting Aurora cluster..."
    
    if aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" &>/dev/null; then
        # Remove deletion protection first
        log "Removing deletion protection..."
        aws rds modify-db-cluster \
            --db-cluster-identifier "$CLUSTER_ID" \
            --no-deletion-protection \
            --apply-immediately
        
        # Wait a moment for the modification to take effect
        sleep 10
        
        # Delete the cluster
        log "Deleting cluster: $CLUSTER_ID"
        aws rds delete-db-cluster \
            --db-cluster-identifier "$CLUSTER_ID" \
            --skip-final-snapshot
        
        log "Waiting for cluster to be deleted..."
        aws rds wait db-cluster-deleted --db-cluster-identifier "$CLUSTER_ID"
        success "Aurora cluster deleted: $CLUSTER_ID"
    else
        warning "Aurora cluster not found: $CLUSTER_ID"
    fi
}

# Function to delete parameter group
delete_parameter_group() {
    log "Deleting DB cluster parameter group..."
    
    if [ -n "${PARAMETER_GROUP_NAME:-}" ]; then
        if aws rds describe-db-cluster-parameter-groups \
            --db-cluster-parameter-group-name "$PARAMETER_GROUP_NAME" &>/dev/null; then
            
            aws rds delete-db-cluster-parameter-group \
                --db-cluster-parameter-group-name "$PARAMETER_GROUP_NAME"
            success "Parameter group deleted: $PARAMETER_GROUP_NAME"
        else
            warning "Parameter group not found: $PARAMETER_GROUP_NAME"
        fi
    else
        warning "Parameter group name not available, skipping deletion"
    fi
}

# Function to delete subnet group
delete_subnet_group() {
    log "Deleting DB subnet group..."
    
    if [ -n "${SUBNET_GROUP_NAME:-}" ]; then
        if aws rds describe-db-subnet-groups \
            --db-subnet-group-name "$SUBNET_GROUP_NAME" &>/dev/null; then
            
            aws rds delete-db-subnet-group \
                --db-subnet-group-name "$SUBNET_GROUP_NAME"
            success "Subnet group deleted: $SUBNET_GROUP_NAME"
        else
            warning "Subnet group not found: $SUBNET_GROUP_NAME"
        fi
    else
        warning "Subnet group name not available, skipping deletion"
    fi
}

# Function to delete security group
delete_security_group() {
    log "Deleting security group..."
    
    if [ -n "${SG_ID:-}" ]; then
        if aws ec2 describe-security-groups --group-ids "$SG_ID" &>/dev/null; then
            aws ec2 delete-security-group --group-id "$SG_ID"
            success "Security group deleted: $SG_ID"
        else
            warning "Security group not found: $SG_ID"
        fi
    else
        warning "Security group ID not available, attempting to find by name..."
        
        # Try to find security group by name pattern
        if [ -n "${CLUSTER_ID:-}" ]; then
            local sg_name="aurora-serverless-sg-*"
            local found_sgs=$(aws ec2 describe-security-groups \
                --filters "Name=group-name,Values=$sg_name" \
                --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
            
            if [ -n "$found_sgs" ]; then
                for sg_id in $found_sgs; do
                    aws ec2 delete-security-group --group-id "$sg_id"
                    success "Security group deleted: $sg_id"
                done
            else
                warning "No matching security groups found"
            fi
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files=(
        ".env"
        "aurora_connection_test.sql"
    )
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            success "Deleted file: $file"
        fi
    done
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues=0
    
    # Check if cluster still exists
    if aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" &>/dev/null; then
        warning "Aurora cluster still exists: $CLUSTER_ID"
        ((issues++))
    fi
    
    # Check if instances still exist
    local instances=(
        "${CLUSTER_ID}-reader"
        "${CLUSTER_ID}-writer"
    )
    
    for instance in "${instances[@]}"; do
        if aws rds describe-db-instances --db-instance-identifier "$instance" &>/dev/null; then
            warning "DB instance still exists: $instance"
            ((issues++))
        fi
    done
    
    # Check CloudWatch alarms
    local alarms=(
        "Aurora-${CLUSTER_ID}-High-ACU"
        "Aurora-${CLUSTER_ID}-Low-ACU"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "None"; then
            # Alarm doesn't exist, which is good
            continue
        else
            warning "CloudWatch alarm still exists: $alarm"
            ((issues++))
        fi
    done
    
    if [ $issues -eq 0 ]; then
        success "Cleanup verification completed successfully"
    else
        warning "Cleanup verification found $issues remaining issues"
        warning "Some resources may take additional time to be fully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been deleted:"
    echo "- Aurora Serverless cluster: ${CLUSTER_ID:-'Unknown'}"
    echo "- DB instances (writer and reader)"
    echo "- CloudWatch alarms"
    echo "- Security group"
    echo "- DB subnet group"
    echo "- Parameter group"
    echo "- Local configuration files"
    echo ""
    echo "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log "Starting Aurora Serverless cleanup..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_alarms
    delete_db_instances
    delete_aurora_cluster
    delete_parameter_group
    delete_subnet_group
    delete_security_group
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
    
    success "Aurora Serverless cleanup completed successfully!"
}

# Trap errors
trap 'error "Cleanup failed at line $LINENO. Some resources may still exist."' ERR

# Help function
show_help() {
    echo "Aurora Serverless Cleanup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Skip confirmation prompt (use with caution)"
    echo ""
    echo "This script will delete all resources created by the deploy script."
    echo "Environment variables will be loaded from .env file if present."
    echo ""
}

# Parse command line arguments
FORCE_DELETE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation function if force delete is enabled
if [ "$FORCE_DELETE" = true ]; then
    confirm_destruction() {
        warning "Force delete enabled, skipping confirmation"
    }
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi