#!/bin/bash

# Adaptive Bitrate Streaming with MediaConvert and CloudFront - Deployment Script
# This script deploys the complete infrastructure for ABR streaming solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
        *)     echo -e "$message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log ERROR "$1"
    log ERROR "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log WARN "Cleaning up resources due to deployment failure..."
    
    # Cancel any running MediaConvert jobs
    if [ ! -z "${MEDIACONVERT_ENDPOINT:-}" ]; then
        aws mediaconvert list-jobs \
            --endpoint-url "${MEDIACONVERT_ENDPOINT}" \
            --status PROGRESSING \
            --query 'Jobs[].Id' --output text 2>/dev/null | \
        while read -r job_id; do
            if [ ! -z "$job_id" ]; then
                aws mediaconvert cancel-job \
                    --endpoint-url "${MEDIACONVERT_ENDPOINT}" \
                    --id "$job_id" 2>/dev/null || true
                log INFO "Cancelled MediaConvert job: $job_id"
            fi
        done
    fi
    
    # Remove S3 event notifications if they exist
    if [ ! -z "${SOURCE_BUCKET:-}" ]; then
        aws s3api put-bucket-notification-configuration \
            --bucket "${SOURCE_BUCKET}" \
            --notification-configuration '{}' 2>/dev/null || true
    fi
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Adaptive Bitrate Streaming infrastructure with MediaConvert and CloudFront

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -r, --region        AWS region (default: current configured region)
    -p, --prefix        Resource name prefix (default: abr-streaming)
    -v, --verbose       Enable verbose logging

EXAMPLES:
    $0                              # Deploy with default settings
    $0 --dry-run                    # Preview deployment
    $0 --region us-west-2           # Deploy to specific region
    $0 --prefix my-streaming        # Use custom resource prefix

ENVIRONMENT VARIABLES:
    AWS_REGION          AWS region for deployment
    RESOURCE_PREFIX     Prefix for resource names

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                RESOURCE_PREFIX="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo "$aws_version" | cut -d. -f1)
    if [ "$major_version" -lt 2 ]; then
        error_exit "AWS CLI v2 is required. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required utilities
    for cmd in jq zip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error_exit "$cmd is required but not installed."
        fi
    done
    
    # Check AWS permissions
    log INFO "Validating AWS permissions..."
    local required_services=("s3" "mediaconvert" "lambda" "iam" "cloudfront")
    for service in "${required_services[@]}"; do
        case $service in
            s3)
                aws s3 ls >/dev/null 2>&1 || error_exit "Missing S3 permissions"
                ;;
            mediaconvert)
                aws mediaconvert describe-endpoints --region "$AWS_REGION" >/dev/null 2>&1 || error_exit "Missing MediaConvert permissions"
                ;;
            lambda)
                aws lambda list-functions --region "$AWS_REGION" >/dev/null 2>&1 || error_exit "Missing Lambda permissions"
                ;;
            iam)
                aws iam list-roles >/dev/null 2>&1 || error_exit "Missing IAM permissions"
                ;;
            cloudfront)
                aws cloudfront list-distributions >/dev/null 2>&1 || error_exit "Missing CloudFront permissions"
                ;;
        esac
    done
    
    log INFO "Prerequisites check completed successfully"
}

# Initialize environment variables
init_environment() {
    log INFO "Initializing environment variables..."
    
    # Set defaults
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export RESOURCE_PREFIX="${RESOURCE_PREFIX:-abr-streaming}"
    
    # Generate unique suffix
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export SOURCE_BUCKET="${RESOURCE_PREFIX}-source-${random_suffix}"
    export OUTPUT_BUCKET="${RESOURCE_PREFIX}-output-${random_suffix}"
    export LAMBDA_FUNCTION="${RESOURCE_PREFIX}-processor-${random_suffix}"
    export MEDIACONVERT_ROLE="${RESOURCE_PREFIX}-MediaConvertRole-${random_suffix}"
    export JOB_TEMPLATE="${RESOURCE_PREFIX}-ABRTemplate-${random_suffix}"
    
    # Get MediaConvert endpoint
    export MEDIACONVERT_ENDPOINT=$(aws mediaconvert describe-endpoints \
        --region "$AWS_REGION" \
        --query Endpoints[0].Url --output text)
    
    log INFO "Environment initialized:"
    log INFO "  Region: $AWS_REGION"
    log INFO "  Account ID: $AWS_ACCOUNT_ID"
    log INFO "  Resource Prefix: $RESOURCE_PREFIX"
    log INFO "  MediaConvert Endpoint: $MEDIACONVERT_ENDPOINT"
}

# Create S3 buckets
create_s3_buckets() {
    log INFO "Creating S3 buckets..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would create S3 buckets: $SOURCE_BUCKET, $OUTPUT_BUCKET"
        return 0
    fi
    
    # Create source bucket
    aws s3 mb "s3://$SOURCE_BUCKET" --region "$AWS_REGION"
    log INFO "Created source bucket: $SOURCE_BUCKET"
    
    # Create output bucket
    aws s3 mb "s3://$OUTPUT_BUCKET" --region "$AWS_REGION"
    log INFO "Created output bucket: $OUTPUT_BUCKET"
    
    # Configure CORS for output bucket
    cat > /tmp/cors-config.json << EOF
{
    "CORSRules": [
        {
            "AllowedOrigins": ["*"],
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "HEAD"],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOF
    
    aws s3api put-bucket-cors \
        --bucket "$OUTPUT_BUCKET" \
        --cors-configuration file:///tmp/cors-config.json
    
    log INFO "Configured CORS for output bucket"
}

# Create IAM roles
create_iam_roles() {
    log INFO "Creating IAM roles..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would create IAM roles: $MEDIACONVERT_ROLE, ${LAMBDA_FUNCTION}-role"
        return 0
    fi
    
    # Create MediaConvert service role
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
    
    aws iam create-role \
        --role-name "$MEDIACONVERT_ROLE" \
        --assume-role-policy-document file:///tmp/mediaconvert-trust-policy.json
    
    # Create S3 access policy for MediaConvert
    cat > /tmp/mediaconvert-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::$SOURCE_BUCKET",
                "arn:aws:s3:::$SOURCE_BUCKET/*",
                "arn:aws:s3:::$OUTPUT_BUCKET",
                "arn:aws:s3:::$OUTPUT_BUCKET/*"
            ]
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "$MEDIACONVERT_ROLE" \
        --policy-name S3AccessPolicy \
        --policy-document file:///tmp/mediaconvert-s3-policy.json
    
    export MEDIACONVERT_ROLE_ARN=$(aws iam get-role \
        --role-name "$MEDIACONVERT_ROLE" \
        --query Role.Arn --output text)
    
    log INFO "Created MediaConvert role: $MEDIACONVERT_ROLE_ARN"
    
    # Create Lambda execution role
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
    
    aws iam create-role \
        --role-name "${LAMBDA_FUNCTION}-role" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION}-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create MediaConvert access policy for Lambda
    cat > /tmp/lambda-mediaconvert-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mediaconvert:CreateJob",
                "mediaconvert:GetJob",
                "mediaconvert:ListJobs",
                "mediaconvert:GetJobTemplate"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": "$MEDIACONVERT_ROLE_ARN"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_FUNCTION}-role" \
        --policy-name MediaConvertAccessPolicy \
        --policy-document file:///tmp/lambda-mediaconvert-policy.json
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_FUNCTION}-role" \
        --query Role.Arn --output text)
    
    log INFO "Created Lambda role: $LAMBDA_ROLE_ARN"
    
    # Wait for role propagation
    log INFO "Waiting for IAM role propagation..."
    sleep 15
}

# Create MediaConvert job template
create_mediaconvert_template() {
    log INFO "Creating MediaConvert job template..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would create MediaConvert job template: $JOB_TEMPLATE"
        return 0
    fi
    
    # Create comprehensive ABR job template
    cat > /tmp/abr-job-template.json << EOF
{
    "Name": "$JOB_TEMPLATE",
    "Description": "Adaptive bitrate streaming template with HLS and DASH outputs",
    "Settings": {
        "OutputGroups": [
            {
                "Name": "HLS_ABR_Package",
                "OutputGroupSettings": {
                    "Type": "HLS_GROUP_SETTINGS",
                    "HlsGroupSettings": {
                        "Destination": "s3://$OUTPUT_BUCKET/hls/",
                        "HlsCdnSettings": {
                            "HlsBasicPutSettings": {
                                "ConnectionRetryInterval": 1,
                                "FilecacheDuration": 300,
                                "NumRetries": 10
                            }
                        },
                        "ManifestDurationFormat": "FLOATING_POINT",
                        "OutputSelection": "MANIFESTS_AND_SEGMENTS",
                        "SegmentControl": "SEGMENTED_FILES",
                        "SegmentLength": 6,
                        "TimedMetadataId3Frame": "PRIV",
                        "TimedMetadataId3Period": 10,
                        "MinSegmentLength": 0,
                        "DirectoryStructure": "SINGLE_DIRECTORY"
                    }
                },
                "Outputs": [
                    {
                        "NameModifier": "_1080p",
                        "ContainerSettings": {
                            "Container": "M3U8",
                            "M3u8Settings": {
                                "PcrControl": "PCR_EVERY_PES_PACKET",
                                "PmtPid": 480,
                                "PrivateMetadataPid": 503,
                                "ProgramNumber": 1,
                                "PatInterval": 0,
                                "PmtInterval": 0,
                                "VideoPid": 481,
                                "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                            }
                        },
                        "VideoDescription": {
                            "Width": 1920,
                            "Height": 1080,
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "QvbrSettings": {
                                        "QvbrQualityLevel": 8
                                    },
                                    "MaxBitrate": 5000000,
                                    "FramerateControl": "INITIALIZE_FROM_SOURCE",
                                    "GopClosedCadence": 1,
                                    "GopSize": 90,
                                    "GopSizeUnits": "FRAMES",
                                    "ParControl": "INITIALIZE_FROM_SOURCE",
                                    "QualityTuningLevel": "SINGLE_PASS",
                                    "SceneChangeDetect": "ENABLED"
                                }
                            }
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "AAC",
                                    "AacSettings": {
                                        "Bitrate": 128000,
                                        "CodingMode": "CODING_MODE_2_0",
                                        "SampleRate": 48000
                                    }
                                }
                            }
                        ]
                    },
                    {
                        "NameModifier": "_720p",
                        "ContainerSettings": {
                            "Container": "M3U8",
                            "M3u8Settings": {
                                "PcrControl": "PCR_EVERY_PES_PACKET",
                                "PmtPid": 480,
                                "PrivateMetadataPid": 503,
                                "ProgramNumber": 1,
                                "PatInterval": 0,
                                "PmtInterval": 0,
                                "VideoPid": 481,
                                "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                            }
                        },
                        "VideoDescription": {
                            "Width": 1280,
                            "Height": 720,
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "QvbrSettings": {
                                        "QvbrQualityLevel": 7
                                    },
                                    "MaxBitrate": 3000000,
                                    "FramerateControl": "INITIALIZE_FROM_SOURCE",
                                    "GopClosedCadence": 1,
                                    "GopSize": 90,
                                    "GopSizeUnits": "FRAMES",
                                    "ParControl": "INITIALIZE_FROM_SOURCE",
                                    "QualityTuningLevel": "SINGLE_PASS",
                                    "SceneChangeDetect": "ENABLED"
                                }
                            }
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "AAC",
                                    "AacSettings": {
                                        "Bitrate": 128000,
                                        "CodingMode": "CODING_MODE_2_0",
                                        "SampleRate": 48000
                                    }
                                }
                            }
                        ]
                    },
                    {
                        "NameModifier": "_480p",
                        "ContainerSettings": {
                            "Container": "M3U8",
                            "M3u8Settings": {
                                "PcrControl": "PCR_EVERY_PES_PACKET",
                                "PmtPid": 480,
                                "PrivateMetadataPid": 503,
                                "ProgramNumber": 1,
                                "PatInterval": 0,
                                "PmtInterval": 0,
                                "VideoPid": 481,
                                "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                            }
                        },
                        "VideoDescription": {
                            "Width": 854,
                            "Height": 480,
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "QvbrSettings": {
                                        "QvbrQualityLevel": 6
                                    },
                                    "MaxBitrate": 1500000,
                                    "FramerateControl": "INITIALIZE_FROM_SOURCE",
                                    "GopClosedCadence": 1,
                                    "GopSize": 90,
                                    "GopSizeUnits": "FRAMES",
                                    "ParControl": "INITIALIZE_FROM_SOURCE",
                                    "QualityTuningLevel": "SINGLE_PASS",
                                    "SceneChangeDetect": "ENABLED"
                                }
                            }
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "AAC",
                                    "AacSettings": {
                                        "Bitrate": 96000,
                                        "CodingMode": "CODING_MODE_2_0",
                                        "SampleRate": 48000
                                    }
                                }
                            }
                        ]
                    },
                    {
                        "NameModifier": "_360p",
                        "ContainerSettings": {
                            "Container": "M3U8",
                            "M3u8Settings": {
                                "PcrControl": "PCR_EVERY_PES_PACKET",
                                "PmtPid": 480,
                                "PrivateMetadataPid": 503,
                                "ProgramNumber": 1,
                                "PatInterval": 0,
                                "PmtInterval": 0,
                                "VideoPid": 481,
                                "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                            }
                        },
                        "VideoDescription": {
                            "Width": 640,
                            "Height": 360,
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "QvbrSettings": {
                                        "QvbrQualityLevel": 5
                                    },
                                    "MaxBitrate": 800000,
                                    "FramerateControl": "INITIALIZE_FROM_SOURCE",
                                    "GopClosedCadence": 1,
                                    "GopSize": 90,
                                    "GopSizeUnits": "FRAMES",
                                    "ParControl": "INITIALIZE_FROM_SOURCE",
                                    "QualityTuningLevel": "SINGLE_PASS",
                                    "SceneChangeDetect": "ENABLED"
                                }
                            }
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "AAC",
                                    "AacSettings": {
                                        "Bitrate": 64000,
                                        "CodingMode": "CODING_MODE_2_0",
                                        "SampleRate": 48000
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            {
                "Name": "DASH_ABR_Package",
                "OutputGroupSettings": {
                    "Type": "DASH_ISO_GROUP_SETTINGS",
                    "DashIsoGroupSettings": {
                        "Destination": "s3://$OUTPUT_BUCKET/dash/",
                        "FragmentLength": 2,
                        "SegmentControl": "SEGMENTED_FILES",
                        "SegmentLength": 30,
                        "MpdProfile": "ON_DEMAND_PROFILE",
                        "HbbtvCompliance": "NONE"
                    }
                },
                "Outputs": [
                    {
                        "NameModifier": "_dash_1080p",
                        "ContainerSettings": {
                            "Container": "MP4",
                            "Mp4Settings": {
                                "CslgAtom": "INCLUDE",
                                "FreeSpaceBox": "EXCLUDE",
                                "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                            }
                        },
                        "VideoDescription": {
                            "Width": 1920,
                            "Height": 1080,
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "QvbrSettings": {
                                        "QvbrQualityLevel": 8
                                    },
                                    "MaxBitrate": 5000000,
                                    "FramerateControl": "INITIALIZE_FROM_SOURCE",
                                    "GopClosedCadence": 1,
                                    "GopSize": 90,
                                    "GopSizeUnits": "FRAMES",
                                    "ParControl": "INITIALIZE_FROM_SOURCE",
                                    "QualityTuningLevel": "SINGLE_PASS",
                                    "SceneChangeDetect": "ENABLED"
                                }
                            }
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "AAC",
                                    "AacSettings": {
                                        "Bitrate": 128000,
                                        "CodingMode": "CODING_MODE_2_0",
                                        "SampleRate": 48000
                                    }
                                }
                            }
                        ]
                    },
                    {
                        "NameModifier": "_dash_720p",
                        "ContainerSettings": {
                            "Container": "MP4",
                            "Mp4Settings": {
                                "CslgAtom": "INCLUDE",
                                "FreeSpaceBox": "EXCLUDE",
                                "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                            }
                        },
                        "VideoDescription": {
                            "Width": 1280,
                            "Height": 720,
                            "CodecSettings": {
                                "Codec": "H_264",
                                "H264Settings": {
                                    "RateControlMode": "QVBR",
                                    "QvbrSettings": {
                                        "QvbrQualityLevel": 7
                                    },
                                    "MaxBitrate": 3000000,
                                    "FramerateControl": "INITIALIZE_FROM_SOURCE",
                                    "GopClosedCadence": 1,
                                    "GopSize": 90,
                                    "GopSizeUnits": "FRAMES",
                                    "ParControl": "INITIALIZE_FROM_SOURCE",
                                    "QualityTuningLevel": "SINGLE_PASS",
                                    "SceneChangeDetect": "ENABLED"
                                }
                            }
                        },
                        "AudioDescriptions": [
                            {
                                "AudioTypeControl": "FOLLOW_INPUT",
                                "CodecSettings": {
                                    "Codec": "AAC",
                                    "AacSettings": {
                                        "Bitrate": 128000,
                                        "CodingMode": "CODING_MODE_2_0",
                                        "SampleRate": 48000
                                    }
                                }
                            }
                        ]
                    }
                ]
            },
            {
                "Name": "Thumbnail_Output",
                "OutputGroupSettings": {
                    "Type": "FILE_GROUP_SETTINGS",
                    "FileGroupSettings": {
                        "Destination": "s3://$OUTPUT_BUCKET/thumbnails/"
                    }
                },
                "Outputs": [
                    {
                        "NameModifier": "_thumb_%04d",
                        "ContainerSettings": {
                            "Container": "RAW"
                        },
                        "VideoDescription": {
                            "Width": 1280,
                            "Height": 720,
                            "CodecSettings": {
                                "Codec": "FRAME_CAPTURE",
                                "FrameCaptureSettings": {
                                    "FramerateNumerator": 1,
                                    "FramerateDenominator": 10,
                                    "MaxCaptures": 10,
                                    "Quality": 80
                                }
                            }
                        }
                    }
                ]
            }
        ],
        "Inputs": [
            {
                "FileInput": "s3://$SOURCE_BUCKET/",
                "AudioSelectors": {
                    "Audio Selector 1": {
                        "Tracks": [1],
                        "DefaultSelection": "DEFAULT"
                    }
                },
                "VideoSelector": {
                    "ColorSpace": "FOLLOW"
                },
                "TimecodeSource": "EMBEDDED"
            }
        ]
    }
}
EOF
    
    aws mediaconvert create-job-template \
        --endpoint-url "$MEDIACONVERT_ENDPOINT" \
        --cli-input-json file:///tmp/abr-job-template.json
    
    log INFO "Created MediaConvert job template: $JOB_TEMPLATE"
}

# Create Lambda function
create_lambda_function() {
    log INFO "Creating Lambda function..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION"
        return 0
    fi
    
    # Create Lambda function code
    cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    # Initialize MediaConvert client
    mediaconvert = boto3.client('mediaconvert', 
        endpoint_url=os.environ['MEDIACONVERT_ENDPOINT'])
    
    # Process S3 event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Only process video files
        video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.mxf', '.mts', '.m2ts')
        if not key.lower().endswith(video_extensions):
            print(f"Skipping non-video file: {key}")
            continue
        
        # Extract filename without extension for output naming
        file_name = key.split('/')[-1].split('.')[0]
        
        # Create MediaConvert job for ABR processing
        job_settings = {
            "JobTemplate": os.environ['JOB_TEMPLATE'],
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
                        },
                        "VideoSelector": {
                            "ColorSpace": "FOLLOW"
                        },
                        "TimecodeSource": "EMBEDDED"
                    }
                ],
                "OutputGroups": [
                    {
                        "OutputGroupSettings": {
                            "Type": "HLS_GROUP_SETTINGS",
                            "HlsGroupSettings": {
                                "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/hls/{file_name}/"
                            }
                        }
                    },
                    {
                        "OutputGroupSettings": {
                            "Type": "DASH_ISO_GROUP_SETTINGS", 
                            "DashIsoGroupSettings": {
                                "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/dash/{file_name}/"
                            }
                        }
                    },
                    {
                        "OutputGroupSettings": {
                            "Type": "FILE_GROUP_SETTINGS",
                            "FileGroupSettings": {
                                "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/thumbnails/{file_name}/"
                            }
                        }
                    }
                ]
            },
            "StatusUpdateInterval": "SECONDS_60",
            "UserMetadata": {
                "SourceFile": key,
                "ProcessingType": "ABR_Streaming"
            }
        }
        
        try:
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            print(f"Created ABR processing job {job_id} for {key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Successfully started ABR processing job {job_id}',
                    'jobId': job_id,
                    'sourceFile': key,
                    'hlsOutput': f"s3://{os.environ['OUTPUT_BUCKET']}/hls/{file_name}/",
                    'dashOutput': f"s3://{os.environ['OUTPUT_BUCKET']}/dash/{file_name}/"
                })
            }
        except Exception as e:
            print(f"Error creating MediaConvert job: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': str(e),
                    'sourceFile': key
                })
            }
EOF
    
    # Create deployment package
    cd /tmp
    zip lambda-abr-function.zip lambda_function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-abr-function.zip \
        --timeout 300 \
        --environment Variables="{MEDIACONVERT_ENDPOINT=$MEDIACONVERT_ENDPOINT,JOB_TEMPLATE=$JOB_TEMPLATE,MEDIACONVERT_ROLE_ARN=$MEDIACONVERT_ROLE_ARN,OUTPUT_BUCKET=$OUTPUT_BUCKET}"
    
    log INFO "Created Lambda function: $LAMBDA_FUNCTION"
    
    cd "$SCRIPT_DIR"
}

# Configure S3 event notifications
configure_s3_events() {
    log INFO "Configuring S3 event notifications..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would configure S3 event notifications for $SOURCE_BUCKET"
        return 0
    fi
    
    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION" \
        --principal s3.amazonaws.com \
        --statement-id s3-video-trigger \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::$SOURCE_BUCKET"
    
    # Create S3 notification configuration
    cat > /tmp/s3-video-notification.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "VideoABRProcessingTrigger",
            "LambdaFunctionArn": "arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$LAMBDA_FUNCTION",
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
        },
        {
            "Id": "VideoABRProcessingTriggerMOV",
            "LambdaFunctionArn": "arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$LAMBDA_FUNCTION",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".mov"
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
        --bucket "$SOURCE_BUCKET" \
        --notification-configuration file:///tmp/s3-video-notification.json
    
    log INFO "Configured S3 event notifications"
}

# Create CloudFront distribution
create_cloudfront_distribution() {
    log INFO "Creating CloudFront distribution..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would create CloudFront distribution"
        return 0
    fi
    
    # Create CloudFront distribution configuration
    cat > /tmp/cloudfront-abr-distribution.json << EOF
{
    "CallerReference": "ABR-Streaming-${RANDOM_SUFFIX}-$(date +%s)",
    "Comment": "Adaptive Bitrate Streaming Distribution",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-ABR-Output",
        "ViewerProtocolPolicy": "redirect-to-https",
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
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
        "DefaultTTL": 86400,
        "MaxTTL": 31536000
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-ABR-Output",
                "DomainName": "$OUTPUT_BUCKET.s3.$AWS_REGION.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                }
            }
        ]
    },
    "CacheBehaviors": {
        "Quantity": 3,
        "Items": [
            {
                "PathPattern": "*.m3u8",
                "TargetOriginId": "S3-ABR-Output",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
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
                "PathPattern": "*.mpd",
                "TargetOriginId": "S3-ABR-Output",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
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
                "PathPattern": "*.ts",
                "TargetOriginId": "S3-ABR-Output",
                "ViewerProtocolPolicy": "redirect-to-https",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
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
                "DefaultTTL": 86400,
                "MaxTTL": 86400
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
    "HttpVersion": "http2",
    "IsIPV6Enabled": true
}
EOF
    
    # Create CloudFront distribution
    export DISTRIBUTION_ID=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/cloudfront-abr-distribution.json \
        --query 'Distribution.Id' --output text)
    
    # Get distribution domain name
    export DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'Distribution.DomainName' --output text)
    
    log INFO "Created CloudFront distribution: $DISTRIBUTION_ID"
    log INFO "Distribution domain: $DISTRIBUTION_DOMAIN"
}

# Create test player
create_test_player() {
    log INFO "Creating test player..."
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would create test player"
        return 0
    fi
    
    # Create HTML5 video player
    cat > /tmp/abr-test-player.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Adaptive Bitrate Streaming Test Player</title>
    <script src="https://vjs.zencdn.net/8.0.4/video.min.js"></script>
    <link href="https://vjs.zencdn.net/8.0.4/video-js.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/videojs-contrib-hls@5.15.0/dist/videojs-contrib-hls.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/videojs-contrib-dash@5.1.1/dist/videojs-contrib-dash.min.js"></script>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .player-wrapper {
            margin: 20px 0;
        }
        .controls {
            display: flex;
            gap: 10px;
            margin: 20px 0;
            flex-wrap: wrap;
        }
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-weight: bold;
            transition: background-color 0.3s;
        }
        .btn-primary {
            background: #007bff;
            color: white;
        }
        .btn-primary:hover {
            background: #0056b3;
        }
        .btn-secondary {
            background: #6c757d;
            color: white;
        }
        .btn-secondary:hover {
            background: #545b62;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .stat-card {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid #007bff;
        }
        .url-input {
            width: 100%;
            padding: 10px;
            margin: 10px 0;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-family: monospace;
        }
        .format-selector {
            margin: 10px 0;
        }
        select {
            padding: 8px 12px;
            border-radius: 5px;
            border: 1px solid #ddd;
            margin-left: 10px;
        }
        .info-panel {
            background: #e9f7ff;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            border-left: 4px solid #007bff;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎥 Adaptive Bitrate Streaming Test Player</h1>
        <p>Test your ABR streaming setup with HLS and DASH playback support</p>
        
        <div class="info-panel">
            <h3>Test URLs</h3>
            <p><strong>HLS Manifest:</strong> https://$DISTRIBUTION_DOMAIN/hls/[video-name]/index.m3u8</p>
            <p><strong>DASH Manifest:</strong> https://$DISTRIBUTION_DOMAIN/dash/[video-name]/index.mpd</p>
        </div>
        
        <div class="format-selector">
            <label for="streamFormat">Streaming Format:</label>
            <select id="streamFormat" onchange="updateInputPlaceholder()">
                <option value="hls">HLS (HTTP Live Streaming)</option>
                <option value="dash">DASH (Dynamic Adaptive Streaming)</option>
            </select>
        </div>
        
        <input type="text" id="streamUrl" class="url-input" 
               placeholder="Enter stream URL..." 
               value="">
        
        <div class="controls">
            <button class="btn btn-primary" onclick="loadStream()">Load Stream</button>
            <button class="btn btn-secondary" onclick="toggleFullscreen()">Fullscreen</button>
            <button class="btn btn-secondary" onclick="toggleMute()">Mute/Unmute</button>
            <button class="btn btn-secondary" onclick="showStats()">Show Stats</button>
        </div>
        
        <div class="player-wrapper">
            <video
                id="abr-player"
                class="video-js vjs-default-skin"
                controls
                preload="auto"
                width="1120"
                height="630"
                data-setup='{"fluid": true, "responsive": true}'>
                <p class="vjs-no-js">
                    To view this video please enable JavaScript, and consider upgrading to a web browser that
                    <a href="https://videojs.com/html5-video-support/" target="_blank">supports HTML5 video</a>.
                </p>
            </video>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <h4>Current Bitrate</h4>
                <p id="currentBitrate">Not available</p>
            </div>
            <div class="stat-card">
                <h4>Resolution</h4>
                <p id="currentResolution">Not available</p>
            </div>
            <div class="stat-card">
                <h4>Buffer Health</h4>
                <p id="bufferHealth">Not available</p>
            </div>
            <div class="stat-card">
                <h4>Dropped Frames</h4>
                <p id="droppedFrames">Not available</p>
            </div>
        </div>
        
        <div class="info-panel">
            <h3>How to Test</h3>
            <ol>
                <li>Upload a video file (.mp4, .mov) to your source S3 bucket</li>
                <li>Wait for MediaConvert processing to complete (check AWS Console)</li>
                <li>Enter the generated HLS or DASH URL in the input field above</li>
                <li>Click "Load Stream" to test adaptive bitrate playback</li>
            </ol>
        </div>
    </div>
    
    <script>
        const player = videojs('abr-player', {
            html5: {
                vhs: {
                    enableLowInitialPlaylist: true,
                    experimentalBufferBasedABR: true,
                    useDevicePixelRatio: true
                }
            },
            playbackRates: [0.5, 1, 1.25, 1.5, 2],
            responsive: true,
            fluid: true
        });
        
        const distributionDomain = "$DISTRIBUTION_DOMAIN";
        
        function updateInputPlaceholder() {
            const format = document.getElementById('streamFormat').value;
            const urlInput = document.getElementById('streamUrl');
            
            if (format === 'hls') {
                urlInput.placeholder = \`https://\${distributionDomain}/hls/[video-name]/index.m3u8\`;
            } else {
                urlInput.placeholder = \`https://\${distributionDomain}/dash/[video-name]/index.mpd\`;
            }
        }
        
        function loadStream() {
            const url = document.getElementById('streamUrl').value;
            const format = document.getElementById('streamFormat').value;
            
            if (!url) {
                alert('Please enter a stream URL');
                return;
            }
            
            const mimeType = format === 'hls' ? 'application/x-mpegURL' : 'application/dash+xml';
            
            player.src({
                src: url,
                type: mimeType
            });
            
            player.ready(() => {
                console.log('Stream loaded:', url);
                updateStats();
            });
        }
        
        function toggleFullscreen() {
            if (player.isFullscreen()) {
                player.exitFullscreen();
            } else {
                player.requestFullscreen();
            }
        }
        
        function toggleMute() {
            player.muted(!player.muted());
        }
        
        function showStats() {
            const tech = player.tech();
            if (tech && tech.vhs) {
                const stats = tech.vhs.stats;
                alert(\`
                    Bandwidth: \${stats.bandwidth ? (stats.bandwidth / 1000).toFixed(0) + ' kbps' : 'N/A'}
                    Buffer: \${player.bufferedPercent() ? (player.bufferedPercent() * 100).toFixed(1) + '%' : 'N/A'}
                    Resolution: \${player.videoWidth()}x\${player.videoHeight()}
                    Current Time: \${player.currentTime().toFixed(2)}s
                \`);
            }
        }
        
        function updateStats() {
            const tech = player.tech();
            if (tech && tech.vhs) {
                const stats = tech.vhs.stats;
                document.getElementById('currentBitrate').textContent = 
                    stats.bandwidth ? (stats.bandwidth / 1000).toFixed(0) + ' kbps' : 'N/A';
                document.getElementById('currentResolution').textContent = 
                    player.videoWidth() + 'x' + player.videoHeight();
                document.getElementById('bufferHealth').textContent = 
                    player.bufferedPercent() ? (player.bufferedPercent() * 100).toFixed(1) + '%' : 'N/A';
                document.getElementById('droppedFrames').textContent = 
                    stats.droppedVideoFrames || '0';
            }
        }
        
        // Update stats every 2 seconds
        setInterval(updateStats, 2000);
        
        // Initialize placeholder
        updateInputPlaceholder();
        
        // Event listeners
        player.on('error', (e) => {
            console.error('Player error:', e);
            alert('Error loading stream. Please check the URL and try again.');
        });
        
        player.on('loadstart', () => {
            console.log('Stream loading started');
        });
        
        player.on('canplay', () => {
            console.log('Stream ready to play');
            updateStats();
        });
    </script>
</body>
</html>
EOF
    
    # Upload test player to output bucket
    aws s3 cp /tmp/abr-test-player.html "s3://$OUTPUT_BUCKET/test-player.html" \
        --content-type "text/html" \
        --cache-control "max-age=300"
    
    log INFO "Created and uploaded test player"
}

# Save deployment information
save_deployment_info() {
    log INFO "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment-info.env" << EOF
# Adaptive Bitrate Streaming Deployment Information
# Generated on $(date)

export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export SOURCE_BUCKET="$SOURCE_BUCKET"
export OUTPUT_BUCKET="$OUTPUT_BUCKET"
export LAMBDA_FUNCTION="$LAMBDA_FUNCTION"
export MEDIACONVERT_ROLE="$MEDIACONVERT_ROLE"
export MEDIACONVERT_ROLE_ARN="$MEDIACONVERT_ROLE_ARN"
export LAMBDA_ROLE_ARN="$LAMBDA_ROLE_ARN"
export JOB_TEMPLATE="$JOB_TEMPLATE"
export MEDIACONVERT_ENDPOINT="$MEDIACONVERT_ENDPOINT"
export DISTRIBUTION_ID="$DISTRIBUTION_ID"
export DISTRIBUTION_DOMAIN="$DISTRIBUTION_DOMAIN"
EOF
    
    log INFO "Deployment information saved to: ${SCRIPT_DIR}/deployment-info.env"
}

# Display deployment summary
display_summary() {
    log INFO "Deployment completed successfully!"
    
    cat << EOF

==================================================
ADAPTIVE BITRATE STREAMING DEPLOYMENT COMPLETE
==================================================

🎯 UPLOAD INSTRUCTIONS:
Upload video files to: s3://$SOURCE_BUCKET/
Supported formats: .mp4, .mov, .avi, .mkv

📋 PROCESSING OUTPUTS:
HLS Streams: s3://$OUTPUT_BUCKET/hls/
DASH Streams: s3://$OUTPUT_BUCKET/dash/
Thumbnails: s3://$OUTPUT_BUCKET/thumbnails/

🌐 CLOUDFRONT DISTRIBUTION:
Domain: $DISTRIBUTION_DOMAIN
Distribution ID: $DISTRIBUTION_ID

🎮 TEST PLAYER:
URL: http://$OUTPUT_BUCKET.s3-website.$AWS_REGION.amazonaws.com/test-player.html

📊 MONITORING:
Lambda Function: $LAMBDA_FUNCTION
Job Template: $JOB_TEMPLATE

⏱️ NEXT STEPS:
1. Upload a test video file to the source bucket
2. Monitor processing in MediaConvert console
3. Test playback using the generated URLs
4. Configure CloudFront for production use

📝 DEPLOYMENT INFO:
Configuration saved to: ${SCRIPT_DIR}/deployment-info.env

==================================================

EOF
}

# Cleanup temporary files
cleanup_temp_files() {
    log DEBUG "Cleaning up temporary files..."
    rm -f /tmp/cors-config.json
    rm -f /tmp/mediaconvert-trust-policy.json
    rm -f /tmp/mediaconvert-s3-policy.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-mediaconvert-policy.json
    rm -f /tmp/abr-job-template.json
    rm -f /tmp/lambda_function.py
    rm -f /tmp/lambda-abr-function.zip
    rm -f /tmp/s3-video-notification.json
    rm -f /tmp/cloudfront-abr-distribution.json
    rm -f /tmp/abr-test-player.html
}

# Main deployment function
main() {
    log INFO "Starting Adaptive Bitrate Streaming deployment..."
    log INFO "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Initialize environment
    init_environment
    
    if [ "$DRY_RUN" = true ]; then
        log INFO "DRY RUN MODE - No resources will be created"
    fi
    
    # Deploy infrastructure
    create_s3_buckets
    create_iam_roles
    create_mediaconvert_template
    create_lambda_function
    configure_s3_events
    create_cloudfront_distribution
    create_test_player
    
    # Save deployment information
    if [ "$DRY_RUN" = false ]; then
        save_deployment_info
        display_summary
    else
        log INFO "DRY RUN completed successfully"
    fi
    
    # Cleanup
    cleanup_temp_files
    
    log INFO "Deployment script completed successfully"
}

# Execute main function with all arguments
main "$@"