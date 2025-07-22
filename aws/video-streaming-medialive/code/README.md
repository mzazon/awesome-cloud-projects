# Infrastructure as Code for Live Video Streaming Platform with MediaLive

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Live Video Streaming Platform with MediaLive".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a comprehensive video streaming platform consisting of:

- **AWS Elemental MediaLive**: Live video ingestion and transcoding with adaptive bitrate outputs
- **AWS Elemental MediaPackage**: Content packaging and origin services with DRM support
- **Amazon CloudFront**: Global content delivery network with optimized caching
- **Amazon S3**: Content storage and archiving with lifecycle management
- **AWS Secrets Manager**: DRM key management and security
- **Amazon CloudWatch**: Monitoring, metrics, and alerting
- **IAM Roles**: Service permissions and security policies

## Prerequisites

### AWS Account Requirements
- AWS account with appropriate permissions for MediaLive, MediaPackage, CloudFront, S3, and IAM
- AWS CLI v2 installed and configured (or AWS CloudShell)
- Understanding of video streaming protocols (RTMP, HLS, DASH, CMAF)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions
- IAM permissions to create service roles and policies

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI v2 (`npm install -g aws-cdk`)
- TypeScript compiler (`npm install -g typescript`)

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI v2 (`pip install aws-cdk`)
- Virtual environment (recommended)

#### Terraform
- Terraform 1.0 or later
- AWS provider plugin (automatically downloaded)
- Terraform CLI with state management setup

#### Bash Scripts
- Bash 4.0 or later
- jq for JSON parsing
- openssl for key generation
- curl for endpoint testing

### Cost Considerations
- **Estimated cost**: $200-500/hour for HD streaming platform (varies by scale and features)
- MediaLive channel: ~$100/hour for HD encoding
- MediaPackage: $0.02/GB egress + requests
- CloudFront: $0.085/GB + requests (varies by region)
- S3 storage: $0.023/GB/month + requests

> **Warning**: This creates a production-grade streaming platform with significant operating costs. Always monitor usage and implement proper resource management.

## Quick Start

### Using CloudFormation

```bash
# Validate the template
aws cloudformation validate-template \
    --template-body file://cloudformation.yaml

# Create the stack
aws cloudformation create-stack \
    --stack-name video-streaming-platform \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PlatformName,ParameterValue=my-streaming-platform \
    --capabilities CAPABILITY_IAM \
    --tags Key=Environment,Value=Production Key=Service,Value=StreamingPlatform

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name video-streaming-platform \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name video-streaming-platform \
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
cdk deploy VideoStreamingPlatformStack \
    --parameters platformName=my-streaming-platform

# View stack outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy VideoStreamingPlatformStack \
    --parameters platformName=my-streaming-platform

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="platform_name=my-streaming-platform" \
    -var="aws_region=us-east-1"

# Apply the configuration
terraform apply \
    -var="platform_name=my-streaming-platform" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PLATFORM_NAME="my-streaming-platform"
export AWS_REGION="us-east-1"

# Deploy the platform
./scripts/deploy.sh

# View deployment summary
cat deployment-summary.txt
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| PlatformName | Unique name for the streaming platform | - | Yes |
| Environment | Deployment environment | Production | No |
| EnableDRM | Enable DRM protection capabilities | true | No |
| EnableLowLatency | Enable low-latency CMAF streaming | true | No |
| ArchiveRetentionDays | S3 archive retention period | 30 | No |

### CDK Context Variables

```json
{
  "platformName": "my-streaming-platform",
  "environment": "production",
  "enableDRM": true,
  "enableLowLatency": true,
  "archiveRetentionDays": 30
}
```

### Terraform Variables

```hcl
# terraform.tfvars
platform_name = "my-streaming-platform"
aws_region = "us-east-1"
environment = "production"
enable_drm = true
enable_low_latency = true
archive_retention_days = 30

# Optional: Restrict RTMP input access
allowed_cidr_blocks = ["0.0.0.0/0"]  # Change to specific IPs for security
```

## Post-Deployment Configuration

### 1. Start the MediaLive Channel

```bash
# Get the channel ID from stack outputs
CHANNEL_ID=$(aws cloudformation describe-stacks \
    --stack-name video-streaming-platform \
    --query 'Stacks[0].Outputs[?OutputKey==`MediaLiveChannelId`].OutputValue' \
    --output text)

# Start the channel
aws medialive start-channel --channel-id ${CHANNEL_ID}

# Wait for channel to be running
aws medialive wait channel-running --channel-id ${CHANNEL_ID}
```

### 2. Configure Streaming Inputs

```bash
# Get RTMP input URLs from stack outputs
PRIMARY_RTMP=$(aws cloudformation describe-stacks \
    --stack-name video-streaming-platform \
    --query 'Stacks[0].Outputs[?OutputKey==`PrimaryRTMPEndpoint`].OutputValue' \
    --output text)

BACKUP_RTMP=$(aws cloudformation describe-stacks \
    --stack-name video-streaming-platform \
    --query 'Stacks[0].Outputs[?OutputKey==`BackupRTMPEndpoint`].OutputValue' \
    --output text)

echo "Primary RTMP: ${PRIMARY_RTMP}/live"
echo "Backup RTMP: ${BACKUP_RTMP}/live"
```

### 3. Test Streaming

```bash
# Get playback URLs
HLS_URL=$(aws cloudformation describe-stacks \
    --stack-name video-streaming-platform \
    --query 'Stacks[0].Outputs[?OutputKey==`HLSPlaybackURL`].OutputValue' \
    --output text)

DASH_URL=$(aws cloudformation describe-stacks \
    --stack-name video-streaming-platform \
    --query 'Stacks[0].Outputs[?OutputKey==`DASHPlaybackURL`].OutputValue' \
    --output text)

# Test with curl
curl -I "${HLS_URL}"
curl -I "${DASH_URL}"
```

## Monitoring and Operations

### CloudWatch Metrics

The platform automatically creates CloudWatch alarms for:
- MediaLive input loss detection
- MediaPackage egress errors
- CloudFront error rates

### Access Logs

- CloudFront access logs: Stored in S3 bucket with prefix `cloudfront-logs/`
- MediaLive logs: Available in CloudWatch Logs
- S3 access logs: Configured for audit trail

### Cost Monitoring

Set up billing alerts for:
- MediaLive encoding costs
- MediaPackage egress charges
- CloudFront data transfer
- S3 storage and requests

## Troubleshooting

### Common Issues

1. **Channel fails to start**:
   ```bash
   # Check channel state
   aws medialive describe-channel --channel-id ${CHANNEL_ID} \
       --query '{State:State,StateDetails:StateDetails}'
   ```

2. **No video in outputs**:
   ```bash
   # Check input status
   aws medialive describe-channel --channel-id ${CHANNEL_ID} \
       --query 'InputAttachments[*].{Id:InputId,State:InputSettings}'
   ```

3. **High latency**:
   - Switch to CMAF low-latency endpoint
   - Check network conditions between source and AWS
   - Verify encoding settings

4. **DRM issues**:
   ```bash
   # Check secrets manager key
   aws secretsmanager describe-secret \
       --secret-id $(aws cloudformation describe-stacks \
           --stack-name video-streaming-platform \
           --query 'Stacks[0].Outputs[?OutputKey==`DRMKeyArn`].OutputValue' \
           --output text)
   ```

## Security Considerations

### Network Security
- Input security groups restrict RTMP access by IP
- CloudFront enforces HTTPS for all playback
- S3 bucket blocks public access by default

### Content Protection
- DRM keys stored in AWS Secrets Manager
- MediaPackage supports multiple DRM systems
- Content signing available for premium content

### Access Control
- IAM roles follow least privilege principle
- Service-linked roles for AWS services
- CloudTrail logging for audit compliance

## Cleanup

### Using CloudFormation

```bash
# Stop MediaLive channel first
aws medialive stop-channel --channel-id ${CHANNEL_ID}
aws medialive wait channel-stopped --channel-id ${CHANNEL_ID}

# Delete the stack
aws cloudformation delete-stack \
    --stack-name video-streaming-platform

# Monitor deletion
aws cloudformation wait stack-delete-complete \
    --stack-name video-streaming-platform
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy VideoStreamingPlatformStack

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="platform_name=my-streaming-platform" \
    -var="aws_region=us-east-1"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

### Manual Cleanup Steps

Some resources may require manual cleanup:

1. **CloudFront Distribution**: Must be disabled before deletion
2. **S3 Objects**: Delete all objects before bucket deletion
3. **CloudWatch Logs**: May retain logs beyond stack deletion
4. **Secrets Manager**: Secrets have recovery period unless force-deleted

## Customization

### Encoding Settings

Modify encoding parameters in the IaC templates:
- Video bitrates and resolutions
- Audio codec settings
- GOP structure and frame rates
- B-frame configuration

### Streaming Protocols

Enable/disable streaming formats:
- HLS for broad compatibility
- DASH for advanced features
- CMAF for low latency
- Additional audio renditions

### Geographic Distribution

Configure CloudFront edge locations:
- Price class selection
- Geographic restrictions
- Custom SSL certificates

### Content Archiving

Customize S3 storage policies:
- Lifecycle transitions
- Retention periods
- Archive formats

## Performance Optimization

### MediaLive Optimization
- Use appropriate input specifications
- Configure proper GOP settings
- Enable adaptive quantization
- Optimize bitrate ladders

### MediaPackage Optimization
- Adjust segment durations
- Configure start-over windows
- Optimize manifest settings
- Enable just-in-time packaging

### CloudFront Optimization
- Configure appropriate cache behaviors
- Use origin request policies
- Enable compression
- Optimize TTL settings

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation
3. Verify IAM permissions
4. Monitor CloudWatch logs
5. Contact AWS Support for service-specific issues

## License

This infrastructure code is provided as part of the AWS recipes collection. Refer to the main repository license for usage terms.