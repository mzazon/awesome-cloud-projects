# AWS CDK Python - Media Workflow Stack

This directory contains a comprehensive AWS CDK Python application for Orchestrating Media Workflows with MediaConnect and Step Functions.

## Architecture Overview

This stack deploys a complete media monitoring and alerting solution that includes:

- **MediaConnect Flow**: Reliable video transport with primary and backup outputs
- **Step Functions State Machine**: Workflow orchestration for monitoring and alerting
- **Lambda Functions**: Stream monitoring and alert handling capabilities
- **CloudWatch Alarms & Dashboard**: Real-time monitoring and visualization
- **SNS Topic**: Instant notifications for operations teams
- **EventBridge Rules**: Automated workflow execution based on alarm states
- **IAM Roles**: Secure, least-privilege access control

## Features

### 🎯 **Real-time Stream Monitoring**
- Continuous monitoring of packet loss and jitter metrics
- Configurable thresholds for quality detection
- Automated issue detection and escalation

### 🔔 **Intelligent Alerting**
- Email notifications via SNS with detailed issue descriptions
- Actionable recommendations for operations teams
- Multiple severity levels (HIGH, MEDIUM) based on metric types

### 📊 **Comprehensive Monitoring**
- CloudWatch dashboard with stream health and performance metrics
- Multiple alarm types with different sensitivity levels
- Historical data tracking and trend analysis

### 🤖 **Automated Workflows**
- Event-driven architecture using EventBridge
- Step Functions orchestration for complex monitoring logic
- Serverless execution with automatic scaling

### 🔒 **Security Best Practices**
- IAM roles with least-privilege permissions
- Encrypted S3 storage for Lambda deployment packages
- Secure API communication between services

## Prerequisites

Before deploying this stack, ensure you have:

- Python 3.8+ installed
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for:
  - MediaConnect
  - Step Functions
  - Lambda
  - CloudWatch
  - SNS
  - EventBridge
  - IAM

## Installation

1. **Clone or navigate to this directory**:
   ```bash
   cd cdk-python/
   ```

2. **Create a virtual environment** (recommended):
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (if not done previously):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

You can configure the stack using environment variables:

```bash
export NOTIFICATION_EMAIL="your-email@example.com"
export SOURCE_WHITELIST_CIDR="192.168.1.0/24"  # Your source IP range
export PRIMARY_OUTPUT_DESTINATION="10.0.0.100"
export BACKUP_OUTPUT_DESTINATION="10.0.0.101"
export PACKET_LOSS_THRESHOLD="0.1"  # 0.1% threshold
export JITTER_THRESHOLD="50"        # 50ms threshold
export FLOW_NAME="my-live-stream"
```

### CDK Context Parameters

Alternatively, use CDK context parameters:

```bash
cdk deploy \
  -c notificationEmail=your-email@example.com \
  -c sourceWhitelistCidr=192.168.1.0/24 \
  -c primaryOutputDestination=10.0.0.100 \
  -c backupOutputDestination=10.0.0.101 \
  -c packetLossThreshold=0.1 \
  -c jitterThreshold=50 \
  -c flowName=my-live-stream
```

## Deployment

### Quick Deploy

Deploy with default settings:

```bash
cdk deploy
```

### Custom Configuration Deploy

Deploy with custom configuration:

```bash
# Using environment variables
export NOTIFICATION_EMAIL="ops-team@yourcompany.com"
export SOURCE_WHITELIST_CIDR="203.0.113.0/24"
cdk deploy

# Or using context parameters
cdk deploy \
  -c notificationEmail=ops-team@yourcompany.com \
  -c sourceWhitelistCidr=203.0.113.0/24
```

### Deployment Verification

After deployment, verify the stack:

```bash
# Check stack outputs
cdk list
aws cloudformation describe-stacks --stack-name MediaWorkflowStack

# Test the Step Functions state machine
aws stepfunctions start-execution \
  --state-machine-arn <STATE_MACHINE_ARN> \
  --input '{"flow_arn": "<FLOW_ARN>"}'
```

## Usage

### Starting the MediaConnect Flow

After deployment, start your MediaConnect flow:

```bash
# Get the flow ARN from stack outputs
FLOW_ARN=$(aws cloudformation describe-stacks \
  --stack-name MediaWorkflowStack \
  --query 'Stacks[0].Outputs[?OutputKey==`MediaConnectFlowArn`].OutputValue' \
  --output text)

# Start the flow
aws mediaconnect start-flow --flow-arn $FLOW_ARN

# Get ingest endpoint
aws mediaconnect describe-flow --flow-arn $FLOW_ARN \
  --query 'Flow.Source.IngestIp' --output text
```

### Monitoring Your Stream

1. **CloudWatch Dashboard**: Navigate to the dashboard URL provided in stack outputs
2. **CloudWatch Alarms**: Monitor alarm states in the CloudWatch console
3. **Step Functions**: View workflow executions in the Step Functions console

### Testing the Workflow

Manually trigger the monitoring workflow:

```bash
# Get the state machine ARN
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
  --stack-name MediaWorkflowStack \
  --query 'Stacks[0].Outputs[?OutputKey==`StepFunctionsStateMachineArn`].OutputValue' \
  --output text)

# Execute the workflow
aws stepfunctions start-execution \
  --state-machine-arn $STATE_MACHINE_ARN \
  --input "{\"flow_arn\": \"$FLOW_ARN\"}"
```

## Customization

### Modifying Thresholds

Update monitoring thresholds by modifying the configuration:

```python
# In app.py, modify the default values
packet_loss_threshold = props.packet_loss_threshold or 0.05  # More sensitive
jitter_threshold = props.jitter_threshold or 30  # More sensitive
```

### Adding Additional Metrics

Extend the stream monitor Lambda function to include additional metrics:

```python
# Add to _get_stream_monitor_code method
# Check source bitrate stability
bitrate_response = cloudwatch.get_metric_statistics(
    Namespace='AWS/MediaConnect',
    MetricName='SourceBitrate',
    # ... additional configuration
)
```

### Custom Alert Messages

Modify the alert handler Lambda function to customize notification content:

```python
# In _get_alert_handler_code method, customize message_lines
message_lines = [
    f"🚨 URGENT: Stream Alert for {monitoring_result.get('flow_name')}",
    f"⏰ Time: {monitoring_result.get('timestamp')}",
    # ... additional customization
]
```

## Development

### Code Quality

This project includes development dependencies for code quality:

```bash
# Code formatting
black app.py

# Linting
flake8 app.py

# Type checking
mypy app.py

# Run tests
pytest
```

### Project Structure

```
cdk-python/
├── app.py              # Main CDK application
├── requirements.txt    # Python dependencies
├── setup.py           # Package configuration
├── cdk.json           # CDK configuration
├── README.md          # This file
└── .gitignore         # Git ignore patterns
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Email Confirmation**: Check your email for SNS subscription confirmation
3. **Flow Start Issues**: Verify source IP whitelist includes your encoder's IP
4. **Lambda Timeouts**: Check CloudWatch logs for detailed error messages

### Debugging

Enable detailed logging:

```bash
# CDK debug mode
cdk deploy --debug

# View Lambda logs
aws logs tail /aws/lambda/stream-monitor-<suffix> --follow

# View Step Functions execution history
aws stepfunctions describe-execution --execution-arn <EXECUTION_ARN>
```

### Stack Cleanup

Remove all resources:

```bash
# Stop MediaConnect flow first
aws mediaconnect stop-flow --flow-arn $FLOW_ARN

# Destroy the stack
cdk destroy
```

## Cost Optimization

### Estimated Costs

- **MediaConnect Flow**: $0.50/hour + data transfer costs
- **Lambda Functions**: $0.20/month (1M requests)
- **Step Functions**: $0.025/1000 state transitions
- **CloudWatch**: $0.50/month (standard monitoring)
- **SNS**: $0.50/month (email notifications)

**Total estimated cost**: ~$40-60/month for a single stream

### Cost Reduction Tips

1. Use EXPRESS Step Functions for high-volume workflows
2. Implement intelligent alarm thresholds to reduce false positives
3. Use CloudWatch log retention policies
4. Consider Reserved Capacity for predictable workloads

## Security Considerations

### Network Security

- Configure specific source IP ranges instead of `0.0.0.0/0`
- Use VPC endpoints for private communication
- Enable CloudTrail for API auditing

### Access Control

- IAM roles follow least-privilege principle
- No hardcoded credentials or secrets
- Separate roles for each service component

### Data Protection

- S3 bucket encryption enabled
- SNS message encryption available
- MediaConnect supports flow encryption

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.

## Support

For issues and questions:

- AWS CDK Documentation: https://docs.aws.amazon.com/cdk/
- MediaConnect Documentation: https://docs.aws.amazon.com/mediaconnect/
- Step Functions Documentation: https://docs.aws.amazon.com/step-functions/

## Related Resources

- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)
- [MediaConnect Best Practices](https://docs.aws.amazon.com/mediaconnect/latest/ug/best-practices.html)
- [Step Functions Best Practices](https://docs.aws.amazon.com/step-functions/latest/dg/bp-lambda-serviceexception.html)
- [CloudWatch Monitoring Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html)