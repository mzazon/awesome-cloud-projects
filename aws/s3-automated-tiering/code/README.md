# Infrastructure as Code for S3 Automated Tiering and Lifecycle Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "S3 Automated Tiering and Lifecycle Management".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for S3, IAM, and CloudWatch
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform v1.0+ installed
- For bash scripts: bash shell and jq utility

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name intelligent-tiering-s3-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=my-intelligent-bucket \
    --capabilities CAPABILITY_IAM

# Monitor deployment status
aws cloudformation describe-stacks \
    --stack-name intelligent-tiering-s3-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python
```bash
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
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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

# Verify deployment
aws s3 ls | grep intelligent-tiering
```

## What Gets Deployed

This infrastructure creates:

1. **S3 Bucket** with versioning enabled
2. **Intelligent Tiering Configuration** for automatic cost optimization
3. **Lifecycle Policies** for additional storage management
4. **CloudWatch Dashboard** for monitoring storage metrics
5. **IAM Roles and Policies** for CloudWatch access to S3 metrics
6. **S3 Bucket Metrics Configuration** for detailed monitoring

## Configuration Options

### CloudFormation Parameters
- `BucketName`: Name for the S3 bucket (must be globally unique)
- `IntelligentTieringId`: ID for the intelligent tiering configuration
- `ArchiveAfterDays`: Days before moving to Archive Access tier (default: 90)
- `DeepArchiveAfterDays`: Days before moving to Deep Archive tier (default: 180)

### CDK Context Values
Customize deployment by setting context values:
```bash
# TypeScript
cdk deploy -c bucketName=my-custom-bucket -c archiveDays=60

# Python
cdk deploy -c bucket_name=my-custom-bucket -c archive_days=60
```

### Terraform Variables
```bash
# Using terraform.tfvars file
echo 'bucket_name = "my-intelligent-bucket"' > terraform.tfvars
echo 'archive_after_days = 60' >> terraform.tfvars
terraform apply

# Using command line
terraform apply \
    -var="bucket_name=my-intelligent-bucket" \
    -var="archive_after_days=60"
```

### Bash Script Environment Variables
```bash
export BUCKET_NAME="my-intelligent-bucket"
export ARCHIVE_DAYS="60"
export DEEP_ARCHIVE_DAYS="120"
./scripts/deploy.sh
```

## Monitoring and Validation

After deployment, verify the configuration:

```bash
# Check intelligent tiering configuration
aws s3api get-bucket-intelligent-tiering-configuration \
    --bucket YOUR_BUCKET_NAME \
    --id EntireBucketConfig

# Check lifecycle configuration
aws s3api get-bucket-lifecycle-configuration \
    --bucket YOUR_BUCKET_NAME

# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "S3-Storage-Optimization-Dashboard"
```

## Cost Optimization Features

- **Automatic Tiering**: Objects automatically move between Frequent and Infrequent Access based on usage
- **Archive Transitions**: Objects transition to Archive Access after 90 days (configurable)
- **Deep Archive**: Long-term archival after 180 days (configurable)
- **Incomplete Upload Cleanup**: Automatically removes incomplete multipart uploads after 7 days
- **Version Management**: Optimizes storage costs for object versions

## Cleanup

### Using CloudFormation
```bash
# Empty the bucket first (CloudFormation cannot delete non-empty buckets)
aws s3 rm s3://YOUR_BUCKET_NAME --recursive

# Delete all object versions
aws s3api delete-objects \
    --bucket YOUR_BUCKET_NAME \
    --delete "$(aws s3api list-object-versions \
        --bucket YOUR_BUCKET_NAME \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"

# Delete the stack
aws cloudformation delete-stack --stack-name intelligent-tiering-s3-stack
```

### Using CDK
```bash
# From the appropriate CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Adding Custom Prefixes
Modify the intelligent tiering configuration to target specific prefixes:

```json
{
    "Filter": {
        "Prefix": "documents/"
    }
}
```

### Custom Lifecycle Rules
Add additional lifecycle rules for specific use cases:

```json
{
    "ID": "LogsCleanup",
    "Status": "Enabled",
    "Filter": {
        "Prefix": "logs/"
    },
    "Expiration": {
        "Days": 30
    }
}
```

### Advanced Monitoring
Extend CloudWatch monitoring with custom metrics and alarms:

```bash
# Create cost alert
aws cloudwatch put-metric-alarm \
    --alarm-name "S3-Storage-Cost-Alert" \
    --alarm-description "Alert when S3 costs exceed threshold" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 86400 \
    --threshold 100 \
    --comparison-operator GreaterThanThreshold
```

## Troubleshooting

### Common Issues

1. **Bucket Name Already Exists**: S3 bucket names must be globally unique
   - Solution: Use a different bucket name or add a random suffix

2. **Insufficient Permissions**: Deployment fails due to missing permissions
   - Solution: Ensure your AWS credentials have the required IAM permissions

3. **Region Mismatch**: Resources created in wrong region
   - Solution: Set AWS_DEFAULT_REGION environment variable or configure AWS CLI

4. **CloudWatch Metrics Not Appearing**: Metrics may take up to 24 hours to appear
   - Solution: Wait for initial metrics collection period

### Debug Commands

```bash
# Check bucket configuration
aws s3api get-bucket-location --bucket YOUR_BUCKET_NAME

# Verify IAM permissions
aws iam get-user --query 'User.UserName'

# Test S3 access
aws s3 ls s3://YOUR_BUCKET_NAME
```

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation for conceptual guidance
2. Check AWS documentation for service-specific configuration details
3. Review CloudFormation/CDK/Terraform provider documentation for syntax issues
4. Verify your AWS credentials and permissions

## Security Considerations

- All resources are created with least privilege access
- Bucket versioning is enabled for data protection
- CloudWatch logging provides audit trail
- IAM roles limit access to only required actions
- No public access is granted to S3 buckets

## Cost Estimation

- **S3 Intelligent Tiering**: $0.0025 per 1,000 objects monitored monthly
- **CloudWatch Metrics**: Included in AWS Free Tier (first 10 metrics free)
- **S3 Storage**: Variable based on data volume and tier utilization
- **Typical Savings**: 20-68% reduction in storage costs

Monitor actual costs using AWS Cost Explorer and the deployed CloudWatch dashboard.