# Infrastructure as Code for Document QA System with Bedrock and Kendra

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document QA System with Bedrock and Kendra".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent document question-answering system that combines:

- **Amazon Kendra**: ML-powered intelligent search for document indexing
- **AWS Bedrock**: Foundation models for natural language generation
- **Amazon S3**: Document storage and repository
- **AWS Lambda**: QA processing and orchestration
- **API Gateway**: REST endpoints for user interaction
- **IAM Roles**: Secure service-to-service communication

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Kendra (index creation and management)
  - AWS Bedrock (model access, specifically Claude models)
  - Amazon S3 (bucket creation and management)
  - AWS Lambda (function deployment)
  - API Gateway (REST API creation)
  - IAM (role and policy management)
- Access to Amazon Bedrock Claude models in your region
- Sample documents for testing (PDFs, Word docs, text files)
- Estimated cost: $50-200/month depending on usage and document volume

> **Note**: Amazon Kendra requires a paid tier for production use. Review [Kendra pricing](https://aws.amazon.com/kendra/pricing/) to understand costs.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name intelligent-qa-system \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=qa-system \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name intelligent-qa-system

# Get outputs
aws cloudformation describe-stacks \
    --stack-name intelligent-qa-system \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory and install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls --outputs
```

### Using CDK Python

```bash
# Navigate to CDK directory and setup environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls --outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create IAM roles for Kendra and Lambda
# 2. Deploy S3 bucket for documents
# 3. Create and configure Kendra index
# 4. Deploy Lambda function with QA processing logic
# 5. Set up API Gateway endpoints
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to:

1. **Upload sample documents** to the S3 bucket:
   ```bash
   # Get bucket name from outputs
   BUCKET_NAME=$(aws cloudformation describe-stacks \
       --stack-name intelligent-qa-system \
       --query 'Stacks[0].Outputs[?OutputKey==`DocumentsBucket`].OutputValue' \
       --output text)
   
   # Upload documents
   aws s3 cp your-document.pdf s3://${BUCKET_NAME}/documents/
   ```

2. **Trigger initial Kendra indexing**:
   ```bash
   # Get data source ID from outputs
   DATA_SOURCE_ID=$(aws cloudformation describe-stacks \
       --stack-name intelligent-qa-system \
       --query 'Stacks[0].Outputs[?OutputKey==`DataSourceId`].OutputValue' \
       --output text)
   
   INDEX_ID=$(aws cloudformation describe-stacks \
       --stack-name intelligent-qa-system \
       --query 'Stacks[0].Outputs[?OutputKey==`KendraIndexId`].OutputValue' \
       --output text)
   
   # Start synchronization
   aws kendra start-data-source-sync-job \
       --index-id $INDEX_ID \
       --id $DATA_SOURCE_ID
   ```

3. **Test the QA system**:
   ```bash
   # Get Lambda function name
   FUNCTION_NAME=$(aws cloudformation describe-stacks \
       --stack-name intelligent-qa-system \
       --query 'Stacks[0].Outputs[?OutputKey==`QAFunctionName`].OutputValue' \
       --output text)
   
   # Test with a question
   aws lambda invoke \
       --function-name $FUNCTION_NAME \
       --payload '{"question": "What topics are covered in the uploaded documents?"}' \
       response.json
   
   cat response.json
   ```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Prefix for all resource names (default: qa-system)
- `Environment`: Environment designation (default: dev)
- `KendraEdition`: Kendra index edition (default: DEVELOPER_EDITION)
- `DocumentBucketName`: Custom S3 bucket name (optional)

### CDK Configuration

Modify the following variables in the CDK applications:

- `project_name`: Project identifier for resource naming
- `environment`: Deployment environment
- `kendra_edition`: Kendra index configuration
- `lambda_timeout`: Function timeout in seconds

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `project_name`: Project identifier
- `aws_region`: AWS region for deployment
- `kendra_edition`: Kendra index edition
- `lambda_runtime`: Lambda runtime version
- `tags`: Resource tags for organization

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor the system using CloudWatch:

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/qa-processor

# View Kendra query metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Kendra \
    --metric-name IndexUtilization \
    --dimensions Name=IndexId,Value=$INDEX_ID \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average
```

### Common Issues

1. **Kendra Index Not Active**: Wait 30-45 minutes for index creation
2. **Bedrock Access Denied**: Ensure your region supports Bedrock and you have model access
3. **Lambda Timeout**: Increase timeout for complex queries
4. **Document Not Found**: Verify S3 bucket permissions and data source sync status

## Security Considerations

The deployed infrastructure follows AWS security best practices:

- **IAM Roles**: Least privilege access for all services
- **Encryption**: S3 bucket encryption enabled by default
- **VPC**: Optional VPC deployment for enhanced network security
- **Access Logging**: CloudTrail integration for audit logging

## Cost Optimization

To optimize costs:

1. **Kendra Edition**: Use DEVELOPER_EDITION for testing ($810/month vs $1008/month for ENTERPRISE)
2. **Lambda Provisioned Concurrency**: Only enable for high-traffic scenarios
3. **S3 Storage Classes**: Use appropriate storage classes for different document types
4. **Bedrock Models**: Monitor token usage and choose cost-effective models

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name intelligent-qa-system

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name intelligent-qa-system
```

### Using CDK

```bash
# From the CDK directory
cdk destroy --force

# Confirm destruction when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Adding Custom Document Types

Modify the Kendra data source configuration to support additional file types:

```json
{
  "S3Configuration": {
    "DocumentsMetadataConfiguration": {
      "S3Prefix": "metadata/"
    },
    "InclusionPatterns": ["*.pdf", "*.docx", "*.txt", "*.html"]
  }
}
```

### Integrating Additional AI Models

Update the Lambda function to use different Bedrock models:

```python
# In the Lambda function code
bedrock_response = bedrock.invoke_model(
    modelId='anthropic.claude-3-haiku-20240307-v1:0',  # Faster, lower cost
    # or
    modelId='anthropic.claude-3-opus-20240229-v1:0',   # Higher capability
    body=json.dumps({
        'anthropic_version': 'bedrock-2023-05-31',
        'max_tokens': 1000,
        'messages': [{'role': 'user', 'content': prompt}]
    })
)
```

### Adding Web Interface

Deploy a frontend application using:

- **Amazon CloudFront**: Content delivery
- **Amazon S3**: Static website hosting
- **AWS Amplify**: Full-stack web application framework

## Performance Tuning

### Kendra Optimization

- **Document Metadata**: Add rich metadata for better search relevance
- **Custom Synonyms**: Configure domain-specific synonyms
- **User Context**: Implement user-based query filtering

### Lambda Optimization

- **Memory Allocation**: Increase memory for faster processing
- **Provisioned Concurrency**: Enable for consistent performance
- **Connection Pooling**: Reuse service connections

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for specific services
3. Monitor CloudWatch logs for error details
4. Verify IAM permissions and service quotas

## Additional Resources

- [Amazon Kendra Developer Guide](https://docs.aws.amazon.com/kendra/)
- [AWS Bedrock User Guide](https://docs.aws.amazon.com/bedrock/)
- [CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)