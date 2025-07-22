# Multi-Region Backup Strategies CDK TypeScript Application

This CDK TypeScript application implements automated multi-region backup strategies using AWS Backup, EventBridge, Lambda, and SNS. The solution creates a comprehensive backup framework that ensures data can be recovered even if an entire region becomes unavailable.

## Architecture Overview

The application deploys the following components:

- **Backup Vaults**: Encrypted backup storage across multiple AWS regions
- **Backup Plans**: Automated backup schedules with cross-region copy destinations
- **IAM Roles**: Service roles with least privilege permissions for AWS Backup
- **EventBridge Rules**: Monitor backup job state changes for automation
- **Lambda Functions**: Backup validation and notification handling
- **SNS Topics**: Alert notifications for backup status updates
- **KMS Keys**: Encryption keys for backup vault security

## Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Node.js** (version 16.x or later)
3. **AWS CDK** (version 2.100.0 or later)
4. **TypeScript** compiler
5. **Multi-region access** to deploy stacks across regions

### Required AWS Permissions

Your AWS credentials must have permissions for:
- AWS Backup (create vaults, plans, selections)
- IAM (create roles and policies)
- EventBridge (create rules and targets)
- Lambda (create and manage functions)
- SNS (create topics and subscriptions)
- KMS (create and manage encryption keys)
- CloudFormation (deploy CDK stacks)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment Variables

Set the following environment variables or update the configuration in `app.ts`:

```bash
export ORGANIZATION_NAME="MyOrg"
export CDK_DEFAULT_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
export TERTIARY_REGION="eu-west-1"
export NOTIFICATION_EMAIL="admin@example.com"
```

### 3. Bootstrap CDK (if not already done)

Bootstrap CDK in all target regions:

```bash
# Bootstrap primary region
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1

# Bootstrap secondary region
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Bootstrap tertiary region
cdk bootstrap aws://ACCOUNT-NUMBER/eu-west-1
```

### 4. Build the Application

```bash
npm run build
```

### 5. Preview Changes

```bash
cdk diff --all
```

### 6. Deploy All Stacks

```bash
cdk deploy --all
```

The deployment will create three stacks:
- `MultiRegionBackupPrimaryStack` (primary region with backup plan)
- `MultiRegionBackupSecondaryStack` (secondary region for disaster recovery)
- `MultiRegionBackupTertiaryStack` (tertiary region for long-term archival)

## Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ORGANIZATION_NAME` | MyOrg | Prefix for resource names |
| `CDK_DEFAULT_REGION` | us-east-1 | Primary deployment region |
| `SECONDARY_REGION` | us-west-2 | Secondary backup region |
| `TERTIARY_REGION` | eu-west-1 | Tertiary archival region |
| `NOTIFICATION_EMAIL` | admin@example.com | Email for backup notifications |

### Customizing Backup Schedules

The backup plan includes two rules:

1. **Daily Backups**: Run at 2:00 AM UTC with 30-day cold storage transition
2. **Weekly Archival**: Run Sundays at 3:00 AM UTC with 90-day cold storage transition

To modify schedules, edit the `scheduleExpression` in `lib/multi-region-backup-stack.ts`:

```typescript
scheduleExpression: events.Schedule.cron({ hour: '2', minute: '0' })
```

### Resource Selection

The backup plan automatically selects resources with these tags:
- `Environment: Production`
- `BackupEnabled: true`

To backup your resources, ensure they have the appropriate tags:

```bash
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true
```

## Deployment Commands

### Build and Test

```bash
# Compile TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm test

# Synthesize CloudFormation
cdk synth
```

### Deploy Specific Stacks

```bash
# Deploy only primary stack
cdk deploy MultiRegionBackupPrimaryStack

# Deploy only secondary stack
cdk deploy MultiRegionBackupSecondaryStack

# Deploy only tertiary stack
cdk deploy MultiRegionBackupTertiaryStack
```

### View Stack Outputs

```bash
# List all stack outputs
aws cloudformation describe-stacks \
    --stack-name MultiRegionBackupPrimaryStack \
    --query 'Stacks[0].Outputs'
```

## Monitoring and Validation

### CloudWatch Logs

Monitor Lambda function execution:

```bash
aws logs tail /aws/lambda/backup-validator-us-east-1 --follow
```

### SNS Notifications

The solution sends email notifications for:
- Successful backup completions
- Backup job failures
- Validation errors

### Backup Job Status

Check backup job status:

```bash
# List recent backup jobs
aws backup list-backup-jobs --max-results 10

# Describe specific backup job
aws backup describe-backup-job --backup-job-id JOB-ID
```

### Cross-Region Copy Jobs

Verify cross-region copies:

```bash
# List copy jobs in secondary region
aws backup list-copy-jobs --region us-west-2
```

## Cost Optimization

The solution implements several cost optimization strategies:

1. **Lifecycle Policies**: Automatic transition to cold storage
2. **Retention Policies**: Automatic deletion of old backups
3. **Resource Selection**: Tag-based backup inclusion
4. **Regional Distribution**: Strategic placement for compliance and cost

### Estimated Costs

Monthly costs depend on:
- Number of resources backed up
- Data volume and storage duration
- Cross-region data transfer
- Lambda function executions

## Security Features

### Encryption
- KMS encryption for all backup vaults
- Automatic key rotation enabled
- Service-specific encryption policies

### Access Control
- Least privilege IAM roles
- Backup vault access policies
- Resource-based permissions

### Monitoring
- EventBridge integration for real-time monitoring
- CloudWatch logging for audit trails
- SNS notifications for immediate alerts

## Troubleshooting

### Common Issues

1. **Cross-Region Copy Failures**
   - Verify destination backup vaults exist
   - Check IAM permissions for cross-region access
   - Ensure KMS key policies allow cross-region access

2. **Resource Selection Issues**
   - Verify resource tags are applied correctly
   - Check backup selection conditions
   - Review IAM permissions for resource discovery

3. **Lambda Function Errors**
   - Check CloudWatch logs for detailed error messages
   - Verify SNS topic permissions
   - Ensure backup service permissions are correct

### Debugging Commands

```bash
# Check backup plan details
aws backup get-backup-plan --backup-plan-id PLAN-ID

# List backup selections
aws backup list-backup-selections --backup-plan-id PLAN-ID

# Describe backup vault
aws backup describe-backup-vault --backup-vault-name VAULT-NAME
```

## Cleanup

To remove all resources:

```bash
# Destroy all stacks
cdk destroy --all
```

**Warning**: This will delete all backup vaults and recovery points. Ensure you have alternative backups if needed.

## Support and Documentation

- [AWS Backup Developer Guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/)
- [CDK API Documentation](https://docs.aws.amazon.com/cdk/api/v2/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)

For issues with this CDK application, check CloudWatch logs and verify your AWS credentials and permissions.

## Contributing

When modifying this application:

1. Update TypeScript definitions in interfaces
2. Follow CDK and AWS security best practices
3. Test changes in a development environment
4. Update documentation and comments
5. Consider impact on existing backup schedules

## License

This CDK application is provided as-is for educational and operational purposes. Review AWS service costs and security implications before deploying in production environments.