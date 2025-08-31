#!/bin/bash

# Blue-Green Deployments with VPC Lattice and Lambda - Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper dependency ordering and confirmation prompts

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load environment variables
load_environment() {
    if [ -f ".deployment-env" ]; then
        log "Loading deployment environment from .deployment-env..."
        source .deployment-env
        
        # Verify required variables are set
        local required_vars=(
            "AWS_REGION"
            "AWS_ACCOUNT_ID"
            "BLUE_FUNCTION_NAME"
            "GREEN_FUNCTION_NAME"
            "BLUE_TG_NAME"
            "GREEN_TG_NAME"
            "LATTICE_SERVICE_NAME"
            "IAM_ROLE_NAME"
            "SERVICE_NETWORK_NAME"
            "RANDOM_SUFFIX"
        )
        
        for var in "${required_vars[@]}"; do
            if [ -z "${!var:-}" ]; then
                error "Required environment variable $var is not set"
                exit 1
            fi
        done
        
        log "Environment variables loaded successfully"
    else
        error "Deployment environment file (.deployment-env) not found"
        error "Cannot proceed with cleanup without deployment configuration"
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    
    if [ "$current_account" != "$AWS_ACCOUNT_ID" ]; then
        error "Current AWS account ($current_account) doesn't match deployment account ($AWS_ACCOUNT_ID)"
        exit 1
    fi
    
    log "AWS credentials validated for account: $current_account"
}

# Function to get confirmation from user
get_confirmation() {
    local resource_type="$1"
    local resource_name="$2"
    
    echo ""
    warn "About to delete $resource_type: $resource_name"
    read -p "Are you sure you want to continue? (y/N): " confirmation
    
    case "$confirmation" in
        [yY][eS]|[yY])
            return 0
            ;;
        *)
            warn "Skipping deletion of $resource_type: $resource_name"
            return 1
            ;;
    esac
}

# Function to safely delete a resource with retry logic
safe_delete() {
    local delete_command="$1"
    local resource_type="$2"
    local resource_name="$3"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$delete_command" >/dev/null 2>&1; then
            log "Successfully deleted $resource_type: $resource_name"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                warn "Failed to delete $resource_type: $resource_name (attempt $retry_count/$max_retries)"
                info "Retrying in 5 seconds..."
                sleep 5
            else
                error "Failed to delete $resource_type: $resource_name after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_type="$2"
    local resource_name="$3"
    local max_wait=120  # 2 minutes
    local wait_time=0
    
    info "Waiting for $resource_type deletion to complete..."
    
    while [ $wait_time -lt $max_wait ]; do
        if ! eval "$check_command" >/dev/null 2>&1; then
            log "$resource_type deletion completed: $resource_name"
            return 0
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        
        if [ $((wait_time % 30)) -eq 0 ]; then
            info "Still waiting for $resource_type deletion... (${wait_time}s elapsed)"
        fi
    done
    
    warn "$resource_type deletion may not be complete after ${max_wait}s: $resource_name"
    return 1
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms=(
        "${GREEN_FUNCTION_NAME}-ErrorRate"
        "${GREEN_FUNCTION_NAME}-Duration"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" >/dev/null 2>&1; then
            if get_confirmation "CloudWatch alarm" "$alarm"; then
                safe_delete "aws cloudwatch delete-alarms --alarm-names '$alarm'" "CloudWatch alarm" "$alarm"
            fi
        else
            info "CloudWatch alarm not found (may already be deleted): $alarm"
        fi
    done
}

# Function to delete VPC Lattice service and associations
delete_lattice_service() {
    log "Checking for VPC Lattice service and associations..."
    
    # Get service ID if it exists
    local service_id=$(aws vpc-lattice list-services \
        --query "items[?name=='$LATTICE_SERVICE_NAME'].id" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$service_id" ]; then
        info "VPC Lattice service not found (may already be deleted): $LATTICE_SERVICE_NAME"
        return 0
    fi
    
    # Get service network ID
    local service_network_id=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='$SERVICE_NETWORK_NAME'].id" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$service_network_id" ]; then
        # Check for service network association
        local association_id=$(aws vpc-lattice list-service-network-service-associations \
            --service-network-identifier "$service_network_id" \
            --query "items[?serviceName=='$LATTICE_SERVICE_NAME'].id" \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$association_id" ]; then
            if get_confirmation "VPC Lattice service network association" "$association_id"; then
                info "Deleting service network association..."
                safe_delete "aws vpc-lattice delete-service-network-service-association --service-network-service-association-identifier '$association_id'" "Service network association" "$association_id"
                
                # Wait for association deletion
                wait_for_deletion "aws vpc-lattice get-service-network-service-association --service-network-service-association-identifier '$association_id'" "Service network association" "$association_id"
            fi
        fi
    fi
    
    # Delete VPC Lattice service
    if get_confirmation "VPC Lattice service" "$LATTICE_SERVICE_NAME"; then
        safe_delete "aws vpc-lattice delete-service --service-identifier '$service_id'" "VPC Lattice service" "$LATTICE_SERVICE_NAME"
        
        # Wait for service deletion
        wait_for_deletion "aws vpc-lattice get-service --service-identifier '$service_id'" "VPC Lattice service" "$LATTICE_SERVICE_NAME"
    fi
}

# Function to delete target groups
delete_target_groups() {
    log "Deleting VPC Lattice target groups..."
    
    local target_groups=("$BLUE_TG_NAME" "$GREEN_TG_NAME")
    
    for tg_name in "${target_groups[@]}"; do
        local tg_arn=$(aws vpc-lattice list-target-groups \
            --query "items[?name=='$tg_name'].arn" \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$tg_arn" ]; then
            if get_confirmation "Target group" "$tg_name"; then
                safe_delete "aws vpc-lattice delete-target-group --target-group-identifier '$tg_arn'" "Target group" "$tg_name"
            fi
        else
            info "Target group not found (may already be deleted): $tg_name"
        fi
    done
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    local functions=("$BLUE_FUNCTION_NAME" "$GREEN_FUNCTION_NAME")
    
    for function_name in "${functions[@]}"; do
        if aws lambda get-function --function-name "$function_name" >/dev/null 2>&1; then
            if get_confirmation "Lambda function" "$function_name"; then
                safe_delete "aws lambda delete-function --function-name '$function_name'" "Lambda function" "$function_name"
            fi
        else
            info "Lambda function not found (may already be deleted): $function_name"
        fi
    done
}

# Function to delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        if get_confirmation "IAM role" "$IAM_ROLE_NAME"; then
            # Detach policies first
            info "Detaching policies from IAM role..."
            aws iam detach-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
                2>/dev/null || warn "Policy may already be detached"
            
            # Delete the role
            safe_delete "aws iam delete-role --role-name '$IAM_ROLE_NAME'" "IAM role" "$IAM_ROLE_NAME"
        fi
    else
        info "IAM role not found (may already be deleted): $IAM_ROLE_NAME"
    fi
}

# Function to delete service network
delete_service_network() {
    log "Deleting VPC Lattice service network..."
    
    local service_network_id=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='$SERVICE_NETWORK_NAME'].id" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$service_network_id" ]; then
        if get_confirmation "VPC Lattice service network" "$SERVICE_NETWORK_NAME"; then
            safe_delete "aws vpc-lattice delete-service-network --service-network-identifier '$service_network_id'" "Service network" "$SERVICE_NETWORK_NAME"
        fi
    else
        info "Service network not found (may already be deleted): $SERVICE_NETWORK_NAME"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        ".deployment-env"
        "blue_function.py"
        "green_function.py"
        "blue_function.zip"
        "green_function.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            if get_confirmation "local file" "$file"; then
                rm -f "$file"
                log "Removed local file: $file"
            fi
        fi
    done
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "========================================="
    echo "         CLEANUP SUMMARY"
    echo "========================================="
    echo "Blue-Green Deployment Cleanup Completed!"
    echo ""
    echo "Resources Cleaned Up:"
    echo "  • CloudWatch Alarms"
    echo "  • VPC Lattice Service: $LATTICE_SERVICE_NAME"
    echo "  • Target Groups: $BLUE_TG_NAME, $GREEN_TG_NAME"
    echo "  • Lambda Functions: $BLUE_FUNCTION_NAME, $GREEN_FUNCTION_NAME"
    echo "  • IAM Role: $IAM_ROLE_NAME"
    echo "  • Service Network: $SERVICE_NETWORK_NAME"
    echo "  • Local temporary files"
    echo ""
    echo "All resources have been successfully removed."
    echo "========================================="
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check Lambda functions
    for function_name in "$BLUE_FUNCTION_NAME" "$GREEN_FUNCTION_NAME"; do
        if aws lambda get-function --function-name "$function_name" >/dev/null 2>&1; then
            warn "Lambda function still exists: $function_name"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        warn "IAM role still exists: $IAM_ROLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check VPC Lattice service
    local service_id=$(aws vpc-lattice list-services \
        --query "items[?name=='$LATTICE_SERVICE_NAME'].id" \
        --output text 2>/dev/null || echo "")
    if [ ! -z "$service_id" ]; then
        warn "VPC Lattice service still exists: $LATTICE_SERVICE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "Cleanup verification passed - all resources removed successfully"
    else
        warn "Cleanup verification found $cleanup_issues remaining resources"
        warn "You may need to manually remove these resources"
    fi
}

# Main cleanup function
main() {
    echo "================================================"
    echo "Blue-Green Deployments with VPC Lattice and Lambda"
    echo "Cleanup Script v1.0"
    echo "================================================"
    echo ""
    
    # Prerequisites check
    log "Starting cleanup prerequisites check..."
    
    # Check if required commands exist
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    # Load environment and check credentials
    load_environment
    check_aws_credentials
    
    log "Prerequisites check completed successfully"
    echo ""
    
    # Display warning about destructive action
    echo ""
    echo "⚠️  WARNING: This script will DELETE the following resources:"
    echo "   • CloudWatch Alarms"
    echo "   • VPC Lattice Service: $LATTICE_SERVICE_NAME"
    echo "   • Target Groups: $BLUE_TG_NAME, $GREEN_TG_NAME"
    echo "   • Lambda Functions: $BLUE_FUNCTION_NAME, $GREEN_FUNCTION_NAME"
    echo "   • IAM Role: $IAM_ROLE_NAME"
    echo "   • Service Network: $SERVICE_NETWORK_NAME"
    echo "   • Local configuration files"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " final_confirmation
    
    if [ "$final_confirmation" != "DELETE" ]; then
        warn "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Starting resource cleanup (resources will be deleted in dependency order)..."
    
    # Delete resources in reverse dependency order
    delete_cloudwatch_alarms
    delete_lattice_service
    delete_target_groups
    delete_lambda_functions
    delete_iam_role
    delete_service_network
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Run main function
main "$@"