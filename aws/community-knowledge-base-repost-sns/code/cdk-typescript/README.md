# Community Knowledge Base with re:Post Private and SNS - CDK TypeScript

This CDK TypeScript application creates the infrastructure for an enterprise knowledge base solution using AWS re:Post Private and Amazon SNS for notifications.

## Architecture

- **Amazon SNS Topic**: Central hub for knowledge base notifications
- **Email Subscriptions**: Team member notification delivery
- **IAM Service Role**: Secure integration with re:Post Private
- **CloudWatch Monitoring**: Operational visibility and alerting
- **CloudWatch Logs**: Activity logging and troubleshooting

## Prerequisites

1. **AWS Enterprise Support Plan**: Required for AWS re:Post Private access
2. **AWS CLI**: Installed and configured with appropriate permissions
3. **Node.js**: Version 18.x or later
4. **AWS CDK**: Version 2.133.0 or later
5. **TypeScript**: For development and build processes

## Required Permissions

Your AWS credentials need the following permissions:
- `sns:*` - SNS topic and subscription management
- `iam:*` - IAM role and policy creation
- `logs:*` - CloudWatch Logs management
- `cloudwatch:*` - CloudWatch dashboard and alarm creation
- `support:*` - Enterprise Support verification

## Installation

1. **Clone and navigate to the CDK directory**:
   ```bash
   cd aws/community-knowledge-base-repost-sns/code/cdk-typescript/
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

### Email Notifications

Configure team member email addresses using CDK context:

```bash
# Single deployment with email addresses
cdk deploy --context notificationEmails='["dev1@company.com","dev2@company.com","lead@company.com"]'

# Or set in cdk.json context section
```

### Environment Variables

Set these environment variables for deployment:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=$(aws configure get region)
```

### Stack Configuration

Customize the deployment using CDK context parameters:

- `stackName`: Custom stack name (default: community-knowledge-base)
- `environment`: Environment tag (development/staging/production)
- `owner`: Owner tag for resource management
- `costCenter`: Cost center for billing allocation
- `enableDetailedMonitoring`: Enable/disable detailed monitoring (default: true)

## Deployment

### Quick Deployment

```bash
# Deploy with default configuration
npm run deploy

# Deploy with custom configuration
cdk deploy --context environment=production --context owner=TeamName
```

### Step-by-Step Deployment

1. **Bootstrap CDK (first time only)**:
   ```bash
   npm run bootstrap
   ```

2. **Review the changes**:
   ```bash
   npm run diff
   ```

3. **Deploy the stack**:
   ```bash
   npm run deploy:with-approval
   ```

4. **Verify deployment**:
   ```bash
   aws sns list-topics --query 'Topics[?contains(TopicArn, `repost-knowledge-notifications`)]'
   ```

## Post-Deployment Configuration

### 1. Confirm Email Subscriptions

Team members will receive email confirmations:
- Check inbox for "AWS Notification - Subscription Confirmation"
- Click "Confirm subscription" link in each email
- Verify subscriptions are confirmed in AWS console

### 2. Configure AWS re:Post Private

1. **Access re:Post Private Console**:
   ```bash
   # Open the console URL from stack outputs
   aws cloudformation describe-stacks \
     --stack-name CommunityKnowledgeBaseStack \
     --query 'Stacks[0].Outputs[?OutputKey==`RePostPrivateConsoleUrl`].OutputValue' \
     --output text
   ```

2. **Complete Initial Setup**:
   - Sign in with IAM Identity Center credentials
   - Complete configuration wizard
   - Customize organization branding
   - Configure topics and tags
   - Select AWS service areas of interest

### 3. Test Notification System

```bash
# Get the SNS topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
  --stack-name CommunityKnowledgeBaseStack \
  --query 'Stacks[0].Outputs[?OutputKey==`NotificationTopicArn`].OutputValue' \
  --output text)

# Send test notification
aws sns publish \
  --topic-arn ${TOPIC_ARN} \
  --subject "Knowledge Base Test: System Ready" \
  --message "Your enterprise knowledge base notification system is configured and ready for use. Team members will receive notifications about new discussions, questions, and solutions."
```

## Monitoring and Operations

### CloudWatch Dashboard

Access the monitoring dashboard:
1. Open AWS CloudWatch Console
2. Navigate to Dashboards
3. Select "community-knowledge-base-[unique-suffix]"

### Key Metrics to Monitor

- **Messages Published**: Number of notifications sent
- **Messages Delivered**: Successful email deliveries  
- **Messages Failed**: Failed delivery attempts
- **Subscription Confirmations**: Team member engagement

### CloudWatch Alarms

The stack creates these operational alarms:
- **Notification Failures**: Alerts on delivery failures
- **High Volume**: Alerts on unexpected notification volume

### Log Analysis

```bash
# Get log group name from stack outputs
LOG_GROUP=$(aws cloudformation describe-stacks \
  --stack-name CommunityKnowledgeBaseStack \
  --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
  --output text)

# View recent log entries
aws logs tail ${LOG_GROUP} --follow
```

## Development

### Running Tests

```bash
# Run unit tests
npm test

# Run tests in watch mode
npm run test:watch

# Generate coverage report
npm test -- --coverage
```

### Code Quality

```bash
# Lint TypeScript code
npm run lint

# Fix linting issues automatically
npm run lint:fix

# Format code with Prettier
npm run format

# Check code formatting
npm run format:check
```

### Development Workflow

```bash
# Watch for changes and rebuild
npm run watch

# Compare local changes with deployed stack
npm run diff

# Deploy changes during development
npm run deploy
```

## Customization

### Adding More Notification Channels

Extend the stack to support additional notification methods:

```typescript
// Add Slack integration
import * as chatbot from 'aws-cdk-lib/aws-chatbot';

// Add Microsoft Teams integration
import * as lambda from 'aws-cdk-lib/aws-lambda';
```

### Custom Email Templates

Create custom SNS message templates for different notification types:

```typescript
// Add message attributes for filtering
this.notificationTopic.addSubscription(
  new snsSubscriptions.EmailSubscription(email, {
    filterPolicy: {
      notificationType: sns.SubscriptionFilter.stringFilter({
        allowlist: ['new-question', 'new-answer', 'discussion-update']
      })
    }
  })
);
```

### Multi-Region Deployment

Deploy to multiple regions for global teams:

```bash
# Deploy to us-east-1
cdk deploy --context region=us-east-1

# Deploy to eu-west-1  
cdk deploy --context region=eu-west-1
```

## Troubleshooting

### Common Issues

1. **Email Confirmations Not Received**:
   - Check spam/junk folders
   - Verify email addresses are correct
   - Check SNS topic subscription status

2. **re:Post Private Access Denied**:
   - Verify Enterprise Support plan is active
   - Check IAM permissions for console access
   - Ensure correct AWS account context

3. **CloudFormation Deployment Failures**:
   - Check IAM permissions
   - Verify region supports all services
   - Review CloudFormation events for specific errors

### Getting Support

- Check AWS re:Post Private documentation
- Review CloudWatch Logs for error details
- Contact AWS Support for Enterprise Support plan issues

## Cost Optimization

### SNS Pricing

- First 1,000 email notifications per month: Free
- Additional emails: $0.50 per 1,000 notifications
- SMS notifications: Additional charges apply

### Monitoring Costs

```bash
# Estimate monthly costs based on usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name NumberOfMessagesPublished \
  --dimensions Name=TopicName,Value=${TOPIC_NAME} \
  --start-time $(date -d '30 days ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 2592000 \
  --statistics Sum
```

## Cleanup

### Remove All Resources

```bash
# Destroy the CDK stack
npm run destroy

# Clean up local build artifacts
npm run clean
```

### Manual Cleanup Steps

1. **Export re:Post Private Content**: Save valuable discussions before deactivation
2. **Contact AWS Support**: Request re:Post Private deactivation
3. **Verify Resource Deletion**: Check AWS console for any remaining resources

## Security Best Practices

- **Least Privilege**: IAM roles follow minimum required permissions
- **Encryption**: SNS topics use AWS managed encryption
- **Access Logging**: All API calls logged via CloudTrail
- **Email Validation**: Basic validation prevents invalid subscriptions

## Support and Contributing

For issues with this CDK application:
1. Review CloudWatch Logs for error details
2. Check AWS documentation for service limits
3. Submit issues via the repository issue tracker

## License

This project is licensed under the MIT License - see the LICENSE file for details.