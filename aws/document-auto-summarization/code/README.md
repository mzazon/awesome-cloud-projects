# Infrastructure as Code for Document Auto-Summarization with Bedrock

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document Auto-Summarization with Bedrock".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - Lambda function deployment
  - IAM role and policy management
  - Amazon Bedrock model access
  - Amazon Textract permissions
  - CloudWatch Logs access
- Access to Amazon Bedrock Claude models in your region
- Basic understanding of serverless architecture

> **Note**: Ensure you have enabled Amazon Bedrock models in your AWS region before deployment. Some regions may require model access requests.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name intelligent-doc-summarization \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name intelligent-doc-summarization \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name intelligent-doc-summarization \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK directory and install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK directory and set up environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws s3 ls | grep document
aws lambda list-functions --query 'Functions[?contains(FunctionName, `doc-summarizer`)]'
```

## Testing the Deployment

After successful deployment, test the document summarization system:

```bash
# Get the input bucket name from outputs
INPUT_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name intelligent-doc-summarization \
    --query 'Stacks[0].Outputs[?OutputKey==`InputBucketName`].OutputValue' \
    --output text)

# Create a test document
cat > test-document.txt << 'EOF'
QUARTERLY BUSINESS REPORT

Executive Summary:
Our company achieved strong performance in Q3 2024 with revenue growth of 15% 
year-over-year, reaching $2.3 million. Key highlights include successful 
product launches, improved customer satisfaction scores, and operational 
efficiency gains.

Key Metrics:
- Revenue: $2.3M (15% increase)
- Customer satisfaction: 94% (up from 89%)
- Market share: 12.5% in target segment
- Employee retention: 96%

Strategic Initiatives:
1. Digital transformation project completed ahead of schedule
2. New product line launched in European markets
3. Partnership established with key industry leader
4. Sustainability program implementation started

Recommendations:
- Increase marketing spend for Q4 holiday season
- Expand customer service team capacity
- Explore opportunities in Asian markets
- Continue focus on operational excellence
EOF

# Upload test document to trigger processing
aws s3 cp test-document.txt s3://${INPUT_BUCKET}/documents/

# Wait for processing and check results
sleep 60
OUTPUT_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name intelligent-doc-summarization \
    --query 'Stacks[0].Outputs[?OutputKey==`OutputBucketName`].OutputValue' \
    --output text)

aws s3 ls s3://${OUTPUT_BUCKET}/summaries/
```

## Customization

### Environment Variables

Customize the deployment by modifying these parameters in the IaC templates:

- **Environment**: Deployment environment (dev, staging, prod)
- **LambdaTimeout**: Function timeout in seconds (default: 300)
- **LambdaMemory**: Function memory allocation in MB (default: 512)
- **BedrockModel**: Bedrock model ID (default: anthropic.claude-3-sonnet-20240229-v1:0)
- **DocumentPrefix**: S3 prefix for input documents (default: documents/)

### Security Configuration

The default deployment includes:

- Least privilege IAM policies
- S3 bucket encryption at rest
- VPC endpoints for secure service communication (optional)
- CloudWatch logging for monitoring and debugging

### Cost Optimization

Monitor and optimize costs by:

- Setting up CloudWatch billing alerts
- Implementing S3 lifecycle policies for document retention
- Using Lambda reserved concurrency to control scaling
- Monitoring Bedrock usage and implementing rate limiting

## Architecture Overview

The deployed infrastructure includes:

- **S3 Input Bucket**: Receives uploaded documents with event notifications
- **S3 Output Bucket**: Stores generated summaries and metadata
- **Lambda Function**: Orchestrates text extraction and summarization
- **IAM Roles**: Secure access permissions following least privilege
- **CloudWatch Logs**: Monitoring and debugging capabilities
- **Event Triggers**: Automatic processing upon document upload

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/doc-summarizer"

# Tail recent logs
aws logs tail /aws/lambda/doc-summarizer-* --follow
```

### Metrics Monitoring

```bash
# Check Lambda invocation metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=doc-summarizer-* \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum
```

### Common Issues

1. **Bedrock Access Denied**: Ensure model access is enabled in your region
2. **Lambda Timeout**: Increase timeout for large documents
3. **Textract Limits**: Implement retry logic for rate limiting
4. **Cost Concerns**: Monitor usage and implement appropriate limits

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty S3 buckets first (CloudFormation can't delete non-empty buckets)
aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name intelligent-doc-summarization \
    --query 'Stacks[0].Outputs[?OutputKey==`InputBucketName`].OutputValue' \
    --output text) --recursive

aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name intelligent-doc-summarization \
    --query 'Stacks[0].Outputs[?OutputKey==`OutputBucketName`].OutputValue' \
    --output text) --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name intelligent-doc-summarization

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name intelligent-doc-summarization \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

- IAM policies follow least privilege principles
- S3 buckets are configured with encryption and versioning
- Lambda functions run with minimal required permissions
- CloudWatch logging is enabled for audit trails
- Network security through VPC configuration (when enabled)

## Performance Optimization

- Lambda memory allocation optimized for document processing
- S3 event filtering to reduce unnecessary invocations
- Textract batch processing for multiple documents
- Bedrock model selection based on accuracy vs. cost requirements

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../intelligent-document-summarization-with-bedrock-lambda.md)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
- [Amazon Bedrock documentation](https://docs.aws.amazon.com/bedrock/)
- [Amazon Textract documentation](https://docs.aws.amazon.com/textract/)
- [AWS CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)

## Cost Estimation

Estimated monthly costs for moderate usage (100 documents/month):

- **Lambda**: $5-15 (based on execution time and memory)
- **S3 Storage**: $1-5 (based on document storage)
- **Textract**: $10-30 (based on document pages processed)
- **Bedrock**: $20-60 (based on text length and model usage)
- **Total**: $36-110/month

> **Warning**: Costs can vary significantly based on document volume, size, and processing frequency. Monitor usage and set up billing alerts.