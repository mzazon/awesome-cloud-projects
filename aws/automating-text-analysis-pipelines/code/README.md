# Infrastructure as Code for Automating Text Analysis Pipelines with Amazon Comprehend

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating Text Analysis Pipelines with Amazon Comprehend".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive NLP pipeline that includes:

- **Amazon Comprehend**: For sentiment analysis, entity detection, and key phrase extraction
- **AWS Lambda**: Serverless function for real-time text processing
- **Amazon S3**: Storage for input documents and processed results
- **IAM Roles**: Secure access permissions for all services
- **Batch Processing**: Support for large-scale document analysis

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Comprehend (all analysis APIs and batch job management)
  - AWS Lambda (function creation and execution)
  - Amazon S3 (bucket creation and object management)
  - IAM (role and policy creation)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name comprehend-nlp-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name comprehend-nlp-pipeline

# Get outputs
aws cloudformation describe-stacks \
    --stack-name comprehend-nlp-pipeline \
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
cdk deploy --require-approval never

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
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

# Apply the infrastructure
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
# 1. Create S3 buckets for input/output
# 2. Create IAM roles and policies
# 3. Deploy Lambda function
# 4. Upload sample data
# 5. Configure batch processing roles
```

## Testing the Deployment

After deployment, test the NLP pipeline:

### Real-time Processing Test

```bash
# Test Lambda function directly
aws lambda invoke \
    --function-name comprehend-processor-<suffix> \
    --payload '{
        "text": "I love this product! The quality is amazing.",
        "output_bucket": "comprehend-nlp-pipeline-<suffix>"
    }' \
    --cli-binary-format raw-in-base64-out \
    response.json

# View results
cat response.json | jq '.body | fromjson'
```

### Batch Processing Test

```bash
# Upload test documents
echo "This product is terrible!" > negative-review.txt
echo "Amazing service and great quality!" > positive-review.txt

aws s3 cp negative-review.txt s3://comprehend-nlp-pipeline-<suffix>/input/
aws s3 cp positive-review.txt s3://comprehend-nlp-pipeline-<suffix>/input/

# Start batch sentiment analysis job
aws comprehend start-sentiment-detection-job \
    --input-data-config "S3Uri=s3://comprehend-nlp-pipeline-<suffix>/input/,InputFormat=ONE_DOC_PER_FILE" \
    --output-data-config "S3Uri=s3://comprehend-nlp-pipeline-<suffix>-output/batch-results/" \
    --data-access-role-arn arn:aws:iam::<account-id>:role/ComprehendServiceRole-<suffix> \
    --job-name test-sentiment-job \
    --language-code en
```

## Configuration Options

### Environment Variables

All implementations support these configuration parameters:

- `ENVIRONMENT_NAME`: Environment identifier (dev, staging, prod)
- `BUCKET_PREFIX`: Custom prefix for S3 bucket names
- `LAMBDA_MEMORY`: Lambda function memory allocation (256-3008 MB)
- `LAMBDA_TIMEOUT`: Lambda function timeout (1-900 seconds)
- `ENABLE_BATCH_PROCESSING`: Enable batch analysis capabilities (true/false)

### CloudFormation Parameters

```yaml
Parameters:
  EnvironmentName:
    Type: String
    Default: dev
    Description: Environment name for resource tagging
  
  BucketPrefix:
    Type: String
    Default: comprehend-nlp-pipeline
    Description: Prefix for S3 bucket names
  
  LambdaMemorySize:
    Type: Number
    Default: 256
    MinValue: 128
    MaxValue: 3008
    Description: Lambda function memory allocation
```

### Terraform Variables

```hcl
variable "environment_name" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
}

variable "bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "comprehend-nlp-pipeline"
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation"
  type        = number
  default     = 256
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}
```

## Outputs

All implementations provide these outputs:

- **InputBucketName**: S3 bucket for input documents
- **OutputBucketName**: S3 bucket for processed results
- **LambdaFunctionName**: Name of the processing Lambda function
- **LambdaFunctionArn**: ARN of the processing Lambda function
- **ComprehendRoleArn**: IAM role ARN for batch processing
- **ProcessorFunctionUrl**: Lambda function URL for direct invocation (if enabled)

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name comprehend-nlp-pipeline

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name comprehend-nlp-pipeline
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy --auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Lambda function
# 2. Delete IAM roles and policies
# 3. Empty and delete S3 buckets
# 4. Clean up local files
```

## Customization

### Adding Custom Classification Models

To extend the solution with custom classification:

1. **Prepare Training Data**: Create CSV file with labeled examples
2. **Upload Training Data**: Store in S3 training folder
3. **Start Training Job**: Use Comprehend CreateDocumentClassifier API
4. **Update Lambda Code**: Add custom classification logic

Example training data format:
```csv
label,text
positive,"Great product with excellent quality!"
negative,"Terrible service and poor quality."
neutral,"Average product, works as expected."
```

### Integrating with Real-time Applications

For real-time integration:

1. **API Gateway**: Add REST API endpoint for external access
2. **SQS Integration**: Add queue for asynchronous processing
3. **EventBridge**: Connect to other AWS services for automated workflows
4. **DynamoDB**: Store analysis results for fast retrieval

### Multi-language Support

To support multiple languages:

1. **Language Detection**: Enable automatic language detection
2. **Translation**: Integrate Amazon Translate for non-English text
3. **Custom Models**: Train language-specific classification models
4. **Localized Outputs**: Configure region-specific Comprehend endpoints

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:

- **Lambda Duration**: Processing time per request
- **Lambda Errors**: Failed invocations and error rates
- **S3 Objects**: Input and output object counts
- **Comprehend API Calls**: Usage and throttling metrics

### Logging

All implementations include comprehensive logging:

- **Lambda Logs**: Detailed processing logs in CloudWatch
- **API Access Logs**: S3 access patterns and performance
- **Error Logs**: Comprehensive error tracking and debugging

### Alerting

Set up CloudWatch alarms for:

- High error rates (>5% over 5 minutes)
- Long processing times (>30 seconds)
- API throttling events
- Cost thresholds exceeded

## Security Considerations

### IAM Best Practices

- **Least Privilege**: Roles have minimal required permissions
- **Resource-Specific**: Policies target specific S3 buckets and resources
- **No Hardcoded Credentials**: All access via IAM roles
- **Regular Rotation**: Support for credential rotation

### Data Protection

- **Encryption at Rest**: S3 buckets use server-side encryption
- **Encryption in Transit**: All API calls use HTTPS
- **Data Retention**: Configurable retention policies for processed data
- **Access Logging**: S3 access logs for audit trails

### Network Security

- **VPC Support**: Lambda can be deployed in VPC for network isolation
- **Security Groups**: Restrict network access where needed
- **Private Endpoints**: Use VPC endpoints for AWS service access

## Cost Optimization

### Pricing Considerations

- **Comprehend**: $0.0001 per unit (100 characters) for real-time analysis
- **Lambda**: Pay per invocation and execution time
- **S3**: Storage costs for input/output data
- **Free Tier**: 50K units (5M characters) free per month for first 12 months

### Cost Optimization Tips

1. **Batch Processing**: Use batch jobs for large document sets (lower cost per unit)
2. **S3 Lifecycle**: Configure automatic deletion of processed files
3. **Lambda Memory**: Right-size memory allocation based on processing needs
4. **Reserved Capacity**: Consider reserved capacity for predictable workloads

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**
   - Verify roles have correct policies attached
   - Check trust relationships are properly configured
   - Ensure account limits haven't been exceeded

2. **Lambda Timeouts**
   - Increase timeout setting for large documents
   - Consider breaking large texts into smaller chunks
   - Monitor memory usage and adjust allocation

3. **Comprehend API Limits**
   - Implement exponential backoff for API calls
   - Monitor for throttling and adjust request rate
   - Consider batch processing for high volumes

4. **S3 Access Issues**
   - Verify bucket policies allow required access
   - Check object naming conventions
   - Ensure proper bucket region configuration

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export AWS_LAMBDA_LOG_LEVEL=DEBUG
export COMPREHEND_DEBUG=true
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for implementation details
2. **AWS Documentation**: Check AWS service documentation for latest features
3. **Community Support**: Use AWS forums and Stack Overflow for troubleshooting
4. **AWS Support**: Contact AWS Support for service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any new features or changes
4. Validate all IaC implementations work correctly
5. Include appropriate error handling and logging

## Version History

- **v1.0**: Initial implementation with basic NLP pipeline
- **v1.1**: Added custom classification model support
- **v1.2**: Enhanced security and monitoring capabilities
- **v1.3**: Added multi-language support and cost optimization features