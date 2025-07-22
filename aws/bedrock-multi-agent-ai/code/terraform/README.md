# Multi-Agent AI Workflows with Amazon Bedrock - Terraform

This Terraform configuration deploys a comprehensive multi-agent AI workflow system using Amazon Bedrock, EventBridge, Lambda, and DynamoDB. The system implements a supervisor-collaborator pattern where specialized AI agents coordinate to handle complex business tasks.

## Architecture Overview

The deployed infrastructure includes:

- **4 Bedrock Agents**: 1 supervisor + 3 specialized agents (Finance, Support, Analytics)
- **EventBridge Custom Bus**: Event-driven coordination between agents
- **Lambda Coordinator**: Central orchestration function for workflow management
- **DynamoDB Table**: Persistent memory storage for agent interactions
- **API Gateway**: RESTful API for external system integration
- **CloudWatch Monitoring**: Comprehensive logging and metrics
- **KMS Encryption**: Optional encryption at rest for all supported resources

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.5 installed
3. **AWS Account** with Amazon Bedrock access enabled
4. **Bedrock Model Access** granted for Claude 3 models in your region
5. **IAM Permissions** for creating all required resources

### Required AWS Permissions

Your AWS credentials must have permissions for:
- Amazon Bedrock (agents, model invocation)
- AWS Lambda (functions, roles, permissions)
- Amazon EventBridge (buses, rules, targets)
- Amazon DynamoDB (tables, streams, indexes)
- Amazon API Gateway (APIs, deployments, stages)
- AWS IAM (roles, policies, attachments)
- Amazon CloudWatch (log groups, dashboards, metrics)
- AWS KMS (keys, aliases) - if encryption is enabled

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/multi-agent-ai-workflows-bedrock-agentcore/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Basic Configuration
aws_region    = "us-east-1"
environment   = "dev"
owner        = "your-team-name"
project_name = "my-multi-agent-system"

# Agent Configuration
supervisor_agent_name = "my-supervisor-agent"
finance_agent_name   = "my-finance-agent"
support_agent_name   = "my-support-agent"
analytics_agent_name = "my-analytics-agent"

# Bedrock Configuration
foundation_model       = "anthropic.claude-3-sonnet-20240229-v1:0"
agent_session_timeout  = 3600

# Lambda Configuration
coordinator_memory_size = 512
coordinator_timeout     = 300
lambda_runtime         = "python3.11"

# Storage Configuration
dynamodb_billing_mode    = "PAY_PER_REQUEST"
memory_retention_days    = 30

# Security Configuration
enable_resource_encryption = true
enable_xray_tracing       = true

# Monitoring Configuration
enable_enhanced_monitoring = true
log_retention_days        = 30

# Additional tags
additional_tags = {
  CostCenter = "AI-Platform"
  Project    = "Multi-Agent-Workflows"
}
```

### 4. Plan the Deployment

```bash
terraform plan
```

### 5. Deploy the Infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

### 6. Verify Deployment

After successful deployment, Terraform will output key resource information. Test the system:

```bash
# Test supervisor agent
aws bedrock-agent-runtime invoke-agent \
    --agent-id $(terraform output -raw supervisor_agent_id) \
    --agent-alias-id $(terraform output -raw supervisor_agent_alias_id) \
    --session-id "test-$(date +%s)" \
    --input-text "Help me analyze Q4 financial performance and customer satisfaction metrics"

# Send test event to EventBridge
aws events put-events \
    --entries '[{
        "Source": "multi-agent.test",
        "DetailType": "Test Event", 
        "Detail": "{\"test\": true}",
        "EventBusName": "'$(terraform output -raw eventbridge_bus_name)'"
    }]'

# Check agent memory table
aws dynamodb scan \
    --table-name $(terraform output -raw memory_table_name) \
    --limit 5
```

## Configuration Options

### Agent Configuration

- `foundation_model`: Choose from supported Claude models
- `agent_session_timeout`: Session timeout in seconds (600-28800)
- Agent names are customizable and will be suffixed with a unique identifier

### Performance Tuning

- `coordinator_memory_size`: Lambda memory allocation (128-10240 MB)
- `coordinator_timeout`: Lambda timeout (1-900 seconds)
- `dynamodb_billing_mode`: Choose between PAY_PER_REQUEST or PROVISIONED

### Security Options

- `enable_resource_encryption`: Enables KMS encryption for supported resources
- `enable_xray_tracing`: Enables AWS X-Ray distributed tracing
- `kms_key_deletion_window`: KMS key deletion window (7-30 days)

### Monitoring Configuration

- `enable_enhanced_monitoring`: Creates CloudWatch dashboard and custom metrics
- `log_retention_days`: CloudWatch log retention period
- `event_retention_days`: Dead letter queue message retention

## API Usage

The deployed API Gateway provides a REST endpoint for external integration:

### Invoke Multi-Agent Coordination

```bash
curl -X POST https://$(terraform output -raw api_gateway_invoke_url)/agents \
  -H "Content-Type: application/json" \
  -d '{
    "taskType": "multi_agent_coordination",
    "input": "I need a comprehensive business analysis including financial metrics, customer satisfaction data, and sales trends",
    "sessionId": "user-session-123"
  }'
```

### Direct Agent Invocation

```bash
# Financial analysis
curl -X POST https://$(terraform output -raw api_gateway_invoke_url)/agents \
  -H "Content-Type: application/json" \
  -d '{
    "taskType": "financial_analysis",
    "input": "Analyze Q4 revenue trends and profit margins",
    "sessionId": "finance-session-456"
  }'
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the monitoring dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=<your-region>#dashboards:name=<dashboard-name>
```

### Log Groups

- Agent logs: `/aws/bedrock/agents/multi-agent-<unique-id>`
- Coordinator logs: `/aws/lambda/<coordinator-function-name>`

### X-Ray Tracing

If enabled, view distributed traces in the AWS X-Ray console to analyze request flows across the multi-agent system.

## Cost Management

### Estimated Monthly Costs

The system costs vary based on usage patterns:

- **Bedrock Agents**: $50-200/month (based on invocations)
- **Lambda Functions**: $5-20/month (based on executions)
- **DynamoDB**: $10-50/month (based on capacity and storage)
- **EventBridge**: $1-10/month (based on event volume)
- **CloudWatch**: $5-25/month (logs, metrics, dashboards)
- **KMS**: $1/month per key (if encryption enabled)

**Total Estimated Range**: $70-300/month

### Cost Optimization Tips

1. **Use PAY_PER_REQUEST billing** for DynamoDB in development
2. **Adjust log retention periods** based on compliance requirements
3. **Monitor agent invocations** and optimize prompts for efficiency
4. **Set up billing alerts** in AWS Cost Explorer
5. **Use reserved capacity** for predictable workloads in production

## Troubleshooting

### Common Issues

#### Bedrock Access Denied
```bash
# Request model access in the AWS Console
aws bedrock list-foundation-models --region us-east-1
```

#### Agent Preparation Timeout
```bash
# Check agent status
aws bedrock-agent get-agent --agent-id <agent-id>

# Manually prepare agent if needed
aws bedrock-agent prepare-agent --agent-id <agent-id>
```

#### Lambda Function Timeout
- Increase `coordinator_timeout` variable
- Check CloudWatch logs for detailed error information

#### DynamoDB Throttling
- Switch to PAY_PER_REQUEST billing mode
- Or increase provisioned capacity

### Debug Commands

```bash
# Check agent status
terraform output | grep agent_id | while read -r line; do
    agent_id=$(echo $line | cut -d'"' -f4)
    aws bedrock-agent get-agent --agent-id $agent_id --query 'agent.agentStatus'
done

# View recent coordinator logs
aws logs tail $(terraform output -raw log_groups | jq -r '.coordinator') --since 30m

# Check EventBridge metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name MatchedEvents \
    --dimensions Name=EventBusName,Value=$(terraform output -raw eventbridge_bus_name) \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600
```

## Cleanup

To avoid ongoing charges, destroy the infrastructure when no longer needed:

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Note**: This will permanently delete all agents, data, and configuration. Ensure you have backups of any important data before destroying.

## Security Considerations

### Best Practices Implemented

- **Least Privilege IAM**: All roles follow minimum required permissions
- **VPC Isolation**: Resources are deployed in isolated network contexts where applicable
- **Encryption at Rest**: Optional KMS encryption for all supported services
- **Secure Communications**: All inter-service communication uses AWS internal networks
- **Access Logging**: Comprehensive audit trails in CloudWatch

### Additional Security Measures

1. **Enable AWS Config** for compliance monitoring
2. **Set up AWS GuardDuty** for threat detection
3. **Use AWS Secrets Manager** for sensitive configuration
4. **Implement API Gateway authorizers** for authentication
5. **Regular security assessments** of agent interactions

## Support and Contributing

For issues with this Terraform configuration:

1. Check the [troubleshooting section](#troubleshooting)
2. Review AWS service quotas and limits
3. Consult the original recipe documentation
4. Check AWS service health status

## License

This code is provided under the MIT License. See LICENSE file for details.