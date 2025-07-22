# Intelligent Content Moderation with Amazon Bedrock and EventBridge

This CDK TypeScript application deploys a comprehensive content moderation system that leverages Amazon Bedrock's AI capabilities and EventBridge for event-driven workflows.

## Architecture Overview

The solution provides:

- **Automated Content Analysis**: Uses Amazon Bedrock Claude models to analyze uploaded content
- **Event-Driven Processing**: Leverages EventBridge for decoupled workflow orchestration
- **Multi-Stage Workflow**: Handles approved, rejected, and review workflows
- **Comprehensive Notifications**: SNS-based notifications for all moderation decisions
- **Security & Compliance**: Implements Bedrock Guardrails and proper IAM controls

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ installed
- CDK CLI installed (`npm install -g aws-cdk`)
- Amazon Bedrock model access enabled for Anthropic Claude models

## Installation

1. Install dependencies:
```bash
npm install
```

2. Bootstrap CDK (if not already done):
```bash
cdk bootstrap
```

## Configuration

### Environment Variables

You can configure the stack using CDK context variables:

```bash
# Set notification email
cdk deploy -c notificationEmail=your-email@example.com

# Set resource prefix
cdk deploy -c resourcePrefix=my-content-mod

# Set environment
cdk deploy -c environment=production
```

### Bedrock Model Access

Before deploying, ensure you have access to Anthropic Claude models in Amazon Bedrock:

1. Go to the AWS Console → Amazon Bedrock
2. Navigate to "Model access" in the left sidebar
3. Request access to "Anthropic Claude" models
4. Wait for approval (usually immediate for most regions)

## Deployment

### Quick Deploy

```bash
# Deploy with default settings
cdk deploy

# Deploy with custom email
cdk deploy -c notificationEmail=admin@mycompany.com
```

### Advanced Deploy

```bash
# Deploy with custom configuration
cdk deploy \\
  -c notificationEmail=admin@mycompany.com \\
  -c resourcePrefix=content-mod \\
  -c environment=production
```

## Usage

### Upload Content for Moderation

1. Upload text files (.txt) to the content bucket:
```bash
aws s3 cp sample-content.txt s3://CONTENT_BUCKET_NAME/
```

2. The system will automatically:
   - Analyze the content using Bedrock Claude
   - Route the content based on moderation decision
   - Send notifications about the decision
   - Store processed content in appropriate buckets

### Monitor Processing

- **CloudWatch Logs**: View Lambda function logs for processing details
- **Email Notifications**: Receive SNS notifications for all moderation decisions
- **S3 Buckets**: Check approved/rejected buckets for processed content

## Stack Resources

### Core Infrastructure

- **S3 Buckets**: Content upload, approved content, rejected content
- **EventBridge**: Custom event bus for workflow orchestration
- **SNS Topic**: Notification delivery
- **Bedrock Guardrails**: Enhanced content safety filtering

### Lambda Functions

- **Content Analysis**: Processes uploaded content using Bedrock Claude
- **Approved Handler**: Manages approved content workflow
- **Rejected Handler**: Manages rejected content workflow
- **Review Handler**: Manages content requiring human review

### Security & Compliance

- **IAM Roles**: Least-privilege access for all components
- **Encryption**: S3 server-side encryption for all buckets
- **VPC**: Optional VPC deployment for enhanced security
- **Monitoring**: CloudWatch logs and metrics

## Testing

### Unit Tests

```bash
npm test
```

### Integration Testing

1. Deploy the stack
2. Upload test content files
3. Monitor CloudWatch logs and SNS notifications
4. Verify content appears in appropriate buckets

### Sample Test Content

```bash
# Create test files
echo "This is a great product review!" > positive-content.txt
echo "This content contains inappropriate language" > negative-content.txt
echo "This is neutral content for testing" > neutral-content.txt

# Upload for testing
aws s3 cp positive-content.txt s3://YOUR_CONTENT_BUCKET/
aws s3 cp negative-content.txt s3://YOUR_CONTENT_BUCKET/
aws s3 cp neutral-content.txt s3://YOUR_CONTENT_BUCKET/
```

## Monitoring & Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:
```bash
aws logs tail /aws/lambda/content-moderation-content-analysis --follow
aws logs tail /aws/lambda/content-moderation-approved-handler --follow
aws logs tail /aws/lambda/content-moderation-rejected-handler --follow
aws logs tail /aws/lambda/content-moderation-review-handler --follow
```

### Common Issues

1. **Bedrock Access Denied**: Ensure Claude model access is enabled
2. **SNS Subscription**: Check email for SNS subscription confirmation
3. **Lambda Timeouts**: Adjust timeout settings for large content files
4. **S3 Permissions**: Verify IAM roles have proper S3 access

## Customization

### Moderation Criteria

Edit the content analysis Lambda function to customize:
- Moderation prompt for different content types
- Confidence thresholds for decisions
- Additional content categories

### Workflow Logic

Modify workflow handlers to implement:
- Custom approval processes
- Integration with external systems
- Additional notification channels

### Guardrails Configuration

Update Bedrock Guardrails settings:
- Content filter strengths
- Topic restrictions
- PII handling policies

## Cost Optimization

- **S3 Lifecycle**: Automated tiering for cost optimization
- **Lambda Memory**: Right-sized memory allocation
- **Bedrock Usage**: Monitor token consumption
- **Log Retention**: Configured for one week retention

## Security Best Practices

- **IAM Roles**: Least-privilege access patterns
- **Encryption**: Server-side encryption for all data
- **Network Security**: VPC deployment options
- **Audit Logging**: Comprehensive audit trails

## Cleanup

```bash
# Delete the stack
cdk destroy

# Clean up CDK bootstrap (optional)
aws cloudformation delete-stack --stack-name CDKToolkit
```

## Support

For issues and questions:
- Check CloudWatch logs for detailed error messages
- Review IAM permissions for access issues
- Verify Bedrock model access and quotas
- Monitor SNS topic subscriptions

## License

This project is licensed under the MIT License - see the LICENSE file for details.