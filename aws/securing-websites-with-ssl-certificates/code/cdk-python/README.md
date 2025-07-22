# Secure Static Website CDK Python Application

This AWS CDK Python application deploys a complete secure static website hosting solution using AWS Certificate Manager, Amazon CloudFront, and Amazon S3.

## Architecture Overview

The application creates a production-ready infrastructure for hosting static websites with enterprise-grade security:

- **Amazon S3**: Secure storage for static website content with versioning
- **AWS Certificate Manager (ACM)**: Free SSL/TLS certificates with automatic renewal
- **Amazon CloudFront**: Global CDN with HTTPS enforcement and security headers
- **Amazon Route 53**: DNS management and certificate validation
- **Origin Access Control (OAC)**: Secure access between CloudFront and S3

## Features

### 🔐 Security
- HTTPS-only access (HTTP redirects to HTTPS)
- Free SSL/TLS certificates via AWS Certificate Manager
- Automatic certificate renewal
- Origin Access Control prevents direct S3 access
- Modern TLS protocols (TLS 1.2+)
- Security headers via CloudFront
- IPv6 support

### 🌍 Performance
- Global content delivery via CloudFront CDN
- Optimized caching policies
- Compression enabled
- Edge locations worldwide

### 📊 Monitoring & Management
- CloudFront access logging
- CloudWatch integration
- Infrastructure as Code with CDK
- Automated deployments

## Prerequisites

1. **AWS Account**: Active AWS account with appropriate permissions
2. **AWS CLI**: Installed and configured
3. **Python**: 3.8 or later
4. **Node.js**: 18.x or later (for CDK CLI)
5. **Domain**: Registered domain name for SSL certificate

### Required AWS Permissions

Your AWS credentials need permissions for:
- Amazon S3 (bucket creation, policy management)
- Amazon CloudFront (distribution management)
- AWS Certificate Manager (certificate request, validation)
- Amazon Route 53 (hosted zone, DNS records)
- AWS IAM (policy creation for services)

## Installation & Setup

### 1. Install Prerequisites

```bash
# Install AWS CDK CLI globally
npm install -g aws-cdk

# Verify installation
cdk --version
```

### 2. Clone and Setup

```bash
# Navigate to the CDK application directory
cd aws/securing-static-websites-certificate-manager/code/cdk-python/

# Create Python virtual environment
python -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\\Scripts\\activate.bat

# Install Python dependencies
pip install -r requirements.txt
```

### 3. Configure Environment

```bash
# Set your domain name (replace with your actual domain)
export DOMAIN_NAME="yourdomain.com"
export SUBDOMAIN="www.yourdomain.com"

# Set AWS region (us-east-1 recommended for ACM with CloudFront)
export CDK_DEFAULT_REGION="us-east-1"
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```

### 4. Bootstrap CDK (First Time Only)

```bash
# Bootstrap CDK in your AWS account/region
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$CDK_DEFAULT_REGION
```

## Deployment

### 1. Review Infrastructure

```bash
# Generate and review CloudFormation template
cdk synth

# Check what will be deployed
cdk diff
```

### 2. Deploy Infrastructure

```bash
# Deploy the stack
cdk deploy

# Deploy with auto-approval (for automation)
cdk deploy --require-approval never
```

### 3. Post-Deployment

After deployment:

1. **DNS Setup**: If using external DNS provider, update nameservers to Route 53
2. **Certificate Validation**: Ensure ACM certificate is validated (automatic with Route 53)
3. **Content Upload**: Sample content is automatically deployed
4. **Testing**: Verify HTTPS access to your domain

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DOMAIN_NAME` | Primary domain name | `example.com` | Yes |
| `SUBDOMAIN` | Subdomain (www) | `www.${DOMAIN_NAME}` | No |
| `CDK_DEFAULT_REGION` | AWS deployment region | `us-east-1` | No |
| `CDK_DEFAULT_ACCOUNT` | AWS account ID | Auto-detected | No |

### Customization

Edit `stacks/secure_static_website_stack.py` to customize:

- **S3 Configuration**: Bucket names, versioning, encryption
- **CloudFront Settings**: Cache policies, behaviors, security headers
- **Certificate Options**: Key algorithms, transparency logging
- **DNS Configuration**: Additional records, health checks

## Usage Examples

### Custom Domain Deployment

```bash
# Deploy with custom domain
export DOMAIN_NAME="mycompany.com"
export SUBDOMAIN="www.mycompany.com"
cdk deploy
```

### Development Environment

```bash
# Deploy with development settings
export DOMAIN_NAME="dev.mycompany.com"
cdk deploy --context environment=development
```

### Content Updates

```bash
# Redeploy to update website content
cdk deploy --hotswap  # Faster for content-only changes
```

## Monitoring & Maintenance

### CloudWatch Logs
- CloudFront access logs: Stored in S3 bucket
- Distribution metrics: Available in CloudWatch console

### Certificate Monitoring
- ACM automatically renews certificates 60-90 days before expiry
- CloudWatch alarms can monitor certificate expiry dates

### Cost Optimization
- CloudFront: Pay-per-use with free tier
- S3: Storage and request charges
- ACM: Free certificates
- Route 53: Hosted zone charges

## Troubleshooting

### Common Issues

1. **Certificate Validation Fails**
   ```bash
   # Check Route 53 records
   aws route53 list-resource-record-sets --hosted-zone-id YOUR_ZONE_ID
   
   # Verify certificate status
   aws acm describe-certificate --certificate-arn YOUR_CERT_ARN --region us-east-1
   ```

2. **CloudFront Distribution Access Denied**
   ```bash
   # Check S3 bucket policy
   aws s3api get-bucket-policy --bucket YOUR_BUCKET_NAME
   
   # Verify OAC configuration
   aws cloudfront get-origin-access-control --id YOUR_OAC_ID
   ```

3. **DNS Resolution Issues**
   ```bash
   # Test DNS propagation
   nslookup yourdomain.com
   dig yourdomain.com
   ```

### Debug Mode

```bash
# Enable CDK debug logging
cdk deploy --debug

# Verbose output
cdk deploy --verbose
```

## Security Best Practices

### Implemented
- ✅ HTTPS enforcement
- ✅ Modern TLS protocols only
- ✅ Origin Access Control
- ✅ Security headers
- ✅ Automatic certificate renewal
- ✅ Access logging enabled

### Additional Recommendations
- Enable AWS WAF for additional protection
- Implement CloudTrail for API logging
- Use AWS Config for compliance monitoring
- Enable GuardDuty for threat detection

## Cleanup

### Remove All Resources

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion
cdk destroy --force
```

### Manual Cleanup (if needed)

1. **S3 Buckets**: May need manual deletion if not empty
2. **Route 53 Records**: Verify DNS records are removed
3. **CloudWatch Logs**: May persist after stack deletion

## Development

### Project Structure

```
cdk-python/
├── app.py                          # CDK application entry point
├── cdk.json                        # CDK configuration
├── requirements.txt                # Python dependencies
├── setup.py                        # Package configuration
├── README.md                       # This file
└── stacks/
    ├── __init__.py
    └── secure_static_website_stack.py  # Main stack definition
```

### Code Quality

```bash
# Format code
black .

# Lint code
flake8 .

# Type checking
mypy .

# Sort imports
isort .
```

### Testing

```bash
# Run tests
pytest

# Run tests with coverage
pytest --cov=stacks/
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Run code quality checks
6. Submit a pull request

## Resources

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/)
- [Amazon CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/latest/developerguide/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/s3/latest/userguide/)
- [Amazon Route 53 Developer Guide](https://docs.aws.amazon.com/route53/latest/developerguide/)

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](LICENSE) file for details.

## Support

For issues and questions:
- AWS CDK Issues: [GitHub Issues](https://github.com/aws/aws-cdk/issues)
- AWS Support: [AWS Support Center](https://console.aws.amazon.com/support/)
- AWS CDK Documentation: [CDK Developer Guide](https://docs.aws.amazon.com/cdk/)

---

**Note**: This CDK application creates AWS resources that may incur charges. Review the [AWS Pricing](https://aws.amazon.com/pricing/) for each service before deployment.