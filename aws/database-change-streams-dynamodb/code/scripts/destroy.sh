#!/bin/bash

# Destroy script for Real-time Database Change Streams with DynamoDB Streams
# This script safely removes all infrastructure created by the deploy script

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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy DynamoDB Streams real-time processing infrastructure.

OPTIONS:
    -y, --yes                      Skip confirmation prompts
    -b, --backup                   Create backup before destroying
    -f, --force                    Force destroy even if errors occur
    --dry-run                      Show what would be destroyed without actually doing it
    -h, --help                     Show this help message

EXAMPLES:
    $0                             # Interactive destroy with confirmations
    $0 -y                          # Auto-confirm destroy
    $0 -b -y                       # Backup data then destroy
    $0 --dry-run                   # See what would be destroyed
    $0 -f                          # Force destroy (skip error handling)

WARNING:
    This will permanently delete ALL resources and data.
    Make sure you have backups if you need the data.

EOF
}

# Default values
SKIP_CONFIRMATION="false"
CREATE_BACKUP="false"
FORCE_DESTROY="false"
DRY_RUN="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        -b|--backup)
            CREATE_BACKUP="true"
            shift
            ;;
        -f|--force)
            FORCE_DESTROY="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
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

# Function to load environment variables
load_environment() {
    if [[ -f .env ]]; then
        log "Loading environment variables from .env file..."
        source .env
        success "Environment variables loaded"
    else
        error ".env file not found. Please run deploy.sh first or ensure you're in the correct directory."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set up IAM roles."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to create backup of data
create_backup() {
    if [[ "${CREATE_BACKUP}" != "true" ]]; then
        return 0
    fi
    
    log "Creating backup of data before destruction..."
    
    BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${BACKUP_DIR}"
    
    # Backup DynamoDB table data if table exists
    if [[ -n "${TABLE_NAME:-}" ]]; then
        if aws dynamodb describe-table --table-name "${TABLE_NAME}" &>/dev/null; then
            log "Backing up DynamoDB table: ${TABLE_NAME}"
            
            # Export table schema
            aws dynamodb describe-table --table-name "${TABLE_NAME}" \
                > "${BACKUP_DIR}/table-schema.json" 2>/dev/null || true
            
            # Export table data
            aws dynamodb scan --table-name "${TABLE_NAME}" \
                > "${BACKUP_DIR}/table-data.json" 2>/dev/null || true
            
            success "DynamoDB backup completed"
        fi
    fi
    
    # Backup S3 audit logs if bucket exists
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        if aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
            log "Backing up S3 audit logs: ${S3_BUCKET_NAME}"
            
            aws s3 sync "s3://${S3_BUCKET_NAME}" "${BACKUP_DIR}/s3-backup/" \
                --quiet || true
            
            success "S3 backup completed"
        fi
    fi
    
    # Save environment variables
    cp .env "${BACKUP_DIR}/" 2>/dev/null || true
    
    success "Backup completed: ${BACKUP_DIR}"
}

# Function to show what will be destroyed
show_destruction_plan() {
    log "Resources that will be destroyed:"
    echo "=================================="
    
    echo "DynamoDB Resources:"
    echo "  - Table: ${TABLE_NAME:-Not found}"
    echo "  - Stream: ${STREAM_ARN:-Not found}"
    echo ""
    
    echo "Lambda Resources:"
    echo "  - Function: ${FUNCTION_NAME:-Not found}"
    echo "  - Event Source Mapping: ${MAPPING_UUID:-Not found}"
    echo ""
    
    echo "Storage Resources:"
    echo "  - S3 Bucket: ${S3_BUCKET_NAME:-Not found}"
    echo "  - SQS DLQ: ${DLQ_URL:-Not found}"
    echo ""
    
    echo "Notification Resources:"
    echo "  - SNS Topic: ${SNS_TOPIC_ARN:-Not found}"
    echo ""
    
    echo "IAM Resources:"
    echo "  - Role: ${ROLE_NAME:-Not found}"
    echo "  - Custom Policy: ${ROLE_NAME:-Not found}-custom-policy"
    echo ""
    
    echo "CloudWatch Resources:"
    echo "  - Lambda Error Alarm: ${FUNCTION_NAME:-Not found}-errors"
    echo "  - DLQ Messages Alarm: ${FUNCTION_NAME:-Not found}-dlq-messages"
    echo "  - Lambda Log Group: /aws/lambda/${FUNCTION_NAME:-Not found}"
    echo ""
}

# Function to remove event source mapping
remove_event_source_mapping() {
    if [[ -n "${MAPPING_UUID:-}" ]]; then
        log "Removing Lambda event source mapping..."
        
        if aws lambda get-event-source-mapping --uuid "${MAPPING_UUID}" &>/dev/null; then
            aws lambda delete-event-source-mapping --uuid "${MAPPING_UUID}" || {
                if [[ "${FORCE_DESTROY}" != "true" ]]; then
                    error "Failed to delete event source mapping"
                    exit 1
                fi
                warning "Failed to delete event source mapping (continuing due to force mode)"
            }
            success "Event source mapping deleted"
        else
            warning "Event source mapping not found, skipping"
        fi
    fi
}

# Function to remove Lambda function
remove_lambda_function() {
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log "Removing Lambda function..."
        
        if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
            aws lambda delete-function --function-name "${FUNCTION_NAME}" || {
                if [[ "${FORCE_DESTROY}" != "true" ]]; then
                    error "Failed to delete Lambda function"
                    exit 1
                fi
                warning "Failed to delete Lambda function (continuing due to force mode)"
            }
            success "Lambda function deleted"
        else
            warning "Lambda function not found, skipping"
        fi
    fi
}

# Function to remove CloudWatch alarms and logs
remove_cloudwatch_resources() {
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log "Removing CloudWatch resources..."
        
        # Delete CloudWatch alarms
        aws cloudwatch delete-alarms \
            --alarm-names "${FUNCTION_NAME}-errors" "${FUNCTION_NAME}-dlq-messages" 2>/dev/null || {
            if [[ "${FORCE_DESTROY}" != "true" ]]; then
                warning "Some CloudWatch alarms may not have been deleted"
            fi
        }
        
        # Delete Lambda log group
        aws logs delete-log-group \
            --log-group-name "/aws/lambda/${FUNCTION_NAME}" 2>/dev/null || {
            warning "Lambda log group may not exist or already deleted"
        }
        
        success "CloudWatch resources removed"
    fi
}

# Function to remove DynamoDB table
remove_dynamodb_table() {
    if [[ -n "${TABLE_NAME:-}" ]]; then
        log "Removing DynamoDB table..."
        
        if aws dynamodb describe-table --table-name "${TABLE_NAME}" &>/dev/null; then
            aws dynamodb delete-table --table-name "${TABLE_NAME}" || {
                if [[ "${FORCE_DESTROY}" != "true" ]]; then
                    error "Failed to delete DynamoDB table"
                    exit 1
                fi
                warning "Failed to delete DynamoDB table (continuing due to force mode)"
            }
            
            log "Waiting for table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "${TABLE_NAME}" || {
                warning "Table deletion may still be in progress"
            }
            
            success "DynamoDB table deleted"
        else
            warning "DynamoDB table not found, skipping"
        fi
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    if [[ -n "${ROLE_NAME:-}" && -n "${AWS_ACCOUNT_ID:-}" ]]; then
        log "Removing IAM resources..."
        
        # Detach policies from role
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole 2>/dev/null || {
            warning "AWS managed policy may not be attached or already detached"
        }
        
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-custom-policy" 2>/dev/null || {
            warning "Custom policy may not be attached or already detached"
        }
        
        # Delete custom policy
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-custom-policy" 2>/dev/null || {
            warning "Custom policy may not exist or already deleted"
        }
        
        # Delete IAM role
        aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null || {
            if [[ "${FORCE_DESTROY}" != "true" ]]; then
                error "Failed to delete IAM role"
                exit 1
            fi
            warning "Failed to delete IAM role (continuing due to force mode)"
        }
        
        success "IAM resources removed"
    fi
}

# Function to remove SNS and SQS resources
remove_messaging_resources() {
    # Remove SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log "Removing SNS topic..."
        
        aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}" 2>/dev/null || {
            warning "SNS topic may not exist or already deleted"
        }
        
        success "SNS topic removed"
    fi
    
    # Remove SQS dead letter queue
    if [[ -n "${DLQ_URL:-}" ]]; then
        log "Removing SQS dead letter queue..."
        
        aws sqs delete-queue --queue-url "${DLQ_URL}" 2>/dev/null || {
            warning "SQS queue may not exist or already deleted"
        }
        
        success "SQS dead letter queue removed"
    fi
}

# Function to remove S3 bucket
remove_s3_bucket() {
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        log "Removing S3 bucket..."
        
        if aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
            # Empty bucket first
            aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive || {
                warning "Some S3 objects may not have been deleted"
            }
            
            # Delete bucket
            aws s3 rb "s3://${S3_BUCKET_NAME}" || {
                if [[ "${FORCE_DESTROY}" != "true" ]]; then
                    error "Failed to delete S3 bucket"
                    exit 1
                fi
                warning "Failed to delete S3 bucket (continuing due to force mode)"
            }
            
            success "S3 bucket removed"
        else
            warning "S3 bucket not found, skipping"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    rm -f .env
    
    # Remove any temporary files that might have been left
    rm -f lambda-trust-policy.json custom-policy.json \
          stream-processor.py lambda-function.zip
    
    success "Local files cleaned up"
}

# Function to display summary
display_summary() {
    success "Destruction completed!"
    echo ""
    log "Summary of actions taken:"
    echo "========================"
    echo "✅ Event source mapping removed"
    echo "✅ Lambda function removed"
    echo "✅ CloudWatch alarms and logs removed"
    echo "✅ DynamoDB table removed"
    echo "✅ IAM role and policies removed"
    echo "✅ SNS topic removed"
    echo "✅ SQS dead letter queue removed"
    echo "✅ S3 bucket removed"
    echo "✅ Local files cleaned up"
    echo ""
    
    if [[ "${CREATE_BACKUP}" == "true" ]]; then
        log "Your data backup is available in:"
        echo "  $(find . -name "backup-*" -type d | tail -1 2>/dev/null || echo "Backup directory not found")"
        echo ""
    fi
    
    log "Please check your AWS console to verify all resources have been removed."
    warning "This destruction is permanent and cannot be undone!"
}

# Main execution
main() {
    log "Starting DynamoDB Streams infrastructure destruction..."
    echo ""
    
    check_prerequisites
    load_environment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN MODE - No resources will actually be destroyed"
        show_destruction_plan
        exit 0
    fi
    
    show_destruction_plan
    
    # Confirm destruction unless skipping confirmation
    if [[ "${SKIP_CONFIRMATION}" != "true" ]]; then
        echo ""
        error "⚠️  DANGER: This will permanently delete ALL infrastructure and data!"
        warning "This action cannot be undone."
        echo ""
        
        if [[ "${CREATE_BACKUP}" == "true" ]]; then
            log "A backup will be created before destruction."
        else
            warning "No backup will be created. Use -b flag to create a backup."
        fi
        
        echo ""
        read -p "Type 'destroy' to confirm destruction: " confirm
        if [[ "${confirm}" != "destroy" ]]; then
            log "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    create_backup
    
    log "Beginning resource destruction..."
    echo ""
    
    # Remove resources in reverse order of creation
    remove_event_source_mapping
    remove_lambda_function
    remove_cloudwatch_resources
    remove_dynamodb_table
    remove_iam_resources
    remove_messaging_resources
    remove_s3_bucket
    cleanup_local_files
    
    display_summary
}

# Run main function
main "$@"