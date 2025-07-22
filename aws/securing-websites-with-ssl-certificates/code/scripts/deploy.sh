#!/bin/bash

# Deploy script for Securing Websites with SSL Certificates
# This script deploys a complete secure static website using S3, CloudFront, and ACM

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" | tee -a "${LOG_FILE}"
}

# Cleanup function for safe exit
cleanup() {
    log "Cleaning up temporary files..."
    rm -f index.html error.html bucket-policy.json dns-records.json disabled-config.json
}

# Trap for cleanup on exit
trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing"
        exit 1
    fi
    
    # Check openssl for SSL verification
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl for SSL verification"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Validate domain configuration
validate_domain() {
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        log_error "DOMAIN_NAME environment variable is required"
        log "Please set DOMAIN_NAME to your domain (e.g., export DOMAIN_NAME=example.com)"
        exit 1
    fi
    
    # Validate domain format
    if [[ ! "${DOMAIN_NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: ${DOMAIN_NAME}"
        exit 1
    fi
    
    log_success "Domain validation passed: ${DOMAIN_NAME}"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # AWS configuration
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Domain configuration
    export SUBDOMAIN="www.${DOMAIN_NAME}"
    
    # Resource naming
    export BUCKET_NAME="static-website-${RANDOM_SUFFIX}"
    
    log_success "Environment configured"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "Domain: ${DOMAIN_NAME}"
    log "Subdomain: ${SUBDOMAIN}"
    log "Bucket Name: ${BUCKET_NAME}"
}

# Create S3 bucket for static website hosting
create_s3_bucket() {
    log "Creating S3 bucket for static website hosting..."
    
    # Create bucket
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Configure static website hosting
    aws s3api put-bucket-website \
        --bucket ${BUCKET_NAME} \
        --website-configuration \
        'IndexDocument={Suffix=index.html},ErrorDocument={Key=error.html}'
    
    log_success "S3 bucket created and configured: ${BUCKET_NAME}"
}

# Upload sample website content
upload_website_content() {
    log "Creating and uploading sample website content..."
    
    # Create index.html
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Secure Static Website</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 50px; 
            background-color: #f5f5f5;
            line-height: 1.6;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .secure { 
            color: #28a745; 
            font-weight: bold; 
        }
        .ssl-indicator {
            background: #28a745;
            color: white;
            padding: 10px;
            border-radius: 5px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Your <span class="secure">Secure</span> Website</h1>
        <div class="ssl-indicator">
            🔒 This website is served over HTTPS using AWS Certificate Manager
        </div>
        <p>This secure static website demonstrates:</p>
        <ul>
            <li>SSL/TLS certificate automatically managed by AWS ACM</li>
            <li>Global content delivery via Amazon CloudFront</li>
            <li>Secure S3 origin with Origin Access Control</li>
            <li>Custom domain with DNS validation</li>
        </ul>
        <p>Your connection is encrypted and secure!</p>
    </div>
</body>
</html>
EOF
    
    # Create error.html
    cat > error.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 50px; 
            background-color: #f5f5f5;
            line-height: 1.6;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        .error-code {
            font-size: 48px;
            color: #dc3545;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <h1>Page Not Found</h1>
        <p>The requested page could not be found on this secure website.</p>
        <p>Please check the URL and try again.</p>
    </div>
</body>
</html>
EOF
    
    # Upload files to S3
    aws s3 cp index.html s3://${BUCKET_NAME}/
    aws s3 cp error.html s3://${BUCKET_NAME}/
    
    log_success "Website content uploaded to S3"
}

# Request SSL certificate from ACM
request_ssl_certificate() {
    log "Requesting SSL certificate from AWS Certificate Manager..."
    
    # Request certificate (must be in us-east-1 for CloudFront)
    CERTIFICATE_ARN=$(aws acm request-certificate \
        --domain-name ${DOMAIN_NAME} \
        --subject-alternative-names ${SUBDOMAIN} \
        --validation-method DNS \
        --region us-east-1 \
        --query CertificateArn \
        --output text)
    
    echo "CERTIFICATE_ARN=${CERTIFICATE_ARN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "SSL certificate requested: ${CERTIFICATE_ARN}"
    
    # Display DNS validation records
    log "DNS validation records (add these to your domain's DNS):"
    aws acm describe-certificate \
        --certificate-arn ${CERTIFICATE_ARN} \
        --region us-east-1 \
        --query 'Certificate.DomainValidationOptions[*].[DomainName,ResourceRecord.Name,ResourceRecord.Value]' \
        --output table
    
    log "⚠️  IMPORTANT: Add the DNS validation records above to your domain's DNS before continuing"
    log "⚠️  The deployment will wait for certificate validation to complete"
}

# Create CloudFront Origin Access Control
create_origin_access_control() {
    log "Creating CloudFront Origin Access Control..."
    
    OAC_ID=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config \
        Name=OAC-${RANDOM_SUFFIX},\
        Description="Origin Access Control for ${BUCKET_NAME}",\
        OriginAccessControlOriginType=s3,\
        SigningBehavior=always,\
        SigningProtocol=sigv4 \
        --query 'OriginAccessControl.Id' \
        --output text)
    
    echo "OAC_ID=${OAC_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Origin Access Control created: ${OAC_ID}"
}

# Wait for certificate validation
wait_for_certificate_validation() {
    log "Waiting for SSL certificate validation..."
    log "This may take several minutes depending on DNS propagation..."
    
    # Wait with timeout (30 minutes max)
    timeout 1800 aws acm wait certificate-validated \
        --certificate-arn ${CERTIFICATE_ARN} \
        --region us-east-1 || {
        log_error "Certificate validation timed out after 30 minutes"
        log "Please ensure DNS validation records are correctly configured"
        exit 1
    }
    
    log_success "SSL certificate validated successfully"
}

# Create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution with SSL certificate..."
    
    # Create distribution configuration
    DISTRIBUTION_CONFIG=$(cat << EOF
{
    "CallerReference": "static-website-${RANDOM_SUFFIX}",
    "DefaultRootObject": "index.html",
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-${BUCKET_NAME}",
                "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
                "OriginAccessControlId": "${OAC_ID}",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-${BUCKET_NAME}",
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
    "Comment": "CloudFront distribution for ${DOMAIN_NAME}",
    "Enabled": true,
    "ViewerCertificate": {
        "ACMCertificateArn": "${CERTIFICATE_ARN}",
        "SSLSupportMethod": "sni-only",
        "MinimumProtocolVersion": "TLSv1.2_2021"
    },
    "Aliases": {
        "Quantity": 2,
        "Items": ["${DOMAIN_NAME}", "${SUBDOMAIN}"]
    }
}
EOF
    )
    
    DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config "${DISTRIBUTION_CONFIG}" \
        --query 'Distribution.Id' \
        --output text)
    
    echo "DISTRIBUTION_ID=${DISTRIBUTION_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "CloudFront distribution created: ${DISTRIBUTION_ID}"
}

# Update S3 bucket policy for CloudFront access
update_bucket_policy() {
    log "Updating S3 bucket policy for CloudFront access..."
    
    # Create bucket policy
    cat > bucket-policy.json << EOF
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
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket ${BUCKET_NAME} \
        --policy file://bucket-policy.json
    
    log_success "S3 bucket policy updated for CloudFront access"
}

# Get CloudFront domain name
get_cloudfront_domain() {
    log "Retrieving CloudFront distribution domain name..."
    
    CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution \
        --id ${DISTRIBUTION_ID} \
        --query 'Distribution.DomainName' \
        --output text)
    
    echo "CLOUDFRONT_DOMAIN=${CLOUDFRONT_DOMAIN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "CloudFront domain: ${CLOUDFRONT_DOMAIN}"
}

# Configure DNS records (optional - requires Route 53 hosted zone)
configure_dns_records() {
    log "Configuring DNS records..."
    
    # Check if Route 53 hosted zone exists
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
        --dns-name ${DOMAIN_NAME} \
        --query 'HostedZones[0].Id' \
        --output text 2>/dev/null | cut -d'/' -f3 || echo "")
    
    if [[ -z "${HOSTED_ZONE_ID}" || "${HOSTED_ZONE_ID}" == "None" ]]; then
        log "⚠️  No Route 53 hosted zone found for ${DOMAIN_NAME}"
        log "⚠️  You'll need to manually create DNS records pointing to: ${CLOUDFRONT_DOMAIN}"
        log "⚠️  Create CNAME records for both ${DOMAIN_NAME} and ${SUBDOMAIN}"
        return 0
    fi
    
    # Create DNS records
    cat > dns-records.json << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${DOMAIN_NAME}",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "${CLOUDFRONT_DOMAIN}",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "Z2FDTNDATAQYW2"
                }
            }
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${SUBDOMAIN}",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "${CLOUDFRONT_DOMAIN}",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "Z2FDTNDATAQYW2"
                }
            }
        }
    ]
}
EOF
    
    # Update DNS records
    aws route53 change-resource-record-sets \
        --hosted-zone-id ${HOSTED_ZONE_ID} \
        --change-batch file://dns-records.json
    
    echo "HOSTED_ZONE_ID=${HOSTED_ZONE_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "DNS records configured for custom domain"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check certificate status
    CERT_STATUS=$(aws acm describe-certificate \
        --certificate-arn ${CERTIFICATE_ARN} \
        --region us-east-1 \
        --query 'Certificate.Status' \
        --output text)
    
    if [[ "${CERT_STATUS}" != "ISSUED" ]]; then
        log_error "Certificate status: ${CERT_STATUS}"
        return 1
    fi
    
    # Check CloudFront distribution status
    DISTRIBUTION_STATUS=$(aws cloudfront get-distribution \
        --id ${DISTRIBUTION_ID} \
        --query 'Distribution.Status' \
        --output text)
    
    log "Certificate Status: ${CERT_STATUS}"
    log "Distribution Status: ${DISTRIBUTION_STATUS}"
    
    # Test CloudFront domain
    log "Testing CloudFront domain connectivity..."
    if curl -sf "https://${CLOUDFRONT_DOMAIN}" > /dev/null; then
        log_success "CloudFront domain is accessible"
    else
        log "⚠️  CloudFront domain not yet accessible (may take 15-20 minutes to deploy)"
    fi
    
    log_success "Deployment validation completed"
}

# Print deployment summary
print_summary() {
    log "============================================"
    log "           DEPLOYMENT SUMMARY"
    log "============================================"
    log "Domain: ${DOMAIN_NAME}"
    log "Subdomain: ${SUBDOMAIN}"
    log "S3 Bucket: ${BUCKET_NAME}"
    log "CloudFront Domain: ${CLOUDFRONT_DOMAIN}"
    log "Certificate ARN: ${CERTIFICATE_ARN}"
    log "Distribution ID: ${DISTRIBUTION_ID}"
    log "============================================"
    log ""
    log "🎉 Deployment completed successfully!"
    log ""
    log "Next steps:"
    log "1. Wait 15-20 minutes for CloudFront distribution to fully deploy"
    log "2. Test your secure website:"
    log "   - CloudFront domain: https://${CLOUDFRONT_DOMAIN}"
    if [[ -n "${HOSTED_ZONE_ID:-}" ]]; then
        log "   - Custom domain: https://${DOMAIN_NAME}"
        log "   - Custom subdomain: https://${SUBDOMAIN}"
    else
        log "   - Configure DNS manually to point to: ${CLOUDFRONT_DOMAIN}"
    fi
    log "3. Verify SSL certificate: Check for the 🔒 lock icon in your browser"
    log ""
    log "Environment variables saved to: ${SCRIPT_DIR}/.env"
    log "Deployment logs saved to: ${LOG_FILE}"
}

# Main deployment function
main() {
    log "Starting deployment of secure static website with AWS Certificate Manager"
    log "========================================================================="
    
    # Initialize environment file
    echo "# Environment variables for secure static website deployment" > "${SCRIPT_DIR}/.env"
    echo "# Generated on: $(date)" >> "${SCRIPT_DIR}/.env"
    
    check_prerequisites
    validate_domain
    setup_environment
    create_s3_bucket
    upload_website_content
    request_ssl_certificate
    create_origin_access_control
    wait_for_certificate_validation
    create_cloudfront_distribution
    update_bucket_policy
    get_cloudfront_domain
    configure_dns_records
    validate_deployment
    print_summary
    
    log "Deployment completed successfully! 🎉"
}

# Script usage
usage() {
    cat << EOF
Usage: $0

Deploy a secure static website using AWS Certificate Manager, CloudFront, and S3.

Prerequisites:
- AWS CLI installed and configured
- jq installed for JSON processing
- openssl installed for SSL verification
- A registered domain name

Required environment variables:
- DOMAIN_NAME: Your domain name (e.g., example.com)

Example:
    export DOMAIN_NAME=mywebsite.com
    $0

For more information, see the recipe documentation.
EOF
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac