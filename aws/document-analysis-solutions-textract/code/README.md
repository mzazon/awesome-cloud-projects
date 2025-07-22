# Infrastructure as Code for Creating Document Analysis Solutions with Textract

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Creating Document Analysis Solutions with Textract".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Textract operations
  - S3 bucket creation and management
  - Lambda function deployment
  - SNS topic creation
  - IAM role and policy management
  - CloudWatch logs access
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

## Architecture Overview

This solution creates an intelligent document processing pipeline that automatically extracts text, forms, and tables from documents using Amazon Textract. The architecture includes:

- **S3 Input Bucket**: Receives uploaded documents for processing
- **Lambda Function**: Orchestrates Textract analysis and result processing
- **Amazon Textract**: Performs ML-powered document analysis
- **S3 Output Bucket**: Stores processed results in JSON format
- **SNS Topic**: Sends processing notifications
- **CloudWatch Logs**: Monitors processing activities

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name textract-document-analysis \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=textract-demo

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name textract-document-analysis \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
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

# Check deployment status
aws s3 ls | grep textract
aws lambda list-functions --query 'Functions[?contains(FunctionName, `textract`)]'
```

## Testing the Solution

After deployment, test the document processing pipeline:

1. **Upload a test document**:
   ```bash
   # Get the input bucket name from outputs
   INPUT_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name textract-document-analysis \
       --query 'Stacks[0].Outputs[?OutputKey==`InputBucketName`].OutputValue' \
       --output text)
   
   # Upload a PDF document
   aws s3 cp your-document.pdf s3://${INPUT_BUCKET}/test-documents/
   ```

2. **Monitor processing**:
   ```bash
   # Check Lambda logs
   aws logs tail /aws/lambda/textract-processor --follow
   
   # Check output bucket
   OUTPUT_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name textract-document-analysis \
       --query 'Stacks[0].Outputs[?OutputKey==`OutputBucketName`].OutputValue' \
       --output text)
   
   aws s3 ls s3://${OUTPUT_BUCKET}/processed/
   ```

3. **View results**:
   ```bash
   # Download processed results
   aws s3 cp s3://${OUTPUT_BUCKET}/processed/your-document.pdf.json ./
   
   # View extracted data
   cat your-document.pdf.json | jq '.blocks[] | select(.BlockType=="LINE") | .Text'
   ```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Name prefix for all resources (default: textract-analysis)
- `Environment`: Environment tag (default: development)
- `NotificationEmail`: Email address for SNS notifications (optional)

### CDK Configuration

Modify the following variables in the CDK code:

- `project_name`: Resource naming prefix
- `environment`: Deployment environment
- `lambda_timeout`: Lambda function timeout (default: 300 seconds)
- `lambda_memory`: Lambda memory allocation (default: 512 MB)

### Terraform Variables

Configure these variables in `terraform/variables.tf`:

- `project_name`: Project name for resource naming
- `environment`: Environment identifier
- `aws_region`: AWS region for deployment
- `lambda_timeout`: Function timeout in seconds
- `lambda_memory_size`: Memory allocation in MB

## Customization

### Adding Document Types

To support additional document formats, modify the S3 event trigger:

```yaml
# CloudFormation example
Filter:
  Key:
    FilterRules:
      - Name: suffix
        Value: .pdf
      - Name: suffix
        Value: .png
      - Name: suffix
        Value: .jpg
```

### Enhanced Processing

Add custom processing logic by modifying the Lambda function:

```python
# Add custom extraction logic
def extract_custom_fields(blocks):
    # Your custom extraction logic here
    return extracted_fields

# Enhanced query configuration
queries = [
    {'Text': 'What is the document type?'},
    {'Text': 'What is the total amount?'},
    {'Text': 'What is the invoice number?'},
    {'Text': 'What is the due date?'}
]
```

### Notification Configuration

Configure SNS notifications for different processing outcomes:

```python
# Success notification
sns.publish(
    TopicArn=os.environ['SNS_TOPIC_ARN'],
    Message=f"Document processed successfully: {document_name}",
    Subject='Textract Processing Complete'
)

# Error notification with details
sns.publish(
    TopicArn=os.environ['SNS_TOPIC_ARN'],
    Message=f"Processing failed: {error_details}",
    Subject='Textract Processing Error'
)
```

## Monitoring and Observability

### CloudWatch Metrics

Monitor key metrics:

- Lambda function duration and error rates
- S3 bucket object counts and sizes
- Textract API call volumes and success rates
- SNS message delivery status

### CloudWatch Alarms

Set up alarms for:

```bash
# Lambda error rate alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "TextractProcessingErrors" \
    --alarm-description "High error rate in Textract processing" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold
```

### Log Analysis

Query CloudWatch Logs Insights:

```sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

## Security Considerations

### IAM Permissions

The solution follows the principle of least privilege:

- Lambda execution role has minimal required permissions
- S3 bucket policies restrict access to specific operations
- Textract access is limited to document analysis operations

### Data Security

- All S3 buckets can be configured with encryption at rest
- Documents are processed without persistent storage in Lambda
- SNS topics support encryption in transit

### Network Security

For enhanced security, consider:

- VPC deployment for Lambda functions
- S3 bucket policies with IP restrictions
- Private endpoints for AWS services

## Cost Optimization

### Pricing Considerations

- **Amazon Textract**: $0.0015 per page for text detection, $0.015-0.05 per page for forms/tables
- **Lambda**: Pay per execution and compute time
- **S3**: Storage costs for input/output documents
- **SNS**: Minimal notification costs

### Optimization Strategies

1. **Batch Processing**: Process multiple documents in single Lambda invocation
2. **Lifecycle Policies**: Automatically archive processed documents
3. **Reserved Capacity**: Consider reserved capacity for high-volume processing
4. **Monitoring**: Track processing costs with AWS Cost Explorer

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name textract-document-analysis

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name textract-document-analysis \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
aws s3 ls | grep textract
aws lambda list-functions --query 'Functions[?contains(FunctionName, `textract`)]'
```

### Manual Cleanup

If automated cleanup fails, manually remove:

```bash
# Delete S3 buckets (empty first)
aws s3 rm s3://textract-input-bucket --recursive
aws s3 rb s3://textract-input-bucket

aws s3 rm s3://textract-output-bucket --recursive
aws s3 rb s3://textract-output-bucket

# Delete Lambda function
aws lambda delete-function --function-name textract-processor

# Delete SNS topic
aws sns delete-topic --topic-arn arn:aws:sns:region:account:topic-name

# Delete IAM role
aws iam delete-role --role-name textract-lambda-role
```

## Troubleshooting

### Common Issues

1. **Lambda timeout errors**: Increase timeout and memory allocation
2. **Textract API limits**: Implement exponential backoff and retry logic
3. **S3 permissions**: Verify bucket policies and IAM permissions
4. **Large document processing**: Consider asynchronous Textract operations

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/textract

# Test S3 event trigger
aws s3api head-bucket-notification-configuration --bucket your-input-bucket

# Verify IAM permissions
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::account:role/textract-lambda-role \
    --action-names textract:AnalyzeDocument \
    --resource-arns "*"
```

## Performance Optimization

### Lambda Configuration

- **Memory**: 512MB minimum for document processing
- **Timeout**: 300 seconds for large documents
- **Concurrency**: Set reserved concurrency for predictable performance

### Processing Optimization

- Implement parallel processing for multi-page documents
- Use Textract's asynchronous APIs for large documents
- Cache processed results to avoid reprocessing

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../document-analysis-solutions-amazon-textract.md)
- [Amazon Textract documentation](https://docs.aws.amazon.com/textract/)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
- [AWS S3 documentation](https://docs.aws.amazon.com/s3/)

## Contributing

When modifying this infrastructure:

1. Test all changes in a development environment
2. Update relevant documentation
3. Ensure security best practices are maintained
4. Validate against AWS Well-Architected Framework principles