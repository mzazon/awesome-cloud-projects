# AWS CDK Python - WAF Rate Limiting Solution

This CDK Python application deploys a comprehensive AWS Web Application Firewall (WAF) solution with rate limiting rules, IP reputation filtering, and comprehensive monitoring capabilities.

## Architecture Overview

The solution deploys:

- **AWS WAF Web ACL** with CloudFront scope for global edge protection
- **Rate Limiting Rule** to prevent DDoS attacks (default: 2000 requests per 5 minutes per IP)
- **IP Reputation Rule** using AWS managed rule groups for threat intelligence
- **CloudWatch Logging** for security audit trails and compliance
- **CloudWatch Dashboard** for real-time security monitoring
- **CloudWatch Alarms** for automated security alerting

## Features

### Security Protection
- **Rate Limiting**: Automatically blocks IP addresses exceeding request thresholds
- **IP Reputation Filtering**: Leverages AWS threat intelligence to block known malicious IPs
- **Edge Protection**: Deploys at CloudFront for global protection and performance
- **Comprehensive Logging**: Detailed request logging for security analysis

### Monitoring & Observability
- **Real-time Dashboard**: Visual monitoring of security events and metrics
- **Security Alarms**: Automated alerting for potential attacks
- **Request Analytics**: Detailed analysis of allowed vs blocked traffic
- **Rule Performance**: Individual rule effectiveness monitoring

### Enterprise Features
- **Configurable Rate Limits**: Customizable request thresholds per environment
- **Log Retention Policies**: Configurable log retention for compliance requirements
- **Multi-Environment Support**: Environment-specific configurations
- **Cost Optimization**: Efficient resource tagging and lifecycle management

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8 or later
- Node.js 14.x or later (for CDK CLI)
- AWS CDK v2.100.0 or later
- Appropriate AWS permissions for WAF, CloudWatch, and Logs

### Required AWS Permissions

Your AWS credentials must have permissions for:
- `wafv2:*` - WAF management
- `cloudwatch:*` - Metrics and dashboards
- `logs:*` - CloudWatch Logs
- `iam:PassRole` - Service roles
- `cloudformation:*` - Stack deployment

## Quick Start

### 1. Installation

```bash
# Clone the repository
git clone <repository-url>
cd cdk-python

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Install CDK CLI globally
npm install -g aws-cdk

# Verify installation
cdk --version
```

### 2. Configuration

#### Environment Variables
```bash
# Required
export AWS_REGION=us-east-1
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Optional configuration
export RATE_LIMIT=2000                    # Requests per 5 minutes per IP
export LOG_RETENTION_DAYS=30              # CloudWatch log retention
export ENVIRONMENT=development            # Environment tag
```

#### CDK Context (Alternative Configuration)
```bash
# Set context values (alternative to environment variables)
cdk deploy --context rateLimit=5000 --context environment=production
```

### 3. Deployment

```bash
# Bootstrap CDK (first time only)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# Deploy with confirmation
cdk deploy --require-approval never
```

### 4. Verification

After deployment, verify the resources:

```bash
# Check Web ACL
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1

# View CloudWatch dashboard
# URL provided in stack outputs

# Check WAF logs
aws logs describe-log-groups --log-group-name-prefix "/aws/wafv2"
```

## Configuration Options

### Rate Limiting Configuration

```python
# In app.py or via context
rate_limit = 2000  # Requests per 5 minutes per IP

# Environment-specific limits
production_rate_limit = 5000
development_rate_limit = 1000
```

### Log Retention Configuration

```python
# Log retention options (days)
log_retention_options = {
    "development": 7,
    "staging": 30,
    "production": 90
}
```

### Custom Rule Configuration

To add custom rules, modify the `_create_web_acl` method in `app.py`:

```python
# Example: Geographic blocking rule
geo_blocking_rule = wafv2.CfnWebACL.RuleProperty(
    name="GeoBlockingRule",
    priority=3,
    statement=wafv2.CfnWebACL.StatementProperty(
        geo_match_statement=wafv2.CfnWebACL.GeoMatchStatementProperty(
            country_codes=["CN", "RU"]  # Block specific countries
        )
    ),
    action=wafv2.CfnWebACL.RuleActionProperty(block={}),
    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
        sampled_requests_enabled=True,
        cloud_watch_metrics_enabled=True,
        metric_name="GeoBlockingRule"
    )
)
```

## Associating with CloudFront

To protect a CloudFront distribution, associate the Web ACL:

```bash
# Get the Web ACL ARN from stack outputs
WEB_ACL_ARN=$(aws cloudformation describe-stacks \
    --stack-name WafRateLimitingStack-development \
    --query 'Stacks[0].Outputs[?OutputKey==`WebAclArn`].OutputValue' \
    --output text)

# Update CloudFront distribution configuration
aws cloudfront update-distribution \
    --id YOUR_DISTRIBUTION_ID \
    --distribution-config file://distribution-config.json
```

Example distribution configuration snippet:
```json
{
  "DistributionConfig": {
    "WebACLId": "arn:aws:wafv2:us-east-1:123456789012:global/webacl/..."
  }
}
```

## Monitoring and Alerting

### CloudWatch Dashboard

Access the dashboard via the URL in stack outputs:
- **Allowed vs Blocked Requests**: Overall traffic patterns
- **Blocked Requests by Rule**: Rule-specific blocking activity
- **Rate Limiting Activity**: Real-time rate limiting events

### CloudWatch Alarms

The solution creates two types of alarms:

1. **High Blocked Requests Alarm**
   - Threshold: 1000 blocked requests in 10 minutes
   - Indicates potential attack activity

2. **Rate Limit Activation Alarm**
   - Threshold: Any rate limiting activation
   - Immediate notification of rate limiting events

### Log Analysis

Query WAF logs using CloudWatch Logs Insights:

```sql
-- Top blocked IP addresses
fields @timestamp, httpRequest.clientIp, action
| filter action = "BLOCK"
| stats count() as blocked_requests by httpRequest.clientIp
| sort blocked_requests desc
| limit 10

-- Rate limiting events
fields @timestamp, httpRequest.clientIp, terminatingRuleId
| filter terminatingRuleId = "RateLimitRule"
| stats count() as rate_limit_blocks by httpRequest.clientIp
| sort rate_limit_blocks desc
```

## Testing the Solution

### Rate Limiting Test

```bash
# Test rate limiting (replace with your application URL)
APPLICATION_URL="https://your-app.example.com"

# Generate rapid requests to trigger rate limiting
for i in {1..100}; do
  curl -s -o /dev/null -w "%{http_code}\n" $APPLICATION_URL &
done
wait

# Check for HTTP 403 responses indicating rate limiting
```

### Monitoring Test Traffic

```bash
# Monitor real-time logs
aws logs tail /aws/wafv2/security-logs --follow

# Check metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/WAFV2 \
    --metric-name BlockedRequests \
    --dimensions Name=WebACL,Value=YOUR_WEB_ACL_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Security Best Practices

### 1. Principle of Least Privilege
- Use specific IAM policies for deployment
- Limit Web ACL associations to necessary resources

### 2. Log Security
- Enable log encryption at rest
- Implement log retention policies
- Monitor log access patterns

### 3. Rate Limit Tuning
- Start with conservative limits
- Monitor false positives
- Adjust based on legitimate traffic patterns

### 4. Regular Reviews
- Review blocked traffic patterns monthly
- Update IP reputation rules
- Analyze attack trends

## Troubleshooting

### Common Issues

#### 1. CDK Bootstrap Issues
```bash
# Re-bootstrap if needed
cdk bootstrap --force
```

#### 2. Permission Errors
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check required permissions
aws iam simulate-principal-policy \
    --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
    --action-names wafv2:CreateWebACL
```

#### 3. Rate Limit Too Restrictive
```bash
# Update rate limit
cdk deploy --context rateLimit=5000
```

#### 4. Web ACL Association Issues
- Ensure Web ACL scope is "CLOUDFRONT" for CloudFront distributions
- Verify region is us-east-1 for CloudFront associations

### Debugging

Enable debug logging:
```bash
# CDK debug output
cdk deploy --debug

# Python logging
export CDK_DEBUG=true
```

## Cost Optimization

### Resource Costs
- **Web ACL**: $1.00/month
- **Rules**: $0.60/month per rule (2 rules = $1.20/month)
- **Requests**: $0.60 per million web requests
- **CloudWatch Logs**: ~$0.50/GB ingested + storage costs
- **CloudWatch Dashboards**: $3.00/month per dashboard

### Cost Reduction Tips
1. **Optimize Log Retention**: Reduce retention period for non-production
2. **Filter Logs**: Use redacted fields to reduce log volume
3. **Monitor Metrics**: Use CloudWatch metrics for trends vs detailed logs
4. **Environment Separation**: Use different configurations per environment

## Cleanup

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
cdk destroy --force

# Clean up CDK assets (optional)
aws s3 rm s3://cdktoolkit-stagingbucket-* --recursive
aws cloudformation delete-stack --stack-name CDKToolkit
```

## Advanced Configuration

### Custom Stack Names
```bash
# Deploy with custom stack name
cdk deploy --stack-name MyCustomWafStack
```

### Multiple Environments
```bash
# Deploy to multiple environments
cdk deploy WafRateLimitingStack-development --context environment=development
cdk deploy WafRateLimitingStack-production --context environment=production
```

### CI/CD Integration
```yaml
# GitHub Actions example
- name: Deploy WAF Stack
  run: |
    npm install -g aws-cdk
    pip install -r requirements.txt
    cdk deploy --require-approval never
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    RATE_LIMIT: 5000
    ENVIRONMENT: production
```

## Support and Contribution

### Getting Help
- Check AWS WAF documentation
- Review CloudWatch logs for error details
- Use AWS Support for service-specific issues

### Contributing
1. Fork the repository
2. Create a feature branch
3. Follow coding standards (black, flake8, mypy)
4. Add comprehensive tests
5. Submit a pull request

### Development Setup
```bash
# Install development dependencies
pip install -e ".[dev]"

# Run code quality checks
black .
flake8 .
mypy --ignore-missing-imports .

# Run tests
pytest tests/ -v --cov=.
```

---

For more information about AWS WAF and CDK, see:
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)