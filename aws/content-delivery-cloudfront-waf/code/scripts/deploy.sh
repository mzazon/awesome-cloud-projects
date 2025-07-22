#!/bin/bash

# Deploy script for Secure Content Delivery with CloudFront WAF
# This script automates the deployment of a secure content delivery solution

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version (require v2)
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! $AWS_VERSION =~ ^2\. ]]; then
        error "AWS CLI version 2 is required. Current version: $AWS_VERSION"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
        exit 1
    fi
    
    # Check required permissions (basic check)
    log "Validating AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws iam get-role --role-name "$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)" &> /dev/null; then
        warning "Cannot verify IAM permissions. Ensure you have necessary permissions for CloudFront, WAF, S3, and CloudWatch."
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region (default to us-east-1 for CloudFront/WAF global resources)
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_REGION=${AWS_REGION:-"us-east-1"}
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export BUCKET_NAME="secure-content-${RANDOM_SUFFIX}"
    export DISTRIBUTION_NAME="secure-distribution-${RANDOM_SUFFIX}"
    export WAF_WEB_ACL_NAME="secure-web-acl-${RANDOM_SUFFIX}"
    
    # Create working directory for temporary files
    export WORK_DIR="$(pwd)/cloudfront-waf-deploy"
    mkdir -p "$WORK_DIR"
    
    log "Environment variables configured:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  BUCKET_NAME: $BUCKET_NAME"
    log "  WAF_WEB_ACL_NAME: $WAF_WEB_ACL_NAME"
    log "  WORK_DIR: $WORK_DIR"
    
    # Save environment to file for cleanup script
    cat > "$WORK_DIR/environment.sh" << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BUCKET_NAME="$BUCKET_NAME"
export DISTRIBUTION_NAME="$DISTRIBUTION_NAME"
export WAF_WEB_ACL_NAME="$WAF_WEB_ACL_NAME"
export WORK_DIR="$WORK_DIR"
EOF
    
    success "Environment setup completed"
}

# Function to create S3 bucket and sample content
create_s3_bucket() {
    log "Creating S3 bucket and sample content..."
    
    # Create S3 bucket
    if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
        warning "Bucket $BUCKET_NAME already exists"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
        success "S3 bucket created: $BUCKET_NAME"
    fi
    
    # Create sample content
    cat > "$WORK_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Secure Content Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
        .status { background: #d4edda; border: 1px solid #c3e6cb; color: #155724; padding: 12px; border-radius: 4px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Secure Content Delivery Test</h1>
        <div class="status">
            ✅ This content is successfully protected by AWS WAF and delivered through CloudFront.
        </div>
        <p>This page demonstrates a secure content delivery system with the following protections:</p>
        <ul>
            <li><strong>AWS WAF Protection:</strong> Blocks malicious requests and bot traffic</li>
            <li><strong>Rate Limiting:</strong> Prevents DDoS attacks</li>
            <li><strong>Geographic Restrictions:</strong> Controls access by country</li>
            <li><strong>HTTPS Enforcement:</strong> Encrypts all data in transit</li>
            <li><strong>Origin Access Control:</strong> Prevents direct S3 access</li>
        </ul>
        <p><small>Generated on: $(date)</small></p>
    </div>
</body>
</html>
EOF
    
    # Upload sample content to S3
    aws s3 cp "$WORK_DIR/index.html" "s3://$BUCKET_NAME/index.html"
    success "Sample content uploaded to S3"
}

# Function to create WAF Web ACL
create_waf_web_acl() {
    log "Creating AWS WAF Web ACL with security rules..."
    
    # Create managed rules configuration
    cat > "$WORK_DIR/waf-managed-rules.json" << 'EOF'
[
  {
    "Name": "AWS-AWSManagedRulesCommonRuleSet",
    "Priority": 1,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesCommonRuleSet"
      }
    },
    "OverrideAction": {
      "None": {}
    },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "CommonRuleSetMetric"
    }
  },
  {
    "Name": "AWS-AWSManagedRulesKnownBadInputsRuleSet",
    "Priority": 2,
    "Statement": {
      "ManagedRuleGroupStatement": {
        "VendorName": "AWS",
        "Name": "AWSManagedRulesKnownBadInputsRuleSet"
      }
    },
    "OverrideAction": {
      "None": {}
    },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "KnownBadInputsMetric"
    }
  },
  {
    "Name": "RateLimitRule",
    "Priority": 3,
    "Statement": {
      "RateBasedStatement": {
        "Limit": 2000,
        "AggregateKeyType": "IP"
      }
    },
    "Action": {
      "Block": {}
    },
    "VisibilityConfig": {
      "SampledRequestsEnabled": true,
      "CloudWatchMetricsEnabled": true,
      "MetricName": "RateLimitMetric"
    }
  }
]
EOF
    
    # Create WAF Web ACL
    log "Creating WAF Web ACL..."
    aws wafv2 create-web-acl \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --name "$WAF_WEB_ACL_NAME" \
        --description "Web ACL for CloudFront security protection - $BUCKET_NAME" \
        --default-action Allow={} \
        --rules file://"$WORK_DIR/waf-managed-rules.json" > "$WORK_DIR/waf-output.json"
    
    # Get Web ACL ARN for CloudFront association
    export WAF_WEB_ACL_ARN=$(aws wafv2 list-web-acls \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME'].ARN" \
        --output text)
    
    echo "export WAF_WEB_ACL_ARN=\"$WAF_WEB_ACL_ARN\"" >> "$WORK_DIR/environment.sh"
    
    success "WAF Web ACL created with ARN: $WAF_WEB_ACL_ARN"
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution with Origin Access Control..."
    
    # Create Origin Access Control for S3
    log "Creating Origin Access Control..."
    aws cloudfront create-origin-access-control \
        --origin-access-control-config \
        Name="OAC-$BUCKET_NAME",Description="Origin Access Control for $BUCKET_NAME",SigningBehavior="always",SigningProtocol="sigv4",OriginAccessControlOriginType="s3" \
        --query "OriginAccessControl.Id" --output text > "$WORK_DIR/oac-id.txt"
    
    export OAC_ID=$(cat "$WORK_DIR/oac-id.txt")
    echo "export OAC_ID=\"$OAC_ID\"" >> "$WORK_DIR/environment.sh"
    
    # Create CloudFront distribution configuration
    cat > "$WORK_DIR/cloudfront-config.json" << EOF
{
  "CallerReference": "secure-distribution-$(date +%s)",
  "Comment": "Secure CloudFront distribution with WAF protection - $BUCKET_NAME",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "$BUCKET_NAME",
        "DomainName": "$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com",
        "OriginPath": "",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        },
        "OriginAccessControlId": "$OAC_ID"
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "$BUCKET_NAME",
    "ViewerProtocolPolicy": "redirect-to-https",
    "MinTTL": 0,
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {
        "Forward": "none"
      }
    },
    "TrustedSigners": {
      "Enabled": false,
      "Quantity": 0
    }
  },
  "Enabled": true,
  "WebACLId": "$WAF_WEB_ACL_ARN",
  "PriceClass": "PriceClass_100",
  "Restrictions": {
    "GeoRestriction": {
      "RestrictionType": "blacklist",
      "Quantity": 2,
      "Items": ["RU", "CN"]
    }
  }
}
EOF
    
    # Create CloudFront distribution
    log "Creating CloudFront distribution (this may take several minutes)..."
    aws cloudfront create-distribution \
        --distribution-config file://"$WORK_DIR/cloudfront-config.json" \
        --query "Distribution.Id" --output text > "$WORK_DIR/distribution-id.txt"
    
    export DISTRIBUTION_ID=$(cat "$WORK_DIR/distribution-id.txt")
    echo "export DISTRIBUTION_ID=\"$DISTRIBUTION_ID\"" >> "$WORK_DIR/environment.sh"
    
    success "CloudFront distribution created with ID: $DISTRIBUTION_ID"
}

# Function to configure S3 bucket policy
configure_s3_policy() {
    log "Configuring S3 bucket policy for CloudFront access..."
    
    # Wait a moment for distribution to be created
    sleep 30
    
    # Create S3 bucket policy for CloudFront OAC
    cat > "$WORK_DIR/bucket-policy.json" << EOF
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
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::$AWS_ACCOUNT_ID:distribution/$DISTRIBUTION_ID"
        }
      }
    }
  ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file://"$WORK_DIR/bucket-policy.json"
    
    success "S3 bucket policy configured for CloudFront access"
}

# Function to wait for distribution deployment
wait_for_distribution() {
    log "Waiting for CloudFront distribution deployment (this can take 15-20 minutes)..."
    
    # Get domain name for immediate reference
    export DOMAIN_NAME=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query "Distribution.DomainName" --output text)
    
    echo "export DOMAIN_NAME=\"$DOMAIN_NAME\"" >> "$WORK_DIR/environment.sh"
    
    log "Distribution domain: $DOMAIN_NAME"
    log "You can check deployment status at: https://console.aws.amazon.com/cloudfront/home#distribution-settings:$DISTRIBUTION_ID"
    
    # Wait for deployment (with timeout)
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=60   # Check every minute
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(aws cloudfront get-distribution \
            --id "$DISTRIBUTION_ID" \
            --query "Distribution.Status" --output text)
        
        if [ "$status" = "Deployed" ]; then
            success "CloudFront distribution is now deployed and ready!"
            return 0
        fi
        
        log "Distribution status: $status (waited ${elapsed}s/${timeout}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    warning "Distribution deployment is taking longer than expected. Check AWS console for status."
    warning "You can continue to use the distribution URL: https://$DOMAIN_NAME"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Source environment variables
    source "$WORK_DIR/environment.sh"
    
    # Test 1: Verify WAF Web ACL
    log "Validating WAF Web ACL configuration..."
    local waf_rules=$(aws wafv2 get-web-acl \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
            --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME'].Id" --output text) \
        --query "WebACL.Rules[].Name" --output text)
    
    if [[ $waf_rules == *"AWS-AWSManagedRulesCommonRuleSet"* ]]; then
        success "WAF managed rules configured correctly"
    else
        warning "WAF managed rules may not be configured properly"
    fi
    
    # Test 2: Verify CloudFront distribution
    log "Validating CloudFront distribution..."
    local distribution_status=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query "Distribution.Status" --output text)
    
    log "Distribution status: $distribution_status"
    
    # Test 3: Test HTTPS access (if deployed)
    if [ "$distribution_status" = "Deployed" ]; then
        log "Testing HTTPS access..."
        if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME/index.html" | grep -q "200"; then
            success "HTTPS access test passed"
        else
            warning "HTTPS access test failed - distribution may still be propagating"
        fi
        
        # Test 4: Test HTTP redirect
        log "Testing HTTP to HTTPS redirect..."
        local redirect_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_NAME/index.html")
        if [ "$redirect_code" = "301" ] || [ "$redirect_code" = "302" ]; then
            success "HTTP to HTTPS redirect working correctly"
        else
            warning "HTTP redirect test returned code: $redirect_code"
        fi
    else
        warning "Skipping access tests - distribution still deploying"
    fi
    
    # Test 5: Verify S3 direct access is blocked
    log "Verifying S3 direct access is blocked..."
    local s3_direct_code=$(curl -s -o /dev/null -w "%{http_code}" "https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/index.html")
    if [ "$s3_direct_code" = "403" ]; then
        success "S3 direct access properly blocked"
    else
        warning "S3 direct access returned code: $s3_direct_code (expected 403)"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo ""
    echo "✅ Resources Created:"
    echo "   - S3 Bucket: $BUCKET_NAME"
    echo "   - WAF Web ACL: $WAF_WEB_ACL_NAME"
    echo "   - CloudFront Distribution: $DISTRIBUTION_ID"
    echo "   - Origin Access Control: $OAC_ID"
    echo ""
    echo "🌐 Access URLs:"
    echo "   - CloudFront URL: https://$DOMAIN_NAME"
    echo "   - Test Page: https://$DOMAIN_NAME/index.html"
    echo ""
    echo "🔧 Management URLs:"
    echo "   - CloudFront Console: https://console.aws.amazon.com/cloudfront/home#distribution-settings:$DISTRIBUTION_ID"
    echo "   - WAF Console: https://console.aws.amazon.com/wafv2/homev2/web-acl/secure-web-acl-*/overview?region=us-east-1"
    echo "   - S3 Console: https://console.aws.amazon.com/s3/buckets/$BUCKET_NAME"
    echo ""
    echo "🛡️ Security Features Enabled:"
    echo "   - AWS WAF with managed rules (OWASP Top 10, Known Bad Inputs)"
    echo "   - Rate limiting (2000 requests per 5 minutes per IP)"
    echo "   - Geographic restrictions (blocking RU, CN)"
    echo "   - HTTPS enforcement"
    echo "   - Origin Access Control (prevents direct S3 access)"
    echo ""
    echo "💰 Estimated Monthly Cost:"
    echo "   - CloudFront: ~$0.50-2.00 (depends on traffic)"
    echo "   - WAF: ~$1.00 (base) + $0.60 per million requests"
    echo "   - S3: ~$0.023 per GB stored"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Test the CloudFront URL: https://$DOMAIN_NAME/index.html"
    echo "   2. Monitor WAF metrics in CloudWatch"
    echo "   3. Customize WAF rules as needed"
    echo "   4. Add your own content to the S3 bucket"
    echo ""
    echo "🧹 Cleanup:"
    echo "   Run './destroy.sh' to remove all resources and avoid charges"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    echo "=============================================="
    echo "🚀 AWS CloudFront + WAF Deployment Script"
    echo "=============================================="
    echo ""
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_waf_web_acl
    create_cloudfront_distribution
    configure_s3_policy
    wait_for_distribution
    run_validation
    display_summary
    
    echo ""
    echo "Environment variables saved to: $WORK_DIR/environment.sh"
    echo "This file is needed for the cleanup script."
}

# Trap errors and cleanup
trap 'error "Deployment failed. Check the error messages above."; exit 1' ERR

# Run main function
main "$@"