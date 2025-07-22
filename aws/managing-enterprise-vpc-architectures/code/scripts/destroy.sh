#!/bin/bash

# Destroy script for Multi-VPC Architectures with Transit Gateway
# This script safely destroys all resources created by the deploy.sh script
# with proper confirmation prompts and error handling

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or you're not authenticated."
        log_error "Please run 'aws configure' first."
        exit 1
    fi
    
    # Check IAM permissions (basic check)
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        log_error "Insufficient IAM permissions for EC2 operations."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load environment variables from deployment
load_deployment_state() {
    log "Loading deployment state..."
    
    # Check if deployment variables file exists
    if [[ -f "/tmp/deployment_vars.env" ]]; then
        source /tmp/deployment_vars.env
        log_success "Loaded deployment variables from /tmp/deployment_vars.env"
    else
        log_warning "Deployment variables file not found. Using interactive mode..."
        prompt_for_resources
    fi
    
    # Set AWS region if not already set
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            log_warning "AWS region not set, defaulting to us-east-1"
        fi
    fi
}

# Interactive prompt for resource IDs if deployment vars not found
prompt_for_resources() {
    log_warning "Entering interactive mode. Please provide resource IDs to delete:"
    
    echo -n "Transit Gateway ID (or 'auto' to discover): "
    read TGW_ID
    
    if [[ "$TGW_ID" == "auto" ]]; then
        discover_resources
    else
        echo -n "Production VPC ID: "
        read PROD_VPC_ID
        echo -n "Development VPC ID: "
        read DEV_VPC_ID
        echo -n "Test VPC ID: "
        read TEST_VPC_ID
        echo -n "Shared Services VPC ID: "
        read SHARED_VPC_ID
        
        # Export the variables
        export TGW_ID PROD_VPC_ID DEV_VPC_ID TEST_VPC_ID SHARED_VPC_ID
    fi
}

# Auto-discover resources based on tags
discover_resources() {
    log "Attempting to discover resources automatically..."
    
    # Try to find Transit Gateway with our naming pattern
    TGW_LIST=$(aws ec2 describe-transit-gateways \
        --filters "Name=state,Values=available" \
        --query 'TransitGateways[?contains(Tags[?Key==`Name`].Value, `enterprise-tgw`)].{Id:TransitGatewayId,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output table)
    
    if [[ -n "$TGW_LIST" ]]; then
        echo "Found Transit Gateways:"
        echo "$TGW_LIST"
        echo -n "Enter Transit Gateway ID to delete: "
        read TGW_ID
        export TGW_ID
        
        # Discover VPCs attached to this Transit Gateway
        discover_attached_vpcs
    else
        log_error "No Transit Gateways found with enterprise-tgw naming pattern"
        exit 1
    fi
}

# Discover VPCs attached to the Transit Gateway
discover_attached_vpcs() {
    log "Discovering VPCs attached to Transit Gateway $TGW_ID..."
    
    # Get all VPC attachments for this Transit Gateway
    ATTACHMENTS=$(aws ec2 describe-transit-gateway-vpc-attachments \
        --filters "Name=transit-gateway-id,Values=$TGW_ID" "Name=state,Values=available" \
        --query 'TransitGatewayVpcAttachments[].[TransitGatewayAttachmentId,VpcId]' \
        --output text)
    
    if [[ -n "$ATTACHMENTS" ]]; then
        log "Found VPC attachments:"
        echo "$ATTACHMENTS"
        
        # Extract VPC IDs (this is a simplified approach)
        VPC_IDS=$(echo "$ATTACHMENTS" | awk '{print $2}')
        log "VPCs found: $VPC_IDS"
        
        # For safety, we'll still prompt for confirmation
        echo "VPCs that will be deleted:"
        for vpc_id in $VPC_IDS; do
            VPC_NAME=$(aws ec2 describe-vpcs \
                --vpc-ids $vpc_id \
                --query 'Vpcs[0].Tags[?Key==`Name`].Value' \
                --output text 2>/dev/null || echo "Unknown")
            echo "  $vpc_id ($VPC_NAME)"
        done
    else
        log_warning "No VPC attachments found for Transit Gateway $TGW_ID"
    fi
}

# Safety confirmation
confirm_destruction() {
    log_warning "==================== DESTRUCTION CONFIRMATION ===================="
    log_warning "This script will DELETE the following resources:"
    log_warning ""
    
    if [[ -n "${TGW_ID:-}" ]]; then
        log_warning "Transit Gateway: $TGW_ID"
    fi
    
    if [[ -n "${PROD_VPC_ID:-}" ]]; then
        log_warning "Production VPC: $PROD_VPC_ID"
    fi
    
    if [[ -n "${DEV_VPC_ID:-}" ]]; then
        log_warning "Development VPC: $DEV_VPC_ID"
    fi
    
    if [[ -n "${TEST_VPC_ID:-}" ]]; then
        log_warning "Test VPC: $TEST_VPC_ID"
    fi
    
    if [[ -n "${SHARED_VPC_ID:-}" ]]; then
        log_warning "Shared Services VPC: $SHARED_VPC_ID"
    fi
    
    log_warning ""
    log_warning "ALL ASSOCIATED RESOURCES WILL BE DELETED INCLUDING:"
    log_warning "- Subnets, Route Tables, Security Groups"
    log_warning "- Transit Gateway Attachments and Route Tables"
    log_warning "- CloudWatch Alarms and Log Groups"
    log_warning ""
    log_warning "THIS ACTION CANNOT BE UNDONE!"
    log_warning "=================================================================="
    
    echo ""
    echo -n "Are you absolutely sure you want to delete these resources? (Type 'DELETE' to confirm): "
    read confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
    sleep 3
}

# Delete security groups
delete_security_groups() {
    log "Deleting security groups..."
    
    # Delete production security group
    if [[ -n "${PROD_SG_ID:-}" ]]; then
        aws ec2 delete-security-group --group-id $PROD_SG_ID 2>/dev/null || log_warning "Failed to delete production security group $PROD_SG_ID"
        log_success "Deleted production security group"
    fi
    
    # Delete development security group
    if [[ -n "${DEV_SG_ID:-}" ]]; then
        aws ec2 delete-security-group --group-id $DEV_SG_ID 2>/dev/null || log_warning "Failed to delete development security group $DEV_SG_ID"
        log_success "Deleted development security group"
    fi
    
    # Find and delete any additional security groups by deployment ID
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        ADDITIONAL_SGS=$(aws ec2 describe-security-groups \
            --filters "Name=tag:DeploymentId,Values=$RANDOM_SUFFIX" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
            --output text 2>/dev/null || echo "")
        
        for sg_id in $ADDITIONAL_SGS; do
            aws ec2 delete-security-group --group-id $sg_id 2>/dev/null || log_warning "Failed to delete security group $sg_id"
            log_success "Deleted additional security group $sg_id"
        done
    fi
}

# Delete VPC attachments
delete_vpc_attachments() {
    log "Deleting VPC attachments..."
    
    if [[ -n "${TGW_ID:-}" ]]; then
        # Get all VPC attachments for this Transit Gateway
        ATTACHMENTS=$(aws ec2 describe-transit-gateway-vpc-attachments \
            --filters "Name=transit-gateway-id,Values=$TGW_ID" \
            --query 'TransitGatewayVpcAttachments[?State!=`deleted`].TransitGatewayAttachmentId' \
            --output text 2>/dev/null || echo "")
        
        for attachment_id in $ATTACHMENTS; do
            log "Deleting VPC attachment $attachment_id..."
            aws ec2 delete-transit-gateway-vpc-attachment \
                --transit-gateway-attachment-id $attachment_id 2>/dev/null || log_warning "Failed to delete attachment $attachment_id"
        done
        
        # Wait for attachments to be deleted
        if [[ -n "$ATTACHMENTS" ]]; then
            log "Waiting for VPC attachments to be deleted..."
            for attachment_id in $ATTACHMENTS; do
                aws ec2 wait transit-gateway-attachment-deleted \
                    --transit-gateway-attachment-ids $attachment_id 2>/dev/null || log_warning "Timeout waiting for attachment $attachment_id deletion"
            done
            log_success "VPC attachments deleted"
        fi
    fi
}

# Delete Transit Gateway route tables
delete_transit_gateway_route_tables() {
    log "Deleting Transit Gateway route tables..."
    
    if [[ -n "${TGW_ID:-}" ]]; then
        # Get all custom route tables for this Transit Gateway
        ROUTE_TABLES=$(aws ec2 describe-transit-gateway-route-tables \
            --filters "Name=transit-gateway-id,Values=$TGW_ID" "Name=default-association-route-table,Values=false" \
            --query 'TransitGatewayRouteTables[].TransitGatewayRouteTableId' \
            --output text 2>/dev/null || echo "")
        
        for rt_id in $ROUTE_TABLES; do
            log "Deleting Transit Gateway route table $rt_id..."
            aws ec2 delete-transit-gateway-route-table \
                --transit-gateway-route-table-id $rt_id 2>/dev/null || log_warning "Failed to delete route table $rt_id"
            log_success "Deleted Transit Gateway route table $rt_id"
        done
    fi
}

# Delete Transit Gateway
delete_transit_gateway() {
    log "Deleting Transit Gateway..."
    
    if [[ -n "${TGW_ID:-}" ]]; then
        aws ec2 delete-transit-gateway \
            --transit-gateway-id $TGW_ID 2>/dev/null || log_warning "Failed to delete Transit Gateway $TGW_ID"
        log_success "Initiated Transit Gateway deletion: $TGW_ID"
        log "Note: Transit Gateway deletion may take several minutes to complete"
    fi
}

# Delete VPCs and associated resources
delete_vpcs() {
    log "Deleting VPCs and associated resources..."
    
    VPC_LIST=""
    if [[ -n "${PROD_VPC_ID:-}" ]]; then VPC_LIST="$VPC_LIST $PROD_VPC_ID"; fi
    if [[ -n "${DEV_VPC_ID:-}" ]]; then VPC_LIST="$VPC_LIST $DEV_VPC_ID"; fi
    if [[ -n "${TEST_VPC_ID:-}" ]]; then VPC_LIST="$VPC_LIST $TEST_VPC_ID"; fi
    if [[ -n "${SHARED_VPC_ID:-}" ]]; then VPC_LIST="$VPC_LIST $SHARED_VPC_ID"; fi
    
    for vpc_id in $VPC_LIST; do
        if [[ -n "$vpc_id" ]]; then
            log "Deleting VPC $vpc_id and its resources..."
            
            # Delete subnets
            SUBNETS=$(aws ec2 describe-subnets \
                --filters "Name=vpc-id,Values=$vpc_id" \
                --query 'Subnets[].SubnetId' \
                --output text 2>/dev/null || echo "")
            
            for subnet_id in $SUBNETS; do
                aws ec2 delete-subnet --subnet-id $subnet_id 2>/dev/null || log_warning "Failed to delete subnet $subnet_id"
            done
            
            # Delete custom route tables (keep main route table)
            ROUTE_TABLES=$(aws ec2 describe-route-tables \
                --filters "Name=vpc-id,Values=$vpc_id" \
                --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
                --output text 2>/dev/null || echo "")
            
            for rt_id in $ROUTE_TABLES; do
                aws ec2 delete-route-table --route-table-id $rt_id 2>/dev/null || log_warning "Failed to delete route table $rt_id"
            done
            
            # Delete internet gateways
            IGWS=$(aws ec2 describe-internet-gateways \
                --filters "Name=attachment.vpc-id,Values=$vpc_id" \
                --query 'InternetGateways[].InternetGatewayId' \
                --output text 2>/dev/null || echo "")
            
            for igw_id in $IGWS; do
                aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id 2>/dev/null || log_warning "Failed to detach IGW $igw_id"
                aws ec2 delete-internet-gateway --internet-gateway-id $igw_id 2>/dev/null || log_warning "Failed to delete IGW $igw_id"
            done
            
            # Delete the VPC
            aws ec2 delete-vpc --vpc-id $vpc_id 2>/dev/null || log_warning "Failed to delete VPC $vpc_id"
            log_success "Deleted VPC $vpc_id"
        fi
    done
}

# Delete CloudWatch resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete CloudWatch alarms
    if [[ -n "${ALARM_NAME:-}" ]]; then
        aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME" 2>/dev/null || log_warning "Failed to delete alarm $ALARM_NAME"
        log_success "Deleted CloudWatch alarm"
    fi
    
    # Delete alarms by deployment ID if available
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        ALARMS=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "TransitGateway-DataProcessing-High-$RANDOM_SUFFIX" \
            --query 'MetricAlarms[].AlarmName' \
            --output text 2>/dev/null || echo "")
        
        for alarm_name in $ALARMS; do
            aws cloudwatch delete-alarms --alarm-names "$alarm_name" 2>/dev/null || log_warning "Failed to delete alarm $alarm_name"
            log_success "Deleted CloudWatch alarm $alarm_name"
        done
    fi
    
    # Delete log groups
    aws logs delete-log-group --log-group-name /aws/transitgateway/flowlogs 2>/dev/null || log_warning "Failed to delete log group"
    aws logs delete-log-group --log-group-name /aws/vpc/flowlogs 2>/dev/null || log_warning "Failed to delete VPC flow logs group"
    log_success "Deleted CloudWatch log groups"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f /tmp/deployment_vars.env 2>/dev/null || true
    rm -f /tmp/deployment_state.json 2>/dev/null || true
    rm -f /tmp/deployment_summary.txt 2>/dev/null || true
    rm -f /tmp/*-vpc-id 2>/dev/null || true
    rm -f /tmp/*-subnet-id 2>/dev/null || true
    rm -f /tmp/*-rt-id 2>/dev/null || true
    rm -f /tmp/*-attachment-id 2>/dev/null || true
    rm -f /tmp/*-sg-id 2>/dev/null || true
    rm -f /tmp/tgw-id 2>/dev/null || true
    rm -f /tmp/dr-tgw-id 2>/dev/null || true
    rm -f /tmp/peering-attachment-id 2>/dev/null || true
    
    log_success "Cleaned up temporary files"
}

# Verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    REMAINING_RESOURCES=0
    
    # Check Transit Gateway
    if [[ -n "${TGW_ID:-}" ]]; then
        TGW_STATE=$(aws ec2 describe-transit-gateways \
            --transit-gateway-ids $TGW_ID \
            --query 'TransitGateways[0].State' \
            --output text 2>/dev/null || echo "deleted")
        
        if [[ "$TGW_STATE" != "deleted" && "$TGW_STATE" != "deleting" ]]; then
            log_warning "Transit Gateway $TGW_ID still exists (state: $TGW_STATE)"
            REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
        fi
    fi
    
    # Check VPCs
    for vpc_id in ${PROD_VPC_ID:-} ${DEV_VPC_ID:-} ${TEST_VPC_ID:-} ${SHARED_VPC_ID:-}; do
        if [[ -n "$vpc_id" ]]; then
            VPC_EXISTS=$(aws ec2 describe-vpcs \
                --vpc-ids $vpc_id \
                --query 'Vpcs[0].VpcId' \
                --output text 2>/dev/null || echo "None")
            
            if [[ "$VPC_EXISTS" != "None" ]]; then
                log_warning "VPC $vpc_id still exists"
                REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
            fi
        fi
    done
    
    if [[ $REMAINING_RESOURCES -eq 0 ]]; then
        log_success "All resources have been successfully deleted"
    else
        log_warning "$REMAINING_RESOURCES resources may still exist. Please check manually."
    fi
}

# Generate destruction summary
generate_destruction_summary() {
    log "Generating destruction summary..."
    
    cat > /tmp/destruction_summary.txt << EOF
=== Multi-VPC Transit Gateway Destruction Summary ===

Destruction completed on: $(date)
AWS Region: ${AWS_REGION}

Resources Deleted:
==================

Transit Gateway: ${TGW_ID:-"Not specified"}
VPCs Deleted:
- Production VPC: ${PROD_VPC_ID:-"Not specified"}
- Development VPC: ${DEV_VPC_ID:-"Not specified"}
- Test VPC: ${TEST_VPC_ID:-"Not specified"}
- Shared Services VPC: ${SHARED_VPC_ID:-"Not specified"}

Additional Resources Deleted:
- All subnets in the VPCs
- Transit Gateway route tables
- VPC attachments
- Security groups
- CloudWatch alarms and log groups
- Route table entries

Notes:
======
- Transit Gateway deletion may take additional time to complete
- Some resources may have deletion protection enabled
- Check AWS Console to verify complete deletion
- Any remaining resources should be manually reviewed

Cleanup Status: Complete

EOF
    
    log_success "Destruction completed!"
    log ""
    log "Summary saved to: /tmp/destruction_summary.txt"
    log ""
    cat /tmp/destruction_summary.txt
}

# Main execution
main() {
    log "Starting Multi-VPC Transit Gateway destruction..."
    log "================================================"
    
    check_prerequisites
    load_deployment_state
    confirm_destruction
    
    log "Beginning resource deletion in reverse order..."
    
    delete_security_groups
    delete_vpc_attachments
    delete_transit_gateway_route_tables
    delete_transit_gateway
    delete_vpcs
    delete_monitoring_resources
    cleanup_temp_files
    verify_deletion
    generate_destruction_summary
    
    log_success "Multi-VPC Transit Gateway destruction completed!"
    log_warning "Please verify in AWS Console that all resources have been deleted."
}

# Handle script arguments
case "${1:-}" in
    --force)
        log_warning "Force mode enabled - skipping confirmation"
        export FORCE_MODE=true
        ;;
    --help)
        echo "Usage: $0 [--force|--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts (use with caution)"
        echo "  --help     Show this help message"
        echo ""
        echo "This script will delete all resources created by deploy.sh"
        exit 0
        ;;
esac

# Run main function
main "$@"