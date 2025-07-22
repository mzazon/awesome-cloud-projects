# Multi-Region Aurora DSQL Application - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a globally distributed serverless application using Aurora DSQL across multiple AWS regions with Lambda functions and API Gateway.

## Architecture Overview

The infrastructure creates:

- **Aurora DSQL Clusters**: Active-active multi-region database clusters with strong consistency
- **Lambda Functions**: Serverless compute in both primary and secondary regions
- **API Gateway**: RESTful APIs with regional endpoints for optimal performance
- **Monitoring**: CloudWatch logs, metrics, and alarms for observability
- **Security**: IAM roles and policies following least privilege principles

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** version 1.0 or later installed
3. **AWS Account** with sufficient permissions to create:
   - Aurora DSQL clusters
   - Lambda functions
   - API Gateway resources
   - IAM roles and policies
   - CloudWatch resources
   - Route 53 health checks (optional)

## Required AWS Permissions

Your AWS credentials need permissions for the following services:
- Aurora DSQL (dsql:*)
- Lambda (lambda:*)
- API Gateway (apigateway:*)
- IAM (iam:*)
- CloudWatch (cloudwatch:*, logs:*)
- Route 53 (route53:*) - if using health checks

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables to match your requirements
vim terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

### 3. Plan the Deployment

```bash
# Review the execution plan
terraform plan
```

### 4. Deploy the Infrastructure

```bash
# Apply the configuration
terraform apply
```

### 5. Verify the Deployment

After deployment, test the endpoints:

```bash
# Test primary region health endpoint
curl https://PRIMARY_API_ID.execute-api.us-east-1.amazonaws.com/prod/health

# Test secondary region health endpoint  
curl https://SECONDARY_API_ID.execute-api.us-east-2.amazonaws.com/prod/health

# List users from primary region
curl https://PRIMARY_API_ID.execute-api.us-east-1.amazonaws.com/prod/users

# Create a user in secondary region
curl -X POST https://SECONDARY_API_ID.execute-api.us-east-2.amazonaws.com/prod/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}'
```

## Configuration

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `primary_region` | Primary AWS region | `us-east-1` |
| `secondary_region` | Secondary AWS region | `us-east-2` |
| `witness_region` | Witness region for Aurora DSQL | `us-west-2` |

### Important Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_deletion_protection` | Protect Aurora DSQL clusters from deletion | `true` |
| `lambda_timeout` | Lambda function timeout in seconds | `30` |
| `lambda_memory_size` | Lambda function memory in MB | `512` |
| `enable_cloudwatch_logs` | Enable CloudWatch logging | `true` |
| `create_sample_data` | Create sample users during initialization | `true` |

### Security Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `lambda_subnet_ids` | VPC subnets for Lambda (optional) | `[]` |
| `lambda_security_group_ids` | Security groups for Lambda | `[]` |
| `enable_api_key_required` | Require API keys for endpoints | `false` |
| `cors_allow_origins` | CORS allowed origins | `["*"]` |

## Outputs

After successful deployment, Terraform provides these key outputs:

- **API Endpoints**: URLs for both regional API Gateway endpoints
- **Aurora DSQL Clusters**: ARNs and endpoints for database clusters
- **Lambda Functions**: Names and ARNs of deployed functions
- **Monitoring**: CloudWatch log groups and dashboard URLs
- **Validation Commands**: curl commands for testing deployment

## File Structure

```
terraform/
├── main.tf                    # Main infrastructure configuration
├── variables.tf               # Variable definitions
├── versions.tf               # Provider requirements
├── outputs.tf                # Output definitions
├── terraform.tfvars.example  # Example configuration
├── README.md                 # This file
├── lambda_function.py.tpl    # Lambda function template
├── init_db.py.tpl           # Database initialization template
└── modules/
    ├── api_gateway/          # API Gateway module
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── lambda_monitoring/    # Lambda monitoring module
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Customization

### VPC Deployment

To deploy Lambda functions in a VPC:

```hcl
lambda_subnet_ids = ["subnet-12345678", "subnet-87654321"]
lambda_security_group_ids = ["sg-12345678"]
```

### Custom Domain

To use a custom domain with Route 53:

```hcl
route53_hosted_zone_id = "Z1234567890ABC"
custom_domain_name = "api.yourdomain.com"
create_route53_health_checks = true
```

### Additional Lambda Layers

To add Lambda layers:

```hcl
lambda_layer_arns = [
  "arn:aws:lambda:us-east-1:123456789012:layer:my-layer:1"
]
```

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

### CloudWatch Dashboards

- **Lambda Metrics**: Function invocations, errors, duration, and throttles
- **Aurora DSQL Metrics**: Database performance and connectivity
- **API Gateway Metrics**: Request counts, latency, and error rates

### CloudWatch Alarms

- Lambda error rate monitoring
- Lambda duration threshold alerts
- Lambda throttling detection
- Aurora DSQL connectivity monitoring

### AWS X-Ray Tracing

Distributed tracing is enabled by default for:
- Lambda function execution
- Aurora DSQL database calls
- API Gateway request flows

## Cost Optimization

### Aurora DSQL Pricing

Aurora DSQL uses pay-per-request pricing:
- No minimum charges or upfront costs
- Charged for actual database requests and storage
- Cross-region replication included

### Lambda Pricing

Lambda functions benefit from:
- AWS Free Tier: 1M requests + 400,000 GB-seconds monthly
- Pay-per-millisecond execution time
- No charges when idle

### API Gateway Pricing

API Gateway costs:
- Free Tier: 1M API calls per month
- Regional endpoints for reduced latency
- CloudWatch logging included

## Security Best Practices

The infrastructure implements security best practices:

### IAM Roles and Policies

- **Least Privilege**: Lambda functions have minimal required permissions
- **Resource-Specific**: Policies scoped to specific Aurora DSQL clusters
- **No Hard-coded Credentials**: Uses AWS IAM roles for authentication

### Network Security

- **VPC Support**: Optional VPC deployment for Lambda functions
- **Security Groups**: Configurable network access controls
- **CORS Configuration**: Customizable cross-origin resource sharing

### Data Security

- **Encryption**: Aurora DSQL uses encryption at rest and in transit
- **Strong Consistency**: ACID transaction properties across regions
- **Audit Logging**: CloudTrail and CloudWatch logs for compliance

## Troubleshooting

### Common Issues

#### Aurora DSQL Cluster Pending

If clusters remain in PENDING state:
- Verify regions support Aurora DSQL
- Check IAM permissions for DSQL operations
- Wait 5-10 minutes for cluster activation

#### Lambda Function Timeouts

If Lambda functions timeout:
- Increase `lambda_timeout` variable
- Check Aurora DSQL cluster connectivity
- Review CloudWatch logs for specific errors

#### API Gateway 5xx Errors

If API returns server errors:
- Check Lambda function logs in CloudWatch
- Verify Aurora DSQL cluster status
- Test database connectivity

### Debugging Commands

```bash
# Check Aurora DSQL cluster status
aws dsql get-cluster --region us-east-1 --cluster-identifier CLUSTER_ID

# View Lambda function logs
aws logs tail /aws/lambda/FUNCTION_NAME --region us-east-1

# Test Lambda function directly
aws lambda invoke --function-name FUNCTION_NAME --region us-east-1 response.json

# Check API Gateway execution logs
aws logs tail /aws/apigateway/API_ID --region us-east-1
```

## Maintenance

### Regular Tasks

1. **Monitor Costs**: Review AWS Cost Explorer monthly
2. **Update Dependencies**: Keep Lambda runtime versions current
3. **Review Logs**: Check CloudWatch logs for errors or warnings
4. **Performance Tuning**: Adjust Lambda memory/timeout based on metrics

### Updates and Upgrades

```bash
# Update Terraform providers
terraform init -upgrade

# Plan changes before applying
terraform plan

# Apply updates
terraform apply
```

## Cleanup

To destroy all infrastructure:

```bash
# Remove deletion protection first (if enabled)
terraform apply -var="enable_deletion_protection=false"

# Destroy all resources
terraform destroy
```

**Warning**: This will permanently delete all data in Aurora DSQL clusters.

## Support

For issues with this Terraform configuration:

1. Check the [AWS Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/)
2. Review Terraform AWS Provider documentation
3. Check CloudWatch logs for specific error messages
4. Refer to the original recipe documentation

## Advanced Features

### Blue-Green Deployments

The infrastructure supports blue-green deployments by:
- Creating parallel Lambda function versions
- Using API Gateway stage variables
- Implementing gradual traffic shifting

### Multi-Account Deployment

For multi-account setups:
- Use Terraform workspaces
- Configure cross-account IAM roles
- Implement centralized monitoring

### Disaster Recovery

Built-in disaster recovery features:
- Active-active multi-region architecture
- Automatic failover with Route 53 health checks
- Strong consistency across regions
- Point-in-time recovery capabilities