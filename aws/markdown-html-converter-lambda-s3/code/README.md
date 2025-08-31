# Infrastructure as Code for Simple Markdown to HTML Converter with Lambda and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Markdown to HTML Converter with Lambda and S3". This serverless solution automatically converts uploaded Markdown files to formatted HTML using AWS Lambda and S3 with event-driven processing.

## Architecture Overview

The solution deploys:
- **S3 Input Bucket**: Receives Markdown files with server-side encryption and versioning
- **S3 Output Bucket**: Stores converted HTML files with matching security configuration
- **Lambda Function**: Python-based converter using markdown2 library with comprehensive error handling
- **IAM Role**: Execution role with least-privilege permissions for S3 access and CloudWatch logging
- **S3 Event Notification**: Automatic trigger for Lambda function when .md files are uploaded
- **CloudWatch Logs**: Monitoring and debugging capabilities

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with permissions for Lambda, S3, IAM, and CloudWatch services
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of serverless computing concepts
- Estimated cost: $0.01-$0.05 for testing (Lambda executions and S3 storage)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack with default parameters
aws cloudformation create-stack \
    --stack-name markdown-converter-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ResourcePrefix,ParameterValue=markdown-converter

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name markdown-converter-stack

# Get stack outputs for bucket names and function name
aws cloudformation describe-stacks \
    --stack-name markdown-converter-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View deployed resources
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View deployed resources
cdk list
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

# View deployed resources
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output bucket names and function details
```

## Testing the Deployment

After deployment, test the solution with these steps:

1. **Create a sample Markdown file**:
```bash
cat > test-document.md << 'EOF'
# Test Document

This is a **test markdown document** for the converter.

## Features
- **Bold text** and *italic text*
- `inline code` snippets
- [Links](https://aws.amazon.com)

### Code Block
```python
def hello():
    print("Hello from Lambda!")
```

| Service | Purpose |
|---------|---------|
| Lambda | Compute |
| S3 | Storage |
EOF
```

2. **Upload to input bucket** (replace bucket name from outputs):
```bash
# Get bucket name from CloudFormation outputs
INPUT_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name markdown-converter-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`InputBucketName`].OutputValue' \
    --output text)

# Upload test file
aws s3 cp test-document.md s3://${INPUT_BUCKET}/
```

3. **Check conversion results**:
```bash
# Get output bucket name
OUTPUT_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name markdown-converter-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`OutputBucketName`].OutputValue' \
    --output text)

# Wait a few seconds for processing
sleep 10

# Check if HTML file was created
aws s3 ls s3://${OUTPUT_BUCKET}/

# Download the converted HTML file
aws s3 cp s3://${OUTPUT_BUCKET}/test-document.html ./
```

## Customization

### CloudFormation Parameters

The CloudFormation template supports these parameters:
- `ResourcePrefix`: Prefix for resource names (default: markdown-converter)
- `LambdaTimeout`: Function timeout in seconds (default: 60)
- `LambdaMemorySize`: Function memory allocation in MB (default: 256)

Example with custom parameters:
```bash
aws cloudformation create-stack \
    --stack-name my-converter-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ResourcePrefix,ParameterValue=my-converter \
        ParameterKey=LambdaTimeout,ParameterValue=90 \
        ParameterKey=LambdaMemorySize,ParameterValue=512
```

### CDK Context Variables

Both CDK implementations support context variables:
```bash
# Deploy with custom configuration
cdk deploy \
    --context resourcePrefix=my-converter \
    --context lambdaTimeout=90 \
    --context lambdaMemorySize=512
```

### Terraform Variables

The Terraform implementation uses variables defined in `variables.tf`:
```bash
# Deploy with custom values
terraform apply \
    -var="resource_prefix=my-converter" \
    -var="lambda_timeout=90" \
    -var="lambda_memory_size=512" \
    -auto-approve
```

Or create a `terraform.tfvars` file:
```hcl
resource_prefix = "my-converter"
lambda_timeout = 90
lambda_memory_size = 512
```

## Monitoring and Troubleshooting

### View Lambda Function Logs

```bash
# Get function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name markdown-converter-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# View recent logs
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow
```

### Check S3 Event Configuration

```bash
# Verify S3 event notification is configured
aws s3api get-bucket-notification-configuration \
    --bucket ${INPUT_BUCKET}
```

### Monitor Lambda Metrics

```bash
# Get Lambda function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=${FUNCTION_NAME} \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name markdown-converter-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name markdown-converter-stack
```

### Using CDK (AWS)

```bash
# From the CDK directory (cdk-typescript/ or cdk-python/)
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Security Considerations

The IaC implementations include these security best practices:

- **S3 Bucket Encryption**: Server-side encryption with AES-256 enabled by default
- **S3 Bucket Versioning**: Enabled for data protection and recovery
- **IAM Least Privilege**: Lambda execution role has minimal required permissions
- **S3 Public Access**: Block all public access to both input and output buckets
- **Lambda Function**: No external network access required, operates within AWS VPC
- **CloudWatch Logs**: Encrypted log groups for monitoring and debugging

## Cost Optimization

The solution is designed for cost efficiency:

- **Lambda**: Pay-per-request pricing with optimized memory allocation (256MB)
- **S3**: Standard storage class with intelligent tiering options available
- **CloudWatch**: Logs retention period can be configured to manage costs
- **No Always-On Resources**: Fully serverless with no persistent compute costs

Estimated monthly costs for moderate usage (100 file conversions):
- Lambda: $0.01-0.02
- S3 Storage: $0.01-0.05
- CloudWatch Logs: $0.01
- **Total**: ~$0.03-0.08/month

## Troubleshooting Common Issues

### Lambda Function Not Triggering

1. Verify S3 event notification configuration
2. Check Lambda function permissions for S3 invocation
3. Ensure files have .md extension
4. Review CloudWatch logs for error messages

### Conversion Failures

1. Check file encoding (UTF-8 required)
2. Verify markdown2 library is included in deployment package
3. Review Lambda function timeout settings
4. Check S3 permissions for reading input and writing output

### Permission Errors

1. Verify IAM role has correct policies attached
2. Check S3 bucket policies don't block Lambda access
3. Ensure output bucket allows PutObject operations
4. Review CloudWatch Logs permissions

## Advanced Configuration

### Custom HTML Templates

Modify the Lambda function code to support custom CSS themes:

```python
# Add to environment variables in IaC templates
CSS_THEME = "dark"  # or "light", "minimal", etc.
```

### Batch Processing

Extend the solution to handle ZIP files containing multiple Markdown documents by modifying the Lambda function to:
1. Detect ZIP file uploads
2. Extract contents to temporary storage
3. Process each Markdown file individually
4. Maintain folder structure in output

### Multiple Output Formats

Add PDF generation capability by including additional Python libraries:
- WeasyPrint for HTML-to-PDF conversion
- ReportLab for direct PDF generation
- Configure Lambda layer for heavy dependencies

## Support and Contributing

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation for specific services
3. Refer to the original recipe documentation
4. Check AWS service health status

The infrastructure code follows AWS Well-Architected Framework principles and can be extended for production use with additional monitoring, alerting, and backup strategies.