# Infrastructure as Code for Performance Monitoring AI Agents with AgentCore and CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Performance Monitoring AI Agents with AgentCore and CloudWatch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Bedrock AgentCore
  - Amazon CloudWatch (Logs, Metrics, Alarms, Dashboards)
  - AWS Lambda
  - Amazon S3
  - AWS IAM
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Estimated cost: $15-25 per month for monitoring stack (excluding agent compute costs)

> **Note**: AWS Bedrock AgentCore is currently in preview and available at no charge during the preview period. Standard AWS pricing applies to CloudWatch, Lambda, and S3 services.

## Architecture Overview

This solution deploys a comprehensive monitoring system that includes:

- **AI Agent Layer**: Bedrock AgentCore Agent with Memory and Gateway components
- **Monitoring & Observability**: OpenTelemetry SDK integration with CloudWatch Logs and Metrics
- **Alerting & Automation**: CloudWatch Alarms triggering Lambda-based performance optimization
- **Storage & Reporting**: S3 storage for performance reports with Athena analytics capability

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the monitoring infrastructure
aws cloudformation create-stack \
    --stack-name agentcore-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AgentName,ParameterValue=my-ai-agent \
                 ParameterKey=Environment,ParameterValue=production \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name agentcore-monitoring-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name agentcore-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy AgentCoreMonitoringStack \
    --parameters agentName=my-ai-agent \
    --parameters environment=production

# View deployed resources
cdk list

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name AgentCoreMonitoringStack \
    --query 'Stacks[0].Outputs'
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy AgentCoreMonitoringStack \
    --parameters agentName=my-ai-agent \
    --parameters environment=production

# View deployed resources
cdk list

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name AgentCoreMonitoringStack \
    --query 'Stacks[0].Outputs'
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="agent_name=my-ai-agent" \
    -var="environment=production" \
    -var="aws_region=us-east-1"

# Apply the configuration
terraform apply \
    -var="agent_name=my-ai-agent" \
    -var="environment=production" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export AGENT_NAME=my-ai-agent
export ENVIRONMENT=production
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
aws cloudwatch describe-alarms --alarm-names "AgentCore-HighLatency-*"
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `agent_name` | Name for the AgentCore agent | `ai-agent` | Yes |
| `environment` | Deployment environment | `development` | No |
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `log_retention_days` | CloudWatch log retention period | `30` | No |
| `lambda_timeout` | Lambda function timeout (seconds) | `60` | No |
| `lambda_memory_size` | Lambda function memory (MB) | `256` | No |
| `alarm_evaluation_periods` | CloudWatch alarm evaluation periods | `2` | No |
| `latency_threshold_ms` | High latency alarm threshold | `30000` | No |
| `error_threshold` | System error alarm threshold | `5` | No |
| `throttle_threshold` | Throttling alarm threshold | `10` | No |

### CloudFormation Parameters

Additional parameters specific to CloudFormation deployment:

```yaml
Parameters:
  AgentName:
    Type: String
    Default: ai-agent
    Description: Name for the AgentCore agent
  
  Environment:
    Type: String
    Default: development
    AllowedValues: [development, staging, production]
    Description: Deployment environment
  
  EnableDetailedMonitoring:
    Type: String
    Default: 'true'
    AllowedValues: ['true', 'false']
    Description: Enable detailed CloudWatch monitoring
```

### CDK Context Values

For CDK deployments, you can set context values in `cdk.json`:

```json
{
  "context": {
    "agent_name": "my-ai-agent",
    "environment": "production",
    "log_retention_days": 30,
    "enable_detailed_monitoring": true
  }
}
```

### Terraform Variables

Customize deployment through `terraform.tfvars`:

```hcl
agent_name = "my-ai-agent"
environment = "production"
aws_region = "us-east-1"
log_retention_days = 30
lambda_timeout = 60
lambda_memory_size = 256
```

## Post-Deployment Verification

### 1. Verify CloudWatch Dashboard

```bash
# Get dashboard URL
aws cloudwatch get-dashboard \
    --dashboard-name "AgentCore-Performance-${RANDOM_SUFFIX}" \
    --query 'DashboardBody' --output text

# Access dashboard via AWS Console
echo "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=AgentCore-Performance-${RANDOM_SUFFIX}"
```

### 2. Test CloudWatch Alarms

```bash
# List created alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "AgentCore-" \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table

# Test alarm functionality with metric data
aws cloudwatch put-metric-data \
    --namespace AWS/BedrockAgentCore \
    --metric-data MetricName=Latency,Value=35000,Unit=Milliseconds,Dimensions=[{Name=AgentId,Value=${AGENT_NAME}}]
```

### 3. Verify Lambda Function

```bash
# Test Lambda function
aws lambda invoke \
    --function-name "agent-performance-optimizer-${RANDOM_SUFFIX}" \
    --payload '{"AlarmName":"TestAlarm","AlarmDescription":"Test alarm","NewStateValue":"ALARM"}' \
    response.json

# Check response
cat response.json
```

### 4. Validate S3 Bucket

```bash
# List S3 bucket contents
aws s3 ls s3://agent-monitoring-data-${RANDOM_SUFFIX}/ --recursive

# Check bucket encryption
aws s3api get-bucket-encryption \
    --bucket agent-monitoring-data-${RANDOM_SUFFIX}
```

## Monitoring and Alerting

### Available Metrics

The solution monitors these key metrics:

- **Latency**: Agent response time in milliseconds
- **Invocations**: Number of agent invocations
- **SessionCount**: Active agent sessions
- **UserErrors**: User-generated errors
- **SystemErrors**: System-level errors
- **Throttles**: Rate limiting occurrences

### Custom Metrics

Additional custom metrics are collected through log filters:

- **AgentResponseTime**: Custom response time measurements
- **ConversationQuality**: Quality scores from agent interactions
- **BusinessOutcomeSuccess**: Business outcome tracking

### Alarm Thresholds

| Alarm | Threshold | Evaluation Periods | Description |
|-------|-----------|-------------------|-------------|
| High Latency | 30 seconds | 2 | Alert when average latency exceeds 30 seconds |
| System Errors | 5 errors | 1 | Alert when system errors exceed 5 in 5 minutes |
| High Throttles | 10 throttles | 2 | Alert when throttling occurs frequently |

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure the deployment role has sufficient permissions for all services
2. **Bedrock Access**: Verify Bedrock AgentCore is available in your region
3. **Lambda Timeouts**: Increase timeout if performance analysis takes longer than expected
4. **Log Group Creation**: Verify log groups are created with proper retention settings

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name agentcore-monitoring-stack

# View Lambda logs
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/agent-performance-optimizer-${RANDOM_SUFFIX}"

# Check alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name "AgentCore-HighLatency-${RANDOM_SUFFIX}"
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name agentcore-monitoring-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name agentcore-monitoring-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy AgentCoreMonitoringStack

# Confirm deletion
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="agent_name=my-ai-agent" \
    -var="environment=production" \
    -var="aws_region=us-east-1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
aws cloudwatch describe-alarms --alarm-name-prefix "AgentCore-"
aws s3 ls | grep agent-monitoring-data
```

## Cost Optimization

### Estimated Monthly Costs

- **CloudWatch Logs**: $0.50-$2.00 (based on log volume)
- **CloudWatch Metrics**: $0.30-$1.00 (custom metrics)
- **CloudWatch Alarms**: $0.30 (3 alarms)
- **Lambda**: $0.20-$1.00 (based on invocations)
- **S3 Storage**: $0.50-$2.00 (based on report volume)

### Cost Optimization Tips

1. **Log Retention**: Adjust log retention periods based on compliance requirements
2. **Metric Frequency**: Reduce custom metric frequency for non-critical metrics
3. **S3 Lifecycle**: Implement S3 lifecycle policies for older performance reports
4. **Lambda Memory**: Optimize Lambda memory allocation based on actual usage

## Security Considerations

### IAM Roles and Policies

- **Principle of Least Privilege**: All IAM roles follow minimal permission requirements
- **Service-Linked Roles**: Uses AWS service-linked roles where possible
- **Cross-Service Access**: Secure cross-service communication through IAM policies

### Data Protection

- **Encryption at Rest**: S3 bucket uses AES-256 encryption
- **Encryption in Transit**: All API communications use TLS 1.2+
- **Log Data**: CloudWatch Logs are encrypted using AWS managed keys

### Network Security

- **VPC Integration**: Can be deployed within existing VPC for network isolation
- **Security Groups**: Minimal required access for Lambda functions
- **Resource-Based Policies**: S3 bucket policies restrict access to authorized services only

## Support

For issues with this infrastructure code, refer to:

- [Original Recipe Documentation](../performance-monitoring-agentcore-cloudwatch.md)
- [AWS Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/)
- [AWS CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)

## Contributing

When modifying this infrastructure code:

1. Test all changes in a development environment
2. Update parameter documentation
3. Verify security best practices
4. Update cost estimates if resources change
5. Test cleanup procedures thoroughly

## License

This infrastructure code is provided as-is for educational and reference purposes. Ensure compliance with your organization's policies before deploying to production environments.