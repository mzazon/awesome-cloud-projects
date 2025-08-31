# Infrastructure as Code for AWS CLI Setup and First Commands

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AWS CLI Setup and First Commands with CLI and S3".

## Overview

This recipe focuses on AWS CLI installation, configuration, and fundamental S3 operations. While the primary value is in learning CLI usage patterns, the infrastructure components include S3 buckets with security best practices, IAM policies for proper access control, and CloudWatch logging for operational visibility.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - S3 bucket creation and management
  - IAM role and policy creation
  - CloudWatch logging (optional)
- Administrative access for local CLI installation
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

> **Note**: This recipe demonstrates AWS CLI fundamentals. The IaC implementations provide the supporting infrastructure for practice and learning scenarios.

## Infrastructure Components

The infrastructure includes:

- **S3 Bucket**: Encrypted storage with versioning enabled
- **IAM Roles**: Least-privilege access for CLI operations
- **Bucket Policies**: Security controls and access restrictions
- **CloudWatch Logging**: Optional operational monitoring
- **KMS Keys**: Customer-managed encryption (optional)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name aws-cli-tutorial-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=tutorial \
        ParameterKey=BucketPrefix,ParameterValue=my-cli-tutorial

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name aws-cli-tutorial-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name aws-cli-tutorial-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Preview changes
npx cdk diff

# Deploy the stack
npx cdk deploy

# Get outputs
npx cdk ls --long
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

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export AWS_REGION="us-east-1"
export ENVIRONMENT="tutorial"
export BUCKET_PREFIX="my-cli-tutorial"

# Deploy infrastructure
./deploy.sh

# Verify deployment
aws s3 ls | grep $BUCKET_PREFIX
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

```bash
# Required
export AWS_REGION="us-east-1"              # AWS region for resources
export ENVIRONMENT="tutorial"              # Environment tag (tutorial, dev, prod)

# Optional
export BUCKET_PREFIX="my-cli-tutorial"     # S3 bucket name prefix
export ENABLE_VERSIONING="true"            # Enable S3 bucket versioning
export ENABLE_LOGGING="false"              # Enable CloudWatch logging
export KMS_ENCRYPTION="false"              # Use customer-managed KMS keys
export RETENTION_DAYS="7"                  # CloudWatch log retention
```

### Parameters by Implementation

#### CloudFormation Parameters

```yaml
Parameters:
  Environment:
    Description: Environment name for resource tagging
    Type: String
    Default: tutorial
    AllowedValues: [tutorial, dev, staging, prod]
  
  BucketPrefix:
    Description: Prefix for S3 bucket names
    Type: String
    Default: aws-cli-tutorial
  
  EnableVersioning:
    Description: Enable S3 bucket versioning
    Type: String
    Default: "true"
    AllowedValues: ["true", "false"]
  
  EnableLogging:
    Description: Enable CloudWatch logging
    Type: String
    Default: "false"
    AllowedValues: ["true", "false"]
```

#### CDK Configuration

```typescript
// cdk-typescript/cdk.json
{
  "context": {
    "environment": "tutorial",
    "bucketPrefix": "aws-cli-tutorial",
    "enableVersioning": true,
    "enableLogging": false,
    "retentionDays": 7
  }
}
```

#### Terraform Variables

```hcl
# terraform/terraform.tfvars
environment         = "tutorial"
bucket_prefix      = "aws-cli-tutorial"
enable_versioning  = true
enable_logging     = false
retention_days     = 7
kms_encryption     = false
```

## Validation and Testing

### Infrastructure Validation

```bash
# Verify S3 bucket creation
aws s3api head-bucket --bucket $(terraform output -raw bucket_name)

# Check bucket encryption
aws s3api get-bucket-encryption --bucket $(terraform output -raw bucket_name)

# Verify IAM role exists
aws iam get-role --role-name $(terraform output -raw cli_role_name)

# Test bucket access with temporary credentials
aws sts assume-role \
    --role-arn $(terraform output -raw cli_role_arn) \
    --role-session-name cli-test-session
```

### CLI Operations Testing

```bash
# Set bucket name from infrastructure output
export BUCKET_NAME=$(terraform output -raw bucket_name)

# Test basic S3 operations
echo "Hello AWS CLI Tutorial!" > test-file.txt
aws s3 cp test-file.txt s3://$BUCKET_NAME/
aws s3 ls s3://$BUCKET_NAME/
aws s3 cp s3://$BUCKET_NAME/test-file.txt downloaded-test.txt

# Verify file integrity
diff test-file.txt downloaded-test.txt

# Test CLI help and advanced features
aws s3api list-objects-v2 --bucket $BUCKET_NAME \
    --query 'Contents[].{Name:Key,Size:Size}' \
    --output table

# Clean up test files
rm -f test-file.txt downloaded-test.txt
aws s3 rm s3://$BUCKET_NAME/test-file.txt
```

### Security Validation

```bash
# Verify bucket public access is blocked
aws s3api get-public-access-block --bucket $(terraform output -raw bucket_name)

# Check bucket policy
aws s3api get-bucket-policy --bucket $(terraform output -raw bucket_name)

# Verify server-side encryption
aws s3api get-bucket-encryption --bucket $(terraform output -raw bucket_name)

# Test IAM policy restrictions
aws iam simulate-principal-policy \
    --policy-source-arn $(terraform output -raw cli_role_arn) \
    --action-names s3:GetObject \
    --resource-arns "arn:aws:s3:::$(terraform output -raw bucket_name)/*"
```

## Cleanup

### Using CloudFormation

```bash
# Empty S3 buckets first (required for deletion)
aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name aws-cli-tutorial-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text) --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name aws-cli-tutorial-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name aws-cli-tutorial-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy  # or: cdk destroy for Python

# Confirm deletion
npx cdk ls  # Should show no stacks
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup
aws s3 ls | grep $BUCKET_PREFIX || echo "All resources cleaned up"
```

## Troubleshooting

### Common Issues

1. **CLI Not Installed**: Ensure AWS CLI v2 is properly installed and in PATH
   ```bash
   aws --version  # Should show version 2.x.x
   ```

2. **Insufficient Permissions**: Verify your AWS credentials have required permissions
   ```bash
   aws sts get-caller-identity
   aws iam get-user
   ```

3. **Bucket Name Conflicts**: S3 bucket names must be globally unique
   ```bash
   # Use timestamp suffix for uniqueness
   export BUCKET_PREFIX="my-cli-tutorial-$(date +%Y%m%d-%H%M%S)"
   ```

4. **Region Mismatch**: Ensure all resources are in the same region
   ```bash
   aws configure get region
   export AWS_DEFAULT_REGION=$(aws configure get region)
   ```

### Debugging Commands

```bash
# Check AWS configuration
aws configure list
aws configure list-profiles

# Verify resource creation
aws cloudformation describe-stack-resources --stack-name aws-cli-tutorial-stack
aws s3api list-buckets --query 'Buckets[?contains(Name, `cli-tutorial`)]'

# Test connectivity
aws sts get-caller-identity
aws s3 ls
```

## Cost Considerations

### Estimated Costs

- **S3 Storage**: ~$0.023 per GB per month (Standard tier)
- **S3 Requests**: ~$0.0004 per 1,000 PUT requests
- **CloudWatch Logs**: ~$0.50 per GB per month (if enabled)
- **KMS Keys**: ~$1.00 per key per month (if customer-managed keys enabled)

### Cost Optimization

```bash
# Monitor storage usage
aws s3api list-objects-v2 --bucket $BUCKET_NAME \
    --query 'sum(Contents[].Size)' --output text

# Check bucket lifecycle configuration
aws s3api get-bucket-lifecycle-configuration --bucket $BUCKET_NAME

# Set up billing alerts
aws budgets create-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget file://budget-config.json
```

## Security Best Practices

### Applied Security Measures

1. **Encryption at Rest**: All S3 buckets use AES-256 encryption
2. **Encryption in Transit**: All CLI communications use HTTPS
3. **Access Control**: IAM policies follow least-privilege principle
4. **Public Access**: S3 public access is blocked by default
5. **Versioning**: Optional S3 versioning for data protection
6. **Logging**: Optional CloudWatch logging for audit trails

### Additional Security Recommendations

```bash
# Enable CloudTrail for API logging
aws cloudtrail create-trail \
    --name cli-tutorial-trail \
    --s3-bucket-name $(terraform output -raw logging_bucket_name)

# Configure MFA for sensitive operations
aws iam create-virtual-mfa-device \
    --virtual-mfa-device-name cli-tutorial-mfa \
    --outfile mfa-qr-code.png \
    --bootstrap-method QRCodePNG

# Use temporary credentials
aws sts get-session-token --duration-seconds 3600
```

## Learning Resources

### AWS CLI Documentation

- [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/)
- [AWS CLI Command Reference](https://docs.aws.amazon.com/cli/latest/reference/)
- [AWS CLI Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)

### S3 Best Practices

- [S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [S3 Performance Guidelines](https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-performance.html)
- [S3 Cost Optimization](https://docs.aws.amazon.com/AmazonS3/latest/userguide/optimizing-costs.html)

### Infrastructure as Code

- [CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
- [CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: Check official AWS service documentation
3. **Community Support**: AWS forums and Stack Overflow
4. **Professional Support**: AWS Support plans for production workloads

## Contributing

When modifying this infrastructure code:

1. Follow the respective tool's best practices
2. Maintain security standards and least-privilege access
3. Update documentation and comments
4. Test changes in a non-production environment
5. Validate resource cleanup procedures

---

**Note**: This infrastructure supports the AWS CLI learning recipe. The primary value is in mastering CLI commands and patterns, while the IaC provides a consistent, secure foundation for practice and experimentation.