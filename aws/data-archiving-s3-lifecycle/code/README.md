# Infrastructure as Code for Data Archiving Solutions with S3 Lifecycle

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Archiving Solutions with S3 Lifecycle".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for S3, CloudWatch, and IAM operations
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $1-5 for testing with small amounts of data

> **Note**: This solution uses multiple S3 storage classes which have different minimum storage durations and retrieval fees. Review the [S3 Storage Classes documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html) before implementing in production.

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name data-archiving-s3-lifecycle \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-archiving-bucket-$(date +%s)
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys:

- **S3 Bucket** with versioning enabled for data archiving
- **Lifecycle Policies** for automated transitions between storage classes:
  - Documents: Standard → IA (30 days) → Glacier (90 days) → Deep Archive (365 days)
  - Logs: Standard → IA (7 days) → Glacier (30 days) → Deep Archive (90 days) → Delete (7 years)
  - Backups: Standard → IA (1 day) → Glacier (30 days)
  - Media: Intelligent Tiering for automatic optimization
- **S3 Intelligent Tiering** configuration for media files
- **S3 Inventory** for daily storage tracking and cost analysis
- **S3 Analytics** for storage class analysis and optimization recommendations
- **CloudWatch Alarms** for monitoring storage costs and object counts
- **IAM Role and Policy** for lifecycle management operations

## Configuration Options

### CloudFormation Parameters

- `BucketName`: Name for the S3 bucket (default: auto-generated)
- `EnableCostAlerts`: Enable CloudWatch cost monitoring (default: true)
- `EnableAnalytics`: Enable S3 Analytics for optimization (default: true)
- `LogRetentionDays`: Log file retention period in days (default: 2555)

### CDK Configuration

Modify the configuration in the CDK app files:

```typescript
// CDK TypeScript - app.ts
const config = {
  bucketName: 'my-archiving-bucket',
  enableCostAlerts: true,
  enableAnalytics: true,
  logRetentionDays: 2555
};
```

```python
# CDK Python - app.py
config = {
    "bucket_name": "my-archiving-bucket",
    "enable_cost_alerts": True,
    "enable_analytics": True,
    "log_retention_days": 2555
}
```

### Terraform Variables

Edit `terraform.tfvars` or provide variables during apply:

```hcl
bucket_name = "my-archiving-bucket"
enable_cost_alerts = true
enable_analytics = true
log_retention_days = 2555
aws_region = "us-east-1"
```

## Testing the Deployment

After deployment, test the solution:

1. **Upload Sample Data**:
   ```bash
   # Create test files
   echo "Test document" > test-document.txt
   echo "Test log entry" > test-log.log
   
   # Upload to different prefixes
   aws s3 cp test-document.txt s3://your-bucket-name/documents/
   aws s3 cp test-log.log s3://your-bucket-name/logs/
   ```

2. **Verify Lifecycle Configuration**:
   ```bash
   aws s3api get-bucket-lifecycle-configuration \
       --bucket your-bucket-name
   ```

3. **Check Intelligent Tiering**:
   ```bash
   aws s3api list-bucket-intelligent-tiering-configurations \
       --bucket your-bucket-name
   ```

4. **Monitor CloudWatch Metrics**:
   ```bash
   aws cloudwatch list-metrics \
       --namespace AWS/S3 \
       --dimensions Name=BucketName,Value=your-bucket-name
   ```

## Cost Optimization Features

- **Automated Transitions**: Objects automatically move to cheaper storage classes based on age
- **Intelligent Tiering**: Media files optimize costs based on access patterns
- **Lifecycle Expiration**: Log files automatically delete after 7 years
- **Cost Monitoring**: CloudWatch alarms notify of unexpected cost increases
- **Usage Analytics**: S3 Analytics provides optimization recommendations

## Security Features

- **IAM Least Privilege**: Role with minimal required permissions for lifecycle operations
- **Bucket Versioning**: Enabled for data protection and compliance
- **Access Logging**: Optional S3 access logging for security monitoring
- **Encryption**: Server-side encryption enabled by default

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack \
    --stack-name data-archiving-s3-lifecycle
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

> **Warning**: Cleanup will permanently delete all data in the S3 bucket. Ensure you have backups of any important data before proceeding.

## Customization

### Adding New Data Types

To add lifecycle policies for new data types, modify the lifecycle configuration:

1. **CloudFormation**: Add new rules to the `LifecycleConfiguration` property
2. **CDK**: Add new lifecycle rules in the bucket configuration
3. **Terraform**: Add new lifecycle rules to the `aws_s3_bucket_lifecycle_configuration` resource

### Modifying Transition Schedules

Adjust the `Days` values in lifecycle rules based on your data access patterns:

- **Frequent Access**: Keep in Standard storage longer
- **Infrequent Access**: Transition to IA sooner
- **Archive Requirements**: Adjust Glacier and Deep Archive timing
- **Compliance**: Set appropriate expiration policies

### Integration with Existing Infrastructure

- **VPC Endpoints**: Add S3 VPC endpoints for private network access
- **Cross-Region Replication**: Enable for disaster recovery
- **Event Notifications**: Add S3 event triggers for automation
- **Data Catalogs**: Integrate with AWS Glue for metadata management

## Monitoring and Alerting

The solution includes several monitoring components:

- **Cost Alarms**: Alert when storage costs exceed thresholds
- **Object Count Monitoring**: Track bucket growth patterns
- **Storage Class Distribution**: Analyze cost optimization effectiveness
- **Access Pattern Analysis**: Identify optimization opportunities

## Troubleshooting

### Common Issues

1. **Lifecycle Policy Not Applied**:
   - Check IAM permissions for lifecycle operations
   - Verify policy syntax and filter conditions

2. **Intelligent Tiering Not Working**:
   - Ensure minimum object size requirements (128KB)
   - Check that objects are in supported storage classes

3. **Cost Alarms Not Triggering**:
   - Verify CloudWatch billing alerts are enabled in account settings
   - Check alarm threshold values and comparison operators

4. **Analytics Reports Missing**:
   - Analytics reports take 24-48 hours to generate initially
   - Verify S3 Analytics configuration and destination bucket permissions

### Support Resources

- [S3 Lifecycle Management Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [S3 Intelligent Tiering Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering-overview.html)
- [S3 Storage Classes Comparison](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [CloudWatch S3 Metrics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudwatch-monitoring.html)

## Support

For issues with this infrastructure code, refer to the original recipe documentation or the AWS documentation for specific services used in this solution.