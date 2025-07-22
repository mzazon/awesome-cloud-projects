# Infrastructure as Code for AI Content Moderation with Bedrock

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Content Moderation with Bedrock".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an intelligent content moderation system that:

- Automatically analyzes uploaded content using Amazon Bedrock's Claude models
- Routes moderation decisions through Amazon EventBridge custom event bus
- Processes approved, rejected, and flagged content through dedicated workflows
- Provides real-time notifications via Amazon SNS
- Implements Bedrock Guardrails for enhanced AI safety

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon S3 (bucket creation and management)
  - AWS Lambda (function creation and execution)
  - Amazon Bedrock (model access and guardrail management)
  - Amazon EventBridge (custom bus and rule management)
  - Amazon SNS (topic management and publishing)
  - IAM (role and policy management)
- Amazon Bedrock model access enabled for Anthropic Claude models
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)

> **Important**: Request access to Amazon Bedrock Claude models through the AWS console under Bedrock > Model access before deployment.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name content-moderation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment status
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
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
npx cdk describe
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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
cdk describe
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment outputs
cat deployment-outputs.json
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| NotificationEmail | Email address for SNS notifications | - | Yes |
| Environment | Environment name for resource tagging | dev | No |
| ContentBucketPrefix | Prefix for content S3 bucket names | content-moderation | No |

### CDK Configuration

The CDK implementations support the same parameters through context variables or command-line parameters:

```bash
# Using context
npx cdk deploy -c notificationEmail=your-email@example.com -c environment=prod

# Using parameters
npx cdk deploy --parameters notificationEmail=your-email@example.com
```

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| notification_email | Email address for SNS notifications | string | - | Yes |
| region | AWS region for deployment | string | us-east-1 | No |
| environment | Environment name for resource tagging | string | dev | No |
| content_bucket_prefix | Prefix for content S3 bucket names | string | content-moderation | No |

## Testing the Deployment

After successful deployment, test the content moderation system:

1. **Upload test content**:
   ```bash
   # Get the content bucket name from outputs
   CONTENT_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name content-moderation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ContentBucketName`].OutputValue' \
       --output text)
   
   # Create test files
   echo "This is a great product review. I love this item!" > positive-content.txt
   echo "This product is okay. Nothing special but it works fine." > neutral-content.txt
   
   # Upload test content
   aws s3 cp positive-content.txt s3://${CONTENT_BUCKET}/
   aws s3 cp neutral-content.txt s3://${CONTENT_BUCKET}/
   ```

2. **Monitor processing**:
   ```bash
   # Check Lambda logs
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/ContentAnalysis"
   
   # Check processed content buckets
   aws s3 ls s3://$(aws cloudformation describe-stacks \
       --stack-name content-moderation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ApprovedBucketName`].OutputValue' \
       --output text)/approved/ --recursive
   ```

3. **Verify notifications**:
   - Check your email for SNS notifications about moderation decisions
   - Review CloudWatch Logs for function execution details

## Monitoring and Observability

The deployed infrastructure includes comprehensive monitoring:

- **CloudWatch Logs**: All Lambda functions log execution details
- **CloudWatch Metrics**: Function invocation and error metrics
- **SNS Notifications**: Real-time alerts for moderation decisions
- **EventBridge Metrics**: Event processing statistics

Access monitoring dashboards:

```bash
# View recent Lambda logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/ContentAnalysisFunction \
    --start-time $(date -d '1 hour ago' +%s)000

# Check EventBridge rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --dimensions Name=RuleName,Value=approved-content-rule \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cost Optimization

To optimize costs for this solution:

1. **Bedrock Usage**: Monitor model invocation costs through CloudWatch
2. **Lambda Optimization**: Functions are configured with appropriate memory allocation
3. **S3 Storage**: Configure lifecycle policies for processed content
4. **EventBridge**: Custom bus usage is included in base pricing

Estimated monthly costs (based on 1,000 content items/day):
- Amazon Bedrock: $5-15 (varies by model usage)
- AWS Lambda: $2-5
- Amazon S3: $1-3
- EventBridge: $1
- SNS: $0.50

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for all Lambda functions
- **S3 Encryption**: Server-side encryption enabled on all buckets
- **VPC**: Optional VPC deployment for enhanced isolation
- **Bedrock Guardrails**: AI safety controls configured
- **Event Filtering**: EventBridge rules restrict event processing

## Troubleshooting

### Common Issues

1. **Bedrock Model Access Denied**:
   - Ensure Claude model access is enabled in Bedrock console
   - Verify IAM permissions include bedrock:InvokeModel

2. **Lambda Function Timeouts**:
   - Check CloudWatch Logs for execution details
   - Verify Bedrock service availability in your region

3. **S3 Event Notifications Not Triggering**:
   - Verify Lambda function permissions for S3 invocation
   - Check S3 bucket notification configuration

4. **EventBridge Rules Not Firing**:
   - Verify custom event bus exists and rules are enabled
   - Check event pattern matching in rule definitions

### Debug Commands

```bash
# Check Bedrock model access
aws bedrock list-foundation-models --region ${AWS_REGION}

# Verify Lambda function configuration
aws lambda get-function --function-name ContentAnalysisFunction

# Test EventBridge rule
aws events test-event-pattern \
    --event-pattern file://test-event-pattern.json \
    --event file://test-event.json
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
cd cdk-typescript/  # or cdk-python/
npx cdk destroy     # or cdk destroy for Python
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources:

```bash
# Empty S3 buckets before deletion
aws s3 rm s3://your-content-bucket --recursive
aws s3 rm s3://your-approved-bucket --recursive
aws s3 rm s3://your-rejected-bucket --recursive

# Delete Bedrock guardrail
aws bedrock delete-guardrail --guardrail-identifier your-guardrail-id

# Remove any remaining Lambda functions
aws lambda delete-function --function-name ContentAnalysisFunction
```

## Customization

### Adding Custom Moderation Logic

1. **Modify Lambda Function Code**: Update the content analysis logic in the Lambda function
2. **Custom Guardrails**: Configure additional Bedrock Guardrails for specific policies
3. **Workflow Extensions**: Add new EventBridge rules for additional processing workflows

### Integration with Existing Systems

1. **API Gateway Integration**: Add REST API endpoints for programmatic content submission
2. **Database Integration**: Store moderation results in DynamoDB or RDS
3. **Workflow Orchestration**: Integrate with Step Functions for complex approval workflows

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check AWS service documentation for specific configurations
3. Verify IAM permissions and service limits
4. Review CloudWatch Logs for detailed error information

## Additional Resources

- [Amazon Bedrock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Content Moderation Best Practices](https://aws.amazon.com/blogs/machine-learning/)