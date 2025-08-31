# Infrastructure as Code for Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business

This directory contains comprehensive Terraform Infrastructure as Code (IaC) for deploying a production-ready multi-agent knowledge management system using AWS Bedrock AgentCore and Q Business.

## Architecture Overview

The solution implements a supervisor-collaborator pattern with:
- **Supervisor Agent**: Orchestrates query routing and response synthesis
- **Specialized Agents**: Finance, HR, and Technical domain experts
- **Knowledge Storage**: S3 buckets with domain-specific documents
- **Enterprise Search**: Q Business for intelligent knowledge retrieval
- **Session Management**: DynamoDB for conversation context
- **API Gateway**: Secure, scalable external interface

## Prerequisites

### Required Tools
- [Terraform](https://terraform.io/) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) v2 configured with appropriate credentials
- [jq](https://stedolan.github.io/jq/) for JSON processing (optional, for testing)

### Required Permissions
Your AWS credentials must have permissions for:
- IAM role and policy management
- Lambda function deployment and configuration
- S3 bucket creation and management
- DynamoDB table operations
- API Gateway configuration
- CloudWatch log group management
- Q Business application setup (manual step)

### Cost Considerations
- **Development/Testing**: $20-50/month
- **Production**: $100-300/month (varies by usage)
- Key cost factors: Lambda invocations, API Gateway requests, DynamoDB operations, S3 storage

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd aws/multi-agent-knowledge-management-agentcore-q/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Review and Customize Variables
```bash
# Copy example variables (optional)
cp terraform.tfvars.example terraform.tfvars

# Edit variables to match your requirements
nano terraform.tfvars
```

### 4. Plan Deployment
```bash
terraform plan -out=deployment.tfplan
```

### 5. Deploy Infrastructure
```bash
terraform apply deployment.tfplan
```

### 6. Manual Q Business Configuration
After Terraform deployment, manually configure Q Business:

1. Navigate to the [Q Business Console](https://console.aws.amazon.com/qbusiness/)
2. Create a new application using the outputs from Terraform:
   ```bash
   terraform output q_business_setup_info
   ```
3. Configure data sources pointing to the created S3 buckets
4. Start data source synchronization
5. Update Lambda environment variables with the Q Business application ID

## Configuration Options

### Essential Variables

Create a `terraform.tfvars` file with your customizations:

```hcl
# Basic Configuration
aws_region = "us-east-1"
project_name = "my-multi-agent-km"
environment = "dev"

# Lambda Configuration
lambda_timeout = 60
lambda_memory_size = 512

# API Gateway Throttling
api_throttle_burst_limit = 1000
api_throttle_rate_limit = 500

# Security Settings
enable_versioning = true
enable_encryption = true

# Session Management
session_ttl_hours = 24
```

### Advanced Configuration

```hcl
# Knowledge Domain Customization
knowledge_domains = {
  finance = {
    display_name = "Finance Knowledge Base"
    description = "Financial policies and procedures"
    metadata_prefix = "finance/"
  }
  hr = {
    display_name = "Human Resources"
    description = "Employee policies and benefits"
    metadata_prefix = "hr/"
  }
  technical = {
    display_name = "Technical Documentation"
    description = "Development and system procedures"
    metadata_prefix = "tech/"
  }
  # Add custom domains as needed
}

# Agent-Specific Settings
agent_configurations = {
  supervisor = {
    display_name = "Supervisor Agent"
    description = "Multi-agent coordinator"
    memory_size = 512
    timeout = 60
  }
  # Customize individual agent settings
}

# CORS Configuration
cors_allowed_origins = ["https://yourdomain.com"]
cors_allowed_methods = ["GET", "POST", "OPTIONS"]
```

## Post-Deployment Setup

### 1. Q Business Configuration
```bash
# Get configuration details
terraform output q_business_setup_info

# Manual steps required:
# 1. Create Q Business application
# 2. Configure data sources
# 3. Start synchronization
# 4. Update Lambda environment variables
```

### 2. Update Lambda Functions with Q Business App ID
```bash
# After creating Q Business application, update the environment variables
aws lambda update-function-configuration \
  --function-name $(terraform output -raw finance_agent_function_name) \
  --environment Variables="{Q_APP_ID=your-q-business-app-id,DOMAIN=finance,PROJECT_NAME=$(terraform output -json deployment_info | jq -r '.value.project_name'),ENVIRONMENT=$(terraform output -json deployment_info | jq -r '.value.environment')}"

# Repeat for hr and technical agents
aws lambda update-function-configuration \
  --function-name $(terraform output -raw hr_agent_function_name) \
  --environment Variables="{Q_APP_ID=your-q-business-app-id,DOMAIN=hr,PROJECT_NAME=$(terraform output -json deployment_info | jq -r '.value.project_name'),ENVIRONMENT=$(terraform output -json deployment_info | jq -r '.value.environment')}"

aws lambda update-function-configuration \
  --function-name $(terraform output -raw technical_agent_function_name) \
  --environment Variables="{Q_APP_ID=your-q-business-app-id,DOMAIN=technical,PROJECT_NAME=$(terraform output -json deployment_info | jq -r '.value.project_name'),ENVIRONMENT=$(terraform output -json deployment_info | jq -r '.value.environment')}"
```

### 3. Upload Additional Knowledge Documents
```bash
# Upload to finance bucket
aws s3 cp my-finance-docs/ s3://$(terraform output -raw finance_bucket_name)/ --recursive

# Upload to HR bucket
aws s3 cp my-hr-docs/ s3://$(terraform output -raw hr_bucket_name)/ --recursive

# Upload to technical bucket
aws s3 cp my-tech-docs/ s3://$(terraform output -raw technical_bucket_name)/ --recursive
```

## Testing and Validation

### 1. Health Check
```bash
# Test API health
curl -X GET $(terraform output -raw api_health_check_url)
```

### 2. Simple Query Test
```bash
# Test basic query
curl -X POST $(terraform output -raw api_query_url) \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the expense approval process?",
    "sessionId": "test-session-001"
  }'
```

### 3. Multi-Domain Query Test
```bash
# Test complex query requiring multiple agents
curl -X POST $(terraform output -raw api_query_url) \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the budget approval process for international travel expenses and how does it relate to employee performance reviews?",
    "sessionId": "test-session-002"
  }'
```

### 4. Lambda Function Status
```bash
# Check all Lambda functions
terraform output -json all_agent_function_names | jq -r '.value[]' | while read func; do
  echo "Checking $func:"
  aws lambda get-function --function-name $func --query 'Configuration.State' --output text
done
```

### 5. Session Persistence Test
```bash
# Test follow-up query in same session
curl -X POST $(terraform output -raw api_query_url) \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Can you provide more details about the approval timeframes mentioned earlier?",
    "sessionId": "test-session-001"
  }'
```

## Monitoring and Troubleshooting

### CloudWatch Logs
```bash
# View supervisor agent logs
aws logs tail $(terraform output -json cloudwatch_log_groups | jq -r '.value.supervisor_agent') --follow

# View API Gateway logs
aws logs tail $(terraform output -json cloudwatch_log_groups | jq -r '.value.api_gateway') --follow
```

### Common Issues and Solutions

1. **Q Business Integration Errors**
   - Ensure Q Business application is created and configured
   - Verify Lambda environment variables contain correct App ID
   - Check IAM permissions for Q Business access

2. **Agent Invocation Failures**
   - Verify Lambda function names match expected pattern
   - Check IAM permissions for cross-Lambda invocation
   - Review CloudWatch logs for specific error messages

3. **API Gateway CORS Issues**
   - Verify CORS configuration in variables
   - Check that preflight OPTIONS requests are handled
   - Confirm allowed origins match your application domain

4. **Session Management Problems**
   - Verify DynamoDB table exists and is accessible
   - Check TTL configuration for automatic cleanup
   - Review session storage logic in supervisor agent

### Performance Optimization

1. **Lambda Optimization**
   ```bash
   # Increase memory for better performance
   terraform apply -var="lambda_memory_size=1024"
   ```

2. **API Gateway Caching**
   ```hcl
   # Add to variables for production
   enable_api_caching = true
   cache_ttl_seconds = 300
   ```

3. **DynamoDB Performance**
   ```hcl
   # Switch to provisioned billing for predictable workloads
   dynamodb_billing_mode = "PROVISIONED"
   read_capacity = 5
   write_capacity = 5
   ```

## Security Best Practices

### 1. IAM Least Privilege
- Review and customize IAM policies
- Remove unnecessary permissions
- Use resource-specific ARNs where possible

### 2. API Security
```hcl
# Add API Gateway authorization
api_authorization_type = "AWS_IAM"
# Or implement custom authorizers
```

### 3. Data Encryption
- S3 server-side encryption is enabled by default
- DynamoDB encryption at rest is configurable
- Consider AWS KMS for advanced key management

### 4. Network Security
```hcl
# Deploy in VPC for additional isolation
vpc_enabled = true
private_subnets = ["subnet-xxx", "subnet-yyy"]
```

## Scaling for Production

### 1. Multi-Region Deployment
```hcl
# Configure multiple regions
provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

# Replicate infrastructure across regions
```

### 2. High Availability
- Deploy across multiple Availability Zones
- Implement health checks and auto-recovery
- Consider Lambda reserved concurrency for critical functions

### 3. Monitoring and Alerting
```hcl
# Add CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "lambda-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors lambda error rate"
}
```

## Cleanup

### Complete Infrastructure Removal
```bash
# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Selective Cleanup
```bash
# Remove specific resources
terraform destroy -target=aws_lambda_function.supervisor_agent
```

### Manual Cleanup Required
- Q Business applications (if created manually)
- CloudWatch logs (optional, for data retention)
- S3 bucket contents (if versioning disabled)

## Cost Management

### Monitor Costs
```bash
# Check current month costs by service
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

### Cost Optimization Tips
1. **Lambda**: Use ARM-based Graviton2 processors
2. **DynamoDB**: Enable auto-scaling for variable workloads
3. **S3**: Implement lifecycle policies for automatic archival
4. **API Gateway**: Use caching to reduce backend calls
5. **CloudWatch**: Set appropriate log retention periods

## Support and Maintenance

### Regular Updates
- Monitor AWS service announcements for new features
- Update Terraform provider versions regularly
- Review and update IAM policies as services evolve

### Backup Strategy
- S3 bucket versioning provides document history
- DynamoDB point-in-time recovery for session data
- Export Terraform state for disaster recovery

### Documentation
- Maintain custom documentation for business-specific configurations
- Document any manual configuration steps
- Keep runbooks for common operational procedures

## Contributing

When customizing this infrastructure:
1. Test changes in development environment first
2. Use Terraform workspaces for environment isolation
3. Implement proper CI/CD for infrastructure changes
4. Document any custom modifications

## License

This infrastructure code is provided as part of the AWS recipe collection. See the main repository for license information.