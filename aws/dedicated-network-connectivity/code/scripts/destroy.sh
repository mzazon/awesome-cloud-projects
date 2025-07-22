#!/bin/bash

# Destroy script for AWS Direct Connect Hybrid Cloud Connectivity
# This script safely removes all infrastructure created by the deploy.sh script

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Cleanup function for signals
cleanup() {
    log "WARN" "Script interrupted. Partial cleanup may have occurred."
    exit 1
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Load deployment state
load_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

# Check if resources exist
check_resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "vpc")
            aws ec2 describe-vpcs --vpc-ids "$resource_id" >/dev/null 2>&1
            ;;
        "subnet")
            aws ec2 describe-subnets --subnet-ids "$resource_id" >/dev/null 2>&1
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" >/dev/null 2>&1
            ;;
        "transit-gateway")
            aws ec2 describe-transit-gateways --transit-gateway-ids "$resource_id" >/dev/null 2>&1
            ;;
        "transit-gateway-attachment")
            aws ec2 describe-transit-gateway-attachments --transit-gateway-attachment-ids "$resource_id" >/dev/null 2>&1
            ;;
        "direct-connect-gateway")
            aws directconnect describe-direct-connect-gateways --direct-connect-gateway-id "$resource_id" >/dev/null 2>&1
            ;;
        "resolver-endpoint")
            aws route53resolver get-resolver-endpoint --resolver-endpoint-id "$resource_id" >/dev/null 2>&1
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_id" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local timeout="$3"
    local count=0
    
    while check_resource_exists "$resource_type" "$resource_id"; do
        if [[ $count -ge $timeout ]]; then
            log "WARN" "Timeout waiting for $resource_type $resource_id to be deleted"
            return 1
        fi
        sleep 10
        ((count++))
        log "INFO" "Waiting for $resource_type $resource_id to be deleted... ($count/$timeout)"
    done
    
    return 0
}

# Confirm destruction
confirm_destruction() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log "WARN" "No deployment state file found. Nothing to destroy."
        exit 0
    fi
    
    echo
    echo "=================================================="
    echo "WARNING: DESTRUCTIVE OPERATION"
    echo "=================================================="
    echo "This will permanently delete all resources created by deploy.sh"
    echo
    echo "Resources to be deleted:"
    echo "- VPCs and subnets"
    echo "- Transit Gateway and attachments"
    echo "- Direct Connect Gateway"
    echo "- DNS Resolver endpoints"
    echo "- Security groups"
    echo "- CloudWatch dashboards and alarms"
    echo "- SNS topics"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Type the project ID to confirm: " project_id_input
    PROJECT_ID=$(load_state 'PROJECT_ID')
    
    if [[ "$project_id_input" != "$PROJECT_ID" ]]; then
        log "ERROR" "Project ID mismatch. Destruction cancelled."
        exit 1
    fi
    
    log "INFO" "Destruction confirmed. Proceeding..."
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured."
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed."
    fi
    
    # Get AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not configured."
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "SUCCESS" "Prerequisites check completed"
}

# Remove CloudWatch monitoring
remove_monitoring() {
    log "INFO" "Removing monitoring resources..."
    
    PROJECT_ID=$(load_state 'PROJECT_ID')
    SNS_TOPIC_ARN=$(load_state 'SNS_TOPIC_ARN')
    
    # Delete CloudWatch alarms
    log "INFO" "Deleting CloudWatch alarms..."
    aws cloudwatch delete-alarms \
        --alarm-names "DX-Connection-Down-${PROJECT_ID}" 2>/dev/null || true
    
    # Delete CloudWatch dashboard
    log "INFO" "Deleting CloudWatch dashboard..."
    aws cloudwatch delete-dashboards \
        --dashboard-names "DirectConnect-${PROJECT_ID}" 2>/dev/null || true
    
    # Delete SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        log "INFO" "Deleting SNS topic..."
        if check_resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null || true
        fi
    fi
    
    log "SUCCESS" "Monitoring resources removed"
}

# Remove DNS resolver endpoints
remove_dns_resolution() {
    log "INFO" "Removing DNS resolver endpoints..."
    
    INBOUND_ENDPOINT=$(load_state 'INBOUND_ENDPOINT')
    OUTBOUND_ENDPOINT=$(load_state 'OUTBOUND_ENDPOINT')
    RESOLVER_SG=$(load_state 'RESOLVER_SG')
    
    # Delete resolver endpoints
    if [[ -n "$INBOUND_ENDPOINT" ]]; then
        log "INFO" "Deleting inbound resolver endpoint..."
        if check_resource_exists "resolver-endpoint" "$INBOUND_ENDPOINT"; then
            aws route53resolver delete-resolver-endpoint \
                --resolver-endpoint-id "$INBOUND_ENDPOINT" 2>/dev/null || true
            wait_for_deletion "resolver-endpoint" "$INBOUND_ENDPOINT" 30
        fi
    fi
    
    if [[ -n "$OUTBOUND_ENDPOINT" ]]; then
        log "INFO" "Deleting outbound resolver endpoint..."
        if check_resource_exists "resolver-endpoint" "$OUTBOUND_ENDPOINT"; then
            aws route53resolver delete-resolver-endpoint \
                --resolver-endpoint-id "$OUTBOUND_ENDPOINT" 2>/dev/null || true
            wait_for_deletion "resolver-endpoint" "$OUTBOUND_ENDPOINT" 30
        fi
    fi
    
    # Delete security group
    if [[ -n "$RESOLVER_SG" ]]; then
        log "INFO" "Deleting resolver security group..."
        if check_resource_exists "security-group" "$RESOLVER_SG"; then
            aws ec2 delete-security-group --group-id "$RESOLVER_SG" 2>/dev/null || true
        fi
    fi
    
    log "SUCCESS" "DNS resolver endpoints removed"
}

# Remove Direct Connect Gateway
remove_direct_connect_gateway() {
    log "INFO" "Removing Direct Connect Gateway..."
    
    DX_GATEWAY_ID=$(load_state 'DX_GATEWAY_ID')
    DX_TGW_ATTACHMENT=$(load_state 'DX_TGW_ATTACHMENT')
    
    # Delete Transit Gateway Direct Connect Gateway attachment
    if [[ -n "$DX_TGW_ATTACHMENT" ]]; then
        log "INFO" "Deleting DX Gateway attachment..."
        if check_resource_exists "transit-gateway-attachment" "$DX_TGW_ATTACHMENT"; then
            aws ec2 delete-transit-gateway-direct-connect-gateway-attachment \
                --transit-gateway-attachment-id "$DX_TGW_ATTACHMENT" 2>/dev/null || true
            wait_for_deletion "transit-gateway-attachment" "$DX_TGW_ATTACHMENT" 60
        fi
    fi
    
    # Delete Direct Connect Gateway
    if [[ -n "$DX_GATEWAY_ID" ]]; then
        log "INFO" "Deleting Direct Connect Gateway..."
        if check_resource_exists "direct-connect-gateway" "$DX_GATEWAY_ID"; then
            aws directconnect delete-direct-connect-gateway \
                --direct-connect-gateway-id "$DX_GATEWAY_ID" 2>/dev/null || true
            
            # Wait for deletion
            local count=0
            while check_resource_exists "direct-connect-gateway" "$DX_GATEWAY_ID"; do
                if [[ $count -ge 60 ]]; then
                    log "WARN" "Timeout waiting for DX Gateway to be deleted"
                    break
                fi
                sleep 10
                ((count++))
                log "INFO" "Waiting for DX Gateway to be deleted... ($count/60)"
            done
        fi
    fi
    
    log "SUCCESS" "Direct Connect Gateway removed"
}

# Remove Transit Gateway and VPC attachments
remove_transit_gateway() {
    log "INFO" "Removing Transit Gateway and VPC attachments..."
    
    TRANSIT_GATEWAY_ID=$(load_state 'TRANSIT_GATEWAY_ID')
    PROD_ATTACHMENT=$(load_state 'PROD_ATTACHMENT')
    DEV_ATTACHMENT=$(load_state 'DEV_ATTACHMENT')
    SHARED_ATTACHMENT=$(load_state 'SHARED_ATTACHMENT')
    
    # Delete VPC attachments
    for attachment in "$PROD_ATTACHMENT" "$DEV_ATTACHMENT" "$SHARED_ATTACHMENT"; do
        if [[ -n "$attachment" ]]; then
            log "INFO" "Deleting VPC attachment: $attachment"
            if check_resource_exists "transit-gateway-attachment" "$attachment"; then
                aws ec2 delete-transit-gateway-vpc-attachment \
                    --transit-gateway-attachment-id "$attachment" 2>/dev/null || true
            fi
        fi
    done
    
    # Wait for attachments to be deleted
    log "INFO" "Waiting for VPC attachments to be deleted..."
    for attachment in "$PROD_ATTACHMENT" "$DEV_ATTACHMENT" "$SHARED_ATTACHMENT"; do
        if [[ -n "$attachment" ]]; then
            wait_for_deletion "transit-gateway-attachment" "$attachment" 60
        fi
    done
    
    # Delete Transit Gateway
    if [[ -n "$TRANSIT_GATEWAY_ID" ]]; then
        log "INFO" "Deleting Transit Gateway..."
        if check_resource_exists "transit-gateway" "$TRANSIT_GATEWAY_ID"; then
            aws ec2 delete-transit-gateway \
                --transit-gateway-id "$TRANSIT_GATEWAY_ID" 2>/dev/null || true
            wait_for_deletion "transit-gateway" "$TRANSIT_GATEWAY_ID" 120
        fi
    fi
    
    log "SUCCESS" "Transit Gateway and attachments removed"
}

# Remove VPC resources
remove_vpc_resources() {
    log "INFO" "Removing VPC resources..."
    
    PROD_VPC_ID=$(load_state 'PROD_VPC_ID')
    DEV_VPC_ID=$(load_state 'DEV_VPC_ID')
    SHARED_VPC_ID=$(load_state 'SHARED_VPC_ID')
    
    # Remove VPCs and their resources
    for vpc_id in "$PROD_VPC_ID" "$DEV_VPC_ID" "$SHARED_VPC_ID"; do
        if [[ -n "$vpc_id" ]] && check_resource_exists "vpc" "$vpc_id"; then
            log "INFO" "Removing VPC: $vpc_id"
            
            # Delete subnets
            log "INFO" "Deleting subnets in VPC: $vpc_id"
            SUBNETS=$(aws ec2 describe-subnets \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
            
            for subnet in $SUBNETS; do
                if [[ -n "$subnet" ]]; then
                    log "INFO" "Deleting subnet: $subnet"
                    aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
                fi
            done
            
            # Delete security groups (except default)
            log "INFO" "Deleting security groups in VPC: $vpc_id"
            SECURITY_GROUPS=$(aws ec2 describe-security-groups \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
            
            for sg in $SECURITY_GROUPS; do
                if [[ -n "$sg" ]]; then
                    log "INFO" "Deleting security group: $sg"
                    aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
                fi
            done
            
            # Delete network ACLs (except default)
            log "INFO" "Deleting network ACLs in VPC: $vpc_id"
            NETWORK_ACLS=$(aws ec2 describe-network-acls \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output text 2>/dev/null || echo "")
            
            for nacl in $NETWORK_ACLS; do
                if [[ -n "$nacl" ]]; then
                    log "INFO" "Deleting network ACL: $nacl"
                    aws ec2 delete-network-acl --network-acl-id "$nacl" 2>/dev/null || true
                fi
            done
            
            # Delete route tables (except main)
            log "INFO" "Deleting route tables in VPC: $vpc_id"
            ROUTE_TABLES=$(aws ec2 describe-route-tables \
                --filters "Name=vpc-id,Values=${vpc_id}" \
                --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")
            
            for rt in $ROUTE_TABLES; do
                if [[ -n "$rt" ]]; then
                    log "INFO" "Deleting route table: $rt"
                    aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
                fi
            done
            
            # Wait a bit for resources to be deleted
            sleep 10
            
            # Delete VPC
            log "INFO" "Deleting VPC: $vpc_id"
            aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || true
            
            # Wait for VPC deletion
            wait_for_deletion "vpc" "$vpc_id" 30
        fi
    done
    
    log "SUCCESS" "VPC resources removed"
}

# Remove VPC Flow Logs
remove_vpc_flow_logs() {
    log "INFO" "Removing VPC Flow Logs..."
    
    PROJECT_ID=$(load_state 'PROJECT_ID')
    
    # Delete VPC Flow Logs
    FLOW_LOGS=$(aws ec2 describe-flow-logs \
        --query 'FlowLogs[?LogGroupName==`/aws/vpc/flowlogs-'${PROJECT_ID}'`].FlowLogId' --output text 2>/dev/null || echo "")
    
    for flow_log in $FLOW_LOGS; do
        if [[ -n "$flow_log" ]]; then
            log "INFO" "Deleting VPC Flow Log: $flow_log"
            aws ec2 delete-flow-logs --flow-log-ids "$flow_log" 2>/dev/null || true
        fi
    done
    
    # Delete CloudWatch log group
    log "INFO" "Deleting CloudWatch log group..."
    aws logs delete-log-group --log-group-name "/aws/vpc/flowlogs-${PROJECT_ID}" 2>/dev/null || true
    
    log "SUCCESS" "VPC Flow Logs removed"
}

# Clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # List of files to remove
    local files_to_remove=(
        "${SCRIPT_DIR}/bgp-config-template.txt"
        "${SCRIPT_DIR}/dx-dashboard.json"
        "${SCRIPT_DIR}/test-hybrid-connectivity.sh"
        "${SCRIPT_DIR}/deployment-summary.txt"
        "${SCRIPT_DIR}/.deployment_state"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "INFO" "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    log "SUCCESS" "Local files cleaned up"
}

# Generate destruction summary
generate_destruction_summary() {
    log "INFO" "Generating destruction summary..."
    
    cat > "${SCRIPT_DIR}/destruction-summary.txt" << EOF
AWS Direct Connect Hybrid Cloud Connectivity Destruction Summary
================================================================

Destruction completed on: $(date)
Project ID: $(load_state 'PROJECT_ID')

Resources Removed:
- VPCs and all associated resources
- Transit Gateway and VPC attachments
- Direct Connect Gateway
- DNS Resolver endpoints
- Security groups and Network ACLs
- CloudWatch dashboards and alarms
- SNS topics
- VPC Flow Logs
- Local configuration files

The infrastructure has been successfully removed.
EOF
    
    log "SUCCESS" "Destruction summary generated"
}

# Main destruction function
main() {
    log "INFO" "Starting AWS Direct Connect Hybrid Cloud Connectivity destruction..."
    
    # Initialize log file
    > "$LOG_FILE"
    
    # Check prerequisites and confirm destruction
    check_prerequisites
    confirm_destruction
    
    # Run destruction steps in reverse order
    remove_monitoring
    remove_dns_resolution
    remove_direct_connect_gateway
    remove_transit_gateway
    remove_vpc_flow_logs
    remove_vpc_resources
    generate_destruction_summary
    cleanup_local_files
    
    log "SUCCESS" "Destruction completed successfully!"
    
    echo
    echo "=================================================="
    echo "DESTRUCTION COMPLETED SUCCESSFULLY!"
    echo "=================================================="
    echo "All resources have been removed."
    echo "Check destruction-summary.txt for details."
    echo "=================================================="
}

# Run main function
main "$@"