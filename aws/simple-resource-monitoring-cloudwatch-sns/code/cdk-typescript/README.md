# CDK TypeScript - Simple Resource Monitoring with CloudWatch and SNS

This directory contains the AWS CDK TypeScript implementation for the Simple Resource Monitoring recipe. This implementation creates a complete monitoring solution using EC2, CloudWatch, and SNS services.

## Architecture Overview

This CDK application creates:

- **EC2 Instance**: A t2.micro instance running Amazon Linux 2023 for monitoring demonstration
- **SNS Topic**: For sending alert notifications via email
- **CloudWatch Alarms**: 
  - High CPU utilization alarm (>70% for 2 periods)
  - Instance status check failure alarm
- **IAM Roles**: Proper permissions for EC2 instance to work with SSM and CloudWatch
- **Security Group**: Basic security configuration for the EC2 instance

## Prerequisites

- AWS CLI installed and configured
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- AWS account with appropriate permissions for EC2, CloudWatch, SNS, and IAM
- Valid email address for receiving notifications

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

## Deployment

### Option 1: Deploy with Email Address via Context

```bash
# Deploy with email address provided as context
cdk deploy --context userEmail=your-email@example.com
```

### Option 2: Deploy with Environment Variable

```bash
# Set environment variable and deploy
export USER_EMAIL=your-email@example.com
cdk deploy
```

### Optional: Specify Key Pair for SSH Access

```bash
# Deploy with SSH key pair for EC2 access
cdk deploy \
  --context userEmail=your-email@example.com \
  --context keyPairName=your-key-pair-name
```

## Verification and Testing

After deployment, you'll receive outputs including:

- **InstanceId**: The EC2 instance ID for monitoring
- **SnsTopicArn**: The SNS topic ARN for alerts
- **HighCpuAlarmArn**: The CloudWatch alarm ARN
- **StressTestCommand**: AWS CLI command to trigger CPU load for testing

### Confirm Email Subscription

1. Check your email for an SNS subscription confirmation message
2. Click the "Confirm subscription" link in the email

### Test the Monitoring System

Use the stress test command from the deployment outputs:

```bash
# Replace INSTANCE-ID with the actual instance ID from outputs
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --instance-ids i-1234567890abcdef0 \
  --parameters 'commands=["/home/ec2-user/stress-test.sh"]'
```

Or manually generate CPU load:

```bash
# Connect via SSH or Session Manager and run:
stress-ng --cpu 4 --timeout 300s
```

### Monitor Alarm State

```bash
# Check alarm status
aws cloudwatch describe-alarms \
  --alarm-names SimpleResourceMonitoringStack-high-cpu-alarm \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' \
  --output table

# View alarm history
aws cloudwatch describe-alarm-history \
  --alarm-name SimpleResourceMonitoringStack-high-cpu-alarm \
  --max-records 5
```

## Customization

### Modifying Alarm Thresholds

Edit `app.ts` and modify the alarm configuration:

```typescript
// Change CPU threshold from 70% to your desired value
threshold: 80,  // Change this value

// Modify evaluation periods
evaluationPeriods: 3,  // Change this value
```

### Adding Additional Alarms

You can extend the stack to monitor additional metrics:

```typescript
// Example: Add memory utilization alarm (requires CloudWatch agent)
const memoryAlarm = new cloudwatch.Alarm(this, 'HighMemoryAlarm', {
  alarmName: `${id}-high-memory-alarm`,
  alarmDescription: 'Alert when memory exceeds 80%',
  metric: new cloudwatch.Metric({
    namespace: 'CWAgent',
    metricName: 'mem_used_percent',
    dimensionsMap: {
      InstanceId: monitoringInstance.instanceId
    },
    period: cdk.Duration.minutes(5),
    statistic: cloudwatch.Stats.AVERAGE
  }),
  threshold: 80,
  comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
  evaluationPeriods: 2
});
```

## Project Structure

```
cdk-typescript/
├── app.ts              # Main CDK application and stack definition
├── package.json        # Node.js dependencies and scripts
├── tsconfig.json       # TypeScript compiler configuration
├── cdk.json           # CDK CLI configuration
└── README.md          # This file
```

## Available Scripts

- `npm run build` - Compile TypeScript to JavaScript
- `npm run watch` - Watch for changes and compile automatically
- `npm run test` - Run unit tests (if implemented)
- `npm run cdk` - Run CDK CLI commands
- `npm run deploy` - Deploy the stack
- `npm run destroy` - Destroy the stack
- `npm run diff` - Show differences between deployed stack and current code
- `npm run synth` - Synthesize CloudFormation template

## Cleanup

To remove all resources created by this stack:

```bash
cdk destroy
```

This will:
- Terminate the EC2 instance
- Delete the CloudWatch alarms
- Delete the SNS topic (and unsubscribe email)
- Remove the IAM role and security group

## Cost Considerations

This stack creates the following billable resources:

- **EC2 t2.micro instance**: ~$8.50/month (free tier eligible for 750 hours/month)
- **CloudWatch alarms**: $0.10/alarm/month (2 alarms = $0.20/month)
- **SNS email notifications**: Free for first 1,000 emails/month
- **CloudWatch metrics**: Basic EC2 metrics are free

**Estimated Monthly Cost**: $0.20-$8.70 depending on free tier eligibility

## Troubleshooting

### Common Issues

1. **Email subscription not confirmed**
   - Check spam folder for SNS confirmation email
   - Redeploy if confirmation link expired

2. **Instance not appearing in CloudWatch**
   - Wait 5-10 minutes for metrics to populate
   - Ensure instance is in "running" state

3. **Alarms not triggering**
   - Verify alarm configuration with `aws cloudwatch describe-alarms`
   - Check alarm history for evaluation details

4. **Permission errors**
   - Ensure AWS CLI is configured with appropriate permissions
   - Verify CDK bootstrap has been run

### Getting Help

- Check CloudWatch alarm history for evaluation details
- Review CloudFormation events in AWS Console
- Use `cdk diff` to see what changes would be made
- Enable CDK debug logging: `cdk deploy --debug`

## Security Notes

- The security group allows SSH access from anywhere (0.0.0.0/0) for demonstration purposes
- In production, restrict SSH access to specific IP ranges
- The IAM role follows least privilege principles for SSM and CloudWatch access
- Consider using Session Manager instead of SSH for secure instance access

## Next Steps

Consider these enhancements for production use:

1. **Add CloudWatch agent** for custom metrics (memory, disk usage)
2. **Implement auto-scaling** based on CloudWatch alarms
3. **Add dashboard** for centralized monitoring view
4. **Set up log aggregation** with CloudWatch Logs
5. **Integrate with AWS Systems Manager** for automated remediation