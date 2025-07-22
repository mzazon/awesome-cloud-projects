# Infrastructure as Code for Automated Video Content Analysis with Rekognition

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Video Content Analysis with Rekognition".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated video content analysis pipeline using:

- **Amazon Rekognition**: For video content moderation and segment detection
- **AWS Step Functions**: For workflow orchestration
- **AWS Lambda**: For serverless processing functions
- **Amazon S3**: For video storage and results
- **Amazon DynamoDB**: For job tracking and metadata
- **Amazon SNS/SQS**: For event notifications
- **Amazon CloudWatch**: For monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate AWS permissions for:
  - Rekognition video analysis operations
  - Step Functions state machine creation
  - Lambda function deployment
  - S3 bucket management
  - DynamoDB table creation
  - IAM role and policy management
  - SNS/SQS resource creation
  - CloudWatch dashboard and alarm creation

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name video-analysis-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name video-analysis-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name video-analysis-stack \
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

# View deployed resources
cdk list
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
cdk deploy

# View deployed resources
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
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
./scripts/status.sh
```

## Testing the Solution

After deployment, test the video analysis pipeline:

```bash
# Upload a sample video to trigger analysis
aws s3 cp sample-video.mp4 s3://YOUR_SOURCE_BUCKET/

# Monitor Step Functions execution
aws stepfunctions list-executions \
    --state-machine-arn YOUR_STATE_MACHINE_ARN

# Check analysis results
aws dynamodb scan \
    --table-name YOUR_ANALYSIS_TABLE \
    --max-items 5

# View results in S3
aws s3 ls s3://YOUR_RESULTS_BUCKET/analysis-results/ --recursive
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Environment name (dev/staging/prod) | dev | Yes |
| MinConfidence | Minimum confidence for content moderation | 50.0 | No |
| RetentionDays | CloudWatch logs retention days | 30 | No |
| EnableDashboard | Create CloudWatch dashboard | true | No |

### CDK Configuration

Customize the deployment by modifying the configuration in:
- **TypeScript**: `cdk-typescript/lib/config.ts`
- **Python**: `cdk-python/config.py`

### Terraform Variables

Configure the deployment using `terraform.tfvars`:

```hcl
# terraform.tfvars
environment = "dev"
min_confidence = 50.0
retention_days = 30
enable_dashboard = true
allowed_video_formats = ["mp4", "avi", "mov", "mkv"]
```

## Monitoring and Alerts

The solution includes:

- **CloudWatch Dashboard**: Visualizes Lambda performance and Step Functions executions
- **CloudWatch Alarms**: Alerts on failed executions and high error rates
- **SNS Notifications**: Real-time alerts for analysis completion and failures
- **DynamoDB Metrics**: Tracks job processing status and performance

## Security Features

- **IAM Roles**: Least privilege access for all components
- **S3 Bucket Policies**: Secure access controls and SSL enforcement
- **VPC Endpoints**: Optional secure connectivity (in advanced configurations)
- **Encryption**: Data encrypted at rest and in transit
- **Resource Tagging**: Comprehensive tagging for governance

## Cost Optimization

- **Serverless Architecture**: Pay-per-use pricing model
- **S3 Lifecycle Policies**: Automatic transition to cheaper storage classes
- **DynamoDB On-Demand**: Automatic scaling based on usage
- **Lambda Optimizations**: Right-sized memory and timeout configurations

## Troubleshooting

### Common Issues

1. **Step Functions Execution Failures**
   ```bash
   # Check execution details
   aws stepfunctions describe-execution \
       --execution-arn YOUR_EXECUTION_ARN
   ```

2. **Lambda Function Errors**
   ```bash
   # View function logs
   aws logs tail /aws/lambda/YOUR_FUNCTION_NAME --follow
   ```

3. **Rekognition Job Failures**
   ```bash
   # Check job status
   aws rekognition get-content-moderation --job-id YOUR_JOB_ID
   ```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export DEBUG=true
export LOG_LEVEL=DEBUG
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name video-analysis-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name video-analysis-stack
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm cleanup
./scripts/status.sh
```

## Advanced Configuration

### Custom Content Moderation

To implement custom content moderation models:

1. Train custom labels using Amazon Rekognition Custom Labels
2. Update the Lambda function to use custom model ARN
3. Modify confidence thresholds based on model performance

### Multi-Region Deployment

For multi-region deployments:

1. Deploy infrastructure in multiple regions
2. Configure cross-region replication for S3 buckets
3. Set up DynamoDB Global Tables for metadata synchronization

### Integration with Content Delivery

To integrate with Amazon CloudFront:

1. Add CloudFront distribution to serve analyzed content
2. Configure origin access identity for S3 access
3. Set up cache behaviors based on content analysis results

## Performance Optimization

- **Lambda Concurrency**: Configure reserved concurrency for critical functions
- **Step Functions Express**: Use Express workflows for high-volume processing
- **S3 Transfer Acceleration**: Enable for faster global uploads
- **DynamoDB Provisioned Capacity**: Use for predictable workloads

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../video-content-analysis-aws-elemental-mediaanalyzer.md)
2. Review AWS service documentation:
   - [Amazon Rekognition Video](https://docs.aws.amazon.com/rekognition/latest/dg/video.html)
   - [AWS Step Functions](https://docs.aws.amazon.com/step-functions/)
   - [AWS Lambda](https://docs.aws.amazon.com/lambda/)
3. Consult provider-specific documentation for CloudFormation, CDK, or Terraform

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate with all supported IaC tools
3. Update documentation as needed
4. Follow AWS best practices and security guidelines

## License

This infrastructure code is provided under the same license as the original recipe documentation.