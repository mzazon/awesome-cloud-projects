# Infrastructure as Code for Optimizing Large File Uploads with S3 Multipart Strategies

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Optimizing Large File Uploads with S3 Multipart Strategies".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for S3 bucket creation and management
- CloudWatch dashboard access permissions
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name s3-multipart-upload-demo \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketNameSuffix,ParameterValue=$(openssl rand -hex 3) \
    --capabilities CAPABILITY_IAM
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
cdk bootstrap  # Only needed once per AWS account/region
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # Only needed once per AWS account/region
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## What Gets Deployed

This infrastructure creates:

- **S3 Bucket**: Configured for multipart upload demonstrations with lifecycle policies
- **Bucket Lifecycle Policy**: Automatically cleans up incomplete multipart uploads after 7 days
- **CloudWatch Dashboard**: Monitors S3 bucket metrics including object count and storage size
- **IAM Policies**: Appropriate permissions for multipart upload operations (where applicable)

## Configuration Options

### Environment Variables
- `AWS_REGION`: Target AWS region (defaults to configured CLI region)
- `BUCKET_NAME_SUFFIX`: Optional suffix for bucket naming (auto-generated if not provided)

### CloudFormation Parameters
- `BucketNameSuffix`: Unique suffix for bucket naming
- `LifecycleDays`: Days after which incomplete multipart uploads are cleaned up (default: 7)

### Terraform Variables
- `bucket_name_suffix`: Unique suffix for bucket naming
- `aws_region`: Target AWS region
- `lifecycle_cleanup_days`: Days for incomplete multipart upload cleanup
- `environment`: Environment tag for resources

### CDK Configuration
Both CDK implementations support customization through:
- Environment variables for region and account
- Constructor parameters for bucket naming and lifecycle policies
- Configurable CloudWatch dashboard widgets

## Testing the Infrastructure

After deployment, test the multipart upload functionality:

```bash
# Create a test file (1GB)
dd if=/dev/urandom of=test-large-file.bin bs=1048576 count=1024

# Configure AWS CLI for optimal multipart uploads
aws configure set default.s3.multipart_threshold 100MB
aws configure set default.s3.multipart_chunksize 100MB
aws configure set default.s3.max_concurrent_requests 10

# Upload using multipart upload
aws s3 cp test-large-file.bin s3://your-bucket-name/

# Verify upload
aws s3api head-object \
    --bucket your-bucket-name \
    --key test-large-file.bin
```

## Monitoring and Observability

The deployed CloudWatch dashboard provides:

- **Bucket Size Metrics**: Track storage growth over time
- **Object Count**: Monitor number of objects in the bucket
- **Request Metrics**: View upload and download activity (when enabled)

Access the dashboard in the AWS Console under CloudWatch > Dashboards > "S3-MultipartUpload-Monitoring".

## Cost Considerations

- **S3 Storage**: Standard storage charges apply for uploaded objects
- **Request Charges**: PUT requests for each multipart upload part
- **Incomplete Uploads**: Parts from incomplete uploads incur storage charges until cleaned up
- **CloudWatch**: Dashboard viewing is free; custom metrics incur minimal charges

Expected costs for testing: $0.10-$0.50 for a few hours of testing with 1-5GB files.

## Security Features

- **Bucket Encryption**: Server-side encryption enabled by default
- **Access Logging**: Optional S3 access logging configuration
- **Least Privilege**: IAM policies grant minimum required permissions
- **Lifecycle Management**: Automatic cleanup prevents orphaned storage charges

## Cleanup

### Using CloudFormation
```bash
# Remove all objects first (CloudFormation cannot delete non-empty buckets)
aws s3 rm s3://your-bucket-name --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name s3-multipart-upload-demo
```

### Using CDK
```bash
# Remove all objects first
aws s3 rm s3://your-bucket-name --recursive

# Destroy the stack
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Bucket Configuration
- Modify versioning settings in the IaC templates
- Adjust lifecycle policies for your retention requirements
- Configure cross-region replication if needed

### Performance Tuning
- Adjust multipart thresholds based on your file sizes
- Modify concurrent request limits based on your bandwidth
- Configure Transfer Acceleration for global users

### Monitoring Enhancements
- Add custom CloudWatch alarms for upload failures
- Implement AWS Config rules for bucket compliance
- Set up SNS notifications for lifecycle events

### Advanced Features
- Implement S3 Event Notifications for upload completion
- Add Lambda functions for post-upload processing
- Configure AWS DataSync for large-scale migrations

## Troubleshooting

### Common Issues

**Bucket Name Conflicts**
- S3 bucket names must be globally unique
- The infrastructure generates random suffixes to avoid conflicts
- If deployment fails, try with a different suffix

**Incomplete Multipart Upload Cleanup**
```bash
# List incomplete uploads
aws s3api list-multipart-uploads --bucket your-bucket-name

# Manually abort specific uploads
aws s3api abort-multipart-upload \
    --bucket your-bucket-name \
    --key filename \
    --upload-id upload-id
```

**Permission Errors**
- Ensure your AWS credentials have sufficient permissions
- Check that the IAM user/role can create S3 buckets and CloudWatch dashboards
- Verify region-specific permissions if using cross-region resources

**CloudWatch Dashboard Not Showing Data**
- S3 metrics may take 15-30 minutes to appear
- Ensure the bucket has some objects for metrics to be generated
- Check that CloudWatch has appropriate permissions

## Integration Examples

### Application Integration
```python
import boto3
from botocore.config import Config

# Configure S3 client for multipart uploads
config = Config(
    s3={
        'multipart_threshold': 100 * 1024 * 1024,  # 100MB
        'multipart_chunksize': 100 * 1024 * 1024,  # 100MB
        'max_concurrent_requests': 10
    }
)

s3_client = boto3.client('s3', config=config)

# Upload large file
s3_client.upload_file('large-file.bin', 'bucket-name', 'large-file.bin')
```

### CI/CD Pipeline Integration
```yaml
# Example GitHub Actions workflow
- name: Deploy S3 Infrastructure
  run: |
    cd terraform/
    terraform init
    terraform apply -auto-approve
    
- name: Upload Large Files
  run: |
    aws configure set default.s3.multipart_threshold 100MB
    aws s3 sync ./large-files/ s3://$BUCKET_NAME/
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS S3 multipart upload documentation
4. Review CloudFormation/CDK/Terraform provider documentation

## Version History

- **v1.1**: Initial infrastructure code generation
- Supports multipart upload optimization for large files
- Includes automated lifecycle management
- Provides comprehensive monitoring and cleanup capabilities