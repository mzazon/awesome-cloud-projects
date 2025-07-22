# IoT Device Management CDK Python Application

This CDK Python application implements a comprehensive IoT Device Management solution using AWS IoT Core and related services.

## Architecture Overview

The application creates:
- **IoT Thing Type**: Template for sensor devices with searchable attributes
- **IoT Thing Group**: Static group for production sensors
- **Dynamic Thing Groups**: Auto-categorization based on firmware version and location
- **IoT Policy**: Secure device access permissions with least privilege
- **Fleet Metrics**: Monitoring for device connectivity and firmware distribution
- **CloudWatch Log Group**: Centralized logging for IoT devices
- **Sample IoT Things**: Demo devices for testing

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Docker (for asset bundling)

## Required AWS Permissions

Your AWS credentials need the following permissions:
- IoT Core full access
- CloudWatch Logs write access
- CloudFormation full access
- IAM role/policy management

## Quick Start

1. **Set up Python environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **View the resources**:
   ```bash
   cdk list
   cdk ls
   ```

## Deployment

### Development Environment
```bash
# Synthesize CloudFormation template
cdk synth

# Preview changes
cdk diff

# Deploy with confirmation
cdk deploy --require-approval broadening
```

### Production Environment
```bash
# Deploy with specific profile and region
cdk deploy --profile production --region us-west-2

# Deploy with parameters
cdk deploy --parameters env=production
```

## Testing

Run the included tests:
```bash
# Install test dependencies
pip install -r requirements.txt

# Run tests
pytest tests/

# Run tests with coverage
pytest --cov=app tests/
```

## Customization

### Environment Variables
Set these environment variables or CDK context values:
- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region (default: us-east-1)

### CDK Context
Add to `cdk.json`:
```json
{
  "context": {
    "account": "123456789012",
    "region": "us-east-1",
    "environmentName": "production"
  }
}
```

### Custom Device Configuration
Modify the `devices` list in `_create_sample_things()` method to add more devices:
```python
devices = [
    {"name": "temp-sensor-05", "location": "Building-E", "firmware": "1.2.0"},
    {"name": "humidity-sensor-01", "location": "Building-A", "firmware": "1.1.0"},
    # Add more devices...
]
```

## Fleet Management Operations

### Device Provisioning
After deployment, provision additional devices:
```bash
# Create IoT Thing
aws iot create-thing \
    --thing-name "new-sensor-01" \
    --thing-type-name "$(aws cloudformation describe-stacks \
        --stack-name IoTDeviceManagementStack \
        --query 'Stacks[0].Outputs[?OutputKey==`ThingTypeName`].OutputValue' \
        --output text)"

# Add to Thing Group
aws iot add-thing-to-thing-group \
    --thing-name "new-sensor-01" \
    --thing-group-name "$(aws cloudformation describe-stacks \
        --stack-name IoTDeviceManagementStack \
        --query 'Stacks[0].Outputs[?OutputKey==`ThingGroupName`].OutputValue' \
        --output text)"
```

### Certificate Management
Create and attach certificates for devices:
```bash
# Create certificate
aws iot create-keys-and-certificate \
    --set-as-active \
    --query 'certificateArn' \
    --output text

# Attach policy to certificate
aws iot attach-policy \
    --policy-name "$(aws cloudformation describe-stacks \
        --stack-name IoTDeviceManagementStack \
        --query 'Stacks[0].Outputs[?OutputKey==`IoTPolicyName`].OutputValue' \
        --output text)" \
    --target "arn:aws:iot:region:account:cert/certificate-id"
```

### Fleet Monitoring
Monitor fleet metrics in CloudWatch:
```bash
# Get fleet metrics
aws iot describe-fleet-metric \
    --metric-name "ConnectedDevices-IoTDeviceManagementStack"

# View CloudWatch metrics
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/iot/device-management"
```

## Security Considerations

### IoT Policy
The IoT policy implements least privilege access:
- Devices can only connect using their thing name
- Topic access is scoped to device-specific topics
- Shadow access is limited to device's own shadow

### Network Security
- Use VPC endpoints for IoT Core in production
- Implement certificate-based authentication
- Enable CloudTrail for audit logging

### Data Protection
- Enable encryption for device shadows
- Use AWS KMS for certificate encryption
- Implement proper certificate rotation

## Monitoring and Alerting

### CloudWatch Dashboards
Create custom dashboards for fleet monitoring:
```python
# Add to your CDK stack
dashboard = cloudwatch.Dashboard(self, "IoTFleetDashboard")
dashboard.add_widgets(
    cloudwatch.GraphWidget(
        title="Connected Devices",
        left=[connected_devices_metric]
    )
)
```

### Alarms
Set up CloudWatch alarms for fleet health:
```python
# Add alarm for disconnected devices
cloudwatch.Alarm(
    self, "DisconnectedDevicesAlarm",
    metric=connected_devices_metric,
    threshold=10,
    evaluation_periods=2,
    comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD
)
```

## Troubleshooting

### Common Issues

1. **Certificate attachment fails**:
   - Verify certificate is active
   - Check IAM permissions for IoT operations

2. **Device connection refused**:
   - Verify IoT policy allows connection
   - Check thing name matches certificate

3. **Fleet metrics not updating**:
   - Ensure fleet indexing is enabled
   - Check device attribute syntax

### Debug Commands
```bash
# Check IoT policy
aws iot get-policy --policy-name "device-policy-stackname"

# List thing groups
aws iot list-thing-groups

# Check fleet indexing status
aws iot describe-index --index-name "AWS_Things"
```

## Cleanup

To remove all resources:
```bash
# Delete the stack
cdk destroy

# Confirm deletion
cdk destroy --force
```

## Cost Optimization

- Use lifecycle policies for CloudWatch logs
- Implement device-level logging controls
- Monitor Fleet Metrics usage for cost impact
- Consider using IoT Device Defender for security insights

## Additional Resources

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [AWS CDK Python Documentation](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [IoT Device Management Best Practices](https://docs.aws.amazon.com/iot/latest/developerguide/device-management.html)
- [Fleet Indexing Guide](https://docs.aws.amazon.com/iot/latest/developerguide/fleet-indexing.html)

## License

This project is licensed under the MIT License - see the LICENSE file for details.