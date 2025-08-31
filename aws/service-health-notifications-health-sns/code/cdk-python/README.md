# AWS CDK Python - Service Health Notifications

This CDK Python application creates an automated notification system that monitors AWS Personal Health Dashboard events and sends real-time alerts via Amazon SNS.

## Architecture

The solution includes:
- **SNS Topic**: Central hub for health notifications
- **EventBridge Rule**: Captures AWS Health events with pattern matching
- **IAM Role**: Allows EventBridge to publish to SNS securely
- **Email Subscription**: Delivers notifications to specified email address
- **Security Policies**: Least-privilege access controls

## Prerequisites

- AWS CLI installed and configured
- Python 3.8 or later
- Node.js 14.x or later (for CDK CLI)
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for creating IAM roles, SNS topics, and EventBridge rules

## Installation

1. **Clone and navigate to the CDK Python directory**:
   ```bash
   cd cdk-python/
   ```

2. **Create and activate a Python virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

### Method 1: Environment Variable
```bash
export NOTIFICATION_EMAIL="your-email@example.com"
```

### Method 2: CDK Context
```bash
cdk deploy -c notification_email="your-email@example.com"
```

### Method 3: CDK Context File
Add to `cdk.json`:
```json
{
  "context": {
    "notification_email": "your-email@example.com"
  }
}
```

## Deployment

1. **Synthesize CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm email subscription**:
   Check your email and click the confirmation link sent by AWS SNS.

## Usage

### Testing the Notification System
```bash
# Get the SNS topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name ServiceHealthNotificationsStack \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# Send a test notification
aws sns publish \
    --topic-arn $TOPIC_ARN \
    --subject "Test: AWS Health Notification System" \
    --message "This is a test message to verify your notification system is working."
```

### Monitoring Health Events
The system automatically monitors AWS Health events. When service issues occur:
1. AWS Personal Health Dashboard generates an event
2. EventBridge rule captures the event
3. SNS delivers a formatted notification to your email

### Customizing Event Patterns
Modify the EventBridge rule in `app.py` to filter specific events:
```python
# Example: Only security-related events
event_pattern=events.EventPattern(
    source=["aws.health"],
    detail_type=["AWS Health Event"],
    detail={
        "eventTypeCategory": ["security"]
    }
)
```

## Cleanup

Remove all resources created by this stack:
```bash
cdk destroy
```

## Stack Outputs

After deployment, the following outputs are available:
- **SNSTopicArn**: ARN of the SNS topic for notifications
- **EventBridgeRuleName**: Name of the EventBridge rule
- **IAMRoleArn**: ARN of the IAM role used by EventBridge
- **NotificationEmail**: Configured email address

## Development

### Code Formatting
```bash
black app.py
```

### Type Checking
```bash
mypy app.py
```

### Security Scanning
```bash
bandit -r .
```

### Testing
```bash
pytest
```

## Troubleshooting

### Common Issues

1. **Email not received**:
   - Check spam folder
   - Verify email address is correct
   - Confirm SNS subscription in AWS Console

2. **CDK deploy fails**:
   - Ensure AWS credentials are configured
   - Verify CDK is bootstrapped: `cdk bootstrap`
   - Check IAM permissions

3. **EventBridge rule not triggering**:
   - Verify rule is enabled in AWS Console
   - Check CloudWatch Logs for EventBridge errors
   - Ensure IAM role has SNS publish permissions

### Debugging

Enable verbose logging:
```bash
cdk deploy --verbose
```

Check CloudWatch Logs:
- EventBridge rule executions
- SNS delivery status
- IAM role assume role logs

## Security Considerations

- The IAM role follows least-privilege principles
- SNS topic policy restricts access to EventBridge service
- All resources are tagged for governance
- Email subscriptions require confirmation to prevent spam

## Cost Optimization

- SNS charges $0.50 per 1 million notifications
- EventBridge rules are free for AWS service events
- IAM roles and policies have no additional charges
- Typical monthly cost: Less than $1 for normal notification volumes

## Additional Resources

- [AWS Personal Health Dashboard](https://docs.aws.amazon.com/health/)
- [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/)
- [SNS Developer Guide](https://docs.aws.amazon.com/sns/)
- [CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)