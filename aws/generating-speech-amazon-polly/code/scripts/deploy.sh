#!/bin/bash

# AWS Text-to-Speech Applications with Amazon Polly - Deployment Script
# This script creates the infrastructure needed for the Amazon Polly text-to-speech recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account information
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    
    # Check if user has necessary permissions
    log "Checking AWS permissions..."
    
    # Test S3 permissions
    if ! aws s3 ls &> /dev/null; then
        error "Insufficient S3 permissions. Please ensure you have S3 access."
        exit 1
    fi
    
    # Test Polly permissions
    if ! aws polly describe-voices --max-items 1 &> /dev/null; then
        error "Insufficient Polly permissions. Please ensure you have Amazon Polly access."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Export AWS configuration
    export AWS_REGION
    export AWS_ACCOUNT_ID
    
    # Generate unique identifiers for resources
    if command -v aws &> /dev/null; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 6)
    fi
    
    export POLLY_BUCKET_NAME="polly-audio-output-${RANDOM_SUFFIX}"
    export SAMPLE_TEXT_FILE="sample_text.txt"
    export SSML_TEXT_FILE="ssml_sample.xml"
    
    # Create deployment state file
    cat > polly-deployment-state.env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
POLLY_BUCKET_NAME=$POLLY_BUCKET_NAME
SAMPLE_TEXT_FILE=$SAMPLE_TEXT_FILE
SSML_TEXT_FILE=$SSML_TEXT_FILE
DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    success "Environment variables configured"
    log "Bucket name: $POLLY_BUCKET_NAME"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for audio output..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create S3 bucket: $POLLY_BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3 ls "s3://$POLLY_BUCKET_NAME" &> /dev/null; then
        warning "S3 bucket $POLLY_BUCKET_NAME already exists"
        return 0
    fi
    
    # Create bucket with appropriate region configuration
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$POLLY_BUCKET_NAME"
    else
        aws s3 mb "s3://$POLLY_BUCKET_NAME" --region "$AWS_REGION"
    fi
    
    # Configure bucket versioning
    aws s3api put-bucket-versioning \
        --bucket "$POLLY_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Configure bucket encryption
    aws s3api put-bucket-encryption \
        --bucket "$POLLY_BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    # Set bucket policy for secure access
    aws s3api put-bucket-policy \
        --bucket "$POLLY_BUCKET_NAME" \
        --policy '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "DenyInsecureConnections",
                    "Effect": "Deny",
                    "Principal": "*",
                    "Action": "s3:*",
                    "Resource": [
                        "arn:aws:s3:::'"$POLLY_BUCKET_NAME"'",
                        "arn:aws:s3:::'"$POLLY_BUCKET_NAME"'/*"
                    ],
                    "Condition": {
                        "Bool": {
                            "aws:SecureTransport": "false"
                        }
                    }
                }
            ]
        }'
    
    success "S3 bucket created: $POLLY_BUCKET_NAME"
}

# Function to create sample text files
create_sample_files() {
    log "Creating sample text files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create sample text files"
        return 0
    fi
    
    # Create sample text file
    cat > "$SAMPLE_TEXT_FILE" << 'EOF'
Welcome to Amazon Polly! This is a demonstration of text-to-speech synthesis. 
Amazon Polly can convert this text into natural-sounding speech using a variety of voices and languages. 
You can use Amazon Polly to create voice-enabled applications for mobile apps, IoT devices, and accessibility features.
EOF
    
    # Create SSML sample file
    cat > "$SSML_TEXT_FILE" << 'EOF'
<speak>
    <prosody rate="slow" pitch="low">
        Welcome to our <emphasis level="strong">premium</emphasis> service.
    </prosody>
    <break time="1s"/>
    <prosody rate="fast" pitch="high">
        This is an exciting announcement!
    </prosody>
    <break time="500ms"/>
    <prosody volume="soft">
        Please speak quietly in the library.
    </prosody>
    <break time="1s"/>
    <say-as interpret-as="telephone">1-800-555-0123</say-as>
    <break time="500ms"/>
    <say-as interpret-as="date" format="ymd">2024-01-15</say-as>
</speak>
EOF
    
    success "Sample text files created"
}

# Function to create pronunciation lexicon
create_pronunciation_lexicon() {
    log "Creating custom pronunciation lexicon..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would create pronunciation lexicon"
        return 0
    fi
    
    # Create pronunciation lexicon file
    cat > custom_pronunciation.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<lexicon version="1.0" 
    xmlns="http://www.w3.org/2005/01/pronunciation-lexicon"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
    xsi:schemaLocation="http://www.w3.org/2005/01/pronunciation-lexicon 
        http://www.w3.org/TR/2007/CR-pronunciation-lexicon-20071212/pls.xsd"
    alphabet="ipa" 
    xml:lang="en-US">
    <lexeme>
        <grapheme>AWS</grapheme>
        <alias>Amazon Web Services</alias>
    </lexeme>
    <lexeme>
        <grapheme>API</grapheme>
        <alias>Application Programming Interface</alias>
    </lexeme>
</lexicon>
EOF
    
    # Upload pronunciation lexicon
    aws polly put-lexicon \
        --name tech-terminology \
        --content file://custom_pronunciation.xml
    
    success "Pronunciation lexicon created: tech-terminology"
}

# Function to test basic functionality
test_basic_functionality() {
    log "Testing basic Polly functionality..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would test basic functionality"
        return 0
    fi
    
    # Test voice listing
    log "Testing voice listing..."
    VOICE_COUNT=$(aws polly describe-voices \
        --query 'length(Voices[])' \
        --output text)
    
    if [[ "$VOICE_COUNT" -gt 0 ]]; then
        success "Found $VOICE_COUNT available voices"
    else
        error "No voices found - check Polly permissions"
        exit 1
    fi
    
    # Test basic synthesis
    log "Testing basic speech synthesis..."
    aws polly synthesize-speech \
        --text "Hello from Amazon Polly deployment test" \
        --output-format mp3 \
        --voice-id Joanna \
        --engine neural \
        deployment-test.mp3
    
    if [[ -f "deployment-test.mp3" ]]; then
        success "Basic speech synthesis test passed"
        rm -f deployment-test.mp3
    else
        error "Basic speech synthesis test failed"
        exit 1
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would validate deployment"
        return 0
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://$POLLY_BUCKET_NAME" &> /dev/null; then
        success "S3 bucket validation passed"
    else
        error "S3 bucket validation failed"
        exit 1
    fi
    
    # Check pronunciation lexicon
    if aws polly get-lexicon --name tech-terminology &> /dev/null; then
        success "Pronunciation lexicon validation passed"
    else
        error "Pronunciation lexicon validation failed"
        exit 1
    fi
    
    # Check sample files
    if [[ -f "$SAMPLE_TEXT_FILE" ]] && [[ -f "$SSML_TEXT_FILE" ]]; then
        success "Sample files validation passed"
    else
        error "Sample files validation failed"
        exit 1
    fi
    
    success "All validation checks passed"
}

# Function to display deployment summary
show_deployment_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo "S3 Bucket: $POLLY_BUCKET_NAME"
    echo "Sample Text File: $SAMPLE_TEXT_FILE"
    echo "SSML Sample File: $SSML_TEXT_FILE"
    echo "Pronunciation Lexicon: tech-terminology"
    echo "Deployment State: polly-deployment-state.env"
    echo "===================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "Next Steps:"
        echo "1. Run the recipe steps from the markdown file"
        echo "2. Test voice synthesis with different voices and languages"
        echo "3. Experiment with SSML markup for advanced speech control"
        echo "4. Use the destroy.sh script to clean up resources when finished"
        echo ""
        echo "Cost Estimate:"
        echo "- S3 Storage: ~$0.01/month (minimal usage)"
        echo "- Amazon Polly: $4.00 per 1M characters (Standard) / $16.00 per 1M characters (Neural)"
        echo "- First 5M characters per month are free for 12 months"
    fi
}

# Main deployment function
main() {
    log "Starting Amazon Polly Text-to-Speech deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_sample_files
    create_pronunciation_lexicon
    test_basic_functionality
    validate_deployment
    show_deployment_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN completed successfully - no resources were created"
    else
        success "Deployment completed successfully!"
        echo ""
        echo "To clean up resources, run: ./destroy.sh"
    fi
}

# Trap errors and cleanup
trap 'error "Deployment failed! Check the error messages above."' ERR

# Run main function
main "$@"