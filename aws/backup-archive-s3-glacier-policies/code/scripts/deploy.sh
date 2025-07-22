#!/bin/bash

# Deploy script for Backup and Archive Strategies with S3 Glacier and Lifecycle Policies
# This script creates a comprehensive backup and archive solution using S3 Glacier storage classes

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CONFIG_DIR="${SCRIPT_DIR}/../config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partial resources..."
    
    # Attempt to clean up resources that may have been created
    if [[ -n "${BACKUP_BUCKET_NAME:-}" ]]; then
        log_info "Attempting to clean up bucket: $BACKUP_BUCKET_NAME"
        aws s3 rm "s3://$BACKUP_BUCKET_NAME" --recursive --quiet 2>/dev/null || true
        aws s3api delete-bucket --bucket "$BACKUP_BUCKET_NAME" 2>/dev/null || true
    fi
    
    if [[ -n "${CLOUDWATCH_ALARM_NAME:-}" ]]; then
        log_info "Attempting to clean up CloudWatch alarm: $CLOUDWATCH_ALARM_NAME"
        aws cloudwatch delete-alarms --alarm-names "$CLOUDWATCH_ALARM_NAME" 2>/dev/null || true
    fi
    
    log_error "Cleanup completed. Check logs for details."
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required permissions
    log_info "Verifying AWS permissions..."
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log_info "AWS Account ID: $account_id"
    
    # Test basic S3 permissions
    if ! aws s3 ls &> /dev/null; then
        log_error "Insufficient S3 permissions. Please ensure you have S3 admin access."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export BACKUP_BUCKET_NAME="backup-archive-demo-${random_suffix}"
    export LIFECYCLE_POLICY_NAME="backup-archive-lifecycle-policy"
    export CLOUDWATCH_ALARM_NAME="glacier-cost-alarm-${random_suffix}"
    export IAM_ROLE_NAME="GlacierOperationsRole-${random_suffix}"
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    # Save environment variables for later use
    cat > "${CONFIG_DIR}/deployment.env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
BACKUP_BUCKET_NAME=$BACKUP_BUCKET_NAME
LIFECYCLE_POLICY_NAME=$LIFECYCLE_POLICY_NAME
CLOUDWATCH_ALARM_NAME=$CLOUDWATCH_ALARM_NAME
IAM_ROLE_NAME=$IAM_ROLE_NAME
DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    log_success "Environment setup completed"
    log_info "Backup bucket name: $BACKUP_BUCKET_NAME"
    log_info "AWS region: $AWS_REGION"
}

# Create S3 bucket with versioning
create_s3_bucket() {
    log_info "Creating S3 bucket: $BACKUP_BUCKET_NAME"
    
    # Create bucket with region-specific configuration
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$BACKUP_BUCKET_NAME"
    else
        aws s3api create-bucket \
            --bucket "$BACKUP_BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BACKUP_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "$BACKUP_BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BACKUP_BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    log_success "S3 bucket created and configured: $BACKUP_BUCKET_NAME"
}

# Create lifecycle policy
create_lifecycle_policy() {
    log_info "Creating comprehensive lifecycle policy..."
    
    # Create lifecycle policy configuration
    cat > "${CONFIG_DIR}/lifecycle-policy.json" << 'EOF'
{
  "Rules": [
    {
      "ID": "backup-archive-strategy",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "backups/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER_IR"
        },
        {
          "Days": 365,
          "StorageClass": "GLACIER"
        },
        {
          "Days": 2555,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ],
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 7,
          "StorageClass": "STANDARD_IA"
        },
        {
          "NoncurrentDays": 30,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 2920
      }
    },
    {
      "ID": "logs-retention-policy",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "logs/"
      },
      "Transitions": [
        {
          "Days": 7,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 30,
          "StorageClass": "GLACIER_IR"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "Expiration": {
        "Days": 2555
      }
    },
    {
      "ID": "documents-long-term-archive",
      "Status": "Enabled",
      "Filter": {
        "And": {
          "Prefix": "documents/",
          "Tags": [
            {
              "Key": "DataClass",
              "Value": "Archive"
            }
          ]
        }
      },
      "Transitions": [
        {
          "Days": 60,
          "StorageClass": "GLACIER_IR"
        },
        {
          "Days": 180,
          "StorageClass": "GLACIER"
        },
        {
          "Days": 1095,
          "StorageClass": "DEEP_ARCHIVE"
        }
      ]
    }
  ]
}
EOF
    
    # Apply lifecycle policy to bucket
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BACKUP_BUCKET_NAME" \
        --lifecycle-configuration "file://${CONFIG_DIR}/lifecycle-policy.json"
    
    log_success "Lifecycle policy applied to bucket"
}

# Create IAM role for Glacier operations
create_iam_role() {
    log_info "Creating IAM role for Glacier operations..."
    
    # Create trust policy
    cat > "${CONFIG_DIR}/glacier-trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "glacier.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document "file://${CONFIG_DIR}/glacier-trust-policy.json" \
        --description "Role for S3 Glacier operations in backup archive strategy"
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    # Wait for role to be ready
    sleep 10
    
    log_success "IAM role created: $IAM_ROLE_NAME"
}

# Setup CloudWatch monitoring
setup_monitoring() {
    log_info "Setting up CloudWatch monitoring..."
    
    # Create log group for lifecycle transitions
    aws logs create-log-group \
        --log-group-name /aws/s3/lifecycle-transitions \
        --region "$AWS_REGION" 2>/dev/null || log_warning "Log group may already exist"
    
    # Create CloudWatch alarm for storage costs
    aws cloudwatch put-metric-alarm \
        --alarm-name "$CLOUDWATCH_ALARM_NAME" \
        --alarm-description "Monitor S3 storage costs for backup archive strategy" \
        --metric-name EstimatedCharges \
        --namespace AWS/Billing \
        --statistic Maximum \
        --period 86400 \
        --threshold 50.0 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=Currency,Value=USD Name=ServiceName,Value=AmazonS3 \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching
    
    log_success "CloudWatch monitoring configured"
}

# Configure data retrieval policy
configure_retrieval_policy() {
    log_info "Configuring data retrieval policy for cost control..."
    
    # Create data retrieval policy
    cat > "${CONFIG_DIR}/data-retrieval-policy.json" << 'EOF'
{
  "Rules": [
    {
      "Strategy": "BytesPerHour",
      "BytesPerHour": 1073741824
    }
  ]
}
EOF
    
    # Apply retrieval policy
    aws glacier set-data-retrieval-policy \
        --account-id "$AWS_ACCOUNT_ID" \
        --policy "file://${CONFIG_DIR}/data-retrieval-policy.json"
    
    log_success "Data retrieval policy configured"
}

# Create sample data for testing
create_sample_data() {
    log_info "Creating and uploading sample data..."
    
    local sample_dir="${CONFIG_DIR}/sample-data"
    mkdir -p "$sample_dir"/{backups,logs,documents}
    
    # Generate sample backup files
    echo "Database backup - $(date)" > "$sample_dir/backups/db-backup-$(date +%Y%m%d).sql"
    echo "Application backup - $(date)" > "$sample_dir/backups/app-backup-$(date +%Y%m%d).tar.gz"
    echo "Config backup - $(date)" > "$sample_dir/backups/config-backup-$(date +%Y%m%d).json"
    
    # Generate sample log files
    echo "Application log - $(date)" > "$sample_dir/logs/app-$(date +%Y%m%d).log"
    echo "System log - $(date)" > "$sample_dir/logs/system-$(date +%Y%m%d).log"
    
    # Generate sample document files
    echo "Legal document - $(date)" > "$sample_dir/documents/legal-doc-$(date +%Y%m%d).pdf"
    echo "Financial record - $(date)" > "$sample_dir/documents/financial-$(date +%Y%m%d).xlsx"
    
    # Upload backup files
    aws s3 cp "$sample_dir/backups/" "s3://$BACKUP_BUCKET_NAME/backups/" --recursive
    
    # Upload log files
    aws s3 cp "$sample_dir/logs/" "s3://$BACKUP_BUCKET_NAME/logs/" --recursive
    
    # Upload document files with tags
    for file in "$sample_dir/documents"/*; do
        filename=$(basename "$file")
        aws s3 cp "$file" "s3://$BACKUP_BUCKET_NAME/documents/$filename" \
            --tagging "DataClass=Archive&Department=Legal&Retention=LongTerm"
    done
    
    log_success "Sample data uploaded to bucket"
}

# Create automation scripts
create_automation_scripts() {
    log_info "Creating backup automation scripts..."
    
    # Create backup automation script
    cat > "${CONFIG_DIR}/backup-automation.sh" << 'EOF'
#!/bin/bash

# Backup automation script for S3 Glacier lifecycle management
set -euo pipefail

# Function usage
usage() {
    echo "Usage: $0 <bucket_name> <source_dir> <backup_type>"
    echo "Backup types: database, application, logs"
    exit 1
}

# Check arguments
if [[ $# -ne 3 ]]; then
    usage
fi

BACKUP_BUCKET="$1"
SOURCE_DIR="$2"
BACKUP_TYPE="$3"
DATE=$(date +%Y%m%d-%H%M%S)

# Validate source directory
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist"
    exit 1
fi

# Configure backup based on type
case $BACKUP_TYPE in
    "database")
        PREFIX="backups/database/"
        TAGS="BackupType=Database&Schedule=Daily&CreatedBy=AutomationScript"
        ;;
    "application")
        PREFIX="backups/application/"
        TAGS="BackupType=Application&Schedule=Weekly&CreatedBy=AutomationScript"
        ;;
    "logs")
        PREFIX="logs/"
        TAGS="BackupType=Logs&Schedule=Daily&CreatedBy=AutomationScript"
        ;;
    *)
        echo "Invalid backup type. Use: database, application, or logs"
        exit 1
        ;;
esac

BACKUP_FILE="${BACKUP_TYPE}-backup-${DATE}.tar.gz"

echo "Creating backup: $BACKUP_FILE"
# Create backup archive
tar -czf "$BACKUP_FILE" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"

echo "Uploading to S3: s3://${BACKUP_BUCKET}/${PREFIX}${BACKUP_FILE}"
# Upload to S3 with appropriate tags
aws s3 cp "$BACKUP_FILE" \
    "s3://${BACKUP_BUCKET}/${PREFIX}${BACKUP_FILE}" \
    --tagging "$TAGS"

# Clean up local backup file
rm "$BACKUP_FILE"

echo "Backup completed successfully: ${PREFIX}${BACKUP_FILE}"
EOF
    
    chmod +x "${CONFIG_DIR}/backup-automation.sh"
    
    # Create compliance report script
    cat > "${CONFIG_DIR}/compliance-report.sh" << 'EOF'
#!/bin/bash

# Compliance reporting script for S3 Glacier lifecycle management
set -euo pipefail

BUCKET_NAME="$1"
REPORT_DATE=$(date +%Y%m%d)
REPORT_FILE="compliance-report-${REPORT_DATE}.txt"

if [[ -z "$BUCKET_NAME" ]]; then
    echo "Usage: $0 <bucket_name>"
    exit 1
fi

echo "Generating S3 Glacier Compliance Report - $REPORT_DATE" > "$REPORT_FILE"
echo "===========================================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "Bucket: $BUCKET_NAME" >> "$REPORT_FILE"
echo "Report Generated: $(date)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Get bucket lifecycle configuration
echo "Current Lifecycle Policies:" >> "$REPORT_FILE"
aws s3api get-bucket-lifecycle-configuration \
    --bucket "$BUCKET_NAME" \
    --query 'Rules[].{ID:ID,Status:Status,Transitions:Transitions}' \
    --output table >> "$REPORT_FILE" 2>/dev/null || echo "No lifecycle policies found" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"

# Get storage class distribution
echo "Storage Class Distribution:" >> "$REPORT_FILE"
aws s3api list-objects-v2 \
    --bucket "$BUCKET_NAME" \
    --query 'Contents[].StorageClass' \
    --output text | sort | uniq -c >> "$REPORT_FILE" 2>/dev/null || echo "No objects found" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"

# Get objects in Glacier storage classes
echo "Objects in Glacier Storage Classes:" >> "$REPORT_FILE"
aws s3api list-objects-v2 \
    --bucket "$BUCKET_NAME" \
    --query 'Contents[?StorageClass==`GLACIER` || StorageClass==`DEEP_ARCHIVE`].{Key:Key,StorageClass:StorageClass,LastModified:LastModified}' \
    --output table >> "$REPORT_FILE" 2>/dev/null || echo "No Glacier objects found" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "Report saved to: $REPORT_FILE"
cat "$REPORT_FILE"
EOF
    
    chmod +x "${CONFIG_DIR}/compliance-report.sh"
    
    log_success "Automation scripts created"
}

# Main deployment function
main() {
    log_info "Starting deployment of Backup and Archive Strategies with S3 Glacier"
    log_info "Deployment log: $LOG_FILE"
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_lifecycle_policy
    create_iam_role
    setup_monitoring
    configure_retrieval_policy
    create_sample_data
    create_automation_scripts
    
    # Display deployment summary
    echo ""
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    log_info "Deployment Summary:"
    log_info "  Backup Bucket: $BACKUP_BUCKET_NAME"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  IAM Role: $IAM_ROLE_NAME"
    log_info "  CloudWatch Alarm: $CLOUDWATCH_ALARM_NAME"
    echo ""
    log_info "Configuration files saved in: $CONFIG_DIR"
    log_info "Deployment details saved in: ${CONFIG_DIR}/deployment.env"
    echo ""
    log_info "Next Steps:"
    log_info "1. Review the lifecycle policies applied to your bucket"
    log_info "2. Monitor CloudWatch for cost alerts"
    log_info "3. Use the automation scripts for regular backups"
    log_info "4. Run compliance reports using: ${CONFIG_DIR}/compliance-report.sh $BACKUP_BUCKET_NAME"
    echo ""
    log_warning "Note: Lifecycle transitions will begin within 24 hours based on object age"
    log_warning "Estimated monthly cost: \$5-15 (depends on data volume and access patterns)"
    echo ""
}

# Run main function
main "$@"