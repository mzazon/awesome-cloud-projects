#!/bin/bash

# AWS DMS Database Migration Cleanup Script
# This script safely destroys all AWS DMS migration infrastructure
# Including migration tasks, endpoints, replication instances, databases, and networking

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a destroy.log
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a destroy.log
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}" | tee -a destroy.log
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a destroy.log
}

# Function to safely delete resources with retries
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$delete_command" 2>/dev/null; then
            log_success "$resource_type deleted successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warning "$resource_type deletion failed, retrying ($retry_count/$max_retries)..."
                sleep 10
            else
                log_error "$resource_type deletion failed after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to check if resource exists
resource_exists() {
    local check_command="$1"
    eval "$check_command" &>/dev/null
}

# Parse command line arguments
SKIP_CONFIRMATIONS=false
ENVIRONMENT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirmations)
            SKIP_CONFIRMATIONS=true
            shift
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Destroy AWS DMS database migration infrastructure"
            echo ""
            echo "Options:"
            echo "  --skip-confirmations   Skip confirmation prompts"
            echo "  --environment ENV      Set environment name"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "Starting AWS DMS Database Migration infrastructure cleanup..."

# Check if resource_ids.env exists
if [[ ! -f "resource_ids.env" ]]; then
    log_error "resource_ids.env file not found. Cannot determine resources to delete."
    log "Please ensure you're running this script from the same directory as the deployment."
    exit 1
fi

# Load resource IDs
log "Loading resource identifiers..."
source resource_ids.env

# Validate required environment variables
required_vars=(
    "AWS_REGION"
    "DMS_REPLICATION_INSTANCE_ID"
    "DMS_SUBNET_GROUP_ID"
    "TARGET_DB_INSTANCE_ID"
    "TARGET_ENDPOINT_ID"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        log_error "Required environment variable $var is not set in resource_ids.env"
        exit 1
    fi
done

log "Environment: ${ENVIRONMENT:-unknown}"
log "Region: $AWS_REGION"

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

log_success "Prerequisites check completed"

# Safety confirmation
if [[ "$SKIP_CONFIRMATIONS" != "true" ]]; then
    echo ""
    log_warning "This will PERMANENTLY DELETE the following resources:"
    echo ""
    log "Migration Infrastructure:"
    log "- DMS Replication Instance: $DMS_REPLICATION_INSTANCE_ID"
    log "- DMS Subnet Group: $DMS_SUBNET_GROUP_ID"
    log "- Target Database: $TARGET_DB_INSTANCE_ID"
    echo ""
    log "Network Infrastructure:"
    log "- VPC: ${VPC_ID:-unknown}"
    log "- Subnets: ${SUBNET_1_ID:-unknown}, ${SUBNET_2_ID:-unknown}"
    log "- Internet Gateway: ${IGW_ID:-unknown}"
    echo ""
    log "Monitoring:"
    log "- CloudWatch Dashboard: DMS-Migration-Dashboard-${ENVIRONMENT:-unknown}"
    log "- CloudWatch Log Group: /aws/dms/tasks"
    echo ""
    log "Secrets:"
    log "- Database password in AWS Secrets Manager"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? Type 'delete' to confirm: " -r
    if [[ "$REPLY" != "delete" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Start cleanup process
log "Starting resource cleanup..."

# Step 1: Stop and delete migration tasks
log "Stopping and deleting migration tasks..."

# Check and stop/delete migration tasks
if [[ -n "$MIGRATION_TASK_ID" ]]; then
    if resource_exists "aws dms describe-replication-tasks --replication-task-identifier $MIGRATION_TASK_ID"; then
        log "Stopping migration task: $MIGRATION_TASK_ID"
        aws dms stop-replication-task \
            --replication-task-identifier $MIGRATION_TASK_ID || true
        
        log "Waiting for migration task to stop..."
        aws dms wait replication-task-stopped \
            --replication-task-identifier $MIGRATION_TASK_ID || true
        
        safe_delete "Migration task" \
            "aws dms delete-replication-task --replication-task-identifier $MIGRATION_TASK_ID"
    else
        log_warning "Migration task $MIGRATION_TASK_ID not found"
    fi
fi

# Check and stop/delete CDC tasks
if [[ -n "$CDC_TASK_ID" ]]; then
    if resource_exists "aws dms describe-replication-tasks --replication-task-identifier $CDC_TASK_ID"; then
        log "Stopping CDC task: $CDC_TASK_ID"
        aws dms stop-replication-task \
            --replication-task-identifier $CDC_TASK_ID || true
        
        log "Waiting for CDC task to stop..."
        aws dms wait replication-task-stopped \
            --replication-task-identifier $CDC_TASK_ID || true
        
        safe_delete "CDC task" \
            "aws dms delete-replication-task --replication-task-identifier $CDC_TASK_ID"
    else
        log_warning "CDC task $CDC_TASK_ID not found"
    fi
fi

# Step 2: Delete database endpoints
log "Deleting database endpoints..."

# Delete source endpoint if it exists
if [[ -n "$SOURCE_ENDPOINT_ID" ]]; then
    if resource_exists "aws dms describe-endpoints --endpoint-identifier $SOURCE_ENDPOINT_ID"; then
        safe_delete "Source endpoint" \
            "aws dms delete-endpoint --endpoint-identifier $SOURCE_ENDPOINT_ID"
    else
        log_warning "Source endpoint $SOURCE_ENDPOINT_ID not found"
    fi
fi

# Delete target endpoint
if resource_exists "aws dms describe-endpoints --endpoint-identifier $TARGET_ENDPOINT_ID"; then
    safe_delete "Target endpoint" \
        "aws dms delete-endpoint --endpoint-identifier $TARGET_ENDPOINT_ID"
else
    log_warning "Target endpoint $TARGET_ENDPOINT_ID not found"
fi

# Step 3: Delete DMS replication instance
log "Deleting DMS replication instance..."

if resource_exists "aws dms describe-replication-instances --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID"; then
    safe_delete "DMS replication instance" \
        "aws dms delete-replication-instance --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID"
    
    log "Waiting for replication instance to be deleted..."
    aws dms wait replication-instance-deleted \
        --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID || true
else
    log_warning "DMS replication instance $DMS_REPLICATION_INSTANCE_ID not found"
fi

# Step 4: Delete RDS database
log "Deleting RDS database..."

if resource_exists "aws rds describe-db-instances --db-instance-identifier $TARGET_DB_INSTANCE_ID"; then
    log "Deleting RDS database (this may take several minutes)..."
    aws rds delete-db-instance \
        --db-instance-identifier $TARGET_DB_INSTANCE_ID \
        --skip-final-snapshot \
        --delete-automated-backups || true
    
    log "Waiting for RDS database to be deleted..."
    aws rds wait db-instance-deleted \
        --db-instance-identifier $TARGET_DB_INSTANCE_ID || true
    
    log_success "RDS database deleted"
else
    log_warning "RDS database $TARGET_DB_INSTANCE_ID not found"
fi

# Step 5: Delete RDS subnet group
log "Deleting RDS subnet group..."

if [[ -n "$RANDOM_SUFFIX" ]]; then
    RDS_SUBNET_GROUP_NAME="rds-subnet-group-${ENVIRONMENT:-dev}-${RANDOM_SUFFIX}"
    if resource_exists "aws rds describe-db-subnet-groups --db-subnet-group-name $RDS_SUBNET_GROUP_NAME"; then
        safe_delete "RDS subnet group" \
            "aws rds delete-db-subnet-group --db-subnet-group-name $RDS_SUBNET_GROUP_NAME"
    else
        log_warning "RDS subnet group $RDS_SUBNET_GROUP_NAME not found"
    fi
fi

# Step 6: Delete DMS subnet group
log "Deleting DMS subnet group..."

if resource_exists "aws dms describe-replication-subnet-groups --replication-subnet-group-identifier $DMS_SUBNET_GROUP_ID"; then
    safe_delete "DMS subnet group" \
        "aws dms delete-replication-subnet-group --replication-subnet-group-identifier $DMS_SUBNET_GROUP_ID"
else
    log_warning "DMS subnet group $DMS_SUBNET_GROUP_ID not found"
fi

# Step 7: Delete AWS Secrets Manager secret
log "Deleting AWS Secrets Manager secret..."

if [[ -n "$RANDOM_SUFFIX" ]]; then
    SECRET_NAME="dms-migration-target-db-password-${ENVIRONMENT:-dev}-${RANDOM_SUFFIX}"
    if resource_exists "aws secretsmanager describe-secret --secret-id $SECRET_NAME"; then
        safe_delete "Secrets Manager secret" \
            "aws secretsmanager delete-secret --secret-id $SECRET_NAME --force-delete-without-recovery"
    else
        log_warning "Secret $SECRET_NAME not found"
    fi
fi

# Step 8: Delete CloudWatch resources
log "Deleting CloudWatch resources..."

# Delete CloudWatch dashboard
DASHBOARD_NAME="DMS-Migration-Dashboard-${ENVIRONMENT:-dev}"
if resource_exists "aws cloudwatch get-dashboard --dashboard-name $DASHBOARD_NAME"; then
    safe_delete "CloudWatch dashboard" \
        "aws cloudwatch delete-dashboard --dashboard-name $DASHBOARD_NAME"
else
    log_warning "CloudWatch dashboard $DASHBOARD_NAME not found"
fi

# Delete CloudWatch log group
if resource_exists "aws logs describe-log-groups --log-group-name-prefix /aws/dms/tasks"; then
    safe_delete "CloudWatch log group" \
        "aws logs delete-log-group --log-group-name /aws/dms/tasks"
else
    log_warning "CloudWatch log group /aws/dms/tasks not found"
fi

# Step 9: Delete VPC and networking resources
log "Deleting VPC and networking resources..."

# Delete route table associations first
if [[ -n "$ROUTE_TABLE_ID" && -n "$SUBNET_1_ID" ]]; then
    log "Disassociating route table from subnet 1..."
    aws ec2 disassociate-route-table \
        --association-id $(aws ec2 describe-route-tables \
            --route-table-ids $ROUTE_TABLE_ID \
            --query 'RouteTables[0].Associations[?SubnetId==`'$SUBNET_1_ID'`].RouteTableAssociationId' \
            --output text) || true
fi

if [[ -n "$ROUTE_TABLE_ID" && -n "$SUBNET_2_ID" ]]; then
    log "Disassociating route table from subnet 2..."
    aws ec2 disassociate-route-table \
        --association-id $(aws ec2 describe-route-tables \
            --route-table-ids $ROUTE_TABLE_ID \
            --query 'RouteTables[0].Associations[?SubnetId==`'$SUBNET_2_ID'`].RouteTableAssociationId' \
            --output text) || true
fi

# Delete route table
if [[ -n "$ROUTE_TABLE_ID" ]]; then
    if resource_exists "aws ec2 describe-route-tables --route-table-ids $ROUTE_TABLE_ID"; then
        safe_delete "Route table" \
            "aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID"
    else
        log_warning "Route table $ROUTE_TABLE_ID not found"
    fi
fi

# Detach and delete internet gateway
if [[ -n "$IGW_ID" && -n "$VPC_ID" ]]; then
    if resource_exists "aws ec2 describe-internet-gateways --internet-gateway-ids $IGW_ID"; then
        log "Detaching internet gateway..."
        aws ec2 detach-internet-gateway \
            --internet-gateway-id $IGW_ID \
            --vpc-id $VPC_ID || true
        
        safe_delete "Internet gateway" \
            "aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID"
    else
        log_warning "Internet gateway $IGW_ID not found"
    fi
fi

# Delete subnets
if [[ -n "$SUBNET_1_ID" ]]; then
    if resource_exists "aws ec2 describe-subnets --subnet-ids $SUBNET_1_ID"; then
        safe_delete "Subnet 1" \
            "aws ec2 delete-subnet --subnet-id $SUBNET_1_ID"
    else
        log_warning "Subnet $SUBNET_1_ID not found"
    fi
fi

if [[ -n "$SUBNET_2_ID" ]]; then
    if resource_exists "aws ec2 describe-subnets --subnet-ids $SUBNET_2_ID"; then
        safe_delete "Subnet 2" \
            "aws ec2 delete-subnet --subnet-id $SUBNET_2_ID"
    else
        log_warning "Subnet $SUBNET_2_ID not found"
    fi
fi

# Delete VPC
if [[ -n "$VPC_ID" ]]; then
    if resource_exists "aws ec2 describe-vpcs --vpc-ids $VPC_ID"; then
        safe_delete "VPC" \
            "aws ec2 delete-vpc --vpc-id $VPC_ID"
    else
        log_warning "VPC $VPC_ID not found"
    fi
fi

# Step 10: Clean up local files
log "Cleaning up local files..."

# List of files to clean up
local_files=(
    "table-mappings.json"
    "task-settings.json"
    "dashboard-config.json"
    "sct-project-config.json"
    "assessment-report-template.sql"
    "validate-migration.sh"
    "monitor-migration.sh"
    "resource_ids.env"
)

for file in "${local_files[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log_success "Removed local file: $file"
    fi
done

# Clean up environment variables
unset AWS_REGION AWS_ACCOUNT_ID DMS_REPLICATION_INSTANCE_ID DMS_SUBNET_GROUP_ID
unset SOURCE_ENDPOINT_ID TARGET_ENDPOINT_ID MIGRATION_TASK_ID CDC_TASK_ID
unset TARGET_DB_INSTANCE_ID TARGET_DB_HOST TARGET_DB_PASSWORD
unset VPC_ID SUBNET_1_ID SUBNET_2_ID IGW_ID ROUTE_TABLE_ID RANDOM_SUFFIX

log_success "Environment variables cleared"

# Final summary
log_success "AWS DMS Database Migration infrastructure cleanup completed!"
echo ""
log "=== Cleanup Summary ==="
log "All migration infrastructure resources have been destroyed"
log "All local configuration files have been removed"
log "All environment variables have been cleared"
echo ""
log "=== Cleanup Log ==="
log "Full cleanup log saved to: destroy.log"
echo ""
log_warning "Please verify in AWS console that all resources have been deleted"
log_warning "Some resources may take additional time to fully terminate"
echo ""
log "=== Cost Impact ==="
log "Resource charges should stop within a few minutes"
log "Final bills may include usage up to cleanup time"
echo ""
log_success "Cleanup process completed successfully!"