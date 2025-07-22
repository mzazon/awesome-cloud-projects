#!/bin/bash

# =============================================================================
# Amazon Timestream Time-Series Data Solution - Cleanup Script
# =============================================================================
#
# This script safely removes all resources created by the deployment script:
# - CloudWatch alarms
# - IoT Core rules
# - Lambda functions
# - IAM roles and policies
# - Timestream tables and databases
#
# Version: 1.0
# Author: AWS Recipe Generator
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# =============================================================================
# Configuration and Variables
# =============================================================================

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}
VERBOSE=${VERBOSE:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resource identification
RESOURCE_SUFFIX=${RESOURCE_SUFFIX:-}
DATABASE_NAME=""
TABLE_NAME="sensor-data"
LAMBDA_FUNCTION_NAME=""
IOT_RULE_NAME=""

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

confirm_action() {
    local message="$1"
    
    if $FORCE; then
        log_warning "FORCE mode enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${YELLOW}${message}${NC}"
    read -p "Do you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local check_command=$3
    local max_attempts=${4:-30}
    local sleep_time=${5:-10}
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be deleted..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if ! eval "$check_command" &>/dev/null; then
            log_success "${resource_type} '${resource_name}' has been deleted"
            return 0
        fi
        
        if [[ $i -eq $max_attempts ]]; then
            log_error "Timeout waiting for ${resource_type} '${resource_name}' deletion"
            return 1
        fi
        
        sleep $sleep_time
    done
}

# =============================================================================
# Resource Discovery
# =============================================================================

discover_resources() {
    log_info "Discovering deployed resources..."
    
    # Get AWS account information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "AWS Region: ${AWS_REGION}"
    
    # If suffix is provided, construct resource names
    if [[ -n "$RESOURCE_SUFFIX" ]]; then
        DATABASE_NAME="iot-timeseries-db-${RESOURCE_SUFFIX}"
        LAMBDA_FUNCTION_NAME="timestream-data-ingestion-${RESOURCE_SUFFIX}"
        IOT_RULE_NAME="timestream-iot-rule-${RESOURCE_SUFFIX}"
        
        log_info "Using provided suffix: ${RESOURCE_SUFFIX}"
    else
        # Try to discover resources by pattern
        log_info "Attempting to discover resources automatically..."
        
        # Find Timestream databases matching pattern
        local databases=$(aws timestream-write list-databases \
            --query 'Databases[?starts_with(DatabaseName, `iot-timeseries-db-`)].DatabaseName' \
            --output text)
        
        if [[ -n "$databases" ]]; then
            # Use the first matching database
            DATABASE_NAME=$(echo "$databases" | head -1)
            RESOURCE_SUFFIX=${DATABASE_NAME#iot-timeseries-db-}
            LAMBDA_FUNCTION_NAME="timestream-data-ingestion-${RESOURCE_SUFFIX}"
            IOT_RULE_NAME="timestream-iot-rule-${RESOURCE_SUFFIX}"
            
            log_info "Discovered database: ${DATABASE_NAME}"
            log_info "Inferred suffix: ${RESOURCE_SUFFIX}"
        else
            log_error "No Timestream databases found matching pattern 'iot-timeseries-db-*'"
            log_error "Please specify the resource suffix using --suffix option"
            exit 1
        fi
    fi
    
    log_info "Target resources:"
    log_info "  Database: ${DATABASE_NAME}"
    log_info "  Table: ${TABLE_NAME}"
    log_info "  Lambda: ${LAMBDA_FUNCTION_NAME}"
    log_info "  IoT Rule: ${IOT_RULE_NAME}"
}

list_resources_to_delete() {
    log_info "Scanning for resources to delete..."
    
    local resources_found=false
    
    # Check CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms \
        --alarm-names "Timestream-IngestionRate-${DATABASE_NAME}" "Timestream-QueryLatency-${DATABASE_NAME}" \
        --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || true)
    
    if [[ -n "$alarms" ]]; then
        log_info "CloudWatch Alarms to delete:"
        for alarm in $alarms; do
            log_info "  - $alarm"
        done
        resources_found=true
    fi
    
    # Check IoT rule
    if aws iot get-topic-rule --rule-name "$IOT_RULE_NAME" &>/dev/null; then
        log_info "IoT Rule to delete:"
        log_info "  - $IOT_RULE_NAME"
        resources_found=true
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_info "Lambda Function to delete:"
        log_info "  - $LAMBDA_FUNCTION_NAME"
        resources_found=true
    fi
    
    # Check IAM roles
    local roles=("${LAMBDA_FUNCTION_NAME}-role" "${IOT_RULE_NAME}-role")
    local existing_roles=()
    
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            existing_roles+=("$role")
        fi
    done
    
    if [[ ${#existing_roles[@]} -gt 0 ]]; then
        log_info "IAM Roles to delete:"
        for role in "${existing_roles[@]}"; do
            log_info "  - $role"
        done
        resources_found=true
    fi
    
    # Check IAM policies
    local policies=("${LAMBDA_FUNCTION_NAME}-timestream-policy" "${IOT_RULE_NAME}-timestream-policy")
    local existing_policies=()
    
    for policy in "${policies[@]}"; do
        if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy" &>/dev/null; then
            existing_policies+=("$policy")
        fi
    done
    
    if [[ ${#existing_policies[@]} -gt 0 ]]; then
        log_info "IAM Policies to delete:"
        for policy in "${existing_policies[@]}"; do
            log_info "  - $policy"
        done
        resources_found=true
    fi
    
    # Check Timestream table
    if aws timestream-write describe-table \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME" &>/dev/null; then
        log_info "Timestream Table to delete:"
        log_info "  - ${DATABASE_NAME}.${TABLE_NAME}"
        resources_found=true
    fi
    
    # Check Timestream database
    if aws timestream-write describe-database --database-name "$DATABASE_NAME" &>/dev/null; then
        log_info "Timestream Database to delete:"
        log_info "  - $DATABASE_NAME"
        resources_found=true
    fi
    
    if ! $resources_found; then
        log_warning "No resources found to delete"
        exit 0
    fi
    
    return 0
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    local alarms=("Timestream-IngestionRate-${DATABASE_NAME}" "Timestream-QueryLatency-${DATABASE_NAME}")
    local existing_alarms=()
    
    # Check which alarms exist
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text &>/dev/null; then
            existing_alarms+=("$alarm")
        fi
    done
    
    if [[ ${#existing_alarms[@]} -eq 0 ]]; then
        log_info "No CloudWatch alarms found to delete"
        return 0
    fi
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would delete CloudWatch alarms: ${existing_alarms[*]}"
        return 0
    fi
    
    aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}"
    log_success "Deleted CloudWatch alarms"
}

delete_iot_rule() {
    log_info "Deleting IoT Core rule..."
    
    if ! aws iot get-topic-rule --rule-name "$IOT_RULE_NAME" &>/dev/null; then
        log_info "IoT rule '${IOT_RULE_NAME}' not found"
        return 0
    fi
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would delete IoT rule: ${IOT_RULE_NAME}"
        return 0
    fi
    
    aws iot delete-topic-rule --rule-name "$IOT_RULE_NAME"
    log_success "Deleted IoT Core rule: ${IOT_RULE_NAME}"
}

delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_info "Lambda function '${LAMBDA_FUNCTION_NAME}' not found"
        return 0
    fi
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
    log_success "Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
}

delete_iam_policies() {
    log_info "Deleting IAM policies..."
    
    local policies=("${LAMBDA_FUNCTION_NAME}-timestream-policy" "${IOT_RULE_NAME}-timestream-policy")
    local roles=("${LAMBDA_FUNCTION_NAME}-role" "${IOT_RULE_NAME}-role")
    
    for i in "${!policies[@]}"; do
        local policy="${policies[$i]}"
        local role="${roles[$i]}"
        local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy"
        
        if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
            if $DRY_RUN; then
                log_info "[DRY RUN] Would detach and delete policy: ${policy}"
                continue
            fi
            
            # Detach policy from role if role exists
            if aws iam get-role --role-name "$role" &>/dev/null; then
                log_info "Detaching policy '${policy}' from role '${role}'"
                aws iam detach-role-policy \
                    --role-name "$role" \
                    --policy-arn "$policy_arn" || true
            fi
            
            # Delete policy
            log_info "Deleting policy: ${policy}"
            aws iam delete-policy --policy-arn "$policy_arn"
            log_success "Deleted IAM policy: ${policy}"
        else
            log_info "IAM policy '${policy}' not found"
        fi
    done
}

delete_iam_roles() {
    log_info "Deleting IAM roles..."
    
    local roles=("${LAMBDA_FUNCTION_NAME}-role" "${IOT_RULE_NAME}-role")
    
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            if $DRY_RUN; then
                log_info "[DRY RUN] Would delete IAM role: ${role}"
                continue
            fi
            
            # List and detach any remaining attached policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$role" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || true)
            
            if [[ -n "$attached_policies" ]]; then
                log_warning "Found attached policies for role '${role}', detaching..."
                for policy_arn in $attached_policies; do
                    aws iam detach-role-policy \
                        --role-name "$role" \
                        --policy-arn "$policy_arn" || true
                done
            fi
            
            # Delete role
            log_info "Deleting role: ${role}"
            aws iam delete-role --role-name "$role"
            log_success "Deleted IAM role: ${role}"
        else
            log_info "IAM role '${role}' not found"
        fi
    done
}

delete_timestream_table() {
    log_info "Deleting Timestream table..."
    
    if ! aws timestream-write describe-table \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME" &>/dev/null; then
        log_info "Timestream table '${DATABASE_NAME}.${TABLE_NAME}' not found"
        return 0
    fi
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would delete Timestream table: ${DATABASE_NAME}.${TABLE_NAME}"
        return 0
    fi
    
    aws timestream-write delete-table \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME"
    
    # Wait for table deletion to complete
    wait_for_deletion "table" "${DATABASE_NAME}.${TABLE_NAME}" \
        "aws timestream-write describe-table --database-name '$DATABASE_NAME' --table-name '$TABLE_NAME'"
    
    log_success "Deleted Timestream table: ${DATABASE_NAME}.${TABLE_NAME}"
}

delete_timestream_database() {
    log_info "Deleting Timestream database..."
    
    if ! aws timestream-write describe-database --database-name "$DATABASE_NAME" &>/dev/null; then
        log_info "Timestream database '${DATABASE_NAME}' not found"
        return 0
    fi
    
    # Check if database has any remaining tables
    local tables=$(aws timestream-write list-tables \
        --database-name "$DATABASE_NAME" \
        --query 'Tables[].TableName' \
        --output text 2>/dev/null || true)
    
    if [[ -n "$tables" ]]; then
        log_error "Database '${DATABASE_NAME}' still contains tables: ${tables}"
        log_error "Please delete all tables before deleting the database"
        return 1
    fi
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would delete Timestream database: ${DATABASE_NAME}"
        return 0
    fi
    
    aws timestream-write delete-database --database-name "$DATABASE_NAME"
    
    # Wait for database deletion to complete
    wait_for_deletion "database" "$DATABASE_NAME" \
        "aws timestream-write describe-database --database-name '$DATABASE_NAME'"
    
    log_success "Deleted Timestream database: ${DATABASE_NAME}"
}

delete_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/../lambda"
        "${SCRIPT_DIR}/../tools"
        "${SCRIPT_DIR}/deploy.log"
    )
    
    for file_path in "${files_to_remove[@]}"; do
        if [[ -e "$file_path" ]]; then
            if $DRY_RUN; then
                log_info "[DRY RUN] Would remove: ${file_path}"
            else
                rm -rf "$file_path"
                log_success "Removed: ${file_path}"
            fi
        fi
    done
}

# =============================================================================
# Main Cleanup Functions
# =============================================================================

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

print_cleanup_summary() {
    log_info "==================================================================="
    log_info "                     CLEANUP SUMMARY"
    log_info "==================================================================="
    log_info "The following resources have been deleted:"
    log_info ""
    log_info "✅ CloudWatch Alarms"
    log_info "   - Timestream-IngestionRate-${DATABASE_NAME}"
    log_info "   - Timestream-QueryLatency-${DATABASE_NAME}"
    log_info ""
    log_info "✅ IoT Core Rule"
    log_info "   - ${IOT_RULE_NAME}"
    log_info ""
    log_info "✅ Lambda Function"
    log_info "   - ${LAMBDA_FUNCTION_NAME}"
    log_info ""
    log_info "✅ IAM Policies"
    log_info "   - ${LAMBDA_FUNCTION_NAME}-timestream-policy"
    log_info "   - ${IOT_RULE_NAME}-timestream-policy"
    log_info ""
    log_info "✅ IAM Roles"
    log_info "   - ${LAMBDA_FUNCTION_NAME}-role"
    log_info "   - ${IOT_RULE_NAME}-role"
    log_info ""
    log_info "✅ Timestream Resources"
    log_info "   - Table: ${DATABASE_NAME}.${TABLE_NAME}"
    log_info "   - Database: ${DATABASE_NAME}"
    log_info ""
    log_info "✅ Local Files"
    log_info "   - Lambda function code"
    log_info "   - Data generation tools"
    log_info "   - Deployment logs"
    log_info ""
    log_info "🎉 Cleanup completed successfully!"
    log_info ""
    log_warning "Note: Any data stored in Timestream has been permanently deleted."
    log_warning "If you need to redeploy, run the deploy.sh script again."
    log_info "==================================================================="
}

main() {
    local start_time=$(date +%s)
    
    log_info "Starting Amazon Timestream Time-Series Data Solution cleanup..."
    log_info "Timestamp: $(date)"
    log_info "Log file: ${LOG_FILE}"
    
    if $DRY_RUN; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Validate prerequisites
    validate_prerequisites
    
    # Discover resources
    discover_resources
    
    # List resources to be deleted
    list_resources_to_delete
    
    # Confirm deletion (unless force mode is enabled)
    if ! $DRY_RUN; then
        confirm_action "⚠️  WARNING: This will permanently delete all Timestream data and associated resources!"
    fi
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_alarms
    delete_iot_rule
    delete_lambda_function
    delete_iam_policies
    delete_iam_roles
    delete_timestream_table
    delete_timestream_database
    delete_local_files
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if ! $DRY_RUN; then
        print_cleanup_summary
    fi
    
    log_success "Cleanup completed successfully in ${duration} seconds!"
}

# =============================================================================
# Script Entry Point
# =============================================================================

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
        --suffix)
            RESOURCE_SUFFIX="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without removing resources"
            echo "  --force      Skip confirmation prompts (dangerous!)"
            echo "  --verbose    Enable verbose logging"
            echo "  --suffix     Specify resource suffix to target specific deployment"
            echo "  --help       Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_SUFFIX    Specify resource suffix to target"
            echo "  DRY_RUN           Set to 'true' for dry run mode"
            echo "  FORCE             Set to 'true' to skip confirmations"
            echo "  VERBOSE           Set to 'true' for verbose output"
            echo ""
            echo "Examples:"
            echo "  $0                    # Interactive cleanup with resource discovery"
            echo "  $0 --dry-run          # See what would be deleted"
            echo "  $0 --suffix abc123    # Target specific deployment"
            echo "  $0 --force            # Skip confirmations (use with caution)"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"