# S3 Cross-Region Replication Disaster Recovery - CDK TypeScript

This CDK TypeScript application implements a comprehensive disaster recovery solution using Amazon S3 Cross-Region Replication (CRR). The solution automatically replicates data between AWS regions to ensure business continuity and data protection against regional disasters.

## Architecture

The solution deploys two stacks across two different AWS regions:

### Primary Stack (Source Region)
- **S3 Source Bucket**: Versioned bucket with lifecycle policies and security configurations
- **IAM Replication Role**: Least privilege role for cross-region replication operations
- **CloudWatch Monitoring**: Alarms and dashboards for replication metrics
- **CloudTrail Logging**: Comprehensive audit trail for compliance
- **SNS Alerts**: Notification system for replication issues

### DR Stack (Destination Region)
- **S3 Destination Bucket**: Versioned bucket configured to receive replicated objects
- **CloudWatch Monitoring**: DR-specific metrics and alerting
- **Optional CloudTrail**: Destination region audit logging

## Prerequisites

- **AWS CLI v2** installed and configured
- **Node.js 18+** and npm installed
- **AWS CDK v2** installed globally (`npm install -g aws-cdk`)
- **TypeScript** installed globally (`npm install -g typescript`)
- **Two different AWS regions** selected for primary and disaster recovery
- **Appropriate AWS permissions** for S3, IAM, CloudWatch, CloudTrail, and SNS

### Required AWS Permissions

Ensure your AWS credentials have the following minimum permissions:
- `s3:*` (for bucket creation and configuration)
- `iam:*` (for replication role creation)
- `cloudwatch:*` (for monitoring and alarms)
- `cloudtrail:*` (for audit logging)
- `sns:*` (for alert notifications)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

Set environment variables for your deployment:

```bash
export PRIMARY_REGION="us-east-1"
export DR_REGION="us-west-2"
export BUCKET_PREFIX="my-company-dr"
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```

### 3. Bootstrap CDK (if not already done)

Bootstrap both regions for CDK deployment:

```bash
# Bootstrap primary region
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/${PRIMARY_REGION}

# Bootstrap DR region
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/${DR_REGION}
```

### 4. Deploy the Solution

Deploy both stacks:

```bash
# Build the TypeScript code
npm run build

# Deploy both stacks
cdk deploy --all
```

Or deploy stacks individually:

```bash
# Deploy primary stack first
cdk deploy DisasterRecoveryS3PrimaryStack

# Deploy DR stack
cdk deploy DisasterRecoveryS3DrStack
```

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PRIMARY_REGION` | AWS region for source bucket | `us-east-1` |
| `DR_REGION` | AWS region for destination bucket | `us-west-2` |
| `BUCKET_PREFIX` | Prefix for bucket names | `dr-replication` |

### CDK Context Parameters

You can also configure the application using CDK context:

```bash
# Deploy with custom configuration
cdk deploy --all --context primaryRegion=us-east-1 --context drRegion=eu-west-1 --context bucketPrefix=mycompany-backup

# Configure email alerts
cdk deploy --all --context alertEmail=alerts@company.com --context drAlertEmail=dr-alerts@company.com

# Disable optional features
cdk deploy --all --context enableCloudTrail=false --context enableMonitoring=false
```

### CDK Context File

Create a `cdk.context.json` file for persistent configuration:

```json
{
  "primaryRegion": "us-east-1",
  "drRegion": "us-west-2",
  "bucketPrefix": "mycompany-dr",
  "alertEmail": "alerts@company.com",
  "drAlertEmail": "dr-alerts@company.com",
  "enableCloudTrail": true,
  "enableMonitoring": true
}
```

## Validation and Testing

### 1. Verify Deployment

Check CloudFormation stacks:

```bash
# List deployed stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE

# Get stack outputs
aws cloudformation describe-stacks --stack-name disaster-recovery-s3-primary-${PRIMARY_REGION} --query 'Stacks[0].Outputs'
```

### 2. Test Replication

Upload test files to verify replication:

```bash
# Get source bucket name from stack outputs
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name disaster-recovery-s3-primary-${PRIMARY_REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
  --output text)

DEST_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name disaster-recovery-s3-dr-${DR_REGION} \
  --query 'Stacks[0].Outputs[?OutputKey==`DestinationBucketName`].OutputValue' \
  --output text)

# Upload test file
echo "Test file - $(date)" > test-replication.txt
aws s3 cp test-replication.txt s3://${SOURCE_BUCKET}/test-replication.txt

# Wait and verify replication
sleep 60
aws s3 ls s3://${DEST_BUCKET}/ --region ${DR_REGION}
```

### 3. Monitor Replication

Access CloudWatch dashboards and alarms:

```bash
# View replication metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name ReplicationLatency \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --dimensions Name=SourceBucket,Value=${SOURCE_BUCKET}
```

## Cost Optimization

### Storage Classes

The solution uses cost-optimized storage classes:
- **Source bucket**: STANDARD with transition to INFREQUENT_ACCESS after 30 days
- **Destination bucket**: STANDARD_IA for replicated objects, transition to GLACIER after 90 days

### Lifecycle Management

Both buckets include lifecycle rules to:
- Delete incomplete multipart uploads after 1 day
- Transition objects to cheaper storage classes over time

### Monitoring Costs

Monitor your cross-region replication costs:

```bash
# View S3 costs by service
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Security Considerations

### IAM Permissions

The replication role uses least privilege permissions:
- Read access only to source bucket objects and versions
- Write access only to destination bucket for replication operations
- No unnecessary permissions for other AWS services

### Encryption

- Both buckets use S3 server-side encryption (SSE-S3)
- SSL/TLS enforcement for all bucket operations
- Block all public access enabled on both buckets

### Audit Logging

CloudTrail provides comprehensive audit logs:
- All S3 API calls are logged
- Log file integrity validation enabled
- Multi-region trail for complete coverage

## Troubleshooting

### Common Issues

1. **Replication not working**: Check IAM role permissions and bucket versioning
2. **CloudTrail errors**: Verify bucket permissions for CloudTrail logging
3. **Cross-region access**: Ensure both regions are accessible and bootstrapped

### Debug Commands

```bash
# Check replication configuration
aws s3api get-bucket-replication --bucket ${SOURCE_BUCKET}

# View CloudTrail events
aws logs filter-log-events \
  --log-group-name CloudTrail/S3ReplicationTrail \
  --start-time $(date -d '1 hour ago' +%s)000

# Check IAM role
aws iam get-role --role-name s3-replication-role-*
```

## Cleanup

To remove all resources and avoid ongoing costs:

```bash
# Empty buckets first (required for deletion)
aws s3 rm s3://${SOURCE_BUCKET} --recursive
aws s3 rm s3://${DEST_BUCKET} --recursive --region ${DR_REGION}

# Delete the stacks
cdk destroy --all
```

**Note**: Buckets are configured with `RETAIN` deletion policy to prevent accidental data loss. You may need to manually delete buckets after stack deletion.

## Advanced Configuration

### Custom Replication Rules

Modify the replication configuration in the stack for advanced scenarios:

```typescript
// Example: Replicate only specific prefixes
cfnBucket.replicationConfiguration = {
  role: replicationRole.roleArn,
  rules: [
    {
      id: 'replicate-critical-data',
      status: 'Enabled',
      priority: 1,
      filter: {
        prefix: 'critical/', // Only replicate objects with this prefix
      },
      destination: {
        bucket: destinationBucketArn,
        storageClass: 'STANDARD_IA',
      },
    },
  ],
};
```

### Multiple Destination Regions

Extend the solution for multiple DR regions by deploying additional destination stacks.

### Integration with AWS Backup

Consider integrating with AWS Backup for additional protection:
- Point-in-time recovery
- Cross-account backup
- Centralized backup management

## Support and Contributing

For issues and questions:
1. Check the AWS CDK documentation
2. Review AWS S3 Cross-Region Replication documentation
3. Check CloudFormation stack events for deployment issues

## License

This project is licensed under the MIT License - see the LICENSE file for details.