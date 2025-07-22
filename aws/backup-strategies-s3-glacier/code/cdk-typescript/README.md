# Backup Strategies with S3 and Glacier - CDK TypeScript

This directory contains a CDK TypeScript implementation of a comprehensive backup strategy using Amazon S3, Glacier storage classes, Lambda functions, and EventBridge for automated backup orchestration.

## Architecture Overview

This solution implements:

- **S3 Bucket** with versioning, encryption, and intelligent lifecycle policies
- **Lifecycle Management** with automatic transitions to Infrequent Access, Glacier, and Deep Archive
- **Lambda Function** for backup orchestration and validation
- **EventBridge Rules** for scheduled daily and weekly backups
- **SNS Topic** for backup notifications and alerts
- **CloudWatch Alarms** for monitoring backup success and duration
- **Cross-Region Replication** (optional) for disaster recovery
- **IAM Roles** with least privilege access for secure operations

## Prerequisites

- Node.js 18.x or later
- AWS CLI v2 installed and configured
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- Appropriate AWS permissions for creating S3, Lambda, EventBridge, IAM, SNS, and CloudWatch resources

## Installation

1. Install dependencies:
   ```bash
   npm install
   ```

2. Bootstrap CDK (if not already done in your account/region):
   ```bash
   cdk bootstrap
   ```

## Configuration

You can customize the deployment by setting context variables:

```bash
# Set stack name
cdk deploy -c stackName=MyBackupStack

# Set environment
cdk deploy -c environment=prod

# Deploy with email notifications
cdk deploy --parameters notificationEmail=admin@example.com

# Enable cross-region replication
cdk deploy --parameters enableCrossRegionReplication=true \
           --parameters replicationDestinationRegion=us-west-2
```

## Deployment

### Quick Deploy

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# Deploy with confirmation
cdk deploy --require-approval never
```

### Deploy with Parameters

```bash
# Deploy with email notifications
cdk deploy --parameters notificationEmail=your-email@example.com

# Deploy with cross-region replication enabled
cdk deploy \
  --parameters enableCrossRegionReplication=true \
  --parameters replicationDestinationRegion=us-west-2 \
  --parameters notificationEmail=admin@example.com
```

## Testing

1. **Upload test data to the bucket**:
   ```bash
   aws s3 cp test-file.txt s3://backup-strategy-demo-xxxxxxxx/data/
   ```

2. **Manually trigger the backup function**:
   ```bash
   aws lambda invoke \
     --function-name backup-orchestrator-xxxxxxxx \
     --payload '{"backup_type":"test","source_prefix":"data/"}' \
     response.json
   ```

3. **Check backup notifications** in your email

4. **Monitor CloudWatch metrics** in the AWS Console

## Lifecycle Policy Details

The solution implements a comprehensive lifecycle policy:

- **Day 0-30**: S3 Standard storage class
- **Day 30-90**: Transition to S3 Infrequent Access
- **Day 90-365**: Transition to S3 Glacier Flexible Retrieval
- **Day 365+**: Transition to S3 Glacier Deep Archive
- **Non-current versions**: Follow similar pattern with 7-year retention

## Backup Schedule

- **Daily Backups**: Every day at 2:00 AM UTC (incremental)
- **Weekly Backups**: Every Sunday at 1:00 AM UTC (full)

You can modify the schedule by updating the EventBridge rules in the stack.

## Monitoring and Alerts

The solution includes CloudWatch alarms for:

- **Backup Failures**: Triggers when backup success metric drops below 1
- **Long Duration**: Triggers when backup takes longer than 10 minutes

Both alarms send notifications to the SNS topic.

## Cost Optimization

This solution optimizes costs through:

- **Intelligent Tiering**: Automatically moves objects between access tiers
- **Lifecycle Policies**: Transitions to cheaper storage classes over time
- **Serverless Architecture**: Pay-per-use Lambda execution
- **Scheduled Operations**: Backups run during low-cost periods

## Security Features

- **Encryption**: All S3 objects encrypted with S3-managed keys
- **Versioning**: Protects against accidental deletions
- **IAM Roles**: Least privilege access principles
- **Block Public Access**: Prevents accidental public exposure
- **VPC Endpoints**: Can be configured for private network access

## Customization

### Modifying Lifecycle Rules

Edit the `lifecycleRules` property in `BackupStrategyStack`:

```typescript
lifecycleRules: [
  {
    id: 'custom-lifecycle-rule',
    enabled: true,
    transitions: [
      {
        storageClass: s3.StorageClass.INFREQUENT_ACCESS,
        transitionAfter: cdk.Duration.days(7), // Custom transition
      },
      // Add more transitions...
    ],
  },
],
```

### Adding Custom Backup Logic

Modify the Lambda function code in the stack to implement custom backup logic:

```typescript
code: lambda.Code.fromAsset('lambda'), // Use external file
```

### Changing Backup Schedule

Update the EventBridge rules:

```typescript
schedule: events.Schedule.cron({
  minute: '0',
  hour: '6',  // Changed from 2 AM to 6 AM
  day: '*',
  month: '*',
  year: '*',
}),
```

## Troubleshooting

### Common Issues

1. **Deployment Fails**: Check AWS credentials and permissions
2. **Lambda Timeout**: Increase timeout in function configuration
3. **No Notifications**: Verify email subscription confirmation
4. **High Costs**: Review lifecycle policies and storage class transitions

### Debugging

1. **Check CloudWatch Logs**:
   ```bash
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/backup-orchestrator"
   ```

2. **View Stack Events**:
   ```bash
   cdk diff
   aws cloudformation describe-stack-events --stack-name BackupStrategyStack
   ```

3. **Test Lambda Function**:
   ```bash
   aws lambda invoke --function-name backup-orchestrator-xxxxxxxx test-output.json
   ```

## Cleanup

To remove all resources created by this stack:

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
cdk destroy --force
```

**Note**: The S3 bucket is configured with `autoDeleteObjects: true` for demo purposes. In production, you may want to disable this and manually manage bucket deletion.

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [S3 Lifecycle Management](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [S3 Intelligent Tiering](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering.html)
- [AWS Backup Best Practices](https://docs.aws.amazon.com/aws-backup/latest/devguide/best-practices.html)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)

## Support

For issues with this CDK implementation:

1. Check the [AWS CDK GitHub Issues](https://github.com/aws/aws-cdk/issues)
2. Review [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
3. Consult the original recipe documentation