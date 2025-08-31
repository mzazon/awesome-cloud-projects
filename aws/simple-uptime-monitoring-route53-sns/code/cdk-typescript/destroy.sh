#!/bin/bash

# Simple Website Uptime Monitoring - CDK TypeScript Cleanup Script
# This script safely removes all monitoring resources

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

print_success "Prerequisites check completed"

# Check if stack exists
print_status "Checking for existing monitoring stack..."
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
    print_warning "No default region set, using us-east-1"
fi

STACK_NAME="UptimeMonitoringStack"

if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_status "Found monitoring stack: $STACK_NAME"
    
    # Get stack outputs for user information
    print_status "Current monitoring configuration:"
    WEBSITE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`WebsiteUrl`].OutputValue' --output text 2>/dev/null || echo "Unknown")
    ADMIN_EMAIL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`AdminEmail`].OutputValue' --output text 2>/dev/null || echo "Unknown")
    
    echo "  - Website: $WEBSITE_URL"
    echo "  - Admin Email: $ADMIN_EMAIL"
    echo
    
    # Confirmation prompt
    print_warning "This will permanently delete all uptime monitoring resources including:"
    echo "  - Route53 health check"
    echo "  - CloudWatch alarms"
    echo "  - SNS topic and email subscription"
    echo "  - All monitoring history and metrics"
    echo
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo
    
    if [ "$REPLY" != "DELETE" ]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    # Perform the destruction
    print_status "Removing uptime monitoring resources..."
    cdk destroy --force
    
    # Check destruction status
    if [ $? -eq 0 ]; then
        print_success "All monitoring resources have been successfully removed!"
        echo
        print_status "Cleanup completed:"
        echo "  ✓ Route53 health check deleted"
        echo "  ✓ CloudWatch alarms deleted"
        echo "  ✓ SNS topic and subscription removed"
        echo "  ✓ All monitoring history cleared"
        echo
        print_status "Your website is no longer being monitored."
        print_status "If you need monitoring again, run the deploy script."
    else
        print_error "Cleanup failed. Please check the error messages above."
        print_status "You may need to manually remove some resources from the AWS console."
        exit 1
    fi
    
else
    print_warning "No monitoring stack found. Nothing to clean up."
    print_status "If you have resources that need manual cleanup, check the AWS console:"
    echo "  - Route53 health checks"
    echo "  - CloudWatch alarms"
    echo "  - SNS topics"
fi

# Optional: Clean up local files
echo
read -p "Do you want to clean up local project files (node_modules, build files)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Cleaning up local files..."
    
    if [ -d "node_modules" ]; then
        rm -rf node_modules
        print_status "Removed node_modules directory"
    fi
    
    if [ -d "cdk.out" ]; then
        rm -rf cdk.out
        print_status "Removed cdk.out directory"
    fi
    
    if [ -f "cdk.context.json" ]; then
        rm -f cdk.context.json
        print_status "Removed cdk.context.json"
    fi
    
    # Clean up compiled files
    find . -name "*.js" -not -path "./node_modules/*" -not -name "jest.config.js" -delete 2>/dev/null || true
    find . -name "*.d.ts" -not -path "./node_modules/*" -delete 2>/dev/null || true
    
    print_success "Local cleanup completed"
fi

print_success "Cleanup process finished!"