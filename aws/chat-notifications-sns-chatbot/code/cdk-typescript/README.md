# Chat Notifications with SNS and Chatbot - CDK TypeScript

This CDK TypeScript application deploys infrastructure for sending real-time notifications from AWS services to Slack or Microsoft Teams channels using Amazon SNS and AWS Chatbot integration.

## Architecture

The application creates:

- **SNS Topic** with KMS encryption for secure message delivery
- **KMS Key** for encrypting SNS messages at rest and in transit
- **CloudWatch Alarm** for demonstration and testing purposes
- **IAM Role** for AWS Chatbot with appropriate permissions
- **Proper outputs** for manual AWS Chatbot configuration

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ and npm installed
- AWS account with appropriate permissions
- CDK CLI installed (`npm install -g aws-cdk`)
- Active Slack workspace or Microsoft Teams (for AWS Chatbot integration)

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

Set environment variables (optional):

```bash
export AWS_ACCOUNT_ID="123456789012"  # Your AWS account ID
export AWS_REGION="us-east-1"         # Your preferred region
export ENVIRONMENT="production"        # Environment tag
export OWNER="DevOpsTeam"             # Owner tag
export COST_CENTER="Engineering"      # Cost center tag
```

## Deployment

1. Synthesize the CloudFormation template:

```bash
npm run synth
```

2. Deploy the stack:

```bash
npm run deploy
```

3. The deployment will output important values including:
   - SNS topic ARN for AWS Chatbot configuration
   - IAM role ARN for Chatbot permissions
   - AWS Chatbot console URL for manual setup

## Manual AWS Chatbot Setup

After deployment, complete the AWS Chatbot configuration:

1. Navigate to the [AWS Chatbot Console](https://console.aws.amazon.com/chatbot/)
2. Choose your chat client (Slack or Microsoft Teams)
3. Click "Configure" and authorize AWS Chatbot in your workspace
4. Create a new channel configuration:
   - **Configuration name**: `team-alerts-{suffix}`
   - **Slack/Teams channel**: Select your target channel
   - **IAM role**: Use the role ARN from stack outputs
   - **Channel guardrail policies**: Add `ReadOnlyAccess`
   - **SNS topics**: Add the SNS topic ARN from stack outputs

## Testing

### Unit Tests

Run the comprehensive test suite:

```bash
npm test
```

The test suite validates:
- SNS topic creation with encryption
- KMS key configuration and policies
- IAM role setup for AWS Chatbot
- CloudWatch alarm configuration
- Stack outputs and tagging
- Resource count and properties

### Integration Testing

1. Test the notification flow:

```bash
# Get the SNS topic ARN from stack outputs
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name ChatNotificationsStack \
  --query 'Stacks[0].Outputs[?OutputKey==`SnsTopicArn`].OutputValue' \
  --output text)

# Send a test message
aws sns publish \
  --topic-arn $SNS_TOPIC_ARN \
  --subject "Test Alert: Infrastructure Notification" \
  --message "Testing chat notification system - this message should appear in your configured Slack/Teams channel"
```

2. Verify the CloudWatch alarm:

```bash
# Check alarm status
aws cloudwatch describe-alarms \
  --query 'MetricAlarms[?contains(AlarmName, `demo-cpu-alarm`)].{Name:AlarmName,State:StateValue}'
```

## Security Features

This implementation includes:

- **KMS Encryption**: All SNS messages are encrypted using a customer-managed KMS key
- **IAM Least Privilege**: Chatbot role has minimal required permissions
- **CDK Nag Integration**: Automated security best practice validation
- **SSL Enforcement**: SNS topic enforces SSL for all communications

## CDK Commands

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and compile
- `npm run test`: Run unit tests
- `npm run synth`: Synthesize CloudFormation template
- `npm run deploy`: Deploy the stack
- `npm run destroy`: Destroy the stack

## Customization

### Environment Variables

You can customize the deployment using these environment variables:

- `ENVIRONMENT`: Environment tag (default: "development")
- `OWNER`: Owner tag (default: "DevOpsTeam")
- `COST_CENTER`: Cost center tag (default: "Engineering")
- `ENABLE_CDK_NAG`: Enable CDK Nag security checks (default: "true")

### Stack Modifications

To modify the infrastructure:

1. Edit `lib/chat-notifications-stack.ts`
2. Run `npm run synth` to validate changes
3. Deploy with `npm run deploy`

## Cleanup

To remove all resources:

```bash
npm run destroy
```

**Note**: You should also manually remove the AWS Chatbot channel configuration from the console.

## Outputs

The stack provides these outputs:

- `SnsTopicArn`: ARN of the SNS topic for notifications
- `SnsTopicName`: Name of the SNS topic
- `ChatbotRoleArn`: IAM role ARN for AWS Chatbot
- `KmsKeyArn`: KMS key ARN for encryption
- `DemoAlarmName`: CloudWatch alarm name for testing
- `ChatbotConsoleUrl`: Direct link to AWS Chatbot console
- `ManualSetupInstructions`: Step-by-step Chatbot setup guide

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**: Run `cdk bootstrap` if you see bootstrap-related errors
2. **Permission Denied**: Ensure your AWS credentials have sufficient permissions
3. **Resource Conflicts**: The stack uses unique suffixes to avoid naming conflicts

### Support

- AWS CDK Documentation: https://docs.aws.amazon.com/cdk/
- AWS Chatbot Documentation: https://docs.aws.amazon.com/chatbot/
- AWS SNS Documentation: https://docs.aws.amazon.com/sns/

## Contributing

1. Follow TypeScript best practices
2. Maintain CDK Nag compliance
3. Update documentation for any changes
4. Test thoroughly before deployment