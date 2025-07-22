#!/bin/bash

# Deploy script for Amazon Polly Text-to-Speech Solutions
# This script deploys all infrastructure and resources needed for the recipe

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Amazon Polly Text-to-Speech Solutions infrastructure

OPTIONS:
    -h, --help          Show this help message
    -r, --region        AWS region (default: from AWS config)
    -d, --dry-run       Show what would be deployed without creating resources
    -v, --verbose       Enable verbose output

EXAMPLES:
    $0                  Deploy with default settings
    $0 -r us-east-1     Deploy to specific region
    $0 --dry-run        Show deployment plan without creating resources

EOF
}

# Parse command line arguments
DRY_RUN=false
VERBOSE=false
AWS_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose output if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Get AWS account information
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    log "AWS Account ID: $account_id"
    log "User/Role: $user_arn"
    
    success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set region
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, using default: $AWS_REGION"
        fi
    fi
    
    # Get account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export BUCKET_NAME="polly-audio-storage-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="polly-batch-processor-${random_suffix}"
    export IAM_ROLE_NAME="PollyProcessorRole-${random_suffix}"
    
    log "Environment variables set:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  BUCKET_NAME: $BUCKET_NAME"
    log "  LAMBDA_FUNCTION_NAME: $LAMBDA_FUNCTION_NAME"
    log "  IAM_ROLE_NAME: $IAM_ROLE_NAME"
    
    # Save environment variables for cleanup script
    cat > .env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
BUCKET_NAME=$BUCKET_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
IAM_ROLE_NAME=$IAM_ROLE_NAME
EOF
    
    success "Environment setup completed"
}

# Execute command with dry-run support
execute_command() {
    local description="$1"
    local command="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] $description"
        log "[DRY-RUN] Command: $command"
    else
        log "$description"
        eval "$command"
    fi
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for audio storage..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        warning "S3 bucket $BUCKET_NAME already exists"
        return 0
    fi
    
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        execute_command "Creating S3 bucket in us-east-1" \
            "aws s3 mb s3://${BUCKET_NAME}"
    else
        execute_command "Creating S3 bucket in $AWS_REGION" \
            "aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}"
    fi
    
    # Enable versioning
    execute_command "Enabling S3 bucket versioning" \
        "aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} --versioning-configuration Status=Enabled"
    
    # Set bucket policy for secure access
    local bucket_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
    )
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$bucket_policy" > bucket-policy.json
        execute_command "Applying bucket security policy" \
            "aws s3api put-bucket-policy --bucket ${BUCKET_NAME} --policy file://bucket-policy.json"
        rm -f bucket-policy.json
    fi
    
    success "S3 bucket created successfully"
}

# Create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        warning "IAM role $IAM_ROLE_NAME already exists"
        return 0
    fi
    
    # Create trust policy
    local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    )
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$trust_policy" > trust-policy.json
        execute_command "Creating IAM role" \
            "aws iam create-role --role-name ${IAM_ROLE_NAME} --assume-role-policy-document file://trust-policy.json"
        rm -f trust-policy.json
    else
        execute_command "Creating IAM role" \
            "aws iam create-role --role-name ${IAM_ROLE_NAME} --assume-role-policy-document '<trust-policy>'"
    fi
    
    # Attach managed policies
    execute_command "Attaching Lambda basic execution policy" \
        "aws iam attach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    execute_command "Attaching Polly full access policy" \
        "aws iam attach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonPollyFullAccess"
    
    # Create custom S3 policy for the specific bucket
    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
    )
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$s3_policy" > s3-policy.json
        execute_command "Creating custom S3 policy" \
            "aws iam create-policy --policy-name ${IAM_ROLE_NAME}-S3Policy --policy-document file://s3-policy.json"
        
        execute_command "Attaching custom S3 policy" \
            "aws iam attach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_ROLE_NAME}-S3Policy"
        rm -f s3-policy.json
    else
        execute_command "Creating and attaching custom S3 policy" \
            "aws iam create-policy and attach to role"
    fi
    
    # Wait for role to be available
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for IAM role to be available..."
        sleep 10
    fi
    
    success "IAM role created successfully"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        warning "Lambda function $LAMBDA_FUNCTION_NAME already exists"
        return 0
    fi
    
    # Create Lambda function code
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > lambda_function.py << 'EOF'
import boto3
import json
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    polly = boto3.client('polly')
    s3 = boto3.client('s3')
    
    # Get bucket name from environment
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        # Handle S3 event or direct invocation
        if 'Records' in event:
            # S3 event trigger
            record = event['Records'][0]
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Read text content from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            text_content = response['Body'].read().decode('utf-8')
        else:
            # Direct invocation
            text_content = event.get('text', 'Hello from Amazon Polly!')
        
        # Synthesize speech
        response = polly.synthesize_speech(
            Text=text_content,
            OutputFormat='mp3',
            VoiceId=event.get('voice_id', 'Joanna'),
            Engine='neural'
        )
        
        # Generate output filename
        output_key = f"audio/{context.aws_request_id}.mp3"
        
        # Save to S3
        s3.put_object(
            Bucket=bucket_name,
            Key=output_key,
            Body=response['AudioStream'].read(),
            ContentType='audio/mpeg'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Speech synthesis completed',
                'audio_url': f"s3://{bucket_name}/{output_key}",
                'characters_processed': len(text_content)
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF
        
        # Create deployment package
        zip lambda_function.zip lambda_function.py
    fi
    
    # Create Lambda function
    local role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
    execute_command "Creating Lambda function" \
        "aws lambda create-function \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --runtime python3.9 \
            --role ${role_arn} \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda_function.zip \
            --environment Variables='{BUCKET_NAME=${BUCKET_NAME}}' \
            --timeout 60 \
            --region ${AWS_REGION}"
    
    # Clean up deployment package
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f lambda_function.py lambda_function.zip
    fi
    
    success "Lambda function created successfully"
}

# Create sample content and test resources
create_sample_content() {
    log "Creating sample content and test resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create sample text files
        cat > sample_text.txt << 'EOF'
Welcome to Amazon Polly! This is a demonstration of high-quality text-to-speech synthesis using neural voices. Amazon Polly can convert this text into natural-sounding speech in multiple languages and voices.
EOF
        
        cat > ssml_example.xml << 'EOF'
<speak>
<prosody rate="medium" pitch="medium">
Welcome to our <emphasis level="strong">premium</emphasis> service.
</prosody>

<break time="1s"/>

<prosody rate="slow">
Please note that our phone number is <say-as interpret-as="telephone">+1-555-123-4567</say-as>.
</prosody>

<break time="500ms"/>

<prosody volume="soft">
Thank you for choosing our service. Have a wonderful day!
</prosody>
</speak>
EOF
        
        cat > long_content.txt << 'EOF'
Welcome to our comprehensive guide on sustainable business practices. In today's rapidly evolving marketplace, organizations must balance profitability with environmental responsibility. This presentation will explore innovative strategies that successful companies have implemented to reduce their carbon footprint while maintaining competitive advantages.

Our first topic covers renewable energy adoption in corporate environments. Many Fortune 500 companies have successfully transitioned to solar and wind power, resulting in significant cost savings and improved public perception. The initial investment in renewable infrastructure typically pays for itself within five to seven years through reduced energy costs.

The second area we'll examine is supply chain optimization. By implementing data-driven logistics solutions and partnering with environmentally conscious suppliers, companies can reduce transportation costs while minimizing environmental impact. This approach often leads to improved efficiency and stronger supplier relationships.
EOF
        
        # Upload sample content to S3
        execute_command "Uploading sample content to S3" \
            "aws s3 cp sample_text.txt s3://${BUCKET_NAME}/samples/ && \
             aws s3 cp ssml_example.xml s3://${BUCKET_NAME}/samples/ && \
             aws s3 cp long_content.txt s3://${BUCKET_NAME}/samples/"
        
        # Clean up local files
        rm -f sample_text.txt ssml_example.xml long_content.txt
    else
        execute_command "Creating and uploading sample content" \
            "Create sample text files and upload to S3"
    fi
    
    success "Sample content created successfully"
}

# Create custom lexicon
create_custom_lexicon() {
    log "Creating custom pronunciation lexicon..."
    
    # Check if lexicon already exists
    if aws polly get-lexicon --name CustomPronunciations --region "${AWS_REGION}" &> /dev/null; then
        warning "Custom lexicon already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > custom_lexicon.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<lexicon version="1.0" xmlns="http://www.w3.org/2005/01/pronunciation-lexicon" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://www.w3.org/2005/01/pronunciation-lexicon 
                             http://www.w3.org/TR/2007/CR-pronunciation-lexicon-20071212/pls.xsd"
         alphabet="ipa" xml:lang="en-US">
    <lexeme>
        <grapheme>AWS</grapheme>
        <phoneme>eɪ dʌbljuː ɛs</phoneme>
    </lexeme>
    <lexeme>
        <grapheme>Polly</grapheme>
        <phoneme>pɑli</phoneme>
    </lexeme>
    <lexeme>
        <grapheme>API</grapheme>
        <phoneme>eɪ piː aɪ</phoneme>
    </lexeme>
</lexicon>
EOF
        
        execute_command "Uploading custom lexicon to Polly" \
            "aws polly put-lexicon --name CustomPronunciations --content file://custom_lexicon.xml --region ${AWS_REGION}"
        
        rm -f custom_lexicon.xml
    else
        execute_command "Creating and uploading custom lexicon" \
            "aws polly put-lexicon with custom pronunciations"
    fi
    
    success "Custom lexicon created successfully"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Test Lambda function
        log "Testing Lambda function..."
        aws lambda invoke \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --payload '{"text": "This is a test of the Amazon Polly deployment. The system is working correctly.", "voice_id": "Joanna"}' \
            --region "${AWS_REGION}" \
            test_response.json > /dev/null
        
        if [[ $? -eq 0 ]]; then
            log "Lambda test response:"
            cat test_response.json
            rm -f test_response.json
        else
            error "Lambda function test failed"
        fi
        
        # Test S3 bucket access
        log "Testing S3 bucket access..."
        aws s3 ls "s3://${BUCKET_NAME}/" > /dev/null
        
        # Test Polly service
        log "Testing Polly service..."
        aws polly describe-voices --region "${AWS_REGION}" --query 'Voices[0].[VoiceId,Gender,LanguageCode]' --output table
        
        success "Deployment tests completed successfully"
    else
        log "[DRY-RUN] Would test Lambda function, S3 access, and Polly service"
    fi
}

# Main deployment function
main() {
    log "Starting Amazon Polly Text-to-Speech Solutions deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY-RUN mode enabled - no resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_role
    create_lambda_function
    create_sample_content
    create_custom_lexicon
    test_deployment
    
    success "Deployment completed successfully!"
    
    log "Deployment Summary:"
    log "=================="
    log "S3 Bucket: $BUCKET_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "IAM Role: $IAM_ROLE_NAME"
    log "AWS Region: $AWS_REGION"
    log ""
    log "Next Steps:"
    log "1. Explore the Polly console to see available voices"
    log "2. Upload text files to S3 for batch processing"
    log "3. Test different voice options and SSML features"
    log "4. Review the sample content in your S3 bucket"
    log ""
    log "To clean up resources, run: ./destroy.sh"
}

# Trap to ensure cleanup on script exit
cleanup_on_exit() {
    if [[ -f "bucket-policy.json" ]]; then rm -f bucket-policy.json; fi
    if [[ -f "trust-policy.json" ]]; then rm -f trust-policy.json; fi
    if [[ -f "s3-policy.json" ]]; then rm -f s3-policy.json; fi
    if [[ -f "lambda_function.py" ]]; then rm -f lambda_function.py; fi
    if [[ -f "lambda_function.zip" ]]; then rm -f lambda_function.zip; fi
    if [[ -f "custom_lexicon.xml" ]]; then rm -f custom_lexicon.xml; fi
    if [[ -f "test_response.json" ]]; then rm -f test_response.json; fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"