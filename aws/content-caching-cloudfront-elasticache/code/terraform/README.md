# Content Caching Strategies - Terraform Implementation

This Terraform configuration deploys a comprehensive multi-tier caching infrastructure using AWS CloudFront and ElastiCache, demonstrating advanced content delivery and application-level caching strategies.

## Architecture Overview

The infrastructure implements a two-tier caching strategy:

1. **CloudFront Edge Caching**: Global content delivery network caching static assets and API responses at edge locations
2. **ElastiCache Application Caching**: Redis-based in-memory caching for database queries and session data
3. **Lambda Compute Layer**: Serverless functions implementing cache-aside pattern
4. **API Gateway**: RESTful API interface with intelligent cache header management

## Deployed Resources

### Core Infrastructure
- **CloudFront Distribution** with multiple origins and custom cache policies
- **ElastiCache Redis Cluster** with VPC subnet group configuration
- **Lambda Function** with VPC access and environment variables
- **API Gateway HTTP API** with Lambda proxy integration
- **S3 Bucket** for static content hosting with Origin Access Control

### Security & Monitoring
- **IAM Roles and Policies** following least privilege principles
- **CloudWatch Log Groups** for centralized logging
- **CloudWatch Alarms** for cache performance monitoring
- **S3 Bucket Policies** for secure CloudFront access

## Prerequisites

- **AWS CLI** v2.0 or later, configured with appropriate credentials
- **Terraform** v1.0 or later
- **AWS Account** with permissions for:
  - CloudFront distributions and cache policies
  - ElastiCache clusters and subnet groups
  - Lambda functions and IAM roles
  - API Gateway HTTP APIs
  - S3 buckets and policies
  - CloudWatch logs and alarms

## Quick Start

### 1. Initialize Terraform

```bash
# Clone and navigate to the terraform directory
cd aws/content-caching-strategies-cloudfront-elasticache/code/terraform/

# Initialize Terraform (downloads providers)
terraform init
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your preferred settings
# Key variables to review:
# - aws_region: Your preferred AWS region
# - environment: dev, staging, or prod
# - project_name: Unique identifier for your resources
```

### 3. Plan and Deploy

```bash
# Review the planned infrastructure changes
terraform plan

# Deploy the infrastructure
terraform apply

# Type 'yes' when prompted to confirm deployment
```

### 4. Verify Deployment

```bash
# View key outputs
terraform output

# Test the CloudFront distribution
curl -I $(terraform output -raw cloudfront_distribution_url)

# Test the API endpoint through CloudFront
curl $(terraform output -raw cloudfront_distribution_url)/api/data

# Test cache behavior with multiple requests
for i in {1..3}; do 
  curl -s $(terraform output -raw cloudfront_distribution_url)/api/data | jq '.cache_hit'
  sleep 2
done
```

## Configuration Options

### Environment-Specific Settings

```hcl
# Development Environment
environment = "dev"
elasticache_node_type = "cache.t3.micro"
lambda_memory_size = 128
cloudfront_price_class = "PriceClass_100"

# Production Environment  
environment = "prod"
elasticache_node_type = "cache.r6g.large"
lambda_memory_size = 512
cloudfront_price_class = "PriceClass_All"
enable_deletion_protection = true
```

### Cache TTL Optimization

```hcl
# Fast-changing data
api_cache_ttl_default = 30    # 30 seconds
elasticache_ttl = 120         # 2 minutes

# Stable data
api_cache_ttl_default = 300   # 5 minutes  
elasticache_ttl = 1800        # 30 minutes
```

## Testing the Caching Strategy

### 1. Cache Behavior Testing

```bash
# Get the CloudFront URL
CLOUDFRONT_URL=$(terraform output -raw cloudfront_distribution_url)

# Test static content caching
curl -I $CLOUDFRONT_URL/

# Test API endpoint caching (observe X-Cache headers)
curl -I $CLOUDFRONT_URL/api/data

# Test multiple requests to see cache hits
for i in {1..5}; do
  echo "Request $i:"
  curl -s $CLOUDFRONT_URL/api/data | jq '{cache_hit: .cache_hit, source: .source}'
  sleep 2
done
```

### 2. Performance Testing

```bash
# Test response times
time curl -s $CLOUDFRONT_URL/api/data > /dev/null

# Test from different locations using online tools:
# - GTmetrix: https://gtmetrix.com/
# - Pingdom: https://www.pingdom.com/
# - WebPageTest: https://www.webpagetest.org/
```

### 3. Cache Invalidation Testing

```bash
# Create CloudFront invalidation
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/api/*"

# Monitor invalidation status
aws cloudfront list-invalidations \
  --distribution-id $(terraform output -raw cloudfront_distribution_id)
```

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics in the AWS Console:

1. **CloudFront Metrics**:
   - Cache Hit Rate
   - Requests per second
   - Data transfer volumes

2. **ElastiCache Metrics**:
   - CPU Utilization
   - Memory Usage
   - Cache Hit Ratio

3. **Lambda Metrics**:
   - Duration
   - Error Rate
   - Concurrent Executions

### Log Analysis

```bash
# View API Gateway logs
aws logs filter-log-events \
  --log-group-name $(terraform output -raw cloudwatch_log_group_api_gateway) \
  --start-time $(date -d '1 hour ago' +%s)000

# View Lambda logs
aws logs filter-log-events \
  --log-group-name $(terraform output -raw cloudwatch_log_group_lambda) \
  --start-time $(date -d '1 hour ago' +%s)000
```

## Cost Optimization

### Development Environment
- Use `cache.t3.micro` for ElastiCache (~$15/month)
- Use `PriceClass_100` for CloudFront (US/Europe only)
- Set conservative Lambda memory allocation (128MB)

### Production Environment
- Scale ElastiCache based on data volume
- Consider `PriceClass_All` for global reach
- Optimize Lambda memory for performance vs. cost
- Implement proper resource tagging for cost allocation

## Troubleshooting

### Common Issues

1. **Lambda timeout connecting to ElastiCache**:
   ```bash
   # Check VPC configuration and security groups
   terraform output vpc_id
   terraform output subnet_ids
   ```

2. **CloudFront not serving updated content**:
   ```bash
   # Create invalidation
   aws cloudfront create-invalidation \
     --distribution-id $(terraform output -raw cloudfront_distribution_id) \
     --paths "/*"
   ```

3. **ElastiCache connection refused**:
   ```bash
   # Verify cluster status
   aws elasticache describe-cache-clusters \
     --cache-cluster-id $(terraform output -raw elasticache_cluster_id)
   ```

### Debug Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# View detailed output
terraform apply -auto-approve -detailed-exitcode
```

## Security Considerations

### Network Security
- ElastiCache deployed in private subnets
- Lambda functions have VPC access controls
- S3 bucket access restricted to CloudFront

### Access Controls
- IAM roles follow least privilege principle
- CloudFront Origin Access Control prevents direct S3 access
- API Gateway supports CORS for browser security

### Data Protection
- S3 server-side encryption enabled
- CloudFront supports HTTPS redirection
- ElastiCache connections are within VPC

## Cleanup

### Complete Infrastructure Removal

```bash
# Destroy all resources (this will delete everything)
terraform destroy

# Type 'yes' when prompted to confirm destruction
```

### Selective Resource Removal

```bash
# Remove only CloudFront distribution (takes 15-20 minutes)
terraform destroy -target=aws_cloudfront_distribution.cache_demo

# Remove only ElastiCache cluster
terraform destroy -target=aws_elasticache_cluster.redis
```

## Advanced Customization

### Multi-Region Deployment

To deploy across multiple regions, use Terraform workspaces:

```bash
# Create workspace for different region
terraform workspace new us-west-2

# Deploy with region-specific variables
terraform apply -var="aws_region=us-west-2"
```

### Custom Cache Policies

Add custom cache behaviors in the `main.tf` file:

```hcl
ordered_cache_behavior {
  path_pattern = "/assets/*"
  target_origin_id = "S3-${aws_s3_bucket.static_content.id}"
  cache_policy_id = "custom-policy-id"
  viewer_protocol_policy = "redirect-to-https"
}
```

### Integration with Existing Infrastructure

Import existing resources into Terraform state:

```bash
# Import existing S3 bucket
terraform import aws_s3_bucket.static_content existing-bucket-name

# Import existing ElastiCache cluster  
terraform import aws_elasticache_cluster.redis existing-cluster-id
```

## Support and Maintenance

### Regular Maintenance Tasks

1. **Update Terraform providers** monthly
2. **Review CloudWatch alarms** weekly
3. **Analyze cache hit ratios** weekly
4. **Update Lambda runtime** as needed
5. **Review security configurations** quarterly

### Performance Optimization

1. **Analyze CloudFront reports** for cache efficiency
2. **Monitor ElastiCache memory usage** for right-sizing
3. **Review Lambda execution times** for optimization opportunities
4. **Test from different geographic locations** for global performance

For additional support, refer to the original recipe documentation or AWS service documentation.