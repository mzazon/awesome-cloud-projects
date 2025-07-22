#!/bin/bash

# AWS Video Processing Workflows Deployment Script
# This script deploys the complete video processing pipeline using S3, Lambda, and MediaConvert

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI configuration
validate_aws_cli() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi

    # Check if region is set
    if [ -z "$(aws configure get region)" ]; then
        error "AWS region not configured. Please set a region with 'aws configure set region <region>'"
        exit 1
    fi
}

# Function to check required AWS permissions
check_permissions() {
    log "Checking AWS permissions..."
    
    # Check S3 permissions
    if ! aws s3 ls >/dev/null 2>&1; then
        error "Insufficient S3 permissions. Please ensure you have S3 access."
        exit 1
    fi

    # Check Lambda permissions
    if ! aws lambda list-functions >/dev/null 2>&1; then
        error "Insufficient Lambda permissions. Please ensure you have Lambda access."
        exit 1
    fi

    # Check MediaConvert permissions
    if ! aws mediaconvert describe-endpoints >/dev/null 2>&1; then
        error "Insufficient MediaConvert permissions. Please ensure you have MediaConvert access."
        exit 1
    fi

    # Check IAM permissions
    if ! aws iam list-roles >/dev/null 2>&1; then
        error "Insufficient IAM permissions. Please ensure you have IAM access."
        exit 1
    fi

    log "✅ All required permissions validated"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

    export S3_SOURCE_BUCKET="video-source-${RANDOM_SUFFIX}"
    export S3_OUTPUT_BUCKET="video-output-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="video-processor-${RANDOM_SUFFIX}"
    export MEDIACONVERT_ROLE_NAME="MediaConvertRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="LambdaVideoProcessorRole-${RANDOM_SUFFIX}"
    export COMPLETION_HANDLER_NAME="completion-handler-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="MediaConvert-JobComplete-${RANDOM_SUFFIX}"

    # Store variables for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
S3_SOURCE_BUCKET=${S3_SOURCE_BUCKET}
S3_OUTPUT_BUCKET=${S3_OUTPUT_BUCKET}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
MEDIACONVERT_ROLE_NAME=${MEDIACONVERT_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
COMPLETION_HANDLER_NAME=${COMPLETION_HANDLER_NAME}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF

    log "✅ Environment variables configured"
    info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create source bucket
    if aws s3api head-bucket --bucket "${S3_SOURCE_BUCKET}" 2>/dev/null; then
        warn "Source bucket ${S3_SOURCE_BUCKET} already exists"
    else
        aws s3 mb "s3://${S3_SOURCE_BUCKET}" --region "${AWS_REGION}"
        log "✅ Created source bucket: ${S3_SOURCE_BUCKET}"
    fi

    # Create output bucket
    if aws s3api head-bucket --bucket "${S3_OUTPUT_BUCKET}" 2>/dev/null; then
        warn "Output bucket ${S3_OUTPUT_BUCKET} already exists"
    else
        aws s3 mb "s3://${S3_OUTPUT_BUCKET}" --region "${AWS_REGION}"
        log "✅ Created output bucket: ${S3_OUTPUT_BUCKET}"
    fi

    # Enable versioning on buckets
    aws s3api put-bucket-versioning \
        --bucket "${S3_SOURCE_BUCKET}" \
        --versioning-configuration Status=Enabled

    aws s3api put-bucket-versioning \
        --bucket "${S3_OUTPUT_BUCKET}" \
        --versioning-configuration Status=Enabled

    log "✅ S3 buckets created and configured"
}

# Function to create IAM role for MediaConvert
create_mediaconvert_role() {
    log "Creating IAM role for MediaConvert..."
    
    # Create trust policy for MediaConvert
    cat > /tmp/mediaconvert-trust-policy.json << EOF
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

    # Check if role already exists
    if aws iam get-role --role-name "${MEDIACONVERT_ROLE_NAME}" >/dev/null 2>&1; then
        warn "MediaConvert role ${MEDIACONVERT_ROLE_NAME} already exists"
    else
        # Create MediaConvert role
        aws iam create-role \
            --role-name "${MEDIACONVERT_ROLE_NAME}" \
            --assume-role-policy-document file:///tmp/mediaconvert-trust-policy.json

        # Wait for role to be created
        aws iam wait role-exists --role-name "${MEDIACONVERT_ROLE_NAME}"
        
        log "✅ Created MediaConvert role: ${MEDIACONVERT_ROLE_NAME}"
    fi

    # Attach required policies
    aws iam attach-role-policy \
        --role-name "${MEDIACONVERT_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

    aws iam attach-role-policy \
        --role-name "${MEDIACONVERT_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

    export MEDIACONVERT_ROLE_ARN=$(aws iam get-role \
        --role-name "${MEDIACONVERT_ROLE_NAME}" \
        --query Role.Arn --output text)

    log "✅ MediaConvert role configured with ARN: ${MEDIACONVERT_ROLE_ARN}"
}

# Function to create IAM role for Lambda
create_lambda_role() {
    log "Creating IAM role for Lambda..."
    
    # Create trust policy for Lambda
    cat > /tmp/lambda-trust-policy.json << EOF
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

    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        warn "Lambda role ${LAMBDA_ROLE_NAME} already exists"
    else
        # Create Lambda role
        aws iam create-role \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json

        # Wait for role to be created
        aws iam wait role-exists --role-name "${LAMBDA_ROLE_NAME}"
        
        log "✅ Created Lambda role: ${LAMBDA_ROLE_NAME}"
    fi

    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Create custom policy for MediaConvert and S3 access
    cat > /tmp/lambda-permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "mediaconvert:*",
        "s3:GetObject",
        "s3:PutObject",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Create and attach the custom policy
    LAMBDA_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaMediaConvertPolicy-${RANDOM_SUFFIX}"
    
    if aws iam get-policy --policy-arn "${LAMBDA_POLICY_ARN}" >/dev/null 2>&1; then
        warn "Lambda policy already exists"
    else
        aws iam create-policy \
            --policy-name "LambdaMediaConvertPolicy-${RANDOM_SUFFIX}" \
            --policy-document file:///tmp/lambda-permissions-policy.json
        
        log "✅ Created Lambda custom policy"
    fi

    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn "${LAMBDA_POLICY_ARN}"

    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --query Role.Arn --output text)

    log "✅ Lambda role configured with ARN: ${LAMBDA_ROLE_ARN}"
}

# Function to get MediaConvert endpoint
get_mediaconvert_endpoint() {
    log "Getting MediaConvert endpoint..."
    
    export MEDIACONVERT_ENDPOINT=$(aws mediaconvert describe-endpoints \
        --query Endpoints[0].Url --output text)
    
    log "✅ MediaConvert endpoint: ${MEDIACONVERT_ENDPOINT}"
}

# Function to create Lambda function for video processing
create_lambda_function() {
    log "Creating Lambda function for video processing..."
    
    # Create Lambda function code
    cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import urllib.parse
import os

def lambda_handler(event, context):
    # Initialize MediaConvert client
    mediaconvert = boto3.client('mediaconvert', 
        endpoint_url=os.environ['MEDIACONVERT_ENDPOINT'])
    
    # Parse S3 event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        # Skip if not a video file
        if not key.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.m4v')):
            continue
        
        # Create job settings
        job_settings = {
            "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
            "Settings": {
                "Inputs": [{
                    "AudioSelectors": {
                        "Audio Selector 1": {
                            "Offset": 0,
                            "DefaultSelection": "DEFAULT",
                            "ProgramSelection": 1
                        }
                    },
                    "VideoSelector": {
                        "ColorSpace": "FOLLOW"
                    },
                    "FilterEnable": "AUTO",
                    "PsiControl": "USE_PSI",
                    "FilterStrength": 0,
                    "DeblockFilter": "DISABLED",
                    "DenoiseFilter": "DISABLED",
                    "TimecodeSource": "EMBEDDED",
                    "FileInput": f"s3://{bucket}/{key}"
                }],
                "OutputGroups": [
                    {
                        "Name": "Apple HLS",
                        "OutputGroupSettings": {
                            "Type": "HLS_GROUP_SETTINGS",
                            "HlsGroupSettings": {
                                "ManifestDurationFormat": "INTEGER",
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/hls/{key.split('.')[0]}/",
                                "TimedMetadataId3Frame": "PRIV",
                                "CodecSpecification": "RFC_4281",
                                "OutputSelection": "MANIFESTS_AND_SEGMENTS",
                                "ProgramDateTimePeriod": 600,
                                "MinSegmentLength": 0,
                                "DirectoryStructure": "SINGLE_DIRECTORY",
                                "ProgramDateTime": "EXCLUDE",
                                "SegmentLength": 10,
                                "ManifestCompression": "NONE",
                                "ClientCache": "ENABLED",
                                "AudioOnlyHeader": "INCLUDE"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "ScalingBehavior": "DEFAULT",
                                    "TimecodeInsertion": "DISABLED",
                                    "AntiAlias": "ENABLED",
                                    "Sharpness": 50,
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "InterlaceMode": "PROGRESSIVE",
                                            "NumberReferenceFrames": 3,
                                            "Syntax": "DEFAULT",
                                            "Softness": 0,
                                            "GopClosedCadence": 1,
                                            "GopSize": 90,
                                            "Slices": 1,
                                            "GopBReference": "DISABLED",
                                            "SlowPal": "DISABLED",
                                            "SpatialAdaptiveQuantization": "ENABLED",
                                            "TemporalAdaptiveQuantization": "ENABLED",
                                            "FlickerAdaptiveQuantization": "DISABLED",
                                            "EntropyEncoding": "CABAC",
                                            "Bitrate": 2000000,
                                            "FramerateControl": "SPECIFIED",
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "Telecine": "NONE",
                                            "MinIInterval": 0,
                                            "AdaptiveQuantization": "HIGH",
                                            "CodecLevel": "AUTO",
                                            "FieldEncoding": "PAFF",
                                            "SceneChangeDetect": "ENABLED",
                                            "QualityTuningLevel": "SINGLE_PASS",
                                            "FramerateConversionAlgorithm": "DUPLICATE_DROP",
                                            "UnregisteredSeiTimecode": "DISABLED",
                                            "GopSizeUnits": "FRAMES",
                                            "ParControl": "SPECIFIED",
                                            "NumberBFramesBetweenReferenceFrames": 2,
                                            "RepeatPps": "DISABLED",
                                            "FramerateNumerator": 30,
                                            "FramerateDenominator": 1,
                                            "ParNumerator": 1,
                                            "ParDenominator": 1
                                        }
                                    },
                                    "AfdSignaling": "NONE",
                                    "DropFrameTimecode": "ENABLED",
                                    "RespondToAfd": "NONE",
                                    "ColorMetadata": "INSERT",
                                    "Width": 1280,
                                    "Height": 720
                                },
                                "AudioDescriptions": [
                                    {
                                        "AudioTypeControl": "FOLLOW_INPUT",
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "AudioDescriptionBroadcasterMix": "NORMAL",
                                                "Bitrate": 96000,
                                                "RateControlMode": "CBR",
                                                "CodecProfile": "LC",
                                                "CodingMode": "CODING_MODE_2_0",
                                                "RawFormat": "NONE",
                                                "SampleRate": 48000,
                                                "Specification": "MPEG4"
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1",
                                        "LanguageCodeControl": "FOLLOW_INPUT"
                                    }
                                ],
                                "OutputSettings": {
                                    "HlsSettings": {
                                        "AudioGroupId": "program_audio",
                                        "AudioTrackType": "ALTERNATE_AUDIO_AUTO_SELECT_DEFAULT",
                                        "IFrameOnlyManifest": "EXCLUDE"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    },
                    {
                        "Name": "File Group",
                        "OutputGroupSettings": {
                            "Type": "FILE_GROUP_SETTINGS",
                            "FileGroupSettings": {
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/mp4/"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "Width": 1280,
                                    "Height": 720,
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "Bitrate": 2000000,
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "GopSize": 90,
                                            "FramerateControl": "SPECIFIED",
                                            "FramerateNumerator": 30,
                                            "FramerateDenominator": 1
                                        }
                                    }
                                },
                                "AudioDescriptions": [
                                    {
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "Bitrate": 96000,
                                                "SampleRate": 48000
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1"
                                    }
                                ],
                                "ContainerSettings": {
                                    "Container": "MP4",
                                    "Mp4Settings": {
                                        "CslgAtom": "INCLUDE",
                                        "FreeSpaceBox": "EXCLUDE",
                                        "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    }
                ]
            }
        }
        
        # Create MediaConvert job
        try:
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            print(f"Created MediaConvert job: {job_id} for {key}")
            
        except Exception as e:
            print(f"Error creating MediaConvert job: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Video processing initiated successfully')
    }
EOF

    # Create deployment package
    cd /tmp && zip lambda-function.zip lambda_function.py
    
    # Wait for IAM role to be available
    sleep 10
    
    # Check if function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        warn "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating..."
        
        # Update function code
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip
        
        # Update function configuration
        aws lambda update-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --environment Variables="{MEDIACONVERT_ENDPOINT=${MEDIACONVERT_ENDPOINT},MEDIACONVERT_ROLE_ARN=${MEDIACONVERT_ROLE_ARN},S3_OUTPUT_BUCKET=${S3_OUTPUT_BUCKET}}"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 60 \
            --environment Variables="{MEDIACONVERT_ENDPOINT=${MEDIACONVERT_ENDPOINT},MEDIACONVERT_ROLE_ARN=${MEDIACONVERT_ROLE_ARN},S3_OUTPUT_BUCKET=${S3_OUTPUT_BUCKET}}"
    fi

    log "✅ Created Lambda function: ${LAMBDA_FUNCTION_NAME}"
}

# Function to create completion handler Lambda
create_completion_handler() {
    log "Creating completion handler Lambda function..."
    
    # Create completion handler code
    cat > /tmp/completion_handler.py << 'EOF'
import json
import boto3

def lambda_handler(event, context):
    print(f"MediaConvert job completed: {json.dumps(event)}")
    
    # Extract job details
    job_id = event['detail']['jobId']
    status = event['detail']['status']
    
    # Here you can add additional processing logic:
    # - Send notifications
    # - Update database records
    # - Trigger additional workflows
    
    print(f"Job {job_id} completed with status: {status}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Job completion handled successfully')
    }
EOF

    # Create deployment package
    cd /tmp && zip completion-handler.zip completion_handler.py
    
    # Check if function already exists
    if aws lambda get-function --function-name "${COMPLETION_HANDLER_NAME}" >/dev/null 2>&1; then
        warn "Completion handler ${COMPLETION_HANDLER_NAME} already exists, updating..."
        
        aws lambda update-function-code \
            --function-name "${COMPLETION_HANDLER_NAME}" \
            --zip-file fileb://completion-handler.zip
    else
        # Create completion handler Lambda function
        aws lambda create-function \
            --function-name "${COMPLETION_HANDLER_NAME}" \
            --runtime python3.9 \
            --role "${LAMBDA_ROLE_ARN}" \
            --handler completion_handler.lambda_handler \
            --zip-file fileb://completion-handler.zip \
            --timeout 30
    fi

    log "✅ Created completion handler: ${COMPLETION_HANDLER_NAME}"
}

# Function to configure S3 event notification
configure_s3_notification() {
    log "Configuring S3 event notification..."
    
    # Add Lambda invoke permission for S3
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id s3-trigger-${RANDOM_SUFFIX} \
        --action lambda:InvokeFunction \
        --principal s3.amazonaws.com \
        --source-arn "arn:aws:s3:::${S3_SOURCE_BUCKET}" 2>/dev/null || warn "Permission already exists"

    # Create S3 event notification configuration
    cat > /tmp/s3-notification.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "video-processing-trigger",
      "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".mp4"
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
        --bucket "${S3_SOURCE_BUCKET}" \
        --notification-configuration file:///tmp/s3-notification.json

    log "✅ Configured S3 event notification"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for job completion..."
    
    # Create EventBridge rule for MediaConvert job completion
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --event-pattern '{
          "source": ["aws.mediaconvert"],
          "detail-type": ["MediaConvert Job State Change"],
          "detail": {
            "status": ["COMPLETE"]
          }
        }' >/dev/null

    # Add EventBridge target
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${COMPLETION_HANDLER_NAME}"

    # Add permission for EventBridge to invoke Lambda
    aws lambda add-permission \
        --function-name "${COMPLETION_HANDLER_NAME}" \
        --statement-id eventbridge-trigger-${RANDOM_SUFFIX} \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" 2>/dev/null || warn "Permission already exists"

    log "✅ Created EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution for content delivery..."
    
    # Create CloudFront distribution configuration
    cat > /tmp/cloudfront-distribution.json << EOF
{
  "CallerReference": "video-distribution-${RANDOM_SUFFIX}",
  "Aliases": {
    "Quantity": 0
  },
  "Comment": "Video streaming distribution",
  "Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-${S3_OUTPUT_BUCKET}",
        "DomainName": "${S3_OUTPUT_BUCKET}.s3.amazonaws.com",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-${S3_OUTPUT_BUCKET}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    },
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {
        "Forward": "none"
      }
    },
    "TrustedSigners": {
      "Enabled": false,
      "Quantity": 0
    },
    "MinTTL": 0
  },
  "PriceClass": "PriceClass_100"
}
EOF

    # Create CloudFront distribution
    DISTRIBUTION_INFO=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/cloudfront-distribution.json \
        --query 'Distribution.{Id:Id,DomainName:DomainName}' \
        --output json)

    DISTRIBUTION_ID=$(echo $DISTRIBUTION_INFO | jq -r '.Id')
    DISTRIBUTION_DOMAIN=$(echo $DISTRIBUTION_INFO | jq -r '.DomainName')

    # Store distribution info for cleanup
    echo "DISTRIBUTION_ID=${DISTRIBUTION_ID}" >> .env

    log "✅ Created CloudFront distribution: ${DISTRIBUTION_ID}"
    info "Distribution domain: ${DISTRIBUTION_DOMAIN}"
}

# Function to test the deployment
test_deployment() {
    log "Testing deployment..."
    
    # Create a simple test video (this would normally be a real video file)
    info "Note: In a real deployment, you would upload an actual video file for testing"
    
    # Display deployment summary
    log "Deployment Summary:"
    info "Source Bucket: ${S3_SOURCE_BUCKET}"
    info "Output Bucket: ${S3_OUTPUT_BUCKET}"
    info "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    info "Completion Handler: ${COMPLETION_HANDLER_NAME}"
    info "EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    info "MediaConvert Endpoint: ${MEDIACONVERT_ENDPOINT}"
    
    log "✅ Deployment testing completed"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f /tmp/mediaconvert-trust-policy.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-permissions-policy.json
    rm -f /tmp/lambda_function.py
    rm -f /tmp/completion_handler.py
    rm -f /tmp/lambda-function.zip
    rm -f /tmp/completion-handler.zip
    rm -f /tmp/s3-notification.json
    rm -f /tmp/cloudfront-distribution.json
    
    log "✅ Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting AWS Video Processing Workflows deployment..."
    
    # Check prerequisites
    validate_aws_cli
    check_permissions
    
    # Setup environment
    setup_environment
    
    # Create infrastructure
    create_s3_buckets
    create_mediaconvert_role
    create_lambda_role
    get_mediaconvert_endpoint
    create_lambda_function
    create_completion_handler
    configure_s3_notification
    create_eventbridge_rule
    create_cloudfront_distribution
    
    # Test deployment
    test_deployment
    
    # Cleanup
    cleanup_temp_files
    
    log "🎉 Deployment completed successfully!"
    log "Environment configuration saved to .env file"
    log "To test the pipeline, upload a video file to: s3://${S3_SOURCE_BUCKET}/"
    log "Processed videos will be available in: s3://${S3_OUTPUT_BUCKET}/"
}

# Handle script interruption
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"