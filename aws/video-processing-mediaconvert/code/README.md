# Infrastructure as Code for Building Video Processing Workflows with S3, Lambda, and MediaConvert

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Video Processing Workflows with S3, Lambda, and MediaConvert".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The deployed infrastructure creates an automated video processing workflow that:

1. **Receives video uploads** in an S3 source bucket
2. **Triggers Lambda processing** via S3 event notifications
3. **Initiates MediaConvert jobs** for video transcoding
4. **Outputs processed videos** to an S3 output bucket in multiple formats (HLS, MP4)
5. **Distributes content globally** via CloudFront CDN
6. **Handles job completion** through EventBridge and Lambda

### Key Components

- **S3 Buckets**: Source and output storage for video files
- **Lambda Functions**: Event-driven orchestration and completion handling
- **MediaConvert**: Professional video transcoding service
- **CloudFront**: Global content delivery network
- **EventBridge**: Event-driven workflow coordination
- **IAM Roles**: Secure service-to-service authentication
- **CloudWatch**: Logging and monitoring

## Prerequisites

- AWS CLI installed and configured
- Appropriate IAM permissions for:
  - S3 (CreateBucket, PutObject, GetObject)
  - Lambda (CreateFunction, UpdateFunctionCode)
  - MediaConvert (CreateJob, DescribeEndpoints)
  - IAM (CreateRole, AttachRolePolicy)
  - CloudFront (CreateDistribution)
  - EventBridge (PutRule, PutTargets)
  - CloudWatch (CreateLogGroup)
- Estimated cost: $5-15 for testing (depends on video processing volume)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- AWS CDK v2 installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.5.0 or later
- AWS provider 5.0 or later

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name video-processing-workflow \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=SourceBucketName,ParameterValue=my-video-source-bucket \
                 ParameterKey=OutputBucketName,ParameterValue=my-video-output-bucket
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
cdk bootstrap  # If first time using CDK in this account/region
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # If first time using CDK in this account/region
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

## Configuration

Each implementation supports customization through parameters/variables:

### Common Parameters
- `SourceBucketName`: S3 bucket for video uploads
- `OutputBucketName`: S3 bucket for processed videos
- `LambdaTimeout`: Lambda function timeout (default: 60 seconds)
- `MediaConvertQueue`: MediaConvert queue priority (default: Default)
- `CloudFrontPriceClass`: CloudFront price class (default: PriceClass_100)
- `Environment`: Environment name (dev/staging/prod)
- `ProjectName`: Project name for resource naming

### Video Processing Settings
- `MediaConvertBitrate`: Video bitrate in bits per second (default: 2000000)
- `MediaConvertFramerate`: Video framerate (default: 30)
- `MediaConvertWidth`: Video width in pixels (default: 1280)
- `MediaConvertHeight`: Video height in pixels (default: 720)

### Terraform-Specific Variables

```hcl
# terraform.tfvars example
aws_region = "us-east-1"
environment = "dev"
project_name = "video-processing"
lambda_timeout = 60
mediaconvert_bitrate = 2000000
mediaconvert_framerate = 30
mediaconvert_width = 1280
mediaconvert_height = 720
cloudfront_enabled = true
enable_completion_handler = true
s3_lifecycle_enabled = true
```

## Testing the Deployment

1. **Upload a test video**:
   ```bash
   # For CloudFormation/CDK
   aws s3 cp test-video.mp4 s3://your-source-bucket/
   
   # For Terraform
   aws s3 cp test-video.mp4 s3://$(terraform output -raw s3_source_bucket_name)/
   ```

2. **Monitor processing**:
   ```bash
   # Monitor Lambda logs
   aws logs tail /aws/lambda/video-processor-function --follow
   ```

3. **Check outputs**:
   ```bash
   # For CloudFormation/CDK
   aws s3 ls s3://your-output-bucket/ --recursive
   
   # For Terraform
   aws s3 ls s3://$(terraform output -raw s3_output_bucket_name)/ --recursive
   ```

## Video Processing Capabilities

The deployed infrastructure supports:

- **Input Formats**: MP4, MOV, AVI, MKV, M4V
- **Output Formats**: 
  - HLS adaptive bitrate streaming (720p)
  - MP4 format (720p)
- **Video Codec**: H.264
- **Audio Codec**: AAC encoding at 96kbps
- **Automatic Scaling**: Serverless architecture scales with demand

## Monitoring and Debugging

### CloudWatch Logs
```bash
# Monitor video processor logs
aws logs tail /aws/lambda/video-processor-function --follow

# Monitor completion handler logs
aws logs tail /aws/lambda/completion-handler-function --follow
```

### MediaConvert Jobs
```bash
# List recent MediaConvert jobs
aws mediaconvert list-jobs --endpoint-url MEDIACONVERT_ENDPOINT --max-results 10

# Get job details
aws mediaconvert get-job --endpoint-url MEDIACONVERT_ENDPOINT --id JOB_ID
```

### S3 Content Verification
```bash
# Check source bucket contents
aws s3 ls s3://your-source-bucket/

# Check output bucket contents
aws s3 ls s3://your-output-bucket/ --recursive
```

## Security Features

- **S3 bucket encryption** using AES-256
- **S3 public access blocked** on all buckets
- **IAM roles** with least privilege access
- **CloudFront HTTPS** enforcement
- **Resource-based policies** for secure service integration

## Cost Optimization

- **S3 lifecycle policies** for automatic storage class transitions
- **CloudFront caching** to reduce origin requests
- **Lambda provisioned concurrency** disabled by default
- **MediaConvert on-demand** pricing (no reserved capacity)
- **CloudWatch log retention** set to 30 days

### Estimated Monthly Costs
- **S3 Storage**: ~$0.023 per GB per month
- **Lambda Invocations**: ~$0.20 per 1M invocations
- **MediaConvert**: ~$0.0075 per minute of video processed
- **CloudFront**: ~$0.085 per GB data transfer
- **Total**: Varies based on video processing volume

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name video-processing-workflow
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
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

### Adding New Output Formats

Modify the MediaConvert job template in the Lambda function to include additional output groups:

```python
# Add new output group for different resolution
{
    "Name": "File Group 480p",
    "OutputGroupSettings": {
        "Type": "FILE_GROUP_SETTINGS",
        "FileGroupSettings": {
            "Destination": f"s3://{output_bucket}/mp4-480p/"
        }
    },
    "Outputs": [...] # Configure 480p output settings
}
```

### Custom Processing Logic

Extend the completion handler Lambda function to:
- Send SNS notifications
- Update DynamoDB records
- Trigger additional workflows
- Generate custom thumbnails

### Advanced Security

- Enable S3 bucket encryption with KMS
- Use AWS KMS for encryption keys
- Implement VPC endpoints for private communication
- Add WAF protection for CloudFront

## Troubleshooting

### Common Issues

1. **MediaConvert Job Failures**:
   - Check input video format compatibility
   - Verify S3 bucket permissions
   - Review MediaConvert service limits

2. **Lambda Timeout Errors**:
   - Increase Lambda timeout value
   - Optimize job creation logic
   - Implement retry mechanisms

3. **S3 Event Notification Issues**:
   - Verify Lambda function permissions
   - Check S3 event configuration
   - Review CloudWatch logs

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name video-processor-function

# Test Lambda function manually
aws lambda invoke --function-name video-processor-function --payload '{"test": "event"}' response.json

# Check S3 event notification configuration
aws s3api get-bucket-notification-configuration --bucket your-source-bucket
```

## Performance Optimization

- **Parallel Processing**: Lambda automatically handles concurrent video uploads
- **Regional Optimization**: Deploy in regions close to your users
- **Caching Strategy**: Configure CloudFront caching for optimal performance
- **Monitoring**: Use CloudWatch metrics to identify bottlenecks

## Advanced Configuration

### VPC Integration

For enhanced security, deploy Lambda functions within a VPC:

```hcl
# Terraform example
vpc_id = "vpc-12345678"
subnet_ids = ["subnet-12345678", "subnet-87654321"]
security_group_ids = ["sg-12345678"]
```

### Custom Domain and SSL

Integrate with Route53 and Certificate Manager:

```hcl
# Variables for custom domain
domain_name = "videos.example.com"
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
```

### Multi-Region Deployment

For global redundancy:

```bash
# Deploy in multiple regions using Terraform
terraform workspace new us-west-2
terraform apply -var="aws_region=us-west-2"

terraform workspace new eu-west-1
terraform apply -var="aws_region=eu-west-1"
```

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../video-processing-workflows-s3-lambda-elastic-transcoder.md)
- [AWS MediaConvert Developer Guide](https://docs.aws.amazon.com/mediaconvert/latest/ug/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS S3 Developer Guide](https://docs.aws.amazon.com/s3/latest/dev/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)

## License

This infrastructure code is provided under the same license as the recipe collection.

## Version History

- **v1.0**: Initial Terraform implementation
- **v1.1**: Added CloudFront distribution and completion handler
- **v1.2**: Enhanced security and monitoring features
- **v1.3**: Added comprehensive documentation and examples
- **v1.4**: Added CloudFormation, CDK TypeScript, CDK Python, and Bash implementations