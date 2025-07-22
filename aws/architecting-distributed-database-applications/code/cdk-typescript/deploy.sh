#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="MultiRegionDistributedApp"
PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"

echo -e "${GREEN}🚀 Starting deployment of Multi-Region Distributed Applications with Aurora DSQL${NC}"

# Check prerequisites
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI v2.${NC}"
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found. Please install Node.js 18+.${NC}"
    exit 1
fi

if ! command -v cdk &> /dev/null; then
    echo -e "${RED}❌ AWS CDK not found. Please install CDK: npm install -g aws-cdk${NC}"
    exit 1
fi

# Get AWS account and set environment variables
echo -e "${YELLOW}🔧 Setting up environment...${NC}"
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to get AWS account ID. Please check your AWS credentials.${NC}"
    exit 1
fi

echo "Using AWS Account: $CDK_DEFAULT_ACCOUNT"

# Install dependencies
echo -e "${YELLOW}📦 Installing dependencies...${NC}"
npm install

# Compile TypeScript
echo -e "${YELLOW}🔨 Compiling TypeScript...${NC}"
npm run build

# Synthesize CDK templates
echo -e "${YELLOW}🏗️  Synthesizing CDK templates...${NC}"
cdk synth

# Bootstrap regions if needed
echo -e "${YELLOW}🌱 Checking CDK bootstrap status...${NC}"

# Check if primary region is bootstrapped
if ! aws cloudformation describe-stacks --region $PRIMARY_REGION --stack-name CDKToolkit &>/dev/null; then
    echo -e "${YELLOW}📱 Bootstrapping primary region ($PRIMARY_REGION)...${NC}"
    cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$PRIMARY_REGION
else
    echo -e "${GREEN}✅ Primary region ($PRIMARY_REGION) already bootstrapped${NC}"
fi

# Check if secondary region is bootstrapped
if ! aws cloudformation describe-stacks --region $SECONDARY_REGION --stack-name CDKToolkit &>/dev/null; then
    echo -e "${YELLOW}📱 Bootstrapping secondary region ($SECONDARY_REGION)...${NC}"
    cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$SECONDARY_REGION
else
    echo -e "${GREEN}✅ Secondary region ($SECONDARY_REGION) already bootstrapped${NC}"
fi

# Deploy primary stack first
echo -e "${GREEN}🚀 Deploying primary region stack...${NC}"
cdk deploy $PROJECT_NAME-Primary --require-approval never

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Primary stack deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Primary stack deployed successfully${NC}"

# Deploy secondary stack
echo -e "${GREEN}🚀 Deploying secondary region stack...${NC}"
cdk deploy $PROJECT_NAME-Secondary --require-approval never

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Secondary stack deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Secondary stack deployed successfully${NC}"

# Display outputs
echo -e "${GREEN}📋 Deployment completed! Stack outputs:${NC}"

echo -e "\n${YELLOW}Primary Region (${PRIMARY_REGION}):${NC}"
aws cloudformation describe-stacks \
    --region $PRIMARY_REGION \
    --stack-name $PROJECT_NAME-Primary-Stack \
    --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' \
    --output table

echo -e "\n${YELLOW}Secondary Region (${SECONDARY_REGION}):${NC}"
aws cloudformation describe-stacks \
    --region $SECONDARY_REGION \
    --stack-name $PROJECT_NAME-Secondary-Stack \
    --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' \
    --output table

# Test deployment
echo -e "\n${GREEN}🧪 Running basic deployment test...${NC}"

# Get Lambda function names
PRIMARY_FUNCTION=$(aws cloudformation describe-stacks \
    --region $PRIMARY_REGION \
    --stack-name $PROJECT_NAME-Primary-Stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

SECONDARY_FUNCTION=$(aws cloudformation describe-stacks \
    --region $SECONDARY_REGION \
    --stack-name $PROJECT_NAME-Secondary-Stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test primary region function
echo -e "${YELLOW}Testing primary region Lambda function...${NC}"
aws lambda invoke \
    --region $PRIMARY_REGION \
    --function-name $PRIMARY_FUNCTION \
    --payload '{"operation":"read"}' \
    --cli-binary-format raw-in-base64-out \
    primary-test.json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Primary region test successful${NC}"
    echo "Response: $(cat primary-test.json)"
else
    echo -e "${RED}❌ Primary region test failed${NC}"
fi

# Test secondary region function
echo -e "${YELLOW}Testing secondary region Lambda function...${NC}"
aws lambda invoke \
    --region $SECONDARY_REGION \
    --function-name $SECONDARY_FUNCTION \
    --payload '{"operation":"read"}' \
    --cli-binary-format raw-in-base64-out \
    secondary-test.json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Secondary region test successful${NC}"
    echo "Response: $(cat secondary-test.json)"
else
    echo -e "${RED}❌ Secondary region test failed${NC}"
fi

# Cleanup test files
rm -f primary-test.json secondary-test.json

echo -e "\n${GREEN}🎉 Multi-region deployment completed successfully!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Test multi-region consistency by creating transactions in one region and reading from another"
echo "2. Monitor CloudWatch logs for both Lambda functions"
echo "3. Set up CloudWatch alarms for production monitoring"
echo "4. Configure additional EventBridge rules for your use cases"

echo -e "\n${YELLOW}Useful commands:${NC}"
echo "- View logs: aws logs tail /aws/lambda/$PRIMARY_FUNCTION --follow"
echo "- Test create: aws lambda invoke --region $PRIMARY_REGION --function-name $PRIMARY_FUNCTION --payload '{\"operation\":\"create\",\"amount\":100.50}' response.json"
echo "- Cleanup: ./destroy.sh"