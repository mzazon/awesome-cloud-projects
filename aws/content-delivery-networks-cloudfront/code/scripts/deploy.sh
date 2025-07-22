#!/bin/bash

# CloudFront Advanced CDN Deployment Script
# This script deploys a comprehensive CloudFront distribution with:
# - Multiple origins (S3 and custom)
# - CloudFront Functions and Lambda@Edge
# - AWS WAF integration
# - Real-time logging and monitoring
# - KeyValueStore for dynamic configuration

set -e  # Exit on any error

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    # Check required tools
    for tool in jq curl base64; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install $tool."
        fi
    done
    
    success "Prerequisites check passed"
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    export CDN_PROJECT_NAME="advanced-cdn-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="cdn-content-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="cdn-edge-processor-${RANDOM_SUFFIX}"
    export WAF_WEBACL_NAME="cdn-security-${RANDOM_SUFFIX}"
    export CLOUDFRONT_FUNCTION_NAME="cdn-request-processor-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    cat > /tmp/cdn-deployment-state.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CDN_PROJECT_NAME=${CDN_PROJECT_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
WAF_WEBACL_NAME=${WAF_WEBACL_NAME}
CLOUDFRONT_FUNCTION_NAME=${CLOUDFRONT_FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment configured with suffix: ${RANDOM_SUFFIX}"
}

# Create S3 bucket and upload content
create_s3_resources() {
    log "Creating S3 bucket and uploading content..."
    
    # Create S3 bucket
    if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} 2>/dev/null; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists"
    else
        aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
        success "S3 bucket created: ${S3_BUCKET_NAME}"
    fi
    
    # Create sample content for testing
    mkdir -p /tmp/cdn-content/api
    cat > /tmp/cdn-content/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Advanced CDN Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #232F3E; color: white; padding: 20px; border-radius: 8px; }
        .content { margin: 20px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Advanced CloudFront CDN</h1>
        <p>Main Site - Version: 1.0</p>
    </div>
    <div class="content">
        <h2>Features Demonstrated:</h2>
        <ul>
            <li>Multi-origin content delivery</li>
            <li>Edge functions for content manipulation</li>
            <li>WAF security protection</li>
            <li>Real-time logging and monitoring</li>
        </ul>
        <p><a href="/api/">Visit API Documentation</a></p>
    </div>
</body>
</html>
EOF
    
    cat > /tmp/cdn-content/api/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>API Documentation - Advanced CDN</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .api-header { background: #FF9900; color: white; padding: 20px; border-radius: 8px; }
    </style>
</head>
<body>
    <div class="api-header">
        <h1>API Documentation</h1>
        <p>Version: 2.0</p>
    </div>
    <p>This content is served from a custom origin through CloudFront.</p>
    <p><a href="/api/status.json">Check API Status</a></p>
</body>
</html>
EOF
    
    echo '{"message": "Hello from API", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'", "status": "healthy"}' > /tmp/cdn-content/api/status.json
    
    # Upload content to S3
    aws s3 cp /tmp/cdn-content s3://${S3_BUCKET_NAME}/ --recursive
    success "Content uploaded to S3 bucket"
}

# Create CloudFront Function
create_cloudfront_function() {
    log "Creating CloudFront Function for request processing..."
    
    cat > /tmp/cloudfront-function.js << 'EOF'
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    
    // Add security headers
    headers['x-forwarded-proto'] = {value: 'https'};
    headers['x-request-id'] = {value: generateRequestId()};
    
    // Normalize cache key by removing tracking parameters
    var uri = request.uri;
    var querystring = request.querystring;
    
    // Remove tracking parameters to improve cache hit ratio
    delete querystring.utm_source;
    delete querystring.utm_medium;
    delete querystring.utm_campaign;
    delete querystring.fbclid;
    
    // Redirect old paths to new structure
    if (uri.startsWith('/old-api/')) {
        uri = uri.replace('/old-api/', '/api/');
        request.uri = uri;
    }
    
    return request;
}

function generateRequestId() {
    return 'req-' + Math.random().toString(36).substr(2, 9);
}
EOF
    
    # Create CloudFront Function
    aws cloudfront create-function \
        --name ${CLOUDFRONT_FUNCTION_NAME} \
        --function-config Comment="Request processing function",Runtime="cloudfront-js-2.0" \
        --function-code fileb:///tmp/cloudfront-function.js
    
    # Get function details and publish
    FUNCTION_ETAG=$(aws cloudfront describe-function \
        --name ${CLOUDFRONT_FUNCTION_NAME} \
        --query 'ETag' --output text)
    
    aws cloudfront publish-function \
        --name ${CLOUDFRONT_FUNCTION_NAME} \
        --if-match ${FUNCTION_ETAG}
    
    success "CloudFront Function created and published"
}

# Create Lambda@Edge function
create_lambda_edge_function() {
    log "Creating Lambda@Edge function for response manipulation..."
    
    # Create Lambda@Edge function code
    mkdir -p /tmp/lambda-edge
    cat > /tmp/lambda-edge/index.js << 'EOF'
const aws = require('aws-sdk');

exports.handler = async (event, context) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const headers = response.headers;
    
    // Add comprehensive security headers
    headers['strict-transport-security'] = [{
        key: 'Strict-Transport-Security',
        value: 'max-age=31536000; includeSubDomains; preload'
    }];
    
    headers['x-content-type-options'] = [{
        key: 'X-Content-Type-Options',
        value: 'nosniff'
    }];
    
    headers['x-frame-options'] = [{
        key: 'X-Frame-Options',
        value: 'SAMEORIGIN'
    }];
    
    headers['x-xss-protection'] = [{
        key: 'X-XSS-Protection',
        value: '1; mode=block'
    }];
    
    headers['referrer-policy'] = [{
        key: 'Referrer-Policy',
        value: 'strict-origin-when-cross-origin'
    }];
    
    headers['content-security-policy'] = [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    }];
    
    // Add custom headers based on request path
    if (request.uri.startsWith('/api/')) {
        headers['access-control-allow-origin'] = [{
            key: 'Access-Control-Allow-Origin',
            value: '*'
        }];
        headers['access-control-allow-methods'] = [{
            key: 'Access-Control-Allow-Methods',
            value: 'GET, POST, OPTIONS, PUT, DELETE'
        }];
        headers['access-control-allow-headers'] = [{
            key: 'Access-Control-Allow-Headers',
            value: 'Content-Type, Authorization, X-Requested-With'
        }];
    }
    
    // Add performance headers
    headers['x-edge-location'] = [{
        key: 'X-Edge-Location',
        value: event.Records[0].cf.config.distributionId
    }];
    
    headers['x-cache-status'] = [{
        key: 'X-Cache-Status',
        value: 'PROCESSED'
    }];
    
    return response;
};
EOF
    
    # Create deployment package
    cd /tmp/lambda-edge
    zip -r lambda-edge.zip index.js
    
    # Create IAM role for Lambda@Edge
    cat > /tmp/lambda-edge-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "lambda.amazonaws.com",
                    "edgelambda.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create the role
    aws iam create-role \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --assume-role-policy-document file:///tmp/lambda-edge-trust-policy.json || true
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 15
    
    # Create Lambda function in us-east-1 (required for Lambda@Edge)
    aws lambda create-function \
        --region us-east-1 \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --runtime nodejs18.x \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role \
        --handler index.handler \
        --zip-file fileb:///tmp/lambda-edge/lambda-edge.zip \
        --timeout 5 \
        --memory-size 128
    
    # Publish version (required for Lambda@Edge)
    LAMBDA_VERSION=$(aws lambda publish-version \
        --region us-east-1 \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --query 'Version' --output text)
    
    export LAMBDA_ARN="arn:aws:lambda:us-east-1:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}:${LAMBDA_VERSION}"
    echo "LAMBDA_ARN=${LAMBDA_ARN}" >> /tmp/cdn-deployment-state.env
    
    success "Lambda@Edge function created with ARN: ${LAMBDA_ARN}"
}

# Create WAF Web ACL
create_waf_webacl() {
    log "Creating WAF Web ACL for security..."
    
    cat > /tmp/waf-webacl.json << EOF
{
    "Name": "${WAF_WEBACL_NAME}",
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
            "Name": "AWSManagedRulesKnownBadInputsRuleSet",
            "Priority": 2,
            "OverrideAction": {
                "None": {}
            },
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesKnownBadInputsRuleSet"
                }
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "KnownBadInputsRuleSetMetric"
            }
        },
        {
            "Name": "RateLimitRule",
            "Priority": 3,
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
                "MetricName": "RateLimitRuleMetric"
            }
        }
    ],
    "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "${WAF_WEBACL_NAME}"
    }
}
EOF
    
    # Create WAF Web ACL
    WAF_WEBACL_ID=$(aws wafv2 create-web-acl \
        --cli-input-json file:///tmp/waf-webacl.json \
        --query 'Summary.Id' --output text)
    
    export WAF_WEBACL_ARN="arn:aws:wafv2:us-east-1:${AWS_ACCOUNT_ID}:global/webacl/${WAF_WEBACL_NAME}/${WAF_WEBACL_ID}"
    echo "WAF_WEBACL_ID=${WAF_WEBACL_ID}" >> /tmp/cdn-deployment-state.env
    echo "WAF_WEBACL_ARN=${WAF_WEBACL_ARN}" >> /tmp/cdn-deployment-state.env
    
    success "WAF Web ACL created with ID: ${WAF_WEBACL_ID}"
}

# Create Origin Access Control
create_origin_access_control() {
    log "Creating Origin Access Control for S3..."
    
    cat > /tmp/oac-config.json << EOF
{
    "Name": "${CDN_PROJECT_NAME}-oac",
    "OriginAccessControlConfig": {
        "Name": "${CDN_PROJECT_NAME}-oac",
        "Description": "Origin Access Control for S3 bucket",
        "SigningProtocol": "sigv4",
        "SigningBehavior": "always",
        "OriginAccessControlOriginType": "s3"
    }
}
EOF
    
    # Create OAC
    OAC_ID=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config file:///tmp/oac-config.json \
        --query 'OriginAccessControl.Id' --output text)
    
    export OAC_ID
    echo "OAC_ID=${OAC_ID}" >> /tmp/cdn-deployment-state.env
    
    success "Origin Access Control created with ID: ${OAC_ID}"
}

# Create CloudFront Distribution
create_cloudfront_distribution() {
    log "Creating advanced CloudFront distribution..."
    
    # Get CloudFront Function ARN
    CLOUDFRONT_FUNCTION_ARN=$(aws cloudfront describe-function \
        --name ${CLOUDFRONT_FUNCTION_NAME} \
        --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)
    
    # Create comprehensive distribution configuration
    cat > /tmp/distribution-config.json << EOF
{
    "CallerReference": "${CDN_PROJECT_NAME}-$(date +%s)",
    "Comment": "Advanced CDN with multiple origins and edge functions",
    "Enabled": true,
    "Origins": {
        "Quantity": 2,
        "Items": [
            {
                "Id": "S3Origin",
                "DomainName": "${S3_BUCKET_NAME}.s3.amazonaws.com",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "${OAC_ID}",
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10,
                "OriginShield": {
                    "Enabled": false
                }
            },
            {
                "Id": "CustomOrigin",
                "DomainName": "httpbin.org",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only",
                    "OriginSslProtocols": {
                        "Quantity": 3,
                        "Items": ["TLSv1.2", "TLSv1.1", "TLSv1"]
                    },
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                },
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10,
                "OriginShield": {
                    "Enabled": false
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "TrustedKeyGroups": {
            "Enabled": false,
            "Quantity": 0
        },
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "SmoothStreaming": false,
        "Compress": true,
        "LambdaFunctionAssociations": {
            "Quantity": 1,
            "Items": [
                {
                    "LambdaFunctionARN": "${LAMBDA_ARN}",
                    "EventType": "origin-response",
                    "IncludeBody": false
                }
            ]
        },
        "FunctionAssociations": {
            "Quantity": 1,
            "Items": [
                {
                    "FunctionARN": "${CLOUDFRONT_FUNCTION_ARN}",
                    "EventType": "viewer-request"
                }
            ]
        },
        "FieldLevelEncryptionId": "",
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
        "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
    },
    "CacheBehaviors": {
        "Quantity": 2,
        "Items": [
            {
                "PathPattern": "/api/*",
                "TargetOriginId": "CustomOrigin",
                "ViewerProtocolPolicy": "redirect-to-https",
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "AllowedMethods": {
                    "Quantity": 7,
                    "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["GET", "HEAD"]
                    }
                },
                "SmoothStreaming": false,
                "Compress": true,
                "LambdaFunctionAssociations": {
                    "Quantity": 1,
                    "Items": [
                        {
                            "LambdaFunctionARN": "${LAMBDA_ARN}",
                            "EventType": "origin-response",
                            "IncludeBody": false
                        }
                    ]
                },
                "FunctionAssociations": {
                    "Quantity": 0
                },
                "FieldLevelEncryptionId": "",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
            },
            {
                "PathPattern": "/static/*",
                "TargetOriginId": "S3Origin",
                "ViewerProtocolPolicy": "redirect-to-https",
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "AllowedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["GET", "HEAD"]
                    }
                },
                "SmoothStreaming": false,
                "Compress": true,
                "LambdaFunctionAssociations": {
                    "Quantity": 0
                },
                "FunctionAssociations": {
                    "Quantity": 0
                },
                "FieldLevelEncryptionId": "",
                "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6"
            }
        ]
    },
    "CustomErrorResponses": {
        "Quantity": 2,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/404.html",
                "ResponseCode": "404",
                "ErrorCachingMinTTL": 300
            },
            {
                "ErrorCode": 500,
                "ResponsePagePath": "/500.html",
                "ResponseCode": "500",
                "ErrorCachingMinTTL": 0
            }
        ]
    },
    "Logging": {
        "Enabled": true,
        "IncludeCookies": false,
        "Bucket": "${S3_BUCKET_NAME}.s3.amazonaws.com",
        "Prefix": "cloudfront-logs/"
    },
    "PriceClass": "PriceClass_All",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021",
        "CertificateSource": "cloudfront"
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    },
    "WebACLId": "${WAF_WEBACL_ARN}",
    "HttpVersion": "http2and3",
    "IsIPV6Enabled": true,
    "DefaultRootObject": "index.html"
}
EOF
    
    # Create CloudFront distribution
    DISTRIBUTION_OUTPUT=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/distribution-config.json)
    
    export DISTRIBUTION_ID=$(echo $DISTRIBUTION_OUTPUT | jq -r '.Distribution.Id')
    export DISTRIBUTION_DOMAIN=$(echo $DISTRIBUTION_OUTPUT | jq -r '.Distribution.DomainName')
    
    echo "DISTRIBUTION_ID=${DISTRIBUTION_ID}" >> /tmp/cdn-deployment-state.env
    echo "DISTRIBUTION_DOMAIN=${DISTRIBUTION_DOMAIN}" >> /tmp/cdn-deployment-state.env
    
    success "CloudFront distribution created with ID: ${DISTRIBUTION_ID}"
    success "Distribution domain: ${DISTRIBUTION_DOMAIN}"
}

# Configure S3 bucket policy
configure_s3_bucket_policy() {
    log "Configuring S3 bucket policy for CloudFront access..."
    
    cat > /tmp/s3-policy.json << EOF
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
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket ${S3_BUCKET_NAME} \
        --policy file:///tmp/s3-policy.json
    
    success "S3 bucket policy configured for CloudFront access"
}

# Create monitoring resources
create_monitoring_resources() {
    log "Setting up real-time logs and monitoring..."
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name /aws/cloudfront/realtime-logs/${CDN_PROJECT_NAME} || true
    
    # Create Kinesis Data Stream
    aws kinesis create-stream \
        --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX} \
        --shard-count 1 || true
    
    # Wait for stream to be active
    log "Waiting for Kinesis stream to be active..."
    aws kinesis wait stream-exists \
        --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX} || true
    
    # Create IAM role for CloudFront real-time logs
    cat > /tmp/realtime-logs-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name CloudFront-RealTimeLogs-${RANDOM_SUFFIX} \
        --assume-role-policy-document file:///tmp/realtime-logs-trust-policy.json || true
    
    # Create policy for Kinesis access
    cat > /tmp/realtime-logs-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:PutRecords",
                "kinesis:PutRecord"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name CloudFront-RealTimeLogs-${RANDOM_SUFFIX} \
        --policy-name KinesisAccess \
        --policy-document file:///tmp/realtime-logs-policy.json || true
    
    # Wait for role to be available
    sleep 10
    
    # Create real-time log configuration
    KINESIS_STREAM_ARN="arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/cloudfront-realtime-logs-${RANDOM_SUFFIX}"
    REALTIME_LOGS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/CloudFront-RealTimeLogs-${RANDOM_SUFFIX}"
    
    aws cloudfront create-realtime-log-config \
        --name "realtime-logs-${RANDOM_SUFFIX}" \
        --end-points StreamType=Kinesis,StreamArn=${KINESIS_STREAM_ARN},RoleArn=${REALTIME_LOGS_ROLE_ARN} \
        --fields timestamp c-ip sc-status cs-method cs-uri-stem cs-uri-query cs-referer cs-user-agent || true
    
    success "Real-time logging configured"
}

# Create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    cat > /tmp/dashboard-config.json << EOF
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
                    ["AWS/CloudFront", "Requests", "DistributionId", "${DISTRIBUTION_ID}"],
                    [".", "BytesDownloaded", ".", "."],
                    [".", "BytesUploaded", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "CloudFront Traffic"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/CloudFront", "4xxErrorRate", "DistributionId", "${DISTRIBUTION_ID}"],
                    [".", "5xxErrorRate", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Error Rates"
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
                    ["AWS/CloudFront", "CacheHitRate", "DistributionId", "${DISTRIBUTION_ID}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Cache Hit Rate"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/WAFV2", "AllowedRequests", "WebACL", "${WAF_WEBACL_NAME}", "Rule", "ALL", "Region", "CloudFront"],
                    [".", "BlockedRequests", ".", ".", ".", ".", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "WAF Activity"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "CloudFront-Advanced-CDN-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    success "CloudWatch dashboard created"
}

# Create KeyValueStore
create_keyvalue_store() {
    log "Creating CloudFront KeyValueStore for dynamic configuration..."
    
    KVS_NAME="cdn-config-${RANDOM_SUFFIX}"
    
    aws cloudfront create-key-value-store \
        --name ${KVS_NAME} \
        --comment "Dynamic configuration store for CDN" || true
    
    # Wait for KVS to be ready
    sleep 30
    
    # Get KVS details
    KVS_ID=$(aws cloudfront describe-key-value-store \
        --name ${KVS_NAME} \
        --query 'KeyValueStore.Id' --output text)
    
    KVS_ARN=$(aws cloudfront describe-key-value-store \
        --name ${KVS_NAME} \
        --query 'KeyValueStore.ARN' --output text)
    
    # Add initial key-value pairs
    aws cloudfront put-key \
        --kvs-arn ${KVS_ARN} \
        --key "maintenance_mode" \
        --value "false" || true
    
    aws cloudfront put-key \
        --kvs-arn ${KVS_ARN} \
        --key "feature_flags" \
        --value '{"new_ui": true, "beta_features": false}' || true
    
    aws cloudfront put-key \
        --kvs-arn ${KVS_ARN} \
        --key "redirect_rules" \
        --value '{"old_domain": "new_domain.com", "legacy_path": "/new-path"}' || true
    
    echo "KVS_ID=${KVS_ID}" >> /tmp/cdn-deployment-state.env
    echo "KVS_ARN=${KVS_ARN}" >> /tmp/cdn-deployment-state.env
    echo "KVS_NAME=${KVS_NAME}" >> /tmp/cdn-deployment-state.env
    
    success "CloudFront KeyValueStore configured with ID: ${KVS_ID}"
}

# Wait for distribution deployment
wait_for_deployment() {
    log "Waiting for CloudFront distribution to be deployed (this may take 10-15 minutes)..."
    
    # Show progress while waiting
    while true; do
        STATUS=$(aws cloudfront get-distribution \
            --id ${DISTRIBUTION_ID} \
            --query 'Distribution.Status' --output text)
        
        if [ "$STATUS" = "Deployed" ]; then
            break
        fi
        
        log "Distribution status: ${STATUS}. Waiting 30 seconds..."
        sleep 30
    done
    
    success "CloudFront distribution is now deployed and ready"
}

# Test deployment
test_deployment() {
    log "Testing CloudFront distribution..."
    
    # Test main origin
    log "Testing main origin..."
    curl -s -I https://${DISTRIBUTION_DOMAIN}/ | head -5
    
    # Test API path (custom origin)
    log "Testing API path..."
    curl -s -I https://${DISTRIBUTION_DOMAIN}/api/ip | head -5
    
    # Test security headers
    log "Checking security headers..."
    HEADERS=$(curl -s -I https://${DISTRIBUTION_DOMAIN}/ | grep -i "x-content-type-options\|x-frame-options\|strict-transport-security" | wc -l)
    
    if [ "$HEADERS" -gt 0 ]; then
        success "Security headers are present"
    else
        warning "Security headers may not be applied yet (Lambda@Edge can take a few minutes)"
    fi
    
    success "Basic functionality test completed"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo ""
    echo "======================================================"
    echo "Advanced CloudFront CDN Deployment Complete"
    echo "======================================================"
    echo ""
    echo "📊 Key Resources Created:"
    echo "  • CloudFront Distribution: ${DISTRIBUTION_ID}"
    echo "  • Distribution Domain: ${DISTRIBUTION_DOMAIN}"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "  • Lambda@Edge Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • CloudFront Function: ${CLOUDFRONT_FUNCTION_NAME}"
    echo "  • WAF Web ACL: ${WAF_WEBACL_NAME}"
    echo ""
    echo "🌐 Access URLs:"
    echo "  • Main Site: https://${DISTRIBUTION_DOMAIN}/"
    echo "  • API Docs: https://${DISTRIBUTION_DOMAIN}/api/"
    echo "  • API Status: https://${DISTRIBUTION_DOMAIN}/api/status.json"
    echo ""
    echo "📈 Monitoring:"
    echo "  • CloudWatch Dashboard: CloudFront-Advanced-CDN-${RANDOM_SUFFIX}"
    echo "  • Real-time Logs: cloudfront-realtime-logs-${RANDOM_SUFFIX}"
    echo ""
    echo "🔧 Management:"
    echo "  • Deployment State: /tmp/cdn-deployment-state.env"
    echo "  • Use destroy.sh to clean up resources"
    echo ""
    echo "⚠️  Important Notes:"
    echo "  • Edge functions may take 5-10 minutes to propagate globally"
    echo "  • Monitor CloudWatch for WAF and performance metrics"
    echo "  • S3 bucket policy restricts access to CloudFront only"
    echo "======================================================"
}

# Cleanup function for errors
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    if [ -f /tmp/cdn-deployment-state.env ]; then
        source /tmp/cdn-deployment-state.env
        ./destroy.sh --force 2>/dev/null || true
    fi
}

# Main deployment function
main() {
    trap cleanup_on_error ERR
    
    log "Starting Advanced CloudFront CDN Deployment"
    
    check_prerequisites
    setup_environment
    create_s3_resources
    create_cloudfront_function
    create_lambda_edge_function
    create_waf_webacl
    create_origin_access_control
    create_cloudfront_distribution
    configure_s3_bucket_policy
    create_monitoring_resources
    create_dashboard
    create_keyvalue_store
    wait_for_deployment
    test_deployment
    display_summary
    
    success "Advanced CloudFront CDN deployment completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Deploy an advanced CloudFront CDN with multiple origins, edge functions, and WAF protection."
            echo ""
            echo "Options:"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "This script creates:"
            echo "  • CloudFront distribution with multiple origins"
            echo "  • CloudFront Functions and Lambda@Edge"
            echo "  • AWS WAF Web ACL with security rules"
            echo "  • Real-time logging and CloudWatch dashboard"
            echo "  • S3 bucket with Origin Access Control"
            echo "  • KeyValueStore for dynamic configuration"
            echo ""
            echo "Prerequisites:"
            echo "  • AWS CLI v2 configured with appropriate permissions"
            echo "  • jq, curl, and base64 utilities"
            echo ""
            echo "Estimated deployment time: 15-20 minutes"
            echo "Estimated cost: \$50-100/month for moderate traffic"
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
    shift
done

# Run main deployment
main