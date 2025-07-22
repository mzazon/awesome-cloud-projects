# Infrastructure as Code for Web Application Security with WAF Rules

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Web Application Security with WAF Rules".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS WAF v2
  - CloudFront
  - Application Load Balancer
  - CloudWatch
  - SNS
  - IAM (for service roles)
- Existing CloudFront distribution or Application Load Balancer to protect
- Basic understanding of web application security concepts

## Quick Start

### Using CloudFormation
```bash
# Deploy the WAF infrastructure
aws cloudformation create-stack \
    --stack-name waf-security-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=CloudFrontDistributionId,ParameterValue=YOUR_DISTRIBUTION_ID \
                 ParameterKey=EmailAddress,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment status
aws cloudformation wait stack-create-complete \
    --stack-name waf-security-stack \
    --region us-east-1
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the infrastructure
cdk deploy \
    --parameters cloudFrontDistributionId=YOUR_DISTRIBUTION_ID \
    --parameters emailAddress=your-email@example.com
```

### Using CDK Python
```bash
cd cdk-python/

# Set up virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the infrastructure
cdk deploy \
    --parameters cloudFrontDistributionId=YOUR_DISTRIBUTION_ID \
    --parameters emailAddress=your-email@example.com
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
cloudfront_distribution_id = "YOUR_DISTRIBUTION_ID"
email_address = "your-email@example.com"
aws_region = "us-east-1"
environment = "production"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export CLOUDFRONT_DISTRIBUTION_ID=YOUR_DISTRIBUTION_ID
export EMAIL_ADDRESS=your-email@example.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| CloudFront Distribution ID | ID of existing CloudFront distribution to protect | `E1234567890ABC` |
| Email Address | Email for security alerts and notifications | `security@example.com` |
| AWS Region | AWS region for deployment (must be us-east-1 for CloudFront) | `us-east-1` |

### Optional Parameters

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| Environment | Environment name for resource tagging | `production` | `staging` |
| Rate Limit | Requests per IP per 5-minute window | `10000` | `5000` |
| Blocked Countries | Countries to block (comma-separated) | `CN,RU,KP` | `CN,RU` |
| Enable Bot Control | Enable AWS Managed Bot Control rules | `true` | `false` |

## Deployed Resources

This infrastructure creates the following AWS resources:

### Core WAF Resources
- **AWS WAF v2 Web ACL** with comprehensive rule sets:
  - AWS Managed Rules Common Rule Set (OWASP Top 10)
  - AWS Managed Rules Known Bad Inputs
  - AWS Managed Rules SQL Injection Protection
  - AWS Managed Bot Control Rules (optional)
- **Rate Limiting Rules** for DDoS protection
- **Geographic Blocking Rules** for country-based restrictions
- **IP Set** for custom IP blocking
- **Regex Pattern Set** for custom threat detection

### Monitoring and Alerting
- **CloudWatch Log Group** for WAF logs
- **CloudWatch Dashboard** for security monitoring
- **CloudWatch Alarms** for blocked request thresholds
- **SNS Topic** for security notifications
- **SNS Subscription** for email alerts

### Security Features
- Comprehensive logging of all security events
- Real-time monitoring and alerting
- Custom pattern matching for application-specific threats
- Automated bot detection and blocking
- Rate limiting to prevent DDoS attacks

## Testing the Deployment

### Verify WAF Configuration
```bash
# List Web ACLs
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1

# Check rule configuration
aws wafv2 get-web-acl \
    --scope CLOUDFRONT \
    --id YOUR_WEB_ACL_ID \
    --region us-east-1
```

### Test Rate Limiting
```bash
# Test with your domain (replace with actual domain)
DOMAIN="your-domain.com"

# Send multiple requests to test rate limiting
for i in {1..20}; do
    curl -s -o /dev/null -w "%{http_code} " "https://$DOMAIN/"
    sleep 0.1
done
```

### Monitor WAF Metrics
```bash
# Check blocked requests metric
aws cloudwatch get-metric-statistics \
    --namespace "AWS/WAFV2" \
    --metric-name "BlockedRequests" \
    --dimensions Name=WebACL,Value=YOUR_WEB_ACL_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1
```

## Customization

### Adjusting Rate Limits
Modify the rate limiting threshold based on your application's traffic patterns:

- **Terraform**: Update `rate_limit` variable in `terraform.tfvars`
- **CloudFormation**: Update `RateLimit` parameter
- **CDK**: Update the `rateLimit` parameter during deployment

### Adding Custom IP Blocks
To block additional IP addresses or ranges:

1. Update the IP Set configuration in your chosen IaC tool
2. Add IP addresses in CIDR notation (e.g., `192.168.1.0/24`)
3. Redeploy the infrastructure

### Modifying Geographic Restrictions
To change blocked countries:

- **Terraform**: Update `blocked_countries` variable
- **CloudFormation**: Update `BlockedCountries` parameter
- **CDK**: Update the `blockedCountries` parameter

### Custom Rule Patterns
Add application-specific threat patterns by modifying the Regex Pattern Set:

```bash
# Example patterns for common threats
"(?i)(union.*select|select.*from)"     # SQL Injection
"(?i)(<script|javascript:|onerror=)"   # XSS Attempts
"(?i)(\\.\\./)|(\\\\\\.\\.\\\\)"       # Directory Traversal
```

## Security Considerations

### Best Practices Implemented
- **Least Privilege IAM**: All resources use minimal required permissions
- **Encryption**: WAF logs are encrypted at rest in CloudWatch
- **Monitoring**: Comprehensive logging and alerting for security events
- **Geographic Filtering**: Blocks traffic from high-risk countries
- **Rate Limiting**: Prevents DDoS and brute force attacks

### Security Recommendations
1. **Regular Review**: Monitor WAF logs weekly for new attack patterns
2. **Rule Tuning**: Adjust rate limits based on legitimate traffic patterns
3. **IP Set Maintenance**: Regularly update blocked IP lists
4. **Alert Response**: Establish incident response procedures for WAF alerts
5. **Testing**: Periodically test WAF effectiveness with security scanning tools

## Troubleshooting

### Common Issues

#### WAF Not Blocking Traffic
- Verify WAF is associated with CloudFront distribution
- Check rule priorities and actions
- Confirm rules are not in "Count" mode

#### False Positives
- Review WAF logs for legitimate blocked requests
- Consider rule exceptions for specific patterns
- Adjust rate limiting thresholds

#### High Costs
- Monitor WAF request charges in AWS Cost Explorer
- Consider sampling rates for logging
- Review rule complexity and optimization

### Debugging Commands
```bash
# Check WAF association with CloudFront
aws cloudfront get-distribution \
    --id YOUR_DISTRIBUTION_ID \
    --query "Distribution.DistributionConfig.WebACLId"

# View recent WAF logs
aws logs tail /aws/wafv2/YOUR_WEB_ACL_NAME \
    --since 1h \
    --format short

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names "waf-high-blocked-requests"
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name waf-security-stack \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name waf-security-stack \
    --region us-east-1
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1
```

## Cost Estimation

### WAF Pricing (us-east-1)
- **Web ACL**: $1.00 per month
- **Rule Evaluations**: $0.60 per million requests
- **Managed Rule Groups**: $1.00-$2.00 per million requests
- **CloudWatch Logs**: $0.50 per GB ingested
- **SNS Notifications**: $0.50 per million notifications

### Example Monthly Costs
- **Small Application** (1M requests): ~$5-10
- **Medium Application** (10M requests): ~$15-25
- **Large Application** (100M requests): ~$80-150

## Support

### Documentation References
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/)
- [CloudFormation WAF Resource Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_WAFv2.html)
- [AWS CDK WAF Module](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_wafv2-readme.html)
- [Terraform AWS WAF Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)

### Getting Help
- For infrastructure code issues, refer to the original recipe documentation
- For AWS WAF questions, consult the AWS documentation
- For provider-specific issues, check the respective tool documentation

### Contributing
To improve this infrastructure code:
1. Test changes in a non-production environment
2. Validate against AWS best practices
3. Update documentation as needed
4. Submit changes following the repository guidelines