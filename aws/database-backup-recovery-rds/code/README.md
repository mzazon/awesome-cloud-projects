# Infrastructure as Code for Database Backup and Point-in-Time Recovery Strategies

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Backup and Recovery with RDS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML format)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive backup and recovery strategy using:

- **Amazon RDS**: MySQL database instance with automated backups
- **AWS Backup**: Centralized backup management and cross-region replication
- **AWS KMS**: Encryption for backups at rest
- **AWS IAM**: Service roles and policies for backup operations
- **Amazon CloudWatch**: Monitoring and alerting for backup operations
- **Amazon SNS**: Notifications for backup failures
- **Cross-Region Replication**: Disaster recovery capabilities

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - RDS (create, modify, delete instances)
  - AWS Backup (create vaults, plans, selections)
  - KMS (create keys, manage key policies)
  - IAM (create roles, attach policies)
  - CloudWatch (create alarms)
  - SNS (create topics)
- Basic understanding of database backup concepts
- For CDK: Node.js 18+ (TypeScript) or Python 3.9+ (Python)
- For Terraform: Terraform 1.0+ installed

## Cost Considerations

Estimated monthly costs for test environment:
- RDS db.t3.micro: ~$15-25
- AWS Backup storage: ~$5-10 per 10GB
- Cross-region backup replication: ~$10-20
- KMS key usage: ~$1-2

**Total estimated cost: $31-57/month for test resources**

Production costs will vary significantly based on database size, backup frequency, and retention policies.

## Quick Start

### Using CloudFormation

Deploy the complete infrastructure stack:

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name rds-backup-recovery \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DatabaseInstanceClass,ParameterValue=db.t3.micro \
                 ParameterKey=DatabasePassword,ParameterValue=TempPassword123! \
                 ParameterKey=BackupRetentionPeriod,ParameterValue=7 \
                 ParameterKey=CrossRegionBackupRetention,ParameterValue=14

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name rds-backup-recovery \
    --query 'Stacks[0].StackStatus'

# Wait for stack to complete
aws cloudformation wait stack-create-complete \
    --stack-name rds-backup-recovery
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Deploy the stack
cdk deploy

# View deployed resources
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# View deployed resources
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# View deployed resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
aws rds describe-db-instances \
    --query 'DBInstances[?DBInstanceStatus==`available`].[DBInstanceIdentifier,DBInstanceStatus]' \
    --output table
```

## Validation and Testing

After deployment, validate the backup and recovery setup:

### 1. Verify RDS Instance Configuration

```bash
# Check RDS backup settings
aws rds describe-db-instances \
    --db-instance-identifier <your-db-instance-id> \
    --query 'DBInstances[0].[BackupRetentionPeriod,PreferredBackupWindow,StorageEncrypted]' \
    --output table
```

### 2. Test Point-in-Time Recovery

```bash
# Get latest restorable time
LATEST_RESTORE_TIME=$(aws rds describe-db-instances \
    --db-instance-identifier <your-db-instance-id> \
    --query 'DBInstances[0].LatestRestorableTime' \
    --output text)

# Create point-in-time recovery test
aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier <your-db-instance-id> \
    --target-db-instance-identifier <your-db-instance-id>-pitr-test \
    --restore-time "$LATEST_RESTORE_TIME" \
    --db-instance-class db.t3.micro
```

### 3. Verify Backup Vault Contents

```bash
# List recovery points
aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name <your-backup-vault-name> \
    --query 'RecoveryPoints[*].[RecoveryPointArn,Status,CreationDate]' \
    --output table
```

### 4. Test Cross-Region Backup Replication

```bash
# Check cross-region automated backups
aws rds describe-db-instance-automated-backups \
    --region us-west-2 \
    --query 'DBInstanceAutomatedBackups[*].[Status,Region,DBInstanceIdentifier]' \
    --output table
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Valid Values |
|-----------|-------------|---------|--------------|
| `DatabaseInstanceClass` | RDS instance class | `db.t3.micro` | `db.t3.micro`, `db.t3.small`, etc. |
| `DatabasePassword` | Master password | Required | 8+ characters |
| `BackupRetentionPeriod` | Backup retention (days) | `7` | `1-35` |
| `CrossRegionBackupRetention` | DR backup retention (days) | `14` | `1-35` |
| `DisasterRecoveryRegion` | DR region | `us-west-2` | Valid AWS regions |

### CDK Configuration

Modify the configuration variables in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// TypeScript example
const config = {
  databaseInstanceClass: 'db.t3.micro',
  backupRetentionPeriod: 7,
  crossRegionBackupRetention: 14,
  disasterRecoveryRegion: 'us-west-2'
};
```

### Terraform Variables

Edit `variables.tf` or create `terraform.tfvars`:

```hcl
# terraform.tfvars
database_instance_class = "db.t3.micro"
backup_retention_period = 7
cross_region_backup_retention = 14
disaster_recovery_region = "us-west-2"
```

## Monitoring and Alerting

The solution includes CloudWatch alarms for:

- **Backup Job Failures**: Alerts when backup jobs fail
- **Database CPU Utilization**: Monitors RDS performance
- **Database Connections**: Tracks connection usage
- **Backup Vault Access**: Monitors vault access patterns

### View Backup Monitoring

```bash
# Check backup job status
aws backup list-backup-jobs \
    --by-state COMPLETED \
    --query 'BackupJobs[*].[BackupJobId,State,CreationDate]' \
    --output table

# View CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names "RDS-Backup-Failures-*" \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table
```

## Security Features

### Encryption

- **Database Encryption**: RDS instance encrypted at rest with KMS
- **Backup Encryption**: All backups encrypted with customer-managed KMS keys
- **Cross-Region Encryption**: Separate KMS keys for each region

### IAM Security

- **Least Privilege**: IAM roles with minimal required permissions
- **Service Roles**: Dedicated roles for AWS Backup operations
- **Cross-Account Access**: Optional backup vault access policies

### Network Security

- **VPC Isolation**: RDS deployed in private subnets
- **Security Groups**: Restricted database access
- **Encryption in Transit**: SSL/TLS encryption for database connections

## Disaster Recovery

### RTO and RPO Objectives

- **RTO (Recovery Time Objective)**: 15-30 minutes for point-in-time recovery
- **RPO (Recovery Point Objective)**: 5 minutes (transaction log frequency)

### Cross-Region Failover

```bash
# Restore from cross-region backup
aws rds restore-db-instance-from-db-snapshot \
    --region us-west-2 \
    --db-instance-identifier <failover-db-instance-id> \
    --db-snapshot-identifier <cross-region-snapshot-id> \
    --db-instance-class db.t3.micro
```

## Cleanup

### Using CloudFormation

```bash
# Delete test restore instances first
aws rds delete-db-instance \
    --db-instance-identifier <your-db-instance-id>-pitr-test \
    --skip-final-snapshot \
    --delete-automated-backups

# Delete the main stack
aws cloudformation delete-stack \
    --stack-name rds-backup-recovery

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name rds-backup-recovery
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm destruction
# Type 'y' when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

## Troubleshooting

### Common Issues

1. **Backup Job Failures**
   - Check IAM permissions for backup service role
   - Verify KMS key policies allow backup service access
   - Review CloudWatch logs for detailed error messages

2. **Cross-Region Replication Issues**
   - Ensure KMS keys exist in target region
   - Verify cross-region replication is enabled
   - Check network connectivity between regions

3. **Point-in-Time Recovery Failures**
   - Verify backup retention period covers desired restore time
   - Check that automated backups are enabled
   - Ensure sufficient storage for restored instance

### Debugging Commands

```bash
# Check backup service role permissions
aws iam get-role --role-name <backup-role-name>

# View backup job details
aws backup describe-backup-job \
    --backup-job-id <backup-job-id>

# Check KMS key policy
aws kms get-key-policy \
    --key-id <kms-key-id> \
    --policy-name default
```

## Best Practices

1. **Regular Testing**: Test restore procedures monthly
2. **Monitoring**: Set up comprehensive CloudWatch alarms
3. **Documentation**: Maintain recovery runbooks
4. **Automation**: Use infrastructure as code for consistency
5. **Security**: Regularly rotate KMS keys and review IAM policies
6. **Cost Optimization**: Use lifecycle policies to transition old backups to cold storage

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review CloudWatch logs for detailed error messages
3. Consult AWS documentation for specific services
4. Refer to the original recipe documentation for implementation details

## Additional Resources

- [AWS Backup Documentation](https://docs.aws.amazon.com/aws-backup/)
- [Amazon RDS Backup and Restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_CommonTasks.BackupRestore.html)
- [AWS Well-Architected Framework - Reliability](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)
- [RDS Cross-Region Automated Backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/AutomatedBackups.Replicating.html)