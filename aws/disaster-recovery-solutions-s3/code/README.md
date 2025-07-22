# Infrastructure as Code for S3 Disaster Recovery Solutions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "S3 Disaster Recovery Solutions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for S3, IAM, CloudWatch, CloudTrail, and SNS
- For CDK: Node.js (v18+) and npm installed
- For Terraform: Terraform v1.0+ installed
- Understanding of disaster recovery concepts and cross-region replication

### Required AWS Permissions

Your AWS user/role needs permissions for:
- S3 bucket creation and management
- IAM role and policy creation
- CloudWatch alarms and dashboards
- CloudTrail management
- SNS topic creation (for alerts)

### Cost Estimates

- **S3 Storage**: ~$0.023/GB/month for Standard storage
- **Cross-Region Replication**: ~$0.02/GB for data transfer
- **CloudWatch**: ~$0.30/alarm/month
- **CloudTrail**: First trail is free, $2.00/100,000 events thereafter
- **Total Monthly Cost**: ~$50-100 for 1TB of replicated data

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name disaster-recovery-s3-crr \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name disaster-recovery-s3-crr \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name disaster-recovery-s3-crr \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output

# Synthesize CloudFormation template (optional)
cdk synth
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # Linux/Mac
# OR
.venv\Scripts\activate     # Windows

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

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
terraform apply -auto-approve

# View outputs
terraform output

# Show current state
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status

# Run validation tests
./scripts/deploy.sh --validate
```

## Configuration Options

### Environment Variables

Set these environment variables to customize the deployment:

```bash
# Required
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Optional customization
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2
export BUCKET_PREFIX=my-dr-solution
export ENABLE_CLOUDTRAIL=true
export ENABLE_LIFECYCLE_POLICIES=true
export REPLICATION_PRIORITY=1
```

### CloudFormation Parameters

- `PrimaryRegion`: Primary AWS region (default: us-east-1)
- `SecondaryRegion`: Secondary AWS region (default: us-west-2)
- `BucketPrefix`: Prefix for bucket names (default: dr-solution)
- `EnableCloudTrail`: Enable CloudTrail logging (default: true)
- `EnableLifecyclePolicies`: Enable S3 lifecycle policies (default: true)

### CDK Context Values

```json
{
  "primaryRegion": "us-east-1",
  "secondaryRegion": "us-west-2",
  "bucketPrefix": "dr-solution",
  "enableCloudTrail": true,
  "enableLifecyclePolicies": true
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
primary_region = "us-east-1"
secondary_region = "us-west-2"
bucket_prefix = "dr-solution"
enable_cloudtrail = true
enable_lifecycle_policies = true
replication_priority = 1

# Optional tags
tags = {
  Environment = "Production"
  Purpose = "DisasterRecovery"
  CostCenter = "IT-DR"
}
```

## Post-Deployment Steps

### 1. Verify Replication Configuration

```bash
# Check replication status
aws s3api get-bucket-replication \
    --bucket $(terraform output -raw source_bucket_name) \
    --query 'ReplicationConfiguration.Rules[0].Status'
```

### 2. Upload Test Data

```bash
# Create test file
echo "Test data - $(date)" > test-file.txt

# Upload to source bucket
aws s3 cp test-file.txt s3://$(terraform output -raw source_bucket_name)/test/

# Wait for replication (30 seconds)
sleep 30

# Verify in replica bucket
aws s3 ls s3://$(terraform output -raw replica_bucket_name)/test/ \
    --region $(terraform output -raw secondary_region)
```

### 3. Configure Monitoring

```bash
# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name $(terraform output -raw dashboard_name)

# Check replication metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name ReplicationLatency \
    --dimensions Name=SourceBucket,Value=$(terraform output -raw source_bucket_name) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Testing Disaster Recovery

### 1. Failover Test

```bash
# Test failover script (generated during deployment)
./scripts/dr-failover.sh $(terraform output -raw replica_bucket_name) app-config.txt

# Verify application configuration
cat app-config.txt
```

### 2. Failback Test

```bash
# Test failback script
./scripts/dr-failback.sh $(terraform output -raw source_bucket_name) app-config.txt

# Verify application configuration
cat app-config.txt
```

### 3. Validation Tests

```bash
# Run comprehensive validation
./scripts/validate-dr.sh

# Test cross-region access
aws s3 cp s3://$(terraform output -raw replica_bucket_name)/test/test-file.txt \
    downloaded-file.txt \
    --region $(terraform output -raw secondary_region)

# Compare files
diff test-file.txt downloaded-file.txt
```

## Monitoring and Alerting

### CloudWatch Metrics

Monitor these key metrics:

- **ReplicationLatency**: Time to replicate objects
- **ReplicationFailureCount**: Number of failed replications
- **BucketSizeBytes**: Size of source and replica buckets
- **NumberOfObjects**: Object count in both buckets

### CloudWatch Alarms

The solution creates these alarms:

- **S3-Replication-Failure**: Triggers when replication latency exceeds 15 minutes
- **S3-Replication-Error**: Triggers on replication failures

### SNS Notifications

Configure SNS topic for alerts:

```bash
# Subscribe to replication alerts
aws sns subscribe \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty buckets first (required for deletion)
aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name disaster-recovery-s3-crr \
    --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' \
    --output text) --recursive

aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name disaster-recovery-s3-crr \
    --query 'Stacks[0].Outputs[?OutputKey==`ReplicaBucketName`].OutputValue' \
    --output text) --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name disaster-recovery-s3-crr

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name disaster-recovery-s3-crr \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Empty buckets first
cdk destroy --force

# Verify cleanup
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

1. **Replication Not Working**
   - Verify IAM role permissions
   - Check bucket versioning is enabled
   - Ensure regions are different

2. **Access Denied Errors**
   - Check IAM permissions
   - Verify bucket policies
   - Ensure proper region configuration

3. **High Replication Latency**
   - Check CloudWatch metrics
   - Verify network connectivity
   - Review S3 service health

### Debug Commands

```bash
# Check replication configuration
aws s3api get-bucket-replication --bucket BUCKET_NAME

# View replication metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name ReplicationLatency \
    --dimensions Name=SourceBucket,Value=BUCKET_NAME

# Check IAM role
aws iam get-role --role-name ROLE_NAME
aws iam get-role-policy --role-name ROLE_NAME --policy-name PolicyName
```

### Log Analysis

```bash
# View CloudTrail logs
aws logs filter-log-events \
    --log-group-name /aws/s3/replication \
    --start-time $(date -d '1 hour ago' +%s)000

# Check S3 access logs
aws s3 ls s3://ACCESS_LOG_BUCKET/
```

## Security Considerations

### IAM Best Practices

- Use least privilege principle
- Regularly rotate access keys
- Enable MFA for sensitive operations
- Monitor IAM usage with CloudTrail

### Encryption

- Enable encryption at rest for both buckets
- Use KMS keys for sensitive data
- Enable encryption in transit (default)

### Network Security

- Use VPC endpoints for S3 access
- Implement bucket policies for access control
- Enable CloudTrail for audit logging

## Performance Optimization

### Replication Performance

- Use S3 Transfer Acceleration
- Monitor replication latency
- Implement parallel uploads
- Use multipart uploads for large files

### Cost Optimization

- Implement lifecycle policies
- Use appropriate storage classes
- Monitor data transfer costs
- Regular cost analysis

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS S3 replication documentation
3. Consult provider-specific documentation
4. Check CloudWatch logs and metrics

## Additional Resources

- [AWS S3 Cross-Region Replication Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [S3 Replication Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-best-practices.html)
- [Disaster Recovery with AWS](https://aws.amazon.com/disaster-recovery/)
- [S3 Replication Pricing](https://aws.amazon.com/s3/pricing/)