#!/bin/bash

# Advanced Request Routing with VPC Lattice and ALB - Deployment Script
# This script deploys the CDK TypeScript stack with error checking and validation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    print_status "Validating AWS credentials..."
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Get account and region info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        print_error "AWS region is not configured. Please set a default region."
        exit 1
    fi
    
    print_success "AWS credentials validated for account $AWS_ACCOUNT_ID in region $AWS_REGION"
}

# Function to check Node.js and npm
validate_nodejs() {
    print_status "Validating Node.js environment..."
    
    if ! command_exists node; then
        print_error "Node.js is not installed. Please install Node.js 18+."
        exit 1
    fi
    
    if ! command_exists npm; then
        print_error "npm is not installed. Please install npm."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        print_warning "Node.js version is $NODE_VERSION. Version 18+ is recommended."
    fi
    
    print_success "Node.js environment validated"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing npm dependencies..."
    
    if [ ! -f "package.json" ]; then
        print_error "package.json not found. Please run this script from the CDK project directory."
        exit 1
    fi
    
    npm install
    print_success "Dependencies installed successfully"
}

# Function to check if CDK is installed
validate_cdk() {
    print_status "Validating CDK installation..."
    
    if ! command_exists cdk; then
        print_warning "CDK CLI is not installed globally. Installing CDK..."
        npm install -g aws-cdk
    fi
    
    CDK_VERSION=$(cdk --version | cut -d' ' -f1)
    print_success "CDK version $CDK_VERSION is available"
}

# Function to bootstrap CDK if needed
bootstrap_cdk() {
    print_status "Checking CDK bootstrap status..."
    
    # Check if CDK is already bootstrapped
    BOOTSTRAP_STACK_NAME="CDKToolkit"
    if aws cloudformation describe-stacks --stack-name $BOOTSTRAP_STACK_NAME >/dev/null 2>&1; then
        print_success "CDK is already bootstrapped in this account/region"
    else
        print_status "Bootstrapping CDK..."
        cdk bootstrap
        print_success "CDK bootstrap completed"
    fi
}

# Function to validate CDK syntax
validate_cdk_syntax() {
    print_status "Validating CDK syntax and configuration..."
    
    # Compile TypeScript
    npm run build
    
    # Synthesize CloudFormation template
    cdk synth >/dev/null
    
    print_success "CDK syntax validation passed"
}

# Function to deploy the stack
deploy_stack() {
    print_status "Deploying the Advanced Request Routing stack..."
    
    # Get deployment parameters
    STACK_PREFIX=${1:-"AdvancedRouting"}
    ENVIRONMENT=${2:-"dev"}
    VPC_CIDR=${3:-"10.0.0.0/16"}
    TARGET_VPC_CIDR=${4:-"10.1.0.0/16"}
    
    print_status "Deployment parameters:"
    print_status "  Stack Prefix: $STACK_PREFIX"
    print_status "  Environment: $ENVIRONMENT"
    print_status "  Primary VPC CIDR: $VPC_CIDR"
    print_status "  Target VPC CIDR: $TARGET_VPC_CIDR"
    
    # Deploy with context parameters
    cdk deploy \
        --context stackPrefix="$STACK_PREFIX" \
        --context environment="$ENVIRONMENT" \
        --context vpcCidr="$VPC_CIDR" \
        --context targetVpcCidr="$TARGET_VPC_CIDR" \
        --require-approval never
    
    print_success "Stack deployment completed successfully!"
}

# Function to display stack outputs
display_outputs() {
    print_status "Retrieving stack outputs..."
    
    STACK_NAME="AdvancedRouting-dev"  # Default stack name
    
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
        print_success "Stack outputs:"
        aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
            --output table
    else
        print_warning "Stack not found or not yet fully deployed"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [STACK_PREFIX] [ENVIRONMENT] [VPC_CIDR] [TARGET_VPC_CIDR]"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 MyRouting prod                     # Custom prefix and environment"
    echo "  $0 Demo test 172.16.0.0/16 172.17.0.0/16  # Custom all parameters"
    echo ""
    echo "Default values:"
    echo "  STACK_PREFIX: AdvancedRouting"
    echo "  ENVIRONMENT: dev"
    echo "  VPC_CIDR: 10.0.0.0/16"
    echo "  TARGET_VPC_CIDR: 10.1.0.0/16"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "Advanced Request Routing Deployment"
    echo "=========================================="
    echo ""
    
    # Show usage if help requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Validation steps
    validate_aws_credentials
    validate_nodejs
    validate_cdk
    install_dependencies
    bootstrap_cdk
    validate_cdk_syntax
    
    echo ""
    print_status "All validations passed. Starting deployment..."
    echo ""
    
    # Deploy the stack
    deploy_stack "$1" "$2" "$3" "$4"
    
    echo ""
    print_success "Deployment completed successfully!"
    echo ""
    
    # Display outputs
    display_outputs
    
    echo ""
    print_success "To test the routing, use the VPC Lattice service domain from the outputs above."
    print_status "Example test commands:"
    echo "  curl -v \"http://\${LATTICE_DOMAIN}/api/v1/\""
    echo "  curl -v -H \"X-Service-Version: beta\" \"http://\${LATTICE_DOMAIN}/\""
    echo "  curl -v \"http://\${LATTICE_DOMAIN}/admin\"  # Should return 403"
    echo ""
    print_warning "Remember to run './destroy.sh' when you're done to avoid ongoing charges."
}

# Error handling
trap 'print_error "Deployment failed! Check the error messages above."' ERR

# Run main function
main "$@"