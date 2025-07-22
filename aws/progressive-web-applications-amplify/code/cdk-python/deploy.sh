#!/bin/bash

# Progressive Web Application CDK Deployment Script
# This script automates the deployment of the PWA infrastructure

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="${PROJECT_NAME:-fullstack-pwa}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-us-east-1}"
ENABLE_DELETION_PROTECTION="${ENABLE_DELETION_PROTECTION:-false}"

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_error "AWS CDK is not installed. Please install it with: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check if Python is installed
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed. Please install Python 3.8 or later."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' or set up credentials."
        exit 1
    fi
    
    print_success "All prerequisites are met."
}

# Function to set up Python environment
setup_python_env() {
    print_status "Setting up Python environment..."
    
    # Create virtual environment if it doesn't exist
    if [ ! -d ".venv" ]; then
        print_status "Creating virtual environment..."
        python3 -m venv .venv
    fi
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install dependencies
    print_status "Installing Python dependencies..."
    pip install -r requirements.txt
    
    print_success "Python environment set up successfully."
}

# Function to bootstrap CDK
bootstrap_cdk() {
    print_status "Checking CDK bootstrap status..."
    
    # Get AWS account ID and region
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Check if CDK is already bootstrapped
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region $REGION &> /dev/null; then
        print_success "CDK is already bootstrapped in $REGION."
    else
        print_status "Bootstrapping CDK in $REGION..."
        cdk bootstrap aws://$ACCOUNT_ID/$REGION
        print_success "CDK bootstrap completed."
    fi
}

# Function to run tests
run_tests() {
    print_status "Running unit tests..."
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Run tests
    if python -m pytest tests/ -v; then
        print_success "All tests passed."
    else
        print_warning "Some tests failed. Continuing with deployment..."
    fi
}

# Function to deploy the stack
deploy_stack() {
    print_status "Deploying Progressive Web Application stack..."
    
    # Activate virtual environment
    source .venv/bin/activate
    
    # Stack name
    STACK_NAME="ProgressiveWebAppStack-${ENVIRONMENT}"
    
    # Deploy with parameters
    cdk deploy $STACK_NAME \
        --parameters ProjectName=$PROJECT_NAME \
        --parameters EnvironmentName=$ENVIRONMENT \
        --parameters EnableDeletionProtection=$ENABLE_DELETION_PROTECTION \
        --require-approval never \
        --verbose
    
    print_success "Stack deployment completed successfully!"
}

# Function to show outputs
show_outputs() {
    print_status "Retrieving stack outputs..."
    
    STACK_NAME="ProgressiveWebAppStack-${ENVIRONMENT}"
    
    # Get stack outputs
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs' \
        --output table 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "Stack Outputs:"
        echo "=============="
        echo "$OUTPUTS"
        echo ""
        
        # Extract key outputs
        USER_POOL_ID=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --region $REGION \
            --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
            --output text 2>/dev/null)
        
        GRAPHQL_URL=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --region $REGION \
            --query 'Stacks[0].Outputs[?OutputKey==`GraphQLApiUrl`].OutputValue' \
            --output text 2>/dev/null)
        
        AMPLIFY_URL=$(aws cloudformation describe-stacks \
            --stack-name $STACK_NAME \
            --region $REGION \
            --query 'Stacks[0].Outputs[?OutputKey==`AmplifyAppUrl`].OutputValue' \
            --output text 2>/dev/null)
        
        echo "Key Resources:"
        echo "=============="
        echo "User Pool ID: $USER_POOL_ID"
        echo "GraphQL API URL: $GRAPHQL_URL"
        echo "Amplify App URL: $AMPLIFY_URL"
        echo ""
    else
        print_warning "Could not retrieve stack outputs. Stack may still be deploying."
    fi
}

# Function to clean up resources
cleanup() {
    print_status "Cleaning up resources..."
    
    STACK_NAME="ProgressiveWebAppStack-${ENVIRONMENT}"
    
    # Confirm deletion
    read -p "Are you sure you want to delete the stack '$STACK_NAME'? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Activate virtual environment
        source .venv/bin/activate
        
        # Delete stack
        cdk destroy $STACK_NAME \
            --force \
            --verbose
        
        print_success "Stack deleted successfully!"
    else
        print_status "Stack deletion cancelled."
    fi
}

# Function to show help
show_help() {
    echo "Progressive Web Application CDK Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy     Deploy the PWA stack (default)"
    echo "  test       Run unit tests only"
    echo "  outputs    Show stack outputs"
    echo "  diff       Show differences between current and deployed stack"
    echo "  synth      Synthesize CloudFormation template"
    echo "  cleanup    Delete the deployed stack"
    echo "  help       Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME                 Name of the project (default: fullstack-pwa)"
    echo "  ENVIRONMENT                  Environment name (default: dev)"
    echo "  AWS_REGION                   AWS region (default: us-east-1)"
    echo "  ENABLE_DELETION_PROTECTION   Enable deletion protection (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  PROJECT_NAME=my-pwa ENVIRONMENT=prod $0 deploy"
    echo "  $0 test"
    echo "  $0 cleanup"
}

# Main function
main() {
    local command=${1:-deploy}
    
    case $command in
        deploy)
            check_prerequisites
            setup_python_env
            bootstrap_cdk
            run_tests
            deploy_stack
            show_outputs
            ;;
        test)
            setup_python_env
            run_tests
            ;;
        outputs)
            show_outputs
            ;;
        diff)
            source .venv/bin/activate
            cdk diff "ProgressiveWebAppStack-${ENVIRONMENT}"
            ;;
        synth)
            source .venv/bin/activate
            cdk synth "ProgressiveWebAppStack-${ENVIRONMENT}"
            ;;
        cleanup)
            cleanup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"