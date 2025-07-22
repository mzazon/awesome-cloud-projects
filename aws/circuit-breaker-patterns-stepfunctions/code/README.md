# Infrastructure as Code for Circuit Breaker Patterns with Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Circuit Breaker Patterns with Step Functions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a resilient circuit breaker pattern using:

- **AWS Step Functions**: Orchestrates circuit breaker logic and service routing
- **AWS Lambda**: Provides downstream service simulation, fallback responses, and health checks
- **Amazon DynamoDB**: Maintains circuit breaker state persistence across executions
- **Amazon CloudWatch**: Monitors circuit breaker metrics and provides alerting

The circuit breaker automatically detects service failures, prevents cascading failures, and enables graceful degradation while periodically testing for service recovery.

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Step Functions (create/execute state machines)
  - Lambda (create/invoke functions)
  - DynamoDB (create/read/write tables)
  - CloudWatch (create alarms and metrics)
  - IAM (create/manage roles and policies)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name circuit-breaker-patterns \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name circuit-breaker-patterns

# Get outputs
aws cloudformation describe-stacks \
    --stack-name circuit-breaker-patterns \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to TypeScript CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy CircuitBreakerPatternsStack

# View outputs
cdk deploy CircuitBreakerPatternsStack --outputs-file outputs.json
```

### Using CDK Python

```bash
# Navigate to Python CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy CircuitBreakerPatternsStack

# View outputs
cdk deploy CircuitBreakerPatternsStack --outputs-file outputs.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Test the circuit breaker (optional)
./scripts/test-circuit-breaker.sh

# View deployment outputs
./scripts/show-outputs.sh
```

## Testing the Circuit Breaker

After deployment, test the circuit breaker functionality:

```bash
# Get the state machine ARN from outputs
export STATE_MACHINE_ARN="<your-state-machine-arn>"

# Test normal operation (circuit breaker CLOSED)
aws stepfunctions start-execution \
    --state-machine-arn $STATE_MACHINE_ARN \
    --name "test-normal-$(date +%s)" \
    --input '{
        "service_name": "payment-service",
        "request_payload": {
            "amount": 100.00,
            "currency": "USD",
            "customer_id": "12345"
        }
    }'

# Increase failure rate to trip circuit breaker
aws lambda update-function-configuration \
    --function-name <downstream-service-function-name> \
    --environment Variables='{
        "FAILURE_RATE": "0.9",
        "LATENCY_MS": "300"
    }'

# Execute multiple times to trip circuit breaker to OPEN state
for i in {1..5}; do
    aws stepfunctions start-execution \
        --state-machine-arn $STATE_MACHINE_ARN \
        --name "test-failure-$i-$(date +%s)" \
        --input '{
            "service_name": "payment-service",
            "request_payload": {
                "amount": 100.00,
                "currency": "USD",
                "customer_id": "12345"
            }
        }'
    sleep 2
done

# Check circuit breaker state
aws dynamodb get-item \
    --table-name <circuit-breaker-table-name> \
    --key '{"ServiceName": {"S": "payment-service"}}'
```

## Configuration Options

### Environment Variables

All implementations support these configuration parameters:

- **EnvironmentName**: Environment identifier (dev/staging/prod)
- **FailureThreshold**: Number of failures before tripping circuit breaker (default: 3)
- **TimeoutWindow**: Time window for failure counting in seconds (default: 300)
- **HealthCheckInterval**: Health check execution interval in minutes (default: 5)
- **CircuitBreakerTimeout**: Time before attempting recovery in seconds (default: 60)

### CloudFormation Parameters

```yaml
Parameters:
  EnvironmentName:
    Type: String
    Default: dev
    Description: Environment name for resource naming
  
  FailureThreshold:
    Type: Number
    Default: 3
    Description: Number of failures before opening circuit breaker
  
  TimeoutWindow:
    Type: Number
    Default: 300
    Description: Time window for failure counting (seconds)
```

### CDK Context Variables

```json
{
  "environment": "dev",
  "circuit-breaker": {
    "failureThreshold": 3,
    "timeoutWindow": 300,
    "healthCheckInterval": 5
  }
}
```

### Terraform Variables

```hcl
variable "environment_name" {
  description = "Environment name for resource naming"
  type        = string
  default     = "dev"
}

variable "failure_threshold" {
  description = "Number of failures before opening circuit breaker"
  type        = number
  default     = 3
}

variable "timeout_window" {
  description = "Time window for failure counting (seconds)"
  type        = number
  default     = 300
}
```

## Monitoring and Observability

### CloudWatch Metrics

The implementation creates custom metrics in the `CircuitBreaker` namespace:

- **CircuitBreakerOpen**: Tracks when circuit breaker opens
- **ServiceFailures**: Counts service failure events
- **FallbackInvocations**: Counts fallback service usage
- **HealthCheckResults**: Tracks health check outcomes

### CloudWatch Alarms

Pre-configured alarms monitor:

- Circuit breaker state changes to OPEN
- High service failure rates
- Health check failures
- Excessive fallback service usage

### Step Functions Monitoring

Monitor circuit breaker executions through:

- Step Functions console execution history
- CloudWatch Logs for detailed execution traces
- X-Ray tracing for distributed request tracking

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name circuit-breaker-patterns

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name circuit-breaker-patterns
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy CircuitBreakerPatternsStack
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy CircuitBreakerPatternsStack
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

## Customization

### Adding New Services

To add additional services to the circuit breaker:

1. Update the state machine definition to include new service names
2. Configure service-specific thresholds in DynamoDB
3. Add CloudWatch alarms for the new service
4. Update IAM permissions if needed

### Custom Fallback Logic

Modify the fallback Lambda function to implement:

- Service-specific fallback responses
- Cached data retrieval
- Alternative service routing
- Custom business logic for degraded mode

### Advanced Circuit Breaker Features

Extend the implementation with:

- **Bulkhead Pattern**: Isolate different request types
- **Adaptive Thresholds**: ML-based threshold adjustment
- **Multi-Region Support**: Cross-region state synchronization
- **Rate Limiting**: Request throttling integration

## Troubleshooting

### Common Issues

**Circuit Breaker Not Tripping**
- Verify failure threshold configuration
- Check Lambda function error rates
- Review Step Functions execution history

**Health Checks Failing**
- Verify health check Lambda permissions
- Check downstream service availability
- Review health check logic implementation

**State Machine Execution Errors**
- Verify IAM role permissions
- Check DynamoDB table access
- Review Lambda function configurations

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export DEBUG=true
export LOG_LEVEL=DEBUG
```

### Log Analysis

Query CloudWatch Logs for troubleshooting:

```bash
# View Step Functions execution logs
aws logs filter-log-events \
    --log-group-name /aws/stepfunctions/CircuitBreakerStateMachine \
    --start-time $(date -d '1 hour ago' +%s)000

# View Lambda function logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/downstream-service \
    --filter-pattern "ERROR"
```

## Performance Considerations

### Scaling

- **Concurrent Executions**: Step Functions supports up to 1000 concurrent executions per account
- **DynamoDB Throughput**: Adjust read/write capacity based on traffic patterns
- **Lambda Concurrency**: Configure reserved concurrency for critical functions

### Cost Optimization

- Use Step Functions Express Workflows for high-volume, short-duration executions
- Implement DynamoDB on-demand billing for unpredictable traffic
- Optimize Lambda memory allocation based on execution metrics

## Security Best Practices

### IAM Permissions

- Implement least privilege access
- Use resource-based policies where appropriate
- Enable CloudTrail for audit logging

### Encryption

- Enable DynamoDB encryption at rest
- Use encrypted Lambda environment variables
- Enable Step Functions logging encryption

### Network Security

- Deploy Lambda functions in VPC when accessing private resources
- Use VPC endpoints for AWS service access
- Implement proper security group configurations

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation
3. Verify IAM permissions and resource configurations
4. Enable debug logging for detailed troubleshooting

For AWS-specific issues, consult the [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html) and [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/).