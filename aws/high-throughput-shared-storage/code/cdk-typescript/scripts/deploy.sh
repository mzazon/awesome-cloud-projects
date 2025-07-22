#!/bin/bash

# High-Performance File Systems with Amazon FSx - CDK Deployment Script
# This script deploys the FSx infrastructure using AWS CDK

set -e

echo "🚀 Starting deployment of High-Performance File Systems with Amazon FSx..."

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Aborting." >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "❌ Node.js is required but not installed. Aborting." >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "❌ npm is required but not installed. Aborting." >&2; exit 1; }

# Verify AWS credentials
echo "🔐 Checking AWS credentials..."
aws sts get-caller-identity > /dev/null || { echo "❌ AWS credentials not configured. Please run 'aws configure' first." >&2; exit 1; }

# Set environment variables
export CDK_DEFAULT_REGION=${AWS_REGION:-$(aws configure get region)}
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo "📍 Deploying to region: $CDK_DEFAULT_REGION"
echo "🏠 Using account: $CDK_DEFAULT_ACCOUNT"

# Install dependencies
echo "📦 Installing dependencies..."
npm install

# Bootstrap CDK if needed
echo "🏗️  Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region $CDK_DEFAULT_REGION > /dev/null 2>&1; then
    echo "🔧 Bootstrapping CDK..."
    npx cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$CDK_DEFAULT_REGION
else
    echo "✅ CDK already bootstrapped"
fi

# Build the project
echo "🔨 Building TypeScript project..."
npm run build

# Run tests
echo "🧪 Running tests..."
npm test

# Show diff
echo "📋 Showing deployment diff..."
npx cdk diff

# Confirm deployment
echo ""
read -p "🤔 Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Deploy the stack
echo "🚀 Deploying stack..."
npx cdk deploy --require-approval never

echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "📋 Important outputs saved above. Please note:"
echo "• Lustre file system ID and DNS name for mounting"
echo "• Windows file system DNS name for SMB access"
echo "• S3 bucket name for data repository operations"
echo "• EC2 instance ID for testing file system access"
echo ""
echo "🔧 Next steps:"
echo "1. Connect to the EC2 instance using AWS Systems Manager Session Manager"
echo "2. Use the Lustre mount command from the outputs to mount the file system"
echo "3. Test performance using the commands in the README.md"
echo "4. Monitor CloudWatch alarms for file system health"
echo ""
echo "💰 Remember to run 'npm run destroy' when done to avoid ongoing charges!"
echo ""