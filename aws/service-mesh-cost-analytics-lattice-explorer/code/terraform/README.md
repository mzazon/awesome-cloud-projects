# VPC Lattice Cost Analytics - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive VPC Lattice cost analytics platform on AWS. The infrastructure combines VPC Lattice monitoring capabilities with Cost Explorer APIs to provide detailed service mesh cost insights and optimization recommendations.

## Architecture Overview

The Terraform code deploys the following components:

- **S3 Bucket**: Secure storage for cost analytics data with encryption and versioning
- **Lambda Function**: Serverless cost processor that combines VPC Lattice metrics with Cost Explorer data
- **IAM Role & Policies**: Least-privilege permissions for secure access to AWS services
- **EventBridge Rule**: Automated scheduling for regular cost analysis
- **CloudWatch Dashboard**: Real-time visualization of cost metrics and trends
- **VPC Lattice Demo Resources**: Optional service network and service for testing

## Prerequisites

1. **AWS Account**: Active AWS account with appropriate permissions
2. **Terraform**: Version 1.5.0 or later installed
3. **AWS CLI**: Version 2.x configured with credentials
4. **Cost Explorer**: Enabled in your AWS account (may take up to 24 hours)
5. **IAM Permissions**: Ability to create IAM roles, policies, Lambda functions, S3 buckets, and VPC Lattice resources

### Required AWS Permissions

Your AWS credentials must have permissions for:
- IAM role and policy management
- Lambda function creation and management
- S3 bucket creation and configuration
- EventBridge rule management
- CloudWatch dashboard creation
- VPC Lattice service management (if using demo resources)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/service-mesh-cost-analytics-lattice-explorer/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables to match your environment
nano terraform.tfvars
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name for resource naming | `lattice-cost-analytics` | No |
| `environment` | Environment name (dev/staging/prod/demo) | `demo` | No |
| `cost_center` | Cost center for billing allocation | `engineering` | No |
| `owner` | Team or individual responsible | `platform-team` | No |

### Lambda Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `lambda_timeout` | Function timeout in seconds | `300` | 30-900 |
| `lambda_memory_size` | Memory allocation in MB | `512` | 128-10240 |
| `lambda_runtime` | Python runtime version | `python3.11` | - |

### Feature Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cloudwatch_dashboard` | Create CloudWatch dashboard | `true` |
| `enable_demo_vpc_lattice` | Deploy demo VPC Lattice resources | `true` |
| `s3_versioning_enabled` | Enable S3 bucket versioning | `true` |
| `s3_encryption_enabled` | Enable S3 server-side encryption | `true` |

### Scheduling

| Variable | Description | Default |
|----------|-------------|---------|
| `cost_analysis_schedule` | EventBridge schedule expression | `rate(1 day)` |

Example schedule expressions:
- `rate(1 day)` - Daily execution
- `rate(12 hours)` - Twice daily
- `cron(0 9 * * ? *)` - Daily at 9 AM UTC

## Example terraform.tfvars

```hcl
# Project Configuration
project_name = "my-lattice-analytics"
environment  = "prod"
cost_center  = "platform-engineering"
owner        = "devops-team"

# Lambda Configuration
lambda_timeout     = 300
lambda_memory_size = 512
lambda_runtime     = "python3.11"

# Feature Configuration
enable_cloudwatch_dashboard = true
enable_demo_vpc_lattice     = false  # Disable for production
s3_versioning_enabled       = true
s3_encryption_enabled       = true

# Scheduling
cost_analysis_schedule = "rate(1 day)"

# Custom Tags
additional_tags = {
  Department = "Engineering"
  Purpose    = "Cost Optimization"
  CreatedBy  = "Terraform"
}
```

## Deployment Outputs

After successful deployment, Terraform provides these important outputs:

### Core Infrastructure
- `s3_bucket_name` - Analytics data storage bucket
- `lambda_function_name` - Cost processor function name
- `lambda_function_arn` - Function ARN for manual invocation
- `eventbridge_rule_name` - Scheduled analysis rule name

### Demo Resources (if enabled)
- `demo_service_network_id` - VPC Lattice service network ID
- `demo_service_id` - VPC Lattice service ID
- `demo_association_id` - Service network association ID

### Useful URLs
- `cloudwatch_dashboard_url` - Direct link to cost analytics dashboard

### Testing Commands
- `manual_test_commands` - CLI commands for manual testing

## Post-Deployment Verification

### 1. Test Lambda Function

```bash
# Get function name from outputs
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# Invoke function manually
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# Check response
cat response.json
```

### 2. Verify S3 Storage

```bash
# Get bucket name from outputs
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# List bucket contents
aws s3 ls s3://$BUCKET_NAME/ --recursive
```

### 3. Check CloudWatch Metrics

```bash
# List custom metrics
aws cloudwatch list-metrics \
    --namespace VPCLattice/CostAnalytics

# View dashboard (if enabled)
echo "Dashboard URL: $(terraform output -raw cloudwatch_dashboard_url)"
```

### 4. Monitor Logs

```bash
# Get log group name
LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)

# View recent logs
aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --order-by LastEventTime \
    --descending
```

## Cost Optimization

### Expected Costs

The deployed infrastructure has minimal ongoing costs:

- **Lambda Function**: Pay-per-execution (estimated $1-5/month)
- **S3 Storage**: Storage and requests (estimated $1-3/month)
- **CloudWatch**: Logs and custom metrics (estimated $2-5/month)
- **EventBridge**: Rule executions (minimal cost)

**Total estimated cost**: $5-15/month (excluding VPC Lattice traffic costs)

### Cost Optimization Tips

1. **Adjust Lambda Memory**: Monitor execution time and optimize memory allocation
2. **S3 Lifecycle Policies**: Archive old analytics data to cheaper storage classes
3. **Log Retention**: CloudWatch logs are set to 14-day retention
4. **Demo Resources**: Disable `enable_demo_vpc_lattice` in production
5. **Scheduling**: Adjust `cost_analysis_schedule` based on your needs

## Troubleshooting

### Common Issues

1. **Cost Explorer Not Enabled**
   ```bash
   # Check if Cost Explorer is available
   aws ce get-cost-and-usage \
       --time-period Start=2025-01-01,End=2025-01-02 \
       --granularity MONTHLY \
       --metrics BlendedCost
   ```

2. **Lambda Permission Errors**
   - Verify IAM policies are attached correctly
   - Check EventBridge trigger permissions
   - Review S3 bucket permissions

3. **No VPC Lattice Data**
   - Ensure VPC Lattice service networks exist
   - Verify metrics are being generated
   - Check CloudWatch namespace: `AWS/VpcLattice`

4. **Dashboard Not Showing Data**
   - Wait for Lambda execution to publish metrics
   - Check custom metrics in namespace: `VPCLattice/CostAnalytics`
   - Verify EventBridge rule is triggering

### Debugging Commands

```bash
# Check Lambda execution logs
aws logs filter-log-events \
    --log-group-name $(terraform output -raw cloudwatch_log_group_name) \
    --start-time $(date -d '1 hour ago' +%s)000

# Verify EventBridge rule status
aws events describe-rule \
    --name $(terraform output -raw eventbridge_rule_name)

# Check S3 bucket policy
aws s3api get-bucket-policy \
    --bucket $(terraform output -raw s3_bucket_name)
```

## Customization

### Adding Custom Metrics

Modify the Lambda function template (`lambda_function.py.tpl`) to include additional cost metrics:

```python
# Add custom metric
cw_client.put_metric_data(
    Namespace='VPCLattice/CostAnalytics',
    MetricData=[
        {
            'MetricName': 'CustomCostMetric',
            'Value': your_calculated_value,
            'Unit': 'None'
        }
    ]
)
```

### Adding Dashboard Widgets

Extend the dashboard template (`dashboard.json.tpl`) with additional visualizations:

```json
{
  "type": "metric",
  "properties": {
    "metrics": [
      [ "YourNamespace", "YourMetric" ]
    ],
    "title": "Your Custom Widget"
  }
}
```

## Security Considerations

1. **IAM Permissions**: Uses least-privilege principle with service-specific permissions
2. **S3 Encryption**: Server-side encryption enabled by default
3. **S3 Public Access**: Blocked by default for security
4. **VPC Lattice Auth**: Uses AWS_IAM authentication type
5. **Resource Tagging**: Comprehensive tagging for cost tracking and governance

## Cleanup

To destroy all deployed resources:

```bash
# Plan destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy
```

**Note**: Terraform will prompt for confirmation before destroying resources. Type `yes` to confirm.

### Manual Cleanup (if needed)

If Terraform destroy fails, manually clean up these resources:

1. Empty S3 bucket before deletion
2. Remove EventBridge rule targets
3. Delete Lambda function
4. Remove IAM policies and roles
5. Delete VPC Lattice resources

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../service-mesh-cost-analytics-lattice-explorer.md)
2. Check AWS service documentation for specific components
3. Verify Terraform version compatibility
4. Review AWS provider documentation

## Contributing

When modifying this infrastructure:

1. Follow Terraform best practices
2. Update variable descriptions and validation
3. Add appropriate outputs for new resources
4. Update this README with configuration changes
5. Test thoroughly in a development environment

## License

This infrastructure code is provided as-is for educational and implementation purposes. Review and adapt according to your organization's security and compliance requirements.