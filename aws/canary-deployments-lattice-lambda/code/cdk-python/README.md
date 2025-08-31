# Canary Deployments with VPC Lattice and Lambda - CDK Python

This CDK Python application implements a complete canary deployment solution using AWS VPC Lattice for advanced traffic routing and AWS Lambda for serverless compute. The solution enables progressive deployment strategies with automated monitoring and rollback capabilities.

## Architecture Overview

The application creates the following AWS resources:

- **Lambda Functions**: Two versions (production v1.0.0 and canary v2.0.0) with different functionality
- **VPC Lattice Service Network**: Provides application-layer connectivity and traffic management
- **VPC Lattice Service**: Defines the entry point for application traffic
- **Target Groups**: Separate groups for production and canary Lambda versions
- **Weighted Listener**: Routes traffic with configurable percentages (initially 90% production, 10% canary)
- **CloudWatch Alarms**: Monitor error rates and response times for canary version
- **SNS Topic**: Notification system for rollback events
- **Rollback Lambda**: Automatically reverts traffic to production on alarm triggers
- **IAM Roles**: Least privilege access for all Lambda functions

## Features

- **Progressive Traffic Shifting**: Start with 10% canary traffic and gradually increase
- **Automated Monitoring**: CloudWatch alarms track key performance metrics
- **Instant Rollback**: Automatic reversion to production on error threshold breach
- **Version Management**: Proper Lambda versioning for isolated deployments
- **Security Best Practices**: IAM roles with minimal required permissions
- **Comprehensive Logging**: CloudWatch Logs integration for debugging

## Prerequisites

- Python 3.8 or later
- AWS CLI v2 installed and configured
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for:
  - Lambda (create functions, versions, permissions)
  - VPC Lattice (create service networks, services, target groups)
  - CloudWatch (create alarms, log groups)
  - SNS (create topics, subscriptions)
  - IAM (create roles, attach policies)

## Installation and Deployment

### 1. Set up Python Virtual Environment

```bash
# Create virtual environment
python3 -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate.bat
```

### 2. Install Dependencies

```bash
# Install CDK dependencies
pip install -r requirements.txt
```

### 3. Bootstrap CDK (First Time Only)

```bash
# Bootstrap CDK in your AWS account/region
cdk bootstrap
```

### 4. Synthesize CloudFormation Template

```bash
# Generate CloudFormation template (optional - for review)
cdk synth
```

### 5. Deploy the Stack

```bash
# Deploy the canary deployment infrastructure
cdk deploy

# Or deploy with automatic approval (skip manual confirmation)
cdk deploy --require-approval never
```

## Usage and Testing

### Initial Traffic Distribution

After deployment, the VPC Lattice service will route:
- 90% of traffic to production Lambda version (v1.0.0)
- 10% of traffic to canary Lambda version (v2.0.0)

### Testing the Deployment

1. **Get Service Endpoint**:
   ```bash
   # The service DNS endpoint is provided in CDK outputs
   SERVICE_DNS=$(aws cloudformation describe-stacks \
       --stack-name CanaryDeploymentLatticeStack \
       --query 'Stacks[0].Outputs[?OutputKey==`ServiceDNS`].OutputValue' \
       --output text)
   ```

2. **Send Test Requests**:
   ```bash
   # Test traffic distribution
   for i in {1..20}; do
       echo "Request $i:"
       curl -s "https://${SERVICE_DNS}" | jq -r '.body | fromjson | .version'
       sleep 1
   done
   ```

3. **Monitor Version Distribution**:
   You should see approximately 90% responses from v1.0.0 and 10% from v2.0.0.

### Progressive Traffic Shifting

To manually adjust traffic distribution:

```bash
# Get resource IDs from CDK outputs
SERVICE_ID=$(aws cloudformation describe-stacks \
    --stack-name CanaryDeploymentLatticeStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceId`].OutputValue' \
    --output text)

LISTENER_ID=$(aws cloudformation describe-stacks \
    --stack-name CanaryDeploymentLatticeStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ListenerId`].OutputValue' \
    --output text)

# Shift to 70% production, 30% canary
aws vpc-lattice update-listener \
    --service-identifier ${SERVICE_ID} \
    --listener-identifier ${LISTENER_ID} \
    --default-action '{
        "forward": {
            "targetGroups": [
                {
                    "targetGroupIdentifier": "PROD_TARGET_GROUP_ID",
                    "weight": 70
                },
                {
                    "targetGroupIdentifier": "CANARY_TARGET_GROUP_ID",
                    "weight": 30
                }
            ]
        }
    }'
```

### Monitoring and Alarms

The application creates CloudWatch alarms that monitor:

1. **Error Rate**: Triggers if canary version generates more than 5 errors in 10 minutes
2. **Response Time**: Triggers if average duration exceeds 5 seconds

When alarms fire, the rollback Lambda automatically reverts traffic to 100% production.

### Viewing Metrics

```bash
# Check alarm status
aws cloudwatch describe-alarms \
    --alarm-name-prefix "canary-lambda"

# View Lambda metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=FUNCTION_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Customization

### Adjusting Traffic Weights

Edit the `lattice_listener` configuration in `app.py`:

```python
lattice.CfnListener.WeightedTargetGroupProperty(
    target_group_identifier=production_target_group.attr_id,
    weight=80  # Change from 90 to 80
),
lattice.CfnListener.WeightedTargetGroupProperty(
    target_group_identifier=canary_target_group.attr_id,
    weight=20  # Change from 10 to 20
)
```

### Modifying Alarm Thresholds

Adjust CloudWatch alarm sensitivity in the `_create_cloudwatch_alarms` method:

```python
# Change error threshold
threshold=3,  # Reduced from 5 to 3 errors

# Change evaluation periods
evaluation_periods=1,  # Reduced from 2 to 1 period
```

### Lambda Function Code

Modify the Lambda function code in the `_get_production_lambda_code()` and `_get_canary_lambda_code()` methods to implement your specific business logic.

## Cleanup

Remove all created resources:

```bash
# Destroy the stack
cdk destroy

# Confirm destruction when prompted
```

## Troubleshooting

### Common Issues

1. **VPC Lattice Service Not Accessible**:
   - Ensure your account has VPC Lattice enabled
   - Check that the service network is in ACTIVE state

2. **Lambda Permissions Errors**:
   - Verify IAM roles have correct permissions
   - Check CloudWatch Logs for detailed error messages

3. **Target Group Health Issues**:
   - Confirm Lambda functions are responding correctly
   - Check target group health in AWS Console

### Useful Commands

```bash
# View CDK differences
cdk diff

# List all stacks
cdk list

# Get specific resource information
aws vpc-lattice describe-service --service-identifier SERVICE_ID
aws lambda list-versions-by-function --function-name FUNCTION_NAME
```

## Security Considerations

- IAM roles follow least privilege principle
- Lambda functions only have necessary VPC Lattice permissions
- CloudWatch Logs are configured with appropriate retention
- No hardcoded credentials or sensitive data in code

## Cost Optimization

- Lambda functions use appropriate memory allocation (256MB)
- CloudWatch Logs have limited retention (1 week)
- Resources are properly tagged for cost tracking
- VPC Lattice charges based on processed requests

## Further Reading

- [AWS VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
- [AWS Lambda Versioning](https://docs.aws.amazon.com/lambda/latest/dg/configuration-versions.html)
- [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [Canary Deployment Patterns](https://docs.aws.amazon.com/whitepapers/latest/overview-deployment-options/canary-deployments.html)