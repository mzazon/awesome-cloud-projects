#!/bin/bash

# Deployment script for Persistent Customer Support Agent CDK Python Application
# This script handles the complete deployment process including prerequisites

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Python
    if ! command_exists python3; then
        log_error "Python 3 is required but not installed."
        exit 1
    fi
    
    # Check Python version
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'; then
        log_error "Python 3.8 or higher is required. Current version: $PYTHON_VERSION"
        exit 1
    fi
    log_success "Python $PYTHON_VERSION found"
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is required but not installed."
        log_info "Install it from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    log_success "AWS CLI found"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        log_info "Run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    log_success "AWS credentials configured for account: $ACCOUNT_ID in region: $REGION"
    
    # Check CDK CLI
    if ! command_exists cdk; then
        log_warning "CDK CLI not found. Installing globally..."
        if command_exists npm; then
            npm install -g aws-cdk
        else
            log_error "npm is required to install CDK CLI. Install Node.js first."
            exit 1
        fi
    fi
    
    CDK_VERSION=$(cdk --version)
    log_success "CDK CLI found: $CDK_VERSION"
}

# Function to setup Python virtual environment
setup_venv() {
    log_info "Setting up Python virtual environment..."
    
    if [ ! -d ".venv" ]; then
        python3 -m venv .venv
        log_success "Virtual environment created"
    else
        log_info "Virtual environment already exists"
    fi
    
    # Activate virtual environment
    source .venv/bin/activate
    log_success "Virtual environment activated"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install dependencies
    log_info "Installing Python dependencies..."
    pip install -r requirements.txt
    log_success "Dependencies installed"
}

# Function to bootstrap CDK
bootstrap_cdk() {
    log_info "Checking CDK bootstrap status..."
    
    # Check if CDK is already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit >/dev/null 2>&1; then
        log_info "CDK already bootstrapped"
    else
        log_info "Bootstrapping CDK..."
        cdk bootstrap
        log_success "CDK bootstrapped successfully"
    fi
}

# Function to deploy the stack
deploy_stack() {
    log_info "Synthesizing CDK application..."
    cdk synth
    log_success "CDK synthesis completed"
    
    log_info "Deploying CDK stack..."
    cdk deploy --require-approval never
    log_success "CDK stack deployed successfully"
}

# Function to get stack outputs
get_stack_outputs() {
    log_info "Retrieving stack outputs..."
    
    STACK_NAME="PersistentCustomerSupportStack"
    
    # Get outputs
    API_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
        --output text 2>/dev/null || echo "Not available")
    
    LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
        --output text 2>/dev/null || echo "Not available")
    
    DDB_TABLE=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' \
        --output text 2>/dev/null || echo "Not available")
    
    MEMORY_NAME=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`AgentCoreMemoryName`].OutputValue' \
        --output text 2>/dev/null || echo "Not available")
    
    echo
    log_success "Deployment completed successfully!"
    echo
    echo "=== Stack Outputs ==="
    echo "API Endpoint: $API_ENDPOINT"
    echo "Lambda Function: $LAMBDA_FUNCTION"
    echo "DynamoDB Table: $DDB_TABLE"
    echo "Memory Name: $MEMORY_NAME"
    echo
}

# Function to display post-deployment instructions
show_post_deployment() {
    log_warning "IMPORTANT: Post-deployment setup required!"
    echo
    echo "1. Create Bedrock AgentCore Memory:"
    echo "   aws bedrock-agentcore-control create-memory \\"
    echo "       --name $MEMORY_NAME \\"
    echo "       --description 'Customer support agent memory' \\"
    echo "       --event-expiry-duration 'P30D'"
    echo
    echo "2. Update Lambda environment variable:"
    echo "   MEMORY_ID=\$(aws bedrock-agentcore-control get-memory \\"
    echo "       --name $MEMORY_NAME \\"
    echo "       --query 'memory.memoryId' --output text)"
    echo "   aws lambda update-function-configuration \\"
    echo "       --function-name $LAMBDA_FUNCTION \\"
    echo "       --environment Variables=\"{DDB_TABLE_NAME=$DDB_TABLE,MEMORY_ID=\$MEMORY_ID}\""
    echo
    echo "3. Test the API:"
    echo "   curl -X POST $API_ENDPOINT \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"customerId\": \"test-001\", \"message\": \"Hello, I need help.\"}'"
    echo
    log_info "See README.md for detailed usage instructions."
}

# Main deployment function
main() {
    echo "========================================"
    echo "CDK Python Deployment Script"
    echo "Persistent Customer Support Agent"
    echo "========================================"
    echo
    
    # Parse command line arguments
    SKIP_PREREQ=false
    SKIP_BOOTSTRAP=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-prereq)
                SKIP_PREREQ=true
                shift
                ;;
            --skip-bootstrap)
                SKIP_BOOTSTRAP=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --skip-prereq    Skip prerequisite checks"
                echo "  --skip-bootstrap Skip CDK bootstrap check"
                echo "  -h, --help       Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run deployment steps
    if [ "$SKIP_PREREQ" = false ]; then
        check_prerequisites
    fi
    
    setup_venv
    
    if [ "$SKIP_BOOTSTRAP" = false ]; then
        bootstrap_cdk
    fi
    
    deploy_stack
    get_stack_outputs
    show_post_deployment
}

# Run main function
main "$@"