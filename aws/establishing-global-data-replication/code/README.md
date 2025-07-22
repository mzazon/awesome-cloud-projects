# Infrastructure as Code for Establishing Global Data Replication with S3 Cross-Region Replication

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Global Data Replication with S3 Cross-Region Replication".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a comprehensive multi-region S3 replication solution including:

- **S3 Buckets**: Source bucket with versioning and encryption across multiple regions
- **Cross-Region Replication**: Automated replication with priority-based rules and RTC
- **KMS Encryption**: Customer-managed keys in each region for data sovereignty
- **IAM Roles**: Service-linked roles with least privilege permissions
- **CloudWatch Monitoring**: Comprehensive metrics, alarms, and dashboards
- **Intelligent Storage**: Automated cost optimization with intelligent tiering
- **Security Controls**: Bucket policies, public access blocks, and audit logging

## Prerequisites

- AWS CLI v2 installed and configured (minimum version 2.0.0)
- AWS account with administrative permissions for S3, KMS, IAM, CloudWatch, and CloudTrail
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.8+ and pip (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Understanding of multi-region AWS architecture and S3 replication concepts
- Estimated cost: $5-15/hour for testing environment

> **Note**: Cross-region replication incurs additional charges for storage in destination regions, data transfer between regions, and KMS operations. Review AWS pricing before deployment.

## Quick Start

### Using CloudFormation

```bash
# Deploy the multi-region replication infrastructure
aws cloudformation create-stack \
    --stack-name multi-region-s3-replication \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=production \
                 ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
                 ParameterKey=TertiaryRegion,ParameterValue=eu-west-1 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --enable-termination-protection

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name multi-region-s3-replication
```

### Using CDK TypeScript

```bash
# Install dependencies and deploy
cd cdk-typescript/
npm install

# Configure deployment parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Bootstrap CDK (if not already done)
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/us-east-1
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/us-west-2
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/eu-west-1

# Deploy the infrastructure
cdk deploy MultiRegionS3ReplicationStack \
    --parameters primaryRegion=us-east-1 \
    --parameters secondaryRegion=us-west-2 \
    --parameters tertiaryRegion=eu-west-1 \
    --require-approval never

# View stack outputs
cdk describe MultiRegionS3ReplicationStack
```

### Using CDK Python

```bash
# Install dependencies and deploy
cd cdk-python/
python -m pip install -r requirements.txt

# Set environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Bootstrap CDK in all regions (if not already done)
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/us-east-1
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/us-west-2
cdk bootstrap aws://${CDK_DEFAULT_ACCOUNT}/eu-west-1

# Deploy the infrastructure
cdk deploy MultiRegionS3ReplicationStack \
    --parameters primaryRegion=us-east-1 \
    --parameters secondaryRegion=us-west-2 \
    --parameters tertiaryRegion=eu-west-1 \
    --require-approval never

# List stack resources
cdk list
```

### Using Terraform

```bash
# Initialize and deploy
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the deployment plan
terraform plan \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2" \
    -var="tertiary_region=eu-west-1" \
    -var="environment=production"

# Apply the infrastructure
terraform apply \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2" \
    -var="tertiary_region=eu-west-1" \
    -var="environment=production"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Optional: Deploy with custom parameters
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
export TERTIARY_REGION="eu-west-1"
export ENVIRONMENT="production"
./scripts/deploy.sh
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `primary_region` | Primary AWS region for source bucket | `us-east-1` | Yes |
| `secondary_region` | Secondary region for first replica | `us-west-2` | Yes |
| `tertiary_region` | Tertiary region for second replica | `eu-west-1` | Yes |
| `environment` | Environment name for resource tagging | `production` | Yes |
| `bucket_prefix` | Prefix for S3 bucket names | `multi-region-replication` | No |
| `enable_intelligent_tiering` | Enable S3 Intelligent Tiering | `true` | No |
| `enable_replication_time_control` | Enable RTC for 15-min replication SLA | `true` | No |
| `notification_email` | Email for CloudWatch alarms | `` | No |

### Advanced Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `lifecycle_transition_ia_days` | Days to transition to IA storage | `30` |
| `lifecycle_transition_glacier_days` | Days to transition to Glacier | `90` |
| `lifecycle_transition_deep_archive_days` | Days to transition to Deep Archive | `365` |
| `replication_timeout_minutes` | RTC replication timeout | `15` |
| `alarm_failure_threshold` | Failed replication alarm threshold | `10` |
| `alarm_latency_threshold_seconds` | Replication latency alarm threshold | `900` |

## Post-Deployment Validation

### 1. Verify Infrastructure Deployment

```bash
# Check S3 buckets in all regions
aws s3 ls | grep multi-region

# Verify replication configuration
aws s3api get-bucket-replication --bucket <source-bucket-name>

# Check KMS keys
aws kms list-keys --region us-east-1
aws kms list-keys --region us-west-2
aws kms list-keys --region eu-west-1
```

### 2. Test Replication Functionality

```bash
# Upload test file to source bucket
echo "Multi-region replication test - $(date)" > test-file.txt
aws s3 cp test-file.txt s3://<source-bucket-name>/test/

# Wait for replication and verify in destination regions
sleep 60
aws s3 ls s3://<dest-bucket-1-name>/test/ --region us-west-2
aws s3 ls s3://<dest-bucket-2-name>/test/ --region eu-west-1
```

### 3. Validate Monitoring and Alerting

```bash
# Check CloudWatch dashboard
aws cloudwatch list-dashboards --region us-east-1

# Verify alarm configuration
aws cloudwatch describe-alarms --region us-east-1

# Test CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name ReplicationLatency \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --region us-east-1
```

## Operational Procedures

### Health Monitoring

The deployment includes automated health monitoring through:

- **CloudWatch Metrics**: Replication latency, failure rates, and bucket size metrics
- **CloudWatch Alarms**: Automated alerting for replication issues
- **CloudWatch Dashboard**: Centralized monitoring view
- **SNS Notifications**: Email/SMS alerts for critical issues

### Disaster Recovery Testing

```bash
# Test failover procedures (using generated scripts)
./scripts/health-check.sh
./scripts/failover-test.sh

# Validate cross-region access
aws s3 ls s3://<dest-bucket-name> --region us-west-2
```

### Cost Optimization

The solution includes several cost optimization features:

- **S3 Intelligent-Tiering**: Automatic cost optimization based on access patterns
- **Lifecycle Policies**: Automated transitions to cheaper storage classes
- **KMS Bucket Keys**: Reduced encryption costs for high-volume scenarios
- **Storage Class Analysis**: Recommendations for optimal storage class usage

## Security Features

### Encryption

- **Server-Side Encryption**: All buckets use customer-managed KMS keys
- **Regional Key Isolation**: Separate KMS keys per region for data sovereignty
- **In-Transit Encryption**: HTTPS-only bucket policies enforce encrypted connections

### Access Controls

- **IAM Roles**: Least privilege service roles for replication
- **Bucket Policies**: Restrictive policies preventing unauthorized access
- **Public Access Blocks**: Complete prevention of public access
- **CloudTrail Integration**: Comprehensive audit logging

### Compliance

- **Data Residency**: Region-specific encryption keys support compliance requirements
- **Audit Trails**: Complete logging of all S3 and KMS operations
- **Resource Tagging**: Comprehensive tagging for compliance and cost allocation

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name multi-region-s3-replication

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name multi-region-s3-replication
```

### Using CDK

```bash
# Destroy CDK infrastructure
cd cdk-typescript/ # or cdk-python/
cdk destroy MultiRegionS3ReplicationStack --force
```

### Using Terraform

```bash
# Destroy Terraform infrastructure
cd terraform/
terraform destroy \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2" \
    -var="tertiary_region=eu-west-1" \
    -var="environment=production"
```

### Using Bash Scripts

```bash
# Run destruction script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Force delete S3 buckets with objects
aws s3 rb s3://<bucket-name> --force --region <region>

# Delete KMS keys (scheduled deletion)
aws kms schedule-key-deletion \
    --key-id <key-id> \
    --pending-window-in-days 7 \
    --region <region>
```

## Customization

### Modifying Replication Rules

Edit the replication configuration in your chosen IaC tool to:

- Add additional destination regions
- Modify storage class transitions
- Customize replication priorities
- Configure prefix-based filtering

### Extending Monitoring

Enhance monitoring by:

- Adding custom CloudWatch metrics
- Integrating with AWS Config for compliance
- Setting up automated remediation with Lambda
- Implementing cost anomaly detection

### Security Enhancements

Consider additional security measures:

- AWS Organizations SCPs for governance
- AWS GuardDuty for threat detection
- AWS Security Hub for centralized security
- Cross-account replication for enhanced isolation

## Troubleshooting

### Common Issues

1. **Replication Delays**
   - Check IAM permissions for replication role
   - Verify KMS key policies allow S3 access
   - Monitor CloudWatch metrics for bottlenecks

2. **Permission Errors**
   - Ensure replication role has proper cross-region permissions
   - Verify bucket policies don't conflict with replication
   - Check KMS key policies in destination regions

3. **Cost Concerns**
   - Review data transfer charges between regions
   - Optimize storage classes for replicated data
   - Implement lifecycle policies for cost reduction

### Support Resources

- [AWS S3 Cross-Region Replication Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [AWS S3 Replication Time Control](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-time-control.html)
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
- [S3 Cost Optimization Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-costs.html)

## Support

For issues with this infrastructure code, refer to:

1. Original recipe documentation for architecture details
2. AWS service documentation for configuration options
3. Provider tool documentation (CloudFormation, CDK, Terraform)
4. AWS Support for service-specific issues

## License

This infrastructure code is provided as-is for educational and reference purposes. Review and modify according to your organization's requirements and security policies.