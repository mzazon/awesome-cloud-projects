# S3 Cross-Region Replication CDK Python Application

This AWS CDK Python application implements a comprehensive S3 cross-region replication solution with encryption and access controls.

## Features

- **KMS Encryption**: Separate KMS keys for source and destination regions with automatic key rotation
- **S3 Cross-Region Replication**: Automated replication with encryption re-wrapping in destination region
- **Security Controls**: Bucket policies enforcing HTTPS and KMS encryption
- **IAM Best Practices**: Least privilege IAM role for replication service
- **CloudWatch Monitoring**: Alarms for replication failures and latency monitoring
- **Production Ready**: Comprehensive tagging and resource management

## Architecture

The solution creates:

- **Source S3 Bucket**: Versioned bucket with KMS encryption in primary region
- **Destination S3 Bucket**: Versioned bucket with KMS encryption in secondary region
- **KMS Keys**: Separate encryption keys in each region with automatic rotation
- **IAM Role**: Service role for S3 replication with minimal permissions
- **CloudWatch Alarms**: Monitoring for replication latency and failures
- **Security Policies**: Bucket policies enforcing encryption and secure transport

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8 or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for:
  - S3 (buckets, replication, policies)
  - KMS (keys, aliases, policies)
  - IAM (roles, policies)
  - CloudWatch (alarms, metrics)

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/s3-cross-region-replication-encryption-access-controls/code/cdk-python
   ```

2. **Create and activate a virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Configuration

### Environment Variables

Set the following environment variables to configure the deployment:

```bash
# Required: AWS account and primary region
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION="us-east-1"

# Optional: Secondary region (defaults to us-west-2)
export SECONDARY_REGION="us-west-2"
```

### CDK Context

You can also configure regions using CDK context in `cdk.json`:

```json
{
  "context": {
    "primaryRegion": "us-east-1",
    "secondaryRegion": "us-west-2"
  }
}
```

## Deployment

### Bootstrap CDK (if not already done)

Bootstrap CDK in both regions:

```bash
# Bootstrap primary region
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$CDK_DEFAULT_REGION

# Bootstrap secondary region
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$SECONDARY_REGION
```

### Deploy the Stack

1. **Synthesize the CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Verify deployment**:
   ```bash
   aws s3 ls | grep s3-crr
   aws kms list-aliases | grep s3-crr
   ```

## Testing

### Upload Test Files

After deployment, test the replication:

```bash
# Get bucket names from stack outputs
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name S3CrossRegionReplicationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
    --output text)

DEST_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name S3CrossRegionReplicationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`DestBucketName`].OutputValue' \
    --output text)

# Upload a test file
echo "Test content $(date)" > test-file.txt
aws s3 cp test-file.txt s3://$SOURCE_BUCKET/

# Wait for replication and check destination
sleep 30
aws s3 ls s3://$DEST_BUCKET/ --recursive --region $SECONDARY_REGION
```

### Verify Encryption

```bash
# Check encryption on source object
aws s3api head-object \
    --bucket $SOURCE_BUCKET \
    --key test-file.txt \
    --query '[ServerSideEncryption,SSEKMSKeyId]' \
    --output table

# Check encryption on replicated object
aws s3api head-object \
    --bucket $DEST_BUCKET \
    --key test-file.txt \
    --region $SECONDARY_REGION \
    --query '[ServerSideEncryption,SSEKMSKeyId]' \
    --output table
```

### Monitor Replication

```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name NumberOfObjectsPendingReplication \
    --dimensions Name=SourceBucket,Value=$SOURCE_BUCKET \
                Name=DestinationBucket,Value=$DEST_BUCKET \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

To avoid ongoing charges, clean up the resources:

```bash
# Empty buckets first (required for deletion)
aws s3 rm s3://$SOURCE_BUCKET/ --recursive
aws s3 rm s3://$DEST_BUCKET/ --recursive --region $SECONDARY_REGION

# Destroy the stack
cdk destroy

# Clean up local files
rm -f test-file.txt
```

## Cost Considerations

This solution incurs costs for:

- **S3 Storage**: Standard storage in primary region, Standard-IA in secondary region
- **S3 Requests**: PUT/GET requests for replication
- **Data Transfer**: Cross-region replication bandwidth
- **KMS**: Key usage for encryption/decryption operations
- **CloudWatch**: Custom metrics and alarms

Estimated cost for testing: $0.50-$2.00 per hour

## Security Features

### Encryption
- KMS keys with automatic rotation
- Separate keys for each region
- Envelope encryption for cross-region replication

### Access Controls
- IAM role with least privilege permissions
- Bucket policies denying unencrypted uploads
- Enforcement of HTTPS-only access

### Monitoring
- CloudWatch alarms for replication failures
- Metrics for replication latency
- S3 access logging capability

## Troubleshooting

### Common Issues

1. **Replication not working**:
   - Verify IAM role permissions
   - Check KMS key policies
   - Ensure versioning is enabled

2. **Permission errors**:
   - Verify AWS credentials and permissions
   - Check CDK bootstrap completion
   - Ensure regions are different

3. **Deployment failures**:
   - Check CloudFormation events in AWS Console
   - Verify resource naming conflicts
   - Ensure sufficient service quotas

### Useful Commands

```bash
# Check CDK diff
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name S3CrossRegionReplicationStack

# List stack resources
aws cloudformation list-stack-resources \
    --stack-name S3CrossRegionReplicationStack
```

## Development

### Code Quality

The project includes development dependencies for code quality:

```bash
# Install development dependencies
pip install -r requirements.txt

# Format code
black app.py

# Type checking
mypy app.py

# Linting
flake8 app.py
pylint app.py

# Sort imports
isort app.py
```

### Testing

```bash
# Run tests (when test suite is available)
pytest tests/

# Coverage report
pytest --cov=app tests/
```

## References

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [S3 Cross-Region Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [AWS KMS Key Policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html)
- [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)

## License

This code is provided under the MIT License. See LICENSE file for details.