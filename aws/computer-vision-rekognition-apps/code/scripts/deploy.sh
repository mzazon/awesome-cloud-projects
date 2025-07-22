#!/bin/bash

# Deploy script for Computer Vision Applications with Amazon Rekognition
# This script deploys the complete infrastructure for the computer vision solution

set -euo pipefail

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please configure AWS CLI first."
        exit 1
    fi
}

# Function to check AWS permissions
check_aws_permissions() {
    local required_services=("rekognition" "s3" "iam" "kinesis" "kinesisvideo")
    
    for service in "${required_services[@]}"; do
        case $service in
            "rekognition")
                if ! aws rekognition list-collections &> /dev/null; then
                    error "Missing permissions for Amazon Rekognition. Please ensure you have the necessary IAM permissions."
                    exit 1
                fi
                ;;
            "s3")
                if ! aws s3 ls &> /dev/null; then
                    error "Missing permissions for Amazon S3. Please ensure you have the necessary IAM permissions."
                    exit 1
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    error "Missing permissions for IAM. Please ensure you have the necessary IAM permissions."
                    exit 1
                fi
                ;;
            "kinesis")
                if ! aws kinesis list-streams &> /dev/null; then
                    error "Missing permissions for Kinesis Data Streams. Please ensure you have the necessary IAM permissions."
                    exit 1
                fi
                ;;
            "kinesisvideo")
                if ! aws kinesisvideo list-streams &> /dev/null; then
                    error "Missing permissions for Kinesis Video Streams. Please ensure you have the necessary IAM permissions."
                    exit 1
                fi
                ;;
        esac
    done
}

# Function to create IAM role for Rekognition
create_iam_role() {
    log "Creating IAM role for Rekognition video analysis..."
    
    # Check if role already exists
    if aws iam get-role --role-name RekognitionVideoAnalysisRole &> /dev/null; then
        warn "IAM role 'RekognitionVideoAnalysisRole' already exists. Skipping creation."
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "rekognition.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create the IAM role
    aws iam create-role \
        --role-name RekognitionVideoAnalysisRole \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "Role for Amazon Rekognition video analysis operations"
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name RekognitionVideoAnalysisRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRekognitionServiceRole
    
    # Wait for role to be available
    aws iam wait role-exists --role-name RekognitionVideoAnalysisRole
    
    success "IAM role created successfully"
    rm -f /tmp/trust-policy.json
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for computer vision data..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warn "S3 bucket '${S3_BUCKET_NAME}' already exists. Skipping creation."
        return 0
    fi
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
    fi
    
    # Create bucket structure
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key images/
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key videos/
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key results/
    
    success "S3 bucket created and structured"
}

# Function to create face collection
create_face_collection() {
    log "Creating Rekognition face collection..."
    
    # Check if collection already exists
    if aws rekognition describe-collection --collection-id "${FACE_COLLECTION_NAME}" &> /dev/null; then
        warn "Face collection '${FACE_COLLECTION_NAME}' already exists. Skipping creation."
        return 0
    fi
    
    # Create face collection
    aws rekognition create-collection \
        --collection-id "${FACE_COLLECTION_NAME}" \
        --region "$AWS_REGION"
    
    success "Face collection created: ${FACE_COLLECTION_NAME}"
}

# Function to create Kinesis streams
create_kinesis_streams() {
    log "Creating Kinesis streams for real-time processing..."
    
    # Create Kinesis Data Stream
    if ! aws kinesis describe-stream --stream-name "${KDS_STREAM_NAME}" &> /dev/null; then
        aws kinesis create-stream \
            --stream-name "${KDS_STREAM_NAME}" \
            --shard-count 1 \
            --region "$AWS_REGION"
        
        # Wait for stream to be active
        log "Waiting for Kinesis Data Stream to become active..."
        aws kinesis wait stream-exists --stream-name "${KDS_STREAM_NAME}" --region "$AWS_REGION"
        success "Kinesis Data Stream created: ${KDS_STREAM_NAME}"
    else
        warn "Kinesis Data Stream '${KDS_STREAM_NAME}' already exists. Skipping creation."
    fi
    
    # Create Kinesis Video Stream
    if ! aws kinesisvideo describe-stream --stream-name "${KVS_STREAM_NAME}" &> /dev/null; then
        aws kinesisvideo create-stream \
            --stream-name "${KVS_STREAM_NAME}" \
            --data-retention-in-hours 24 \
            --region "$AWS_REGION"
        success "Kinesis Video Stream created: ${KVS_STREAM_NAME}"
    else
        warn "Kinesis Video Stream '${KVS_STREAM_NAME}' already exists. Skipping creation."
    fi
}

# Function to create stream processor
create_stream_processor() {
    log "Creating Rekognition stream processor..."
    
    # Get stream ARNs
    local kvs_arn
    kvs_arn=$(aws kinesisvideo describe-stream \
        --stream-name "${KVS_STREAM_NAME}" \
        --query 'StreamInfo.StreamARN' --output text)
    
    local kds_arn
    kds_arn=$(aws kinesis describe-stream \
        --stream-name "${KDS_STREAM_NAME}" \
        --query 'StreamDescription.StreamARN' --output text)
    
    local role_arn
    role_arn=$(aws iam get-role \
        --role-name RekognitionVideoAnalysisRole \
        --query 'Role.Arn' --output text)
    
    local processor_name="face-search-processor-${RANDOM_SUFFIX}"
    
    # Check if stream processor already exists
    if aws rekognition list-stream-processors --query "StreamProcessors[?Name=='${processor_name}']" --output text | grep -q "${processor_name}"; then
        warn "Stream processor '${processor_name}' already exists. Skipping creation."
        return 0
    fi
    
    # Create stream processor
    aws rekognition create-stream-processor \
        --name "${processor_name}" \
        --input "{\"KinesisVideoStream\":{\"Arn\":\"${kvs_arn}\"}}" \
        --stream-processor-output "{\"KinesisDataStream\":{\"Arn\":\"${kds_arn}\"}}" \
        --role-arn "${role_arn}" \
        --settings "{\"FaceSearch\":{\"CollectionId\":\"${FACE_COLLECTION_NAME}\",\"FaceMatchThreshold\":80.0}}" \
        --region "$AWS_REGION"
    
    success "Stream processor created: ${processor_name}"
}

# Function to create local directories
create_local_directories() {
    log "Creating local directories for demo files..."
    
    local demo_dir="$HOME/computer-vision-demo"
    mkdir -p "${demo_dir}"/{images,videos,results}
    
    success "Local directories created at ${demo_dir}"
}

# Function to download sample content
download_sample_content() {
    log "Downloading sample images for testing..."
    
    local demo_dir="$HOME/computer-vision-demo"
    
    # Download sample images if they don't exist
    if [ ! -f "${demo_dir}/images/person1.jpg" ]; then
        curl -s -o "${demo_dir}/images/person1.jpg" \
            "https://images.pexels.com/photos/220453/pexels-photo-220453.jpeg?auto=compress&cs=tinysrgb&w=400" || \
            warn "Failed to download sample image 1"
    fi
    
    if [ ! -f "${demo_dir}/images/person2.jpg" ]; then
        curl -s -o "${demo_dir}/images/person2.jpg" \
            "https://images.pexels.com/photos/614810/pexels-photo-614810.jpeg?auto=compress&cs=tinysrgb&w=400" || \
            warn "Failed to download sample image 2"
    fi
    
    # Upload images to S3
    if [ -f "${demo_dir}/images/person1.jpg" ] || [ -f "${demo_dir}/images/person2.jpg" ]; then
        aws s3 cp "${demo_dir}/images/" "s3://${S3_BUCKET_NAME}/images/" --recursive --exclude "*" --include "*.jpg"
        success "Sample images uploaded to S3"
    fi
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    local state_file="$HOME/computer-vision-demo/deployment-state.json"
    
    cat > "${state_file}" << EOF
{
    "deployment_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "s3_bucket_name": "${S3_BUCKET_NAME}",
    "face_collection_name": "${FACE_COLLECTION_NAME}",
    "kvs_stream_name": "${KVS_STREAM_NAME}",
    "kds_stream_name": "${KDS_STREAM_NAME}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "iam_role_name": "RekognitionVideoAnalysisRole"
}
EOF
    
    success "Deployment state saved to ${state_file}"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "================================================"
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "================================================"
    echo ""
    echo "Resources created:"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "  • Face Collection: ${FACE_COLLECTION_NAME}"
    echo "  • Kinesis Video Stream: ${KVS_STREAM_NAME}"
    echo "  • Kinesis Data Stream: ${KDS_STREAM_NAME}"
    echo "  • IAM Role: RekognitionVideoAnalysisRole"
    echo "  • Stream Processor: face-search-processor-${RANDOM_SUFFIX}"
    echo ""
    echo "Local demo directory: $HOME/computer-vision-demo"
    echo ""
    echo "Next steps:"
    echo "  1. Follow the recipe steps to analyze images and videos"
    echo "  2. Run ./destroy.sh when you're done to clean up resources"
    echo ""
    echo "Estimated monthly cost: \$15-25 USD (for processing 1,000 images and 1 hour of video)"
    echo ""
}

# Main deployment function
main() {
    echo "🚀 Starting deployment of Computer Vision Applications with Amazon Rekognition"
    echo ""
    
    # Prerequisites check
    log "Checking prerequisites..."
    check_command "aws"
    check_command "jq"
    check_command "curl"
    check_aws_credentials
    check_aws_permissions
    
    # Set environment variables
    log "Setting up environment variables..."
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    export S3_BUCKET_NAME="computer-vision-app-${RANDOM_SUFFIX}"
    export FACE_COLLECTION_NAME="retail-faces-${RANDOM_SUFFIX}"
    export KVS_STREAM_NAME="security-video-${RANDOM_SUFFIX}"
    export KDS_STREAM_NAME="rekognition-results-${RANDOM_SUFFIX}"
    
    log "Using AWS Region: ${AWS_REGION}"
    log "Using AWS Account: ${AWS_ACCOUNT_ID}"
    log "Using Random Suffix: ${RANDOM_SUFFIX}"
    
    # Create resources
    create_iam_role
    create_s3_bucket
    create_face_collection
    create_kinesis_streams
    create_stream_processor
    create_local_directories
    download_sample_content
    save_deployment_state
    
    # Display summary
    display_summary
}

# Error handler
error_handler() {
    error "Deployment failed on line $1"
    echo ""
    echo "To clean up any partially created resources, run:"
    echo "  ./destroy.sh"
    echo ""
    exit 1
}

# Set up error handling
trap 'error_handler $LINENO' ERR

# Run main function
main "$@"