#!/bin/bash

# Simple Website Uptime Monitoring - CDK TypeScript Deployment Script
# This script helps deploy the uptime monitoring solution with proper validation

set -e  # Exit on any error

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

# Function to validate email format
validate_email() {
    local email=$1
    if [[ ! $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate URL format
validate_url() {
    local url=$1
    if [[ ! $url =~ ^https?://[A-Za-z0-9.-]+(\.[A-Za-z]{2,})?(/.*)?$ ]]; then
        return 1
    fi
    return 0
}

# Check prerequisites
print_status "Checking prerequisites..."

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials are not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    print_error "AWS CDK is not installed. Please install it with: npm install -g aws-cdk"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 18+ first."
    exit 1
fi

# Check Node.js version
NODE_VERSION=$(node --version | cut -d 'v' -f 2 | cut -d '.' -f 1)
if [ "$NODE_VERSION" -lt 18 ]; then
    print_error "Node.js version must be 18 or higher. Current version: $(node --version)"
    exit 1
fi

print_success "All prerequisites are met"

# Get configuration
print_status "Configuration setup..."

# Check for existing environment variables
if [ -n "$WEBSITE_URL" ] && [ -n "$ADMIN_EMAIL" ]; then
    print_status "Using environment variables for configuration"
    WEBSITE_URL_INPUT="$WEBSITE_URL"
    ADMIN_EMAIL_INPUT="$ADMIN_EMAIL"
else
    # Interactive input
    echo
    read -p "Enter the website URL to monitor (e.g., https://example.com): " WEBSITE_URL_INPUT
    read -p "Enter the admin email for alerts (e.g., admin@example.com): " ADMIN_EMAIL_INPUT
fi

# Validate inputs
if [ -z "$WEBSITE_URL_INPUT" ]; then
    print_error "Website URL is required"
    exit 1
fi

if [ -z "$ADMIN_EMAIL_INPUT" ]; then
    print_error "Admin email is required"
    exit 1
fi

if ! validate_url "$WEBSITE_URL_INPUT"; then
    print_error "Invalid URL format. Please use http:// or https://"
    exit 1
fi

if ! validate_email "$ADMIN_EMAIL_INPUT"; then
    print_error "Invalid email format"
    exit 1
fi

print_success "Configuration validated"

# Set environment variables
export WEBSITE_URL="$WEBSITE_URL_INPUT"
export ADMIN_EMAIL="$ADMIN_EMAIL_INPUT"

# Install dependencies
print_status "Installing dependencies..."
if [ ! -d "node_modules" ]; then
    npm install
else
    print_status "Dependencies already installed"
fi

# Check if CDK is bootstrapped
print_status "Checking CDK bootstrap status..."
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
    print_warning "No default region set, using us-east-1"
fi

# Try to describe the CDK toolkit stack
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$AWS_REGION" &> /dev/null; then
    print_status "CDK not bootstrapped. Bootstrapping now..."
    cdk bootstrap aws://$AWS_ACCOUNT/$AWS_REGION
    print_success "CDK bootstrapped successfully"
else
    print_status "CDK already bootstrapped"
fi

# Synthesize the template (dry run)
print_status "Synthesizing CloudFormation template..."
cdk synth > /dev/null
print_success "Template synthesis successful"

# Deploy the stack
print_status "Deploying uptime monitoring stack..."
echo
print_status "Website URL: $WEBSITE_URL"
print_status "Admin Email: $ADMIN_EMAIL"
print_status "AWS Account: $AWS_ACCOUNT"
print_status "AWS Region: $AWS_REGION"
echo

read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled by user"
    exit 0
fi

# Perform the deployment
cdk deploy --require-approval never

# Check deployment status
if [ $? -eq 0 ]; then
    print_success "Deployment completed successfully!"
    echo
    print_status "Next steps:"
    echo "1. Check your email ($ADMIN_EMAIL) for SNS subscription confirmation"
    echo "2. Click the confirmation link to receive alerts"
    echo "3. Monitor your website uptime in the AWS CloudWatch console"
    echo
    print_status "To view stack outputs:"
    echo "aws cloudformation describe-stacks --stack-name UptimeMonitoringStack --query 'Stacks[0].Outputs'"
    echo
    print_status "To test the monitoring:"
    echo "You can temporarily block your website or modify the health check to see alerts in action"
else
    print_error "Deployment failed. Please check the error messages above."
    exit 1
fi