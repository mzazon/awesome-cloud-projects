#!/bin/bash

# AWS PartyRock and S3 Static Website Deployment Script
# This script deploys the infrastructure for hosting a PartyRock AI application
# with S3 static website hosting and CloudFront CDN distribution

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    log_info "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set a default region with 'aws configure' or export AWS_DEFAULT_REGION."
        exit 1
    fi
    
    log_success "AWS CLI configured. Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
    local required_commands=("curl" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' is not installed."
            exit 1
        fi
    done
    
    log_success "All prerequisites are met"
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for unique resource names
    if command_exists aws; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 6)
    fi
    
    # Export environment variables
    export AWS_REGION="${AWS_REGION}"
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
    export BUCKET_NAME="partyrock-app-${RANDOM_SUFFIX}"
    export DISTRIBUTION_NAME="partyrock-cdn-${RANDOM_SUFFIX}"
    
    log_success "Resource names generated:"
    log_info "  Bucket Name: ${BUCKET_NAME}"
    log_info "  Distribution Name: ${DISTRIBUTION_NAME}"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account: ${AWS_ACCOUNT_ID}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for static website hosting..."
    
    # Create S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "Bucket ${BUCKET_NAME} already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb s3://${BUCKET_NAME}
        else
            aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
        fi
        log_success "S3 bucket created: ${BUCKET_NAME}"
    fi
    
    # Enable versioning
    log_info "Enabling versioning on S3 bucket..."
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    log_info "Enabling server-side encryption..."
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    log_success "S3 bucket security features configured"
}

# Function to configure static website hosting
configure_website_hosting() {
    log_info "Configuring S3 static website hosting..."
    
    # Enable static website hosting
    aws s3 website s3://${BUCKET_NAME} \
        --index-document index.html \
        --error-document error.html
    
    # Create the HTML index file
    log_info "Creating website content..."
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Business Name Generator</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 40px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }
        .container { 
            max-width: 900px; 
            margin: 0 auto; 
            background: white; 
            border-radius: 15px; 
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #2c3e50; 
            text-align: center; 
            margin-bottom: 30px;
            font-size: 2.5em;
        }
        .intro {
            font-size: 1.2em;
            text-align: center;
            margin-bottom: 40px;
            color: #666;
        }
        .partyrock-embed { 
            border: 2px solid #3498db; 
            padding: 30px; 
            border-radius: 10px;
            background: #f8f9fa;
            margin: 30px 0;
        }
        .btn { 
            background: linear-gradient(45deg, #ff9900, #ff6600); 
            color: white; 
            padding: 15px 30px; 
            text-decoration: none; 
            border-radius: 8px; 
            display: inline-block;
            font-weight: bold;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(255, 153, 0, 0.4);
        }
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 40px 0;
        }
        .feature {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #3498db;
        }
        .feature h3 {
            color: #2c3e50;
            margin-top: 0;
        }
        .tech-stack {
            background: #e8f5e8;
            padding: 20px;
            border-radius: 8px;
            margin: 30px 0;
        }
        .deployment-info {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            padding: 20px;
            border-radius: 8px;
            margin: 30px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 AI-Powered Business Name Generator</h1>
        <p class="intro">Experience the power of generative AI with our no-code application built using Amazon PartyRock and hosted on AWS cloud infrastructure.</p>
        
        <div class="partyrock-embed">
            <h2>🎯 Try the AI Application</h2>
            <p>Our AI business name generator uses advanced language models to create catchy, industry-specific business names tailored to your target audience. Click the button below to access the application:</p>
            <div style="text-align: center; margin: 20px 0;">
                <a href="#" class="btn" onclick="showPartyRockInfo()">
                    🎨 Launch AI Name Generator
                </a>
            </div>
            <p style="font-size: 0.9em; color: #666; text-align: center;">
                <em>Note: Replace the href above with your actual PartyRock application URL</em>
            </p>
        </div>
        
        <div class="features">
            <div class="feature">
                <h3>🤖 AI-Powered Generation</h3>
                <p>Leverages Amazon Bedrock's foundation models for intelligent name suggestions</p>
            </div>
            <div class="feature">
                <h3>🎯 Industry-Specific</h3>
                <p>Tailored suggestions based on your specific industry and business type</p>
            </div>
            <div class="feature">
                <h3>👥 Audience-Aware</h3>
                <p>Considers your target audience demographics and preferences</p>
            </div>
            <div class="feature">
                <h3>🎨 Visual Concepts</h3>
                <p>Generates logo concepts and branding ideas for selected names</p>
            </div>
        </div>
        
        <div class="tech-stack">
            <h2>🏗️ Technology Stack</h2>
            <ul>
                <li><strong>Amazon PartyRock</strong> - No-code AI application platform</li>
                <li><strong>Amazon Bedrock</strong> - Foundation models for AI generation</li>
                <li><strong>Amazon S3</strong> - Static website hosting with 99.999999999% durability</li>
                <li><strong>Amazon CloudFront</strong> - Global content delivery network</li>
                <li><strong>AWS Certificate Manager</strong> - SSL/TLS certificate management</li>
            </ul>
        </div>
        
        <div class="deployment-info">
            <h2>📋 Deployment Information</h2>
            <p><strong>Deployed on:</strong> <span id="deployDate"></span></p>
            <p><strong>S3 Bucket:</strong> <span id="bucketName">Loading...</span></p>
            <p><strong>CloudFront Distribution:</strong> <span id="cloudFrontDomain">Loading...</span></p>
            <p><strong>AWS Region:</strong> <span id="awsRegion">Loading...</span></p>
        </div>
    </div>
    
    <script>
        // Set deployment date
        document.getElementById('deployDate').textContent = new Date().toLocaleDateString();
        
        // Function to show PartyRock information
        function showPartyRockInfo() {
            alert('To complete the setup:\n\n1. Visit https://partyrock.aws/\n2. Create your AI application\n3. Make it public and get the share URL\n4. Replace the href in this HTML with your PartyRock URL\n5. Re-upload this file to S3');
        }
        
        // Try to populate deployment info from URL or environment
        try {
            // This would be populated by your deployment script
            document.getElementById('bucketName').textContent = window.location.hostname.includes('s3') ? 
                window.location.hostname.split('.')[0] : 'Check S3 Console';
            document.getElementById('cloudFrontDomain').textContent = window.location.hostname.includes('cloudfront') ? 
                window.location.hostname : 'Check CloudFront Console';
            document.getElementById('awsRegion').textContent = 'Check AWS Console';
        } catch (e) {
            console.log('Could not auto-populate deployment info');
        }
    </script>
</body>
</html>
EOF
    
    # Create error page
    cat > error.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - AI Business Name Generator</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 40px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
            text-align: center;
        }
        .container { 
            max-width: 600px; 
            margin: 100px auto; 
            background: white; 
            border-radius: 15px; 
            padding: 40px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
        }
        h1 { color: #e74c3c; font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; margin-bottom: 30px; }
        .btn { 
            background: linear-gradient(45deg, #3498db, #2980b9); 
            color: white; 
            padding: 15px 30px; 
            text-decoration: none; 
            border-radius: 8px; 
            display: inline-block;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>404</h1>
        <h2>Page Not Found</h2>
        <p>The page you're looking for doesn't exist. Let's get you back to the AI Business Name Generator.</p>
        <a href="/" class="btn">← Back to Home</a>
    </div>
</body>
</html>
EOF
    
    # Upload files to S3
    aws s3 cp index.html s3://${BUCKET_NAME}/
    aws s3 cp error.html s3://${BUCKET_NAME}/
    
    # Clean up local files
    rm -f index.html error.html
    
    log_success "Website content uploaded to S3"
}

# Function to configure public access
configure_public_access() {
    log_info "Configuring public access for website hosting..."
    
    # Remove S3 public access block
    aws s3api delete-public-access-block --bucket ${BUCKET_NAME} || true
    
    # Create bucket policy for public read access
    cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        }
    ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket ${BUCKET_NAME} \
        --policy file://bucket-policy.json
    
    # Clean up policy file
    rm -f bucket-policy.json
    
    log_success "Public access configured for website hosting"
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log_info "Creating CloudFront distribution..."
    
    # Create CloudFront distribution configuration
    cat > cloudfront-config.json << EOF
{
    "CallerReference": "${DISTRIBUTION_NAME}-$(date +%s)",
    "Comment": "PartyRock AI Application CDN - ${BUCKET_NAME}",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-${BUCKET_NAME}",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {"Forward": "none"}
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
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-${BUCKET_NAME}",
                "DomainName": "${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                }
            }
        ]
    },
    "Enabled": true,
    "DefaultRootObject": "index.html",
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
    "PriceClass": "PriceClass_100"
}
EOF
    
    # Create CloudFront distribution
    DISTRIBUTION_RESULT=$(aws cloudfront create-distribution \
        --distribution-config file://cloudfront-config.json)
    
    DISTRIBUTION_ID=$(echo "$DISTRIBUTION_RESULT" | jq -r '.Distribution.Id')
    CLOUDFRONT_DOMAIN=$(echo "$DISTRIBUTION_RESULT" | jq -r '.Distribution.DomainName')
    
    # Clean up config file
    rm -f cloudfront-config.json
    
    # Save distribution info
    echo "DISTRIBUTION_ID=${DISTRIBUTION_ID}" > deployment-info.txt
    echo "CLOUDFRONT_DOMAIN=${CLOUDFRONT_DOMAIN}" >> deployment-info.txt
    echo "BUCKET_NAME=${BUCKET_NAME}" >> deployment-info.txt
    echo "AWS_REGION=${AWS_REGION}" >> deployment-info.txt
    echo "DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> deployment-info.txt
    
    log_success "CloudFront distribution created: ${DISTRIBUTION_ID}"
    log_info "CloudFront domain: https://${CLOUDFRONT_DOMAIN}"
    log_warning "Distribution deployment in progress (may take 10-15 minutes)"
}

# Function to display deployment results
display_results() {
    log_success "Deployment completed successfully!"
    echo
    log_info "=== Deployment Summary ==="
    log_info "S3 Bucket: ${BUCKET_NAME}"
    log_info "S3 Website URL: http://${BUCKET_NAME}.s3-website.${AWS_REGION}.amazonaws.com"
    log_info "CloudFront Domain: https://${CLOUDFRONT_DOMAIN}"
    log_info "Distribution ID: ${DISTRIBUTION_ID}"
    echo
    log_info "=== Next Steps ==="
    log_info "1. Visit https://partyrock.aws/ to create your AI application"
    log_info "2. Sign in with Apple, Amazon, or Google account"
    log_info "3. Create a business name generator application"
    log_info "4. Make your PartyRock app public and get the share URL"
    log_info "5. Update the HTML file with your PartyRock URL and re-upload to S3"
    echo
    log_info "=== Testing Access ==="
    log_info "S3 Website (immediate): curl -I http://${BUCKET_NAME}.s3-website.${AWS_REGION}.amazonaws.com"
    log_info "CloudFront (after deployment): curl -I https://${CLOUDFRONT_DOMAIN}"
    echo
    log_warning "Note: CloudFront distribution may take 10-15 minutes to fully deploy"
    log_info "Deployment information saved to: deployment-info.txt"
}

# Function to wait for CloudFront deployment (optional)
wait_for_cloudfront() {
    if [ "${WAIT_FOR_CLOUDFRONT:-false}" = "true" ]; then
        log_info "Waiting for CloudFront distribution deployment..."
        aws cloudfront wait distribution-deployed --id ${DISTRIBUTION_ID}
        log_success "CloudFront distribution is now deployed and ready"
    else
        log_info "Skipping CloudFront deployment wait. Set WAIT_FOR_CLOUDFRONT=true to wait."
    fi
}

# Main deployment function
main() {
    log_info "Starting AWS PartyRock and S3 deployment..."
    echo
    
    # Run all deployment steps
    check_aws_config
    check_prerequisites
    generate_resource_names
    create_s3_bucket
    configure_website_hosting
    configure_public_access
    create_cloudfront_distribution
    wait_for_cloudfront
    display_results
    
    log_success "Deployment script completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created. Check AWS console or run destroy.sh to clean up."; exit 1' INT TERM

# Parse command line arguments
WAIT_FOR_CLOUDFRONT=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --wait-cloudfront)
            WAIT_FOR_CLOUDFRONT=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --wait-cloudfront    Wait for CloudFront distribution to deploy completely"
            echo "  --dry-run           Show what would be deployed without actually deploying"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function if not dry run
if [ "$DRY_RUN" = "true" ]; then
    log_info "DRY RUN MODE - Would deploy the following resources:"
    log_info "- S3 bucket for static website hosting"
    log_info "- S3 bucket policy for public read access"
    log_info "- CloudFront distribution for global CDN"
    log_info "- HTML files for the website"
    log_info "Run without --dry-run to actually deploy these resources."
else
    main
fi