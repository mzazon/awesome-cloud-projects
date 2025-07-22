#!/bin/bash

# =============================================================================
# AWS CloudFront CDN Deployment Script
# CDN with CloudFront Origin Access Controls
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Deployment configuration
readonly MAX_RETRIES=3
readonly WAIT_TIMEOUT=1800  # 30 minutes for CloudFront deployment

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Save current state for potential recovery
    if [[ -f "$STATE_FILE" ]]; then
        cp "$STATE_FILE" "${STATE_FILE}.failed.$(date +%s)"
    fi
    
    # Attempt cleanup
    if command -v ./destroy.sh &> /dev/null; then
        log_info "Running cleanup script..."
        ./destroy.sh --force 2>/dev/null || true
    fi
    
    exit 1
}

trap cleanup_on_error ERR

save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "$STATE_FILE"
}

get_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2- | tail -1
    fi
}

wait_for_resource() {
    local check_command="$1"
    local description="$2"
    local timeout="${3:-300}"
    
    log_info "Waiting for ${description}..."
    local elapsed=0
    local interval=10
    
    while ! eval "$check_command" &>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for ${description}"
            return 1
        fi
        
        printf "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    log_success "${description} is ready"
}

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
    log_info "AWS CLI version: ${aws_version}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    local tools=("jq" "curl")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '${tool}' is not installed."
            exit 1
        fi
    done
    
    # Check AWS permissions
    log_info "Checking AWS permissions..."
    local required_permissions=(
        "s3:CreateBucket"
        "s3:PutObject"
        "s3:PutBucketPolicy"
        "cloudfront:CreateDistribution"
        "cloudfront:CreateOriginAccessControl"
        "wafv2:CreateWebACL"
        "cloudwatch:PutMetricAlarm"
        "iam:PassRole"
    )
    
    # Note: Full permission check would require AWS Access Analyzer or custom policy simulation
    log_info "Please ensure you have permissions for: ${required_permissions[*]}"
    
    log_success "Prerequisites check completed"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    log_info "Setting up environment variables..."
    
    # AWS configuration
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No region configured, using default: ${AWS_REGION}"
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || openssl rand -hex 4)
    
    # Resource names
    export BUCKET_NAME="cdn-content-${random_suffix}"
    export LOGS_BUCKET_NAME="cdn-logs-${random_suffix}"
    export OAC_NAME="cdn-oac-${random_suffix}"
    export DISTRIBUTION_COMMENT="CDN Distribution ${random_suffix}"
    export WAF_NAME="cdn-waf-${random_suffix}"
    
    # Save configuration to state file
    cat > "$STATE_FILE" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
LOGS_BUCKET_NAME=${LOGS_BUCKET_NAME}
OAC_NAME=${OAC_NAME}
DISTRIBUTION_COMMENT=${DISTRIBUTION_COMMENT}
WAF_NAME=${WAF_NAME}
RANDOM_SUFFIX=${random_suffix}
EOF
    
    log_info "Environment configured:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account: ${AWS_ACCOUNT_ID}"
    log_info "  Content Bucket: ${BUCKET_NAME}"
    log_info "  Logs Bucket: ${LOGS_BUCKET_NAME}"
    
    log_success "Environment setup completed"
}

# =============================================================================
# Sample Content Creation
# =============================================================================

create_sample_content() {
    log_info "Creating sample content..."
    
    local content_dir="${SCRIPT_DIR}/cdn-content"
    mkdir -p "${content_dir}"/{images,css,js}
    
    # Create HTML file
    cat > "${content_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CDN Test Page</title>
    <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
    <h1>CloudFront CDN Test</h1>
    <p>This content is served through Amazon CloudFront with Origin Access Control.</p>
    <img src="/images/test-image.jpg" alt="Test Image">
    <script src="/js/main.js"></script>
</body>
</html>
EOF
    
    # Create CSS file
    cat > "${content_dir}/css/styles.css" << 'EOF'
body { 
    font-family: Arial, sans-serif; 
    margin: 40px; 
    background-color: #f5f5f5;
}
h1 { 
    color: #232F3E; 
    border-bottom: 2px solid #FF9900;
    padding-bottom: 10px;
}
img { 
    max-width: 100%; 
    height: auto; 
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 5px;
}
p {
    color: #666;
    line-height: 1.6;
}
EOF
    
    # Create JavaScript file
    cat > "${content_dir}/js/main.js" << 'EOF'
console.log('CDN assets loaded successfully from CloudFront');
document.addEventListener('DOMContentLoaded', function() {
    console.log('Page loaded at:', new Date().toISOString());
    
    // Add load time display
    const loadTime = window.performance.timing.loadEventEnd - window.performance.timing.navigationStart;
    console.log('Page load time:', loadTime + 'ms');
});
EOF
    
    # Create sample image (base64 encoded small PNG)
    cat > "${content_dir}/images/test-image.jpg" << 'EOF'
This is a sample image placeholder for CDN testing.
In a real scenario, this would be an actual image file.
EOF
    
    save_state "CONTENT_DIR" "$content_dir"
    log_success "Sample content created in ${content_dir}"
}

# =============================================================================
# S3 Bucket Creation and Configuration
# =============================================================================

create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create main content bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "Bucket ${BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
        log_success "Created content bucket: ${BUCKET_NAME}"
    fi
    
    # Create logs bucket
    if aws s3api head-bucket --bucket "$LOGS_BUCKET_NAME" 2>/dev/null; then
        log_warning "Bucket ${LOGS_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${LOGS_BUCKET_NAME}" --region "$AWS_REGION"
        log_success "Created logs bucket: ${LOGS_BUCKET_NAME}"
    fi
    
    # Block public access on both buckets
    for bucket in "$BUCKET_NAME" "$LOGS_BUCKET_NAME"; do
        aws s3api put-public-access-block \
            --bucket "$bucket" \
            --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        
        log_info "Applied public access block to ${bucket}"
    done
    
    save_state "BUCKET_CREATED" "true"
    save_state "LOGS_BUCKET_CREATED" "true"
    log_success "S3 buckets configured with security settings"
}

upload_content() {
    log_info "Uploading sample content to S3..."
    
    local content_dir
    content_dir=$(get_state "CONTENT_DIR")
    
    if [[ ! -d "$content_dir" ]]; then
        log_error "Content directory not found: ${content_dir}"
        return 1
    fi
    
    # Upload HTML files
    aws s3 cp "${content_dir}/" "s3://${BUCKET_NAME}/" \
        --recursive \
        --exclude "*" \
        --include "*.html" \
        --content-type "text/html" \
        --cache-control "max-age=3600"
    
    # Upload CSS files
    aws s3 cp "${content_dir}/css/" "s3://${BUCKET_NAME}/css/" \
        --recursive \
        --content-type "text/css" \
        --cache-control "max-age=86400"
    
    # Upload JavaScript files
    aws s3 cp "${content_dir}/js/" "s3://${BUCKET_NAME}/js/" \
        --recursive \
        --content-type "application/javascript" \
        --cache-control "max-age=86400"
    
    # Upload image files
    aws s3 cp "${content_dir}/images/" "s3://${BUCKET_NAME}/images/" \
        --recursive \
        --content-type "image/jpeg" \
        --cache-control "max-age=604800"
    
    save_state "CONTENT_UPLOADED" "true"
    log_success "Content uploaded with appropriate MIME types and cache headers"
}

# =============================================================================
# Origin Access Control Creation
# =============================================================================

create_origin_access_control() {
    log_info "Creating Origin Access Control..."
    
    # Create OAC configuration
    local oac_config
    oac_config=$(cat << EOF
{
    "Name": "${OAC_NAME}",
    "Description": "Origin Access Control for ${BUCKET_NAME}",
    "OriginAccessControlConfig": {
        "Name": "${OAC_NAME}",
        "Description": "OAC for secure S3 access",
        "SigningProtocol": "sigv4",
        "SigningBehavior": "always",
        "OriginAccessControlOriginType": "s3"
    }
}
EOF
)
    
    # Create the OAC
    local oac_output
    oac_output=$(echo "$oac_config" | aws cloudfront create-origin-access-control \
        --origin-access-control-config file:///dev/stdin)
    
    local oac_id
    oac_id=$(echo "$oac_output" | jq -r '.OriginAccessControl.Id')
    
    save_state "OAC_ID" "$oac_id"
    log_success "Created Origin Access Control: ${oac_id}"
}

# =============================================================================
# WAF Web ACL Creation
# =============================================================================

create_waf_web_acl() {
    log_info "Creating WAF Web ACL for security..."
    
    # Create WAF configuration
    local waf_config
    waf_config=$(cat << EOF
{
    "Name": "${WAF_NAME}",
    "Scope": "CLOUDFRONT",
    "DefaultAction": {
        "Allow": {}
    },
    "Rules": [
        {
            "Name": "AWSManagedRulesCommonRuleSet",
            "Priority": 1,
            "OverrideAction": {
                "None": {}
            },
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesCommonRuleSet"
                }
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "CommonRuleSetMetric"
            }
        },
        {
            "Name": "RateLimitRule",
            "Priority": 2,
            "Action": {
                "Block": {}
            },
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 2000,
                    "AggregateKeyType": "IP"
                }
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitMetric"
            }
        }
    ],
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "CDNWebACL"
    }
}
EOF
)
    
    # Create the Web ACL
    local waf_output
    waf_output=$(echo "$waf_config" | aws wafv2 create-web-acl \
        --cli-input-json file:///dev/stdin)
    
    local waf_arn
    waf_arn=$(echo "$waf_output" | jq -r '.Summary.ARN')
    
    save_state "WAF_ARN" "$waf_arn"
    log_success "Created WAF Web ACL: ${waf_arn}"
}

# =============================================================================
# CloudFront Distribution Creation
# =============================================================================

create_cloudfront_distribution() {
    log_info "Creating CloudFront distribution..."
    
    local oac_id
    oac_id=$(get_state "OAC_ID")
    local waf_arn
    waf_arn=$(get_state "WAF_ARN")
    
    if [[ -z "$oac_id" ]] || [[ -z "$waf_arn" ]]; then
        log_error "Missing required components: OAC_ID or WAF_ARN"
        return 1
    fi
    
    # Create distribution configuration
    local distribution_config
    distribution_config=$(cat << EOF
{
    "CallerReference": "$(date +%s)-${RANDOM}",
    "Comment": "${DISTRIBUTION_COMMENT}",
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
                "OriginAccessControlId": "${oac_id}",
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10,
                "OriginShield": {
                    "Enabled": false
                }
            }
        ]
    },
    "OriginGroups": {
        "Quantity": 0
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "${BUCKET_NAME}",
        "ViewerProtocolPolicy": "redirect-to-https",
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
        "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
        "ResponseHeadersPolicyId": "5cc3b908-e619-4b99-88e5-2cf7f45965bd",
        "Compress": true,
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "TrustedKeyGroups": {
            "Enabled": false,
            "Quantity": 0
        },
        "FieldLevelEncryptionId": ""
    },
    "CacheBehaviors": {
        "Quantity": 3,
        "Items": [
            {
                "PathPattern": "/images/*",
                "TargetOriginId": "${BUCKET_NAME}",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "Compress": true,
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "FieldLevelEncryptionId": ""
            },
            {
                "PathPattern": "/css/*",
                "TargetOriginId": "${BUCKET_NAME}",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "Compress": true,
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "FieldLevelEncryptionId": ""
            },
            {
                "PathPattern": "/js/*",
                "TargetOriginId": "${BUCKET_NAME}",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "Compress": true,
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "FieldLevelEncryptionId": ""
            }
        ]
    },
    "CustomErrorResponses": {
        "Quantity": 2,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 300
            },
            {
                "ErrorCode": 403,
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
    "PriceClass": "PriceClass_All",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021",
        "CertificateSource": "cloudfront"
    },
    "WebACLId": "${waf_arn}",
    "HttpVersion": "http2and3",
    "IsIPV6Enabled": true,
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    }
}
EOF
)
    
    # Create the distribution
    local distribution_output
    distribution_output=$(echo "$distribution_config" | aws cloudfront create-distribution \
        --distribution-config file:///dev/stdin)
    
    local distribution_id
    distribution_id=$(echo "$distribution_output" | jq -r '.Distribution.Id')
    local distribution_domain
    distribution_domain=$(echo "$distribution_output" | jq -r '.Distribution.DomainName')
    
    save_state "DISTRIBUTION_ID" "$distribution_id"
    save_state "DISTRIBUTION_DOMAIN" "$distribution_domain"
    
    log_success "Created CloudFront distribution: ${distribution_id}"
    log_info "Distribution domain: ${distribution_domain}"
}

# =============================================================================
# S3 Bucket Policy Configuration
# =============================================================================

configure_s3_bucket_policy() {
    log_info "Configuring S3 bucket policy for OAC access..."
    
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    
    if [[ -z "$distribution_id" ]]; then
        log_error "Distribution ID not found"
        return 1
    fi
    
    # Create S3 bucket policy
    local bucket_policy
    bucket_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipalReadOnly",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${distribution_id}"
                }
            }
        }
    ]
}
EOF
)
    
    # Apply the bucket policy
    echo "$bucket_policy" | aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file:///dev/stdin
    
    save_state "BUCKET_POLICY_APPLIED" "true"
    log_success "Applied S3 bucket policy for OAC access"
}

# =============================================================================
# CloudFront Distribution Deployment Wait
# =============================================================================

wait_for_distribution_deployment() {
    log_info "Waiting for CloudFront distribution deployment..."
    
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    
    if [[ -z "$distribution_id" ]]; then
        log_error "Distribution ID not found"
        return 1
    fi
    
    # Wait for distribution to be deployed
    wait_for_resource \
        "aws cloudfront get-distribution --id ${distribution_id} --query 'Distribution.Status' --output text | grep -q 'Deployed'" \
        "CloudFront distribution deployment" \
        "$WAIT_TIMEOUT"
    
    # Enable additional metrics
    aws cloudfront put-monitoring-subscription \
        --distribution-id "$distribution_id" \
        --monitoring-subscription 'RealtimeMetricsSubscriptionConfig={RealtimeMetricsSubscriptionStatus=Enabled}' \
        2>/dev/null || log_warning "Could not enable real-time metrics (may require additional permissions)"
    
    save_state "DISTRIBUTION_DEPLOYED" "true"
    log_success "CloudFront distribution deployed and monitoring enabled"
}

# =============================================================================
# CloudWatch Alarms Creation
# =============================================================================

create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms for monitoring..."
    
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    
    if [[ -z "$distribution_id" ]]; then
        log_error "Distribution ID not found"
        return 1
    fi
    
    # Create alarm for 4xx error rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "CloudFront-4xx-Errors-${distribution_id}" \
        --alarm-description "High 4xx error rate for CloudFront distribution" \
        --metric-name "4xxErrorRate" \
        --namespace "AWS/CloudFront" \
        --statistic "Average" \
        --period 300 \
        --threshold 5.0 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=DistributionId,Value="$distribution_id" \
        --treat-missing-data "notBreaching"
    
    # Create alarm for cache hit rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "CloudFront-Low-Cache-Hit-Rate-${distribution_id}" \
        --alarm-description "Low cache hit rate for CloudFront distribution" \
        --metric-name "CacheHitRate" \
        --namespace "AWS/CloudFront" \
        --statistic "Average" \
        --period 300 \
        --threshold 80.0 \
        --comparison-operator "LessThanThreshold" \
        --evaluation-periods 3 \
        --dimensions Name=DistributionId,Value="$distribution_id" \
        --treat-missing-data "notBreaching"
    
    save_state "CLOUDWATCH_ALARMS_CREATED" "true"
    log_success "Created CloudWatch alarms for monitoring"
}

# =============================================================================
# Testing and Validation
# =============================================================================

test_deployment() {
    log_info "Testing CDN deployment and security features..."
    
    local distribution_domain
    distribution_domain=$(get_state "DISTRIBUTION_DOMAIN")
    
    if [[ -z "$distribution_domain" ]]; then
        log_error "Distribution domain not found"
        return 1
    fi
    
    # Test CloudFront distribution
    log_info "Testing CloudFront distribution..."
    
    local test_url="https://${distribution_domain}"
    
    # Test main page
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$test_url" || echo "000")
    
    if [[ "$http_status" == "200" ]]; then
        log_success "Main page test: HTTP ${http_status} ✓"
    else
        log_warning "Main page test: HTTP ${http_status} (may need more time to propagate)"
    fi
    
    # Test CSS file
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "${test_url}/css/styles.css" || echo "000")
    if [[ "$http_status" == "200" ]]; then
        log_success "CSS file test: HTTP ${http_status} ✓"
    else
        log_warning "CSS file test: HTTP ${http_status}"
    fi
    
    # Test that direct S3 access is blocked
    log_info "Testing direct S3 access (should be blocked)..."
    local s3_url="https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/index.html"
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "$s3_url" || echo "000")
    
    if [[ "$http_status" == "403" ]]; then
        log_success "Direct S3 access blocked: HTTP ${http_status} ✓"
    else
        log_warning "Direct S3 access test: HTTP ${http_status} (unexpected)"
    fi
    
    save_state "DEPLOYMENT_TESTED" "true"
}

# =============================================================================
# Deployment Summary
# =============================================================================

display_deployment_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    
    local distribution_domain
    distribution_domain=$(get_state "DISTRIBUTION_DOMAIN")
    local distribution_id
    distribution_id=$(get_state "DISTRIBUTION_ID")
    
    echo ""
    log_success "✅ CDN Deployment Complete!"
    echo ""
    log_info "CloudFront Distribution:"
    log_info "  Distribution ID: ${distribution_id}"
    log_info "  Domain: ${distribution_domain}"
    echo ""
    log_info "Test URLs:"
    log_info "  Main page: https://${distribution_domain}"
    log_info "  CSS: https://${distribution_domain}/css/styles.css"
    log_info "  JS: https://${distribution_domain}/js/main.js"
    log_info "  Image: https://${distribution_domain}/images/test-image.jpg"
    echo ""
    log_info "AWS Resources Created:"
    log_info "  S3 Content Bucket: ${BUCKET_NAME}"
    log_info "  S3 Logs Bucket: ${LOGS_BUCKET_NAME}"
    log_info "  Origin Access Control: $(get_state "OAC_ID")"
    log_info "  WAF Web ACL: $(get_state "WAF_ARN")"
    echo ""
    log_info "Monitoring:"
    log_info "  CloudWatch Alarms: Created for 4xx errors and cache hit rate"
    log_info "  Real-time Metrics: Enabled (if permissions allow)"
    echo ""
    log_info "Security Features:"
    log_info "  ✓ Origin Access Control (OAC) protecting S3"
    log_info "  ✓ WAF with managed rules and rate limiting"
    log_info "  ✓ HTTPS-only access enforced"
    log_info "  ✓ Security headers applied"
    echo ""
    log_warning "Note: CloudFront global propagation may take 15-20 minutes."
    log_info "State file saved to: ${STATE_FILE}"
    echo ""
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log_info "Starting AWS CloudFront CDN deployment..."
    log_info "Script: $0"
    log_info "Working directory: $(pwd)"
    log_info "Timestamp: $(date)"
    
    # Parse command line arguments
    local dry_run=false
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --help)
                cat << EOF
AWS CloudFront CDN Deployment Script

Usage: $0 [OPTIONS]

Options:
    --dry-run    Perform a dry run (check prerequisites only)
    --force      Force deployment even if state file exists
    --help       Show this help message

This script deploys a complete CDN solution with:
- Amazon CloudFront distribution
- S3 origin with Origin Access Control
- AWS WAF for security
- CloudWatch monitoring and alarms
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check if deployment already exists
    if [[ -f "$STATE_FILE" ]] && [[ "$force" != true ]]; then
        log_warning "Deployment state file exists: ${STATE_FILE}"
        log_warning "Use --force to redeploy or run destroy.sh first"
        exit 1
    fi
    
    # Initialize log file
    echo "AWS CloudFront CDN Deployment Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "==========================================" >> "$LOG_FILE"
    
    # Prerequisites check
    check_prerequisites
    
    if [[ "$dry_run" == true ]]; then
        log_info "Dry run completed successfully"
        exit 0
    fi
    
    # Main deployment steps
    setup_environment
    create_sample_content
    create_s3_buckets
    upload_content
    create_origin_access_control
    create_waf_web_acl
    create_cloudfront_distribution
    configure_s3_bucket_policy
    wait_for_distribution_deployment
    create_cloudwatch_alarms
    test_deployment
    
    # Display summary
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
    log_info "Total runtime: $SECONDS seconds"
}

# =============================================================================
# Script Execution
# =============================================================================

# Ensure script is executable
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi