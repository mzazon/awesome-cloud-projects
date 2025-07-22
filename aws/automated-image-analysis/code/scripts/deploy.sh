#!/bin/bash

# Deploy script for Image Analysis Application with Amazon Rekognition
# This script automates the deployment of the image analysis solution

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo "=========================================="
echo "  AWS Rekognition Image Analysis Setup"
echo "=========================================="
echo ""

# Prerequisites check
print_status "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install AWS CLI v2 first."
    log_error "AWS CLI not found"
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS CLI is not configured or credentials are invalid."
    log_error "AWS CLI configuration check failed"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_warning "jq is not installed. Installing jq for JSON parsing..."
    # Try to install jq based on the system
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq
    elif command -v brew &> /dev/null; then
        brew install jq
    else
        print_error "Cannot install jq automatically. Please install jq manually."
        exit 1
    fi
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    print_error "curl is not installed. Please install curl first."
    exit 1
fi

print_success "Prerequisites check completed"

# Set environment variables
print_status "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="us-east-1"
    print_warning "AWS region not configured, defaulting to us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    print_error "Failed to get AWS Account ID"
    log_error "Failed to retrieve AWS Account ID"
    exit 1
fi

# Generate unique identifier for S3 bucket
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || \
    openssl rand -hex 3)

export BUCKET_NAME="rekognition-images-${RANDOM_SUFFIX}"

log "Environment variables set: AWS_REGION=${AWS_REGION}, AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}, BUCKET_NAME=${BUCKET_NAME}"
print_success "Environment variables configured"

# Create deployment state file
DEPLOYMENT_STATE="${SCRIPT_DIR}/deployment-state.json"
cat > "$DEPLOYMENT_STATE" << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "bucket_name": "${BUCKET_NAME}",
    "resources_created": []
}
EOF

# Function to update deployment state
update_deployment_state() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_arn="$3"
    
    jq --arg type "$resource_type" \
       --arg name "$resource_name" \
       --arg arn "$resource_arn" \
       '.resources_created += [{"type": $type, "name": $name, "arn": $arn}]' \
       "$DEPLOYMENT_STATE" > "${DEPLOYMENT_STATE}.tmp" && \
       mv "${DEPLOYMENT_STATE}.tmp" "$DEPLOYMENT_STATE"
}

# Check if Rekognition service is available in the region
print_status "Verifying Amazon Rekognition availability in region ${AWS_REGION}..."
if ! aws rekognition describe-projects --region "${AWS_REGION}" &> /dev/null; then
    print_error "Amazon Rekognition is not available in region ${AWS_REGION}"
    log_error "Rekognition service check failed in region ${AWS_REGION}"
    exit 1
fi
print_success "Amazon Rekognition is available in region ${AWS_REGION}"

# Create S3 bucket
print_status "Creating S3 bucket: ${BUCKET_NAME}..."

# Check if bucket already exists
if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
    print_warning "S3 bucket ${BUCKET_NAME} already exists, skipping creation"
else
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "S3 bucket created: ${BUCKET_NAME}"
        update_deployment_state "s3-bucket" "${BUCKET_NAME}" "arn:aws:s3:::${BUCKET_NAME}"
        log "S3 bucket created successfully: ${BUCKET_NAME}"
    else
        print_error "Failed to create S3 bucket: ${BUCKET_NAME}"
        log_error "S3 bucket creation failed: ${BUCKET_NAME}"
        exit 1
    fi
fi

# Wait for bucket to be available
print_status "Waiting for S3 bucket to be available..."
aws s3 wait bucket-exists --bucket "${BUCKET_NAME}"
print_success "S3 bucket is ready"

# Enable versioning on the bucket (recommended for production)
print_status "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled
print_success "S3 bucket versioning enabled"

# Create directory structure
print_status "Creating local directory structure..."
WORK_DIR="${HOME}/rekognition-demo"
mkdir -p "${WORK_DIR}/images"
mkdir -p "${WORK_DIR}/results"
mkdir -p "${WORK_DIR}/scripts"

# Create analysis scripts
print_status "Creating analysis scripts..."

# Create the batch analysis script
cat > "${WORK_DIR}/scripts/analyze-images.sh" << 'EOF'
#!/bin/bash

# Batch image analysis script
set -e

# Get environment variables
BUCKET_NAME=$1
AWS_REGION=$2
OUTPUT_DIR=$3

if [ -z "$BUCKET_NAME" ] || [ -z "$AWS_REGION" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <bucket_name> <aws_region> <output_dir>"
    exit 1
fi

echo "Starting batch analysis..."
echo "Bucket: $BUCKET_NAME"
echo "Region: $AWS_REGION"
echo "Output: $OUTPUT_DIR"

# Get the list of images
IMAGES=$(aws s3 ls s3://${BUCKET_NAME}/images/ --region ${AWS_REGION} | awk '{print $4}')

if [ -z "$IMAGES" ]; then
    echo "No images found in s3://${BUCKET_NAME}/images/"
    exit 1
fi

# Process each image
for IMAGE in $IMAGES; do
    if [[ $IMAGE == *.jpg || $IMAGE == *.jpeg || $IMAGE == *.png || $IMAGE == *.JPG || $IMAGE == *.JPEG || $IMAGE == *.PNG ]]; then
        echo "Analyzing image: $IMAGE"
        
        # Create output directory for this image
        mkdir -p "${OUTPUT_DIR}/${IMAGE}"
        
        # Detect labels
        echo "  - Detecting labels..."
        aws rekognition detect-labels \
            --image "{'S3Object':{'Bucket':'${BUCKET_NAME}','Name':'images/${IMAGE}'}}" \
            --features GENERAL_LABELS \
            --settings "{'GeneralLabels':{'LabelInclusionFilters':[],'LabelExclusionFilters':[],'LabelCategoryInclusionFilters':[],'LabelCategoryExclusionFilters':[]}}" \
            --region "${AWS_REGION}" > "${OUTPUT_DIR}/${IMAGE}/labels.json"
        
        # Detect text
        echo "  - Detecting text..."
        aws rekognition detect-text \
            --image "{'S3Object':{'Bucket':'${BUCKET_NAME}','Name':'images/${IMAGE}'}}" \
            --region "${AWS_REGION}" > "${OUTPUT_DIR}/${IMAGE}/text.json"
        
        # Detect unsafe content
        echo "  - Analyzing content moderation..."
        aws rekognition detect-moderation-labels \
            --image "{'S3Object':{'Bucket':'${BUCKET_NAME}','Name':'images/${IMAGE}'}}" \
            --region "${AWS_REGION}" > "${OUTPUT_DIR}/${IMAGE}/moderation.json"
        
        echo "  ✅ Analysis completed for $IMAGE"
    fi
done

echo "✅ All images analyzed successfully"
EOF

chmod +x "${WORK_DIR}/scripts/analyze-images.sh"

# Create report generation script
cat > "${WORK_DIR}/scripts/generate-report.sh" << 'EOF'
#!/bin/bash

# Report generation script
set -e

# Get parameters
RESULTS_DIR=$1

if [ -z "$RESULTS_DIR" ]; then
    echo "Usage: $0 <results_directory>"
    exit 1
fi

# Create report file
REPORT_FILE="${RESULTS_DIR}/analysis-report.md"

# Create report header
echo "# Image Analysis Report" > "${REPORT_FILE}"
echo "Generated on: $(date)" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# Create summary section
echo "## Summary" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

TOTAL_IMAGES=$(find "${RESULTS_DIR}" -maxdepth 1 -type d ! -path "${RESULTS_DIR}" | wc -l)
echo "- Total images analyzed: ${TOTAL_IMAGES}" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# Process each image result
for IMAGE_DIR in "${RESULTS_DIR}"/*; do
    if [ -d "${IMAGE_DIR}" ]; then
        IMAGE_NAME=$(basename "${IMAGE_DIR}")
        echo "## Image: ${IMAGE_NAME}" >> "${REPORT_FILE}"
        
        # Add label analysis
        echo "### Detected Objects and Scenes" >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
        
        if [ -f "${IMAGE_DIR}/labels.json" ]; then
            TOP_LABELS=$(cat "${IMAGE_DIR}/labels.json" | \
                jq -r '.Labels | sort_by(-.Confidence) | .[0:5] | .[] | "- \(.Name): \(.Confidence | floor)%"')
            if [ -n "${TOP_LABELS}" ]; then
                echo "${TOP_LABELS}" >> "${REPORT_FILE}"
            else
                echo "- No objects detected" >> "${REPORT_FILE}"
            fi
        else
            echo "- No label analysis available" >> "${REPORT_FILE}"
        fi
        
        echo "" >> "${REPORT_FILE}"
        
        # Add text analysis
        echo "### Detected Text" >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
        
        if [ -f "${IMAGE_DIR}/text.json" ]; then
            TEXT=$(cat "${IMAGE_DIR}/text.json" | \
                jq -r '.TextDetections | .[] | select(.Type=="LINE") | "- \(.DetectedText)"')
            
            if [ -z "${TEXT}" ]; then
                echo "- No text detected" >> "${REPORT_FILE}"
            else
                echo "${TEXT}" >> "${REPORT_FILE}"
            fi
        else
            echo "- No text analysis available" >> "${REPORT_FILE}"
        fi
        
        echo "" >> "${REPORT_FILE}"
        
        # Add moderation analysis
        echo "### Content Moderation" >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
        
        if [ -f "${IMAGE_DIR}/moderation.json" ]; then
            MODERATION=$(cat "${IMAGE_DIR}/moderation.json" | \
                jq -r '.ModerationLabels | length')
            
            if [ "$MODERATION" -eq 0 ]; then
                echo "- ✅ No inappropriate content detected" >> "${REPORT_FILE}"
            else
                echo "- ⚠️ Potential inappropriate content detected:" >> "${REPORT_FILE}"
                cat "${IMAGE_DIR}/moderation.json" | \
                    jq -r '.ModerationLabels[] | "  - \(.Name): \(.Confidence | floor)%"' >> "${REPORT_FILE}"
            fi
        else
            echo "- No moderation analysis available" >> "${REPORT_FILE}"
        fi
        
        echo "" >> "${REPORT_FILE}"
        echo "---" >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
    fi
done

echo "Report generated at: ${REPORT_FILE}"
EOF

chmod +x "${WORK_DIR}/scripts/generate-report.sh"

print_success "Analysis scripts created"

# Download sample image if no images directory exists or is empty
print_status "Setting up sample image..."
if [ ! "$(ls -A "${WORK_DIR}/images" 2>/dev/null)" ]; then
    print_status "Downloading sample image..."
    curl -s -o "${WORK_DIR}/images/sample.jpg" \
        "https://images.pexels.com/photos/3184418/pexels-photo-3184418.jpeg?auto=compress&cs=tinysrgb&w=800"
    
    if [ $? -eq 0 ]; then
        print_success "Sample image downloaded"
    else
        print_warning "Failed to download sample image, you can add your own images to ${WORK_DIR}/images/"
    fi
else
    print_success "Images directory already contains files"
fi

# Upload images to S3
print_status "Uploading images to S3..."
if [ "$(ls -A "${WORK_DIR}/images" 2>/dev/null)" ]; then
    aws s3 cp "${WORK_DIR}/images/" "s3://${BUCKET_NAME}/images/" \
        --recursive --region "${AWS_REGION}"
    
    if [ $? -eq 0 ]; then
        print_success "Images uploaded to S3"
        
        # List uploaded images
        UPLOADED_COUNT=$(aws s3 ls "s3://${BUCKET_NAME}/images/" --region "${AWS_REGION}" | wc -l)
        print_success "Total images uploaded: ${UPLOADED_COUNT}"
    else
        print_error "Failed to upload images to S3"
        log_error "Image upload failed"
        exit 1
    fi
else
    print_warning "No images found to upload in ${WORK_DIR}/images/"
fi

# Save environment variables for subsequent scripts
cat > "${WORK_DIR}/.env" << EOF
# Environment variables for Rekognition demo
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export BUCKET_NAME="${BUCKET_NAME}"
export WORK_DIR="${WORK_DIR}"
EOF

print_success "Environment variables saved to ${WORK_DIR}/.env"

# Create a quick analysis demo
print_status "Running quick analysis demo on first image..."
FIRST_IMAGE=$(aws s3 ls "s3://${BUCKET_NAME}/images/" --region "${AWS_REGION}" | head -1 | awk '{print $4}')

if [ -n "$FIRST_IMAGE" ]; then
    echo "Analyzing: ${FIRST_IMAGE}"
    
    # Quick label detection
    aws rekognition detect-labels \
        --image "{'S3Object':{'Bucket':'${BUCKET_NAME}','Name':'images/${FIRST_IMAGE}'}}" \
        --features GENERAL_LABELS \
        --region "${AWS_REGION}" > "${WORK_DIR}/results/demo-labels.json"
    
    echo ""
    echo "🔍 Top 3 detected labels:"
    cat "${WORK_DIR}/results/demo-labels.json" | \
        jq -r '.Labels | sort_by(-.Confidence) | .[0:3] | .[] | "  • \(.Name): \(.Confidence | floor)%"'
    
    print_success "Demo analysis completed"
fi

# Final status
echo ""
echo "=========================================="
print_success "Deployment completed successfully!"
echo "=========================================="
echo ""
echo "📁 Working directory: ${WORK_DIR}"
echo "🪣 S3 Bucket: ${BUCKET_NAME}"
echo "🌍 AWS Region: ${AWS_REGION}"
echo ""
echo "Next steps:"
echo "1. Add more images to: ${WORK_DIR}/images/"
echo "2. Upload with: aws s3 cp ${WORK_DIR}/images/ s3://${BUCKET_NAME}/images/ --recursive"
echo "3. Run batch analysis: ${WORK_DIR}/scripts/analyze-images.sh ${BUCKET_NAME} ${AWS_REGION} ${WORK_DIR}/results"
echo "4. Generate report: ${WORK_DIR}/scripts/generate-report.sh ${WORK_DIR}/results"
echo ""
echo "To load environment variables in new shell sessions:"
echo "source ${WORK_DIR}/.env"
echo ""
print_warning "Remember to run destroy.sh when finished to avoid ongoing charges!"

log "Deployment completed successfully at $(date)"
exit 0