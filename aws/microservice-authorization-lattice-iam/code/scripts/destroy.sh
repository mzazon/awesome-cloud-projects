#!/bin/bash

# Microservice Authorization with VPC Lattice and IAM - Cleanup Script
# This script removes all infrastructure created by the deployment script

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Microservice Authorization with VPC Lattice and IAM - Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -r, --region            AWS region (defaults to current CLI region)
    -p, --prefix            Resource name prefix (defaults to 'microservice-auth')
    -s, --suffix            Resource name suffix (required if not using state file)
    -f, --state-file        Path to deployment state file
    -d, --dry-run           Show what would be done without executing
    -v, --verbose           Enable verbose output
    --auto-confirm          Skip confirmation prompts
    --force                 Force deletion even if resources are not found
    --parallel              Delete resources in parallel where safe

EXAMPLES:
    $0 --suffix abc123                          # Cleanup using suffix
    $0 --state-file deployment-state-abc123.json   # Cleanup using state file
    $0 --prefix my-demo --suffix abc123         # Cleanup with custom prefix
    $0 --dry-run --suffix abc123                # Preview cleanup

PREREQUISITES:
    - AWS CLI v2.0 or later installed and configured
    - Appropriate IAM permissions for resource deletion
    - jq command-line JSON processor (for state file parsing)

EOF
}

# Default values
DRY_RUN=false
VERBOSE=false
AUTO_CONFIRM=false
FORCE_DELETE=false
PARALLEL_DELETE=false
RESOURCE_PREFIX="microservice-auth"
RESOURCE_SUFFIX=""
STATE_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--prefix)
            RESOURCE_PREFIX="$2"
            shift 2
            ;;
        -s|--suffix)
            RESOURCE_SUFFIX="$2"
            shift 2
            ;;
        -f|--state-file)
            STATE_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --auto-confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --parallel)
            PARALLEL_DELETE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose output if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
        exit 1
    fi
    
    # Check jq if state file is provided
    if [[ -n "$STATE_FILE" ]] && ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load deployment state function
load_deployment_state() {
    if [[ -n "$STATE_FILE" ]]; then
        log "Loading deployment state from: $STATE_FILE"
        
        if [[ ! -f "$STATE_FILE" ]]; then
            error "State file not found: $STATE_FILE"
            exit 1
        fi
        
        # Extract values from state file
        AWS_REGION=$(jq -r '.awsRegion' "$STATE_FILE")
        AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' "$STATE_FILE")
        RESOURCE_PREFIX=$(jq -r '.resourcePrefix' "$STATE_FILE")
        RESOURCE_SUFFIX=$(jq -r '.randomSuffix' "$STATE_FILE")
        NETWORK_NAME=$(jq -r '.networkName' "$STATE_FILE")
        NETWORK_ID=$(jq -r '.networkId' "$STATE_FILE")
        SERVICE_NAME=$(jq -r '.serviceName' "$STATE_FILE")
        SERVICE_ID=$(jq -r '.serviceId' "$STATE_FILE")
        TARGET_GROUP_ID=$(jq -r '.targetGroupId' "$STATE_FILE")
        CLIENT_FUNCTION=$(jq -r '.clientFunction' "$STATE_FILE")
        PROVIDER_FUNCTION=$(jq -r '.providerFunction' "$STATE_FILE")
        PRODUCT_ROLE_NAME=$(jq -r '.productRoleName' "$STATE_FILE")
        ORDER_ROLE_NAME=$(jq -r '.orderRoleName' "$STATE_FILE")
        LOG_GROUP=$(jq -r '.logGroup' "$STATE_FILE")
        
        success "Deployment state loaded from file"
    elif [[ -n "$RESOURCE_SUFFIX" ]]; then
        log "Using resource suffix: $RESOURCE_SUFFIX"
        setup_environment_from_suffix
    else
        error "Either --suffix or --state-file must be provided"
        show_help
        exit 1
    fi
}

# Setup environment from suffix function
setup_environment_from_suffix() {
    log "Setting up environment from suffix..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not set. Use --region parameter or configure AWS CLI."
            exit 1
        fi
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Failed to get AWS account ID"
        exit 1
    fi
    
    # Set resource names based on prefix and suffix
    NETWORK_NAME="${RESOURCE_PREFIX}-network-${RESOURCE_SUFFIX}"
    SERVICE_NAME="${RESOURCE_PREFIX}-order-service-${RESOURCE_SUFFIX}"
    CLIENT_FUNCTION="${RESOURCE_PREFIX}-product-service-${RESOURCE_SUFFIX}"
    PROVIDER_FUNCTION="${RESOURCE_PREFIX}-order-service-${RESOURCE_SUFFIX}"
    LOG_GROUP="/aws/vpclattice/${NETWORK_NAME}"
    PRODUCT_ROLE_NAME="ProductServiceRole-${RESOURCE_SUFFIX}"
    ORDER_ROLE_NAME="OrderServiceRole-${RESOURCE_SUFFIX}"
    
    # Try to discover resource IDs
    discover_resource_ids
    
    success "Environment setup completed"
}

# Discover resource IDs function
discover_resource_ids() {
    log "Discovering resource IDs..."
    
    # Try to find service network ID
    NETWORK_ID=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='$NETWORK_NAME'].id" \
        --output text 2>/dev/null || echo "")
    
    # Try to find service ID
    SERVICE_ID=$(aws vpc-lattice list-services \
        --query "items[?name=='$SERVICE_NAME'].id" \
        --output text 2>/dev/null || echo "")
    
    # Try to find target group ID
    if [[ -n "$SERVICE_ID" ]]; then
        TARGET_GROUP_ID=$(aws vpc-lattice list-target-groups \
            --query "items[?name=='order-targets-${RESOURCE_SUFFIX}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    log "Discovered resource IDs:"
    log "  Network ID: ${NETWORK_ID:-'Not found'}"
    log "  Service ID: ${SERVICE_ID:-'Not found'}"
    log "  Target Group ID: ${TARGET_GROUP_ID:-'Not found'}"
}

# Execute command with dry-run and error handling
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description"
        echo "  Command: $cmd"
        return 0
    fi
    
    log "$description"
    if eval "$cmd" 2>/dev/null; then
        success "$description completed"
        return 0
    else
        if [[ "$ignore_errors" == "true" || "$FORCE_DELETE" == "true" ]]; then
            warning "$description failed (continuing due to --force or ignore_errors)"
            return 0
        else
            error "$description failed"
            return 1
        fi
    fi
}

# Confirmation function
confirm_deletion() {
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "=== DELETION CONFIRMATION ==="
    echo "This will delete the following resources:"
    echo "  - Network: $NETWORK_NAME (${NETWORK_ID:-'Unknown ID'})"
    echo "  - Service: $SERVICE_NAME (${SERVICE_ID:-'Unknown ID'})"
    echo "  - Lambda Functions: $CLIENT_FUNCTION, $PROVIDER_FUNCTION"
    echo "  - IAM Roles: $PRODUCT_ROLE_NAME, $ORDER_ROLE_NAME"
    echo "  - CloudWatch Log Group: $LOG_GROUP"
    echo "  - CloudWatch Alarm: VPC-Lattice-Auth-Failures-${RESOURCE_SUFFIX}"
    echo ""
    echo "Region: $AWS_REGION"
    echo "Account: $AWS_ACCOUNT_ID"
    echo ""
    
    read -p "Are you sure you want to delete these resources? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Delete VPC Lattice resources function
delete_vpc_lattice_resources() {
    log "Deleting VPC Lattice resources..."
    
    # Delete auth policy first
    if [[ -n "$SERVICE_ID" ]]; then
        execute_command \
            "aws vpc-lattice delete-auth-policy \
                --resource-identifier $SERVICE_ID" \
            "Deleting authorization policy" \
            true
    fi
    
    # Delete service network service association
    if [[ -n "$NETWORK_ID" && -n "$SERVICE_ID" ]]; then
        execute_command \
            "aws vpc-lattice delete-service-network-service-association \
                --service-network-service-association-identifier ${NETWORK_ID}/${SERVICE_ID}" \
            "Deleting service network association" \
            true
        
        # Wait for association deletion
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Waiting for association deletion..."
            sleep 20
        fi
    fi
    
    # Delete listener
    if [[ -n "$SERVICE_ID" ]]; then
        local listener_id
        listener_id=$(aws vpc-lattice list-listeners \
            --service-identifier "$SERVICE_ID" \
            --query 'items[0].id' --output text 2>/dev/null || echo "")
        
        if [[ -n "$listener_id" && "$listener_id" != "None" ]]; then
            execute_command \
                "aws vpc-lattice delete-listener \
                    --service-identifier $SERVICE_ID \
                    --listener-identifier $listener_id" \
                "Deleting service listener" \
                true
        fi
    fi
    
    # Deregister targets and delete target group
    if [[ -n "$TARGET_GROUP_ID" ]]; then
        execute_command \
            "aws vpc-lattice deregister-targets \
                --target-group-identifier $TARGET_GROUP_ID \
                --targets id=$PROVIDER_FUNCTION" \
            "Deregistering Lambda targets" \
            true
        
        execute_command \
            "aws vpc-lattice delete-target-group \
                --target-group-identifier $TARGET_GROUP_ID" \
            "Deleting target group" \
            true
    fi
    
    # Delete service
    if [[ -n "$SERVICE_ID" ]]; then
        execute_command \
            "aws vpc-lattice delete-service \
                --service-identifier $SERVICE_ID" \
            "Deleting VPC Lattice service" \
            true
    fi
    
    # Delete service network
    if [[ -n "$NETWORK_ID" ]]; then
        execute_command \
            "aws vpc-lattice delete-service-network \
                --service-network-identifier $NETWORK_ID" \
            "Deleting VPC Lattice service network" \
            true
    fi
    
    success "VPC Lattice resources deletion completed"
}

# Delete Lambda functions function
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete Lambda functions
    execute_command \
        "aws lambda delete-function \
            --function-name $CLIENT_FUNCTION" \
        "Deleting product service Lambda function" \
        true
    
    execute_command \
        "aws lambda delete-function \
            --function-name $PROVIDER_FUNCTION" \
        "Deleting order service Lambda function" \
        true
    
    success "Lambda functions deletion completed"
}

# Delete IAM resources function
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Detach and delete policies from product service role
    execute_command \
        "aws iam detach-role-policy \
            --role-name $PRODUCT_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Detaching Lambda execution policy from product service role" \
        true
    
    execute_command \
        "aws iam delete-role-policy \
            --role-name $PRODUCT_ROLE_NAME \
            --policy-name VPCLatticeInvokePolicy" \
        "Deleting VPC Lattice invoke policy from product service role" \
        true
    
    execute_command \
        "aws iam delete-role \
            --role-name $PRODUCT_ROLE_NAME" \
        "Deleting product service IAM role" \
        true
    
    # Detach and delete policies from order service role
    execute_command \
        "aws iam detach-role-policy \
            --role-name $ORDER_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Detaching Lambda execution policy from order service role" \
        true
    
    execute_command \
        "aws iam delete-role \
            --role-name $ORDER_ROLE_NAME" \
        "Deleting order service IAM role" \
        true
    
    success "IAM resources deletion completed"
}

# Delete CloudWatch resources function
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarm
    execute_command \
        "aws cloudwatch delete-alarms \
            --alarm-names VPC-Lattice-Auth-Failures-${RESOURCE_SUFFIX}" \
        "Deleting CloudWatch alarm" \
        true
    
    # Delete access log subscription (automatically removed with service network)
    # Delete CloudWatch log group
    execute_command \
        "aws logs delete-log-group \
            --log-group-name $LOG_GROUP" \
        "Deleting CloudWatch log group" \
        true
    
    success "CloudWatch resources deletion completed"
}

# Clean up local files function
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_clean=(
        "lambda-trust-policy.json"
        "auth-policy.json"
        "vpc-lattice-invoke-policy.json"
        "product-service.py"
        "order-service.py"
        "product-service.zip"
        "order-service.zip"
        "response.json"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "${YELLOW}[DRY-RUN]${NC} Would remove file: $file"
            else
                rm -f "$file"
                log "Removed file: $file"
            fi
        fi
    done
    
    # Clean up deployment state file if using suffix
    if [[ -z "$STATE_FILE" && -f "deployment-state-${RESOURCE_SUFFIX}.json" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would remove deployment state file: deployment-state-${RESOURCE_SUFFIX}.json"
        else
            rm -f "deployment-state-${RESOURCE_SUFFIX}.json"
            log "Removed deployment state file: deployment-state-${RESOURCE_SUFFIX}.json"
        fi
    fi
    
    success "Local file cleanup completed"
}

# Parallel deletion function
delete_resources_parallel() {
    log "Starting parallel resource deletion..."
    
    # Start Lambda deletion in background
    (delete_lambda_functions) &
    local lambda_pid=$!
    
    # Start CloudWatch deletion in background
    (delete_cloudwatch_resources) &
    local cloudwatch_pid=$!
    
    # Delete VPC Lattice resources (must be done sequentially)
    delete_vpc_lattice_resources
    
    # Wait for parallel deletions to complete
    wait $lambda_pid
    wait $cloudwatch_pid
    
    # Delete IAM resources last (may be in use by Lambda)
    delete_iam_resources
    
    success "Parallel resource deletion completed"
}

# Sequential deletion function
delete_resources_sequential() {
    log "Starting sequential resource deletion..."
    
    delete_vpc_lattice_resources
    delete_lambda_functions
    delete_iam_resources
    delete_cloudwatch_resources
    
    success "Sequential resource deletion completed"
}

# Verification function
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    local remaining_resources=()
    
    # Check if service network still exists
    if [[ -n "$NETWORK_ID" ]]; then
        if aws vpc-lattice get-service-network --service-network-identifier "$NETWORK_ID" &>/dev/null; then
            remaining_resources+=("Service Network: $NETWORK_ID")
        fi
    fi
    
    # Check if Lambda functions still exist
    if aws lambda get-function --function-name "$CLIENT_FUNCTION" &>/dev/null; then
        remaining_resources+=("Lambda Function: $CLIENT_FUNCTION")
    fi
    
    if aws lambda get-function --function-name "$PROVIDER_FUNCTION" &>/dev/null; then
        remaining_resources+=("Lambda Function: $PROVIDER_FUNCTION")
    fi
    
    # Check if IAM roles still exist
    if aws iam get-role --role-name "$PRODUCT_ROLE_NAME" &>/dev/null; then
        remaining_resources+=("IAM Role: $PRODUCT_ROLE_NAME")
    fi
    
    if aws iam get-role --role-name "$ORDER_ROLE_NAME" &>/dev/null; then
        remaining_resources+=("IAM Role: $ORDER_ROLE_NAME")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        success "All resources successfully deleted"
    else
        warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            echo "  - $resource"
        done
        echo "These resources may be in a deleting state and will be removed shortly."
    fi
}

# Main cleanup function
main() {
    log "Starting microservice authorization cleanup..."
    log "Script version: 1.0"
    log "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_deletion
    
    if [[ "$PARALLEL_DELETE" == "true" ]]; then
        delete_resources_parallel
    else
        delete_resources_sequential
    fi
    
    cleanup_local_files
    verify_deletion
    
    success "Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "=== Cleanup Summary ==="
        echo "All resources for suffix '$RESOURCE_SUFFIX' have been deleted."
        echo "If any resources remain, they may be in a deleting state."
        echo "Check the AWS console to verify complete deletion."
    fi
}

# Run main function
main "$@"