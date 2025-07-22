# Business Notifications CDK Python Application

This AWS CDK application creates a serverless notification system using EventBridge Scheduler and Amazon SNS to automatically send business notifications on predefined schedules.

## Architecture

The solution creates:
- **SNS Topic**: Central hub for business notifications with email subscriptions
- **EventBridge Scheduler**: Precise scheduling with cron expressions and flexible time windows  
- **IAM Role**: Least privilege execution role for scheduler to publish to SNS
- **Schedule Group**: Logical organization for related business schedules
- **Multiple Schedules**: Daily (weekdays 9 AM), weekly (Monday 8 AM), monthly (1st at 10 AM)

## Prerequisites

- Python 3.8 or higher
- AWS CLI installed and configured
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions to create EventBridge, SNS, and IAM resources

## Quick Start

### 1. Install Dependencies

```bash
# Create and activate virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Deploy with Email Notification

```bash
# Deploy with your email address for notifications
cdk deploy -c notification_email=your.email@company.com

# Or set in cdk.json context and deploy
cdk deploy
```

### 4. Confirm Email Subscription

After deployment, check your email and confirm the SNS subscription to start receiving notifications.

## Configuration Options

### Environment Variables

You can configure the application using CDK context:

```bash
# Custom timezone
cdk deploy -c timezone="UTC"

# Custom environment tag  
cdk deploy -c environment="staging"

# Multiple options
cdk deploy -c notification_email=admin@company.com -c timezone="America/Los_Angeles" -c environment="production"
```

### Schedule Customization

The schedules are configurable in `cdk.json` under the `business-notifications` context:

```json
{
  "schedule-expressions": {
    "daily": "cron(0 9 ? * MON-FRI *)",
    "weekly": "cron(0 8 ? * MON *)", 
    "monthly": "cron(0 10 1 * ? *)"
  },
  "flexible-windows": {
    "daily": 15,
    "weekly": 30,
    "monthly": 0
  }
}
```

## Available CDK Commands

```bash
# View differences before deployment
cdk diff

# Deploy the stack
cdk deploy

# Destroy the stack  
cdk destroy

# Synthesize CloudFormation template
cdk synth

# List all stacks
cdk list

# Show stack outputs
aws cloudformation describe-stacks --stack-name BusinessNotificationsStack --query 'Stacks[0].Outputs'
```

## Testing the Solution

### Manual Test

Send a test notification to verify setup:

```bash
# Get the SNS topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name BusinessNotificationsStack \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# Send test message
aws sns publish \
    --topic-arn $TOPIC_ARN \
    --subject "Test Business Notification" \
    --message "This is a test message to verify your business notification system."
```

### Verify Schedules

```bash
# List schedules in the group
aws scheduler list-schedules \
    --group-name $(aws cloudformation describe-stacks \
        --stack-name BusinessNotificationsStack \
        --query 'Stacks[0].Outputs[?OutputKey==`ScheduleGroupName`].OutputValue' \
        --output text)
```

## Cost Optimization

This solution is designed to be cost-effective:

- **EventBridge Scheduler**: $1.00 per million schedule invocations
- **SNS**: $0.50 per million requests + $0.06 per 100,000 email notifications
- **IAM**: No additional cost for roles and policies

**Estimated monthly cost for typical business notifications**: $0.01 - $0.50

## Security Features

- **Least Privilege IAM**: Scheduler role can only publish to the specific SNS topic
- **Topic Policy**: Restricts publishing to EventBridge Scheduler from your account
- **No Hardcoded Secrets**: Uses AWS service-to-service authentication
- **Resource Isolation**: Each deployment creates isolated resources

## Customization Examples

### Adding SMS Notifications

```python
# Add to the _create_sns_topic method
sms_subscription = sns.Subscription(
    self,
    "SMSSubscription", 
    topic=self.notification_topic,
    protocol=sns.SubscriptionProtocol.SMS,
    endpoint="+1234567890"  # Your SMS number
)
```

### Adding SQS Integration

```python
# Create SQS queue for programmatic processing
notification_queue = sqs.Queue(
    self,
    "NotificationQueue",
    queue_name="business-notifications"
)

# Subscribe queue to topic
sns.Subscription(
    self,
    "SQSSubscription",
    topic=self.notification_topic,
    protocol=sns.SubscriptionProtocol.SQS,
    endpoint=notification_queue.queue_arn
)
```

## Troubleshooting

### Common Issues

1. **Email not received**: Check spam folder and ensure subscription is confirmed
2. **Deployment fails**: Verify AWS credentials and permissions
3. **Schedules not working**: Check IAM role permissions and timezone settings
4. **CloudWatch logs**: EventBridge Scheduler logs execution details

### Debugging

```bash
# Check recent EventBridge Scheduler executions
aws logs describe-log-groups --log-group-name-prefix "/aws/scheduler"

# View SNS topic attributes
aws sns get-topic-attributes --topic-arn $TOPIC_ARN
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will delete:
- All EventBridge schedules
- Schedule group
- SNS topic and subscriptions  
- IAM role and policies

## Support

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/scheduler/latest/UserGuide/)
- [Amazon SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/)

## License

This sample application is provided under the MIT License. See LICENSE file for details.