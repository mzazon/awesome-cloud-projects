#!/bin/bash

# Destroy script for Advanced DynamoDB Streaming with Global Tables
# This script safely removes all resources created by the deploy script

set -euo pipefail

# Colors for output
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Advanced DynamoDB Streaming with Global Tables infrastructure

OPTIONS:
    -h, --help              Display this help message
    -d, --dry-run          Show what would be destroyed without actually destroying
    -f, --force            Force destruction without confirmation prompts
    -y, --yes              Skip confirmation prompts (same as --force)
    --log-file            Custom log file path (default: ./destroy.log)

EXAMPLES:
    $0                     # Interactive destruction with confirmations
    $0 --dry-run          # Preview what would be destroyed
    $0 --force            # Destroy without confirmations
    $0 -y                 # Destroy without confirmations (short form)

SAFETY:
    This script will permanently delete all resources created by the deploy script.
    Use --dry-run first to review what will be destroyed.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force|-y|--yes)
            FORCE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "Starting DynamoDB Global Streaming destruction at $(date)"
log_info "Dry Run: $DRY_RUN"
log_info "Force: $FORCE"

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log_error "Deployment state file not found: $STATE_FILE"
        log_error "Cannot proceed without knowing what resources to destroy"
        exit 1
    fi
    
    # Source the state file to load variables
    source "$STATE_FILE"
    
    # Validate required variables
    if [[ -z "${TABLE_NAME:-}" || -z "${STREAM_NAME:-}" || -z "${LAMBDA_ROLE_NAME:-}" ]]; then
        log_error "Invalid state file - missing required variables"
        exit 1
    fi
    
    log_info "Loaded deployment state:"
    log_info "  Table Name: $TABLE_NAME"
    log_info "  Stream Name: $STREAM_NAME"
    log_info "  Lambda Role: $LAMBDA_ROLE_NAME"
    log_info "  Primary Region: ${PRIMARY_REGION:-us-east-1}"
    log_info "  Secondary Region: ${SECONDARY_REGION:-eu-west-1}"
    log_info "  Tertiary Region: ${TERTIARY_REGION:-ap-southeast-1}"
    log_info "  Deployment Date: ${DEPLOYMENT_DATE:-unknown}"
}

# Confirm destruction
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "DESTRUCTIVE OPERATION WARNING"
    echo "This will permanently delete the following resources:"
    echo "  • DynamoDB Global Tables in 3 regions"
    echo "  • Kinesis Data Streams in 3 regions"
    echo "  • Lambda functions in 3 regions"
    echo "  • Event source mappings"
    echo "  • IAM roles and policies"
    echo "  • CloudWatch dashboard"
    echo "  • All data stored in these resources"
    echo
    echo "Resources to be destroyed:"
    echo "  Table: $TABLE_NAME"
    echo "  Stream: $STREAM_NAME"
    echo "  Role: $LAMBDA_ROLE_NAME"
    echo "  Regions: $PRIMARY_REGION, $SECONDARY_REGION, $TERTIARY_REGION"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Type the table name '$TABLE_NAME' to confirm: " -r
    if [[ "$REPLY" != "$TABLE_NAME" ]]; then
        log_error "Table name confirmation failed"
        exit 1
    fi
    
    log_info "Destruction confirmed by user"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check if configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Get account info
    local aws_account_id
    aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    
    # Verify account matches deployment state
    if [[ -n "${AWS_ACCOUNT_ID:-}" && "$aws_account_id" != "$AWS_ACCOUNT_ID" ]]; then
        log_error "AWS Account ID mismatch!"
        log_error "Current: $aws_account_id"
        log_error "Expected: $AWS_ACCOUNT_ID"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Delete Lambda functions and event source mappings
delete_lambda_resources() {
    log_info "Deleting Lambda functions and event source mappings..."
    
    for region in "${PRIMARY_REGION:-us-east-1}" "${SECONDARY_REGION:-eu-west-1}" "${TERTIARY_REGION:-ap-southeast-1}"; do
        log_info "Cleaning up Lambda resources in $region..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Lambda resources in $region"
            continue
        fi
        
        # Delete event source mappings for stream processor
        local stream_function="${TABLE_NAME}-stream-processor"
        if aws lambda get-function --region "$region" --function-name "$stream_function" &> /dev/null; then
            log_info "Deleting event source mappings for $stream_function..."
            
            local mappings
            mappings=$(aws lambda list-event-source-mappings \
                --region "$region" \
                --function-name "$stream_function" \
                --query 'EventSourceMappings[*].UUID' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$mappings" ]]; then
                for uuid in $mappings; do
                    aws lambda delete-event-source-mapping \
                        --region "$region" \
                        --uuid "$uuid" &> /dev/null || log_warning "Failed to delete mapping $uuid"
                done
            fi
            
            # Delete function
            aws lambda delete-function \
                --region "$region" \
                --function-name "$stream_function" || log_warning "Failed to delete $stream_function"
            
            log_success "Deleted stream processor in $region"
        else
            log_warning "Stream processor not found in $region"
        fi
        
        # Delete event source mappings for Kinesis processor
        local kinesis_function="${STREAM_NAME}-kinesis-processor"
        if aws lambda get-function --region "$region" --function-name "$kinesis_function" &> /dev/null; then
            log_info "Deleting event source mappings for $kinesis_function..."
            
            local mappings
            mappings=$(aws lambda list-event-source-mappings \
                --region "$region" \
                --function-name "$kinesis_function" \
                --query 'EventSourceMappings[*].UUID' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$mappings" ]]; then
                for uuid in $mappings; do
                    aws lambda delete-event-source-mapping \
                        --region "$region" \
                        --uuid "$uuid" &> /dev/null || log_warning "Failed to delete mapping $uuid"
                done
            fi
            
            # Delete function
            aws lambda delete-function \
                --region "$region" \
                --function-name "$kinesis_function" || log_warning "Failed to delete $kinesis_function"
            
            log_success "Deleted Kinesis processor in $region"
        else
            log_warning "Kinesis processor not found in $region"
        fi
    done
    
    log_success "Lambda resources cleanup completed"
}

# Disable Kinesis integration for DynamoDB
disable_kinesis_integration() {
    log_info "Disabling Kinesis Data Streams integration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would disable Kinesis integration for table: $TABLE_NAME"
        return 0
    fi
    
    # Check if table exists and has Kinesis integration
    if aws dynamodb describe-table --region "${PRIMARY_REGION:-us-east-1}" --table-name "$TABLE_NAME" &> /dev/null; then
        # Get Kinesis stream ARN
        local kinesis_arn
        kinesis_arn=$(aws kinesis describe-stream \
            --region "${PRIMARY_REGION:-us-east-1}" \
            --stream-name "$STREAM_NAME" \
            --query 'StreamDescription.StreamARN' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$kinesis_arn" ]]; then
            # Disable integration
            aws dynamodb disable-kinesis-streaming-destination \
                --region "${PRIMARY_REGION:-us-east-1}" \
                --table-name "$TABLE_NAME" \
                --stream-arn "$kinesis_arn" || log_warning "Failed to disable Kinesis integration"
            
            log_success "Kinesis integration disabled"
        else
            log_warning "Kinesis stream not found, skipping integration disable"
        fi
    else
        log_warning "Table not found, skipping Kinesis integration disable"
    fi
}

# Delete Global Tables and replicas
delete_dynamodb_tables() {
    log_info "Deleting DynamoDB Global Tables and replicas..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete DynamoDB tables in all regions"
        return 0
    fi
    
    # Delete replica tables first
    for region in "${SECONDARY_REGION:-eu-west-1}" "${TERTIARY_REGION:-ap-southeast-1}"; do
        log_info "Deleting replica table in $region..."
        
        if aws dynamodb describe-table --region "$region" --table-name "$TABLE_NAME" &> /dev/null; then
            # Wait for any ongoing operations to complete
            aws dynamodb wait table-exists --region "$region" --table-name "$TABLE_NAME" || true
            
            # Delete table
            aws dynamodb delete-table \
                --region "$region" \
                --table-name "$TABLE_NAME"
            
            # Wait for deletion
            log_info "Waiting for table deletion in $region..."
            aws dynamodb wait table-not-exists \
                --region "$region" \
                --table-name "$TABLE_NAME" || log_warning "Timeout waiting for table deletion in $region"
            
            log_success "Replica table deleted in $region"
        else
            log_warning "Replica table not found in $region"
        fi
    done
    
    # Delete primary table
    log_info "Deleting primary table in ${PRIMARY_REGION:-us-east-1}..."
    
    if aws dynamodb describe-table --region "${PRIMARY_REGION:-us-east-1}" --table-name "$TABLE_NAME" &> /dev/null; then
        # Wait for any ongoing operations to complete
        aws dynamodb wait table-exists --region "${PRIMARY_REGION:-us-east-1}" --table-name "$TABLE_NAME" || true
        
        # Delete table
        aws dynamodb delete-table \
            --region "${PRIMARY_REGION:-us-east-1}" \
            --table-name "$TABLE_NAME"
        
        # Wait for deletion
        log_info "Waiting for primary table deletion..."
        aws dynamodb wait table-not-exists \
            --region "${PRIMARY_REGION:-us-east-1}" \
            --table-name "$TABLE_NAME" || log_warning "Timeout waiting for primary table deletion"
        
        log_success "Primary table deleted"
    else
        log_warning "Primary table not found"
    fi
}

# Delete Kinesis Data Streams
delete_kinesis_streams() {
    log_info "Deleting Kinesis Data Streams..."
    
    for region in "${PRIMARY_REGION:-us-east-1}" "${SECONDARY_REGION:-eu-west-1}" "${TERTIARY_REGION:-ap-southeast-1}"; do
        log_info "Deleting Kinesis stream in $region..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete stream: $STREAM_NAME in $region"
            continue
        fi
        
        if aws kinesis describe-stream --region "$region" --stream-name "$STREAM_NAME" &> /dev/null; then
            # Delete stream
            aws kinesis delete-stream \
                --region "$region" \
                --stream-name "$STREAM_NAME" || log_warning "Failed to delete stream in $region"
            
            log_success "Kinesis stream deleted in $region"
        else
            log_warning "Kinesis stream not found in $region"
        fi
    done
}

# Delete IAM resources
delete_iam_resources() {
    log_info "Deleting IAM role and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM role: $LAMBDA_ROLE_NAME"
        return 0
    fi
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        # Detach policies
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
            "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
            "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
            "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        )
        
        for policy in "${policies[@]}"; do
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "$policy" || log_warning "Failed to detach policy: $policy"
        done
        
        # Delete role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" || log_warning "Failed to delete IAM role"
        
        log_success "IAM role deleted"
    else
        log_warning "IAM role not found"
    fi
}

# Delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log_info "Deleting CloudWatch dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch dashboard: ECommerce-Global-Monitoring"
        return 0
    fi
    
    # Delete dashboard
    aws cloudwatch delete-dashboards \
        --region "${PRIMARY_REGION:-us-east-1}" \
        --dashboard-names "ECommerce-Global-Monitoring" || log_warning "Failed to delete CloudWatch dashboard"
    
    log_success "CloudWatch dashboard deleted"
}

# Validate destruction
validate_destruction() {
    log_info "Validating resource destruction..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Destruction validation would be performed"
        return 0
    fi
    
    local validation_passed=true
    
    # Check if tables still exist
    for region in "${PRIMARY_REGION:-us-east-1}" "${SECONDARY_REGION:-eu-west-1}" "${TERTIARY_REGION:-ap-southeast-1}"; do
        if aws dynamodb describe-table --region "$region" --table-name "$TABLE_NAME" &> /dev/null; then
            log_warning "Table $TABLE_NAME still exists in $region"
            validation_passed=false
        fi
        
        if aws kinesis describe-stream --region "$region" --stream-name "$STREAM_NAME" &> /dev/null; then
            log_warning "Kinesis stream $STREAM_NAME still exists in $region"
            validation_passed=false
        fi
        
        if aws lambda get-function --region "$region" --function-name "${TABLE_NAME}-stream-processor" &> /dev/null; then
            log_warning "Stream processor still exists in $region"
            validation_passed=false
        fi
        
        if aws lambda get-function --region "$region" --function-name "${STREAM_NAME}-kinesis-processor" &> /dev/null; then
            log_warning "Kinesis processor still exists in $region"
            validation_passed=false
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        log_warning "IAM role $LAMBDA_ROLE_NAME still exists"
        validation_passed=false
    fi
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "All resources successfully destroyed"
    else
        log_warning "Some resources may still exist - check manually"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up state file: $STATE_FILE"
        return 0
    fi
    
    # Remove state file
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_success "State file removed"
    fi
    
    # Keep log file for reference
    log_info "Log file preserved: $LOG_FILE"
}

# Print destruction summary
print_summary() {
    log_info "Destruction Summary"
    echo "================================================"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "The following resources have been destroyed:"
        echo "  ✓ DynamoDB Global Tables: $TABLE_NAME"
        echo "  ✓ Kinesis Data Streams: $STREAM_NAME"
        echo "  ✓ Lambda functions and event mappings"
        echo "  ✓ IAM role: $LAMBDA_ROLE_NAME"
        echo "  ✓ CloudWatch dashboard: ECommerce-Global-Monitoring"
        echo "  ✓ Local state file"
        echo
        echo "Regions cleaned: ${PRIMARY_REGION:-us-east-1}, ${SECONDARY_REGION:-eu-west-1}, ${TERTIARY_REGION:-ap-southeast-1}"
        log_success "Destruction completed successfully!"
    else
        echo "DRY RUN - No resources were actually destroyed"
        echo "The following would be destroyed:"
        echo "  • DynamoDB Global Tables: $TABLE_NAME"
        echo "  • Kinesis Data Streams: $STREAM_NAME"
        echo "  • Lambda functions and event mappings"
        echo "  • IAM role: $LAMBDA_ROLE_NAME"
        echo "  • CloudWatch dashboard: ECommerce-Global-Monitoring"
        echo "  • Local state file"
        echo
        echo "Regions affected: ${PRIMARY_REGION:-us-east-1}, ${SECONDARY_REGION:-eu-west-1}, ${TERTIARY_REGION:-ap-southeast-1}"
        log_info "Run without --dry-run to perform actual destruction"
    fi
    
    echo "================================================"
    echo "Log file: $LOG_FILE"
}

# Main destruction function
main() {
    load_deployment_state
    confirm_destruction
    check_prerequisites
    
    # Destruction order is important - Lambda first to stop processing
    delete_lambda_resources
    disable_kinesis_integration
    delete_dynamodb_tables
    delete_kinesis_streams
    delete_iam_resources
    delete_cloudwatch_dashboard
    
    validate_destruction
    cleanup_local_files
    print_summary
}

# Handle script interruption
cleanup_on_error() {
    log_error "Script interrupted or failed"
    log_info "Check the log file for details: $LOG_FILE"
    log_warning "Some resources may still exist - check AWS Console"
    exit 1
}

trap cleanup_on_error ERR INT TERM

# Run main function
main

log_info "Script completed at $(date)"