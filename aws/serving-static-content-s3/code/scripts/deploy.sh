#!/bin/bash

# Deploy script for Static Website with S3 and CloudFront
# This script automates the deployment of a static website using Amazon S3 and CloudFront
# as described in the "Serving Static Content with S3 and CloudFront" recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO:${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Check $LOG_FILE for details."
    if [[ -f "$CONFIG_FILE" ]]; then
        warn "Partial deployment detected. Run destroy.sh to clean up resources."
    fi
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $aws_version"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed (needed for JSON parsing)
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Get AWS account info
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured. Run 'aws configure' to set a default region."
        exit 1
    fi
    
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "AWS Region: $AWS_REGION"
    
    success "Prerequisites check completed successfully"
}

# Function to generate unique resource names
generate_resource_names() {
    info "Generating unique resource names..."
    
    # Generate a random suffix for bucket name to ensure uniqueness
    RANDOM_STRING=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s)$(shuf -i 100-999 -n 1)")
    
    # Define resource names
    export BUCKET_NAME="website-${RANDOM_STRING}"
    export LOGS_BUCKET_NAME="${BUCKET_NAME}-logs"
    
    info "Website bucket: $BUCKET_NAME"
    info "Logs bucket: $LOGS_BUCKET_NAME"
}

# Function to handle domain configuration
configure_domain() {
    # Ask if user wants to configure a custom domain
    echo
    read -p "Do you want to set up a custom domain? (y/n): " SETUP_DOMAIN
    
    if [[ "$SETUP_DOMAIN" == "y" || "$SETUP_DOMAIN" == "Y" ]]; then
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
        export DOMAIN_NAME
        export SETUP_DOMAIN="y"
        
        info "Checking if domain is registered in Route 53..."
        
        # Check if domain is registered in Route 53
        HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
            --dns-name "$DOMAIN_NAME." \
            --query "HostedZones[0].Id" \
            --output text 2>/dev/null || echo "None")
            
        if [[ "$HOSTED_ZONE_ID" == "None" || "$HOSTED_ZONE_ID" == "null" ]]; then
            warn "Domain not found in Route 53. You will need to:"
            warn "1. Register your domain in Route 53 or transfer it"
            warn "2. Or update your DNS provider with CloudFront details later"
            export HOSTED_ZONE_ID="None"
        else
            # Clean up the hosted zone ID (remove /hostedzone/ prefix)
            HOSTED_ZONE_ID=$(echo "$HOSTED_ZONE_ID" | sed 's|/hostedzone/||')
            success "Domain found in Route 53: $HOSTED_ZONE_ID"
            export HOSTED_ZONE_ID
        fi
    else
        export SETUP_DOMAIN="n"
        info "Proceeding without custom domain setup"
    fi
}

# Function to create sample website if needed
create_sample_website() {
    local website_dir="${SCRIPT_DIR}/../website"
    
    if [[ ! -d "$website_dir" ]]; then
        info "Creating sample website files..."
        mkdir -p "$website_dir"
        
        # Create index.html
        cat > "$website_dir/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS S3 Static Website</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>Hello from Amazon S3 and CloudFront!</h1>
        <p>This static website is served from Amazon S3 and delivered via CloudFront.</p>
        <p>The current time is: <span id="current-time"></span></p>
    </div>
    <script src="script.js"></script>
</body>
</html>
EOF
        
        # Create styles.css
        cat > "$website_dir/styles.css" << 'EOF'
body {
    font-family: Arial, sans-serif;
    line-height: 1.6;
    margin: 0;
    padding: 0;
    background-color: #f4f4f4;
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100vh;
}

.container {
    max-width: 800px;
    margin: 0 auto;
    padding: 30px;
    background-color: white;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
    text-align: center;
}

h1 {
    color: #ff9900;
}
EOF
        
        # Create script.js
        cat > "$website_dir/script.js" << 'EOF'
document.addEventListener('DOMContentLoaded', function() {
    function updateTime() {
        const now = new Date();
        document.getElementById('current-time').textContent = now.toLocaleTimeString();
    }
    
    updateTime();
    setInterval(updateTime, 1000);
});
EOF
        
        # Create error.html
        cat > "$website_dir/error.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Error - Page Not Found</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>404 - Page Not Found</h1>
        <p>The page you're looking for doesn't exist.</p>
        <p><a href="/">Return to homepage</a></p>
    </div>
</body>
</html>
EOF

        success "Sample website created in $website_dir"
    else
        info "Using existing website files in $website_dir"
    fi
    
    export WEBSITE_DIR="$website_dir"
}

# Function to create S3 buckets
create_s3_buckets() {
    info "Creating S3 buckets..."
    
    # Create main website bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Create bucket for access logs
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket "$LOGS_BUCKET_NAME" \
            --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$LOGS_BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Block public access for logs bucket
    aws s3api put-public-access-block \
        --bucket "$LOGS_BUCKET_NAME" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    # Enable static website hosting on the main bucket
    aws s3 website \
        "$BUCKET_NAME" \
        --index-document index.html \
        --error-document error.html
    
    success "Created S3 buckets successfully"
}

# Function to upload website content
upload_website_content() {
    info "Uploading website content with proper MIME types..."
    
    # Upload all files first (general upload)
    aws s3 sync "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" \
        --include "*" \
        --exclude "*.html" \
        --exclude "*.css" \
        --exclude "*.js" \
        --exclude "*.json" \
        --exclude "*.xml" \
        --exclude "*.svg" \
        --exclude "*.jpg" \
        --exclude "*.jpeg" \
        --exclude "*.png" \
        --exclude "*.gif"
    
    # Upload HTML files with correct content-type
    aws s3 sync "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" \
        --exclude "*" \
        --include "*.html" \
        --content-type "text/html"
    
    # Upload CSS files with correct content-type
    aws s3 sync "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" \
        --exclude "*" \
        --include "*.css" \
        --content-type "text/css"
    
    # Upload JavaScript files with correct content-type
    aws s3 sync "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" \
        --exclude "*" \
        --include "*.js" \
        --content-type "application/javascript"
    
    # Upload image files with correct content-types (if any exist)
    if find "$WEBSITE_DIR" -name "*.jpg" -o -name "*.jpeg" | grep -q .; then
        aws s3 sync "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" \
            --exclude "*" \
            --include "*.jpg" --include "*.jpeg" \
            --content-type "image/jpeg"
    fi
    
    if find "$WEBSITE_DIR" -name "*.png" | grep -q .; then
        aws s3 sync "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" \
            --exclude "*" \
            --include "*.png" \
            --content-type "image/png"
    fi
    
    if find "$WEBSITE_DIR" -name "*.gif" | grep -q .; then
        aws s3 sync "$WEBSITE_DIR/" "s3://$BUCKET_NAME/" \
            --exclude "*" \
            --include "*.gif" \
            --content-type "image/gif"
    fi
    
    success "Uploaded website content to S3 bucket"
}

# Function to create Origin Access Control
create_origin_access_control() {
    info "Creating Origin Access Control..."
    
    OAC_ID=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config '{
            "Name": "S3OriginAccessControl-'"$BUCKET_NAME"'",
            "Description": "OAC for S3 static website",
            "SigningProtocol": "sigv4",
            "SigningBehavior": "always",
            "OriginAccessControlOriginType": "s3"
        }' \
        --query 'OriginAccessControl.Id' \
        --output text)
    
    export OAC_ID
    success "Created Origin Access Control: $OAC_ID"
}

# Function to set up SSL certificate
setup_ssl_certificate() {
    if [[ "$SETUP_DOMAIN" == "y" ]]; then
        info "Requesting SSL certificate for $DOMAIN_NAME..."
        
        # Request a certificate in us-east-1 (required for CloudFront)
        CERT_ARN=$(aws acm request-certificate \
            --domain-name "$DOMAIN_NAME" \
            --validation-method DNS \
            --region us-east-1 \
            --query 'CertificateArn' \
            --output text)
        
        export CERT_ARN
        success "Requested SSL certificate: $CERT_ARN"
        
        # Wait a moment for certificate details to be available
        sleep 5
        
        # Get validation record details
        VALIDATION_RECORD=$(aws acm describe-certificate \
            --certificate-arn "$CERT_ARN" \
            --region us-east-1 \
            --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
            --output json)
        
        VALIDATION_NAME=$(echo "$VALIDATION_RECORD" | jq -r '.Name')
        VALIDATION_VALUE=$(echo "$VALIDATION_RECORD" | jq -r '.Value')
        
        export VALIDATION_NAME VALIDATION_VALUE
        
        info "Certificate validation record:"
        info "Name: $VALIDATION_NAME"
        info "Value: $VALIDATION_VALUE"
        
        # Add validation record to Route 53 if hosted zone exists
        if [[ "$HOSTED_ZONE_ID" != "None" && "$HOSTED_ZONE_ID" != "null" ]]; then
            info "Adding validation record to Route 53..."
            
            CHANGE_ID=$(aws route53 change-resource-record-sets \
                --hosted-zone-id "$HOSTED_ZONE_ID" \
                --change-batch '{
                    "Changes": [{
                        "Action": "UPSERT",
                        "ResourceRecordSet": {
                            "Name": "'"$VALIDATION_NAME"'",
                            "Type": "CNAME",
                            "TTL": 300,
                            "ResourceRecords": [{"Value": "'"$VALIDATION_VALUE"'"}]
                        }
                    }]
                }' \
                --query 'ChangeInfo.Id' \
                --output text)
            
            success "Added validation record to Route 53"
            info "Waiting for certificate validation (this may take several minutes)..."
            
            # Wait for certificate validation with timeout
            if timeout 1200 aws acm wait certificate-validated \
                --certificate-arn "$CERT_ARN" \
                --region us-east-1; then
                success "Certificate validated successfully"
            else
                error "Certificate validation timed out. Please check DNS configuration."
                exit 1
            fi
        else
            warn "Please add this CNAME record to your DNS provider to validate the certificate:"
            warn "Name: $VALIDATION_NAME"
            warn "Value: $VALIDATION_VALUE"
            echo
            read -p "Press Enter once the certificate is validated... "
        fi
    fi
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    info "Creating CloudFront distribution..."
    
    # Create temporary file for distribution config
    local dist_config_file="${SCRIPT_DIR}/distribution-config.json"
    
    # Generate distribution configuration based on domain setup
    if [[ "$SETUP_DOMAIN" == "y" ]]; then
        cat > "$dist_config_file" << EOF
{
    "CallerReference": "${RANDOM_STRING}",
    "Comment": "Distribution for ${DOMAIN_NAME}",
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3Origin",
                "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "${OAC_ID}"
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "Compress": true
    },
    "Aliases": {
        "Quantity": 1,
        "Items": ["${DOMAIN_NAME}"]
    },
    "ViewerCertificate": {
        "ACMCertificateArn": "${CERT_ARN}",
        "SSLSupportMethod": "sni-only",
        "MinimumProtocolVersion": "TLSv1.2_2021"
    },
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/error.html",
                "ResponseCode": "404",
                "ErrorCachingMinTTL": 300
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
}
EOF
    else
        cat > "$dist_config_file" << EOF
{
    "CallerReference": "${RANDOM_STRING}",
    "Comment": "Distribution for S3 static website",
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3Origin",
                "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "${OAC_ID}"
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
        "Compress": true
    },
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/error.html",
                "ResponseCode": "404",
                "ErrorCachingMinTTL": 300
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
}
EOF
    fi
    
    # Create CloudFront distribution
    DISTRIBUTION_RESULT=$(aws cloudfront create-distribution \
        --distribution-config file://"$dist_config_file")
    
    DISTRIBUTION_ID=$(echo "$DISTRIBUTION_RESULT" | jq -r '.Distribution.Id')
    DISTRIBUTION_DOMAIN=$(echo "$DISTRIBUTION_RESULT" | jq -r '.Distribution.DomainName')
    
    export DISTRIBUTION_ID DISTRIBUTION_DOMAIN
    
    # Clean up temporary file
    rm -f "$dist_config_file"
    
    success "Created CloudFront distribution: $DISTRIBUTION_ID"
    info "CloudFront domain: $DISTRIBUTION_DOMAIN"
}

# Function to configure S3 bucket policy
configure_s3_bucket_policy() {
    info "Configuring S3 bucket policy for CloudFront access..."
    
    # Create bucket policy for CloudFront access
    local bucket_policy_file="${SCRIPT_DIR}/bucket-policy.json"
    
    cat > "$bucket_policy_file" << EOF
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
        --policy file://"$bucket_policy_file"
    
    # Clean up temporary file
    rm -f "$bucket_policy_file"
    
    success "Applied bucket policy for CloudFront access"
}

# Function to create Route 53 DNS record
create_route53_record() {
    if [[ "$SETUP_DOMAIN" == "y" && "$HOSTED_ZONE_ID" != "None" && "$HOSTED_ZONE_ID" != "null" ]]; then
        info "Waiting for CloudFront distribution to deploy..."
        
        # Wait for CloudFront distribution to deploy (with timeout)
        if timeout 1800 aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"; then
            success "CloudFront distribution deployed successfully"
        else
            warn "CloudFront distribution deployment timed out, but continuing..."
        fi
        
        info "Creating Route 53 record for $DOMAIN_NAME..."
        
        # Create Route 53 record pointing to CloudFront
        CHANGE_ID=$(aws route53 change-resource-record-sets \
            --hosted-zone-id "$HOSTED_ZONE_ID" \
            --change-batch '{
                "Changes": [{
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": "'"$DOMAIN_NAME"'",
                        "Type": "A",
                        "AliasTarget": {
                            "HostedZoneId": "Z2FDTNDATAQYW2",
                            "DNSName": "'"$DISTRIBUTION_DOMAIN"'",
                            "EvaluateTargetHealth": false
                        }
                    }
                }]
            }' \
            --query 'ChangeInfo.Id' \
            --output text)
        
        success "Created Route 53 record for $DOMAIN_NAME"
        info "Record change status: $CHANGE_ID"
    elif [[ "$SETUP_DOMAIN" == "y" ]]; then
        info "To use your custom domain with CloudFront:"
        info "1. Create an A record in your DNS provider"
        info "2. Point it to your CloudFront distribution: $DISTRIBUTION_DOMAIN"
    fi
}

# Function to save deployment configuration
save_deployment_config() {
    info "Saving deployment configuration..."
    
    cat > "$CONFIG_FILE" << EOF
# Deployment configuration
# Generated on $(date)
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BUCKET_NAME="$BUCKET_NAME"
export LOGS_BUCKET_NAME="$LOGS_BUCKET_NAME"
export OAC_ID="$OAC_ID"
export DISTRIBUTION_ID="$DISTRIBUTION_ID"
export DISTRIBUTION_DOMAIN="$DISTRIBUTION_DOMAIN"
export SETUP_DOMAIN="$SETUP_DOMAIN"
EOF

    if [[ "$SETUP_DOMAIN" == "y" ]]; then
        cat >> "$CONFIG_FILE" << EOF
export DOMAIN_NAME="$DOMAIN_NAME"
export HOSTED_ZONE_ID="$HOSTED_ZONE_ID"
export CERT_ARN="$CERT_ARN"
export VALIDATION_NAME="$VALIDATION_NAME"
export VALIDATION_VALUE="$VALIDATION_VALUE"
EOF
    fi
    
    success "Deployment configuration saved to $CONFIG_FILE"
}

# Function to run validation tests
run_validation_tests() {
    info "Running validation tests..."
    
    # Test 1: Verify CloudFront distribution status
    info "Testing CloudFront distribution status..."
    local dist_status=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'Distribution.Status' \
        --output text)
    
    if [[ "$dist_status" == "Deployed" ]]; then
        success "CloudFront distribution is deployed"
    else
        warn "CloudFront distribution status: $dist_status (may still be deploying)"
    fi
    
    # Test 2: Test website access via CloudFront
    info "Testing website access via CloudFront..."
    local cloudfront_url="https://$DISTRIBUTION_DOMAIN"
    
    if curl -s -f "$cloudfront_url/index.html" > /dev/null; then
        success "Website accessible via CloudFront: $cloudfront_url"
    else
        warn "Website may not be accessible yet. CloudFront deployment may still be in progress."
    fi
    
    # Test 3: Test custom domain (if configured)
    if [[ "$SETUP_DOMAIN" == "y" ]]; then
        info "Testing custom domain access..."
        local domain_url="https://$DOMAIN_NAME"
        
        if curl -s -f "$domain_url/index.html" > /dev/null; then
            success "Website accessible via custom domain: $domain_url"
        else
            warn "Custom domain may not be accessible yet. DNS propagation may take time."
        fi
    fi
}

# Function to display deployment summary
display_deployment_summary() {
    echo
    echo "======================================"
    success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "======================================"
    echo
    info "Resource Summary:"
    info "- S3 Website Bucket: $BUCKET_NAME"
    info "- S3 Logs Bucket: $LOGS_BUCKET_NAME"
    info "- CloudFront Distribution: $DISTRIBUTION_ID"
    info "- CloudFront Domain: $DISTRIBUTION_DOMAIN"
    
    if [[ "$SETUP_DOMAIN" == "y" ]]; then
        info "- Custom Domain: $DOMAIN_NAME"
        if [[ "$HOSTED_ZONE_ID" != "None" && "$HOSTED_ZONE_ID" != "null" ]]; then
            info "- Route 53 Hosted Zone: $HOSTED_ZONE_ID"
        fi
        info "- SSL Certificate: $CERT_ARN"
    fi
    
    echo
    info "Access your website at:"
    info "- CloudFront URL: https://$DISTRIBUTION_DOMAIN"
    
    if [[ "$SETUP_DOMAIN" == "y" ]]; then
        info "- Custom Domain: https://$DOMAIN_NAME"
        if [[ "$HOSTED_ZONE_ID" == "None" || "$HOSTED_ZONE_ID" == "null" ]]; then
            warn "Note: Configure your DNS provider to point to $DISTRIBUTION_DOMAIN"
        fi
    fi
    
    echo
    info "Important Notes:"
    info "- CloudFront deployment can take 5-15 minutes to fully propagate"
    info "- DNS changes may take up to 48 hours to propagate globally"
    info "- Configuration saved to: $CONFIG_FILE"
    info "- Deployment logs saved to: $LOG_FILE"
    
    if [[ "$SETUP_DOMAIN" == "y" && ("$HOSTED_ZONE_ID" == "None" || "$HOSTED_ZONE_ID" == "null") ]]; then
        echo
        warn "Manual DNS Configuration Required:"
        warn "Add the following record to your DNS provider:"
        warn "Type: A (Alias)"
        warn "Name: $DOMAIN_NAME"
        warn "Value: $DISTRIBUTION_DOMAIN"
    fi
    
    echo
    info "To clean up all resources, run: ./destroy.sh"
    echo "======================================"
}

# Main deployment function
main() {
    echo "======================================"
    echo "AWS S3 + CloudFront Website Deployment"
    echo "======================================"
    echo
    
    log "Starting deployment at $(date)"
    
    # Run deployment steps
    check_prerequisites
    generate_resource_names
    configure_domain
    create_sample_website
    create_s3_buckets
    upload_website_content
    create_origin_access_control
    setup_ssl_certificate
    create_cloudfront_distribution
    configure_s3_bucket_policy
    create_route53_record
    save_deployment_config
    run_validation_tests
    display_deployment_summary
    
    log "Deployment completed successfully at $(date)"
}

# Run main function
main "$@"