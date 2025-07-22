# Infrastructure as Code for S3 Cross-Region Replication with Encryption and Access Controls

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Replicating S3 Data Across Regions with Encryption".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements:
- S3 Cross-Region Replication between two AWS regions
- KMS encryption with separate keys per region
- IAM roles with least privilege permissions
- CloudWatch monitoring and alarms
- Security policies enforcing encryption requirements

## Prerequisites

- AWS CLI v2 installed and configured (minimum version 2.0.0)
- AWS account with administrative permissions for S3, KMS, IAM, and CloudWatch
- Two AWS regions available for deployment (default: us-east-1 and us-west-2)
- Understanding of S3 bucket policies and IAM roles
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

> **Cost Estimate**: $0.50-$2.00 per hour for testing (includes S3 storage, KMS requests, and data transfer)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name s3-crr-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name s3-crr-stack \
    --region us-east-1

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name s3-crr-stack \
    --query 'Stacks[0].Outputs' \
    --region us-east-1
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap --region us-east-1
npx cdk bootstrap --region us-west-2

# Deploy the stack
npx cdk deploy --all --require-approval never

# View stack outputs
npx cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap --region us-east-1
cdk bootstrap --region us-west-2

# Deploy the stack
cdk deploy --all --require-approval never

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for regions if not set as environment variables
# Or set them before running:
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
./scripts/deploy.sh
```

## Configuration Options

### Environment Variables

Set these environment variables to customize the deployment:

```bash
# Required regions
export PRIMARY_REGION="us-east-1"          # Source region
export SECONDARY_REGION="us-west-2"        # Destination region

# Optional customizations
export BUCKET_PREFIX="my-company"           # Custom bucket prefix
export ENABLE_MONITORING="true"            # Enable CloudWatch monitoring
export STORAGE_CLASS="STANDARD_IA"         # Destination storage class
export REPLICATION_PREFIX=""               # Object prefix filter
```

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| PrimaryRegion | Source region for replication | us-east-1 | Yes |
| SecondaryRegion | Destination region | us-west-2 | Yes |
| BucketPrefix | Prefix for bucket names | crr | No |
| StorageClass | Destination storage class | STANDARD_IA | No |
| EnableMonitoring | Enable CloudWatch monitoring | true | No |

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
primary_region    = "us-east-1"
secondary_region  = "us-west-2"
bucket_prefix     = "mycompany-crr"
storage_class     = "STANDARD_IA"
enable_monitoring = true

tags = {
  Environment = "production"
  Project     = "disaster-recovery"
  Owner       = "platform-team"
}
```

## Testing the Deployment

After deployment, test the replication:

```bash
# Get bucket names from outputs
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name s3-crr-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
    --output text)

DEST_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name s3-crr-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DestinationBucketName`].OutputValue' \
    --output text)

# Upload test file
echo "Test replication - $(date)" > test-file.txt
aws s3 cp test-file.txt s3://${SOURCE_BUCKET}/test-file.txt

# Wait for replication (typically 1-2 minutes)
sleep 120

# Verify replication
aws s3 ls s3://${DEST_BUCKET}/ --region ${SECONDARY_REGION}

# Check encryption
aws s3api head-object \
    --bucket ${DEST_BUCKET} \
    --key test-file.txt \
    --region ${SECONDARY_REGION} \
    --query '[ServerSideEncryption,SSEKMSKeyId]'
```

## Monitoring and Validation

### CloudWatch Metrics

Monitor replication performance using CloudWatch:

```bash
# Check replication metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name NumberOfObjectsPendingReplication \
    --dimensions Name=SourceBucket,Value=${SOURCE_BUCKET} \
                 Name=DestinationBucket,Value=${DEST_BUCKET} \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Check for replication alarms
aws cloudwatch describe-alarms \
    --alarm-names "S3-Replication-Failures-${SOURCE_BUCKET}"
```

### Security Validation

Verify security configurations:

```bash
# Test bucket policy enforcement (should fail)
echo "Unencrypted test" > unencrypted.txt
aws s3 cp unencrypted.txt s3://${SOURCE_BUCKET}/unencrypted.txt \
    2>&1 | grep -q "AccessDenied" && echo "✅ Security policy working" || echo "❌ Security issue"

# Verify encryption requirements
aws s3api get-bucket-encryption --bucket ${SOURCE_BUCKET}
aws s3api get-bucket-encryption --bucket ${DEST_BUCKET} --region us-west-2

# Clean up test file
rm unencrypted.txt
```

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **source_region**: Primary AWS region (default: us-east-1)
- **destination_region**: Secondary AWS region (default: us-west-2)
- **project_name**: Project identifier for resource naming
- **storage_class**: Storage class for replicated objects (default: STANDARD_IA)
- **enable_delete_marker_replication**: Replicate delete markers (default: true)
- **replication_timeout_minutes**: CloudWatch alarm threshold (default: 15)

### Advanced Configuration

For production deployments, consider these customizations:

1. **Multi-destination replication**: Modify templates to support multiple destination regions
2. **Replication Time Control (RTC)**: Enable 15-minute replication guarantees
3. **Lifecycle policies**: Add automatic transition to cheaper storage classes
4. **Cross-account replication**: Configure replication to buckets in different AWS accounts
5. **Selective replication**: Use object tags or prefixes to replicate specific data

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this will clean up all resources)
aws cloudformation delete-stack \
    --stack-name s3-crr-stack \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name s3-crr-stack \
    --region us-east-1
```

### Using CDK

```bash
# From the CDK directory
npx cdk destroy --all

# Or for Python CDK
cdk destroy --all
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh
```

> **Warning**: The cleanup process will delete all data in the buckets. Ensure you have backups of any important data before running cleanup commands.

## Cost Optimization

To optimize costs:

1. **Storage Classes**: Use appropriate storage classes (STANDARD_IA, GLACIER)
2. **Lifecycle Policies**: Implement lifecycle rules for long-term storage
3. **Bucket Keys**: Enabled by default to reduce KMS costs
4. **Monitoring**: Set up billing alerts for unexpected charges
5. **Selective Replication**: Use prefix filters to replicate only necessary objects

## Advanced Configuration

### Multi-Destination Replication

To replicate to multiple regions, modify the replication configuration:

```json
{
  "Rules": [
    {
      "ID": "ReplicateToWest",
      "Status": "Enabled",
      "Destination": {
        "Bucket": "arn:aws:s3:::dest-bucket-west",
        "StorageClass": "STANDARD_IA"
      }
    },
    {
      "ID": "ReplicateToEast",
      "Status": "Enabled", 
      "Destination": {
        "Bucket": "arn:aws:s3:::dest-bucket-east",
        "StorageClass": "GLACIER"
      }
    }
  ]
}
```

### Cross-Account Replication

For cross-account scenarios, additional IAM policies are required:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::SOURCE-ACCOUNT:role/replication-role"
      },
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete"
      ],
      "Resource": "arn:aws:s3:::destination-bucket/*"
    }
  ]
}
```

## Troubleshooting

### Common Issues

1. **Replication not working**:
   - Verify source bucket has versioning enabled
   - Check IAM role permissions
   - Ensure destination bucket exists and is accessible
   - Verify KMS key permissions in both regions

2. **Access denied errors**:
   - Check bucket policies
   - Verify IAM role trust relationships
   - Ensure KMS key policies allow S3 service access

3. **High replication latency**:
   - Check CloudWatch metrics for pending objects
   - Verify network connectivity between regions
   - Consider enabling Replication Time Control (RTC)

4. **Cost concerns**:
   - Monitor data transfer charges
   - Consider using Intelligent-Tiering
   - Implement lifecycle policies for older objects

## Support and Documentation

- [AWS S3 Cross-Region Replication Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [AWS KMS Developer Guide](https://docs.aws.amazon.com/kms/latest/developerguide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS documentation links above.

## Security Considerations

This implementation includes several security best practices:

- **Encryption at Rest**: All objects encrypted with KMS
- **Encryption in Transit**: HTTPS required for all API calls
- **Access Controls**: Bucket policies deny unencrypted uploads
- **Least Privilege**: IAM role has minimal required permissions
- **Key Isolation**: Separate KMS keys per region
- **Monitoring**: CloudWatch alarms for replication issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure proper testing in non-production environments before deploying to production.