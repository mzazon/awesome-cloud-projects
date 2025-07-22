# Infrastructure as Code for Automating Multi-Region Backup Strategies using AWS Backup

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating Multi-Region Backup Strategies using AWS Backup".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- AWS account with permissions for AWS Backup, EventBridge, IAM, Lambda, SNS, and CloudWatch
- Multiple AWS regions configured (minimum of 2, recommended 3)
- Existing AWS resources to be backed up (EC2 instances, RDS databases, DynamoDB tables, EFS file systems)
- Understanding of RPO/RTO requirements for your organization
- Estimated monthly cost: $50-200 depending on data volume and retention period

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI version 2.x or higher
- IAM permissions for CloudFormation stack operations

#### CDK TypeScript
- Node.js 18.x or higher
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript (`npm install -g typescript`)

#### CDK Python
- Python 3.8 or higher
- AWS CDK CLI (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0 or higher
- AWS provider for Terraform

#### Bash Scripts
- Bash shell environment
- jq for JSON processing
- AWS CLI configured with appropriate permissions

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name multi-region-backup-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
                 ParameterKey=TertiaryRegion,ParameterValue=eu-west-1 \
                 ParameterKey=OrganizationName,ParameterValue=YourOrg \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name multi-region-backup-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name multi-region-backup-stack \
    --region us-east-1 \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Review the deployment plan
cdk diff

# Deploy the infrastructure
cdk deploy --all

# View stack outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Review the deployment plan
cdk diff

# Deploy the infrastructure
cdk deploy --all

# View stack outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
export TERTIARY_REGION="eu-west-1"
export ORGANIZATION_NAME="YourOrg"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Environment Variables

All implementations support these environment variables for customization:

- `PRIMARY_REGION`: Primary AWS region for backup operations (default: us-east-1)
- `SECONDARY_REGION`: Secondary AWS region for backup replication (default: us-west-2)
- `TERTIARY_REGION`: Tertiary AWS region for long-term archival (default: eu-west-1)
- `ORGANIZATION_NAME`: Organization name prefix for resource naming (default: YourOrg)
- `BACKUP_PLAN_NAME`: Name for the backup plan (default: MultiRegionBackupPlan)
- `NOTIFICATION_EMAIL`: Email address for backup notifications

### Customizable Parameters

#### CloudFormation Parameters

- `PrimaryRegion`: Primary region for backup operations
- `SecondaryRegion`: Secondary region for disaster recovery
- `TertiaryRegion`: Tertiary region for long-term archival
- `OrganizationName`: Organization name for resource naming
- `NotificationEmail`: Email for backup notifications
- `BackupPlanName`: Name for the backup plan
- `DailyRetentionDays`: Retention period for daily backups (default: 365)
- `WeeklyRetentionDays`: Retention period for weekly backups (default: 2555)

#### Terraform Variables

Customize the deployment by modifying `terraform.tfvars` or passing variables:

```bash
terraform apply \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2" \
    -var="tertiary_region=eu-west-1" \
    -var="organization_name=YourOrg" \
    -var="notification_email=admin@yourorg.com"
```

## Resource Tagging Strategy

The infrastructure automatically tags resources for backup inclusion. Ensure your critical resources have these tags:

- `Environment`: Set to "Production" for backup inclusion
- `BackupEnabled`: Set to "true" to enable automatic backup
- `CriticalityLevel`: Optional tag for backup prioritization (High, Medium, Low)
- `DataClassification`: Optional tag for data classification compliance

Example tagging for existing resources:

```bash
# Tag EC2 instances
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=Production \
           Key=BackupEnabled,Value=true \
           Key=CriticalityLevel,Value=High

# Tag RDS instances
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:123456789012:db:mydb \
    --tags Key=Environment,Value=Production \
           Key=BackupEnabled,Value=true \
           Key=CriticalityLevel,Value=High
```

## Monitoring and Validation

### Verify Backup Plan Status

```bash
# List backup plans
aws backup list-backup-plans --region us-east-1

# Get backup plan details
aws backup get-backup-plan \
    --backup-plan-id <backup-plan-id> \
    --region us-east-1
```

### Monitor Backup Jobs

```bash
# List recent backup jobs
aws backup list-backup-jobs \
    --region us-east-1 \
    --max-results 20

# List cross-region copy jobs
aws backup list-copy-jobs \
    --region us-west-2 \
    --max-results 20
```

### Test Backup Functionality

```bash
# Start on-demand backup for testing
aws backup start-backup-job \
    --backup-vault-name YourOrg-primary-vault \
    --resource-arn "arn:aws:ec2:us-east-1:123456789012:instance/i-1234567890abcdef0" \
    --iam-role-arn "arn:aws:iam::123456789012:role/AWSBackupServiceRole" \
    --region us-east-1
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name multi-region-backup-stack \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name multi-region-backup-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the infrastructure
cdk destroy --all

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm destruction when prompted
```

## Cost Optimization

### Backup Storage Costs

- **Daily backups**: Automatically transition to cold storage after 30 days
- **Weekly backups**: Automatically transition to cold storage after 90 days
- **Cross-region data transfer**: Consider data transfer costs between regions
- **Storage classes**: Leverage AWS Backup's intelligent tiering

### Monitoring Costs

Set up billing alerts to monitor backup-related costs:

```bash
# Create billing alarm (requires SNS topic)
aws cloudwatch put-metric-alarm \
    --alarm-name "BackupCostAlert" \
    --alarm-description "Alert when backup costs exceed threshold" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 86400 \
    --threshold 100.0 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=Currency,Value=USD \
    --evaluation-periods 1
```

## Security Best Practices

### IAM Permissions

The solution implements least privilege access:

- AWS Backup service role with minimal required permissions
- Lambda execution role limited to backup validation functions
- EventBridge rules with specific resource access patterns

### Encryption

- All backup vaults use AWS KMS encryption
- Cross-region copies maintain encryption in transit and at rest
- Default AWS managed keys (alias/aws/backup) for cost optimization

### Network Security

- Lambda functions operate within VPC when required
- EventBridge rules restrict access to specific backup events
- SNS topics use encryption for notification delivery

## Troubleshooting

### Common Issues

1. **Backup Job Failures**
   - Verify IAM permissions for AWS Backup service role
   - Check resource tags for backup inclusion criteria
   - Review EventBridge rule configurations

2. **Cross-Region Copy Failures**
   - Ensure backup vaults exist in destination regions
   - Verify KMS key permissions across regions
   - Check network connectivity between regions

3. **Lambda Function Errors**
   - Review CloudWatch logs for Lambda execution errors
   - Verify SNS topic permissions for notifications
   - Check EventBridge rule patterns and targets

### Debugging Commands

```bash
# Check backup job details
aws backup describe-backup-job \
    --backup-job-id <job-id> \
    --region us-east-1

# Review Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/backup-validator"

# Check EventBridge rule status
aws events describe-rule \
    --name BackupJobFailureRule \
    --region us-east-1
```

## Advanced Configuration

### Custom Backup Windows

Modify backup schedules in the templates to align with maintenance windows:

```bash
# Example: Schedule backups during off-peak hours
# Modify ScheduleExpression in backup plan configuration
"ScheduleExpression": "cron(0 2 ? * MON-FRI *)"  # Weekdays at 2 AM UTC
```

### Additional Compliance Features

- Enable backup vault access policies for additional security
- Configure backup plan advanced features like continuous backups
- Implement custom backup validation logic in Lambda functions

## Support and Documentation

### Additional Resources

- [AWS Backup Developer Guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/)
- [AWS Backup API Reference](https://docs.aws.amazon.com/aws-backup/latest/devguide/api-reference.html)
- [AWS Backup Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/backup-recovery/aws-backup.html)
- [Cross-Region Backup Configuration](https://docs.aws.amazon.com/aws-backup/latest/devguide/cross-region-backup.html)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service health dashboards
3. Consult AWS Backup documentation
4. Contact AWS Support for service-specific issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate security and compliance requirements
3. Update documentation accordingly
4. Follow AWS best practices for infrastructure as code