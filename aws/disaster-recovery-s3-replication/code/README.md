# Infrastructure as Code for Implementing S3 Cross-Region Disaster Recovery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing S3 Cross-Region Disaster Recovery".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for S3, IAM, CloudWatch, CloudTrail, and SNS
- Two AWS regions selected for primary and disaster recovery locations
- Basic understanding of S3 bucket policies and IAM roles
- Estimated cost: $0.025 per GB for cross-region replication transfer, plus standard S3 storage costs in destination region

## Quick Start

### Using CloudFormation

```bash
# Create the CloudFormation stack
aws cloudformation create-stack \
    --stack-name s3-disaster-recovery-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=DRRegion,ParameterValue=us-west-2 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor stack creation progress
aws cloudformation wait stack-create-complete \
    --stack-name s3-disaster-recovery-stack \
    --region us-east-1

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name s3-disaster-recovery-stack \
    --query 'Stacks[0].Outputs' \
    --region us-east-1
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK in both regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the stack
cdk deploy DisasterRecoveryStack

# List all stacks
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK in both regions (if not already done)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2

# Deploy the stack
cdk deploy DisasterRecoveryStack

# List all stacks
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
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

# Deploy the infrastructure
./scripts/deploy.sh

# Test the deployment (optional)
./scripts/test.sh
```

## Configuration Options

### CloudFormation Parameters

- `PrimaryRegion`: Primary AWS region for source bucket (default: us-east-1)
- `DRRegion`: Disaster recovery region for destination bucket (default: us-west-2)
- `BucketPrefix`: Prefix for bucket names (default: dr-s3-replication)
- `ReplicationStorageClass`: Storage class for replicated objects (default: STANDARD_IA)
- `EnableCloudTrail`: Enable CloudTrail logging (default: true)
- `EnableCloudWatchAlarms`: Enable CloudWatch monitoring (default: true)

### CDK Context Variables

Configure in `cdk.json`:

```json
{
  "context": {
    "primaryRegion": "us-east-1",
    "drRegion": "us-west-2",
    "bucketPrefix": "dr-s3-replication",
    "replicationStorageClass": "STANDARD_IA",
    "enableCloudTrail": true,
    "enableCloudWatchAlarms": true
  }
}
```

### Terraform Variables

Customize in `terraform.tfvars`:

```hcl
primary_region             = "us-east-1"
dr_region                 = "us-west-2"
bucket_prefix             = "dr-s3-replication"
replication_storage_class = "STANDARD_IA"
enable_cloudtrail         = true
enable_cloudwatch_alarms  = true
environment               = "production"
```

### Bash Script Environment Variables

Set before running scripts:

```bash
export PRIMARY_REGION="us-east-1"
export DR_REGION="us-west-2"
export BUCKET_PREFIX="dr-s3-replication"
export REPLICATION_STORAGE_CLASS="STANDARD_IA"
export ENABLE_CLOUDTRAIL="true"
export ENABLE_CLOUDWATCH_ALARMS="true"
```

## Testing the Deployment

After deployment, test the disaster recovery setup:

```bash
# Get bucket names from outputs
SOURCE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name s3-disaster-recovery-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
    --output text --region us-east-1)

DEST_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name s3-disaster-recovery-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DestinationBucketName`].OutputValue' \
    --output text --region us-east-1)

# Upload test file
echo "Test file $(date)" > test-replication.txt
aws s3 cp test-replication.txt s3://${SOURCE_BUCKET}/test-replication.txt

# Wait for replication
sleep 60

# Verify replication
aws s3 ls s3://${DEST_BUCKET}/ --region us-west-2

# Test disaster recovery scenario
aws s3 sync s3://${DEST_BUCKET}/ ./dr-test/ --region us-west-2
cat ./dr-test/test-replication.txt

# Cleanup test files
rm test-replication.txt
rm -rf ./dr-test/
```

## Monitoring and Maintenance

### CloudWatch Metrics

Monitor these key metrics:

- `ReplicationLatency`: Time to replicate objects
- `ReplicatedObjectCount`: Number of replicated objects
- `ReplicationFailureCount`: Failed replication attempts

### CloudTrail Events

Key S3 API calls to monitor:

- `PutObject`: Object uploads to source bucket
- `ReplicateObject`: Replication events
- `GetObject`: Object retrievals from destination bucket

### Cost Optimization

- Use S3 Intelligent-Tiering for automatic cost optimization
- Implement lifecycle policies on destination bucket
- Monitor cross-region data transfer costs
- Consider S3 Transfer Acceleration for large files

## Cleanup

### Using CloudFormation

```bash
# Empty buckets first (CloudFormation can't delete non-empty buckets)
aws s3 rm s3://${SOURCE_BUCKET} --recursive
aws s3 rm s3://${DEST_BUCKET} --recursive

# Delete the stack
aws cloudformation delete-stack \
    --stack-name s3-disaster-recovery-stack \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name s3-disaster-recovery-stack \
    --region us-east-1
```

### Using CDK

```bash
# Empty buckets first
SOURCE_BUCKET=$(cdk ls --json | jq -r '.[0].outputs.SourceBucketName')
DEST_BUCKET=$(cdk ls --json | jq -r '.[0].outputs.DestinationBucketName')

aws s3 rm s3://${SOURCE_BUCKET} --recursive
aws s3 rm s3://${DEST_BUCKET} --recursive

# Destroy the stack
cdk destroy DisasterRecoveryStack --force
```

### Using Terraform

```bash
# Terraform will handle bucket cleanup automatically
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Replication Not Working**
   - Verify both buckets have versioning enabled
   - Check IAM role permissions
   - Ensure buckets are in different regions

2. **Access Denied Errors**
   - Verify AWS credentials and permissions
   - Check IAM role trust relationships
   - Ensure cross-region permissions are configured

3. **High Replication Latency**
   - Check source and destination region locations
   - Consider S3 Transfer Acceleration
   - Monitor CloudWatch metrics for bottlenecks

4. **Cost Concerns**
   - Implement lifecycle policies
   - Use appropriate storage classes
   - Monitor data transfer patterns

### Debugging Commands

```bash
# Check replication status
aws s3api get-bucket-replication --bucket ${SOURCE_BUCKET}

# Monitor replication metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name ReplicationLatency \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --dimensions Name=SourceBucket,Value=${SOURCE_BUCKET}

# Check CloudTrail logs
aws logs filter-log-events \
    --log-group-name CloudTrail/S3DataEvents \
    --start-time $(date -d '1 hour ago' +%s)000 \
    --filter-pattern "{ $.eventName = \"ReplicateObject\" }"
```

## Security Considerations

- All IAM roles follow least privilege principle
- S3 buckets have public access blocked by default
- CloudTrail provides comprehensive audit logging
- Cross-region replication uses encrypted channels
- Optional: Enable S3 Object Lock for WORM compliance

## Customization

Refer to the variable definitions in each implementation to customize the deployment for your environment:

- Modify storage classes for cost optimization
- Adjust CloudWatch alarm thresholds
- Configure custom bucket policies
- Add additional monitoring and alerting
- Implement custom lifecycle policies

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../disaster-recovery-s3-cross-region-replication.md)
- [AWS S3 Cross-Region Replication documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [AWS CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This infrastructure code is provided as-is for educational and reference purposes. Modify as needed for your specific requirements.