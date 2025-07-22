#!/bin/bash

# Long-term Data Archiving with S3 Glacier Deep Archive - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="s3-glacier-archiving"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_DIR="${SCRIPT_DIR}/../config"
CONFIG_FILE="$CONFIG_DIR/deployment-config.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS CLI is not configured or not authenticated."
        log "INFO" "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    log "INFO" "AWS Account ID: $account_id"
    log "INFO" "AWS Region: $region"
    log "INFO" "AWS User/Role: $user_arn"
    
    log "INFO" "Prerequisites check completed"
}

# Function to load deployment configuration
load_config() {
    log "INFO" "Loading deployment configuration..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "Configuration file not found: $CONFIG_FILE"
        log "ERROR" "This could mean:"
        log "ERROR" "  1. The deployment script was never run successfully"
        log "ERROR" "  2. The configuration file was deleted"
        log "ERROR" "  3. You're running this script from the wrong directory"
        log "INFO" ""
        log "INFO" "You can still manually clean up resources by providing them as arguments:"
        log "INFO" "  $0 --manual-cleanup BUCKET_NAME SNS_TOPIC_ARN"
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    log "INFO" "Configuration loaded:"
    log "INFO" "  AWS Region: ${AWS_REGION:-not set}"
    log "INFO" "  AWS Account ID: ${AWS_ACCOUNT_ID:-not set}"
    log "INFO" "  Bucket Name: ${BUCKET_NAME:-not set}"
    log "INFO" "  SNS Topic: ${SNS_TOPIC_NAME:-not set}"
    log "INFO" "  Topic ARN: ${TOPIC_ARN:-not set}"
    
    # Validate required variables
    if [ -z "${BUCKET_NAME:-}" ]; then
        log "ERROR" "BUCKET_NAME not found in configuration"
        exit 1
    fi
}

# Function to confirm deletion with user
confirm_deletion() {
    if [ "${1:-}" = "--force" ] || [ "${FORCE_DELETE:-}" = "true" ]; then
        log "INFO" "Force deletion enabled, skipping confirmation"
        return 0
    fi
    
    log "WARN" "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log "WARN" ""
    log "WARN" "This will permanently delete the following resources:"
    log "WARN" "  • S3 Bucket: ${BUCKET_NAME:-not set}"
    log "WARN" "  • All objects in the bucket (including archived data)"
    log "WARN" "  • SNS Topic: ${SNS_TOPIC_NAME:-not set}"
    log "WARN" "  • All associated configurations"
    log "WARN" ""
    log "WARN" "⚠️  DATA IN GLACIER DEEP ARCHIVE WILL BE PERMANENTLY LOST ⚠️"
    log "WARN" ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    echo
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    log "INFO" "User confirmed deletion. Proceeding with cleanup..."
}

# Function to check if bucket has objects in Glacier
check_glacier_objects() {
    log "INFO" "Checking for objects in Glacier storage classes..."
    
    local glacier_objects=0
    
    # Check for objects in GLACIER storage class
    if aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query "Contents[?StorageClass=='GLACIER']" --output text 2>/dev/null | grep -q .; then
        glacier_objects=1
        log "WARN" "Found objects in GLACIER storage class"
    fi
    
    # Check for objects in DEEP_ARCHIVE storage class
    if aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query "Contents[?StorageClass=='DEEP_ARCHIVE']" --output text 2>/dev/null | grep -q .; then
        glacier_objects=1
        log "WARN" "Found objects in DEEP_ARCHIVE storage class"
    fi
    
    if [ $glacier_objects -eq 1 ]; then
        log "WARN" ""
        log "WARN" "⚠️  GLACIER/DEEP ARCHIVE OBJECTS DETECTED ⚠️"
        log "WARN" ""
        log "WARN" "Some objects are in Glacier or Deep Archive storage classes."
        log "WARN" "Deleting these objects may incur early deletion charges:"
        log "WARN" "  • Glacier: Minimum 90-day storage charge"
        log "WARN" "  • Deep Archive: Minimum 180-day storage charge"
        log "WARN" ""
        log "WARN" "Objects younger than the minimum storage duration will incur"
        log "WARN" "pro-rated charges for the remaining time."
        log "WARN" ""
        
        if [ "${FORCE_DELETE:-}" != "true" ]; then
            read -p "Do you want to continue and potentially incur early deletion charges? Type 'yes': " -r
            echo
            
            if [[ ! $REPLY =~ ^yes$ ]]; then
                log "INFO" "Cleanup cancelled due to Glacier storage concerns"
                exit 0
            fi
        fi
    fi
}

# Function to remove S3 bucket notification configuration
remove_bucket_notifications() {
    log "INFO" "Removing S3 bucket notification configuration..."
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        # Remove notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket "$BUCKET_NAME" \
            --notification-configuration "{}" || {
            log "WARN" "Failed to remove notification configuration (may not exist)"
        }
        log "INFO" "✓ Bucket notification configuration removed"
    else
        log "WARN" "Bucket $BUCKET_NAME does not exist or is not accessible"
    fi
}

# Function to remove S3 bucket lifecycle configuration
remove_lifecycle_configuration() {
    log "INFO" "Removing S3 bucket lifecycle configuration..."
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        aws s3api delete-bucket-lifecycle \
            --bucket "$BUCKET_NAME" || {
            log "WARN" "Failed to remove lifecycle configuration (may not exist)"
        }
        log "INFO" "✓ Bucket lifecycle configuration removed"
    fi
}

# Function to remove S3 bucket inventory configuration
remove_inventory_configuration() {
    log "INFO" "Removing S3 bucket inventory configuration..."
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        aws s3api delete-bucket-inventory-configuration \
            --bucket "$BUCKET_NAME" \
            --id "Weekly-Inventory" || {
            log "WARN" "Failed to remove inventory configuration (may not exist)"
        }
        log "INFO" "✓ Bucket inventory configuration removed"
    fi
}

# Function to empty and delete S3 bucket
delete_s3_bucket() {
    log "INFO" "Deleting S3 bucket and all contents..."
    
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        log "WARN" "Bucket $BUCKET_NAME does not exist or is not accessible"
        return 0
    fi
    
    # Check if bucket has contents
    local object_count=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query 'KeyCount' --output text 2>/dev/null || echo "0")
    
    if [ "$object_count" -gt 0 ]; then
        log "INFO" "Bucket contains $object_count objects. Deleting all objects..."
        
        # Delete all object versions and delete markers (for versioned buckets)
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || {
            log "WARN" "Failed to delete object versions (may not be versioned)"
        }
        
        # Delete delete markers
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || {
            log "WARN" "Failed to delete markers (may not exist)"
        }
        
        # Force delete all remaining objects
        aws s3 rm "s3://$BUCKET_NAME" --recursive --force || {
            log "WARN" "Some objects may still remain"
        }
        
        log "INFO" "✓ All objects deleted from bucket"
    else
        log "INFO" "Bucket is already empty"
    fi
    
    # Delete the bucket
    aws s3api delete-bucket --bucket "$BUCKET_NAME"
    log "INFO" "✓ S3 bucket deleted: $BUCKET_NAME"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "INFO" "Deleting SNS topic..."
    
    if [ -n "${TOPIC_ARN:-}" ]; then
        # Check if topic exists
        if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &>/dev/null; then
            # Delete all subscriptions first
            local subscriptions=$(aws sns list-subscriptions-by-topic \
                --topic-arn "$TOPIC_ARN" \
                --query 'Subscriptions[].SubscriptionArn' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$subscriptions" ] && [ "$subscriptions" != "None" ]; then
                log "INFO" "Deleting SNS subscriptions..."
                for subscription in $subscriptions; do
                    if [ "$subscription" != "PendingConfirmation" ]; then
                        aws sns unsubscribe --subscription-arn "$subscription" || {
                            log "WARN" "Failed to delete subscription: $subscription"
                        }
                    fi
                done
            fi
            
            # Delete the topic
            aws sns delete-topic --topic-arn "$TOPIC_ARN"
            log "INFO" "✓ SNS topic deleted: $TOPIC_ARN"
        else
            log "WARN" "SNS topic does not exist or is not accessible: $TOPIC_ARN"
        fi
    else
        log "WARN" "SNS Topic ARN not found in configuration"
    fi
}

# Function to clean up local configuration files
cleanup_local_files() {
    log "INFO" "Cleaning up local configuration files..."
    
    if [ -d "$CONFIG_DIR" ]; then
        # List files being deleted
        log "INFO" "Removing configuration directory: $CONFIG_DIR"
        
        if [ -f "$CONFIG_FILE" ]; then
            log "INFO" "  • deployment-config.env"
        fi
        
        if [ -f "$CONFIG_DIR/lifecycle-config.json" ]; then
            log "INFO" "  • lifecycle-config.json"
        fi
        
        if [ -f "$CONFIG_DIR/notification-config.json" ]; then
            log "INFO" "  • notification-config.json"
        fi
        
        if [ -f "$CONFIG_DIR/inventory-config.json" ]; then
            log "INFO" "  • inventory-config.json"
        fi
        
        if [ -d "$CONFIG_DIR/sample-data" ]; then
            log "INFO" "  • sample-data/ directory"
        fi
        
        # Remove the entire config directory
        rm -rf "$CONFIG_DIR"
        log "INFO" "✓ Local configuration files cleaned up"
    else
        log "INFO" "No local configuration files to clean up"
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log "INFO" "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check if bucket still exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        log "ERROR" "✗ S3 bucket still exists: $BUCKET_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    else
        log "INFO" "✓ S3 bucket successfully deleted"
    fi
    
    # Check if SNS topic still exists
    if [ -n "${TOPIC_ARN:-}" ]; then
        if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &>/dev/null; then
            log "ERROR" "✗ SNS topic still exists: $TOPIC_ARN"
            cleanup_errors=$((cleanup_errors + 1))
        else
            log "INFO" "✓ SNS topic successfully deleted"
        fi
    fi
    
    # Check if config directory still exists
    if [ -d "$CONFIG_DIR" ]; then
        log "ERROR" "✗ Configuration directory still exists: $CONFIG_DIR"
        cleanup_errors=$((cleanup_errors + 1))
    else
        log "INFO" "✓ Configuration files successfully cleaned up"
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        log "INFO" "✓ Cleanup validation successful - all resources removed"
        return 0
    else
        log "ERROR" "✗ Cleanup validation failed - $cleanup_errors errors found"
        return 1
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log "INFO" ""
    log "INFO" "🧹 CLEANUP SUMMARY"
    log "INFO" "=================="
    log "INFO" "✓ S3 bucket and all contents removed"
    log "INFO" "✓ SNS topic and subscriptions removed"
    log "INFO" "✓ All bucket configurations removed"
    log "INFO" "✓ Local configuration files cleaned up"
    log "INFO" ""
    log "INFO" "💰 COST IMPACT"
    log "INFO" "==============="
    log "INFO" "• Storage charges stopped immediately"
    log "INFO" "• Early deletion charges may apply for objects in Glacier/Deep Archive"
    log "INFO" "• Check your next AWS bill for any early deletion fees"
    log "INFO" ""
    log "INFO" "✅ All resources have been successfully removed!"
    log "INFO" "   No further charges will be incurred for this deployment."
}

# Function for manual cleanup when config is missing
manual_cleanup() {
    local bucket_name="$1"
    local topic_arn="${2:-}"
    
    log "INFO" "Starting manual cleanup mode..."
    log "INFO" "Bucket: $bucket_name"
    log "INFO" "Topic ARN: ${topic_arn:-not provided}"
    
    # Set variables for cleanup functions
    export BUCKET_NAME="$bucket_name"
    export TOPIC_ARN="$topic_arn"
    
    confirm_deletion "$@"
    
    if [ -n "$bucket_name" ]; then
        check_glacier_objects
        remove_bucket_notifications
        remove_lifecycle_configuration
        remove_inventory_configuration
        delete_s3_bucket
    fi
    
    if [ -n "$topic_arn" ]; then
        delete_sns_topic
    fi
    
    log "INFO" "Manual cleanup completed"
}

# Main cleanup function
main() {
    log "INFO" "Starting S3 Glacier Deep Archive cleanup..."
    log "INFO" "Cleanup started at $(date)"
    
    # Initialize log file
    echo "S3 Glacier Deep Archive Cleanup Log" > "$LOG_FILE"
    echo "Started at $(date)" >> "$LOG_FILE"
    echo "======================================" >> "$LOG_FILE"
    
    # Check for manual cleanup mode
    if [ "${1:-}" = "--manual-cleanup" ]; then
        shift
        if [ $# -lt 1 ]; then
            log "ERROR" "Manual cleanup requires at least bucket name"
            log "INFO" "Usage: $0 --manual-cleanup BUCKET_NAME [SNS_TOPIC_ARN]"
            exit 1
        fi
        manual_cleanup "$@"
        return
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_config
    confirm_deletion "$@"
    check_glacier_objects
    remove_bucket_notifications
    remove_lifecycle_configuration  
    remove_inventory_configuration
    delete_sns_topic
    delete_s3_bucket
    cleanup_local_files
    validate_cleanup
    show_cleanup_summary
    
    log "INFO" "Cleanup completed successfully at $(date)"
}

# Handle script interruption
cleanup_on_error() {
    log "ERROR" "Cleanup interrupted. Some resources may still exist."
    log "INFO" "Check AWS console and re-run script if needed."
    exit 1
}

# Set up error handling
trap cleanup_on_error INT TERM ERR

# Check if running in dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log "INFO" "Running in dry-run mode - no resources will be deleted"
    check_prerequisites
    if [ -f "$CONFIG_FILE" ]; then
        load_config
        log "INFO" "Resources that would be deleted:"
        log "INFO" "  S3 Bucket: $BUCKET_NAME"
        log "INFO" "  SNS Topic: ${TOPIC_ARN:-not set}"
        log "INFO" "  Configuration files in: $CONFIG_DIR"
    else
        log "WARN" "Configuration file not found. Manual cleanup would be required."
    fi
    exit 0
fi

# Show help if requested
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "S3 Glacier Deep Archive Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run                Show what would be deleted without doing it"
    echo "  --force                  Skip confirmation prompts"
    echo "  --manual-cleanup BUCKET [TOPIC_ARN]"
    echo "                          Clean up resources manually when config is missing"
    echo "  --help, -h              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_DELETE=true       Same as --force flag"
    echo ""
    echo "Examples:"
    echo "  $0                      Normal cleanup with confirmations"
    echo "  $0 --force              Cleanup without confirmations"
    echo "  $0 --dry-run            Preview what would be deleted"
    echo "  $0 --manual-cleanup my-bucket-123 arn:aws:sns:us-east-1:123:topic"
    exit 0
fi

# Run main cleanup
main "$@"