# Community Knowledge Base with re:Post Private and SNS - CDK Python

This directory contains the AWS CDK Python implementation for deploying a Community Knowledge Base solution using AWS re:Post Private integrated with Amazon SNS email notifications.

## Architecture Overview

This CDK application creates:

- **SNS Topic**: Central notification hub for knowledge base updates
- **Email Subscriptions**: Automated notifications for team members
- **IAM Policies**: Appropriate permissions for secure operations
- **Resource Tags**: Consistent tagging for governance and cost tracking

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Python 3.8 or higher
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- AWS Enterprise Support or Enterprise On-Ramp Support plan (required for re:Post Private)
- Virtual environment (recommended)

## Installation

1. **Create and activate a virtual environment**:

   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

2. **Install dependencies**:

   ```bash
   pip install -r requirements.txt
   ```

3. **Install development dependencies** (optional):

   ```bash
   pip install -e .[dev]
   ```

## Configuration

### Environment Variables

Set these environment variables or use CDK context:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### Parameters

The application accepts the following parameters during deployment:

- **TeamEmails**: Comma-separated list of email addresses for notifications
- **TopicName**: Name for the SNS topic (default: `repost-knowledge-notifications`)

## Deployment

### Quick Start

```bash
# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy
```

### Custom Configuration

```bash
# Deploy with custom team emails
cdk deploy --parameters TeamEmails="dev1@company.com,dev2@company.com,lead@company.com"

# Deploy with custom topic name
cdk deploy --parameters TopicName="my-knowledge-notifications"

# Deploy with both parameters
cdk deploy \
  --parameters TeamEmails="dev1@company.com,dev2@company.com" \
  --parameters TopicName="enterprise-knowledge-alerts"
```

### Context Configuration

Alternatively, configure parameters via CDK context in `cdk.json`:

```json
{
  "context": {
    "teamEmails": ["dev1@company.com", "dev2@company.com"],
    "topicName": "knowledge-notifications"
  }
}
```

## Usage

### After Deployment

1. **Confirm Email Subscriptions**: Team members will receive confirmation emails and must click the confirmation links to start receiving notifications.

2. **Access re:Post Private**: Navigate to the AWS re:Post Private console at:
   ```
   https://console.aws.amazon.com/repost-private/
   ```

3. **Configure re:Post Private**: Complete the initial setup including:
   - Organization branding and customization
   - Content topics and tags
   - User permissions and access levels

### Testing Notifications

Send a test notification to verify the setup:

```bash
# Get the topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name CommunityKnowledgeBaseStack \
  --query 'Stacks[0].Outputs[?OutputKey==`KnowledgeTopicArn`].OutputValue' \
  --output text)

# Send test notification
aws sns publish \
  --topic-arn $TOPIC_ARN \
  --subject "Knowledge Base Test Notification" \
  --message "This is a test notification from your enterprise knowledge base system."
```

## Development

### Code Structure

```
cdk-python/
├── app.py                 # Main CDK application entry point
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

### Key Classes

- **`CommunityKnowledgeBaseStack`**: Main CDK stack containing all resources
- **`CommunityKnowledgeBaseApp`**: CDK application class for initialization

### Code Quality

Run code quality checks:

```bash
# Format code
black app.py

# Lint code
flake8 app.py

# Type checking
mypy app.py
```

### Testing

Run tests (if implemented):

```bash
pytest
```

## Stack Outputs

The deployed stack provides these outputs:

- **KnowledgeTopicArn**: ARN of the SNS topic for notifications
- **KnowledgeTopicName**: Name of the SNS topic
- **RePostPrivateUrl**: URL to access AWS re:Post Private console

## Customization

### Adding Additional Subscriptions

Modify the `_create_email_subscriptions` method in `app.py` to add other subscription types:

```python
# Add SMS subscription
self.knowledge_topic.add_subscription(
    subscriptions.SmsSubscription("+1234567890")
)

# Add SQS subscription
queue = sqs.Queue(self, "NotificationQueue")
self.knowledge_topic.add_subscription(
    subscriptions.SqsSubscription(queue)
)
```

### Custom Resource Tags

Modify the `_add_resource_tags` method to add organization-specific tags:

```python
Tags.of(self).add("Department", "Engineering")
Tags.of(self).add("CostCenter", "12345")
Tags.of(self).add("Compliance", "SOX")
```

## Cleanup

Remove all deployed resources:

```bash
cdk destroy
```

## Troubleshooting

### Common Issues

1. **Enterprise Support Required**: Ensure your AWS account has Enterprise Support or Enterprise On-Ramp Support plan active.

2. **Email Confirmation**: Team members must confirm their email subscriptions to receive notifications.

3. **Permission Issues**: Verify your AWS credentials have sufficient permissions to create SNS topics and subscriptions.

4. **Region Restrictions**: Some AWS services may not be available in all regions.

### Support

For issues with this CDK application:

1. Check AWS CloudFormation console for deployment errors
2. Review CloudWatch logs for runtime issues
3. Verify AWS service limits and quotas
4. Consult AWS re:Post Private documentation

## Security Considerations

- SNS topics use server-side encryption by default
- Email subscriptions require confirmation to prevent spam
- IAM policies follow least privilege principles
- Resource tags enable proper access control and auditing

## Cost Optimization

- SNS charges apply only for message delivery beyond the free tier (1,000 email notifications per month)
- re:Post Private is included with Enterprise Support plans at no additional cost
- Consider using SQS for high-volume notifications to reduce costs

## Integration Examples

### CloudWatch Integration

Monitor knowledge base activity:

```python
# Add CloudWatch alarm for high notification volume
alarm = cloudwatch.Alarm(
    self, "HighNotificationVolume",
    metric=self.knowledge_topic.metric_number_of_messages_published(),
    threshold=100,
    evaluation_periods=1
)
```

### Lambda Integration

Process notifications with Lambda:

```python
# Add Lambda subscription for automated processing
notification_processor = lambda_.Function(
    self, "NotificationProcessor",
    runtime=lambda_.Runtime.PYTHON_3_9,
    handler="index.handler",
    code=lambda_.Code.from_inline("# Your processing logic here")
)

self.knowledge_topic.add_subscription(
    subscriptions.LambdaSubscription(notification_processor)
)
```

## License

This CDK application is provided under the Apache 2.0 License. See LICENSE file for details.