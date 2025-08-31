# Environment Health Check CDK Application

This CDK TypeScript application implements automated environment health monitoring using AWS Systems Manager, Lambda, EventBridge, and SNS notifications. It continuously monitors EC2 instances through SSM Agent connectivity and sends alerts when health issues are detected.

## Architecture Overview

The solution includes:

- **SNS Topic**: Sends email notifications for health alerts
- **Lambda Function**: Performs health checks and updates Systems Manager compliance
- **EventBridge Rules**: Schedules health checks and responds to compliance events
- **Systems Manager Compliance**: Tracks custom health metrics
- **IAM Roles**: Provides secure access with least privilege principles

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ and npm installed
- CDK CLI installed (`npm install -g aws-cdk`)
- At least one EC2 instance with SSM Agent installed and running
- Valid email address for notifications

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

### Method 1: Context Variable (Recommended)

Set your notification email in `cdk.json`:

```json
{
  "context": {
    "notificationEmail": "your-email@example.com"
  }
}
```

### Method 2: Deploy-time Parameter

Deploy without pre-configuring email (will prompt during deployment):

```bash
cdk deploy --parameters NotificationEmail=your-email@example.com
```

### Method 3: CDK Context Command

```bash
cdk deploy -c notificationEmail=your-email@example.com
```

## Deployment

1. **Synthesize CloudFormation template** (optional, for validation):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm email subscription**:
   - Check your email inbox for a subscription confirmation
   - Click the confirmation link to activate notifications

## Testing

1. **Test health check function manually**:
   ```bash
   aws lambda invoke \
     --function-name $(aws cloudformation describe-stacks \
       --stack-name EnvironmentHealthCheckStack \
       --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
       --output text) \
     --payload '{"source":"manual-test"}' \
     response.json
   ```

2. **View CloudWatch logs**:
   ```bash
   aws logs tail $(aws cloudformation describe-stacks \
     --stack-name EnvironmentHealthCheckStack \
     --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
     --output text | sed 's/^/\/aws\/lambda\//')
   ```

3. **Test SNS notifications**:
   ```bash
   aws sns publish \
     --topic-arn $(aws cloudformation describe-stacks \
       --stack-name EnvironmentHealthCheckStack \
       --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
       --output text) \
     --subject "Test Health Alert" \
     --message "This is a test notification from your environment health monitoring system."
   ```

## Monitoring and Operations

### Health Check Schedule

- **Default**: Runs every 5 minutes
- **Customization**: Modify `scheduleExpression` in the stack constructor

### Compliance Tracking

View compliance status:

```bash
# List compliance summaries
aws ssm list-compliance-summaries \
  --query 'ComplianceSummaryItems[?ComplianceType==`Custom:EnvironmentHealth`]'

# Get detailed compliance items for a specific instance
aws ssm list-compliance-items \
  --resource-ids i-1234567890abcdef0 \
  --resource-types ManagedInstance \
  --filters Key=ComplianceType,Values="Custom:EnvironmentHealth"
```

### CloudWatch Monitoring

- **Function Metrics**: Available in CloudWatch under AWS/Lambda
- **Log Groups**: `/aws/lambda/environment-health-check-*`
- **Custom Metrics**: Track instance compliance trends

## Customization

### Health Check Logic

Modify the Lambda function code in `lib/environment-health-check-stack.ts` to add:

- Custom health endpoints
- Database connectivity checks
- Application-specific validations
- Integration with external monitoring tools

### Notification Channels

Extend SNS subscriptions to include:

```typescript
// Add SMS notifications
healthAlertsTopic.addSubscription(new subscriptions.SmsSubscription('+1234567890'));

// Add Lambda function for custom processing
healthAlertsTopic.addSubscription(new subscriptions.LambdaSubscription(customProcessorFunction));
```

### Schedule Customization

Modify the schedule expression:

```typescript
// Every 10 minutes
schedule: events.Schedule.expression('rate(10 minutes)')

// Daily at 9 AM UTC
schedule: events.Schedule.expression('cron(0 9 * * ? *)')

// Business hours only (9 AM - 5 PM UTC, weekdays)
schedule: events.Schedule.expression('cron(0 9-17 ? * MON-FRI *)')
```

## Security Considerations

### IAM Permissions

The solution follows least privilege principles:

- Lambda function has minimal Systems Manager permissions
- SNS publish permissions limited to the health alerts topic
- CloudWatch Logs permissions for function logging only

### CDK Nag Security Scanning

Security checks are automatically applied:

```bash
# View security recommendations
cdk synth | grep -A 5 -B 5 "AwsSolutions"
```

### Data Encryption

- **SNS**: Uses AWS managed encryption by default
- **CloudWatch Logs**: Encrypted at rest
- **Lambda Environment Variables**: Encrypted using AWS managed keys

## Troubleshooting

### Common Issues

1. **Email not received**:
   - Check spam folder
   - Verify email address in configuration
   - Confirm subscription in AWS SNS console

2. **Lambda function fails**:
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions
   - Ensure EC2 instances have SSM agent installed

3. **No compliance data**:
   - Verify instances are managed by Systems Manager
   - Check SSM agent status on EC2 instances
   - Review Lambda function logs for errors

### Debug Commands

```bash
# Check EventBridge rules
aws events list-rules --name-prefix health-check-schedule

# Verify SNS topic and subscriptions
aws sns list-topics
aws sns list-subscriptions

# Check Lambda function status
aws lambda get-function --function-name environment-health-check-*
```

## Cost Optimization

### Expected Costs

- **Lambda**: ~$0.20/month (based on 5-minute intervals)
- **SNS**: ~$0.50/month (for notifications)
- **EventBridge**: ~$1.00/month (for rule evaluations)
- **CloudWatch Logs**: ~$0.50/month (with log retention)

**Total estimated cost**: $2-3/month

### Cost Reduction Options

1. **Increase check intervals** (e.g., 15 minutes instead of 5)
2. **Reduce log retention** (e.g., 3 days instead of 14 days)
3. **Use CloudWatch Alarms** for basic checks instead of Lambda

## Cleanup

Remove all resources:

```bash
cdk destroy
```

Confirm deletion when prompted. This will remove:

- All Lambda functions and associated resources
- SNS topics and subscriptions
- EventBridge rules and targets
- IAM roles and policies
- CloudWatch log groups

## Support

For issues with this CDK application:

1. Check AWS CloudFormation stack events
2. Review CloudWatch logs for detailed error messages
3. Consult AWS documentation for service-specific issues
4. Use AWS Support for account-specific problems

## License

This project is licensed under the MIT License.