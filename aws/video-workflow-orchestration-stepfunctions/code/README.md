# Infrastructure as Code for Video Workflow Orchestration with Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Video Workflow Orchestration with Step Functions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive video processing workflow using AWS Step Functions to orchestrate:

- **MediaConvert**: Video transcoding with multiple output formats (MP4, HLS, thumbnails)
- **Lambda Functions**: Metadata extraction, quality control, and content publishing
- **S3 Storage**: Source, output, and archive buckets with lifecycle management
- **DynamoDB**: Job tracking and audit trail storage
- **API Gateway**: HTTP API for programmatic workflow triggering
- **CloudWatch**: Comprehensive monitoring and alerting
- **SNS**: Notification system for workflow status updates

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Step Functions (full access)
  - MediaConvert (job creation and management)
  - Lambda (function creation and execution)
  - S3 (bucket creation and object management)
  - DynamoDB (table creation and item management)
  - API Gateway (API creation and deployment)
  - IAM (role and policy management)
  - CloudWatch (dashboard and log group creation)
  - SNS (topic creation and publishing)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)

### Estimated Costs

- **Development/Testing**: $50-150 per month
- **Production (1000 videos/month)**: $200-500 per month
- **MediaConvert**: $0.0045-0.072 per minute (varies by resolution)
- **Step Functions Express**: $1.00 per million state transitions
- **Lambda**: Pay per request and execution time
- **S3**: Storage costs vary by data volume and access patterns

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete workflow infrastructure
aws cloudformation create-stack \
    --stack-name video-workflow-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=prod \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
    
# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name video-workflow-stack \
    --query 'Stacks[0].StackStatus'
    
# Get workflow endpoints
aws cloudformation describe-stacks \
    --stack-name video-workflow-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the workflow stack
cdk deploy VideoWorkflowStack \
    --parameters notificationEmail=your-email@example.com

# Get deployment outputs
cdk list
cdk outputs VideoWorkflowStack
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the workflow stack
cdk deploy VideoWorkflowStack \
    -c notification_email=your-email@example.com

# Get deployment outputs
cdk list
cdk outputs VideoWorkflowStack
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="notification_email=your-email@example.com" \
    -var="environment=prod"

# Deploy infrastructure
terraform apply \
    -var="notification_email=your-email@example.com" \
    -var="environment=prod"

# Get output values
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export ENVIRONMENT="prod"

# Deploy the complete workflow
./scripts/deploy.sh

# Monitor deployment progress
./scripts/deploy.sh --status
```

## Configuration Options

### Environment Variables

```bash
# Required
export NOTIFICATION_EMAIL="your-email@example.com"

# Optional (with defaults)
export ENVIRONMENT="dev"                    # dev, staging, prod
export AWS_REGION="us-east-1"              # AWS region for deployment
export SOURCE_BUCKET_PREFIX="video-source" # S3 bucket naming prefix
export OUTPUT_BUCKET_PREFIX="video-output" # S3 bucket naming prefix
export ENABLE_MONITORING="true"            # Enable CloudWatch dashboard
export LAMBDA_TIMEOUT="300"                # Lambda timeout in seconds
export MEDIACONVERT_QUEUE="Default"        # MediaConvert queue name
```

### Terraform Variables

```hcl
# terraform.tfvars
notification_email = "your-email@example.com"
environment       = "prod"
aws_region        = "us-east-1"

# Optional advanced configuration
enable_versioning = true
enable_encryption = true
retention_days    = 90
```

### CDK Context Values

```json
{
  "notification_email": "your-email@example.com",
  "environment": "prod",
  "enable_monitoring": true,
  "lambda_memory_size": 1024,
  "workflow_type": "EXPRESS"
}
```

## Usage Examples

### 1. Automatic Video Processing (S3 Upload)

```bash
# Upload video to trigger automatic processing
aws s3 cp your-video.mp4 s3://[SOURCE_BUCKET_NAME]/

# Monitor workflow execution
aws stepfunctions list-executions \
    --state-machine-arn [STATE_MACHINE_ARN] \
    --max-results 5
```

### 2. API-Triggered Processing

```bash
# Get API endpoint from stack outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name video-workflow-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Trigger workflow via API
curl -X POST ${API_ENDPOINT}/start-workflow \
    -H "Content-Type: application/json" \
    -d '{
        "bucket": "[SOURCE_BUCKET_NAME]",
        "key": "path/to/your-video.mp4"
    }'
```

### 3. Batch Processing Multiple Videos

```bash
# Create batch processing script
cat > batch_process.sh << 'EOF'
#!/bin/bash
for video in videos/*.mp4; do
    echo "Processing: $video"
    aws s3 cp "$video" s3://[SOURCE_BUCKET_NAME]/batch/
    sleep 30  # Stagger uploads
done
EOF

chmod +x batch_process.sh
./batch_process.sh
```

### 4. Monitor Processing Results

```bash
# Check job status in DynamoDB
aws dynamodb scan \
    --table-name [JOBS_TABLE_NAME] \
    --filter-expression "JobStatus = :status" \
    --expression-attribute-values '{":status":{"S":"COMPLETED"}}' \
    --max-items 10

# List processed outputs
aws s3 ls s3://[OUTPUT_BUCKET_NAME]/ --recursive
```

## Monitoring and Troubleshooting

### CloudWatch Dashboard

Access the generated CloudWatch dashboard to monitor:
- Workflow execution rates and success/failure ratios
- MediaConvert job statistics and processing times
- Lambda function performance and error rates
- S3 bucket storage metrics and transfer rates

### Step Functions Console

Monitor workflow executions in the AWS Step Functions console:
- Visual workflow execution graphs
- Detailed state transition logs
- Error analysis and retry patterns
- Performance metrics and bottlenecks

### Common Issues and Solutions

#### 1. MediaConvert Job Failures

```bash
# Check MediaConvert job details
aws mediaconvert describe-job \
    --id [JOB_ID] \
    --endpoint [MEDIACONVERT_ENDPOINT]

# Common causes:
# - Invalid input file format
# - Insufficient IAM permissions
# - Output bucket access issues
```

#### 2. Lambda Function Timeouts

```bash
# Increase Lambda timeout via CloudFormation parameter
aws cloudformation update-stack \
    --stack-name video-workflow-stack \
    --use-previous-template \
    --parameters ParameterKey=LambdaTimeout,ParameterValue=600

# Monitor Lambda metrics
aws logs filter-log-events \
    --log-group-name /aws/lambda/[FUNCTION_NAME] \
    --filter-pattern "TIMEOUT"
```

#### 3. Workflow Execution Failures

```bash
# Get execution details
aws stepfunctions describe-execution \
    --execution-arn [EXECUTION_ARN]

# Check execution history
aws stepfunctions get-execution-history \
    --execution-arn [EXECUTION_ARN] \
    --max-results 20
```

## Performance Optimization

### High-Volume Processing

For processing thousands of videos:

1. **Use Standard Workflows** for complex jobs requiring longer execution times
2. **Implement Parallel Processing** by adjusting workflow concurrency limits
3. **Optimize MediaConvert Settings** based on content characteristics
4. **Use S3 Transfer Acceleration** for faster uploads

### Cost Optimization

1. **Implement S3 Lifecycle Policies** to archive processed content
2. **Use Spot Instances** for batch processing workloads
3. **Optimize MediaConvert Output Settings** based on delivery requirements
4. **Monitor and Alert** on unexpected cost spikes

## Security Considerations

### IAM Best Practices

- All IAM roles follow least privilege principle
- MediaConvert role has minimal S3 and SNS permissions
- Lambda execution roles are scoped to specific resources
- Cross-service permissions are explicitly defined

### Data Protection

- S3 buckets use server-side encryption (SSE-S3)
- Optional KMS encryption for sensitive content
- Bucket policies prevent unauthorized access
- VPC endpoints available for private networking

### Compliance Features

- CloudTrail integration for audit logging
- DynamoDB provides complete job audit trails
- Configurable retention policies for processed content
- Support for compliance requirements (SOX, HIPAA, etc.)

## Cleanup

### Using CloudFormation

```bash
# Delete the complete stack
aws cloudformation delete-stack \
    --stack-name video-workflow-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name video-workflow-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the workflow stack
cd cdk-typescript/  # or cdk-python/
cdk destroy VideoWorkflowStack

# Confirm deletion
cdk list
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="notification_email=your-email@example.com" \
    -var="environment=prod"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
./scripts/destroy.sh --verify
```

### Manual Cleanup (if needed)

```bash
# Remove S3 bucket contents (if not empty)
aws s3 rm s3://[SOURCE_BUCKET_NAME] --recursive
aws s3 rm s3://[OUTPUT_BUCKET_NAME] --recursive
aws s3 rm s3://[ARCHIVE_BUCKET_NAME] --recursive

# Delete CloudWatch log groups
aws logs delete-log-group \
    --log-group-name /aws/stepfunctions/video-workflow

# Remove any remaining Lambda log groups
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/video- \
    --query 'logGroups[].logGroupName' \
    --output text | xargs -I {} aws logs delete-log-group --log-group-name {}
```

## Advanced Configuration

### Custom MediaConvert Presets

```json
// Create custom MediaConvert preset
{
  "Name": "HighQuality1080p",
  "Settings": {
    "VideoDescription": {
      "Width": 1920,
      "Height": 1080,
      "CodecSettings": {
        "Codec": "H_264",
        "H264Settings": {
          "RateControlMode": "QVBR",
          "QvbrSettings": {
            "QvbrQualityLevel": 9
          },
          "MaxBitrate": 8000000
        }
      }
    }
  }
}
```

### Workflow Customization

Modify the Step Functions state machine definition to:
- Add additional processing steps
- Implement content-based routing
- Include external API integrations
- Add approval workflows for sensitive content

### Integration Patterns

- **Event-Driven**: Integrate with EventBridge for complex event routing
- **API Gateway**: Extend API with additional endpoints for status checking
- **SQS Integration**: Add queuing for high-volume batch processing
- **CloudFront**: Implement CDN distribution for processed content

## Support and Documentation

- **AWS Step Functions**: [User Guide](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html)
- **AWS MediaConvert**: [User Guide](https://docs.aws.amazon.com/mediaconvert/latest/ug/what-is.html)
- **AWS CDK**: [Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- **Terraform AWS Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the project repository.

## License

This infrastructure code is provided under the same license as the parent recipe repository.