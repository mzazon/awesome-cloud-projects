# Resource Cleanup Automation CDK TypeScript

This CDK TypeScript application creates an automated resource cleanup system using AWS Lambda and SNS notifications. The solution identifies and terminates EC2 instances based on specific tags, helping organizations reduce AWS costs by cleaning up forgotten or unused resources.

## Architecture

The CDK application deploys:

- **Lambda Function**: Identifies and terminates EC2 instances with specific tags
- **SNS Topic**: Sends notifications about cleanup actions
- **IAM Role**: Provides least privilege permissions for Lambda execution
- **CloudWatch Log Group**: Stores Lambda function logs
- **EventBridge Rule**: Optional scheduled execution (disabled by default)

## Prerequisites

Before deploying this application, ensure you have:

- AWS CLI installed and configured with appropriate permissions
- Node.js 18.0 or later
- AWS CDK 2.126.0 or later installed globally (`npm install -g aws-cdk`)
- TypeScript installed globally (`npm install -g typescript`)

## Required Permissions

Your AWS credentials need permissions for:

- Lambda (create, update, delete functions)
- SNS (create topics, subscriptions)
- IAM (create roles, attach policies)
- CloudWatch Logs (create log groups)
- EventBridge (create rules)
- EC2 (for Lambda function execution)

## Installation

1. **Clone and navigate to the project directory**:
   ```bash
   cd aws/simple-resource-cleanup-lambda-tags/code/cdk-typescript/
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Build the TypeScript code**:
   ```bash
   npm run build
   ```

## Configuration

The application accepts configuration through CDK context variables or environment variables:

### Via CDK Context (Recommended)

Create a `cdk.context.json` file:
```json
{
  "notificationEmail": "admin@example.com",
  "scheduleExpression": "cron(0 2 * * ? *)",
  "cleanupTagKey": "AutoCleanup",
  "cleanupTagValues": ["true", "True", "TRUE"]
}
```

### Via Environment Variables

```bash
export NOTIFICATION_EMAIL="admin@example.com"
export SCHEDULE_EXPRESSION="cron(0 2 * * ? *)"
export CLEANUP_TAG_KEY="AutoCleanup"
export CLEANUP_TAG_VALUES="true,True,TRUE"
```

### Via CDK Deploy Command

```bash
cdk deploy --context notificationEmail=admin@example.com \
           --context scheduleExpression="cron(0 2 * * ? *)" \
           --context cleanupTagKey=AutoCleanup
```

## Bootstrap (First Time Only)

If you haven't used CDK in your AWS account/region before:

```bash
cdk bootstrap
```

## Deployment

### Quick Deployment

```bash
npm run deploy
```

### Guided Deployment (Recommended for first deployment)

```bash
npm run deploy:guided
```

### Manual Steps

1. **Synthesize CloudFormation template**:
   ```bash
   npm run synth
   ```

2. **Review differences** (for updates):
   ```bash
   npm run diff
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

## Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `notificationEmail` | None | Email address for cleanup notifications |
| `scheduleExpression` | `cron(0 2 * * ? *)` | CloudWatch Events rule schedule |
| `cleanupTagKey` | `'AutoCleanup'` | Tag key to identify resources for cleanup |
| `cleanupTagValues` | `['true', 'True', 'TRUE']` | Tag values that trigger cleanup |

### Schedule Expression Examples

- Daily at 2 AM UTC: `cron(0 2 * * ? *)`
- Weekdays at 6 PM UTC: `cron(0 18 ? * MON-FRI *)`
- Every 6 hours: `rate(6 hours)`
- Weekly on Sunday: `cron(0 0 ? * SUN *)`

## Usage

### Manual Testing

After deployment, test the Lambda function manually:

```bash
# Get the function name from the CDK output
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

### Create Test Instance

Create a test EC2 instance with the cleanup tag:

```bash
# Get the latest Amazon Linux 2023 AMI ID
LATEST_AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query 'Parameter.Value' --output text)

# Launch test instance with cleanup tag
aws ec2 run-instances \
  --image-id $LATEST_AMI_ID \
  --instance-type t2.micro \
  --tag-specifications \
  "ResourceType=instance,Tags=[{Key=Name,Value=test-cleanup-instance},{Key=AutoCleanup,Value=true}]"
```

### Enable Scheduled Cleanup

The EventBridge rule is disabled by default for safety. To enable it:

```bash
# Get the rule name from CDK output
RULE_NAME=$(aws cloudformation describe-stacks \
  --stack-name ResourceCleanupStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ScheduleRuleName`].OutputValue' \
  --output text)

# Enable the rule
aws events enable-rule --name $RULE_NAME
```

### Monitor Execution

View Lambda function logs:

```bash
# Get log group name
LOG_GROUP=$(aws cloudformation describe-stacks \
  --stack-name ResourceCleanupStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
  --output text)

# View recent logs
aws logs filter-log-events \
  --log-group-name $LOG_GROUP \
  --start-time $(date -d '1 hour ago' +%s)000
```

## Email Subscription

If you provided a notification email during deployment:

1. Check your email inbox for a subscription confirmation
2. Click the "Confirm subscription" link
3. You'll receive notifications when cleanup actions occur

To add additional email subscriptions:

```bash
# Get SNS topic ARN from CDK output
TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name ResourceCleanupStack \
  --query 'Stacks[0].Outputs[?OutputKey==`NotificationTopicArn`].OutputValue' \
  --output text)

# Subscribe additional email
aws sns subscribe \
  --topic-arn $TOPIC_ARN \
  --protocol email \
  --notification-endpoint new-admin@example.com
```

## Development

### Code Formatting and Linting

```bash
# Format code
npm run format

# Check formatting
npm run format:check

# Lint code
npm run lint

# Fix linting issues
npm run lint:fix
```

### Testing

```bash
# Run tests
npm test

# Watch mode
npm run test:watch
```

### Build and Watch

```bash
# Build once
npm run build

# Watch for changes
npm run watch
```

## Cost Considerations

This solution incurs minimal costs:

- **Lambda**: Pay per invocation (~$0.0000002 per request)
- **SNS**: ~$0.50 per million notifications
- **CloudWatch Logs**: ~$0.50/GB ingested
- **EventBridge**: ~$1.00 per million events

Estimated monthly cost: **$0.50 - $2.00** (depending on usage)

## Security Best Practices

The CDK application implements security best practices:

- **Least Privilege IAM**: Lambda role has minimal required permissions
- **Resource-specific Permissions**: SNS policy restricted to specific topic
- **No Hardcoded Secrets**: All configuration via environment variables
- **CloudWatch Logging**: Full audit trail of all actions
- **Concurrency Limits**: Prevents multiple simultaneous executions

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**:
   - Ensure your AWS credentials have sufficient permissions
   - Check the Lambda execution role has correct policies

2. **Email Notifications Not Received**:
   - Confirm email subscription in SNS console
   - Check spam/junk folders
   - Verify email address in deployment configuration

3. **Lambda Timeout**:
   - Check CloudWatch logs for details
   - Consider increasing timeout in `app.ts`

4. **No Instances Found**:
   - Verify instances have the correct tag key and values
   - Check instance states (must be 'running' or 'stopped')

### Debug Mode

Enable debug logging by setting environment variable:

```bash
export CDK_DEBUG=true
npm run deploy
```

### View Stack Resources

```bash
# List all resources in the stack
aws cloudformation describe-stack-resources \
  --stack-name ResourceCleanupStack
```

## Cleanup

To remove all resources created by this CDK application:

```bash
npm run destroy
```

Or manually:

```bash
cdk destroy
```

> **Warning**: This will permanently delete the Lambda function, SNS topic, and all associated resources. Email subscriptions will be automatically removed.

## Customization

### Extending to Other Resource Types

Modify the Lambda function code in `app.ts` to support additional AWS resources:

```typescript
// Add RDS instance cleanup
const rdsResponse = await rds.describeDBInstances({
  Filters: [
    {
      Name: `tag:${cleanupTagKey}`,
      Values: cleanupTagValues
    }
  ]
}).promise();
```

### Adding Approval Workflow

Integrate with AWS Step Functions for approval workflows:

```typescript
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';

// Add Step Functions state machine for approval workflow
```

### Multi-Region Support

Deploy the stack to multiple regions:

```bash
cdk deploy --context region=us-west-2
cdk deploy --context region=eu-west-1
```

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review CloudWatch logs for Lambda execution details
3. Consult the original recipe documentation
4. Open an issue in the project repository

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.