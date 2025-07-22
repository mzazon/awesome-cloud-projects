# Infrastructure as Code for Automated Backup Solutions with AWS Backup

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Backup Solutions with AWS Backup".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Backup service operations
  - IAM role creation and management
  - CloudWatch alarms and metrics
  - SNS topic creation and management
  - S3 bucket creation (for backup reporting)
  - AWS Config (optional, for compliance monitoring)
  - Cross-region resource access
- Existing AWS resources tagged with `Environment: Production` for backup selection
- Basic understanding of AWS Backup concepts, backup strategies, and disaster recovery
- Valid email address for backup notifications

### Cost Considerations

- **Backup Storage**: $0.05 per GB-month for AWS Backup storage
- **Cross-Region Transfer**: $0.02 per GB for data transfer between regions
- **Restore Operations**: $0.02 per GB for data restore
- **CloudWatch**: Minimal costs for custom metrics and alarms
- **SNS**: $0.50 per 1 million notifications
- **Estimated Total**: $0.50-$5.00 per backup depending on data volume and retention policies

## Quick Start

### Using CloudFormation

```bash
aws cloudformation create-stack \
    --stack-name automated-backup-solution \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BackupPlanName,ParameterValue=enterprise-backup-plan \
                ParameterKey=DisasterRecoveryRegion,ParameterValue=us-east-1 \
                ParameterKey=NotificationEmail,ParameterValue=admin@example.com
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install
cdk bootstrap  # If not already bootstrapped
cdk deploy --parameters notificationEmail=admin@example.com
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # If not already bootstrapped
cdk deploy --parameters notification-email=admin@example.com
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan -var="notification_email=admin@example.com"
terraform apply -var="notification_email=admin@example.com"
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This solution implements a comprehensive automated backup strategy with the following components:

### Core Infrastructure
- **Primary Backup Vault**: Encrypted storage container in your primary AWS region
- **Disaster Recovery Backup Vault**: Secondary encrypted storage in your DR region
- **Backup Plans**: Policy-driven automation with daily and weekly schedules
- **IAM Service Role**: Least-privilege permissions for AWS Backup operations

### Cross-Region Disaster Recovery
- **Automatic Replication**: Real-time backup copying to disaster recovery region
- **Geographic Distribution**: Protection against regional failures
- **Consistent Security**: Same encryption and access controls across regions

### Monitoring and Alerting
- **CloudWatch Alarms**: Proactive monitoring for backup failures and storage usage
- **SNS Notifications**: Real-time alerts for all backup events
- **Backup Reporting**: Automated compliance and operational reports
- **Restore Testing**: Automated validation of backup integrity

### Security and Compliance
- **Vault Access Policies**: Immutable backup protection against ransomware
- **Encryption**: AWS KMS encryption for all backup data
- **Compliance Rules**: AWS Config integration for policy validation
- **Audit Trails**: CloudTrail logging for all backup operations

## Configuration

### Environment Variables (for Bash Scripts)

Set these variables before running the deployment scripts:

```bash
export AWS_REGION="us-west-2"                    # Primary region
export DR_REGION="us-east-1"                     # Disaster recovery region
export NOTIFICATION_EMAIL="admin@example.com"    # Email for notifications
export BACKUP_PLAN_NAME="enterprise-backup"      # Backup plan name prefix
export ENVIRONMENT_TAG="Production"              # Environment tag for resource selection
```

### Resource Tagging Strategy

The backup solution uses tags to automatically discover and protect resources:

- **Required Tag**: `Environment: Production`
- **Automatic Inclusion**: Resources with this tag are automatically protected
- **Dynamic Selection**: New resources with correct tags are automatically included
- **Governance**: Consistent tagging enables scalable backup management

### Backup Schedule Configuration

**Daily Backups**:
- Schedule: 2:00 AM UTC daily
- Retention: 30 days
- Cross-region copy: Enabled
- Start window: 60 minutes
- Completion window: 120 minutes

**Weekly Backups**:
- Schedule: 3:00 AM UTC every Sunday
- Retention: 90 days
- Cross-region copy: Enabled
- Start window: 60 minutes
- Completion window: 240 minutes

### Customizable Parameters

All implementations support these configuration options:

| Parameter | Default | Description |
|-----------|---------|-------------|
| Backup Schedule | Daily 2 AM, Weekly 3 AM Sunday | Cron expressions for backup timing |
| Retention Period | 30 days daily, 90 days weekly | Automatic lifecycle management |
| Cross-Region Replication | Enabled | Disaster recovery backup copying |
| Notification Events | All backup events | SNS alert configuration |
| Security Level | Vault lock enabled | Immutable backup protection |
| Compliance Monitoring | AWS Config rules | Automated policy validation |

## Monitoring and Alerts

### CloudWatch Metrics and Alarms

**Backup Job Monitoring**:
- Backup job success/failure rates
- Backup completion times
- Storage utilization trends
- Cross-region replication status

**Storage Management**:
- Backup vault storage consumption
- Storage cost optimization opportunities
- Lifecycle policy effectiveness
- Regional storage distribution

**Performance Metrics**:
- Backup duration and throughput
- Restore operation performance
- Network transfer efficiency
- Resource utilization patterns

### SNS Notification Events

The solution provides real-time notifications for:

- **Backup Operations**: Job started, completed, failed
- **Restore Operations**: Job started, completed, failed
- **Copy Operations**: Cross-region replication status
- **Vault Events**: Access policy changes, configuration updates
- **Compliance**: Policy violations, configuration drift

### Compliance and Governance

**AWS Config Integration**:
- Backup plan frequency validation
- Retention period compliance
- Cross-region replication verification
- Resource tag compliance

**Automated Restore Testing**:
- Weekly validation of backup integrity
- Automated restore operations
- Performance benchmarking
- Recovery time measurement

## Validation

After deployment, verify the solution using these commands:

### 1. Check Backup Plans
```bash
aws backup list-backup-plans --region $AWS_REGION
aws backup get-backup-plan --backup-plan-id <plan-id> --region $AWS_REGION
```

### 2. Verify Backup Vaults
```bash
aws backup list-backup-vaults --region $AWS_REGION
aws backup list-backup-vaults --region $DR_REGION
aws backup describe-backup-vault --backup-vault-name <vault-name> --region $AWS_REGION
```

### 3. Monitor Backup Jobs
```bash
aws backup list-backup-jobs --region $AWS_REGION
aws backup list-copy-jobs --region $AWS_REGION
aws backup list-restore-jobs --region $AWS_REGION
```

### 4. Test Monitoring Setup
```bash
aws sns list-topics --region $AWS_REGION
aws cloudwatch describe-alarms --region $AWS_REGION
aws logs describe-log-groups --log-group-name-prefix "/aws/backup" --region $AWS_REGION
```

### 5. Validate Cross-Region Replication
```bash
aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name <dr-vault-name> \
    --region $DR_REGION
```

## Cleanup

> **Important**: Backup vaults cannot be deleted while they contain recovery points. You must manually delete all recovery points before destroying the infrastructure.

### Pre-Cleanup: Remove Recovery Points

```bash
# List and delete recovery points in primary region
aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name <vault-name> \
    --region $AWS_REGION

# Delete each recovery point (replace with actual ARNs)
aws backup delete-recovery-point \
    --backup-vault-name <vault-name> \
    --recovery-point-arn <recovery-point-arn> \
    --region $AWS_REGION

# Repeat for DR region
aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name <dr-vault-name> \
    --region $DR_REGION
```

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name automated-backup-solution
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="notification_email=admin@example.com"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Security Considerations

### Encryption and Data Protection
- **AWS KMS Integration**: All backups encrypted with customer-managed or AWS-managed keys
- **Encryption in Transit**: All data transfers use TLS encryption
- **Access Controls**: IAM policies enforce least-privilege access
- **Vault Policies**: Additional protection layer against unauthorized access

### Ransomware Protection
- **Immutable Backups**: Vault lock prevents premature deletion
- **Cross-Region Isolation**: Geographic separation of backup copies
- **Access Logging**: CloudTrail audit trail for all backup operations
- **Monitoring**: Real-time alerts for suspicious activities

### Compliance Features
- **Data Residency**: Control over backup storage regions
- **Retention Policies**: Automated lifecycle management
- **Audit Trails**: Comprehensive logging and reporting
- **Access Reviews**: Regular validation of permissions

## Troubleshooting

### Common Issues and Solutions

**1. Backup Jobs Failing**
- **Symptom**: Backup jobs show FAILED status
- **Causes**: IAM permissions, resource tags, service compatibility
- **Solution**: Verify service role permissions and resource tags

```bash
# Check backup job details
aws backup describe-backup-job --backup-job-id <job-id>

# Verify IAM role permissions
aws iam get-role --role-name AWSBackupDefaultServiceRole
```

**2. Cross-Region Replication Issues**
- **Symptom**: Copy jobs failing or not starting
- **Causes**: DR vault permissions, region availability
- **Solution**: Verify cross-region permissions and vault configuration

```bash
# Check copy job status
aws backup list-copy-jobs --by-destination-vault-arn <dr-vault-arn>

# Verify DR region vault
aws backup describe-backup-vault --backup-vault-name <dr-vault> --region $DR_REGION
```

**3. CloudWatch Alarms Not Triggering**
- **Symptom**: No notifications despite backup failures
- **Causes**: SNS subscription, alarm configuration
- **Solution**: Verify SNS topic and subscription configuration

```bash
# Check alarm configuration
aws cloudwatch describe-alarms --alarm-names "AWS-Backup-Job-Failures"

# Verify SNS subscriptions
aws sns list-subscriptions-by-topic --topic-arn <sns-topic-arn>
```

**4. Vault Deletion Failures**
- **Symptom**: Cannot delete backup vault
- **Causes**: Existing recovery points, ongoing jobs
- **Solution**: Remove all recovery points and wait for jobs to complete

### Performance Optimization

**Backup Window Optimization**:
- Schedule backups during low-activity periods
- Stagger backup times across resources
- Monitor backup duration and adjust windows

**Storage Optimization**:
- Implement appropriate lifecycle policies
- Monitor storage costs and usage patterns
- Consider backup frequency based on business requirements

**Network Optimization**:
- Choose regions based on data locality
- Monitor cross-region transfer costs
- Optimize backup selection for network efficiency

## Advanced Configuration

### Custom Backup Schedules

Modify backup timing in IaC templates:

```yaml
# CloudFormation example
DailyBackupRule:
  ScheduleExpression: "cron(0 2 ? * * *)"  # Daily at 2 AM UTC
  StartWindowMinutes: 60                    # 1 hour start window
  CompletionWindowMinutes: 120              # 2 hour completion window

WeeklyBackupRule:
  ScheduleExpression: "cron(0 3 ? * SUN *)" # Sundays at 3 AM UTC
  StartWindowMinutes: 60
  CompletionWindowMinutes: 240              # 4 hour completion window
```

### Multi-Account Backup Strategy

For AWS Organizations integration:

```bash
# Enable cross-account backup sharing
aws backup put-backup-vault-access-policy \
    --backup-vault-name MyVault \
    --policy file://cross-account-policy.json

# Create organization-wide backup policies
aws organizations create-policy \
    --name BackupPolicy \
    --type BACKUP_POLICY \
    --content file://backup-policy.json
```

### Enhanced Compliance Monitoring

Deploy additional AWS Config rules:

```bash
# Backup plan compliance rule
aws configservice put-config-rule \
    --config-rule file://backup-plan-compliance.json

# Resource backup coverage rule
aws configservice put-config-rule \
    --config-rule file://backup-coverage-rule.json
```

### Integration Examples

**With AWS Security Hub**:
```bash
# Enable backup findings in Security Hub
aws securityhub batch-enable-standards \
    --standards-subscription-requests StandardsArn=arn:aws:securityhub:::ruleset/finding-format/aws-foundational-security-standard
```

**With AWS Systems Manager**:
```bash
# Automate backup validation with Systems Manager
aws ssm create-association \
    --name "AmazonInspector-ManageAWSAgent" \
    --targets Key=tag:Environment,Values=Production
```

**With AWS Lambda**:
```bash
# Custom backup notification processing
aws lambda create-function \
    --function-name backup-processor \
    --runtime python3.9 \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://backup-processor.zip
```

## Support Resources

- [AWS Backup User Guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/)
- [AWS Backup API Reference](https://docs.aws.amazon.com/aws-backup/latest/devguide/api-reference.html)
- [AWS Backup Best Practices](https://docs.aws.amazon.com/aws-backup/latest/devguide/best-practices.html)
- [AWS Backup Pricing](https://aws.amazon.com/backup/pricing/)
- [AWS Backup FAQs](https://aws.amazon.com/backup/faqs/)
- [Disaster Recovery Strategies](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html)

For issues with this infrastructure code, refer to the original recipe documentation or contact AWS Support for service-specific assistance.