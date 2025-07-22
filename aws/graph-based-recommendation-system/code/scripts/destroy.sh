#!/bin/bash

# Destroy script for Amazon Neptune Graph Database and Recommendation Engine
# Recipe: Graph-Based Recommendation Engine

set -e

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Amazon Neptune cluster and all associated resources.

Options:
    -h, --help          Show this help message
    -f, --force         Skip confirmation prompts
    -k, --keep-data     Keep S3 bucket and sample data
    --dry-run           Show what would be destroyed without deleting resources
    --deployment-file   Path to deployment info file (default: neptune-deployment-info.json)

Examples:
    $0                          # Interactive cleanup with confirmations
    $0 --force                  # Force cleanup without prompts
    $0 --dry-run                # Preview what would be destroyed
    $0 --keep-data              # Keep S3 bucket and sample data

Warning: This will permanently delete all Neptune resources and data!

EOF
}

# Default values
FORCE=false
KEEP_DATA=false
DRY_RUN=false
DEPLOYMENT_FILE="neptune-deployment-info.json"

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
        -k|--keep-data)
            KEEP_DATA=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --deployment-file)
            DEPLOYMENT_FILE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ ! -f "$DEPLOYMENT_FILE" ]]; then
        warning "Deployment file not found: $DEPLOYMENT_FILE"
        log "Attempting to discover resources automatically..."
        discover_resources
        return
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        error "jq is required to parse deployment file. Please install jq."
    fi
    
    # Parse deployment file
    export AWS_REGION=$(jq -r '.aws_region // empty' "$DEPLOYMENT_FILE")
    export NEPTUNE_CLUSTER_ID=$(jq -r '.neptune_cluster_id // empty' "$DEPLOYMENT_FILE")
    export VPC_ID=$(jq -r '.vpc_id // empty' "$DEPLOYMENT_FILE")
    export NEPTUNE_SG_ID=$(jq -r '.security_group_id // empty' "$DEPLOYMENT_FILE")
    export EC2_INSTANCE_ID=$(jq -r '.ec2_instance_id // empty' "$DEPLOYMENT_FILE")
    export EC2_KEY_PAIR_NAME=$(jq -r '.ec2_key_pair // empty' "$DEPLOYMENT_FILE")
    export S3_BUCKET_NAME=$(jq -r '.s3_bucket // empty' "$DEPLOYMENT_FILE")
    export SUBNET_GROUP_NAME=$(jq -r '.subnet_group // empty' "$DEPLOYMENT_FILE")
    
    # Set AWS region if available
    if [[ -n "$AWS_REGION" ]]; then
        aws configure set region "$AWS_REGION"
    fi
    
    success "Deployment information loaded from $DEPLOYMENT_FILE"
}

# Discover resources if deployment file is missing
discover_resources() {
    log "Discovering Neptune resources..."
    
    # Get current AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please configure AWS CLI or provide deployment file."
    fi
    
    # Find Neptune clusters with our naming pattern
    CLUSTERS=$(aws neptune describe-db-clusters \
        --query 'DBClusters[?starts_with(DBClusterIdentifier, `neptune-recommendations-`)].DBClusterIdentifier' \
        --output text)
    
    if [[ -z "$CLUSTERS" ]]; then
        error "No Neptune clusters found matching pattern 'neptune-recommendations-*'"
    fi
    
    # Use the first cluster found
    export NEPTUNE_CLUSTER_ID=$(echo $CLUSTERS | awk '{print $1}')
    
    # Find associated VPC
    export VPC_ID=$(aws neptune describe-db-clusters \
        --db-cluster-identifier "$NEPTUNE_CLUSTER_ID" \
        --query 'DBClusters[0].DBSubnetGroup' --output text | \
        xargs aws neptune describe-db-subnet-groups \
        --db-subnet-group-name --query 'DBSubnetGroups[0].VpcId' --output text 2>/dev/null || echo "")
    
    # Find EC2 instances with neptune-client tag
    export EC2_INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=neptune-client" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "")
    
    warning "Using discovered resources. Some resources might be missed."
    log "Found Neptune cluster: $NEPTUNE_CLUSTER_ID"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "======================================"
    echo "⚠️  DESTRUCTION CONFIRMATION"
    echo "======================================"
    echo ""
    echo "This will permanently destroy the following resources:"
    echo "  • Neptune Cluster: ${NEPTUNE_CLUSTER_ID:-Unknown}"
    echo "  • Neptune Instances: Primary + Replicas"
    echo "  • EC2 Instance: ${EC2_INSTANCE_ID:-Unknown}"
    echo "  • VPC and all networking components"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME:-Unknown} (unless --keep-data)"
    echo "  • Security groups, subnets, route tables"
    echo ""
    echo "💰 This will stop all hourly charges for these resources."
    echo ""
    warning "This action cannot be undone!"
    echo ""
    read -p "Type 'DELETE' to confirm destruction: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    echo ""
    log "Proceeding with destruction..."
}

# Dry run summary
dry_run_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
        echo ""
        echo "Would delete the following resources:"
        echo "  • Neptune Cluster: ${NEPTUNE_CLUSTER_ID:-Unknown}"
        echo "  • Neptune Instances: All instances in cluster"
        echo "  • EC2 Instance: ${EC2_INSTANCE_ID:-Unknown}"
        echo "  • VPC: ${VPC_ID:-Unknown}"
        echo "  • Security Groups and Networking"
        if [[ "$KEEP_DATA" != "true" ]]; then
            echo "  • S3 Bucket: ${S3_BUCKET_NAME:-Unknown}"
        fi
        echo ""
        echo "Run without --dry-run to actually delete these resources."
        exit 0
    fi
}

# Delete Neptune instances
delete_neptune_instances() {
    if [[ -z "$NEPTUNE_CLUSTER_ID" ]]; then
        warning "Neptune cluster ID not found, skipping instance deletion"
        return
    fi
    
    log "Deleting Neptune instances..."
    
    # Get all instances in the cluster
    INSTANCES=$(aws neptune describe-db-instances \
        --query "DBInstances[?DBClusterIdentifier=='$NEPTUNE_CLUSTER_ID'].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$INSTANCES" ]]; then
        warning "No Neptune instances found for cluster $NEPTUNE_CLUSTER_ID"
        return
    fi
    
    # Delete all instances
    for instance in $INSTANCES; do
        log "Deleting Neptune instance: $instance"
        aws neptune delete-db-instance \
            --db-instance-identifier "$instance" \
            --skip-final-snapshot \
            2>/dev/null || warning "Failed to delete instance $instance (may already be deleted)"
    done
    
    # Wait for all instances to be deleted
    for instance in $INSTANCES; do
        log "Waiting for instance deletion: $instance"
        aws neptune wait db-instance-deleted \
            --db-instance-identifier "$instance" \
            2>/dev/null || warning "Failed to wait for instance $instance deletion"
    done
    
    success "Neptune instances deleted"
}

# Delete Neptune cluster
delete_neptune_cluster() {
    if [[ -z "$NEPTUNE_CLUSTER_ID" ]]; then
        warning "Neptune cluster ID not found, skipping cluster deletion"
        return
    fi
    
    log "Deleting Neptune cluster: $NEPTUNE_CLUSTER_ID"
    
    aws neptune delete-db-cluster \
        --db-cluster-identifier "$NEPTUNE_CLUSTER_ID" \
        --skip-final-snapshot \
        2>/dev/null || warning "Failed to delete cluster (may already be deleted)"
    
    # Wait for cluster deletion
    log "Waiting for Neptune cluster deletion..."
    aws neptune wait db-cluster-deleted \
        --db-cluster-identifier "$NEPTUNE_CLUSTER_ID" \
        2>/dev/null || warning "Failed to wait for cluster deletion"
    
    success "Neptune cluster deleted"
}

# Delete Neptune subnet group
delete_neptune_subnet_group() {
    if [[ -z "$SUBNET_GROUP_NAME" ]]; then
        # Try to find subnet group by pattern
        SUBNET_GROUP_NAME=$(aws neptune describe-db-subnet-groups \
            --query 'DBSubnetGroups[?starts_with(DBSubnetGroupName, `neptune-subnet-group-`)].DBSubnetGroupName' \
            --output text 2>/dev/null | head -1)
    fi
    
    if [[ -z "$SUBNET_GROUP_NAME" ]]; then
        warning "Neptune subnet group not found, skipping"
        return
    fi
    
    log "Deleting Neptune subnet group: $SUBNET_GROUP_NAME"
    
    aws neptune delete-db-subnet-group \
        --db-subnet-group-name "$SUBNET_GROUP_NAME" \
        2>/dev/null || warning "Failed to delete subnet group (may already be deleted)"
    
    success "Neptune subnet group deleted"
}

# Terminate EC2 instance
terminate_ec2_instance() {
    if [[ -z "$EC2_INSTANCE_ID" ]]; then
        warning "EC2 instance ID not found, skipping EC2 termination"
        return
    fi
    
    log "Terminating EC2 instance: $EC2_INSTANCE_ID"
    
    aws ec2 terminate-instances \
        --instance-ids "$EC2_INSTANCE_ID" \
        2>/dev/null || warning "Failed to terminate EC2 instance (may already be terminated)"
    
    # Wait for termination
    log "Waiting for EC2 instance termination..."
    aws ec2 wait instance-terminated \
        --instance-ids "$EC2_INSTANCE_ID" \
        2>/dev/null || warning "Failed to wait for EC2 termination"
    
    success "EC2 instance terminated"
}

# Delete EC2 key pair
delete_ec2_key_pair() {
    if [[ -z "$EC2_KEY_PAIR_NAME" ]]; then
        warning "EC2 key pair name not found, skipping key pair deletion"
        return
    fi
    
    log "Deleting EC2 key pair: $EC2_KEY_PAIR_NAME"
    
    aws ec2 delete-key-pair \
        --key-name "$EC2_KEY_PAIR_NAME" \
        2>/dev/null || warning "Failed to delete key pair (may already be deleted)"
    
    # Remove local PEM file
    if [[ -f "${EC2_KEY_PAIR_NAME}.pem" ]]; then
        rm -f "${EC2_KEY_PAIR_NAME}.pem"
        log "Deleted local key file: ${EC2_KEY_PAIR_NAME}.pem"
    fi
    
    success "EC2 key pair deleted"
}

# Delete VPC and networking components
delete_networking() {
    if [[ -z "$VPC_ID" ]]; then
        warning "VPC ID not found, skipping networking cleanup"
        return
    fi
    
    log "Deleting networking components for VPC: $VPC_ID"
    
    # Delete security groups (except default)
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    for sg in $SECURITY_GROUPS; do
        log "Deleting security group: $sg"
        aws ec2 delete-security-group \
            --group-id "$sg" \
            2>/dev/null || warning "Failed to delete security group $sg"
    done
    
    # Delete subnets
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[].SubnetId' \
        --output text 2>/dev/null || echo "")
    
    for subnet in $SUBNETS; do
        log "Deleting subnet: $subnet"
        aws ec2 delete-subnet \
            --subnet-id "$subnet" \
            2>/dev/null || warning "Failed to delete subnet $subnet"
    done
    
    # Delete route tables (except main)
    ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
        --output text 2>/dev/null || echo "")
    
    for rt in $ROUTE_TABLES; do
        log "Deleting route table: $rt"
        aws ec2 delete-route-table \
            --route-table-id "$rt" \
            2>/dev/null || warning "Failed to delete route table $rt"
    done
    
    # Delete internet gateway
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$IGW_ID" && "$IGW_ID" != "None" ]]; then
        log "Detaching and deleting internet gateway: $IGW_ID"
        aws ec2 detach-internet-gateway \
            --internet-gateway-id "$IGW_ID" \
            --vpc-id "$VPC_ID" \
            2>/dev/null || warning "Failed to detach internet gateway"
        
        aws ec2 delete-internet-gateway \
            --internet-gateway-id "$IGW_ID" \
            2>/dev/null || warning "Failed to delete internet gateway"
    fi
    
    # Delete VPC
    log "Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc \
        --vpc-id "$VPC_ID" \
        2>/dev/null || warning "Failed to delete VPC"
    
    success "Networking components deleted"
}

# Delete S3 bucket
delete_s3_bucket() {
    if [[ "$KEEP_DATA" == "true" ]]; then
        warning "Keeping S3 bucket and data as requested"
        return
    fi
    
    if [[ -z "$S3_BUCKET_NAME" ]]; then
        warning "S3 bucket name not found, skipping S3 cleanup"
        return
    fi
    
    log "Deleting S3 bucket: $S3_BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$S3_BUCKET_NAME" &>/dev/null; then
        warning "S3 bucket does not exist: $S3_BUCKET_NAME"
        return
    fi
    
    # Delete all objects in bucket
    aws s3 rm "s3://$S3_BUCKET_NAME" --recursive \
        2>/dev/null || warning "Failed to delete S3 objects"
    
    # Delete bucket
    aws s3 rb "s3://$S3_BUCKET_NAME" \
        2>/dev/null || warning "Failed to delete S3 bucket"
    
    success "S3 bucket deleted"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove sample data files
    rm -f sample-*.csv load-data.groovy user-data.sh
    
    # Remove deployment info if not keeping data
    if [[ "$KEEP_DATA" != "true" && -f "$DEPLOYMENT_FILE" ]]; then
        rm -f "$DEPLOYMENT_FILE"
        log "Removed deployment file: $DEPLOYMENT_FILE"
    fi
    
    success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues=0
    
    # Check Neptune cluster
    if [[ -n "$NEPTUNE_CLUSTER_ID" ]]; then
        if aws neptune describe-db-clusters --db-cluster-identifier "$NEPTUNE_CLUSTER_ID" &>/dev/null; then
            warning "Neptune cluster still exists: $NEPTUNE_CLUSTER_ID"
            ((issues++))
        fi
    fi
    
    # Check EC2 instance
    if [[ -n "$EC2_INSTANCE_ID" ]]; then
        STATUS=$(aws ec2 describe-instances \
            --instance-ids "$EC2_INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "terminated")
        
        if [[ "$STATUS" != "terminated" ]]; then
            warning "EC2 instance not terminated: $EC2_INSTANCE_ID (status: $STATUS)"
            ((issues++))
        fi
    fi
    
    # Check VPC
    if [[ -n "$VPC_ID" ]]; then
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" &>/dev/null; then
            warning "VPC still exists: $VPC_ID"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "All resources successfully cleaned up"
    else
        warning "$issues issue(s) found during cleanup verification"
    fi
}

# Print cleanup summary
print_summary() {
    echo ""
    echo "======================================"
    echo "🧹 Neptune Cleanup Complete!"
    echo "======================================"
    echo ""
    echo "✅ Destroyed Resources:"
    echo "  • Neptune Cluster: ${NEPTUNE_CLUSTER_ID:-N/A}"
    echo "  • Neptune Instances: Primary + Replicas"
    echo "  • EC2 Instance: ${EC2_INSTANCE_ID:-N/A}"
    echo "  • VPC and Networking: ${VPC_ID:-N/A}"
    if [[ "$KEEP_DATA" != "true" ]]; then
        echo "  • S3 Bucket: ${S3_BUCKET_NAME:-N/A}"
    else
        echo "  • S3 Bucket: Preserved (--keep-data)"
    fi
    echo ""
    echo "💰 Cost Impact:"
    echo "  • Stopped all hourly charges"
    echo "  • No more Neptune cluster costs ($12-25/hour)"
    echo "  • No more EC2 instance costs ($0.10/hour)"
    echo ""
    if [[ "$KEEP_DATA" == "true" && -n "$S3_BUCKET_NAME" ]]; then
        echo "📦 Preserved Data:"
        echo "  • S3 Bucket: $S3_BUCKET_NAME"
        echo "  • Sample data files available for future use"
        echo ""
    fi
    echo "🎉 All resources have been cleaned up successfully!"
}

# Error handling
handle_errors() {
    if [[ $? -ne 0 ]]; then
        error "Cleanup encountered errors. Some resources may still exist."
    fi
}

# Main cleanup function
main() {
    echo "🧹 Starting Neptune Resource Cleanup"
    echo "====================================="
    
    # Set error trap
    trap handle_errors ERR
    
    # Load deployment information
    load_deployment_info
    
    # Show what would be destroyed
    dry_run_summary
    
    # Get user confirmation
    confirm_destruction
    
    log "Starting resource destruction..."
    
    # Delete resources in reverse order of creation
    delete_neptune_instances
    delete_neptune_cluster
    delete_neptune_subnet_group
    terminate_ec2_instance
    delete_ec2_key_pair
    delete_networking
    delete_s3_bucket
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Print summary
    print_summary
}

# Run main function
main "$@"