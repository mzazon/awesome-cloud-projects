#!/bin/bash

# URL Shortener CDK Cleanup Script
set -e

echo "🧹 Cleaning up URL Shortener CDK Application"
echo "============================================"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    echo "❌ AWS CDK is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "🔐 Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

aws_account=$(aws sts get-caller-identity --query Account --output text)
aws_region=$(aws configure get region || echo "us-east-1")

echo "✅ AWS Account: $aws_account"
echo "✅ AWS Region: $aws_region"

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name UrlShortenerStack --region $aws_region &> /dev/null; then
    echo "ℹ️  UrlShortenerStack does not exist or has already been deleted."
    exit 0
fi

# Show current resources
echo "📋 Current stack resources:"
aws cloudformation describe-stack-resources \
    --stack-name UrlShortenerStack \
    --query 'StackResources[?ResourceStatus!=`DELETE_COMPLETE`].[ResourceType,LogicalResourceId,ResourceStatus]' \
    --output table

echo ""
echo "⚠️  WARNING: This will delete ALL resources in the UrlShortenerStack!"
echo "This includes:"
echo "• DynamoDB table (and all data)"
echo "• Lambda function"
echo "• API Gateway"
echo "• CloudWatch logs"
echo "• IAM roles and policies"
echo ""

read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "🚫 Cleanup cancelled."
    exit 0
fi

echo "🗑️  Destroying URL Shortener stack..."
npm run destroy

echo ""
echo "🧹 Cleanup operations completed!"
echo "==============================="
echo ""
echo "✅ All AWS resources have been deleted"
echo "💰 You will no longer be charged for these resources"
echo ""
echo "📝 If you want to redeploy:"
echo "   ./deploy.sh"
echo ""
echo "🔍 Verify cleanup in AWS Console:"
echo "• CloudFormation: https://console.aws.amazon.com/cloudformation/home?region=${aws_region}"
echo "• DynamoDB: https://console.aws.amazon.com/dynamodbv2/home?region=${aws_region}#tables"
echo "• Lambda: https://console.aws.amazon.com/lambda/home?region=${aws_region}#/functions"