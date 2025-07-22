#!/bin/bash

# Deploy script for AWS Elemental MediaConnect Live Event Broadcasting
# This script creates a complete live broadcasting pipeline with redundancy

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export FLOW_NAME_PRIMARY="live-event-primary-${RANDOM_SUFFIX}"
    export FLOW_NAME_BACKUP="live-event-backup-${RANDOM_SUFFIX}"
    export MEDIALIVE_CHANNEL_NAME="live-event-channel-${RANDOM_SUFFIX}"
    export MEDIAPACKAGE_CHANNEL_ID="live-event-package-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="MediaLiveAccessRole-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > /tmp/live-broadcast-env.txt << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export FLOW_NAME_PRIMARY="$FLOW_NAME_PRIMARY"
export FLOW_NAME_BACKUP="$FLOW_NAME_BACKUP"
export MEDIALIVE_CHANNEL_NAME="$MEDIALIVE_CHANNEL_NAME"
export MEDIAPACKAGE_CHANNEL_ID="$MEDIAPACKAGE_CHANNEL_ID"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
EOF
    
    success "Environment variables configured"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for MediaLive..."
    
    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document '{
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
        }' > /dev/null
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/MediaLiveFullAccess"
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/MediaConnectFullAccess"
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/MediaPackageFullAccess"
    
    # Get role ARN
    export MEDIALIVE_ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    # Add to environment file
    echo "export MEDIALIVE_ROLE_ARN=\"$MEDIALIVE_ROLE_ARN\"" >> /tmp/live-broadcast-env.txt
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 30
    
    success "IAM role created: ${MEDIALIVE_ROLE_ARN}"
}

# Function to create MediaConnect flows
create_mediaconnect_flows() {
    log "Creating MediaConnect flows..."
    
    # Create primary flow
    aws mediaconnect create-flow \
        --name "${FLOW_NAME_PRIMARY}" \
        --description "Primary flow for live event broadcasting" \
        --availability-zone "${AWS_REGION}a" \
        --source \
            Name=PrimarySource,\
            Protocol=rtp,\
            IngestPort=5000,\
            WhitelistCidr=0.0.0.0/0,\
            Description="Primary encoder input" > /dev/null
    
    # Get primary flow ARN
    export PRIMARY_FLOW_ARN=$(aws mediaconnect list-flows \
        --query "Flows[?Name=='${FLOW_NAME_PRIMARY}'].FlowArn" \
        --output text)
    
    # Create backup flow
    aws mediaconnect create-flow \
        --name "${FLOW_NAME_BACKUP}" \
        --description "Backup flow for live event broadcasting" \
        --availability-zone "${AWS_REGION}b" \
        --source \
            Name=BackupSource,\
            Protocol=rtp,\
            IngestPort=5001,\
            WhitelistCidr=0.0.0.0/0,\
            Description="Backup encoder input" > /dev/null
    
    # Get backup flow ARN
    export BACKUP_FLOW_ARN=$(aws mediaconnect list-flows \
        --query "Flows[?Name=='${FLOW_NAME_BACKUP}'].FlowArn" \
        --output text)
    
    # Add to environment file
    echo "export PRIMARY_FLOW_ARN=\"$PRIMARY_FLOW_ARN\"" >> /tmp/live-broadcast-env.txt
    echo "export BACKUP_FLOW_ARN=\"$BACKUP_FLOW_ARN\"" >> /tmp/live-broadcast-env.txt
    
    success "MediaConnect flows created"
}

# Function to configure flow outputs
configure_flow_outputs() {
    log "Configuring MediaConnect flow outputs..."
    
    # Add output to primary flow
    aws mediaconnect add-flow-outputs \
        --flow-arn "${PRIMARY_FLOW_ARN}" \
        --outputs \
            Name=MediaLiveOutput,\
            Protocol=rtp-fec,\
            Destination=0.0.0.0,\
            Port=5002,\
            Description="Output to MediaLive primary input" > /dev/null
    
    # Add output to backup flow
    aws mediaconnect add-flow-outputs \
        --flow-arn "${BACKUP_FLOW_ARN}" \
        --outputs \
            Name=MediaLiveOutput,\
            Protocol=rtp-fec,\
            Destination=0.0.0.0,\
            Port=5003,\
            Description="Output to MediaLive backup input" > /dev/null
    
    success "Flow outputs configured"
}

# Function to create MediaPackage channel
create_mediapackage_channel() {
    log "Creating MediaPackage channel..."
    
    # Create channel
    aws mediapackage create-channel \
        --id "${MEDIAPACKAGE_CHANNEL_ID}" \
        --description "Live event broadcasting channel" > /dev/null
    
    # Get channel details
    export MEDIAPACKAGE_CHANNEL_ARN=$(aws mediapackage describe-channel \
        --id "${MEDIAPACKAGE_CHANNEL_ID}" \
        --query Arn --output text)
    
    # Get ingest endpoints
    export MEDIAPACKAGE_INGEST_URL=$(aws mediapackage describe-channel \
        --id "${MEDIAPACKAGE_CHANNEL_ID}" \
        --query 'HlsIngest.IngestEndpoints[0].Url' \
        --output text)
    
    # Add to environment file
    echo "export MEDIAPACKAGE_CHANNEL_ARN=\"$MEDIAPACKAGE_CHANNEL_ARN\"" >> /tmp/live-broadcast-env.txt
    echo "export MEDIAPACKAGE_INGEST_URL=\"$MEDIAPACKAGE_INGEST_URL\"" >> /tmp/live-broadcast-env.txt
    
    success "MediaPackage channel created"
}

# Function to create MediaLive inputs
create_medialive_inputs() {
    log "Creating MediaLive inputs..."
    
    # Create primary input
    aws medialive create-input \
        --name "${FLOW_NAME_PRIMARY}-input" \
        --type MEDIACONNECT \
        --mediaconnect-flows \
            FlowArn="${PRIMARY_FLOW_ARN}" \
        --role-arn "${MEDIALIVE_ROLE_ARN}" > /dev/null
    
    # Get primary input ID
    export PRIMARY_INPUT_ID=$(aws medialive list-inputs \
        --query "Inputs[?Name=='${FLOW_NAME_PRIMARY}-input'].Id" \
        --output text)
    
    # Create backup input
    aws medialive create-input \
        --name "${FLOW_NAME_BACKUP}-input" \
        --type MEDIACONNECT \
        --mediaconnect-flows \
            FlowArn="${BACKUP_FLOW_ARN}" \
        --role-arn "${MEDIALIVE_ROLE_ARN}" > /dev/null
    
    # Get backup input ID
    export BACKUP_INPUT_ID=$(aws medialive list-inputs \
        --query "Inputs[?Name=='${FLOW_NAME_BACKUP}-input'].Id" \
        --output text)
    
    # Add to environment file
    echo "export PRIMARY_INPUT_ID=\"$PRIMARY_INPUT_ID\"" >> /tmp/live-broadcast-env.txt
    echo "export BACKUP_INPUT_ID=\"$BACKUP_INPUT_ID\"" >> /tmp/live-broadcast-env.txt
    
    success "MediaLive inputs created"
}

# Function to create MediaLive channel
create_medialive_channel() {
    log "Creating MediaLive channel..."
    
    # Create channel configuration
    cat > /tmp/medialive-channel-config.json << EOF
{
    "Name": "${MEDIALIVE_CHANNEL_NAME}",
    "RoleArn": "${MEDIALIVE_ROLE_ARN}",
    "InputAttachments": [
        {
            "InputAttachmentName": "primary-input",
            "InputId": "${PRIMARY_INPUT_ID}",
            "InputSettings": {
                "AudioSelectors": [
                    {
                        "Name": "default",
                        "SelectorSettings": {
                            "AudioPidSelection": {
                                "Pid": 256
                            }
                        }
                    }
                ],
                "VideoSelector": {
                    "ProgramId": 1
                }
            }
        },
        {
            "InputAttachmentName": "backup-input",
            "InputId": "${BACKUP_INPUT_ID}",
            "InputSettings": {
                "AudioSelectors": [
                    {
                        "Name": "default",
                        "SelectorSettings": {
                            "AudioPidSelection": {
                                "Pid": 256
                            }
                        }
                    }
                ],
                "VideoSelector": {
                    "ProgramId": 1
                }
            }
        }
    ],
    "Destinations": [
        {
            "Id": "mediapackage-destination",
            "MediaPackageSettings": [
                {
                    "ChannelId": "${MEDIAPACKAGE_CHANNEL_ID}"
                }
            ]
        }
    ],
    "EncoderSettings": {
        "AudioDescriptions": [
            {
                "AudioSelectorName": "default",
                "CodecSettings": {
                    "AacSettings": {
                        "Bitrate": 128000,
                        "CodingMode": "CODING_MODE_2_0",
                        "InputType": "BROADCASTER_MIXED_AD",
                        "Profile": "LC",
                        "SampleRate": 48000
                    }
                },
                "Name": "audio_1"
            }
        ],
        "VideoDescriptions": [
            {
                "CodecSettings": {
                    "H264Settings": {
                        "Bitrate": 2000000,
                        "FramerateControl": "SPECIFIED",
                        "FramerateDenominator": 1,
                        "FramerateNumerator": 30,
                        "GopBReference": "DISABLED",
                        "GopClosedCadence": 1,
                        "GopNumBFrames": 2,
                        "GopSize": 90,
                        "GopSizeUnits": "FRAMES",
                        "Level": "H264_LEVEL_4_1",
                        "LookAheadRateControl": "MEDIUM",
                        "MaxBitrate": 2000000,
                        "NumRefFrames": 3,
                        "ParControl": "INITIALIZE_FROM_SOURCE",
                        "Profile": "MAIN",
                        "RateControlMode": "CBR",
                        "Syntax": "DEFAULT"
                    }
                },
                "Height": 720,
                "Name": "video_720p30",
                "RespondToAfd": "NONE",
                "Sharpness": 50,
                "Width": 1280
            }
        ],
        "OutputGroups": [
            {
                "Name": "mediapackage-output-group",
                "OutputGroupSettings": {
                    "MediaPackageGroupSettings": {
                        "Destination": {
                            "DestinationRefId": "mediapackage-destination"
                        }
                    }
                },
                "Outputs": [
                    {
                        "AudioDescriptionNames": ["audio_1"],
                        "OutputName": "720p30",
                        "OutputSettings": {
                            "MediaPackageOutputSettings": {}
                        },
                        "VideoDescriptionName": "video_720p30"
                    }
                ]
            }
        ]
    },
    "InputSpecification": {
        "Codec": "AVC",
        "Resolution": "HD",
        "MaximumBitrate": "MAX_10_MBPS"
    }
}
EOF
    
    # Create channel
    aws medialive create-channel \
        --cli-input-json file:///tmp/medialive-channel-config.json > /dev/null
    
    # Get channel ID
    export MEDIALIVE_CHANNEL_ID=$(aws medialive list-channels \
        --query "Channels[?Name=='${MEDIALIVE_CHANNEL_NAME}'].Id" \
        --output text)
    
    # Add to environment file
    echo "export MEDIALIVE_CHANNEL_ID=\"$MEDIALIVE_CHANNEL_ID\"" >> /tmp/live-broadcast-env.txt
    
    # Wait for channel to be ready
    log "Waiting for MediaLive channel to be ready..."
    aws medialive wait channel-created --channel-id "${MEDIALIVE_CHANNEL_ID}"
    
    success "MediaLive channel created: ${MEDIALIVE_CHANNEL_ID}"
}

# Function to create MediaPackage endpoint
create_mediapackage_endpoint() {
    log "Creating MediaPackage origin endpoint..."
    
    # Create HLS endpoint
    aws mediapackage create-origin-endpoint \
        --channel-id "${MEDIAPACKAGE_CHANNEL_ID}" \
        --id "${MEDIAPACKAGE_CHANNEL_ID}-hls" \
        --description "HLS endpoint for live event broadcasting" \
        --hls-package \
            AdMarkers=NONE,\
            IncludeIframeOnlyStream=false,\
            PlaylistType=EVENT,\
            PlaylistWindowSeconds=60,\
            ProgramDateTimeIntervalSeconds=0,\
            SegmentDurationSeconds=6,\
            StreamSelection='{
                "MaxVideoBitsPerSecond": 2147483647,
                "MinVideoBitsPerSecond": 0,
                "StreamOrder": "ORIGINAL"
            }' > /dev/null
    
    # Get endpoint URL
    export HLS_ENDPOINT_URL=$(aws mediapackage describe-origin-endpoint \
        --id "${MEDIAPACKAGE_CHANNEL_ID}-hls" \
        --query Url --output text)
    
    # Add to environment file
    echo "export HLS_ENDPOINT_URL=\"$HLS_ENDPOINT_URL\"" >> /tmp/live-broadcast-env.txt
    
    success "MediaPackage HLS endpoint created"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Create alarm for primary flow
    aws cloudwatch put-metric-alarm \
        --alarm-name "${FLOW_NAME_PRIMARY}-source-errors" \
        --alarm-description "Alert on MediaConnect primary flow source errors" \
        --metric-name "SourceConnectionErrors" \
        --namespace "AWS/MediaConnect" \
        --statistic "Sum" \
        --period 300 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 1 \
        --dimensions Name=FlowName,Value="${FLOW_NAME_PRIMARY}" > /dev/null
    
    # Create alarm for MediaLive channel
    aws cloudwatch put-metric-alarm \
        --alarm-name "${MEDIALIVE_CHANNEL_NAME}-input-errors" \
        --alarm-description "Alert on MediaLive channel input errors" \
        --metric-name "InputVideoFrameRate" \
        --namespace "AWS/MediaLive" \
        --statistic "Average" \
        --period 300 \
        --threshold 1 \
        --comparison-operator "LessThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=ChannelId,Value="${MEDIALIVE_CHANNEL_ID}" > /dev/null
    
    # Create log groups
    aws logs create-log-group \
        --log-group-name "/aws/mediaconnect/${FLOW_NAME_PRIMARY}" || true
    
    aws logs create-log-group \
        --log-group-name "/aws/mediaconnect/${FLOW_NAME_BACKUP}" || true
    
    success "CloudWatch monitoring configured"
}

# Function to start the pipeline
start_pipeline() {
    log "Starting broadcasting pipeline..."
    
    # Start flows
    aws mediaconnect start-flow --flow-arn "${PRIMARY_FLOW_ARN}" > /dev/null
    aws mediaconnect start-flow --flow-arn "${BACKUP_FLOW_ARN}" > /dev/null
    
    # Start MediaLive channel
    aws medialive start-channel --channel-id "${MEDIALIVE_CHANNEL_ID}" > /dev/null
    
    # Wait for channel to start
    log "Waiting for MediaLive channel to start..."
    aws medialive wait channel-running --channel-id "${MEDIALIVE_CHANNEL_ID}"
    
    success "Broadcasting pipeline started"
}

# Function to display deployment summary
show_deployment_summary() {
    log "Deployment completed successfully!"
    
    # Get endpoint information
    PRIMARY_INGEST_IP=$(aws mediaconnect describe-flow \
        --flow-arn "${PRIMARY_FLOW_ARN}" \
        --query 'Flow.Source.IngestIp' --output text)
    
    BACKUP_INGEST_IP=$(aws mediaconnect describe-flow \
        --flow-arn "${BACKUP_FLOW_ARN}" \
        --query 'Flow.Source.IngestIp' --output text)
    
    echo
    echo "================================================="
    echo "        LIVE BROADCASTING DEPLOYMENT SUMMARY"
    echo "================================================="
    echo
    echo "Encoder Endpoints:"
    echo "  Primary: ${PRIMARY_INGEST_IP}:5000"
    echo "  Backup:  ${BACKUP_INGEST_IP}:5001"
    echo
    echo "Viewer Endpoint:"
    echo "  HLS URL: ${HLS_ENDPOINT_URL}"
    echo
    echo "AWS Resources Created:"
    echo "  MediaConnect Flows: ${FLOW_NAME_PRIMARY}, ${FLOW_NAME_BACKUP}"
    echo "  MediaLive Channel: ${MEDIALIVE_CHANNEL_NAME}"
    echo "  MediaPackage Channel: ${MEDIAPACKAGE_CHANNEL_ID}"
    echo "  IAM Role: ${IAM_ROLE_NAME}"
    echo
    echo "Environment file saved to: /tmp/live-broadcast-env.txt"
    echo "Use this file with destroy.sh to clean up resources."
    echo
    echo "To clean up resources, run: ./destroy.sh"
    echo "================================================="
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up partially created resources..."
    
    # Source environment if it exists
    if [[ -f /tmp/live-broadcast-env.txt ]]; then
        source /tmp/live-broadcast-env.txt
        
        # Clean up resources that might have been created
        ./destroy.sh --force 2>/dev/null || true
    fi
    
    rm -f /tmp/medialive-channel-config.json
    rm -f /tmp/live-broadcast-env.txt
    
    exit 1
}

# Main deployment function
main() {
    echo "=========================================="
    echo "AWS Live Event Broadcasting Deployment"
    echo "=========================================="
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_mediaconnect_flows
    configure_flow_outputs
    create_mediapackage_channel
    create_medialive_inputs
    create_medialive_channel
    create_mediapackage_endpoint
    configure_monitoring
    start_pipeline
    
    # Clean up temporary files
    rm -f /tmp/medialive-channel-config.json
    
    show_deployment_summary
}

# Run main function
main "$@"