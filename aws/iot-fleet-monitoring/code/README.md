# Infrastructure as Code for IoT Fleet Monitoring with Device Defender

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Fleet Monitoring with Device Defender".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for IoT Core, Device Defender, CloudWatch, Lambda, SNS, and IAM services
- For CDK implementations: Node.js 18+ and CDK CLI installed
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $50-100/month for moderate fleet size (depends on device count and data volume)

> **Note**: This implementation creates production-ready infrastructure for IoT fleet monitoring. Review all security configurations before deployment.

## Architecture Overview

The infrastructure includes:

- **IoT Core**: Device registry and rules engine for message routing
- **Device Defender**: Security profiles and behavioral monitoring
- **CloudWatch**: Custom dashboards, alarms, and metrics
- **Lambda**: Automated remediation functions
- **SNS**: Alert notifications and event routing
- **IAM**: Service roles and policies with least privilege access

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name iot-fleet-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=FleetName,ParameterValue=my-iot-fleet \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name iot-fleet-monitoring \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-fleet-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment (optional)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the application
cdk deploy IoTFleetMonitoringStack \
    --parameters FleetName=my-iot-fleet \
    --parameters NotificationEmail=your-email@example.com

# View deployed resources
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment (optional)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the application
cdk deploy IoTFleetMonitoringStack \
    --parameters FleetName=my-iot-fleet \
    --parameters NotificationEmail=your-email@example.com

# View deployed resources
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
fleet_name = "my-iot-fleet"
notification_email = "your-email@example.com"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export FLEET_NAME="my-iot-fleet"
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Parameters

### Required Parameters

- **FleetName**: Name for the IoT device fleet and thing group
- **NotificationEmail**: Email address for security alerts and notifications
- **AWSRegion**: AWS region for resource deployment

### Optional Parameters

- **DeviceCount**: Number of test devices to create (default: 5)
- **SecurityProfileName**: Custom name for Device Defender security profile
- **DashboardName**: Custom name for CloudWatch dashboard
- **RetentionPeriod**: Log retention period in days (default: 30)

## Post-Deployment Configuration

### 1. Confirm SNS Subscription

```bash
# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn $(terraform output -raw sns_topic_arn)

# Confirm subscription via email if pending
echo "Check your email and confirm SNS subscription"
```

### 2. Verify Device Defender Configuration

```bash
# List security profiles
aws iot list-security-profiles

# Check security profile details
aws iot describe-security-profile \
    --security-profile-name $(terraform output -raw security_profile_name)
```

### 3. Access CloudWatch Dashboard

```bash
# Get dashboard URL
DASHBOARD_NAME=$(terraform output -raw dashboard_name)
echo "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
```

### 4. Test Security Monitoring

```bash
# Create additional test device
aws iot create-thing --thing-name test-device-security

# Add to fleet for monitoring
aws iot add-thing-to-thing-group \
    --thing-group-name $(terraform output -raw fleet_name) \
    --thing-name test-device-security
```

## Monitoring and Alerts

### CloudWatch Alarms

The implementation creates several CloudWatch alarms:

- **High Security Violations**: Triggers when security violations exceed threshold
- **Low Device Connectivity**: Alerts when connected devices fall below minimum
- **Message Processing Errors**: Monitors IoT message processing failures

### Custom Metrics

Custom metrics are created in the `AWS/IoT/FleetMonitoring` namespace:

- `SecurityViolations`: Count of security violations by fleet
- `DeviceConnectionEvents`: Device connection/disconnection events
- `MessageVolume`: Message processing volume from devices

### Dashboard Widgets

The CloudWatch dashboard includes:

- Fleet connectivity overview
- Security violations timeline
- Message processing statistics
- Recent security violation logs

## Security Considerations

### IAM Roles and Policies

The implementation follows least privilege principles:

- **Device Defender Role**: Minimal permissions for audit and security monitoring
- **Lambda Execution Role**: Permissions for IoT actions and CloudWatch metrics
- **IoT Rules Role**: Permissions for CloudWatch Logs and metrics

### Security Profiles

Device Defender security profiles monitor:

- Authorization failures (threshold: 5 failures in 5 minutes)
- Message byte size (threshold: 1024 bytes)
- Message volume (threshold: 100 messages in 5 minutes)
- Connection attempts (threshold: 10 attempts in 5 minutes)

### Encryption

- All data in transit is encrypted using TLS
- CloudWatch Logs encryption is enabled
- SNS topics use server-side encryption

## Customization

### Adding Custom Security Behaviors

Modify the security profile to add custom behaviors:

```json
{
  "name": "CustomBehavior",
  "metric": "aws:custom-metric",
  "criteria": {
    "comparisonOperator": "greater-than",
    "value": {"count": 10},
    "durationSeconds": 300
  }
}
```

### Extending Lambda Remediation

Enhance the Lambda function for custom remediation actions:

```python
def handle_security_violation(violation_type, thing_name):
    if violation_type == "custom-violation":
        # Implement custom remediation logic
        disable_device_temporarily(thing_name)
        notify_security_team(violation_details)
```

### Adding Dashboard Widgets

Extend the CloudWatch dashboard with additional widgets:

```json
{
  "type": "metric",
  "properties": {
    "metrics": [
      ["AWS/IoT", "CustomMetric", "ThingName", "device-name"]
    ],
    "period": 300,
    "stat": "Average",
    "region": "us-east-1",
    "title": "Custom Device Metrics"
  }
}
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name iot-fleet-monitoring

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name iot-fleet-monitoring
```

### Using CDK

```bash
# Destroy the application
cdk destroy IoTFleetMonitoringStack

# Clean up CDK bootstrap (if no longer needed)
# cdk bootstrap --destroy
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm cleanup completion
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check IAM permissions
   aws iam simulate-principal-policy \
       --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
       --action-names iot:CreateThing iot:CreateSecurityProfile \
       --resource-arns "*"
   ```

2. **Device Defender Not Monitoring**
   ```bash
   # Verify security profile attachment
   aws iot list-targets-for-security-profile \
       --security-profile-name YOUR_SECURITY_PROFILE_NAME
   ```

3. **CloudWatch Alarms Not Triggering**
   ```bash
   # Check alarm configuration
   aws cloudwatch describe-alarms \
       --alarm-names YOUR_ALARM_NAME
   ```

4. **Lambda Function Errors**
   ```bash
   # Check Lambda logs
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/lambda/"
   ```

### Debug Commands

```bash
# Check IoT Core connectivity
aws iot describe-endpoint --endpoint-type iot:Data-ATS

# List IoT things in fleet
aws iot list-things-in-thing-group \
    --thing-group-name YOUR_FLEET_NAME

# Check security profile violations
aws iot list-violation-events \
    --start-time $(date -d "1 hour ago" +%s) \
    --end-time $(date +%s)
```

## Cost Optimization

### Monitoring Costs

- Review CloudWatch custom metrics usage
- Optimize log retention periods
- Monitor Lambda execution costs
- Consider Device Defender pricing for fleet size

### Resource Optimization

- Use appropriate alarm evaluation periods
- Implement lifecycle policies for log groups
- Regular cleanup of unused IoT things
- Monitor SNS message costs

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Verify IAM permissions and service quotas
4. Check CloudWatch Logs for error messages

## Related Resources

- [AWS IoT Device Defender User Guide](https://docs.aws.amazon.com/iot-device-defender/latest/devguide/)
- [AWS IoT Core Developer Guide](https://docs.aws.amazon.com/iot/latest/developerguide/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)