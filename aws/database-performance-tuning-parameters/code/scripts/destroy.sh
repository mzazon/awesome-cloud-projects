#!/bin/bash

# Database Performance Tuning with Parameter Groups - Cleanup Script
# This script safely removes all resources created by the deploy.sh script
# including RDS instances, parameter groups, VPC, and CloudWatch resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f /tmp/perf-tuning-env.sh ]]; then
        source /tmp/perf-tuning-env.sh
        success "Environment variables loaded from /tmp/perf-tuning-env.sh"
    else
        warning "Environment file not found. Attempting manual cleanup..."
        echo "Please provide the following information for cleanup:"
        read -p "Enter DB Instance ID (or press Enter to skip): " DB_INSTANCE_ID
        read -p "Enter Parameter Group Name (or press Enter to skip): " PARAMETER_GROUP_NAME
        read -p "Enter Random Suffix (or press Enter to skip): " RANDOM_SUFFIX
        
        if [[ -n "$RANDOM_SUFFIX" ]]; then
            export DB_INSTANCE_ID=${DB_INSTANCE_ID:-"perf-tuning-db-${RANDOM_SUFFIX}"}
            export PARAMETER_GROUP_NAME=${PARAMETER_GROUP_NAME:-"perf-tuning-pg-${RANDOM_SUFFIX}"}
            export SUBNET_GROUP_NAME="perf-tuning-subnet-${RANDOM_SUFFIX}"
            export SECURITY_GROUP_NAME="perf-tuning-sg-${RANDOM_SUFFIX}"
            export DASHBOARD_NAME="Database-Performance-Tuning-${RANDOM_SUFFIX}"
            export AWS_REGION=$(aws configure get region)
        fi
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    echo "⚠️  WARNING: This will DELETE the following resources:"
    echo "   - RDS Database Instance: ${DB_INSTANCE_ID:-'Not specified'}"
    echo "   - Read Replica (if exists): ${DB_INSTANCE_ID:-'Not specified'}-replica"
    echo "   - Parameter Group: ${PARAMETER_GROUP_NAME:-'Not specified'}"
    echo "   - CloudWatch Dashboard: ${DASHBOARD_NAME:-'Not specified'}"
    echo "   - CloudWatch Alarms"
    echo "   - VPC and networking resources"
    echo "   - Security groups and subnets"
    echo ""
    echo "⚠️  This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to delete RDS instances
delete_rds_instances() {
    log "Deleting RDS instances..."
    
    # Check if read replica exists and delete it first
    if aws rds describe-db-instances --db-instance-identifier "${DB_INSTANCE_ID}-replica" &> /dev/null; then
        log "Deleting read replica: ${DB_INSTANCE_ID}-replica"
        aws rds delete-db-instance \
            --db-instance-identifier "${DB_INSTANCE_ID}-replica" \
            --skip-final-snapshot \
            --delete-automated-backups || warning "Failed to delete read replica"
        
        # Wait for replica deletion
        log "Waiting for read replica deletion to complete..."
        aws rds wait db-instance-deleted \
            --db-instance-identifier "${DB_INSTANCE_ID}-replica" || warning "Timeout waiting for replica deletion"
        
        success "Read replica deleted"
    else
        log "No read replica found to delete"
    fi
    
    # Delete primary database instance
    if [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" &> /dev/null; then
            log "Deleting primary database instance: $DB_INSTANCE_ID"
            aws rds delete-db-instance \
                --db-instance-identifier "$DB_INSTANCE_ID" \
                --skip-final-snapshot \
                --delete-automated-backups || warning "Failed to delete primary database instance"
            
            # Wait for primary instance deletion
            log "Waiting for primary database deletion to complete (this may take several minutes)..."
            aws rds wait db-instance-deleted \
                --db-instance-identifier "$DB_INSTANCE_ID" || warning "Timeout waiting for database deletion"
            
            success "Primary database instance deleted"
        else
            log "Primary database instance not found or already deleted"
        fi
    else
        warning "DB_INSTANCE_ID not specified, skipping database deletion"
    fi
}

# Function to delete parameter groups and subnet groups
delete_parameter_groups() {
    log "Deleting parameter groups and subnet groups..."
    
    # Delete custom parameter group
    if [[ -n "${PARAMETER_GROUP_NAME:-}" ]]; then
        if aws rds describe-db-parameter-groups --db-parameter-group-name "$PARAMETER_GROUP_NAME" &> /dev/null; then
            log "Deleting parameter group: $PARAMETER_GROUP_NAME"
            aws rds delete-db-parameter-group \
                --db-parameter-group-name "$PARAMETER_GROUP_NAME" || warning "Failed to delete parameter group"
            success "Parameter group deleted"
        else
            log "Parameter group not found or already deleted"
        fi
    else
        warning "PARAMETER_GROUP_NAME not specified, skipping parameter group deletion"
    fi
    
    # Delete subnet group
    if [[ -n "${SUBNET_GROUP_NAME:-}" ]]; then
        if aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP_NAME" &> /dev/null; then
            log "Deleting subnet group: $SUBNET_GROUP_NAME"
            aws rds delete-db-subnet-group \
                --db-subnet-group-name "$SUBNET_GROUP_NAME" || warning "Failed to delete subnet group"
            success "Subnet group deleted"
        else
            log "Subnet group not found or already deleted"
        fi
    else
        warning "SUBNET_GROUP_NAME not specified, skipping subnet group deletion"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &> /dev/null; then
            log "Deleting CloudWatch dashboard: $DASHBOARD_NAME"
            aws cloudwatch delete-dashboards \
                --dashboard-names "$DASHBOARD_NAME" || warning "Failed to delete dashboard"
            success "CloudWatch dashboard deleted"
        else
            log "CloudWatch dashboard not found or already deleted"
        fi
    else
        warning "DASHBOARD_NAME not specified, skipping dashboard deletion"
    fi
    
    # Delete CloudWatch alarms
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local alarm_names=(
            "Database-High-CPU-${RANDOM_SUFFIX}"
            "Database-High-Connections-${RANDOM_SUFFIX}" 
            "Database-High-Read-Latency-${RANDOM_SUFFIX}"
        )
        
        for alarm_name in "${alarm_names[@]}"; do
            if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0].AlarmName' --output text | grep -q "$alarm_name"; then
                log "Deleting CloudWatch alarm: $alarm_name"
                aws cloudwatch delete-alarms --alarm-names "$alarm_name" || warning "Failed to delete alarm: $alarm_name"
            else
                log "CloudWatch alarm not found: $alarm_name"
            fi
        done
        
        success "CloudWatch alarms deleted"
    else
        warning "RANDOM_SUFFIX not specified, skipping alarm deletion"
    fi
}

# Function to delete networking resources
delete_networking_resources() {
    log "Deleting networking resources..."
    
    # Delete security group
    if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
        if aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" &> /dev/null; then
            log "Deleting security group: $SECURITY_GROUP_ID"
            aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID" || warning "Failed to delete security group"
            success "Security group deleted"
        else
            log "Security group not found or already deleted"
        fi
    elif [[ -n "${SECURITY_GROUP_NAME:-}" ]]; then
        # Try to find security group by name
        local sg_id=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
            --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
        
        if [[ "$sg_id" != "None" && "$sg_id" != "" ]]; then
            log "Deleting security group by name: $SECURITY_GROUP_NAME ($sg_id)"
            aws ec2 delete-security-group --group-id "$sg_id" || warning "Failed to delete security group"
            success "Security group deleted"
        else
            log "Security group not found: $SECURITY_GROUP_NAME"
        fi
    else
        warning "Security group identifier not specified, skipping security group deletion"
    fi
    
    # Delete subnets
    if [[ -n "${SUBNET_1_ID:-}" ]]; then
        if aws ec2 describe-subnets --subnet-ids "$SUBNET_1_ID" &> /dev/null; then
            log "Deleting subnet: $SUBNET_1_ID"
            aws ec2 delete-subnet --subnet-id "$SUBNET_1_ID" || warning "Failed to delete subnet 1"
        else
            log "Subnet 1 not found or already deleted"
        fi
    fi
    
    if [[ -n "${SUBNET_2_ID:-}" ]]; then
        if aws ec2 describe-subnets --subnet-ids "$SUBNET_2_ID" &> /dev/null; then
            log "Deleting subnet: $SUBNET_2_ID"
            aws ec2 delete-subnet --subnet-id "$SUBNET_2_ID" || warning "Failed to delete subnet 2"
        else
            log "Subnet 2 not found or already deleted"
        fi
    fi
    
    # Delete VPC
    if [[ -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &> /dev/null; then
            log "Deleting VPC: $VPC_ID"
            aws ec2 delete-vpc --vpc-id "$VPC_ID" || warning "Failed to delete VPC"
            success "VPC deleted"
        else
            log "VPC not found or already deleted"
        fi
    else
        warning "VPC_ID not specified, skipping VPC deletion"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/perf-tuning-env.sh"
        "/tmp/create_test_data.sql"
        "/tmp/baseline_test.sql"
        "/tmp/analyze_performance.sql"
        "/tmp/concurrent_test.sql"
        "/tmp/load_test.sql"
        "/tmp/dashboard.json"
        "/tmp/rds-monitoring-trust-policy.json"
        "/tmp/baseline_results.txt"
        "/tmp/optimized_results.txt"
        "/tmp/analysis_results.txt"
        "/tmp/baseline_parameters.txt"
        "/tmp/baseline_times.txt"
        "/tmp/optimized_times.txt"
        "/tmp/load_test_results.txt"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    # Clean up any concurrent test result files
    rm -f /tmp/concurrent_test_*.txt 2>/dev/null || true
    
    success "Temporary files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if database instance still exists
    if [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" &> /dev/null; then
            warning "Database instance still exists: $DB_INSTANCE_ID"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if parameter group still exists
    if [[ -n "${PARAMETER_GROUP_NAME:-}" ]]; then
        if aws rds describe-db-parameter-groups --db-parameter-group-name "$PARAMETER_GROUP_NAME" &> /dev/null; then
            warning "Parameter group still exists: $PARAMETER_GROUP_NAME"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if VPC still exists
    if [[ -n "${VPC_ID:-}" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &> /dev/null; then
            warning "VPC still exists: $VPC_ID"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification completed successfully"
    else
        warning "Cleanup completed with $cleanup_issues potential issues. Please check AWS console for remaining resources."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been processed for deletion:"
    echo "  ✓ RDS Database Instance: ${DB_INSTANCE_ID:-'Not specified'}"
    echo "  ✓ Read Replica (if existed)"
    echo "  ✓ Parameter Group: ${PARAMETER_GROUP_NAME:-'Not specified'}"
    echo "  ✓ CloudWatch Dashboard: ${DASHBOARD_NAME:-'Not specified'}"
    echo "  ✓ CloudWatch Alarms"
    echo "  ✓ VPC and networking resources"
    echo "  ✓ Security groups and subnets"
    echo "  ✓ Temporary files"
    echo ""
    echo "Note: RDS deletion may take several minutes to complete."
    echo "Please check the AWS Console to confirm all resources are deleted."
    echo ""
    success "Cleanup process completed!"
}

# Main cleanup function
main() {
    log "Starting Database Performance Tuning cleanup..."
    
    load_environment
    confirm_cleanup
    delete_rds_instances
    delete_parameter_groups
    delete_cloudwatch_resources
    delete_networking_resources
    cleanup_temp_files
    verify_cleanup
    display_cleanup_summary
}

# Handle script interruption
trap 'error "Cleanup script interrupted. Some resources may still exist."' INT TERM

# Run main function
main "$@"