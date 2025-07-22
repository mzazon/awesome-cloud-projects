# Infrastructure as Code for Data Encryption at Rest and in Transit

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Encryption at Rest and in Transit".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements comprehensive data encryption using:

- **AWS KMS**: Customer-managed keys for centralized encryption key management
- **S3**: Server-side encryption with KMS (SSE-KMS) for object storage
- **RDS**: Database encryption at rest using KMS keys
- **EC2/EBS**: Encrypted EBS volumes for compute instances
- **Secrets Manager**: Encrypted storage for sensitive configuration data
- **Certificate Manager**: SSL/TLS certificates for data in transit
- **CloudTrail**: Audit logging for encryption events

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for:
  - KMS (Key Management Service)
  - S3 (Simple Storage Service)
  - RDS (Relational Database Service)
  - EC2 (Elastic Compute Cloud)
  - Certificate Manager
  - Secrets Manager
  - CloudTrail
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of encryption concepts and AWS security services
- Estimated cost: $15-25/month for KMS keys, RDS instance, and certificate management

> **Security Note**: This recipe creates production-ready encryption infrastructure. Ensure you have appropriate permissions and follow your organization's security policies.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name data-encryption-demo \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name data-encryption-demo \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name data-encryption-demo \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
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

# Apply the infrastructure
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

# The script will:
# 1. Create KMS customer-managed key
# 2. Set up encrypted S3 bucket
# 3. Deploy encrypted RDS instance
# 4. Configure encrypted EC2 instance
# 5. Set up Secrets Manager
# 6. Configure CloudTrail logging
```

## Configuration Options

### Environment Variables

Set these environment variables to customize the deployment:

```bash
# Required
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Optional customization
export ENVIRONMENT=demo
export PROJECT_NAME=encryption-demo
export KMS_KEY_ALIAS=alias/encryption-demo-key
export S3_BUCKET_PREFIX=encrypted-data-bucket
export RDS_INSTANCE_CLASS=db.t3.micro
export EC2_INSTANCE_TYPE=t3.micro
```

### Parameters

Each IaC implementation supports customizable parameters:

- **Environment**: Deployment environment (dev, staging, prod)
- **KmsKeyAlias**: Alias for the customer-managed KMS key
- **S3BucketPrefix**: Prefix for S3 bucket names
- **RdsInstanceClass**: RDS instance size
- **Ec2InstanceType**: EC2 instance type
- **EnableCloudTrail**: Enable CloudTrail logging (true/false)

## Verification Steps

After deployment, verify the encryption implementation:

### 1. Verify KMS Key Creation

```bash
# Check KMS key status
aws kms describe-key --key-id alias/encryption-demo-key \
    --query 'KeyMetadata.[KeyId,KeyState,KeyUsage]'
```

### 2. Test S3 Encryption

```bash
# Upload test file
echo "Test encryption content" > test-file.txt
aws s3 cp test-file.txt s3://your-bucket-name/

# Verify encryption
aws s3api head-object \
    --bucket your-bucket-name \
    --key test-file.txt \
    --query '[ServerSideEncryption,SSEKMSKeyId]'

# Clean up
aws s3 rm s3://your-bucket-name/test-file.txt
rm test-file.txt
```

### 3. Verify RDS Encryption

```bash
# Check RDS encryption status
aws rds describe-db-instances \
    --db-instance-identifier your-rds-instance \
    --query 'DBInstances[0].[StorageEncrypted,KmsKeyId]'
```

### 4. Test Secrets Manager

```bash
# Retrieve encrypted secret
aws secretsmanager get-secret-value \
    --secret-id your-secret-name \
    --query 'SecretString' --output text
```

### 5. Verify EBS Encryption

```bash
# Check EC2 instance volumes
aws ec2 describe-instances \
    --instance-ids your-instance-id \
    --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.[Encrypted,KmsKeyId]'
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name data-encryption-demo

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name data-encryption-demo \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete CloudTrail configuration
# 2. Terminate EC2 instances
# 3. Delete RDS instances
# 4. Delete S3 buckets
# 5. Delete Secrets Manager secrets
# 6. Schedule KMS key deletion
# 7. Clean up VPC resources
```

## Security Considerations

### Key Management

- **KMS Keys**: Customer-managed keys provide full control over encryption policies
- **Key Rotation**: Automatic key rotation is enabled for enhanced security
- **Key Policies**: Implement least privilege access to encryption keys
- **Audit Logging**: All key usage is logged in CloudTrail

### Data Protection

- **Encryption at Rest**: All data storage services use AES-256 encryption
- **Encryption in Transit**: TLS 1.2+ for all network communications
- **Secret Management**: Credentials stored in Secrets Manager with automatic rotation
- **Access Control**: IAM roles and policies enforce least privilege access

### Compliance

This implementation supports compliance with:

- **HIPAA**: Healthcare data protection requirements
- **PCI DSS**: Payment card industry data security standards
- **SOC 2**: Service organization control framework
- **FedRAMP**: Federal risk and authorization management program

## Cost Optimization

### KMS Costs

- Customer-managed keys: $1/month per key
- API requests: $0.03 per 10,000 requests
- Use S3 bucket keys to reduce API calls by up to 99%

### Storage Costs

- S3 encryption: No additional cost for SSE-KMS
- RDS encryption: No additional cost for storage encryption
- EBS encryption: No additional cost for volume encryption

### Monitoring

- CloudTrail: Data events may incur additional charges
- Use lifecycle policies to manage log retention costs

## Troubleshooting

### Common Issues

1. **KMS Key Access Denied**
   - Verify IAM permissions include KMS actions
   - Check key policy allows the required operations

2. **RDS Encryption Error**
   - Ensure KMS key is in the same region as RDS
   - Verify RDS service has permissions to use the key

3. **S3 Encryption Issues**
   - Confirm bucket policy allows KMS operations
   - Check bucket key configuration for cost optimization

4. **Certificate Validation**
   - Verify domain ownership for ACM certificates
   - Check DNS records for certificate validation

### Support Resources

- [AWS KMS Documentation](https://docs.aws.amazon.com/kms/)
- [S3 Encryption Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html)
- [RDS Encryption Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html)
- [AWS Certificate Manager Documentation](https://docs.aws.amazon.com/acm/)

## Advanced Configuration

### Multi-Region Encryption

For multi-region deployments, consider:

- Cross-region KMS key replication
- S3 cross-region replication with encryption
- RDS cross-region snapshots with encryption

### Automated Compliance Reporting

Extend the solution with:

- AWS Config rules for encryption compliance
- Lambda functions for automated reporting
- CloudWatch dashboards for monitoring

### Custom Key Policies

Implement advanced key policies for:

- Cross-account access
- Service-specific permissions
- Time-based access controls

## Performance Considerations

### KMS Performance

- Use data keys for high-volume encryption operations
- Implement caching for frequently accessed keys
- Consider regional key placement for latency optimization

### Application Integration

- Use AWS SDK encryption libraries
- Implement proper error handling for encryption operations
- Consider client-side encryption for sensitive data

## Maintenance

### Regular Tasks

- Review and update key policies quarterly
- Monitor CloudTrail logs for anomalous key usage
- Update certificates before expiration
- Review and rotate secrets regularly

### Security Updates

- Keep AWS CLI and SDKs updated
- Review AWS security bulletins
- Update IAM policies as needed
- Monitor AWS service deprecations

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Consult AWS support for service-specific issues
4. Refer to the original recipe documentation for implementation details

---

**Warning**: This infrastructure creates billable AWS resources. Monitor your AWS billing dashboard and follow cleanup procedures to avoid unexpected charges.

**Note**: Always test encryption implementations in a development environment before deploying to production. Ensure you have appropriate backup and recovery procedures for encrypted data.