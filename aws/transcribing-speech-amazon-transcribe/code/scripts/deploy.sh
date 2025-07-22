#!/bin/bash

# Deploy script for Speech Recognition Applications with Amazon Transcribe
# This script deploys the complete infrastructure for the recipe

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check region
    if [ -z "$AWS_DEFAULT_REGION" ] && [ -z "$(aws configure get region)" ]; then
        error "AWS region not configured. Please set AWS_DEFAULT_REGION or configure default region."
    fi
    
    log "Prerequisites check passed ✅"
}

# Initialize environment variables
initialize_variables() {
    log "Initializing environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export BUCKET_NAME="transcribe-demo-${RANDOM_SUFFIX}"
    export VOCABULARY_NAME="custom-vocab-${RANDOM_SUFFIX}"
    export VOCABULARY_FILTER_NAME="content-filter-${RANDOM_SUFFIX}"
    export LANGUAGE_MODEL_NAME="custom-lm-${RANDOM_SUFFIX}"
    export ROLE_NAME="TranscribeServiceRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="TranscribeLambdaRole-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="transcribe-processor-${RANDOM_SUFFIX}"
    
    # Export for cleanup script
    echo "export BUCKET_NAME=\"${BUCKET_NAME}\"" > .env
    echo "export VOCABULARY_NAME=\"${VOCABULARY_NAME}\"" >> .env
    echo "export VOCABULARY_FILTER_NAME=\"${VOCABULARY_FILTER_NAME}\"" >> .env
    echo "export LANGUAGE_MODEL_NAME=\"${LANGUAGE_MODEL_NAME}\"" >> .env
    echo "export ROLE_NAME=\"${ROLE_NAME}\"" >> .env
    echo "export LAMBDA_ROLE_NAME=\"${LAMBDA_ROLE_NAME}\"" >> .env
    echo "export LAMBDA_FUNCTION_NAME=\"${LAMBDA_FUNCTION_NAME}\"" >> .env
    echo "export AWS_REGION=\"${AWS_REGION}\"" >> .env
    echo "export RANDOM_SUFFIX=\"${RANDOM_SUFFIX}\"" >> .env
    
    log "Environment variables initialized ✅"
}

# Create S3 bucket and folder structure
create_s3_infrastructure() {
    log "Creating S3 infrastructure..."
    
    # Create S3 bucket
    aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION} || error "Failed to create S3 bucket"
    
    # Create folder structure
    aws s3api put-object --bucket ${BUCKET_NAME} --key audio-input/ || error "Failed to create audio-input folder"
    aws s3api put-object --bucket ${BUCKET_NAME} --key transcription-output/ || error "Failed to create transcription-output folder"
    aws s3api put-object --bucket ${BUCKET_NAME} --key custom-vocabulary/ || error "Failed to create custom-vocabulary folder"
    aws s3api put-object --bucket ${BUCKET_NAME} --key training-data/ || error "Failed to create training-data folder"
    
    log "S3 infrastructure created ✅"
}

# Create IAM roles and policies
create_iam_resources() {
    log "Creating IAM resources..."
    
    # Create trust policy for Transcribe service
    cat > transcribe-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "transcribe.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role for Transcribe
    aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file://transcribe-trust-policy.json || error "Failed to create Transcribe IAM role"
    
    # Create policy for S3 access
    cat > transcribe-s3-policy.json << EOF
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
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-name TranscribeS3Access \
        --policy-document file://transcribe-s3-policy.json || error "Failed to attach S3 policy to Transcribe role"
    
    # Store role ARN
    export ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query Role.Arn --output text)
    echo "export ROLE_ARN=\"${ROLE_ARN}\"" >> .env
    
    log "IAM resources created ✅"
}

# Create custom vocabulary and filter
create_custom_vocabulary() {
    log "Creating custom vocabulary and filter..."
    
    # Create custom vocabulary terms file
    cat > custom-vocabulary.txt << EOF
AWS
Amazon
Transcribe
API
WebSocket
real-time
speech-to-text
transcription
diarization
vocabulary
EOF
    
    # Upload vocabulary file to S3
    aws s3 cp custom-vocabulary.txt s3://${BUCKET_NAME}/custom-vocabulary/custom-vocabulary.txt || error "Failed to upload vocabulary file"
    
    # Create custom vocabulary
    aws transcribe create-vocabulary \
        --language-code en-US \
        --vocabulary-name ${VOCABULARY_NAME} \
        --vocabulary-file-uri s3://${BUCKET_NAME}/custom-vocabulary/custom-vocabulary.txt || error "Failed to create custom vocabulary"
    
    # Create vocabulary filter terms
    cat > vocabulary-filter.txt << EOF
inappropriate
confidential
sensitive
private
EOF
    
    # Upload filter file to S3
    aws s3 cp vocabulary-filter.txt s3://${BUCKET_NAME}/custom-vocabulary/vocabulary-filter.txt || error "Failed to upload vocabulary filter file"
    
    # Create vocabulary filter
    aws transcribe create-vocabulary-filter \
        --language-code en-US \
        --vocabulary-filter-name ${VOCABULARY_FILTER_NAME} \
        --vocabulary-filter-file-uri s3://${BUCKET_NAME}/custom-vocabulary/vocabulary-filter.txt || error "Failed to create vocabulary filter"
    
    log "Custom vocabulary and filter created ✅"
}

# Wait for custom vocabulary to be ready
wait_for_vocabulary() {
    log "Waiting for custom vocabulary to be ready..."
    
    while true; do
        VOCAB_STATUS=$(aws transcribe get-vocabulary \
            --vocabulary-name ${VOCABULARY_NAME} \
            --query VocabularyState --output text)
        
        if [ "$VOCAB_STATUS" = "READY" ]; then
            log "Custom vocabulary is ready ✅"
            break
        elif [ "$VOCAB_STATUS" = "FAILED" ]; then
            error "Custom vocabulary creation failed"
        fi
        
        log "Vocabulary status: $VOCAB_STATUS (waiting 30 seconds...)"
        sleep 30
    done
}

# Create Lambda function for processing
create_lambda_function() {
    log "Creating Lambda function for transcription processing..."
    
    # Create Lambda function code
    cat > lambda-function.py << 'EOF'
import json
import boto3

def lambda_handler(event, context):
    """
    Process Amazon Transcribe results
    """
    transcribe = boto3.client('transcribe')
    s3 = boto3.client('s3')
    
    # Extract job name from event
    job_name = event.get('jobName')
    
    if not job_name:
        return {
            'statusCode': 400,
            'body': json.dumps('Job name not provided')
        }
    
    try:
        # Get transcription job details
        response = transcribe.get_transcription_job(
            TranscriptionJobName=job_name
        )
        
        job_status = response['TranscriptionJob']['TranscriptionJobStatus']
        
        if job_status == 'COMPLETED':
            transcript_uri = response['TranscriptionJob']['Transcript']['TranscriptFileUri']
            
            # Process completed job
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Transcription completed',
                    'jobName': job_name,
                    'transcriptUri': transcript_uri
                })
            }
        else:
            return {
                'statusCode': 202,
                'body': json.dumps({
                    'message': 'Transcription in progress',
                    'jobName': job_name,
                    'status': job_status
                })
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing transcription: {str(e)}')
        }
EOF
    
    # Create Lambda deployment package
    zip -q lambda-function.zip lambda-function.py || error "Failed to create Lambda deployment package"
    
    # Create Lambda execution role trust policy
    cat > lambda-trust-policy.json << EOF
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
    
    # Create Lambda role
    aws iam create-role \
        --role-name ${LAMBDA_ROLE_NAME} \
        --assume-role-policy-document file://lambda-trust-policy.json || error "Failed to create Lambda IAM role"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || error "Failed to attach basic execution policy"
    
    # Create policy for Transcribe access
    cat > lambda-transcribe-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "transcribe:GetTranscriptionJob",
                "transcribe:ListTranscriptionJobs"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach Transcribe access policy
    aws iam put-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-name TranscribeAccess \
        --policy-document file://lambda-transcribe-policy.json || error "Failed to attach Transcribe policy to Lambda role"
    
    # Get Lambda role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name ${LAMBDA_ROLE_NAME} --query Role.Arn --output text)
    echo "export LAMBDA_ROLE_ARN=\"${LAMBDA_ROLE_ARN}\"" >> .env
    
    # Wait for role to be available
    log "Waiting for Lambda role to be available..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler lambda-function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --description "Process Amazon Transcribe results" || error "Failed to create Lambda function"
    
    log "Lambda function created ✅"
}

# Create sample files and configurations
create_sample_files() {
    log "Creating sample files and configurations..."
    
    # Create sample audio metadata file
    cat > sample-audio-metadata.txt << EOF
Sample audio file for transcription testing.
This file represents a 30-second audio clip containing:
- Clear speech at normal speaking pace
- Technical terminology for custom vocabulary testing
- Multiple speakers for diarization testing
EOF
    
    # Upload metadata file
    aws s3 cp sample-audio-metadata.txt s3://${BUCKET_NAME}/audio-input/sample-audio-metadata.txt || error "Failed to upload sample metadata"
    
    # Create training data for custom language model
    cat > training-data.txt << EOF
AWS Transcribe provides automatic speech recognition capabilities.
The service supports real-time streaming transcription.
Custom vocabularies improve transcription accuracy for domain-specific terms.
Speaker diarization identifies different speakers in audio files.
Content redaction removes personally identifiable information.
Amazon Transcribe integrates with other AWS services seamlessly.
EOF
    
    # Upload training data
    aws s3 cp training-data.txt s3://${BUCKET_NAME}/training-data/training-data.txt || error "Failed to upload training data"
    
    # Create streaming configuration
    cat > streaming-config.json << EOF
{
    "LanguageCode": "en-US",
    "MediaSampleRateHertz": 44100,
    "MediaEncoding": "pcm",
    "EnablePartialResultsStabilization": true,
    "PartialResultsStability": "high",
    "VocabularyName": "${VOCABULARY_NAME}",
    "ShowSpeakerLabels": false
}
EOF
    
    # Create monitoring script
    cat > monitor-jobs.sh << 'EOF'
#!/bin/bash

# Monitor transcription jobs
echo "Monitoring active transcription jobs..."

# List all jobs
aws transcribe list-transcription-jobs \
    --status IN_PROGRESS \
    --query 'TranscriptionJobSummaries[*].{JobName:TranscriptionJobName,Status:TranscriptionJobStatus,CreationTime:CreationTime}' \
    --output table

# Check specific jobs if provided
if [ ! -z "$1" ]; then
    echo "Checking specific job: $1"
    aws transcribe get-transcription-job \
        --transcription-job-name "$1" \
        --query 'TranscriptionJob.{JobName:TranscriptionJobName,Status:TranscriptionJobStatus,Progress:JobExecutionSettings,OutputUri:Transcript.TranscriptFileUri}' \
        --output table
fi
EOF
    
    chmod +x monitor-jobs.sh
    
    log "Sample files and configurations created ✅"
}

# Create custom language model (optional)
create_custom_language_model() {
    log "Creating custom language model (this may take several hours)..."
    
    # Create custom language model (Note: This is a long-running process)
    aws transcribe create-language-model \
        --language-code en-US \
        --base-model-name WideBand \
        --model-name ${LANGUAGE_MODEL_NAME} \
        --input-data-config S3Uri="s3://${BUCKET_NAME}/training-data/",DataAccessRoleArn="${ROLE_ARN}" \
        2>/dev/null || warn "Custom language model creation may have failed or is already in progress"
    
    log "Custom language model creation initiated (this is a long-running process) ✅"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f transcribe-trust-policy.json
    rm -f transcribe-s3-policy.json
    rm -f lambda-trust-policy.json
    rm -f lambda-transcribe-policy.json
    rm -f custom-vocabulary.txt
    rm -f vocabulary-filter.txt
    rm -f training-data.txt
    rm -f lambda-function.py
    rm -f lambda-function.zip
    rm -f sample-audio-metadata.txt
    
    log "Temporary files cleaned up ✅"
}

# Display deployment summary
display_summary() {
    log "Deployment completed successfully! 🎉"
    echo
    echo -e "${BLUE}Created Resources:${NC}"
    echo "- S3 Bucket: ${BUCKET_NAME}"
    echo "- Custom Vocabulary: ${VOCABULARY_NAME}"
    echo "- Vocabulary Filter: ${VOCABULARY_FILTER_NAME}"
    echo "- Language Model: ${LANGUAGE_MODEL_NAME}"
    echo "- IAM Role: ${ROLE_NAME}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "- Lambda Role: ${LAMBDA_ROLE_NAME}"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Upload audio files to s3://${BUCKET_NAME}/audio-input/"
    echo "2. Run transcription jobs using the AWS CLI or Lambda function"
    echo "3. Use ./monitor-jobs.sh to monitor job progress"
    echo "4. Check transcription results in s3://${BUCKET_NAME}/transcription-output/"
    echo
    echo -e "${BLUE}Example Commands:${NC}"
    echo "# Monitor jobs:"
    echo "./monitor-jobs.sh"
    echo
    echo "# Test Lambda function:"
    echo "aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} --payload '{\"jobName\":\"test\"}' --cli-binary-format raw-in-base64-out response.json"
    echo
    echo -e "${YELLOW}Important:${NC} Custom vocabulary and language model creation may take time to complete."
    echo "Environment variables saved to .env file for cleanup script."
}

# Main deployment function
main() {
    log "Starting deployment of Speech Recognition Applications with Amazon Transcribe..."
    
    check_prerequisites
    initialize_variables
    create_s3_infrastructure
    create_iam_resources
    create_custom_vocabulary
    wait_for_vocabulary
    create_lambda_function
    create_sample_files
    create_custom_language_model
    cleanup_temp_files
    display_summary
    
    log "Deployment completed! ✅"
}

# Run main function
main "$@"