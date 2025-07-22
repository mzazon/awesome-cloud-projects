#!/bin/bash

# Long-term Data Archiving with S3 Glacier Deep Archive - Deployment Script
# This script deploys the infrastructure for automated S3 lifecycle management
# and long-term archiving with Glacier Deep Archive

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="s3-glacier-archiving"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CONFIG_DIR="${SCRIPT_DIR}/../config"

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
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS CLI is not configured or not authenticated."
        log "INFO" "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Get AWS account info
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    log "INFO" "AWS Account ID: $account_id"
    log "INFO" "AWS Region: $region"
    log "INFO" "AWS User/Role: $user_arn"
    
    # Check required permissions
    log "INFO" "Checking required AWS permissions..."
    
    # Check S3 permissions
    if ! aws iam simulate-principal-policy \
        --policy-source-arn "$user_arn" \
        --action-names "s3:CreateBucket" "s3:GetBucketLocation" "s3:ListBucket" \
        --resource-arns "arn:aws:s3:::*" \
        --query 'EvaluationResults[?Decision==`denied`].ActionName' \
        --output text 2>/dev/null | grep -q .; then
        log "INFO" "S3 permissions verified"
    else
        log "WARN" "Some S3 permissions may be missing. Deployment may fail."
    fi
    
    # Check SNS permissions  
    if ! aws iam simulate-principal-policy \
        --policy-source-arn "$user_arn" \
        --action-names "sns:CreateTopic" "sns:Subscribe" \
        --resource-arns "arn:aws:sns:$region:$account_id:*" \
        --query 'EvaluationResults[?Decision==`denied`].ActionName' \
        --output text 2>/dev/null | grep -q .; then
        log "INFO" "SNS permissions verified"
    else
        log "WARN" "Some SNS permissions may be missing. Deployment may fail."
    fi
    
    log "INFO" "Prerequisites check completed"
}

# Function to generate unique resource names
generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    # Generate random suffix for unique naming
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set environment variables for resource names
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export BUCKET_NAME="long-term-archive-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="s3-archive-notifications-${RANDOM_SUFFIX}"
    
    log "INFO" "Resource names generated:"
    log "INFO" "  Bucket Name: $BUCKET_NAME"
    log "INFO" "  SNS Topic: $SNS_TOPIC_NAME"
    log "INFO" "  Random Suffix: $RANDOM_SUFFIX"
    
    # Save configuration for cleanup
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/deployment-config.env" << EOF
# Deployment Configuration
# Generated on $(date)
AWS_REGION="$AWS_REGION"
AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
BUCKET_NAME="$BUCKET_NAME"
SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    log "INFO" "Configuration saved to $CONFIG_DIR/deployment-config.env"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "INFO" "Creating S3 bucket for long-term archiving..."
    
    # Create bucket with appropriate configuration
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning for better data protection
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    log "INFO" "S3 bucket created and configured: $BUCKET_NAME"
}

# Function to configure lifecycle policies
configure_lifecycle_policies() {
    log "INFO" "Configuring S3 lifecycle policies for automated archiving..."
    
    # Create lifecycle configuration
    cat > "$CONFIG_DIR/lifecycle-config.json" << 'EOF'
{
  "Rules": [
    {
      "ID": "Archive files with archives prefix after 90 days",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "archives/"
      },
      "Transitions": [
        {
          "Days": 90,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    },
    {
      "ID": "Archive all files after 180 days",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
      "Transitions": [
        {
          "Days": 180,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    },
    {
      "ID": "Delete incomplete multipart uploads after 7 days",
      "Status": "Enabled",
      "Filter": {
        "Prefix": ""
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
EOF
    
    # Apply lifecycle configuration
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file://"$CONFIG_DIR/lifecycle-config.json"
    
    log "INFO" "Lifecycle policies configured successfully"
}

# Function to create SNS topic and notifications
setup_notifications() {
    log "INFO" "Setting up SNS topic for archive notifications..."
    
    # Create SNS topic
    export TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --output text --query 'TopicArn')
    
    log "INFO" "SNS topic created: $TOPIC_ARN"
    
    # Create notification configuration
    cat > "$CONFIG_DIR/notification-config.json" << EOF
{
  "TopicConfigurations": [
    {
      "TopicArn": "$TOPIC_ARN",
      "Events": ["s3:LifecycleTransition"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".pdf"
            }
          ]
        }
      }
    }
  ]
}
EOF
    
    # Apply bucket notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration file://"$CONFIG_DIR/notification-config.json"
    
    # Update configuration file with topic ARN
    echo "TOPIC_ARN=\"$TOPIC_ARN\"" >> "$CONFIG_DIR/deployment-config.env"
    
    log "INFO" "Event notifications configured successfully"
    log "WARN" "Remember to subscribe to the SNS topic to receive notifications"
    log "INFO" "Subscribe with: aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
}

# Function to enable S3 inventory
enable_inventory() {
    log "INFO" "Enabling S3 inventory for archive tracking..."
    
    # Create inventory configuration
    cat > "$CONFIG_DIR/inventory-config.json" << EOF
{
  "Id": "Weekly-Inventory",
  "Destination": {
    "S3BucketDestination": {
      "Format": "CSV",
      "Bucket": "arn:aws:s3:::$BUCKET_NAME",
      "Prefix": "inventory-reports/"
    }
  },
  "IsEnabled": true,
  "IncludedObjectVersions": "Current",
  "Schedule": {
    "Frequency": "Weekly"
  },
  "OptionalFields": [
    "Size",
    "LastModifiedDate", 
    "StorageClass",
    "ETag",
    "ReplicationStatus"
  ]
}
EOF
    
    # Apply inventory configuration
    aws s3api put-bucket-inventory-configuration \
        --bucket "$BUCKET_NAME" \
        --id "Weekly-Inventory" \
        --inventory-configuration file://"$CONFIG_DIR/inventory-config.json"
    
    log "INFO" "Weekly inventory reporting enabled"
}

# Function to upload sample test data
upload_sample_data() {
    log "INFO" "Uploading sample test data..."
    
    # Create sample documents
    mkdir -p "$CONFIG_DIR/sample-data"
    
    # Create sample PDF document
    echo "This is a sample archived document for testing lifecycle policies" > "$CONFIG_DIR/sample-data/sample-document.txt"
    echo "Sample archive content - $(date)" > "$CONFIG_DIR/sample-data/archive-test.txt"
    
    # Upload to archives folder (90-day transition)
    aws s3 cp "$CONFIG_DIR/sample-data/sample-document.txt" "s3://$BUCKET_NAME/archives/sample-document.txt"
    aws s3 cp "$CONFIG_DIR/sample-data/archive-test.txt" "s3://$BUCKET_NAME/archives/archive-test.txt"
    
    # Upload to root folder (180-day transition)  
    aws s3 cp "$CONFIG_DIR/sample-data/sample-document.txt" "s3://$BUCKET_NAME/sample-document.txt"
    
    # Upload a file to simulate immediate Deep Archive (for testing restore)
    aws s3 cp "$CONFIG_DIR/sample-data/archive-test.txt" \
        "s3://$BUCKET_NAME/immediate-archive/archive-test.txt" \
        --storage-class DEEP_ARCHIVE
    
    log "INFO" "Sample data uploaded successfully"
    log "INFO" "Files uploaded:"
    log "INFO" "  archives/sample-document.txt (will archive after 90 days)"
    log "INFO" "  archives/archive-test.txt (will archive after 90 days)"
    log "INFO" "  sample-document.txt (will archive after 180 days)"
    log "INFO" "  immediate-archive/archive-test.txt (immediately in Deep Archive)"
}

# Function to validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Check bucket exists and is accessible
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        log "INFO" "✓ S3 bucket is accessible"
    else
        log "ERROR" "✗ S3 bucket is not accessible"
        return 1
    fi
    
    # Check lifecycle configuration
    if aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET_NAME" &>/dev/null; then
        log "INFO" "✓ Lifecycle policies are configured"
    else
        log "ERROR" "✗ Lifecycle policies are not configured"
        return 1
    fi
    
    # Check notification configuration
    if aws s3api get-bucket-notification-configuration --bucket "$BUCKET_NAME" &>/dev/null; then
        log "INFO" "✓ Event notifications are configured"
    else
        log "ERROR" "✗ Event notifications are not configured"
        return 1
    fi
    
    # Check inventory configuration
    if aws s3api get-bucket-inventory-configuration --bucket "$BUCKET_NAME" --id "Weekly-Inventory" &>/dev/null; then
        log "INFO" "✓ Inventory reporting is configured"
    else
        log "ERROR" "✗ Inventory reporting is not configured"
        return 1
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &>/dev/null; then
        log "INFO" "✓ SNS topic is accessible"
    else
        log "ERROR" "✗ SNS topic is not accessible"
        return 1
    fi
    
    # List uploaded files
    log "INFO" "Files in bucket:"
    aws s3 ls "s3://$BUCKET_NAME" --recursive | while read -r line; do
        log "INFO" "  $line"
    done
    
    log "INFO" "Deployment validation completed successfully"
}

# Function to display deployment summary
show_deployment_summary() {
    log "INFO" "Deployment completed successfully!"
    log "INFO" ""
    log "INFO" "📋 DEPLOYMENT SUMMARY"
    log "INFO" "====================="
    log "INFO" "S3 Bucket: $BUCKET_NAME"
    log "INFO" "SNS Topic: $TOPIC_ARN"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" ""
    log "INFO" "🔄 LIFECYCLE POLICIES"
    log "INFO" "====================="
    log "INFO" "• Files in 'archives/' folder: Archive after 90 days"
    log "INFO" "• All other files: Archive after 180 days"
    log "INFO" "• Incomplete multipart uploads: Delete after 7 days"
    log "INFO" ""
    log "INFO" "📬 NOTIFICATIONS"
    log "INFO" "================"
    log "INFO" "• PDF files transitioning to Deep Archive will trigger notifications"
    log "INFO" "• Subscribe to SNS topic to receive alerts:"
    log "INFO" "  aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    log "INFO" ""
    log "INFO" "📊 MONITORING"
    log "INFO" "============="
    log "INFO" "• Weekly inventory reports will be generated"
    log "INFO" "• Reports location: s3://$BUCKET_NAME/inventory-reports/"
    log "INFO" ""
    log "INFO" "🧪 TESTING"
    log "INFO" "=========="
    log "INFO" "• Sample files have been uploaded for testing"
    log "INFO" "• Test restore with:"
    log "INFO" "  aws s3api restore-object --bucket $BUCKET_NAME --key immediate-archive/archive-test.txt --restore-request 'Days=5,GlacierJobParameters={Tier=Bulk}'"
    log "INFO" ""
    log "INFO" "💰 COST OPTIMIZATION"
    log "INFO" "==================="
    log "INFO" "• Deep Archive storage: ~\$0.00099 per GB/month (75% less than S3 Standard)"
    log "INFO" "• Retrieval times: 9-12 hours (Standard), up to 48 hours (Bulk)"
    log "INFO" "• Plan retrieval operations carefully to manage costs"
    log "INFO" ""
    log "INFO" "🧹 CLEANUP"
    log "INFO" "=========="
    log "INFO" "• Run './destroy.sh' to remove all resources"
    log "INFO" "• Configuration saved in: $CONFIG_DIR/deployment-config.env"
}

# Main deployment function
main() {
    log "INFO" "Starting S3 Glacier Deep Archive deployment..."
    log "INFO" "Deployment started at $(date)"
    
    # Initialize log file
    echo "S3 Glacier Deep Archive Deployment Log" > "$LOG_FILE"
    echo "Started at $(date)" >> "$LOG_FILE"
    echo "======================================" >> "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    generate_resource_names
    create_s3_bucket
    configure_lifecycle_policies
    setup_notifications
    enable_inventory
    upload_sample_data
    validate_deployment
    show_deployment_summary
    
    log "INFO" "Deployment completed successfully at $(date)"
}

# Handle script interruption
cleanup_on_error() {
    log "ERROR" "Deployment interrupted. Cleaning up partial resources..."
    if [ -n "${BUCKET_NAME:-}" ]; then
        log "INFO" "Removing partially created resources..."
        # Clean up will be handled by destroy.sh if needed
    fi
    exit 1
}

# Set up error handling
trap cleanup_on_error INT TERM ERR

# Check if running in dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log "INFO" "Running in dry-run mode - no resources will be created"
    check_prerequisites
    generate_resource_names
    log "INFO" "Dry-run completed. Resources that would be created:"
    log "INFO" "  S3 Bucket: $BUCKET_NAME"
    log "INFO" "  SNS Topic: $SNS_TOPIC_NAME"
    exit 0
fi

# Run main deployment
main "$@"