#!/bin/bash

#####################################################################
# AWS Application Health Monitoring with VPC Lattice and CloudWatch
# Destruction Script
# 
# This script safely removes all resources created by the deployment
# script, including VPC Lattice resources, CloudWatch alarms,
# Lambda functions, SNS topics, and IAM roles.
#####################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destruction.log"
readonly RESOURCE_FILE="${SCRIPT_DIR}/deployed_resources.env"

#####################################################################
# Utility Functions
#####################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

confirm_destruction() {
    local force_destroy="$1"
    
    if [[ "$force_destroy" == "true" ]]; then
        log "INFO" "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log "WARN" "⚠️  WARNING: This will destroy ALL resources created by the deployment script!"
    log "WARN" "This action cannot be undone."
    echo
    
    if [[ -f "$RESOURCE_FILE" ]]; then
        source "$RESOURCE_FILE" 2>/dev/null || true
        log "INFO" "Resources to be destroyed:"
        [[ -n "${SERVICE_NETWORK_NAME:-}" ]] && log "INFO" "  - Service Network: ${SERVICE_NETWORK_NAME}"
        [[ -n "${SERVICE_NAME:-}" ]] && log "INFO" "  - Service: ${SERVICE_NAME}"
        [[ -n "${TARGET_GROUP_NAME:-}" ]] && log "INFO" "  - Target Group: ${TARGET_GROUP_NAME}"
        [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && log "INFO" "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        [[ -n "${SNS_TOPIC_NAME:-}" ]] && log "INFO" "  - SNS Topic: ${SNS_TOPIC_NAME}"
        [[ -n "${IAM_ROLE_NAME:-}" ]] && log "INFO" "  - IAM Role: ${IAM_ROLE_NAME}"
        [[ -n "${IAM_POLICY_NAME:-}" ]] && log "INFO" "  - IAM Policy: ${IAM_POLICY_NAME}"
        [[ -n "${DASHBOARD_NAME:-}" ]] && log "INFO" "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
        echo
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Destruction cancelled by user"
        exit 0
    fi
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local max_attempts=30
    local attempt=1
    
    log "INFO" "Waiting for $resource_type $resource_id to be deleted..."
    
    while [[ $attempt -le $max_attempts ]]; do
        local exists=true
        
        case $resource_type in
            "service-network")
                aws vpc-lattice get-service-network \
                    --service-network-identifier "$resource_id" \
                    &>/dev/null || exists=false
                ;;
            "service")
                aws vpc-lattice get-service \
                    --service-identifier "$resource_id" \
                    &>/dev/null || exists=false
                ;;
            "target-group")
                aws vpc-lattice get-target-group \
                    --target-group-identifier "$resource_id" \
                    &>/dev/null || exists=false
                ;;
            "lambda")
                aws lambda get-function \
                    --function-name "$resource_id" \
                    &>/dev/null || exists=false
                ;;
            "sns-topic")
                aws sns get-topic-attributes \
                    --topic-arn "$resource_id" \
                    &>/dev/null || exists=false
                ;;
        esac
        
        if [[ "$exists" == "false" ]]; then
            log "INFO" "$resource_type $resource_id has been deleted"
            return 0
        fi
        
        log "DEBUG" "Waiting for $resource_type deletion (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    log "WARN" "Timeout waiting for $resource_type $resource_id to be deleted"
    return 1
}

safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_name="${3:-}"
    
    log "INFO" "Attempting to delete $resource_type: $resource_name"
    
    if eval "$delete_command" 2>/dev/null; then
        log "INFO" "✅ Successfully deleted $resource_type: $resource_name"
        return 0
    else
        local exit_code=$?
        log "WARN" "⚠️  Failed to delete $resource_type: $resource_name (exit code: $exit_code)"
        return $exit_code
    fi
}

#####################################################################
# Resource Cleanup Functions
#####################################################################

cleanup_cloudwatch_resources() {
    log "INFO" "Cleaning up CloudWatch resources..."
    
    if [[ -n "${SERVICE_NAME:-}" ]]; then
        # Delete CloudWatch alarms
        local alarms=(
            "VPCLattice-${SERVICE_NAME}-High5XXRate"
            "VPCLattice-${SERVICE_NAME}-RequestTimeouts"
            "VPCLattice-${SERVICE_NAME}-HighResponseTime"
        )
        
        for alarm in "${alarms[@]}"; do
            safe_delete "CloudWatch Alarm" \
                "aws cloudwatch delete-alarms --alarm-names \"$alarm\"" \
                "$alarm"
        done
    fi
    
    # Delete CloudWatch dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        safe_delete "CloudWatch Dashboard" \
            "aws cloudwatch delete-dashboards --dashboard-names \"$DASHBOARD_NAME\"" \
            "$DASHBOARD_NAME"
    fi
    
    log "INFO" "CloudWatch cleanup completed"
}

cleanup_lambda_resources() {
    log "INFO" "Cleaning up Lambda and IAM resources..."
    
    # Delete Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        safe_delete "Lambda Function" \
            "aws lambda delete-function --function-name \"$LAMBDA_FUNCTION_NAME\"" \
            "$LAMBDA_FUNCTION_NAME"
        
        wait_for_deletion "lambda" "$LAMBDA_FUNCTION_NAME"
    fi
    
    # Detach and delete IAM policies
    if [[ -n "${IAM_ROLE_NAME:-}" ]] && [[ -n "${POLICY_ARN:-}" ]]; then
        safe_delete "IAM Policy Attachment" \
            "aws iam detach-role-policy --role-name \"$IAM_ROLE_NAME\" --policy-arn \"$POLICY_ARN\"" \
            "$POLICY_ARN"
        
        safe_delete "IAM Basic Policy Attachment" \
            "aws iam detach-role-policy --role-name \"$IAM_ROLE_NAME\" --policy-arn \"arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole\"" \
            "AWSLambdaBasicExecutionRole"
        
        # Delete custom policy
        safe_delete "IAM Policy" \
            "aws iam delete-policy --policy-arn \"$POLICY_ARN\"" \
            "$IAM_POLICY_NAME"
        
        # Delete IAM role
        safe_delete "IAM Role" \
            "aws iam delete-role --role-name \"$IAM_ROLE_NAME\"" \
            "$IAM_ROLE_NAME"
    fi
    
    log "INFO" "Lambda and IAM cleanup completed"
}

cleanup_sns_resources() {
    log "INFO" "Cleaning up SNS resources..."
    
    # Delete SNS topic (this automatically deletes all subscriptions)
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        safe_delete "SNS Topic" \
            "aws sns delete-topic --topic-arn \"$SNS_TOPIC_ARN\"" \
            "$SNS_TOPIC_NAME"
        
        wait_for_deletion "sns-topic" "$SNS_TOPIC_ARN"
    fi
    
    log "INFO" "SNS cleanup completed"
}

cleanup_vpc_lattice_resources() {
    log "INFO" "Cleaning up VPC Lattice resources..."
    
    # Delete service network service association
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]] && [[ -n "${SERVICE_ID:-}" ]]; then
        local service_association_id
        service_association_id=$(aws vpc-lattice list-service-network-service-associations \
            --service-network-identifier "$SERVICE_NETWORK_ID" \
            --query "items[?serviceId=='${SERVICE_ID}'].id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$service_association_id" && "$service_association_id" != "None" ]]; then
            safe_delete "Service Network Association" \
                "aws vpc-lattice delete-service-network-service-association --service-network-service-association-identifier \"$service_association_id\"" \
                "$service_association_id"
        fi
    fi
    
    # Delete VPC association
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]] && [[ -n "${VPC_ID:-}" ]]; then
        local vpc_association_id
        vpc_association_id=$(aws vpc-lattice list-service-network-vpc-associations \
            --service-network-identifier "$SERVICE_NETWORK_ID" \
            --query "items[?vpcId=='${VPC_ID}'].id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$vpc_association_id" && "$vpc_association_id" != "None" ]]; then
            safe_delete "VPC Network Association" \
                "aws vpc-lattice delete-service-network-vpc-association --service-network-vpc-association-identifier \"$vpc_association_id\"" \
                "$vpc_association_id"
        fi
    fi
    
    # Delete VPC Lattice service
    if [[ -n "${SERVICE_ID:-}" ]]; then
        safe_delete "VPC Lattice Service" \
            "aws vpc-lattice delete-service --service-identifier \"$SERVICE_ID\"" \
            "$SERVICE_NAME"
        
        wait_for_deletion "service" "$SERVICE_ID"
    fi
    
    # Delete target group
    if [[ -n "${TARGET_GROUP_ID:-}" ]]; then
        safe_delete "Target Group" \
            "aws vpc-lattice delete-target-group --target-group-identifier \"$TARGET_GROUP_ID\"" \
            "$TARGET_GROUP_NAME"
        
        wait_for_deletion "target-group" "$TARGET_GROUP_ID"
    fi
    
    # Delete service network (last, as it depends on other resources)
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
        safe_delete "Service Network" \
            "aws vpc-lattice delete-service-network --service-network-identifier \"$SERVICE_NETWORK_ID\"" \
            "$SERVICE_NETWORK_NAME"
        
        wait_for_deletion "service-network" "$SERVICE_NETWORK_ID"
    fi
    
    log "INFO" "VPC Lattice cleanup completed"
}

cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # Remove temporary files
    for file in lambda_function.py lambda_function.zip response.json policy_arn.txt; do
        if [[ -f "${SCRIPT_DIR}/$file" ]]; then
            rm -f "${SCRIPT_DIR}/$file"
            log "INFO" "Removed local file: $file"
        fi
    done
    
    log "INFO" "Local cleanup completed"
}

#####################################################################
# Validation
#####################################################################

validate_cleanup() {
    log "INFO" "Validating resource cleanup..."
    
    local cleanup_success=true
    
    # Check if key resources still exist
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
        if aws vpc-lattice get-service-network --service-network-identifier "$SERVICE_NETWORK_ID" &>/dev/null; then
            log "WARN" "⚠️  Service network still exists: $SERVICE_NETWORK_ID"
            cleanup_success=false
        else
            log "INFO" "✅ Service network successfully deleted"
        fi
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            log "WARN" "⚠️  Lambda function still exists: $LAMBDA_FUNCTION_NAME"
            cleanup_success=false
        else
            log "INFO" "✅ Lambda function successfully deleted"
        fi
    fi
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            log "WARN" "⚠️  SNS topic still exists: $SNS_TOPIC_ARN"
            cleanup_success=false
        else
            log "INFO" "✅ SNS topic successfully deleted"
        fi
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log "INFO" "✅ All resources successfully cleaned up"
    else
        log "WARN" "⚠️  Some resources may still exist. Check AWS console for manual cleanup."
    fi
    
    return $([[ "$cleanup_success" == "true" ]] && echo 0 || echo 1)
}

#####################################################################
# Main Destruction Function
#####################################################################

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --force         Skip confirmation prompt"
    echo "  -h, --help          Show this help message"
    echo "  --dry-run           Show what would be destroyed without executing"
    echo "  --partial RESOURCE  Only destroy specific resource type"
    echo "                      Options: cloudwatch, lambda, sns, vpc-lattice, local"
    echo
    echo "Examples:"
    echo "  $0                          # Interactive destruction with confirmation"
    echo "  $0 --force                  # Destroy without confirmation"
    echo "  $0 --dry-run                # Show what would be destroyed"
    echo "  $0 --partial cloudwatch     # Only destroy CloudWatch resources"
}

main() {
    local force_destroy=false
    local dry_run=false
    local partial_cleanup=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_destroy=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --partial)
                partial_cleanup="$2"
                shift 2
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize log file
    echo "# VPC Lattice Health Monitoring Destruction Log" > "$LOG_FILE"
    echo "# Started at: $(date)" >> "$LOG_FILE"
    
    log "INFO" "Starting VPC Lattice Health Monitoring cleanup..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Check if resource file exists
    if [[ ! -f "$RESOURCE_FILE" ]]; then
        log "WARN" "Resource file not found: $RESOURCE_FILE"
        log "WARN" "Attempting to find resources by name patterns..."
        
        # Try to find resources by common naming patterns
        if command -v aws &> /dev/null; then
            log "INFO" "Searching for resources to clean up..."
            # This would require additional logic to discover resources
            log "WARN" "Manual resource discovery not implemented. Please check AWS console."
        fi
        
        if [[ "$force_destroy" == "false" ]]; then
            log "ERROR" "Cannot proceed without resource information"
            exit 1
        fi
    else
        # Load resource information
        source "$RESOURCE_FILE"
        log "INFO" "Loaded resource information from $RESOURCE_FILE"
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log "INFO" "DRY RUN MODE - No resources will be destroyed"
        log "INFO" "Resources that would be destroyed:"
        [[ -n "${SERVICE_NETWORK_NAME:-}" ]] && log "INFO" "  - Service Network: ${SERVICE_NETWORK_NAME}"
        [[ -n "${SERVICE_NAME:-}" ]] && log "INFO" "  - Service: ${SERVICE_NAME}"
        [[ -n "${TARGET_GROUP_NAME:-}" ]] && log "INFO" "  - Target Group: ${TARGET_GROUP_NAME}"
        [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && log "INFO" "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        [[ -n "${SNS_TOPIC_NAME:-}" ]] && log "INFO" "  - SNS Topic: ${SNS_TOPIC_NAME}"
        [[ -n "${IAM_ROLE_NAME:-}" ]] && log "INFO" "  - IAM Role: ${IAM_ROLE_NAME}"
        [[ -n "${DASHBOARD_NAME:-}" ]] && log "INFO" "  - CloudWatch Dashboard: ${DASHBOARD_NAME}"
        exit 0
    fi
    
    # Confirm destruction unless forced
    confirm_destruction "$force_destroy"
    
    log "INFO" "Starting resource cleanup..."
    
    # Execute cleanup based on partial or full cleanup
    case "$partial_cleanup" in
        "cloudwatch")
            cleanup_cloudwatch_resources
            ;;
        "lambda")
            cleanup_lambda_resources
            ;;
        "sns")
            cleanup_sns_resources
            ;;
        "vpc-lattice")
            cleanup_vpc_lattice_resources
            ;;
        "local")
            cleanup_local_files
            ;;
        "")
            # Full cleanup in reverse order of creation
            cleanup_cloudwatch_resources
            cleanup_lambda_resources
            cleanup_sns_resources
            cleanup_vpc_lattice_resources
            cleanup_local_files
            ;;
        *)
            log "ERROR" "Unknown partial cleanup option: $partial_cleanup"
            show_usage
            exit 1
            ;;
    esac
    
    # Validate cleanup
    if [[ -z "$partial_cleanup" ]]; then
        validate_cleanup
        
        # Remove resource file after successful cleanup
        if [[ -f "$RESOURCE_FILE" ]]; then
            rm -f "$RESOURCE_FILE"
            log "INFO" "Removed resource file: $RESOURCE_FILE"
        fi
    fi
    
    log "INFO" "🎉 Cleanup completed!"
    log "INFO" ""
    log "INFO" "Summary:"
    if [[ -z "$partial_cleanup" ]]; then
        log "INFO" "  - All VPC Lattice Health Monitoring resources have been removed"
        log "INFO" "  - CloudWatch alarms and dashboard deleted"
        log "INFO" "  - Lambda function and IAM resources deleted"
        log "INFO" "  - SNS topic and subscriptions deleted"
        log "INFO" "  - VPC Lattice service network and components deleted"
    else
        log "INFO" "  - Partial cleanup completed for: $partial_cleanup"
    fi
    log "INFO" ""
    log "INFO" "Please verify in the AWS console that all resources have been removed."
    log "INFO" "Check for any remaining resources that may incur charges."
}

# Execute main function with all arguments
main "$@"