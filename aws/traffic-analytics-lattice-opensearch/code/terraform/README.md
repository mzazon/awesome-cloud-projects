# Terraform Infrastructure for Traffic Analytics with VPC Lattice and OpenSearch

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive traffic analytics solution using VPC Lattice access logs streamed through Kinesis Data Firehose to OpenSearch Service.

## Architecture Overview

The infrastructure creates:
- **OpenSearch Service Domain** for analytics and visualization
- **Kinesis Data Firehose** for streaming data ingestion
- **Lambda Function** for real-time log transformation and enrichment
- **VPC Lattice Service Network** with demo service for traffic generation
- **S3 Bucket** for backup storage and error handling
- **IAM Roles and Policies** for secure service communication
- **CloudWatch Dashboard** for monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - OpenSearch Service
  - VPC Lattice
  - Kinesis Data Firehose
  - Lambda
  - IAM roles and policies
  - S3 buckets
  - CloudWatch

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or navigate to the terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init
```

### 2. Review and Customize Variables

```bash
# Review available variables
cat variables.tf

# Create a terraform.tfvars file for customization (optional)
cat > terraform.tfvars << EOF
project_name = "my-traffic-analytics"
environment = "dev"
aws_region = "us-east-1"
opensearch_instance_type = "t3.small.search"
opensearch_volume_size = 20
log_retention_days = 7
EOF
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Access Your Analytics Platform

After deployment, Terraform will output important URLs and resource information:

```bash
# View all outputs
terraform output

# Get specific outputs
terraform output opensearch_dashboards_url
terraform output cloudwatch_dashboard_url
```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Name prefix for all resources | `traffic-analytics` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `aws_region` | AWS region for deployment | `us-east-1` | No |

### OpenSearch Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `opensearch_version` | OpenSearch engine version | `OpenSearch_2.11` | No |
| `opensearch_instance_type` | Instance type for OpenSearch | `t3.small.search` | No |
| `opensearch_instance_count` | Number of OpenSearch instances | `1` | No |
| `opensearch_volume_size` | EBS volume size (GB) | `20` | No |

### Performance and Monitoring

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `firehose_buffer_size` | Firehose buffer size (MB) | `1` | No |
| `firehose_buffer_interval` | Firehose buffer interval (seconds) | `60` | No |
| `lambda_timeout` | Lambda timeout (seconds) | `60` | No |
| `lambda_memory_size` | Lambda memory (MB) | `256` | No |
| `log_retention_days` | CloudWatch log retention | `7` | No |

### Security Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_s3_encryption` | Enable S3 encryption | `true` | No |
| `enable_opensearch_encryption` | Enable OpenSearch encryption | `true` | No |
| `enforce_https` | Enforce HTTPS for OpenSearch | `true` | No |

## Outputs

The Terraform configuration provides comprehensive outputs for integration and monitoring:

### Key Endpoints
- `opensearch_dashboards_url` - Direct link to OpenSearch Dashboards
- `opensearch_endpoint` - OpenSearch API endpoint
- `cloudwatch_dashboard_url` - CloudWatch monitoring dashboard

### Resource Information
- `resource_names` - Map of all created resource names
- `resource_arns` - Map of all created resource ARNs
- `useful_commands` - AWS CLI commands for resource management

### Integration Details
- `integration_endpoints` - Key endpoints for external integration
- `security_information` - Security configuration details
- `deployment_info` - Environment and deployment metadata

## Verification and Testing

### 1. Verify OpenSearch Domain

```bash
# Check domain status
aws opensearch describe-domain \
    --domain-name $(terraform output -raw opensearch_domain_name) \
    --query 'DomainStatus.Processing'

# Check cluster health
curl -X GET "$(terraform output -raw opensearch_endpoint)/_cluster/health"
```

### 2. Test Firehose Delivery

```bash
# Check delivery stream status
aws firehose describe-delivery-stream \
    --delivery-stream-name $(terraform output -raw firehose_delivery_stream_name) \
    --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Send test record
echo '{"test": "data", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' | \
aws firehose put-record \
    --delivery-stream-name $(terraform output -raw firehose_delivery_stream_name) \
    --record Data=blob://dev/stdin
```

### 3. Monitor Lambda Function

```bash
# Check Lambda function status
aws lambda get-function \
    --function-name $(terraform output -raw lambda_function_name) \
    --query 'Configuration.State'

# View recent logs
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
    --order-by LastEventTime --descending
```

## Cost Optimization

### Estimated Monthly Costs

- **OpenSearch t3.small.search**: ~$20-40/month
- **EBS Storage (20GB)**: ~$2-5/month
- **Kinesis Data Firehose**: Pay per GB ingested
- **Lambda**: Pay per invocation and duration
- **S3 Storage**: Pay per GB stored

### Cost Optimization Tips

1. **Right-size OpenSearch instances** based on your traffic volume
2. **Adjust buffer settings** to optimize Firehose costs
3. **Implement S3 lifecycle policies** for backup data
4. **Monitor CloudWatch metrics** to optimize resource utilization

## Security Considerations

### Current Security Features

- ✅ OpenSearch encryption at rest and in transit
- ✅ S3 bucket encryption and public access blocking
- ✅ IAM roles with least privilege principles
- ✅ HTTPS enforcement for all endpoints

### Production Security Enhancements

For production deployments, consider implementing:

1. **VPC Integration**: Deploy OpenSearch in a VPC with private subnets
2. **Fine-grained Access Control**: Implement OpenSearch fine-grained access control
3. **Cognito Authentication**: Enable Cognito for OpenSearch Dashboards authentication
4. **Custom Access Policies**: Replace the open access policy with restrictive policies
5. **WAF Integration**: Add AWS WAF for additional protection

### Security Configuration

```bash
# Example: Update to use custom access policy
# Edit terraform.tfvars to include:
custom_opensearch_policy = jsonencode({
  Version = "2012-10-17"
  Statement = [
    {
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::ACCOUNT-ID:user/specific-user"
      }
      Action = "es:*"
      Resource = "domain-arn/*"
    }
  ]
})
```

## Advanced Configuration

### Backend Configuration

For team collaboration, configure a remote backend:

```hcl
# Add to versions.tf
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "traffic-analytics/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

### Multi-Environment Deployment

Use Terraform workspaces for multiple environments:

```bash
# Create and switch to development workspace
terraform workspace new dev
terraform workspace select dev

# Deploy to development
terraform apply -var="environment=dev"

# Create and deploy to staging
terraform workspace new staging
terraform workspace select staging
terraform apply -var="environment=staging"
```

### Custom Lambda Function

To customize the Lambda transformation function:

1. Edit `lambda_function.py` with your custom logic
2. Run `terraform apply` to update the function

## Troubleshooting

### Common Issues

1. **OpenSearch domain creation fails**
   - Check service limits in your AWS account
   - Verify IAM permissions for OpenSearch Service
   - Ensure the domain name is unique

2. **Firehose delivery failures**
   - Check IAM role permissions
   - Verify OpenSearch domain is accessible
   - Review CloudWatch logs for error details

3. **Lambda function errors**
   - Check function logs in CloudWatch
   - Verify memory and timeout configurations
   - Test with sample data

### Debugging Commands

```bash
# Check all resource status
terraform refresh
terraform show

# View detailed logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
    --start-time $(date -d '1 hour ago' +%s)000

# Check Firehose metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/KinesisFirehose \
    --metric-name DeliveryToOpenSearch.Records \
    --dimensions Name=DeliveryStreamName,Value=$(terraform output -raw firehose_delivery_stream_name) \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## Cleanup

To remove all created resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm destruction
terraform show
```

**Note**: The OpenSearch domain deletion takes 10-15 minutes to complete.

## Support and Contributing

- For issues with this Terraform configuration, refer to the original recipe documentation
- Check AWS service documentation for provider-specific issues
- Terraform AWS Provider documentation: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify and adapt according to your organization's requirements and security policies.