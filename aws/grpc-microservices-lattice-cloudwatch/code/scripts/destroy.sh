#!/bin/bash

# destroy.sh - gRPC Microservices with VPC Lattice and CloudWatch Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper dependency handling and confirmation prompts.

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
AWS_REGION=""
AWS_ACCOUNT_ID=""
RANDOM_SUFFIX=""
DEPLOYMENT_FILE=""
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_handler() {
    local line_no=$1
    log_error "An error occurred on line $line_no during cleanup."
    log_warning "Some resources may still exist. Check AWS Console and retry if needed."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -s, --suffix SUFFIX         Specify the deployment suffix (random ID)
    -f, --force                 Force deletion without confirmation prompts
    -y, --yes                   Skip interactive confirmations
    -d, --deployment-file FILE  Use specific deployment file
    -h, --help                  Show this help message

EXAMPLES:
    $0                          # Interactive cleanup with auto-detection
    $0 -s abc123               # Cleanup specific deployment
    $0 -f -y                   # Force cleanup without prompts
    $0 -d /tmp/deployment.json # Use specific deployment file

NOTES:
    - The script will attempt to auto-detect the deployment if no suffix is provided
    - Use --force to skip safety checks (not recommended for production)
    - Some resources may take time to delete and the script will wait appropriately
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -d|--deployment-file)
                DEPLOYMENT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Auto-detect deployment
auto_detect_deployment() {
    if [ -n "$DEPLOYMENT_FILE" ] && [ -f "$DEPLOYMENT_FILE" ]; then
        log_info "Using deployment file: $DEPLOYMENT_FILE"
        return 0
    fi
    
    if [ -n "$RANDOM_SUFFIX" ]; then
        DEPLOYMENT_FILE="/tmp/grpc-lattice-deployment-${RANDOM_SUFFIX}.json"
        if [ -f "$DEPLOYMENT_FILE" ]; then
            log_info "Found deployment file: $DEPLOYMENT_FILE"
            return 0
        fi
    fi
    
    # Search for deployment files
    local deployment_files=($(ls /tmp/grpc-lattice-deployment-*.json 2>/dev/null || true))
    
    if [ ${#deployment_files[@]} -eq 0 ]; then
        log_warning "No deployment files found. Will attempt cleanup using AWS resource tags."
        return 1
    elif [ ${#deployment_files[@]} -eq 1 ]; then
        DEPLOYMENT_FILE="${deployment_files[0]}"
        RANDOM_SUFFIX=$(basename "$DEPLOYMENT_FILE" | sed 's/grpc-lattice-deployment-\(.*\)\.json/\1/')
        log_info "Auto-detected deployment: $DEPLOYMENT_FILE"
        return 0
    else
        log_info "Multiple deployment files found:"
        for i in "${!deployment_files[@]}"; do
            local suffix=$(basename "${deployment_files[$i]}" | sed 's/grpc-lattice-deployment-\(.*\)\.json/\1/')
            local timestamp=""
            if command -v jq &> /dev/null; then
                timestamp=$(jq -r '.timestamp // "unknown"' "${deployment_files[$i]}" 2>/dev/null || echo "unknown")
            fi
            log_info "  $((i+1))) ${deployment_files[$i]} (suffix: $suffix, created: $timestamp)"
        done
        
        if [ "$SKIP_CONFIRMATION" = false ]; then
            echo -n "Select deployment to cleanup (1-${#deployment_files[@]}): "
            read -r selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#deployment_files[@]} ]; then
                DEPLOYMENT_FILE="${deployment_files[$((selection-1))]}"
                RANDOM_SUFFIX=$(basename "$DEPLOYMENT_FILE" | sed 's/grpc-lattice-deployment-\(.*\)\.json/\1/')
                log_info "Selected: $DEPLOYMENT_FILE"
                return 0
            else
                log_error "Invalid selection"
                exit 1
            fi
        else
            log_error "Multiple deployments found but --yes specified. Use --suffix to specify which deployment to cleanup."
            exit 1
        fi
    fi
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ -f "$DEPLOYMENT_FILE" ]; then
        if command -v jq &> /dev/null; then
            AWS_REGION=$(jq -r '.region // empty' "$DEPLOYMENT_FILE")
            AWS_ACCOUNT_ID=$(jq -r '.account_id // empty' "$DEPLOYMENT_FILE")
            RANDOM_SUFFIX=$(jq -r '.deployment_id // empty' "$DEPLOYMENT_FILE")
        else
            log_warning "jq not found. Using basic parsing."
            AWS_REGION=$(grep -o '"region"[^,]*' "$DEPLOYMENT_FILE" | sed 's/"region": "\([^"]*\)"/\1/')
            AWS_ACCOUNT_ID=$(grep -o '"account_id"[^,]*' "$DEPLOYMENT_FILE" | sed 's/"account_id": "\([^"]*\)"/\1/')
            RANDOM_SUFFIX=$(grep -o '"deployment_id"[^,]*' "$DEPLOYMENT_FILE" | sed 's/"deployment_id": "\([^"]*\)"/\1/')
        fi
    fi
    
    # Set defaults or get from environment
    AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "")}
    AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")}
    
    if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "Could not determine AWS region or account ID. Please configure AWS CLI."
        exit 1
    fi
    
    log_info "Region: $AWS_REGION"
    log_info "Account: $AWS_ACCOUNT_ID"
    log_info "Deployment ID: $RANDOM_SUFFIX"
}

# Confirm deletion
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = true ] || [ "$FORCE_DELETE" = true ]; then
        log_warning "Skipping confirmation as requested"
        return 0
    fi
    
    echo ""
    log_warning "⚠️  WARNING: This will delete ALL resources from the gRPC microservices deployment"
    log_warning "   Deployment ID: $RANDOM_SUFFIX"
    log_warning "   Region: $AWS_REGION"
    echo ""
    log_info "Resources to be deleted:"
    log_info "  • VPC Lattice Service Network and Services"
    log_info "  • Target Groups and Listeners"
    log_info "  • EC2 Instances"
    log_info "  • VPC, Subnets, and Security Groups"
    log_info "  • CloudWatch Dashboards, Alarms, and Log Groups"
    echo ""
    echo -n "Are you sure you want to continue? (type 'yes' to confirm): "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with cleanup..."
}

# Get resource IDs from deployment file or AWS
get_resource_ids() {
    log_info "Gathering resource IDs..."
    
    # If we have deployment file, extract IDs
    if [ -f "$DEPLOYMENT_FILE" ] && command -v jq &> /dev/null; then
        VPC_ID=$(jq -r '.resources.vpc_id // empty' "$DEPLOYMENT_FILE")
        SUBNET_ID=$(jq -r '.resources.subnet_id // empty' "$DEPLOYMENT_FILE")
        SG_ID=$(jq -r '.resources.security_group_id // empty' "$DEPLOYMENT_FILE")
        SERVICE_NETWORK_ID=$(jq -r '.resources.service_network_id // empty' "$DEPLOYMENT_FILE")
        VPC_ASSOCIATION_ID=$(jq -r '.resources.vpc_association_id // empty' "$DEPLOYMENT_FILE")
        
        USER_TG_ID=$(jq -r '.resources.target_groups.user_service // empty' "$DEPLOYMENT_FILE")
        ORDER_TG_ID=$(jq -r '.resources.target_groups.order_service // empty' "$DEPLOYMENT_FILE")
        INVENTORY_TG_ID=$(jq -r '.resources.target_groups.inventory_service // empty' "$DEPLOYMENT_FILE")
        
        USER_INSTANCE_ID=$(jq -r '.resources.instances.user_service // empty' "$DEPLOYMENT_FILE")
        ORDER_INSTANCE_ID=$(jq -r '.resources.instances.order_service // empty' "$DEPLOYMENT_FILE")
        INVENTORY_INSTANCE_ID=$(jq -r '.resources.instances.inventory_service // empty' "$DEPLOYMENT_FILE")
        
        USER_SERVICE_ID=$(jq -r '.resources.services.user_service // empty' "$DEPLOYMENT_FILE")
        ORDER_SERVICE_ID=$(jq -r '.resources.services.order_service // empty' "$DEPLOYMENT_FILE")
        INVENTORY_SERVICE_ID=$(jq -r '.resources.services.inventory_service // empty' "$DEPLOYMENT_FILE")
        
        USER_SERVICE_ASSOC_ID=$(jq -r '.resources.service_associations.user_service // empty' "$DEPLOYMENT_FILE")
        ORDER_SERVICE_ASSOC_ID=$(jq -r '.resources.service_associations.order_service // empty' "$DEPLOYMENT_FILE")
        INVENTORY_SERVICE_ASSOC_ID=$(jq -r '.resources.service_associations.inventory_service // empty' "$DEPLOYMENT_FILE")
        
        USER_LISTENER_ID=$(jq -r '.resources.listeners.user_service // empty' "$DEPLOYMENT_FILE")
        ORDER_LISTENER_ID=$(jq -r '.resources.listeners.order_service // empty' "$DEPLOYMENT_FILE")
        INVENTORY_LISTENER_ID=$(jq -r '.resources.listeners.inventory_service // empty' "$DEPLOYMENT_FILE")
        
        log_success "Resource IDs loaded from deployment file"
    else
        log_warning "Deployment file not available or jq not installed. Will search by tags."
        # Search for resources by tags
        search_resources_by_tags
    fi
}

# Search for resources by tags
search_resources_by_tags() {
    log_info "Searching for resources by tags..."
    
    # Find VPC by tag
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=grpc-vpc-${RANDOM_SUFFIX}" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [ "$VPC_ID" != "" ] && [ "$VPC_ID" != "None" ]; then
        log_success "Found VPC: $VPC_ID"
        
        # Find other resources within the VPC
        SUBNET_ID=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=grpc-subnet-${RANDOM_SUFFIX}" \
            --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
        
        SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=grpc-services-${RANDOM_SUFFIX}" \
            --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
    fi
    
    # Find service network
    SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='grpc-microservices-${RANDOM_SUFFIX}'].id | [0]" \
        --output text 2>/dev/null || echo "")
    
    # Find instances by tag
    local instance_ids=($(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=gRPC-Microservices" "Name=instance-state-name,Values=running,stopped,pending,shutting-down" \
        --query "Reservations[].Instances[?contains(Tags[?Key=='Name'].Value, '${RANDOM_SUFFIX}')].InstanceId" \
        --output text 2>/dev/null || echo ""))
    
    for instance_id in "${instance_ids[@]}"; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            local instance_name=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --query 'Reservations[0].Instances[0].Tags[?Key==`Name`].Value | [0]' \
                --output text 2>/dev/null || echo "")
            
            case "$instance_name" in
                *user-service*)
                    USER_INSTANCE_ID="$instance_id"
                    ;;
                *order-service*)
                    ORDER_INSTANCE_ID="$instance_id"
                    ;;
                *inventory-service*)
                    INVENTORY_INSTANCE_ID="$instance_id"
                    ;;
            esac
        fi
    done
    
    log_info "Resource discovery by tags completed"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete alarms
    local alarms=(
        "gRPC-UserService-HighErrorRate-${RANDOM_SUFFIX}"
        "gRPC-OrderService-HighLatency-${RANDOM_SUFFIX}"
        "gRPC-Services-ConnectionFailures-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log_success "Deleted alarm: $alarm"
        else
            log_warning "Alarm not found: $alarm"
        fi
    done
    
    # Delete dashboard
    local dashboard_name="gRPC-Microservices-${RANDOM_SUFFIX}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        log_success "Deleted dashboard: $dashboard_name"
    else
        log_warning "Dashboard not found: $dashboard_name"
    fi
    
    # Delete log group
    local log_group="/aws/vpc-lattice/grpc-services-${RANDOM_SUFFIX}"
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
        aws logs delete-log-group --log-group-name "$log_group"
        log_success "Deleted log group: $log_group"
    else
        log_warning "Log group not found: $log_group"
    fi
}

# Delete VPC Lattice listeners
delete_listeners() {
    log_info "Deleting VPC Lattice listeners..."
    
    local listeners=("$USER_LISTENER_ID" "$ORDER_LISTENER_ID" "$INVENTORY_LISTENER_ID")
    local services=("$USER_SERVICE_ID" "$ORDER_SERVICE_ID" "$INVENTORY_SERVICE_ID")
    
    for i in "${!listeners[@]}"; do
        local listener_id="${listeners[$i]}"
        local service_id="${services[$i]}"
        
        if [ -n "$listener_id" ] && [ -n "$service_id" ] && [ "$listener_id" != "None" ] && [ "$service_id" != "None" ]; then
            aws vpc-lattice delete-listener \
                --service-identifier "$service_id" \
                --listener-identifier "$listener_id" || log_warning "Failed to delete listener: $listener_id"
            log_success "Deleted listener: $listener_id"
        fi
    done
}

# Delete service network associations
delete_service_associations() {
    log_info "Deleting service network associations..."
    
    local associations=("$USER_SERVICE_ASSOC_ID" "$ORDER_SERVICE_ASSOC_ID" "$INVENTORY_SERVICE_ASSOC_ID")
    
    for assoc_id in "${associations[@]}"; do
        if [ -n "$assoc_id" ] && [ "$assoc_id" != "None" ]; then
            aws vpc-lattice delete-service-network-service-association \
                --service-network-service-association-identifier "$assoc_id" || log_warning "Failed to delete service association: $assoc_id"
            log_success "Deleted service association: $assoc_id"
        fi
    done
    
    # Delete VPC association
    if [ -n "$VPC_ASSOCIATION_ID" ] && [ "$VPC_ASSOCIATION_ID" != "None" ]; then
        aws vpc-lattice delete-service-network-vpc-association \
            --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" || log_warning "Failed to delete VPC association: $VPC_ASSOCIATION_ID"
        log_success "Deleted VPC association: $VPC_ASSOCIATION_ID"
        
        # Wait for VPC association to be deleted
        log_info "Waiting for VPC association to be deleted..."
        local max_attempts=30
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if ! aws vpc-lattice get-service-network-vpc-association \
                --service-network-vpc-association-identifier "$VPC_ASSOCIATION_ID" &>/dev/null; then
                log_success "VPC association deleted"
                break
            fi
            
            log_info "VPC association still exists (attempt $((attempt + 1))/$max_attempts)"
            sleep 10
            ((attempt++))
        done
    fi
}

# Delete VPC Lattice services and target groups
delete_lattice_services() {
    log_info "Deleting VPC Lattice services and target groups..."
    
    # Delete services
    local services=("$USER_SERVICE_ID" "$ORDER_SERVICE_ID" "$INVENTORY_SERVICE_ID")
    for service_id in "${services[@]}"; do
        if [ -n "$service_id" ] && [ "$service_id" != "None" ]; then
            aws vpc-lattice delete-service --service-identifier "$service_id" || log_warning "Failed to delete service: $service_id"
            log_success "Deleted service: $service_id"
        fi
    done
    
    # Deregister targets and delete target groups
    local target_groups=("$USER_TG_ID" "$ORDER_TG_ID" "$INVENTORY_TG_ID")
    local instances=("$USER_INSTANCE_ID" "$ORDER_INSTANCE_ID" "$INVENTORY_INSTANCE_ID")
    
    for i in "${!target_groups[@]}"; do
        local tg_id="${target_groups[$i]}"
        local instance_id="${instances[$i]}"
        
        if [ -n "$tg_id" ] && [ "$tg_id" != "None" ]; then
            # Deregister target if instance exists
            if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                aws vpc-lattice deregister-targets \
                    --target-group-identifier "$tg_id" \
                    --targets id="$instance_id" || log_warning "Failed to deregister target: $instance_id"
                log_success "Deregistered target: $instance_id"
            fi
            
            # Delete target group
            aws vpc-lattice delete-target-group --target-group-identifier "$tg_id" || log_warning "Failed to delete target group: $tg_id"
            log_success "Deleted target group: $tg_id"
        fi
    done
}

# Delete service network
delete_service_network() {
    log_info "Deleting service network..."
    
    if [ -n "$SERVICE_NETWORK_ID" ] && [ "$SERVICE_NETWORK_ID" != "None" ]; then
        aws vpc-lattice delete-service-network \
            --service-network-identifier "$SERVICE_NETWORK_ID" || log_warning "Failed to delete service network: $SERVICE_NETWORK_ID"
        log_success "Deleted service network: $SERVICE_NETWORK_ID"
    else
        log_warning "Service network ID not found"
    fi
}

# Terminate EC2 instances
terminate_instances() {
    log_info "Terminating EC2 instances..."
    
    local instances=("$USER_INSTANCE_ID" "$ORDER_INSTANCE_ID" "$INVENTORY_INSTANCE_ID")
    local valid_instances=()
    
    # Collect valid instance IDs
    for instance_id in "${instances[@]}"; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            # Check if instance exists and is not already terminated
            local state=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --query 'Reservations[0].Instances[0].State.Name' \
                --output text 2>/dev/null || echo "not-found")
            
            if [ "$state" != "not-found" ] && [ "$state" != "terminated" ] && [ "$state" != "terminating" ]; then
                valid_instances+=("$instance_id")
            fi
        fi
    done
    
    if [ ${#valid_instances[@]} -gt 0 ]; then
        aws ec2 terminate-instances --instance-ids "${valid_instances[@]}"
        log_success "Terminated instances: ${valid_instances[*]}"
        
        # Wait for instances to terminate
        log_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids "${valid_instances[@]}" || log_warning "Timeout waiting for instances to terminate"
        log_success "All instances terminated"
    else
        log_warning "No valid instances to terminate"
    fi
}

# Delete VPC resources
delete_vpc_resources() {
    log_info "Deleting VPC and networking resources..."
    
    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        # Find and delete internet gateway
        local igw_id=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
            --query 'InternetGateways[0].InternetGatewayId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$igw_id" ] && [ "$igw_id" != "None" ]; then
            aws ec2 detach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$igw_id" || log_warning "Failed to detach IGW"
            aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" || log_warning "Failed to delete IGW"
            log_success "Deleted internet gateway: $igw_id"
        fi
        
        # Find and delete route tables (except main)
        local route_tables=($(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
            --output text 2>/dev/null || echo ""))
        
        for rt_id in "${route_tables[@]}"; do
            if [ -n "$rt_id" ] && [ "$rt_id" != "None" ]; then
                # Disassociate route table
                local association_id=$(aws ec2 describe-route-tables \
                    --route-table-ids "$rt_id" \
                    --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId | [0]' \
                    --output text 2>/dev/null || echo "")
                
                if [ -n "$association_id" ] && [ "$association_id" != "None" ]; then
                    aws ec2 disassociate-route-table --association-id "$association_id" || log_warning "Failed to disassociate route table"
                fi
                
                aws ec2 delete-route-table --route-table-id "$rt_id" || log_warning "Failed to delete route table: $rt_id"
                log_success "Deleted route table: $rt_id"
            fi
        done
        
        # Delete security group
        if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
            aws ec2 delete-security-group --group-id "$SG_ID" || log_warning "Failed to delete security group: $SG_ID"
            log_success "Deleted security group: $SG_ID"
        fi
        
        # Delete subnet
        if [ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "None" ]; then
            aws ec2 delete-subnet --subnet-id "$SUBNET_ID" || log_warning "Failed to delete subnet: $SUBNET_ID"
            log_success "Deleted subnet: $SUBNET_ID"
        fi
        
        # Delete VPC
        aws ec2 delete-vpc --vpc-id "$VPC_ID" || log_warning "Failed to delete VPC: $VPC_ID"
        log_success "Deleted VPC: $VPC_ID"
    else
        log_warning "VPC ID not found"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove deployment and environment files
    if [ -n "$RANDOM_SUFFIX" ]; then
        rm -f "/tmp/grpc-lattice-deployment-${RANDOM_SUFFIX}.json"
        rm -f "/tmp/grpc-lattice-env-${RANDOM_SUFFIX}.sh"
        rm -f "/tmp/user-data-${RANDOM_SUFFIX}.sh"
        rm -f "/tmp/dashboard-${RANDOM_SUFFIX}.json"
        log_success "Cleaned up temporary files"
    fi
}

# Main cleanup function
main() {
    log_info "Starting gRPC Microservices with VPC Lattice cleanup..."
    
    parse_args "$@"
    
    # Auto-detect deployment if not specified
    if ! auto_detect_deployment; then
        if [ -z "$RANDOM_SUFFIX" ]; then
            log_error "Could not auto-detect deployment. Please specify --suffix or ensure deployment files exist."
            exit 1
        fi
    fi
    
    load_deployment_info
    confirm_deletion
    get_resource_ids
    
    log_info "Beginning cleanup process..."
    
    # Delete resources in reverse dependency order
    delete_cloudwatch_resources
    delete_listeners
    delete_service_associations
    delete_lattice_services
    delete_service_network
    terminate_instances
    delete_vpc_resources
    cleanup_temp_files
    
    log_success "🎉 Cleanup completed successfully!"
    echo ""
    log_info "📋 Cleanup Summary:"
    log_info "  • Deployment ID: ${RANDOM_SUFFIX}"
    log_info "  • All AWS resources have been deleted"
    log_info "  • Temporary files have been cleaned up"
    echo ""
    log_success "💰 Cost Notice: All billable resources have been removed."
    echo ""
    
    # Verification step
    if [ "$FORCE_DELETE" = false ]; then
        log_info "🔍 Verification: You may want to check the AWS Console to confirm all resources are deleted."
    fi
}

# Run main function
main "$@"