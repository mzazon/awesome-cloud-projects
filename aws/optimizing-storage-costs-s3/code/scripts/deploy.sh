#!/bin/bash

# Storage Cost Optimization with S3 Storage Classes - Deployment Script
# This script deploys the complete S3 storage cost optimization solution

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warning "Running in DRY-RUN mode - no resources will be created"
    AWS_CLI_OPTS="--dry-run"
else
    AWS_CLI_OPTS=""
fi

# Banner
echo "======================================================="
echo "   S3 Storage Cost Optimization - Deployment Script"
echo "======================================================="
echo

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI v2"
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
log "AWS CLI version: $AWS_CLI_VERSION"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'"
fi

# Check Python3 for scripts
if ! command -v python3 &> /dev/null; then
    error "Python 3 not found. Please install Python 3"
fi

# Get AWS account information
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
    warning "No region configured, using default: $AWS_REGION"
fi

log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"

# Set environment variables
export AWS_REGION
export AWS_ACCOUNT_ID

# Generate unique identifiers
log "Generating unique identifiers..."
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export BUCKET_NAME="storage-optimization-demo-${RANDOM_SUFFIX}"
export ANALYTICS_CONFIG_ID="storage-analytics-${RANDOM_SUFFIX}"
export LIFECYCLE_CONFIG_ID="cost-optimization-lifecycle"
export BUDGET_NAME="S3-Storage-Cost-Budget-${RANDOM_SUFFIX}"

log "Bucket name: $BUCKET_NAME"
log "Analytics config ID: $ANALYTICS_CONFIG_ID"
log "Lifecycle config ID: $LIFECYCLE_CONFIG_ID"
log "Budget name: $BUDGET_NAME"

# Check if bucket already exists
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    warning "Bucket $BUCKET_NAME already exists. Continuing with existing bucket..."
else
    # Create S3 bucket
    log "Creating S3 bucket..."
    if [ "$DRY_RUN" != "true" ]; then
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$BUCKET_NAME"
        else
            aws s3api create-bucket --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        success "Created S3 bucket: $BUCKET_NAME"
    else
        log "DRY-RUN: Would create S3 bucket: $BUCKET_NAME"
    fi
fi

# Create sample data
log "Creating sample data..."
if [ "$DRY_RUN" != "true" ]; then
    mkdir -p temp-data/{frequently-accessed,infrequently-accessed,archive}
    
    # Generate sample files with different access patterns
    echo "Frequently accessed application logs - $(date)" > temp-data/frequently-accessed/app-logs-$(date +%Y%m%d).log
    echo "Monthly financial reports - $(date)" > temp-data/infrequently-accessed/financial-report-$(date +%Y%m).pdf
    echo "Historical compliance data - $(date)" > temp-data/archive/compliance-archive-2023.zip
    
    # Upload sample data to S3
    aws s3 cp temp-data/frequently-accessed/ s3://${BUCKET_NAME}/data/frequently-accessed/ --recursive
    aws s3 cp temp-data/infrequently-accessed/ s3://${BUCKET_NAME}/data/infrequently-accessed/ --recursive
    aws s3 cp temp-data/archive/ s3://${BUCKET_NAME}/data/archive/ --recursive
    
    success "Uploaded sample data to S3 bucket"
else
    log "DRY-RUN: Would create and upload sample data"
fi

# Configure S3 Storage Analytics
log "Configuring S3 Storage Analytics..."
if [ "$DRY_RUN" != "true" ]; then
    cat > analytics-config.json << EOF
{
    "Id": "${ANALYTICS_CONFIG_ID}",
    "Filter": {
        "Prefix": "data/"
    },
    "IsEnabled": true,
    "StorageClassAnalysis": {
        "DataExport": {
            "OutputSchemaVersion": "V_1",
            "Destination": {
                "S3BucketDestination": {
                    "Format": "CSV",
                    "Bucket": "arn:aws:s3:::${BUCKET_NAME}",
                    "Prefix": "analytics-reports/"
                }
            }
        }
    }
}
EOF
    
    aws s3api put-bucket-analytics-configuration \
        --bucket "$BUCKET_NAME" \
        --id "$ANALYTICS_CONFIG_ID" \
        --analytics-configuration file://analytics-config.json
    
    success "Configured S3 Storage Analytics"
else
    log "DRY-RUN: Would configure S3 Storage Analytics"
fi

# Enable S3 Intelligent Tiering
log "Enabling S3 Intelligent Tiering..."
if [ "$DRY_RUN" != "true" ]; then
    cat > intelligent-tiering-config.json << EOF
{
    "Id": "EntireBucketIntelligentTiering",
    "Status": "Enabled",
    "Filter": {
        "Prefix": "data/"
    },
    "Tierings": [
        {
            "Days": 1,
            "AccessTier": "ARCHIVE_ACCESS"
        },
        {
            "Days": 90,
            "AccessTier": "DEEP_ARCHIVE_ACCESS"
        }
    ]
}
EOF
    
    aws s3api put-bucket-intelligent-tiering-configuration \
        --bucket "$BUCKET_NAME" \
        --id "EntireBucketIntelligentTiering" \
        --intelligent-tiering-configuration file://intelligent-tiering-config.json
    
    success "Enabled S3 Intelligent Tiering"
else
    log "DRY-RUN: Would enable S3 Intelligent Tiering"
fi

# Create lifecycle policies
log "Creating lifecycle policies..."
if [ "$DRY_RUN" != "true" ]; then
    cat > lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "FrequentlyAccessedData",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "data/frequently-accessed/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        },
        {
            "ID": "InfrequentlyAccessedData",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "data/infrequently-accessed/"
            },
            "Transitions": [
                {
                    "Days": 1,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 30,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 180,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        },
        {
            "ID": "ArchiveData",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "data/archive/"
            },
            "Transitions": [
                {
                    "Days": 1,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 30,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file://lifecycle-policy.json
    
    success "Created lifecycle policies"
else
    log "DRY-RUN: Would create lifecycle policies"
fi

# Create CloudWatch dashboard
log "Creating CloudWatch dashboard..."
if [ "$DRY_RUN" != "true" ]; then
    cat > storage-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/S3", "BucketSizeBytes", "BucketName", "${BUCKET_NAME}", "StorageType", "StandardStorage"],
                    ["...", "StandardIAStorage"],
                    ["...", "GlacierStorage"],
                    ["...", "DeepArchiveStorage"]
                ],
                "period": 86400,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "S3 Storage by Class - ${BUCKET_NAME}"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/S3", "NumberOfObjects", "BucketName", "${BUCKET_NAME}", "StorageType", "AllStorageTypes"]
                ],
                "period": 86400,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Total Objects in ${BUCKET_NAME}"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "S3-Storage-Cost-Optimization-${RANDOM_SUFFIX}" \
        --dashboard-body file://storage-dashboard.json
    
    success "Created CloudWatch dashboard"
else
    log "DRY-RUN: Would create CloudWatch dashboard"
fi

# Create cost budget
log "Creating cost budget..."
if [ "$DRY_RUN" != "true" ]; then
    cat > cost-budget.json << EOF
{
    "BudgetName": "${BUDGET_NAME}",
    "BudgetLimit": {
        "Amount": "50.0",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
        "Service": ["Amazon Simple Storage Service"]
    },
    "TimePeriod": {
        "Start": "$(date -u -d 'first day of this month' +%Y-%m-%d)T00:00:00Z",
        "End": "$(date -u -d 'first day of next month' +%Y-%m-%d)T00:00:00Z"
    }
}
EOF
    
    cat > budget-notifications.json << EOF
[
    {
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 80.0,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "EMAIL",
                "Address": "admin@example.com"
            }
        ]
    }
]
EOF
    
    # Try to create budget with notifications, fallback to budget without notifications
    aws budgets create-budget \
        --account-id "$AWS_ACCOUNT_ID" \
        --budget file://cost-budget.json \
        --notifications-with-subscribers file://budget-notifications.json 2>/dev/null || \
        aws budgets create-budget \
        --account-id "$AWS_ACCOUNT_ID" \
        --budget file://cost-budget.json
    
    success "Created cost budget"
else
    log "DRY-RUN: Would create cost budget"
fi

# Create cost analysis script
log "Creating cost analysis script..."
if [ "$DRY_RUN" != "true" ]; then
    cat > cost-analysis-script.py << 'EOF'
import boto3
import json
from datetime import datetime, timedelta
import os

def generate_storage_cost_report():
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    bucket_name = os.environ.get('BUCKET_NAME', 'your-bucket-name')
    
    # Get storage metrics for the last 30 days
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(days=30)
    
    storage_classes = ['StandardStorage', 'StandardIAStorage', 'GlacierStorage', 'DeepArchiveStorage']
    
    print("S3 Storage Cost Analysis Report")
    print("="*50)
    print(f"Analysis Period: {start_time.date()} to {end_time.date()}")
    print(f"Bucket: {bucket_name}")
    print()
    
    for storage_class in storage_classes:
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='BucketSizeBytes',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': storage_class}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=86400,
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                avg_size = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
                avg_size_gb = avg_size / (1024**3)
                
                # Rough cost calculation (approximate pricing)
                cost_per_gb = {
                    'StandardStorage': 0.023,
                    'StandardIAStorage': 0.0125,
                    'GlacierStorage': 0.004,
                    'DeepArchiveStorage': 0.00099
                }
                
                estimated_monthly_cost = avg_size_gb * cost_per_gb.get(storage_class, 0)
                
                print(f"{storage_class}:")
                print(f"  Average Size: {avg_size_gb:.2f} GB")
                print(f"  Estimated Monthly Cost: ${estimated_monthly_cost:.2f}")
                print()
        except Exception as e:
            print(f"Error getting metrics for {storage_class}: {str(e)}")

if __name__ == "__main__":
    generate_storage_cost_report()
EOF
    
    # Run the cost analysis script
    BUCKET_NAME="$BUCKET_NAME" python3 cost-analysis-script.py
    
    success "Created and executed cost analysis script"
else
    log "DRY-RUN: Would create cost analysis script"
fi

# Save deployment information
log "Saving deployment information..."
if [ "$DRY_RUN" != "true" ]; then
    cat > deployment-info.json << EOF
{
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "aws_region": "${AWS_REGION}",
    "bucket_name": "${BUCKET_NAME}",
    "analytics_config_id": "${ANALYTICS_CONFIG_ID}",
    "lifecycle_config_id": "${LIFECYCLE_CONFIG_ID}",
    "budget_name": "${BUDGET_NAME}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "dashboard_name": "S3-Storage-Cost-Optimization-${RANDOM_SUFFIX}"
}
EOF
    success "Saved deployment information to deployment-info.json"
fi

# Final validation
log "Performing final validation..."
if [ "$DRY_RUN" != "true" ]; then
    # Check bucket exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        success "Bucket validation passed"
    else
        error "Bucket validation failed"
    fi
    
    # Check analytics configuration
    if aws s3api get-bucket-analytics-configuration --bucket "$BUCKET_NAME" --id "$ANALYTICS_CONFIG_ID" &>/dev/null; then
        success "Analytics configuration validation passed"
    else
        warning "Analytics configuration validation failed"
    fi
    
    # Check lifecycle configuration
    if aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET_NAME" &>/dev/null; then
        success "Lifecycle configuration validation passed"
    else
        warning "Lifecycle configuration validation failed"
    fi
fi

echo
echo "======================================================="
echo "                   DEPLOYMENT COMPLETE"
echo "======================================================="
echo
if [ "$DRY_RUN" != "true" ]; then
    echo "Resources created:"
    echo "  • S3 Bucket: $BUCKET_NAME"
    echo "  • CloudWatch Dashboard: S3-Storage-Cost-Optimization-${RANDOM_SUFFIX}"
    echo "  • Cost Budget: $BUDGET_NAME"
    echo "  • Storage Analytics: $ANALYTICS_CONFIG_ID"
    echo "  • Lifecycle Policies: $LIFECYCLE_CONFIG_ID"
    echo
    echo "Next steps:"
    echo "  1. Monitor the CloudWatch dashboard for storage metrics"
    echo "  2. Review storage analytics reports (available in 24-48 hours)"
    echo "  3. Adjust lifecycle policies based on your specific requirements"
    echo "  4. Run the cost analysis script periodically to track savings"
    echo
    echo "To clean up resources, run: ./destroy.sh"
else
    echo "DRY-RUN completed successfully. No resources were created."
fi