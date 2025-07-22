# Basic Log Monitoring with CloudWatch Logs and SNS - CDK TypeScript

This CDK TypeScript application deploys a complete log monitoring solution using AWS CloudWatch Logs, SNS, and Lambda for automated error detection and alerting.

## Architecture

The solution creates:

- **CloudWatch Log Group** - Centralized log collection with configurable retention
- **Metric Filter** - Detects error patterns in log events 
- **CloudWatch Alarm** - Triggers when error threshold is exceeded
- **SNS Topic** - Delivers notifications to multiple endpoints
- **Lambda Function** - Processes alarm notifications and enables custom logic
- **Email Subscription** - Optional email notifications

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Appropriate AWS permissions for CloudWatch, SNS, Lambda, and IAM

## Installation

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Build the TypeScript code:**
   ```bash
   npm run build
   ```

3. **Bootstrap CDK (if not done previously):**
   ```bash
   npm run bootstrap
   ```

## Configuration

### Basic Deployment

Deploy with default settings:

```bash
npm run deploy
```

### Custom Configuration

Deploy with custom parameters using CDK context:

```bash
# Deploy with email notifications
cdk deploy -c notificationEmail=your-email@example.com

# Deploy with custom error threshold
cdk deploy -c notificationEmail=your-email@example.com -c errorThreshold=5

# Deploy with custom evaluation period (minutes)
cdk deploy -c evaluationPeriodMinutes=10
```

### Environment Variables

Set AWS environment variables if needed:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
```

## Available Scripts

- `npm run build` - Compile TypeScript code
- `npm run watch` - Watch for changes and auto-compile
- `npm run test` - Run unit tests
- `npm run synth` - Synthesize CloudFormation template
- `npm run deploy` - Build and deploy the stack
- `npm run diff` - Show differences between local and deployed stack
- `npm run destroy` - Delete the stack and all resources
- `npm run lint` - Run ESLint
- `npm run lint:fix` - Fix ESLint issues automatically

## Testing the Solution

After deployment, test the monitoring system:

1. **Send test log events to the log group:**
   ```bash
   # Get the log group name from CDK outputs
   LOG_GROUP_NAME=$(aws cloudformation describe-stacks \
     --stack-name BasicLogMonitoringStack \
     --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
     --output text)

   # Create a log stream
   aws logs create-log-stream \
     --log-group-name ${LOG_GROUP_NAME} \
     --log-stream-name test-stream-$(date +%Y%m%d%H%M%S)

   # Send test error events
   LOG_STREAM_NAME=$(aws logs describe-log-streams \
     --log-group-name ${LOG_GROUP_NAME} \
     --order-by LastEventTime --descending \
     --query 'logStreams[0].logStreamName' --output text)

   for i in {1..3}; do
     aws logs put-log-events \
       --log-group-name ${LOG_GROUP_NAME} \
       --log-stream-name ${LOG_STREAM_NAME} \
       --log-events \
         timestamp=$(date +%s000),message="ERROR: Test error event $i"
     sleep 2
   done
   ```

2. **Monitor alarm state:**
   ```bash
   aws cloudwatch describe-alarms \
     --alarm-names application-errors-alarm \
     --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue}'
   ```

3. **Check Lambda function logs:**
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/lambda/log-processor-basiclogmonitoringstack \
     --start-time $(date -d '10 minutes ago' +%s)000
   ```

## Customization

### Modify Error Detection Patterns

Edit the `app.ts` file to customize the metric filter patterns:

```typescript
// Current patterns detect: ERROR, FAILED, EXCEPTION, TIMEOUT
filterPattern: logs.FilterPattern.anyTerm(
  '{ ($.level = "ERROR") }',
  '{ ($.message = "*ERROR*") }',
  '{ ($.message = "*FAILED*") }',
  '{ ($.message = "*EXCEPTION*") }',
  '{ ($.message = "*TIMEOUT*") }'
),
```

### Add Additional Subscriptions

Add more notification endpoints:

```typescript
// Add Slack webhook
this.snsTopic.addSubscription(new snsSubscriptions.UrlSubscription(slackWebhookUrl));

// Add SMS notifications
this.snsTopic.addSubscription(new snsSubscriptions.SmsSubscription(phoneNumber));
```

### Extend Lambda Processing

Modify the Lambda function code to add custom processing logic:

```typescript
// Add to the Lambda function code:
// - Query CloudWatch Logs for error context
// - Send notifications to external systems  
// - Trigger automated remediation actions
// - Create support tickets
// - Update dashboards
```

## Stack Outputs

After deployment, the stack provides these outputs:

- `LogGroupName` - CloudWatch Log Group name
- `LogGroupArn` - CloudWatch Log Group ARN
- `SnsTopicArn` - SNS Topic ARN for alerts
- `SnsTopicName` - SNS Topic name
- `AlarmArn` - CloudWatch Alarm ARN
- `LambdaFunctionArn` - Lambda function ARN
- `LambdaFunctionName` - Lambda function name

## Cleanup

To remove all resources:

```bash
npm run destroy
```

Confirm the deletion when prompted.

## Cost Considerations

This solution uses AWS services with the following cost implications:

- **CloudWatch Logs**: Pay for data ingested and stored
- **CloudWatch Metrics**: Custom metrics charges apply
- **CloudWatch Alarms**: Per alarm monthly charges
- **SNS**: Pay per message sent
- **Lambda**: Pay per execution and duration

Estimated monthly cost for moderate usage: $5-15

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Insufficient Permissions**
   - Ensure AWS credentials have necessary permissions
   - Check IAM policies for CloudWatch, SNS, Lambda access

3. **Email Subscription Not Working**
   - Check email for confirmation message
   - Confirm subscription in SNS console

4. **Alarm Not Triggering**
   - Verify metric filter pattern matches your log format
   - Check CloudWatch metrics for ApplicationErrors data
   - Ensure sufficient test events to exceed threshold

### Debug Commands

```bash
# Check stack status
cdk list
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name BasicLogMonitoringStack

# Check Lambda function logs
aws logs tail /aws/lambda/log-processor-basiclogmonitoringstack --follow
```

## Security Best Practices

- Use least privilege IAM policies
- Enable CloudTrail logging for audit trails
- Consider VPC deployment for production workloads
- Rotate SNS topic access policies regularly
- Monitor Lambda function security with GuardDuty

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [CloudWatch Logs Documentation](https://docs.aws.amazon.com/cloudwatch/latest/logs/)
- [SNS Documentation](https://docs.aws.amazon.com/sns/)
- [Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)