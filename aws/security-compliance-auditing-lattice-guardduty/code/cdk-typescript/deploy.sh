#!/bin/bash

# Security Compliance Auditing CDK Deployment Script
# This script automates the deployment of the security compliance auditing infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists node; then
        print_error "Node.js is not installed. Please install Node.js 18.x or later."
        exit 1
    fi
    
    if ! command_exists npm; then
        print_error "npm is not installed. Please install npm."
        exit 1
    fi
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! command_exists cdk; then
        print_error "AWS CDK is not installed. Install with: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    print_success "All prerequisites satisfied"
}

# Install dependencies
install_dependencies() {
    print_status "Installing npm dependencies..."
    npm install
    print_success "Dependencies installed"
}

# Bootstrap CDK if needed
bootstrap_cdk() {
    print_status "Checking CDK bootstrap status..."
    
    # Get current AWS account and region
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    
    if [ -z "$REGION" ]; then
        REGION="us-east-1"
        print_warning "No default region set, using us-east-1"
    fi
    
    print_status "Deploying to account $ACCOUNT in region $REGION"
    
    # Check if CDK is bootstrapped
    if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" >/dev/null 2>&1; then
        print_status "Bootstrapping CDK..."
        cdk bootstrap "aws://$ACCOUNT/$REGION"
        print_success "CDK bootstrapped"
    else
        print_success "CDK already bootstrapped"
    fi
}

# Parse command line arguments
parse_arguments() {
    EMAIL=""
    DISABLE_DEMO=false
    ENVIRONMENT="demo"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --disable-demo)
                DISABLE_DEMO=true
                shift
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Security Compliance Auditing CDK Deployment Script

Usage: $0 [OPTIONS]

Options:
    --email EMAIL           Email address for security alerts
    --disable-demo          Disable demo VPC Lattice service network
    --environment ENV       Environment name (default: demo)
    -h, --help             Show this help message

Examples:
    $0 --email security@company.com
    $0 --email alerts@company.com --environment production --disable-demo
    $0 --disable-demo

EOF
}

# Deploy the CDK stack
deploy_stack() {
    print_status "Deploying Security Compliance Auditing stack..."
    
    # Build CDK context parameters
    CONTEXT_PARAMS=""
    
    if [ -n "$EMAIL" ]; then
        CONTEXT_PARAMS="$CONTEXT_PARAMS -c emailForAlerts=$EMAIL"
    fi
    
    if [ "$DISABLE_DEMO" = true ]; then
        CONTEXT_PARAMS="$CONTEXT_PARAMS -c enableVpcLatticeDemo=false"
    fi
    
    CONTEXT_PARAMS="$CONTEXT_PARAMS -c environment=$ENVIRONMENT"
    
    # Deploy with context parameters
    eval "cdk deploy $CONTEXT_PARAMS --require-approval never"
    
    print_success "Stack deployed successfully!"
}

# Display post-deployment information
show_deployment_info() {
    print_success "Deployment completed!"
    echo ""
    print_status "Important information:"
    echo "  • Check your email for SNS subscription confirmation"
    echo "  • Monitor the CloudWatch dashboard for security events"
    echo "  • Compliance reports will be stored in the S3 bucket"
    echo "  • Review Lambda function logs for processing details"
    echo ""
    print_status "Next steps:"
    echo "  1. Confirm SNS email subscription"
    echo "  2. Access CloudWatch dashboard via the output URL"
    echo "  3. Generate test traffic to VPC Lattice (if demo enabled)"
    echo "  4. Review S3 bucket for compliance reports"
    echo ""
    print_warning "Remember to run 'cdk destroy' when you're done to avoid charges!"
}

# Main execution
main() {
    echo "🔒 Security Compliance Auditing CDK Deployment"
    echo "=============================================="
    echo ""
    
    parse_arguments "$@"
    check_prerequisites
    install_dependencies
    bootstrap_cdk
    deploy_stack
    show_deployment_info
}

# Run main function with all arguments
main "$@"