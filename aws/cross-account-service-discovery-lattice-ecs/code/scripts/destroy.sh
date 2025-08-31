#!/bin/bash

# Cross-Account Service Discovery with VPC Lattice and ECS - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Cross-Account Service Discovery with VPC Lattice and ECS - Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -s, --suffix SUFFIX     Resource name suffix (required)
    -r, --region REGION     AWS region (default: current configured region)
    -f, --force            Skip confirmation prompts
    -d, --dry-run          Show what would be deleted without making changes
    --keep-logs            Keep CloudWatch log groups
    --keep-roles           Keep IAM roles
    -h, --help             Show this help message

Example:
    $0 --suffix abc123
    $0 --suffix abc123 --force
    $0 --suffix abc123 --dry-run

Environment Variables:
    You can also source the deployment state file:
    source /tmp/deployment-state.env
    $0

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
KEEP_LOGS=false
KEEP_ROLES=false
RESOURCE_SUFFIX=""
AWS_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--suffix)
            RESOURCE_SUFFIX="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --keep-roles)
            KEEP_ROLES=true
            shift
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Set AWS region
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            log_error "AWS region not configured. Set it using aws configure or --region option."
            exit 1
        fi
    fi
    
    # Check resource suffix
    if [[ -z "${RESOURCE_SUFFIX}" ]]; then
        log_error "Resource suffix is required. Use --suffix option or source deployment-state.env"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get account information
    if [[ -z "${ACCOUNT_A_ID:-}" ]]; then
        export ACCOUNT_A_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION="${AWS_REGION}"
    fi
    
    # Set resource names using suffix
    if [[ -z "${CLUSTER_NAME_A:-}" ]]; then
        export CLUSTER_NAME_A="producer-cluster-${RESOURCE_SUFFIX}"
    fi
    
    if [[ -z "${SERVICE_NAME_A:-}" ]]; then
        export SERVICE_NAME_A="producer-service-${RESOURCE_SUFFIX}"
    fi
    
    if [[ -z "${LATTICE_SERVICE_A:-}" ]]; then
        export LATTICE_SERVICE_A="lattice-producer-${RESOURCE_SUFFIX}"
    fi
    
    if [[ -z "${SERVICE_NETWORK_NAME:-}" ]]; then
        export SERVICE_NETWORK_NAME="cross-account-network-${RESOURCE_SUFFIX}"
    fi
    
    log_success "Environment configured"
    log "Account ID: ${ACCOUNT_A_ID}"
    log "Region: ${AWS_REGION}"
    log "Resource Suffix: ${RESOURCE_SUFFIX}"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will DELETE the following resources:"
    echo "  - ECS Cluster: ${CLUSTER_NAME_A}"
    echo "  - ECS Service: ${SERVICE_NAME_A}"
    echo "  - VPC Lattice Service: ${LATTICE_SERVICE_A}"
    echo "  - Service Network: ${SERVICE_NETWORK_NAME}"
    echo "  - AWS RAM Resource Share"
    echo "  - EventBridge Rules and Targets"
    echo "  - CloudWatch Dashboard"
    
    if [[ "${KEEP_LOGS}" == "false" ]]; then
        echo "  - CloudWatch Log Groups"
    fi
    
    if [[ "${KEEP_ROLES}" == "false" ]]; then
        echo "  - IAM Roles (EventBridgeLogsRole)"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to find resource ARNs
find_resource_arns() {
    log "Finding resource ARNs..."
    
    # Find service network ARN
    if [[ -z "${SERVICE_NETWORK_ARN:-}" ]]; then
        SERVICE_NETWORK_ARN=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].arn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${SERVICE_NETWORK_ARN}" ]]; then
            SERVICE_NETWORK_ID=$(echo "${SERVICE_NETWORK_ARN}" | cut -d'/' -f2)
        fi
    fi
    
    # Find VPC Lattice service ARN
    if [[ -z "${LATTICE_SERVICE_ARN:-}" ]]; then
        LATTICE_SERVICE_ARN=$(aws vpc-lattice list-services \
            --query "items[?name=='${LATTICE_SERVICE_A}'].arn" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Find target group ARN
    if [[ -z "${TARGET_GROUP_ARN:-}" ]]; then
        TARGET_GROUP_ARN=$(aws vpc-lattice list-target-groups \
            --query "items[?name=='producer-targets-${RESOURCE_SUFFIX}'].arn" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Find resource share ARN
    if [[ -z "${RESOURCE_SHARE_ARN:-}" ]]; then
        RESOURCE_SHARE_ARN=$(aws ram get-resource-shares \
            --resource-owner SELF \
            --name "lattice-network-share-${RESOURCE_SUFFIX}" \
            --query 'resourceShares[0].resourceShareArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ "${RESOURCE_SHARE_ARN}" == "None" ]]; then
            RESOURCE_SHARE_ARN=""
        fi
    fi
    
    log_success "Resource ARNs discovered"
}

# Function to delete ECS service and cluster
delete_ecs_resources() {
    log "Deleting ECS resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would delete ECS service ${SERVICE_NAME_A} and cluster ${CLUSTER_NAME_A}"
        return
    fi
    
    # Check if ECS service exists
    if aws ecs describe-services --cluster "${CLUSTER_NAME_A}" --services "${SERVICE_NAME_A}" \
        --query 'services[?status==`ACTIVE`]' --output text 2>/dev/null | grep -q .; then
        
        log "Scaling down ECS service..."
        aws ecs update-service \
            --cluster "${CLUSTER_NAME_A}" \
            --service "${SERVICE_NAME_A}" \
            --desired-count 0 > /dev/null
        
        aws ecs wait services-stable \
            --cluster "${CLUSTER_NAME_A}" \
            --services "${SERVICE_NAME_A}"
        
        log "Deleting ECS service..."
        aws ecs delete-service \
            --cluster "${CLUSTER_NAME_A}" \
            --service "${SERVICE_NAME_A}" > /dev/null
        
        log_success "ECS service deleted"
    else
        log "ECS service not found or already deleted"
    fi
    
    # Delete ECS cluster
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME_A}" \
        --query 'clusters[?status==`ACTIVE`]' --output text 2>/dev/null | grep -q .; then
        
        aws ecs delete-cluster --cluster "${CLUSTER_NAME_A}" > /dev/null
        log_success "ECS cluster deleted"
    else
        log "ECS cluster not found or already deleted"
    fi
    
    # Deregister task definition (mark as INACTIVE)
    local task_def_arn=$(aws ecs list-task-definitions \
        --family-prefix "producer-task-${RESOURCE_SUFFIX}" \
        --status ACTIVE \
        --query 'taskDefinitionArns[0]' --output text 2>/dev/null || echo "")
    
    if [[ -n "${task_def_arn}" && "${task_def_arn}" != "None" ]]; then
        aws ecs deregister-task-definition \
            --task-definition "${task_def_arn}" > /dev/null
        log_success "Task definition deregistered"
    fi
}

# Function to delete VPC Lattice resources
delete_lattice_resources() {
    log "Deleting VPC Lattice resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would delete VPC Lattice resources"
        return
    fi
    
    # Delete service network associations first
    if [[ -n "${SERVICE_NETWORK_ARN}" ]]; then
        # Delete VPC associations
        local vpc_associations=$(aws vpc-lattice list-service-network-vpc-associations \
            --service-network-identifier "${SERVICE_NETWORK_ARN}" \
            --query 'items[].id' --output text 2>/dev/null || echo "")
        
        for assoc_id in ${vpc_associations}; do
            if [[ -n "${assoc_id}" && "${assoc_id}" != "None" ]]; then
                aws vpc-lattice delete-service-network-vpc-association \
                    --service-network-vpc-association-identifier "${assoc_id}" 2>/dev/null || true
                log "Deleted VPC association: ${assoc_id}"
            fi
        done
        
        # Delete service associations
        local service_associations=$(aws vpc-lattice list-service-network-service-associations \
            --service-network-identifier "${SERVICE_NETWORK_ARN}" \
            --query 'items[].id' --output text 2>/dev/null || echo "")
        
        for assoc_id in ${service_associations}; do
            if [[ -n "${assoc_id}" && "${assoc_id}" != "None" ]]; then
                aws vpc-lattice delete-service-network-service-association \
                    --service-network-service-association-identifier "${assoc_id}" 2>/dev/null || true
                log "Deleted service association: ${assoc_id}"
            fi
        done
    fi
    
    # Delete VPC Lattice service
    if [[ -n "${LATTICE_SERVICE_ARN}" ]]; then
        # Delete listeners first
        local listeners=$(aws vpc-lattice list-listeners \
            --service-identifier "${LATTICE_SERVICE_ARN}" \
            --query 'items[].arn' --output text 2>/dev/null || echo "")
        
        for listener_arn in ${listeners}; do
            if [[ -n "${listener_arn}" && "${listener_arn}" != "None" ]]; then
                aws vpc-lattice delete-listener \
                    --listener-identifier "${listener_arn}" 2>/dev/null || true
                log "Deleted listener: ${listener_arn}"
            fi
        done
        
        aws vpc-lattice delete-service \
            --service-identifier "${LATTICE_SERVICE_ARN}" 2>/dev/null || true
        log_success "VPC Lattice service deleted"
    fi
    
    # Delete target group
    if [[ -n "${TARGET_GROUP_ARN}" ]]; then
        aws vpc-lattice delete-target-group \
            --target-group-identifier "${TARGET_GROUP_ARN}" 2>/dev/null || true
        log_success "Target group deleted"
    fi
    
    # Delete service network
    if [[ -n "${SERVICE_NETWORK_ARN}" ]]; then
        aws vpc-lattice delete-service-network \
            --service-network-identifier "${SERVICE_NETWORK_ARN}" 2>/dev/null || true
        log_success "Service network deleted"
    fi
}

# Function to delete AWS RAM resource share
delete_resource_share() {
    log "Deleting AWS RAM resource share..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would delete AWS RAM resource share"
        return
    fi
    
    if [[ -n "${RESOURCE_SHARE_ARN}" ]]; then
        aws ram delete-resource-share \
            --resource-share-arn "${RESOURCE_SHARE_ARN}" 2>/dev/null || true
        log_success "AWS RAM resource share deleted"
    else
        log "AWS RAM resource share not found"
    fi
}

# Function to delete EventBridge resources
delete_eventbridge_resources() {
    log "Deleting EventBridge resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would delete EventBridge resources"
        return
    fi
    
    # Remove EventBridge targets
    if aws events describe-rule --name "vpc-lattice-events" &> /dev/null; then
        aws events remove-targets \
            --rule "vpc-lattice-events" \
            --ids "1" 2>/dev/null || true
        
        # Delete EventBridge rule
        aws events delete-rule \
            --name "vpc-lattice-events" 2>/dev/null || true
        
        log_success "EventBridge rule deleted"
    else
        log "EventBridge rule not found"
    fi
    
    # Delete IAM role if not keeping roles
    if [[ "${KEEP_ROLES}" == "false" ]]; then
        if aws iam get-role --role-name "EventBridgeLogsRole" &> /dev/null; then
            # Delete role policy first
            aws iam delete-role-policy \
                --role-name "EventBridgeLogsRole" \
                --policy-name "EventBridgeLogsPolicy" 2>/dev/null || true
            
            # Delete role
            aws iam delete-role \
                --role-name "EventBridgeLogsRole" 2>/dev/null || true
            
            log_success "EventBridge IAM role deleted"
        fi
    else
        log "Keeping EventBridge IAM role (--keep-roles specified)"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would delete CloudWatch resources"
        return
    fi
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "cross-account-service-discovery-${RESOURCE_SUFFIX}" &> /dev/null; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "cross-account-service-discovery-${RESOURCE_SUFFIX}" 2>/dev/null || true
        log_success "CloudWatch dashboard deleted"
    else
        log "CloudWatch dashboard not found"
    fi
    
    # Delete log groups if not keeping them
    if [[ "${KEEP_LOGS}" == "false" ]]; then
        local log_groups=("/aws/events/vpc-lattice" "/ecs/producer")
        
        for log_group in "${log_groups[@]}"; do
            if aws logs describe-log-groups --log-group-name-prefix "${log_group}" \
                --query 'logGroups[?logGroupName==`'${log_group}'`]' --output text 2>/dev/null | grep -q "${log_group}"; then
                
                aws logs delete-log-group \
                    --log-group-name "${log_group}" 2>/dev/null || true
                log_success "Deleted log group: ${log_group}"
            fi
        done
    else
        log "Keeping CloudWatch log groups (--keep-logs specified)"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN: Would clean up temporary files"
        return
    fi
    
    local temp_files=(
        "/tmp/deployment-state.env"
        "/tmp/producer-task-def.json"
        "/tmp/dashboard-config.json"
        "/tmp/eventbridge-role-policy.json"
        "/tmp/eventbridge-logs-policy.json"
        "/tmp/ecs-trust-policy.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log "Removed temporary file: ${file}"
        fi
    done
    
    log_success "Temporary files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local errors=0
    
    # Check ECS cluster
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME_A}" \
        --query 'clusters[?status==`ACTIVE`]' --output text 2>/dev/null | grep -q .; then
        log_error "ECS cluster still exists: ${CLUSTER_NAME_A}"
        ((errors++))
    fi
    
    # Check VPC Lattice service
    if [[ -n "${LATTICE_SERVICE_ARN}" ]] && \
        aws vpc-lattice get-service --service-identifier "${LATTICE_SERVICE_ARN}" &> /dev/null; then
        log_error "VPC Lattice service still exists: ${LATTICE_SERVICE_A}"
        ((errors++))
    fi
    
    # Check service network
    if [[ -n "${SERVICE_NETWORK_ARN}" ]] && \
        aws vpc-lattice get-service-network --service-network-identifier "${SERVICE_NETWORK_ARN}" &> /dev/null; then
        log_error "Service network still exists: ${SERVICE_NETWORK_NAME}"
        ((errors++))
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "vpc-lattice-events" &> /dev/null; then
        log_error "EventBridge rule still exists: vpc-lattice-events"
        ((errors++))
    fi
    
    if [[ ${errors} -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found ${errors} remaining resources"
        log "Some resources may take time to fully delete or have dependencies"
    fi
}

# Function to print cleanup summary
print_summary() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN completed - no resources were actually deleted"
        return
    fi
    
    log_success "Cleanup completed!"
    echo ""
    echo "=== Cleanup Summary ==="
    echo "Resource Suffix: ${RESOURCE_SUFFIX}"
    echo "AWS Region: ${AWS_REGION}"
    echo "Account ID: ${ACCOUNT_A_ID}"
    echo ""
    echo "=== Deleted Resources ==="
    echo "✅ ECS Cluster: ${CLUSTER_NAME_A}"
    echo "✅ ECS Service: ${SERVICE_NAME_A}"
    echo "✅ VPC Lattice Service: ${LATTICE_SERVICE_A}"
    echo "✅ Service Network: ${SERVICE_NETWORK_NAME}"
    echo "✅ AWS RAM Resource Share"
    echo "✅ EventBridge Rules and Targets"
    echo "✅ CloudWatch Dashboard"
    
    if [[ "${KEEP_LOGS}" == "false" ]]; then
        echo "✅ CloudWatch Log Groups"
    else
        echo "⚠️  CloudWatch Log Groups (kept)"
    fi
    
    if [[ "${KEEP_ROLES}" == "false" ]]; then
        echo "✅ IAM Roles"
    else
        echo "⚠️  IAM Roles (kept)"
    fi
    
    echo ""
    echo "=== Notes ==="
    echo "• Some resources may take a few minutes to fully delete"
    echo "• If you shared resources with Account B, those associations may need manual cleanup"
    echo "• Task definitions are deregistered but remain in INACTIVE state (this is normal)"
}

# Main cleanup function
main() {
    log "Starting Cross-Account Service Discovery cleanup..."
    
    check_prerequisites
    setup_environment
    find_resource_arns
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_ecs_resources
    delete_lattice_resources
    delete_resource_share
    delete_eventbridge_resources
    delete_cloudwatch_resources
    cleanup_temp_files
    
    verify_cleanup
    print_summary
}

# Trap errors and provide helpful messages
trap 'log_error "Cleanup failed on line $LINENO. Some resources may still exist."' ERR

# Run main function
main "$@"