# Service Quota Monitoring with CloudWatch Alarms - CDK TypeScript

This CDK TypeScript application deploys automated AWS service quota monitoring using CloudWatch alarms and SNS notifications. The solution proactively tracks quota utilization for EC2 instances, VPCs, and Lambda concurrent executions, alerting teams before limits are reached.

## Architecture

The solution creates:
- **SNS Topic**: Central notification hub for quota alerts
- **CloudWatch Alarms**: Monitor service quota utilization for:
  - EC2 Running Instances (quota code: L-1216C47A)
  - VPCs per Region (quota code: L-F678F1CE)
  - Lambda Concurrent Executions (quota code: L-B99A9384)
- **Email Subscription**: Optional email notifications for quota alerts

## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate permissions
2. **Node.js**: Version 18.x or later
3. **AWS CDK**: Version 2.100.0 or later
4. **Permissions**: The deploying user/role needs permissions for:
   - CloudWatch (alarms, metrics)
   - SNS (topics, subscriptions)
   - CloudFormation (stack operations)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (First-time setup)

```bash
npx cdk bootstrap
```

### 3. Deploy with Default Settings

```bash
# Deploy without email notifications
npx cdk deploy

# Deploy with email notifications
npx cdk deploy -c notificationEmail=your-email@example.com
```

### 4. Confirm Email Subscription

If you provided an email address, check your inbox for a confirmation email from AWS SNS and click the confirmation link.

## Configuration Options

### Context Parameters

You can customize the deployment using CDK context parameters:

```bash
# Set notification email
npx cdk deploy -c notificationEmail=ops-team@company.com

# Set custom quota threshold (default: 80%)
npx cdk deploy -c quotaThreshold=75

# Disable email notifications
npx cdk deploy -c enableEmailNotification=false

# Combine multiple parameters
npx cdk deploy \
  -c notificationEmail=ops-team@company.com \
  -c quotaThreshold=85 \
  -c enableEmailNotification=true
```

### Stack Configuration

You can also modify the stack configuration directly in `app.ts`:

```typescript
new ServiceQuotaMonitoringStack(app, 'ServiceQuotaMonitoringStack', {
  notificationEmail: 'your-email@example.com',
  quotaThreshold: 80,
  enableEmailNotification: true,
  // ... other props
});
```

## Usage Examples

### Deploy for Production Environment

```bash
# Deploy with production-ready settings
npx cdk deploy \
  -c notificationEmail=production-alerts@company.com \
  -c quotaThreshold=75 \
  --require-approval never
```

### Deploy for Development Environment

```bash
# Deploy without email notifications for dev
npx cdk deploy \
  -c enableEmailNotification=false \
  -c quotaThreshold=90
```

### Test Alarm Configuration

After deployment, you can test the alarm system:

```bash
# Get the alarm names from stack outputs
aws cloudformation describe-stacks \
  --stack-name ServiceQuotaMonitoringStack \
  --query 'Stacks[0].Outputs'

# Test an alarm by setting it to ALARM state
aws cloudwatch set-alarm-state \
  --alarm-name "EC2-Running-Instances-Quota-Alert" \
  --state-value ALARM \
  --state-reason "Testing alarm notification system"

# Reset alarm state
aws cloudwatch set-alarm-state \
  --alarm-name "EC2-Running-Instances-Quota-Alert" \
  --state-value OK \
  --state-reason "Test complete"
```

## Monitoring and Validation

### View Stack Outputs

```bash
# View all stack outputs
npx cdk list --outputs

# Or use AWS CLI
aws cloudformation describe-stacks \
  --stack-name ServiceQuotaMonitoringStack \
  --query 'Stacks[0].Outputs'
```

### Check Alarm Status

```bash
# List all quota monitoring alarms
aws cloudwatch describe-alarms \
  --alarm-names \
    "EC2-Running-Instances-Quota-Alert" \
    "VPC-Quota-Alert" \
    "Lambda-Concurrent-Executions-Quota-Alert"
```

### Verify SNS Subscriptions

```bash
# List subscriptions for the topic (replace ARN with actual value)
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:region:account:service-quota-alerts-servicequotamonitoringstack
```

### View Service Quota Metrics

```bash
# Check current EC2 quota utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ServiceQuotas \
  --metric-name ServiceQuotaUtilization \
  --dimensions Name=ServiceCode,Value=ec2 Name=QuotaCode,Value=L-1216C47A \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Maximum
```

## Customization

### Adding Additional Service Quotas

To monitor additional service quotas, modify the `app.ts` file:

```typescript
// Example: Add RDS DB Instances quota monitoring
const rdsInstancesAlarm = new cloudwatch.Alarm(this, 'RDSInstancesQuotaAlarm', {
  alarmName: 'RDS-DB-Instances-Quota-Alert',
  alarmDescription: `Alert when RDS DB instances exceed ${quotaThreshold}% of quota`,
  metric: new cloudwatch.Metric({
    namespace: 'AWS/ServiceQuotas',
    metricName: 'ServiceQuotaUtilization',
    dimensionsMap: {
      'ServiceCode': 'rds',
      'QuotaCode': 'L-7B6409FD'  // DB instances quota code
    },
    statistic: 'Maximum',
    period: cdk.Duration.minutes(5)
  }),
  threshold: quotaThreshold,
  comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  evaluationPeriods: 1
});

rdsInstancesAlarm.addAlarmAction(new cloudwatchActions.SnsAction(quotaAlertsTopic));
```

### Changing Alarm Sensitivity

Modify the alarm evaluation parameters:

```typescript
const ec2InstancesAlarm = new cloudwatch.Alarm(this, 'EC2RunningInstancesQuotaAlarm', {
  // ... other properties
  evaluationPeriods: 2,  // Require 2 consecutive breaches
  datapointsToAlarm: 2,  // Both datapoints must be alarming
  treatMissingData: cloudwatch.TreatMissingData.BREACHING  // Treat missing data as breach
});
```

## Cost Considerations

- **CloudWatch Alarms**: $0.10 per alarm per month (first 10 alarms are free)
- **SNS Notifications**: $0.50 per 1 million email notifications
- **Total estimated cost**: $0.50-$2.00 per month for this solution

## Troubleshooting

### Common Issues

1. **No metrics available**: Some services may not have published quota metrics yet. Wait 5-10 minutes after account activity.

2. **Email notifications not received**: 
   - Check spam folder
   - Verify email subscription confirmation
   - Test with alarm state change

3. **Deployment failures**:
   - Ensure CDK is bootstrapped: `npx cdk bootstrap`
   - Check AWS credentials and permissions
   - Verify region supports Service Quotas

### Debug Commands

```bash
# Synthesize CloudFormation template without deploying
npx cdk synth

# Show differences between deployed and local template
npx cdk diff

# Enable verbose logging
npx cdk deploy --verbose

# Validate template
npx cdk synth --strict
```

## Cleanup

To remove all resources:

```bash
npx cdk destroy
```

Or manually delete through AWS Console:
1. Delete CloudWatch alarms
2. Delete SNS topic and subscriptions
3. Delete CloudFormation stack

## Security Best Practices

1. **Least Privilege**: The solution follows AWS security best practices with minimal required permissions
2. **No Hardcoded Secrets**: All configuration is passed through context or environment variables
3. **Resource Tagging**: All resources are tagged for governance and cost tracking
4. **Email Confirmation**: SNS email subscriptions require confirmation to prevent spam

## Support

For issues with this CDK application:
1. Check the [original recipe documentation](../../../service-quota-monitoring-cloudwatch.md)
2. Review AWS CDK documentation
3. Check AWS Service Quotas and CloudWatch documentation
4. Verify your AWS account has the necessary service limits

## Contributing

To extend this solution:
1. Fork the repository
2. Make your changes
3. Test thoroughly
4. Submit a pull request with documentation updates

## License

This code is provided under the MIT License. See the LICENSE file for details.