#!/bin/bash

# Knowledge Management Assistant - CDK Deployment Script
# This script deploys the complete knowledge management solution using AWS CDK

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="KnowledgeManagementAssistant"
ENVIRONMENT="development"
REGION="us-east-1"
REQUIRE_APPROVAL="any-change"
ENABLE_CDK_NAG="true"

# Function to print colored output
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

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --stack-name NAME     Stack name (default: KnowledgeManagementAssistant)"
    echo "  -e, --environment ENV     Environment (default: development)"
    echo "  -r, --region REGION       AWS region (default: us-east-1)"
    echo "  -b, --bucket-name NAME    Custom S3 bucket name"
    echo "  -c, --cost-center CC      Cost center tag"
    echo "  --no-approval            Skip approval prompts"
    echo "  --disable-nag            Disable CDK Nag security checks"
    echo "  --dry-run                Synthesize only, don't deploy"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --stack-name MyKnowledgeAssistant --environment production"
    echo "  $0 --region us-west-2 --bucket-name my-enterprise-docs"
    echo "  $0 --dry-run  # Just synthesize templates"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -b|--bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -c|--cost-center)
            COST_CENTER="$2"
            shift 2
            ;;
        --no-approval)
            REQUIRE_APPROVAL="never"
            shift
            ;;
        --disable-nag)
            ENABLE_CDK_NAG="false"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate prerequisites
print_status "Validating prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 18 or later."
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    print_error "Node.js version 18 or later is required. Current version: $(node --version)"
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed. Please install npm."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    print_warning "AWS CDK is not installed globally. Installing it now..."
    npm install -g aws-cdk
fi

# Validate AWS credentials
print_status "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Get AWS account and region info
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${CDK_DEFAULT_REGION:-$REGION}

print_success "AWS Account: $AWS_ACCOUNT"
print_success "AWS Region: $AWS_REGION"

# Validate Bedrock model access
print_status "Checking Bedrock model access in region $AWS_REGION..."

# List of required models
REQUIRED_MODELS=(
    "anthropic.claude-3-5-sonnet-20241022-v2:0"
    "amazon.titan-embed-text-v2:0"
)

for model in "${REQUIRED_MODELS[@]}"; do
    if aws bedrock list-foundation-models --region "$AWS_REGION" --query "modelSummaries[?modelId=='$model']" --output text | grep -q "$model"; then
        print_success "Model access confirmed: $model"
    else
        print_warning "Model may not be available or access not granted: $model"
        print_warning "Please ensure you have enabled model access in the Bedrock console"
    fi
done

# Install dependencies
print_status "Installing dependencies..."
npm install

# Bootstrap CDK if needed
print_status "Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$AWS_REGION" &> /dev/null; then
    print_status "Bootstrapping CDK..."
    cdk bootstrap aws://$AWS_ACCOUNT/$AWS_REGION
else
    print_success "CDK already bootstrapped"
fi

# Build context arguments
CONTEXT_ARGS=()
CONTEXT_ARGS+=("-c" "environment=$ENVIRONMENT")
CONTEXT_ARGS+=("-c" "enableCdkNag=$ENABLE_CDK_NAG")

if [ -n "$BUCKET_NAME" ]; then
    CONTEXT_ARGS+=("-c" "bucketName=$BUCKET_NAME")
fi

if [ -n "$COST_CENTER" ]; then
    CONTEXT_ARGS+=("-c" "costCenter=$COST_CENTER")
fi

# Set environment variables
export CDK_DEFAULT_ACCOUNT=$AWS_ACCOUNT
export CDK_DEFAULT_REGION=$AWS_REGION

# Synthesize the stack
print_status "Synthesizing CloudFormation template..."
if ! cdk synth "$STACK_NAME" "${CONTEXT_ARGS[@]}"; then
    print_error "CDK synthesis failed"
    exit 1
fi

print_success "CloudFormation template synthesized successfully"

# If dry run, exit here
if [ "$DRY_RUN" = "true" ]; then
    print_success "Dry run completed. CloudFormation template is in cdk.out/"
    exit 0
fi

# Show deployment summary
echo ""
print_status "Deployment Summary:"
echo "  Stack Name: $STACK_NAME"
echo "  Environment: $ENVIRONMENT"
echo "  Region: $AWS_REGION"
echo "  Account: $AWS_ACCOUNT"
echo "  CDK Nag: $ENABLE_CDK_NAG"
echo "  Bucket Name: ${BUCKET_NAME:-auto-generated}"
echo "  Cost Center: ${COST_CENTER:-engineering}"
echo ""

# Deploy the stack
print_status "Deploying stack: $STACK_NAME"
CDK_DEPLOY_ARGS=(
    "deploy"
    "$STACK_NAME"
    "--require-approval" "$REQUIRE_APPROVAL"
    "${CONTEXT_ARGS[@]}"
)

if ! cdk "${CDK_DEPLOY_ARGS[@]}"; then
    print_error "CDK deployment failed"
    exit 1
fi

# Get stack outputs
print_status "Retrieving stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query 'Stacks[0].Outputs' --output table 2>/dev/null || echo "No outputs available")

echo ""
print_success "Deployment completed successfully!"
echo ""
print_status "Stack Outputs:"
echo "$OUTPUTS"

# Provide next steps
echo ""
print_status "Next Steps:"
echo "1. Upload your enterprise documents to the S3 bucket"
echo "2. Wait for the knowledge base ingestion to complete (check Bedrock console)"
echo "3. Test the API endpoint with sample queries"
echo ""
echo "Example API call:"
echo "curl -X POST <QueryEndpoint> \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"query\": \"What is our remote work policy?\", \"sessionId\": \"test-session\"}'"
echo ""

# Get bucket name for document upload
BUCKET_NAME_OUTPUT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`DocumentBucketName`].OutputValue' --output text 2>/dev/null || echo "")

if [ -n "$BUCKET_NAME_OUTPUT" ]; then
    echo "Upload documents with:"
    echo "aws s3 cp your-documents/ s3://$BUCKET_NAME_OUTPUT/documents/ --recursive"
fi

print_success "Knowledge Management Assistant is ready!"