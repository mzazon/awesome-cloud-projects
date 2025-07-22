#!/bin/bash

# Deploy script for Computer Vision Solutions with Amazon Rekognition
# This script deploys the infrastructure and sets up the demo environment

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Computer Vision Solutions with Amazon Rekognition - Deploy Script

Usage: $0 [OPTIONS]

OPTIONS:
    -r, --region REGION     AWS region (default: current configured region)
    -p, --prefix PREFIX     Resource name prefix (default: rekognition-demo)
    -h, --help             Show this help message
    --dry-run              Show what would be deployed without making changes
    --skip-samples         Skip uploading sample images
    --force                Force deployment even if resources exist

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --region us-west-2                # Deploy to specific region
    $0 --prefix my-cv-demo               # Use custom prefix
    $0 --dry-run                         # Preview deployment
    $0 --skip-samples                    # Deploy without sample images

EOF
}

# Parse command line arguments
DRY_RUN=false
SKIP_SAMPLES=false
FORCE=false
PREFIX="rekognition-demo"

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-samples)
            SKIP_SAMPLES=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Prerequisite checks
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            AWS_REGION="us-east-1"
            warning "No AWS region configured, using default: $AWS_REGION"
        fi
    fi
    export AWS_REGION
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Set resource names
    export BUCKET_NAME="${PREFIX}-${RANDOM_SUFFIX}"
    export COLLECTION_NAME="face-collection-${RANDOM_SUFFIX}"
    export ROLE_NAME="RekognitionDemoRole-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="RekognitionProcessor-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE_NAME="RekognitionResults-${RANDOM_SUFFIX}"
    
    log "Environment configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account: $AWS_ACCOUNT_ID"
    log "  S3 Bucket: $BUCKET_NAME"
    log "  Face Collection: $COLLECTION_NAME"
    log "  IAM Role: $ROLE_NAME"
}

# Check if resources already exist
check_existing_resources() {
    log "Checking for existing resources..."
    
    # Check if bucket exists
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        if [[ "$FORCE" == "false" ]]; then
            error "S3 bucket $BUCKET_NAME already exists. Use --force to override."
            exit 1
        else
            warning "S3 bucket $BUCKET_NAME exists, will use existing bucket"
        fi
    fi
    
    # Check if collection exists
    if aws rekognition describe-collection --collection-id "$COLLECTION_NAME" &> /dev/null; then
        if [[ "$FORCE" == "false" ]]; then
            error "Rekognition collection $COLLECTION_NAME already exists. Use --force to override."
            exit 1
        else
            warning "Collection $COLLECTION_NAME exists, will use existing collection"
        fi
    fi
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        if [[ "$FORCE" == "false" ]]; then
            error "IAM role $ROLE_NAME already exists. Use --force to override."
            exit 1
        else
            warning "IAM role $ROLE_NAME exists, will use existing role"
        fi
    fi
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket: $BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create S3 bucket: $BUCKET_NAME"
        return
    fi
    
    # Create bucket with region constraint if not us-east-1
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$BUCKET_NAME"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
    fi
    
    # Enable versioning for better data protection
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Block public access for security
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    success "S3 bucket created successfully"
}

# Create IAM role
create_iam_role() {
    log "Creating IAM role: $ROLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create IAM role: $ROLE_NAME"
        return
    fi
    
    # Create trust policy
    cat > /tmp/trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": ["lambda.amazonaws.com", "rekognition.amazonaws.com"]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create the role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json \
        --description "Role for Rekognition computer vision demo"
    
    # Attach managed policies
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonRekognitionFullAccess
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    # Clean up temp file
    rm -f /tmp/trust-policy.json
    
    success "IAM role created successfully"
}

# Create Rekognition face collection
create_face_collection() {
    log "Creating Rekognition face collection: $COLLECTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create face collection: $COLLECTION_NAME"
        return
    fi
    
    aws rekognition create-collection --collection-id "$COLLECTION_NAME"
    
    # Get collection details
    COLLECTION_ARN=$(aws rekognition describe-collection \
        --collection-id "$COLLECTION_NAME" \
        --query 'CollectionARN' --output text)
    
    log "Collection ARN: $COLLECTION_ARN"
    success "Face collection created successfully"
}

# Create DynamoDB table for results
create_dynamodb_table() {
    log "Creating DynamoDB table: $DYNAMODB_TABLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create DynamoDB table: $DYNAMODB_TABLE_NAME"
        return
    fi
    
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --attribute-definitions \
            AttributeName=ImageKey,AttributeType=S \
        --key-schema \
            AttributeName=ImageKey,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Purpose,Value=RekognitionDemo
    
    # Wait for table to be active
    log "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME"
    
    success "DynamoDB table created successfully"
}

# Create comprehensive analysis function
create_analysis_function() {
    log "Creating comprehensive analysis function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create analysis function"
        return
    fi
    
    cat > comprehensive-analysis.py << 'EOF'
import boto3
import json
import sys
import os
from datetime import datetime

def analyze_image_comprehensive(bucket_name, image_key, collection_id, table_name=None):
    """
    Perform comprehensive analysis on an image using Amazon Rekognition
    """
    rekognition = boto3.client('rekognition')
    
    results = {
        'image': f's3://{bucket_name}/{image_key}',
        'timestamp': datetime.utcnow().isoformat(),
        'analyses': {}
    }
    
    try:
        # Face Detection
        log_operation("Face Detection")
        face_response = rekognition.detect_faces(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': image_key}},
            Attributes=['ALL']
        )
        results['analyses']['faces'] = {
            'count': len(face_response['FaceDetails']),
            'details': face_response['FaceDetails']
        }
        
        # Object Detection
        log_operation("Object Detection")
        label_response = rekognition.detect_labels(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': image_key}},
            MaxLabels=10,
            MinConfidence=75
        )
        results['analyses']['objects'] = {
            'count': len(label_response['Labels']),
            'labels': label_response['Labels']
        }
        
        # Text Detection
        log_operation("Text Detection")
        text_response = rekognition.detect_text(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': image_key}}
        )
        text_lines = [t for t in text_response['TextDetections'] if t['Type'] == 'LINE']
        results['analyses']['text'] = {
            'count': len(text_lines),
            'lines': text_lines
        }
        
        # Content Moderation
        log_operation("Content Moderation")
        moderation_response = rekognition.detect_moderation_labels(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': image_key}},
            MinConfidence=60
        )
        results['analyses']['moderation'] = {
            'inappropriate_content': len(moderation_response['ModerationLabels']) > 0,
            'labels': moderation_response['ModerationLabels']
        }
        
        # Face Search (if collection provided)
        if collection_id:
            try:
                log_operation("Face Search")
                search_response = rekognition.search_faces_by_image(
                    CollectionId=collection_id,
                    Image={'S3Object': {'Bucket': bucket_name, 'Name': image_key}},
                    FaceMatchThreshold=80,
                    MaxFaces=5
                )
                results['analyses']['face_search'] = {
                    'matches_found': len(search_response['FaceMatches']),
                    'matches': search_response['FaceMatches']
                }
            except rekognition.exceptions.InvalidParameterException:
                results['analyses']['face_search'] = {
                    'matches_found': 0,
                    'matches': [],
                    'note': 'No faces detected for search'
                }
        
        # Store results in DynamoDB if table provided
        if table_name:
            store_results_in_dynamodb(table_name, image_key, results)
        
        return results
        
    except Exception as e:
        results['error'] = str(e)
        return results

def log_operation(operation):
    """Log the current operation"""
    print(f"🔍 Performing {operation}...", file=sys.stderr)

def store_results_in_dynamodb(table_name, image_key, results):
    """Store analysis results in DynamoDB"""
    try:
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(table_name)
        
        # Prepare item for DynamoDB (convert Decimals, etc.)
        item = {
            'ImageKey': image_key,
            'AnalysisResults': json.loads(json.dumps(results, default=str)),
            'Timestamp': datetime.utcnow().isoformat()
        }
        
        table.put_item(Item=item)
        print(f"✅ Results stored in DynamoDB table: {table_name}", file=sys.stderr)
        
    except Exception as e:
        print(f"⚠️  Failed to store results in DynamoDB: {str(e)}", file=sys.stderr)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python comprehensive-analysis.py <bucket> <image-key> [collection-id] [table-name]")
        sys.exit(1)
    
    bucket = sys.argv[1]
    image = sys.argv[2]
    collection = sys.argv[3] if len(sys.argv) > 3 else None
    table = sys.argv[4] if len(sys.argv) > 4 else None
    
    results = analyze_image_comprehensive(bucket, image, collection, table)
    print(json.dumps(results, indent=2, default=str))
EOF
    
    success "Analysis function created successfully"
}

# Upload sample images
upload_sample_images() {
    if [[ "$SKIP_SAMPLES" == "true" ]]; then
        log "Skipping sample image upload"
        return
    fi
    
    log "Preparing sample images..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would upload sample images to S3"
        return
    fi
    
    # Create sample images directory
    mkdir -p sample-images
    
    # Create a simple instruction file for users
    cat > sample-images/README.txt << EOF
Sample Images Directory
======================

Add your test images to this directory for analysis.

Recommended image types:
- Face photos (for face detection and recognition)
- Scene photos (for object detection)
- Images with text (for text extraction)
- Various content types (for moderation testing)

Supported formats: JPEG, PNG
Maximum file size: 15MB per image
Maximum image dimensions: 4096 x 4096 pixels

After adding images, run the analysis with:
python3 comprehensive-analysis.py $BUCKET_NAME images/your-image.jpg $COLLECTION_NAME $DYNAMODB_TABLE_NAME
EOF
    
    # Upload the README to S3
    aws s3 cp sample-images/README.txt "s3://$BUCKET_NAME/images/"
    
    # Check if user has added any sample images
    if [ "$(ls -A sample-images/ 2>/dev/null | grep -v README.txt)" ]; then
        log "Uploading sample images to S3..."
        aws s3 cp sample-images/ "s3://$BUCKET_NAME/images/" --recursive --exclude "README.txt"
        success "Sample images uploaded successfully"
    else
        warning "No sample images found. Add images to sample-images/ directory and upload manually with:"
        warning "aws s3 cp sample-images/ s3://$BUCKET_NAME/images/ --recursive"
    fi
}

# Save configuration
save_configuration() {
    log "Saving deployment configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would save configuration"
        return
    fi
    
    cat > deployment-config.json << EOF
{
    "deployment_info": {
        "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "region": "$AWS_REGION",
        "account_id": "$AWS_ACCOUNT_ID"
    },
    "resources": {
        "s3_bucket": "$BUCKET_NAME",
        "face_collection": "$COLLECTION_NAME",
        "iam_role": "$ROLE_NAME",
        "dynamodb_table": "$DYNAMODB_TABLE_NAME"
    },
    "endpoints": {
        "s3_console": "https://s3.console.aws.amazon.com/s3/buckets/$BUCKET_NAME",
        "rekognition_console": "https://$AWS_REGION.console.aws.amazon.com/rekognition/home?region=$AWS_REGION#/collections",
        "dynamodb_console": "https://$AWS_REGION.console.aws.amazon.com/dynamodbv2/home?region=$AWS_REGION#table?name=$DYNAMODB_TABLE_NAME"
    }
}
EOF
    
    success "Configuration saved to deployment-config.json"
}

# Display deployment summary
show_deployment_summary() {
    log "Deployment Summary:"
    echo ""
    echo "🎯 Resources Created:"
    echo "   • S3 Bucket: $BUCKET_NAME"
    echo "   • Face Collection: $COLLECTION_NAME"
    echo "   • IAM Role: $ROLE_NAME"
    echo "   • DynamoDB Table: $DYNAMODB_TABLE_NAME"
    echo ""
    echo "🔗 Quick Links:"
    echo "   • S3 Console: https://s3.console.aws.amazon.com/s3/buckets/$BUCKET_NAME"
    echo "   • Rekognition Console: https://$AWS_REGION.console.aws.amazon.com/rekognition/home?region=$AWS_REGION#/collections"
    echo "   • DynamoDB Console: https://$AWS_REGION.console.aws.amazon.com/dynamodbv2/home?region=$AWS_REGION#table?name=$DYNAMODB_TABLE_NAME"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Add sample images to the sample-images/ directory"
    echo "   2. Upload them to S3: aws s3 cp sample-images/ s3://$BUCKET_NAME/images/ --recursive"
    echo "   3. Run analysis: python3 comprehensive-analysis.py $BUCKET_NAME images/your-image.jpg $COLLECTION_NAME $DYNAMODB_TABLE_NAME"
    echo ""
    echo "🧹 To clean up: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    log "Starting Computer Vision Solutions deployment..."
    
    check_prerequisites
    setup_environment
    
    if [[ "$DRY_RUN" == "false" ]]; then
        check_existing_resources
    fi
    
    create_s3_bucket
    create_iam_role
    create_face_collection
    create_dynamodb_table
    create_analysis_function
    upload_sample_images
    
    if [[ "$DRY_RUN" == "false" ]]; then
        save_configuration
        success "Deployment completed successfully!"
        show_deployment_summary
    else
        log "Dry run completed. No resources were created."
    fi
}

# Trap errors and cleanup
trap 'error "Deployment failed! Check the logs above for details."' ERR

# Run main function
main "$@"