#!/bin/bash

# Database Performance Monitoring CDK Deployment Script
# This script provides an easy way to deploy the CDK stack with common configurations

set -e

# Default values
STACK_NAME="DatabasePerformanceMonitoringStack"
REGION=""
NOTIFICATION_EMAIL=""
ENVIRONMENT="development"
DB_INSTANCE_CLASS="db.t3.small"
ENABLE_DASHBOARD="true"
ENABLE_ENCRYPTION="true"
SKIP_CONFIRMATION="false"
PROFILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -s, --stack-name NAME          CDK stack name (default: $STACK_NAME)"
    echo "  -r, --region REGION            AWS region (default: from AWS CLI config)"
    echo "  -e, --email EMAIL              Email for notifications (required)"
    echo "  -n, --environment ENV          Environment name (default: $ENVIRONMENT)"
    echo "  -i, --instance-class CLASS     DB instance class (default: $DB_INSTANCE_CLASS)"
    echo "  -d, --disable-dashboard        Disable CloudWatch dashboard creation"
    echo "  -u, --disable-encryption       Disable encryption at rest"
    echo "  -y, --yes                      Skip confirmation prompts"
    echo "  -p, --profile PROFILE          AWS CLI profile to use"
    echo "  -h, --help                     Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -e admin@example.com -r us-west-2 -n production"
    echo "  $0 --email admin@example.com --instance-class db.t3.medium --yes"
    echo "  $0 -e admin@example.com -p production-profile"
}

# Function to validate email format
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        print_color $RED "Error: Invalid email format: $email"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_color $BLUE "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_color $RED "Error: AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_color $RED "Error: AWS CDK is not installed. Please install it first:"
        print_color $YELLOW "npm install -g aws-cdk"
        exit 1
    fi
    
    # Check if TypeScript is installed
    if ! command -v tsc &> /dev/null; then
        print_color $RED "Error: TypeScript is not installed. Please install it first:"
        print_color $YELLOW "npm install -g typescript"
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        print_color $RED "Error: Node.js is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if [[ -n "$PROFILE" ]]; then
        export AWS_PROFILE=$PROFILE
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        print_color $RED "Error: AWS credentials not configured or invalid."
        print_color $YELLOW "Please run 'aws configure' or set AWS_PROFILE environment variable."
        exit 1
    fi
    
    print_color $GREEN "✓ All prerequisites met"
}

# Function to set region
set_region() {
    if [[ -z "$REGION" ]]; then
        REGION=$(aws configure get region)
        if [[ -z "$REGION" ]]; then
            print_color $RED "Error: No region specified and no default region configured."
            print_color $YELLOW "Please specify a region with -r or configure default region with 'aws configure'."
            exit 1
        fi
    fi
    
    export CDK_DEFAULT_REGION=$REGION
    print_color $GREEN "✓ Using region: $REGION"
}

# Function to bootstrap CDK if needed
bootstrap_cdk() {
    print_color $BLUE "Checking CDK bootstrap status..."
    
    # Check if CDK is bootstrapped in this region
    if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region $REGION &> /dev/null; then
        print_color $YELLOW "CDK not bootstrapped in region $REGION. Bootstrapping..."
        cdk bootstrap aws://$(aws sts get-caller-identity --query Account --output text)/$REGION
        print_color $GREEN "✓ CDK bootstrapped successfully"
    else
        print_color $GREEN "✓ CDK already bootstrapped"
    fi
}

# Function to install dependencies
install_dependencies() {
    print_color $BLUE "Installing dependencies..."
    
    if [[ ! -f "package.json" ]]; then
        print_color $RED "Error: package.json not found. Please run this script from the CDK project directory."
        exit 1
    fi
    
    npm install
    print_color $GREEN "✓ Dependencies installed"
}

# Function to build the project
build_project() {
    print_color $BLUE "Building TypeScript project..."
    
    npm run build
    print_color $GREEN "✓ Project built successfully"
}

# Function to deploy the stack
deploy_stack() {
    print_color $BLUE "Deploying CDK stack..."
    
    # Build context parameters
    local context_params=""
    
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        context_params="$context_params --context notificationEmail=$NOTIFICATION_EMAIL"
    fi
    
    context_params="$context_params --context environment=$ENVIRONMENT"
    context_params="$context_params --context dbInstanceClass=$DB_INSTANCE_CLASS"
    context_params="$context_params --context createDashboard=$ENABLE_DASHBOARD"
    context_params="$context_params --context enableEncryption=$ENABLE_ENCRYPTION"
    
    # Deploy with confirmation or without
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        cdk deploy $STACK_NAME --require-approval never $context_params
    else
        cdk deploy $STACK_NAME $context_params
    fi
    
    print_color $GREEN "✓ Stack deployed successfully"
}

# Function to show deployment summary
show_summary() {
    print_color $BLUE "Deployment Summary:"
    echo "===================="
    echo "Stack Name: $STACK_NAME"
    echo "Region: $REGION"
    echo "Environment: $ENVIRONMENT"
    echo "DB Instance Class: $DB_INSTANCE_CLASS"
    echo "Dashboard Enabled: $ENABLE_DASHBOARD"
    echo "Encryption Enabled: $ENABLE_ENCRYPTION"
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        echo "Notification Email: $NOTIFICATION_EMAIL"
    fi
    echo
    
    # Get stack outputs
    print_color $BLUE "Stack Outputs:"
    echo "==============="
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo
    print_color $GREEN "🎉 Database Performance Monitoring solution deployed successfully!"
    print_color $YELLOW "Don't forget to:"
    echo "  1. Confirm your email subscription in SNS"
    echo "  2. Review the CloudWatch dashboard"
    echo "  3. Test the Performance Insights integration"
    echo "  4. Configure additional monitoring as needed"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -e|--email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        -n|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -i|--instance-class)
            DB_INSTANCE_CLASS="$2"
            shift 2
            ;;
        -d|--disable-dashboard)
            ENABLE_DASHBOARD="false"
            shift
            ;;
        -u|--disable-encryption)
            ENABLE_ENCRYPTION="false"
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_color $RED "Error: Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$NOTIFICATION_EMAIL" ]]; then
    print_color $RED "Error: Email address is required for notifications."
    print_color $YELLOW "Please provide an email address with -e or --email option."
    exit 1
fi

# Validate email format
validate_email "$NOTIFICATION_EMAIL"

# Main execution
print_color $BLUE "Starting Database Performance Monitoring CDK deployment..."
echo

check_prerequisites
set_region
bootstrap_cdk
install_dependencies
build_project
deploy_stack
show_summary

print_color $GREEN "Deployment completed successfully! 🚀"