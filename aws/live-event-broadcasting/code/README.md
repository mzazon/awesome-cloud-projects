# Infrastructure as Code for Live Event Broadcasting with Elemental MediaConnect

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Live Event Broadcasting with Elemental MediaConnect".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a professional-grade live event broadcasting system using:

- **AWS Elemental MediaConnect**: Reliable video transport with redundant flows
- **AWS Elemental MediaLive**: Professional encoding with automatic failover
- **AWS Elemental MediaPackage**: Scalable video packaging and distribution
- **Amazon CloudWatch**: Real-time monitoring and alerting

The architecture provides redundant video paths, automatic failover capabilities, and broadcast-quality reliability for live events.

## Prerequisites

### Common Requirements
- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - MediaConnect (flow creation and management)
  - MediaLive (channel and input management)
  - MediaPackage (channel and endpoint management)
  - CloudWatch (metrics and alarms)
  - IAM (role creation and policy attachment)
- Basic understanding of video streaming protocols (RTP, RTMP, HLS)
- Access to video encoder equipment or software

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CloudFormation service permissions
- Understanding of YAML syntax

#### CDK TypeScript
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK v2 installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0 or later
- AWS provider plugin (automatically downloaded)

### Cost Considerations

**Estimated hourly costs during active streaming:**
- MediaConnect flows: ~$0.05 per hour per flow
- MediaLive channel: ~$2.00 per hour for HD encoding
- MediaPackage: ~$0.01 per hour + data transfer costs
- CloudWatch: ~$0.10 per hour for monitoring
- **Total estimated cost: $50-100 per hour** (includes data transfer and processing)

> **Warning**: These resources incur charges while active. Ensure proper cleanup when not in use.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name live-event-broadcasting \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=live-event-demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name live-event-broadcasting \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name live-event-broadcasting \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get outputs
cdk outputs
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
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will provide progress updates and final endpoints
```

## Post-Deployment Configuration

After deployment, you'll need to configure your video encoders:

### Encoder Configuration

1. **Primary Encoder Setup**:
   - Set destination to the primary flow ingest IP and port 5000
   - Configure RTP protocol with H.264 video and AAC audio
   - Set video resolution to 1280x720 at 30fps
   - Set video bitrate to 2-5 Mbps for optimal quality

2. **Backup Encoder Setup**:
   - Set destination to the backup flow ingest IP and port 5001
   - Use identical encoding settings as primary
   - Configure automatic failover switching

3. **Stream Validation**:
   - Verify both encoders are sending video to their respective flows
   - Check MediaLive channel shows both inputs as active
   - Test HLS playback URL with a video player

### Monitoring Setup

The deployment includes CloudWatch alarms for:
- MediaConnect flow connection errors
- MediaLive channel input frame rate drops
- MediaPackage endpoint errors

Configure SNS notifications for production use:

```bash
# Create SNS topic for alerts
aws sns create-topic --name live-event-alerts

# Subscribe to alerts
aws sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:123456789012:live-event-alerts \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Testing Your Deployment

### 1. Verify Resource Creation

```bash
# Check MediaConnect flows
aws mediaconnect list-flows

# Check MediaLive channel
aws medialive list-channels

# Check MediaPackage channel
aws mediapackage list-channels
```

### 2. Test Video Streaming

```bash
# Test HLS endpoint (replace with your actual endpoint)
curl -I https://your-mediapackage-endpoint.aws/live/index.m3u8

# Test with FFmpeg (if available)
ffmpeg -f lavfi -i testsrc=duration=10:size=1280x720:rate=30 \
    -c:v libx264 -b:v 2M -preset fast \
    -f rtp rtp://your-primary-ingest-ip:5000
```

### 3. Monitor Stream Health

```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/MediaConnect \
    --metric-name SourceBitRate \
    --dimensions Name=FlowName,Value=your-flow-name \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T01:00:00Z \
    --period 300 \
    --statistics Average
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name live-event-broadcasting

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name live-event-broadcasting \
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

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Configuration Parameters

Each implementation supports customization through variables:

- **Project Name**: Prefix for resource names
- **Environment**: Environment tag (dev, staging, prod)
- **AWS Region**: Deployment region
- **Availability Zones**: AZs for redundant flows
- **Video Settings**: Resolution, bitrate, frame rate
- **Monitoring Level**: Basic or detailed monitoring

### Common Customizations

1. **Multi-Region Deployment**:
   - Deploy flows in multiple regions for geographic redundancy
   - Use Route 53 for automated failover between regions

2. **Enhanced Security**:
   - Implement VPC endpoints for private connectivity
   - Add encryption at rest and in transit
   - Configure IP whitelisting for encoder access

3. **Advanced Monitoring**:
   - Add custom CloudWatch dashboards
   - Implement AWS Lambda functions for automated responses
   - Integrate with third-party monitoring systems

4. **Cost Optimization**:
   - Implement automated start/stop schedules
   - Use spot instances for non-critical components
   - Configure lifecycle policies for log retention

## Security Best Practices

This implementation follows AWS security best practices:

- **IAM Roles**: Least privilege access with service-specific roles
- **Network Security**: Proper security group configurations
- **Encryption**: Data encrypted in transit and at rest where applicable
- **Monitoring**: Comprehensive logging and alerting
- **Access Control**: IP-based access restrictions where appropriate

### Additional Security Recommendations

1. **Encoder Security**:
   - Use VPN connections for encoder traffic
   - Implement certificate-based authentication
   - Regular security updates for encoder software

2. **Content Protection**:
   - Implement DRM for premium content
   - Use signed URLs for content access
   - Configure geo-blocking if required

3. **Operational Security**:
   - Regular security audits and penetration testing
   - Incident response procedures
   - Access logging and monitoring

## Troubleshooting

### Common Issues

1. **MediaConnect Flow Connection Errors**:
   - Verify encoder IP addresses and ports
   - Check network connectivity and firewall rules
   - Validate RTP stream format and bitrate

2. **MediaLive Channel Issues**:
   - Confirm both inputs are receiving video
   - Check encoding settings match input format
   - Monitor channel state transitions

3. **MediaPackage Playback Problems**:
   - Verify HLS endpoint accessibility
   - Check segment generation and availability
   - Monitor CloudWatch metrics for errors

### Diagnostic Commands

```bash
# Check MediaConnect flow health
aws mediaconnect describe-flow --flow-arn YOUR_FLOW_ARN

# Monitor MediaLive channel state
aws medialive describe-channel --channel-id YOUR_CHANNEL_ID

# Test MediaPackage endpoint
aws mediapackage describe-origin-endpoint --id YOUR_ENDPOINT_ID

# View CloudWatch logs
aws logs describe-log-streams --log-group-name /aws/medialive/YOUR_CHANNEL
```

## Performance Optimization

### Encoding Optimization

1. **Bitrate Settings**:
   - Adjust based on content complexity
   - Use adaptive bitrate for varying network conditions
   - Monitor quality metrics regularly

2. **Latency Optimization**:
   - Minimize segment duration for lower latency
   - Use low-latency HLS settings
   - Optimize encoder buffering settings

3. **Scalability Considerations**:
   - Plan for peak concurrent viewers
   - Implement CloudFront for global distribution
   - Monitor and scale based on usage patterns

## Support and Documentation

### AWS Documentation
- [AWS Elemental MediaConnect User Guide](https://docs.aws.amazon.com/mediaconnect/)
- [AWS Elemental MediaLive User Guide](https://docs.aws.amazon.com/medialive/)
- [AWS Elemental MediaPackage User Guide](https://docs.aws.amazon.com/mediapackage/)

### Additional Resources
- [AWS Media Services Workshops](https://aws.amazon.com/media-services/resources/)
- [AWS Elemental Blog](https://aws.amazon.com/blogs/media/)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Consult the original recipe documentation
4. Contact AWS Support for service-specific issues

## License

This infrastructure code is provided as-is under the MIT License. See the original recipe documentation for complete terms and conditions.