#!/bin/bash

# Intelligent Tiering and Lifecycle Management for S3 - Deployment Script
# This script deploys the complete S3 Intelligent Tiering and Lifecycle Management solution
# Based on the recipe: S3 Automated Tiering and Lifecycle Management

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

# Script configuration
SCRIPT_NAME="S3 Intelligent Tiering Deployment"
SCRIPT_VERSION="1.0"
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Banner function
print_banner() {
    echo "=================================================="
    echo "  $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "=================================================="
    echo ""
}

# Prerequisites check function
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI and configure it."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured or credentials are invalid. Please run 'aws configure'."
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    success "Prerequisites check completed"
}

# Environment setup function
setup_environment() {
    info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error_exit "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error_exit "Unable to retrieve AWS account ID."
    fi
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set bucket name
    export BUCKET_NAME="intelligent-tiering-demo-${RANDOM_SUFFIX}"
    
    # Set CloudWatch dashboard name
    export DASHBOARD_NAME="S3-Storage-Optimization-${RANDOM_SUFFIX}"
    
    success "Environment setup completed"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Bucket Name: $BUCKET_NAME"
    info "Dashboard Name: $DASHBOARD_NAME"
}

# Create S3 bucket function
create_s3_bucket() {
    info "Creating S3 bucket with Intelligent Tiering configuration..."
    
    # Create the S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}" || error_exit "Failed to create S3 bucket"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION" || error_exit "Failed to create S3 bucket"
    fi
    
    # Enable versioning for better data protection
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled || error_exit "Failed to enable versioning"
    
    success "S3 bucket created with versioning enabled: $BUCKET_NAME"
}

# Configure intelligent tiering function
configure_intelligent_tiering() {
    info "Configuring Intelligent Tiering for the bucket..."
    
    # Create intelligent tiering configuration
    aws s3api put-bucket-intelligent-tiering-configuration \
        --bucket "$BUCKET_NAME" \
        --id "EntireBucketConfig" \
        --intelligent-tiering-configuration '{
            "Id": "EntireBucketConfig",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
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
        }' || error_exit "Failed to configure Intelligent Tiering"
    
    success "Intelligent Tiering configured for entire bucket"
}

# Create lifecycle policy function
create_lifecycle_policy() {
    info "Creating lifecycle policy for additional cost optimization..."
    
    # Create lifecycle policy configuration file
    cat > lifecycle-policy.json << 'EOF'
{
    "Rules": [
        {
            "ID": "OptimizeStorage",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "INTELLIGENT_TIERING"
                }
            ],
            "AbortIncompleteMultipartUpload": {
                "DaysAfterInitiation": 7
            },
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "NoncurrentDays": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 365
            }
        }
    ]
}
EOF
    
    # Apply lifecycle policy to bucket
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file://lifecycle-policy.json || error_exit "Failed to apply lifecycle policy"
    
    success "Lifecycle policy applied successfully"
}

# Upload sample data function
upload_sample_data() {
    info "Uploading sample data with different access patterns..."
    
    # Create sample files with different sizes and types
    echo "Frequently accessed data - $(date)" > frequent-data.txt
    echo "Archive data from $(date)" > archive-data.txt
    
    # Create a larger sample file (1MB)
    if command -v base64 &> /dev/null; then
        base64 /dev/urandom | head -c 1048576 > large-sample.dat 2>/dev/null || {
            # Fallback if base64/urandom fails
            dd if=/dev/zero of=large-sample.dat bs=1024 count=1024 2>/dev/null || {
                # Final fallback
                echo "Large sample file content - $(date)" > large-sample.dat
            }
        }
    else
        echo "Large sample file content - $(date)" > large-sample.dat
    fi
    
    # Upload files to different prefixes
    aws s3 cp frequent-data.txt "s3://${BUCKET_NAME}/active/" || error_exit "Failed to upload frequent data"
    aws s3 cp archive-data.txt "s3://${BUCKET_NAME}/archive/" || error_exit "Failed to upload archive data"
    aws s3 cp large-sample.dat "s3://${BUCKET_NAME}/data/" || error_exit "Failed to upload large sample"
    
    # Add metadata tags for better organization
    aws s3api put-object-tagging \
        --bucket "$BUCKET_NAME" \
        --key "active/frequent-data.txt" \
        --tagging 'TagSet=[{Key=AccessPattern,Value=Frequent},{Key=Department,Value=Operations}]' || warning "Failed to add tags to frequent data"
    
    success "Sample data uploaded with appropriate tagging"
    
    # Clean up local files
    rm -f frequent-data.txt archive-data.txt large-sample.dat lifecycle-policy.json
}

# Configure CloudWatch monitoring function
configure_cloudwatch_monitoring() {
    info "Configuring CloudWatch monitoring for storage metrics..."
    
    # Enable S3 request metrics for the bucket
    aws s3api put-bucket-metrics-configuration \
        --bucket "$BUCKET_NAME" \
        --id "EntireBucket" \
        --metrics-configuration '{
            "Id": "EntireBucket",
            "Filter": {
                "Prefix": ""
            }
        }' || error_exit "Failed to configure bucket metrics"
    
    # Create CloudWatch dashboard for monitoring
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/S3", "BucketSizeBytes", "BucketName", "'$BUCKET_NAME'", "StorageType", "StandardStorage"],
                            [".", ".", ".", ".", ".", "IntelligentTieringIAStorage"],
                            [".", ".", ".", ".", ".", "IntelligentTieringAAStorage"]
                        ],
                        "period": 86400,
                        "stat": "Average",
                        "region": "'$AWS_REGION'",
                        "title": "S3 Storage by Class"
                    }
                }
            ]
        }' || error_exit "Failed to create CloudWatch dashboard"
    
    success "CloudWatch monitoring configured"
    info "Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
}

# Validation function
validate_deployment() {
    info "Validating deployment..."
    
    # Check bucket exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        success "Bucket exists and is accessible"
    else
        error_exit "Bucket validation failed"
    fi
    
    # Check intelligent tiering configuration
    if aws s3api get-bucket-intelligent-tiering-configuration \
        --bucket "$BUCKET_NAME" \
        --id "EntireBucketConfig" &>/dev/null; then
        success "Intelligent Tiering configuration verified"
    else
        error_exit "Intelligent Tiering configuration validation failed"
    fi
    
    # Check lifecycle configuration
    if aws s3api get-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" &>/dev/null; then
        success "Lifecycle policy configuration verified"
    else
        error_exit "Lifecycle policy validation failed"
    fi
    
    # List objects to verify uploads
    OBJECT_COUNT=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive | wc -l)
    if [ "$OBJECT_COUNT" -gt 0 ]; then
        success "Sample data uploaded successfully ($OBJECT_COUNT objects)"
    else
        warning "No objects found in bucket"
    fi
    
    success "Deployment validation completed"
}

# Main deployment function
main() {
    print_banner
    
    info "Starting deployment of S3 Intelligent Tiering and Lifecycle Management solution..."
    info "Log file: $LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    configure_intelligent_tiering
    create_lifecycle_policy
    upload_sample_data
    configure_cloudwatch_monitoring
    validate_deployment
    
    echo ""
    echo "=================================================="
    success "Deployment completed successfully!"
    echo "=================================================="
    echo ""
    echo "📊 Resources created:"
    echo "   • S3 Bucket: $BUCKET_NAME"
    echo "   • Intelligent Tiering: Enabled with Archive Access (90d) and Deep Archive Access (180d)"
    echo "   • Lifecycle Policy: Applied with transitions and cleanup rules"
    echo "   • CloudWatch Dashboard: $DASHBOARD_NAME"
    echo ""
    echo "🔍 Next steps:"
    echo "   • Monitor storage metrics in CloudWatch dashboard"
    echo "   • Upload additional data to test Intelligent Tiering"
    echo "   • Review cost optimization after 30+ days"
    echo ""
    echo "💰 Cost optimization:"
    echo "   • Intelligent Tiering monitoring: ~$0.0025 per 1,000 objects"
    echo "   • Expected savings: 20-68% on storage costs"
    echo "   • Archive Access: Up to 68% savings after 90 days"
    echo "   • Deep Archive Access: Up to 95% savings after 180 days"
    echo ""
    warning "Remember to run destroy.sh when you're done testing to avoid ongoing charges"
}

# Run main function
main "$@"