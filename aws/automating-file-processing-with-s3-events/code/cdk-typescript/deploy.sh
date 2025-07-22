#!/bin/bash

# S3 Event Processing CDK Deployment Script
# This script deploys the S3 Event Notifications and Automated Processing stack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_error "AWS CDK is not installed. Please install it: npm install -g aws-cdk"
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
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    print_status "All prerequisites met!"
}

# Function to set environment variables
set_environment() {
    print_status "Setting up environment variables..."
    
    export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    export CDK_DEFAULT_REGION=$(aws configure get region)
    
    if [ -z "$CDK_DEFAULT_REGION" ]; then
        export CDK_DEFAULT_REGION="us-east-1"
        print_warning "No default region set, using us-east-1"
    fi
    
    print_status "Account: $CDK_DEFAULT_ACCOUNT"
    print_status "Region: $CDK_DEFAULT_REGION"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    npm install
    print_status "Dependencies installed successfully!"
}

# Function to build the project
build_project() {
    print_status "Building the project..."
    npm run build
    print_status "Project built successfully!"
}

# Function to run tests
run_tests() {
    if [ "$SKIP_TESTS" != "true" ]; then
        print_status "Running tests..."
        npm test
        print_status "All tests passed!"
    else
        print_warning "Skipping tests..."
    fi
}

# Function to check CDK bootstrap
check_bootstrap() {
    print_status "Checking CDK bootstrap status..."
    
    # Try to synthesize the stack to check if bootstrap is needed
    if ! cdk synth &> /dev/null; then
        print_warning "CDK bootstrap may be required..."
        print_status "Running CDK bootstrap..."
        cdk bootstrap
        print_status "CDK bootstrap completed!"
    else
        print_status "CDK bootstrap is already configured."
    fi
}

# Function to deploy the stack
deploy_stack() {
    print_status "Deploying the S3 Event Processing stack..."
    
    # Build deployment command with optional parameters
    DEPLOY_CMD="cdk deploy"
    
    if [ -n "$ENVIRONMENT" ]; then
        DEPLOY_CMD="$DEPLOY_CMD -c environment=$ENVIRONMENT"
    fi
    
    if [ -n "$NOTIFICATION_EMAIL" ]; then
        DEPLOY_CMD="$DEPLOY_CMD -c notificationEmail=$NOTIFICATION_EMAIL"
    fi
    
    if [ -n "$BUCKET_NAME" ]; then
        DEPLOY_CMD="$DEPLOY_CMD -c bucketName=$BUCKET_NAME"
    fi
    
    if [ "$ENABLE_ENCRYPTION" == "false" ]; then
        DEPLOY_CMD="$DEPLOY_CMD -c enableEncryption=false"
    fi
    
    if [ -n "$LOG_RETENTION_DAYS" ]; then
        DEPLOY_CMD="$DEPLOY_CMD -c logRetentionDays=$LOG_RETENTION_DAYS"
    fi
    
    if [ "$AUTO_APPROVE" == "true" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --require-approval never"
    fi
    
    print_status "Running: $DEPLOY_CMD"
    eval $DEPLOY_CMD
    
    print_status "Stack deployed successfully!"
}

# Function to display stack outputs
show_outputs() {
    print_status "Stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name S3EventProcessingStack \
        --query 'Stacks[0].Outputs' \
        --output table
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment          Environment name (dev, staging, prod)"
    echo "  -m, --email               Notification email for SNS subscriptions"
    echo "  -b, --bucket-name         Custom S3 bucket name"
    echo "  -r, --retention-days      CloudWatch log retention days"
    echo "      --no-encryption       Disable encryption for development"
    echo "      --skip-tests          Skip running tests"
    echo "      --auto-approve        Auto-approve deployment without prompts"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -e dev -m admin@example.com"
    echo "  $0 -e prod -m ops@company.com -r 90"
    echo "  $0 --environment staging --no-encryption --skip-tests"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -m|--email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        -b|--bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -r|--retention-days)
            LOG_RETENTION_DAYS="$2"
            shift 2
            ;;
        --no-encryption)
            ENABLE_ENCRYPTION="false"
            shift
            ;;
        --skip-tests)
            SKIP_TESTS="true"
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE="true"
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

# Main execution
main() {
    print_status "Starting S3 Event Processing CDK deployment..."
    
    check_prerequisites
    set_environment
    install_dependencies
    build_project
    run_tests
    check_bootstrap
    deploy_stack
    show_outputs
    
    print_status "Deployment completed successfully!"
    print_status ""
    print_status "Next steps:"
    print_status "1. Test the immediate processing: aws s3 cp test.txt s3://\$(BUCKET_NAME)/immediate/test.txt"
    print_status "2. Test the batch processing: aws s3 cp test.txt s3://\$(BUCKET_NAME)/batch/test.txt"
    print_status "3. Test the notifications: aws s3 cp test.txt s3://\$(BUCKET_NAME)/uploads/test.txt"
    print_status "4. Monitor Lambda logs: aws logs tail /aws/lambda/file-processor-* --follow"
}

# Run main function
main