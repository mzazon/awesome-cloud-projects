# Infrastructure as Code for Video-on-Demand Platform with MediaStore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Video-on-Demand Platform with MediaStore".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Elemental MediaStore (create containers, manage policies)
  - Amazon CloudFront (create distributions, manage cache behaviors)
  - Amazon S3 (create buckets, manage objects)
  - AWS IAM (create roles and policies)
  - Amazon CloudWatch (create alarms and metrics)
- For CDK: Node.js 14+ (TypeScript) or Python 3.7+ (Python)
- For Terraform: Terraform 1.0+
- Estimated cost: $5-15 for testing resources (varies by data transfer)

> **Warning**: AWS Elemental MediaStore support will end on November 13, 2025. Consider migrating to S3 with CloudFront for new implementations.

## Architecture Overview

This infrastructure deploys:
- AWS Elemental MediaStore container for optimized video storage
- Amazon CloudFront distribution for global content delivery
- S3 staging bucket for content upload
- IAM roles for secure access management
- CloudWatch monitoring and alarms
- CORS and security policies for web access

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name vod-platform-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-vod-platform \
    --capabilities CAPABILITY_IAM
```

Monitor deployment progress:
```bash
aws cloudformation describe-stacks \
    --stack-name vod-platform-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
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

## Configuration Options

### CloudFormation Parameters
- `ProjectName`: Name prefix for all resources (default: vod-platform)
- `Environment`: Environment tag (default: dev)
- `PriceClass`: CloudFront price class (default: PriceClass_100)

### CDK Configuration
Edit the configuration section in the main CDK file to customize:
- Container naming conventions
- CloudFront cache behaviors
- Monitoring settings
- Lifecycle policies

### Terraform Variables
Customize deployment by modifying `terraform/variables.tf`:
- `project_name`: Resource naming prefix
- `aws_region`: Target AWS region
- `cloudfront_price_class`: CloudFront pricing tier
- `enable_monitoring`: Enable CloudWatch monitoring

## Deployment Outputs

After successful deployment, you'll receive:
- **MediaStore Container Endpoint**: HTTPS endpoint for video content
- **CloudFront Distribution Domain**: Global CDN endpoint
- **S3 Staging Bucket**: Bucket for content upload
- **IAM Role ARN**: Role for programmatic access

## Testing Your Deployment

1. **Upload test content**:
   ```bash
   # Using AWS CLI
   aws mediastore-data put-object \
       --endpoint-url https://YOUR_MEDIASTORE_ENDPOINT \
       --body test-video.mp4 \
       --path /videos/test-video.mp4 \
       --content-type video/mp4
   ```

2. **Test CloudFront delivery**:
   ```bash
   curl -I https://YOUR_CLOUDFRONT_DOMAIN/videos/test-video.mp4
   ```

3. **Verify monitoring**:
   ```bash
   aws cloudwatch get-metric-statistics \
       --namespace AWS/MediaStore \
       --metric-name RequestCount \
       --start-time 2024-01-01T00:00:00Z \
       --end-time 2024-01-01T23:59:59Z \
       --period 3600 \
       --statistics Sum
   ```

## Security Considerations

The deployed infrastructure implements several security best practices:
- HTTPS-only access to MediaStore containers
- IAM roles with least privilege principles
- CloudFront security headers and SSL/TLS enforcement
- Container policies restricting unauthorized access
- CORS configuration for secure web player integration

## Monitoring and Metrics

The infrastructure includes:
- CloudWatch metrics for MediaStore request patterns
- CloudWatch alarms for high request rates
- CloudFront access logging capabilities
- Lifecycle policies for automated content management

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name vod-platform-stack
```

### Using CDK
```bash
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

### Adding Custom Cache Behaviors
Modify the CloudFront configuration to add specific cache behaviors for different content types:
- Video files: Long cache durations (24 hours)
- Manifest files: Short cache durations (5 minutes)
- Thumbnail images: Medium cache durations (1 hour)

### Implementing Content Protection
For premium content, consider adding:
- CloudFront signed URLs for time-limited access
- AWS WAF for additional security layers
- Custom authentication with Lambda@Edge

### Scaling Considerations
For high-traffic scenarios:
- Use CloudFront Origin Shield for additional caching layers
- Implement multiple MediaStore containers for geographic distribution
- Add auto-scaling for supporting infrastructure

## Migration to S3

Given MediaStore's end-of-support date (November 13, 2025), plan migration to:
- Amazon S3 with CloudFront for origin storage
- AWS Elemental MediaConvert for video processing
- Amazon S3 Transfer Acceleration for global uploads

## Troubleshooting

### Common Issues

1. **MediaStore Access Denied**:
   - Verify IAM permissions include MediaStore actions
   - Check container policy allows your access patterns
   - Ensure HTTPS is being used for all requests

2. **CloudFront Cache Issues**:
   - Verify origin access is configured correctly
   - Check cache behaviors for appropriate TTL settings
   - Use CloudFront invalidations to clear cached content

3. **CORS Errors**:
   - Verify CORS policy includes your web application domain
   - Check that proper headers are being forwarded
   - Ensure OPTIONS requests are handled correctly

### Debugging Commands

```bash
# Check MediaStore container status
aws mediastore describe-container --container-name YOUR_CONTAINER_NAME

# View CloudFront distribution details
aws cloudfront get-distribution --id YOUR_DISTRIBUTION_ID

# Test MediaStore connectivity
aws mediastore-data list-items --endpoint-url YOUR_MEDIASTORE_ENDPOINT
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation for MediaStore and CloudFront
3. Verify your AWS permissions and quotas
4. Consider migrating to S3-based solutions for long-term sustainability

## Additional Resources

- [AWS Elemental MediaStore Developer Guide](https://docs.aws.amazon.com/mediastore/)
- [Amazon CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest)