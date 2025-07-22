# Infrastructure as Code for Content Caching Strategies with CloudFront

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Caching Strategies with CloudFront".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a multi-tier caching architecture that combines:

- **CloudFront Distribution**: Global content delivery with edge caching
- **ElastiCache Redis Cluster**: Application-level in-memory caching
- **Lambda Functions**: Serverless compute with cache-aside pattern implementation
- **API Gateway**: RESTful API endpoint for dynamic content
- **S3 Bucket**: Static content storage with secure CloudFront access
- **IAM Roles**: Least privilege security configurations
- **CloudWatch**: Monitoring and alerting for cache performance

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions for:
  - CloudFront distribution creation and management
  - ElastiCache cluster operations
  - Lambda function deployment with VPC access
  - API Gateway configuration
  - S3 bucket creation and policy management
  - IAM role and policy creation
  - CloudWatch monitoring setup
- Estimated cost: $50-100/month for development environment

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name content-caching-demo \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev
```

Monitor deployment progress:
```bash
aws cloudformation describe-stack-events \
    --stack-name content-caching-demo
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build
cdk bootstrap  # if not previously done
cdk deploy --all
```

### Using CDK Python
```bash
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
cdk bootstrap  # if not previously done
cdk deploy --all
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="environment=dev"
terraform apply -var="environment=dev"
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Options

### CloudFormation Parameters

- `Environment`: Deployment environment (dev, staging, prod)
- `CacheNodeType`: ElastiCache instance type (default: cache.t3.micro)
- `CloudFrontPriceClass`: Price class for CloudFront (default: PriceClass_100)
- `EnableMonitoring`: Enable CloudWatch monitoring and alarms (default: true)

### CDK Context Variables

Configure in `cdk.json` or pass via command line:
```bash
cdk deploy -c environment=prod -c cacheNodeType=cache.t3.small
```

### Terraform Variables

Create a `terraform.tfvars` file or set via command line:
```bash
terraform apply \
    -var="environment=prod" \
    -var="cache_node_type=cache.t3.small" \
    -var="enable_monitoring=true"
```

## Post-Deployment

### Verify Deployment

1. **Check CloudFront Distribution**:
   ```bash
   aws cloudfront list-distributions \
       --query "DistributionList.Items[?Comment=='Multi-tier caching demo']"
   ```

2. **Verify ElastiCache Cluster**:
   ```bash
   aws elasticache describe-cache-clusters \
       --show-cache-node-info \
       --query "CacheClusters[?CacheClusterStatus=='available']"
   ```

3. **Test Lambda Function**:
   ```bash
   aws lambda invoke \
       --function-name cache-demo-function \
       --payload '{}' \
       response.json && cat response.json
   ```

### Testing the Caching Strategy

1. **Test API Endpoint**:
   ```bash
   # Get API Gateway endpoint from outputs
   API_ENDPOINT=$(aws apigatewayv2 get-apis \
       --query "Items[?Name=='cache-demo-api'].ApiEndpoint" \
       --output text)
   
   # Test multiple requests to verify caching
   for i in {1..3}; do
       echo "Request $i:"
       curl -s ${API_ENDPOINT}/api/data | jq '.'
       sleep 2
   done
   ```

2. **Test CloudFront Distribution**:
   ```bash
   # Get CloudFront domain
   DOMAIN=$(aws cloudfront list-distributions \
       --query "DistributionList.Items[0].DomainName" \
       --output text)
   
   # Test static content
   curl -I https://${DOMAIN}/
   
   # Test API through CloudFront
   curl -s https://${DOMAIN}/api/data | jq '.'
   ```

### Monitoring and Optimization

1. **Monitor Cache Performance**:
   ```bash
   # Check CloudFront metrics
   aws cloudwatch get-metric-statistics \
       --namespace AWS/CloudFront \
       --metric-name CacheHitRate \
       --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
       --period 300 \
       --statistics Average
   ```

2. **ElastiCache Monitoring**:
   ```bash
   # Check ElastiCache performance
   aws cloudwatch get-metric-statistics \
       --namespace AWS/ElastiCache \
       --metric-name CacheHits \
       --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
       --period 300 \
       --statistics Sum
   ```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name content-caching-demo
```

Monitor deletion progress:
```bash
aws cloudformation describe-stack-events \
    --stack-name content-caching-demo
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy --all
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="environment=dev"
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Scaling Configuration

Modify cache configurations for different environments:

- **Development**: `cache.t3.micro` ElastiCache, `PriceClass_100` CloudFront
- **Production**: `cache.r6g.large` ElastiCache, `PriceClass_All` CloudFront

### Security Enhancements

1. **VPC Configuration**: All implementations place ElastiCache in private subnets
2. **IAM Policies**: Least privilege access for all components
3. **S3 Security**: Bucket access restricted to CloudFront only
4. **API Security**: Consider adding AWS WAF for API protection

### Performance Optimization

1. **TTL Configuration**: Adjust cache TTL values based on content type
2. **Compression**: Enable Brotli compression in CloudFront
3. **Origin Shield**: Enable for high-traffic scenarios
4. **Multi-AZ**: Configure ElastiCache across multiple availability zones

## Cost Optimization

1. **Reserved Instances**: Consider ElastiCache reserved instances for production
2. **CloudFront Price Classes**: Use regional price classes for cost savings
3. **Monitoring**: Set up billing alerts and cost optimization recommendations
4. **Right-sizing**: Monitor cache utilization and adjust instance types

## Troubleshooting

### Common Issues

1. **Lambda VPC Timeout**: Ensure Lambda has proper VPC configuration and NAT Gateway access
2. **ElastiCache Connection**: Verify security group rules allow Redis port 6379
3. **CloudFront Cache Miss**: Check TTL settings and cache behaviors
4. **API Gateway 5xx Errors**: Monitor Lambda logs in CloudWatch

### Debug Commands

```bash
# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/cache-demo"

# Monitor ElastiCache events
aws elasticache describe-events --duration 60

# CloudFront real-time logs (if enabled)
aws logs filter-log-events \
    --log-group-name "/aws/cloudfront/realtime/content-caching-demo"
```

## Advanced Features

### Multi-Region Deployment

The Terraform implementation supports multi-region deployment:

```bash
terraform apply \
    -var="enable_multi_region=true" \
    -var="secondary_regions=[\"us-west-2\",\"eu-west-1\"]"
```

### Auto-Scaling Configuration

ElastiCache cluster can be configured for automatic scaling:

```bash
# Enable auto-scaling for production workloads
terraform apply -var="enable_auto_scaling=true"
```

### Cache Warming

Implement cache warming strategies using EventBridge schedules:

```bash
# Deploy with cache warming enabled
cdk deploy -c enableCacheWarming=true
```

## Support

- For infrastructure code issues, refer to the original recipe documentation
- For AWS service-specific questions, consult the [AWS Documentation](https://docs.aws.amazon.com/)
- For Terraform provider issues, see the [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- For CDK issues, refer to the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)

## Related Resources

- [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [AWS ElastiCache Documentation](https://docs.aws.amazon.com/elasticache/)
- [Caching Best Practices](https://docs.aws.amazon.com/whitepapers/latest/database-caching-strategies-using-redis/caching-patterns.html)
- [CloudFront Security Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/security-best-practices.html)