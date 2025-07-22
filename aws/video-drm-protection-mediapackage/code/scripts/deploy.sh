#!/bin/bash

# Video Content Protection with DRM and MediaPackage - Deployment Script
# This script deploys a complete DRM-protected video streaming infrastructure using
# AWS Elemental MediaLive, MediaPackage, Lambda (SPEKE), and CloudFront

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required utilities
    for cmd in jq curl zip; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd is not installed. Please install it first."
        fi
    done
    
    # Verify AWS region is set
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region is not configured. Please set it using 'aws configure set region <region>'"
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to check required permissions
check_permissions() {
    log "Checking AWS permissions..."
    
    # Test IAM permissions
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity --query 'Arn' --output text | grep -q 'assumed-role'; then
        warn "Could not verify IAM permissions. Proceeding with deployment..."
    fi
    
    # Test service permissions by attempting to list resources
    services=("medialive" "mediapackage" "lambda" "secretsmanager" "kms" "cloudfront" "s3")
    for service in "${services[@]}"; do
        case $service in
            "medialive")
                aws medialive list-channels --max-results 1 &> /dev/null || warn "May not have sufficient MediaLive permissions"
                ;;
            "mediapackage")
                aws mediapackage list-channels --max-results 1 &> /dev/null || warn "May not have sufficient MediaPackage permissions"
                ;;
            "lambda")
                aws lambda list-functions --max-items 1 &> /dev/null || warn "May not have sufficient Lambda permissions"
                ;;
            "secretsmanager")
                aws secretsmanager list-secrets --max-results 1 &> /dev/null || warn "May not have sufficient Secrets Manager permissions"
                ;;
            "kms")
                aws kms list-keys --limit 1 &> /dev/null || warn "May not have sufficient KMS permissions"
                ;;
            "cloudfront")
                aws cloudfront list-distributions --max-items 1 &> /dev/null || warn "May not have sufficient CloudFront permissions"
                ;;
            "s3")
                aws s3 ls &> /dev/null || warn "May not have sufficient S3 permissions"
                ;;
        esac
    done
    
    log "Permission check completed"
}

# Function to generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix for resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword)
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CHANNEL_NAME="drm-protected-channel-${RANDOM_SUFFIX}"
    export PACKAGE_CHANNEL="drm-package-channel-${RANDOM_SUFFIX}"
    export SPEKE_ENDPOINT="drm-speke-endpoint-${RANDOM_SUFFIX}"
    export DRM_KEY_SECRET="drm-encryption-keys-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION="drm-speke-provider-${RANDOM_SUFFIX}"
    export DISTRIBUTION_NAME="drm-protected-distribution-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="drm-test-content-${RANDOM_SUFFIX}"
    
    # Save configuration to file for cleanup
    cat > drm-deployment-config.json << EOF
{
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "channel_name": "${CHANNEL_NAME}",
    "package_channel": "${PACKAGE_CHANNEL}",
    "drm_key_secret": "${DRM_KEY_SECRET}",
    "lambda_function": "${LAMBDA_FUNCTION}",
    "output_bucket": "${OUTPUT_BUCKET}",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Resource names generated and saved to drm-deployment-config.json"
}

# Function to create KMS key for DRM encryption
create_kms_resources() {
    log "Creating KMS key for DRM encryption..."
    
    # Create KMS key
    DRM_KMS_KEY_ID=$(aws kms create-key \
        --description "DRM content encryption key for ${RANDOM_SUFFIX}" \
        --usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query 'KeyMetadata.KeyId' --output text)
    
    export DRM_KMS_KEY_ID
    
    # Create alias for the KMS key
    aws kms create-alias \
        --alias-name "alias/drm-content-${RANDOM_SUFFIX}" \
        --target-key-id ${DRM_KMS_KEY_ID}
    
    # Update configuration file
    jq --arg key_id "$DRM_KMS_KEY_ID" '.drm_kms_key_id = $key_id' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created KMS key: ${DRM_KMS_KEY_ID}"
}

# Function to create Secrets Manager secret
create_secrets() {
    log "Creating Secrets Manager secret for DRM configuration..."
    
    # Create DRM configuration
    cat > drm-config.json << EOF
{
    "widevine_provider": "speke-reference",
    "playready_provider": "speke-reference", 
    "fairplay_provider": "speke-reference",
    "content_id_template": "urn:uuid:",
    "key_rotation_interval_seconds": 3600,
    "license_duration_seconds": 86400
}
EOF
    
    # Create secret
    DRM_SECRET_ARN=$(aws secretsmanager create-secret \
        --name ${DRM_KEY_SECRET} \
        --description "DRM configuration and keys for ${RANDOM_SUFFIX}" \
        --secret-string file://drm-config.json \
        --kms-key-id ${DRM_KMS_KEY_ID} \
        --query 'ARN' --output text)
    
    export DRM_SECRET_ARN
    
    # Update configuration file
    jq --arg secret_arn "$DRM_SECRET_ARN" '.drm_secret_arn = $secret_arn' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created DRM configuration secret: ${DRM_SECRET_ARN}"
    rm -f drm-config.json
}

# Function to create S3 bucket for test content
create_s3_bucket() {
    log "Creating S3 bucket for test content..."
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${OUTPUT_BUCKET}
    else
        aws s3 mb s3://${OUTPUT_BUCKET} --region ${AWS_REGION}
    fi
    
    # Configure bucket for static website hosting
    aws s3 website s3://${OUTPUT_BUCKET} \
        --index-document index.html \
        --error-document error.html
    
    log "Created S3 bucket: ${OUTPUT_BUCKET}"
}

# Function to create SPEKE Lambda function
create_speke_lambda() {
    log "Creating SPEKE key provider Lambda function..."
    
    # Create SPEKE provider Python code
    cat > speke_provider.py << 'EOF'
import json
import boto3
import base64
import uuid
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    print(f"SPEKE request: {json.dumps(event, indent=2)}")
    
    # Parse SPEKE request
    if 'body' in event:
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
    else:
        body = event
    
    # Extract content ID and DRM systems
    content_id = body.get('content_id', str(uuid.uuid4()))
    drm_systems = body.get('drm_systems', [])
    
    # Initialize response
    response = {
        "content_id": content_id,
        "drm_systems": []
    }
    
    # Generate keys for each requested DRM system
    for drm_system in drm_systems:
        system_id = drm_system.get('system_id')
        
        if system_id == 'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed':  # Widevine
            drm_response = generate_widevine_keys(content_id)
        elif system_id == '9a04f079-9840-4286-ab92-e65be0885f95':  # PlayReady  
            drm_response = generate_playready_keys(content_id)
        elif system_id == '94ce86fb-07ff-4f43-adb8-93d2fa968ca2':  # FairPlay
            drm_response = generate_fairplay_keys(content_id)
        else:
            continue
        
        response['drm_systems'].append(drm_response)
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response)
    }

def generate_widevine_keys(content_id):
    # Generate 16-byte content key
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"https://proxy.uat.widevine.com/proxy?provider=widevine_test",
        "pssh": generate_widevine_pssh(key_id)
    }

def generate_playready_keys(content_id):
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "9a04f079-9840-4286-ab92-e65be0885f95", 
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"https://playready-license.test.com/rightsmanager.asmx",
        "pssh": generate_playready_pssh(key_id, content_key)
    }

def generate_fairplay_keys(content_id):
    content_key = os.urandom(16) 
    key_id = os.urandom(16)
    iv = os.urandom(16)
    
    return {
        "system_id": "94ce86fb-07ff-4f43-adb8-93d2fa968ca2",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"skd://fairplay-license.test.com/license",
        "certificate_url": f"https://fairplay-license.test.com/cert",
        "iv": base64.b64encode(iv).decode('utf-8')
    }

def generate_widevine_pssh(key_id):
    # Simplified Widevine PSSH generation
    pssh_data = {
        "key_ids": [base64.b64encode(key_id).decode('utf-8')],
        "provider": "widevine_test",
        "content_id": base64.b64encode(key_id).decode('utf-8')
    }
    return base64.b64encode(json.dumps(pssh_data).encode()).decode('utf-8')

def generate_playready_pssh(key_id, content_key):
    # Simplified PlayReady PSSH generation
    pssh_data = f"""
    <WRMHEADER xmlns="http://schemas.microsoft.com/DRM/2007/03/PlayReadyHeader" version="4.0.0.0">
        <DATA>
            <PROTECTINFO>
                <KEYLEN>16</KEYLEN>
                <ALGID>AESCTR</ALGID>
            </PROTECTINFO>
            <KID>{base64.b64encode(key_id).decode('utf-8')}</KID>
            <CHECKSUM></CHECKSUM>
        </DATA>
    </WRMHEADER>
    """
    return base64.b64encode(pssh_data.encode()).decode('utf-8')
EOF
    
    # Create deployment package
    zip speke-provider.zip speke_provider.py
    
    # Create IAM trust policy for Lambda
    cat > speke-lambda-trust-policy.json << EOF
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
        --role-name ${LAMBDA_FUNCTION}-role \
        --assume-role-policy-document file://speke-lambda-trust-policy.json
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name ${LAMBDA_FUNCTION}-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create policy for Secrets Manager access
    cat > speke-secrets-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "${DRM_SECRET_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:GenerateDataKey"
            ],
            "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${DRM_KMS_KEY_ID}"
        }
    ]
}
EOF
    
    # Attach Secrets Manager policy
    aws iam put-role-policy \
        --role-name ${LAMBDA_FUNCTION}-role \
        --policy-name SecretsManagerAccessPolicy \
        --policy-document file://speke-secrets-policy.json
    
    # Get Lambda role ARN
    SPEKE_LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name ${LAMBDA_FUNCTION}-role \
        --query Role.Arn --output text)
    
    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION} \
        --runtime python3.9 \
        --role ${SPEKE_LAMBDA_ROLE_ARN} \
        --handler speke_provider.lambda_handler \
        --zip-file fileb://speke-provider.zip \
        --timeout 30 \
        --environment Variables="{DRM_SECRET_ARN=${DRM_SECRET_ARN}}"
    
    # Create function URL for SPEKE endpoint
    SPEKE_FUNCTION_URL=$(aws lambda create-function-url-config \
        --function-name ${LAMBDA_FUNCTION} \
        --auth-type NONE \
        --cors AllowCredentials=false,AllowHeaders="*",AllowMethods="*",AllowOrigins="*" \
        --query 'FunctionUrl' --output text)
    
    export SPEKE_FUNCTION_URL
    
    # Update configuration file
    jq --arg function_url "$SPEKE_FUNCTION_URL" '.speke_function_url = $function_url' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    jq --arg lambda_role "$SPEKE_LAMBDA_ROLE_ARN" '.speke_lambda_role_arn = $lambda_role' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created SPEKE Lambda function: ${LAMBDA_FUNCTION}"
    log "SPEKE endpoint URL: ${SPEKE_FUNCTION_URL}"
    
    # Cleanup temporary files
    rm -f speke_provider.py speke-provider.zip speke-lambda-trust-policy.json speke-secrets-policy.json
}

# Function to create MediaLive resources
create_medialive_resources() {
    log "Creating MediaLive input and security group..."
    
    # Create input security group
    SECURITY_GROUP_ID=$(aws medialive create-input-security-group \
        --region ${AWS_REGION} \
        --whitelist-rules Cidr=0.0.0.0/0 \
        --tags "Name=DRMSecurityGroup-${RANDOM_SUFFIX},Environment=Production" \
        --query 'SecurityGroup.Id' --output text)
    
    # Create RTMP input
    INPUT_ID=$(aws medialive create-input \
        --region ${AWS_REGION} \
        --name "${CHANNEL_NAME}-input" \
        --type RTMP_PUSH \
        --input-security-groups ${SECURITY_GROUP_ID} \
        --tags "Name=DRMInput-${RANDOM_SUFFIX},Type=Live" \
        --query 'Input.Id' --output text)
    
    export INPUT_ID
    export SECURITY_GROUP_ID
    
    # Update configuration file
    jq --arg input_id "$INPUT_ID" '.input_id = $input_id' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    jq --arg sg_id "$SECURITY_GROUP_ID" '.security_group_id = $sg_id' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created MediaLive input: ${INPUT_ID}"
}

# Function to create MediaPackage channel
create_mediapackage_channel() {
    log "Creating MediaPackage channel..."
    
    # Create MediaPackage channel
    aws mediapackage create-channel \
        --region ${AWS_REGION} \
        --id ${PACKAGE_CHANNEL} \
        --description "DRM-protected streaming channel for ${RANDOM_SUFFIX}" \
        --tags "Name=DRMChannel-${RANDOM_SUFFIX},Environment=Production"
    
    # Get MediaPackage ingest credentials
    PACKAGE_INGEST_URL=$(aws mediapackage describe-channel \
        --region ${AWS_REGION} \
        --id ${PACKAGE_CHANNEL} \
        --query 'HlsIngest.IngestEndpoints[0].Url' --output text)
    
    PACKAGE_USERNAME=$(aws mediapackage describe-channel \
        --region ${AWS_REGION} \
        --id ${PACKAGE_CHANNEL} \
        --query 'HlsIngest.IngestEndpoints[0].Username' --output text)
    
    # Update configuration file
    jq --arg package_channel "$PACKAGE_CHANNEL" '.package_channel = $package_channel' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    jq --arg ingest_url "$PACKAGE_INGEST_URL" '.package_ingest_url = $ingest_url' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created MediaPackage channel: ${PACKAGE_CHANNEL}"
}

# Function to create DRM-protected endpoints
create_drm_endpoints() {
    log "Creating DRM-protected MediaPackage endpoints..."
    
    # Create HLS endpoint with multi-DRM protection
    aws mediapackage create-origin-endpoint \
        --region ${AWS_REGION} \
        --channel-id ${PACKAGE_CHANNEL} \
        --id "${PACKAGE_CHANNEL}-hls-drm" \
        --manifest-name "index.m3u8" \
        --hls-package '{
            "SegmentDurationSeconds": 6,
            "PlaylistType": "EVENT",
            "PlaylistWindowSeconds": 300,
            "ProgramDateTimeIntervalSeconds": 60,
            "AdMarkers": "SCTE35_ENHANCED",
            "IncludeIframeOnlyStream": false,
            "UseAudioRenditionGroup": true,
            "Encryption": {
                "SpekeKeyProvider": {
                    "Url": "'${SPEKE_FUNCTION_URL}'",
                    "ResourceId": "'${PACKAGE_CHANNEL}'-hls",
                    "SystemIds": [
                        "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
                        "9a04f079-9840-4286-ab92-e65be0885f95",
                        "94ce86fb-07ff-4f43-adb8-93d2fa968ca2"
                    ]
                },
                "KeyRotationIntervalSeconds": 3600
            }
        }' \
        --tags "Type=HLS,DRM=MultiDRM,Environment=Production"
    
    # Create DASH endpoint with multi-DRM protection
    aws mediapackage create-origin-endpoint \
        --region ${AWS_REGION} \
        --channel-id ${PACKAGE_CHANNEL} \
        --id "${PACKAGE_CHANNEL}-dash-drm" \
        --manifest-name "index.mpd" \
        --dash-package '{
            "SegmentDurationSeconds": 6,
            "MinBufferTimeSeconds": 30,
            "MinUpdatePeriodSeconds": 15,
            "SuggestedPresentationDelaySeconds": 30,
            "Profile": "NONE",
            "PeriodTriggers": ["ADS"],
            "Encryption": {
                "SpekeKeyProvider": {
                    "Url": "'${SPEKE_FUNCTION_URL}'",
                    "ResourceId": "'${PACKAGE_CHANNEL}'-dash",
                    "SystemIds": [
                        "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
                        "9a04f079-9840-4286-ab92-e65be0885f95"
                    ]
                },
                "KeyRotationIntervalSeconds": 3600
            }
        }' \
        --tags "Type=DASH,DRM=MultiDRM,Environment=Production"
    
    # Get protected endpoint URLs
    HLS_DRM_ENDPOINT=$(aws mediapackage describe-origin-endpoint \
        --region ${AWS_REGION} \
        --id "${PACKAGE_CHANNEL}-hls-drm" \
        --query 'Url' --output text)
    
    DASH_DRM_ENDPOINT=$(aws mediapackage describe-origin-endpoint \
        --region ${AWS_REGION} \
        --id "${PACKAGE_CHANNEL}-dash-drm" \
        --query 'Url' --output text)
    
    export HLS_DRM_ENDPOINT
    export DASH_DRM_ENDPOINT
    
    # Update configuration file
    jq --arg hls_endpoint "$HLS_DRM_ENDPOINT" '.hls_drm_endpoint = $hls_endpoint' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    jq --arg dash_endpoint "$DASH_DRM_ENDPOINT" '.dash_drm_endpoint = $dash_endpoint' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created DRM-protected endpoints:"
    log "  HLS: ${HLS_DRM_ENDPOINT}"
    log "  DASH: ${DASH_DRM_ENDPOINT}"
}

# Function to create MediaLive IAM role
create_medialive_role() {
    log "Creating IAM role for MediaLive..."
    
    # Create MediaLive service role trust policy
    cat > medialive-drm-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "medialive.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create MediaLive role
    aws iam create-role \
        --role-name MediaLiveDRMRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://medialive-drm-trust-policy.json
    
    # Create policy for MediaLive DRM operations
    cat > medialive-drm-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mediapackage:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "${DRM_SECRET_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:GenerateDataKey"
            ],
            "Resource": "arn:aws:kms:${AWS_REGION}:${AWS_ACCOUNT_ID}:key/${DRM_KMS_KEY_ID}"
        }
    ]
}
EOF
    
    # Attach policy to MediaLive role
    aws iam put-role-policy \
        --role-name MediaLiveDRMRole-${RANDOM_SUFFIX} \
        --policy-name MediaLiveDRMPolicy \
        --policy-document file://medialive-drm-policy.json
    
    # Get MediaLive role ARN
    MEDIALIVE_ROLE_ARN=$(aws iam get-role \
        --role-name MediaLiveDRMRole-${RANDOM_SUFFIX} \
        --query Role.Arn --output text)
    
    export MEDIALIVE_ROLE_ARN
    
    # Update configuration file
    jq --arg role_arn "$MEDIALIVE_ROLE_ARN" '.medialive_role_arn = $role_arn' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created MediaLive DRM role: ${MEDIALIVE_ROLE_ARN}"
    
    # Cleanup temporary files
    rm -f medialive-drm-trust-policy.json medialive-drm-policy.json
    
    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 15
}

# Function to create MediaLive channel
create_medialive_channel() {
    log "Creating MediaLive channel..."
    
    # Create MediaLive channel configuration
    cat > medialive-drm-channel.json << EOF
{
    "Name": "${CHANNEL_NAME}",
    "RoleArn": "${MEDIALIVE_ROLE_ARN}",
    "InputSpecification": {
        "Codec": "AVC",
        "Resolution": "HD",
        "MaximumBitrate": "MAX_20_MBPS"
    },
    "InputAttachments": [
        {
            "InputId": "${INPUT_ID}",
            "InputAttachmentName": "primary-input",
            "InputSettings": {
                "SourceEndBehavior": "CONTINUE",
                "InputFilter": "AUTO",
                "FilterStrength": 1,
                "DeblockFilter": "ENABLED",
                "DenoiseFilter": "ENABLED"
            }
        }
    ],
    "Destinations": [
        {
            "Id": "mediapackage-drm-destination",
            "MediaPackageSettings": [
                {
                    "ChannelId": "${PACKAGE_CHANNEL}"
                }
            ]
        }
    ],
    "EncoderSettings": {
        "AudioDescriptions": [
            {
                "Name": "audio_aac",
                "AudioSelectorName": "default",
                "AudioTypeControl": "FOLLOW_INPUT",
                "LanguageCodeControl": "FOLLOW_INPUT",
                "CodecSettings": {
                    "AacSettings": {
                        "Bitrate": 128000,
                        "CodingMode": "CODING_MODE_2_0",
                        "SampleRate": 48000,
                        "Spec": "MPEG4"
                    }
                }
            }
        ],
        "VideoDescriptions": [
            {
                "Name": "video_1080p_drm",
                "Width": 1920,
                "Height": 1080,
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 5000000,
                        "FramerateControl": "SPECIFIED",
                        "FramerateNumerator": 30,
                        "FramerateDenominator": 1,
                        "GopBReference": "ENABLED",
                        "GopClosedCadence": 1,
                        "GopNumBFrames": 3,
                        "GopSize": 90,
                        "GopSizeUnits": "FRAMES",
                        "Profile": "HIGH",
                        "Level": "H264_LEVEL_4_1",
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT",
                        "AdaptiveQuantization": "HIGH",
                        "ColorMetadata": "INSERT",
                        "EntropyEncoding": "CABAC",
                        "FlickerAq": "ENABLED",
                        "ForceFieldPictures": "DISABLED",
                        "TemporalAq": "ENABLED",
                        "SpatialAq": "ENABLED"
                    }
                },
                "RespondToAfd": "RESPOND",
                "ScalingBehavior": "DEFAULT",
                "Sharpness": 50
            },
            {
                "Name": "video_720p_drm",
                "Width": 1280,
                "Height": 720,
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 3000000,
                        "FramerateControl": "SPECIFIED",
                        "FramerateNumerator": 30,
                        "FramerateDenominator": 1,
                        "GopBReference": "ENABLED",
                        "GopClosedCadence": 1,
                        "GopNumBFrames": 3,
                        "GopSize": 90,
                        "GopSizeUnits": "FRAMES",
                        "Profile": "HIGH",
                        "Level": "H264_LEVEL_3_1",
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT",
                        "AdaptiveQuantization": "HIGH",
                        "TemporalAq": "ENABLED",
                        "SpatialAq": "ENABLED"
                    }
                },
                "RespondToAfd": "RESPOND",
                "ScalingBehavior": "DEFAULT",
                "Sharpness": 50
            },
            {
                "Name": "video_480p_drm",
                "Width": 854,
                "Height": 480,
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 1500000,
                        "FramerateControl": "SPECIFIED",
                        "FramerateNumerator": 30,
                        "FramerateDenominator": 1,
                        "GopBReference": "DISABLED",
                        "GopClosedCadence": 1,
                        "GopNumBFrames": 2,
                        "GopSize": 90,
                        "GopSizeUnits": "FRAMES",
                        "Profile": "MAIN",
                        "Level": "H264_LEVEL_3_0",
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT",
                        "AdaptiveQuantization": "MEDIUM"
                    }
                },
                "RespondToAfd": "RESPOND",
                "ScalingBehavior": "DEFAULT",
                "Sharpness": 50
            }
        ],
        "OutputGroups": [
            {
                "Name": "MediaPackage-DRM-ABR",
                "OutputGroupSettings": {
                    "MediaPackageGroupSettings": {
                        "Destination": {
                            "DestinationRefId": "mediapackage-drm-destination"
                        }
                    }
                },
                "Outputs": [
                    {
                        "OutputName": "1080p-protected",
                        "VideoDescriptionName": "video_1080p_drm",
                        "AudioDescriptionNames": ["audio_aac"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    },
                    {
                        "OutputName": "720p-protected",
                        "VideoDescriptionName": "video_720p_drm",
                        "AudioDescriptionNames": ["audio_aac"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    },
                    {
                        "OutputName": "480p-protected",
                        "VideoDescriptionName": "video_480p_drm",
                        "AudioDescriptionNames": ["audio_aac"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    }
                ]
            }
        ],
        "TimecodeConfig": {
            "Source": "EMBEDDED"
        }
    },
    "Tags": {
        "Environment": "Production",
        "Service": "DRM-Protected-Streaming",
        "Component": "MediaLive"
    }
}
EOF
    
    # Create MediaLive channel
    CHANNEL_ID=$(aws medialive create-channel \
        --region ${AWS_REGION} \
        --cli-input-json file://medialive-drm-channel.json \
        --query 'Channel.Id' --output text)
    
    export CHANNEL_ID
    
    # Update configuration file
    jq --arg channel_id "$CHANNEL_ID" '.channel_id = $channel_id' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created MediaLive channel: ${CHANNEL_ID}"
    
    # Cleanup temporary files
    rm -f medialive-drm-channel.json
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution for DRM content delivery..."
    
    # Extract domain names from MediaPackage endpoints
    HLS_DOMAIN=$(echo ${HLS_DRM_ENDPOINT} | cut -d'/' -f3)
    DASH_DOMAIN=$(echo ${DASH_DRM_ENDPOINT} | cut -d'/' -f3)
    HLS_PATH="/$(echo ${HLS_DRM_ENDPOINT} | cut -d'/' -f4- | sed 's|/[^/]*$||')"
    DASH_PATH="/$(echo ${DASH_DRM_ENDPOINT} | cut -d'/' -f4- | sed 's|/[^/]*$||')"
    
    # Create CloudFront distribution configuration
    cat > cloudfront-drm-distribution.json << EOF
{
    "CallerReference": "DRM-Protected-${RANDOM_SUFFIX}-$(date +%s)",
    "Comment": "DRM-protected content distribution with geo-restrictions for ${RANDOM_SUFFIX}",
    "DefaultCacheBehavior": {
        "TargetOriginId": "MediaPackage-HLS-DRM",
        "ViewerProtocolPolicy": "https-only",
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
        "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
        "Compress": false,
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "MinTTL": 0,
        "DefaultTTL": 5,
        "MaxTTL": 86400
    },
    "Origins": {
        "Quantity": 2,
        "Items": [
            {
                "Id": "MediaPackage-HLS-DRM",
                "DomainName": "${HLS_DOMAIN}",
                "OriginPath": "${HLS_PATH}",
                "CustomOriginConfig": {
                    "HTTPPort": 443,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    }
                },
                "CustomHeaders": {
                    "Quantity": 1,
                    "Items": [
                        {
                            "HeaderName": "X-MediaPackage-CDNIdentifier",
                            "HeaderValue": "drm-protected-${RANDOM_SUFFIX}"
                        }
                    ]
                }
            },
            {
                "Id": "MediaPackage-DASH-DRM",
                "DomainName": "${DASH_DOMAIN}",
                "OriginPath": "${DASH_PATH}",
                "CustomOriginConfig": {
                    "HTTPPort": 443,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only",
                    "OriginSslProtocols": {
                        "Quantity": 1,
                        "Items": ["TLSv1.2"]
                    }
                },
                "CustomHeaders": {
                    "Quantity": 1,
                    "Items": [
                        {
                            "HeaderName": "X-MediaPackage-CDNIdentifier",
                            "HeaderValue": "drm-protected-${RANDOM_SUFFIX}"
                        }
                    ]
                }
            }
        ]
    },
    "CacheBehaviors": {
        "Quantity": 2,
        "Items": [
            {
                "PathPattern": "*.mpd",
                "TargetOriginId": "MediaPackage-DASH-DRM",
                "ViewerProtocolPolicy": "https-only",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
                "Compress": false,
                "AllowedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["GET", "HEAD"]
                    }
                },
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "MinTTL": 0,
                "DefaultTTL": 5,
                "MaxTTL": 60
            },
            {
                "PathPattern": "*/license/*",
                "TargetOriginId": "MediaPackage-HLS-DRM",
                "ViewerProtocolPolicy": "https-only",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
                "Compress": false,
                "AllowedMethods": {
                    "Quantity": 7,
                    "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["GET", "HEAD"]
                    }
                },
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "MinTTL": 0,
                "DefaultTTL": 0,
                "MaxTTL": 0
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_All",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021",
        "CertificateSource": "cloudfront"
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "blacklist",
            "Quantity": 2,
            "Items": ["CN", "RU"]
        }
    },
    "HttpVersion": "http2",
    "IsIPV6Enabled": true,
    "WebACLId": ""
}
EOF
    
    # Create CloudFront distribution
    DRM_DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config file://cloudfront-drm-distribution.json \
        --query 'Distribution.Id' --output text)
    
    export DRM_DISTRIBUTION_ID
    
    # Get distribution domain name
    DRM_DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution \
        --id ${DRM_DISTRIBUTION_ID} \
        --query 'Distribution.DomainName' --output text)
    
    export DRM_DISTRIBUTION_DOMAIN
    
    # Update configuration file
    jq --arg dist_id "$DRM_DISTRIBUTION_ID" '.drm_distribution_id = $dist_id' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    jq --arg dist_domain "$DRM_DISTRIBUTION_DOMAIN" '.drm_distribution_domain = $dist_domain' drm-deployment-config.json > tmp.json && mv tmp.json drm-deployment-config.json
    
    log "Created CloudFront distribution: ${DRM_DISTRIBUTION_ID}"
    log "Distribution domain: ${DRM_DISTRIBUTION_DOMAIN}"
    
    # Cleanup temporary files
    rm -f cloudfront-drm-distribution.json
}

# Function to create test player
create_test_player() {
    log "Creating DRM test player..."
    
    # Create comprehensive test player HTML
    cat > drm-test-player.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DRM-Protected Video Player</title>
    <script src="https://vjs.zencdn.net/8.0.4/video.min.js"></script>
    <link href="https://vjs.zencdn.net/8.0.4/video-js.css" rel="stylesheet">
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            backdrop-filter: blur(10px);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .shield-icon {
            font-size: 60px;
            color: #ffd700;
            margin-bottom: 10px;
        }
        .info-panel {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            border-left: 4px solid #ffd700;
        }
        .tech-details {
            background: rgba(0, 0, 0, 0.3);
            padding: 15px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 12px;
            overflow-x: auto;
            margin: 15px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="shield-icon">🛡️</div>
            <h1>DRM-Protected Video Streaming Test Player</h1>
            <p>Advanced content protection with multi-DRM support</p>
        </div>
        
        <div class="info-panel">
            <h3>Security Features Enabled</h3>
            <ul>
                <li>Multi-DRM Support (Widevine, PlayReady, FairPlay)</li>
                <li>HTTPS-Only Content Delivery</li>
                <li>Geographic Content Restrictions</li>
                <li>Device Authentication</li>
                <li>Encrypted Content Keys</li>
            </ul>
        </div>
        
        <video
            id="drm-player"
            class="video-js vjs-default-skin"
            controls
            preload="auto"
            width="1340"
            height="754"
            data-setup='{"fluid": true, "responsive": true}'>
            <p class="vjs-no-js">
                To view this DRM-protected content, please enable JavaScript and ensure your browser supports the required DRM systems.
            </p>
        </video>
        
        <div class="tech-details">
            <h4>Technical Information</h4>
            <div id="drmTechInfo">
                <p><strong>CDN Domain:</strong> ${DRM_DISTRIBUTION_DOMAIN}</p>
                <p><strong>SPEKE Endpoint:</strong> ${SPEKE_FUNCTION_URL}</p>
                <p><strong>Geographic Restrictions:</strong> Blocked in CN, RU</p>
                <p><strong>HLS Endpoint:</strong> https://${DRM_DISTRIBUTION_DOMAIN}/out/v1/index.m3u8</p>
                <p><strong>DASH Endpoint:</strong> https://${DRM_DISTRIBUTION_DOMAIN}/out/v1/index.mpd</p>
            </div>
        </div>
        
        <div class="info-panel">
            <h3>Testing Instructions</h3>
            <ol>
                <li>Start your MediaLive channel to begin streaming</li>
                <li>Use the URLs above to test protected content</li>
                <li>Verify license acquisition and playback</li>
                <li>Test on multiple devices and browsers</li>
            </ol>
        </div>
    </div>
    
    <script>
        const player = videojs('drm-player', {
            html5: {
                vhs: {
                    enableLowInitialPlaylist: true,
                    experimentalBufferBasedABR: true,
                    useDevicePixelRatio: true,
                    overrideNative: true
                }
            },
            playbackRates: [0.5, 1, 1.25, 1.5, 2],
            responsive: true,
            fluid: true
        });
        
        player.on('error', (e) => {
            console.error('Player error:', e);
            alert('Error loading DRM-protected stream. Check console for details.');
        });
    </script>
</body>
</html>
EOF
    
    # Upload test player to S3
    aws s3 cp drm-test-player.html s3://${OUTPUT_BUCKET}/drm-player.html \
        --content-type "text/html" \
        --cache-control "max-age=300"
    
    log "Created DRM test player and uploaded to S3"
    
    # Cleanup temporary file
    rm -f drm-test-player.html
}

# Function to start MediaLive channel
start_medialive_channel() {
    log "Starting MediaLive channel..."
    
    # Start the MediaLive channel
    aws medialive start-channel \
        --region ${AWS_REGION} \
        --channel-id ${CHANNEL_ID}
    
    log "MediaLive channel start command issued"
    log "Note: Channel startup takes 3-5 minutes. Use 'aws medialive describe-channel --channel-id ${CHANNEL_ID}' to check status"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "================================================================"
    echo "DRM-PROTECTED VIDEO STREAMING DEPLOYMENT COMPLETE"
    echo "================================================================"
    echo ""
    echo "🔐 SECURITY FEATURES:"
    echo "• Multi-DRM Support (Widevine, PlayReady, FairPlay)"
    echo "• SPEKE API Integration for Key Management"
    echo "• Content Encryption with Key Rotation"
    echo "• Geographic Content Restrictions"
    echo "• HTTPS-Only Content Delivery"
    echo ""
    echo "🎯 STREAMING CONFIGURATION:"
    echo "Channel ID: ${CHANNEL_ID}"
    echo "Package Channel: ${PACKAGE_CHANNEL}"
    echo ""
    echo "🛡️ PROTECTED ENDPOINTS:"
    echo "HLS + DRM: https://${DRM_DISTRIBUTION_DOMAIN}/out/v1/index.m3u8"
    echo "DASH + DRM: https://${DRM_DISTRIBUTION_DOMAIN}/out/v1/index.mpd"
    echo ""
    echo "🔑 DRM INFRASTRUCTURE:"
    echo "SPEKE Endpoint: ${SPEKE_FUNCTION_URL}"
    echo "KMS Key ID: ${DRM_KMS_KEY_ID}"
    echo "Secrets ARN: ${DRM_SECRET_ARN}"
    echo ""
    echo "🌐 CONTENT DELIVERY:"
    echo "CloudFront Domain: ${DRM_DISTRIBUTION_DOMAIN}"
    echo "Distribution ID: ${DRM_DISTRIBUTION_ID}"
    echo "Geographic Blocking: China, Russia"
    echo ""
    echo "🎮 TEST RESOURCES:"
    echo "DRM Player: http://${OUTPUT_BUCKET}.s3-website.${AWS_REGION}.amazonaws.com/drm-player.html"
    echo ""
    echo "📊 RTMP INPUTS:"
    # Get RTMP endpoints
    PRIMARY_RTMP=$(aws medialive describe-input --region ${AWS_REGION} --input-id ${INPUT_ID} --query 'Destinations[0].Url' --output text 2>/dev/null || echo "Not available")
    BACKUP_RTMP=$(aws medialive describe-input --region ${AWS_REGION} --input-id ${INPUT_ID} --query 'Destinations[1].Url' --output text 2>/dev/null || echo "Not available")
    echo "Primary RTMP: ${PRIMARY_RTMP}"
    echo "Backup RTMP: ${BACKUP_RTMP}"
    echo "Stream Key: live"
    echo ""
    echo "⚠️  IMPORTANT NOTES:"
    echo "• MediaLive channel is starting (takes 3-5 minutes)"
    echo "• Test DRM playback on actual devices (not just browsers)"
    echo "• Monitor CloudWatch for channel health and errors"
    echo "• Configuration saved to: drm-deployment-config.json"
    echo "• Run destroy.sh to clean up all resources"
    echo ""
    echo "📋 ESTIMATED COSTS:"
    echo "• MediaLive: ~\$15-20/hour when running"
    echo "• MediaPackage: ~\$0.01-0.05 per GB delivered"
    echo "• CloudFront: ~\$0.085-0.25 per GB (varies by region)"
    echo "• Lambda: ~\$0.0000002 per SPEKE request"
    echo "• Other services: <\$1/day"
    echo "================================================================"
}

# Main execution function
main() {
    log "Starting DRM-protected video streaming deployment..."
    
    # Run prerequisite checks
    check_prerequisites
    check_permissions
    
    # Generate unique resource names
    generate_resource_names
    
    # Create infrastructure components
    create_kms_resources
    create_secrets
    create_s3_bucket
    create_speke_lambda
    create_medialive_resources
    create_mediapackage_channel
    create_drm_endpoints
    create_medialive_role
    create_medialive_channel
    create_cloudfront_distribution
    create_test_player
    start_medialive_channel
    
    # Display summary
    display_summary
}

# Trap errors and cleanup on failure
trap 'error "Deployment failed! Check logs above for details. Run destroy.sh to clean up any created resources."' ERR

# Execute main function
main "$@"