#!/bin/bash
set -e

# Deploy script for Cost-Optimized Batch Processing CDK Stack
# This script sets up the Python environment and deploys the CDK stack

echo "🚀 Deploying Cost-Optimized Batch Processing CDK Stack..."

# Check if Python 3.8+ is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3.8+ is required but not installed."
    exit 1
fi

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is required but not installed."
    exit 1
fi

# Check if CDK is available
if ! command -v cdk &> /dev/null; then
    echo "❌ AWS CDK CLI is required but not installed."
    echo "Install with: npm install -g aws-cdk"
    exit 1
fi

# Get AWS account and region
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_ACCOUNT" ] || [ -z "$AWS_REGION" ]; then
    echo "❌ AWS credentials not configured properly."
    echo "Please run 'aws configure' first."
    exit 1
fi

echo "📋 Using AWS Account: $AWS_ACCOUNT"
echo "📋 Using AWS Region: $AWS_REGION"

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "🔧 Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📦 Installing dependencies..."
pip install -r requirements.txt

# Bootstrap CDK if needed
echo "🔧 Bootstrapping CDK (if needed)..."
cdk bootstrap aws://$AWS_ACCOUNT/$AWS_REGION

# Update CDK context with current account/region
echo "🔧 Updating CDK context..."
cdk context --clear

# Synthesize the stack
echo "🔨 Synthesizing CDK stack..."
cdk synth

# Deploy the stack
echo "🚀 Deploying CDK stack..."
cdk deploy --require-approval never

# Display outputs
echo "✅ Deployment completed successfully!"
echo ""
echo "📊 Stack Outputs:"
aws cloudformation describe-stacks \
    --stack-name CostOptimizedBatchProcessingStack \
    --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' \
    --output table

echo ""
echo "🔍 Next Steps:"
echo "1. Build and push your batch application container to ECR"
echo "2. Submit test jobs to the batch queue"
echo "3. Monitor job execution in CloudWatch"
echo ""
echo "📝 To submit a test job:"
echo "aws batch submit-job \\"
echo "  --job-name test-job-\$(date +%s) \\"
echo "  --job-queue \$(aws cloudformation describe-stacks --stack-name CostOptimizedBatchProcessingStack --query 'Stacks[0].Outputs[?OutputKey==\`JobQueueName\`].OutputValue' --output text) \\"
echo "  --job-definition \$(aws cloudformation describe-stacks --stack-name CostOptimizedBatchProcessingStack --query 'Stacks[0].Outputs[?OutputKey==\`JobDefinitionName\`].OutputValue' --output text)"
echo ""
echo "🧹 To clean up resources:"
echo "cdk destroy"