#!/bin/bash

# URL Shortener CDK Deployment Script
set -e

echo "🚀 Deploying URL Shortener CDK Application"
echo "==========================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    echo "❌ AWS CDK is not installed. Installing globally..."
    npm install -g aws-cdk
fi

# Check if Node.js version is compatible
node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$node_version" -lt 18 ]; then
    echo "❌ Node.js version 18 or higher is required. Current version: $(node --version)"
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

# Install dependencies
echo "📦 Installing dependencies..."
npm install

# Build the application
echo "🔨 Building TypeScript application..."
npm run build

# Check if CDK is bootstrapped
echo "🏗️  Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region $aws_region &> /dev/null; then
    echo "🚀 Bootstrapping CDK for account $aws_account in region $aws_region..."
    npm run bootstrap
else
    echo "✅ CDK already bootstrapped"
fi

# Synthesize the template
echo "📋 Synthesizing CloudFormation template..."
npm run synth

# Deploy the stack
echo "🚢 Deploying URL Shortener stack..."
npm run deploy

# Get outputs
echo "📊 Retrieving stack outputs..."
API_URL=$(aws cloudformation describe-stacks \
    --stack-name UrlShortenerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text 2>/dev/null || echo "Not available")

LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name UrlShortenerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text 2>/dev/null || echo "Not available")

TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name UrlShortenerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' \
    --output text 2>/dev/null || echo "Not available")

echo ""
echo "🎉 Deployment Complete!"
echo "======================"
echo "API Gateway URL: $API_URL"
echo "Lambda Function: $LAMBDA_FUNCTION"
echo "DynamoDB Table: $TABLE_NAME"
echo ""
echo "📝 Test your deployment:"
echo "curl -X POST ${API_URL}shorten \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"url\": \"https://example.com\"}'"
echo ""
echo "🎯 Create short URLs: ${API_URL}shorten"
echo "🔗 Redirect URLs: ${API_URL}{short_id}"
echo ""
echo "📊 Monitor your application:"
echo "• CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=${aws_region}#logsV2:log-groups"
echo "• DynamoDB: https://console.aws.amazon.com/dynamodbv2/home?region=${aws_region}#tables"
echo "• API Gateway: https://console.aws.amazon.com/apigateway/home?region=${aws_region}#/apis"
echo ""
echo "💡 To destroy resources: npm run destroy"