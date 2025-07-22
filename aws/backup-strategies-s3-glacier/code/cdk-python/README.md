# AWS CDK Python Application for Backup Strategies with S3 and Glacier

This AWS CDK Python application deploys a comprehensive backup strategy using Amazon S3 with intelligent lifecycle transitions to Glacier storage classes, automated backup scheduling with Lambda functions, and event-driven notifications through EventBridge.

## Architecture Overview

The application creates:

- **S3 Bucket**: Primary backup storage with versioning, encryption, and lifecycle policies
- **Disaster Recovery Bucket**: Secondary bucket for cross-region replication
- **Lambda Function**: Backup orchestration with validation and monitoring
- **EventBridge Rules**: Scheduled backup execution (daily and weekly)
- **SNS Topic**: Notification system for backup status alerts
- **CloudWatch**: Monitoring dashboard and alarms for backup operations
- **IAM Roles**: Least privilege access for all components

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK CLI v2 installed (`npm install -g aws-cdk`)
- Virtual environment (recommended)

## Installation

1. **Create and activate a virtual environment**:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

The application accepts several configuration parameters through CDK context:

- `notification_email`: Email address for backup notifications
- `dr_region`: Disaster recovery region (default: us-west-2)
- `backup_retention_days`: Number of days to retain backup versions (default: 2555)

### Setting Configuration Parameters

You can set these parameters in multiple ways:

1. **Command line**:
   ```bash
   cdk deploy -c notification_email=admin@example.com -c dr_region=us-east-1
   ```

2. **Environment variables**:
   ```bash
   export CDK_CONTEXT_notification_email=admin@example.com
   export CDK_CONTEXT_dr_region=us-east-1
   ```

3. **Add to cdk.json**:
   ```json
   {
     "context": {
       "notification_email": "admin@example.com",
       "dr_region": "us-east-1",
       "backup_retention_days": 2555
     }
   }
   ```

## Deployment

1. **Synthesize the CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   With configuration:
   ```bash
   cdk deploy -c notification_email=your-email@example.com
   ```

3. **Confirm SNS subscription**: Check your email and confirm the SNS subscription to receive backup notifications.

## Usage

Once deployed, the backup system will automatically:

- Execute daily incremental backups at 2:00 AM UTC
- Execute weekly full backups on Sundays at 1:00 AM UTC
- Apply lifecycle policies to transition data through storage tiers:
  - Standard → IA (30 days)
  - IA → Glacier (90 days)
  - Glacier → Deep Archive (365 days)
- Send notifications for backup success/failure
- Monitor backup operations with CloudWatch alarms

### Manual Backup Execution

You can manually trigger a backup using the AWS CLI:

```bash
aws lambda invoke \
    --function-name <backup-function-name> \
    --payload '{"backup_type":"manual","source_prefix":"test/"}' \
    response.json
```

### Monitoring

Access the CloudWatch dashboard to monitor:
- Backup success rates
- Backup duration metrics
- Failed backup alerts

## Cost Optimization

The application implements several cost optimization strategies:

1. **Lifecycle Policies**: Automatic transition to cheaper storage classes
2. **Intelligent Tiering**: Automatic optimization based on access patterns
3. **Versioning Management**: Automatic cleanup of old versions
4. **Lambda Efficiency**: Event-driven execution minimizes compute costs

### Estimated Costs

- S3 Standard storage: ~$0.023 per GB/month
- S3 IA storage: ~$0.0125 per GB/month
- S3 Glacier: ~$0.004 per GB/month
- S3 Deep Archive: ~$0.00099 per GB/month
- Lambda execution: ~$0.20 per 1M requests
- CloudWatch metrics: ~$0.30 per metric/month

## Security Features

- **Encryption**: Server-side encryption (SSE-S3) for all data
- **Access Control**: Least privilege IAM roles and policies
- **Versioning**: Protection against accidental deletions
- **Public Access Block**: Prevents accidental public exposure
- **Cross-Region Replication**: Disaster recovery protection

## Customization

The CDK application is designed to be extensible. You can customize:

1. **Backup Schedules**: Modify EventBridge cron expressions
2. **Storage Classes**: Adjust lifecycle transition timing
3. **Retention Policies**: Change backup retention periods
4. **Notification Channels**: Add additional SNS subscriptions
5. **Monitoring**: Create custom CloudWatch dashboards

### Example Customizations

```python
# Custom backup schedule
daily_rule = events.Rule(
    self, "CustomBackupSchedule",
    schedule=events.Schedule.cron(
        minute="30",
        hour="3",
        day="*",
        month="*",
        year="*"
    ),
)

# Custom lifecycle policy
bucket.add_lifecycle_rule(
    id="custom-lifecycle",
    transitions=[
        s3.Transition(
            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
            transition_after=Duration.days(7)  # Faster transition
        ),
    ],
)
```

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: Ensure CDK is bootstrapped in your account/region
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Permission Errors**: Verify your AWS credentials have sufficient permissions for:
   - S3 bucket creation and management
   - Lambda function deployment
   - IAM role creation
   - EventBridge rule management
   - SNS topic creation

3. **Email Notifications Not Working**: Confirm SNS subscription in your email

4. **Cross-Region Issues**: Ensure the DR region supports all required services

### Debugging

Enable debug logging:
```bash
cdk deploy --debug
```

View CloudFormation events:
```bash
aws cloudformation describe-stack-events --stack-name BackupStrategiesStack
```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
cdk destroy
```

**Warning**: This will permanently delete all backup data and configurations. Ensure you have alternative backups before proceeding.

## Support

For issues specific to this CDK application:
1. Check the CloudWatch logs for the Lambda function
2. Review CloudFormation stack events
3. Verify IAM permissions and resource configurations

For AWS CDK issues, refer to the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/).

## License

This code is provided under the Apache License 2.0. See the LICENSE file for details.