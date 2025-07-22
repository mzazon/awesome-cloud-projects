#!/bin/bash

# =============================================================================
# DynamoDB Global Tables Multi-Region Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script:
# - CloudWatch alarms and dashboards
# - Lambda functions from all regions
# - Global table replicas
# - Primary DynamoDB table
# - IAM roles and policies
# - Temporary files and logs
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/dynamodb-global-tables-destroy-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Info logging
info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

# Success logging
success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

# Warning logging
warn() {
    log "WARN" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

# Error logging
error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

# Fatal error (exits script)
fatal() {
    error "$@"
    exit 1
}

# Progress indicator
progress() {
    local step="$1"
    local total="$2"
    local description="$3"
    
    info "Step $step/$total: $description"
}

# Confirmation prompt
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "${FORCE:-false}" = "true" ]; then
        info "Force mode enabled, auto-confirming: $message"
        return 0
    fi
    
    local prompt="$message"
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$prompt" -r response
    response=${response:-$default}
    
    case $response in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS CLI is not configured or credentials are invalid."
    fi
    
    success "Prerequisites check completed"
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

load_environment() {
    info "Loading environment variables..."
    
    # Try to load from environment file first
    if [ -f "/tmp/global-table-env.sh" ]; then
        info "Loading environment from /tmp/global-table-env.sh"
        source /tmp/global-table-env.sh
    else
        warn "Environment file not found, using defaults or manual input"
    fi
    
    # Set defaults or prompt for required variables
    if [ -z "${TABLE_NAME:-}" ]; then
        if [ "${INTERACTIVE:-true}" = "true" ]; then
            read -p "Enter table name: " TABLE_NAME
        else
            fatal "TABLE_NAME environment variable is required"
        fi
    fi
    
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if [ "${INTERACTIVE:-true}" = "true" ]; then
            read -p "Enter Lambda function name: " LAMBDA_FUNCTION_NAME
        else
            fatal "LAMBDA_FUNCTION_NAME environment variable is required"
        fi
    fi
    
    if [ -z "${IAM_ROLE_NAME:-}" ]; then
        if [ "${INTERACTIVE:-true}" = "true" ]; then
            read -p "Enter IAM role name: " IAM_ROLE_NAME
        else
            fatal "IAM_ROLE_NAME environment variable is required"
        fi
    fi
    
    if [ -z "${CLOUDWATCH_ALARM_PREFIX:-}" ]; then
        if [ "${INTERACTIVE:-true}" = "true" ]; then
            read -p "Enter CloudWatch alarm prefix: " CLOUDWATCH_ALARM_PREFIX
        else
            fatal "CLOUDWATCH_ALARM_PREFIX environment variable is required"
        fi
    fi
    
    # Set region defaults
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export SECONDARY_REGION="${SECONDARY_REGION:-eu-west-1}"
    export TERTIARY_REGION="${TERTIARY_REGION:-ap-northeast-1}"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    
    success "Environment loaded successfully"
    info "Table name: $TABLE_NAME"
    info "Lambda function: $LAMBDA_FUNCTION_NAME"
    info "IAM role: $IAM_ROLE_NAME"
    info "Primary region: $PRIMARY_REGION"
    info "Secondary region: $SECONDARY_REGION"
    info "Tertiary region: $TERTIARY_REGION"
}

# =============================================================================
# RESOURCE DISCOVERY
# =============================================================================

discover_resources() {
    info "Discovering existing resources..."
    
    # Check if primary table exists
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$PRIMARY_REGION" &> /dev/null; then
        info "Found primary table: $TABLE_NAME in $PRIMARY_REGION"
        export TABLE_EXISTS=true
    else
        warn "Primary table not found: $TABLE_NAME in $PRIMARY_REGION"
        export TABLE_EXISTS=false
    fi
    
    # Check replicas
    local regions=("$SECONDARY_REGION" "$TERTIARY_REGION")
    export REPLICA_REGIONS=()
    
    for region in "${regions[@]}"; do
        if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$region" &> /dev/null; then
            info "Found replica in region: $region"
            REPLICA_REGIONS+=("$region")
        else
            warn "Replica not found in region: $region"
        fi
    done
    
    # Check Lambda functions
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    export LAMBDA_REGIONS=()
    
    for region in "${regions[@]}"; do
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$region" &> /dev/null; then
            info "Found Lambda function in region: $region"
            LAMBDA_REGIONS+=("$region")
        else
            warn "Lambda function not found in region: $region"
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        info "Found IAM role: $IAM_ROLE_NAME"
        export ROLE_EXISTS=true
    else
        warn "IAM role not found: $IAM_ROLE_NAME"
        export ROLE_EXISTS=false
    fi
    
    # Check CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$CLOUDWATCH_ALARM_PREFIX" \
        --region "$PRIMARY_REGION" \
        --query 'MetricAlarms[].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$alarms" ]; then
        info "Found CloudWatch alarms: $alarms"
        export ALARMS_EXIST=true
    else
        warn "No CloudWatch alarms found"
        export ALARMS_EXIST=false
    fi
    
    # Check dashboard
    if aws cloudwatch get-dashboard --dashboard-name "$CLOUDWATCH_ALARM_PREFIX-Dashboard" --region "$PRIMARY_REGION" &> /dev/null; then
        info "Found CloudWatch dashboard: $CLOUDWATCH_ALARM_PREFIX-Dashboard"
        export DASHBOARD_EXISTS=true
    else
        warn "CloudWatch dashboard not found"
        export DASHBOARD_EXISTS=false
    fi
    
    success "Resource discovery completed"
}

# =============================================================================
# SAFETY CHECKS
# =============================================================================

perform_safety_checks() {
    info "Performing safety checks..."
    
    # Check if this is a production environment
    if [[ "$TABLE_NAME" == *"prod"* ]] || [[ "$TABLE_NAME" == *"production"* ]]; then
        error "This appears to be a production environment!"
        if ! confirm "Are you absolutely sure you want to delete production resources?" "n"; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Check if table contains data
    if [ "$TABLE_EXISTS" = "true" ]; then
        local item_count=$(aws dynamodb describe-table \
            --table-name "$TABLE_NAME" \
            --region "$PRIMARY_REGION" \
            --query 'Table.ItemCount' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$item_count" -gt 0 ]; then
            warn "Table contains $item_count items"
            if ! confirm "This will delete all data in the table. Continue?" "n"; then
                info "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    success "Safety checks completed"
}

# =============================================================================
# CLOUDWATCH CLEANUP
# =============================================================================

cleanup_cloudwatch() {
    progress 1 8 "Cleaning up CloudWatch resources"
    
    # Remove CloudWatch alarms
    if [ "$ALARMS_EXIST" = "true" ]; then
        info "Removing CloudWatch alarms..."
        
        local alarms=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "$CLOUDWATCH_ALARM_PREFIX" \
            --region "$PRIMARY_REGION" \
            --query 'MetricAlarms[].AlarmName' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$alarms" ]; then
            # Convert space-separated string to array
            local alarm_array=($alarms)
            
            aws cloudwatch delete-alarms \
                --alarm-names "${alarm_array[@]}" \
                --region "$PRIMARY_REGION" || warn "Failed to delete some alarms"
            
            success "CloudWatch alarms deleted"
        fi
    fi
    
    # Remove CloudWatch dashboard
    if [ "$DASHBOARD_EXISTS" = "true" ]; then
        info "Removing CloudWatch dashboard..."
        
        aws cloudwatch delete-dashboards \
            --dashboard-names "$CLOUDWATCH_ALARM_PREFIX-Dashboard" \
            --region "$PRIMARY_REGION" || warn "Failed to delete dashboard"
        
        success "CloudWatch dashboard deleted"
    fi
    
    success "CloudWatch cleanup completed"
}

# =============================================================================
# LAMBDA CLEANUP
# =============================================================================

cleanup_lambda_functions() {
    progress 2 8 "Cleaning up Lambda functions"
    
    for region in "${LAMBDA_REGIONS[@]}"; do
        info "Deleting Lambda function in $region..."
        
        aws lambda delete-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --region "$region" || warn "Failed to delete Lambda function in $region"
        
        success "Lambda function deleted from $region"
    done
    
    success "Lambda functions cleanup completed"
}

# =============================================================================
# GLOBAL TABLE CLEANUP
# =============================================================================

cleanup_global_table_replicas() {
    progress 3 8 "Cleaning up global table replicas"
    
    if [ "$TABLE_EXISTS" = "false" ]; then
        info "No primary table found, skipping replica cleanup"
        return
    fi
    
    # Remove replicas in reverse order (tertiary first, then secondary)
    local replica_regions_reverse=()
    for ((i=${#REPLICA_REGIONS[@]}-1; i>=0; i--)); do
        replica_regions_reverse+=("${REPLICA_REGIONS[i]}")
    done
    
    for region in "${replica_regions_reverse[@]}"; do
        info "Removing replica from $region..."
        
        # Skip if it's the primary region
        if [ "$region" = "$PRIMARY_REGION" ]; then
            continue
        fi
        
        aws dynamodb update-table \
            --table-name "$TABLE_NAME" \
            --replica-updates \
                "Delete={RegionName=$region}" \
            --region "$PRIMARY_REGION" || warn "Failed to remove replica from $region"
        
        info "Waiting for replica removal from $region..."
        sleep 30
    done
    
    # Wait for all replicas to be removed
    info "Waiting for replica cleanup to complete..."
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local remaining_replicas=$(aws dynamodb describe-table \
            --table-name "$TABLE_NAME" \
            --region "$PRIMARY_REGION" \
            --query 'Table.Replicas[?ReplicaStatus!=`DELETING`].RegionName' \
            --output text 2>/dev/null || echo "")
        
        # Count replicas (excluding primary region)
        local replica_count=0
        for replica in $remaining_replicas; do
            if [ "$replica" != "$PRIMARY_REGION" ]; then
                replica_count=$((replica_count + 1))
            fi
        done
        
        if [ $replica_count -eq 0 ]; then
            break
        fi
        
        attempt=$((attempt + 1))
        info "Attempt $attempt/$max_attempts: Still removing replicas..."
        sleep 30
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warn "Replica removal took longer than expected, continuing..."
    fi
    
    success "Global table replicas cleanup completed"
}

# =============================================================================
# DYNAMODB TABLE CLEANUP
# =============================================================================

cleanup_primary_table() {
    progress 4 8 "Cleaning up primary DynamoDB table"
    
    if [ "$TABLE_EXISTS" = "false" ]; then
        info "Primary table not found, skipping"
        return
    fi
    
    info "Deleting primary table: $TABLE_NAME"
    
    aws dynamodb delete-table \
        --table-name "$TABLE_NAME" \
        --region "$PRIMARY_REGION" || warn "Failed to delete primary table"
    
    # Wait for table deletion
    info "Waiting for table deletion to complete..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ! aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$PRIMARY_REGION" &> /dev/null; then
            break
        fi
        
        attempt=$((attempt + 1))
        info "Attempt $attempt/$max_attempts: Table still exists..."
        sleep 30
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warn "Table deletion took longer than expected"
    else
        success "Primary table deleted successfully"
    fi
    
    success "Primary table cleanup completed"
}

# =============================================================================
# IAM CLEANUP
# =============================================================================

cleanup_iam_resources() {
    progress 5 8 "Cleaning up IAM resources"
    
    if [ "$ROLE_EXISTS" = "false" ]; then
        info "IAM role not found, skipping"
        return
    fi
    
    info "Detaching policies from IAM role..."
    
    # Detach Lambda execution policy
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        --region "$PRIMARY_REGION" || warn "Failed to detach Lambda execution policy"
    
    # Detach DynamoDB policy
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
        --region "$PRIMARY_REGION" || warn "Failed to detach DynamoDB policy"
    
    # Wait a bit for policies to be detached
    sleep 10
    
    # Delete IAM role
    info "Deleting IAM role..."
    aws iam delete-role \
        --role-name "$IAM_ROLE_NAME" \
        --region "$PRIMARY_REGION" || warn "Failed to delete IAM role"
    
    success "IAM resources cleanup completed"
}

# =============================================================================
# TEMPORARY FILES CLEANUP
# =============================================================================

cleanup_temporary_files() {
    progress 6 8 "Cleaning up temporary files"
    
    # Clean up temporary files
    local temp_files=(
        "/tmp/global-table-env.sh"
        "/tmp/global-table-processor.py"
        "/tmp/global-table-processor.zip"
        "/tmp/lambda-deployment"
        "/tmp/dashboard-body.json"
        "/tmp/response-*.json"
        "/tmp/conflict-*.json"
        "/tmp/failover-*.json"
        "/tmp/performance-*.json"
        "/tmp/test.json"
    )
    
    for file_pattern in "${temp_files[@]}"; do
        if [ -e "$file_pattern" ] || [ -d "$file_pattern" ]; then
            info "Removing: $file_pattern"
            rm -rf $file_pattern 2>/dev/null || warn "Failed to remove $file_pattern"
        fi
    done
    
    # Clean up old log files (keep last 5)
    if ls /tmp/dynamodb-global-tables-*-*.log &> /dev/null; then
        info "Cleaning up old log files..."
        ls -t /tmp/dynamodb-global-tables-*-*.log | tail -n +6 | xargs rm -f 2>/dev/null || true
    fi
    
    success "Temporary files cleanup completed"
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_cleanup() {
    progress 7 8 "Verifying cleanup"
    
    local cleanup_issues=0
    
    # Check if table still exists
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$PRIMARY_REGION" &> /dev/null; then
        error "Primary table still exists: $TABLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check replicas
    local regions=("$SECONDARY_REGION" "$TERTIARY_REGION")
    for region in "${regions[@]}"; do
        if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$region" &> /dev/null; then
            error "Replica still exists in region: $region"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    done
    
    # Check Lambda functions
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    for region in "${regions[@]}"; do
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$region" &> /dev/null; then
            error "Lambda function still exists in region: $region"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        error "IAM role still exists: $IAM_ROLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$CLOUDWATCH_ALARM_PREFIX" \
        --region "$PRIMARY_REGION" \
        --query 'MetricAlarms[].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$alarms" ]; then
        error "CloudWatch alarms still exist: $alarms"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check dashboard
    if aws cloudwatch get-dashboard --dashboard-name "$CLOUDWATCH_ALARM_PREFIX-Dashboard" --region "$PRIMARY_REGION" &> /dev/null; then
        error "CloudWatch dashboard still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "Cleanup verification completed - all resources removed"
    else
        warn "Cleanup verification found $cleanup_issues issues"
        info "Some resources may take additional time to be fully removed"
    fi
    
    return $cleanup_issues
}

# =============================================================================
# CLEANUP SUMMARY
# =============================================================================

show_cleanup_summary() {
    progress 8 8 "Cleanup summary"
    
    echo
    echo "==============================================================================="
    echo "                           CLEANUP SUMMARY"
    echo "==============================================================================="
    echo
    echo "🧹 Resources Removed:"
    echo "   • DynamoDB Table: $TABLE_NAME"
    echo "   • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "   • IAM Role: $IAM_ROLE_NAME"
    echo "   • CloudWatch Alarms: $CLOUDWATCH_ALARM_PREFIX-*"
    echo "   • CloudWatch Dashboard: $CLOUDWATCH_ALARM_PREFIX-Dashboard"
    echo "   • Temporary files and logs"
    echo
    echo "🌍 Regions Processed:"
    echo "   • Primary: $PRIMARY_REGION"
    echo "   • Secondary: $SECONDARY_REGION"
    echo "   • Tertiary: $TERTIARY_REGION"
    echo
    echo "📋 Log File: $LOG_FILE"
    echo
    echo "💡 Note: Some AWS resources may take additional time to be fully removed"
    echo "   from the AWS console due to eventual consistency."
    echo "==============================================================================="
    echo
    
    success "Cleanup completed successfully!"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Print header
    echo "==============================================================================="
    echo "                    DynamoDB Global Tables Cleanup"
    echo "==============================================================================="
    echo
    
    # Start logging
    info "Starting cleanup at $(date)"
    info "Log file: $LOG_FILE"
    
    # Check if dry run
    if [ "${DRY_RUN:-false}" = "true" ]; then
        info "DRY RUN MODE - No resources will be deleted"
        load_environment
        discover_resources
        info "Resources that would be deleted:"
        if [ "$TABLE_EXISTS" = "true" ]; then
            info "  - DynamoDB Table: $TABLE_NAME"
        fi
        for region in "${LAMBDA_REGIONS[@]}"; do
            info "  - Lambda Function: $LAMBDA_FUNCTION_NAME in $region"
        done
        if [ "$ROLE_EXISTS" = "true" ]; then
            info "  - IAM Role: $IAM_ROLE_NAME"
        fi
        if [ "$ALARMS_EXIST" = "true" ]; then
            info "  - CloudWatch Alarms with prefix: $CLOUDWATCH_ALARM_PREFIX"
        fi
        if [ "$DASHBOARD_EXISTS" = "true" ]; then
            info "  - CloudWatch Dashboard: $CLOUDWATCH_ALARM_PREFIX-Dashboard"
        fi
        exit 0
    fi
    
    # Final confirmation
    if [ "${FORCE:-false}" != "true" ]; then
        echo
        warn "This will permanently delete all DynamoDB Global Tables resources!"
        echo
        if ! confirm "Are you sure you want to continue?" "n"; then
            info "Cleanup cancelled by user"
            exit 0
        fi
        echo
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    discover_resources
    perform_safety_checks
    cleanup_cloudwatch
    cleanup_lambda_functions
    cleanup_global_table_replicas
    cleanup_primary_table
    cleanup_iam_resources
    cleanup_temporary_files
    
    # Verify cleanup
    if verify_cleanup; then
        show_cleanup_summary
    else
        warn "Cleanup completed with some issues - check the log file for details"
    fi
    
    info "Cleanup completed at $(date)"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --force)
            export FORCE=true
            shift
            ;;
        --non-interactive)
            export INTERACTIVE=false
            shift
            ;;
        --table-name)
            export TABLE_NAME="$2"
            shift 2
            ;;
        --lambda-function-name)
            export LAMBDA_FUNCTION_NAME="$2"
            shift 2
            ;;
        --iam-role-name)
            export IAM_ROLE_NAME="$2"
            shift 2
            ;;
        --cloudwatch-alarm-prefix)
            export CLOUDWATCH_ALARM_PREFIX="$2"
            shift 2
            ;;
        --primary-region)
            export PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            export SECONDARY_REGION="$2"
            shift 2
            ;;
        --tertiary-region)
            export TERTIARY_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --dry-run                    Run in dry-run mode (no resources deleted)"
            echo "  --force                      Skip confirmation prompts"
            echo "  --non-interactive            Run without user prompts"
            echo "  --table-name NAME            Specify table name to delete"
            echo "  --lambda-function-name NAME  Specify Lambda function name to delete"
            echo "  --iam-role-name NAME         Specify IAM role name to delete"
            echo "  --cloudwatch-alarm-prefix P  Specify CloudWatch alarm prefix"
            echo "  --primary-region REGION      Set primary region (default: us-east-1)"
            echo "  --secondary-region REGION    Set secondary region (default: eu-west-1)"
            echo "  --tertiary-region REGION     Set tertiary region (default: ap-northeast-1)"
            echo "  --help                       Show this help message"
            echo
            echo "Examples:"
            echo "  $0 --dry-run                 # Show what would be deleted"
            echo "  $0 --force                   # Delete without confirmation"
            echo "  $0 --table-name MyTable      # Delete specific table"
            echo
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"