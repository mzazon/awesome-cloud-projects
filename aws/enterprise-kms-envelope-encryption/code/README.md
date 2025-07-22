# Infrastructure as Code for Enterprise KMS Envelope Encryption

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise KMS Envelope Encryption".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for KMS, S3, Lambda, CloudWatch Events, and IAM
- Basic understanding of encryption concepts and AWS KMS service
- Estimated cost: $15-25/month for KMS operations, Lambda executions, and S3 storage

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 18+ and npm
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8+ and pip
- AWS CDK CLI: `npm install -g aws-cdk`

#### Terraform
- Terraform 1.0+ installed
- AWS provider properly configured

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name enterprise-kms-encryption-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=RandomSuffix,ParameterValue=$(openssl rand -hex 3)

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name enterprise-kms-encryption-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name enterprise-kms-encryption-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output important resource identifiers
# Follow the prompts for any required inputs
```

## Architecture Overview

The infrastructure includes:

- **KMS Customer Master Key (CMK)** with automatic rotation enabled
- **S3 bucket** with KMS encryption configuration and versioning
- **Lambda function** for key rotation monitoring
- **IAM roles and policies** for secure Lambda execution
- **CloudWatch Events rule** for automated Lambda scheduling
- **CloudWatch log groups** for monitoring and auditing

## Configuration Options

### Environment Variables (for scripts)
```bash
export AWS_REGION="us-east-1"              # Target AWS region
export KMS_KEY_ALIAS="enterprise-encryption" # KMS key alias prefix
export ROTATION_SCHEDULE="rate(7 days)"    # CloudWatch Events schedule
```

### CloudFormation Parameters
- `RandomSuffix`: Unique suffix for resource names
- `KMSKeyAlias`: Alias for the KMS key
- `RotationSchedule`: CloudWatch Events schedule expression
- `LogRetentionDays`: CloudWatch logs retention period

### Terraform Variables
```bash
# terraform/terraform.tfvars
random_suffix = "abc123"
kms_key_alias = "enterprise-encryption"
rotation_schedule = "rate(7 days)"
log_retention_days = 30
```

## Testing the Deployment

After deployment, test the infrastructure:

```bash
# Test KMS key creation and rotation status
aws kms get-key-rotation-status --key-id alias/enterprise-encryption-${SUFFIX}

# Upload test file to encrypted S3 bucket
echo "Test data" > test-file.txt
aws s3 cp test-file.txt s3://enterprise-encrypted-data-${SUFFIX}/

# Manually invoke Lambda function
aws lambda invoke \
    --function-name kms-key-rotator-${SUFFIX} \
    --payload '{}' \
    response.json && cat response.json

# Check CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/kms-key-rotator"
```

## Monitoring and Compliance

The solution includes:

- **CloudWatch Logs**: All Lambda executions are logged
- **Key Rotation Monitoring**: Weekly automated checks of rotation status
- **S3 Access Logging**: Optional bucket-level access logging
- **CloudTrail Integration**: KMS API calls are automatically logged

To enable additional monitoring:

```bash
# Enable CloudTrail for KMS operations (if not already enabled)
aws cloudtrail create-trail \
    --name kms-audit-trail \
    --s3-bucket-name your-cloudtrail-bucket

# Create CloudWatch dashboard for KMS metrics
aws cloudwatch put-dashboard \
    --dashboard-name KMS-Monitoring \
    --dashboard-body file://monitoring-dashboard.json
```

## Security Considerations

- **Least Privilege IAM**: Lambda function has minimal required permissions
- **Encryption at Rest**: All S3 objects encrypted with customer-managed KMS keys
- **Key Rotation**: Automatic annual rotation with manual override capability
- **Audit Logging**: All key operations logged via CloudTrail
- **Resource Isolation**: Unique resource names prevent conflicts

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name enterprise-kms-encryption-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name enterprise-kms-encryption-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy --force

# Clean up CDK bootstrap (optional)
# cdk destroy CDKToolkit
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run destruction script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# The script includes safety checks and confirmation steps
```

## Troubleshooting

### Common Issues

1. **KMS Key Deletion**: Keys have a 7-day deletion waiting period
   ```bash
   # Cancel key deletion if needed
   aws kms cancel-key-deletion --key-id <key-id>
   ```

2. **S3 Bucket Not Empty**: Remove all objects before bucket deletion
   ```bash
   aws s3 rm s3://bucket-name --recursive
   ```

3. **Lambda Permission Errors**: Verify IAM role has correct policies attached
   ```bash
   aws iam list-attached-role-policies --role-name lambda-role-name
   ```

4. **CloudWatch Events Not Triggering**: Check rule state and target configuration
   ```bash
   aws events describe-rule --name rule-name
   ```

### Debug Mode

For detailed debugging, enable verbose logging:

```bash
# CloudFormation
aws cloudformation describe-stack-events --stack-name stack-name

# Terraform
export TF_LOG=DEBUG
terraform apply

# CDK
cdk deploy --debug
```

## Customization

### Adding Custom Key Policies

Modify the KMS key policy to restrict access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT-ID:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
```

### Extending Lambda Monitoring

Add custom metrics or SNS notifications:

```python
# Add to Lambda function
import boto3

cloudwatch = boto3.client('cloudwatch')
cloudwatch.put_metric_data(
    Namespace='KMS/KeyRotation',
    MetricData=[
        {
            'MetricName': 'RotationChecks',
            'Value': 1,
            'Unit': 'Count'
        }
    ]
)
```

### Multi-Region Deployment

For multi-region key replication:

```bash
# Create replica in different region
aws kms replicate-key \
    --key-id alias/enterprise-encryption \
    --replica-region us-west-2 \
    --replica-policy file://replica-policy.json
```

## Cost Optimization

- **KMS Keys**: $1/month per CMK + $0.03 per 10,000 requests
- **Lambda**: First 1M requests free, then $0.20 per 1M requests
- **S3 Storage**: Varies by storage class and region
- **CloudWatch Logs**: $0.50 per GB ingested

To minimize costs:
- Use S3 Bucket Keys to reduce KMS API calls
- Set appropriate CloudWatch log retention periods
- Consider S3 lifecycle policies for older data

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: [AWS KMS Developer Guide](https://docs.aws.amazon.com/kms/latest/developerguide/)
3. **CloudFormation**: [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
4. **CDK**: [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
5. **Terraform**: [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Additional Resources

- [AWS KMS Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-kms-best-practices/)
- [S3 Encryption Configuration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html)
- [Lambda Security Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/lambda-security.html)
- [CloudWatch Events User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)