# Infrastructure as Code for Knowledge Management Assistant with Bedrock Agents

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Knowledge Management Assistant with Bedrock Agents".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript (v2.38.0+)
- **CDK Python**: AWS Cloud Development Kit with Python (v2.38.0+)
- **Terraform**: Multi-cloud infrastructure as code using AWS provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent knowledge management assistant using:

- **Amazon Bedrock Agents** with Claude 3.5 Sonnet for conversational AI
- **Amazon Bedrock Knowledge Bases** with Titan Text Embeddings V2 for RAG
- **OpenSearch Serverless** for scalable vector storage
- **S3** for secure document storage with versioning and encryption
- **Lambda** for API integration with enhanced error handling
- **API Gateway** for REST endpoints with CORS and logging
- **IAM roles** following least privilege principles

## Prerequisites

### General Requirements
- AWS account with Amazon Bedrock access and model permissions
- AWS CLI installed and configured (version 2.x or later)
- Appropriate IAM permissions for resource creation and management
- Enable access to Claude 3.5 Sonnet and Amazon Titan models in your AWS region

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.x or AWS Console access
- CloudFormation service permissions

#### CDK TypeScript
- Node.js 14.15.0 or higher
- npm or yarn package manager
- AWS CDK CLI v2.38.0 or higher

```bash
npm install -g aws-cdk@latest
```

#### CDK Python
- Python 3.8 or higher
- pip package manager
- AWS CDK CLI v2.38.0 or higher

```bash
pip install aws-cdk-lib>=2.38.0
```

#### Terraform
- Terraform v1.0 or higher
- AWS provider v5.0 or higher

```bash
# Install Terraform (macOS with Homebrew)
brew install terraform

# Verify installation
terraform version
```

### Cost Estimates
- **Testing Environment**: $5-15 per session depending on document volume and query frequency
- **Production Environment**: $50-200+ per month based on usage patterns
- **Key cost factors**: Bedrock model invocations, OpenSearch Serverless storage, Lambda executions

> **Note**: Amazon Bedrock charges per token for model usage. Monitor your usage through AWS Cost Explorer and set up billing alerts.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name knowledge-assistant-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketPrefix,ParameterValue=my-knowledge-docs

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name knowledge-assistant-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint after deployment
aws cloudformation describe-stacks \
    --stack-name knowledge-assistant-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy with confirmation prompts
cdk deploy --require-approval never

# Deploy with custom parameters
cdk deploy \
    --parameters bucketPrefix=my-company-docs \
    --parameters enableDetailedMonitoring=true

# View outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy

# Deploy with custom context
cdk deploy --context bucketPrefix=enterprise-knowledge
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply with auto-approval
terraform apply -auto-approve

# Apply with custom variables
terraform apply \
    -var="bucket_prefix=company-docs" \
    -var="enable_detailed_logging=true"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy with default settings
./scripts/deploy.sh

# Deploy with custom prefix
BUCKET_PREFIX=my-docs ./scripts/deploy.sh

# Deploy in specific region
AWS_REGION=us-west-2 ./scripts/deploy.sh
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

- `AWS_REGION`: Target AWS region (default: us-east-1)
- `BUCKET_PREFIX`: Prefix for S3 bucket names (default: knowledge-docs)
- `AGENT_NAME`: Custom name for Bedrock agent (default: knowledge-assistant)
- `ENABLE_DETAILED_LOGGING`: Enable detailed CloudWatch logging (default: false)

### Parameters

#### CloudFormation Parameters
- `BucketPrefix`: Prefix for S3 bucket (default: knowledge-docs)
- `ModelId`: Bedrock model ID (default: anthropic.claude-3-5-sonnet-20241022-v2:0)
- `EnableXRayTracing`: Enable X-Ray tracing (default: false)

#### CDK Context Variables
- `bucketPrefix`: S3 bucket prefix
- `enableDetailedMonitoring`: Enhanced monitoring
- `retentionDays`: CloudWatch log retention (default: 30 days)

#### Terraform Variables
- `bucket_prefix`: S3 bucket prefix
- `model_id`: Bedrock foundation model
- `enable_detailed_logging`: CloudWatch detailed logging
- `tags`: Resource tags (map)

## Testing the Deployment

After deployment, test your knowledge management assistant:

```bash
# Get the API endpoint (replace with your actual endpoint)
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Test with a sample query
curl -X POST ${API_ENDPOINT}/query \
    -H "Content-Type: application/json" \
    -d '{
      "query": "What are the company policies?",
      "sessionId": "test-session"
    }' | jq .

# Upload sample documents to test with
aws s3 cp sample-document.txt s3://your-bucket-name/documents/
```

## Monitoring and Observability

### CloudWatch Metrics
- Lambda function duration and errors
- API Gateway request count and latency
- Bedrock model invocation metrics

### Logging
- Lambda function logs: `/aws/lambda/bedrock-agent-proxy-*`
- API Gateway access logs: `/aws/apigateway/knowledge-management-api-*`
- Bedrock agent execution traces (when enabled)

### Alarms
The infrastructure includes basic CloudWatch alarms for:
- Lambda function errors
- API Gateway 4xx/5xx error rates
- Bedrock throttling

## Security Considerations

### IAM Permissions
- Bedrock agents use least privilege IAM roles
- Lambda functions have minimal required permissions
- S3 buckets use server-side encryption
- API Gateway supports CORS for web applications

### Data Protection
- Documents stored in S3 with AES-256 encryption
- Vector embeddings stored in OpenSearch Serverless with encryption
- API communications use HTTPS/TLS
- No credentials stored in Lambda environment variables

### Access Control
- API Gateway can be integrated with AWS Cognito for authentication
- Consider implementing API keys for production use
- VPC endpoints available for private network access

## Customization

### Adding New Document Types
1. Update S3 bucket policies for new file types
2. Configure custom chunking strategies in Knowledge Base
3. Add file type validation in Lambda function

### Enhancing the Agent
1. Add action groups for external API integration
2. Implement custom prompts for domain-specific responses
3. Configure memory retention for conversation context

### Scaling for Production
1. Enable API Gateway caching
2. Implement CloudFront for global distribution
3. Add DynamoDB for session management
4. Configure auto-scaling for Lambda concurrency

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name knowledge-assistant-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name knowledge-assistant-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)
```bash
# Destroy all resources
cdk destroy

# Destroy specific stack
cdk destroy KnowledgeManagementAssistantStack

# Force destruction without confirmation
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Destroy with auto-approval
terraform destroy -auto-approve

# Destroy specific resources
terraform destroy -target=aws_s3_bucket.documents
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Cleanup with confirmation prompts disabled
SKIP_CONFIRMATION=true ./scripts/destroy.sh
```

### Manual Cleanup Verification

After running cleanup, verify these resources are removed:
- S3 buckets and objects
- OpenSearch Serverless collections
- Bedrock agents and knowledge bases
- Lambda functions
- API Gateway REST APIs
- IAM roles and policies
- CloudWatch log groups

## Troubleshooting

### Common Issues

#### Bedrock Model Access
```bash
# Check model access in your region
aws bedrock list-foundation-models --region us-east-1

# Request model access if needed
# Visit AWS Console > Bedrock > Model access
```

#### Knowledge Base Ingestion Failures
```bash
# Check ingestion job status
aws bedrock-agent list-ingestion-jobs \
    --knowledge-base-id YOUR_KB_ID \
    --data-source-id YOUR_DATA_SOURCE_ID

# Check S3 bucket permissions
aws s3api get-bucket-policy --bucket YOUR_BUCKET_NAME
```

#### API Gateway CORS Issues
- Verify OPTIONS method is configured
- Check Access-Control-Allow-* headers
- Test with browser developer tools

#### Lambda Timeout Issues
- Increase Lambda timeout (default: 30 seconds)
- Monitor CloudWatch metrics for duration
- Consider implementing async processing for large documents

### Getting Help

- **AWS Documentation**: [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/)
- **CDK Documentation**: [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- **Terraform AWS Provider**: [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest)
- **CloudFormation**: [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)

### Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Examine CloudWatch logs for detailed error messages
4. Refer to the original recipe documentation for architecture guidance

## License

This infrastructure code is provided as-is for educational and reference purposes. Ensure compliance with your organization's security and governance requirements before deploying in production environments.