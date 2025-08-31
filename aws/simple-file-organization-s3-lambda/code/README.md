# Infrastructure as Code for Simple File Organization with S3 and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Organization with S3 and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - Lambda function creation and deployment
  - IAM role and policy management
  - CloudWatch logs access
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+ installed

## Architecture Overview

This solution creates an automated file organization system that:

1. **S3 Bucket**: Stores uploaded files with versioning and encryption enabled
2. **Lambda Function**: Analyzes file extensions and moves files to organized folders
3. **IAM Role**: Provides Lambda with necessary S3 and CloudWatch permissions
4. **S3 Event Notification**: Triggers Lambda function on file uploads
5. **Folder Structure**: Pre-created folders for images, documents, videos, and other files

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name file-organizer-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-file-organizer-bucket

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name file-organizer-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to TypeScript implementation
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python (AWS)

```bash
# Navigate to Python implementation
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack information
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform implementation
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

# Follow prompts for configuration
```

## Testing Your Deployment

After deployment, test the file organization system:

```bash
# Get bucket name from outputs (adjust based on your deployment method)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name file-organizer-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

# Create test files
echo "Sample image content" > test-image.jpg
echo "Sample document content" > test-document.pdf
echo "Sample video metadata" > test-video.mp4

# Upload files to trigger organization
aws s3 cp test-image.jpg s3://${BUCKET_NAME}/
aws s3 cp test-document.pdf s3://${BUCKET_NAME}/
aws s3 cp test-video.mp4 s3://${BUCKET_NAME}/

# Wait for processing (5-10 seconds)
sleep 10

# Verify files were organized
aws s3 ls s3://${BUCKET_NAME}/ --recursive

# Expected structure:
# images/test-image.jpg
# documents/test-document.pdf
# videos/test-video.mp4
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty the S3 bucket first (required before deletion)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name file-organizer-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name file-organizer-stack
```

### Using CDK (AWS)

```bash
# Navigate to the CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Customization

### Parameters and Variables

Each implementation supports customization through parameters:

#### CloudFormation Parameters
- `BucketName`: Name for the S3 bucket (must be globally unique)
- `LambdaTimeout`: Function timeout in seconds (default: 60)
- `LambdaMemorySize`: Function memory allocation in MB (default: 256)

#### CDK Context Values
- `bucketName`: Custom bucket name
- `enableVersioning`: Enable S3 versioning (default: true)
- `enableEncryption`: Enable S3 encryption (default: true)

#### Terraform Variables
- `bucket_name`: S3 bucket name
- `lambda_timeout`: Function timeout
- `lambda_memory_size`: Function memory allocation
- `aws_region`: AWS region for deployment

### File Type Categories

The Lambda function organizes files into these categories:

- **Images**: jpg, jpeg, png, gif, bmp, tiff, svg, webp
- **Documents**: pdf, doc, docx, txt, rtf, odt, xls, xlsx, ppt, pptx, csv
- **Videos**: mp4, avi, mov, wmv, flv, webm, mkv, m4v
- **Other**: All other file types

To modify file type mappings, update the Lambda function code in your chosen implementation.

## Security Considerations

All implementations follow AWS security best practices:

- **Least Privilege IAM**: Lambda execution role has minimal required permissions
- **Encryption**: S3 bucket uses server-side encryption (AES-256)
- **Versioning**: S3 versioning enabled for data protection
- **Resource Isolation**: Resources are properly scoped to prevent unauthorized access

## Monitoring and Logging

The solution includes comprehensive logging:

- **CloudWatch Logs**: Lambda function execution logs
- **S3 Access Logs**: Optional bucket access logging
- **CloudWatch Metrics**: Lambda performance metrics

Access logs through:

```bash
# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/file-organizer"

# Get latest log stream
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/file-organizer-function" \
    --order-by LastEventTime --descending \
    --max-items 1
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Verify AWS CLI is configured with appropriate permissions
   - Check IAM policies allow S3, Lambda, and IAM operations

2. **Bucket Name Already Exists**
   - S3 bucket names must be globally unique
   - Modify the bucket name parameter in your deployment

3. **Lambda Function Not Triggering**
   - Verify S3 event notification is configured correctly
   - Check Lambda function permissions include S3 invoke permission

4. **Files Not Moving**
   - Check CloudWatch logs for Lambda execution errors
   - Verify S3 bucket policies don't prevent object operations

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name file-organizer-function

# View recent Lambda invocations
aws lambda get-function --function-name file-organizer-function \
    --query 'Configuration.LastModified'

# Check S3 bucket notification configuration
aws s3api get-bucket-notification-configuration --bucket YOUR_BUCKET_NAME
```

## Cost Optimization

This solution is designed for cost efficiency:

- **Lambda**: Pay only for execution time (typically <1 second per file)
- **S3**: Standard storage pricing with lifecycle policies
- **Free Tier**: Eligible for AWS Free Tier benefits

Estimated monthly costs for moderate usage (1000 files):
- Lambda: $0.20
- S3 Storage (1GB): $0.023
- S3 Requests: $0.005
- **Total**: ~$0.23/month

## Extensions and Enhancements

Consider these enhancements for production deployments:

1. **Content-Based Organization**: Use AWS Rekognition for image content analysis
2. **Duplicate Detection**: Implement file hash comparison
3. **Notification System**: Add SNS notifications for processing status
4. **Advanced Analytics**: Integrate with AWS Glue for file metadata analysis
5. **Multi-Region**: Deploy across multiple AWS regions for redundancy

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation:
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
   - [Amazon S3 User Guide](https://docs.aws.amazon.com/s3/)
   - [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
3. Consult the AWS CDK documentation for CDK-specific issues
4. Review Terraform AWS Provider documentation for Terraform issues

## Version Information

- CloudFormation: Uses latest AWS resource specifications
- CDK: Compatible with CDK v2.x
- Terraform: Requires Terraform 1.0+ and AWS Provider 5.0+
- Lambda Runtime: Python 3.12 (latest supported runtime)

Last updated: 2025-07-12