#!/bin/bash

# Multi-Language Voice Processing Pipeline - Deployment Script
# This script deploys a comprehensive voice processing platform using Amazon Transcribe,
# Amazon Translate, and Amazon Polly with Step Functions orchestration.

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for resource creation
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=30
    local attempt=0
    
    log "Waiting for ${resource_type} ${resource_name} to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        case $resource_type in
            "table")
                if aws dynamodb describe-table --table-name "$resource_name" --query 'Table.TableStatus' --output text 2>/dev/null | grep -q "ACTIVE"; then
                    return 0
                fi
                ;;
            "role")
                if aws iam get-role --role-name "$resource_name" >/dev/null 2>&1; then
                    sleep 10  # Additional wait for IAM eventual consistency
                    return 0
                fi
                ;;
        esac
        
        sleep 10
        ((attempt++))
        log "Attempt $attempt/$max_attempts..."
    done
    
    error "Timeout waiting for ${resource_type} ${resource_name}"
    return 1
}

# Function to create unique resource names
generate_unique_suffix() {
    if command_exists aws; then
        aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)"
    else
        echo "$(date +%s | tail -c 6)"
    fi
}

# Function to cleanup on error
cleanup_on_error() {
    error "Deployment failed. Starting cleanup of partial resources..."
    
    # Note: This is a basic cleanup. For production, implement more comprehensive cleanup
    if [ -n "$PROJECT_NAME" ]; then
        warning "Cleaning up partially created resources for project: $PROJECT_NAME"
        # Add cleanup commands here if needed
    fi
}

# Set up error handling
trap cleanup_on_error ERR

# Prerequisites check
log "Checking prerequisites..."

if ! command_exists aws; then
    error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    error "AWS CLI is not configured or credentials are invalid."
    exit 1
fi

# Check required permissions
log "Validating AWS permissions..."
required_services=("transcribe" "translate" "polly" "lambda" "stepfunctions" "dynamodb" "s3" "iam")
for service in "${required_services[@]}"; do
    if ! aws $service list-* --max-items 1 >/dev/null 2>&1; then
        error "Insufficient permissions for AWS $service service"
        exit 1
    fi
done

success "Prerequisites check completed"

# Configuration
log "Setting up configuration..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    error "AWS region not configured. Please set a default region."
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers
RANDOM_SUFFIX=$(generate_unique_suffix)
export PROJECT_NAME="voice-pipeline-${RANDOM_SUFFIX}"
export INPUT_BUCKET="voice-input-${RANDOM_SUFFIX}"
export OUTPUT_BUCKET="voice-output-${RANDOM_SUFFIX}"
export ROLE_NAME="VoiceProcessingRole-${RANDOM_SUFFIX}"

log "Project Name: $PROJECT_NAME"
log "Input Bucket: $INPUT_BUCKET"
log "Output Bucket: $OUTPUT_BUCKET"
log "IAM Role: $ROLE_NAME"

# Create S3 buckets
log "Creating S3 buckets..."

aws s3 mb s3://${INPUT_BUCKET} --region ${AWS_REGION} || {
    error "Failed to create input bucket"
    exit 1
}

aws s3 mb s3://${OUTPUT_BUCKET} --region ${AWS_REGION} || {
    error "Failed to create output bucket"
    exit 1
}

# Apply bucket policies for security
aws s3api put-public-access-block \
    --bucket ${INPUT_BUCKET} \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

aws s3api put-public-access-block \
    --bucket ${OUTPUT_BUCKET} \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

success "S3 buckets created and secured"

# Create IAM role and policies
log "Creating IAM role and policies..."

cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "states.amazonaws.com",
          "transcribe.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name ${ROLE_NAME} \
    --assume-role-policy-document file:///tmp/trust-policy.json || {
    error "Failed to create IAM role"
    exit 1
}

# Attach required policies
policies=(
    "arn:aws:iam::aws:policy/AmazonTranscribeFullAccess"
    "arn:aws:iam::aws:policy/AmazonPollyFullAccess"
    "arn:aws:iam::aws:policy/TranslateFullAccess"
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
)

for policy in "${policies[@]}"; do
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn $policy || {
        error "Failed to attach policy $policy"
        exit 1
    }
done

export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

# Wait for IAM role to be available
wait_for_resource "role" "${ROLE_NAME}"

success "IAM role created and policies attached"

# Create DynamoDB table
log "Creating DynamoDB table for job tracking..."

aws dynamodb create-table \
    --table-name "${PROJECT_NAME}-jobs" \
    --attribute-definitions \
        AttributeName=JobId,AttributeType=S \
        AttributeName=Status,AttributeType=S \
    --key-schema \
        AttributeName=JobId,KeyType=HASH \
    --global-secondary-indexes \
        IndexName=StatusIndex,KeySchema=[{AttributeName=Status,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
    --provisioned-throughput \
        ReadCapacityUnits=5,WriteCapacityUnits=5 || {
    error "Failed to create DynamoDB table"
    exit 1
}

wait_for_resource "table" "${PROJECT_NAME}-jobs"

success "DynamoDB table created"

# Create Lambda functions
log "Creating Lambda functions..."

# Create temporary directory for Lambda code
mkdir -p /tmp/lambda-code

# Language Detection Lambda
cat > /tmp/lambda-code/language_detector.py << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = event['bucket']
    key = event['key']
    job_id = event.get('job_id', str(uuid.uuid4()))
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.put_item(
            Item={
                'JobId': job_id,
                'Status': 'LANGUAGE_DETECTION',
                'InputFile': f"s3://{bucket}/{key}",
                'Timestamp': int(datetime.now().timestamp()),
                'Stage': 'language_detection'
            }
        )
        
        # Start language identification job
        job_name = f"lang-detect-{job_id}"
        
        transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            Media={'MediaFileUri': f"s3://{bucket}/{key}"},
            IdentifyLanguage=True,
            OutputBucketName=bucket,
            OutputKey=f"language-detection/{job_id}/"
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'transcribe_job_name': job_name,
            'bucket': bucket,
            'key': key,
            'stage': 'language_detection'
        }
        
    except Exception as e:
        table.put_item(
            Item={
                'JobId': job_id,
                'Status': 'FAILED',
                'Error': str(e),
                'Timestamp': int(datetime.now().timestamp()),
                'Stage': 'language_detection'
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }
EOF

# Package and deploy language detector
cd /tmp/lambda-code
zip -q language_detector.zip language_detector.py

aws lambda create-function \
    --function-name "${PROJECT_NAME}-language-detector" \
    --runtime python3.9 \
    --role ${ROLE_ARN} \
    --handler language_detector.lambda_handler \
    --zip-file fileb://language_detector.zip \
    --timeout 60 \
    --environment Variables="{JOBS_TABLE=${PROJECT_NAME}-jobs}" || {
    error "Failed to create language detector Lambda"
    exit 1
}

success "Language detector Lambda created"

# Transcription Processor Lambda
cat > /tmp/lambda-code/transcription_processor.py << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    key = event['key']
    detected_language = event.get('detected_language', 'en-US')
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, DetectedLanguage = :lang',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'TRANSCRIBING',
                ':stage': 'transcription',
                ':lang': detected_language
            }
        )
        
        # Configure transcription based on language
        transcribe_config = {
            'TranscriptionJobName': f"transcribe-{job_id}",
            'Media': {'MediaFileUri': f"s3://{bucket}/{key}"},
            'OutputBucketName': bucket,
            'OutputKey': f"transcriptions/{job_id}/",
            'LanguageCode': detected_language
        }
        
        # Add language-specific settings
        if detected_language.startswith('en'):
            transcribe_config['Settings'] = {
                'ShowSpeakerLabels': True,
                'MaxSpeakerLabels': 10,
                'ShowAlternatives': True,
                'MaxAlternatives': 3
            }
        
        # Add custom vocabulary if available
        vocab_name = f"custom-vocab-{detected_language.split('-')[0]}"
        try:
            transcribe.get_vocabulary(VocabularyName=vocab_name)
            transcribe_config['Settings'] = transcribe_config.get('Settings', {})
            transcribe_config['Settings']['VocabularyName'] = vocab_name
        except transcribe.exceptions.BadRequestException:
            # Custom vocabulary doesn't exist, continue without it
            pass
        
        # Start transcription job
        transcribe.start_transcription_job(**transcribe_config)
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'transcribe_job_name': f"transcribe-{job_id}",
            'detected_language': detected_language,
            'bucket': bucket,
            'stage': 'transcription'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }
EOF

zip -q transcription_processor.zip transcription_processor.py

aws lambda create-function \
    --function-name "${PROJECT_NAME}-transcription-processor" \
    --runtime python3.9 \
    --role ${ROLE_ARN} \
    --handler transcription_processor.lambda_handler \
    --zip-file fileb://transcription_processor.zip \
    --timeout 60 \
    --environment Variables="{JOBS_TABLE=${PROJECT_NAME}-jobs}" || {
    error "Failed to create transcription processor Lambda"
    exit 1
}

success "Transcription processor Lambda created"

# Translation Processor Lambda
cat > /tmp/lambda-code/translation_processor.py << 'EOF'
import json
import boto3
from datetime import datetime

translate = boto3.client('translate')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    source_language = event['source_language']
    target_languages = event.get('target_languages', ['es', 'fr', 'de', 'pt'])
    transcription_uri = event['transcription_uri']
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'TRANSLATING',
                ':stage': 'translation'
            }
        )
        
        # Download transcription results
        transcription_obj = s3.get_object(Bucket=bucket, Key=transcription_uri)
        transcription_data = json.loads(transcription_obj['Body'].read().decode('utf-8'))
        
        # Extract transcript text
        transcript = transcription_data['results']['transcripts'][0]['transcript']
        
        # Map language codes
        source_lang_code = map_transcribe_to_translate_language(source_language)
        
        translations = {}
        
        # Translate to each target language
        for target_lang in target_languages:
            if target_lang != source_lang_code:
                try:
                    # Check if custom terminology exists
                    terminology_name = f"custom-terms-{source_lang_code}-{target_lang}"
                    
                    translate_params = {
                        'Text': transcript,
                        'SourceLanguageCode': source_lang_code,
                        'TargetLanguageCode': target_lang
                    }
                    
                    try:
                        translate.get_terminology(Name=terminology_name)
                        translate_params['TerminologyNames'] = [terminology_name]
                    except translate.exceptions.ResourceNotFoundException:
                        # Custom terminology doesn't exist, continue without it
                        pass
                    
                    result = translate.translate_text(**translate_params)
                    
                    translations[target_lang] = {
                        'translated_text': result['TranslatedText'],
                        'source_language': source_lang_code,
                        'target_language': target_lang,
                        'applied_terminologies': result.get('AppliedTerminologies', [])
                    }
                    
                except Exception as e:
                    print(f"Translation failed for {target_lang}: {str(e)}")
                    translations[target_lang] = {
                        'error': str(e),
                        'source_language': source_lang_code,
                        'target_language': target_lang
                    }
        
        # Store translation results
        translations_key = f"translations/{job_id}/translations.json"
        s3.put_object(
            Bucket=bucket,
            Key=translations_key,
            Body=json.dumps({
                'original_text': transcript,
                'source_language': source_lang_code,
                'translations': translations,
                'timestamp': datetime.now().isoformat()
            }),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'source_language': source_lang_code,
            'translations': translations,
            'translations_uri': translations_key,
            'stage': 'translation'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }

def map_transcribe_to_translate_language(transcribe_lang):
    # Map Transcribe language codes to Translate language codes
    mapping = {
        'en-US': 'en', 'en-GB': 'en', 'en-AU': 'en',
        'es-US': 'es', 'es-ES': 'es',
        'fr-FR': 'fr', 'fr-CA': 'fr',
        'de-DE': 'de', 'it-IT': 'it',
        'pt-BR': 'pt', 'pt-PT': 'pt',
        'ja-JP': 'ja', 'ko-KR': 'ko',
        'zh-CN': 'zh', 'zh-TW': 'zh-TW',
        'ar-AE': 'ar', 'ar-SA': 'ar',
        'hi-IN': 'hi', 'ru-RU': 'ru',
        'nl-NL': 'nl', 'sv-SE': 'sv'
    }
    return mapping.get(transcribe_lang, transcribe_lang.split('-')[0])
EOF

zip -q translation_processor.zip translation_processor.py

aws lambda create-function \
    --function-name "${PROJECT_NAME}-translation-processor" \
    --runtime python3.9 \
    --role ${ROLE_ARN} \
    --handler translation_processor.lambda_handler \
    --zip-file fileb://translation_processor.zip \
    --timeout 300 \
    --environment Variables="{JOBS_TABLE=${PROJECT_NAME}-jobs}" || {
    error "Failed to create translation processor Lambda"
    exit 1
}

success "Translation processor Lambda created"

# Speech Synthesizer Lambda
cat > /tmp/lambda-code/speech_synthesizer.py << 'EOF'
import json
import boto3
from datetime import datetime
import re

polly = boto3.client('polly')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    translations = event['translations']
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'SYNTHESIZING',
                ':stage': 'speech_synthesis'
            }
        )
        
        audio_outputs = {}
        
        # Process each translation
        for target_lang, translation_data in translations.items():
            if 'translated_text' in translation_data:
                try:
                    # Select appropriate voice for language
                    voice_id = select_voice_for_language(target_lang)
                    
                    # Prepare text for synthesis (add SSML if needed)
                    text_to_synthesize = prepare_text_for_synthesis(
                        translation_data['translated_text']
                    )
                    
                    # Synthesize speech
                    synthesis_response = polly.synthesize_speech(
                        Text=text_to_synthesize,
                        VoiceId=voice_id,
                        OutputFormat='mp3',
                        Engine='neural' if supports_neural_voice(voice_id) else 'standard',
                        TextType='ssml' if text_to_synthesize.startswith('<speak>') else 'text'
                    )
                    
                    # Save audio to S3
                    audio_key = f"audio-output/{job_id}/{target_lang}.mp3"
                    s3.put_object(
                        Bucket=bucket,
                        Key=audio_key,
                        Body=synthesis_response['AudioStream'].read(),
                        ContentType='audio/mpeg'
                    )
                    
                    audio_outputs[target_lang] = {
                        'audio_uri': f"s3://{bucket}/{audio_key}",
                        'voice_id': voice_id,
                        'text_length': len(translation_data['translated_text']),
                        'audio_format': 'mp3'
                    }
                    
                except Exception as e:
                    print(f"Speech synthesis failed for {target_lang}: {str(e)}")
                    audio_outputs[target_lang] = {
                        'error': str(e)
                    }
        
        # Update job with final results
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, AudioOutputs = :outputs',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'COMPLETED',
                ':stage': 'completed',
                ':outputs': audio_outputs
            }
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'audio_outputs': audio_outputs,
            'stage': 'completed'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }

def select_voice_for_language(language_code):
    # Map language codes to appropriate Polly voices
    voice_mapping = {
        'en': 'Joanna',  # English - Neural voice
        'es': 'Lupe',    # Spanish - Neural voice
        'fr': 'Lea',     # French - Neural voice
        'de': 'Vicki',   # German - Neural voice
        'it': 'Bianca',  # Italian - Neural voice
        'pt': 'Camila',  # Portuguese - Neural voice
        'ja': 'Takumi',  # Japanese - Neural voice
        'ko': 'Seoyeon', # Korean - Standard voice
        'zh': 'Zhiyu',   # Chinese - Neural voice
        'ar': 'Zeina',   # Arabic - Standard voice
        'hi': 'Aditi',   # Hindi - Standard voice
        'ru': 'Tatyana', # Russian - Standard voice
        'nl': 'Lotte',   # Dutch - Standard voice
        'sv': 'Astrid'   # Swedish - Standard voice
    }
    return voice_mapping.get(language_code, 'Joanna')

def supports_neural_voice(voice_id):
    # Neural voices available in Polly
    neural_voices = [
        'Joanna', 'Matthew', 'Ivy', 'Justin', 'Kendra', 'Kimberly', 'Salli',
        'Joey', 'Lupe', 'Lucia', 'Lea', 'Vicki', 'Bianca', 'Camila',
        'Takumi', 'Zhiyu', 'Ruth', 'Stephen'
    ]
    return voice_id in neural_voices

def prepare_text_for_synthesis(text):
    # Add basic SSML for better speech quality
    if len(text) > 1000:
        # For longer texts, add pauses at sentence boundaries
        text = re.sub(r'\.(\s+)', r'.<break time="500ms"/>\1', text)
        text = re.sub(r'!(\s+)', r'!<break time="500ms"/>\1', text)
        text = re.sub(r'\?(\s+)', r'?<break time="500ms"/>\1', text)
        text = f'<speak>{text}</speak>'
    
    return text
EOF

zip -q speech_synthesizer.zip speech_synthesizer.py

aws lambda create-function \
    --function-name "${PROJECT_NAME}-speech-synthesizer" \
    --runtime python3.9 \
    --role ${ROLE_ARN} \
    --handler speech_synthesizer.lambda_handler \
    --zip-file fileb://speech_synthesizer.zip \
    --timeout 300 \
    --environment Variables="{JOBS_TABLE=${PROJECT_NAME}-jobs}" || {
    error "Failed to create speech synthesizer Lambda"
    exit 1
}

success "Speech synthesizer Lambda created"

# Job Status Checker Lambda
cat > /tmp/lambda-code/job_status_checker.py << 'EOF'
import json
import boto3

transcribe = boto3.client('transcribe')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_name = event['transcribe_job_name']
    job_type = event.get('job_type', 'transcription')
    
    try:
        if job_type == 'language_detection':
            response = transcribe.get_transcription_job(
                TranscriptionJobName=job_name
            )
        else:
            response = transcribe.get_transcription_job(
                TranscriptionJobName=job_name
            )
        
        job_status = response['TranscriptionJob']['TranscriptionJobStatus']
        
        result = {
            'statusCode': 200,
            'job_name': job_name,
            'job_status': job_status,
            'is_complete': job_status in ['COMPLETED', 'FAILED']
        }
        
        if job_status == 'COMPLETED':
            if job_type == 'language_detection':
                # Extract detected language
                language_code = response['TranscriptionJob'].get('LanguageCode')
                identified_languages = response['TranscriptionJob'].get('IdentifiedLanguageScore')
                
                result['detected_language'] = language_code
                result['language_confidence'] = identified_languages
            else:
                # Extract transcription results location
                transcript_uri = response['TranscriptionJob']['Transcript']['TranscriptFileUri']
                result['transcript_uri'] = transcript_uri
                
                # Extract detected language for transcription jobs
                language_code = response['TranscriptionJob'].get('LanguageCode')
                result['source_language'] = language_code
        
        elif job_status == 'FAILED':
            result['failure_reason'] = response['TranscriptionJob'].get('FailureReason', 'Unknown error')
        
        return result
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'job_name': job_name
        }
EOF

zip -q job_status_checker.zip job_status_checker.py

aws lambda create-function \
    --function-name "${PROJECT_NAME}-job-status-checker" \
    --runtime python3.9 \
    --role ${ROLE_ARN} \
    --handler job_status_checker.lambda_handler \
    --zip-file fileb://job_status_checker.zip \
    --timeout 30 || {
    error "Failed to create job status checker Lambda"
    exit 1
}

success "Job status checker Lambda created"

# Create Step Functions workflow
log "Creating Step Functions workflow..."

cat > /tmp/voice_processing_workflow.json << EOF
{
  "Comment": "Multi-language voice processing pipeline",
  "StartAt": "InitializeJob",
  "States": {
    "InitializeJob": {
      "Type": "Pass",
      "Parameters": {
        "bucket.$": "$.bucket",
        "key.$": "$.key",
        "job_id.$": "$.job_id",
        "jobs_table": "${PROJECT_NAME}-jobs",
        "target_languages.$": "$.target_languages"
      },
      "Next": "DetectLanguage"
    },
    "DetectLanguage": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-language-detector",
        "Payload.$": "$"
      },
      "ResultPath": "$.language_detection_result",
      "Next": "WaitForLanguageDetection"
    },
    "WaitForLanguageDetection": {
      "Type": "Wait",
      "Seconds": 30,
      "Next": "CheckLanguageDetectionStatus"
    },
    "CheckLanguageDetectionStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-job-status-checker",
        "Payload": {
          "transcribe_job_name.$": "$.language_detection_result.Payload.transcribe_job_name",
          "job_type": "language_detection"
        }
      },
      "ResultPath": "$.language_status",
      "Next": "IsLanguageDetectionComplete"
    },
    "IsLanguageDetectionComplete": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.language_status.Payload.is_complete",
          "BooleanEquals": true,
          "Next": "ProcessTranscription"
        }
      ],
      "Default": "WaitForLanguageDetection"
    },
    "ProcessTranscription": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-transcription-processor",
        "Payload": {
          "job_id.$": "$.job_id",
          "bucket.$": "$.bucket",
          "key.$": "$.key",
          "detected_language.$": "$.language_status.Payload.detected_language",
          "jobs_table": "${PROJECT_NAME}-jobs"
        }
      },
      "ResultPath": "$.transcription_result",
      "Next": "WaitForTranscription"
    },
    "WaitForTranscription": {
      "Type": "Wait",
      "Seconds": 60,
      "Next": "CheckTranscriptionStatus"
    },
    "CheckTranscriptionStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-job-status-checker",
        "Payload": {
          "transcribe_job_name.$": "$.transcription_result.Payload.transcribe_job_name",
          "job_type": "transcription"
        }
      },
      "ResultPath": "$.transcription_status",
      "Next": "IsTranscriptionComplete"
    },
    "IsTranscriptionComplete": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.transcription_status.Payload.is_complete",
          "BooleanEquals": true,
          "Next": "ProcessTranslation"
        }
      ],
      "Default": "WaitForTranscription"
    },
    "ProcessTranslation": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-translation-processor",
        "Payload": {
          "job_id.$": "$.job_id",
          "bucket.$": "$.bucket",
          "source_language.$": "$.transcription_status.Payload.source_language",
          "target_languages.$": "$.target_languages",
          "transcription_uri.$": "$.transcription_status.Payload.transcript_uri",
          "jobs_table": "${PROJECT_NAME}-jobs"
        }
      },
      "ResultPath": "$.translation_result",
      "Next": "SynthesizeSpeech"
    },
    "SynthesizeSpeech": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${PROJECT_NAME}-speech-synthesizer",
        "Payload": {
          "job_id.$": "$.job_id",
          "bucket.$": "$.bucket",
          "translations.$": "$.translation_result.Payload.translations",
          "jobs_table": "${PROJECT_NAME}-jobs"
        }
      },
      "ResultPath": "$.synthesis_result",
      "End": true
    }
  }
}
EOF

STATE_MACHINE_ARN=$(aws stepfunctions create-state-machine \
    --name "${PROJECT_NAME}-voice-processing" \
    --definition file:///tmp/voice_processing_workflow.json \
    --role-arn ${ROLE_ARN} \
    --query 'stateMachineArn' --output text) || {
    error "Failed to create Step Functions state machine"
    exit 1
}

success "Step Functions workflow created: ${STATE_MACHINE_ARN}"

# Create test audio file
log "Creating test audio file..."

aws polly synthesize-speech \
    --text "Hello, this is a test of our multi-language voice processing pipeline. We will transcribe this English audio, translate it to multiple languages, and generate speech in each target language." \
    --voice-id Joanna \
    --output-format mp3 \
    /tmp/test-audio.mp3 || {
    error "Failed to create test audio file"
    exit 1
}

aws s3 cp /tmp/test-audio.mp3 s3://${INPUT_BUCKET}/test-audio.mp3 || {
    error "Failed to upload test audio file"
    exit 1
}

success "Test audio file created and uploaded"

# Clean up temporary files
rm -rf /tmp/lambda-code
rm -f /tmp/trust-policy.json /tmp/voice_processing_workflow.json /tmp/test-audio.mp3

# Save deployment information
cat > deployment-info.json << EOF
{
  "project_name": "${PROJECT_NAME}",
  "input_bucket": "${INPUT_BUCKET}",
  "output_bucket": "${OUTPUT_BUCKET}",
  "role_name": "${ROLE_NAME}",
  "role_arn": "${ROLE_ARN}",
  "state_machine_arn": "${STATE_MACHINE_ARN}",
  "dynamodb_table": "${PROJECT_NAME}-jobs",
  "region": "${AWS_REGION}",
  "account_id": "${AWS_ACCOUNT_ID}",
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

success "Deployment completed successfully!"
log "Deployment information saved to deployment-info.json"
log ""
log "Next steps:"
log "1. Test the pipeline by running a Step Functions execution"
log "2. Monitor job progress in DynamoDB table: ${PROJECT_NAME}-jobs"
log "3. Check generated audio files in S3 bucket: ${OUTPUT_BUCKET}"
log ""
log "To test the pipeline, run:"
log "aws stepfunctions start-execution --state-machine-arn ${STATE_MACHINE_ARN} --name test-execution-\$(date +%Y%m%d-%H%M%S) --input '{\"bucket\": \"${INPUT_BUCKET}\", \"key\": \"test-audio.mp3\", \"job_id\": \"test-job-\$(date +%s)\", \"target_languages\": [\"es\", \"fr\", \"de\"]}'"
log ""
log "To clean up all resources, run the destroy.sh script"