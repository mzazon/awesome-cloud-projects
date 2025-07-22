# Infrastructure as Code for Implementing Cross-Region Backup Automation with AWS Backup

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Cross-Region Backup Automation with AWS Backup".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS IAM permissions for:
  - AWS Backup (create backup plans, vaults, and selections)
  - IAM (create and manage service roles)
  - EventBridge (create rules and targets)
  - Lambda (create and invoke functions)
  - SNS (create topics and subscriptions)
  - CloudWatch (create log groups)
- Multiple AWS regions configured (minimum of 2, recommended 3)
- Existing AWS resources to be backed up (EC2 instances, RDS databases, DynamoDB tables, EFS file systems)
- Understanding of RPO/RTO requirements for your organization
- Estimated monthly cost: $50-200 depending on data volume and retention period

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Ability to create IAM roles and policies

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript compiler

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI installed (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0 or later
- AWS provider 5.0 or later

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the multi-region backup infrastructure
aws cloudformation create-stack \
    --stack-name multi-region-backup-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
                 ParameterKey=TertiaryRegion,ParameterValue=eu-west-1 \
                 ParameterKey=OrganizationName,ParameterValue=YourOrg \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor stack creation progress
aws cloudformation describe-stacks \
    --stack-name multi-region-backup-stack \
    --query 'Stacks[0].StackStatus' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Bootstrap CDK in required regions (if not already done)
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-east-1
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-west-2
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/eu-west-1

# Deploy the stack
cdk deploy \
    --parameters primaryRegion=us-east-1 \
    --parameters secondaryRegion=us-west-2 \
    --parameters tertiaryRegion=eu-west-1 \
    --parameters organizationName=YourOrg \
    --parameters notificationEmail=your-email@example.com
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Bootstrap CDK in required regions (if not already done)
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-east-1
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/us-west-2
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/eu-west-1

# Deploy the stack
cdk deploy \
    --parameters primaryRegion=us-east-1 \
    --parameters secondaryRegion=us-west-2 \
    --parameters tertiaryRegion=eu-west-1 \
    --parameters organizationName=YourOrg \
    --parameters notificationEmail=your-email@example.com
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat << EOF > terraform.tfvars
primary_region = "us-east-1"
secondary_region = "us-west-2"
tertiary_region = "eu-west-1"
organization_name = "YourOrg"
notification_email = "your-email@example.com"
environment = "production"
EOF

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
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
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| PRIMARY_REGION | Primary AWS region for backup operations | us-east-1 | Yes |
| SECONDARY_REGION | Secondary region for cross-region backup copies | us-west-2 | Yes |
| TERTIARY_REGION | Tertiary region for long-term archival | eu-west-1 | Yes |
| ORGANIZATION_NAME | Organization name for resource naming | - | Yes |
| NOTIFICATION_EMAIL | Email address for backup notifications | - | Yes |

### Resource Tagging Strategy

Resources must be tagged appropriately to be included in backup operations:

```bash
# Tag resources for backup inclusion
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true

# Tag RDS databases
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:region:account:db:database-name \
    --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true

# Tag DynamoDB tables
aws dynamodb tag-resource \
    --resource-arn arn:aws:dynamodb:region:account:table/table-name \
    --tags Key=Environment,Value=Production Key=BackupEnabled,Value=true
```

### Backup Plan Configuration

The solution creates two backup rules:

1. **Daily Backups with Cross-Region Copy**:
   - Schedule: Daily at 2:00 AM UTC
   - Retention: 365 days
   - Cross-region copy to secondary region
   - Lifecycle: Move to cold storage after 30 days

2. **Weekly Long-Term Archival**:
   - Schedule: Weekly on Sundays at 3:00 AM UTC
   - Retention: 7 years (2555 days)
   - Cross-region copy to tertiary region
   - Lifecycle: Move to cold storage after 90 days

## Validation

After deployment, verify the infrastructure:

```bash
# Check backup plan status
aws backup get-backup-plan \
    --backup-plan-id <backup-plan-id> \
    --region $PRIMARY_REGION

# Verify backup vaults in all regions
aws backup describe-backup-vault \
    --backup-vault-name YourOrg-primary-vault \
    --region $PRIMARY_REGION

aws backup describe-backup-vault \
    --backup-vault-name YourOrg-secondary-vault \
    --region $SECONDARY_REGION

aws backup describe-backup-vault \
    --backup-vault-name YourOrg-tertiary-vault \
    --region $TERTIARY_REGION

# Test SNS subscription
aws sns list-subscriptions-by-topic \
    --topic-arn <sns-topic-arn> \
    --region $PRIMARY_REGION

# Verify EventBridge rules
aws events list-rules \
    --name-prefix BackupJobFailureRule \
    --region $PRIMARY_REGION
```

## Monitoring and Alerts

The solution includes comprehensive monitoring:

- **EventBridge Rules**: Monitor backup job state changes
- **Lambda Validation**: Automated backup validation and notifications
- **SNS Notifications**: Email alerts for backup failures
- **CloudWatch Logs**: Detailed logging for troubleshooting

### Viewing Backup Jobs

```bash
# List recent backup jobs
aws backup list-backup-jobs \
    --max-results 10 \
    --region $PRIMARY_REGION

# List copy jobs for cross-region verification
aws backup list-copy-jobs \
    --region $SECONDARY_REGION \
    --max-results 10
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name multi-region-backup-stack \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name multi-region-backup-stack \
    --query 'Stacks[0].StackStatus' \
    --output text
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources:

```bash
# Delete backup vaults (only if empty)
aws backup delete-backup-vault \
    --backup-vault-name YourOrg-primary-vault \
    --region us-east-1

# Clean up IAM roles
aws iam delete-role \
    --role-name AWSBackupServiceRole

aws iam delete-role \
    --role-name BackupValidatorRole

# Delete SNS topics
aws sns delete-topic \
    --topic-arn <sns-topic-arn> \
    --region us-east-1
```

## Cost Optimization

### Storage Cost Management

- Backup storage costs scale with data volume
- Cross-region data transfer charges apply
- Lifecycle policies automatically move data to cheaper storage tiers
- Consider backup frequency vs. cost trade-offs

### Monitoring Costs

```bash
# Check backup storage utilization
aws backup describe-backup-vault \
    --backup-vault-name YourOrg-primary-vault \
    --region $PRIMARY_REGION \
    --query 'NumberOfRecoveryPoints'

# Monitor cross-region transfer costs in AWS Cost Explorer
# Filter by service: AWS Backup
# Group by: Region
```

## Security Considerations

- All backups are encrypted using AWS KMS
- IAM roles follow least privilege principle
- Cross-region copies maintain encryption
- EventBridge rules restrict access to backup events only
- Lambda function has minimal required permissions

## Troubleshooting

### Common Issues

1. **Backup Jobs Failing**:
   - Check resource tags (Environment=Production, BackupEnabled=true)
   - Verify IAM service role permissions
   - Review CloudWatch Logs for detailed error messages

2. **Cross-Region Copy Issues**:
   - Ensure destination backup vaults exist
   - Check cross-region permissions
   - Verify KMS key policies for encryption

3. **Notification Issues**:
   - Confirm SNS subscription
   - Check EventBridge rule configuration
   - Review Lambda function logs

### Debug Commands

```bash
# Check CloudWatch Logs for Lambda function
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/backup-validator" \
    --region $PRIMARY_REGION

# View recent backup job errors
aws backup list-backup-jobs \
    --by-state FAILED \
    --max-results 5 \
    --region $PRIMARY_REGION
```

## Customization

### Modifying Backup Schedules

Edit the backup plan configuration in your chosen IaC implementation:

- **CloudFormation**: Update `ScheduleExpression` in backup rules
- **CDK**: Modify `schedule` properties in backup plan rules
- **Terraform**: Update `rule.schedule` in `aws_backup_plan` resource

### Adding Additional Regions

1. Update region variables in your IaC configuration
2. Create additional backup vaults in new regions
3. Add copy actions to backup plan rules
4. Deploy the updated configuration

### Custom Validation Logic

Modify the Lambda function code to implement custom validation:

- Recovery point integrity checks
- Business-specific validation rules
- Integration with external monitoring systems
- Custom alerting logic

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS Backup documentation: https://docs.aws.amazon.com/backup/
3. Consult provider-specific documentation for your chosen IaC tool
4. Review AWS Well-Architected Framework for backup best practices

## Additional Resources

- [AWS Backup Developer Guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/)
- [AWS Backup Pricing](https://aws.amazon.com/backup/pricing/)
- [Cross-Region Backup with AWS Backup](https://aws.amazon.com/blogs/storage/cross-region-backup-with-aws-backup/)
- [AWS Well-Architected Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/)