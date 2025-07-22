# Basic Monitoring with CloudWatch Alarms - CDK TypeScript

This CDK TypeScript application implements basic monitoring using Amazon CloudWatch alarms and SNS notifications as described in the recipe "Basic Monitoring with CloudWatch Alarms".

## Architecture

This application creates:

- **SNS Topic**: For alarm notifications with email subscription
- **CloudWatch Alarms**:
  - High CPU Utilization (EC2) - triggers when CPU exceeds 80% for 2 evaluation periods
  - High Response Time (ALB) - triggers when response time exceeds 1 second for 3 evaluation periods
  - High Database Connections (RDS) - triggers when connections exceed 80 for 2 evaluation periods

## Prerequisites

- AWS CLI installed and configured
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for CloudWatch and SNS

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if not already done):
   ```bash
   npm run bootstrap
   ```

## Configuration

### Environment Variables

Set the following environment variable before deployment:

```bash
export NOTIFICATION_EMAIL="your-email@example.com"
```

### Context Parameters

Alternatively, you can pass parameters via CDK context:

```bash
cdk deploy -c notificationEmail=your-email@example.com
```

### Advanced Configuration

You can customize thresholds and other parameters:

```bash
cdk deploy \
  -c notificationEmail=your-email@example.com \
  -c cpuThreshold=75 \
  -c responseTimeThreshold=2.0 \
  -c dbConnectionsThreshold=100 \
  -c environment=prod
```

## Deployment

### Quick Deployment

```bash
# Set your email address
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
npm run deploy
```

### Step-by-Step Deployment

1. **Build the application**:
   ```bash
   npm run build
   ```

2. **Synthesize CloudFormation template**:
   ```bash
   npm run synth
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

## Validation

After deployment, verify the resources were created:

1. **Check SNS Topic**:
   ```bash
   aws sns list-topics --query "Topics[?contains(TopicArn, 'monitoring-alerts')]"
   ```

2. **Verify CloudWatch Alarms**:
   ```bash
   aws cloudwatch describe-alarms --query "MetricAlarms[].{Name:AlarmName,State:StateValue,Threshold:Threshold}"
   ```

3. **Confirm Email Subscription**:
   - Check your email for a confirmation message from AWS
   - Click the confirmation link to activate the subscription

## Testing

### Test Alarm Notification

You can manually trigger an alarm to test notifications:

```bash
# Get the alarm name from the stack outputs
ALARM_NAME=$(aws cloudformation describe-stacks \
  --stack-name BasicMonitoringStack \
  --query "Stacks[0].Outputs[?OutputKey=='CPUAlarmName'].OutputValue" \
  --output text)

# Trigger the alarm
aws cloudwatch set-alarm-state \
  --alarm-name "$ALARM_NAME" \
  --state-value ALARM \
  --state-reason "Testing alarm notification"

# Wait a moment, then reset
sleep 30
aws cloudwatch set-alarm-state \
  --alarm-name "$ALARM_NAME" \
  --state-value OK \
  --state-reason "Test completed"
```

## Cleanup

To remove all resources:

```bash
npm run destroy
```

Or using CDK directly:

```bash
cdk destroy
```

## Stack Outputs

The stack provides the following outputs:

- `SNSTopicArn`: ARN of the SNS topic for notifications
- `NotificationEmail`: Email address subscribed to notifications
- `CPUAlarmName`: Name of the CPU utilization alarm
- `ResponseTimeAlarmName`: Name of the response time alarm
- `DBConnectionsAlarmName`: Name of the database connections alarm

## Customization

### Modifying Thresholds

You can modify the alarm thresholds by updating the context parameters:

```bash
cdk deploy -c cpuThreshold=90 -c responseTimeThreshold=0.5
```

### Adding More Alarms

To add additional alarms, modify the `BasicMonitoringStack` class in `app.ts`:

```typescript
// Example: Add a Lambda error rate alarm
const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
  alarmName: `${alarmNamePrefix}-LambdaErrors`,
  alarmDescription: 'Triggers when Lambda error rate exceeds 5%',
  metric: new cloudwatch.Metric({
    namespace: 'AWS/Lambda',
    metricName: 'Errors',
    statistic: 'Sum',
    period: cdk.Duration.minutes(5),
  }),
  threshold: 5,
  comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  evaluationPeriods: 2,
});

lambdaErrorAlarm.addAlarmAction(snsAlarmAction);
```

## Troubleshooting

### Common Issues

1. **Email not confirmed**: Check your email for the SNS subscription confirmation
2. **Invalid email format**: Ensure the email address is properly formatted
3. **Permissions**: Verify you have the necessary AWS permissions for CloudWatch and SNS

### Debug Mode

For detailed CDK output:

```bash
cdk deploy --verbose
```

## Security Considerations

- The SNS topic is created with default encryption
- Email subscriptions require manual confirmation for security
- CloudWatch alarms follow the principle of least privilege

## Cost Optimization

- CloudWatch alarms cost $0.10 per alarm per month
- SNS email notifications are free for the first 1,000 emails per month
- Consider using composite alarms for cost optimization with multiple related metrics

## Contributing

To contribute to this example:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This example is licensed under the MIT License.