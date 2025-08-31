# AWS CDK Python - Resource Cleanup Automation

This AWS CDK Python application creates an automated resource cleanup system using AWS Lambda to identify and terminate EC2 instances based on specific tags, with SNS notifications to alert administrators about cleanup actions.

## Architecture Overview

The solution creates:
- **Lambda Function**: Automated cleanup logic for tagged EC2 instances
- **IAM Role**: Least-privilege permissions for Lambda execution
- **SNS Topic**: Notifications for cleanup actions and errors
- **CloudWatch Log Group**: Function logging with retention policy
- **CloudWatch Events Rule**: Optional scheduled execution

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Python 3.8 or later
- Node.js 18.x or later (for CDK CLI)
- AWS CDK v2 installed globally: `npm install -g aws-cdk`

### Required AWS Permissions

Your AWS credentials need the following permissions:
- Lambda: CreateFunction, UpdateFunction, DeleteFunction
- IAM: CreateRole, AttachRolePolicy, DeleteRole
- SNS: CreateTopic, Subscribe, DeleteTopic
- EC2: DescribeInstances, TerminateInstances (for the Lambda function)
- CloudWatch: CreateLogGroup, PutRetentionPolicy
- CloudFormation: Full access for stack management

## Quick Start

### 1. Environment Setup

```bash
# Clone or navigate to the CDK application directory
cd aws/simple-resource-cleanup-lambda-tags/code/cdk-python/

# Create a Python virtual environment
python3 -m venv .venv

# Activate the virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
# .venv\\Scripts\\activate.bat

# Install dependencies
pip install -r requirements.txt
```

### 2. CDK Bootstrap (First Time Only)

```bash
# Bootstrap CDK in your AWS account and region
cdk bootstrap

# Verify bootstrap
cdk doctor
```

### 3. Configuration Options

#### Option A: Environment Variables (Recommended)

```bash
# Set email address for notifications
export CLEANUP_EMAIL_ADDRESS="admin@example.com"

# Optional: Configure AWS profile and region
export AWS_PROFILE="your-profile"
export AWS_DEFAULT_REGION="us-east-1"
```

#### Option B: CDK Context

```bash
# Deploy with email address
cdk deploy -c email_address="admin@example.com"

# Deploy with scheduled cleanup enabled
cdk deploy -c email_address="admin@example.com" \
          -c enable_scheduled_cleanup=true \
          -c cleanup_schedule="rate(1 day)"
```

### 4. Deploy the Stack

```bash
# Preview the deployment
cdk diff

# Deploy the stack
cdk deploy

# Deploy with automatic approval (non-interactive)
cdk deploy --require-approval never
```

### 5. Confirm Email Subscription

After deployment, check your email inbox for an SNS subscription confirmation. Click the confirmation link to receive cleanup notifications.

## Usage

### Testing the Cleanup Function

1. **Create a test EC2 instance with the cleanup tag**:

```bash
# Launch a test instance
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type t2.micro \
    --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=test-cleanup},{Key=AutoCleanup,Value=true}]'
```

2. **Manually invoke the Lambda function**:

```bash
# Get the function name from CDK output
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name ResourceCleanupStack \
    --query 'Stacks[0].Outputs[?OutputKey==`CleanupFunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# View the response
cat response.json
```

### Enabling Scheduled Cleanup

To enable automatic daily cleanup, redeploy with scheduling enabled:

```bash
cdk deploy -c email_address="admin@example.com" \
          -c enable_scheduled_cleanup=true \
          -c cleanup_schedule="rate(1 day)"
```

**Schedule Examples**:
- `rate(1 day)` - Daily execution
- `rate(12 hours)` - Twice daily
- `cron(0 2 * * ? *)` - Daily at 2 AM UTC
- `cron(0 18 ? * MON-FRI *)` - Weekdays at 6 PM UTC

### Tagging Strategy

The Lambda function looks for EC2 instances with the following tag:
- **Key**: `AutoCleanup`
- **Value**: `true`, `True`, or `TRUE`

Only instances in `running` or `stopped` states will be terminated.

## Monitoring and Logs

### CloudWatch Logs

```bash
# View recent logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/resource-cleanup-function" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### SNS Notifications

You'll receive email notifications for:
- Successful cleanup operations (with instance details)
- No instances found for cleanup
- Error conditions with detailed information

## Configuration Options

### Stack Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `email_address` | Email for notifications | None | `admin@company.com` |
| `enable_scheduled_cleanup` | Enable automatic scheduling | `false` | `true` |
| `cleanup_schedule` | Schedule expression | `rate(1 day)` | `cron(0 2 * * ? *)` |

### Environment Variables

The Lambda function uses these environment variables:
- `SNS_TOPIC_ARN`: ARN of the notification topic
- `AWS_REGION`: Current AWS region

## Security Considerations

### IAM Permissions

The Lambda function has minimal required permissions:
- **EC2**: `DescribeInstances`, `TerminateInstances`, `DescribeTags`
- **SNS**: `Publish` (only to the specific topic)
- **CloudWatch**: Log creation and writing

### Safety Features

- Only terminates instances with explicit `AutoCleanup=true` tag
- Sends notifications for all actions (success and failure)
- Comprehensive error handling and logging
- No hardcoded credentials or resource ARNs

## Customization

### Extending the Cleanup Logic

To modify the cleanup criteria, edit the Lambda function code in `app.py`:

```python
# Current filter
response = ec2.describe_instances(
    Filters=[
        {
            'Name': 'tag:AutoCleanup',
            'Values': ['true', 'True', 'TRUE']
        },
        {
            'Name': 'instance-state-name',
            'Values': ['running', 'stopped']
        }
    ]
)
```

### Adding Additional Resource Types

Extend the function to handle other AWS resources:
- EBS volumes with specific tags
- RDS instances marked for cleanup
- Elastic Load Balancers
- Auto Scaling Groups

## Troubleshooting

### Common Issues

1. **Email not received**:
   - Check spam/junk folder
   - Verify email address is correct
   - Confirm SNS subscription in AWS Console

2. **Lambda function errors**:
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions
   - Ensure SNS topic exists and is accessible

3. **CDK deployment failures**:
   - Run `cdk doctor` to check configuration
   - Verify AWS credentials and permissions
   - Check for resource naming conflicts

### Debug Mode

Enable verbose logging:

```bash
# Deploy with debug context
cdk deploy --verbose

# View detailed CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name ResourceCleanupStack
```

## Cost Optimization

This solution follows AWS cost optimization best practices:

- **Lambda**: Pay-per-invocation, only charges for actual cleanup runs
- **SNS**: Minimal charges for notification delivery
- **CloudWatch**: 1-month log retention to balance cost and debugging needs

**Estimated monthly cost**: $0.50 - $2.00 (based on daily executions)

## Cleanup and Removal

### Remove the Stack

```bash
# Destroy all resources
cdk destroy

# Confirm destruction when prompted
# Type 'y' and press Enter
```

### Manual Cleanup (if needed)

If automatic cleanup fails:

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name ResourceCleanupStack

# Verify deletion
aws cloudformation describe-stacks --stack-name ResourceCleanupStack
```

## Best Practices

1. **Testing**: Always test with non-production instances first
2. **Monitoring**: Set up CloudWatch alarms for function errors
3. **Tagging**: Use consistent tagging strategies across your organization
4. **Scheduling**: Run cleanup during off-peak hours
5. **Notifications**: Include multiple team members in SNS subscriptions

## Contributing

To enhance this CDK application:

1. Fork the repository
2. Create a feature branch
3. Make your changes with appropriate tests
4. Submit a pull request

## License

This CDK application is provided under the Apache 2.0 License. See the LICENSE file for details.

## Support

For issues and questions:
- Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
- Review AWS Lambda best practices: https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html
- AWS Support (for AWS account holders)

## Additional Resources

- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS Tagging Best Practices](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html)
- [AWS Cost Optimization](https://aws.amazon.com/economics/)