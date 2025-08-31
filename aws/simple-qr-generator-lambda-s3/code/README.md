# Infrastructure as Code for Simple QR Code Generator with Lambda and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple QR Code Generator with Lambda and S3".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (or use AWS CloudShell)
- AWS account with appropriate permissions for Lambda, S3, API Gateway, and IAM
- Basic understanding of REST APIs and serverless concepts
- Python programming knowledge for Lambda function customization
- Estimated cost: $0.01-$0.10 for testing (minimal usage of serverless services)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI version 2.0 or later
- IAM permissions for CloudFormation operations

#### CDK TypeScript
- Node.js 16.x or later
- AWS CDK CLI: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI: `pip install aws-cdk-lib`
- pip package manager

#### Terraform
- Terraform 1.0 or later
- AWS provider for Terraform

#### Bash Scripts
- Bash shell environment
- jq (JSON processor) for response parsing
- curl for API testing

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name qr-generator-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=qr-generator-bucket-$(date +%s)

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name qr-generator-stack

# Get the API endpoint
aws cloudformation describe-stacks \
    --stack-name qr-generator-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
cdk list --json
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Get outputs
cdk list --json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply -auto-approve

# Get outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the API endpoint URL when complete
```

## Testing Your Deployment

After deployment, test the QR code generator:

```bash
# Replace API_URL with your actual endpoint
API_URL="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Test QR code generation
curl -X POST ${API_URL}/generate \
    -H "Content-Type: application/json" \
    -d '{"text": "Hello, World! This is my first QR code."}' \
    | jq '.'

# Expected response:
# {
#   "message": "QR code generated successfully",
#   "url": "https://bucket-name.s3.region.amazonaws.com/filename.png",
#   "filename": "qr_20250112_143022_a1b2c3d4.png",
#   "text_length": 42
# }
```

## Architecture Overview

The infrastructure creates:

- **S3 Bucket**: Stores generated QR code images with public read access
- **Lambda Function**: Processes QR code generation requests using Python and qrcode library
- **API Gateway**: Provides REST API endpoint for QR code generation
- **IAM Role**: Grants Lambda permissions to write to S3 and CloudWatch logs

## Configuration Options

### Customizable Parameters

- **Bucket Name**: S3 bucket for storing QR code images
- **Function Name**: Lambda function name
- **API Name**: API Gateway name
- **Memory Size**: Lambda memory allocation (128-3008 MB)
- **Timeout**: Lambda timeout duration (3-900 seconds)
- **Runtime**: Python runtime version (python3.12 recommended)

### Environment Variables

The Lambda function uses these environment variables:
- `BUCKET_NAME`: Target S3 bucket for QR code storage

### Security Configuration

- Lambda execution role with minimal required permissions
- S3 bucket configured for public read access (customizable)
- API Gateway with no authentication (can be enhanced)
- Input validation and error handling in Lambda function

## Cleanup

### Using CloudFormation
```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack --stack-name qr-generator-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name qr-generator-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Enhancing Security

1. **Remove public bucket access**: Use CloudFront with Origin Access Control
2. **Add API authentication**: Implement API keys or Cognito integration
3. **Enable request validation**: Add input validation at API Gateway level
4. **Implement rate limiting**: Configure API Gateway throttling

### Performance Optimization

1. **Adjust Lambda memory**: Increase for faster QR code generation
2. **Enable S3 Transfer Acceleration**: For global access optimization
3. **Add CloudFront**: For global content delivery
4. **Implement caching**: Cache frequently requested QR codes

### Monitoring and Logging

1. **CloudWatch Alarms**: Monitor Lambda errors and API Gateway metrics
2. **X-Ray Tracing**: Enable distributed tracing for debugging
3. **Custom Metrics**: Track QR code generation patterns
4. **Log Analysis**: Use CloudWatch Insights for log analysis

## Cost Optimization

- Use S3 Intelligent Tiering for automatic cost optimization
- Implement S3 lifecycle policies to archive old QR codes
- Monitor Lambda execution costs and optimize memory allocation
- Use API Gateway caching to reduce Lambda invocations

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**: Ensure Lambda execution role has S3 write permissions
2. **API Gateway 500 Errors**: Check CloudWatch logs for Lambda function errors
3. **S3 Access Denied**: Verify bucket policy allows public read access
4. **Cold Start Latency**: Consider provisioned concurrency for production workloads

### Debugging Steps

1. Check CloudWatch logs for Lambda function execution details
2. Test Lambda function directly using AWS CLI or console
3. Verify API Gateway configuration and deployment status
4. Confirm S3 bucket permissions and public access settings

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../simple-qr-generator-lambda-s3.md)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
- [AWS API Gateway documentation](https://docs.aws.amazon.com/apigateway/)
- [AWS S3 documentation](https://docs.aws.amazon.com/s3/)

## Security Considerations

> **Warning**: This configuration enables public read access to the S3 bucket. Only use this for non-sensitive QR codes. For production use, consider using signed URLs or CloudFront with Origin Access Control.

### Production Recommendations

1. Implement API authentication and authorization
2. Use CloudFront with Origin Access Control instead of public S3 access
3. Enable AWS WAF for API protection
4. Implement request logging and monitoring
5. Use KMS encryption for S3 objects
6. Implement input validation and sanitization