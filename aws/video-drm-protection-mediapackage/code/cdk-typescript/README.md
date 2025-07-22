# DRM-Protected Video Streaming with CDK TypeScript

This CDK TypeScript application deploys a complete DRM-protected video streaming infrastructure using AWS Elemental MediaPackage, MediaLive, and CloudFront with multi-DRM support (Widevine, PlayReady, FairPlay).

## Architecture Overview

The solution implements:

- **SPEKE Key Provider**: Lambda-based SPEKE API for DRM key management
- **MediaLive Channel**: Live video encoding with multiple quality tiers
- **MediaPackage**: Content packaging with multi-DRM encryption
- **CloudFront**: Global content delivery with geographic restrictions
- **KMS & Secrets Manager**: Secure key storage and rotation
- **Test Player**: HTML5 player for DRM validation

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ and npm 8+
- AWS CDK v2.110.0 or later
- Understanding of DRM concepts and video streaming

## Required AWS Permissions

The deployment requires permissions for:
- MediaLive (channels, inputs, security groups)
- MediaPackage (channels, origin endpoints)
- Lambda (functions, URLs, event source mappings)
- CloudFront (distributions, cache policies)
- KMS (key creation, encryption, decryption)
- Secrets Manager (secret creation and access)
- S3 (bucket creation and object management)
- IAM (role and policy management)

## Installation

1. **Clone and Install Dependencies**:
   ```bash
   cd aws/video-content-protection-drm-mediapackage/code/cdk-typescript/
   npm install
   ```

2. **Bootstrap CDK (if first time)**:
   ```bash
   npx cdk bootstrap
   ```

3. **Build the Application**:
   ```bash
   npm run build
   ```

## Deployment

### Quick Deployment

Deploy with default settings:
```bash
npx cdk deploy
```

### Custom Deployment

Deploy with custom parameters:
```bash
npx cdk deploy \
  --context stackName=MyDrmStreaming \
  --context environment=prod \
  --context region=us-west-2
```

### Available Context Parameters

- `stackName`: Stack name prefix (default: DrmProtectedVideoStreaming)
- `environment`: Environment name (default: dev)
- `region`: AWS region (default: us-east-1)
- `account`: AWS account ID (default: current account)

## Post-Deployment Configuration

### 1. Start MediaLive Channel

```bash
# Get channel ID from stack outputs
CHANNEL_ID=$(aws cloudformation describe-stacks \
  --stack-name DrmProtectedVideoStreaming-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`MediaLiveChannelId`].OutputValue' \
  --output text)

# Start the channel
aws medialive start-channel --channel-id $CHANNEL_ID
```

### 2. Configure Streaming Input

Use the MediaLive input endpoints from stack outputs to send RTMP streams:
- Primary: `rtmp://[INPUT_URL]/live`
- Backup: `rtmp://[BACKUP_URL]/live`
- Stream Key: `live`

### 3. Test DRM Protection

Access the test player using the URL from stack outputs:
```bash
# Get test player URL
aws cloudformation describe-stacks \
  --stack-name DrmProtectedVideoStreaming-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`TestPlayerUrl`].OutputValue' \
  --output text
```

## DRM Testing

### Supported DRM Systems

- **Widevine**: Android, Chrome, Edge
- **PlayReady**: Windows, Xbox, Edge
- **FairPlay**: iOS, Safari, Apple TV

### Test Streams

After starting MediaLive channel, test these protected endpoints:
- HLS: `https://[CLOUDFRONT_DOMAIN]/out/v1/index.m3u8`
- DASH: `https://[CLOUDFRONT_DOMAIN]/out/v1/index.mpd`

### Validation Steps

1. **License Acquisition**: Verify SPEKE function receives key requests
2. **Content Encryption**: Confirm segments are encrypted
3. **Geographic Blocking**: Test access from restricted regions
4. **Multi-DRM Support**: Validate across different browsers/devices

## Cost Optimization

### Resource Costs (Estimated)

- **MediaLive**: ~$100-300/hour when running
- **MediaPackage**: ~$0.065/GB + $0.020/request
- **CloudFront**: ~$0.085/GB (varies by region)
- **Lambda**: ~$0.0000002 per SPEKE request
- **KMS**: ~$1/month per key + $0.03/10K requests

### Cost Management

- Stop MediaLive channel when not streaming
- Use CloudFront cache policies to reduce origin requests
- Monitor SPEKE function invocations
- Consider regional pricing for CloudFront

## Security Considerations

### DRM Security Features

- **Key Rotation**: Automatic hourly key rotation
- **Geographic Restrictions**: China and Russia blocked by default
- **HTTPS-Only**: End-to-end encrypted delivery
- **Device Authentication**: DRM-based device validation
- **Content Encryption**: AES-128 encryption for all content

### Security Best Practices

1. **Production DRM**: Replace reference SPEKE with commercial DRM provider
2. **Certificate Management**: Use custom SSL certificates for branding
3. **Access Control**: Implement user authentication and authorization
4. **Monitoring**: Set up CloudWatch alarms for security events
5. **Compliance**: Ensure GDPR/regional compliance for user data

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor these key metrics:
- MediaLive channel state and input status
- SPEKE Lambda function errors and duration
- CloudFront cache hit ratio and error rates
- MediaPackage origin request patterns

### Common Issues

1. **License Acquisition Failures**:
   - Check SPEKE function logs
   - Verify KMS key permissions
   - Validate Secrets Manager access

2. **Playback Failures**:
   - Confirm DRM system support in client
   - Check geographic restrictions
   - Verify manifest accessibility

3. **Performance Issues**:
   - Monitor CloudFront cache hit rates
   - Check MediaLive channel health
   - Validate network connectivity

### Debug Commands

```bash
# Check MediaLive channel status
aws medialive describe-channel --channel-id $CHANNEL_ID

# View SPEKE function logs
aws logs tail /aws/lambda/DrmProtectedVideoStreaming-dev-SpekeFunction

# Test SPEKE endpoint
curl -X POST [SPEKE_URL] \
  -H "Content-Type: application/json" \
  -d '{"content_id":"test","drm_systems":[{"system_id":"edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"}]}'
```

## Development

### Project Structure

```
├── app.ts                           # CDK application entry point
├── lib/
│   └── drm-protected-video-streaming-stack.ts  # Main stack definition
├── package.json                     # Dependencies and scripts
├── tsconfig.json                    # TypeScript configuration
├── cdk.json                         # CDK configuration
└── README.md                        # This file
```

### Build and Test

```bash
# Build TypeScript
npm run build

# Run tests
npm test

# Lint code
npm run lint

# Format code
npm run format

# Watch for changes
npm run watch
```

### Customization

#### Adding New DRM Systems

1. Update SPEKE function to support additional system IDs
2. Modify MediaPackage endpoint configurations
3. Update test player with new DRM integration

#### Extending Security

1. Implement user authentication
2. Add token-based access control
3. Integrate with third-party DRM providers
4. Enhance geographic restrictions

## Production Deployment

### Pre-Production Checklist

- [ ] Replace reference SPEKE with production DRM provider
- [ ] Configure custom domain and SSL certificates
- [ ] Set up proper monitoring and alerting
- [ ] Implement user authentication and authorization
- [ ] Test across all target devices and browsers
- [ ] Validate geographic restrictions and compliance
- [ ] Configure backup and disaster recovery

### Production Recommendations

1. **High Availability**: Deploy across multiple regions
2. **Monitoring**: Implement comprehensive observability
3. **Security**: Regular security audits and penetration testing
4. **Performance**: Load testing and optimization
5. **Compliance**: Legal and regulatory compliance validation

## Cleanup

### Stop Services

```bash
# Stop MediaLive channel
aws medialive stop-channel --channel-id $CHANNEL_ID
```

### Destroy Infrastructure

```bash
# Destroy all resources
npx cdk destroy

# Confirm destruction
npx cdk destroy --force
```

### Manual Cleanup

Some resources may require manual cleanup:
- CloudFront distributions (may take time to disable)
- KMS keys (scheduled for deletion with waiting period)
- S3 buckets with versioning enabled

## Support and Resources

### AWS Documentation

- [AWS Elemental MediaPackage User Guide](https://docs.aws.amazon.com/mediapackage/)
- [AWS Elemental MediaLive User Guide](https://docs.aws.amazon.com/medialive/)
- [SPEKE API Documentation](https://docs.aws.amazon.com/mediapackage/latest/ug/what-is-speke.html)
- [CDK TypeScript Documentation](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-typescript.html)

### DRM Resources

- [Widevine Documentation](https://developers.google.com/widevine)
- [PlayReady Documentation](https://docs.microsoft.com/en-us/playready/)
- [FairPlay Streaming Documentation](https://developer.apple.com/streaming/fps/)

### Community

- [AWS CDK GitHub](https://github.com/aws/aws-cdk)
- [AWS re:Post](https://repost.aws/)
- [AWS Media Services Forum](https://forums.aws.amazon.com/forum.jspa?forumID=252)

## License

This sample code is licensed under the MIT-0 License. See the LICENSE file for details.