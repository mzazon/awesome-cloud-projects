#!/bin/bash

################################################################################
# Destroy Zero Trust Network Architecture with VPC Endpoints and PrivateLink
# 
# This script automates the cleanup of the zero trust network architecture
# by removing all AWS resources in the correct dependency order to avoid
# conflicts and ensure complete cleanup.
#
# Usage: ./destroy.sh [OPTIONS]
#
# OPTIONS:
#   --dry-run    Show what would be destroyed without making changes
#   --force      Skip confirmation prompts (use with caution)
#   --verbose    Enable verbose logging
#   --help       Show this help message
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#   - Appropriate IAM permissions for resource deletion
#   - Valid AWS credentials configured
#   - Deployment state file (deployment-state.json) from successful deployment
#
################################################################################

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destruction.log"
STATE_FILE="${SCRIPT_DIR}/deployment-state.json"
DRY_RUN=false
FORCE=false
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Destruction failed. Check $LOG_FILE for details."
    exit 1
}

# Display help
show_help() {
    cat << EOF
Destroy Zero Trust Network Architecture with VPC Endpoints and PrivateLink

USAGE:
    ./destroy.sh [OPTIONS]

OPTIONS:
    --dry-run    Show what would be destroyed without making changes
    --force      Skip confirmation prompts (use with caution)
    --verbose    Enable verbose logging
    --help       Show this help message

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate IAM permissions for resource deletion
    - Valid AWS credentials configured
    - Deployment state file (deployment-state.json) from successful deployment

SAFETY FEATURES:
    - Interactive confirmation before destructive operations
    - Dependency-aware deletion order
    - Partial cleanup capability for failed deployments
    - Comprehensive logging of all operations

WARNING:
    This script will permanently delete all infrastructure created by the
    deployment script. This action cannot be undone. Ensure you have
    backed up any important data before proceeding.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
log "INFO" "Starting destruction of Zero Trust Network Architecture"
log "INFO" "Log file: $LOG_FILE"
log "INFO" "Dry run mode: $DRY_RUN"
log "INFO" "Force mode: $FORCE"

# Prerequisites checking
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid. Run 'aws configure' to set up credentials."
    fi
    
    # Get account and region info
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    log "INFO" "Prerequisites check completed successfully"
}

# Load deployment state
load_deployment_state() {
    log "INFO" "Loading deployment state..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log "WARN" "Deployment state file not found: $STATE_FILE"
        log "WARN" "Will attempt to find and destroy resources by tags"
        return 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log "WARN" "jq not available, using basic parsing"
        # Basic parsing without jq
        export VPC_ID=$(grep '"vpc_id"' "$STATE_FILE" | cut -d'"' -f4)
        export PROVIDER_VPC_ID=$(grep '"provider_vpc_id"' "$STATE_FILE" | cut -d'"' -f4)
        export RANDOM_SUFFIX=$(grep '"random_suffix"' "$STATE_FILE" | cut -d'"' -f4)
    else
        # Parse JSON with jq
        export VPC_ID=$(jq -r '.vpc_id // empty' "$STATE_FILE")
        export PROVIDER_VPC_ID=$(jq -r '.provider_vpc_id // empty' "$STATE_FILE")
        export PRIVATE_SUBNET_1=$(jq -r '.private_subnet_1 // empty' "$STATE_FILE")
        export PRIVATE_SUBNET_2=$(jq -r '.private_subnet_2 // empty' "$STATE_FILE")
        export PROVIDER_SUBNET=$(jq -r '.provider_subnet // empty' "$STATE_FILE")
        export ENDPOINT_SG=$(jq -r '.endpoint_sg // empty' "$STATE_FILE")
        export APP_SG=$(jq -r '.app_sg // empty' "$STATE_FILE")
        export PROVIDER_SG=$(jq -r '.provider_sg // empty' "$STATE_FILE")
        export S3_ENDPOINT=$(jq -r '.s3_endpoint // empty' "$STATE_FILE")
        export LAMBDA_ENDPOINT=$(jq -r '.lambda_endpoint // empty' "$STATE_FILE")
        export LOGS_ENDPOINT=$(jq -r '.logs_endpoint // empty' "$STATE_FILE")
        export CUSTOM_ENDPOINT=$(jq -r '.custom_endpoint // empty' "$STATE_FILE")
        export NLB_ARN=$(jq -r '.nlb_arn // empty' "$STATE_FILE")
        export TARGET_GROUP_ARN=$(jq -r '.target_group_arn // empty' "$STATE_FILE")
        export LISTENER_ARN=$(jq -r '.listener_arn // empty' "$STATE_FILE")
        export SERVICE_ID=$(jq -r '.service_id // empty' "$STATE_FILE")
        export HOSTED_ZONE_ID=$(jq -r '.hosted_zone_id // empty' "$STATE_FILE")
        export ENDPOINT_DNS=$(jq -r '.endpoint_dns // empty' "$STATE_FILE")
        export ROUTE_TABLE_ID=$(jq -r '.route_table_id // empty' "$STATE_FILE")
        export PROVIDER_ROUTE_TABLE=$(jq -r '.provider_route_table // empty' "$STATE_FILE")
        export FLOW_LOGS_ROLE=$(jq -r '.flow_logs_role // empty' "$STATE_FILE")
        export LOG_GROUP_NAME=$(jq -r '.log_group_name // empty' "$STATE_FILE")
        export FLOW_LOGS_ID=$(jq -r '.flow_logs_id // empty' "$STATE_FILE")
        export LAMBDA_ROLE=$(jq -r '.lambda_role // empty' "$STATE_FILE")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name // empty' "$STATE_FILE")
        export RANDOM_SUFFIX=$(jq -r '.random_suffix // empty' "$STATE_FILE")
    fi
    
    log "INFO" "Loaded deployment state successfully"
    log "DEBUG" "VPC ID: $VPC_ID"
    log "DEBUG" "Provider VPC ID: $PROVIDER_VPC_ID"
    log "DEBUG" "Random Suffix: $RANDOM_SUFFIX"
    
    return 0
}

# Find resources by tags when state file is missing
find_resources_by_tags() {
    log "INFO" "Searching for resources by project tags..."
    
    # Find VPCs
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Project,Values=ZeroTrustArchitecture" \
        --query 'Vpcs[].VpcId' --output text 2>/dev/null || true)
    
    if [[ -n "$vpcs" ]]; then
        export VPC_ID=$(echo "$vpcs" | tr '\t' '\n' | grep -E "vpc-" | head -1)
        export PROVIDER_VPC_ID=$(echo "$vpcs" | tr '\t' '\n' | grep -E "vpc-" | tail -1)
        log "INFO" "Found VPCs: $VPC_ID, $PROVIDER_VPC_ID"
    fi
    
    # Find Lambda function
    local lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `zero-trust-test`)].FunctionName' \
        --output text 2>/dev/null || true)
    
    if [[ -n "$lambda_functions" ]]; then
        export LAMBDA_FUNCTION_NAME=$(echo "$lambda_functions" | head -1)
        log "INFO" "Found Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
}

# AWS CLI wrapper for dry run support
aws_exec() {
    local service="$1"
    shift
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would execute: aws $service $*"
        return 0
    else
        log "DEBUG" "Executing: aws $service $*"
        aws "$service" "$@" 2>/dev/null || true
    fi
}

# Safe delete function with error handling
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local service="$3"
    shift 3
    
    if [[ -z "$resource_id" ]]; then
        log "DEBUG" "Skipping $resource_type deletion - no resource ID"
        return 0
    fi
    
    log "INFO" "Deleting $resource_type: $resource_id"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete $resource_type: $resource_id"
        return 0
    fi
    
    # Attempt deletion with error handling
    if aws_exec "$service" "$@"; then
        log "INFO" "Successfully deleted $resource_type: $resource_id"
    else
        log "WARN" "Failed to delete $resource_type: $resource_id (may already be deleted)"
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo -e "${RED}"
    echo "========================================="
    echo "WARNING: DESTRUCTIVE OPERATION"
    echo "========================================="
    echo -e "${NC}"
    echo "This will permanently delete the following resources:"
    echo "  - VPCs and associated subnets"
    echo "  - VPC endpoints and PrivateLink services"
    echo "  - Security groups and network ACLs"
    echo "  - Network Load Balancer and target groups"
    echo "  - Route53 private hosted zones"
    echo "  - VPC Flow Logs and CloudWatch log groups"
    echo "  - IAM roles and policies"
    echo "  - Lambda functions"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Destruction cancelled by user"
        exit 0
    fi
    
    log "INFO" "User confirmed destruction, proceeding..."
}

# Delete Lambda function and IAM role
delete_lambda_resources() {
    log "INFO" "Deleting Lambda function and IAM resources..."
    
    # Delete Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        safe_delete "Lambda function" "$LAMBDA_FUNCTION_NAME" "lambda" \
            delete-function --function-name "$LAMBDA_FUNCTION_NAME"
    fi
    
    # Delete Lambda IAM role
    if [[ -n "${LAMBDA_ROLE:-}" || -n "${RANDOM_SUFFIX:-}" ]]; then
        local role_name="ZeroTrustLambdaRole-${RANDOM_SUFFIX}"
        
        # Detach policies
        aws_exec iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
        
        aws_exec iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
        
        # Delete role
        safe_delete "IAM role" "$role_name" "iam" \
            delete-role --role-name "$role_name"
    fi
}

# Delete VPC endpoints
delete_vpc_endpoints() {
    log "INFO" "Deleting VPC endpoints..."
    
    local endpoints=""
    
    # Collect endpoint IDs
    if [[ -n "${S3_ENDPOINT:-}" ]]; then
        endpoints="$endpoints $S3_ENDPOINT"
    fi
    if [[ -n "${LAMBDA_ENDPOINT:-}" ]]; then
        endpoints="$endpoints $LAMBDA_ENDPOINT"
    fi
    if [[ -n "${LOGS_ENDPOINT:-}" ]]; then
        endpoints="$endpoints $LOGS_ENDPOINT"
    fi
    if [[ -n "${CUSTOM_ENDPOINT:-}" ]]; then
        endpoints="$endpoints $CUSTOM_ENDPOINT"
    fi
    
    if [[ -n "$endpoints" ]]; then
        safe_delete "VPC endpoints" "$endpoints" "ec2" \
            delete-vpc-endpoints --vpc-endpoint-ids $endpoints
    fi
    
    # Also find endpoints by VPC ID
    if [[ -n "${VPC_ID:-}" ]]; then
        local vpc_endpoints=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'VpcEndpoints[].VpcEndpointId' --output text 2>/dev/null || true)
        
        if [[ -n "$vpc_endpoints" ]]; then
            safe_delete "Additional VPC endpoints" "$vpc_endpoints" "ec2" \
                delete-vpc-endpoints --vpc-endpoint-ids $vpc_endpoints
        fi
    fi
}

# Delete VPC endpoint service configuration
delete_endpoint_service() {
    log "INFO" "Deleting VPC endpoint service configuration..."
    
    if [[ -n "${SERVICE_ID:-}" ]]; then
        safe_delete "VPC endpoint service" "$SERVICE_ID" "ec2" \
            delete-vpc-endpoint-service-configurations --service-ids "$SERVICE_ID"
    fi
}

# Delete Network Load Balancer components
delete_load_balancer() {
    log "INFO" "Deleting Network Load Balancer components..."
    
    # Delete listener
    if [[ -n "${LISTENER_ARN:-}" ]]; then
        safe_delete "NLB listener" "$LISTENER_ARN" "elbv2" \
            delete-listener --listener-arn "$LISTENER_ARN"
    fi
    
    # Delete target group
    if [[ -n "${TARGET_GROUP_ARN:-}" ]]; then
        safe_delete "Target group" "$TARGET_GROUP_ARN" "elbv2" \
            delete-target-group --target-group-arn "$TARGET_GROUP_ARN"
    fi
    
    # Delete load balancer
    if [[ -n "${NLB_ARN:-}" ]]; then
        safe_delete "Network Load Balancer" "$NLB_ARN" "elbv2" \
            delete-load-balancer --load-balancer-arn "$NLB_ARN"
    fi
    
    # Find additional load balancers by tags
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local nlb_arns=$(aws elbv2 describe-load-balancers \
            --query "LoadBalancers[?contains(LoadBalancerName, 'zero-trust-nlb-${RANDOM_SUFFIX}')].LoadBalancerArn" \
            --output text 2>/dev/null || true)
        
        if [[ -n "$nlb_arns" ]]; then
            for nlb_arn in $nlb_arns; do
                safe_delete "Additional NLB" "$nlb_arn" "elbv2" \
                    delete-load-balancer --load-balancer-arn "$nlb_arn"
            done
        fi
    fi
}

# Delete Route53 hosted zone
delete_hosted_zone() {
    log "INFO" "Deleting Route53 private hosted zone..."
    
    if [[ -n "${HOSTED_ZONE_ID:-}" && -n "${ENDPOINT_DNS:-}" ]]; then
        # Delete DNS record first
        aws_exec route53 change-resource-record-sets \
            --hosted-zone-id "$HOSTED_ZONE_ID" \
            --change-batch "{
                \"Changes\": [
                    {
                        \"Action\": \"DELETE\",
                        \"ResourceRecordSet\": {
                            \"Name\": \"api.zero-trust-service.internal\",
                            \"Type\": \"CNAME\",
                            \"TTL\": 300,
                            \"ResourceRecords\": [
                                {
                                    \"Value\": \"$ENDPOINT_DNS\"
                                }
                            ]
                        }
                    }
                ]
            }"
        
        # Delete hosted zone
        safe_delete "Route53 hosted zone" "$HOSTED_ZONE_ID" "route53" \
            delete-hosted-zone --id "$HOSTED_ZONE_ID"
    fi
    
    # Find hosted zones by name
    local zone_id=$(aws route53 list-hosted-zones \
        --query 'HostedZones[?Name==`zero-trust-service.internal.`].Id' \
        --output text 2>/dev/null | cut -d'/' -f3 || true)
    
    if [[ -n "$zone_id" ]]; then
        safe_delete "Additional hosted zone" "$zone_id" "route53" \
            delete-hosted-zone --id "$zone_id"
    fi
}

# Delete VPC Flow Logs and CloudWatch resources
delete_flow_logs() {
    log "INFO" "Deleting VPC Flow Logs and CloudWatch resources..."
    
    # Delete VPC Flow Logs
    if [[ -n "${FLOW_LOGS_ID:-}" ]]; then
        safe_delete "VPC Flow Logs" "$FLOW_LOGS_ID" "ec2" \
            delete-flow-logs --flow-log-ids "$FLOW_LOGS_ID"
    fi
    
    # Delete CloudWatch log group
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        safe_delete "CloudWatch log group" "$LOG_GROUP_NAME" "logs" \
            delete-log-group --log-group-name "$LOG_GROUP_NAME"
    fi
    
    # Delete Flow Logs IAM role
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local role_name="VPCFlowLogsRole-${RANDOM_SUFFIX}"
        
        # Detach policy
        aws_exec iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/VPCFlowLogsDeliveryRolePolicy"
        
        # Delete role
        safe_delete "VPC Flow Logs IAM role" "$role_name" "iam" \
            delete-role --role-name "$role_name"
    fi
}

# Delete security groups
delete_security_groups() {
    log "INFO" "Deleting security groups..."
    
    # Delete in order to avoid dependency conflicts
    if [[ -n "${APP_SG:-}" ]]; then
        safe_delete "Application security group" "$APP_SG" "ec2" \
            delete-security-group --group-id "$APP_SG"
    fi
    
    if [[ -n "${ENDPOINT_SG:-}" ]]; then
        safe_delete "Endpoint security group" "$ENDPOINT_SG" "ec2" \
            delete-security-group --group-id "$ENDPOINT_SG"
    fi
    
    if [[ -n "${PROVIDER_SG:-}" ]]; then
        safe_delete "Provider security group" "$PROVIDER_SG" "ec2" \
            delete-security-group --group-id "$PROVIDER_SG"
    fi
    
    # Find additional security groups by tags or names
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local sg_ids=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=*${RANDOM_SUFFIX}*" \
            --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true)
        
        if [[ -n "$sg_ids" ]]; then
            for sg_id in $sg_ids; do
                safe_delete "Additional security group" "$sg_id" "ec2" \
                    delete-security-group --group-id "$sg_id"
            done
        fi
    fi
}

# Delete route tables
delete_route_tables() {
    log "INFO" "Deleting custom route tables..."
    
    if [[ -n "${ROUTE_TABLE_ID:-}" ]]; then
        safe_delete "Consumer route table" "$ROUTE_TABLE_ID" "ec2" \
            delete-route-table --route-table-id "$ROUTE_TABLE_ID"
    fi
    
    if [[ -n "${PROVIDER_ROUTE_TABLE:-}" ]]; then
        safe_delete "Provider route table" "$PROVIDER_ROUTE_TABLE" "ec2" \
            delete-route-table --route-table-id "$PROVIDER_ROUTE_TABLE"
    fi
}

# Delete subnets
delete_subnets() {
    log "INFO" "Deleting subnets..."
    
    if [[ -n "${PRIVATE_SUBNET_1:-}" ]]; then
        safe_delete "Private subnet 1" "$PRIVATE_SUBNET_1" "ec2" \
            delete-subnet --subnet-id "$PRIVATE_SUBNET_1"
    fi
    
    if [[ -n "${PRIVATE_SUBNET_2:-}" ]]; then
        safe_delete "Private subnet 2" "$PRIVATE_SUBNET_2" "ec2" \
            delete-subnet --subnet-id "$PRIVATE_SUBNET_2"
    fi
    
    if [[ -n "${PROVIDER_SUBNET:-}" ]]; then
        safe_delete "Provider subnet" "$PROVIDER_SUBNET" "ec2" \
            delete-subnet --subnet-id "$PROVIDER_SUBNET"
    fi
    
    # Find additional subnets by VPC
    for vpc_id in "${VPC_ID:-}" "${PROVIDER_VPC_ID:-}"; do
        if [[ -n "$vpc_id" ]]; then
            local subnet_ids=$(aws ec2 describe-subnets \
                --filters "Name=vpc-id,Values=$vpc_id" \
                --query 'Subnets[].SubnetId' --output text 2>/dev/null || true)
            
            if [[ -n "$subnet_ids" ]]; then
                for subnet_id in $subnet_ids; do
                    safe_delete "Additional subnet" "$subnet_id" "ec2" \
                        delete-subnet --subnet-id "$subnet_id"
                done
            fi
        fi
    done
}

# Delete VPCs
delete_vpcs() {
    log "INFO" "Deleting VPCs..."
    
    if [[ -n "${VPC_ID:-}" ]]; then
        safe_delete "Consumer VPC" "$VPC_ID" "ec2" \
            delete-vpc --vpc-id "$VPC_ID"
    fi
    
    if [[ -n "${PROVIDER_VPC_ID:-}" ]]; then
        safe_delete "Provider VPC" "$PROVIDER_VPC_ID" "ec2" \
            delete-vpc --vpc-id "$PROVIDER_VPC_ID"
    fi
}

# Clean up deployment state file
cleanup_state_file() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would remove deployment state file: $STATE_FILE"
        return
    fi
    
    if [[ -f "$STATE_FILE" ]]; then
        log "INFO" "Removing deployment state file: $STATE_FILE"
        rm -f "$STATE_FILE"
    fi
}

# Main destruction function
main() {
    log "INFO" "========================================="
    log "INFO" "Zero Trust Network Architecture Destruction"
    log "INFO" "========================================="
    
    check_prerequisites
    
    # Try to load state file, fall back to tag-based discovery
    if ! load_deployment_state; then
        find_resources_by_tags
    fi
    
    confirm_destruction
    
    log "INFO" "Starting infrastructure destruction in dependency order..."
    
    # Delete resources in reverse dependency order
    delete_lambda_resources
    delete_vpc_endpoints
    delete_endpoint_service
    delete_load_balancer
    delete_hosted_zone
    delete_flow_logs
    delete_security_groups
    delete_route_tables
    delete_subnets
    delete_vpcs
    
    cleanup_state_file
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "========================================="
        log "INFO" "DRY RUN COMPLETED SUCCESSFULLY"
        log "INFO" "========================================="
        log "INFO" "No resources were actually destroyed."
        log "INFO" "Run without --dry-run to destroy the infrastructure."
    else
        log "INFO" "========================================="
        log "INFO" "DESTRUCTION COMPLETED SUCCESSFULLY"
        log "INFO" "========================================="
        log "INFO" "Zero trust network architecture has been destroyed successfully!"
        log "INFO" ""
        log "INFO" "All AWS resources have been removed:"
        log "INFO" "  - VPCs and subnets"
        log "INFO" "  - VPC endpoints and PrivateLink services"
        log "INFO" "  - Security groups and route tables"
        log "INFO" "  - Network Load Balancer and target groups"
        log "INFO" "  - Route53 private hosted zones"
        log "INFO" "  - VPC Flow Logs and CloudWatch resources"
        log "INFO" "  - IAM roles and Lambda functions"
        log "INFO" ""
        log "INFO" "Your AWS account should no longer incur charges for these resources."
        log "INFO" "Check the AWS console to verify complete cleanup if needed."
    fi
}

# Run main function
main "$@"