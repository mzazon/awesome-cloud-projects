# Infrastructure as Code for Document Processing Pipelines with Textract

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document Processing Pipelines with Textract".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated document processing pipeline that:

- Automatically processes documents uploaded to S3 using Amazon Textract
- Orchestrates the workflow using AWS Step Functions
- Uses Lambda functions for document processing and result handling
- Provides monitoring and logging through CloudWatch
- Stores processed results in structured format for downstream analytics

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 (bucket creation, object read/write)
  - Lambda (function creation, execution)
  - Step Functions (state machine creation, execution)
  - IAM (role and policy creation)
  - Amazon Textract (document analysis)
  - CloudWatch (logs and monitoring)
- For CDK deployments: Node.js 18+ or Python 3.8+
- For Terraform deployments: Terraform 1.5+ installed

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name document-processing-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-doc-pipeline

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name document-processing-pipeline \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name document-processing-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk outputs
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
terraform apply

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
# 1. Create S3 buckets for input, output, and archive
# 2. Create IAM roles and policies
# 3. Deploy Lambda functions
# 4. Create Step Functions state machine
# 5. Configure S3 event notifications
# 6. Set up CloudWatch monitoring
```

## Testing Your Deployment

After deployment, test the document processing pipeline:

1. **Upload a test document**:
   ```bash
   # Create a test document
   echo "Test Invoice
   ACME Corp
   Invoice #: 12345
   Amount: $1,000.00" > test-document.txt
   
   # Upload to input bucket (replace with your actual bucket name)
   aws s3 cp test-document.txt s3://your-input-bucket/test-document.pdf
   ```

2. **Monitor processing**:
   ```bash
   # Check Step Functions executions
   aws stepfunctions list-executions \
       --state-machine-arn your-state-machine-arn
   
   # Check processed results
   aws s3 ls s3://your-output-bucket/processed/
   ```

3. **View results**:
   ```bash
   # Download processed results
   aws s3 cp s3://your-output-bucket/processed/test-document_results.json ./
   
   # View extracted data
   cat test-document_results.json | jq '.extractedData'
   ```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| ProjectName | Unique identifier for resources | textract-pipeline |
| Environment | Environment tag (dev/staging/prod) | dev |
| LogRetentionDays | CloudWatch log retention period | 14 |
| EnableArchiving | Enable document archiving | true |

### CDK Configuration

Modify the configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript configuration
const config = {
  projectName: 'my-doc-pipeline',
  environment: 'dev',
  logRetentionDays: 14,
  enableArchiving: true
};
```

### Terraform Variables

Configure variables in `terraform.tfvars`:

```hcl
project_name = "my-doc-pipeline"
environment = "dev"
log_retention_days = 14
enable_archiving = true
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **CloudWatch Dashboards**: Visual monitoring of pipeline metrics
- **Lambda Logs**: Detailed execution logs for troubleshooting
- **Step Functions Logs**: Workflow execution tracking
- **S3 Metrics**: Object storage and access patterns
- **Textract Metrics**: Document processing statistics

### Access CloudWatch Dashboard

```bash
# Get dashboard URL from stack outputs
aws cloudformation describe-stacks \
    --stack-name document-processing-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
    --output text
```

## Cost Optimization

To optimize costs:

1. **Set appropriate log retention**: Reduce CloudWatch log retention period
2. **Configure S3 lifecycle policies**: Automatically transition old documents to cheaper storage classes
3. **Monitor Textract usage**: Track page processing costs
4. **Use reserved capacity**: For predictable workloads, consider reserved Lambda capacity

## Security Best Practices

The deployment implements security best practices:

- **Least privilege IAM**: Minimal required permissions for each service
- **Encryption**: S3 buckets and Lambda environment variables encrypted
- **VPC isolation**: Optional VPC deployment for enhanced security
- **Access logging**: Comprehensive audit trail
- **Resource tagging**: Consistent tagging for governance

## Troubleshooting

### Common Issues

1. **Permission errors**: Verify IAM roles have correct policies attached
2. **Textract limits**: Check service quotas and request increases if needed
3. **Lambda timeouts**: Increase timeout values for large documents
4. **S3 event conflicts**: Ensure no conflicting bucket notifications

### Debugging Steps

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/your-function-name --follow

# Check Step Functions execution details
aws stepfunctions describe-execution \
    --execution-arn your-execution-arn

# Verify S3 event configuration
aws s3api get-bucket-notification-configuration \
    --bucket your-input-bucket
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name document-processing-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name document-processing-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy  # or cdk destroy for Python
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Empty and delete S3 buckets
# 2. Delete Step Functions state machine
# 3. Delete Lambda functions
# 4. Remove IAM roles and policies
# 5. Delete CloudWatch resources
```

## Customization

### Adding New Document Types

To support additional document types:

1. Modify Lambda function code to handle new file extensions
2. Update Textract feature types for specific document requirements
3. Adjust result processing logic for document-specific data structures

### Extending Processing Logic

To add custom processing:

1. Create additional Lambda functions for specialized processing
2. Update Step Functions state machine to include new states
3. Modify IAM policies to include new permissions

### Integration with Other Services

Common integrations:

- **Amazon Comprehend**: For sentiment analysis and entity extraction
- **Amazon Translate**: For multi-language document processing
- **Amazon QuickSight**: For business intelligence dashboards
- **Amazon SNS**: For real-time notifications
- **Amazon DynamoDB**: For metadata storage

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Consult CloudFormation/CDK/Terraform documentation
4. Check AWS service limits and quotas

## Additional Resources

- [Amazon Textract Developer Guide](https://docs.aws.amazon.com/textract/latest/dg/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)