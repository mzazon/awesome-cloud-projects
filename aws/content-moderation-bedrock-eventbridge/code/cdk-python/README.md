# Content Moderation CDK Python Application

This directory contains a complete AWS CDK Python implementation for the intelligent content moderation system using Amazon Bedrock and EventBridge.

## Architecture Overview

This CDK application deploys the following AWS resources:

- **S3 Buckets**: Content storage for uploaded, approved, and rejected content
- **Lambda Functions**: Content analysis using Bedrock and workflow processing
- **EventBridge**: Custom bus for event-driven routing of moderation decisions
- **SNS Topic**: Notifications for moderation results
- **IAM Roles**: Least privilege security with appropriate permissions
- **Bedrock Guardrails**: Enhanced AI safety and content filtering

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **AWS CDK v2** installed (`npm install -g aws-cdk`)
3. **Python 3.8+** with pip
4. **Amazon Bedrock** model access enabled for Anthropic Claude models
5. **CDK Bootstrap** completed in your target account/region

### Bedrock Model Access

⚠️ **Important**: You must request access to Anthropic Claude models in Amazon Bedrock before deployment:

1. Navigate to the AWS Bedrock console
2. Go to "Model access" in the left sidebar
3. Request access to Anthropic Claude models
4. Wait for approval (usually takes a few minutes)

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/building-intelligent-content-moderation-amazon-bedrock-eventbridge/code/cdk-python/
   ```

2. **Create and activate a virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Deployment

### Quick Deployment

1. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm deployment** when prompted

### Custom Configuration

You can customize the deployment by providing context variables:

```bash
cdk deploy -c notification_email=your-email@example.com
```

### Deployment Output

After successful deployment, the stack will output:

- Content bucket name for uploading files
- Approved and rejected content bucket names
- EventBridge bus name
- SNS topic ARN
- Bedrock Guardrail ID

## Usage

### Testing Content Moderation

1. **Upload a text file** to the content bucket:
   ```bash
   # Get the bucket name from stack outputs
   CONTENT_BUCKET=$(aws cloudformation describe-stacks \
     --stack-name ContentModerationStack \
     --query 'Stacks[0].Outputs[?OutputKey==`ContentBucketName`].OutputValue' \
     --output text)
   
   # Create and upload test content
   echo "This is a great product review!" > test-content.txt
   aws s3 cp test-content.txt s3://${CONTENT_BUCKET}/
   ```

2. **Monitor processing**:
   - Check CloudWatch Logs for Lambda function execution
   - Check your email for SNS notifications
   - Check approved/rejected buckets for processed content

### Monitoring

- **CloudWatch Logs**: Monitor Lambda function execution and errors
- **CloudWatch Metrics**: Track Lambda invocations, duration, and errors
- **X-Ray Tracing**: Enabled for Lambda functions for detailed tracing
- **SNS Notifications**: Real-time alerts for moderation decisions

## Development

### Local Development

1. **Install development dependencies**:
   ```bash
   pip install -r requirements.txt[dev]
   ```

2. **Run type checking**:
   ```bash
   mypy app.py
   ```

3. **Format code**:
   ```bash
   black app.py
   isort app.py
   ```

4. **Run linting**:
   ```bash
   flake8 app.py
   ```

### Testing Changes

1. **Synthesize CloudFormation template**:
   ```bash
   cdk synth
   ```

2. **Compare changes**:
   ```bash
   cdk diff
   ```

3. **Deploy changes**:
   ```bash
   cdk deploy
   ```

## Customization

### Modifying Content Analysis Logic

The content analysis Lambda function code is embedded in the `_get_content_analysis_code()` method. You can modify the prompt, model parameters, or decision logic by editing this method.

### Adding New Workflow Types

To add new content workflow types:

1. Create a new handler function method (similar to `_create_approved_handler_function()`)
2. Add a new EventBridge rule in `_create_eventbridge_rules()`
3. Update the event pattern to match your new decision type

### Changing Bedrock Guardrails

Modify the `_create_bedrock_guardrail()` method to adjust:
- Content filter strengths
- Topic restrictions
- PII handling rules
- Custom messaging

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Roles have minimal required permissions
- **Encryption**: S3 buckets use server-side encryption
- **VPC Isolation**: Can be deployed in VPC for additional network security
- **Secure Transport**: S3 bucket policies deny insecure connections
- **Content Filtering**: Multiple layers of content safety validation

## Cost Optimization

- **Serverless Architecture**: Pay only for actual usage
- **S3 Lifecycle Rules**: Automatic cleanup of old content versions
- **Lambda Memory Sizing**: Optimized for cost-performance balance
- **EventBridge**: Cost-effective event routing

## Troubleshooting

### Common Issues

1. **Bedrock Access Denied**:
   - Ensure Claude model access is enabled in Bedrock console
   - Check IAM permissions for Bedrock actions

2. **Lambda Timeout**:
   - Increase timeout in Lambda function configuration
   - Optimize content processing logic

3. **S3 Access Denied**:
   - Verify IAM roles have correct S3 permissions
   - Check bucket policies

4. **EventBridge Rules Not Triggering**:
   - Verify event patterns match exactly
   - Check Lambda function permissions for EventBridge invocation

### Debugging

1. **Check CloudWatch Logs**:
   ```bash
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/content-moderation"
   ```

2. **Test Lambda Functions Directly**:
   ```bash
   aws lambda invoke \
     --function-name content-moderation-content-analysis \
     --payload file://test-event.json \
     response.json
   ```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
cdk destroy
```

Confirm the deletion when prompted. This will remove all AWS resources created by the stack.

## Support

For issues related to this implementation:

1. Check the troubleshooting section above
2. Review CloudWatch Logs for error details
3. Consult the AWS CDK documentation
4. Review the original recipe documentation

## License

This code is provided under the Apache License 2.0. See the LICENSE file for details.