#!/bin/bash

# VMware Cloud on AWS Migration - Cleanup/Destroy Script
# This script removes all infrastructure created for VMware Cloud migration
# Version: 1.0

set -e  # Exit on any error

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
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some operations may be limited."
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    local state_file="$HOME/.aws-vmware-migration/deployment-state.json"
    
    if [[ -f "$state_file" ]]; then
        # Load state from local file
        export AWS_REGION=$(cat "$state_file" | jq -r '.aws_region // empty')
        export AWS_ACCOUNT_ID=$(cat "$state_file" | jq -r '.aws_account_id // empty')
        export VPC_ID=$(cat "$state_file" | jq -r '.vpc_id // empty')
        export SUBNET_ID=$(cat "$state_file" | jq -r '.subnet_id // empty')
        export IGW_ID=$(cat "$state_file" | jq -r '.igw_id // empty')
        export RT_ID=$(cat "$state_file" | jq -r '.rt_id // empty')
        export HCX_SG_ID=$(cat "$state_file" | jq -r '.hcx_sg_id // empty')
        export MGN_SG_ID=$(cat "$state_file" | jq -r '.mgn_sg_id // empty')
        export BACKUP_BUCKET=$(cat "$state_file" | jq -r '.backup_bucket // empty')
        export SNS_TOPIC_ARN=$(cat "$state_file" | jq -r '.sns_topic_arn // empty')
        export DX_GATEWAY_ID=$(cat "$state_file" | jq -r '.dx_gateway_id // empty')
        export SDDC_NAME=$(cat "$state_file" | jq -r '.sddc_name // empty')
        
        success "Deployment state loaded from local file"
    else
        warning "No local deployment state found. Will attempt to discover resources by tags."
        
        # Fallback to discovering resources by tags
        discover_resources_by_tags
    fi
}

# Function to discover resources by tags when state file is not available
discover_resources_by_tags() {
    log "Discovering resources by tags..."
    
    # Set AWS region if not already set
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warning "No AWS region configured, using default: us-east-1"
        fi
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Find VPC by tags
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Project,Values=VMware-Migration" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        warning "No VPC found with VMware-Migration tag"
        export VPC_ID=""
    fi
    
    # Find other resources if VPC exists
    if [[ -n "$VPC_ID" ]]; then
        export SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Project,Values=VMware-Migration" \
            --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
        
        export IGW_ID=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
            --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
        
        export RT_ID=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Project,Values=VMware-Migration" \
            --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "")
        
        export HCX_SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=vmware-hcx-sg" \
            --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
        
        export MGN_SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=vmware-mgn-sg" \
            --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    fi
    
    # Find S3 bucket by naming pattern
    export BACKUP_BUCKET=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `vmware-backup-`)].Name' --output text 2>/dev/null || echo "")
    
    # Find SNS topic
    export SNS_TOPIC_ARN=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `VMware-Migration-Alerts`)].TopicArn' --output text 2>/dev/null || echo "")
    
    # Find Direct Connect gateway
    export DX_GATEWAY_ID=$(aws directconnect describe-direct-connect-gateways \
        --query 'directConnectGateways[?directConnectGatewayName==`vmware-migration-dx-gateway`].directConnectGatewayId' --output text 2>/dev/null || echo "")
    
    success "Resource discovery completed"
}

# Function to confirm destruction
confirm_destruction() {
    log "Resources to be destroyed:"
    echo "========================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "VPC ID: ${VPC_ID:-Not found}"
    echo "Subnet ID: ${SUBNET_ID:-Not found}"
    echo "HCX Security Group ID: ${HCX_SG_ID:-Not found}"
    echo "MGN Security Group ID: ${MGN_SG_ID:-Not found}"
    echo "Backup Bucket: ${BACKUP_BUCKET:-Not found}"
    echo "SNS Topic ARN: ${SNS_TOPIC_ARN:-Not found}"
    echo "Direct Connect Gateway ID: ${DX_GATEWAY_ID:-Not found}"
    echo "========================="
    echo ""
    
    read -p "Are you sure you want to destroy these resources? This action cannot be undone. (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    warning "Proceeding with resource destruction..."
}

# Function to remove CloudWatch and monitoring resources
remove_monitoring_resources() {
    log "Removing CloudWatch and monitoring resources..."
    
    # Delete CloudWatch dashboard
    aws cloudwatch delete-dashboard \
        --dashboard-name "VMware-Migration-Dashboard" 2>/dev/null || warning "Dashboard may not exist"
    
    # Delete CloudWatch alarms
    aws cloudwatch delete-alarms \
        --alarm-names "VMware-SDDC-HostHealth" 2>/dev/null || warning "Alarm may not exist"
    
    # Delete log group
    aws logs delete-log-group \
        --log-group-name "/aws/vmware/migration" 2>/dev/null || warning "Log group may not exist"
    
    # Delete SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null || warning "SNS topic deletion failed"
    fi
    
    success "Monitoring resources removed"
}

# Function to remove cost optimization resources
remove_cost_resources() {
    log "Removing cost optimization resources..."
    
    # Delete budget
    aws budgets delete-budget \
        --account-id "$AWS_ACCOUNT_ID" \
        --budget-name "VMware-Cloud-Budget" 2>/dev/null || warning "Budget may not exist"
    
    # Delete cost anomaly detector
    local detector_arn=$(aws ce get-anomaly-detectors \
        --query 'AnomalyDetectors[?DetectorName==`VMware-Cost-Anomaly-Detector`].AnomalyDetectorArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$detector_arn" && "$detector_arn" != "None" ]]; then
        aws ce delete-anomaly-detector --anomaly-detector-arn "$detector_arn" 2>/dev/null || warning "Cost anomaly detector deletion failed"
    fi
    
    success "Cost optimization resources removed"
}

# Function to remove S3 backup resources
remove_s3_backup() {
    log "Removing S3 backup resources..."
    
    if [[ -n "$BACKUP_BUCKET" ]]; then
        # Delete all objects in bucket
        aws s3 rm "s3://$BACKUP_BUCKET" --recursive 2>/dev/null || warning "Failed to delete S3 objects"
        
        # Delete all object versions (if versioning is enabled)
        aws s3api delete-objects \
            --bucket "$BACKUP_BUCKET" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BACKUP_BUCKET" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || warning "Failed to delete object versions"
        
        # Delete bucket
        aws s3api delete-bucket --bucket "$BACKUP_BUCKET" 2>/dev/null || warning "Failed to delete S3 bucket"
        
        success "S3 backup bucket removed: $BACKUP_BUCKET"
    else
        warning "No backup bucket found to remove"
    fi
}

# Function to remove migration tracking resources
remove_migration_tracking() {
    log "Removing migration tracking resources..."
    
    # Delete DynamoDB table
    aws dynamodb delete-table \
        --table-name VMwareMigrationTracking 2>/dev/null || warning "DynamoDB table may not exist"
    
    # Wait for table deletion
    aws dynamodb wait table-not-exists \
        --table-name VMwareMigrationTracking 2>/dev/null || warning "Table deletion wait failed"
    
    success "Migration tracking resources removed"
}

# Function to remove MGN resources
remove_mgn_resources() {
    log "Removing AWS Application Migration Service resources..."
    
    # Note: MGN service initialization cannot be undone, but we can remove templates
    # Delete replication configuration templates
    local template_ids=$(aws mgn describe-replication-configuration-templates \
        --query 'items[].replicationConfigurationTemplateID' --output text 2>/dev/null || echo "")
    
    if [[ -n "$template_ids" ]]; then
        for template_id in $template_ids; do
            aws mgn delete-replication-configuration-template \
                --replication-configuration-template-id "$template_id" 2>/dev/null || warning "Template deletion failed"
        done
    fi
    
    success "MGN resources removed"
}

# Function to remove Direct Connect resources
remove_direct_connect() {
    log "Removing Direct Connect resources..."
    
    if [[ -n "$DX_GATEWAY_ID" ]]; then
        # Delete Direct Connect gateway
        aws directconnect delete-direct-connect-gateway \
            --direct-connect-gateway-id "$DX_GATEWAY_ID" 2>/dev/null || warning "Direct Connect gateway deletion failed"
        
        success "Direct Connect gateway removed: $DX_GATEWAY_ID"
    else
        warning "No Direct Connect gateway found to remove"
    fi
}

# Function to remove security groups
remove_security_groups() {
    log "Removing security groups..."
    
    # Delete HCX security group
    if [[ -n "$HCX_SG_ID" ]]; then
        aws ec2 delete-security-group --group-id "$HCX_SG_ID" 2>/dev/null || warning "HCX security group deletion failed"
        success "HCX security group removed: $HCX_SG_ID"
    fi
    
    # Delete MGN security group
    if [[ -n "$MGN_SG_ID" ]]; then
        aws ec2 delete-security-group --group-id "$MGN_SG_ID" 2>/dev/null || warning "MGN security group deletion failed"
        success "MGN security group removed: $MGN_SG_ID"
    fi
}

# Function to remove networking resources
remove_networking() {
    log "Removing networking resources..."
    
    if [[ -n "$VPC_ID" ]]; then
        # Disassociate and delete route table
        if [[ -n "$RT_ID" ]]; then
            # Get association ID
            local association_id=$(aws ec2 describe-route-tables \
                --route-table-ids "$RT_ID" \
                --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$association_id" && "$association_id" != "None" ]]; then
                aws ec2 disassociate-route-table --association-id "$association_id" 2>/dev/null || warning "Route table disassociation failed"
            fi
            
            # Delete route table
            aws ec2 delete-route-table --route-table-id "$RT_ID" 2>/dev/null || warning "Route table deletion failed"
        fi
        
        # Detach and delete internet gateway
        if [[ -n "$IGW_ID" ]]; then
            aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" 2>/dev/null || warning "IGW detachment failed"
            aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" 2>/dev/null || warning "IGW deletion failed"
        fi
        
        # Delete subnet
        if [[ -n "$SUBNET_ID" ]]; then
            aws ec2 delete-subnet --subnet-id "$SUBNET_ID" 2>/dev/null || warning "Subnet deletion failed"
        fi
        
        # Delete VPC
        aws ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null || warning "VPC deletion failed"
        
        success "Networking resources removed"
    else
        warning "No VPC found to remove"
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM resources..."
    
    # Detach and delete VMware Cloud on AWS service role
    aws iam detach-role-policy \
        --role-name VMwareCloudOnAWS-ServiceRole \
        --policy-arn arn:aws:iam::aws:policy/VMwareCloudOnAWSServiceRolePolicy 2>/dev/null || warning "VMware policy detachment failed"
    
    aws iam delete-role --role-name VMwareCloudOnAWS-ServiceRole 2>/dev/null || warning "VMware role deletion failed"
    
    # Detach and delete Lambda execution role
    aws iam detach-role-policy \
        --role-name VMware-Lambda-ExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || warning "Lambda policy detachment failed"
    
    aws iam delete-role --role-name VMware-Lambda-ExecutionRole 2>/dev/null || warning "Lambda role deletion failed"
    
    success "IAM resources removed"
}

# Function to remove EventBridge rules
remove_eventbridge_rules() {
    log "Removing EventBridge rules..."
    
    # Remove targets from EventBridge rule
    aws events remove-targets \
        --rule VMware-SDDC-StateChange \
        --ids "1" 2>/dev/null || warning "EventBridge target removal failed"
    
    # Delete EventBridge rule
    aws events delete-rule --name VMware-SDDC-StateChange 2>/dev/null || warning "EventBridge rule deletion failed"
    
    success "EventBridge rules removed"
}

# Function to clean up local state
cleanup_local_state() {
    log "Cleaning up local state..."
    
    # Remove local state directory
    if [[ -d "$HOME/.aws-vmware-migration" ]]; then
        rm -rf "$HOME/.aws-vmware-migration"
        success "Local state directory removed"
    fi
    
    # Remove any temporary files
    rm -f /tmp/vmware-* 2>/dev/null || true
    
    success "Local cleanup completed"
}

# Function to display final summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "==================="
    echo "✅ CloudWatch monitoring resources removed"
    echo "✅ Cost optimization resources removed"
    echo "✅ S3 backup resources removed"
    echo "✅ Migration tracking resources removed"
    echo "✅ MGN resources removed"
    echo "✅ Direct Connect resources removed"
    echo "✅ Security groups removed"
    echo "✅ Networking resources removed"
    echo "✅ IAM resources removed"
    echo "✅ EventBridge rules removed"
    echo "✅ Local state cleaned up"
    echo "==================="
    echo ""
    echo "Important Notes:"
    echo "- SDDC in VMware Cloud Console must be manually deleted"
    echo "- Check VMware Cloud Console for any remaining resources"
    echo "- Verify all AWS costs have stopped accruing"
    echo "- Some resources may take time to fully delete"
    echo ""
    warning "Remember to manually delete the SDDC through VMware Cloud Console!"
}

# Function to handle partial cleanup on error
handle_cleanup_error() {
    error "Cleanup process encountered an error"
    warning "Some resources may not have been deleted"
    echo ""
    echo "Manual cleanup may be required for:"
    echo "- SDDC in VMware Cloud Console"
    echo "- Any remaining AWS resources"
    echo "- Cost monitoring to ensure charges have stopped"
    echo ""
    echo "Check the AWS console for any remaining resources tagged with 'Project:VMware-Migration'"
}

# Main execution
main() {
    log "Starting VMware Cloud on AWS migration cleanup..."
    
    # Set error handler
    trap handle_cleanup_error ERR
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_monitoring_resources
    remove_cost_resources
    remove_s3_backup
    remove_migration_tracking
    remove_mgn_resources
    remove_direct_connect
    remove_security_groups
    remove_networking
    remove_iam_resources
    remove_eventbridge_rules
    cleanup_local_state
    
    success "VMware Cloud on AWS migration cleanup completed successfully!"
    
    display_cleanup_summary
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"