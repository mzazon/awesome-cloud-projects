# Static Website Hosting with AWS CDK TypeScript

This CDK TypeScript application deploys a complete static website hosting solution using Amazon S3, CloudFront, and Route 53, following the architecture described in the "Building Static Website Hosting with S3, CloudFront, and Route 53" recipe.

## Architecture

The application creates:

- **S3 Bucket (www subdomain)**: Hosts the static website content
- **S3 Bucket (root domain)**: Redirects traffic to the www subdomain
- **CloudFront Distribution**: Provides global CDN with SSL/TLS termination
- **Route 53 Records**: DNS configuration for both root and www domains
- **SSL Certificate**: Automatic SSL/TLS certificate via AWS Certificate Manager

## Prerequisites

- AWS CLI installed and configured
- Node.js (version 18 or later)
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- A domain name registered and configured with Route 53
- Appropriate AWS permissions for S3, CloudFront, Route 53, and Certificate Manager

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set environment variables**:
   ```bash
   export DOMAIN_NAME="example.com"
   export HOSTED_ZONE_ID="Z1234567890123"  # Optional: if you know your hosted zone ID
   export CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"  # Optional: if you have an existing certificate
   ```

3. **Bootstrap CDK** (if not done previously):
   ```bash
   cdk bootstrap
   ```

4. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

## Configuration Options

You can configure the deployment in several ways:

### Using Environment Variables

```bash
export DOMAIN_NAME="example.com"
export HOSTED_ZONE_ID="Z1234567890123"
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:123456789012:certificate/..."
cdk deploy
```

### Using CDK Context

```bash
cdk deploy -c domainName=example.com -c hostedZoneId=Z1234567890123
```

### Using cdk.json

Add to the `context` section in `cdk.json`:

```json
{
  "context": {
    "domainName": "example.com",
    "hostedZoneId": "Z1234567890123",
    "certificateArn": "arn:aws:acm:us-east-1:123456789012:certificate/..."
  }
}
```

## Website Content

The application includes sample website content in the `website/` directory:

- `index.html`: Main homepage with responsive design
- `error.html`: Custom 404 error page

To customize your website:

1. Replace the files in the `website/` directory with your own content
2. Redeploy with `cdk deploy`

The deployment automatically handles:
- Uploading content to S3
- Invalidating CloudFront cache
- Configuring proper MIME types

## SSL Certificate Management

The application can handle SSL certificates in two ways:

1. **Automatic Certificate Creation** (default):
   - Creates a new certificate with DNS validation
   - Covers both root domain and www subdomain
   - Automatically validated using Route 53 DNS records

2. **Use Existing Certificate**:
   - Set `CERTIFICATE_ARN` environment variable
   - Certificate must be in us-east-1 region for CloudFront
   - Must cover both root domain and www subdomain

## Commands

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and compile
- `npm run test`: Run the Jest unit tests
- `cdk deploy`: Deploy the stack to AWS
- `cdk diff`: Compare deployed stack with current state
- `cdk synth`: Emit the synthesized CloudFormation template
- `cdk destroy`: Remove the stack from AWS

## Project Structure

```
├── app.ts                 # CDK application entry point
├── lib/
│   └── static-website-stack.ts  # Main stack definition
├── website/               # Website content directory
│   ├── index.html        # Homepage
│   └── error.html        # 404 error page
├── package.json          # Node.js dependencies
├── tsconfig.json         # TypeScript configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

## Customization

### Adding Custom Domain Logic

To modify domain handling, edit the `StaticWebsiteStack` class in `lib/static-website-stack.ts`:

```typescript
// Example: Add additional subdomains
const additionalDomains = [`blog.${domainName}`, `api.${domainName}`];
```

### Custom CloudFront Behaviors

Add custom behaviors for different content types:

```typescript
// Example: Add API behavior
const distribution = new cloudfront.Distribution(this, 'WebsiteDistribution', {
  // ... existing configuration
  additionalBehaviors: {
    '/api/*': {
      origin: new origins.HttpOrigin('api.example.com'),
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
    },
  },
});
```

### Security Headers

Add security headers using Lambda@Edge or CloudFront Functions:

```typescript
// Example: Add security headers
const securityHeadersFunction = new cloudfront.Function(this, 'SecurityHeaders', {
  code: cloudfront.FunctionCode.fromInline(`
    function handler(event) {
      var response = event.response;
      response.headers['strict-transport-security'] = {value: 'max-age=31536000'};
      response.headers['x-content-type-options'] = {value: 'nosniff'};
      response.headers['x-frame-options'] = {value: 'DENY'};
      return response;
    }
  `),
});
```

## Cost Optimization

- **S3 Storage**: Pay only for storage used (typically $0.023/GB/month)
- **CloudFront**: First 1TB/month free, then $0.085/GB
- **Route 53**: $0.50/hosted zone/month + $0.40/million queries
- **Certificate Manager**: Free for CloudFront certificates

Estimated monthly cost for a small website: $0.50 - $2.00

## Security Best Practices

The application implements several security best practices:

1. **HTTPS Enforcement**: All traffic redirected to HTTPS
2. **S3 Public Access**: Minimal public access configuration
3. **CloudFront Security**: Security headers and DDoS protection
4. **IAM Least Privilege**: Minimal required permissions
5. **Certificate Management**: Automatic certificate renewal

## Troubleshooting

### Common Issues

1. **Certificate Validation Fails**:
   - Ensure your domain is configured in Route 53
   - Check DNS propagation with `dig` or `nslookup`
   - Certificate must be in us-east-1 region

2. **CloudFront Distribution Takes Too Long**:
   - Initial deployment takes 10-15 minutes
   - Subsequent updates are faster
   - Check AWS CloudFormation console for progress

3. **Website Not Loading**:
   - Verify DNS records in Route 53
   - Check CloudFront distribution status
   - Ensure S3 bucket has public read access

4. **SSL Certificate Errors**:
   - Verify certificate covers both root and www domains
   - Check certificate status in Certificate Manager
   - Ensure certificate is in us-east-1 region

### Useful Commands for Debugging

```bash
# Check DNS resolution
nslookup your-domain.com

# Test SSL certificate
openssl s_client -connect your-domain.com:443 -servername your-domain.com

# Check CloudFront distribution
aws cloudfront list-distributions

# Check Route 53 hosted zone
aws route53 list-hosted-zones
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will:
- Delete the CloudFront distributions
- Remove the S3 buckets and their contents
- Delete the Route 53 records
- Remove the SSL certificate (if created by this stack)

**Note**: The hosted zone itself is not deleted and will continue to incur charges.

## Support

For issues related to this CDK application:

1. Check the AWS CDK documentation: https://docs.aws.amazon.com/cdk/
2. Review the original recipe documentation
3. Check AWS service-specific documentation for S3, CloudFront, and Route 53

## License

This project is licensed under the MIT License.