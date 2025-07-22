# Infrastructure as Code for Adaptive Bitrate Video Streaming with CloudFront

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Adaptive Bitrate Video Streaming with CloudFront".

## Overview

This infrastructure deploys a complete adaptive bitrate streaming solution that automatically converts uploaded videos into multiple quality variants and distributes them globally through CloudFront. The solution includes:

- S3 buckets for source videos and processed outputs
- AWS Elemental MediaConvert for video transcoding
- Lambda function for automated processing triggers
- CloudFront distribution for global content delivery
- IAM roles and policies with least privilege access
- Comprehensive monitoring and logging

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - MediaConvert service access
  - Lambda function deployment
  - CloudFront distribution creation
  - IAM role and policy management
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Architecture

The solution creates an event-driven video processing pipeline:

1. Videos uploaded to source S3 bucket trigger Lambda function
2. Lambda creates MediaConvert jobs using predefined templates
3. MediaConvert transcodes videos into HLS and DASH formats with multiple bitrates
4. Processed content is stored in output S3 bucket
5. CloudFront serves content globally with optimized caching

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name adaptive-streaming-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name adaptive-streaming-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name adaptive-streaming-stack \
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
cdk deploy

# View outputs
cdk output
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
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# View deployment summary
cat deployment-summary.txt
```

## Configuration

### Environment Variables

All implementations support these configuration options:

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Deployment environment (dev/staging/prod) | `dev` |
| `source_bucket_name` | Name for source video bucket | Auto-generated |
| `output_bucket_name` | Name for processed video bucket | Auto-generated |
| `cloudfront_price_class` | CloudFront price class | `PriceClass_100` |
| `lambda_timeout` | Lambda function timeout in seconds | `300` |
| `enable_cors` | Enable CORS on output bucket | `true` |

### Customization Examples

#### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name adaptive-streaming-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=CloudFrontPriceClass,ParameterValue=PriceClass_All \
        ParameterKey=LambdaTimeout,ParameterValue=600
```

#### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
environment = "production"
cloudfront_price_class = "PriceClass_All"
lambda_timeout = 600
enable_monitoring = true
```

#### CDK Context

```bash
cdk deploy -c environment=production -c priceClass=PriceClass_All
```

## Testing the Deployment

After deployment, test the adaptive streaming pipeline:

1. **Upload a test video**:
   ```bash
   aws s3 cp test-video.mp4 s3://[SOURCE_BUCKET_NAME]/
   ```

2. **Monitor processing**:
   ```bash
   # Check Lambda logs
   aws logs tail /aws/lambda/[LAMBDA_FUNCTION_NAME] --follow
   
   # Check MediaConvert jobs
   aws mediaconvert list-jobs --region [REGION] --endpoint-url [MEDIACONVERT_ENDPOINT]
   ```

3. **Verify outputs**:
   ```bash
   # Check HLS outputs
   aws s3 ls s3://[OUTPUT_BUCKET_NAME]/hls/ --recursive
   
   # Check DASH outputs
   aws s3 ls s3://[OUTPUT_BUCKET_NAME]/dash/ --recursive
   ```

4. **Test streaming**:
   - Access the generated test player at the CloudFront domain
   - Load HLS manifest: `https://[CLOUDFRONT_DOMAIN]/hls/[video-name]/index.m3u8`
   - Load DASH manifest: `https://[CLOUDFRONT_DOMAIN]/dash/[video-name]/index.mpd`

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor these key metrics:

- **Lambda**: Invocations, Duration, Errors
- **MediaConvert**: JobsCompleted, JobsErrored, OutputDurationMilliseconds
- **S3**: BucketRequests, BucketSizeBytes
- **CloudFront**: Requests, BytesDownloaded, OriginLatency

### Common Issues

1. **MediaConvert Job Failures**:
   - Check source video format compatibility
   - Verify IAM role permissions
   - Review job template configuration

2. **Lambda Timeout Errors**:
   - Increase Lambda timeout for large video files
   - Monitor MediaConvert endpoint response times

3. **CloudFront Access Issues**:
   - Verify S3 bucket policy allows CloudFront access
   - Check CORS configuration for web player access

### Log Analysis

```bash
# View Lambda logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/[LAMBDA_FUNCTION_NAME] \
    --start-time $(date -d '1 hour ago' +%s)000

# View CloudFront access logs (if enabled)
aws s3 ls s3://[CLOUDFRONT_LOGS_BUCKET]/ --recursive
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack --stack-name adaptive-streaming-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name adaptive-streaming-stack
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
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

# Confirm deletion when prompted
```

### Manual Cleanup Steps

If automated cleanup fails, manually remove:

1. **S3 Bucket Contents**:
   ```bash
   aws s3 rm s3://[SOURCE_BUCKET_NAME] --recursive
   aws s3 rm s3://[OUTPUT_BUCKET_NAME] --recursive
   ```

2. **CloudFront Distribution**:
   - Disable distribution in AWS Console
   - Wait for deployment completion
   - Delete distribution

3. **MediaConvert Jobs**:
   ```bash
   # Cancel any running jobs
   aws mediaconvert list-jobs --status PROGRESSING \
       --endpoint-url [MEDIACONVERT_ENDPOINT] \
       --query 'Jobs[].Id' --output text | \
   xargs -I {} aws mediaconvert cancel-job --id {} \
       --endpoint-url [MEDIACONVERT_ENDPOINT]
   ```

## Cost Optimization

### Estimated Costs

For a development environment with moderate usage:

- **S3 Storage**: $0.023/GB/month
- **MediaConvert**: $0.0075/minute (720p), $0.015/minute (1080p)
- **Lambda**: $0.20/1M requests + $0.0000166667/GB-second
- **CloudFront**: $0.085/GB (first 10TB/month)

### Cost Reduction Tips

1. **Use S3 Intelligent Tiering** for infrequently accessed content
2. **Configure CloudFront caching** to reduce origin requests
3. **Set up S3 lifecycle policies** to archive old content
4. **Monitor MediaConvert usage** and optimize encoding settings
5. **Use CloudFront price classes** appropriate for your audience

## Security Considerations

### Default Security Features

- **IAM Roles**: Least privilege access for all services
- **S3 Bucket Policies**: Restrict access to necessary operations
- **CloudFront**: HTTPS-only distribution with security headers
- **Lambda**: VPC isolation available through configuration
- **Encryption**: S3 server-side encryption enabled by default

### Additional Security Enhancements

1. **Enable CloudTrail** for API logging
2. **Configure S3 access logging** for audit trails
3. **Implement signed URLs** for content protection
4. **Enable AWS Config** for compliance monitoring
5. **Set up GuardDuty** for threat detection

## Performance Optimization

### MediaConvert Settings

- **QVBR encoding**: Optimizes quality per bitrate
- **Scene change detection**: Improves compression efficiency
- **Proper GOP settings**: Ensures smooth quality switching

### CloudFront Configuration

- **Optimized caching**: Different TTLs for manifests vs. segments
- **Compression**: Disabled for video content to avoid processing overhead
- **HTTP/2 support**: Enabled for improved performance

### Monitoring Performance

```bash
# CloudWatch custom metrics for video processing
aws cloudwatch put-metric-data \
    --namespace "AdaptiveStreaming" \
    --metric-data MetricName=ProcessingTime,Value=180,Unit=Seconds
```

## Advanced Features

### Multi-Region Deployment

Extend the infrastructure for multi-region availability:

1. Deploy stacks in multiple regions
2. Configure Route 53 for geo-routing
3. Set up cross-region S3 replication
4. Implement Lambda@Edge for request routing

### Content Protection

Add DRM and content protection:

1. Integrate AWS Elemental MediaPackage
2. Configure SPEKE for key management
3. Implement token-based authentication
4. Add watermarking capabilities

## Support and Documentation

- **AWS MediaConvert**: [Developer Guide](https://docs.aws.amazon.com/mediaconvert/)
- **CloudFront Streaming**: [User Guide](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/live-streaming.html)
- **Lambda Best Practices**: [Documentation](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- **Recipe Documentation**: See parent directory for complete recipe guide

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation.

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new parameters
3. Ensure security best practices are maintained
4. Validate cost implications
5. Update monitoring and alerting as needed