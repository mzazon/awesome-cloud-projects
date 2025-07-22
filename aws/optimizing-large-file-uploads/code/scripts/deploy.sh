#!/bin/bash

# AWS S3 Multi-Part Upload Strategies - Deployment Script
# Creates S3 bucket, configures multipart uploads, and sets up monitoring

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        aws s3api delete-bucket --bucket "$BUCKET_NAME" 2>/dev/null || true
    fi
    rm -f "${TEST_FILE_NAME:-}" "downloaded-${TEST_FILE_NAME:-}" 2>/dev/null || true
    rm -f "${PARTS_FILE:-}" lifecycle-policy.json dashboard-config.json 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "  AWS S3 Multi-Part Upload Deployment"
    echo "=========================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required commands
    local required_commands=("dd" "shasum" "seq")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "Required command '$cmd' is not available."
            exit 1
        fi
    done
    
    print_success "Prerequisites check passed"
}

# Get user confirmation for deployment
get_user_confirmation() {
    echo
    echo "This script will:"
    echo "  - Create an S3 bucket for multipart upload testing"
    echo "  - Generate a 1GB test file"
    echo "  - Configure multipart upload settings"
    echo "  - Set up CloudWatch monitoring"
    echo "  - Create lifecycle policies for cleanup"
    echo
    print_warning "Estimated AWS costs: \$0.10-\$0.50 for testing"
    echo
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        print_error "AWS region not configured. Please set it with 'aws configure'"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export BUCKET_NAME="multipart-upload-demo-${RANDOM_SUFFIX}"
    export TEST_FILE_NAME="large-test-file.bin"
    export TEST_FILE_SIZE="1073741824"  # 1GB in bytes
    export PARTS_FILE="parts-manifest.json"
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Bucket Name: $BUCKET_NAME"
    
    print_success "Environment variables set"
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket: $BUCKET_NAME"
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        print_warning "Bucket $BUCKET_NAME already exists"
        return 0
    fi
    
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
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
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    print_success "S3 bucket created with encryption and versioning enabled"
}

# Create test file
create_test_file() {
    log "Creating 1GB test file: $TEST_FILE_NAME"
    
    if [[ -f "$TEST_FILE_NAME" ]]; then
        local existing_size=$(stat -f%z "$TEST_FILE_NAME" 2>/dev/null || stat -c%s "$TEST_FILE_NAME" 2>/dev/null)
        if [[ "$existing_size" == "$TEST_FILE_SIZE" ]]; then
            print_warning "Test file already exists with correct size"
            return 0
        fi
    fi
    
    print_warning "Creating 1GB test file... This may take a few minutes."
    dd if=/dev/urandom of="$TEST_FILE_NAME" bs=1048576 count=1024 2>/dev/null || {
        print_error "Failed to create test file"
        exit 1
    }
    
    print_success "Test file created: $TEST_FILE_NAME"
}

# Configure multipart upload settings
configure_multipart_settings() {
    log "Configuring multipart upload settings..."
    
    # Set optimal configuration for large files
    aws configure set default.s3.multipart_threshold 100MB
    aws configure set default.s3.multipart_chunksize 100MB
    aws configure set default.s3.max_concurrent_requests 10
    aws configure set default.s3.max_bandwidth 1GB/s
    
    # Verify configuration
    log "Current S3 configuration:"
    aws configure list | grep s3 | tee -a "$LOG_FILE"
    
    print_success "Multipart upload settings configured"
}

# Perform multipart upload demonstration
perform_multipart_upload() {
    log "Performing multipart upload demonstration..."
    
    # Initiate multipart upload with checksum validation
    log "Initiating multipart upload..."
    UPLOAD_ID=$(aws s3api create-multipart-upload \
        --bucket "$BUCKET_NAME" \
        --key "$TEST_FILE_NAME" \
        --metadata "upload-strategy=multipart,file-size=$TEST_FILE_SIZE" \
        --checksum-algorithm SHA256 \
        --storage-class STANDARD \
        --query 'UploadId' --output text)
    
    log "Multipart upload initiated with ID: $UPLOAD_ID"
    
    # Calculate number of parts needed (100MB each)
    local PART_SIZE=104857600  # 100MB in bytes
    local TOTAL_PARTS=$(( (TEST_FILE_SIZE + PART_SIZE - 1) / PART_SIZE ))
    
    log "Uploading $TOTAL_PARTS parts of 100MB each..."
    
    # Create parts manifest file
    echo '{"Parts": [' > "$PARTS_FILE"
    
    # Upload parts in parallel (limiting to 3 concurrent uploads for stability)
    local uploaded_parts=0
    for i in $(seq 1 "$TOTAL_PARTS"); do
        {
            local part_start=$(( (i - 1) * PART_SIZE ))
            local part_file="part-$i"
            
            # Create part file
            dd if="$TEST_FILE_NAME" of="$part_file" \
                bs=1 skip="$part_start" count="$PART_SIZE" 2>/dev/null
            
            # Upload part with retry logic
            local retry_count=0
            local max_retries=3
            local etag=""
            
            while [[ $retry_count -lt $max_retries ]]; do
                if etag=$(aws s3api upload-part \
                    --bucket "$BUCKET_NAME" \
                    --key "$TEST_FILE_NAME" \
                    --part-number "$i" \
                    --upload-id "$UPLOAD_ID" \
                    --body "$part_file" \
                    --checksum-algorithm SHA256 \
                    --query 'ETag' --output text 2>/dev/null); then
                    break
                else
                    ((retry_count++))
                    log "Retry $retry_count for part $i"
                    sleep $((retry_count * 2))
                fi
            done
            
            if [[ -z "$etag" ]]; then
                print_error "Failed to upload part $i after $max_retries retries"
                exit 1
            fi
            
            log "Part $i uploaded with ETag: $etag"
            
            # Add to parts manifest
            if [[ $i -eq $TOTAL_PARTS ]]; then
                echo "    {\"ETag\": $etag, \"PartNumber\": $i}" >> "$PARTS_FILE"
            else
                echo "    {\"ETag\": $etag, \"PartNumber\": $i}," >> "$PARTS_FILE"
            fi
            
            # Cleanup part file
            rm -f "$part_file"
            
            ((uploaded_parts++))
        } &
        
        # Limit concurrent uploads to prevent overwhelming the system
        if (( i % 3 == 0 )); then
            wait
        fi
    done
    
    wait  # Wait for all uploads to complete
    echo ']}' >> "$PARTS_FILE"
    
    log "All $TOTAL_PARTS parts uploaded successfully"
    
    # Complete the multipart upload
    log "Completing multipart upload..."
    aws s3api complete-multipart-upload \
        --bucket "$BUCKET_NAME" \
        --key "$TEST_FILE_NAME" \
        --upload-id "$UPLOAD_ID" \
        --multipart-upload "file://$PARTS_FILE"
    
    print_success "Multipart upload completed successfully"
}

# Set up lifecycle policy for cleanup
setup_lifecycle_policy() {
    log "Setting up lifecycle policy for incomplete multipart uploads..."
    
    cat > lifecycle-policy.json << 'EOF'
{
    "Rules": [
        {
            "ID": "CleanupIncompleteMultipartUploads",
            "Status": "Enabled",
            "Filter": {"Prefix": ""},
            "AbortIncompleteMultipartUpload": {
                "DaysAfterInitiation": 7
            }
        },
        {
            "ID": "ArchiveOldVersions",
            "Status": "Enabled",
            "Filter": {"Prefix": ""},
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
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file://lifecycle-policy.json
    
    print_success "Lifecycle policy applied"
}

# Set up CloudWatch monitoring
setup_cloudwatch_monitoring() {
    log "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch dashboard
    cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/S3", "NumberOfObjects", "BucketName", "$BUCKET_NAME", "StorageType", "AllStorageTypes"],
                    [".", "BucketSizeBytes", ".", ".", ".", "StandardStorage"]
                ],
                "period": 86400,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "S3 Bucket Metrics - $BUCKET_NAME",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/S3", "AllRequests", "BucketName", "$BUCKET_NAME"],
                    [".", "GetRequests", ".", "."],
                    [".", "PutRequests", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "S3 Request Metrics - $BUCKET_NAME"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "S3-MultipartUpload-${RANDOM_SUFFIX}" \
        --dashboard-body file://dashboard-config.json
    
    print_success "CloudWatch dashboard created"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if file was uploaded successfully
    local uploaded_size=$(aws s3api head-object \
        --bucket "$BUCKET_NAME" \
        --key "$TEST_FILE_NAME" \
        --query 'ContentLength' --output text)
    
    if [[ "$uploaded_size" == "$TEST_FILE_SIZE" ]]; then
        print_success "File upload validation passed (Size: $uploaded_size bytes)"
    else
        print_error "File upload validation failed (Expected: $TEST_FILE_SIZE, Got: $uploaded_size)"
        exit 1
    fi
    
    # Test file integrity
    log "Testing file integrity by downloading and comparing checksums..."
    aws s3 cp "s3://$BUCKET_NAME/$TEST_FILE_NAME" "downloaded-$TEST_FILE_NAME" --quiet
    
    local original_checksum=$(shasum -a 256 "$TEST_FILE_NAME" | cut -d' ' -f1)
    local downloaded_checksum=$(shasum -a 256 "downloaded-$TEST_FILE_NAME" | cut -d' ' -f1)
    
    if [[ "$original_checksum" == "$downloaded_checksum" ]]; then
        print_success "File integrity validation passed"
    else
        print_error "File integrity validation failed"
        exit 1
    fi
    
    # Clean up downloaded file
    rm -f "downloaded-$TEST_FILE_NAME"
    
    print_success "All validations passed"
}

# Generate deployment summary
generate_summary() {
    echo
    echo -e "${BLUE}=========================================="
    echo "         Deployment Summary"
    echo -e "==========================================${NC}"
    echo
    echo "✅ S3 Bucket: $BUCKET_NAME"
    echo "✅ Test File: $TEST_FILE_NAME (1GB)"
    echo "✅ Multipart Upload: Completed"
    echo "✅ CloudWatch Dashboard: S3-MultipartUpload-${RANDOM_SUFFIX}"
    echo "✅ Lifecycle Policy: Configured"
    echo
    echo "AWS Console URLs:"
    echo "• S3 Bucket: https://s3.console.aws.amazon.com/s3/buckets/$BUCKET_NAME"
    echo "• CloudWatch Dashboard: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=S3-MultipartUpload-${RANDOM_SUFFIX}"
    echo
    echo "Next Steps:"
    echo "1. Explore the S3 bucket and uploaded file"
    echo "2. Review CloudWatch metrics in the dashboard"
    echo "3. Test additional multipart upload scenarios"
    echo "4. Run './destroy.sh' when finished to clean up resources"
    echo
    print_warning "Remember: This deployment will incur AWS charges until cleaned up"
    echo
}

# Main deployment function
main() {
    print_header
    log "Starting AWS S3 Multi-Part Upload deployment at $TIMESTAMP"
    
    check_prerequisites
    get_user_confirmation
    setup_environment
    create_s3_bucket
    create_test_file
    configure_multipart_settings
    perform_multipart_upload
    setup_lifecycle_policy
    setup_cloudwatch_monitoring
    validate_deployment
    generate_summary
    
    log "Deployment completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
    print_success "AWS S3 Multi-Part Upload deployment completed successfully!"
}

# Run main function
main "$@"