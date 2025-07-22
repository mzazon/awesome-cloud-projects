# Infrastructure as Code for Implementing Document Analysis with Amazon Textract

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Document Analysis with Amazon Textract".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Textract (FullAccess)
  - AWS Lambda (basic execution and creation)
  - Amazon S3 (bucket creation and object operations)
  - Amazon DynamoDB (table creation and operations)
  - AWS Step Functions (state machine creation and execution)
  - Amazon SNS (topic creation and subscriptions)
  - IAM (role and policy management)
- Basic understanding of document processing and machine learning concepts
- Sample documents for testing (PDF, PNG, JPEG formats)
- Estimated cost: $10-15 for processing sample documents and infrastructure

## Architecture Overview

This solution implements intelligent document analysis using:

- **Amazon Textract**: ML-powered text, table, and form extraction
- **AWS Step Functions**: Workflow orchestration for sync/async processing
- **AWS Lambda**: Document classification and results processing
- **Amazon S3**: Input/output document storage
- **Amazon DynamoDB**: Document metadata and status tracking
- **Amazon SNS**: Processing notifications and completion alerts

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name textract-analysis-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=textract-demo

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name textract-analysis-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name textract-analysis-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform
```bash
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
aws stepfunctions list-state-machines \
    --query 'stateMachines[?contains(name, `textract`)].name'
```

## Testing the Solution

### Upload Test Documents
```bash
# Set your bucket name (from outputs)
INPUT_BUCKET="your-input-bucket-name"

# Upload a test document (triggers processing)
aws s3 cp sample-document.pdf s3://${INPUT_BUCKET}/documents/

# Monitor processing
aws dynamodb scan \
    --table-name your-metadata-table \
    --query 'Items[0]'
```

### Test Textract Directly
```bash
# Test synchronous processing
aws textract detect-document-text \
    --document '{"S3Object":{"Bucket":"'${INPUT_BUCKET}'","Name":"documents/sample-document.pdf"}}'

# Test with forms and tables
aws textract analyze-document \
    --document '{"S3Object":{"Bucket":"'${INPUT_BUCKET}'","Name":"documents/sample-document.pdf"}}' \
    --feature-types '["TABLES","FORMS"]'
```

### Monitor Step Functions
```bash
# List executions
aws stepfunctions list-executions \
    --state-machine-arn your-state-machine-arn

# Get execution details
aws stepfunctions describe-execution \
    --execution-arn your-execution-arn
```

## Configuration Options

### Environment Variables
- `PROJECT_NAME`: Unique identifier for resources (default: textract-analysis)
- `AWS_REGION`: Target AWS region for deployment
- `NOTIFICATION_EMAIL`: Email for SNS notifications (optional)

### Customizable Parameters
- **Document Processing Types**: Configure sync vs async thresholds
- **Textract Features**: Enable/disable TABLES, FORMS, QUERIES extraction
- **Storage Classes**: Adjust S3 storage classes for cost optimization
- **DynamoDB Capacity**: Modify read/write capacity based on volume
- **Lambda Timeout**: Adjust timeouts based on document complexity

## Cost Optimization

### Textract Pricing Considerations
- **Page-based billing**: Monitor document page counts
- **Feature-based pricing**: TABLES and FORMS cost more than text-only
- **Async vs Sync**: Async processing has different pricing tiers

### Resource Optimization
- Use S3 Intelligent Tiering for cost-effective storage
- Configure DynamoDB on-demand billing for variable workloads
- Set Lambda memory based on actual usage patterns
- Enable CloudWatch Logs retention policies

## Security Best Practices

### IAM Configuration
- All roles follow least-privilege principle
- Cross-service permissions are scoped to specific resources
- Temporary credentials used throughout the pipeline

### Data Protection
- S3 buckets configured with encryption at rest
- DynamoDB encryption enabled by default
- Lambda environment variables encrypted
- VPC endpoints for enhanced security (optional)

## Monitoring and Troubleshooting

### CloudWatch Metrics
- Monitor Textract API throttling and errors
- Track Step Functions execution success rates
- Monitor Lambda function duration and errors
- Set up alarms for processing failures

### Common Issues
- **Document format errors**: Ensure PDF/image format compatibility
- **Processing timeouts**: Adjust Lambda timeout for large documents
- **Permission errors**: Verify IAM role trust relationships
- **S3 event triggers**: Check bucket notification configuration

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name textract-analysis-stack

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name textract-analysis-stack
```

### Using CDK
```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining S3 objects
aws s3 rm s3://your-input-bucket --recursive
aws s3 rm s3://your-output-bucket --recursive

# Check for orphaned resources
aws lambda list-functions | grep textract
aws stepfunctions list-state-machines | grep textract
```

## Extension Ideas

### Advanced Processing
- Implement custom entity recognition with Amazon Comprehend
- Add document classification using machine learning models
- Integrate with Amazon Translate for multi-language support
- Build confidence scoring and human review workflows

### Integration Patterns
- Connect to business applications via API Gateway
- Implement event-driven processing with EventBridge
- Add batch processing capabilities for large document volumes
- Integrate with compliance and audit systems

### Performance Optimization
- Implement document preprocessing for better OCR accuracy
- Add caching layers for frequently accessed results
- Optimize Lambda function memory allocation
- Implement parallel processing for multi-page documents

## Support and Documentation

- [Amazon Textract Developer Guide](https://docs.aws.amazon.com/textract/latest/dg/what-is.html)
- [AWS Step Functions Documentation](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Recipe Documentation](../document-analysis-amazon-textract.md)

## Version Information

- **Recipe Version**: 1.2
- **AWS CLI**: v2.x required
- **CDK Version**: v2.x (latest stable)
- **Terraform**: v1.x with AWS Provider v5.x
- **Last Updated**: 2025-07-12

For issues with this infrastructure code, refer to the original recipe documentation or AWS service documentation.