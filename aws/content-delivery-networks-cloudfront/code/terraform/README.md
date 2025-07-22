# Advanced CloudFront CDN - Terraform Infrastructure

This Terraform configuration deploys a comprehensive CloudFront Content Delivery Network (CDN) with advanced features including Lambda@Edge functions, CloudFront Functions, AWS WAF protection, real-time logging, and monitoring.

## Architecture Overview

The infrastructure includes:

- **CloudFront Distribution** with multiple origins and cache behaviors
- **S3 Bucket** for static content with Origin Access Control (OAC)
- **Lambda@Edge Functions** for advanced request/response processing
- **CloudFront Functions** for lightweight edge processing
- **AWS WAF** with managed rule sets and rate limiting
- **CloudFront KeyValueStore** for dynamic configuration
- **Kinesis Data Stream** for real-time log streaming
- **CloudWatch Dashboard** for monitoring and analytics

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for creating CloudFront, Lambda, S3, WAF, and monitoring resources
- Understanding of CloudFront edge computing concepts

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/content-delivery-networks-cloudfront/code/terraform/
   ```

2. **Copy and Customize Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific configuration
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Verify Deployment**:
   ```bash
   # Test the CloudFront distribution
   curl -I $(terraform output -raw cloudfront_distribution_url)
   ```

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for resources | `us-west-2` | Yes |
| `project_name` | Project name for resource naming | `advanced-cdn` | Yes |
| `environment` | Environment (dev/staging/prod) | `dev` | Yes |

### CloudFront Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `price_class` | Distribution price class | `PriceClass_All` |
| `enable_ipv6` | Enable IPv6 support | `true` |
| `enable_compression` | Enable content compression | `true` |
| `custom_origin_domain` | Custom origin domain | `httpbin.org` |

### Security Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_waf` | Enable AWS WAF protection | `true` |
| `waf_rate_limit` | WAF rate limit per IP | `2000` |
| `minimum_protocol_version` | Minimum SSL/TLS version | `TLSv1.2_2021` |

### Edge Computing

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_lambda_edge` | Enable Lambda@Edge functions | `true` |
| `enable_cloudfront_functions` | Enable CloudFront Functions | `true` |
| `lambda_edge_timeout` | Lambda@Edge timeout (seconds) | `5` |
| `lambda_edge_memory_size` | Lambda@Edge memory (MB) | `128` |

### Monitoring

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_real_time_logs` | Enable real-time logging | `true` |
| `enable_cloudwatch_dashboard` | Create monitoring dashboard | `true` |
| `cloudwatch_log_retention_days` | Log retention period | `14` |

## Customizing Edge Functions

### CloudFront Functions

Edit `functions/cloudfront-function.js` to customize request processing:

```javascript
function handler(event) {
    var request = event.request;
    
    // Add your custom logic here
    // - Header manipulation
    // - URL rewriting
    // - Cache key normalization
    
    return request;
}
```

### Lambda@Edge Functions

Edit `functions/lambda-edge.js` to customize response processing:

```javascript
exports.handler = async (event, context) => {
    const response = event.Records[0].cf.response;
    
    // Add your custom logic here
    // - Security headers
    // - Content transformation
    // - API integrations
    
    return response;
};
```

## Managing KeyValueStore

Update configuration values dynamically:

```bash
# Get KeyValueStore ARN
KVS_ARN=$(terraform output -raw key_value_store_arn)

# Update maintenance mode
aws cloudfront put-key \
    --kvs-arn $KVS_ARN \
    --key "maintenance_mode" \
    --value "true"

# Update feature flags
aws cloudfront put-key \
    --kvs-arn $KVS_ARN \
    --key "feature_flags" \
    --value '{"new_ui": true, "beta_features": true}'
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the monitoring dashboard:

```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

### Real-time Logs

Monitor real-time logs via Kinesis:

```bash
# Get Kinesis stream name
STREAM_NAME=$(terraform output -raw kinesis_stream_name)

# Read real-time log data
aws kinesis get-records \
    --shard-iterator $(aws kinesis get-shard-iterator \
        --stream-name $STREAM_NAME \
        --shard-id shardId-000000000000 \
        --shard-iterator-type LATEST \
        --query 'ShardIterator' --output text)
```

### CloudFront Metrics

Key metrics to monitor:

- **Requests**: Total number of requests
- **BytesDownloaded**: Data transfer volume
- **4xxErrorRate**: Client error rate
- **5xxErrorRate**: Server error rate
- **CacheHitRate**: Cache efficiency
- **OriginLatency**: Origin response time

## Security Features

### WAF Protection

The WAF includes:

- **Common Rule Set**: OWASP Top 10 protection
- **Known Bad Inputs**: Malicious payload detection
- **Rate Limiting**: IP-based request throttling
- **Geo Restriction**: Country-based access control (optional)

### Security Headers

Lambda@Edge automatically adds:

- `Strict-Transport-Security`
- `X-Content-Type-Options`
- `X-Frame-Options`
- `X-XSS-Protection`
- `Referrer-Policy`
- `Content-Security-Policy`
- `Permissions-Policy`

## Performance Optimization

### Cache Behaviors

The distribution includes optimized cache behaviors:

1. **Default Behavior** (S3 Origin):
   - Static content caching
   - Compression enabled
   - Security header injection

2. **API Behavior** (`/api/*`):
   - Custom origin routing
   - CORS headers
   - Flexible caching

3. **Static Assets** (`/static/*`):
   - Long-term caching
   - S3 origin
   - No edge functions

### Cache Policies

Uses AWS managed cache policies:

- **Managed-CachingOptimized**: For static content
- **Managed-CachingDisabled**: For dynamic content
- **Managed-CORS-S3Origin**: For CORS requests

## Testing the Deployment

### Basic Functionality

```bash
# Get distribution URL
DIST_URL=$(terraform output -raw cloudfront_distribution_url)

# Test main site
curl -I $DIST_URL/

# Test API endpoint
curl -I $DIST_URL/api/

# Test static content
curl -I $DIST_URL/static/

# Test security headers
curl -s -I $DIST_URL/ | grep -i security
```

### Cache Behavior

```bash
# Test cache hit/miss
curl -s -I $DIST_URL/ | grep -i x-cache
curl -s -I $DIST_URL/ | grep -i x-cache  # Second request should show hit
```

### WAF Testing

```bash
# Test rate limiting (requires multiple rapid requests)
for i in {1..10}; do
    curl -s -o /dev/null -w "%{http_code}\n" $DIST_URL/
done
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including S3 content, CloudFront distribution, and monitoring data.

## Cost Considerations

Estimated monthly costs (varies by usage):

- **CloudFront**: $0.085/GB data transfer + $0.0075/10,000 requests
- **Lambda@Edge**: $0.60/1M requests + $0.00005/GB-second
- **CloudFront Functions**: $0.10/1M invocations
- **WAF**: $1.00/web ACL + $0.60/1M requests
- **Kinesis**: $0.014/shard hour + $0.014/1M records
- **S3**: $0.023/GB storage + $0.0004/1,000 requests

## Troubleshooting

### Common Issues

1. **Lambda@Edge Deployment Delays**:
   - Lambda@Edge functions can take 15-45 minutes to propagate
   - Check CloudFormation stack status in us-east-1

2. **S3 Access Denied**:
   - Verify Origin Access Control configuration
   - Check S3 bucket policy includes correct distribution ARN

3. **WAF Blocking Legitimate Traffic**:
   - Review WAF logs in CloudWatch
   - Adjust rate limiting thresholds
   - Consider managed rule set exclusions

4. **Cache Behavior Issues**:
   - Verify path patterns and precedence
   - Check cache policy configuration
   - Use CloudFront invalidations if needed

### Debugging Commands

```bash
# Check distribution status
aws cloudfront get-distribution --id $(terraform output -raw cloudfront_distribution_id)

# View WAF blocked requests
aws wafv2 get-sampled-requests \
    --web-acl-arn $(terraform output -raw waf_web_acl_arn) \
    --rule-metric-name RateLimitRuleMetric \
    --scope CLOUDFRONT \
    --time-window StartTime=$(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S'),EndTime=$(date -u '+%Y-%m-%dT%H:%M:%S') \
    --max-items 10

# Check Lambda@Edge logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/us-east-1.$(terraform output -raw lambda_edge_function_name)"
```

## Additional Resources

- [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [Lambda@Edge Developer Guide](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-at-the-edge.html)
- [CloudFront Functions Guide](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html)
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)
- [CloudFront KeyValueStore Documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/kvs-with-functions.html)

## Support

For issues with this Terraform configuration:

1. Check the troubleshooting section above
2. Review Terraform and AWS provider documentation
3. Consult AWS CloudFront best practices
4. Check AWS service health dashboard

## License

This infrastructure code is provided as-is for educational and demonstration purposes.