#!/bin/bash

# Blockchain Voting System Deployment Script
# This script automates the deployment of the blockchain voting system
# with proper error handling and validation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
REGION="us-east-1"
PROFILE="default"
VALIDATE_ONLY=false
SKIP_BOOTSTRAP=false
ADMIN_EMAIL=""
FORCE_DEPLOY=false

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment    Environment (dev, staging, prod) [default: dev]"
    echo "  -r, --region         AWS region [default: us-east-1]"
    echo "  -p, --profile        AWS profile [default: default]"
    echo "  -m, --admin-email    Admin email for notifications"
    echo "  -v, --validate-only  Only validate, don't deploy"
    echo "  -s, --skip-bootstrap Skip CDK bootstrap"
    echo "  -f, --force          Force deployment without confirmation"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -e prod -r us-west-2 -m admin@example.com"
    echo "  $0 --validate-only"
    echo "  $0 --force --environment staging"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_message $BLUE "🔍 Validating prerequisites..."
    
    # Check if required tools are installed
    if ! command -v aws &> /dev/null; then
        print_message $RED "❌ AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v node &> /dev/null; then
        print_message $RED "❌ Node.js is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        print_message $RED "❌ npm is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --profile $PROFILE &> /dev/null; then
        print_message $RED "❌ AWS credentials not configured for profile: $PROFILE"
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_message $YELLOW "⚠️  CDK not found globally, installing..."
        npm install -g aws-cdk
    fi
    
    # Validate Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2)
    MIN_NODE_VERSION="18.0.0"
    if [ "$(printf '%s\n' "$MIN_NODE_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$MIN_NODE_VERSION" ]; then
        print_message $RED "❌ Node.js version $NODE_VERSION is too old. Minimum required: $MIN_NODE_VERSION"
        exit 1
    fi
    
    print_message $GREEN "✅ Prerequisites validated successfully"
}

# Function to setup environment
setup_environment() {
    print_message $BLUE "🔧 Setting up environment..."
    
    # Export AWS profile
    export AWS_PROFILE=$PROFILE
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)
    AWS_REGION=$REGION
    
    # Export CDK environment variables
    export CDK_DEFAULT_ACCOUNT=$AWS_ACCOUNT_ID
    export CDK_DEFAULT_REGION=$AWS_REGION
    export AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
    export AWS_REGION=$AWS_REGION
    
    print_message $GREEN "✅ Environment configured:"
    print_message $GREEN "   Account ID: $AWS_ACCOUNT_ID"
    print_message $GREEN "   Region: $AWS_REGION"
    print_message $GREEN "   Profile: $PROFILE"
    print_message $GREEN "   Environment: $ENVIRONMENT"
}

# Function to install dependencies
install_dependencies() {
    print_message $BLUE "📦 Installing dependencies..."
    
    if [ ! -d "node_modules" ]; then
        npm install
    else
        print_message $YELLOW "⚠️  Dependencies already installed, skipping..."
    fi
    
    print_message $GREEN "✅ Dependencies installed successfully"
}

# Function to run tests
run_tests() {
    print_message $BLUE "🧪 Running tests..."
    
    # Build the project
    npm run build
    
    # Run linting
    npm run lint
    
    # Run unit tests
    npm run test
    
    print_message $GREEN "✅ All tests passed"
}

# Function to validate CDK
validate_cdk() {
    print_message $BLUE "🔍 Validating CDK configuration..."
    
    # Synthesize the stacks
    cdk synth --all \
        --context environment=$ENVIRONMENT \
        --context adminEmail=$ADMIN_EMAIL \
        --profile $PROFILE
    
    # Run CDK diff to show changes
    print_message $BLUE "📋 CDK diff results:"
    cdk diff --all \
        --context environment=$ENVIRONMENT \
        --context adminEmail=$ADMIN_EMAIL \
        --profile $PROFILE || true
    
    print_message $GREEN "✅ CDK validation completed"
}

# Function to bootstrap CDK
bootstrap_cdk() {
    if [ "$SKIP_BOOTSTRAP" = true ]; then
        print_message $YELLOW "⚠️  Skipping CDK bootstrap as requested"
        return
    fi
    
    print_message $BLUE "🚀 Bootstrapping CDK..."
    
    cdk bootstrap \
        --context environment=$ENVIRONMENT \
        --profile $PROFILE
    
    print_message $GREEN "✅ CDK bootstrap completed"
}

# Function to deploy stacks
deploy_stacks() {
    print_message $BLUE "🚀 Deploying blockchain voting system..."
    
    # Deploy security stack first
    print_message $BLUE "📦 Deploying security stack..."
    cdk deploy \
        blockchain-voting-system-Security-$ENVIRONMENT \
        --context environment=$ENVIRONMENT \
        --context adminEmail=$ADMIN_EMAIL \
        --profile $PROFILE \
        --require-approval never \
        --progress events
    
    # Deploy core system stack
    print_message $BLUE "📦 Deploying core system stack..."
    cdk deploy \
        blockchain-voting-system-Core-$ENVIRONMENT \
        --context environment=$ENVIRONMENT \
        --context adminEmail=$ADMIN_EMAIL \
        --profile $PROFILE \
        --require-approval never \
        --progress events
    
    # Deploy monitoring stack
    print_message $BLUE "📦 Deploying monitoring stack..."
    cdk deploy \
        blockchain-voting-system-Monitoring-$ENVIRONMENT \
        --context environment=$ENVIRONMENT \
        --context adminEmail=$ADMIN_EMAIL \
        --profile $PROFILE \
        --require-approval never \
        --progress events
    
    print_message $GREEN "✅ All stacks deployed successfully"
}

# Function to show deployment outputs
show_outputs() {
    print_message $BLUE "📊 Deployment outputs:"
    
    # Get stack outputs
    SECURITY_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name blockchain-voting-system-Security-$ENVIRONMENT \
        --query 'Stacks[0].Outputs' \
        --output table \
        --profile $PROFILE 2>/dev/null || echo "Security stack outputs not available")
    
    CORE_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name blockchain-voting-system-Core-$ENVIRONMENT \
        --query 'Stacks[0].Outputs' \
        --output table \
        --profile $PROFILE 2>/dev/null || echo "Core stack outputs not available")
    
    MONITORING_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name blockchain-voting-system-Monitoring-$ENVIRONMENT \
        --query 'Stacks[0].Outputs' \
        --output table \
        --profile $PROFILE 2>/dev/null || echo "Monitoring stack outputs not available")
    
    echo ""
    print_message $GREEN "Security Stack Outputs:"
    echo "$SECURITY_OUTPUTS"
    echo ""
    
    print_message $GREEN "Core Stack Outputs:"
    echo "$CORE_OUTPUTS"
    echo ""
    
    print_message $GREEN "Monitoring Stack Outputs:"
    echo "$MONITORING_OUTPUTS"
    echo ""
}

# Function to confirm deployment
confirm_deployment() {
    if [ "$FORCE_DEPLOY" = true ]; then
        return 0
    fi
    
    print_message $YELLOW "⚠️  You are about to deploy to $ENVIRONMENT environment in $REGION region"
    print_message $YELLOW "   This will create AWS resources that may incur charges"
    print_message $YELLOW "   Admin email: ${ADMIN_EMAIL:-"Not specified"}"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message $RED "❌ Deployment cancelled"
        exit 1
    fi
}

# Main execution
main() {
    print_message $BLUE "🗳️  Blockchain Voting System Deployment"
    print_message $BLUE "======================================"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup environment
    setup_environment
    
    # Install dependencies
    install_dependencies
    
    # Run tests
    run_tests
    
    # Validate CDK
    validate_cdk
    
    # If validation only, exit here
    if [ "$VALIDATE_ONLY" = true ]; then
        print_message $GREEN "✅ Validation completed successfully"
        exit 0
    fi
    
    # Confirm deployment
    confirm_deployment
    
    # Bootstrap CDK
    bootstrap_cdk
    
    # Deploy stacks
    deploy_stacks
    
    # Show outputs
    show_outputs
    
    print_message $GREEN "🎉 Deployment completed successfully!"
    print_message $GREEN "   Environment: $ENVIRONMENT"
    print_message $GREEN "   Region: $REGION"
    print_message $GREEN "   Account: $AWS_ACCOUNT_ID"
    
    if [ -n "$ADMIN_EMAIL" ]; then
        print_message $GREEN "   Admin notifications will be sent to: $ADMIN_EMAIL"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -m|--admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        -v|--validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        -s|--skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOY=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_message $RED "❌ Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_message $RED "❌ Invalid environment: $ENVIRONMENT. Must be dev, staging, or prod"
    exit 1
fi

# Validate admin email if provided
if [ -n "$ADMIN_EMAIL" ] && [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    print_message $RED "❌ Invalid admin email format: $ADMIN_EMAIL"
    exit 1
fi

# Run main function
main