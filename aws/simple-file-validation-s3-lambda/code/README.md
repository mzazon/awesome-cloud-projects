# Infrastructure as Code for Simple File Validation with S3 and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Validation with S3 and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating S3 buckets, Lambda functions, and IAM roles
- For CDK implementations: Node.js 18+ and AWS CDK CLI installed
- For Terraform: Terraform 1.0+ installed
- Basic understanding of serverless computing concepts

### Required AWS Permissions

Your AWS user/role needs the following permissions:

- `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutBucketNotification`
- `lambda:CreateFunction`, `lambda:DeleteFunction`, `lambda:AddPermission`
- `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`
- `iam:CreatePolicy`, `iam:DeletePolicy`

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name simple-file-validation \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=file-validation

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name simple-file-validation

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name simple-file-validation \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get stack outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will output bucket names and function details
```

## Testing the Deployment

After successful deployment, test the file validation system:

### 1. Test Valid File Upload

```bash
# Get bucket names from outputs
UPLOAD_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name simple-file-validation \
    --query 'Stacks[0].Outputs[?OutputKey==`UploadBucketName`].OutputValue' \
    --output text)

VALID_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name simple-file-validation \
    --query 'Stacks[0].Outputs[?OutputKey==`ValidBucketName`].OutputValue' \
    --output text)

# Create and upload a valid test file
echo "This is a valid text file" > test-valid.txt
aws s3 cp test-valid.txt s3://${UPLOAD_BUCKET}/

# Wait for processing (15 seconds)
sleep 15

# Check if file was moved to valid bucket
aws s3 ls s3://${VALID_BUCKET}/ --recursive
```

### 2. Test Invalid File Upload

```bash
# Get quarantine bucket name
QUARANTINE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name simple-file-validation \
    --query 'Stacks[0].Outputs[?OutputKey==`QuarantineBucketName`].OutputValue' \
    --output text)

# Create and upload an invalid test file
echo "Invalid file content" > test-invalid.exe
aws s3 cp test-invalid.exe s3://${UPLOAD_BUCKET}/

# Wait for processing
sleep 15

# Check if file was moved to quarantine bucket
aws s3 ls s3://${QUARANTINE_BUCKET}/ --recursive
```

### 3. Monitor Lambda Function Logs

```bash
# Get function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name simple-file-validation \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# View recent logs
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow
```

## Configuration Options

### File Validation Rules

The default configuration validates:

- **Allowed file types**: .txt, .pdf, .jpg, .jpeg, .png, .doc, .docx
- **Maximum file size**: 10 MB

To modify these rules, update the Lambda function code in your chosen implementation:

- **CloudFormation**: Edit the `ZipFile` property in the Lambda function resource
- **CDK**: Modify the function code in the CDK source files
- **Terraform**: Update the Lambda function code in `main.tf`
- **Bash Scripts**: Edit the Lambda function creation in `deploy.sh`

### Customization Parameters

Most implementations support these customization options:

- `ProjectName`: Prefix for resource names (default: "file-validation")
- `Environment`: Environment tag (default: "development")
- `MaxFileSize`: Maximum allowed file size in bytes (default: 10485760)
- `AllowedExtensions`: Comma-separated list of allowed file extensions

## Architecture Overview

This solution implements a serverless file validation system with these components:

1. **S3 Upload Bucket**: Receives file uploads and triggers validation
2. **S3 Valid Bucket**: Stores files that pass validation
3. **S3 Quarantine Bucket**: Isolates files that fail validation
4. **Lambda Function**: Processes uploaded files and applies validation rules
5. **IAM Role**: Provides secure access permissions for Lambda
6. **S3 Event Notification**: Triggers Lambda function on file uploads

### Data Flow

1. User uploads file to Upload Bucket
2. S3 event notification triggers Lambda function
3. Lambda function validates file type and size
4. Valid files are moved to Valid Bucket
5. Invalid files are moved to Quarantine Bucket
6. Original file is deleted from Upload Bucket
7. Processing results are logged to CloudWatch

## Cleanup

### Using CloudFormation

```bash
# Empty S3 buckets before deleting stack
aws s3 rm s3://${UPLOAD_BUCKET} --recursive
aws s3 rm s3://${VALID_BUCKET} --recursive
aws s3 rm s3://${QUARANTINE_BUCKET} --recursive

# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name simple-file-validation

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name simple-file-validation
```

### Using CDK

```bash
# CDK will handle bucket cleanup automatically
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm destruction when prompted
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM role policies are correctly configured

2. **Lambda Function Not Triggering**
   - Verify S3 event notification is properly configured
   - Check Lambda function permissions for S3 invocation

3. **Files Not Moving Between Buckets**
   - Verify Lambda function has read/write permissions to all buckets
   - Check CloudWatch logs for error messages

4. **CDK Bootstrap Issues**
   - Run `cdk bootstrap` in your target AWS region
   - Ensure CDK CLI version matches the version in package.json

### Monitoring and Logging

- **CloudWatch Logs**: Monitor Lambda function execution logs
- **CloudWatch Metrics**: Track Lambda invocations, errors, and duration
- **S3 Access Logs**: Optional monitoring of bucket access patterns
- **AWS X-Ray**: Optional distributed tracing for performance analysis

## Cost Considerations

This solution uses serverless components with pay-as-you-use pricing:

- **S3 Storage**: $0.023 per GB per month (Standard storage class)
- **Lambda**: $0.20 per 1M requests + $0.0000166667 per GB-second
- **CloudWatch Logs**: $0.50 per GB ingested

Estimated monthly cost for moderate usage (1000 files):
- S3 storage (1 GB): ~$0.02
- Lambda execution: ~$0.20
- CloudWatch logs: ~$0.01
- **Total**: Less than $1 per month

## Security Best Practices

This implementation follows AWS security best practices:

- **Least Privilege**: IAM roles have minimal required permissions
- **Bucket Isolation**: Separate buckets for different file states
- **Encryption**: S3 buckets use server-side encryption by default
- **Event-Driven**: No long-running processes or exposed endpoints
- **Logging**: All operations are logged to CloudWatch

## Extensions and Enhancements

Consider these enhancements for production use:

1. **Content Scanning**: Integrate Amazon GuardDuty malware detection
2. **Notification System**: Add SNS notifications for quarantined files
3. **Metadata Extraction**: Use Amazon Textract for document analysis
4. **Monitoring Dashboards**: Create CloudWatch dashboards for operations
5. **Dead Letter Queues**: Handle failed Lambda executions
6. **Multi-Region**: Deploy across multiple AWS regions for availability

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review CloudWatch logs for error details
3. Refer to the original recipe documentation
4. Consult AWS documentation for specific services
5. Use AWS Support for infrastructure-related issues

## Version Information

- **Recipe Version**: 1.1
- **Generated IaC Version**: Compatible with latest AWS services
- **Last Updated**: 2025-07-12
- **AWS CLI Version**: Requires v2.x
- **CDK Version**: Requires v2.x
- **Terraform Version**: Requires v1.0+