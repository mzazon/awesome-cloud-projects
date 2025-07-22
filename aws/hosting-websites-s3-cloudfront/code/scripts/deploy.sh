#!/bin/bash

# Static Website Hosting Deployment Script
# This script deploys a static website using S3, CloudFront, and Route 53
# Based on the recipe: Building Static Website Hosting with S3, CloudFront, and Route 53

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: $1"
    else
        eval "$1"
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or you don't have valid credentials."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some features may not work properly."
    fi
    
    info "Prerequisites check passed"
}

# Function to validate domain name
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain name format: $domain"
    fi
}

# Function to get user input for domain
get_domain_input() {
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
        validate_domain "$DOMAIN_NAME"
    fi
    
    export DOMAIN_NAME
    export SUBDOMAIN="www.${DOMAIN_NAME}"
    export ROOT_BUCKET="${DOMAIN_NAME}"
    export WWW_BUCKET="${SUBDOMAIN}"
    
    info "Domain: $DOMAIN_NAME"
    info "Subdomain: $SUBDOMAIN"
    info "Root bucket: $ROOT_BUCKET"
    info "WWW bucket: $WWW_BUCKET"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured. Please configure AWS CLI."
    fi
    
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to check if hosted zone exists
check_hosted_zone() {
    log "Checking for existing hosted zone..."
    
    local zone_check=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME" --query "HostedZones[?Name=='${DOMAIN_NAME}.']" --output text 2>/dev/null || echo "")
    
    if [[ -z "$zone_check" ]]; then
        error "No hosted zone found for domain: $DOMAIN_NAME. Please create a hosted zone in Route 53 first."
    fi
    
    export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME" --query "HostedZones[0].Id" --output text | cut -d'/' -f3)
    info "Found hosted zone ID: $HOSTED_ZONE_ID"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create WWW bucket
    if aws s3api head-bucket --bucket "$WWW_BUCKET" 2>/dev/null; then
        warn "Bucket $WWW_BUCKET already exists"
    else
        info "Creating bucket: $WWW_BUCKET"
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            execute "aws s3api create-bucket --bucket '$WWW_BUCKET' --region '$AWS_REGION'"
        else
            execute "aws s3api create-bucket --bucket '$WWW_BUCKET' --region '$AWS_REGION' --create-bucket-configuration LocationConstraint='$AWS_REGION'"
        fi
    fi
    
    # Configure website hosting
    execute "aws s3 website 's3://$WWW_BUCKET/' --index-document index.html --error-document error.html"
    
    # Create root domain bucket
    if aws s3api head-bucket --bucket "$ROOT_BUCKET" 2>/dev/null; then
        warn "Bucket $ROOT_BUCKET already exists"
    else
        info "Creating bucket: $ROOT_BUCKET"
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            execute "aws s3api create-bucket --bucket '$ROOT_BUCKET' --region '$AWS_REGION'"
        else
            execute "aws s3api create-bucket --bucket '$ROOT_BUCKET' --region '$AWS_REGION' --create-bucket-configuration LocationConstraint='$AWS_REGION'"
        fi
    fi
    
    # Configure redirect
    cat > /tmp/redirect-config.json << EOF
{
    "RedirectAllRequestsTo": {
        "HostName": "$SUBDOMAIN",
        "Protocol": "https"
    }
}
EOF
    
    execute "aws s3api put-bucket-website --bucket '$ROOT_BUCKET' --website-configuration file:///tmp/redirect-config.json"
    
    log "S3 buckets created and configured successfully"
}

# Function to create sample website content
create_website_content() {
    log "Creating sample website content..."
    
    # Create index.html
    cat > /tmp/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $DOMAIN_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; 
               text-align: center; background-color: #f0f8ff; }
        h1 { color: #2c3e50; }
        p { color: #7f8c8d; font-size: 18px; }
    </style>
</head>
<body>
    <h1>Welcome to $DOMAIN_NAME</h1>
    <p>Your static website is now live with global CDN delivery!</p>
    <p>Powered by AWS S3, CloudFront, and Route 53</p>
</body>
</html>
EOF
    
    # Create error.html
    cat > /tmp/error.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - $DOMAIN_NAME</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; 
               text-align: center; background-color: #fff5f5; }
        h1 { color: #e74c3c; }
    </style>
</head>
<body>
    <h1>404 - Page Not Found</h1>
    <p>The page you're looking for doesn't exist.</p>
    <a href="/">Return to Home</a>
</body>
</html>
EOF
    
    info "Sample website content created"
}

# Function to upload content to S3
upload_content_to_s3() {
    log "Uploading content to S3..."
    
    execute "aws s3 cp /tmp/index.html 's3://$WWW_BUCKET/' --content-type 'text/html'"
    execute "aws s3 cp /tmp/error.html 's3://$WWW_BUCKET/' --content-type 'text/html'"
    
    # Create bucket policy
    cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$WWW_BUCKET/*"
        }
    ]
}
EOF
    
    # Disable block public access
    execute "aws s3api delete-public-access-block --bucket '$WWW_BUCKET'"
    
    # Apply bucket policy
    execute "aws s3api put-bucket-policy --bucket '$WWW_BUCKET' --policy file:///tmp/bucket-policy.json"
    
    info "Content uploaded and public access configured"
}

# Function to request SSL certificate
request_ssl_certificate() {
    log "Requesting SSL certificate..."
    
    # Check if certificate already exists
    local existing_cert=$(aws acm list-certificates --region us-east-1 --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" --output text)
    
    if [[ -n "$existing_cert" ]]; then
        warn "SSL certificate already exists for domain: $DOMAIN_NAME"
        export CERT_ARN="$existing_cert"
    else
        info "Requesting new SSL certificate for $DOMAIN_NAME and $SUBDOMAIN"
        export CERT_ARN=$(aws acm request-certificate \
            --domain-name "$DOMAIN_NAME" \
            --subject-alternative-names "$SUBDOMAIN" \
            --validation-method DNS \
            --region us-east-1 \
            --query CertificateArn --output text)
    fi
    
    info "Certificate ARN: $CERT_ARN"
    
    # Wait for certificate to be created
    sleep 10
}

# Function to create DNS validation records
create_dns_validation() {
    log "Creating DNS validation records..."
    
    # Get validation records
    local validation_records=$(aws acm describe-certificate \
        --certificate-arn "$CERT_ARN" \
        --region us-east-1 \
        --query 'Certificate.DomainValidationOptions[*].[DomainName,ResourceRecord.Name,ResourceRecord.Value]' \
        --output json)
    
    if [[ "$validation_records" == "[]" ]]; then
        info "Certificate may already be validated"
        return 0
    fi
    
    # Create validation records in Route 53
    echo "$validation_records" | jq -r '.[] | @base64' | while read -r record; do
        local domain=$(echo "$record" | base64 -d | jq -r '.[0]')
        local name=$(echo "$record" | base64 -d | jq -r '.[1]')
        local value=$(echo "$record" | base64 -d | jq -r '.[2]')
        
        info "Creating validation record for domain: $domain"
        
        cat > /tmp/validation-record.json << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$name",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "$value"
                    }
                ]
            }
        }
    ]
}
EOF
        
        execute "aws route53 change-resource-record-sets --hosted-zone-id '$HOSTED_ZONE_ID' --change-batch file:///tmp/validation-record.json"
    done
    
    info "DNS validation records created"
    info "Waiting for certificate validation (this may take a few minutes)..."
    
    # Wait for certificate to be validated
    local timeout=300  # 5 minutes
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local cert_status=$(aws acm describe-certificate --certificate-arn "$CERT_ARN" --region us-east-1 --query 'Certificate.Status' --output text)
        
        if [[ "$cert_status" == "ISSUED" ]]; then
            info "Certificate validated successfully"
            return 0
        elif [[ "$cert_status" == "FAILED" ]]; then
            error "Certificate validation failed"
        fi
        
        sleep 30
        elapsed=$((elapsed + 30))
        info "Waiting for certificate validation... ($elapsed/$timeout seconds)"
    done
    
    warn "Certificate validation is taking longer than expected. Continuing with deployment..."
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution..."
    
    # Get S3 website endpoint
    export S3_WEBSITE_ENDPOINT="${WWW_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
    
    # Create CloudFront distribution configuration
    cat > /tmp/cloudfront-config.json << EOF
{
    "CallerReference": "$(date +%s)-$WWW_BUCKET",
    "Comment": "CloudFront distribution for $SUBDOMAIN",
    "DefaultRootObject": "index.html",
    "Aliases": {
        "Quantity": 1,
        "Items": ["$SUBDOMAIN"]
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "$WWW_BUCKET-origin",
                "DomainName": "$S3_WEBSITE_ENDPOINT",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only"
                }
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "$WWW_BUCKET-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "Compress": true,
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
        "MinTTL": 0,
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {"Forward": "none"}
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        }
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100",
    "ViewerCertificate": {
        "ACMCertificateArn": "$CERT_ARN",
        "SSLSupportMethod": "sni-only",
        "MinimumProtocolVersion": "TLSv1.2_2021"
    }
}
EOF
    
    # Create CloudFront distribution
    export CF_DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/cloudfront-config.json \
        --query 'Distribution.Id' --output text)
    
    info "CloudFront Distribution ID: $CF_DISTRIBUTION_ID"
    
    # Wait for distribution to be deployed
    info "Waiting for CloudFront distribution to deploy (this may take 10-15 minutes)..."
    
    aws cloudfront wait distribution-deployed --id "$CF_DISTRIBUTION_ID"
    
    info "CloudFront distribution deployed successfully"
}

# Function to create Route 53 DNS records
create_dns_records() {
    log "Creating Route 53 DNS records..."
    
    # Get CloudFront domain name
    export CF_DOMAIN_NAME=$(aws cloudfront get-distribution \
        --id "$CF_DISTRIBUTION_ID" \
        --query 'Distribution.DomainName' --output text)
    
    info "CloudFront Domain: $CF_DOMAIN_NAME"
    
    # Create DNS record for www subdomain
    cat > /tmp/www-dns-change.json << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$SUBDOMAIN",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "$CF_DOMAIN_NAME",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "Z2FDTNDATAQYW2"
                }
            }
        }
    ]
}
EOF
    
    execute "aws route53 change-resource-record-sets --hosted-zone-id '$HOSTED_ZONE_ID' --change-batch file:///tmp/www-dns-change.json"
    
    # Create DNS record for root domain (redirect)
    cat > /tmp/root-dns-change.json << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$DOMAIN_NAME",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "$ROOT_BUCKET.s3-website-$AWS_REGION.amazonaws.com",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "$(aws s3api get-bucket-location --bucket '$ROOT_BUCKET' --query 'LocationConstraint' --output text | xargs -I {} aws s3api list-buckets --query 'Buckets[0].Name' --output text | xargs -I {} aws s3api get-bucket-website --bucket '$ROOT_BUCKET' --query 'RedirectAllRequestsTo.HostName' --output text | xargs -I {} echo Z3AQBSTGFYJSTF)"
                }
            }
        }
    ]
}
EOF
    
    # Get the correct hosted zone ID for S3 website endpoint
    local s3_hosted_zone_id
    case "$AWS_REGION" in
        us-east-1) s3_hosted_zone_id="Z3AQBSTGFYJSTF" ;;
        us-west-1) s3_hosted_zone_id="Z2F56UZL2M1ACD" ;;
        us-west-2) s3_hosted_zone_id="Z3BJ6K6RIION7M" ;;
        eu-west-1) s3_hosted_zone_id="Z1BKCTXD74EZPE" ;;
        eu-central-1) s3_hosted_zone_id="Z21DNDUVLTQW6Q" ;;
        ap-southeast-1) s3_hosted_zone_id="Z3O0SRN1WG7CG" ;;
        ap-northeast-1) s3_hosted_zone_id="Z2M4EHUR26P7ZW" ;;
        *) s3_hosted_zone_id="Z3AQBSTGFYJSTF" ;;  # Default to us-east-1
    esac
    
    # Update the root domain DNS record with correct hosted zone ID
    cat > /tmp/root-dns-change.json << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$DOMAIN_NAME",
                "Type": "A",
                "AliasTarget": {
                    "DNSName": "$ROOT_BUCKET.s3-website-$AWS_REGION.amazonaws.com",
                    "EvaluateTargetHealth": false,
                    "HostedZoneId": "$s3_hosted_zone_id"
                }
            }
        }
    ]
}
EOF
    
    execute "aws route53 change-resource-record-sets --hosted-zone-id '$HOSTED_ZONE_ID' --change-batch file:///tmp/root-dns-change.json"
    
    info "DNS records created successfully"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check S3 website endpoint
    info "Testing S3 website endpoint..."
    local s3_response=$(curl -s -o /dev/null -w "%{http_code}" "http://${WWW_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com" || echo "000")
    if [[ "$s3_response" == "200" ]]; then
        info "✅ S3 website endpoint is working"
    else
        warn "S3 website endpoint returned status: $s3_response"
    fi
    
    # Check CloudFront distribution status
    info "Checking CloudFront distribution status..."
    local cf_status=$(aws cloudfront get-distribution --id "$CF_DISTRIBUTION_ID" --query 'Distribution.Status' --output text)
    info "CloudFront status: $cf_status"
    
    # Check SSL certificate status
    info "Checking SSL certificate status..."
    local cert_status=$(aws acm describe-certificate --certificate-arn "$CERT_ARN" --region us-east-1 --query 'Certificate.Status' --output text)
    info "Certificate status: $cert_status"
    
    # Test website accessibility (may take time for DNS propagation)
    info "Testing website accessibility..."
    info "Note: DNS propagation may take up to 5 minutes"
    
    sleep 30  # Wait for DNS propagation
    
    local https_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$SUBDOMAIN" || echo "000")
    if [[ "$https_response" == "200" ]]; then
        info "✅ Website is accessible via HTTPS"
    else
        warn "Website returned status: $https_response (DNS may still be propagating)"
    fi
    
    # Test redirect from root domain
    local redirect_response=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_NAME" || echo "000")
    if [[ "$redirect_response" == "301" || "$redirect_response" == "302" ]]; then
        info "✅ Root domain redirect is working"
    else
        warn "Root domain redirect returned status: $redirect_response"
    fi
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > /tmp/deployment-info.json << EOF
{
    "domain_name": "$DOMAIN_NAME",
    "subdomain": "$SUBDOMAIN",
    "root_bucket": "$ROOT_BUCKET",
    "www_bucket": "$WWW_BUCKET",
    "certificate_arn": "$CERT_ARN",
    "cloudfront_distribution_id": "$CF_DISTRIBUTION_ID",
    "cloudfront_domain": "$CF_DOMAIN_NAME",
    "hosted_zone_id": "$HOSTED_ZONE_ID",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    execute "cp /tmp/deployment-info.json ./deployment-info.json"
    
    info "Deployment information saved to deployment-info.json"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    rm -f /tmp/redirect-config.json /tmp/index.html /tmp/error.html /tmp/bucket-policy.json
    rm -f /tmp/validation-record.json /tmp/cloudfront-config.json /tmp/www-dns-change.json /tmp/root-dns-change.json
    rm -f /tmp/deployment-info.json
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Domain Name: $DOMAIN_NAME"
    echo "Website URL: https://$SUBDOMAIN"
    echo "Root Bucket: $ROOT_BUCKET"
    echo "WWW Bucket: $WWW_BUCKET"
    echo "CloudFront Distribution: $CF_DISTRIBUTION_ID"
    echo "Certificate ARN: $CERT_ARN"
    echo "===================="
    echo ""
    info "Your static website is now deployed!"
    info "Website URL: https://$SUBDOMAIN"
    info "Root domain redirect: https://$DOMAIN_NAME"
    echo ""
    warn "Note: DNS propagation may take up to 5 minutes for global availability"
    echo ""
}

# Main execution function
main() {
    log "Starting static website deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Get domain input
    get_domain_input
    
    # Setup environment
    setup_environment
    
    # Check hosted zone
    check_hosted_zone
    
    # Create S3 buckets
    create_s3_buckets
    
    # Create website content
    create_website_content
    
    # Upload content to S3
    upload_content_to_s3
    
    # Request SSL certificate
    request_ssl_certificate
    
    # Create DNS validation records
    create_dns_validation
    
    # Create CloudFront distribution
    create_cloudfront_distribution
    
    # Create DNS records
    create_dns_records
    
    # Validate deployment
    validate_deployment
    
    # Save deployment info
    save_deployment_info
    
    # Display summary
    display_summary
    
    # Cleanup temporary files
    cleanup_temp_files
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi