#!/bin/bash

# Audio Processing Pipelines with AWS Elemental MediaConvert - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
ENV_FILE="${SCRIPT_DIR}/deploy_environment.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Confirmation prompt
confirm() {
    read -p "$(echo -e "${YELLOW}⚠️  ${1} (y/N): ${NC}")" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Load environment variables
load_environment() {
    if [[ -f "${ENV_FILE}" ]]; then
        info "Loading environment from ${ENV_FILE}"
        set -a  # Automatically export variables
        source "${ENV_FILE}"
        set +a
        success "Environment loaded successfully"
    else
        warning "Environment file not found: ${ENV_FILE}"
        info "Please provide resource identifiers manually or run with --manual mode"
        
        # Try to get current AWS settings
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Prompt for manual input
        read -p "Enter random suffix used during deployment: " RANDOM_SUFFIX
        export RANDOM_SUFFIX
        
        # Reconstruct resource names
        export BUCKET_INPUT="audio-processing-input-${RANDOM_SUFFIX}"
        export BUCKET_OUTPUT="audio-processing-output-${RANDOM_SUFFIX}"
        export LAMBDA_FUNCTION="audio-processing-trigger-${RANDOM_SUFFIX}"
        export MEDIACONVERT_ROLE="MediaConvertRole-${RANDOM_SUFFIX}"
        export SNS_TOPIC="audio-processing-notifications-${RANDOM_SUFFIX}"
        
        info "Using reconstructed resource names with suffix: ${RANDOM_SUFFIX}"
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI not found. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up credentials."
    fi
    
    success "Prerequisites check passed"
}

# Get MediaConvert endpoint
get_mediaconvert_endpoint() {
    if [[ -z "${MEDIACONVERT_ENDPOINT}" ]]; then
        info "Getting MediaConvert endpoint..."
        export MEDIACONVERT_ENDPOINT=$(aws mediaconvert describe-endpoints \
            --region ${AWS_REGION} \
            --query Endpoints[0].Url --output text)
        info "MediaConvert endpoint: ${MEDIACONVERT_ENDPOINT}"
    fi
}

# Remove S3 event notifications
remove_s3_notifications() {
    info "Removing S3 event notifications..."
    
    if aws s3api head-bucket --bucket "${BUCKET_INPUT}" 2>/dev/null; then
        aws s3api put-bucket-notification-configuration \
            --bucket ${BUCKET_INPUT} \
            --notification-configuration '{}' 2>/dev/null || true
        success "Removed S3 event notifications"
    else
        warning "Input bucket ${BUCKET_INPUT} not found"
    fi
}

# Delete Lambda function and role
delete_lambda_function() {
    info "Deleting Lambda function and role..."
    
    # Delete Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION}" 2>/dev/null; then
        aws lambda delete-function --function-name ${LAMBDA_FUNCTION}
        success "Deleted Lambda function: ${LAMBDA_FUNCTION}"
    else
        warning "Lambda function ${LAMBDA_FUNCTION} not found"
    fi
    
    # Delete Lambda role policies
    if aws iam get-role --role-name "${LAMBDA_FUNCTION}-role" 2>/dev/null; then
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name ${LAMBDA_FUNCTION}-role \
            --policy-name MediaConvertAccess 2>/dev/null || true
        
        # Detach managed policy
        aws iam detach-role-policy \
            --role-name ${LAMBDA_FUNCTION}-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${LAMBDA_FUNCTION}-role
        success "Deleted Lambda role: ${LAMBDA_FUNCTION}-role"
    else
        warning "Lambda role ${LAMBDA_FUNCTION}-role not found"
    fi
}

# Delete MediaConvert resources
delete_mediaconvert_resources() {
    info "Deleting MediaConvert resources..."
    
    get_mediaconvert_endpoint
    
    # Delete job template
    if [[ -n "${TEMPLATE_ARN}" ]] || aws mediaconvert get-job-template \
        --endpoint-url ${MEDIACONVERT_ENDPOINT} \
        --name "AudioProcessingTemplate-${RANDOM_SUFFIX}" 2>/dev/null; then
        
        aws mediaconvert delete-job-template \
            --endpoint-url ${MEDIACONVERT_ENDPOINT} \
            --name "AudioProcessingTemplate-${RANDOM_SUFFIX}" 2>/dev/null || true
        success "Deleted job template"
    else
        warning "Job template AudioProcessingTemplate-${RANDOM_SUFFIX} not found"
    fi
    
    # Delete preset
    if [[ -n "${PRESET_ARN}" ]] || aws mediaconvert get-preset \
        --endpoint-url ${MEDIACONVERT_ENDPOINT} \
        --name "EnhancedAudioPreset-${RANDOM_SUFFIX}" 2>/dev/null; then
        
        aws mediaconvert delete-preset \
            --endpoint-url ${MEDIACONVERT_ENDPOINT} \
            --name "EnhancedAudioPreset-${RANDOM_SUFFIX}" 2>/dev/null || true
        success "Deleted enhanced audio preset"
    else
        warning "Enhanced audio preset EnhancedAudioPreset-${RANDOM_SUFFIX} not found"
    fi
}

# Delete MediaConvert IAM role
delete_mediaconvert_role() {
    info "Deleting MediaConvert IAM role..."
    
    if aws iam get-role --role-name "${MEDIACONVERT_ROLE}" 2>/dev/null; then
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name ${MEDIACONVERT_ROLE} \
            --policy-name MediaConvertS3SNSPolicy 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${MEDIACONVERT_ROLE}
        success "Deleted MediaConvert role: ${MEDIACONVERT_ROLE}"
    else
        warning "MediaConvert role ${MEDIACONVERT_ROLE} not found"
    fi
}

# Delete S3 buckets
delete_s3_buckets() {
    info "Deleting S3 buckets and contents..."
    
    # Delete input bucket
    if aws s3api head-bucket --bucket "${BUCKET_INPUT}" 2>/dev/null; then
        info "Emptying input bucket: ${BUCKET_INPUT}"
        aws s3 rm s3://${BUCKET_INPUT} --recursive 2>/dev/null || true
        
        # Delete all versions and delete markers
        aws s3api delete-objects --bucket "${BUCKET_INPUT}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_INPUT}" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || true
        
        aws s3api delete-objects --bucket "${BUCKET_INPUT}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_INPUT}" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || true
        
        aws s3 rb s3://${BUCKET_INPUT} --force
        success "Deleted input bucket: ${BUCKET_INPUT}"
    else
        warning "Input bucket ${BUCKET_INPUT} not found"
    fi
    
    # Delete output bucket
    if aws s3api head-bucket --bucket "${BUCKET_OUTPUT}" 2>/dev/null; then
        info "Emptying output bucket: ${BUCKET_OUTPUT}"
        aws s3 rm s3://${BUCKET_OUTPUT} --recursive 2>/dev/null || true
        
        # Delete all versions and delete markers
        aws s3api delete-objects --bucket "${BUCKET_OUTPUT}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_OUTPUT}" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || true
        
        aws s3api delete-objects --bucket "${BUCKET_OUTPUT}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_OUTPUT}" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || true
        
        aws s3 rb s3://${BUCKET_OUTPUT} --force
        success "Deleted output bucket: ${BUCKET_OUTPUT}"
    else
        warning "Output bucket ${BUCKET_OUTPUT} not found"
    fi
}

# Delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    info "Deleting CloudWatch dashboard..."
    
    if aws cloudwatch get-dashboard --dashboard-name "AudioProcessingPipeline-${RANDOM_SUFFIX}" 2>/dev/null; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "AudioProcessingPipeline-${RANDOM_SUFFIX}"
        success "Deleted CloudWatch dashboard: AudioProcessingPipeline-${RANDOM_SUFFIX}"
    else
        warning "CloudWatch dashboard AudioProcessingPipeline-${RANDOM_SUFFIX} not found"
    fi
}

# Delete SNS topic
delete_sns_topic() {
    info "Deleting SNS topic..."
    
    if [[ -n "${SNS_TOPIC_ARN}" ]]; then
        aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN} 2>/dev/null || true
        success "Deleted SNS topic: ${SNS_TOPIC_ARN}"
    else
        # Try to find topic by name
        local TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC}')].TopicArn" --output text 2>/dev/null)
        if [[ -n "${TOPIC_ARN}" ]]; then
            aws sns delete-topic --topic-arn ${TOPIC_ARN}
            success "Deleted SNS topic: ${TOPIC_ARN}"
        else
            warning "SNS topic ${SNS_TOPIC} not found"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "${ENV_FILE}" ]]; then
        rm -f "${ENV_FILE}"
        success "Removed environment file: ${ENV_FILE}"
    fi
    
    # Remove any temporary files that might exist
    rm -f "${SCRIPT_DIR}"/*.json 2>/dev/null || true
    rm -f "${SCRIPT_DIR}"/*.py 2>/dev/null || true
    rm -f "${SCRIPT_DIR}"/*.zip 2>/dev/null || true
    rm -f "${SCRIPT_DIR}"/*.txt 2>/dev/null || true
    
    success "Cleaned up local files"
}

# Verify cleanup
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local ERRORS=0
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "${BUCKET_INPUT}" 2>/dev/null; then
        warning "Input bucket ${BUCKET_INPUT} still exists"
        ((ERRORS++))
    fi
    
    if aws s3api head-bucket --bucket "${BUCKET_OUTPUT}" 2>/dev/null; then
        warning "Output bucket ${BUCKET_OUTPUT} still exists"
        ((ERRORS++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION}" 2>/dev/null; then
        warning "Lambda function ${LAMBDA_FUNCTION} still exists"
        ((ERRORS++))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${MEDIACONVERT_ROLE}" 2>/dev/null; then
        warning "MediaConvert role ${MEDIACONVERT_ROLE} still exists"
        ((ERRORS++))
    fi
    
    if aws iam get-role --role-name "${LAMBDA_FUNCTION}-role" 2>/dev/null; then
        warning "Lambda role ${LAMBDA_FUNCTION}-role still exists"
        ((ERRORS++))
    fi
    
    # Check MediaConvert resources
    if aws mediaconvert get-job-template \
        --endpoint-url ${MEDIACONVERT_ENDPOINT} \
        --name "AudioProcessingTemplate-${RANDOM_SUFFIX}" 2>/dev/null; then
        warning "Job template AudioProcessingTemplate-${RANDOM_SUFFIX} still exists"
        ((ERRORS++))
    fi
    
    if aws mediaconvert get-preset \
        --endpoint-url ${MEDIACONVERT_ENDPOINT} \
        --name "EnhancedAudioPreset-${RANDOM_SUFFIX}" 2>/dev/null; then
        warning "Enhanced audio preset EnhancedAudioPreset-${RANDOM_SUFFIX} still exists"
        ((ERRORS++))
    fi
    
    if [[ ${ERRORS} -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed"
    else
        warning "Cleanup verification found ${ERRORS} resources that may need manual removal"
    fi
}

# Display help
show_help() {
    cat << EOF
Audio Processing Pipeline Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -f, --force         Skip confirmation prompts
    -v, --verify-only   Only verify cleanup, don't delete resources
    --manual           Use manual resource identification mode

Examples:
    $0                  # Interactive cleanup with confirmations
    $0 --force          # Non-interactive cleanup
    $0 --verify-only    # Check what resources would be deleted
    $0 --manual         # Manual resource identification mode

EOF
}

# Parse command line arguments
parse_args() {
    FORCE_MODE=false
    VERIFY_ONLY=false
    MANUAL_MODE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            -v|--verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            --manual)
                MANUAL_MODE=true
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Main cleanup function
main() {
    parse_args "$@"
    
    log "Starting Audio Processing Pipeline Cleanup"
    log "Timestamp: $(date)"
    log "Script: ${0}"
    log "Log file: ${LOG_FILE}"
    
    check_prerequisites
    load_environment
    
    if [[ "${VERIFY_ONLY}" == "true" ]]; then
        info "Verification mode - checking resources..."
        verify_cleanup
        exit 0
    fi
    
    log ""
    log "Resources to be deleted:"
    log "- Input S3 Bucket: ${BUCKET_INPUT}"
    log "- Output S3 Bucket: ${BUCKET_OUTPUT}"
    log "- Lambda Function: ${LAMBDA_FUNCTION}"
    log "- MediaConvert Role: ${MEDIACONVERT_ROLE}"
    log "- SNS Topic: ${SNS_TOPIC}"
    log "- CloudWatch Dashboard: AudioProcessingPipeline-${RANDOM_SUFFIX}"
    log "- Job Template: AudioProcessingTemplate-${RANDOM_SUFFIX}"
    log "- Enhanced Preset: EnhancedAudioPreset-${RANDOM_SUFFIX}"
    log ""
    
    if [[ "${FORCE_MODE}" != "true" ]]; then
        confirm "Are you sure you want to delete all these resources? This action cannot be undone."
    fi
    
    # Execute cleanup steps in reverse order of creation
    remove_s3_notifications
    delete_lambda_function
    delete_mediaconvert_resources
    delete_mediaconvert_role
    delete_s3_buckets
    delete_cloudwatch_dashboard
    delete_sns_topic
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Final success message
    log ""
    success "🎉 Audio Processing Pipeline Cleanup Completed Successfully!"
    log ""
    log "All resources have been removed from your AWS account."
    log "Log file location: ${LOG_FILE}"
    log ""
    warning "Note: Some AWS services may have short delays before resources are fully removed."
    warning "If you encounter any issues, please check the AWS console or run with --verify-only"
}

# Execute main function
main "$@"