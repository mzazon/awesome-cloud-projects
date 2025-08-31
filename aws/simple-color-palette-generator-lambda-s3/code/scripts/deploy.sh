#!/bin/bash

#######################################################################
# AWS Simple Color Palette Generator - Deployment Script
# 
# This script deploys a serverless color palette generator using
# AWS Lambda and S3 following the recipe instructions.
#
# Prerequisites:
# - AWS CLI v2.0+ installed and configured
# - jq installed for JSON processing
# - Appropriate AWS permissions for Lambda, S3, and IAM
#
# Usage: ./deploy.sh [--dry-run]
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RECIPE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly DRY_RUN="${1:-}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if running in dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "--dry-run" ]]
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    
    log_info "$description"
    if is_dry_run; then
        echo "DRY RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Cleanup function for script interruption
cleanup() {
    log_warning "Script interrupted. Cleaning up temporary files..."
    rm -f "$SCRIPT_DIR"/trust-policy.json "$SCRIPT_DIR"/s3-policy.json
    rm -f "$SCRIPT_DIR"/lambda_function.py "$SCRIPT_DIR"/function.zip
    exit 1
}

trap cleanup INT TERM

#######################################################################
# Prerequisites Check
#######################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2.0+"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$aws_version" | cut -d. -f1) -lt 2 ]]; then
        log_error "AWS CLI version 2.0+ required. Current version: $aws_version"
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first"
        exit 1
    fi
    
    # Check zip command
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

#######################################################################
# Environment Setup
#######################################################################

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS environment
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured. Please set default region"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="color-palettes-${random_suffix}"
    export FUNCTION_NAME="palette-generator-${random_suffix}"
    export ROLE_NAME="palette-generator-role-${random_suffix}"
    
    log_info "Environment configured:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account: $AWS_ACCOUNT_ID"
    log_info "  Resource Suffix: $random_suffix"
    log_info "  Bucket Name: $BUCKET_NAME"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Role Name: $ROLE_NAME"
}

#######################################################################
# S3 Bucket Creation
#######################################################################

create_s3_bucket() {
    log_info "Creating S3 bucket for palette storage..."
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        execute_cmd "aws s3 mb s3://$BUCKET_NAME" "Creating S3 bucket"
    else
        execute_cmd "aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION" "Creating S3 bucket"
    fi
    
    # Wait for bucket to be available
    if ! is_dry_run; then
        log_info "Waiting for bucket to be available..."
        aws s3api wait bucket-exists --bucket "$BUCKET_NAME"
    fi
    
    # Enable versioning
    execute_cmd "aws s3api put-bucket-versioning \
        --bucket $BUCKET_NAME \
        --versioning-configuration Status=Enabled" \
        "Enabling bucket versioning"
    
    # Configure bucket encryption
    execute_cmd "aws s3api put-bucket-encryption \
        --bucket $BUCKET_NAME \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'" \
        "Configuring bucket encryption"
    
    log_success "S3 bucket $BUCKET_NAME created with security features"
}

#######################################################################
# IAM Role Creation
#######################################################################

create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Create trust policy
    cat > "$SCRIPT_DIR/trust-policy.json" << 'EOF'
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
    
    # Create IAM role
    execute_cmd "aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document file://$SCRIPT_DIR/trust-policy.json" \
        "Creating IAM role"
    
    # Attach basic Lambda execution policy
    execute_cmd "aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Attaching Lambda execution policy"
    
    log_success "IAM role $ROLE_NAME created with Lambda permissions"
}

#######################################################################
# S3 Access Policy Creation
#######################################################################

create_s3_policy() {
    log_info "Creating S3 access policy for Lambda..."
    
    # Create S3 access policy
    cat > "$SCRIPT_DIR/s3-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::$BUCKET_NAME"
    }
  ]
}
EOF
    
    # Create and attach the S3 policy
    execute_cmd "aws iam create-policy \
        --policy-name $ROLE_NAME-s3-policy \
        --policy-document file://$SCRIPT_DIR/s3-policy.json" \
        "Creating S3 access policy"
    
    execute_cmd "aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$ROLE_NAME-s3-policy" \
        "Attaching S3 policy to Lambda role"
    
    log_success "S3 access policy attached to Lambda role"
}

#######################################################################
# Lambda Function Code Creation
#######################################################################

create_lambda_code() {
    log_info "Creating Lambda function code..."
    
    # Create the Lambda function code
    cat > "$SCRIPT_DIR/lambda_function.py" << 'EOF'
import json
import random
import colorsys
import boto3
import os
from datetime import datetime
import uuid

# Initialize S3 client
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    # Get bucket name from environment variable
    bucket_name = os.environ.get('BUCKET_NAME')
    if not bucket_name:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Bucket name not configured'})
        }
    
    try:
        # Generate color palette based on requested type
        query_params = event.get('queryStringParameters') or {}
        palette_type = query_params.get('type', 'complementary')
        palette = generate_color_palette(palette_type)
        
        # Store palette in S3
        palette_id = str(uuid.uuid4())[:8]
        s3_key = f"palettes/{palette_id}.json"
        
        palette_data = {
            'id': palette_id,
            'type': palette_type,
            'colors': palette,
            'created_at': datetime.utcnow().isoformat(),
            'hex_colors': [rgb_to_hex(color) for color in palette]
        }
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(palette_data, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(palette_data)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def generate_color_palette(palette_type):
    """Generate color palette based on color theory"""
    base_hue = random.uniform(0, 1)
    saturation = random.uniform(0.6, 0.9)
    lightness = random.uniform(0.4, 0.8)
    
    colors = []
    
    if palette_type == 'complementary':
        # Base color and its complement
        colors.append(hsv_to_rgb(base_hue, saturation, lightness))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation, lightness))
        colors.append(hsv_to_rgb(base_hue, saturation * 0.7, lightness * 1.2))
        colors.append(hsv_to_rgb((base_hue + 0.5) % 1, saturation * 0.7, lightness * 1.2))
        
    elif palette_type == 'analogous':
        # Colors adjacent on color wheel
        for i in range(5):
            hue = (base_hue + (i * 0.08)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
            
    elif palette_type == 'triadic':
        # Three colors evenly spaced on color wheel
        for i in range(3):
            hue = (base_hue + (i * 0.333)) % 1
            colors.append(hsv_to_rgb(hue, saturation, lightness))
        # Add two supporting colors
        colors.append(hsv_to_rgb(base_hue, saturation * 0.5, min(lightness * 1.3, 1.0)))
        colors.append(hsv_to_rgb(base_hue, saturation * 0.3, lightness * 0.9))
        
    else:  # Random palette
        for i in range(5):
            hue = random.uniform(0, 1)
            sat = random.uniform(0.5, 0.9)
            light = random.uniform(0.3, 0.8)
            colors.append(hsv_to_rgb(hue, sat, light))
    
    return colors

def hsv_to_rgb(h, s, v):
    """Convert HSV color to RGB"""
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return [int(r * 255), int(g * 255), int(b * 255)]

def rgb_to_hex(rgb):
    """Convert RGB to hex color code"""
    return f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}"
EOF
    
    # Create deployment package
    execute_cmd "cd $SCRIPT_DIR && zip -r function.zip lambda_function.py" \
        "Creating Lambda deployment package"
    
    log_success "Lambda function code created and packaged"
}

#######################################################################
# Lambda Function Deployment
#######################################################################

deploy_lambda_function() {
    log_info "Deploying Lambda function..."
    
    # Wait for IAM role to be fully propagated
    if ! is_dry_run; then
        log_info "Waiting for IAM role propagation..."
        sleep 10
    fi
    
    # Create Lambda function
    execute_cmd "aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --runtime python3.12 \
        --role arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://$SCRIPT_DIR/function.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables=\"{BUCKET_NAME=$BUCKET_NAME}\"" \
        "Creating Lambda function"
    
    # Wait for function to be active
    if ! is_dry_run; then
        log_info "Waiting for Lambda function to be active..."
        aws lambda wait function-active --function-name "$FUNCTION_NAME"
    fi
    
    log_success "Lambda function $FUNCTION_NAME deployed successfully"
}

#######################################################################
# Function URL Creation
#######################################################################

create_function_url() {
    log_info "Creating Function URL for HTTP access..."
    
    # Create function URL
    local function_url_cmd="aws lambda create-function-url-config \
        --function-name $FUNCTION_NAME \
        --auth-type NONE \
        --cors 'AllowCredentials=false,AllowMethods=\"GET,POST,OPTIONS\",AllowOrigins=\"*\",AllowHeaders=\"Content-Type\"' \
        --query FunctionUrl --output text"
    
    if is_dry_run; then
        echo "DRY RUN: $function_url_cmd"
        export FUNCTION_URL="https://example-function-url.lambda-url.$AWS_REGION.on.aws/"
    else
        export FUNCTION_URL
        FUNCTION_URL=$(eval "$function_url_cmd")
    fi
    
    # Add resource-based policy for public access
    execute_cmd "aws lambda add-permission \
        --function-name $FUNCTION_NAME \
        --statement-id AllowPublicAccess \
        --action lambda:InvokeFunctionUrl \
        --principal '*' \
        --function-url-auth-type NONE" \
        "Adding public access permission"
    
    log_success "Function URL created: $FUNCTION_URL"
}

#######################################################################
# Testing and Validation
#######################################################################

test_deployment() {
    if is_dry_run; then
        log_info "Skipping tests in dry-run mode"
        return 0
    fi
    
    log_info "Testing color palette generation..."
    
    # Test different palette types
    local test_types=("complementary" "analogous" "triadic" "random")
    
    for palette_type in "${test_types[@]}"; do
        log_info "Testing $palette_type palette..."
        
        # Test with curl if available, otherwise skip
        if command -v curl &> /dev/null; then
            local response
            response=$(curl -s "${FUNCTION_URL}?type=${palette_type}" 2>/dev/null || echo '{"error": "curl failed"}')
            
            if echo "$response" | jq -e '.hex_colors' &> /dev/null; then
                log_success "$palette_type palette generated successfully"
            else
                log_warning "$palette_type palette test failed or returned unexpected format"
            fi
        else
            log_warning "curl not available, skipping HTTP test for $palette_type"
        fi
    done
    
    # Verify S3 storage
    log_info "Verifying S3 storage..."
    local object_count
    object_count=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --prefix "palettes/" --query 'length(Contents)' --output text 2>/dev/null || echo "0")
    
    if [[ "$object_count" != "null" && "$object_count" -gt 0 ]]; then
        log_success "Found $object_count palette files in S3"
    else
        log_warning "No palette files found in S3 - this may be normal if tests didn't run"
    fi
}

#######################################################################
# Deployment Summary
#######################################################################

deployment_summary() {
    log_info "Deployment Summary:"
    log_info "=================="
    log_info "AWS Region: $AWS_REGION"
    log_info "S3 Bucket: $BUCKET_NAME"
    log_info "Lambda Function: $FUNCTION_NAME"
    log_info "IAM Role: $ROLE_NAME"
    if [[ -n "${FUNCTION_URL:-}" ]]; then
        log_info "Function URL: $FUNCTION_URL"
    fi
    log_info ""
    log_info "Test the deployment:"
    if [[ -n "${FUNCTION_URL:-}" ]]; then
        log_info "curl \"${FUNCTION_URL}?type=complementary\""
    fi
    log_info ""
    log_info "Available palette types: complementary, analogous, triadic, random"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

#######################################################################
# Main Deployment Process
#######################################################################

main() {
    log_info "Starting AWS Simple Color Palette Generator deployment..."
    
    if is_dry_run; then
        log_info "Running in DRY RUN mode - no resources will be created"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Create resources
    create_s3_bucket
    create_iam_role
    create_s3_policy
    create_lambda_code
    deploy_lambda_function
    create_function_url
    
    # Test deployment
    test_deployment
    
    # Cleanup temporary files
    log_info "Cleaning up temporary files..."
    rm -f "$SCRIPT_DIR"/trust-policy.json "$SCRIPT_DIR"/s3-policy.json
    rm -f "$SCRIPT_DIR"/lambda_function.py "$SCRIPT_DIR"/function.zip
    
    # Show summary
    deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"