# Infrastructure as Code for Backup and Archive Strategies with S3 Glacier

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Backup and Archive Strategies with S3 Glacier".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - IAM role creation and policy attachment
  - CloudWatch alarm creation
  - Glacier operations
- Basic understanding of S3 storage classes and lifecycle management
- Knowledge of data retention requirements and compliance needs
- Estimated cost: $5-15/month for testing (depends on data volume and retrieval frequency)

> **Note**: S3 Glacier storage classes have minimum storage duration charges. Objects deleted before the minimum duration will incur early deletion fees. See [S3 Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html) for detailed pricing information.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name backup-archive-strategies \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketNameSuffix,ParameterValue=demo-12345 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name backup-archive-strategies \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name backup-archive-strategies \
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

# Deploy the stack
cdk deploy

# List all stacks
cdk list

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
aws s3 ls | grep backup-archive

# Check lifecycle policies
aws s3api get-bucket-lifecycle-configuration \
    --bucket $(terraform output -raw backup_bucket_name)
```

## Infrastructure Components

This solution deploys:

### Core Storage Infrastructure
- **S3 Bucket** with versioning enabled for backup integrity
- **Lifecycle Policies** with multiple transition rules:
  - Backup data: Standard → IA (30d) → Glacier IR (90d) → Glacier (1y) → Deep Archive (7y)
  - Log data: Standard → IA (7d) → Glacier IR (30d) → Glacier (90d) → Delete (7y)
  - Documents: Standard → Glacier IR (60d) → Glacier (180d) → Deep Archive (3y)

### Security and Access Control
- **IAM Role** for Glacier operations with least privilege permissions
- **Data Retrieval Policy** limiting retrieval to 1GB/hour for cost control
- **Bucket policies** enforcing encryption and access controls

### Monitoring and Compliance
- **CloudWatch Alarms** for storage cost monitoring
- **Log Groups** for lifecycle transition tracking
- **Billing alerts** to prevent unexpected charges

### Sample Data and Testing
- **Sample backup files** demonstrating different data types
- **Tag-based classification** for document archiving
- **Test restore processes** validating retrieval workflows

## Configuration Options

### Customizable Parameters

- **Bucket Name Suffix**: Unique identifier for S3 bucket
- **AWS Region**: Deployment region for resources
- **Lifecycle Transition Days**: Customizable transition schedules
- **Cost Alert Threshold**: CloudWatch alarm threshold for billing
- **Data Retrieval Limit**: Glacier retrieval rate limiting
- **Retention Periods**: Different retention schedules by data type

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export BUCKET_NAME_SUFFIX=demo-$(date +%s)
export COST_ALERT_THRESHOLD=50.0
export DATA_RETRIEVAL_LIMIT=1073741824  # 1GB in bytes
```

## Testing and Validation

### Verify Deployment

```bash
# Check S3 bucket creation
aws s3 ls | grep backup-archive

# Verify lifecycle policies
aws s3api get-bucket-lifecycle-configuration \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX}

# Test sample data upload
echo "Test backup - $(date)" > test-backup.txt
aws s3 cp test-backup.txt s3://backup-archive-demo-${BUCKET_NAME_SUFFIX}/backups/

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names glacier-cost-alarm-${BUCKET_NAME_SUFFIX}
```

### Test Archive Retrieval

```bash
# Create test archive
aws s3 cp test-backup.txt s3://backup-archive-demo-${BUCKET_NAME_SUFFIX}/test-archive.txt \
    --storage-class GLACIER

# Initiate restore (takes 3-5 hours for Standard retrieval)
aws s3api restore-object \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
    --key test-archive.txt \
    --restore-request Days=7,GlacierJobParameters='{Tier=Standard}'

# Check restore status
aws s3api head-object \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
    --key test-archive.txt \
    --query 'Restore'
```

### Compliance Validation

```bash
# Generate compliance report
./scripts/compliance-report.sh backup-archive-demo-${BUCKET_NAME_SUFFIX}

# Check storage class distribution
aws s3api list-objects-v2 \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
    --query 'Contents[].StorageClass' | sort | uniq -c

# Verify cost monitoring
aws cloudwatch get-metric-statistics \
    --namespace AWS/Billing \
    --metric-name EstimatedCharges \
    --dimensions Name=Currency,Value=USD \
    --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Maximum
```

## Cost Optimization

### Storage Cost Breakdown

- **S3 Standard**: $0.023/GB/month (first 50TB)
- **S3 Infrequent Access**: $0.0125/GB/month
- **S3 Glacier Instant Retrieval**: $0.004/GB/month
- **S3 Glacier Flexible Retrieval**: $0.0036/GB/month
- **S3 Glacier Deep Archive**: $0.00099/GB/month

### Retrieval Costs

- **Glacier Standard**: $0.01/GB
- **Glacier Expedited**: $0.03/GB
- **Deep Archive Standard**: $0.02/GB

### Cost Optimization Tips

1. **Use Intelligent-Tiering** for unpredictable access patterns
2. **Monitor retrieval patterns** to optimize transition schedules
3. **Implement cost alerts** for unexpected usage spikes
4. **Regular compliance reviews** to identify optimization opportunities

## Cleanup

### Using CloudFormation

```bash
# Empty S3 bucket first (required for deletion)
aws s3 rm s3://backup-archive-demo-${BUCKET_NAME_SUFFIX} --recursive

# Delete versioned objects
aws s3api delete-objects \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
    --delete "$(aws s3api list-object-versions \
        --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"

# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name backup-archive-strategies

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name backup-archive-strategies \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
# Note: S3 bucket must be empty before CDK can delete it
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
aws s3 ls | grep backup-archive || echo "Cleanup successful"
```

## Security Considerations

### Data Protection

- **Encryption at Rest**: S3 SSE-S3 encryption enabled by default
- **Encryption in Transit**: HTTPS enforced for all S3 operations
- **Versioning**: Enabled for backup integrity and recovery
- **Access Control**: IAM roles with least privilege permissions

### Compliance Features

- **Audit Logging**: CloudTrail integration for API activity tracking
- **Data Governance**: Tag-based policies for compliance classification
- **Retention Policies**: Automated lifecycle management per regulatory requirements
- **Cost Controls**: Retrieval limits preventing unexpected charges

### Best Practices

- **Regular Security Reviews**: Quarterly assessment of IAM permissions
- **Monitor Access Patterns**: CloudWatch metrics for unusual activity
- **Backup Verification**: Regular restore testing for business continuity
- **Documentation**: Maintain compliance documentation for audits

## Troubleshooting

### Common Issues

1. **Lifecycle Policy Not Applied**:
   ```bash
   # Check policy syntax
   aws s3api get-bucket-lifecycle-configuration \
       --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX}
   ```

2. **Restore Request Failed**:
   ```bash
   # Verify object is in Glacier storage class
   aws s3api head-object \
       --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
       --key test-archive.txt
   ```

3. **Cost Alerts Not Working**:
   ```bash
   # Check CloudWatch alarm configuration
   aws cloudwatch describe-alarms \
       --alarm-names glacier-cost-alarm-${BUCKET_NAME_SUFFIX}
   ```

4. **IAM Permission Issues**:
   ```bash
   # Verify role permissions
   aws iam get-role --role-name GlacierOperationsRole
   aws iam list-attached-role-policies --role-name GlacierOperationsRole
   ```

### Debug Commands

```bash
# Check S3 bucket policies
aws s3api get-bucket-policy --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX}

# List all lifecycle configurations
aws s3api list-buckets --query 'Buckets[].Name' | xargs -I {} aws s3api get-bucket-lifecycle-configuration --bucket {}

# Monitor CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/s3/lifecycle

# Check billing and cost data
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Customization

### Extending the Solution

1. **Cross-Region Replication**: Add S3 CRR for disaster recovery
2. **Advanced Monitoring**: Implement custom CloudWatch dashboards
3. **Automated Backup**: Integrate with AWS Backup service
4. **Data Classification**: Implement AWS Macie for sensitive data discovery
5. **Cost Optimization**: Add AWS Cost Explorer integration

### Integration Examples

```bash
# Add S3 Cross-Region Replication
aws s3api put-bucket-replication \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
    --replication-configuration file://replication-config.json

# Enable S3 Transfer Acceleration
aws s3api put-bucket-accelerate-configuration \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
    --accelerate-configuration Status=Enabled

# Configure S3 Event Notifications
aws s3api put-bucket-notification-configuration \
    --bucket backup-archive-demo-${BUCKET_NAME_SUFFIX} \
    --notification-configuration file://notification-config.json
```

## Support

For issues with this infrastructure code, refer to:

- [Original Recipe Documentation](../backup-archive-strategies-s3-glacier-lifecycle-policies.md)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS Glacier Documentation](https://docs.aws.amazon.com/glacier/)
- [S3 Lifecycle Management](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [Archive Retrieval Options](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects-retrieval-options.html)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's security and governance policies before deploying to production environments.