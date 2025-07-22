# Infrastructure as Code for Intelligent Content Moderation with Bedrock

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Content Moderation with Bedrock".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate IAM permissions for creating:
  - Lambda functions
  - S3 buckets
  - EventBridge custom buses and rules
  - SNS topics
  - IAM roles and policies
  - Amazon Bedrock model access (Anthropic Claude models)
- Amazon Bedrock model access enabled for Anthropic Claude models
- Email address for SNS notifications (optional)
- Estimated cost: $0.50-2.00 per hour for testing (varies based on content volume and model usage)

> **Important**: Amazon Bedrock requires explicit model access approval. Enable access through the AWS console under Bedrock > Model access before deployment.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name content-moderation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name content-moderation-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name content-moderation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure notification email (optional)
export NOTIFICATION_EMAIL="your-email@example.com"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure notification email (optional)
export NOTIFICATION_EMAIL="your-email@example.com"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan deployment
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

# Follow the prompts to configure:
# - AWS region
# - Notification email
# - Resource naming preferences
```

## Testing the Solution

After deployment, test the content moderation system:

1. **Upload test content to the content bucket:**
   ```bash
   # Get bucket name from outputs
   CONTENT_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name content-moderation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ContentBucket`].OutputValue' \
       --output text)
   
   # Create test files
   echo "This is a great product review. I love this item and recommend it to everyone!" > positive-content.txt
   echo "I hate this stupid product and the people who made it are complete idiots!" > negative-content.txt
   echo "This product is okay. Nothing special but it works fine for basic use." > neutral-content.txt
   
   # Upload test content
   aws s3 cp positive-content.txt s3://$CONTENT_BUCKET/
   aws s3 cp negative-content.txt s3://$CONTENT_BUCKET/
   aws s3 cp neutral-content.txt s3://$CONTENT_BUCKET/
   ```

2. **Monitor processing:**
   ```bash
   # Check CloudWatch logs
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/ContentAnalysis"
   
   # Check approved content bucket
   APPROVED_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name content-moderation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ApprovedBucket`].OutputValue' \
       --output text)
   aws s3 ls s3://$APPROVED_BUCKET/approved/ --recursive
   
   # Check rejected content bucket
   REJECTED_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name content-moderation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`RejectedBucket`].OutputValue' \
       --output text)
   aws s3 ls s3://$REJECTED_BUCKET/ --recursive
   ```

3. **Review notifications:**
   - Check your email for moderation decision notifications
   - Monitor SNS topic for delivery status

## Configuration Options

### CloudFormation Parameters
- `NotificationEmail`: Email address for moderation notifications
- `ContentBucketName`: Custom name for content upload bucket (optional)
- `Region`: AWS region for deployment

### CDK Configuration
Configure via environment variables:
```bash
export NOTIFICATION_EMAIL="your-email@example.com"
export CONTENT_BUCKET_NAME="my-content-bucket"  # Optional
export AWS_REGION="us-east-1"  # Optional
```

### Terraform Variables
Edit `terraform.tfvars`:
```hcl
notification_email = "your-email@example.com"
content_bucket_name = "my-content-bucket"  # Optional
aws_region = "us-east-1"
environment = "dev"
```

### Bash Script Configuration
The deployment script will prompt for:
- AWS region selection
- Notification email address
- Custom resource naming preferences
- Bedrock model access confirmation

## Architecture Components

The infrastructure creates:

1. **S3 Buckets**: Content upload, approved content, and rejected content storage
2. **Lambda Functions**: Content analysis, approval handler, rejection handler, review handler
3. **EventBridge**: Custom event bus and routing rules for moderation workflows
4. **SNS Topic**: Notifications for moderation decisions
5. **IAM Roles**: Least-privilege access for Lambda functions
6. **Bedrock Guardrails**: Enhanced AI safety and content filtering

## Security Features

- **Encryption**: All S3 buckets use AES-256 encryption
- **IAM Roles**: Least-privilege access with specific resource permissions
- **Bedrock Guardrails**: Multi-layer content filtering and safety controls
- **VPC Support**: Optional VPC deployment for enhanced network security
- **Audit Logging**: CloudWatch logs for all moderation decisions

## Monitoring and Troubleshooting

### CloudWatch Metrics
Monitor key metrics:
- Lambda function invocations and errors
- S3 bucket object counts
- EventBridge rule executions
- SNS message delivery status

### Common Issues
1. **Bedrock Access**: Ensure model access is enabled in Bedrock console
2. **Permissions**: Verify IAM roles have necessary permissions
3. **Email Notifications**: Check SNS subscription confirmation
4. **Content Format**: Ensure uploaded files have .txt extension

### Debugging Commands
```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# View recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/ContentAnalysisFunction" \
    --start-time $(date -d "1 hour ago" +%s)000

# Check EventBridge rules
aws events list-rules --event-bus-name content-moderation-bus

# Verify SNS subscriptions
aws sns list-subscriptions-by-topic --topic-arn <SNS_TOPIC_ARN>
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name content-moderation-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name content-moderation-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Moderation Logic
To customize the AI moderation logic:
1. Modify the prompt template in the Lambda function code
2. Adjust confidence thresholds for decision routing
3. Add custom content categories or policies
4. Configure Bedrock guardrails for specific requirements

### Workflow Extensions
Extend the solution by:
1. Adding image/video analysis with Amazon Rekognition
2. Implementing human review workflows with Amazon A2I
3. Creating custom dashboards with Amazon QuickSight
4. Adding content appeal processes
5. Integrating with external moderation services

### Performance Optimization
- Adjust Lambda memory and timeout settings
- Implement batch processing for high-volume scenarios
- Use S3 Transfer Acceleration for global content uploads
- Configure EventBridge archive and replay for workflow testing

## Cost Optimization

- **Lambda**: Pay-per-request pricing, optimize memory allocation
- **Bedrock**: Monitor model invocation costs, implement batching
- **S3**: Use intelligent tiering for processed content
- **EventBridge**: Minimal cost for event routing
- **SNS**: Low cost for notification delivery

### Cost Monitoring
```bash
# Set up billing alerts
aws budgets create-budget \
    --account-id $AWS_ACCOUNT_ID \
    --budget file://budget-config.json

# Monitor Bedrock usage
aws bedrock get-model-invocation-metrics \
    --model-id anthropic.claude-3-sonnet-20240229-v1:0
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service status and limits
3. Verify Bedrock model access and quotas
4. Consult AWS documentation for specific services
5. Review CloudWatch logs for error details

## License

This infrastructure code is provided under the same license as the original recipe.