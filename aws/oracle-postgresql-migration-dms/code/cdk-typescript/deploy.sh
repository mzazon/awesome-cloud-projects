#!/bin/bash

# Database Migration Oracle to PostgreSQL - CDK Deployment Script
# This script automates the deployment of the database migration infrastructure

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate environment variables
validate_env() {
    local var_name=$1
    local var_value=$2
    if [ -z "$var_value" ]; then
        print_error "Environment variable $var_name is not set"
        return 1
    fi
    print_status "$var_name is set to: $var_value"
}

print_status "Starting Database Migration Infrastructure Deployment"
echo

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists node; then
    print_error "Node.js is not installed. Please install Node.js 18+ and try again."
    exit 1
fi

if ! command_exists npm; then
    print_error "npm is not installed. Please install npm and try again."
    exit 1
fi

if ! command_exists aws; then
    print_error "AWS CLI is not installed. Please install AWS CLI v2 and try again."
    exit 1
fi

if ! command_exists cdk; then
    print_error "AWS CDK is not installed. Please install CDK: npm install -g aws-cdk"
    exit 1
fi

print_success "All prerequisites are installed"
echo

# Validate required environment variables
print_status "Validating environment variables..."

if ! validate_env "CDK_DEFAULT_ACCOUNT" "$CDK_DEFAULT_ACCOUNT"; then
    print_error "Please set CDK_DEFAULT_ACCOUNT: export CDK_DEFAULT_ACCOUNT=123456789012"
    exit 1
fi

if ! validate_env "CDK_DEFAULT_REGION" "$CDK_DEFAULT_REGION"; then
    print_error "Please set CDK_DEFAULT_REGION: export CDK_DEFAULT_REGION=us-east-1"
    exit 1
fi

# Set default values for optional variables
export PROJECT_NAME=${PROJECT_NAME:-"oracle-to-postgresql"}
export ENVIRONMENT=${ENVIRONMENT:-"dev"}
export ORACLE_SERVER_NAME=${ORACLE_SERVER_NAME:-"your-oracle-server.example.com"}
export ORACLE_USERNAME=${ORACLE_USERNAME:-"oracle_user"}
export ORACLE_DATABASE_NAME=${ORACLE_DATABASE_NAME:-"ORCL"}

print_status "PROJECT_NAME: $PROJECT_NAME"
print_status "ENVIRONMENT: $ENVIRONMENT"
print_status "ORACLE_SERVER_NAME: $ORACLE_SERVER_NAME"
print_status "ORACLE_USERNAME: $ORACLE_USERNAME"
print_status "ORACLE_DATABASE_NAME: $ORACLE_DATABASE_NAME"
echo

# Check AWS credentials
print_status "Checking AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    print_error "AWS credentials are not configured or invalid"
    print_error "Please run: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS credentials are valid for account: $ACCOUNT_ID"
echo

# Install dependencies
print_status "Installing Node.js dependencies..."
npm install
print_success "Dependencies installed successfully"
echo

# Check if CDK is bootstrapped
print_status "Checking CDK bootstrap status..."
BOOTSTRAP_STACK_NAME="CDKToolkit"
if ! aws cloudformation describe-stacks --stack-name "$BOOTSTRAP_STACK_NAME" >/dev/null 2>&1; then
    print_warning "CDK is not bootstrapped in this account/region"
    read -p "Do you want to bootstrap CDK now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Bootstrapping CDK..."
        cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$CDK_DEFAULT_REGION
        print_success "CDK bootstrapped successfully"
    else
        print_error "CDK bootstrap is required. Please run: cdk bootstrap"
        exit 1
    fi
else
    print_success "CDK is already bootstrapped"
fi
echo

# Compile TypeScript
print_status "Compiling TypeScript..."
npm run build
print_success "TypeScript compilation completed"
echo

# Synthesize CloudFormation template
print_status "Synthesizing CloudFormation template..."
cdk synth >/dev/null
print_success "CloudFormation template generated successfully"
echo

# Show deployment preview
print_status "Showing deployment differences..."
cdk diff
echo

# Confirm deployment
print_warning "This will deploy AWS resources that may incur charges."
print_warning "Aurora PostgreSQL cluster and DMS replication instance will be created."
read -p "Do you want to proceed with deployment? (y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled by user"
    exit 0
fi

# Deploy the stack
print_status "Deploying the Database Migration Stack..."
cdk deploy --require-approval never

if [ $? -eq 0 ]; then
    print_success "Deployment completed successfully!"
    echo
    
    # Display post-deployment instructions
    print_status "Post-deployment steps:"
    echo "1. Update Oracle credentials in AWS Secrets Manager"
    echo "2. Configure Oracle database for CDC (supplemental logging)"
    echo "3. Test DMS endpoint connections"
    echo "4. Start the migration task"
    echo "5. Monitor migration progress"
    echo
    
    # Get stack outputs
    print_status "Stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name "DatabaseMigrationStack-$ENVIRONMENT" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo
    print_success "For detailed post-deployment instructions, see README.md"
    
else
    print_error "Deployment failed. Check the error messages above."
    exit 1
fi