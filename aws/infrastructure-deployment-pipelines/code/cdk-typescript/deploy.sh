#!/bin/bash

# Infrastructure Deployment Pipeline Deployment Script
# This script deploys the CDK infrastructure deployment pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    log_error "AWS CDK CLI is not installed. Please install it first."
    echo "Run: npm install -g aws-cdk"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed. Please install it first."
    exit 1
fi

# Parse command line arguments
STACK_TYPE="basic"
ENVIRONMENT="dev"
FORCE_DEPLOY=false
SKIP_TESTS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --type|-t)
            STACK_TYPE="$2"
            shift 2
            ;;
        --environment|-e)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --force|-f)
            FORCE_DEPLOY=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --type, -t TYPE       Stack type: basic or advanced (default: basic)"
            echo "  --environment, -e ENV Environment: dev, staging, prod (default: dev)"
            echo "  --force, -f           Force deployment without confirmation"
            echo "  --skip-tests          Skip running tests"
            echo "  --help, -h            Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate stack type
if [[ "$STACK_TYPE" != "basic" && "$STACK_TYPE" != "advanced" ]]; then
    log_error "Invalid stack type: $STACK_TYPE. Must be 'basic' or 'advanced'."
    exit 1
fi

# Get AWS account and region
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [[ -z "$AWS_ACCOUNT" || -z "$AWS_REGION" ]]; then
    log_error "Unable to determine AWS account or region. Please check your AWS configuration."
    exit 1
fi

log_info "Starting deployment..."
log_info "AWS Account: $AWS_ACCOUNT"
log_info "AWS Region: $AWS_REGION"
log_info "Stack Type: $STACK_TYPE"
log_info "Environment: $ENVIRONMENT"

# Check if CDK is bootstrapped
log_info "Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$AWS_REGION" &> /dev/null; then
    log_warning "CDK is not bootstrapped in this region. Bootstrapping now..."
    cdk bootstrap aws://$AWS_ACCOUNT/$AWS_REGION
    log_success "CDK bootstrap completed"
else
    log_success "CDK is already bootstrapped"
fi

# Install dependencies
log_info "Installing Node.js dependencies..."
npm install
log_success "Dependencies installed"

# Run tests unless skipped
if [[ "$SKIP_TESTS" != true ]]; then
    log_info "Running tests..."
    npm test
    log_success "Tests passed"
else
    log_warning "Skipping tests"
fi

# Run linting
log_info "Running ESLint..."
npm run lint
log_success "Linting passed"

# Build the project
log_info "Building TypeScript project..."
npm run build
log_success "Build completed"

# Synthesize CloudFormation templates
log_info "Synthesizing CloudFormation templates..."
cdk synth
log_success "CDK synthesis completed"

# Determine stack name
if [[ "$STACK_TYPE" == "basic" ]]; then
    STACK_NAME="InfrastructureDeploymentPipeline"
else
    STACK_NAME="AdvancedPipelineStack"
fi

# Show diff if stack exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    log_info "Stack exists. Showing differences..."
    cdk diff "$STACK_NAME"
fi

# Confirm deployment
if [[ "$FORCE_DEPLOY" != true ]]; then
    echo
    log_warning "This will deploy the $STACK_TYPE pipeline stack to your AWS account."
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
fi

# Deploy the stack
log_info "Deploying $STACK_NAME..."
if cdk deploy "$STACK_NAME" --require-approval never; then
    log_success "Stack deployed successfully!"
else
    log_error "Stack deployment failed"
    exit 1
fi

# Get and display outputs
log_info "Retrieving stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs' \
    --output json)

if [[ "$OUTPUTS" != "null" && "$OUTPUTS" != "[]" ]]; then
    log_success "Stack outputs:"
    echo "$OUTPUTS" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"'
    
    # Extract repository clone URL
    REPO_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="RepositoryCloneUrl") | .OutputValue')
    if [[ "$REPO_URL" != "null" && "$REPO_URL" != "" ]]; then
        echo
        log_info "Next Steps:"
        echo "1. Clone the repository:"
        echo "   git clone $REPO_URL"
        echo "2. Add your CDK application code to the repository"
        echo "3. Commit and push to trigger the pipeline"
        echo "   git add ."
        echo "   git commit -m 'Initial commit'"
        echo "   git push origin main"
    fi
else
    log_warning "No stack outputs found"
fi

log_success "Deployment completed successfully!"
echo
log_info "You can monitor the pipeline in the AWS Console:"
echo "https://console.aws.amazon.com/codesuite/codepipeline/pipelines"