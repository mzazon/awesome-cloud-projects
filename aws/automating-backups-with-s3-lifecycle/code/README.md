# Infrastructure as Code for Automating Backups with S3 and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating Backups with S3 and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

This solution creates an automated backup system using:

- **Amazon S3**: Primary and backup buckets with versioning and lifecycle policies
- **AWS Lambda**: Python function to perform backup operations
- **Amazon EventBridge**: Scheduled rule to trigger backups daily
- **IAM Role**: Permissions for Lambda to access S3 and CloudWatch Logs

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions to create:
  - S3 buckets
  - Lambda functions
  - EventBridge rules
  - IAM roles and policies
- For CDK implementations:
  - Node.js 18+ (for TypeScript)
  - Python 3.9+ (for Python)
  - AWS CDK CLI: `npm install -g aws-cdk`
- For Terraform:
  - Terraform 1.0+
- Estimated cost: <$5/month for small backup solutions (varies by data volume)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name scheduled-s3-backup \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BackupSchedule,ParameterValue="cron(0 1 * * ? *)"

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name scheduled-s3-backup \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# The script will prompt for configuration values
# or you can set environment variables:
export BACKUP_SCHEDULE="cron(0 1 * * ? *)"
export LIFECYCLE_TRANSITION_DAYS=30
export LIFECYCLE_GLACIER_DAYS=90
export LIFECYCLE_EXPIRATION_DAYS=365
```

## Testing the Deployment

After deployment, test the backup system:

1. **Upload test files to the primary bucket**:
   ```bash
   # Get bucket names from outputs
   PRIMARY_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name scheduled-s3-backup \
       --query 'Stacks[0].Outputs[?OutputKey==`PrimaryBucketName`].OutputValue' \
       --output text)
   
   # Upload test files
   echo "Test file 1" > test1.txt
   echo "Test file 2" > test2.txt
   aws s3 cp test1.txt s3://${PRIMARY_BUCKET}/
   aws s3 cp test2.txt s3://${PRIMARY_BUCKET}/
   ```

2. **Manually trigger the backup function**:
   ```bash
   # Get function name from outputs
   FUNCTION_NAME=$(aws cloudformation describe-stacks \
       --stack-name scheduled-s3-backup \
       --query 'Stacks[0].Outputs[?OutputKey==`BackupFunctionName`].OutputValue' \
       --output text)
   
   # Invoke the function
   aws lambda invoke \
       --function-name ${FUNCTION_NAME} \
       --payload '{}' \
       response.json
   
   # Check response
   cat response.json
   ```

3. **Verify backup was created**:
   ```bash
   # Get backup bucket name
   BACKUP_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name scheduled-s3-backup \
       --query 'Stacks[0].Outputs[?OutputKey==`BackupBucketName`].OutputValue' \
       --output text)
   
   # List backup bucket contents
   aws s3 ls s3://${BACKUP_BUCKET}/
   ```

## Customization

### CloudFormation Parameters
- `BackupSchedule`: EventBridge cron expression (default: daily at 1 AM UTC)
- `LifecycleTransitionDays`: Days before transitioning to Standard-IA (default: 30)
- `LifecycleGlacierDays`: Days before transitioning to Glacier (default: 90)
- `LifecycleExpirationDays`: Days before expiring objects (default: 365)

### CDK Configuration
Modify the configuration in the CDK app files:
- `backupSchedule`: EventBridge schedule expression
- `lifecycleRules`: S3 lifecycle policy configuration
- `lambdaTimeout`: Lambda function timeout (default: 60 seconds)
- `lambdaMemorySize`: Lambda memory allocation (default: 128 MB)

### Terraform Variables
Edit `terraform/variables.tf` or create a `terraform.tfvars` file:
```hcl
backup_schedule = "cron(0 1 * * ? *)"
lifecycle_transition_days = 30
lifecycle_glacier_days = 90
lifecycle_expiration_days = 365
lambda_timeout = 60
lambda_memory_size = 128
```

### Bash Script Environment Variables
Set these variables before running the deploy script:
```bash
export BACKUP_SCHEDULE="cron(0 1 * * ? *)"
export LIFECYCLE_TRANSITION_DAYS=30
export LIFECYCLE_GLACIER_DAYS=90
export LIFECYCLE_EXPIRATION_DAYS=365
export LAMBDA_TIMEOUT=60
export LAMBDA_MEMORY_SIZE=128
```

## Monitoring

### CloudWatch Logs
Monitor Lambda function execution:
```bash
# View recent logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/scheduled-s3-backup"

# Tail logs in real-time
aws logs tail /aws/lambda/scheduled-s3-backup-function --follow
```

### CloudWatch Metrics
Key metrics to monitor:
- Lambda function duration and errors
- S3 bucket size and request metrics
- EventBridge rule invocations

### S3 Metrics
Monitor backup bucket:
```bash
# Check bucket size
aws s3 ls s3://your-backup-bucket --recursive --human-readable --summarize
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege**: IAM role has minimal permissions required
- **Encryption**: S3 buckets use server-side encryption by default
- **Versioning**: Backup bucket has versioning enabled
- **Lifecycle Management**: Automatic cleanup prevents unlimited storage growth
- **Cross-Account Access**: Not enabled by default (can be configured if needed)

## Troubleshooting

### Common Issues

1. **Lambda timeout errors**:
   - Increase Lambda timeout in configuration
   - Consider using S3 Batch Operations for large datasets

2. **Permission denied errors**:
   - Verify IAM role has correct permissions
   - Check S3 bucket policies

3. **EventBridge not triggering**:
   - Verify cron expression syntax
   - Check EventBridge rule is enabled
   - Confirm Lambda function has proper permissions

4. **High costs**:
   - Review lifecycle policy settings
   - Consider using S3 Intelligent-Tiering
   - Monitor S3 request charges

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name your-function-name

# Check EventBridge rule
aws events describe-rule --name your-rule-name

# Check S3 bucket lifecycle configuration
aws s3api get-bucket-lifecycle-configuration --bucket your-backup-bucket

# Check recent Lambda invocations
aws lambda list-invocations --function-name your-function-name
```

## Cleanup

### Using CloudFormation
```bash
# Delete all objects from S3 buckets first
aws s3 rm s3://your-primary-bucket --recursive
aws s3 rm s3://your-backup-bucket --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name scheduled-s3-backup

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name scheduled-s3-backup \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/
# or cd cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Cost Optimization

To minimize costs:

1. **Adjust lifecycle policies** to transition to cheaper storage classes sooner
2. **Use S3 Intelligent-Tiering** for unpredictable access patterns
3. **Set appropriate expiration policies** to avoid unlimited storage growth
4. **Monitor S3 request charges** and optimize backup frequency if needed
5. **Consider S3 One Zone-IA** for less critical backups

## Extensions

Consider these enhancements:

1. **Cross-region replication** for disaster recovery
2. **SNS notifications** for backup completion/failure alerts
3. **Selective backup** based on file tags or prefixes
4. **Backup verification** to ensure file integrity
5. **Restore functionality** for easy recovery operations

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Consult the troubleshooting section above
4. Check CloudWatch logs for detailed error messages

## License

This infrastructure code is provided as-is for educational and demonstration purposes.