# Interactive Data Analytics with Bedrock AgentCore Code Interpreter - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying an interactive data analytics system using AWS Bedrock AgentCore Code Interpreter. The solution enables users to perform complex data analysis through natural language queries, automatically generating and executing Python code in secure, sandboxed environments.

## Architecture Overview

The infrastructure includes:

- **S3 Buckets**: Secure storage for raw data and analysis results with encryption and lifecycle policies
- **Bedrock AgentCore Code Interpreter**: AI-powered code execution environment for data analysis
- **Lambda Function**: Serverless orchestration layer for coordinating analytics workflows
- **API Gateway** (Optional): RESTful API for external access to analytics capabilities
- **CloudWatch**: Comprehensive monitoring, logging, and alerting
- **SQS Dead Letter Queue**: Error handling and recovery mechanisms
- **IAM Roles & Policies**: Least privilege security with fine-grained access controls

## Prerequisites

### AWS Requirements
- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Bedrock (including AgentCore preview access)
  - S3, Lambda, IAM, CloudWatch, SQS
  - API Gateway (if enabled)
- Access to Bedrock AgentCore Code Interpreter (preview feature)

### Tool Requirements
- Terraform >= 1.6
- jq (for JSON processing in provisioners)
- Appropriate AWS permissions for resource creation

### Service Quotas
- Ensure sufficient Lambda concurrency limits
- Verify Bedrock service quotas for your region
- Check S3 bucket limits if deploying multiple environments

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd aws/interactive-data-analytics-bedrock-codeinterpreter/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Review and Customize Variables
```bash
# Copy example variables (optional)
cp terraform.tfvars.example terraform.tfvars

# Edit variables as needed
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

### 6. Test the System
```bash
# Use the test command from outputs
terraform output test_lambda_command
```

## Configuration

### Required Variables
The following variables are required for deployment:

```hcl
# Example terraform.tfvars
environment = "dev"
project_name = "analytics"
aws_region = "us-east-1"
```

### Important Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `"dev"` | Environment name (dev, staging, prod) |
| `project_name` | `"analytics"` | Project name for resource naming |
| `lambda_timeout` | `300` | Lambda function timeout (30-900 seconds) |
| `lambda_memory_size` | `512` | Lambda memory allocation (128-10240 MB) |
| `enable_api_gateway` | `true` | Create API Gateway for external access |
| `enable_xray_tracing` | `false` | Enable X-Ray tracing for debugging |
| `cloudwatch_log_retention_days` | `30` | Log retention period |

### Advanced Configuration

```hcl
# Performance optimization
lambda_reserved_concurrency = 10
lambda_memory_size = 1024

# Cost optimization
s3_lifecycle_transition_days = 30
s3_glacier_transition_days = 90
s3_results_expiration_days = 365

# Security
enable_detailed_monitoring = true
enable_xray_tracing = true

# API Gateway throttling
api_gateway_throttle_rate = 100
api_gateway_throttle_burst = 200
```

## Usage Examples

### 1. Basic Analytics Query via Lambda
```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"query": "Analyze sales data and show trends by region"}' \
  --cli-binary-format raw-in-base64-out \
  response.json
```

### 2. API Gateway Request (if enabled)
```bash
curl -X POST $(terraform output -raw api_gateway_invoke_url) \
  -H "Content-Type: application/json" \
  -d '{"query": "Calculate total revenue by product category"}'
```

### 3. Upload Custom Dataset
```bash
aws s3 cp your_data.csv s3://$(terraform output -raw s3_bucket_raw_data)/datasets/
```

### 4. View Analysis Results
```bash
aws s3 ls s3://$(terraform output -raw s3_bucket_results)/analysis_results/ --recursive
```

## Monitoring and Observability

### CloudWatch Dashboard
Access the pre-built dashboard:
```bash
open $(terraform output -raw cloudwatch_dashboard_url)
```

### Key Metrics to Monitor
- **ExecutionCount**: Number of successful analyses
- **ExecutionErrors**: Failed analysis attempts
- **Lambda Duration**: Function execution time
- **Lambda Errors**: Lambda function failures

### Log Analysis
```bash
# View Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# View Code Interpreter logs
aws logs tail $(terraform output -raw code_interpreter_log_group_name) --follow
```

### CloudWatch Alarms
The deployment includes pre-configured alarms for:
- Execution errors (threshold: 3 errors in 2 evaluation periods)
- Lambda duration (threshold: 4 minutes)
- Lambda errors (threshold: 3 errors in 2 evaluation periods)

## Security Considerations

### IAM Policies
- Follows least privilege principle
- Separate policies for different service access
- No wildcard permissions on sensitive resources

### Data Protection
- S3 buckets with server-side encryption (AES256)
- Private bucket access (no public access)
- VPC endpoints can be added for additional security

### Network Security
- Code Interpreter uses PUBLIC network mode (can be customized)
- API Gateway with throttling limits
- CloudWatch monitoring for security events

### Access Control
- IAM roles for service-to-service communication
- No hardcoded credentials in code
- Temporary session management for Code Interpreter

## Troubleshooting

### Common Issues

#### 1. Bedrock AgentCore Not Available
```bash
# Check if AgentCore is available in your region
aws bedrock-agentcore list-code-interpreters --region us-east-1
```

**Solution**: Ensure you have access to Bedrock AgentCore preview and use a supported region.

#### 2. Lambda Timeout
```bash
# Check CloudWatch logs for timeout errors
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name)
```

**Solution**: Increase `lambda_timeout` variable or optimize your analysis code.

#### 3. Permission Errors
```bash
# Verify IAM role permissions
aws iam simulate-principal-policy \
  --policy-source-arn $(terraform output -raw execution_role_arn) \
  --action-names bedrock:InvokeModel \
  --resource-arns "*"
```

**Solution**: Review IAM policies and ensure all required permissions are granted.

#### 4. Code Interpreter Creation Failed
```bash
# Check the output file for errors
cat code_interpreter_output.json
```

**Solution**: Verify execution role ARN and region support for AgentCore.

### Debug Mode
Enable detailed logging:
```hcl
enable_detailed_monitoring = true
enable_xray_tracing = true
```

## Cost Optimization

### Estimated Monthly Costs
Based on moderate usage (from terraform outputs):
- Lambda executions: ~$5-15
- Bedrock inference: $10-30
- S3 storage: $1-5
- CloudWatch logs: $1-3
- API Gateway: $3-10 (if enabled)
- **Total: $20-65/month**

### Cost Reduction Strategies

1. **Adjust Lambda Configuration**
   ```hcl
   lambda_memory_size = 256  # Reduce if sufficient
   lambda_reserved_concurrency = 5  # Lower for dev environments
   ```

2. **Optimize S3 Lifecycle**
   ```hcl
   s3_lifecycle_transition_days = 7   # Faster transition to IA
   s3_glacier_transition_days = 30    # Faster archival
   s3_results_expiration_days = 90    # Shorter retention
   ```

3. **Reduce Log Retention**
   ```hcl
   cloudwatch_log_retention_days = 7  # For development
   ```

4. **Disable API Gateway for Development**
   ```hcl
   enable_api_gateway = false
   ```

## Maintenance

### Regular Tasks

1. **Monitor Costs**
   ```bash
   aws ce get-cost-and-usage \
     --time-period Start=2024-01-01,End=2024-01-31 \
     --granularity MONTHLY \
     --metrics BlendedCost
   ```

2. **Review Logs**
   ```bash
   # Check for errors in the last 24 hours
   aws logs filter-log-events \
     --log-group-name /aws/lambda/$(terraform output -raw lambda_function_name) \
     --start-time $(date -d '24 hours ago' +%s)000 \
     --filter-pattern "ERROR"
   ```

3. **Update Dependencies**
   ```bash
   # Check for Terraform provider updates
   terraform init -upgrade
   ```

### Backup and Recovery

#### State File Backup
```bash
# Backup Terraform state
cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d)
```

#### S3 Data Backup
Data is automatically protected through:
- S3 versioning (enabled by default)
- Cross-region replication (can be added)
- AWS Backup integration (can be configured)

## Cleanup

### Complete Infrastructure Removal
```bash
terraform destroy
```

### Selective Resource Removal
```bash
# Remove specific resources
terraform destroy -target=aws_api_gateway_rest_api.analytics
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining Code Interpreter manually
aws bedrock-agentcore list-code-interpreters
aws bedrock-agentcore delete-code-interpreter --code-interpreter-identifier <id>
```

## Advanced Customization

### Adding Custom Analytics Libraries
Modify the Lambda function template to include additional Python packages:

```python
# In lambda_function.py.tpl, add to analysis_code:
import scikit-learn
import plotly
# ... your custom libraries
```

### Multi-Region Deployment
```hcl
# Deploy to multiple regions
module "analytics_us_east_1" {
  source = "./modules/analytics"
  aws_region = "us-east-1"
  # ... other variables
}

module "analytics_eu_west_1" {
  source = "./modules/analytics"
  aws_region = "eu-west-1"
  # ... other variables
}
```

### Integration with Existing Infrastructure
```hcl
# Use existing VPC
data "aws_vpc" "existing" {
  tags = {
    Name = "my-vpc"
  }
}

# Use existing subnets for Lambda
data "aws_subnets" "existing" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}
```

## Support and Contributing

### Getting Help
1. Check CloudWatch logs for error details
2. Review AWS service health dashboard
3. Consult AWS Bedrock documentation
4. Use AWS Support (if applicable)

### Feature Requests
To request new features or report issues:
1. Check existing documentation
2. Review Terraform AWS provider changelog
3. Submit detailed feature requests with use cases

### Version History
- v1.0: Initial release with core analytics functionality
- v1.1: Added API Gateway integration and enhanced monitoring
- v1.2: Improved error handling and cost optimization features

---

**Note**: This implementation uses AWS CLI provisioners for Bedrock AgentCore Code Interpreter due to limited Terraform resource support for this preview service. As the service becomes generally available, the implementation will be updated to use native Terraform resources.