#!/bin/bash

# Deploy script for File Sharing Solutions with S3 Presigned URLs
# This script creates the S3 infrastructure needed for secure file sharing
# using presigned URLs with proper security controls and monitoring

set -euo pipefail

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check required permissions (basic test)
    if ! aws s3 ls &> /dev/null; then
        error "Insufficient S3 permissions. Please check your IAM policies."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique bucket name
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export BUCKET_NAME="file-sharing-demo-${RANDOM_SUFFIX}"
    export SAMPLE_FILE="sample-document.txt"
    
    # Save environment variables for later use
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
SAMPLE_FILE=${SAMPLE_FILE}
EOF
    
    success "Environment variables configured"
    log "Bucket name: ${BUCKET_NAME}"
    log "Region: ${AWS_REGION}"
}

# Create S3 bucket with security settings
create_bucket() {
    log "Creating S3 bucket: ${BUCKET_NAME}"
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "Bucket ${BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Wait for bucket to be ready
    aws s3api wait bucket-exists --bucket ${BUCKET_NAME}
    
    success "S3 bucket created successfully"
}

# Configure bucket security
configure_bucket_security() {
    log "Configuring bucket security settings..."
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket ${BUCKET_NAME} \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    # Enable default server-side encryption
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
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
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Add bucket lifecycle configuration to manage costs
    aws s3api put-bucket-lifecycle-configuration \
        --bucket ${BUCKET_NAME} \
        --lifecycle-configuration '{
            "Rules": [
                {
                    "ID": "DeleteOldVersions",
                    "Status": "Enabled",
                    "Filter": {"Prefix": ""},
                    "NoncurrentVersionExpiration": {
                        "NoncurrentDays": 30
                    }
                },
                {
                    "ID": "DeleteIncompleteMultipartUploads",
                    "Status": "Enabled",
                    "Filter": {"Prefix": ""},
                    "AbortIncompleteMultipartUpload": {
                        "DaysAfterInitiation": 7
                    }
                }
            ]
        }'
    
    success "Bucket security configured"
}

# Create sample content
create_sample_content() {
    log "Creating sample files for testing..."
    
    # Create sample document
    cat > ${SAMPLE_FILE} << EOF
# Sample Document for File Sharing

This is a confidential document that demonstrates 
secure file sharing using S3 presigned URLs.

Document ID: DEMO-2025-001
Created: $(date)
Status: For demonstration purposes only

## Security Features
- Private bucket with blocked public access
- Time-limited presigned URLs
- Server-side encryption
- Versioning enabled
- Lifecycle policies configured

## Usage Instructions
1. Generate presigned URLs using AWS CLI or SDK
2. Share URLs with authorized recipients
3. URLs automatically expire after specified time
4. Monitor access through CloudTrail logs
EOF
    
    # Upload sample file to documents folder
    aws s3 cp ${SAMPLE_FILE} s3://${BUCKET_NAME}/documents/ \
        --storage-class STANDARD
    
    # Create additional sample files for testing
    echo "Additional test document $(date)" > "test-doc-2.txt"
    aws s3 cp test-doc-2.txt s3://${BUCKET_NAME}/documents/
    
    # Create uploads directory structure
    echo "Upload directory marker" | aws s3 cp - s3://${BUCKET_NAME}/uploads/.keep
    
    # Clean up local files
    rm -f test-doc-2.txt
    
    success "Sample content created and uploaded"
}

# Create utility scripts
create_utility_scripts() {
    log "Creating utility scripts..."
    
    # Create presigned URL generator script
    cat > generate_presigned_urls.sh << 'EOF'
#!/bin/bash

# Batch presigned URL generator for S3 objects
# Usage: ./generate_presigned_urls.sh <bucket-name> [expiry-hours] [prefix]

set -euo pipefail

BUCKET_NAME=$1
EXPIRY_HOURS=${2:-24}
PREFIX=${3:-""}
EXPIRY_SECONDS=$((EXPIRY_HOURS * 3600))

if [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <bucket-name> [expiry-hours] [prefix]"
    echo "Example: $0 my-bucket 12 documents/"
    exit 1
fi

echo "Generating presigned URLs for bucket: $BUCKET_NAME"
echo "Expiry time: $EXPIRY_HOURS hours"
echo "Prefix filter: ${PREFIX:-'(none)'}"
echo "----------------------------------------"

# List objects with optional prefix and generate presigned URLs
aws s3api list-objects-v2 \
    --bucket "$BUCKET_NAME" \
    ${PREFIX:+--prefix "$PREFIX"} \
    --query 'Contents[].Key' \
    --output text | \
while read -r object_key; do
    if [ -n "$object_key" ] && [ "$object_key" != "None" ]; then
        echo "Processing: $object_key"
        
        # Generate download URL
        download_url=$(aws s3 presign \
            "s3://$BUCKET_NAME/$object_key" \
            --expires-in $EXPIRY_SECONDS)
        
        echo "  Download URL: $download_url"
        echo ""
    fi
done

echo "✅ Presigned URL generation complete"
EOF
    
    chmod +x generate_presigned_urls.sh
    
    # Create URL expiration checker
    cat > check_url_expiry.py << 'EOF'
#!/usr/bin/env python3
"""
URL Expiration Checker for S3 Presigned URLs
Analyzes presigned URLs to determine expiration status
"""

import urllib.parse
import datetime
import sys
import argparse

def check_presigned_url_expiry(url, verbose=False):
    """Check when a presigned URL expires"""
    try:
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
        
        if 'X-Amz-Expires' in params and 'X-Amz-Date' in params:
            expires_seconds = int(params['X-Amz-Expires'][0])
            amz_date = params['X-Amz-Date'][0]
            
            # Parse the AMZ date format
            created_time = datetime.datetime.strptime(
                amz_date, '%Y%m%dT%H%M%SZ'
            )
            expiry_time = created_time + datetime.timedelta(
                seconds=expires_seconds
            )
            
            now = datetime.datetime.utcnow()
            time_remaining = expiry_time - now
            
            if verbose:
                print(f"URL created: {created_time} UTC")
                print(f"URL expires: {expiry_time} UTC")
                print(f"Current time: {now} UTC")
            
            if time_remaining.total_seconds() > 0:
                hours, remainder = divmod(int(time_remaining.total_seconds()), 3600)
                minutes, seconds = divmod(remainder, 60)
                
                print(f"Time remaining: {hours}h {minutes}m {seconds}s")
                print("Status: ✅ VALID")
                return True
            else:
                print("Status: ❌ EXPIRED")
                return False
        else:
            print("❌ Not a valid S3 presigned URL")
            return False
            
    except Exception as e:
        print(f"❌ Error parsing URL: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(
        description="Check S3 presigned URL expiration status"
    )
    parser.add_argument("url", help="S3 presigned URL to check")
    parser.add_argument("-v", "--verbose", action="store_true",
                       help="Show detailed timing information")
    
    args = parser.parse_args()
    
    print("S3 Presigned URL Expiration Checker")
    print("=" * 40)
    
    is_valid = check_presigned_url_expiry(args.url, args.verbose)
    sys.exit(0 if is_valid else 1)

if __name__ == "__main__":
    main()
EOF
    
    chmod +x check_url_expiry.py
    
    success "Utility scripts created"
}

# Generate initial presigned URLs for testing
generate_test_urls() {
    log "Generating initial presigned URLs for testing..."
    
    # Generate download URL for sample document
    DOWNLOAD_URL=$(aws s3 presign \
        s3://${BUCKET_NAME}/documents/${SAMPLE_FILE} \
        --expires-in 3600)
    
    # Generate upload URL for testing
    UPLOAD_FILE="test-upload.txt"
    UPLOAD_URL=$(aws s3 presign \
        s3://${BUCKET_NAME}/uploads/${UPLOAD_FILE} \
        --expires-in 1800 \
        --http-method PUT)
    
    # Save URLs to file for reference
    cat > presigned_urls.txt << EOF
File Sharing Solution - Presigned URLs
Generated: $(date)
Valid for: 1 hour (download), 30 minutes (upload)

DOWNLOAD URL (sample document):
${DOWNLOAD_URL}

UPLOAD URL (test upload):
${UPLOAD_URL}

To test download:
curl -o "downloaded_sample.txt" "${DOWNLOAD_URL}"

To test upload:
echo "Test upload content" > test.txt
curl -X PUT -T test.txt "${UPLOAD_URL}"

Use check_url_expiry.py to monitor URL expiration status.
EOF
    
    success "Test URLs generated and saved to presigned_urls.txt"
}

# Main deployment function
main() {
    log "Starting deployment of File Sharing Solution with S3 Presigned URLs"
    
    check_prerequisites
    setup_environment
    create_bucket
    configure_bucket_security
    create_sample_content
    create_utility_scripts
    generate_test_urls
    
    success "Deployment completed successfully!"
    echo ""
    log "📋 Deployment Summary:"
    echo "  • S3 Bucket: ${BUCKET_NAME}"
    echo "  • Region: ${AWS_REGION}"
    echo "  • Security: Public access blocked, encryption enabled"
    echo "  • Sample files: Uploaded to documents/ folder"
    echo "  • Utility scripts: generate_presigned_urls.sh, check_url_expiry.py"
    echo "  • Test URLs: saved to presigned_urls.txt"
    echo ""
    log "🔗 Next steps:"
    echo "  1. Review presigned_urls.txt for test URLs"
    echo "  2. Test file download: curl -o sample.txt \"<download-url>\""
    echo "  3. Generate batch URLs: ./generate_presigned_urls.sh ${BUCKET_NAME}"
    echo "  4. Monitor URL expiration: python3 check_url_expiry.py \"<url>\""
    echo ""
    warning "Remember to run destroy.sh when finished to avoid ongoing charges"
}

# Run main function
main "$@"