# Automated Backup Solutions CDK TypeScript

This CDK TypeScript application deploys a comprehensive automated backup solution using AWS Backup with cross-region replication, monitoring, and compliance features.

## Architecture Overview

The solution includes:

- **Primary Backup Vault**: Encrypted backup storage in the primary region
- **DR Backup Vault**: Cross-region backup replication for disaster recovery
- **Backup Plans**: Daily and weekly backup schedules with different retention policies
- **Resource Selection**: Tag-based automatic inclusion of production resources
- **Monitoring**: CloudWatch alarms for backup failures and storage usage
- **Notifications**: SNS topic for backup event notifications
- **Compliance**: AWS Config rules for backup policy validation
- **Security**: Vault access policies to prevent unauthorized deletion

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- AWS CDK v2.152.0 or later installed globally: `npm install -g aws-cdk@latest`
- Appropriate AWS permissions for backup, IAM, CloudWatch, SNS, and S3
- Basic understanding of AWS Backup concepts and best practices

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

3. **Synthesize and review the CloudFormation template**:
   ```bash
   cdk synth
   ```

4. **Deploy the stack**:
   ```bash
   # Development deployment
   npm run deploy
   
   # Production deployment with security checks
   npm run deploy:prod
   ```

### Development Workflow

Use these npm scripts for efficient development:

```bash
# Build and watch for changes
npm run watch

# Run security checks only
npm run security-check

# Synthesize without CDK Nag
npm run synth:no-nag

# Type checking
npm run lint
```

## Security and Best Practices

This CDK application includes:

- **CDK Nag Integration**: Automated security checks using `cdk-nag`
- **AWS Well-Architected**: Follows AWS security and operational best practices  
- **Least Privilege**: IAM roles with minimal required permissions
- **Encryption**: All backups encrypted with AWS KMS
- **Compliance**: Built-in compliance monitoring and reporting

### Running Security Checks

CDK Nag is enabled by default and will run security checks during synthesis:

```bash
# Run with CDK Nag enabled (default)
cdk synth

# Disable CDK Nag if needed
cdk synth -c enableCdkNag=false
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION="us-west-2"                    # Primary region
export DR_REGION="us-east-1"                     # Disaster recovery region
export NOTIFICATION_EMAIL="admin@example.com"    # Optional: email for notifications
```

### CDK Context Parameters

You can customize the deployment using CDK context parameters:

```bash
# Custom retention periods
cdk deploy -c backupRetentionDays=45 -c weeklyRetentionDays=120

# Custom DR region
cdk deploy -c drRegion="eu-west-1"

# Email notifications and environment
cdk deploy -c notificationEmail="backup-admin@company.com" -c environment="production"

# Disable CDK Nag checks
cdk deploy -c enableCdkNag=false
```

### Context Configuration

Edit `cdk.json` to set default values:

```json
{
  "context": {
    "drRegion": "us-east-1",
    "backupRetentionDays": 30,
    "weeklyRetentionDays": 90,
    "environment": "development",
    "enableCdkNag": true,
    "notificationEmail": "admin@example.com"
  }
}
```

## Resource Tagging

Resources are automatically included in backups based on tags. Ensure your AWS resources have the following tag:

- **Key**: `Environment`
- **Value**: Matches your deployment environment (e.g., `production`, `development`, `staging`)

Example tagging of an EC2 instance:

```bash
# For production environment
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=production

# For development environment  
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=development
```

## Backup Schedules

### Daily Backups
- **Schedule**: Every day at 2:00 AM UTC
- **Retention**: 30 days (configurable)
- **Start Window**: 60 minutes
- **Completion Window**: 120 minutes
- **Cross-Region Copy**: Yes

### Weekly Backups
- **Schedule**: Every Sunday at 3:00 AM UTC
- **Retention**: 90 days (configurable)
- **Start Window**: 60 minutes
- **Completion Window**: 240 minutes
- **Cross-Region Copy**: Yes

## Monitoring and Alerting

The solution includes CloudWatch alarms for:

1. **Backup Job Failures**: Triggers when any backup job fails
2. **Storage Usage**: Alerts when backup storage exceeds 100 GB

Alerts are sent to the configured SNS topic. Subscribe to receive notifications:

```bash
aws sns subscribe \
    --topic-arn "arn:aws:sns:region:account:backup-notifications-topic" \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Security Features

### Backup Vault Security
- KMS encryption for all backups
- Access policies to prevent unauthorized deletion
- Cross-region replication for disaster recovery

### IAM Roles
- Dedicated service role for AWS Backup
- Least privilege access principles
- AWS managed policies for backup and restore operations

## Compliance and Governance

### AWS Config Rules
- Validates backup plan frequency and retention requirements
- Ensures backup policies meet organizational standards
- Provides compliance reporting for audits

### Backup Reports
- S3 bucket for storing backup compliance reports
- Automated report generation (when available in region)
- CSV and JSON format support

## Cost Optimization

### Lifecycle Management
- Automatic deletion of expired backups
- Different retention periods for daily vs. weekly backups
- Cross-region replication only for critical data

### Storage Classes
- Uses AWS Backup's intelligent tiering
- Automatic transition to cold storage for older backups

## Testing and Validation

### Verify Deployment

1. **Check backup vaults**:
   ```bash
   aws backup list-backup-vaults --region us-west-2
   aws backup list-backup-vaults --region us-east-1
   ```

2. **Verify backup plan**:
   ```bash
   aws backup list-backup-plans --region us-west-2
   ```

3. **Check resource selection**:
   ```bash
   aws backup list-backup-selections \
       --backup-plan-id <backup-plan-id> \
       --region us-west-2
   ```

### Monitor Backup Jobs

```bash
# List recent backup jobs
aws backup list-backup-jobs \
    --max-results 10 \
    --region us-west-2

# Check cross-region copy jobs
aws backup list-copy-jobs \
    --max-results 10 \
    --region us-west-2
```

## Troubleshooting

### Common Issues

1. **No backups running**: Ensure resources have the correct tags (`Environment: Production`)
2. **Cross-region replication failing**: Verify DR region backup vault exists
3. **Permission errors**: Check IAM role policies and trust relationships

### Debugging Commands

```bash
# Check backup job details
aws backup describe-backup-job --backup-job-id <job-id>

# List recovery points
aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name <vault-name>

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Backup \
    --metric-name NumberOfBackupJobsCompleted \
    --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum
```

## Cleanup

To remove all resources:

```bash
# Destroy the CDK stack
cdk destroy

# Note: You may need to manually delete recovery points before destroying backup vaults
```

## Advanced Configuration

### Custom Backup Selection

To backup specific resource types or use different selection criteria, modify the backup selection in `lib/automated-backup-stack.ts`:

```typescript
new backup.BackupSelection(this, 'CustomSelection', {
  backupPlan: this.backupPlan,
  selectionName: 'DatabaseBackups',
  role: backupRole,
  resources: [
    backup.BackupResource.fromArn('arn:aws:rds:*:*:db:*'),
    backup.BackupResource.fromTag('BackupRequired', 'true'),
  ],
});
```

### Multiple Backup Plans

For different backup requirements, create additional backup plans:

```typescript
const criticalBackupPlan = new backup.BackupPlan(this, 'CriticalBackupPlan', {
  backupPlanName: 'critical-resources-backup',
  backupPlanRules: [
    new backup.BackupPlanRule({
      ruleName: 'HourlyBackups',
      scheduleExpression: cdk.aws_events.Schedule.rate(cdk.Duration.hours(1)),
      deleteAfter: cdk.Duration.days(7),
    }),
  ],
});
```

## Support

- [AWS Backup Documentation](https://docs.aws.amazon.com/aws-backup/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Backup Best Practices](https://docs.aws.amazon.com/aws-backup/latest/devguide/best-practices.html)

## License

This project is licensed under the MIT License - see the LICENSE file for details.