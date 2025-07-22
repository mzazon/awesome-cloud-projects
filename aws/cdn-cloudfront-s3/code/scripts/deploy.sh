#!/bin/bash

# Deploy script for CloudFront and S3 CDN Recipe
# This script creates a global content delivery network using Amazon CloudFront with S3 origins

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not authenticated. Please run 'aws configure' first."
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command_exists jq; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    # Check required permissions (basic check)
    log "Checking AWS permissions..."
    if ! aws s3 ls >/dev/null 2>&1; then
        log_error "Missing S3 permissions. Please check your AWS credentials."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No AWS region configured, using default: us-east-1"
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="cdn-content-${RANDOM_SUFFIX}"
    export LOGS_BUCKET_NAME="cdn-logs-${RANDOM_SUFFIX}"
    export OAC_NAME="cdn-oac-${RANDOM_SUFFIX}"
    export DISTRIBUTION_NAME="cdn-distribution-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Content Bucket: $BUCKET_NAME"
    log "Logs Bucket: $LOGS_BUCKET_NAME"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create S3 bucket for content
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "Content bucket $BUCKET_NAME already exists"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
        log_success "Created content bucket: $BUCKET_NAME"
    fi
    
    # Create S3 bucket for CloudFront logs
    if aws s3api head-bucket --bucket "$LOGS_BUCKET_NAME" 2>/dev/null; then
        log_warning "Logs bucket $LOGS_BUCKET_NAME already exists"
    else
        aws s3 mb "s3://${LOGS_BUCKET_NAME}" --region "$AWS_REGION"
        log_success "Created logs bucket: $LOGS_BUCKET_NAME"
    fi
    
    # Block public access to content bucket
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    log_success "S3 buckets created and secured"
}

# Function to create sample content
create_sample_content() {
    log "Creating sample content..."
    
    # Create sample HTML file
    cat > /tmp/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CDN Test Page</title>
    <link rel="stylesheet" href="styles.css">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .content { padding: 20px 0; }
        .timestamp { color: #666; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>CloudFront CDN Test</h1>
            <p class="timestamp">Generated: $(date)</p>
        </div>
        <div class="content">
            <h2>Welcome to Global Content Delivery</h2>
            <p>This content is served via Amazon CloudFront edge locations worldwide.</p>
            <p>CloudFront provides fast, secure content delivery with automatic caching.</p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create CSS file
    cat > /tmp/styles.css << 'EOF'
/* CDN Test Styles */
body { 
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    min-height: 100vh;
    display: flex;
    align-items: center;
}
.container { 
    background: rgba(255,255,255,0.1);
    backdrop-filter: blur(10px);
    border-radius: 10px;
    padding: 30px;
}
EOF
    
    # Create API response file
    cat > /tmp/api-response.json << 'EOF'
{
    "status": "success",
    "data": {
        "message": "API endpoint cached for 1 hour",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "cacheable": true
    }
}
EOF
    
    # Upload content to S3 bucket
    aws s3 cp /tmp/index.html "s3://${BUCKET_NAME}/"
    aws s3 cp /tmp/styles.css "s3://${BUCKET_NAME}/"
    aws s3 cp /tmp/api-response.json "s3://${BUCKET_NAME}/api/"
    
    # Clean up temporary files
    rm -f /tmp/index.html /tmp/styles.css /tmp/api-response.json
    
    log_success "Sample content created and uploaded"
}

# Function to create Origin Access Control
create_oac() {
    log "Creating Origin Access Control..."
    
    # Create OAC configuration
    cat > /tmp/oac-config.json << EOF
{
    "Name": "${OAC_NAME}",
    "Description": "OAC for CDN content bucket",
    "OriginAccessControlOriginType": "s3",
    "SigningBehavior": "always",
    "SigningProtocol": "sigv4"
}
EOF
    
    # Create the OAC
    export OAC_ID=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config file:///tmp/oac-config.json \
        --query 'OriginAccessControl.Id' --output text)
    
    # Clean up temporary file
    rm -f /tmp/oac-config.json
    
    log_success "Created Origin Access Control: $OAC_ID"
}

# Function to create CloudFront distribution
create_distribution() {
    log "Creating CloudFront distribution..."
    
    # Create distribution configuration
    cat > /tmp/distribution-config.json << EOF
{
    "CallerReference": "${DISTRIBUTION_NAME}-$(date +%s)",
    "Comment": "CDN for global content delivery",
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "${BUCKET_NAME}",
                "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "${OAC_ID}"
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "${BUCKET_NAME}",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["HEAD", "GET"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["HEAD", "GET"]
            }
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true
    },
    "CacheBehaviors": {
        "Quantity": 1,
        "Items": [
            {
                "PathPattern": "*.css",
                "TargetOriginId": "${BUCKET_NAME}",
                "ViewerProtocolPolicy": "redirect-to-https",
                "AllowedMethods": {
                    "Quantity": 2,
                    "Items": ["HEAD", "GET"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["HEAD", "GET"]
                    }
                },
                "ForwardedValues": {
                    "QueryString": false,
                    "Cookies": {
                        "Forward": "none"
                    }
                },
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "MinTTL": 0,
                "DefaultTTL": 2592000,
                "MaxTTL": 31536000,
                "Compress": true
            }
        ]
    },
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 300
            }
        ]
    },
    "Logging": {
        "Enabled": true,
        "IncludeCookies": false,
        "Bucket": "${LOGS_BUCKET_NAME}.s3.amazonaws.com",
        "Prefix": "cloudfront-logs/"
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021"
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    },
    "HttpVersion": "http2",
    "IsIPV6Enabled": true
}
EOF
    
    # Create the distribution
    DISTRIBUTION_OUTPUT=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/distribution-config.json)
    
    # Extract distribution ID and domain name
    export DISTRIBUTION_ID=$(echo "$DISTRIBUTION_OUTPUT" | jq -r '.Distribution.Id')
    export DISTRIBUTION_DOMAIN=$(echo "$DISTRIBUTION_OUTPUT" | jq -r '.Distribution.DomainName')
    
    # Clean up temporary file
    rm -f /tmp/distribution-config.json
    
    log_success "Created CloudFront distribution: $DISTRIBUTION_ID"
    log_success "Distribution domain: $DISTRIBUTION_DOMAIN"
}

# Function to configure S3 bucket policy
configure_bucket_policy() {
    log "Configuring S3 bucket policy for OAC access..."
    
    # Create bucket policy for OAC
    cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
EOF
    
    # Apply the bucket policy
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file:///tmp/bucket-policy.json
    
    # Clean up temporary file
    rm -f /tmp/bucket-policy.json
    
    log_success "Applied S3 bucket policy for OAC access"
}

# Function to wait for distribution deployment
wait_for_deployment() {
    log "Waiting for CloudFront distribution deployment..."
    log_warning "This typically takes 10-15 minutes. Please be patient..."
    
    # Show spinner while waiting
    (
        while ps aux | grep -q "[w]ait distribution-deployed"; do
            printf "."
            sleep 5
        done
    ) &
    
    # Wait for distribution to be deployed
    aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
    
    log_success "CloudFront distribution deployed successfully"
}

# Function to create CloudWatch monitoring
create_monitoring() {
    log "Creating CloudWatch monitoring..."
    
    # Create CloudWatch alarm for high error rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "CloudFront-HighErrorRate-${DISTRIBUTION_ID}" \
        --alarm-description "High error rate for CloudFront distribution" \
        --metric-name "4xxErrorRate" \
        --namespace "AWS/CloudFront" \
        --statistic "Average" \
        --period 300 \
        --threshold 5 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=DistributionId,Value="$DISTRIBUTION_ID" \
        --region us-east-1
    
    # Create CloudWatch alarm for origin latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "CloudFront-HighOriginLatency-${DISTRIBUTION_ID}" \
        --alarm-description "High origin latency for CloudFront distribution" \
        --metric-name "OriginLatency" \
        --namespace "AWS/CloudFront" \
        --statistic "Average" \
        --period 300 \
        --threshold 1000 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=DistributionId,Value="$DISTRIBUTION_ID" \
        --region us-east-1
    
    # Create CloudWatch dashboard
    cat > /tmp/dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/CloudFront", "Requests", "DistributionId", "${DISTRIBUTION_ID}"],
                    [".", "BytesDownloaded", ".", "."],
                    [".", "4xxErrorRate", ".", "."],
                    [".", "5xxErrorRate", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "CloudFront Performance Metrics"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/CloudFront", "CacheHitRate", "DistributionId", "${DISTRIBUTION_ID}"],
                    [".", "OriginLatency", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Cache Performance"
            }
        }
    ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "CloudFront-CDN-Performance" \
        --dashboard-body file:///tmp/dashboard-config.json \
        --region us-east-1
    
    # Clean up temporary file
    rm -f /tmp/dashboard-config.json
    
    log_success "Created CloudWatch alarms and dashboard"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    cat > /tmp/deployment-info.json << EOF
{
    "deployment_id": "${DISTRIBUTION_NAME}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resources": {
        "content_bucket": "${BUCKET_NAME}",
        "logs_bucket": "${LOGS_BUCKET_NAME}",
        "oac_id": "${OAC_ID}",
        "distribution_id": "${DISTRIBUTION_ID}",
        "distribution_domain": "${DISTRIBUTION_DOMAIN}"
    }
}
EOF
    
    # Save to current directory
    mv /tmp/deployment-info.json ./cdn-deployment-info.json
    
    log_success "Deployment information saved to cdn-deployment-info.json"
}

# Function to run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Test CloudFront distribution
    log "Testing CloudFront distribution accessibility..."
    if curl -s -I "https://${DISTRIBUTION_DOMAIN}" | grep -q "200 OK"; then
        log_success "Distribution is accessible"
    else
        log_warning "Distribution may not be fully ready yet"
    fi
    
    # Test direct S3 access (should fail)
    log "Testing direct S3 access (should be blocked)..."
    if curl -s -I "https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/index.html" | grep -q "403 Forbidden"; then
        log_success "Direct S3 access is properly blocked"
    else
        log_warning "Direct S3 access test inconclusive"
    fi
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETE ==="
    echo ""
    echo "📋 Deployment Summary:"
    echo "  🌍 CloudFront Distribution: $DISTRIBUTION_ID"
    echo "  🔗 Distribution Domain: $DISTRIBUTION_DOMAIN"
    echo "  📦 Content Bucket: $BUCKET_NAME"
    echo "  📊 Logs Bucket: $LOGS_BUCKET_NAME"
    echo "  🔐 Origin Access Control: $OAC_ID"
    echo ""
    echo "🔗 Access your CDN at: https://$DISTRIBUTION_DOMAIN"
    echo ""
    echo "📊 Monitor performance:"
    echo "  • CloudWatch Dashboard: CloudFront-CDN-Performance"
    echo "  • CloudWatch Alarms: CloudFront-HighErrorRate-$DISTRIBUTION_ID"
    echo "                       CloudFront-HighOriginLatency-$DISTRIBUTION_ID"
    echo ""
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo "📄 Deployment details saved to: cdn-deployment-info.json"
}

# Main execution
main() {
    log "Starting CloudFront CDN deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_sample_content
    create_oac
    create_distribution
    configure_bucket_policy
    wait_for_deployment
    create_monitoring
    save_deployment_info
    run_validation_tests
    display_summary
    
    log_success "CloudFront CDN deployment completed successfully!"
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Check the error above for details."' ERR

# Run main function
main "$@"