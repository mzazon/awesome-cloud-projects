# Infrastructure as Code for Implementing Distributed Tracing with X-Ray

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Distributed Tracing with X-Ray".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a distributed microservices architecture with comprehensive X-Ray tracing:

- **API Gateway**: REST API with X-Ray tracing enabled
- **Lambda Functions**: Order, payment, inventory, and notification services
- **EventBridge**: Custom event bus for service communication
- **X-Ray**: Distributed tracing and service map visualization
- **IAM Roles**: Least privilege permissions for all services

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - X-Ray service access
  - EventBridge management
  - Lambda function creation and execution
  - API Gateway management
  - IAM role and policy management
- For CDK implementations: Node.js 18+ or Python 3.9+
- For Terraform: Terraform v1.0+

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name distributed-tracing-xray-eventbridge \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=RandomSuffix,ParameterValue=$(openssl rand -hex 3)

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name distributed-tracing-xray-eventbridge

# Get API Gateway endpoint
aws cloudformation describe-stacks \
    --stack-name distributed-tracing-xray-eventbridge \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Deploy the stack
cdk deploy DistributedTracingXRayEventBridgeStack

# Get outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Deploy the stack
cdk deploy DistributedTracingXRayEventBridgeStack

# Get outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy infrastructure
terraform apply

# Get API Gateway endpoint
terraform output api_gateway_endpoint
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the API Gateway endpoint when complete
```

## Testing the Implementation

Once deployed, test the distributed tracing flow:

```bash
# Replace with your actual API Gateway endpoint
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Send a test request
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"productId": "12345", "quantity": 1}' \
    "${API_ENDPOINT}/orders/customer123"

# Wait 2-3 minutes for traces to appear in X-Ray
# Then view the service map in the AWS X-Ray console
```

## Monitoring and Observability

### X-Ray Service Map

Access the X-Ray console to view:
- Service dependencies and relationships
- Request latency and error rates
- Performance bottlenecks
- Trace timeline and annotations

### CloudWatch Integration

The implementation includes:
- Lambda function logs in CloudWatch
- API Gateway access logs
- EventBridge rule metrics
- X-Ray service metrics

### Trace Analysis

Use AWS CLI to analyze traces:

```bash
# Get recent trace summaries
aws xray get-trace-summaries \
    --time-range-type TimeRangeByStartTime \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)

# Get detailed trace data
TRACE_ID="your-trace-id"
aws xray batch-get-traces --trace-ids $TRACE_ID
```

## Configuration Options

### Environment Variables

The implementation supports these configuration options:

- `RANDOM_SUFFIX`: Unique identifier for resource names
- `EVENT_BUS_NAME`: Custom EventBridge bus name
- `API_GATEWAY_NAME`: API Gateway REST API name
- `LAMBDA_ROLE_NAME`: IAM role name for Lambda functions

### X-Ray Sampling Rules

Default sampling configuration:
- 1 request per second
- 5% of additional requests
- Custom rules can be added for specific services

### EventBridge Configuration

- Custom event bus for application isolation
- Event patterns for precise service routing
- Built-in retry and error handling

## Cost Optimization

### X-Ray Costs

- $5.00 per 1 million traces recorded
- $0.50 per 1 million traces retrieved
- Use sampling rules to control costs

### EventBridge Costs

- $1.00 per million custom events
- First 1 million events per month are free

### Lambda Costs

- Pay per request and execution time
- Free tier: 1 million requests per month

### API Gateway Costs

- $3.50 per million requests
- Free tier: 1 million requests per month

## Security Considerations

### IAM Permissions

- Least privilege access for all services
- Resource-based policies for cross-service access
- No hardcoded credentials

### Network Security

- VPC endpoints can be added for private communication
- API Gateway can be configured for private access
- Lambda functions support VPC configuration

### Data Protection

- X-Ray traces encrypted at rest
- Sensitive data excluded from trace annotations
- CloudWatch logs encrypted

## Troubleshooting

### Common Issues

1. **Missing Traces**: Verify X-Ray tracing is enabled on all services
2. **Permission Errors**: Check IAM roles and resource-based policies
3. **EventBridge Delivery Failures**: Verify Lambda function permissions
4. **API Gateway Errors**: Check Lambda integration configuration

### Debug Commands

```bash
# Check Lambda function status
aws lambda get-function --function-name your-function-name

# Verify EventBridge rules
aws events list-rules --event-bus-name your-event-bus

# Check X-Ray service statistics
aws xray get-service-graph \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name distributed-tracing-xray-eventbridge

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name distributed-tracing-xray-eventbridge
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy DistributedTracingXRayEventBridgeStack
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Customization

### Adding Additional Services

To extend the architecture:

1. Create new Lambda functions with X-Ray tracing
2. Add EventBridge rules for new event patterns
3. Update IAM permissions for new services
4. Configure appropriate event routing

### Modifying Sampling Rules

Customize X-Ray sampling in the implementation:

```yaml
# CloudFormation example
XRaySamplingRule:
  Type: AWS::XRay::SamplingRule
  Properties:
    SamplingRule:
      RuleName: HighValueTransactions
      ResourceARN: "*"
      ServiceName: payment-service
      HTTPMethod: "*"
      URLPath: "*"
      ReservoirSize: 2
      FixedRate: 0.1
```

### Environment-Specific Configuration

Use parameter files for different environments:

```bash
# Development environment
terraform apply -var-file="dev.tfvars"

# Production environment
terraform apply -var-file="prod.tfvars"
```

## Best Practices

### Performance Optimization

- Use Lambda provisioned concurrency for consistent performance
- Implement connection pooling for external services
- Configure appropriate timeout values

### Monitoring Strategy

- Set up CloudWatch alarms for key metrics
- Use X-Ray annotations for business-specific filtering
- Implement custom metrics for business KPIs

### Error Handling

- Configure dead letter queues for failed events
- Implement circuit breaker patterns
- Use exponential backoff for retries

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Examine CloudWatch logs for error details
4. Refer to the original recipe documentation

## Additional Resources

- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)