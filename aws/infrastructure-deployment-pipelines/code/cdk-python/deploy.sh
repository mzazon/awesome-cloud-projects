#!/bin/bash

# Infrastructure Deployment Pipeline - CDK Python Deployment Script
# This script deploys the infrastructure deployment pipeline using AWS CDK

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="infrastructure-deployment-pipeline"
STACK_NAME="InfrastructurePipelineStack"

# Function to print colored output
print_info() {
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

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_error "AWS CDK is not installed. Please install it first: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check if Python is installed
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please configure them first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to set up environment
setup_environment() {
    print_info "Setting up environment..."
    
    # Change to script directory
    cd "$SCRIPT_DIR"
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CDK_DEFAULT_ACCOUNT=$AWS_ACCOUNT_ID
    export CDK_DEFAULT_REGION=$AWS_REGION
    
    # Generate unique repository name if not provided
    if [ -z "$REPO_NAME" ]; then
        RANDOM_SUFFIX=$(date +%s | tail -c 6)
        export REPO_NAME="infrastructure-pipeline-${RANDOM_SUFFIX}"
    fi
    
    print_info "AWS Region: $AWS_REGION"
    print_info "AWS Account: $AWS_ACCOUNT_ID"
    print_info "Repository Name: $REPO_NAME"
    
    print_success "Environment setup completed"
}

# Function to install dependencies
install_dependencies() {
    print_info "Installing Python dependencies..."
    
    # Create virtual environment if it doesn't exist
    if [ ! -d ".venv" ]; then
        print_info "Creating virtual environment..."
        python3 -m venv .venv
    fi
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install requirements
    pip install -r requirements.txt
    
    print_success "Dependencies installed successfully"
}

# Function to run tests
run_tests() {
    print_info "Running unit tests..."
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Run unit tests
    python -m pytest tests/ -v --tb=short
    
    if [ $? -eq 0 ]; then
        print_success "Unit tests passed"
    else
        print_error "Unit tests failed"
        exit 1
    fi
}

# Function to bootstrap CDK
bootstrap_cdk() {
    print_info "Bootstrapping CDK..."
    
    # Check if CDK is already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region $AWS_REGION &> /dev/null; then
        print_info "CDK is already bootstrapped"
    else
        print_info "Bootstrapping CDK for the first time..."
        cdk bootstrap aws://$AWS_ACCOUNT_ID/$AWS_REGION
        print_success "CDK bootstrapped successfully"
    fi
}

# Function to synthesize CDK
synthesize_cdk() {
    print_info "Synthesizing CDK templates..."
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Synthesize CDK
    cdk synth
    
    print_success "CDK synthesis completed"
}

# Function to deploy CDK stack
deploy_cdk() {
    print_info "Deploying CDK stack..."
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Deploy with confirmation
    if [ "$AUTO_APPROVE" = "true" ]; then
        cdk deploy $STACK_NAME --require-approval never
    else
        cdk deploy $STACK_NAME
    fi
    
    if [ $? -eq 0 ]; then
        print_success "CDK stack deployed successfully"
    else
        print_error "CDK stack deployment failed"
        exit 1
    fi
}

# Function to output important information
output_info() {
    print_info "Deployment completed successfully!"
    print_info ""
    print_info "Important outputs:"
    
    # Get stack outputs
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $AWS_REGION \
        --query 'Stacks[0].Outputs' \
        --output table 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "$OUTPUTS"
    else
        print_warning "Could not retrieve stack outputs"
    fi
    
    print_info ""
    print_info "Next steps:"
    print_info "1. Clone the CodeCommit repository"
    print_info "2. Push your infrastructure code to trigger the pipeline"
    print_info "3. Monitor the pipeline execution in the AWS Console"
    print_info ""
    print_info "Repository URL can be found in the stack outputs above"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -t, --test-only     Run tests only, don't deploy"
    echo "  -s, --skip-tests    Skip tests and deploy directly"
    echo "  -y, --auto-approve  Auto-approve deployment (no interactive prompts)"
    echo "  --repo-name NAME    Specify repository name (default: auto-generated)"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION          AWS region (default: from AWS CLI config)"
    echo "  REPO_NAME           Repository name (default: auto-generated)"
    echo "  AUTO_APPROVE        Auto-approve deployment (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Full deployment with tests"
    echo "  $0 --skip-tests                      # Deploy without running tests"
    echo "  $0 --test-only                       # Run tests only"
    echo "  $0 --auto-approve                    # Deploy without prompts"
    echo "  REPO_NAME=my-repo $0                 # Use specific repository name"
}

# Main function
main() {
    print_info "Starting Infrastructure Deployment Pipeline deployment..."
    print_info "Project: $PROJECT_NAME"
    print_info "Stack: $STACK_NAME"
    print_info ""
    
    # Parse command line arguments
    TEST_ONLY=false
    SKIP_TESTS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -t|--test-only)
                TEST_ONLY=true
                shift
                ;;
            -s|--skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            -y|--auto-approve)
                export AUTO_APPROVE=true
                shift
                ;;
            --repo-name)
                export REPO_NAME="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    install_dependencies
    
    if [ "$TEST_ONLY" = "true" ]; then
        run_tests
        print_success "Tests completed successfully"
        exit 0
    fi
    
    if [ "$SKIP_TESTS" = "false" ]; then
        run_tests
    fi
    
    bootstrap_cdk
    synthesize_cdk
    deploy_cdk
    output_info
    
    print_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"