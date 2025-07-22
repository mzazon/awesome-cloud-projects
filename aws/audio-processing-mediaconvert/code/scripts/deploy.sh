#!/bin/bash

# Audio Processing Pipelines with AWS Elemental MediaConvert - Deployment Script
# This script deploys the complete audio processing pipeline infrastructure

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
TEMP_DIR="/tmp/audio-processing-deploy-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    cleanup_on_error
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Cleanup function for errors
cleanup_on_error() {
    warning "Cleaning up temporary files due to error..."
    rm -rf "${TEMP_DIR}"
    if [[ -n "${BUCKET_INPUT}" ]]; then
        aws s3 rm s3://${BUCKET_INPUT} --recursive --quiet 2>/dev/null || true
        aws s3 rb s3://${BUCKET_INPUT} --force --quiet 2>/dev/null || true
    fi
    if [[ -n "${BUCKET_OUTPUT}" ]]; then
        aws s3 rm s3://${BUCKET_OUTPUT} --recursive --quiet 2>/dev/null || true
        aws s3 rb s3://${BUCKET_OUTPUT} --force --quiet 2>/dev/null || true
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI not found. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up credentials."
    fi
    
    # Check required tools
    for tool in zip jq; do
        if ! command -v "${tool}" &> /dev/null; then
            error_exit "${tool} not found. Please install ${tool}."
        fi
    done
    
    success "Prerequisites check passed"
}

# Initialize environment
initialize_environment() {
    info "Initializing environment..."
    
    # Create temp directory
    mkdir -p "${TEMP_DIR}"
    cd "${TEMP_DIR}"
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export BUCKET_INPUT="audio-processing-input-${RANDOM_SUFFIX}"
    export BUCKET_OUTPUT="audio-processing-output-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION="audio-processing-trigger-${RANDOM_SUFFIX}"
    export MEDIACONVERT_ROLE="MediaConvertRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC="audio-processing-notifications-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup
    cat > "${TEMP_DIR}/environment.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_INPUT=${BUCKET_INPUT}
BUCKET_OUTPUT=${BUCKET_OUTPUT}
LAMBDA_FUNCTION=${LAMBDA_FUNCTION}
MEDIACONVERT_ROLE=${MEDIACONVERT_ROLE}
SNS_TOPIC=${SNS_TOPIC}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    info "Environment initialized for region: ${AWS_REGION}"
    info "Account ID: ${AWS_ACCOUNT_ID}"
    info "Resource suffix: ${RANDOM_SUFFIX}"
    
    success "Environment initialization completed"
}

# Create S3 buckets
create_s3_buckets() {
    info "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3api head-bucket --bucket "${BUCKET_INPUT}" 2>/dev/null; then
        warning "Input bucket ${BUCKET_INPUT} already exists"
    else
        aws s3 mb s3://${BUCKET_INPUT} --region ${AWS_REGION}
        success "Created input bucket: ${BUCKET_INPUT}"
    fi
    
    # Create output bucket
    if aws s3api head-bucket --bucket "${BUCKET_OUTPUT}" 2>/dev/null; then
        warning "Output bucket ${BUCKET_OUTPUT} already exists"
    else
        aws s3 mb s3://${BUCKET_OUTPUT} --region ${AWS_REGION}
        success "Created output bucket: ${BUCKET_OUTPUT}"
    fi
    
    # Enable versioning on buckets
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_INPUT}" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_OUTPUT}" \
        --versioning-configuration Status=Enabled
    
    success "S3 buckets created and configured"
}

# Create SNS topic
create_sns_topic() {
    info "Creating SNS topic..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name ${SNS_TOPIC} \
        --output text --query TopicArn)
    
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${TEMP_DIR}/environment.env"
    
    success "Created SNS topic: ${SNS_TOPIC_ARN}"
}

# Create IAM role for MediaConvert
create_mediaconvert_role() {
    info "Creating MediaConvert IAM role..."
    
    # Create trust policy
    cat > mediaconvert-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "mediaconvert.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create the role
    if aws iam get-role --role-name "${MEDIACONVERT_ROLE}" 2>/dev/null; then
        warning "MediaConvert role ${MEDIACONVERT_ROLE} already exists"
    else
        aws iam create-role \
            --role-name ${MEDIACONVERT_ROLE} \
            --assume-role-policy-document file://mediaconvert-trust-policy.json
    fi
    
    # Create policy
    cat > mediaconvert-policy.json << EOF
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
                "arn:aws:s3:::${BUCKET_INPUT}",
                "arn:aws:s3:::${BUCKET_INPUT}/*",
                "arn:aws:s3:::${BUCKET_OUTPUT}",
                "arn:aws:s3:::${BUCKET_OUTPUT}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name ${MEDIACONVERT_ROLE} \
        --policy-name MediaConvertS3SNSPolicy \
        --policy-document file://mediaconvert-policy.json
    
    # Get role ARN
    export MEDIACONVERT_ROLE_ARN=$(aws iam get-role \
        --role-name ${MEDIACONVERT_ROLE} \
        --query Role.Arn --output text)
    
    echo "MEDIACONVERT_ROLE_ARN=${MEDIACONVERT_ROLE_ARN}" >> "${TEMP_DIR}/environment.env"
    
    success "Created MediaConvert role: ${MEDIACONVERT_ROLE_ARN}"
}

# Get MediaConvert endpoint
get_mediaconvert_endpoint() {
    info "Getting MediaConvert endpoint..."
    
    export MEDIACONVERT_ENDPOINT=$(aws mediaconvert describe-endpoints \
        --region ${AWS_REGION} \
        --query Endpoints[0].Url --output text)
    
    echo "MEDIACONVERT_ENDPOINT=${MEDIACONVERT_ENDPOINT}" >> "${TEMP_DIR}/environment.env"
    
    success "MediaConvert endpoint: ${MEDIACONVERT_ENDPOINT}"
}

# Create MediaConvert job template
create_job_template() {
    info "Creating MediaConvert job template..."
    
    cat > audio-job-template.json << EOF
{
    "Name": "AudioProcessingTemplate-${RANDOM_SUFFIX}",
    "Description": "Template for processing audio files with multiple output formats",
    "Settings": {
        "OutputGroups": [
            {
                "Name": "MP3_Output",
                "OutputGroupSettings": {
                    "Type": "FILE_GROUP_SETTINGS",
                    "FileGroupSettings": {
                        "Destination": "s3://${BUCKET_OUTPUT}/mp3/"
                    }
                },
                "Outputs": [
                    {
                        "NameModifier": "_mp3",
                        "ContainerSettings": {
                            "Container": "MP3"
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "MP3",
                                    "Mp3Settings": {
                                        "Bitrate": 128000,
                                        "Channels": 2,
                                        "RateControlMode": "CBR",
                                        "SampleRate": 44100
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            {
                "Name": "AAC_Output",
                "OutputGroupSettings": {
                    "Type": "FILE_GROUP_SETTINGS",
                    "FileGroupSettings": {
                        "Destination": "s3://${BUCKET_OUTPUT}/aac/"
                    }
                },
                "Outputs": [
                    {
                        "NameModifier": "_aac",
                        "ContainerSettings": {
                            "Container": "MP4"
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "AAC",
                                    "AacSettings": {
                                        "Bitrate": 128000,
                                        "CodingMode": "CODING_MODE_2_0",
                                        "SampleRate": 44100
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            {
                "Name": "FLAC_Output",
                "OutputGroupSettings": {
                    "Type": "FILE_GROUP_SETTINGS",
                    "FileGroupSettings": {
                        "Destination": "s3://${BUCKET_OUTPUT}/flac/"
                    }
                },
                "Outputs": [
                    {
                        "NameModifier": "_flac",
                        "ContainerSettings": {
                            "Container": "FLAC"
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "FLAC",
                                    "FlacSettings": {
                                        "Channels": 2,
                                        "SampleRate": 44100
                                    }
                                }
                            }
                        ]
                    }
                ]
            }
        ],
        "Inputs": [
            {
                "FileInput": "s3://${BUCKET_INPUT}/",
                "AudioSelectors": {
                    "Audio Selector 1": {
                        "Tracks": [1],
                        "DefaultSelection": "DEFAULT"
                    }
                }
            }
        ]
    }
}
EOF
    
    export TEMPLATE_ARN=$(aws mediaconvert create-job-template \
        --endpoint-url ${MEDIACONVERT_ENDPOINT} \
        --cli-input-json file://audio-job-template.json \
        --query JobTemplate.Arn --output text)
    
    echo "TEMPLATE_ARN=${TEMPLATE_ARN}" >> "${TEMP_DIR}/environment.env"
    
    success "Created job template: ${TEMPLATE_ARN}"
}

# Create Lambda function
create_lambda_function() {
    info "Creating Lambda function..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    # Initialize MediaConvert client
    mediaconvert = boto3.client('mediaconvert', 
        endpoint_url=os.environ['MEDIACONVERT_ENDPOINT'])
    
    # Get S3 event information
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Only process audio files
        if not key.lower().endswith(('.mp3', '.wav', '.flac', '.m4a', '.aac')):
            print(f"Skipping non-audio file: {key}")
            continue
        
        # Create MediaConvert job
        job_settings = {
            "JobTemplate": os.environ['TEMPLATE_ARN'],
            "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
            "Settings": {
                "Inputs": [
                    {
                        "FileInput": f"s3://{bucket}/{key}",
                        "AudioSelectors": {
                            "Audio Selector 1": {
                                "Tracks": [1],
                                "DefaultSelection": "DEFAULT"
                            }
                        }
                    }
                ]
            },
            "StatusUpdateInterval": "SECONDS_60"
        }
        
        try:
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            print(f"Created MediaConvert job {job_id} for {key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Successfully started processing job {job_id}',
                    'jobId': job_id
                })
            }
        except Exception as e:
            print(f"Error creating MediaConvert job: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': str(e)
                })
            }
EOF
    
    # Create deployment package
    zip lambda-function.zip lambda_function.py
    
    # Create Lambda trust policy
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
    if aws iam get-role --role-name "${LAMBDA_FUNCTION}-role" 2>/dev/null; then
        warning "Lambda role ${LAMBDA_FUNCTION}-role already exists"
    else
        aws iam create-role \
            --role-name ${LAMBDA_FUNCTION}-role \
            --assume-role-policy-document file://lambda-trust-policy.json
    fi
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name ${LAMBDA_FUNCTION}-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create MediaConvert access policy
    cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mediaconvert:CreateJob",
                "mediaconvert:GetJob",
                "mediaconvert:ListJobs"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": "${MEDIACONVERT_ROLE_ARN}"
        }
    ]
}
EOF
    
    # Attach MediaConvert policy
    aws iam put-role-policy \
        --role-name ${LAMBDA_FUNCTION}-role \
        --policy-name MediaConvertAccess \
        --policy-document file://lambda-policy.json
    
    # Get Lambda role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name ${LAMBDA_FUNCTION}-role \
        --query Role.Arn --output text)
    
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> "${TEMP_DIR}/environment.env"
    
    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    sleep 10
    
    # Create Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION}" 2>/dev/null; then
        warning "Lambda function ${LAMBDA_FUNCTION} already exists"
    else
        aws lambda create-function \
            --function-name ${LAMBDA_FUNCTION} \
            --runtime python3.9 \
            --role ${LAMBDA_ROLE_ARN} \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 300 \
            --environment Variables="{MEDIACONVERT_ENDPOINT=${MEDIACONVERT_ENDPOINT},TEMPLATE_ARN=${TEMPLATE_ARN},MEDIACONVERT_ROLE_ARN=${MEDIACONVERT_ROLE_ARN}}"
    fi
    
    success "Created Lambda function: ${LAMBDA_FUNCTION}"
}

# Configure S3 event notifications
configure_s3_events() {
    info "Configuring S3 event notifications..."
    
    # Add Lambda permission for S3
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION} \
        --principal s3.amazonaws.com \
        --statement-id s3-trigger \
        --action lambda:InvokeFunction \
        --source-arn arn:aws:s3:::${BUCKET_INPUT} 2>/dev/null || true
    
    # Create S3 notification configuration
    cat > s3-notification.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "AudioProcessingTrigger",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".mp3"
                        }
                    ]
                }
            }
        },
        {
            "Id": "AudioProcessingTriggerWAV",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".wav"
                        }
                    ]
                }
            }
        },
        {
            "Id": "AudioProcessingTriggerFLAC",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".flac"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Apply notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket ${BUCKET_INPUT} \
        --notification-configuration file://s3-notification.json
    
    success "Configured S3 event notifications"
}

# Create CloudWatch dashboard
create_monitoring() {
    info "Creating CloudWatch dashboard..."
    
    cat > dashboard.json << EOF
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
                    [ "AWS/MediaConvert", "JobsCompleted" ],
                    [ ".", "JobsErrored" ],
                    [ ".", "JobsSubmitted" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "MediaConvert Jobs"
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
                    [ "AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_FUNCTION}" ],
                    [ ".", "Errors", ".", "." ],
                    [ ".", "Duration", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Lambda Function Metrics"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "AudioProcessingPipeline-${RANDOM_SUFFIX}" \
        --dashboard-body file://dashboard.json
    
    success "Created CloudWatch dashboard: AudioProcessingPipeline-${RANDOM_SUFFIX}"
}

# Create enhanced audio preset
create_enhanced_preset() {
    info "Creating enhanced audio preset..."
    
    cat > enhanced-audio-preset.json << EOF
{
    "Name": "EnhancedAudioPreset-${RANDOM_SUFFIX}",
    "Description": "Preset for enhanced audio processing with noise reduction",
    "Settings": {
        "ContainerSettings": {
            "Container": "MP4"
        },
        "AudioDescriptions": [
            {
                "AudioTypeControl": "FOLLOW_INPUT",
                "CodecSettings": {
                    "Codec": "AAC",
                    "AacSettings": {
                        "Bitrate": 192000,
                        "CodingMode": "CODING_MODE_2_0",
                        "SampleRate": 48000,
                        "Specification": "MPEG4"
                    }
                },
                "AudioNormalizationSettings": {
                    "Algorithm": "ITU_BS_1770_2",
                    "AlgorithmControl": "CORRECT_AUDIO",
                    "LoudnessLogging": "LOG",
                    "PeakCalculation": "TRUE_PEAK",
                    "TargetLkfs": -23.0
                }
            }
        ]
    }
}
EOF
    
    export PRESET_ARN=$(aws mediaconvert create-preset \
        --endpoint-url ${MEDIACONVERT_ENDPOINT} \
        --cli-input-json file://enhanced-audio-preset.json \
        --query Preset.Arn --output text)
    
    echo "PRESET_ARN=${PRESET_ARN}" >> "${TEMP_DIR}/environment.env"
    
    success "Created enhanced audio preset: ${PRESET_ARN}"
}

# Main deployment function
main() {
    log "Starting Audio Processing Pipeline Deployment"
    log "Timestamp: $(date)"
    log "Script: ${0}"
    log "Log file: ${LOG_FILE}"
    
    # Execute deployment steps
    check_prerequisites
    initialize_environment
    create_s3_buckets
    create_sns_topic
    create_mediaconvert_role
    get_mediaconvert_endpoint
    create_job_template
    create_lambda_function
    configure_s3_events
    create_monitoring
    create_enhanced_preset
    
    # Copy environment file to scripts directory for cleanup
    cp "${TEMP_DIR}/environment.env" "${SCRIPT_DIR}/deploy_environment.env"
    
    # Final success message
    log ""
    success "🎉 Audio Processing Pipeline Deployment Completed Successfully!"
    log ""
    log "Resource Summary:"
    log "- Input S3 Bucket: ${BUCKET_INPUT}"
    log "- Output S3 Bucket: ${BUCKET_OUTPUT}"
    log "- Lambda Function: ${LAMBDA_FUNCTION}"
    log "- MediaConvert Role: ${MEDIACONVERT_ROLE}"
    log "- SNS Topic: ${SNS_TOPIC}"
    log "- CloudWatch Dashboard: AudioProcessingPipeline-${RANDOM_SUFFIX}"
    log ""
    log "To test the pipeline:"
    log "1. Upload an audio file (.mp3, .wav, .flac) to: s3://${BUCKET_INPUT}/"
    log "2. Monitor processing in CloudWatch dashboard"
    log "3. Check processed files in: s3://${BUCKET_OUTPUT}/"
    log ""
    log "Environment saved to: ${SCRIPT_DIR}/deploy_environment.env"
    log "Log file location: ${LOG_FILE}"
    
    # Cleanup temp directory
    rm -rf "${TEMP_DIR}"
}

# Execute main function
main "$@"