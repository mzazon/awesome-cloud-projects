#!/bin/bash

set -euo pipefail

# Multi-AZ Database Deployments for High Availability - Cleanup Script
# This script safely removes all resources created by the deployment script

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "Script failed at line $1. Some resources may not have been cleaned up."
    log_warning "Please check AWS console and clean up any remaining resources manually."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo -e "${RED}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║               Multi-AZ Database Deployments - CLEANUP SCRIPT                 ║
║                                                                               ║
║  This script will permanently delete all resources created by the            ║
║  deployment script. This action cannot be undone!                            ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Set environment variables
export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    log_warning "No region configured, defaulting to us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

log "Region: $AWS_REGION"
log "Account ID: $AWS_ACCOUNT_ID"

# Function to get cluster names from deployment info or prompt user
get_cluster_name() {
    local cluster_name=""
    
    # First try to read from deployment info file
    if [[ -f "/tmp/multiaz-deployment-info.txt" ]]; then
        cluster_name=$(grep "Cluster Name:" /tmp/multiaz-deployment-info.txt | cut -d' ' -f3 2>/dev/null || echo "")
        if [[ -n "$cluster_name" ]]; then
            log "Found cluster name from deployment info: $cluster_name"
            echo "$cluster_name"
            return 0
        fi
    fi
    
    # List available clusters and let user choose
    log "Looking for Multi-AZ clusters in your account..."
    local clusters
    clusters=$(aws rds describe-db-clusters \
        --query 'DBClusters[?Engine==`aurora-postgresql`].DBClusterIdentifier' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$clusters" ]]; then
        log_warning "No Aurora PostgreSQL clusters found in your account."
        return 1
    fi
    
    echo ""
    log "Available Aurora PostgreSQL clusters:"
    local cluster_array=($clusters)
    for i in "${!cluster_array[@]}"; do
        echo "  $((i+1)). ${cluster_array[$i]}"
    done
    echo ""
    
    while true; do
        read -p "Enter the number of the cluster to delete (or 'q' to quit): " choice
        if [[ "$choice" == "q" ]]; then
            log "Cleanup cancelled by user."
            exit 0
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#cluster_array[@]}" ]]; then
            cluster_name="${cluster_array[$((choice-1))]}"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ${#cluster_array[@]}."
        fi
    done
    
    echo "$cluster_name"
}

# Function to prompt for confirmation
confirm_deletion() {
    local cluster_name="$1"
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  • RDS Cluster: $cluster_name"
    echo "  • All DB instances in the cluster"
    echo "  • CloudWatch alarms and dashboard"
    echo "  • Security groups, subnet groups, and parameter groups"
    echo "  • Parameter Store entries"
    echo "  • Manual snapshots"
    echo ""
    log_warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Type 'DELETE' to confirm permanent deletion: " final_confirmation
    if [[ "$final_confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
}

# Get cluster name
CLUSTER_NAME=$(get_cluster_name)
if [[ -z "$CLUSTER_NAME" ]]; then
    log_error "No cluster specified or found. Exiting."
    exit 1
fi

# Confirm deletion
confirm_deletion "$CLUSTER_NAME"

log "Starting cleanup process for cluster: $CLUSTER_NAME"

# Derive resource names from cluster name (assumes naming convention from deploy script)
DB_SUBNET_GROUP_NAME=""
DB_PARAMETER_GROUP_NAME=""
VPC_SECURITY_GROUP_NAME=""

# Try to get resource names from Parameter Store or derive them
if aws ssm get-parameter --name "/rds/multiaz/${CLUSTER_NAME}/writer-endpoint" &>/dev/null; then
    # Extract suffix from cluster name
    SUFFIX="${CLUSTER_NAME##*-}"
    DB_SUBNET_GROUP_NAME="multiaz-subnet-group-${SUFFIX}"
    DB_PARAMETER_GROUP_NAME="multiaz-param-group-${SUFFIX}"
    VPC_SECURITY_GROUP_NAME="multiaz-sg-${SUFFIX}"
else
    log_warning "Parameter Store entries not found. Will attempt to find resources by tags."
fi

# Step 1: Remove CloudWatch Alarms and Dashboard
log "Step 1: Removing CloudWatch Alarms and Dashboard..."

# Delete CloudWatch alarms
for alarm in "${CLUSTER_NAME}-high-connections" "${CLUSTER_NAME}-high-cpu"; do
    if aws cloudwatch describe-alarms --alarm-names "$alarm" &>/dev/null; then
        aws cloudwatch delete-alarms --alarm-names "$alarm"
        log_success "Deleted alarm: $alarm"
    else
        log_warning "Alarm not found: $alarm"
    fi
done

# Delete CloudWatch dashboard
if aws cloudwatch get-dashboard --dashboard-name "${CLUSTER_NAME}-monitoring" &>/dev/null; then
    aws cloudwatch delete-dashboards --dashboard-names "${CLUSTER_NAME}-monitoring"
    log_success "Deleted dashboard: ${CLUSTER_NAME}-monitoring"
else
    log_warning "Dashboard not found: ${CLUSTER_NAME}-monitoring"
fi

# Step 2: Delete Manual Snapshots
log "Step 2: Deleting Manual Snapshots..."

# List and delete manual snapshots for this cluster
SNAPSHOTS=$(aws rds describe-db-cluster-snapshots \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --snapshot-type manual \
    --query 'DBClusterSnapshots[*].DBClusterSnapshotIdentifier' \
    --output text 2>/dev/null || echo "")

if [[ -n "$SNAPSHOTS" ]]; then
    for snapshot in $SNAPSHOTS; do
        log "Deleting snapshot: $snapshot"
        aws rds delete-db-cluster-snapshot \
            --db-cluster-snapshot-identifier "$snapshot"
        log_success "Deleted snapshot: $snapshot"
    done
else
    log_warning "No manual snapshots found for cluster: $CLUSTER_NAME"
fi

# Step 3: Get DB Instance Information
log "Step 3: Identifying DB Instances in Cluster..."

# Get all instances in the cluster
DB_INSTANCES=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --query 'DBClusters[0].DBClusterMembers[*].DBInstanceIdentifier' \
    --output text 2>/dev/null || echo "")

if [[ -z "$DB_INSTANCES" ]]; then
    log_warning "No DB instances found in cluster or cluster doesn't exist"
else
    log "Found DB instances: $DB_INSTANCES"
fi

# Step 4: Delete DB Instances
if [[ -n "$DB_INSTANCES" ]]; then
    log "Step 4: Deleting DB Instances..."
    
    # Delete all instances in parallel
    for instance in $DB_INSTANCES; do
        log "Initiating deletion of instance: $instance"
        aws rds delete-db-instance \
            --db-instance-identifier "$instance" \
            --skip-final-snapshot &
    done
    
    # Wait for all deletions to start
    wait
    
    # Wait for all instances to be deleted
    log "Waiting for all instances to be deleted (this may take 10-15 minutes)..."
    for instance in $DB_INSTANCES; do
        log "Waiting for instance to be deleted: $instance"
        aws rds wait db-instance-deleted --db-instance-identifier "$instance" &
    done
    
    # Wait for all wait commands to complete
    wait
    log_success "All DB instances deleted"
else
    log_warning "No DB instances to delete"
fi

# Step 5: Delete DB Cluster
log "Step 5: Deleting DB Cluster..."

# Check if cluster exists and disable deletion protection
if aws rds describe-db-clusters --db-cluster-identifier "${CLUSTER_NAME}" &>/dev/null; then
    log "Disabling deletion protection..."
    aws rds modify-db-cluster \
        --db-cluster-identifier "${CLUSTER_NAME}" \
        --no-deletion-protection \
        --apply-immediately || log_warning "Could not disable deletion protection"
    
    # Wait a moment for the modification to take effect
    sleep 10
    
    log "Deleting cluster: $CLUSTER_NAME"
    aws rds delete-db-cluster \
        --db-cluster-identifier "${CLUSTER_NAME}" \
        --skip-final-snapshot
    
    log_success "DB cluster deletion initiated: $CLUSTER_NAME"
else
    log_warning "Cluster not found: $CLUSTER_NAME"
fi

# Step 6: Delete Parameter Groups
log "Step 6: Deleting Parameter Groups..."

if [[ -n "$DB_PARAMETER_GROUP_NAME" ]]; then
    # Wait for cluster to be fully deleted before deleting parameter group
    log "Waiting for cluster to be fully deleted before removing parameter group..."
    sleep 30
    
    if aws rds describe-db-cluster-parameter-groups --db-cluster-parameter-group-name "$DB_PARAMETER_GROUP_NAME" &>/dev/null; then
        aws rds delete-db-cluster-parameter-group \
            --db-cluster-parameter-group-name "$DB_PARAMETER_GROUP_NAME"
        log_success "Deleted parameter group: $DB_PARAMETER_GROUP_NAME"
    else
        log_warning "Parameter group not found: $DB_PARAMETER_GROUP_NAME"
    fi
else
    # Try to find parameter groups by tags
    log_warning "Parameter group name not specified, searching by tags..."
    PARAM_GROUPS=$(aws rds describe-db-cluster-parameter-groups \
        --query "DBClusterParameterGroups[?contains(Description, 'Multi-AZ PostgreSQL cluster')].DBClusterParameterGroupName" \
        --output text 2>/dev/null || echo "")
    
    for pg in $PARAM_GROUPS; do
        if [[ "$pg" == *"multiaz"* ]]; then
            aws rds delete-db-cluster-parameter-group --db-cluster-parameter-group-name "$pg" || true
            log_success "Deleted parameter group: $pg"
        fi
    done
fi

# Step 7: Delete Subnet Groups
log "Step 7: Deleting Subnet Groups..."

if [[ -n "$DB_SUBNET_GROUP_NAME" ]]; then
    if aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" &>/dev/null; then
        aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP_NAME"
        log_success "Deleted subnet group: $DB_SUBNET_GROUP_NAME"
    else
        log_warning "Subnet group not found: $DB_SUBNET_GROUP_NAME"
    fi
else
    # Try to find subnet groups by description
    log_warning "Subnet group name not specified, searching by description..."
    SUBNET_GROUPS=$(aws rds describe-db-subnet-groups \
        --query "DBSubnetGroups[?contains(DBSubnetGroupDescription, 'Multi-AZ RDS cluster')].DBSubnetGroupName" \
        --output text 2>/dev/null || echo "")
    
    for sg in $SUBNET_GROUPS; do
        aws rds delete-db-subnet-group --db-subnet-group-name "$sg" || true
        log_success "Deleted subnet group: $sg"
    done
fi

# Step 8: Delete Security Groups
log "Step 8: Deleting Security Groups..."

if [[ -n "$VPC_SECURITY_GROUP_NAME" ]]; then
    # Get security group ID by name
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$VPC_SECURITY_GROUP_NAME" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
        aws ec2 delete-security-group --group-id "$SG_ID"
        log_success "Deleted security group: $VPC_SECURITY_GROUP_NAME ($SG_ID)"
    else
        log_warning "Security group not found: $VPC_SECURITY_GROUP_NAME"
    fi
else
    # Try to find security groups by description
    log_warning "Security group name not specified, searching by description..."
    SG_IDS=$(aws ec2 describe-security-groups \
        --filters "Name=description,Values=Security group for Multi-AZ RDS cluster" \
        --query 'SecurityGroups[*].GroupId' \
        --output text 2>/dev/null || echo "")
    
    for sg_id in $SG_IDS; do
        aws ec2 delete-security-group --group-id "$sg_id" || true
        log_success "Deleted security group: $sg_id"
    done
fi

# Step 9: Clean Up Parameter Store
log "Step 9: Cleaning Up Parameter Store..."

# Delete all parameter store entries for this cluster
PARAM_PATHS=(
    "/rds/multiaz/${CLUSTER_NAME}/password"
    "/rds/multiaz/${CLUSTER_NAME}/writer-endpoint"
    "/rds/multiaz/${CLUSTER_NAME}/reader-endpoint"
    "/rds/multiaz/${CLUSTER_NAME}/username"
)

for param_path in "${PARAM_PATHS[@]}"; do
    if aws ssm get-parameter --name "$param_path" &>/dev/null; then
        aws ssm delete-parameter --name "$param_path"
        log_success "Deleted parameter: $param_path"
    else
        log_warning "Parameter not found: $param_path"
    fi
done

# Step 10: Clean Up Local Files
log "Step 10: Cleaning Up Local Files..."

if [[ -f "/tmp/multiaz-deployment-info.txt" ]]; then
    rm -f "/tmp/multiaz-deployment-info.txt"
    log_success "Deleted deployment info file"
fi

# Final verification
log "Step 11: Performing Final Verification..."

# Check if cluster still exists
if aws rds describe-db-clusters --db-cluster-identifier "${CLUSTER_NAME}" &>/dev/null; then
    log_warning "Cluster still exists (deletion may be in progress): $CLUSTER_NAME"
else
    log_success "Cluster successfully deleted: $CLUSTER_NAME"
fi

# Cleanup summary
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║                         CLEANUP COMPLETED SUCCESSFULLY!                      ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_success "Multi-AZ Database cleanup completed!"
echo ""
log "Resources cleaned up:"
echo "  ✅ RDS cluster and instances"
echo "  ✅ CloudWatch alarms and dashboard"
echo "  ✅ Manual snapshots"
echo "  ✅ Parameter groups and subnet groups"
echo "  ✅ Security groups"
echo "  ✅ Parameter Store entries"
echo "  ✅ Local deployment files"
echo ""
log_warning "Note: Automated backups may still exist and will be retained according to the backup retention period."
log_warning "If you want to delete automated backups, you can do so manually in the AWS console."
echo ""
log "💰 All billable resources have been removed. You should no longer incur charges for this deployment."

exit 0