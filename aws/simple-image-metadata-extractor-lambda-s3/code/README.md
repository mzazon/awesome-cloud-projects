# Infrastructure as Code for Simple Image Metadata Extractor with Lambda and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Image Metadata Extractor with Lambda and S3".

## Solution Overview

This serverless solution automatically extracts metadata from images uploaded to S3 using AWS Lambda. When users upload JPG, JPEG, or PNG images to an S3 bucket, Lambda functions automatically process them to extract comprehensive metadata including dimensions, file size, format, aspect ratio, and EXIF data presence.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure creates:
- S3 bucket with versioning and encryption for image storage
- Lambda function for metadata extraction using Python 3.12 runtime
- Lambda layer with PIL/Pillow library for image processing
- IAM role with least privilege permissions
- S3 event triggers for automatic processing
- CloudWatch logs for monitoring and debugging

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with permissions for:
  - S3 (bucket creation, object operations)
  - Lambda (function creation, layer management)
  - IAM (role and policy management)
  - CloudWatch (logs access)
- Estimated cost: $0.01-$0.05 for testing (AWS Free Tier eligible)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI version 2.0 or later

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### Terraform
- Terraform 1.0 or later
- AWS provider 5.0 or later

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name image-metadata-extractor \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-image-bucket-$(date +%s)

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name image-metadata-extractor \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name image-metadata-extractor \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Preview deployment
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

# The script will:
# 1. Set up environment variables
# 2. Create S3 bucket with security settings
# 3. Create IAM role and policies
# 4. Build and deploy Lambda layer
# 5. Deploy Lambda function
# 6. Configure S3 event triggers
```

## Testing the Deployment

After successful deployment, test the solution:

1. **Upload a test image**:
   ```bash
   # Get bucket name from outputs
   aws s3 cp your-test-image.jpg s3://your-bucket-name/test-image.jpg
   ```

2. **Check Lambda logs**:
   ```bash
   # View recent logs
   aws logs tail /aws/lambda/your-function-name --follow
   ```

3. **Expected behavior**:
   - Lambda function automatically triggered on image upload
   - Metadata extracted and logged to CloudWatch
   - JSON output includes dimensions, format, file size, and EXIF data

## Customization Options

### CloudFormation Parameters
- `BucketName`: S3 bucket name (must be globally unique)
- `FunctionName`: Lambda function name
- `LayerName`: Lambda layer name
- `MemorySize`: Lambda memory allocation (default: 256MB)
- `Timeout`: Lambda timeout in seconds (default: 30)

### CDK Configuration
Modify the following in the CDK code:
- Runtime version (Python 3.12 recommended)
- Memory and timeout settings  
- Supported image formats
- Layer dependencies

### Terraform Variables
Available variables in `variables.tf`:
- `region`: AWS region for deployment
- `bucket_name`: S3 bucket name
- `function_name`: Lambda function name
- `memory_size`: Lambda memory allocation
- `timeout`: Function timeout

### Environment Variables
All implementations support these customization options:
```bash
export AWS_REGION=us-east-1
export BUCKET_NAME=my-custom-bucket-name
export FUNCTION_NAME=my-metadata-extractor
export MEMORY_SIZE=512
export TIMEOUT=60
```

## Monitoring and Troubleshooting

### CloudWatch Metrics
Monitor these key metrics:
- Lambda invocation count and duration
- Lambda error rate and throttling
- S3 PUT object requests
- Lambda memory utilization

### Common Issues

1. **Permission Errors**:
   - Verify IAM role has S3 read permissions
   - Check Lambda execution role attachment

2. **Function Timeouts**:
   - Increase timeout for large images
   - Consider optimizing PIL usage

3. **Layer Issues**:
   - Ensure PIL layer is compatible with Python runtime
   - Verify layer is attached to function

4. **Event Trigger Problems**:
   - Check S3 notification configuration
   - Verify file extension filters

### Logs Access
```bash
# View function logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/your-function-name

# Tail live logs
aws logs tail /aws/lambda/your-function-name --follow
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name image-metadata-extractor

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name image-metadata-extractor \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy TypeScript deployment
cd cdk-typescript/
cdk destroy

# Destroy Python deployment
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/

# Preview destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Remove state files (optional)
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Remove S3 event triggers
# 2. Delete Lambda function and layer
# 3. Remove IAM roles and policies
# 4. Empty and delete S3 bucket
# 5. Clean up local files
```

## Security Considerations

### IAM Permissions
The solution implements least privilege access:
- Lambda execution role for CloudWatch Logs
- S3 read-only access to specific bucket
- No write permissions beyond logging

### Data Protection
- S3 bucket encrypted with AES-256
- Versioning enabled for data protection
- Public access blocked by default

### Network Security
- Lambda functions run in AWS managed VPC
- No inbound network access required
- All communications over HTTPS/TLS

## Performance Optimization

### Memory Allocation
- Default: 256MB (suitable for most images)
- Increase to 512MB for large images (>5MB)
- Monitor CloudWatch metrics for optimization

### Cold Start Mitigation
- Keep layer size minimal
- Use provisioned concurrency for high-frequency usage
- Consider connection pooling for external services

### Cost Optimization
- Use S3 Intelligent Tiering for storage
- Monitor Lambda duration for right-sizing
- Set appropriate log retention periods

## Extension Ideas

1. **Database Integration**: Store metadata in DynamoDB for querying
2. **Thumbnail Generation**: Create multiple image sizes
3. **Advanced Analysis**: Integrate with Amazon Rekognition
4. **Batch Processing**: Process existing images in bulk
5. **API Integration**: Expose metadata via API Gateway
6. **Notification System**: Send alerts via SNS for specific image types

## Support and Documentation

- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/s3/latest/userguide/)
- [PIL/Pillow Documentation](https://pillow.readthedocs.io/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and adapt security settings for production use.