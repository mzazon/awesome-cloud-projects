# Infrastructure as Code for IoT Security Monitoring with Device Defender

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Security Monitoring with Device Defender".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for IoT Core, Device Defender, IAM, SNS, and CloudWatch
- For CDK implementations: Node.js (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform CLI v1.0+
- At least one IoT device registered in AWS IoT Core for testing
- Email address for receiving security alerts

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name iot-security-defender-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=EmailAddress,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name iot-security-defender-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-security-defender-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy \
    --parameters EmailAddress=your-email@example.com

# View stack outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy \
    --parameters EmailAddress=your-email@example.com

# View stack outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="email_address=your-email@example.com"

# Apply configuration
terraform apply \
    -var="email_address=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh your-email@example.com

# View deployment status
echo "Check your email and confirm SNS subscription"
echo "Monitor CloudWatch for security violations"
```

## What Gets Deployed

This infrastructure deploys a comprehensive IoT security monitoring solution including:

### Core Resources

- **IAM Role**: Service role for Device Defender with appropriate permissions
- **SNS Topic**: For security alert notifications
- **SNS Subscription**: Email notifications for security events
- **Security Profiles**: Both rule-based and ML-based behavioral monitoring
- **CloudWatch Alarm**: Real-time alerting for security violations
- **Scheduled Audit**: Weekly automated security compliance checks

### Security Monitoring Features

- **Behavioral Rules**: Monitor excessive messages, authorization failures, large message sizes, and unusual connection attempts
- **ML Detection**: Automatic baseline establishment for device behavior patterns
- **Audit Checks**: Certificate expiration, policy compliance, and configuration validation
- **Real-time Alerts**: Immediate notification of security violations via SNS and CloudWatch

### Configuration Details

- Security profiles attached to all registered IoT devices
- Weekly scheduled audits every Monday
- CloudWatch alarm threshold set to 1 violation for immediate alerting
- ML-based detection for adaptive threat identification
- Comprehensive audit coverage including certificate and policy checks

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email and confirm the SNS subscription for security alerts

2. **Verify Device Monitoring**: Ensure your IoT devices are registered and being monitored:
   ```bash
   aws iot list-targets-for-security-profile \
       --security-profile-name IoTSecurityProfile-<suffix>
   ```

3. **Run Initial Audit**: Execute an immediate security audit:
   ```bash
   aws iot start-on-demand-audit-task \
       --target-check-names CA_CERTIFICATE_EXPIRING_CHECK \
       DEVICE_CERTIFICATE_EXPIRING_CHECK \
       DEVICE_CERTIFICATE_SHARED_CHECK \
       IOT_POLICY_OVERLY_PERMISSIVE_CHECK
   ```

4. **Monitor CloudWatch**: Check the AWS Console for Device Defender metrics and violations

## Testing Security Detection

To validate the security monitoring is working:

1. **Test Excessive Messages**: Configure a test device to send more than 100 messages within 5 minutes
2. **Simulate Auth Failures**: Generate repeated authorization failures from a test device
3. **Large Message Test**: Send messages exceeding 1024 bytes
4. **Connection Attempts**: Generate more than 20 connection attempts within 5 minutes

Security violations will trigger:
- SNS email notifications
- CloudWatch alarm activation
- Device Defender violation records

## Monitoring and Maintenance

### Key Metrics to Monitor

- **AWS/IoT/DeviceDefender/Violations**: Security rule violations
- **AWS/IoT/DeviceDefender/AuditFindings**: Compliance audit results
- **SNS Topic**: Delivery success/failure rates
- **CloudWatch Alarms**: Alarm state and history

### Regular Maintenance Tasks

- Review and adjust security profile thresholds based on device behavior
- Monitor ML detection accuracy and tune sensitivity
- Review audit findings and remediate security issues
- Update IAM policies and rotate credentials as needed
- Review SNS subscription status and email delivery

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name iot-security-defender-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name iot-security-defender-stack
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="email_address=your-email@example.com"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Key Variables/Parameters

- **EmailAddress**: Email address for security alert notifications
- **SecurityProfileName**: Name for the security profile (auto-generated with suffix)
- **AuditSchedule**: Frequency of scheduled audits (default: weekly on Monday)
- **ViolationThreshold**: CloudWatch alarm threshold for violations (default: 1)
- **MessageVolumeThreshold**: Maximum messages per 5-minute period (default: 100)
- **AuthFailureThreshold**: Maximum authorization failures per 5-minute period (default: 5)

### Advanced Customization

1. **Modify Behavioral Rules**: Adjust thresholds in security profiles based on your device patterns
2. **Add Custom Metrics**: Extend monitoring with application-specific device metrics
3. **Enhanced Notifications**: Add Lambda functions for automated remediation workflows
4. **Multi-Region Deployment**: Deploy across multiple AWS regions for global IoT fleets
5. **Integration**: Connect with existing SIEM or security orchestration platforms

### Environment-Specific Configurations

For different environments (dev/staging/prod), consider:
- Different violation thresholds and sensitivity levels
- Separate SNS topics and notification channels
- Environment-specific audit schedules
- Customized security profile names and tags

## Troubleshooting

### Common Issues

1. **Email Notifications Not Received**:
   - Verify SNS subscription confirmation
   - Check email spam/junk folders
   - Validate SNS topic permissions

2. **Security Profiles Not Monitoring Devices**:
   - Ensure devices are registered in IoT Core
   - Verify security profile target attachments
   - Check Device Defender service permissions

3. **CloudWatch Alarms Not Triggering**:
   - Validate alarm configuration and thresholds
   - Check CloudWatch metrics data availability
   - Verify SNS topic ARN in alarm configuration

4. **Audit Tasks Failing**:
   - Check IAM role permissions for Device Defender
   - Verify audit check configurations
   - Review CloudWatch logs for error details

### Getting Support

- Review the original recipe documentation for detailed implementation guidance
- Check AWS IoT Device Defender documentation for service-specific troubleshooting
- Monitor CloudWatch logs for detailed error information
- Use AWS Support for service-specific issues

## Security Considerations

- IAM roles follow least privilege principle
- SNS topics use encryption in transit
- CloudWatch logs retain security event history
- Audit trails maintain compliance records
- Security profiles can be customized per device type or environment

## Cost Optimization

- Device Defender charges based on monitored devices and audit frequency
- CloudWatch charges for custom metrics and log retention
- SNS charges for notification delivery
- Consider ML detection vs rule-based monitoring cost trade-offs
- Review and optimize audit frequency based on compliance requirements

This infrastructure provides enterprise-grade IoT security monitoring with comprehensive threat detection, compliance auditing, and automated alerting capabilities.