# Infrastructure as Code for Application Monitoring with X-Ray Distributed Tracing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Application Monitoring with X-Ray Distributed Tracing".

## Solution Overview

This infrastructure deploys a comprehensive AWS X-Ray monitoring solution for distributed applications, including:

- **API Gateway** with X-Ray tracing enabled for request monitoring
- **Lambda Functions** instrumented with X-Ray SDK for distributed tracing
- **DynamoDB** with X-Ray tracing for database operation visibility
- **Custom Sampling Rules** for intelligent trace collection
- **Filter Groups** for organized trace analysis
- **CloudWatch Dashboard** for centralized monitoring
- **Automated Trace Analysis** with scheduled Lambda function
- **Performance Alerts** using CloudWatch Alarms

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - X-Ray service management
  - Lambda function creation and management
  - API Gateway administration
  - DynamoDB table operations
  - IAM role and policy management
  - CloudWatch dashboard and alarm configuration
  - EventBridge rule management
- For CDK implementations: Node.js 16+ (TypeScript) or Python 3.9+ (Python)
- For Terraform: Terraform 1.0+ installed

### Required IAM Permissions

Your AWS credentials need permissions for:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "xray:*",
        "lambda:*",
        "apigateway:*",
        "dynamodb:*",
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:DeleteRole",
        "cloudwatch:*",
        "events:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### Using CloudFormation (AWS)
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name xray-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-xray-monitoring

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name xray-monitoring-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name xray-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=my-xray-monitoring

# View outputs
cdk output
```

### Using CDK Python (AWS)
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy --parameters projectName=my-xray-monitoring

# View outputs
cdk output
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_name=my-xray-monitoring"

# Apply the configuration
terraform apply -var="project_name=my-xray-monitoring"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values
# or you can set environment variables:
export PROJECT_NAME="my-xray-monitoring"
export AWS_REGION="us-east-1"
./scripts/deploy.sh
```

## Configuration Options

### Environment Variables

All implementations support these configuration options:

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_NAME` | Unique identifier for resources | `xray-monitoring-demo` |
| `AWS_REGION` | AWS region for deployment | Current CLI region |
| `DDB_READ_CAPACITY` | DynamoDB read capacity units | `5` |
| `DDB_WRITE_CAPACITY` | DynamoDB write capacity units | `5` |
| `LAMBDA_TIMEOUT` | Lambda function timeout (seconds) | `30` |
| `SAMPLING_RATE` | X-Ray sampling rate for traces | `0.1` (10%) |

### Parameter Files

For CloudFormation and CDK, you can customize deployment using parameter files:

**CloudFormation Parameters** (`parameters.json`):
```json
[
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "my-xray-monitoring"
  },
  {
    "ParameterKey": "Environment",
    "ParameterValue": "production"
  }
]
```

**Terraform Variables** (`terraform.tfvars`):
```hcl
project_name = "my-xray-monitoring"
environment = "production"
aws_region = "us-west-2"
ddb_read_capacity = 10
ddb_write_capacity = 10
```

## Testing the Deployment

After deployment, test the X-Ray monitoring setup:

1. **Generate Test Traffic**:
   ```bash
   # Get API Gateway endpoint from outputs
   API_ENDPOINT=$(aws cloudformation describe-stacks \
       --stack-name xray-monitoring-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
       --output text)
   
   # Send test requests
   for i in {1..10}; do
       curl -X POST ${API_ENDPOINT}/orders \
           -H "Content-Type: application/json" \
           -d "{\"customerId\": \"customer-${i}\", \"productId\": \"product-${i}\", \"quantity\": ${i}}"
       sleep 1
   done
   ```

2. **View X-Ray Service Map**:
   - Open AWS X-Ray console
   - Navigate to Service Map
   - Verify services are appearing with trace data

3. **Check CloudWatch Dashboard**:
   - Open CloudWatch console
   - Navigate to Dashboards
   - View the created X-Ray monitoring dashboard

4. **Verify Trace Data**:
   ```bash
   # Get recent traces
   aws xray get-trace-summaries \
       --time-range-type TimeStamp \
       --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
       --filter-expression 'service("order-processor")'
   ```

## Monitoring and Observability

### Key Metrics to Monitor

1. **X-Ray Traces**:
   - Total traces received
   - Error trace percentage
   - High latency trace count
   - Service response times

2. **Lambda Performance**:
   - Function duration
   - Error rates
   - Throttle counts
   - Concurrent executions

3. **API Gateway**:
   - Request count
   - Error rates (4xx, 5xx)
   - Latency metrics
   - Cache hit rates

4. **DynamoDB**:
   - Read/write capacity utilization
   - Throttled requests
   - System errors
   - Item counts

### Accessing Monitoring Data

- **X-Ray Console**: View service maps, traces, and insights
- **CloudWatch Dashboard**: Centralized metrics view
- **CloudWatch Alarms**: Automated alerting on thresholds
- **X-Ray Insights**: AI-powered anomaly detection

## Cost Optimization

### X-Ray Pricing Considerations

- **Traces**: $5.00 per 1 million traces recorded
- **Trace Retrieval**: $0.50 per 1 million traces retrieved
- **Insights**: No additional charge

### Cost Optimization Strategies

1. **Sampling Rules**: Use custom sampling to reduce trace volume
2. **Filter Groups**: Focus analysis on critical traces
3. **Retention**: Configure appropriate trace retention periods
4. **Reserved Capacity**: Use DynamoDB reserved capacity for predictable workloads

## Security Considerations

### IAM Permissions

The deployment creates IAM roles with least-privilege access:

- Lambda execution role with X-Ray write permissions
- DynamoDB access limited to created table
- CloudWatch metrics and logs access

### Network Security

- API Gateway with CORS enabled
- Lambda functions in default VPC (no custom VPC required)
- DynamoDB with encryption at rest enabled

### Data Protection

- X-Ray traces may contain sensitive data - review sampling rules
- Enable VPC endpoints for private communication (optional)
- Use AWS KMS for additional encryption (configurable)

## Troubleshooting

### Common Issues

1. **No Traces Appearing**:
   - Verify X-Ray tracing is enabled on services
   - Check IAM permissions for X-Ray write access
   - Confirm sampling rules are not filtering all traces

2. **High Costs**:
   - Review sampling rates and adjust rules
   - Check for trace spam or high-volume endpoints
   - Monitor trace retrieval patterns

3. **Missing Service Dependencies**:
   - Ensure AWS SDK is patched for X-Ray in Lambda
   - Verify subsegment creation for downstream calls
   - Check service annotations and metadata

4. **Performance Issues**:
   - Monitor Lambda cold starts affecting traces
   - Check DynamoDB throttling
   - Review API Gateway timeout settings

### Debug Commands

```bash
# Check X-Ray service status
aws xray get-service-graph \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)

# Verify sampling rules
aws xray get-sampling-rules

# Check recent trace summaries
aws xray get-trace-summaries \
    --time-range-type TimeStamp \
    --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --max-items 10

# Test Lambda function directly
aws lambda invoke \
    --function-name ${PROJECT_NAME}-order-processor \
    --payload '{"body": "{\"customerId\": \"test\", \"productId\": \"test\", \"quantity\": 1}"}' \
    response.json
```

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name xray-monitoring-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name xray-monitoring-stack
```

### Using CDK (AWS)
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_name=my-xray-monitoring"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:
- X-Ray sampling rules and filter groups
- CloudWatch dashboards and alarms
- Lambda functions and layers
- DynamoDB tables
- IAM roles and policies
- API Gateway REST APIs

## Customization

### Adding Custom Sampling Rules

Modify sampling rules in your chosen IaC template:

```yaml
# CloudFormation example
CustomSamplingRule:
  Type: AWS::XRay::SamplingRule
  Properties:
    SamplingRule:
      RuleName: "custom-rule"
      Priority: 100
      FixedRate: 0.5
      ReservoirSize: 10
      ServiceName: "my-service"
      ServiceType: "*"
      Host: "*"
      HTTPMethod: "*"
      URLPath: "*"
      Version: 1
```

### Adding Custom Metrics

Extend the trace analyzer Lambda function to create custom metrics:

```python
# Example custom metric
cloudwatch.put_metric_data(
    Namespace='XRay/Custom',
    MetricData=[
        {
            'MetricName': 'BusinessTransactions',
            'Value': business_transaction_count,
            'Unit': 'Count',
            'Dimensions': [
                {
                    'Name': 'TransactionType',
                    'Value': 'OrderProcessing'
                }
            ]
        }
    ]
)
```

### Integrating with External Systems

- **Slack Notifications**: Add SNS topic for alarm notifications
- **PagerDuty Integration**: Configure CloudWatch alarm actions
- **Custom Dashboards**: Export metrics to external monitoring tools
- **Data Export**: Use X-Ray batch get traces for external analysis

## Best Practices

1. **Sampling Strategy**: Start with 10% sampling and adjust based on volume
2. **Annotations**: Use consistent annotation keys for filtering
3. **Metadata**: Include business context in trace metadata
4. **Error Handling**: Ensure X-Ray instrumentation doesn't affect application performance
5. **Testing**: Regularly test trace collection and analysis workflows

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS X-Ray documentation
4. Review CloudFormation/CDK/Terraform provider documentation

## Version Information

- **Recipe Version**: 1.1
- **IaC Templates**: Generated for recipe version 1.1
- **AWS CLI**: Requires v2.x
- **CDK**: Compatible with v2.x
- **Terraform**: Requires v1.0+