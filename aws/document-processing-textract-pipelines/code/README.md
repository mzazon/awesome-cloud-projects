# Infrastructure as Code for Building Document Processing Pipelines with Amazon Textract and Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Document Processing Pipelines with Amazon Textract and Step Functions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- AWS account with administrator access or permissions for:
  - Amazon S3 (create/delete buckets, objects)
  - Amazon Textract (analyze documents, detect text)
  - AWS Step Functions (create/manage state machines)
  - AWS Lambda (create/manage functions)
  - Amazon DynamoDB (create/manage tables)
  - Amazon SNS (create/manage topics)
  - AWS IAM (create/manage roles and policies)
- Basic understanding of JSON and workflow concepts
- Sample documents (PDF, PNG, JPEG) for testing

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI version 2.0 or later

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0 or later
- AWS Provider 5.0 or later

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name document-processing-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketSuffix,ParameterValue=$(openssl rand -hex 6)

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name document-processing-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan
terraform apply -auto-approve
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Testing the Pipeline

After deployment, test the document processing pipeline:

1. **Upload a test document**:
   ```bash
   # Get bucket name from outputs
   DOCUMENT_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name document-processing-pipeline \
       --query 'Stacks[0].Outputs[?OutputKey==`DocumentBucket`].OutputValue' \
       --output text)
   
   # Upload a sample PDF
   aws s3 cp sample-document.pdf s3://${DOCUMENT_BUCKET}/
   ```

2. **Monitor processing**:
   ```bash
   # Check Step Functions executions
   aws stepfunctions list-executions \
       --state-machine-arn $(aws cloudformation describe-stacks \
           --stack-name document-processing-pipeline \
           --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
           --output text) \
       --max-items 5
   ```

3. **Verify results**:
   ```bash
   # Check results bucket
   RESULTS_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name document-processing-pipeline \
       --query 'Stacks[0].Outputs[?OutputKey==`ResultsBucket`].OutputValue' \
       --output text)
   
   aws s3 ls s3://${RESULTS_BUCKET}/ --recursive
   ```

## Architecture Overview

The deployed infrastructure includes:

- **S3 Buckets**: Document input and results storage
- **Step Functions State Machine**: Orchestrates document processing workflow
- **Lambda Function**: Triggers processing on document upload
- **DynamoDB Table**: Tracks processing job status
- **SNS Topic**: Sends processing notifications
- **IAM Roles**: Secure service-to-service communication

## Customization

### Available Parameters

Each implementation supports customization through variables/parameters:

- `BucketSuffix`: Unique suffix for S3 bucket names
- `NotificationEmail`: Email address for SNS notifications (optional)
- `ProcessingTimeout`: Timeout for document processing (default: 300 seconds)
- `RetryAttempts`: Number of retry attempts for failed processing (default: 3)

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name document-processing-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=BucketSuffix,ParameterValue=mycompany123 \
        ParameterKey=NotificationEmail,ParameterValue=admin@mycompany.com
```

### CDK Context Variables

```bash
cdk deploy -c bucketSuffix=mycompany123 -c notificationEmail=admin@mycompany.com
```

### Terraform Variables

```bash
terraform apply \
    -var="bucket_suffix=mycompany123" \
    -var="notification_email=admin@mycompany.com"
```

## Cleanup

### Using CloudFormation

```bash
# Empty S3 buckets first (required before deletion)
aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name document-processing-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`DocumentBucket`].OutputValue' \
    --output text) --recursive

aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name document-processing-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`ResultsBucket`].OutputValue' \
    --output text) --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name document-processing-pipeline
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Monitoring and Troubleshooting

### Step Functions Console

Monitor workflow executions in the AWS Step Functions console:
- View execution history and status
- Debug failed executions with visual workflow
- Inspect input/output data for each step

### CloudWatch Logs

Lambda function logs are available in CloudWatch:
- Function execution logs
- Error details and stack traces
- Processing metrics and performance data

### Common Issues

1. **Permission Errors**: Ensure IAM roles have necessary permissions
2. **Timeout Issues**: Increase processing timeout for large documents
3. **Bucket Access**: Verify S3 bucket policies and cross-region access
4. **Document Format**: Ensure uploaded documents are supported formats (PDF, PNG, JPEG)

## Cost Optimization

- **S3 Storage**: Use appropriate storage classes for different retention needs
- **Step Functions**: Standard workflows for audit requirements, Express for high-volume processing
- **Lambda**: Right-size memory allocation based on processing requirements
- **Textract**: Choose appropriate API (DetectText vs AnalyzeDocument) based on document complexity

## Security Best Practices

The infrastructure implements several security best practices:

- **Least Privilege IAM**: Roles have minimum required permissions
- **Encryption**: S3 buckets use server-side encryption
- **VPC Endpoints**: Optional VPC endpoints for private communication
- **Resource Tagging**: Consistent tagging for compliance and cost tracking

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../document-processing-pipelines-textract-step-functions.md)
2. Review AWS service documentation:
   - [Amazon Textract Developer Guide](https://docs.aws.amazon.com/textract/latest/dg/what-is.html)
   - [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
3. Check AWS CloudFormation/CDK/Terraform documentation for syntax issues
4. Review CloudWatch logs for runtime errors

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any parameter changes
4. Ensure cleanup scripts properly remove all resources