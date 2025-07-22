#!/bin/bash

# AWS Elemental MediaLive Live Streaming Solution Deployment Script
# This script deploys a complete live streaming infrastructure using AWS Elemental MediaLive,
# MediaPackage, CloudFront, and supporting services.

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid. Please run 'aws configure' first."
        exit 1
    fi
    
    success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    
    if [ "$major_version" -lt 2 ]; then
        error "AWS CLI version 2 or higher is required. Current version: $aws_version"
        exit 1
    fi
    
    # Check jq
    if ! command_exists jq; then
        error "jq is required for JSON processing. Please install jq."
        exit 1
    fi
    
    success "All prerequisites satisfied"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local timestamp=$(date +%s)
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "${timestamp:(-6)}")
    
    export STREAM_NAME="live-stream-${random_suffix}"
    export CHANNEL_NAME="live-channel-${random_suffix}"
    export PACKAGE_CHANNEL_NAME="package-channel-${random_suffix}"
    export DISTRIBUTION_NAME="live-distribution-${random_suffix}"
    export BUCKET_NAME="live-streaming-${random_suffix}"
    export IAM_ROLE_NAME="MediaLiveAccessRole-${random_suffix}"
    
    # Save environment variables for cleanup
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
STREAM_NAME=${STREAM_NAME}
CHANNEL_NAME=${CHANNEL_NAME}
PACKAGE_CHANNEL_NAME=${PACKAGE_CHANNEL_NAME}
DISTRIBUTION_NAME=${DISTRIBUTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
EOF
    
    success "Environment variables configured"
    log "Using region: $AWS_REGION"
    log "Using account: $AWS_ACCOUNT_ID"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket $BUCKET_NAME already exists"
        return 0
    fi
    
    # Create bucket with appropriate location constraint
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    success "S3 bucket created: $BUCKET_NAME"
}

# Function to create MediaLive input security group
create_input_security_group() {
    log "Creating MediaLive input security group..."
    
    local security_group_id=$(aws medialive create-input-security-group \
        --region "$AWS_REGION" \
        --whitelist-rules Cidr=0.0.0.0/0 \
        --query 'SecurityGroup.Id' --output text)
    
    echo "$security_group_id" > .security_group_id
    export SECURITY_GROUP_ID="$security_group_id"
    
    success "Created input security group: $security_group_id"
}

# Function to create MediaLive RTMP input
create_medialive_input() {
    log "Creating MediaLive RTMP input..."
    
    local input_id=$(aws medialive create-input \
        --region "$AWS_REGION" \
        --name "${STREAM_NAME}-input" \
        --type RTMP_PUSH \
        --input-security-groups "$SECURITY_GROUP_ID" \
        --query 'Input.Id' --output text)
    
    echo "$input_id" > .input_id
    export INPUT_ID="$input_id"
    
    # Get input destinations
    local input_url=$(aws medialive describe-input \
        --region "$AWS_REGION" \
        --input-id "$input_id" \
        --query 'Destinations[0].Url' --output text)
    
    echo "$input_url" > .input_url
    export INPUT_URL="$input_url"
    
    success "Created MediaLive input: $input_id"
    log "Input URL: $input_url"
}

# Function to create MediaPackage channel
create_mediapackage_channel() {
    log "Creating MediaPackage channel..."
    
    aws mediapackage create-channel \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME" \
        --description "Live streaming package channel"
    
    # Get MediaPackage channel details
    local package_url=$(aws mediapackage describe-channel \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME" \
        --query 'HlsIngest.IngestEndpoints[0].Url' --output text)
    
    local package_username=$(aws mediapackage describe-channel \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME" \
        --query 'HlsIngest.IngestEndpoints[0].Username' --output text)
    
    echo "$package_url" > .package_url
    echo "$package_username" > .package_username
    export PACKAGE_URL="$package_url"
    export PACKAGE_USERNAME="$package_username"
    
    success "Created MediaPackage channel: $PACKAGE_CHANNEL_NAME"
}

# Function to create MediaPackage endpoints
create_mediapackage_endpoints() {
    log "Creating MediaPackage origin endpoints..."
    
    # Create HLS endpoint
    aws mediapackage create-origin-endpoint \
        --region "$AWS_REGION" \
        --channel-id "$PACKAGE_CHANNEL_NAME" \
        --id "${PACKAGE_CHANNEL_NAME}-hls" \
        --manifest-name "index.m3u8" \
        --hls-package StartTag=EXT-X-START,PlaylistType=EVENT,SegmentDurationSeconds=6,PlaylistWindowSeconds=60
    
    # Create DASH endpoint
    aws mediapackage create-origin-endpoint \
        --region "$AWS_REGION" \
        --channel-id "$PACKAGE_CHANNEL_NAME" \
        --id "${PACKAGE_CHANNEL_NAME}-dash" \
        --manifest-name "index.mpd" \
        --dash-package SegmentDurationSeconds=6,MinBufferTimeSeconds=30,MinUpdatePeriodSeconds=15,SuggestedPresentationDelaySeconds=25
    
    # Get endpoint URLs
    local hls_endpoint=$(aws mediapackage describe-origin-endpoint \
        --region "$AWS_REGION" \
        --id "${PACKAGE_CHANNEL_NAME}-hls" \
        --query 'Url' --output text)
    
    local dash_endpoint=$(aws mediapackage describe-origin-endpoint \
        --region "$AWS_REGION" \
        --id "${PACKAGE_CHANNEL_NAME}-dash" \
        --query 'Url' --output text)
    
    echo "$hls_endpoint" > .hls_endpoint
    echo "$dash_endpoint" > .dash_endpoint
    export HLS_ENDPOINT="$hls_endpoint"
    export DASH_ENDPOINT="$dash_endpoint"
    
    success "Created MediaPackage endpoints"
    log "HLS endpoint: $hls_endpoint"
    log "DASH endpoint: $dash_endpoint"
}

# Function to create IAM role for MediaLive
create_iam_role() {
    log "Creating IAM role for MediaLive..."
    
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file://medialive-trust-policy.json
    
    # Attach MediaLive service policy
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/MediaLiveFullAccess
    
    # Get role ARN
    local role_arn=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    echo "$role_arn" > .role_arn
    export ROLE_ARN="$role_arn"
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 15
    
    success "Created MediaLive IAM role: $role_arn"
}

# Function to create MediaLive channel
create_medialive_channel() {
    log "Creating MediaLive channel..."
    
    # Create channel configuration
    cat > channel-config.json << EOF
{
    "Name": "${CHANNEL_NAME}",
    "RoleArn": "${ROLE_ARN}",
    "InputSpecification": {
        "Codec": "AVC",
        "Resolution": "HD",
        "MaximumBitrate": "MAX_10_MBPS"
    },
    "InputAttachments": [
        {
            "InputId": "${INPUT_ID}",
            "InputAttachmentName": "primary-input",
            "InputSettings": {
                "SourceEndBehavior": "CONTINUE"
            }
        }
    ],
    "Destinations": [
        {
            "Id": "destination1",
            "MediaPackageSettings": [
                {
                    "ChannelId": "${PACKAGE_CHANNEL_NAME}"
                }
            ]
        }
    ],
    "EncoderSettings": {
        "AudioDescriptions": [
            {
                "Name": "audio_1",
                "AudioSelectorName": "default",
                "CodecSettings": {
                    "AacSettings": {
                        "Bitrate": 96000,
                        "CodingMode": "CODING_MODE_2_0",
                        "SampleRate": 48000
                    }
                }
            }
        ],
        "VideoDescriptions": [
            {
                "Name": "video_1080p",
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 6000000,
                        "FramerateControl": "SPECIFIED",
                        "FramerateNumerator": 30,
                        "FramerateDenominator": 1,
                        "GopBReference": "DISABLED",
                        "GopClosedCadence": 1,
                        "GopNumBFrames": 2,
                        "GopSize": 90,
                        "GopSizeUnits": "FRAMES",
                        "Profile": "MAIN",
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT"
                    }
                },
                "Width": 1920,
                "Height": 1080,
                "RespondToAfd": "NONE",
                "Sharpness": 50,
                "ScalingBehavior": "DEFAULT"
            },
            {
                "Name": "video_720p",
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 3000000,
                        "FramerateControl": "SPECIFIED",
                        "FramerateNumerator": 30,
                        "FramerateDenominator": 1,
                        "GopBReference": "DISABLED",
                        "GopClosedCadence": 1,
                        "GopNumBFrames": 2,
                        "GopSize": 90,
                        "GopSizeUnits": "FRAMES",
                        "Profile": "MAIN",
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT"
                    }
                },
                "Width": 1280,
                "Height": 720,
                "RespondToAfd": "NONE",
                "Sharpness": 50,
                "ScalingBehavior": "DEFAULT"
            },
            {
                "Name": "video_480p",
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
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT"
                    }
                },
                "Width": 854,
                "Height": 480,
                "RespondToAfd": "NONE",
                "Sharpness": 50,
                "ScalingBehavior": "DEFAULT"
            }
        ],
        "OutputGroups": [
            {
                "Name": "MediaPackage",
                "OutputGroupSettings": {
                    "MediaPackageGroupSettings": {
                        "Destination": {
                            "DestinationRefId": "destination1"
                        }
                    }
                },
                "Outputs": [
                    {
                        "OutputName": "1080p",
                        "VideoDescriptionName": "video_1080p",
                        "AudioDescriptionNames": ["audio_1"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    },
                    {
                        "OutputName": "720p",
                        "VideoDescriptionName": "video_720p",
                        "AudioDescriptionNames": ["audio_1"],
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        }
                    },
                    {
                        "OutputName": "480p",
                        "VideoDescriptionName": "video_480p",
                        "AudioDescriptionNames": ["audio_1"],
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
    }
}
EOF
    
    # Create MediaLive channel
    local channel_id=$(aws medialive create-channel \
        --region "$AWS_REGION" \
        --cli-input-json file://channel-config.json \
        --query 'Channel.Id' --output text)
    
    echo "$channel_id" > .channel_id
    export CHANNEL_ID="$channel_id"
    
    success "Created MediaLive channel: $channel_id"
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution..."
    
    # Extract domain names from endpoints
    local hls_domain=$(echo "$HLS_ENDPOINT" | sed 's|https://||' | cut -d'/' -f1)
    local hls_path=$(echo "$HLS_ENDPOINT" | sed 's|https://[^/]*||')
    
    local dash_domain=$(echo "$DASH_ENDPOINT" | sed 's|https://||' | cut -d'/' -f1)
    local dash_path=$(echo "$DASH_ENDPOINT" | sed 's|https://[^/]*||')
    
    # Create CloudFront distribution configuration
    cat > distribution-config.json << EOF
{
    "CallerReference": "${DISTRIBUTION_NAME}-$(date +%s)",
    "Comment": "Live streaming distribution",
    "DefaultCacheBehavior": {
        "TargetOriginId": "MediaPackage-HLS",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            },
            "Headers": {
                "Quantity": 1,
                "Items": ["*"]
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 5,
        "MaxTTL": 60,
        "Compress": false
    },
    "Origins": {
        "Quantity": 2,
        "Items": [
            {
                "Id": "MediaPackage-HLS",
                "DomainName": "${hls_domain}",
                "OriginPath": "${hls_path}",
                "CustomOriginConfig": {
                    "HTTPPort": 443,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only"
                }
            },
            {
                "Id": "MediaPackage-DASH",
                "DomainName": "${dash_domain}",
                "OriginPath": "${dash_path}",
                "CustomOriginConfig": {
                    "HTTPPort": 443,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "https-only"
                }
            }
        ]
    },
    "CacheBehaviors": {
        "Quantity": 1,
        "Items": [
            {
                "PathPattern": "*.mpd",
                "TargetOriginId": "MediaPackage-DASH",
                "ViewerProtocolPolicy": "redirect-to-https",
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "ForwardedValues": {
                    "QueryString": false,
                    "Cookies": {
                        "Forward": "none"
                    },
                    "Headers": {
                        "Quantity": 1,
                        "Items": ["*"]
                    }
                },
                "MinTTL": 0,
                "DefaultTTL": 5,
                "MaxTTL": 60,
                "Compress": false
            }
        ]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_All"
}
EOF
    
    # Create CloudFront distribution
    local distribution_id=$(aws cloudfront create-distribution \
        --distribution-config file://distribution-config.json \
        --query 'Distribution.Id' --output text)
    
    echo "$distribution_id" > .distribution_id
    export DISTRIBUTION_ID="$distribution_id"
    
    # Get distribution domain name
    local distribution_domain=$(aws cloudfront get-distribution \
        --id "$distribution_id" \
        --query 'Distribution.DomainName' --output text)
    
    echo "$distribution_domain" > .distribution_domain
    export DISTRIBUTION_DOMAIN="$distribution_domain"
    
    success "Created CloudFront distribution: $distribution_id"
    log "Distribution domain: $distribution_domain"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch monitoring alarms..."
    
    # Create SNS topic for alerts (optional)
    local sns_topic_arn=""
    if aws sns create-topic --name medialive-alerts --region "$AWS_REGION" >/dev/null 2>&1; then
        sns_topic_arn=$(aws sns get-topic-attributes \
            --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:medialive-alerts" \
            --query 'Attributes.TopicArn' --output text)
    fi
    
    # Create CloudWatch alarm for MediaLive channel errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "MediaLive-${CHANNEL_NAME}-Errors" \
        --alarm-description "MediaLive channel error alarm" \
        --metric-name "4xxErrors" \
        --namespace "AWS/MediaLive" \
        --statistic "Sum" \
        --period 300 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=ChannelId,Value="$CHANNEL_ID" \
        --region "$AWS_REGION" \
        ${sns_topic_arn:+--alarm-actions "$sns_topic_arn"}
    
    # Create CloudWatch alarm for input video freeze
    aws cloudwatch put-metric-alarm \
        --alarm-name "MediaLive-${CHANNEL_NAME}-InputVideoFreeze" \
        --alarm-description "MediaLive input video freeze alarm" \
        --metric-name "InputVideoFreeze" \
        --namespace "AWS/MediaLive" \
        --statistic "Maximum" \
        --period 300 \
        --threshold 0.5 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 1 \
        --dimensions Name=ChannelId,Value="$CHANNEL_ID" \
        --region "$AWS_REGION" \
        ${sns_topic_arn:+--alarm-actions "$sns_topic_arn"}
    
    success "Created CloudWatch monitoring alarms"
}

# Function to start MediaLive channel
start_medialive_channel() {
    log "Starting MediaLive channel..."
    
    # Start the MediaLive channel
    aws medialive start-channel \
        --region "$AWS_REGION" \
        --channel-id "$CHANNEL_ID"
    
    # Wait for channel to be running
    log "Waiting for channel to start (this may take 2-3 minutes)..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local channel_state=$(aws medialive describe-channel \
            --region "$AWS_REGION" \
            --channel-id "$CHANNEL_ID" \
            --query 'State' --output text)
        
        if [ "$channel_state" = "RUNNING" ]; then
            break
        fi
        
        sleep 10
        attempt=$((attempt + 1))
        log "Channel state: $channel_state (attempt $attempt/$max_attempts)"
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error "Channel failed to start within expected time"
        return 1
    fi
    
    success "MediaLive channel is now running"
}

# Function to create test player
create_test_player() {
    log "Creating test player..."
    
    # Create simple HTML player for testing
    cat > test-player.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Live Stream Test Player</title>
    <script src="https://vjs.zencdn.net/8.0.4/video.js"></script>
    <link href="https://vjs.zencdn.net/8.0.4/video-js.css" rel="stylesheet">
</head>
<body>
    <h1>Live Stream Test Player</h1>
    <video
        id="live-player"
        class="video-js"
        controls
        preload="auto"
        width="1280"
        height="720"
        data-setup="{}">
        <source src="https://${DISTRIBUTION_DOMAIN}/out/v1/index.m3u8" type="application/x-mpegURL">
        <p class="vjs-no-js">
            To view this video please enable JavaScript, and consider upgrading to a web browser that
            <a href="https://videojs.com/html5-video-support/" target="_blank">supports HTML5 video</a>.
        </p>
    </video>
    <script>
        var player = videojs('live-player');
    </script>
</body>
</html>
EOF
    
    # Upload test player to S3
    aws s3 cp test-player.html "s3://${BUCKET_NAME}/test-player.html" \
        --content-type "text/html"
    
    # Enable static website hosting
    aws s3 website "s3://${BUCKET_NAME}" \
        --index-document test-player.html
    
    success "Created test player"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "========================================="
    echo "STREAMING SETUP COMPLETE"
    echo "========================================="
    echo ""
    echo "RTMP Streaming Details:"
    echo "Primary Input URL: $INPUT_URL"
    echo "Stream Key: live"
    echo ""
    echo "Playback URLs:"
    echo "HLS (via CloudFront): https://${DISTRIBUTION_DOMAIN}/out/v1/index.m3u8"
    echo "DASH (via CloudFront): https://${DISTRIBUTION_DOMAIN}/out/v1/index.mpd"
    echo ""
    echo "Test Player: http://${BUCKET_NAME}.s3-website.${AWS_REGION}.amazonaws.com/"
    echo ""
    echo "Resources Created:"
    echo "- S3 Bucket: $BUCKET_NAME"
    echo "- MediaLive Channel: $CHANNEL_ID"
    echo "- MediaPackage Channel: $PACKAGE_CHANNEL_NAME"
    echo "- CloudFront Distribution: $DISTRIBUTION_ID"
    echo "- IAM Role: $IAM_ROLE_NAME"
    echo ""
    echo "To stream content, use the RTMP URL with your streaming software."
    echo "Example with FFmpeg:"
    echo "ffmpeg -re -i your-video.mp4 -c copy -f flv $INPUT_URL/live"
    echo ""
    echo "Important: Remember to run './destroy.sh' to clean up resources and avoid charges!"
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up created resources..."
    
    # Stop the script from exiting on error during cleanup
    set +e
    
    # Clean up resources that may have been created
    if [ -f .channel_id ]; then
        local channel_id=$(cat .channel_id)
        aws medialive stop-channel --region "$AWS_REGION" --channel-id "$channel_id" 2>/dev/null
        sleep 10
        aws medialive delete-channel --region "$AWS_REGION" --channel-id "$channel_id" 2>/dev/null
    fi
    
    if [ -f .distribution_id ]; then
        local distribution_id=$(cat .distribution_id)
        warning "CloudFront distribution $distribution_id created. Manual cleanup may be required."
    fi
    
    if [ -f .package_channel_name ]; then
        aws mediapackage delete-origin-endpoint --region "$AWS_REGION" --id "${PACKAGE_CHANNEL_NAME}-hls" 2>/dev/null
        aws mediapackage delete-origin-endpoint --region "$AWS_REGION" --id "${PACKAGE_CHANNEL_NAME}-dash" 2>/dev/null
        aws mediapackage delete-channel --region "$AWS_REGION" --id "$PACKAGE_CHANNEL_NAME" 2>/dev/null
    fi
    
    if [ -f .input_id ]; then
        local input_id=$(cat .input_id)
        aws medialive delete-input --region "$AWS_REGION" --input-id "$input_id" 2>/dev/null
    fi
    
    if [ -f .security_group_id ]; then
        local security_group_id=$(cat .security_group_id)
        aws medialive delete-input-security-group --region "$AWS_REGION" --input-security-group-id "$security_group_id" 2>/dev/null
    fi
    
    if [ -f .role_arn ]; then
        aws iam detach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/MediaLiveFullAccess 2>/dev/null
        aws iam delete-role --role-name "$IAM_ROLE_NAME" 2>/dev/null
    fi
    
    if [ -f .bucket_name ]; then
        aws s3 rm "s3://$BUCKET_NAME" --recursive 2>/dev/null
        aws s3 rb "s3://$BUCKET_NAME" 2>/dev/null
    fi
    
    # Clean up temporary files
    rm -f .env .*.* *.json test-player.html 2>/dev/null
    
    exit 1
}

# Main deployment function
main() {
    log "Starting AWS Elemental MediaLive Live Streaming Solution deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    validate_aws_credentials
    setup_environment
    create_s3_bucket
    create_input_security_group
    create_medialive_input
    create_mediapackage_channel
    create_mediapackage_endpoints
    create_iam_role
    create_medialive_channel
    create_cloudfront_distribution
    create_cloudwatch_alarms
    start_medialive_channel
    create_test_player
    display_summary
    
    # Clean up temporary files
    rm -f medialive-trust-policy.json channel-config.json distribution-config.json test-player.html
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"