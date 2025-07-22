# Infrastructure as Code for Scalable Live Streaming with Elemental MediaLive

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Live Streaming with Elemental MediaLive".

## Overview

This infrastructure deploys a complete live streaming solution using AWS Elemental MediaLive, MediaPackage, CloudFront, and supporting services. The solution provides scalable live video streaming with adaptive bitrate encoding, global content distribution, and comprehensive monitoring.

## Architecture Components

- **AWS Elemental MediaLive**: Live video encoding and transcoding
- **AWS Elemental MediaPackage**: Content packaging and delivery
- **Amazon CloudFront**: Global content distribution network
- **Amazon S3**: Archive storage and test player hosting
- **Amazon CloudWatch**: Monitoring and alerting
- **AWS IAM**: Service permissions and security

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - MediaLive (full access)
  - MediaPackage (full access)
  - CloudFront (full access)
  - S3 (full access)
  - IAM (role creation)
  - CloudWatch (alarms and metrics)
- Video streaming knowledge (RTMP, HLS, DASH protocols)
- Video encoder or streaming software for testing
- Network bandwidth: minimum 5 Mbps upload for HD streaming

## Cost Considerations

- **MediaLive**: $1.85-15.00/hour depending on input resolution and output bitrates
- **MediaPackage**: $0.07/GB for content packaging
- **CloudFront**: $0.085/GB for data transfer (first 10TB)
- **S3**: $0.023/GB for standard storage
- **CloudWatch**: $0.30/alarm for monitoring

**Estimated Total**: $50-200/hour for HD streaming (varies by duration and viewership)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name live-streaming-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=StreamName,ParameterValue=my-live-stream

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name live-streaming-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name live-streaming-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy stack
cdk deploy

# Get outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy stack
cdk deploy

# Get outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
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

# The script will output streaming URLs and configuration details
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION="us-east-1"
export STREAM_NAME="my-live-stream"
export ENABLE_ARCHIVING="true"
export ENABLE_MONITORING="true"
```

### Customization Options

#### CloudFormation Parameters

- `StreamName`: Name for your live stream (default: live-stream)
- `EnableArchiving`: Enable S3 archiving (default: true)
- `EnableMonitoring`: Enable CloudWatch monitoring (default: true)
- `VideoBitrates`: Comma-separated list of output bitrates (default: 6000000,3000000,1500000)

#### CDK Context Variables

```json
{
  "streamName": "my-live-stream",
  "enableArchiving": true,
  "enableMonitoring": true,
  "videoBitrates": [6000000, 3000000, 1500000]
}
```

#### Terraform Variables

```hcl
# terraform.tfvars
stream_name = "my-live-stream"
enable_archiving = true
enable_monitoring = true
video_bitrates = ["6000000", "3000000", "1500000"]
```

## Deployment Outputs

Each implementation provides these key outputs:

- **RTMPInputURL**: Primary RTMP endpoint for streaming
- **RTMPBackupInputURL**: Backup RTMP endpoint for redundancy
- **HLSPlaybackURL**: HLS streaming URL via CloudFront
- **DASHPlaybackURL**: DASH streaming URL via CloudFront
- **TestPlayerURL**: HTML5 test player URL
- **MediaLiveChannelId**: Channel ID for monitoring
- **CloudWatchDashboardURL**: Monitoring dashboard URL

## Testing Your Stream

### Using FFmpeg

```bash
# Test with a video file
ffmpeg -re -i your-video.mp4 -c copy -f flv rtmp://[INPUT_URL]/live

# Test with webcam (macOS)
ffmpeg -f avfoundation -i "0:0" -c:v libx264 -c:a aac -f flv rtmp://[INPUT_URL]/live

# Test with webcam (Linux)
ffmpeg -f v4l2 -i /dev/video0 -f alsa -i default -c:v libx264 -c:a aac -f flv rtmp://[INPUT_URL]/live
```

### Using OBS Studio

1. Open OBS Studio
2. Go to Settings → Stream
3. Select "Custom" as Service
4. Enter the RTMP URL from outputs
5. Set Stream Key to "live"
6. Click "Start Streaming"

### Playback Testing

Use the provided test player URL or test with these players:

- **VLC**: Open the HLS URL in VLC Media Player
- **Browser**: Use the HTML5 test player
- **Mobile**: Test HLS URLs in native mobile players

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor these key metrics:

- `AWS/MediaLive/ActiveOutputs`: Number of active outputs
- `AWS/MediaLive/InputVideoFrameRate`: Input video frame rate
- `AWS/MediaLive/OutputVideoFrameRate`: Output video frame rate
- `AWS/MediaLive/4xxErrors`: Client errors
- `AWS/MediaLive/5xxErrors`: Server errors

### Common Issues

1. **Channel won't start**: Check IAM permissions and input security groups
2. **Stream not appearing**: Verify RTMP URL and stream key
3. **Poor quality**: Adjust bitrate settings and check network bandwidth
4. **Buffering**: Check CloudFront distribution and origin settings

### Debugging Commands

```bash
# Check MediaLive channel status
aws medialive describe-channel --channel-id [CHANNEL_ID]

# Check MediaPackage endpoints
aws mediapackage list-origin-endpoints --channel-id [PACKAGE_CHANNEL_ID]

# Check CloudFront distribution
aws cloudfront get-distribution --id [DISTRIBUTION_ID]

# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/medialive
```

## Security Best Practices

### Network Security

- Configure input security groups to restrict RTMP access
- Use HTTPS for all playback endpoints
- Enable CloudFront security headers

### Access Control

- Use IAM roles with least privilege principle
- Enable CloudTrail for API logging
- Implement resource-based policies where appropriate

### Content Protection

For production deployments, consider:

- DRM integration with MediaPackage
- Signed URLs for restricted content
- Geographic restrictions via CloudFront
- Token-based authentication

## Scaling Considerations

### Performance Optimization

- Use multiple MediaLive inputs for redundancy
- Configure CloudFront for optimal caching
- Consider MediaPackage endpoint scaling

### Cost Optimization

- Stop MediaLive channels when not streaming
- Use S3 lifecycle policies for archive storage
- Monitor data transfer costs
- Consider regional deployment for global audiences

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name live-streaming-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name live-streaming-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
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

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup

If automated cleanup fails, manually delete resources in this order:

1. Stop and delete MediaLive channels
2. Delete MediaPackage endpoints and channels
3. Disable and delete CloudFront distributions
4. Delete S3 buckets and contents
5. Delete IAM roles and policies
6. Delete CloudWatch alarms and log groups

## Advanced Configuration

### Multi-Region Deployment

For global deployments:

1. Deploy MediaLive in multiple regions
2. Use Route 53 for DNS failover
3. Configure cross-region replication
4. Implement health checks

### High Availability

- Configure dual-input redundancy
- Use multiple availability zones
- Implement automatic failover
- Set up comprehensive monitoring

### Integration Examples

#### With AWS Lambda

```python
import boto3

def lambda_handler(event, context):
    medialive = boto3.client('medialive')
    
    # Start channel on demand
    response = medialive.start_channel(
        ChannelId='your-channel-id'
    )
    
    return {
        'statusCode': 200,
        'body': 'Channel started successfully'
    }
```

#### With Amazon EventBridge

```yaml
# CloudFormation rule for automated responses
EventBridgeRule:
  Type: AWS::Events::Rule
  Properties:
    EventPattern:
      source: ["aws.medialive"]
      detail-type: ["MediaLive Channel State Change"]
    Targets:
      - Arn: !GetAtt NotificationTopic.Arn
        Id: "MediaLiveNotification"
```

## Support and Documentation

### AWS Documentation

- [AWS Elemental MediaLive User Guide](https://docs.aws.amazon.com/medialive/)
- [AWS Elemental MediaPackage User Guide](https://docs.aws.amazon.com/mediapackage/)
- [Amazon CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/)

### Best Practices

- [Live Streaming Best Practices](https://docs.aws.amazon.com/medialive/latest/ug/best-practices.html)
- [AWS Media Services Security](https://docs.aws.amazon.com/medialive/latest/ug/security.html)
- [CloudFront Security Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/SecurityBestPractices.html)

### Community Resources

- [AWS Media Services Blog](https://aws.amazon.com/blogs/media/)
- [AWS re:Invent Sessions](https://reinvent.awsevents.com/)
- [AWS Forums](https://forums.aws.amazon.com/forum.jspa?forumID=347)

## Troubleshooting Guide

### Common Error Messages

**"Channel failed to start"**
- Check IAM role permissions
- Verify input security group configuration
- Ensure MediaPackage channel is active

**"Input not receiving video"**
- Verify RTMP URL and stream key
- Check network connectivity
- Validate encoder settings

**"Playback not working"**
- Check CloudFront distribution status
- Verify MediaPackage endpoint URLs
- Test with different players

### Performance Issues

**High latency**
- Reduce segment duration
- Optimize CloudFront settings
- Use low-latency HLS features

**Poor video quality**
- Adjust encoder bitrates
- Check input video quality
- Verify network bandwidth

### Cost Optimization

**High MediaLive costs**
- Stop channels when not streaming
- Optimize output bitrates
- Use efficient encoding settings

**High data transfer costs**
- Optimize CloudFront caching
- Use appropriate price class
- Monitor usage patterns

For additional support, refer to the original recipe documentation or contact AWS Support.