#!/bin/bash

# =============================================================================
# AWS Elemental MediaStore Video-on-Demand Platform Deployment Script
# =============================================================================
# This script deploys a complete video-on-demand platform using AWS Elemental
# MediaStore and CloudFront for global content delivery.
#
# WARNING: AWS Elemental MediaStore support ends on November 13, 2025.
# Consider using S3 with CloudFront for new implementations.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for MediaStore, CloudFront, S3, and IAM
# - Bash shell environment
# =============================================================================

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

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
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log "WARN" "jq is not installed. Some JSON parsing may be limited."
    fi
    
    log "SUCCESS" "Prerequisites check completed."
}

wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_wait="${3:-600}" # Default 10 minutes
    local wait_interval="${4:-30}" # Default 30 seconds
    
    log "INFO" "Waiting for $resource_type '$resource_name' to be ready..."
    
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        case "$resource_type" in
            "mediastore-container")
                if aws mediastore describe-container --container-name "$resource_name" \
                   --query 'Container.Status' --output text 2>/dev/null | grep -q "ACTIVE"; then
                    log "SUCCESS" "$resource_type '$resource_name' is ready."
                    return 0
                fi
                ;;
            "cloudfront-distribution")
                if aws cloudfront get-distribution --id "$resource_name" \
                   --query 'Distribution.Status' --output text 2>/dev/null | grep -q "Deployed"; then
                    log "SUCCESS" "$resource_type '$resource_name' is ready."
                    return 0
                fi
                ;;
        esac
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
        log "INFO" "Still waiting... ($elapsed/${max_wait}s elapsed)"
    done
    
    log "ERROR" "Timeout waiting for $resource_type '$resource_name' to be ready."
    return 1
}

save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "$STATE_FILE"
}

cleanup_on_error() {
    log "ERROR" "Deployment failed. Cleaning up resources..."
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        
        # Clean up resources in reverse order
        if [ -n "${DISTRIBUTION_ID:-}" ]; then
            log "INFO" "Cleaning up CloudFront distribution..."
            ./destroy.sh --force || true
        fi
    fi
    exit 1
}

# =============================================================================
# Main Deployment Functions
# =============================================================================

setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Initialize state file
    rm -f "$STATE_FILE"
    touch "$STATE_FILE"
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log "WARN" "No default region configured. Using us-east-1."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export MEDIASTORE_CONTAINER_NAME="vod-platform-${RANDOM_SUFFIX}"
    export CLOUDFRONT_DISTRIBUTION_NAME="vod-cdn-${RANDOM_SUFFIX}"
    export S3_STAGING_BUCKET="vod-staging-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="MediaStoreAccessRole-${RANDOM_SUFFIX}"
    
    # Save to state file
    save_state "AWS_REGION" "$AWS_REGION"
    save_state "AWS_ACCOUNT_ID" "$AWS_ACCOUNT_ID"
    save_state "RANDOM_SUFFIX" "$RANDOM_SUFFIX"
    save_state "MEDIASTORE_CONTAINER_NAME" "$MEDIASTORE_CONTAINER_NAME"
    save_state "CLOUDFRONT_DISTRIBUTION_NAME" "$CLOUDFRONT_DISTRIBUTION_NAME"
    save_state "S3_STAGING_BUCKET" "$S3_STAGING_BUCKET"
    save_state "IAM_ROLE_NAME" "$IAM_ROLE_NAME"
    
    log "SUCCESS" "Environment setup completed with suffix: $RANDOM_SUFFIX"
}

create_staging_bucket() {
    log "INFO" "Creating S3 staging bucket..."
    
    if aws s3 mb "s3://${S3_STAGING_BUCKET}" --region "$AWS_REGION" 2>/dev/null; then
        log "SUCCESS" "S3 staging bucket created: $S3_STAGING_BUCKET"
    else
        log "ERROR" "Failed to create S3 staging bucket."
        return 1
    fi
}

create_mediastore_container() {
    log "INFO" "Creating MediaStore container..."
    
    # Create MediaStore container
    if aws mediastore create-container \
        --container-name "$MEDIASTORE_CONTAINER_NAME" \
        --region "$AWS_REGION" &>/dev/null; then
        log "SUCCESS" "MediaStore container creation initiated."
    else
        log "ERROR" "Failed to create MediaStore container."
        return 1
    fi
    
    # Wait for container to be active
    if ! wait_for_resource "mediastore-container" "$MEDIASTORE_CONTAINER_NAME" 600 15; then
        log "ERROR" "MediaStore container failed to become active."
        return 1
    fi
    
    # Get container endpoint
    MEDIASTORE_ENDPOINT=$(aws mediastore describe-container \
        --container-name "$MEDIASTORE_CONTAINER_NAME" \
        --query Container.Endpoint --output text)
    
    if [ -z "$MEDIASTORE_ENDPOINT" ]; then
        log "ERROR" "Failed to get MediaStore endpoint."
        return 1
    fi
    
    save_state "MEDIASTORE_ENDPOINT" "$MEDIASTORE_ENDPOINT"
    log "SUCCESS" "MediaStore container active: $MEDIASTORE_ENDPOINT"
}

configure_container_policies() {
    log "INFO" "Configuring MediaStore container policies..."
    
    # Create container policy
    cat > "${SCRIPT_DIR}/mediastore-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "MediaStoreFullAccess",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "mediastore:GetObject",
                "mediastore:DescribeObject"
            ],
            "Resource": "*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "true"
                }
            }
        },
        {
            "Sid": "MediaStoreUploadAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
            },
            "Action": [
                "mediastore:PutObject",
                "mediastore:DeleteObject"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Apply container policy
    if aws mediastore put-container-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" \
        --policy "file://${SCRIPT_DIR}/mediastore-policy.json"; then
        log "SUCCESS" "Container security policy applied."
    else
        log "ERROR" "Failed to apply container policy."
        return 1
    fi
    
    # Create CORS policy
    cat > "${SCRIPT_DIR}/cors-policy.json" << 'EOF'
[
    {
        "AllowedOrigins": ["*"],
        "AllowedMethods": ["GET", "HEAD"],
        "AllowedHeaders": ["*"],
        "MaxAgeSeconds": 3000,
        "ExposeHeaders": ["Date", "Server"]
    }
]
EOF
    
    # Apply CORS policy
    if aws mediastore put-cors-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" \
        --cors-policy "file://${SCRIPT_DIR}/cors-policy.json"; then
        log "SUCCESS" "CORS policy applied."
    else
        log "ERROR" "Failed to apply CORS policy."
        return 1
    fi
}

create_iam_role() {
    log "INFO" "Creating IAM role for MediaStore access..."
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "mediastore.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    if aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document "file://${SCRIPT_DIR}/trust-policy.json" &>/dev/null; then
        log "SUCCESS" "IAM role created: $IAM_ROLE_NAME"
    else
        log "ERROR" "Failed to create IAM role."
        return 1
    fi
    
    # Create access policy
    cat > "${SCRIPT_DIR}/mediastore-access-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mediastore:GetObject",
                "mediastore:PutObject",
                "mediastore:DeleteObject",
                "mediastore:DescribeObject",
                "mediastore:ListItems"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy to role
    if aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "MediaStoreAccessPolicy" \
        --policy-document "file://${SCRIPT_DIR}/mediastore-access-policy.json"; then
        log "SUCCESS" "IAM policy attached to role."
    else
        log "ERROR" "Failed to attach IAM policy."
        return 1
    fi
}

upload_sample_content() {
    log "INFO" "Uploading sample video content..."
    
    # Create sample content directory
    mkdir -p "${SCRIPT_DIR}/sample-content"
    
    # Create placeholder content
    echo "Sample video content placeholder" > "${SCRIPT_DIR}/sample-content/sample-video.mp4"
    
    # Upload content to MediaStore
    if aws mediastore-data put-object \
        --endpoint-url "$MEDIASTORE_ENDPOINT" \
        --body "${SCRIPT_DIR}/sample-content/sample-video.mp4" \
        --path "/videos/sample-video.mp4" \
        --content-type "video/mp4" &>/dev/null; then
        log "SUCCESS" "Sample content uploaded to /videos/sample-video.mp4"
    else
        log "ERROR" "Failed to upload sample content."
        return 1
    fi
    
    # Upload additional content
    if aws mediastore-data put-object \
        --endpoint-url "$MEDIASTORE_ENDPOINT" \
        --body "${SCRIPT_DIR}/sample-content/sample-video.mp4" \
        --path "/videos/popular/trending-video.mp4" \
        --content-type "video/mp4" &>/dev/null; then
        log "SUCCESS" "Additional content uploaded to /videos/popular/trending-video.mp4"
    else
        log "WARN" "Failed to upload additional sample content."
    fi
}

create_cloudfront_distribution() {
    log "INFO" "Creating CloudFront distribution..."
    
    # Extract domain name from MediaStore endpoint
    local mediastore_domain="${MEDIASTORE_ENDPOINT#https://}"
    
    # Create CloudFront distribution configuration
    cat > "${SCRIPT_DIR}/cloudfront-config.json" << EOF
{
    "CallerReference": "vod-platform-${RANDOM_SUFFIX}-$(date +%s)",
    "Comment": "VOD Platform Distribution",
    "DefaultCacheBehavior": {
        "TargetOriginId": "MediaStoreOrigin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "MinTTL": 0,
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": {
                "Forward": "none"
            },
            "Headers": {
                "Quantity": 3,
                "Items": [
                    "Origin",
                    "Access-Control-Request-Headers",
                    "Access-Control-Request-Method"
                ]
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "Compress": true,
        "SmoothStreaming": false,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        }
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "MediaStoreOrigin",
                "DomainName": "${mediastore_domain}",
                "CustomOriginConfig": {
                    "HTTPPort": 443,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    }
                }
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_All"
}
EOF
    
    # Create CloudFront distribution
    DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config "file://${SCRIPT_DIR}/cloudfront-config.json" \
        --query Distribution.Id --output text 2>/dev/null)
    
    if [ -z "$DISTRIBUTION_ID" ]; then
        log "ERROR" "Failed to create CloudFront distribution."
        return 1
    fi
    
    save_state "DISTRIBUTION_ID" "$DISTRIBUTION_ID"
    log "SUCCESS" "CloudFront distribution created: $DISTRIBUTION_ID"
    
    # Wait for distribution to deploy
    log "INFO" "Waiting for CloudFront distribution to deploy (this may take 15-20 minutes)..."
    if ! wait_for_resource "cloudfront-distribution" "$DISTRIBUTION_ID" 1800 60; then
        log "WARN" "CloudFront distribution deployment is taking longer than expected."
        log "INFO" "You can check status manually: aws cloudfront get-distribution --id $DISTRIBUTION_ID"
    fi
    
    # Get distribution domain
    DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query Distribution.DomainName --output text 2>/dev/null)
    
    if [ -n "$DISTRIBUTION_DOMAIN" ]; then
        save_state "DISTRIBUTION_DOMAIN" "$DISTRIBUTION_DOMAIN"
        log "SUCCESS" "Distribution available at: https://$DISTRIBUTION_DOMAIN"
    fi
}

configure_monitoring() {
    log "INFO" "Configuring monitoring and metrics..."
    
    # Enable CloudWatch metrics for MediaStore
    if aws mediastore put-metric-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" \
        --metric-policy '{
            "ContainerLevelMetrics": "ENABLED",
            "MetricPolicyRules": [
                {
                    "ObjectGroup": "/*",
                    "ObjectGroupName": "AllObjects"
                }
            ]
        }' &>/dev/null; then
        log "SUCCESS" "CloudWatch metrics enabled for MediaStore."
    else
        log "WARN" "Failed to enable CloudWatch metrics."
    fi
    
    # Create CloudWatch alarm
    if aws cloudwatch put-metric-alarm \
        --alarm-name "MediaStore-HighRequestRate-${RANDOM_SUFFIX}" \
        --alarm-description "High request rate on MediaStore container" \
        --metric-name RequestCount \
        --namespace AWS/MediaStore \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 1000 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=ContainerName,Value="$MEDIASTORE_CONTAINER_NAME" &>/dev/null; then
        log "SUCCESS" "CloudWatch alarm created."
    else
        log "WARN" "Failed to create CloudWatch alarm."
    fi
}

configure_lifecycle_policy() {
    log "INFO" "Configuring lifecycle management..."
    
    # Create lifecycle policy
    cat > "${SCRIPT_DIR}/lifecycle-policy.json" << 'EOF'
{
    "Rules": [
        {
            "ObjectGroup": "/videos/temp/*",
            "ObjectGroupName": "TempVideos",
            "Lifecycle": {
                "TransitionToIA": "AFTER_30_DAYS",
                "ExpirationInDays": 90
            }
        },
        {
            "ObjectGroup": "/videos/archive/*",
            "ObjectGroupName": "ArchiveVideos",
            "Lifecycle": {
                "TransitionToIA": "AFTER_7_DAYS",
                "ExpirationInDays": 365
            }
        }
    ]
}
EOF
    
    # Apply lifecycle policy
    if aws mediastore put-lifecycle-policy \
        --container-name "$MEDIASTORE_CONTAINER_NAME" \
        --lifecycle-policy "file://${SCRIPT_DIR}/lifecycle-policy.json" &>/dev/null; then
        log "SUCCESS" "Lifecycle management configured."
    else
        log "WARN" "Failed to configure lifecycle policy."
    fi
}

run_validation_tests() {
    log "INFO" "Running validation tests..."
    
    # Test MediaStore container status
    local container_status=$(aws mediastore describe-container \
        --container-name "$MEDIASTORE_CONTAINER_NAME" \
        --query Container.Status --output text 2>/dev/null)
    
    if [ "$container_status" = "ACTIVE" ]; then
        log "SUCCESS" "MediaStore container is active."
    else
        log "ERROR" "MediaStore container is not active (status: $container_status)."
        return 1
    fi
    
    # Test content access
    if aws mediastore-data get-object \
        --endpoint-url "$MEDIASTORE_ENDPOINT" \
        --path "/videos/sample-video.mp4" \
        "${SCRIPT_DIR}/downloaded-video.mp4" &>/dev/null; then
        log "SUCCESS" "Content can be retrieved from MediaStore."
        rm -f "${SCRIPT_DIR}/downloaded-video.mp4"
    else
        log "WARN" "Could not retrieve content from MediaStore."
    fi
    
    # Test CloudFront distribution
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        local dist_status=$(aws cloudfront get-distribution \
            --id "$DISTRIBUTION_ID" \
            --query Distribution.Status --output text 2>/dev/null)
        
        if [ "$dist_status" = "Deployed" ]; then
            log "SUCCESS" "CloudFront distribution is deployed."
        else
            log "WARN" "CloudFront distribution is not yet deployed (status: $dist_status)."
        fi
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--dry-run] [--help]"
                echo "  --dry-run    Show what would be deployed without actually deploying"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    log "INFO" "Starting AWS Elemental MediaStore VOD Platform deployment..."
    log "WARN" "AWS Elemental MediaStore support ends on November 13, 2025."
    
    if [ "$dry_run" = true ]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_staging_bucket
    create_mediastore_container
    configure_container_policies
    create_iam_role
    upload_sample_content
    create_cloudfront_distribution
    configure_monitoring
    configure_lifecycle_policy
    run_validation_tests
    
    # Print deployment summary
    echo
    log "SUCCESS" "========================================="
    log "SUCCESS" "VOD Platform Deployment Complete!"
    log "SUCCESS" "========================================="
    log "INFO" "MediaStore Container: $MEDIASTORE_CONTAINER_NAME"
    log "INFO" "MediaStore Endpoint: $MEDIASTORE_ENDPOINT"
    if [ -n "${DISTRIBUTION_DOMAIN:-}" ]; then
        log "INFO" "CloudFront Distribution: https://$DISTRIBUTION_DOMAIN"
    fi
    log "INFO" "State file: $STATE_FILE"
    log "INFO" "Log file: $LOG_FILE"
    echo
    log "INFO" "Test your platform:"
    log "INFO" "  curl -I \"https://${DISTRIBUTION_DOMAIN:-YOUR_CLOUDFRONT_DOMAIN}/videos/sample-video.mp4\""
    echo
    log "WARN" "Remember to run ./destroy.sh to clean up resources when done."
}

# Execute main function with all arguments
main "$@"