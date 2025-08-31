#!/bin/bash

# =============================================================================
# Cross-Region Service Failover with VPC Lattice and Route53 - Cleanup Script
# =============================================================================
# Description: Automated cleanup of cross-region failover infrastructure
# Author: AWS Recipe Generator
# Version: 1.0
# =============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="destroy_${TIMESTAMP}.log"
readonly STATE_FILE="deployment_state.json"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Progress tracking
declare -i CURRENT_STEP=0
declare -i TOTAL_STEPS=10

# =============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR: $*${NC}" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO: $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS: $*${NC}" | tee -a "$LOG_FILE"
}

progress() {
    ((CURRENT_STEP++))
    echo -e "${BLUE}[Step ${CURRENT_STEP}/${TOTAL_STEPS}] $*${NC}" | tee -a "$LOG_FILE"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

confirm_destruction() {
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        echo ""
        warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        warn "This script will permanently delete all resources created by the deployment."
        warn "This action cannot be undone!"
        echo ""
        
        if [[ -f "$STATE_FILE" ]]; then
            local domain_name
            domain_name=$(jq -r '.resources.route53.domain_name // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
            warn "Resources to be deleted include:"
            warn "  - Domain: $domain_name"
            warn "  - VPC Lattice services and networks"
            warn "  - Lambda functions"
            warn "  - Route53 health checks and hosted zone"
            warn "  - CloudWatch alarms"
            warn "  - IAM roles and policies"
            warn "  - VPCs and associated resources"
        fi
        
        echo ""
        read -r -p "Are you sure you want to continue? (type 'yes' to confirm): " response
        if [[ "$response" != "yes" ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

load_deployment_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "Deployment state file '$STATE_FILE' not found"
        warn "You may need to manually clean up resources or provide resource IDs via environment variables"
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        error "jq command not found. Please install jq to parse the state file"
        warn "Alternatively, set environment variables manually and re-run with FORCE_DESTROY=true"
        return 1
    fi
    
    # Load variables from state file
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // ""' "$STATE_FILE")
    
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(jq -r '.random_suffix // ""' "$STATE_FILE")
    
    export PRIMARY_REGION
    PRIMARY_REGION=$(jq -r '.primary_region // "us-east-1"' "$STATE_FILE")
    
    export SECONDARY_REGION
    SECONDARY_REGION=$(jq -r '.secondary_region // "us-west-2"' "$STATE_FILE")
    
    # VPC IDs
    export PRIMARY_VPC_ID
    PRIMARY_VPC_ID=$(jq -r '.resources.vpcs.primary_vpc_id // ""' "$STATE_FILE")
    
    export SECONDARY_VPC_ID
    SECONDARY_VPC_ID=$(jq -r '.resources.vpcs.secondary_vpc_id // ""' "$STATE_FILE")
    
    # Service Network IDs
    export PRIMARY_SERVICE_NETWORK_ID
    PRIMARY_SERVICE_NETWORK_ID=$(jq -r '.resources.service_networks.primary_service_network_id // ""' "$STATE_FILE")
    
    export SECONDARY_SERVICE_NETWORK_ID
    SECONDARY_SERVICE_NETWORK_ID=$(jq -r '.resources.service_networks.secondary_service_network_id // ""' "$STATE_FILE")
    
    # Service IDs
    export PRIMARY_SERVICE_ID
    PRIMARY_SERVICE_ID=$(jq -r '.resources.services.primary_service_id // ""' "$STATE_FILE")
    
    export SECONDARY_SERVICE_ID
    SECONDARY_SERVICE_ID=$(jq -r '.resources.services.secondary_service_id // ""' "$STATE_FILE")
    
    # Target Group IDs
    export PRIMARY_TARGET_GROUP_ID
    PRIMARY_TARGET_GROUP_ID=$(jq -r '.resources.target_groups.primary_target_group_id // ""' "$STATE_FILE")
    
    export SECONDARY_TARGET_GROUP_ID
    SECONDARY_TARGET_GROUP_ID=$(jq -r '.resources.target_groups.secondary_target_group_id // ""' "$STATE_FILE")
    
    # Lambda Functions
    export PRIMARY_FUNCTION_NAME
    PRIMARY_FUNCTION_NAME=$(jq -r '.resources.lambda_functions.primary_function_name // ""' "$STATE_FILE")
    
    export SECONDARY_FUNCTION_NAME
    SECONDARY_FUNCTION_NAME=$(jq -r '.resources.lambda_functions.secondary_function_name // ""' "$STATE_FILE")
    
    # IAM Role
    export IAM_ROLE_NAME
    IAM_ROLE_NAME=$(jq -r '.resources.iam_role.role_name // ""' "$STATE_FILE")
    
    # Route53 Resources
    export HOSTED_ZONE_ID
    HOSTED_ZONE_ID=$(jq -r '.resources.route53.hosted_zone_id // ""' "$STATE_FILE")
    
    export PRIMARY_HEALTH_CHECK_ID
    PRIMARY_HEALTH_CHECK_ID=$(jq -r '.resources.route53.primary_health_check_id // ""' "$STATE_FILE")
    
    export SECONDARY_HEALTH_CHECK_ID
    SECONDARY_HEALTH_CHECK_ID=$(jq -r '.resources.route53.secondary_health_check_id // ""' "$STATE_FILE")
    
    export DOMAIN_NAME
    DOMAIN_NAME=$(jq -r '.resources.route53.domain_name // ""' "$STATE_FILE")
    
    export PRIMARY_SERVICE_DNS
    PRIMARY_SERVICE_DNS=$(jq -r '.resources.route53.primary_service_dns // ""' "$STATE_FILE")
    
    export SECONDARY_SERVICE_DNS
    SECONDARY_SERVICE_DNS=$(jq -r '.resources.route53.secondary_service_dns // ""' "$STATE_FILE")
    
    # CloudWatch Alarms
    export PRIMARY_ALARM_NAME
    PRIMARY_ALARM_NAME=$(jq -r '.resources.cloudwatch_alarms.primary_alarm_name // ""' "$STATE_FILE")
    
    export SECONDARY_ALARM_NAME
    SECONDARY_ALARM_NAME=$(jq -r '.resources.cloudwatch_alarms.secondary_alarm_name // ""' "$STATE_FILE")
    
    info "Deployment state loaded successfully"
    log "Configuration:"
    log "  Account ID: $AWS_ACCOUNT_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
    log "  Primary Region: $PRIMARY_REGION"
    log "  Secondary Region: $SECONDARY_REGION"
    log "  Domain: $DOMAIN_NAME"
    
    return 0
}

safe_delete() {
    local description="$1"
    local command="$2"
    
    info "Attempting to delete: $description"
    
    if eval "$command" 2>/dev/null; then
        success "Deleted: $description"
        return 0
    else
        warn "Failed to delete or not found: $description"
        return 1
    fi
}

wait_for_deletion() {
    local check_command="$1"
    local description="$2"
    local max_attempts="${3:-30}"
    local wait_time="${4:-10}"
    
    info "Waiting for $description to be deleted..."
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if ! eval "$check_command" &>/dev/null; then
            success "$description deleted successfully"
            return 0
        fi
        
        info "Attempt $attempt/$max_attempts - waiting ${wait_time}s for deletion..."
        sleep "$wait_time"
        ((attempt++))
    done
    
    warn "$description deletion did not complete within expected time"
    return 1
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

delete_route53_resources() {
    progress "Removing Route53 resources"
    
    if [[ -n "$HOSTED_ZONE_ID" && -n "$DOMAIN_NAME" && -n "$PRIMARY_SERVICE_DNS" && -n "$SECONDARY_SERVICE_DNS" ]]; then
        # Delete DNS records first
        info "Deleting DNS failover records..."
        
        # Delete primary DNS record
        safe_delete "Primary DNS record" "aws route53 change-resource-record-sets \
            --hosted-zone-id '$HOSTED_ZONE_ID' \
            --change-batch '{
                \"Changes\": [{
                    \"Action\": \"DELETE\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"$DOMAIN_NAME\",
                        \"Type\": \"CNAME\",
                        \"SetIdentifier\": \"primary\",
                        \"Failover\": \"PRIMARY\",
                        \"TTL\": 60,
                        \"ResourceRecords\": [{\"Value\": \"$PRIMARY_SERVICE_DNS\"}],
                        \"HealthCheckId\": \"$PRIMARY_HEALTH_CHECK_ID\"
                    }
                }]
            }'"
        
        # Delete secondary DNS record
        safe_delete "Secondary DNS record" "aws route53 change-resource-record-sets \
            --hosted-zone-id '$HOSTED_ZONE_ID' \
            --change-batch '{
                \"Changes\": [{
                    \"Action\": \"DELETE\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"$DOMAIN_NAME\",
                        \"Type\": \"CNAME\",
                        \"SetIdentifier\": \"secondary\",
                        \"Failover\": \"SECONDARY\",
                        \"TTL\": 60,
                        \"ResourceRecords\": [{\"Value\": \"$SECONDARY_SERVICE_DNS\"}]
                    }
                }]
            }'"
    fi
    
    # Delete health checks
    if [[ -n "$PRIMARY_HEALTH_CHECK_ID" ]]; then
        safe_delete "Primary health check" "aws route53 delete-health-check --health-check-id '$PRIMARY_HEALTH_CHECK_ID'"
    fi
    
    if [[ -n "$SECONDARY_HEALTH_CHECK_ID" ]]; then
        safe_delete "Secondary health check" "aws route53 delete-health-check --health-check-id '$SECONDARY_HEALTH_CHECK_ID'"
    fi
    
    # Delete hosted zone
    if [[ -n "$HOSTED_ZONE_ID" ]]; then
        safe_delete "Hosted zone" "aws route53 delete-hosted-zone --id '$HOSTED_ZONE_ID'"
    fi
    
    success "Route53 resources cleanup completed"
}

delete_vpc_lattice_resources() {
    progress "Removing VPC Lattice resources"
    
    # Delete service network associations first
    if [[ -n "$PRIMARY_SERVICE_NETWORK_ID" && -n "$PRIMARY_SERVICE_ID" ]]; then
        info "Finding and deleting primary service network association..."
        local primary_association_id
        primary_association_id=$(aws vpc-lattice list-service-network-service-associations \
            --region "$PRIMARY_REGION" \
            --service-network-identifier "$PRIMARY_SERVICE_NETWORK_ID" \
            --query 'items[0].id' --output text 2>/dev/null || echo "")
        
        if [[ -n "$primary_association_id" && "$primary_association_id" != "None" ]]; then
            safe_delete "Primary service network association" \
                "aws vpc-lattice delete-service-network-service-association \
                --region '$PRIMARY_REGION' \
                --service-network-service-association-identifier '$primary_association_id'"
        fi
    fi
    
    if [[ -n "$SECONDARY_SERVICE_NETWORK_ID" && -n "$SECONDARY_SERVICE_ID" ]]; then
        info "Finding and deleting secondary service network association..."
        local secondary_association_id
        secondary_association_id=$(aws vpc-lattice list-service-network-service-associations \
            --region "$SECONDARY_REGION" \
            --service-network-identifier "$SECONDARY_SERVICE_NETWORK_ID" \
            --query 'items[0].id' --output text 2>/dev/null || echo "")
        
        if [[ -n "$secondary_association_id" && "$secondary_association_id" != "None" ]]; then
            safe_delete "Secondary service network association" \
                "aws vpc-lattice delete-service-network-service-association \
                --region '$SECONDARY_REGION' \
                --service-network-service-association-identifier '$secondary_association_id'"
        fi
    fi
    
    # Wait a moment for associations to be deleted
    sleep 10
    
    # Delete services
    if [[ -n "$PRIMARY_SERVICE_ID" ]]; then
        safe_delete "Primary VPC Lattice service" \
            "aws vpc-lattice delete-service --region '$PRIMARY_REGION' --service-identifier '$PRIMARY_SERVICE_ID'"
    fi
    
    if [[ -n "$SECONDARY_SERVICE_ID" ]]; then
        safe_delete "Secondary VPC Lattice service" \
            "aws vpc-lattice delete-service --region '$SECONDARY_REGION' --service-identifier '$SECONDARY_SERVICE_ID'"
    fi
    
    # Delete target groups
    if [[ -n "$PRIMARY_TARGET_GROUP_ID" ]]; then
        safe_delete "Primary target group" \
            "aws vpc-lattice delete-target-group --region '$PRIMARY_REGION' --target-group-identifier '$PRIMARY_TARGET_GROUP_ID'"
    fi
    
    if [[ -n "$SECONDARY_TARGET_GROUP_ID" ]]; then
        safe_delete "Secondary target group" \
            "aws vpc-lattice delete-target-group --region '$SECONDARY_REGION' --target-group-identifier '$SECONDARY_TARGET_GROUP_ID'"
    fi
    
    # Delete service networks
    if [[ -n "$PRIMARY_SERVICE_NETWORK_ID" ]]; then
        safe_delete "Primary service network" \
            "aws vpc-lattice delete-service-network --region '$PRIMARY_REGION' --service-network-identifier '$PRIMARY_SERVICE_NETWORK_ID'"
    fi
    
    if [[ -n "$SECONDARY_SERVICE_NETWORK_ID" ]]; then
        safe_delete "Secondary service network" \
            "aws vpc-lattice delete-service-network --region '$SECONDARY_REGION' --service-network-identifier '$SECONDARY_SERVICE_NETWORK_ID'"
    fi
    
    success "VPC Lattice resources cleanup completed"
}

delete_lambda_functions() {
    progress "Removing Lambda functions"
    
    if [[ -n "$PRIMARY_FUNCTION_NAME" ]]; then
        safe_delete "Primary Lambda function" \
            "aws lambda delete-function --region '$PRIMARY_REGION' --function-name '$PRIMARY_FUNCTION_NAME'"
    fi
    
    if [[ -n "$SECONDARY_FUNCTION_NAME" ]]; then
        safe_delete "Secondary Lambda function" \
            "aws lambda delete-function --region '$SECONDARY_REGION' --function-name '$SECONDARY_FUNCTION_NAME'"
    fi
    
    success "Lambda functions cleanup completed"
}

delete_iam_resources() {
    progress "Removing IAM resources"
    
    if [[ -n "$IAM_ROLE_NAME" ]]; then
        # Detach policies first
        info "Detaching policies from IAM role..."
        safe_delete "Lambda basic execution policy" \
            "aws iam detach-role-policy \
            --role-name '$IAM_ROLE_NAME' \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        # Delete role
        safe_delete "IAM role" "aws iam delete-role --role-name '$IAM_ROLE_NAME'"
    fi
    
    success "IAM resources cleanup completed"
}

delete_cloudwatch_alarms() {
    progress "Removing CloudWatch alarms"
    
    if [[ -n "$PRIMARY_ALARM_NAME" ]]; then
        safe_delete "Primary CloudWatch alarm" \
            "aws cloudwatch delete-alarms --region '$PRIMARY_REGION' --alarm-names '$PRIMARY_ALARM_NAME'"
    fi
    
    if [[ -n "$SECONDARY_ALARM_NAME" ]]; then
        safe_delete "Secondary CloudWatch alarm" \
            "aws cloudwatch delete-alarms --region '$SECONDARY_REGION' --alarm-names '$SECONDARY_ALARM_NAME'"
    fi
    
    success "CloudWatch alarms cleanup completed"
}

delete_vpcs() {
    progress "Removing VPCs (optional - only if created by deployment)"
    
    # Note: Only delete VPCs if they were created by our deployment
    # Check if VPCs have our specific tags
    
    if [[ -n "$PRIMARY_VPC_ID" ]]; then
        info "Checking if primary VPC should be deleted..."
        local vpc_tags
        vpc_tags=$(aws ec2 describe-tags \
            --region "$PRIMARY_REGION" \
            --filters "Name=resource-id,Values=$PRIMARY_VPC_ID" "Name=key,Values=Purpose" \
            --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
        
        if [[ "$vpc_tags" == "cross-region-failover" ]]; then
            safe_delete "Primary VPC" "aws ec2 delete-vpc --region '$PRIMARY_REGION' --vpc-id '$PRIMARY_VPC_ID'"
        else
            info "Skipping primary VPC deletion (not created by this deployment)"
        fi
    fi
    
    if [[ -n "$SECONDARY_VPC_ID" ]]; then
        info "Checking if secondary VPC should be deleted..."
        local vpc_tags
        vpc_tags=$(aws ec2 describe-tags \
            --region "$SECONDARY_REGION" \
            --filters "Name=resource-id,Values=$SECONDARY_VPC_ID" "Name=key,Values=Purpose" \
            --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
        
        if [[ "$vpc_tags" == "cross-region-failover" ]]; then
            safe_delete "Secondary VPC" "aws ec2 delete-vpc --region '$SECONDARY_REGION' --vpc-id '$SECONDARY_VPC_ID'"
        else
            info "Skipping secondary VPC deletion (not created by this deployment)"
        fi
    fi
    
    success "VPC cleanup completed"
}

cleanup_local_files() {
    progress "Cleaning up local files"
    
    # Remove temporary files
    local files_to_remove=(
        "function.zip"
        "lambda-trust-policy.json"
        "health-check-function.py"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed local file: $file"
        fi
    done
    
    success "Local files cleanup completed"
}

verify_cleanup() {
    progress "Verifying resource cleanup"
    
    local cleanup_errors=0
    
    # Check Lambda functions
    if [[ -n "$PRIMARY_FUNCTION_NAME" ]]; then
        if aws lambda get-function --region "$PRIMARY_REGION" --function-name "$PRIMARY_FUNCTION_NAME" &>/dev/null; then
            error "Primary Lambda function still exists"
            ((cleanup_errors++))
        fi
    fi
    
    if [[ -n "$SECONDARY_FUNCTION_NAME" ]]; then
        if aws lambda get-function --region "$SECONDARY_REGION" --function-name "$SECONDARY_FUNCTION_NAME" &>/dev/null; then
            error "Secondary Lambda function still exists"
            ((cleanup_errors++))
        fi
    fi
    
    # Check Route53 health checks
    if [[ -n "$PRIMARY_HEALTH_CHECK_ID" ]]; then
        if aws route53 get-health-check --health-check-id "$PRIMARY_HEALTH_CHECK_ID" &>/dev/null; then
            error "Primary health check still exists"
            ((cleanup_errors++))
        fi
    fi
    
    if [[ -n "$SECONDARY_HEALTH_CHECK_ID" ]]; then
        if aws route53 get-health-check --health-check-id "$SECONDARY_HEALTH_CHECK_ID" &>/dev/null; then
            error "Secondary health check still exists"
            ((cleanup_errors++))
        fi
    fi
    
    # Check IAM role
    if [[ -n "$IAM_ROLE_NAME" ]]; then
        if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
            error "IAM role still exists"
            ((cleanup_errors++))
        fi
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        success "Resource cleanup verification passed"
    else
        warn "Some resources may still exist ($cleanup_errors issues found)"
        warn "You may need to manually clean up remaining resources"
    fi
    
    return $cleanup_errors
}

remove_deployment_state() {
    progress "Removing deployment state file"
    
    if [[ -f "$STATE_FILE" ]]; then
        # Create backup before removing
        local backup_file="${STATE_FILE}.backup.${TIMESTAMP}"
        cp "$STATE_FILE" "$backup_file"
        rm -f "$STATE_FILE"
        success "Deployment state file removed (backup: $backup_file)"
    else
        info "Deployment state file not found"
    fi
    
    success "State cleanup completed"
}

# =============================================================================
# MAIN CLEANUP FLOW
# =============================================================================

main() {
    info "Starting Cross-Region Service Failover cleanup"
    info "Script: $SCRIPT_NAME"
    info "Timestamp: $TIMESTAMP"
    info "Log file: $LOG_FILE"
    
    # Load deployment state
    if ! load_deployment_state; then
        error "Failed to load deployment state"
        warn "Continuing with manual cleanup (some resources may be missed)"
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Run cleanup steps in reverse order of creation
    delete_route53_resources
    delete_vpc_lattice_resources
    delete_lambda_functions
    delete_iam_resources
    delete_cloudwatch_alarms
    delete_vpcs
    cleanup_local_files
    verify_cleanup
    remove_deployment_state
    
    # Display final status
    echo ""
    success "==================================================================="
    success "CLEANUP COMPLETED"
    success "==================================================================="
    echo ""
    info "Cleanup Summary:"
    info "  All AWS resources have been deleted"
    info "  Local files have been cleaned up"
    info "  Deployment state file has been removed"
    echo ""
    warn "IMPORTANT NOTES:"
    warn "1. Some DNS changes may take time to propagate globally"
    warn "2. Check your AWS bill to ensure no unexpected charges"
    warn "3. If you used a real domain, update your DNS nameservers"
    warn "4. Review CloudWatch logs for any remaining log groups"
    echo ""
    info "Log file: $LOG_FILE"
    success "Cleanup completed at $(date)"
}

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Cross-Region Service Failover Cleanup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h           Show this help message"
    echo "  FORCE_DESTROY=true   Skip confirmation prompt"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_DESTROY        Set to 'true' to skip confirmation"
    echo ""
    echo "Examples:"
    echo "  $0                   # Interactive cleanup with confirmation"
    echo "  FORCE_DESTROY=true $0   # Automated cleanup without confirmation"
    echo ""
    echo "This script will:"
    echo "  1. Load deployment state from deployment_state.json"
    echo "  2. Delete Route53 resources (DNS records, health checks, hosted zone)"
    echo "  3. Delete VPC Lattice resources (services, networks, target groups)"
    echo "  4. Delete Lambda functions"
    echo "  5. Delete IAM roles and policies"
    echo "  6. Delete CloudWatch alarms"
    echo "  7. Delete VPCs (if created by deployment)"
    echo "  8. Clean up local files"
    echo "  9. Verify cleanup completion"
    echo "  10. Remove deployment state file"
    exit 0
fi

# Run main function
main "$@"