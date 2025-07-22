#!/bin/bash

# AWS Aurora Minimal Downtime Migration - Cleanup Script
# This script removes all infrastructure created for the Aurora migration

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Configuration file to load deployment variables
CONFIG_FILE="./deployment-config.env"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check for configuration file
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration file $CONFIG_FILE not found. Cannot proceed with cleanup."
        echo "Please ensure you run this script from the same directory where deploy.sh was executed."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    source "$CONFIG_FILE"
    
    # Verify required variables are set
    required_vars=(
        "AWS_ACCOUNT_ID" "AWS_REGION" "MIGRATION_SUFFIX"
        "VPC_ID" "SUBNET_1_ID" "SUBNET_2_ID"
        "AURORA_SG_ID" "DMS_SG_ID"
        "AURORA_CLUSTER_ID" "DMS_REPLICATION_INSTANCE_ID"
        "SOURCE_ENDPOINT_ID" "TARGET_ENDPOINT_ID"
        "MIGRATION_TASK_ID" "HOSTED_ZONE_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            warning "Variable $var is not set in configuration file"
        fi
    done
    
    success "Configuration loaded successfully"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "==============================================="
    echo "WARNING: This will destroy the following resources:"
    echo "==============================================="
    echo "- Aurora Cluster: $AURORA_CLUSTER_ID"
    echo "- DMS Replication Instance: $DMS_REPLICATION_INSTANCE_ID"
    echo "- DMS Endpoints: $SOURCE_ENDPOINT_ID, $TARGET_ENDPOINT_ID"
    echo "- Migration Task: $MIGRATION_TASK_ID"
    echo "- Route 53 Hosted Zone: $HOSTED_ZONE_ID"
    echo "- VPC Infrastructure: $VPC_ID"
    echo "- Security Groups: $AURORA_SG_ID, $DMS_SG_ID"
    echo "- All associated subnets and configurations"
    echo "==============================================="
    echo ""
    
    read -p "Are you absolutely sure you want to destroy these resources? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Type 'DESTROY' to confirm final destruction: " FINAL_CONFIRM
    if [[ "$FINAL_CONFIRM" != "DESTROY" ]]; then
        log "Destruction cancelled - confirmation not provided"
        exit 0
    fi
    
    success "Destruction confirmed. Proceeding with cleanup..."
}

# Function to stop and delete DMS replication task
cleanup_dms_task() {
    log "Cleaning up DMS replication task..."
    
    if [ -n "$MIGRATION_TASK_ID" ]; then
        # Get task ARN
        REPLICATION_TASK_ARN=$(aws dms describe-replication-tasks \
            --query "ReplicationTasks[?ReplicationTaskIdentifier=='$MIGRATION_TASK_ID'].ReplicationTaskArn" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$REPLICATION_TASK_ARN" ] && [ "$REPLICATION_TASK_ARN" != "None" ]; then
            # Check task status
            TASK_STATUS=$(aws dms describe-replication-tasks \
                --query "ReplicationTasks[?ReplicationTaskIdentifier=='$MIGRATION_TASK_ID'].Status" \
                --output text 2>/dev/null || echo "")
            
            if [ "$TASK_STATUS" = "running" ] || [ "$TASK_STATUS" = "starting" ]; then
                log "Stopping replication task..."
                aws dms stop-replication-task \
                    --replication-task-arn $REPLICATION_TASK_ARN
                
                log "Waiting for task to stop..."
                aws dms wait replication-task-stopped \
                    --replication-task-arn $REPLICATION_TASK_ARN
            fi
            
            log "Deleting replication task..."
            aws dms delete-replication-task \
                --replication-task-arn $REPLICATION_TASK_ARN
            
            success "DMS replication task deleted"
        else
            log "No DMS replication task found to delete"
        fi
    fi
}

# Function to delete DMS endpoints
cleanup_dms_endpoints() {
    log "Cleaning up DMS endpoints..."
    
    # Delete source endpoint
    if [ -n "$SOURCE_ENDPOINT_ID" ]; then
        SOURCE_ENDPOINT_ARN=$(aws dms describe-endpoints \
            --query "Endpoints[?EndpointIdentifier=='$SOURCE_ENDPOINT_ID'].EndpointArn" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SOURCE_ENDPOINT_ARN" ] && [ "$SOURCE_ENDPOINT_ARN" != "None" ]; then
            aws dms delete-endpoint --endpoint-arn $SOURCE_ENDPOINT_ARN
            log "Source endpoint deleted: $SOURCE_ENDPOINT_ID"
        fi
    fi
    
    # Delete target endpoint
    if [ -n "$TARGET_ENDPOINT_ID" ]; then
        TARGET_ENDPOINT_ARN=$(aws dms describe-endpoints \
            --query "Endpoints[?EndpointIdentifier=='$TARGET_ENDPOINT_ID'].EndpointArn" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$TARGET_ENDPOINT_ARN" ] && [ "$TARGET_ENDPOINT_ARN" != "None" ]; then
            aws dms delete-endpoint --endpoint-arn $TARGET_ENDPOINT_ARN
            log "Target endpoint deleted: $TARGET_ENDPOINT_ID"
        fi
    fi
    
    success "DMS endpoints cleaned up"
}

# Function to delete DMS replication instance
cleanup_dms_instance() {
    log "Cleaning up DMS replication instance..."
    
    if [ -n "$DMS_REPLICATION_INSTANCE_ID" ]; then
        # Check if instance exists
        INSTANCE_EXISTS=$(aws dms describe-replication-instances \
            --query "ReplicationInstances[?ReplicationInstanceIdentifier=='$DMS_REPLICATION_INSTANCE_ID'].ReplicationInstanceIdentifier" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$INSTANCE_EXISTS" ] && [ "$INSTANCE_EXISTS" != "None" ]; then
            log "Deleting DMS replication instance..."
            aws dms delete-replication-instance \
                --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID
            
            log "Waiting for DMS instance deletion to complete..."
            aws dms wait replication-instance-deleted \
                --replication-instance-identifier $DMS_REPLICATION_INSTANCE_ID
            
            success "DMS replication instance deleted"
        else
            log "No DMS replication instance found to delete"
        fi
    fi
}

# Function to delete DMS subnet group
cleanup_dms_subnet_group() {
    log "Cleaning up DMS subnet group..."
    
    # Check if subnet group exists
    SUBNET_GROUP_EXISTS=$(aws dms describe-replication-subnet-groups \
        --query "ReplicationSubnetGroups[?ReplicationSubnetGroupIdentifier=='dms-migration-subnet-group'].ReplicationSubnetGroupIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$SUBNET_GROUP_EXISTS" ] && [ "$SUBNET_GROUP_EXISTS" != "None" ]; then
        aws dms delete-replication-subnet-group \
            --replication-subnet-group-identifier dms-migration-subnet-group
        success "DMS subnet group deleted"
    else
        log "No DMS subnet group found to delete"
    fi
}

# Function to delete Aurora cluster
cleanup_aurora_cluster() {
    log "Cleaning up Aurora database cluster..."
    
    if [ -n "$AURORA_CLUSTER_ID" ]; then
        # Get cluster instances
        CLUSTER_INSTANCES=$(aws rds describe-db-clusters \
            --db-cluster-identifier $AURORA_CLUSTER_ID \
            --query 'DBClusters[0].DBClusterMembers[].DBInstanceIdentifier' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$CLUSTER_INSTANCES" ] && [ "$CLUSTER_INSTANCES" != "None" ]; then
            # Delete instances first
            for instance in $CLUSTER_INSTANCES; do
                log "Deleting Aurora instance: $instance"
                aws rds delete-db-instance \
                    --db-instance-identifier $instance \
                    --skip-final-snapshot
            done
            
            # Wait for instances to be deleted
            for instance in $CLUSTER_INSTANCES; do
                log "Waiting for instance deletion: $instance"
                aws rds wait db-instance-deleted \
                    --db-instance-identifier $instance
            done
            
            log "Deleting Aurora cluster: $AURORA_CLUSTER_ID"
            aws rds delete-db-cluster \
                --db-cluster-identifier $AURORA_CLUSTER_ID \
                --skip-final-snapshot
            
            log "Waiting for cluster deletion to complete..."
            aws rds wait db-cluster-deleted \
                --db-cluster-identifier $AURORA_CLUSTER_ID
            
            success "Aurora cluster deleted"
        else
            log "No Aurora cluster found to delete"
        fi
    fi
}

# Function to delete database subnet group and parameter group
cleanup_aurora_resources() {
    log "Cleaning up Aurora related resources..."
    
    # Delete database subnet group
    SUBNET_GROUP_EXISTS=$(aws rds describe-db-subnet-groups \
        --query "DBSubnetGroups[?DBSubnetGroupName=='aurora-migration-subnet-group'].DBSubnetGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$SUBNET_GROUP_EXISTS" ] && [ "$SUBNET_GROUP_EXISTS" != "None" ]; then
        aws rds delete-db-subnet-group \
            --db-subnet-group-name aurora-migration-subnet-group
        log "Database subnet group deleted"
    fi
    
    # Delete parameter group
    PARAM_GROUP_EXISTS=$(aws rds describe-db-cluster-parameter-groups \
        --query "DBClusterParameterGroups[?DBClusterParameterGroupName=='aurora-migration-cluster-pg'].DBClusterParameterGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$PARAM_GROUP_EXISTS" ] && [ "$PARAM_GROUP_EXISTS" != "None" ]; then
        aws rds delete-db-cluster-parameter-group \
            --db-cluster-parameter-group-name aurora-migration-cluster-pg
        log "Database parameter group deleted"
    fi
    
    success "Aurora resources cleaned up"
}

# Function to delete Route 53 hosted zone
cleanup_route53() {
    log "Cleaning up Route 53 hosted zone..."
    
    if [ -n "$HOSTED_ZONE_ID" ]; then
        # Check if hosted zone exists
        ZONE_EXISTS=$(aws route53 get-hosted-zone \
            --id $HOSTED_ZONE_ID \
            --query 'HostedZone.Id' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ZONE_EXISTS" ] && [ "$ZONE_EXISTS" != "None" ]; then
            # List and delete all records except NS and SOA
            RECORD_SETS=$(aws route53 list-resource-record-sets \
                --hosted-zone-id $HOSTED_ZONE_ID \
                --query 'ResourceRecordSets[?Type != `NS` && Type != `SOA`]' \
                --output json 2>/dev/null || echo "[]")
            
            if [ "$RECORD_SETS" != "[]" ]; then
                # Create change batch to delete records
                echo "$RECORD_SETS" | jq '.[] | {Action: "DELETE", ResourceRecordSet: .}' | jq -s '{Changes: .}' > delete-records.json
                
                aws route53 change-resource-record-sets \
                    --hosted-zone-id $HOSTED_ZONE_ID \
                    --change-batch file://delete-records.json
                
                rm -f delete-records.json
                log "Deleted DNS records from hosted zone"
            fi
            
            # Delete hosted zone
            aws route53 delete-hosted-zone --id $HOSTED_ZONE_ID
            success "Route 53 hosted zone deleted"
        else
            log "No Route 53 hosted zone found to delete"
        fi
    fi
}

# Function to delete VPC infrastructure
cleanup_vpc_infrastructure() {
    log "Cleaning up VPC infrastructure..."
    
    # Delete security groups
    if [ -n "$AURORA_SG_ID" ]; then
        SG_EXISTS=$(aws ec2 describe-security-groups \
            --group-ids $AURORA_SG_ID \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SG_EXISTS" ] && [ "$SG_EXISTS" != "None" ]; then
            aws ec2 delete-security-group --group-id $AURORA_SG_ID
            log "Aurora security group deleted: $AURORA_SG_ID"
        fi
    fi
    
    if [ -n "$DMS_SG_ID" ]; then
        SG_EXISTS=$(aws ec2 describe-security-groups \
            --group-ids $DMS_SG_ID \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SG_EXISTS" ] && [ "$SG_EXISTS" != "None" ]; then
            aws ec2 delete-security-group --group-id $DMS_SG_ID
            log "DMS security group deleted: $DMS_SG_ID"
        fi
    fi
    
    # Delete subnets
    if [ -n "$SUBNET_1_ID" ]; then
        SUBNET_EXISTS=$(aws ec2 describe-subnets \
            --subnet-ids $SUBNET_1_ID \
            --query 'Subnets[0].SubnetId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SUBNET_EXISTS" ] && [ "$SUBNET_EXISTS" != "None" ]; then
            aws ec2 delete-subnet --subnet-id $SUBNET_1_ID
            log "Subnet 1 deleted: $SUBNET_1_ID"
        fi
    fi
    
    if [ -n "$SUBNET_2_ID" ]; then
        SUBNET_EXISTS=$(aws ec2 describe-subnets \
            --subnet-ids $SUBNET_2_ID \
            --query 'Subnets[0].SubnetId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SUBNET_EXISTS" ] && [ "$SUBNET_EXISTS" != "None" ]; then
            aws ec2 delete-subnet --subnet-id $SUBNET_2_ID
            log "Subnet 2 deleted: $SUBNET_2_ID"
        fi
    fi
    
    # Delete VPC
    if [ -n "$VPC_ID" ]; then
        VPC_EXISTS=$(aws ec2 describe-vpcs \
            --vpc-ids $VPC_ID \
            --query 'Vpcs[0].VpcId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$VPC_EXISTS" ] && [ "$VPC_EXISTS" != "None" ]; then
            aws ec2 delete-vpc --vpc-id $VPC_ID
            log "VPC deleted: $VPC_ID"
        fi
    fi
    
    success "VPC infrastructure cleaned up"
}

# Function to cleanup IAM roles
cleanup_iam_roles() {
    log "Cleaning up IAM roles..."
    
    # Check if DMS VPC role exists and if it's safe to delete
    ROLE_EXISTS=$(aws iam get-role \
        --role-name dms-vpc-role \
        --query 'Role.RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ROLE_EXISTS" ] && [ "$ROLE_EXISTS" != "None" ]; then
        warning "DMS VPC role exists but may be used by other DMS instances"
        read -p "Do you want to delete the dms-vpc-role? This may affect other DMS operations (y/N): " DELETE_ROLE
        
        if [[ $DELETE_ROLE =~ ^[Yy]$ ]]; then
            aws iam detach-role-policy \
                --role-name dms-vpc-role \
                --policy-arn arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole
            
            aws iam delete-role --role-name dms-vpc-role
            log "DMS VPC role deleted"
        else
            log "Keeping DMS VPC role as requested"
        fi
    else
        log "No DMS VPC role found to delete"
    fi
    
    success "IAM roles cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    # List of files to clean up
    local_files=(
        "table-mappings.json"
        "task-settings.json"
        "dns-record-aurora.json"
        "delete-records.json"
        "dms-vpc-trust-policy.json"
    )
    
    for file in "${local_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Deleted local file: $file"
        fi
    done
    
    # Ask about configuration file
    if [ -f "$CONFIG_FILE" ]; then
        read -p "Do you want to delete the deployment configuration file ($CONFIG_FILE)? (y/N): " DELETE_CONFIG
        if [[ $DELETE_CONFIG =~ ^[Yy]$ ]]; then
            rm -f "$CONFIG_FILE"
            log "Deployment configuration file deleted"
        else
            log "Keeping deployment configuration file"
        fi
    fi
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==========================================="
    echo "The following resources have been destroyed:"
    echo "- DMS Replication Task: $MIGRATION_TASK_ID"
    echo "- DMS Replication Instance: $DMS_REPLICATION_INSTANCE_ID"
    echo "- DMS Endpoints: $SOURCE_ENDPOINT_ID, $TARGET_ENDPOINT_ID"
    echo "- Aurora Cluster: $AURORA_CLUSTER_ID"
    echo "- Route 53 Hosted Zone: $HOSTED_ZONE_ID"
    echo "- VPC Infrastructure: $VPC_ID"
    echo "- Security Groups and Subnets"
    echo "- Configuration files"
    echo "==========================================="
    echo ""
    warning "Please verify in AWS Console that all resources have been properly deleted"
    warning "Check your AWS bill to ensure no unexpected charges remain"
    echo ""
    success "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    echo "==============================================="
    echo "AWS Aurora Minimal Downtime Migration - CLEANUP"
    echo "==============================================="
    echo ""
    
    check_prerequisites
    load_configuration
    confirm_destruction
    
    echo "Starting cleanup process..."
    echo ""
    
    # Execute cleanup in proper order (reverse of creation)
    cleanup_dms_task
    cleanup_dms_endpoints
    cleanup_dms_instance
    cleanup_dms_subnet_group
    cleanup_aurora_cluster
    cleanup_aurora_resources
    cleanup_route53
    cleanup_vpc_infrastructure
    cleanup_iam_roles
    cleanup_local_files
    
    display_cleanup_summary
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi