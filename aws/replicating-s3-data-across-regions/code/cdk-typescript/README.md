# S3 Cross-Region Replication CDK TypeScript

This directory contains the AWS CDK TypeScript implementation for the S3 Cross-Region Replication with Encryption and Access Controls recipe.

## Overview

This CDK application creates a complete S3 cross-region replication solution with:

- **Source S3 bucket** with KMS encryption and versioning (primary region)
- **Destination S3 bucket** with KMS encryption and versioning (secondary region)
- **KMS keys** for encryption in both regions with automatic key rotation
- **IAM replication role** with least privilege permissions
- **Bucket policies** enforcing encryption and secure transport
- **CloudWatch alarms** for monitoring replication health
- **Custom resource** for configuring cross-region replication

## Architecture

The solution deploys resources across two AWS regions:

1. **Primary Region** (default: us-east-1):
   - Source S3 bucket with KMS encryption
   - Source KMS key with automatic rotation
   - IAM replication role
   - CloudWatch alarm for replication monitoring

2. **Secondary Region** (default: us-west-2):
   - Destination S3 bucket with KMS encryption
   - Destination KMS key with automatic rotation
   - Lambda-backed custom resource for replication configuration

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Node.js** 18.x or later
3. **AWS CDK** v2.133.0 or later
4. **TypeScript** 5.3.x or later
5. **AWS account** with permissions for S3, KMS, IAM, Lambda, and CloudWatch

### Required AWS Permissions

Your AWS credentials should have permissions for:
- S3 bucket creation and management
- KMS key creation and management
- IAM role and policy creation
- Lambda function deployment
- CloudWatch alarm creation
- CloudFormation stack operations

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Build the TypeScript code**:
   ```bash
   npm run build
   ```

3. **Bootstrap CDK** (if not already done):
   ```bash
   # Bootstrap primary region
   npx cdk bootstrap aws://ACCOUNT-ID/us-east-1
   
   # Bootstrap secondary region
   npx cdk bootstrap aws://ACCOUNT-ID/us-west-2
   ```

## Configuration

### Environment Variables

You can customize the deployment using environment variables:

```bash
export CDK_PRIMARY_REGION="us-east-1"
export CDK_SECONDARY_REGION="us-west-2"
export CDK_PROJECT_NAME="MyS3Replication"
export CDK_DEFAULT_ACCOUNT="123456789012"
```

### CDK Context

Alternatively, use CDK context parameters:

```bash
npx cdk deploy --all \
  --context primaryRegion=us-east-1 \
  --context secondaryRegion=eu-west-1 \
  --context projectName=MyProject \
  --context environment=production
```

## Deployment

### Deploy All Resources

Deploy both primary and secondary region stacks:

```bash
npm run deploy
# or
npx cdk deploy --all
```

### Deploy Individual Stacks

Deploy primary region resources first:

```bash
npm run deploy:primary
# or
npx cdk deploy S3CrossRegionReplication-Primary-Stack
```

Then deploy secondary region resources:

```bash
npm run deploy:secondary
# or
npx cdk deploy S3CrossRegionReplication-Secondary-Stack
```

### Custom Configuration Deployment

```bash
npx cdk deploy --all \
  --context primaryRegion=us-east-1 \
  --context secondaryRegion=eu-west-1 \
  --context projectName=MyCompany \
  --context environment=production
```

## Testing

### Validate Deployment

1. **Check CloudFormation outputs**:
   ```bash
   npx cdk list
   aws cloudformation describe-stacks --stack-name S3CrossRegionReplication-Primary-Stack
   aws cloudformation describe-stacks --stack-name S3CrossRegionReplication-Secondary-Stack
   ```

2. **Test replication** by uploading a file:
   ```bash
   # Get bucket name from CloudFormation outputs
   SOURCE_BUCKET=$(aws cloudformation describe-stacks \
     --stack-name S3CrossRegionReplication-Primary-Stack \
     --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
     --output text)
   
   # Upload test file
   echo "Test file $(date)" > test-file.txt
   aws s3 cp test-file.txt s3://${SOURCE_BUCKET}/test-file.txt \
     --sse aws:kms
   
   # Wait and check replication
   sleep 30
   DEST_BUCKET=$(aws cloudformation describe-stacks \
     --stack-name S3CrossRegionReplication-Secondary-Stack \
     --region us-west-2 \
     --query 'Stacks[0].Outputs[?OutputKey==`DestinationBucketName`].OutputValue' \
     --output text)
   
   aws s3 ls s3://${DEST_BUCKET}/ --region us-west-2
   ```

### Run TypeScript Tests

```bash
npm test
# or
npm run test:watch
```

## Monitoring

### CloudWatch Alarms

The deployment creates CloudWatch alarms to monitor:
- Replication latency (alerts if > 15 minutes)
- Replication failures

### Viewing Metrics

```bash
# View replication metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name NumberOfObjectsPendingReplication \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Cleanup

### Destroy All Resources

```bash
npm run destroy
# or
npx cdk destroy --all
```

### Destroy Individual Stacks

Destroy in reverse order (secondary first, then primary):

```bash
npx cdk destroy S3CrossRegionReplication-Secondary-Stack
npx cdk destroy S3CrossRegionReplication-Primary-Stack
```

## Development

### Code Quality

The project includes linting and formatting tools:

```bash
# Lint TypeScript code
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run format

# Check formatting
npm run format:check
```

### Project Structure

```
├── app.ts                              # CDK application entry point
├── lib/
│   └── s3-cross-region-replication-stack.ts  # Main stack implementation
├── package.json                        # NPM dependencies and scripts
├── tsconfig.json                       # TypeScript configuration
├── cdk.json                            # CDK configuration
└── README.md                           # This file
```

### Key Components

- **S3CrossRegionReplicationStack**: Main CDK stack class
- **Primary Region Resources**: Source bucket, KMS key, IAM role
- **Secondary Region Resources**: Destination bucket, KMS key
- **Custom Resource**: Lambda function for replication configuration
- **Security Policies**: Bucket policies and IAM permissions

## Security Features

### Encryption
- KMS encryption for all S3 objects
- Separate KMS keys per region
- Automatic key rotation enabled
- Bucket keys for cost optimization

### Access Controls
- Least privilege IAM permissions
- Bucket policies enforcing HTTPS
- Deny unencrypted object uploads
- Cross-account access controls

### Monitoring
- CloudWatch alarms for replication health
- Lambda function logs for troubleshooting
- S3 access logging (optional)

## Troubleshooting

### Common Issues

1. **Bootstrap Errors**: Ensure CDK is bootstrapped in both regions
2. **Permission Errors**: Verify IAM permissions for all required services
3. **Region Errors**: Confirm regions support all required services
4. **Replication Delays**: Check CloudWatch alarms and S3 metrics

### Debug Commands

```bash
# View CloudFormation events
aws cloudformation describe-stack-events --stack-name S3CrossRegionReplication-Primary-Stack

# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/S3CrossRegionReplication"

# Validate IAM role
aws iam get-role --role-name S3ReplicationRole-S3CrossRegionReplication
```

## Cost Optimization

### Storage Classes
- Destination objects use STANDARD_IA for cost savings
- Consider lifecycle policies for long-term storage

### KMS Optimization
- Bucket keys reduce KMS API calls
- Monitor KMS usage in CloudWatch

### Data Transfer
- Cross-region transfer charges apply
- Consider AWS PrivateLink for higher volumes

## Support

For issues related to this CDK implementation:

1. Check the [CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [S3 Cross-Region Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
3. Consult [AWS KMS documentation](https://docs.aws.amazon.com/kms/)
4. Open an issue in the repository

## License

This project is licensed under the MIT License. See the LICENSE file for details.