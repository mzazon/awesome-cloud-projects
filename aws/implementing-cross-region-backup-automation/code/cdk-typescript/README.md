# Multi-Region Backup Strategies CDK TypeScript Implementation

This CDK TypeScript application implements a comprehensive multi-region backup strategy using AWS Backup, EventBridge, Lambda, and SNS. The solution provides automated backup orchestration across multiple AWS regions with intelligent monitoring and alerting capabilities.

## Architecture Overview

The solution deploys backup infrastructure across three regions:
- **Primary Region (us-east-1)**: Main backup operations and plan management
- **Secondary Region (us-west-2)**: Cross-region backup copies for disaster recovery
- **Tertiary Region (eu-west-1)**: Long-term archival storage

## Features

- 🔄 **Multi-Region Backup**: Automated cross-region backup replication
- 📅 **Lifecycle Management**: Intelligent tiering to cold storage and deletion policies
- 🔐 **Encryption**: KMS encryption for all backup data
- 📊 **Monitoring**: Real-time backup job monitoring via EventBridge
- 🚨 **Alerting**: SNS notifications for backup failures and completions
- 🏷️ **Tag-Based Selection**: Flexible resource selection using AWS tags
- ⚡ **Serverless Validation**: Lambda-based backup validation and quality checks

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for backup, IAM, EventBridge, Lambda, and SNS
- Bootstrap CDK in target regions (see Bootstrap section below)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

Update the context values in `cdk.json` or provide them via CLI:

```bash
# Set your organization name
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Configure regions and settings
npx cdk deploy --all \
  --context primaryRegion=us-east-1 \
  --context secondaryRegion=us-west-2 \
  --context tertiaryRegion=eu-west-1 \
  --context organizationName=YourCompany \
  --context notificationEmail=admin@yourcompany.com
```

### 3. Bootstrap CDK (if not already done)

```bash
# Bootstrap all target regions
npx cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-east-1
npx cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-west-2
npx cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/eu-west-1
```

### 4. Deploy the Stacks

```bash
# Deploy all stacks
npm run deploy

# Or deploy individual stacks
npm run deploy:primary    # Primary region stack
npm run deploy:secondary  # Secondary region stack
npm run deploy:tertiary   # Tertiary region stack
```

## Configuration Options

The following context parameters can be customized:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `primaryRegion` | Primary AWS region for backup operations | `us-east-1` |
| `secondaryRegion` | Secondary region for cross-region copies | `us-west-2` |
| `tertiaryRegion` | Tertiary region for long-term archival | `eu-west-1` |
| `organizationName` | Organization name for resource naming | `YourOrg` |
| `notificationEmail` | Email address for backup notifications | `admin@example.com` |

## Resource Tagging for Backup Inclusion

Resources must be tagged with the following tags to be included in backups:

```bash
# Tag your resources for backup inclusion
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true

aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:us-east-1:123456789012:db:mydb \
  --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true
```

Required tags:
- `Environment: Production`
- `BackupEnabled: true`

## Backup Schedule

The solution implements two backup rules:

### Daily Backups
- **Schedule**: Daily at 2:00 AM UTC
- **Retention**: 365 days
- **Cold Storage**: After 30 days
- **Cross-Region Copy**: To secondary region (us-west-2)

### Weekly Backups
- **Schedule**: Weekly on Sundays at 3:00 AM UTC
- **Retention**: 7 years (2555 days)
- **Cold Storage**: After 90 days
- **Cross-Region Copy**: To tertiary region (eu-west-1)

## Monitoring and Alerting

The solution includes:

1. **EventBridge Rules**: Monitor backup job state changes
2. **Lambda Validation**: Automated backup validation and quality checks
3. **SNS Notifications**: Email alerts for backup failures
4. **CloudWatch Logs**: Comprehensive logging for troubleshooting

## Cost Optimization

The solution includes several cost optimization features:

- **Lifecycle Policies**: Automatic transition to cold storage
- **Intelligent Tiering**: Different retention periods for daily vs. weekly backups
- **Tag-Based Selection**: Only backup resources explicitly tagged
- **Regional Strategy**: Optimize cross-region transfer costs

## Security Features

- 🔐 **KMS Encryption**: All backups encrypted with customer-managed keys
- 🔒 **Access Policies**: Backup vault access policies prevent unauthorized deletion
- 🛡️ **IAM Roles**: Least privilege access for all service roles
- 🚫 **Secure Transport**: Enforce HTTPS for all backup operations

## Useful Commands

```bash
# Synthesize CloudFormation templates
npm run synth

# View differences before deployment
npm run diff

# Run tests
npm test

# Clean up resources
npm run destroy
```

## Validation

After deployment, verify the setup:

1. **Check Backup Vaults**:
   ```bash
   aws backup list-backup-vaults --region us-east-1
   aws backup list-backup-vaults --region us-west-2
   aws backup list-backup-vaults --region eu-west-1
   ```

2. **Verify Backup Plan**:
   ```bash
   aws backup list-backup-plans --region us-east-1
   ```

3. **Test SNS Subscription**:
   Check your email for the SNS subscription confirmation

4. **Trigger Test Backup**:
   ```bash
   aws backup start-backup-job \
     --backup-vault-name YourOrg-primary-vault \
     --resource-arn arn:aws:ec2:us-east-1:123456789012:instance/i-1234567890abcdef0 \
     --iam-role-arn arn:aws:iam::123456789012:role/AWSBackupServiceRole-us-east-1 \
     --region us-east-1
   ```

## Troubleshooting

### Common Issues

1. **Backup Plan Creation Fails**:
   - Ensure target backup vaults exist in destination regions
   - Verify IAM permissions for cross-region operations

2. **Lambda Function Timeout**:
   - Check CloudWatch Logs for the validator function
   - Increase timeout if needed for large backup jobs

3. **SNS Notifications Not Received**:
   - Confirm email subscription in SNS console
   - Check spam folder for confirmation emails

### Monitoring Resources

- **CloudWatch Logs**: `/aws/lambda/backup-validator-{region}`
- **EventBridge Rules**: Monitor backup job state changes
- **SNS Topics**: `backup-notifications-{region}`

## Cleanup

To remove all resources:

```bash
# Destroy all stacks
npm run destroy

# Or destroy individual stacks
npx cdk destroy MultiRegionBackupStackPrimary
npx cdk destroy MultiRegionBackupStackSecondary
npx cdk destroy MultiRegionBackupStackTertiary
```

**Warning**: Backup vaults with recovery points cannot be deleted. You may need to manually delete recovery points before destroying the stacks.

## Support

For issues with this implementation:
1. Check the original recipe documentation
2. Review CloudWatch Logs for error details
3. Consult AWS Backup documentation
4. Open an issue in the project repository

## License

This code is provided under the MIT License. See LICENSE file for details.