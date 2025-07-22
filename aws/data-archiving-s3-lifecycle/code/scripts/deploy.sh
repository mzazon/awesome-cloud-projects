#!/bin/bash

# Data Archiving Solutions with S3 Lifecycle Policies - Deployment Script
# This script automates the deployment of S3 lifecycle policies for data archiving
# Based on the recipe: "Data Archiving Solutions with S3 Lifecycle"

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✅ $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ⚠️ $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ❌ $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2 | cut -d. -f1)
    if [ "$AWS_CLI_VERSION" -lt 2 ]; then
        error "AWS CLI v2 is required. Current version: $(aws --version)"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some JSON processing may not work optimally."
    fi
    
    success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region from configuration or use default
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: $AWS_REGION"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        openssl rand -hex 3)
    
    export BUCKET_NAME="data-archiving-demo-${RANDOM_SUFFIX}"
    export POLICY_NAME="DataArchivingPolicy"
    export ROLE_NAME="S3LifecycleRole"
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "S3 Bucket Name: $BUCKET_NAME"
    
    success "Environment variables configured"
}

# Function to create S3 bucket and enable versioning
create_s3_bucket() {
    log "Creating S3 bucket and enabling versioning..."
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning for better lifecycle management
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    success "Created S3 bucket: ${BUCKET_NAME} with versioning enabled"
}

# Function to create sample data structure
create_sample_data() {
    log "Creating sample data structure..."
    
    # Create local directory structure
    mkdir -p lifecycle-demo-data/{documents,logs,backups,media}
    
    # Generate sample files with different sizes and types
    echo "Important business document - $(date)" > \
        lifecycle-demo-data/documents/business-doc-$(date +%Y%m%d).txt
    echo "Application log entry - $(date)" > \
        lifecycle-demo-data/logs/app-log-$(date +%Y%m%d).log
    echo "Database backup metadata - $(date)" > \
        lifecycle-demo-data/backups/db-backup-$(date +%Y%m%d).sql
    echo "Media file placeholder - $(date)" > \
        lifecycle-demo-data/media/video-$(date +%Y%m%d).mp4
    
    # Upload files to S3 with different prefixes
    aws s3 cp lifecycle-demo-data/documents/ \
        s3://${BUCKET_NAME}/documents/ --recursive
    aws s3 cp lifecycle-demo-data/logs/ \
        s3://${BUCKET_NAME}/logs/ --recursive
    aws s3 cp lifecycle-demo-data/backups/ \
        s3://${BUCKET_NAME}/backups/ --recursive
    aws s3 cp lifecycle-demo-data/media/ \
        s3://${BUCKET_NAME}/media/ --recursive
    
    success "Created and uploaded sample data to S3"
}

# Function to create comprehensive lifecycle policy
create_lifecycle_policy() {
    log "Creating comprehensive lifecycle policy..."
    
    # Create comprehensive lifecycle policy for different data types
    cat > comprehensive-lifecycle-policy.json << 'EOF'
{
    "Rules": [
        {
            "ID": "DocumentArchiving",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "documents/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        },
        {
            "ID": "LogArchiving",
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
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 90,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ],
            "Expiration": {
                "Days": 2555
            }
        },
        {
            "ID": "BackupArchiving",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "backups/"
            },
            "Transitions": [
                {
                    "Days": 1,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 30,
                    "StorageClass": "GLACIER"
                }
            ]
        },
        {
            "ID": "MediaIntelligentTiering",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "media/"
            },
            "Transitions": [
                {
                    "Days": 0,
                    "StorageClass": "INTELLIGENT_TIERING"
                }
            ]
        }
    ]
}
EOF
    
    # Apply comprehensive lifecycle policy
    aws s3api put-bucket-lifecycle-configuration \
        --bucket ${BUCKET_NAME} \
        --lifecycle-configuration file://comprehensive-lifecycle-policy.json
    
    success "Applied comprehensive lifecycle policy for all data types"
}

# Function to configure S3 Intelligent Tiering
configure_intelligent_tiering() {
    log "Configuring S3 Intelligent Tiering..."
    
    # Create intelligent tiering configuration
    cat > intelligent-tiering-config.json << 'EOF'
{
    "Id": "MediaIntelligentTieringConfig",
    "Status": "Enabled",
    "Filter": {
        "Prefix": "media/"
    },
    "Tierings": [
        {
            "Days": 90,
            "AccessTier": "ARCHIVE_ACCESS"
        },
        {
            "Days": 180,
            "AccessTier": "DEEP_ARCHIVE_ACCESS"
        }
    ]
}
EOF
    
    # Apply intelligent tiering configuration
    aws s3api put-bucket-intelligent-tiering-configuration \
        --bucket ${BUCKET_NAME} \
        --id MediaIntelligentTieringConfig \
        --intelligent-tiering-configuration file://intelligent-tiering-config.json
    
    success "Configured S3 Intelligent Tiering for media files"
}

# Function to set up S3 Inventory
setup_s3_inventory() {
    log "Setting up S3 Inventory for cost tracking..."
    
    # Create inventory configuration to track storage usage
    cat > inventory-config.json << EOF
{
    "Id": "StorageInventoryConfig",
    "IsEnabled": true,
    "Destination": {
        "S3BucketDestination": {
            "Bucket": "arn:aws:s3:::${BUCKET_NAME}",
            "Prefix": "inventory-reports/",
            "Format": "CSV"
        }
    },
    "Schedule": {
        "Frequency": "Daily"
    },
    "IncludedObjectVersions": "Current",
    "OptionalFields": [
        "Size",
        "LastModifiedDate",
        "StorageClass",
        "IntelligentTieringAccessTier"
    ]
}
EOF
    
    # Apply inventory configuration
    aws s3api put-bucket-inventory-configuration \
        --bucket ${BUCKET_NAME} \
        --id StorageInventoryConfig \
        --inventory-configuration file://inventory-config.json
    
    success "Configured S3 Inventory for storage tracking"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for storage monitoring..."
    
    # Create CloudWatch alarm for storage costs (if billing metrics are enabled)
    aws cloudwatch put-metric-alarm \
        --alarm-name "S3-Storage-Cost-${BUCKET_NAME}" \
        --alarm-description "Monitor S3 storage costs" \
        --metric-name "EstimatedCharges" \
        --namespace "AWS/Billing" \
        --statistic "Maximum" \
        --period 86400 \
        --threshold 10.0 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions Name=Currency,Value=USD Name=ServiceName,Value=AmazonS3 \
        --evaluation-periods 1 \
        --treat-missing-data "notBreaching" || \
        warning "Could not create billing alarm - billing metrics may not be enabled"
    
    # Create CloudWatch alarm for object count
    aws cloudwatch put-metric-alarm \
        --alarm-name "S3-Object-Count-${BUCKET_NAME}" \
        --alarm-description "Monitor S3 object count" \
        --metric-name "NumberOfObjects" \
        --namespace "AWS/S3" \
        --statistic "Average" \
        --period 86400 \
        --threshold 1000 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions Name=BucketName,Value=${BUCKET_NAME} Name=StorageType,Value=AllStorageTypes \
        --evaluation-periods 1 \
        --treat-missing-data "notBreaching"
    
    success "Created CloudWatch alarms for storage monitoring"
}

# Function to configure S3 Analytics
configure_s3_analytics() {
    log "Configuring S3 Analytics for storage class analysis..."
    
    # Create analytics configuration for documents
    cat > analytics-config.json << EOF
{
    "Id": "DocumentAnalytics",
    "Filter": {
        "Prefix": "documents/"
    },
    "StorageClassAnalysis": {
        "DataExport": {
            "OutputSchemaVersion": "V_1",
            "Destination": {
                "S3BucketDestination": {
                    "Bucket": "arn:aws:s3:::${BUCKET_NAME}",
                    "Prefix": "analytics-reports/documents/",
                    "Format": "CSV"
                }
            }
        }
    }
}
EOF
    
    # Apply analytics configuration
    aws s3api put-bucket-analytics-configuration \
        --bucket ${BUCKET_NAME} \
        --id DocumentAnalytics \
        --analytics-configuration file://analytics-config.json
    
    success "Configured S3 Analytics for storage class analysis"
}

# Function to create IAM role for lifecycle management
create_iam_role() {
    log "Creating IAM role for lifecycle management..."
    
    # Create trust policy for S3 lifecycle role
    cat > lifecycle-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role for lifecycle management
    aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file://lifecycle-trust-policy.json \
        --description "Role for S3 lifecycle management operations" || \
        warning "IAM role may already exist or insufficient permissions"
    
    # Create policy for lifecycle management
    cat > lifecycle-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:GetBucketLifecycleConfiguration",
                "s3:PutBucketLifecycleConfiguration",
                "s3:GetBucketVersioning",
                "s3:GetBucketIntelligentTieringConfiguration",
                "s3:PutBucketIntelligentTieringConfiguration"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::*",
                "arn:aws:s3:::*/*"
            ]
        }
    ]
}
EOF
    
    # Create and attach policy to role
    aws iam create-policy \
        --policy-name ${POLICY_NAME} \
        --policy-document file://lifecycle-policy.json || \
        warning "IAM policy may already exist or insufficient permissions"
    
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" || \
        warning "Could not attach policy to role"
    
    success "Created IAM role and policy for lifecycle management"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check lifecycle configuration
    if aws s3api get-bucket-lifecycle-configuration --bucket ${BUCKET_NAME} &> /dev/null; then
        success "Lifecycle configuration validated"
    else
        error "Lifecycle configuration validation failed"
        return 1
    fi
    
    # Check intelligent tiering configuration
    if aws s3api get-bucket-intelligent-tiering-configuration \
        --bucket ${BUCKET_NAME} \
        --id MediaIntelligentTieringConfig &> /dev/null; then
        success "Intelligent tiering configuration validated"
    else
        warning "Intelligent tiering configuration validation failed"
    fi
    
    # Check analytics configuration
    if aws s3api get-bucket-analytics-configuration \
        --bucket ${BUCKET_NAME} \
        --id DocumentAnalytics &> /dev/null; then
        success "Analytics configuration validated"
    else
        warning "Analytics configuration validation failed"
    fi
    
    # Check inventory configuration
    if aws s3api get-bucket-inventory-configuration \
        --bucket ${BUCKET_NAME} \
        --id StorageInventoryConfig &> /dev/null; then
        success "Inventory configuration validated"
    else
        warning "Inventory configuration validation failed"
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo ""
    echo "🗂️  S3 Bucket: ${BUCKET_NAME}"
    echo "🌍 AWS Region: ${AWS_REGION}"
    echo "📋 IAM Role: ${ROLE_NAME}"
    echo "📊 IAM Policy: ${POLICY_NAME}"
    echo ""
    echo "✅ Lifecycle policies configured for:"
    echo "   📄 Documents: 30d → IA → 90d → Glacier → 365d → Deep Archive"
    echo "   📋 Logs: 7d → IA → 30d → Glacier → 90d → Deep Archive → 2555d expiry"
    echo "   💾 Backups: 1d → IA → 30d → Glacier"
    echo "   🎬 Media: Intelligent Tiering with Archive tiers"
    echo ""
    echo "📈 Monitoring configured:"
    echo "   📊 S3 Analytics for documents"
    echo "   📋 S3 Inventory for storage tracking"
    echo "   ⏰ CloudWatch alarms for cost and object count monitoring"
    echo ""
    echo "🔍 View your bucket contents:"
    echo "   aws s3 ls s3://${BUCKET_NAME} --recursive"
    echo ""
    echo "💰 Monitor costs in AWS Cost Explorer and CloudWatch"
    echo ""
    warning "Note: Lifecycle transitions may take 24-48 hours to take effect"
    warning "Remember to run destroy.sh when done to avoid ongoing charges"
}

# Function to save environment variables for cleanup
save_environment() {
    log "Saving environment variables for cleanup..."
    
    cat > .lifecycle-demo-env << EOF
# Environment variables for S3 Lifecycle Demo
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export BUCKET_NAME="${BUCKET_NAME}"
export POLICY_NAME="${POLICY_NAME}"
export ROLE_NAME="${ROLE_NAME}"
EOF
    
    success "Environment variables saved to .lifecycle-demo-env"
}

# Function to handle script interruption
cleanup_on_error() {
    error "Script interrupted or failed"
    warning "You may need to manually clean up resources"
    if [ -n "${BUCKET_NAME:-}" ]; then
        warning "S3 Bucket: ${BUCKET_NAME}"
        warning "To cleanup, run: aws s3 rb s3://${BUCKET_NAME} --force"
    fi
    exit 1
}

# Trap for handling interruptions
trap cleanup_on_error INT TERM ERR

# Main deployment function
main() {
    echo ""
    echo "🚀 Starting Data Archiving Solutions with S3 Lifecycle Policies Deployment"
    echo "================================================================="
    echo ""
    
    check_prerequisites
    setup_environment
    save_environment
    create_s3_bucket
    create_sample_data
    create_lifecycle_policy
    configure_intelligent_tiering
    setup_s3_inventory
    create_cloudwatch_alarms
    configure_s3_analytics
    create_iam_role
    validate_deployment
    
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo "================================================================="
    display_summary
    
    # Cleanup temporary files
    rm -f *.json lifecycle-demo-data -rf
    
    success "Deployment script completed successfully"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi