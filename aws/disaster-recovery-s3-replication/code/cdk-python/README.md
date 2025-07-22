# AWS CDK Python - S3 Cross-Region Replication Disaster Recovery

This directory contains an AWS CDK Python application that implements a comprehensive S3 Cross-Region Replication disaster recovery solution. The application creates all necessary infrastructure components including S3 buckets, IAM roles, CloudTrail logging, and CloudWatch monitoring.

## Architecture Overview

The CDK application deploys:

- **Source S3 Bucket**: Primary storage bucket with versioning in the primary region
- **Destination S3 Bucket**: Disaster recovery bucket with versioning in the DR region  
- **IAM Replication Role**: Service role with least-privilege permissions for replication
- **Cross-Region Replication**: Automatic replication configuration with STANDARD_IA storage class
- **CloudTrail**: Audit logging for all S3 API calls across both buckets
- **CloudWatch Alarms**: Monitoring for replication latency and failures
- **SNS Topic**: Notifications for replication alerts

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI v2** installed and configured with appropriate permissions
2. **Python 3.8+** installed on your system
3. **AWS CDK v2** installed globally: `npm install -g aws-cdk`
4. **AWS Account** with permissions for S3, IAM, CloudTrail, CloudWatch, and SNS
5. **Bootstrapped CDK environment** in both primary and DR regions

### Required AWS Permissions

Your AWS credentials need permissions for:
- S3 bucket creation and configuration
- IAM role creation and policy attachment
- CloudTrail creation and configuration
- CloudWatch alarm creation
- SNS topic creation
- Cross-region resource access

## Installation

1. **Clone or navigate** to this directory:
   ```bash
   cd aws/disaster-recovery-s3-cross-region-replication/code/cdk-python/
   ```

2. **Create a virtual environment** (recommended):
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Verify CDK installation**:
   ```bash
   cdk --version
   ```

## Configuration

### Environment Variables

Set the following environment variables or use CDK context:

```bash
# Required: AWS Account ID
export CDK_DEFAULT_ACCOUNT="123456789012"

# Optional: Override default regions
export PRIMARY_REGION="us-east-1"
export DR_REGION="us-west-2"
```

### CDK Context Configuration

You can also configure regions using CDK context in `cdk.json`:

```json
{
  "context": {
    "primary_region": "us-east-1",
    "dr_region": "us-west-2",
    "unique_suffix": "mycompany"
  }
}
```

### Custom Configuration

To customize the deployment, you can override context values:

```bash
# Deploy with custom regions
cdk deploy --context primary_region=eu-west-1 --context dr_region=eu-central-1

# Deploy with custom unique suffix
cdk deploy --context unique_suffix=prod-env-001

# Deploy to specific account
cdk deploy --context account=987654321098
```

## Deployment

### Bootstrap CDK (First Time Only)

Bootstrap CDK in both regions before first deployment:

```bash
# Bootstrap primary region
cdk bootstrap aws://123456789012/us-east-1

# Bootstrap DR region  
cdk bootstrap aws://123456789012/us-west-2
```

### Deploy the Stack

1. **Review the deployment plan**:
   ```bash
   cdk diff
   ```

2. **Deploy the infrastructure**:
   ```bash
   cdk deploy
   ```

   The deployment will create:
   - S3 buckets with unique names (e.g., `dr-source-a1b2c3`, `dr-destination-a1b2c3`)
   - IAM role for replication (`s3-replication-role-a1b2c3`)
   - CloudTrail for audit logging
   - CloudWatch alarms for monitoring
   - SNS topic for notifications

3. **Note the outputs**: After deployment, CDK will display important resource information:
   ```
   Outputs:
   DisasterRecoveryS3Primary.SourceBucketName = dr-source-a1b2c3
   DisasterRecoveryS3Primary.DestinationBucketName = dr-destination-a1b2c3
   DisasterRecoveryS3Primary.ReplicationRoleArn = arn:aws:iam::123456789012:role/s3-replication-role-a1b2c3
   DisasterRecoveryS3Primary.CloudTrailArn = arn:aws:cloudtrail:us-east-1:123456789012:trail/s3-replication-trail-a1b2c3
   DisasterRecoveryS3Primary.AlertTopicArn = arn:aws:sns:us-east-1:123456789012:s3-replication-alerts-a1b2c3
   ```

## Testing the Deployment

### Upload Test Files

```bash
# Get bucket names from CDK outputs
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name DisasterRecoveryS3Primary \
    --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
    --output text)

DEST_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name DisasterRecoveryS3Primary \
    --query 'Stacks[0].Outputs[?OutputKey==`DestinationBucketName`].OutputValue' \
    --output text)

# Upload test file
echo "Test file content $(date)" > test-file.txt
aws s3 cp test-file.txt s3://${SOURCE_BUCKET}/test-file.txt

# Wait for replication
sleep 60

# Verify replication
aws s3 ls s3://${DEST_BUCKET}/ --region us-west-2
```

### Monitor Replication

```bash
# Check replication metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name ReplicationLatency \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --dimensions Name=SourceBucket,Value=${SOURCE_BUCKET}
```

## Monitoring and Maintenance

### CloudWatch Dashboards

The application creates CloudWatch alarms for:
- **Replication Latency**: Alerts when replication takes longer than 15 minutes
- **Replication Failures**: Alerts when replication exceeds 30 minutes (indicating potential failure)

### SNS Notifications

To receive notifications, subscribe to the SNS topic:

```bash
# Get topic ARN from CDK outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name DisasterRecoveryS3Primary \
    --query 'Stacks[0].Outputs[?OutputKey==`AlertTopicArn`].OutputValue' \
    --output text)

# Subscribe email address
aws sns subscribe \
    --topic-arn ${TOPIC_ARN} \
    --protocol email \
    --notification-endpoint your-email@company.com
```

### Cost Optimization

The deployment includes several cost optimization features:
- **Lifecycle Rules**: Automatic transition to IA and Glacier storage classes
- **Incomplete Multipart Upload Cleanup**: Removes incomplete uploads after 7 days
- **STANDARD_IA Storage**: Replicated objects use cost-effective storage class

## Cleanup

### Remove Test Resources

```bash
# Remove test files
rm test-file.txt

# Clean up S3 objects (optional - handled automatically by CDK)
aws s3 rm s3://${SOURCE_BUCKET} --recursive
aws s3 rm s3://${DEST_BUCKET} --recursive
```

### Destroy the Stack

```bash
# Destroy all resources
cdk destroy

# Confirm deletion when prompted
```

**Note**: The S3 buckets are configured with `auto_delete_objects=True` and `removal_policy=RemovalPolicy.DESTROY`, so all objects and buckets will be automatically cleaned up during stack deletion.

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: If you see bootstrap errors, ensure CDK is bootstrapped in both regions
2. **Permissions Issues**: Verify your AWS credentials have sufficient permissions
3. **Region Mismatch**: Ensure you're deploying to the correct regions
4. **Bucket Name Conflicts**: The application uses unique suffixes to avoid naming conflicts

### Debug Mode

Enable debug logging for more detailed output:

```bash
cdk deploy --verbose
```

### CDK Doctor

Run CDK doctor to check your environment:

```bash
cdk doctor
```

## Advanced Configuration

### Custom Storage Classes

Modify the replication configuration to use different storage classes:

```python
# In app.py, modify the replication destination
destination=s3.CfnBucket.ReplicationDestinationProperty(
    bucket=f"arn:aws:s3:::{dest_bucket_name}",
    storage_class="GLACIER"  # Options: STANDARD, STANDARD_IA, REDUCED_REDUNDANCY, GLACIER, DEEP_ARCHIVE
)
```

### Multiple Replication Rules

Add multiple replication rules for different prefixes:

```python
# Add prefix-specific replication rules
rules=[
    s3.CfnBucket.ReplicationRuleProperty(
        id="documents-replication",
        status="Enabled",
        priority=1,
        filter=s3.CfnBucket.ReplicationRuleFilterProperty(
            prefix="documents/"
        ),
        destination=s3.CfnBucket.ReplicationDestinationProperty(
            bucket=f"arn:aws:s3:::{dest_bucket_name}",
            storage_class="STANDARD"
        )
    ),
    s3.CfnBucket.ReplicationRuleProperty(
        id="logs-replication",
        status="Enabled", 
        priority=2,
        filter=s3.CfnBucket.ReplicationRuleFilterProperty(
            prefix="logs/"
        ),
        destination=s3.CfnBucket.ReplicationDestinationProperty(
            bucket=f"arn:aws:s3:::{dest_bucket_name}",
            storage_class="GLACIER"
        )
    )
]
```

## Security Considerations

- **IAM Permissions**: The replication role follows the principle of least privilege
- **Bucket Policies**: Both buckets block all public access by default
- **Encryption**: S3-managed encryption is enabled on both buckets
- **CloudTrail**: Comprehensive audit logging for compliance
- **VPC Endpoints**: Consider adding VPC endpoints for private network access

## Contributing

To contribute improvements to this CDK application:

1. **Fork the repository** and create a feature branch
2. **Make your changes** following Python and CDK best practices
3. **Test thoroughly** in a development environment
4. **Update documentation** as needed
5. **Submit a pull request** with a clear description

## License

This CDK application is provided under the Apache License 2.0. See the main repository LICENSE file for details.

## Support

For support with this CDK application:
- **AWS CDK Documentation**: https://docs.aws.amazon.com/cdk/
- **AWS S3 Cross-Region Replication**: https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html
- **CDK Python Reference**: https://docs.aws.amazon.com/cdk/api/v2/python/
- **Recipe Documentation**: See the main recipe markdown file for detailed implementation guidance