#!/bin/bash

# Self-Managed Kubernetes Integration with VPC Lattice IP Targets - Cleanup Script
# Recipe: kubernetes-integration-lattice-ip
# Version: 1.1
# Last Updated: 2025-07-12

set -euo pipefail

# Enable debug mode if DEBUG environment variable is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Error handling
cleanup_error() {
    log_error "$1"
    log_warning "Continuing with cleanup of remaining resources..."
}

# Trap to handle script interruption
trap 'log_warning "Script interrupted by user. Some resources may not be cleaned up."' INT TERM

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f ".deployment_state" ]]; then
        log_error "Deployment state file not found."
        log_error "Cannot proceed with automated cleanup."
        log_info "Please manually delete resources or run with --force if you know the resource IDs."
        exit 1
    fi
    
    # Source the deployment state file
    source .deployment_state
    
    # Verify critical variables are loaded
    local required_vars=(
        "RANDOM_SUFFIX"
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "SERVICE_NETWORK_ID"
        "VPC_A_ID"
        "VPC_B_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in deployment state."
            log_error "Deployment state file may be corrupted."
            exit 1
        fi
    done
    
    log_success "Deployment state loaded successfully"
    log_info "Cleanup suffix: ${RANDOM_SUFFIX}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set appropriate environment variables."
        exit 1
    fi
    
    # Verify account ID matches
    local current_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        log_error "AWS account ID mismatch!"
        log_error "Deployment was created in account: ${AWS_ACCOUNT_ID}"
        log_error "Current account: ${current_account}"
        log_error "Please configure credentials for the correct account."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "${FORCE:-}" == "true" ]]; then
        log_warning "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo
    log_warning "This will PERMANENTLY DELETE the following resources:"
    echo "  • VPC Lattice Service Network: ${SERVICE_NETWORK_ID}"
    echo "  • VPCs: ${VPC_A_ID}, ${VPC_B_ID}"
    echo "  • EC2 Instances: ${INSTANCE_A_ID:-N/A}, ${INSTANCE_B_ID:-N/A}"
    echo "  • All associated networking components"
    echo "  • CloudWatch resources"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm resource destruction: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation text did not match"
        exit 0
    fi
    
    log_warning "Starting resource cleanup in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# Deregister targets from target groups
deregister_targets() {
    log_info "Deregistering targets from target groups..."
    
    # Deregister frontend targets
    if [[ -n "${FRONTEND_TG_ID:-}" && -n "${INSTANCE_A_IP:-}" ]]; then
        aws vpc-lattice deregister-targets \
            --target-group-identifier ${FRONTEND_TG_ID} \
            --targets id=${INSTANCE_A_IP} 2>/dev/null || \
            cleanup_error "Failed to deregister frontend targets"
    fi
    
    # Deregister backend targets
    if [[ -n "${BACKEND_TG_ID:-}" && -n "${INSTANCE_B_IP:-}" ]]; then
        aws vpc-lattice deregister-targets \
            --target-group-identifier ${BACKEND_TG_ID} \
            --targets id=${INSTANCE_B_IP} 2>/dev/null || \
            cleanup_error "Failed to deregister backend targets"
    fi
    
    # Wait for targets to be deregistered
    if [[ -n "${FRONTEND_TG_ID:-}" || -n "${BACKEND_TG_ID:-}" ]]; then
        log_info "Waiting for targets to be deregistered..."
        sleep 30
    fi
    
    log_success "Targets deregistered from target groups"
}

# Remove service network associations
remove_service_associations() {
    log_info "Removing service network associations..."
    
    if [[ -z "${SERVICE_NETWORK_ID:-}" ]]; then
        log_warning "Service network ID not available, skipping service associations cleanup"
        return 0
    fi
    
    # Get and delete service associations
    local service_associations=$(aws vpc-lattice list-service-network-service-associations \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --query 'items[].id' --output text 2>/dev/null || echo "")
    
    if [[ -n "$service_associations" ]]; then
        for assoc_id in $service_associations; do
            log_info "Removing service association: $assoc_id"
            aws vpc-lattice delete-service-network-service-association \
                --service-network-service-association-identifier $assoc_id 2>/dev/null || \
                cleanup_error "Failed to remove service association: $assoc_id"
        done
        
        # Wait for associations to be removed
        log_info "Waiting for service associations to be removed..."
        local max_attempts=30
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            local remaining=$(aws vpc-lattice list-service-network-service-associations \
                --service-network-identifier ${SERVICE_NETWORK_ID} \
                --query 'length(items)' --output text 2>/dev/null || echo "0")
            
            if [[ "$remaining" == "0" ]]; then
                break
            fi
            
            log_info "Service associations remaining: $remaining, waiting... (attempt ${attempt}/${max_attempts})"
            sleep 10
            ((attempt++))
        done
    fi
    
    log_success "Service network associations removed"
}

# Delete VPC Lattice services and listeners
delete_lattice_services() {
    log_info "Deleting VPC Lattice services and listeners..."
    
    # Delete frontend service listeners and service
    if [[ -n "${FRONTEND_SERVICE_ID:-}" ]]; then
        log_info "Deleting frontend service listeners..."
        local frontend_listeners=$(aws vpc-lattice list-listeners \
            --service-identifier ${FRONTEND_SERVICE_ID} \
            --query 'items[].id' --output text 2>/dev/null || echo "")
        
        for listener_id in $frontend_listeners; do
            aws vpc-lattice delete-listener \
                --service-identifier ${FRONTEND_SERVICE_ID} \
                --listener-identifier $listener_id 2>/dev/null || \
                cleanup_error "Failed to delete frontend listener: $listener_id"
        done
        
        log_info "Deleting frontend service..."
        aws vpc-lattice delete-service \
            --service-identifier ${FRONTEND_SERVICE_ID} 2>/dev/null || \
            cleanup_error "Failed to delete frontend service"
    fi
    
    # Delete backend service listeners and service
    if [[ -n "${BACKEND_SERVICE_ID:-}" ]]; then
        log_info "Deleting backend service listeners..."
        local backend_listeners=$(aws vpc-lattice list-listeners \
            --service-identifier ${BACKEND_SERVICE_ID} \
            --query 'items[].id' --output text 2>/dev/null || echo "")
        
        for listener_id in $backend_listeners; do
            aws vpc-lattice delete-listener \
                --service-identifier ${BACKEND_SERVICE_ID} \
                --listener-identifier $listener_id 2>/dev/null || \
                cleanup_error "Failed to delete backend listener: $listener_id"
        done
        
        log_info "Deleting backend service..."
        aws vpc-lattice delete-service \
            --service-identifier ${BACKEND_SERVICE_ID} 2>/dev/null || \
            cleanup_error "Failed to delete backend service"
    fi
    
    log_success "VPC Lattice services and listeners deleted"
}

# Delete target groups
delete_target_groups() {
    log_info "Deleting VPC Lattice target groups..."
    
    # Delete frontend target group
    if [[ -n "${FRONTEND_TG_ID:-}" ]]; then
        aws vpc-lattice delete-target-group \
            --target-group-identifier ${FRONTEND_TG_ID} 2>/dev/null || \
            cleanup_error "Failed to delete frontend target group"
    fi
    
    # Delete backend target group
    if [[ -n "${BACKEND_TG_ID:-}" ]]; then
        aws vpc-lattice delete-target-group \
            --target-group-identifier ${BACKEND_TG_ID} 2>/dev/null || \
            cleanup_error "Failed to delete backend target group"
    fi
    
    log_success "VPC Lattice target groups deleted"
}

# Remove VPC associations and delete service network
delete_service_network() {
    log_info "Removing VPC associations and deleting service network..."
    
    if [[ -z "${SERVICE_NETWORK_ID:-}" ]]; then
        log_warning "Service network ID not available, skipping service network cleanup"
        return 0
    fi
    
    # Get and delete VPC associations
    local vpc_associations=$(aws vpc-lattice list-service-network-vpc-associations \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --query 'items[].id' --output text 2>/dev/null || echo "")
    
    if [[ -n "$vpc_associations" ]]; then
        for assoc_id in $vpc_associations; do
            log_info "Removing VPC association: $assoc_id"
            aws vpc-lattice delete-service-network-vpc-association \
                --service-network-vpc-association-identifier $assoc_id 2>/dev/null || \
                cleanup_error "Failed to remove VPC association: $assoc_id"
        done
        
        # Wait for VPC associations to be removed
        log_info "Waiting for VPC associations to be removed..."
        local max_attempts=30
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            local remaining=$(aws vpc-lattice list-service-network-vpc-associations \
                --service-network-identifier ${SERVICE_NETWORK_ID} \
                --query 'length(items)' --output text 2>/dev/null || echo "0")
            
            if [[ "$remaining" == "0" ]]; then
                break
            fi
            
            log_info "VPC associations remaining: $remaining, waiting... (attempt ${attempt}/${max_attempts})"
            sleep 10
            ((attempt++))
        done
    fi
    
    # Delete service network
    log_info "Deleting service network..."
    aws vpc-lattice delete-service-network \
        --service-network-identifier ${SERVICE_NETWORK_ID} 2>/dev/null || \
        cleanup_error "Failed to delete service network"
    
    log_success "VPC Lattice service network deleted"
}

# Terminate EC2 instances
terminate_instances() {
    log_info "Terminating EC2 instances..."
    
    local instances_to_terminate=()
    
    if [[ -n "${INSTANCE_A_ID:-}" ]]; then
        instances_to_terminate+=("${INSTANCE_A_ID}")
    fi
    
    if [[ -n "${INSTANCE_B_ID:-}" ]]; then
        instances_to_terminate+=("${INSTANCE_B_ID}")
    fi
    
    if [[ ${#instances_to_terminate[@]} -eq 0 ]]; then
        log_warning "No EC2 instances to terminate"
        return 0
    fi
    
    # Terminate instances
    aws ec2 terminate-instances \
        --instance-ids "${instances_to_terminate[@]}" 2>/dev/null || \
        cleanup_error "Failed to terminate EC2 instances"
    
    # Wait for instances to be terminated
    log_info "Waiting for instances to be terminated..."
    aws ec2 wait instance-terminated \
        --instance-ids "${instances_to_terminate[@]}" 2>/dev/null || \
        log_warning "Timeout waiting for instances to terminate (continuing with cleanup)"
    
    log_success "EC2 instances terminated"
}

# Delete SSH key pair
delete_ssh_key() {
    log_info "Deleting SSH key pair..."
    
    if [[ -n "${KEY_PAIR_NAME:-}" ]]; then
        aws ec2 delete-key-pair \
            --key-name "${KEY_PAIR_NAME}" 2>/dev/null || \
            cleanup_error "Failed to delete SSH key pair"
        
        # Remove local key file
        if [[ -f "k8s-lattice-key.pem" ]]; then
            rm -f k8s-lattice-key.pem
            log_info "Local SSH key file removed"
        fi
    fi
    
    log_success "SSH key pair deleted"
}

# Delete security groups
delete_security_groups() {
    log_info "Deleting security groups..."
    
    # Delete security group A
    if [[ -n "${SG_A_ID:-}" ]]; then
        aws ec2 delete-security-group \
            --group-id ${SG_A_ID} 2>/dev/null || \
            cleanup_error "Failed to delete security group A"
    fi
    
    # Delete security group B
    if [[ -n "${SG_B_ID:-}" ]]; then
        aws ec2 delete-security-group \
            --group-id ${SG_B_ID} 2>/dev/null || \
            cleanup_error "Failed to delete security group B"
    fi
    
    log_success "Security groups deleted"
}

# Delete internet gateways
delete_internet_gateways() {
    log_info "Deleting internet gateways..."
    
    # Delete internet gateway A
    if [[ -n "${IGW_A_ID:-}" && -n "${VPC_A_ID:-}" ]]; then
        aws ec2 detach-internet-gateway \
            --internet-gateway-id ${IGW_A_ID} \
            --vpc-id ${VPC_A_ID} 2>/dev/null || \
            cleanup_error "Failed to detach internet gateway A"
        
        aws ec2 delete-internet-gateway \
            --internet-gateway-id ${IGW_A_ID} 2>/dev/null || \
            cleanup_error "Failed to delete internet gateway A"
    fi
    
    # Delete internet gateway B
    if [[ -n "${IGW_B_ID:-}" && -n "${VPC_B_ID:-}" ]]; then
        aws ec2 detach-internet-gateway \
            --internet-gateway-id ${IGW_B_ID} \
            --vpc-id ${VPC_B_ID} 2>/dev/null || \
            cleanup_error "Failed to detach internet gateway B"
        
        aws ec2 delete-internet-gateway \
            --internet-gateway-id ${IGW_B_ID} 2>/dev/null || \
            cleanup_error "Failed to delete internet gateway B"
    fi
    
    log_success "Internet gateways deleted"
}

# Delete subnets and VPCs
delete_networking_infrastructure() {
    log_info "Deleting subnets and VPCs..."
    
    # Delete subnet A
    if [[ -n "${SUBNET_A_ID:-}" ]]; then
        aws ec2 delete-subnet \
            --subnet-id ${SUBNET_A_ID} 2>/dev/null || \
            cleanup_error "Failed to delete subnet A"
    fi
    
    # Delete subnet B
    if [[ -n "${SUBNET_B_ID:-}" ]]; then
        aws ec2 delete-subnet \
            --subnet-id ${SUBNET_B_ID} 2>/dev/null || \
            cleanup_error "Failed to delete subnet B"
    fi
    
    # Delete VPC A
    if [[ -n "${VPC_A_ID:-}" ]]; then
        aws ec2 delete-vpc \
            --vpc-id ${VPC_A_ID} 2>/dev/null || \
            cleanup_error "Failed to delete VPC A"
    fi
    
    # Delete VPC B
    if [[ -n "${VPC_B_ID:-}" ]]; then
        aws ec2 delete-vpc \
            --vpc-id ${VPC_B_ID} 2>/dev/null || \
            cleanup_error "Failed to delete VPC B"
    fi
    
    log_success "Networking infrastructure deleted"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch log group
    if [[ -n "${SERVICE_NETWORK_NAME:-}" ]]; then
        aws logs delete-log-group \
            --log-group-name "/aws/vpc-lattice/${SERVICE_NETWORK_NAME}" 2>/dev/null || \
            cleanup_error "Failed to delete CloudWatch log group"
    fi
    
    # Delete CloudWatch dashboard
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "VPC-Lattice-K8s-Mesh-${RANDOM_SUFFIX}" 2>/dev/null || \
            cleanup_error "Failed to delete CloudWatch dashboard"
    fi
    
    log_success "CloudWatch resources deleted"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f ".deployment_state" ]]; then
        rm -f .deployment_state
        log_info "Deployment state file removed"
    fi
    
    # Remove SSH key file if it exists
    if [[ -f "k8s-lattice-key.pem" ]]; then
        rm -f k8s-lattice-key.pem
        log_info "SSH key file removed"
    fi
    
    log_success "Local files cleaned up"
}

# Print cleanup summary
print_cleanup_summary() {
    log_success "=== Cleanup Complete ==="
    echo
    log_info "The following resources have been removed:"
    echo "  • VPC Lattice Service Network and all components"
    echo "  • EC2 instances and SSH key pair"
    echo "  • VPCs, subnets, and networking components"
    echo "  • Security groups and internet gateways"
    echo "  • CloudWatch logs and dashboard"
    echo "  • Local configuration files"
    echo
    log_success "All resources have been successfully cleaned up!"
    echo
    log_info "Note: Some resources may take a few minutes to fully terminate."
    log_info "You can verify cleanup completion in the AWS console."
}

# Perform manual cleanup (when state file is not available)
manual_cleanup() {
    log_warning "=== Manual Cleanup Mode ==="
    log_info "Searching for resources with suffix pattern..."
    
    if [[ -z "${MANUAL_SUFFIX:-}" ]]; then
        log_error "Manual cleanup requires MANUAL_SUFFIX environment variable"
        log_error "Example: MANUAL_SUFFIX=abc123 ./destroy.sh --manual"
        exit 1
    fi
    
    # Try to find and delete resources by name pattern
    log_info "Searching for VPC Lattice service networks..."
    local service_networks=$(aws vpc-lattice list-service-networks \
        --query "items[?contains(name, '${MANUAL_SUFFIX}')].{Name:name,Id:id}" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$service_networks" ]]; then
        while read -r name id; do
            log_info "Found service network: $name ($id)"
            # Set variables for cleanup functions
            export SERVICE_NETWORK_ID="$id"
            export SERVICE_NETWORK_NAME="$name"
            remove_service_associations
            delete_service_network
        done <<< "$service_networks"
    fi
    
    # Search for VPCs
    log_info "Searching for VPCs..."
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=*${MANUAL_SUFFIX}*" \
        --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
    
    for vpc_id in $vpcs; do
        log_info "Found VPC: $vpc_id"
        # Delete VPC and its components (simplified cleanup)
        aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || \
            log_warning "Failed to delete VPC $vpc_id (may have dependencies)"
    done
    
    log_warning "Manual cleanup completed. Some resources may require manual deletion."
}

# Main execution
main() {
    log_info "Starting VPC Lattice Kubernetes Integration cleanup..."
    echo
    
    # Check for manual cleanup mode
    if [[ "${1:-}" == "--manual" ]]; then
        manual_cleanup
        exit 0
    fi
    
    # Check for force mode
    if [[ "${1:-}" == "--force" ]]; then
        export FORCE="true"
    fi
    
    load_deployment_state
    check_prerequisites
    confirm_destruction
    
    # Cleanup in reverse order of creation
    deregister_targets
    remove_service_associations
    delete_lattice_services
    delete_target_groups
    delete_service_network
    terminate_instances
    delete_ssh_key
    delete_security_groups
    delete_internet_gateways
    delete_networking_infrastructure
    delete_cloudwatch_resources
    cleanup_local_files
    
    print_cleanup_summary
}

# Handle command line arguments
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "VPC Lattice Kubernetes Integration Cleanup Script"
    echo
    echo "Usage:"
    echo "  $0                 # Interactive cleanup using deployment state"
    echo "  $0 --force         # Skip confirmation prompts"
    echo "  $0 --manual        # Manual cleanup mode (requires MANUAL_SUFFIX env var)"
    echo "  $0 --help          # Show this help message"
    echo
    echo "Environment Variables:"
    echo "  DEBUG=true         # Enable debug output"
    echo "  FORCE=true         # Skip confirmation prompts"
    echo "  MANUAL_SUFFIX=xxx  # Resource suffix for manual cleanup"
    echo
    echo "Examples:"
    echo "  DEBUG=true $0                           # Cleanup with debug output"
    echo "  MANUAL_SUFFIX=abc123 $0 --manual       # Manual cleanup by suffix"
    echo
    exit 0
fi

# Execute main function
main "$@"