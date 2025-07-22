# Distributed Tracing with X-Ray - CDK Python

This CDK Python application implements a complete distributed tracing solution using AWS X-Ray and Amazon EventBridge across a microservices architecture.

## Architecture Overview

The application creates:

- **Custom EventBridge Bus**: Isolated event routing for microservices communication
- **Lambda Functions**: Four microservices (Order, Payment, Inventory, Notification) with X-Ray tracing
- **API Gateway**: REST API with X-Ray tracing enabled as the entry point
- **EventBridge Rules**: Event routing logic based on source and detail-type patterns
- **IAM Roles**: Least privilege access for Lambda functions
- **CloudWatch Logs**: Centralized logging with one-week retention

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate credentials
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Docker (for bundling Lambda dependencies if needed)

## Installation

1. **Clone or navigate to this directory**:
   ```bash
   cd aws/distributed-tracing-x-ray-eventbridge/code/cdk-python/
   ```

2. **Create and activate a virtual environment**:
   ```bash
   python -m venv .venv
   
   # On macOS/Linux:
   source .venv/bin/activate
   
   # On Windows:
   .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if not done previously)**:
   ```bash
   cdk bootstrap
   ```

## Deployment

1. **Synthesize CloudFormation template** (optional):
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   The deployment will output:
   - API Gateway endpoint URL
   - EventBridge bus name and ARN
   - X-Ray service map console URL

3. **Confirm deployment**:
   - Type `y` when prompted to deploy the stack

## Testing

1. **Test the distributed tracing flow**:
   ```bash
   # Get the API endpoint from CDK outputs
   API_ENDPOINT=$(aws cloudformation describe-stacks \
     --stack-name DistributedTracingStack \
     --query 'Stacks[0].Outputs[?OutputKey==`APIGatewayURL`].OutputValue' \
     --output text)
   
   # Send a test request
   curl -X POST \
     -H "Content-Type: application/json" \
     -d '{"productId": "12345", "quantity": 1}' \
     "${API_ENDPOINT}orders/customer123"
   ```

2. **View X-Ray traces**:
   - Wait 1-2 minutes for traces to be processed
   - Open the X-Ray console: https://console.aws.amazon.com/xray/
   - Navigate to Service Map to see service interactions
   - View Traces to see detailed execution flows

3. **Monitor logs**:
   ```bash
   # View logs for each service
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/DistributedTracingStack"
   ```

## Architecture Details

### Lambda Functions

- **Order Service**: Entry point that receives API Gateway requests and publishes order events
- **Payment Service**: Processes payment for orders and publishes payment completion events
- **Inventory Service**: Updates inventory for orders and publishes inventory events
- **Notification Service**: Sends notifications based on payment and inventory completion

### Event Flow

1. API Gateway → Order Service (via Lambda proxy integration)
2. Order Service → EventBridge (Order Created event)
3. EventBridge → Payment Service + Inventory Service (parallel processing)
4. Payment/Inventory Services → EventBridge (completion events)
5. EventBridge → Notification Service (final notifications)

### X-Ray Integration

- All Lambda functions have active tracing enabled
- API Gateway propagates trace context to Lambda
- Custom annotations and metadata for filtering and analysis
- Subsegments for detailed operation tracking

## Customization

### Environment Variables

Modify the CDK app to customize:

```python
# In app.py
import os

# Custom configuration
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'demo')
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'DistributedTracing')
```

### Lambda Function Code

The Lambda function code is embedded inline for simplicity. For production:

1. Create separate files for each function
2. Use `_lambda.Code.from_asset()` for local code
3. Consider Lambda layers for shared dependencies

### Monitoring and Alerting

Add CloudWatch alarms for:

```python
# Example alarm for high error rates
alarm = cloudwatch.Alarm(
    self, "HighErrorRate",
    metric=self.lambda_functions['order'].metric_errors(),
    threshold=5,
    evaluation_periods=2
)
```

## Cost Optimization

- **X-Ray Sampling**: Implement custom sampling rules to control trace volume
- **Log Retention**: Adjust CloudWatch log retention periods based on requirements
- **Lambda Memory**: Right-size Lambda function memory allocations

## Security Considerations

- **IAM Roles**: Uses least privilege access with minimal required permissions
- **API Gateway**: Consider adding authentication and authorization
- **Encryption**: Enable encryption for EventBridge and Lambda environment variables
- **VPC**: Consider deploying Lambda functions in VPC for additional security

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   ```bash
   # Check CDK version compatibility
   cdk --version
   
   # Verify AWS credentials
   aws sts get-caller-identity
   ```

2. **Missing Traces**:
   - Verify X-Ray sampling rules
   - Check Lambda function logs for errors
   - Ensure proper IAM permissions for X-Ray

3. **EventBridge Issues**:
   - Verify event patterns match published events
   - Check Lambda function permissions for EventBridge
   - Monitor EventBridge metrics in CloudWatch

### Useful Commands

```bash
# View CDK differences before deployment
cdk diff

# Destroy the stack
cdk destroy

# List all stacks
cdk list

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name DistributedTracingStack
```

## Cleanup

To avoid ongoing charges, destroy the stack:

```bash
cdk destroy
```

Confirm deletion when prompted.

## Additional Resources

- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)

## Support

For issues with this CDK application:

1. Check the AWS CDK documentation
2. Review CloudFormation stack events
3. Examine CloudWatch logs for detailed error information
4. Refer to the original recipe documentation