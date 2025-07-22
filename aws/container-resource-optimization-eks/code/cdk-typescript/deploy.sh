#!/bin/bash

# Container Resource Optimization CDK Deployment Script
# This script deploys the complete container resource optimization solution

set -e

echo "🚀 Starting Container Resource Optimization CDK Deployment"
echo "============================================================"

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    echo "❌ AWS CDK is not installed. Installing now..."
    npm install -g aws-cdk
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js 16+ first."
    exit 1
fi

# Verify AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Get AWS account and region info
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=$(aws configure get region)

echo "✅ Prerequisites check passed"
echo "   AWS Account: $AWS_ACCOUNT_ID"
echo "   AWS Region: $AWS_REGION"
echo

# Install NPM dependencies
echo "📦 Installing dependencies..."
npm install
echo "✅ Dependencies installed"
echo

# Bootstrap CDK if needed
echo "🔧 Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region $AWS_REGION &> /dev/null; then
    echo "📋 Bootstrapping CDK for account $AWS_ACCOUNT_ID in region $AWS_REGION..."
    cdk bootstrap aws://$AWS_ACCOUNT_ID/$AWS_REGION
    echo "✅ CDK bootstrap completed"
else
    echo "✅ CDK already bootstrapped"
fi
echo

# Build TypeScript
echo "🔨 Building TypeScript..."
npm run build
echo "✅ TypeScript build completed"
echo

# Show what will be deployed
echo "👀 Reviewing deployment plan..."
cdk synth --quiet
echo "✅ Deployment plan generated"
echo

# Confirm deployment
echo "⚠️  About to deploy the following resources:"
echo "   - VPC with public and private subnets"
echo "   - EKS cluster with managed node groups"
echo "   - Vertical Pod Autoscaler (VPA)"
echo "   - CloudWatch Container Insights"
echo "   - Cost monitoring dashboard"
echo "   - SNS topic for cost alerts"
echo "   - Lambda function for automation"
echo
echo "💰 Estimated monthly cost: \$200-500 (varies by usage)"
echo

read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled by user"
    exit 1
fi

# Deploy the stack
echo "🚀 Deploying CDK stack..."
cdk deploy --require-approval never

# Check deployment status
if [ $? -eq 0 ]; then
    echo
    echo "✅ Deployment completed successfully!"
    echo
    
    # Get cluster name from CDK output
    CLUSTER_NAME=$(aws cloudformation describe-stacks \
        --stack-name ContainerResourceOptimizationStack \
        --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$CLUSTER_NAME" ]; then
        echo "📋 Post-deployment steps:"
        echo "1. Configure kubectl:"
        echo "   aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME"
        echo
        echo "2. Verify VPA installation (wait 5-10 minutes):"
        echo "   kubectl get pods -n vpa-system"
        echo
        echo "3. Check sample application:"
        echo "   kubectl get pods -n cost-optimization"
        echo
        echo "4. View VPA recommendations (after 15+ minutes):"
        echo "   kubectl describe vpa resource-test-app-vpa -n cost-optimization"
        echo
        echo "5. Access cost dashboard in AWS Console:"
        echo "   CloudWatch > Dashboards > cost-opt-cost-optimization"
        echo
        echo "6. Monitor costs and optimization opportunities"
        echo
    fi
    
    echo "🎉 Container Resource Optimization solution deployed successfully!"
    echo "   Cluster: $CLUSTER_NAME"
    echo "   Region: $AWS_REGION"
    echo
    echo "💡 Next steps:"
    echo "   - Wait 15+ minutes for VPA to generate recommendations"
    echo "   - Review cost optimization dashboard"
    echo "   - Configure SNS subscriptions for cost alerts"
    echo "   - Consider enabling VPA auto-updates after validation"
    
else
    echo "❌ Deployment failed. Please check the error messages above."
    echo "💡 Common troubleshooting steps:"
    echo "   - Ensure AWS permissions are sufficient"
    echo "   - Check AWS service limits (EKS, VPC, etc.)"
    echo "   - Verify CDK version compatibility"
    echo "   - Review CloudFormation events in AWS Console"
    exit 1
fi