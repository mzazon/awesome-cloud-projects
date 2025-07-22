# GuardDuty Threat Detection - CDK TypeScript

This CDK TypeScript application deploys a comprehensive threat detection system using Amazon GuardDuty with automated alerting and monitoring capabilities.

## Architecture

The solution creates:

- **Amazon GuardDuty**: Continuous threat detection using machine learning and threat intelligence
- **SNS Topic**: Real-time alert notifications via email
- **EventBridge Rule**: Routes GuardDuty findings to notification systems
- **CloudWatch Dashboard**: Security monitoring and metrics visualization
- **S3 Bucket**: Optional long-term storage for GuardDuty findings (with lifecycle policies)

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18 or later
- npm or yarn package manager
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for GuardDuty, SNS, CloudWatch, EventBridge, and S3

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if not already done):
   ```bash
   cdk bootstrap
   ```

3. **Deploy with notification email**:
   ```bash
   # Option 1: Set environment variable
   export NOTIFICATION_EMAIL="your-email@example.com"
   cdk deploy
   
   # Option 2: Use CDK context
   cdk deploy --context notificationEmail="your-email@example.com"
   ```

4. **Confirm email subscription**: Check your email and confirm the SNS subscription to receive alerts.

## Configuration Options

### Required Parameters

- **notificationEmail**: Email address to receive GuardDuty alerts

### Optional Parameters (via CDK context)

- **enableS3Export**: Enable S3 export for findings (default: true)
- **findingPublishingFrequency**: Frequency for publishing findings (default: "FIFTEEN_MINUTES")
- **environment**: Environment name for tagging (default: "development")
- **costCenter**: Cost center for resource tagging

Example with all options:
```bash
cdk deploy \
  --context notificationEmail="security@company.com" \
  --context enableS3Export="true" \
  --context findingPublishingFrequency="FIFTEEN_MINUTES" \
  --context environment="production" \
  --context costCenter="security-ops"
```

## Available Commands

```bash
# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm run test

# Deploy stack
npm run deploy
# or
cdk deploy

# View differences
cdk diff

# Synthesize CloudFormation template
cdk synth

# Destroy stack
npm run destroy
# or
cdk destroy
```

## Deployment Process

1. **GuardDuty Detector**: Creates and enables GuardDuty with specified finding frequency
2. **SNS Topic**: Creates topic for alert notifications with email subscription
3. **EventBridge Rule**: Configures rule to capture all GuardDuty findings
4. **Integration**: Connects EventBridge to SNS with proper IAM permissions
5. **Dashboard**: Creates CloudWatch dashboard for security monitoring
6. **S3 Export**: Optionally creates S3 bucket with lifecycle policies for finding storage

## Security Features

- **Continuous Monitoring**: 24/7 threat detection across CloudTrail, VPC Flow Logs, and DNS logs
- **Real-time Alerting**: Immediate email notifications for security findings
- **Automated Response**: Event-driven architecture enables automated incident response
- **Long-term Storage**: S3 export with intelligent tiering for compliance and analysis
- **Least Privilege**: IAM roles follow principle of least privilege

## Monitoring and Alerting

### CloudWatch Dashboard
- GuardDuty findings count over time
- Findings categorized by severity (High, Medium, Low)
- Real-time security metrics

### Email Notifications
- Immediate alerts for all GuardDuty findings
- Formatted messages with finding details
- Direct links to AWS console for investigation

### S3 Export
- Automated export of all findings
- Lifecycle policies for cost optimization
- Long-term retention for compliance

## Cost Optimization

- GuardDuty pricing based on log volume analyzed
- S3 lifecycle policies transition data to cheaper storage classes
- CloudWatch dashboard uses efficient metric queries
- SNS notifications optimized for security team distribution

## Testing

Generate sample findings to test the notification pipeline:

```bash
# Via AWS CLI
aws guardduty create-sample-findings \
  --detector-id <detector-id> \
  --finding-types Backdoor:EC2/C&CActivity.B!DNS

# Via EventBridge (test notification system)
aws events put-events \
  --entries '[{
    "Source": "aws.guardduty",
    "DetailType": "GuardDuty Finding",
    "Detail": "{\"test\": \"notification\"}"
  }]'
```

## Customization

### Adding More Notification Channels

```typescript
// Add Slack notification
import * as chatbot from 'aws-cdk-lib/aws-chatbot';

const slackChannel = new chatbot.SlackChannelConfiguration(this, 'SlackNotifications', {
  slackChannelConfigurationName: 'guardduty-alerts',
  slackWorkspaceId: 'YOUR_WORKSPACE_ID',
  slackChannelId: 'YOUR_CHANNEL_ID',
});

guardDutyRule.addTarget(new targets.SnsTopic(slackChannel.slackChannelConfigurationArn));
```

### Custom Finding Filters

```typescript
// Filter for high severity findings only
const highSeverityRule = new events.Rule(this, 'HighSeverityFindings', {
  eventPattern: {
    source: ['aws.guardduty'],
    detailType: ['GuardDuty Finding'],
    detail: {
      severity: [{ numeric: ['>=', 7.0] }], // High severity findings
    },
  },
});
```

### Automated Response Actions

```typescript
import * as lambda from 'aws-cdk-lib/aws-lambda';

// Lambda function for automated response
const responseFunction = new lambda.Function(this, 'AutoResponse', {
  runtime: lambda.Runtime.PYTHON_3_11,
  handler: 'index.handler',
  code: lambda.Code.fromAsset('lambda'),
});

guardDutyRule.addTarget(new targets.LambdaFunction(responseFunction));
```

## Troubleshooting

### Common Issues

1. **Email not received**: Check spam folder and confirm SNS subscription
2. **No findings**: GuardDuty needs time to learn baseline behavior (24-48 hours)
3. **Permission errors**: Ensure proper IAM permissions for all services
4. **S3 export fails**: Verify bucket policies and GuardDuty service role permissions

### Useful Commands

```bash
# Check GuardDuty status
aws guardduty get-detector --detector-id <detector-id>

# List SNS subscriptions
aws sns list-subscriptions

# View CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name GuardDuty-Security-Monitoring

# Check EventBridge rules
aws events list-rules --name-prefix guardduty
```

## Cleanup

```bash
# Destroy all resources
cdk destroy

# Or manually clean up specific resources
aws guardduty delete-detector --detector-id <detector-id>
aws sns delete-topic --topic-arn <topic-arn>
aws s3 rb s3://<bucket-name> --force
```

## Security Considerations

- GuardDuty findings may contain sensitive infrastructure information
- Configure proper access controls on S3 buckets and SNS topics
- Consider encrypting SNS messages for sensitive environments
- Regularly review and tune finding types based on your environment
- Implement automated response playbooks for common threat types

## Support

For issues with this CDK application:
1. Check AWS CDK documentation
2. Review GuardDuty service documentation
3. Validate IAM permissions and service limits
4. Use AWS CloudTrail to debug API calls

## Contributing

When modifying this CDK application:
1. Follow TypeScript and CDK best practices
2. Update tests for new functionality
3. Document configuration changes
4. Test deployment in non-production environment first