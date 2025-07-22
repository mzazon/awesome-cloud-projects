#!/bin/bash

# =============================================================================
# FIFO Message Processing System Cleanup Script
# Recipe: Processing Ordered Messages with SQS FIFO and Dead Letter Queues
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Global variables
DRY_RUN=false
FORCE_CLEANUP=false
PARTIAL_CLEANUP=false
SKIP_CONFIRMATION=false

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    local tools=("jq")
    for tool in "${tools[@]}"; do
        if ! command -v ${tool} &> /dev/null; then
            error "${tool} is not installed. Please install it first."
            exit 1
        fi
    done
    
    info "✅ All prerequisites met"
}

load_environment() {
    log "Loading environment variables..."
    
    # Try to load from deployment environment file
    if [[ -f ".deployment_env" ]]; then
        source .deployment_env
        info "✅ Loaded environment from .deployment_env"
    else
        warn "No .deployment_env file found. You'll need to provide project details manually."
        
        # Try to detect from command line or prompt
        if [[ -z "${PROJECT_NAME:-}" ]]; then
            if [[ "${SKIP_CONFIRMATION}" != "true" ]]; then
                echo -n "Enter project name (e.g., fifo-processing-abc123): "
                read PROJECT_NAME
            else
                error "PROJECT_NAME not provided and no .deployment_env file found"
                exit 1
            fi
        fi
        
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        if [[ -z "${AWS_REGION}" ]]; then
            export AWS_REGION="us-east-1"
            warn "No AWS region configured. Using default: ${AWS_REGION}"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export MAIN_QUEUE_NAME="${PROJECT_NAME}-main-queue.fifo"
        export DLQ_NAME="${PROJECT_NAME}-dlq.fifo"
        export ORDER_TABLE_NAME="${PROJECT_NAME}-orders"
        export ARCHIVE_BUCKET_NAME="${PROJECT_NAME}-message-archive"
        export SNS_TOPIC_NAME="${PROJECT_NAME}-alerts"
    fi
    
    # Validate required variables
    local required_vars=(
        "PROJECT_NAME" "AWS_REGION" "AWS_ACCOUNT_ID"
        "MAIN_QUEUE_NAME" "DLQ_NAME" "ORDER_TABLE_NAME"
        "ARCHIVE_BUCKET_NAME" "SNS_TOPIC_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable ${var} is not set"
            exit 1
        fi
    done
    
    info "✅ Environment loaded: ${PROJECT_NAME}"
}

show_resources_to_delete() {
    log "📋 RESOURCES TO BE DELETED"
    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project Name:          ${PROJECT_NAME}
AWS Region:            ${AWS_REGION}
AWS Account:           ${AWS_ACCOUNT_ID}

💥 RESOURCES THAT WILL BE DELETED:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Lambda Functions:    3 functions
• Event Source Mappings
• SQS Queues:          ${MAIN_QUEUE_NAME}, ${DLQ_NAME}
• CloudWatch Alarms:   3 alarms
• DynamoDB Table:      ${ORDER_TABLE_NAME}
• S3 Bucket:           ${ARCHIVE_BUCKET_NAME} (and ALL contents)
• SNS Topic:           ${SNS_TOPIC_NAME}
• IAM Roles:           2 roles and policies

⚠️  WARNING: This action cannot be undone!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

confirm_deletion() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]] || [[ "${FORCE_CLEANUP}" == "true" ]]; then
        warn "Skipping confirmation - proceeding with deletion"
        return 0
    fi
    
    show_resources_to_delete
    
    echo -n "Are you sure you want to delete ALL these resources? (type 'DELETE' to confirm): "
    read confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo -n "This will permanently delete all data. Type 'YES' to continue: "
    read final_confirmation
    
    if [[ "${final_confirmation}" != "YES" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion - proceeding..."
}

check_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    
    if eval "${check_command}" &> /dev/null; then
        return 0  # Resource exists
    else
        return 1  # Resource does not exist
    fi
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_lambda_functions() {
    log "Deleting Lambda functions and event source mappings..."
    
    local functions=(
        "${PROJECT_NAME}-message-processor"
        "${PROJECT_NAME}-poison-handler"
        "${PROJECT_NAME}-message-replay"
    )
    
    for function in "${functions[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "DRY RUN: Would delete Lambda function ${function}"
            continue
        fi
        
        if check_resource_exists "Lambda function" "${function}" "aws lambda get-function --function-name ${function}"; then
            # Delete event source mappings first
            log "Deleting event source mappings for ${function}..."
            local mappings=$(aws lambda list-event-source-mappings \
                --function-name "${function}" \
                --query 'EventSourceMappings[*].UUID' --output text 2>/dev/null || echo "")
            
            for uuid in ${mappings}; do
                if [[ -n "${uuid}" && "${uuid}" != "None" ]]; then
                    aws lambda delete-event-source-mapping --uuid "${uuid}" &> /dev/null || true
                    info "  ✅ Deleted event source mapping: ${uuid}"
                fi
            done
            
            # Delete the function
            aws lambda delete-function --function-name "${function}"
            info "  ✅ Deleted Lambda function: ${function}"
        else
            warn "Lambda function ${function} not found - skipping"
        fi
    done
}

delete_sqs_queues() {
    log "Deleting SQS queues..."
    
    local queues=(
        "${MAIN_QUEUE_NAME}"
        "${DLQ_NAME}"
    )
    
    for queue_name in "${queues[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "DRY RUN: Would delete SQS queue ${queue_name}"
            continue
        fi
        
        local queue_url=""
        if queue_url=$(aws sqs get-queue-url --queue-name "${queue_name}" --query 'QueueUrl' --output text 2>/dev/null); then
            aws sqs delete-queue --queue-url "${queue_url}"
            info "  ✅ Deleted SQS queue: ${queue_name}"
        else
            warn "SQS queue ${queue_name} not found - skipping"
        fi
    done
}

delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms=(
        "${PROJECT_NAME}-high-failure-rate"
        "${PROJECT_NAME}-poison-messages-detected"
        "${PROJECT_NAME}-high-processing-latency"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would delete CloudWatch alarms: ${alarms[*]}"
        return 0
    fi
    
    # Check which alarms exist
    local existing_alarms=()
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "${alarm}" --query 'MetricAlarms[0].AlarmName' --output text &> /dev/null; then
            existing_alarms+=("${alarm}")
        fi
    done
    
    if [[ ${#existing_alarms[@]} -gt 0 ]]; then
        aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}"
        info "  ✅ Deleted CloudWatch alarms: ${existing_alarms[*]}"
    else
        warn "No CloudWatch alarms found - skipping"
    fi
}

delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would delete DynamoDB table ${ORDER_TABLE_NAME}"
        return 0
    fi
    
    if check_resource_exists "DynamoDB table" "${ORDER_TABLE_NAME}" "aws dynamodb describe-table --table-name ${ORDER_TABLE_NAME}"; then
        aws dynamodb delete-table --table-name "${ORDER_TABLE_NAME}"
        
        # Wait for table deletion to complete
        log "Waiting for DynamoDB table deletion to complete..."
        while aws dynamodb describe-table --table-name "${ORDER_TABLE_NAME}" &> /dev/null; do
            sleep 5
            echo -n "."
        done
        echo ""
        
        info "  ✅ Deleted DynamoDB table: ${ORDER_TABLE_NAME}"
    else
        warn "DynamoDB table ${ORDER_TABLE_NAME} not found - skipping"
    fi
}

delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would delete S3 bucket ${ARCHIVE_BUCKET_NAME} and all contents"
        return 0
    fi
    
    if check_resource_exists "S3 bucket" "${ARCHIVE_BUCKET_NAME}" "aws s3 ls s3://${ARCHIVE_BUCKET_NAME}"; then
        # First, delete all objects in the bucket
        log "Emptying S3 bucket..."
        aws s3 rm "s3://${ARCHIVE_BUCKET_NAME}" --recursive || true
        
        # Delete any incomplete multipart uploads
        aws s3api list-multipart-uploads --bucket "${ARCHIVE_BUCKET_NAME}" \
            --query 'Uploads[].{Key:Key,UploadId:UploadId}' --output text | \
        while read key upload_id; do
            if [[ -n "${key}" && -n "${upload_id}" ]]; then
                aws s3api abort-multipart-upload \
                    --bucket "${ARCHIVE_BUCKET_NAME}" \
                    --key "${key}" \
                    --upload-id "${upload_id}" || true
            fi
        done
        
        # Delete all object versions if versioning is enabled
        aws s3api list-object-versions --bucket "${ARCHIVE_BUCKET_NAME}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
        while read key version_id; do
            if [[ -n "${key}" && -n "${version_id}" ]]; then
                aws s3api delete-object \
                    --bucket "${ARCHIVE_BUCKET_NAME}" \
                    --key "${key}" \
                    --version-id "${version_id}" || true
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions --bucket "${ARCHIVE_BUCKET_NAME}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | \
        while read key version_id; do
            if [[ -n "${key}" && -n "${version_id}" ]]; then
                aws s3api delete-object \
                    --bucket "${ARCHIVE_BUCKET_NAME}" \
                    --key "${key}" \
                    --version-id "${version_id}" || true
            fi
        done
        
        # Finally, delete the bucket
        aws s3 rb "s3://${ARCHIVE_BUCKET_NAME}"
        info "  ✅ Deleted S3 bucket: ${ARCHIVE_BUCKET_NAME}"
    else
        warn "S3 bucket ${ARCHIVE_BUCKET_NAME} not found - skipping"
    fi
}

delete_sns_topic() {
    log "Deleting SNS topic..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN: Would delete SNS topic ${SNS_TOPIC_NAME}"
        return 0
    fi
    
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    if check_resource_exists "SNS topic" "${SNS_TOPIC_NAME}" "aws sns get-topic-attributes --topic-arn ${topic_arn}"; then
        aws sns delete-topic --topic-arn "${topic_arn}"
        info "  ✅ Deleted SNS topic: ${SNS_TOPIC_NAME}"
    else
        warn "SNS topic ${SNS_TOPIC_NAME} not found - skipping"
    fi
}

delete_iam_roles() {
    log "Deleting IAM roles and policies..."
    
    local roles=(
        "${PROJECT_NAME}-processor-role"
        "${PROJECT_NAME}-poison-handler-role"
    )
    
    for role in "${roles[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "DRY RUN: Would delete IAM role ${role}"
            continue
        fi
        
        if check_resource_exists "IAM role" "${role}" "aws iam get-role --role-name ${role}"; then
            # Detach managed policies
            local managed_policies=$(aws iam list-attached-role-policies \
                --role-name "${role}" \
                --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in ${managed_policies}; do
                if [[ -n "${policy_arn}" && "${policy_arn}" != "None" ]]; then
                    aws iam detach-role-policy --role-name "${role}" --policy-arn "${policy_arn}"
                    info "  ✅ Detached managed policy: ${policy_arn}"
                fi
            done
            
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies \
                --role-name "${role}" \
                --query 'PolicyNames' --output text 2>/dev/null || echo "")
            
            for policy in ${inline_policies}; do
                if [[ -n "${policy}" && "${policy}" != "None" ]]; then
                    aws iam delete-role-policy --role-name "${role}" --policy-name "${policy}"
                    info "  ✅ Deleted inline policy: ${policy}"
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name "${role}"
            info "  ✅ Deleted IAM role: ${role}"
        else
            warn "IAM role ${role} not found - skipping"
        fi
    done
}

cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files=(
        ".deployment_env"
        "trust_policy.json"
        "processor_policy.json"
        "poison_policy.json"
        "message_processor.py"
        "poison_message_handler.py"
        "message_replay.py"
        "message_processor.zip"
        "poison_message_handler.zip"
        "message_replay.zip"
        "deployment_*.log"
        "cleanup_*.log"
    )
    
    for file_pattern in "${files[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            if ls ${file_pattern} &> /dev/null; then
                info "DRY RUN: Would delete local files matching: ${file_pattern}"
            fi
            continue
        fi
        
        if ls ${file_pattern} &> /dev/null 2>&1; then
            rm -f ${file_pattern}
            info "  ✅ Deleted local files: ${file_pattern}"
        fi
    done
}

# =============================================================================
# Validation and Summary Functions
# =============================================================================

validate_cleanup() {
    log "Validating resource cleanup..."
    
    local cleanup_errors=0
    
    # Check if resources were actually deleted
    local resources=(
        "Lambda function ${PROJECT_NAME}-message-processor:aws lambda get-function --function-name ${PROJECT_NAME}-message-processor"
        "Lambda function ${PROJECT_NAME}-poison-handler:aws lambda get-function --function-name ${PROJECT_NAME}-poison-handler"
        "Lambda function ${PROJECT_NAME}-message-replay:aws lambda get-function --function-name ${PROJECT_NAME}-message-replay"
        "SQS queue ${MAIN_QUEUE_NAME}:aws sqs get-queue-url --queue-name ${MAIN_QUEUE_NAME}"
        "SQS queue ${DLQ_NAME}:aws sqs get-queue-url --queue-name ${DLQ_NAME}"
        "DynamoDB table ${ORDER_TABLE_NAME}:aws dynamodb describe-table --table-name ${ORDER_TABLE_NAME}"
        "S3 bucket ${ARCHIVE_BUCKET_NAME}:aws s3 ls s3://${ARCHIVE_BUCKET_NAME}"
        "SNS topic ${SNS_TOPIC_NAME}:aws sns get-topic-attributes --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        "IAM role ${PROJECT_NAME}-processor-role:aws iam get-role --role-name ${PROJECT_NAME}-processor-role"
        "IAM role ${PROJECT_NAME}-poison-handler-role:aws iam get-role --role-name ${PROJECT_NAME}-poison-handler-role"
    )
    
    for resource in "${resources[@]}"; do
        local name=$(echo "${resource}" | cut -d: -f1)
        local command=$(echo "${resource}" | cut -d: -f2-)
        
        if eval "${command}" &> /dev/null; then
            error "❌ ${name} still exists - cleanup may have failed"
            ((cleanup_errors++))
        else
            info "✅ ${name} successfully deleted"
        fi
    done
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        log "🎉 All resources cleaned up successfully!"
        return 0
    else
        error "❌ ${cleanup_errors} resources still exist - manual cleanup may be required"
        return 1
    fi
}

show_cleanup_summary() {
    log "📋 CLEANUP SUMMARY"
    cat << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Project Name:          ${PROJECT_NAME}
AWS Region:            ${AWS_REGION}
Cleanup Completed:     $(date)

🗑️  RESOURCES DELETED:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Lambda Functions:    3 functions
• Event Source Mappings
• SQS Queues:          2 queues
• CloudWatch Alarms:   3 alarms  
• DynamoDB Table:      1 table
• S3 Bucket:           1 bucket (with all contents)
• SNS Topic:           1 topic
• IAM Roles:           2 roles with policies
• Local Files:         Temporary files

💰 COST IMPACT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
All AWS resources have been deleted. You should no longer
incur charges related to this FIFO message processing system.

📋 LOG FILE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Cleanup log saved to: ${LOG_FILE}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# =============================================================================
# Main Functions
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up FIFO Message Processing System resources

OPTIONS:
    --dry-run           Show what would be deleted without making changes
    --force             Skip all confirmation prompts
    --partial           Partial cleanup mode (for failed deployments)
    --project-name      Specify project name (default: from .deployment_env)
    --region           Specify AWS region (default: from AWS CLI config)
    --help             Show this help message

EXAMPLES:
    $0                          # Interactive cleanup with confirmations
    $0 --dry-run               # Show what would be deleted
    $0 --force                 # Force cleanup without confirmations
    $0 --partial               # Cleanup after failed deployment

SAFETY FEATURES:
    • Double confirmation required for deletion
    • Dry-run mode to preview actions
    • Comprehensive validation after cleanup
    • Detailed logging of all operations

EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_CLEANUP=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --partial)
                PARTIAL_CLEANUP=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Header
    log "🧹 Starting FIFO Message Processing System Cleanup"
    log "📅 $(date)"
    log "📍 Log file: ${LOG_FILE}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warn "🔍 DRY RUN MODE - No resources will be deleted"
    fi
    
    if [[ "${PARTIAL_CLEANUP}" == "true" ]]; then
        warn "🔧 PARTIAL CLEANUP MODE - Cleaning up after failed deployment"
    fi
    
    # Main cleanup flow
    check_prerequisites
    load_environment
    
    if [[ "${PARTIAL_CLEANUP}" != "true" ]]; then
        confirm_deletion
    fi
    
    # Cleanup steps - order matters for dependencies
    log "🗑️  Starting resource cleanup..."
    
    delete_lambda_functions
    delete_sqs_queues
    delete_cloudwatch_alarms
    delete_dynamodb_table
    delete_s3_bucket
    delete_sns_topic
    delete_iam_roles
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        cleanup_local_files
        validate_cleanup
        show_cleanup_summary
        
        log "🎉 Cleanup completed successfully!"
        log "💰 All AWS resources have been deleted - no more charges will be incurred"
    else
        log "🔍 Dry run completed - no resources were deleted"
    fi
}

# Run main function
main "$@"