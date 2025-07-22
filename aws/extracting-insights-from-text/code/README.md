# Infrastructure as Code for Extracting Insights from Text with Amazon Comprehend

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Extracting Insights from Text with Amazon Comprehend".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Comprehend (full access)
  - AWS Lambda (create/invoke functions)
  - Amazon S3 (create/manage buckets)
  - Amazon EventBridge (create/manage rules)
  - IAM (create/manage roles and policies)
- Basic understanding of NLP concepts and AWS services
- Sample text data for testing (customer reviews, support tickets, etc.)

### Tool-Specific Prerequisites

#### For CloudFormation
- AWS CLI v2 with CloudFormation permissions

#### For CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript compiler

#### For CDK Python
- Python 3.8 or later
- AWS CDK CLI (`pip install aws-cdk-lib`)
- Virtual environment (recommended)

#### For Terraform
- Terraform 1.0 or later
- AWS provider knowledge

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the complete NLP solution
aws cloudformation create-stack \
    --stack-name comprehend-nlp-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-nlp-project

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name comprehend-nlp-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name comprehend-nlp-stack \
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
cdk deploy

# View stack outputs
cdk outputs
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk outputs
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

# Deploy the solution
./scripts/deploy.sh

# The script will:
# - Create S3 buckets for input/output
# - Set up IAM roles for Comprehend and Lambda
# - Deploy Lambda function for real-time processing
# - Configure EventBridge rules for automation
# - Upload sample text files for testing
```

## Architecture Overview

The deployed infrastructure includes:

### Core Components
- **Amazon Comprehend**: NLP processing service for sentiment analysis, entity detection, and topic modeling
- **AWS Lambda**: Serverless function for real-time text processing
- **Amazon S3**: Storage buckets for input documents and analysis results
- **Amazon EventBridge**: Event-driven automation for processing workflows

### IAM Security
- **Comprehend Service Role**: Allows batch processing with S3 access
- **Lambda Execution Role**: Enables real-time processing with Comprehend permissions
- **Least Privilege Access**: Minimal permissions for each service component

### Processing Capabilities
- **Real-time Analysis**: Sub-second response for individual text samples
- **Batch Processing**: Scalable analysis of large document collections
- **Custom Models**: Support for domain-specific entity recognition and classification
- **Multi-language Support**: Processing text in multiple languages

## Configuration Parameters

### CloudFormation Parameters
- `ProjectName`: Name prefix for all resources (default: comprehend-nlp)
- `Environment`: Deployment environment (default: dev)
- `RetentionDays`: Log retention period (default: 30)

### CDK Context Variables
- `project-name`: Name prefix for resources
- `environment`: Target environment
- `enable-custom-models`: Enable custom entity recognition (default: false)

### Terraform Variables
- `project_name`: Name prefix for all resources
- `aws_region`: AWS region for deployment
- `environment`: Environment tag for resources
- `retention_days`: CloudWatch log retention period

## Testing the Deployment

### 1. Verify Real-time Processing

```bash
# Test Lambda function (replace with actual function name)
aws lambda invoke \
    --function-name comprehend-processor-[suffix] \
    --payload '{"text": "I love this product! Great customer service."}' \
    /tmp/lambda-response.json

# View results
cat /tmp/lambda-response.json | jq '.body | fromjson'
```

### 2. Test Batch Processing

```bash
# Upload sample documents to input bucket
aws s3 cp sample-documents/ s3://comprehend-input-[suffix]/ --recursive

# Monitor job status
aws comprehend list-sentiment-detection-jobs \
    --query 'SentimentDetectionJobPropertiesList[*].{Name:JobName,Status:JobStatus}'
```

### 3. Verify EventBridge Automation

```bash
# Upload a test file to trigger automated processing
echo "This is a test document for automated processing." > test-upload.txt
aws s3 cp test-upload.txt s3://comprehend-input-[suffix]/

# Check CloudWatch logs for Lambda execution
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/comprehend-processor"
```

## Customization

### Adding Custom Entity Recognition

1. **Prepare Training Data**: Create CSV files with entity annotations
2. **Update IAM Permissions**: Add entity recognizer permissions to the service role
3. **Modify Lambda Code**: Include custom entity recognition in processing pipeline
4. **Configure Training Job**: Set up entity recognizer training parameters

### Scaling Considerations

- **Lambda Concurrency**: Adjust reserved concurrency based on expected load
- **S3 Bucket Policies**: Configure lifecycle policies for cost optimization
- **Comprehend Quotas**: Monitor service limits and request increases if needed
- **EventBridge Rules**: Fine-tune event patterns for efficient processing

### Security Enhancements

- **VPC Configuration**: Deploy Lambda functions in private subnets
- **S3 Encryption**: Enable server-side encryption for sensitive data
- **KMS Integration**: Use customer-managed keys for advanced encryption
- **Access Logging**: Enable CloudTrail for API call auditing

## Monitoring and Observability

### CloudWatch Metrics
- Lambda function duration and error rates
- Comprehend job completion times
- S3 bucket object counts and sizes
- EventBridge rule invocation metrics

### Logging
- Lambda execution logs for debugging
- Comprehend job status and error logs
- S3 access logs for audit trails
- EventBridge event processing logs

### Alarms
- Lambda function errors and timeouts
- Comprehend job failures
- S3 bucket access violations
- Unusual processing patterns

## Cost Optimization

### Comprehend Costs
- Use batch processing for large datasets (more cost-effective than real-time)
- Monitor character counts to optimize pricing
- Implement text preprocessing to reduce redundant analysis

### Lambda Costs
- Optimize memory allocation based on performance testing
- Use provisioned concurrency only when necessary
- Implement efficient error handling to reduce retry costs

### S3 Costs
- Configure lifecycle policies to archive old results
- Use intelligent tiering for variable access patterns
- Monitor transfer costs for cross-region operations

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack --stack-name comprehend-nlp-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name comprehend-nlp-stack
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
# This removes all resources including S3 buckets and their contents
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
# This removes all managed resources
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# - Stop any running Comprehend jobs
# - Delete Lambda functions and roles
# - Remove EventBridge rules
# - Delete S3 buckets and contents
# - Clean up IAM roles and policies
```

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**
   - Verify service roles have correct policies attached
   - Check trust relationships for assume role permissions
   - Ensure cross-service permissions are properly configured

2. **Lambda Function Timeouts**
   - Increase function timeout for complex text processing
   - Monitor memory usage and adjust allocation
   - Implement proper error handling and retries

3. **Comprehend Job Failures**
   - Verify input data format and character encoding
   - Check S3 bucket permissions and access policies
   - Monitor service quotas and limits

4. **S3 Access Issues**
   - Confirm bucket policies allow service access
   - Verify object permissions and ownership
   - Check encryption settings compatibility

### Debugging Steps

1. **Check CloudWatch Logs**: Review function execution logs for errors
2. **Monitor CloudTrail**: Audit API calls for permission issues
3. **Test Components**: Isolate issues by testing individual services
4. **Verify Configurations**: Ensure all parameters are correctly set

## Performance Optimization

### Real-time Processing
- Implement connection pooling for Comprehend clients
- Use asynchronous processing for multiple text analysis tasks
- Cache frequently analyzed content to reduce API calls

### Batch Processing
- Optimize document batch sizes for efficiency
- Use parallel processing for large document collections
- Implement progressive result processing for long-running jobs

### Resource Allocation
- Monitor Lambda memory usage and optimize allocation
- Use reserved concurrency for predictable workloads
- Implement auto-scaling based on queue depth

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown for context
2. **AWS Documentation**: Consult service-specific documentation for configuration details
3. **Service Limits**: Review AWS service quotas and limits
4. **Best Practices**: Follow AWS Well-Architected Framework principles

### Useful Resources

- [Amazon Comprehend Developer Guide](https://docs.aws.amazon.com/comprehend/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

## Advanced Features

### Custom Classification Models
- Train document classifiers for business-specific categories
- Implement model versioning and A/B testing
- Monitor model performance and retrain as needed

### Multi-language Processing
- Configure language detection for automatic processing
- Implement language-specific processing pipelines
- Handle mixed-language documents appropriately

### Integration Patterns
- Connect with Amazon Translate for multi-language support
- Integrate with Amazon Textract for document processing
- Use Amazon Bedrock for advanced generative AI capabilities

This infrastructure provides a complete, production-ready NLP solution using Amazon Comprehend with proper security, monitoring, and scalability considerations.