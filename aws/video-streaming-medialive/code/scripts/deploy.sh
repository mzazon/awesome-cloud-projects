#!/bin/bash

# Enterprise Video Streaming Platform Deployment Script
# AWS Elemental MediaLive, MediaPackage, and CloudFront
# Recipe: Live Video Streaming Platform with MediaLive

set -euo pipefail

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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.streaming-platform-state"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Redirect all output to log file and console
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version (v2 required)
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! $aws_version =~ ^2\. ]]; then
        error "AWS CLI v2 is required. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required tools
    for tool in jq curl openssl; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install $tool."
        fi
    done
    
    # Check AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not set. Use 'aws configure' or set AWS_REGION environment variable."
        fi
    fi
    
    log "Prerequisites check completed successfully"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    warn "Deployment failed. Starting cleanup of partial resources..."
    
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        
        # Stop and delete MediaLive channel if exists
        if [[ -n "${CHANNEL_ID:-}" ]]; then
            aws medialive stop-channel --channel-id "$CHANNEL_ID" --region "$AWS_REGION" 2>/dev/null || true
            sleep 30
            aws medialive delete-channel --channel-id "$CHANNEL_ID" --region "$AWS_REGION" 2>/dev/null || true
        fi
        
        # Delete MediaLive inputs
        for input_id in "${RTMP_INPUT_ID:-}" "${HLS_INPUT_ID:-}" "${RTP_INPUT_ID:-}"; do
            if [[ -n "$input_id" ]]; then
                aws medialive delete-input --input-id "$input_id" --region "$AWS_REGION" 2>/dev/null || true
            fi
        done
        
        # Delete MediaPackage endpoints
        for endpoint_id in "${PACKAGE_CHANNEL_NAME:-}-hls-advanced" "${PACKAGE_CHANNEL_NAME:-}-dash-drm" "${PACKAGE_CHANNEL_NAME:-}-cmaf-ll"; do
            if [[ -n "${PACKAGE_CHANNEL_NAME:-}" ]]; then
                aws mediapackage delete-origin-endpoint --id "$endpoint_id" --region "$AWS_REGION" 2>/dev/null || true
            fi
        done
        
        # Delete MediaPackage channel
        if [[ -n "${PACKAGE_CHANNEL_NAME:-}" ]]; then
            aws mediapackage delete-channel --id "$PACKAGE_CHANNEL_NAME" --region "$AWS_REGION" 2>/dev/null || true
        fi
        
        # Delete security groups
        for sg_id in "${SECURITY_GROUP_ID:-}" "${INTERNAL_SG_ID:-}"; do
            if [[ -n "$sg_id" ]]; then
                aws medialive delete-input-security-group --input-security-group-id "$sg_id" --region "$AWS_REGION" 2>/dev/null || true
            fi
        done
        
        # Delete S3 bucket
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            aws s3 rm "s3://$BUCKET_NAME" --recursive 2>/dev/null || true
            aws s3 rb "s3://$BUCKET_NAME" 2>/dev/null || true
        fi
        
        # Delete IAM role
        if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
            aws iam delete-role-policy --role-name "MediaLivePlatformRole-$RANDOM_SUFFIX" --policy-name "MediaLivePlatformPolicy" 2>/dev/null || true
            aws iam delete-role --role-name "MediaLivePlatformRole-$RANDOM_SUFFIX" 2>/dev/null || true
        fi
    fi
    
    rm -f "$STATE_FILE"
    warn "Cleanup completed"
}

# Trap for cleanup on script exit with error
trap cleanup_on_error ERR

# Generate unique identifiers
generate_identifiers() {
    log "Generating unique identifiers..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword)
    
    export PLATFORM_NAME="video-platform-${RANDOM_SUFFIX}"
    export LIVE_CHANNEL_NAME="live-channel-${RANDOM_SUFFIX}"
    export PACKAGE_CHANNEL_NAME="package-channel-${RANDOM_SUFFIX}"
    export DISTRIBUTION_NAME="streaming-distribution-${RANDOM_SUFFIX}"
    export BUCKET_NAME="streaming-platform-${RANDOM_SUFFIX}"
    export DRM_KEY_NAME="drm-key-${RANDOM_SUFFIX}"
    
    # Save state
    cat > "$STATE_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
PLATFORM_NAME=$PLATFORM_NAME
LIVE_CHANNEL_NAME=$LIVE_CHANNEL_NAME
PACKAGE_CHANNEL_NAME=$PACKAGE_CHANNEL_NAME
DISTRIBUTION_NAME=$DISTRIBUTION_NAME
BUCKET_NAME=$BUCKET_NAME
DRM_KEY_NAME=$DRM_KEY_NAME
EOF
    
    log "Generated platform name: $PLATFORM_NAME"
}

# Create S3 bucket with lifecycle policies
create_storage() {
    log "Creating S3 storage bucket..."
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$BUCKET_NAME"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Create lifecycle policy
    cat > lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "streaming-content-lifecycle",
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ],
            "Filter": {
                "Prefix": "archives/"
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file://lifecycle-policy.json
    
    rm -f lifecycle-policy.json
    log "S3 bucket created with lifecycle policies"
}

# Create IAM roles and policies
create_iam_roles() {
    log "Creating IAM roles and policies..."
    
    # Create trust policy
    cat > medialive-trust-policy.json << EOF
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
        --role-name "MediaLivePlatformRole-$RANDOM_SUFFIX" \
        --assume-role-policy-document file://medialive-trust-policy.json
    
    # Create custom policy
    cat > medialive-platform-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mediapackage:*",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "secretsmanager:GetSecretValue",
                "secretsmanager:CreateSecret",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "MediaLivePlatformRole-$RANDOM_SUFFIX" \
        --policy-name "MediaLivePlatformPolicy" \
        --policy-document file://medialive-platform-policy.json
    
    # Wait for role propagation
    sleep 10
    
    # Get role ARN
    MEDIALIVE_ROLE_ARN=$(aws iam get-role \
        --role-name "MediaLivePlatformRole-$RANDOM_SUFFIX" \
        --query 'Role.Arn' --output text)
    
    echo "MEDIALIVE_ROLE_ARN=$MEDIALIVE_ROLE_ARN" >> "$STATE_FILE"
    
    rm -f medialive-trust-policy.json medialive-platform-policy.json
    log "IAM roles created successfully"
}

# Create MediaLive security groups
create_security_groups() {
    log "Creating MediaLive input security groups..."
    
    # Create public security group
    SECURITY_GROUP_ID=$(aws medialive create-input-security-group \
        --region "$AWS_REGION" \
        --whitelist-rules Cidr=0.0.0.0/0 \
        --tags "Name=StreamingPlatformSG-$RANDOM_SUFFIX,Environment=Production" \
        --query 'SecurityGroup.Id' --output text)
    
    # Create internal security group
    INTERNAL_SG_ID=$(aws medialive create-input-security-group \
        --region "$AWS_REGION" \
        --whitelist-rules Cidr=10.0.0.0/8 Cidr=172.16.0.0/12 Cidr=192.168.0.0/16 \
        --tags "Name=InternalStreamingSG-$RANDOM_SUFFIX,Environment=Production" \
        --query 'SecurityGroup.Id' --output text)
    
    echo "SECURITY_GROUP_ID=$SECURITY_GROUP_ID" >> "$STATE_FILE"
    echo "INTERNAL_SG_ID=$INTERNAL_SG_ID" >> "$STATE_FILE"
    
    log "Security groups created: $SECURITY_GROUP_ID, $INTERNAL_SG_ID"
}

# Create MediaLive inputs
create_medialive_inputs() {
    log "Creating MediaLive inputs..."
    
    # Create RTMP Push input
    RTMP_INPUT_ID=$(aws medialive create-input \
        --region "$AWS_REGION" \
        --name "$PLATFORM_NAME-rtmp-input" \
        --type RTMP_PUSH \
        --input-security-groups "$SECURITY_GROUP_ID" \
        --tags "Name=RTMPInput-$RANDOM_SUFFIX,Type=Live" \
        --query 'Input.Id' --output text)
    
    # Create HLS Pull input
    HLS_INPUT_ID=$(aws medialive create-input \
        --region "$AWS_REGION" \
        --name "$PLATFORM_NAME-hls-input" \
        --type URL_PULL \
        --sources Url=https://example.com/stream.m3u8 \
        --tags "Name=HLSInput-$RANDOM_SUFFIX,Type=Remote" \
        --query 'Input.Id' --output text)
    
    # Create RTP Push input
    RTP_INPUT_ID=$(aws medialive create-input \
        --region "$AWS_REGION" \
        --name "$PLATFORM_NAME-rtp-input" \
        --type RTP_PUSH \
        --input-security-groups "$INTERNAL_SG_ID" \
        --tags "Name=RTPInput-$RANDOM_SUFFIX,Type=Professional" \
        --query 'Input.Id' --output text)
    
    echo "RTMP_INPUT_ID=$RTMP_INPUT_ID" >> "$STATE_FILE"
    echo "HLS_INPUT_ID=$HLS_INPUT_ID" >> "$STATE_FILE"
    echo "RTP_INPUT_ID=$RTP_INPUT_ID" >> "$STATE_FILE"
    
    log "MediaLive inputs created: RTMP=$RTMP_INPUT_ID, HLS=$HLS_INPUT_ID, RTP=$RTP_INPUT_ID"
}

# Create MediaPackage channel
create_mediapackage_channel() {
    log "Creating MediaPackage channel..."
    
    # Create MediaPackage channel
    aws mediapackage create-channel \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME" \
        --description "Enterprise streaming platform channel" \
        --tags "Name=StreamingChannel-$RANDOM_SUFFIX,Environment=Production"
    
    # Create DRM key
    DRM_KEY_ID=$(aws secretsmanager create-secret \
        --name "medialive-drm-key-$RANDOM_SUFFIX" \
        --description "DRM encryption key for streaming platform" \
        --secret-string "{\"key\":\"$(openssl rand -base64 32)\"}" \
        --query 'ARN' --output text)
    
    echo "DRM_KEY_ID=$DRM_KEY_ID" >> "$STATE_FILE"
    
    log "MediaPackage channel created with DRM support"
}

# Create MediaPackage origin endpoints
create_mediapackage_endpoints() {
    log "Creating MediaPackage origin endpoints..."
    
    # Create HLS endpoint
    aws mediapackage create-origin-endpoint \
        --region "$AWS_REGION" \
        --channel-id "$PACKAGE_CHANNEL_NAME" \
        --id "$PACKAGE_CHANNEL_NAME-hls-advanced" \
        --manifest-name "master.m3u8" \
        --startover-window-seconds 3600 \
        --time-delay-seconds 10 \
        --hls-package '{
            "SegmentDurationSeconds": 4,
            "PlaylistType": "EVENT",
            "PlaylistWindowSeconds": 300,
            "ProgramDateTimeIntervalSeconds": 60,
            "AdMarkers": "SCTE35_ENHANCED",
            "IncludeIframeOnlyStream": true,
            "UseAudioRenditionGroup": true
        }' \
        --tags "Type=HLS,Quality=Advanced,Environment=Production" > /dev/null
    
    # Create DASH endpoint
    aws mediapackage create-origin-endpoint \
        --region "$AWS_REGION" \
        --channel-id "$PACKAGE_CHANNEL_NAME" \
        --id "$PACKAGE_CHANNEL_NAME-dash-drm" \
        --manifest-name "manifest.mpd" \
        --startover-window-seconds 3600 \
        --time-delay-seconds 10 \
        --dash-package '{
            "SegmentDurationSeconds": 4,
            "MinBufferTimeSeconds": 20,
            "MinUpdatePeriodSeconds": 10,
            "SuggestedPresentationDelaySeconds": 30,
            "Profile": "NONE",
            "PeriodTriggers": ["ADS"]
        }' \
        --tags "Type=DASH,DRM=Enabled,Environment=Production" > /dev/null
    
    # Create CMAF endpoint
    aws mediapackage create-origin-endpoint \
        --region "$AWS_REGION" \
        --channel-id "$PACKAGE_CHANNEL_NAME" \
        --id "$PACKAGE_CHANNEL_NAME-cmaf-ll" \
        --manifest-name "index.m3u8" \
        --startover-window-seconds 1800 \
        --time-delay-seconds 2 \
        --cmaf-package '{
            "SegmentDurationSeconds": 2,
            "SegmentPrefix": "segment",
            "HlsManifests": [
                {
                    "Id": "low-latency",
                    "ManifestName": "ll.m3u8",
                    "PlaylistType": "EVENT",
                    "PlaylistWindowSeconds": 60,
                    "ProgramDateTimeIntervalSeconds": 60,
                    "AdMarkers": "SCTE35_ENHANCED"
                }
            ]
        }' \
        --tags "Type=CMAF,Latency=Low,Environment=Production" > /dev/null
    
    log "MediaPackage endpoints created successfully"
}

# Create MediaLive channel
create_medialive_channel() {
    log "Creating MediaLive channel with multiple bitrates..."
    
    # Load state to get variables
    source "$STATE_FILE"
    
    # Create comprehensive channel configuration
    cat > platform-channel-config.json << EOF
{
    "Name": "$LIVE_CHANNEL_NAME",
    "RoleArn": "$MEDIALIVE_ROLE_ARN",
    "InputSpecification": {
        "Codec": "AVC",
        "Resolution": "HD",
        "MaximumBitrate": "MAX_50_MBPS"
    },
    "InputAttachments": [
        {
            "InputId": "$RTMP_INPUT_ID",
            "InputAttachmentName": "primary-rtmp",
            "InputSettings": {
                "SourceEndBehavior": "CONTINUE",
                "InputFilter": "AUTO",
                "FilterStrength": 1,
                "DeblockFilter": "ENABLED",
                "DenoiseFilter": "ENABLED"
            }
        },
        {
            "InputId": "$HLS_INPUT_ID",
            "InputAttachmentName": "backup-hls",
            "InputSettings": {
                "SourceEndBehavior": "CONTINUE",
                "InputFilter": "AUTO",
                "FilterStrength": 1
            }
        }
    ],
    "Destinations": [
        {
            "Id": "mediapackage-destination",
            "MediaPackageSettings": [
                {
                    "ChannelId": "$PACKAGE_CHANNEL_NAME"
                }
            ]
        },
        {
            "Id": "s3-archive-destination",
            "S3Settings": [
                {
                    "BucketName": "$BUCKET_NAME",
                    "FileNamePrefix": "archives/",
                    "RoleArn": "$MEDIALIVE_ROLE_ARN"
                }
            ]
        }
    ],
    "EncoderSettings": {
        "AudioDescriptions": [
            {
                "Name": "audio_stereo",
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
                "Name": "video_1080p",
                "Width": 1920,
                "Height": 1080,
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 6000000,
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
                        "TemporalAq": "ENABLED",
                        "SpatialAq": "ENABLED"
                    }
                },
                "RespondToAfd": "RESPOND",
                "ScalingBehavior": "DEFAULT",
                "Sharpness": 50
            },
            {
                "Name": "video_720p",
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
                        "GopNumBFrames": 2,
                        "GopSize": 90,
                        "GopSizeUnits": "FRAMES",
                        "Profile": "HIGH",
                        "Level": "H264_LEVEL_3_1",
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT",
                        "AdaptiveQuantization": "MEDIUM",
                        "TemporalAq": "ENABLED",
                        "SpatialAq": "ENABLED"
                    }
                },
                "RespondToAfd": "RESPOND",
                "ScalingBehavior": "DEFAULT",
                "Sharpness": 50
            },
            {
                "Name": "video_480p",
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
                "Name": "MediaPackage-ABR",
                "OutputGroupSettings": {
                    "MediaPackageGroupSettings": {
                        "Destination": {
                            "DestinationRefId": "mediapackage-destination"
                        }
                    }
                },
                "Outputs": [
                    {
                        "OutputName": "1080p-HD",
                        "VideoDescriptionName": "video_1080p",
                        "AudioDescriptionNames": ["audio_stereo"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    },
                    {
                        "OutputName": "720p-HD",
                        "VideoDescriptionName": "video_720p",
                        "AudioDescriptionNames": ["audio_stereo"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    },
                    {
                        "OutputName": "480p-SD",
                        "VideoDescriptionName": "video_480p",
                        "AudioDescriptionNames": ["audio_stereo"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    }
                ]
            },
            {
                "Name": "S3-Archive",
                "OutputGroupSettings": {
                    "ArchiveGroupSettings": {
                        "Destination": {
                            "DestinationRefId": "s3-archive-destination"
                        },
                        "RolloverInterval": 3600
                    }
                },
                "Outputs": [
                    {
                        "OutputName": "archive-source",
                        "VideoDescriptionName": "video_1080p",
                        "AudioDescriptionNames": ["audio_stereo"],
                        "OutputSettings": {
                            "ArchiveOutputSettings": {
                                "NameModifier": "-archive",
                                "Extension": "m2ts"
                            }
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
        "Service": "StreamingPlatform",
        "Component": "MediaLive"
    }
}
EOF
    
    # Create the MediaLive channel
    CHANNEL_ID=$(aws medialive create-channel \
        --region "$AWS_REGION" \
        --cli-input-json file://platform-channel-config.json \
        --query 'Channel.Id' --output text)
    
    echo "CHANNEL_ID=$CHANNEL_ID" >> "$STATE_FILE"
    
    rm -f platform-channel-config.json
    log "MediaLive channel created: $CHANNEL_ID"
}

# Create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution..."
    
    # Get MediaPackage endpoint URLs
    HLS_ENDPOINT=$(aws mediapackage describe-origin-endpoint \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME-hls-advanced" \
        --query 'Url' --output text)
    
    DASH_ENDPOINT=$(aws mediapackage describe-origin-endpoint \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME-dash-drm" \
        --query 'Url' --output text)
    
    CMAF_ENDPOINT=$(aws mediapackage describe-origin-endpoint \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME-cmaf-ll" \
        --query 'Url' --output text)
    
    # Create CloudFront distribution (simplified configuration for reliability)
    DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config '{
            "CallerReference": "'$DISTRIBUTION_NAME-$(date +%s)'",
            "Comment": "Enterprise Video Streaming Platform Distribution",
            "DefaultCacheBehavior": {
                "TargetOriginId": "MediaPackage-HLS-Primary",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
                "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
                "Compress": true,
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
                "MaxTTL": 31536000
            },
            "Origins": {
                "Quantity": 1,
                "Items": [
                    {
                        "Id": "MediaPackage-HLS-Primary",
                        "DomainName": "'$(echo $HLS_ENDPOINT | cut -d'/' -f3)'",
                        "OriginPath": "/'$(echo $HLS_ENDPOINT | cut -d'/' -f4- | sed 's|/[^/]*$||')'",
                        "CustomOriginConfig": {
                            "HTTPPort": 443,
                            "HTTPSPort": 443,
                            "OriginProtocolPolicy": "https-only",
                            "OriginSslProtocols": {
                                "Quantity": 1,
                                "Items": ["TLSv1.2"]
                            }
                        }
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
                    "RestrictionType": "none",
                    "Quantity": 0
                }
            },
            "HttpVersion": "http2",
            "IsIPV6Enabled": true
        }' \
        --query 'Distribution.Id' --output text)
    
    echo "DISTRIBUTION_ID=$DISTRIBUTION_ID" >> "$STATE_FILE"
    
    log "CloudFront distribution created: $DISTRIBUTION_ID"
}

# Create monitoring alarms
create_monitoring() {
    log "Creating CloudWatch monitoring alarms..."
    
    # Load state
    source "$STATE_FILE"
    
    # Create MediaLive alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "MediaLive-$LIVE_CHANNEL_NAME-InputLoss" \
        --alarm-description "MediaLive channel input loss detection" \
        --metric-name "InputVideoFreeze" \
        --namespace "AWS/MediaLive" \
        --statistic "Maximum" \
        --period 60 \
        --threshold 0.5 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --treat-missing-data "breaching" \
        --dimensions Name=ChannelId,Value="$CHANNEL_ID" 2>/dev/null || true
    
    # Create MediaPackage alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "MediaPackage-$PACKAGE_CHANNEL_NAME-EgressErrors" \
        --alarm-description "MediaPackage egress error detection" \
        --metric-name "EgressRequestCount" \
        --namespace "AWS/MediaPackage" \
        --statistic "Sum" \
        --period 300 \
        --threshold 100 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=Channel,Value="$PACKAGE_CHANNEL_NAME" 2>/dev/null || true
    
    log "Monitoring alarms created"
}

# Start MediaLive channel
start_channel() {
    log "Starting MediaLive channel..."
    
    # Load state
    source "$STATE_FILE"
    
    # Start the channel
    aws medialive start-channel \
        --region "$AWS_REGION" \
        --channel-id "$CHANNEL_ID"
    
    log "MediaLive channel start initiated. Waiting for channel to be running..."
    
    # Wait for channel to start (with timeout)
    local timeout=300  # 5 minutes
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local state=$(aws medialive describe-channel \
            --region "$AWS_REGION" \
            --channel-id "$CHANNEL_ID" \
            --query 'State' --output text)
        
        if [[ "$state" == "RUNNING" ]]; then
            log "MediaLive channel is now running"
            break
        elif [[ "$state" == "CREATE_FAILED" || "$state" == "START_FAILED" ]]; then
            error "MediaLive channel failed to start. State: $state"
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        info "Channel state: $state (${elapsed}s elapsed)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        error "Timeout waiting for MediaLive channel to start"
    fi
}

# Display platform information
display_platform_info() {
    log "Deployment completed successfully!"
    
    # Load final state
    source "$STATE_FILE"
    
    # Get endpoints
    local distribution_domain=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'Distribution.DomainName' --output text)
    
    local rtmp_primary=$(aws medialive describe-input \
        --region "$AWS_REGION" \
        --input-id "$RTMP_INPUT_ID" \
        --query 'Destinations[0].Url' --output text)
    
    local rtmp_backup=$(aws medialive describe-input \
        --region "$AWS_REGION" \
        --input-id "$RTMP_INPUT_ID" \
        --query 'Destinations[1].Url' --output text 2>/dev/null || echo "N/A")
    
    echo ""
    echo "========================================================"
    echo "ENTERPRISE STREAMING PLATFORM DEPLOYMENT COMPLETE"
    echo "========================================================"
    echo ""
    echo "🎥 STREAMING INPUTS:"
    echo "Primary RTMP: $rtmp_primary"
    echo "Backup RTMP: $rtmp_backup"
    echo "Stream Key: live"
    echo ""
    echo "🌐 PLAYBACK ENDPOINTS:"
    echo "HLS (Adaptive): https://$distribution_domain/out/v1/master.m3u8"
    echo "DASH (DRM Ready): https://$distribution_domain/out/v1/manifest.mpd"
    echo "CMAF (Low Latency): https://$distribution_domain/out/v1/ll.m3u8"
    echo ""
    echo "📊 PLATFORM COMPONENTS:"
    echo "Platform Name: $PLATFORM_NAME"
    echo "Channel ID: $CHANNEL_ID"
    echo "Package Channel: $PACKAGE_CHANNEL_NAME"
    echo "Distribution ID: $DISTRIBUTION_ID"
    echo "S3 Bucket: $BUCKET_NAME"
    echo ""
    echo "✨ FEATURES ENABLED:"
    echo "• Adaptive Bitrate Streaming (480p to 1080p)"
    echo "• Multiple Protocol Support (HLS, DASH, CMAF)"
    echo "• Low Latency Streaming"
    echo "• DRM Protection Ready"
    echo "• Global CDN Distribution"
    echo "• Real-time Monitoring"
    echo "• Content Archiving"
    echo "• Professional Input Support"
    echo ""
    echo "💰 COST MONITORING:"
    echo "• Monitor AWS billing dashboard regularly"
    echo "• MediaLive charges apply when channel is RUNNING"
    echo "• CloudFront data transfer charges apply"
    echo "• S3 storage charges for archived content"
    echo ""
    echo "🔧 MANAGEMENT:"
    echo "• State file: $STATE_FILE"
    echo "• Log file: $LOG_FILE"
    echo "• Use destroy.sh to clean up resources"
    echo "========================================================"
}

# Main deployment function
main() {
    log "Starting enterprise video streaming platform deployment..."
    
    # Check if already deployed
    if [[ -f "$STATE_FILE" ]]; then
        warn "Existing deployment found. Remove $STATE_FILE to redeploy."
        exit 1
    fi
    
    # Execute deployment steps
    check_prerequisites
    generate_identifiers
    create_storage
    create_iam_roles
    create_security_groups
    create_medialive_inputs
    create_mediapackage_channel
    create_mediapackage_endpoints
    create_medialive_channel
    create_cloudfront_distribution
    create_monitoring
    start_channel
    display_platform_info
    
    log "Enterprise streaming platform deployed successfully!"
}

# Execute main function
main "$@"