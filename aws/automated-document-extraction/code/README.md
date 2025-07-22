# Infrastructure as Code for Automated Document Extraction with Textract

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Document Extraction with Textract".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for S3, Lambda, Textract, and IAM services
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Sample documents (PDFs, images) for testing

### Required AWS Permissions

Your AWS user/role needs the following permissions:
- `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutObject`, `s3:GetObject`
- `lambda:CreateFunction`, `lambda:DeleteFunction`, `lambda:InvokeFunction`
- `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`
- `textract:DetectDocumentText`, `textract:AnalyzeDocument`
- `logs:CreateLogGroup`, `logs:DescribeLogGroups`

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name textract-document-processing \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketSuffix,ParameterValue=$(date +%s)

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name textract-document-processing

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name textract-document-processing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file (optional)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred values

# Plan deployment
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

# Follow the prompts and wait for deployment completion
```

## Testing the Deployment

Once deployed, test your document processing pipeline:

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name textract-document-processing \
    --query 'Stacks[0].Outputs[?OutputKey==`DocumentBucket`].OutputValue' \
    --output text)

# Upload a test document
echo "This is a sample document for testing Amazon Textract." > test-document.txt
aws s3 cp test-document.txt s3://${BUCKET_NAME}/documents/

# Wait for processing (about 30 seconds)
sleep 30

# Check results
aws s3 ls s3://${BUCKET_NAME}/results/
aws s3 cp s3://${BUCKET_NAME}/results/test-document.txt_results.json ./
cat test-document.txt_results.json
```

## Architecture Overview

The deployed infrastructure includes:

- **S3 Bucket**: Stores input documents and processing results
- **Lambda Function**: Orchestrates Textract analysis and result storage
- **IAM Role**: Provides secure access to AWS services
- **S3 Event Notification**: Triggers processing when documents are uploaded
- **CloudWatch Logs**: Captures function execution logs for monitoring

## Configuration Options

### CloudFormation Parameters

- `BucketSuffix`: Unique suffix for S3 bucket name
- `LambdaTimeout`: Function timeout in seconds (default: 60)
- `LambdaMemorySize`: Function memory allocation (default: 256)

### CDK Configuration

Edit the stack configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const stack = new TextractStack(app, 'TextractStack', {
  timeout: Duration.seconds(60),
  memorySize: 256,
  env: { region: 'us-east-1' }
});
```

### Terraform Variables

Available variables in `variables.tf`:

- `aws_region`: AWS region for deployment
- `bucket_name_suffix`: Unique suffix for bucket naming
- `lambda_timeout`: Function timeout (seconds)
- `lambda_memory_size`: Function memory (MB)
- `lambda_runtime`: Python runtime version

## Monitoring and Troubleshooting

### CloudWatch Logs

View Lambda function logs:

```bash
# Get log group name
LOG_GROUP="/aws/lambda/$(aws cloudformation describe-stacks \
    --stack-name textract-document-processing \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunction`].OutputValue' \
    --output text)"

# View recent logs
aws logs filter-log-events --log-group-name "$LOG_GROUP" --start-time $(date -d '1 hour ago' +%s000)
```

### Common Issues

1. **Permission Errors**: Ensure IAM role has required Textract and S3 permissions
2. **Timeout Issues**: Increase Lambda timeout for large documents
3. **Unsupported Formats**: Textract supports PDF, PNG, JPEG, and TIFF formats
4. **Memory Errors**: Increase Lambda memory size for complex documents

## Cleanup

### Using CloudFormation

```bash
# Empty S3 bucket first
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name textract-document-processing \
    --query 'Stacks[0].Outputs[?OutputKey==`DocumentBucket`].OutputValue' \
    --output text)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete stack
aws cloudformation delete-stack --stack-name textract-document-processing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name textract-document-processing
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy  # or 'cdk destroy' for Python

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow the prompts for confirmation
```

## Cost Considerations

This solution uses several AWS services with associated costs:

- **S3**: Storage costs for documents and results ($0.023 per GB/month)
- **Lambda**: Compute costs based on execution time and memory
- **Textract**: Pay-per-page processing ($0.0015 per page for DetectDocumentText)
- **CloudWatch Logs**: Log storage and retention costs

For development/testing, estimated costs are $5-10 per month with moderate usage.

## Security Best Practices

The infrastructure implements several security measures:

- **IAM Least Privilege**: Lambda role has minimal required permissions
- **S3 Bucket Policies**: Restrict access to specific prefixes
- **Encryption**: S3 server-side encryption enabled by default
- **VPC Isolation**: Can be enhanced with VPC deployment for Lambda

## Advanced Configuration

### Processing Different Document Types

The Lambda function can be enhanced to handle different document types:

```python
# Example: Add table extraction for forms
response = textract_client.analyze_document(
    Document={'S3Object': {'Bucket': bucket, 'Name': key}},
    FeatureTypes=['TABLES', 'FORMS']
)
```

### Batch Processing

For high-volume scenarios, consider:

- Using Textract's asynchronous APIs
- Implementing SQS for batch processing
- Adding Step Functions for workflow orchestration

### Multi-Region Deployment

Deploy across multiple regions for:

- Reduced latency for global users
- Disaster recovery capabilities
- Compliance with data residency requirements

## Integration Examples

### API Gateway Integration

Connect to API Gateway for REST API access:

```bash
# Create API Gateway integration (example)
aws apigateway create-rest-api --name textract-api
```

### EventBridge Integration

Route processing events to other systems:

```python
# Send events to EventBridge
eventbridge.put_events(
    Entries=[{
        'Source': 'textract.processing',
        'DetailType': 'Document Processed',
        'Detail': json.dumps(results)
    }]
)
```

## Support and Documentation

- [Amazon Textract Documentation](https://docs.aws.amazon.com/textract/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Original Recipe Documentation](../intelligent-document-processing-amazon-textract.md)
- [AWS CDK Reference](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.