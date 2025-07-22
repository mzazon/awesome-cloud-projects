# Secure Content Delivery with CloudFront and AWS WAF - CDK TypeScript

This CDK application deploys a secure content delivery system using Amazon CloudFront and AWS WAF, providing comprehensive protection against web threats while ensuring high-performance global content delivery.

## Architecture

The application creates:

- **S3 Bucket**: Secure storage for static content with encryption and versioning
- **AWS WAF Web ACL**: Multi-layered security protection with managed rules and rate limiting
- **CloudFront Distribution**: Global content delivery network with edge security
- **Origin Access Control (OAC)**: Secure bucket access restricted to CloudFront only
- **Geographic Restrictions**: Country-based access controls

## Security Features

### AWS WAF Protection
- **Common Rule Set**: Protection against OWASP Top 10 vulnerabilities
- **Known Bad Inputs**: Blocks malicious payloads and attack patterns
- **Rate-Based Rules**: DDoS protection with configurable IP-based rate limiting
- **Geographic Restrictions**: Country-level access controls

### CloudFront Security
- **HTTPS Enforcement**: Automatic redirect from HTTP to HTTPS
- **Origin Access Control**: Prevents direct S3 bucket access
- **Edge Caching**: Reduces origin load and improves performance
- **Compression**: Automatic content compression for faster delivery

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ installed
- TypeScript installed globally (`npm install -g typescript`)
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- Appropriate AWS permissions for CloudFront, WAF, S3, and IAM

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

You can customize the deployment using CDK context parameters:

```bash
# Set custom bucket name
cdk deploy -c bucketName=my-secure-content-bucket

# Configure blocked countries (default: RU, CN)
cdk deploy -c blockedCountries='["XX","YY"]'

# Set rate limit per IP (default: 2000)
cdk deploy -c rateLimitPerIp=5000

# Set environment tag
cdk deploy -c environment=production
```

### Available Context Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `bucketName` | string | auto-generated | S3 bucket name for content storage |
| `blockedCountries` | array | `["RU","CN"]` | Countries to block access from |
| `allowedCountries` | array | `[]` | Countries to allow (if specified, blocks all others) |
| `rateLimitPerIp` | number | `2000` | Maximum requests per IP per 5-minute window |
| `environment` | string | `dev` | Environment tag for resources |

## Deployment

1. **Review the changes**:
   ```bash
   cdk diff
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Deploy with custom configuration**:
   ```bash
   cdk deploy \
     -c bucketName=my-content-bucket \
     -c environment=production \
     -c rateLimitPerIp=5000
   ```

## Testing

After deployment, test the secure content delivery:

1. **Access the content URL** (provided in stack outputs):
   ```bash
   curl -I https://[DISTRIBUTION_DOMAIN]/index.html
   ```

2. **Verify HTTPS enforcement**:
   ```bash
   curl -I http://[DISTRIBUTION_DOMAIN]/index.html
   # Should return 301 redirect to HTTPS
   ```

3. **Test direct S3 access** (should be blocked):
   ```bash
   curl -I https://[BUCKET_NAME].s3.[REGION].amazonaws.com/index.html
   # Should return 403 Forbidden
   ```

## Monitoring

The application automatically configures CloudWatch metrics for:

- WAF Web ACL metrics and sampled requests
- CloudFront distribution metrics
- Rate-based rule metrics

Access these through the AWS Console > CloudWatch > Metrics.

## Customization

### Adding Custom WAF Rules

To add custom WAF rules, modify the `webAcl.rules` array in `lib/secure-content-delivery-stack.ts`:

```typescript
{
  name: 'CustomRule',
  priority: 4,
  action: { block: {} },
  statement: {
    // Your custom rule statement
  },
  visibilityConfig: {
    sampledRequestsEnabled: true,
    cloudWatchMetricsEnabled: true,
    metricName: 'CustomRuleMetric'
  }
}
```

### Modifying Cache Behaviors

Update the `behaviors` array in the CloudFront configuration to add custom caching rules for different content types.

### Adding Multiple Origins

To serve both static (S3) and dynamic (ALB/API Gateway) content, add additional origins to the `originConfigs` array.

## Cleanup

To remove all resources:

```bash
cdk destroy
```

**Note**: The S3 bucket is configured with `autoDeleteObjects: true` for easy cleanup in development environments. For production, consider setting `removalPolicy: cdk.RemovalPolicy.RETAIN` and manually manage bucket deletion.

## Cost Optimization

- **Price Class**: Set to `PRICE_CLASS_100` (US, Canada, Europe) for cost optimization
- **Cache Settings**: Configured for optimal caching to reduce origin requests
- **Compression**: Enabled to reduce data transfer costs

For global distribution, change to `PRICE_CLASS_ALL` in the distribution configuration.

## Security Best Practices

1. **Regular Updates**: Keep WAF managed rules up to date
2. **Monitoring**: Review WAF metrics and blocked requests regularly
3. **Rate Limits**: Adjust based on your application's legitimate traffic patterns
4. **Geographic Restrictions**: Update based on your user base and threat landscape
5. **Access Logs**: Consider enabling CloudFront access logs for detailed analysis

## Troubleshooting

### Common Issues

1. **Deployment Fails with WAF Error**: Ensure you're deploying to `us-east-1` region or update WAF scope
2. **Content Not Accessible**: Wait for CloudFront distribution deployment (can take 15-20 minutes)
3. **Direct S3 Access Still Works**: Ensure bucket policy has been applied after distribution creation

### Useful Commands

```bash
# View stack outputs
cdk diff --outputs-file outputs.json

# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name SecureContentDeliveryStack

# View WAF metrics
aws wafv2 get-sampled-requests --web-acl-arn [WEB_ACL_ARN] --rule-metric-name CommonRuleSetMetric --scope CLOUDFRONT --time-window StartTime=1234567890,EndTime=1234567899 --max-items 100
```

## Support

For issues related to this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [CloudFront documentation](https://docs.aws.amazon.com/cloudfront/)
3. Consult [AWS WAF documentation](https://docs.aws.amazon.com/waf/)

## License

This project is licensed under the MIT License - see the LICENSE file for details.