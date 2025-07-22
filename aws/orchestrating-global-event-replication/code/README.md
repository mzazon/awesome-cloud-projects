# Infrastructure as Code for Orchestrating Global Event Replication with EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Orchestrating Global Event Replication with EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon EventBridge (events:*)
  - AWS Lambda (lambda:*)
  - Amazon Route 53 (route53:*)
  - Amazon CloudWatch (cloudwatch:*, logs:*)
  - Amazon SNS (sns:*)
  - AWS IAM (iam:*)
- Access to three AWS regions (us-east-1, us-west-2, eu-west-1)
- For CDK: Node.js 16+ or Python 3.8+
- For Terraform: Terraform 1.0+
- Estimated cost: $50-100/month for production workloads

## Architecture Overview

This implementation creates a multi-region event replication system with:

- **Custom EventBridge buses** in three regions (us-east-1, us-west-2, eu-west-1)
- **Global endpoint** with automatic failover capabilities
- **Lambda functions** for event processing in each region
- **Cross-region event rules** for intelligent event routing
- **CloudWatch monitoring** with alarms and dashboards
- **Route 53 health checks** for endpoint monitoring
- **IAM roles** for secure cross-region access

## Quick Start

### Using CloudFormation

```bash
# Deploy to primary region (us-east-1)
aws cloudformation create-stack \
    --stack-name eventbridge-multi-region-primary \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production \
    --region us-east-1

# Deploy to secondary region (us-west-2)
aws cloudformation create-stack \
    --stack-name eventbridge-multi-region-secondary \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production \
                 ParameterKey=DeploymentType,ParameterValue=secondary \
    --region us-west-2

# Deploy to tertiary region (eu-west-1)
aws cloudformation create-stack \
    --stack-name eventbridge-multi-region-tertiary \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production \
                 ParameterKey=DeploymentType,ParameterValue=tertiary \
    --region eu-west-1
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install

# Configure regions
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2
export TERTIARY_REGION=eu-west-1

# Deploy to all regions
cdk deploy EventBridgeMultiRegionStack-Primary --region $PRIMARY_REGION
cdk deploy EventBridgeMultiRegionStack-Secondary --region $SECONDARY_REGION
cdk deploy EventBridgeMultiRegionStack-Tertiary --region $TERTIARY_REGION
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt

# Configure regions
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2
export TERTIARY_REGION=eu-west-1

# Deploy to all regions
cdk deploy EventBridgeMultiRegionStack-Primary --region $PRIMARY_REGION
cdk deploy EventBridgeMultiRegionStack-Secondary --region $SECONDARY_REGION
cdk deploy EventBridgeMultiRegionStack-Tertiary --region $TERTIARY_REGION
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts to configure regions and parameters
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Environment | production | Environment name for resource tagging |
| DeploymentType | primary | Deployment type (primary/secondary/tertiary) |
| EventBusName | global-events-bus | Name for custom EventBridge bus |
| LambdaTimeout | 30 | Lambda function timeout in seconds |
| EnableMonitoring | true | Enable CloudWatch monitoring and alarms |

### CDK Configuration

Configure the deployment through environment variables:

```bash
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2
export TERTIARY_REGION=eu-west-1
export ENVIRONMENT=production
export ENABLE_MONITORING=true
```

### Terraform Variables

Customize the deployment by creating a `terraform.tfvars` file:

```hcl
primary_region = "us-east-1"
secondary_region = "us-west-2"
tertiary_region = "eu-west-1"
environment = "production"
event_bus_name = "global-events-bus"
lambda_timeout = 30
enable_monitoring = true
enable_kms_encryption = true
```

## Testing the Deployment

### Send Test Events

```bash
# Set your global endpoint ARN
export GLOBAL_ENDPOINT_ARN="arn:aws:events:us-east-1:123456789012:endpoint/global-endpoint-abc123"

# Send test financial transaction event
aws events put-events \
    --entries '[{
        "Source": "finance.transactions",
        "DetailType": "Transaction Created",
        "Detail": "{\"transactionId\":\"tx-test-001\",\"amount\":\"1500.00\",\"currency\":\"USD\",\"priority\":\"high\"}"
    }]' \
    --endpoint-id ${GLOBAL_ENDPOINT_ARN} \
    --region us-east-1

# Send test user management event
aws events put-events \
    --entries '[{
        "Source": "user.management",
        "DetailType": "User Action",
        "Detail": "{\"userId\":\"user-456\",\"action\":\"login\",\"risk_level\":\"medium\"}"
    }]' \
    --endpoint-id ${GLOBAL_ENDPOINT_ARN} \
    --region us-east-1
```

### Verify Event Processing

```bash
# Check Lambda function logs in all regions
for region in us-east-1 us-west-2 eu-west-1; do
    echo "=== Checking logs in $region ==="
    aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/event-processor" \
        --region $region \
        --query 'logGroups[0].logGroupName' \
        --output text
done

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum \
    --region us-east-1
```

### Test Failover Scenarios

```bash
# Check global endpoint health
aws events describe-endpoint \
    --name global-endpoint-* \
    --region us-east-1 \
    --query 'State' \
    --output text

# Monitor Route 53 health check status
aws route53 get-health-check \
    --health-check-id <health-check-id> \
    --query 'HealthCheck.Config'
```

## Monitoring and Observability

### CloudWatch Dashboards

Access the multi-region monitoring dashboard:

1. Open CloudWatch console in us-east-1
2. Navigate to Dashboards
3. Open "EventBridge-MultiRegion-*" dashboard
4. Monitor metrics across all regions

### Key Metrics to Monitor

- **EventBridge Metrics**:
  - `SuccessfulInvocations`: Events processed successfully
  - `FailedInvocations`: Events that failed processing
  - `InvocationsCount`: Total event invocations

- **Lambda Metrics**:
  - `Invocations`: Function execution count
  - `Errors`: Function execution errors
  - `Duration`: Function execution time
  - `Throttles`: Function throttling events

- **Route 53 Health Check**:
  - `HealthCheckStatus`: Endpoint health status
  - `HealthCheckPercentHealthy`: Percentage of healthy checks

### Alarms Configuration

The deployment includes pre-configured alarms for:

- EventBridge rule failures (threshold: 5 failures in 10 minutes)
- Lambda function errors (threshold: 3 errors in 10 minutes)
- Route 53 health check failures
- Cross-region replication failures

## Security Features

### Encryption

- **EventBridge**: Uses AWS KMS encryption for event data at rest
- **Lambda**: Environment variables encrypted with AWS KMS
- **CloudWatch Logs**: Log groups encrypted with AWS KMS

### IAM Roles and Policies

- **EventBridge Cross-Region Role**: Least privilege access for cross-region event delivery
- **Lambda Execution Role**: Basic execution permissions plus CloudWatch logging
- **Route 53 Health Check Role**: Read-only access to EventBridge endpoints

### Network Security

- **VPC Endpoints**: Optional configuration for private network access
- **Security Groups**: Restrictive security groups for Lambda functions
- **Resource-Based Policies**: Event bus policies controlling access

## Troubleshooting

### Common Issues

1. **Cross-Region Replication Failures**:
   ```bash
   # Check IAM role permissions
   aws iam get-role-policy \
       --role-name eventbridge-cross-region-role \
       --policy-name EventBridgeCrossRegionPolicy
   ```

2. **Lambda Function Errors**:
   ```bash
   # Check function logs
   aws logs filter-log-events \
       --log-group-name /aws/lambda/event-processor-* \
       --start-time $(date -d '1 hour ago' +%s)000 \
       --filter-pattern "ERROR"
   ```

3. **Global Endpoint Issues**:
   ```bash
   # Check endpoint configuration
   aws events describe-endpoint \
       --name global-endpoint-* \
       --region us-east-1
   ```

### Performance Optimization

- **Lambda Concurrency**: Configure reserved concurrency for consistent performance
- **EventBridge Rules**: Use specific event patterns to reduce unnecessary processing
- **CloudWatch Logs**: Configure log retention to manage costs
- **KMS Keys**: Use regional KMS keys for optimal performance

## Cleanup

### Using CloudFormation

```bash
# Delete stacks in reverse order
aws cloudformation delete-stack \
    --stack-name eventbridge-multi-region-tertiary \
    --region eu-west-1

aws cloudformation delete-stack \
    --stack-name eventbridge-multi-region-secondary \
    --region us-west-2

aws cloudformation delete-stack \
    --stack-name eventbridge-multi-region-primary \
    --region us-east-1
```

### Using CDK

```bash
# Destroy stacks in reverse order
cdk destroy EventBridgeMultiRegionStack-Tertiary --region $TERTIARY_REGION
cdk destroy EventBridgeMultiRegionStack-Secondary --region $SECONDARY_REGION
cdk destroy EventBridgeMultiRegionStack-Primary --region $PRIMARY_REGION
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Advanced Configuration

### Custom Event Patterns

Modify event patterns for your specific use case:

```json
{
    "source": ["your.application"],
    "detail-type": ["Custom Event Type"],
    "detail": {
        "priority": ["high", "critical"],
        "region": ["us-east-1", "us-west-2", "eu-west-1"],
        "amount": [{"numeric": [">=", 1000]}]
    }
}
```

### Lambda Function Customization

Customize the Lambda function for your business logic:

```python
def process_business_event(source, detail_type, detail, region):
    """Implement your custom business logic here"""
    
    # Example: Database operations
    if source == "your.application":
        # Update database, send notifications, etc.
        pass
    
    # Example: Integration with other services
    if detail_type == "Custom Event Type":
        # Call external APIs, update cache, etc.
        pass
```

### Multi-Account Deployment

For multi-account deployments, update IAM roles and policies:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::ACCOUNT-B:root"
            },
            "Action": "events:PutEvents",
            "Resource": "arn:aws:events:*:ACCOUNT-A:event-bus/*"
        }
    ]
}
```

## Cost Optimization

### Estimated Costs

- **EventBridge**: $1.00 per million events
- **Lambda**: $0.20 per million requests + compute time
- **Route 53**: $0.50 per health check per month
- **CloudWatch**: $0.30 per dashboard per month + log storage

### Cost Optimization Strategies

1. **Event Filtering**: Use specific event patterns to reduce unnecessary processing
2. **Lambda Optimization**: Right-size memory allocation and timeout settings
3. **Log Retention**: Configure appropriate log retention periods
4. **Regional Deployment**: Deploy only to required regions

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../multi-region-event-replication-eventbridge.md)
- [AWS EventBridge documentation](https://docs.aws.amazon.com/eventbridge/)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
- [AWS Route 53 documentation](https://docs.aws.amazon.com/route53/)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment
2. Validate security configurations
3. Update documentation as needed
4. Follow AWS best practices for IaC

## License

This infrastructure code is provided as-is for educational and implementation purposes. Please review and modify according to your organization's security and compliance requirements.