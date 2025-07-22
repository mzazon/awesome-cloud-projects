# Infrastructure as Code for IoT Certificate Security with X.509 Authentication

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Certificate Security with X.509 Authentication".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a comprehensive IoT security framework including:

- **IoT Core Resources**: Thing types, things, certificates, and security policies
- **Device Authentication**: X.509 certificate-based authentication for each device
- **Security Monitoring**: AWS IoT Device Defender security profiles and behavioral monitoring
- **Event Processing**: Lambda functions for security event handling and device quarantine
- **Compliance Monitoring**: CloudWatch dashboards, alarms, and logging
- **Data Storage**: DynamoDB table for security event history
- **Automated Response**: Certificate rotation monitoring and incident response capabilities

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for IoT Core, IAM, CloudWatch, DynamoDB, and Lambda
- For CDK: Node.js (for TypeScript) or Python 3.8+ (for Python)
- For Terraform: Terraform v1.0+
- Understanding of X.509 certificates and IoT security concepts
- Estimated cost: $10-15 per month for testing resources

### Required AWS Permissions

Your AWS credentials need permissions for:
- IoT Core (things, certificates, policies, security profiles)
- IAM (roles and policies for Lambda and services)
- CloudWatch (logs, metrics, dashboards, alarms)
- Lambda (function management and execution)
- DynamoDB (table creation and access)
- SNS (topics and subscriptions for alerts)
- EventBridge (rules for scheduled tasks)
- S3 (for AWS Config if compliance monitoring is enabled)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name iot-security-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=iot-security-demo \
        ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name iot-security-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-security-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan -var="project_name=iot-security-demo" -var="environment=dev"

# Apply the configuration
terraform apply -var="project_name=iot-security-demo" -var="environment=dev"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# or you can set environment variables:
# export PROJECT_NAME=iot-security-demo
# export ENVIRONMENT=dev
# ./scripts/deploy.sh
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to:

1. **Download Device Certificates**: Extract certificates from the created resources for device configuration
2. **Configure Device Clients**: Use the generated certificates in your IoT device applications
3. **Test Security Policies**: Verify that devices can only access authorized resources
4. **Monitor Security Events**: Check CloudWatch dashboards for device behavior and security alerts

### Getting IoT Endpoint

```bash
# Get your IoT endpoint for device connections
aws iot describe-endpoint --endpoint-type iot:Data-ATS
```

### Download Device Certificates

The infrastructure creates certificates for demonstration devices. In production, implement a secure certificate distribution mechanism.

## Customization

### Key Parameters

All implementations support these customization options:

- **Project Name**: Prefix for all resource names
- **Environment**: Environment identifier (dev, staging, prod)
- **Number of Demo Devices**: How many demonstration devices to create
- **Security Profile Settings**: Behavioral thresholds for anomaly detection
- **Monitoring Retention**: Log retention periods and alarm thresholds

### CloudFormation Parameters

Edit the parameter values in your deployment command or create a parameters file:

```json
[
    {
        "ParameterKey": "ProjectName",
        "ParameterValue": "iot-security-demo"
    },
    {
        "ParameterKey": "Environment",
        "ParameterValue": "production"
    },
    {
        "ParameterKey": "NumberOfDemoDevices",
        "ParameterValue": "5"
    }
]
```

### CDK Context

Modify `cdk.json` or pass context values:

```bash
cdk deploy -c projectName=my-iot-project -c environment=production
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_name = "iot-security-demo"
environment = "production"
number_of_demo_devices = 5
log_retention_days = 90
enable_device_defender = true
```

## Security Features

### 1. Certificate-Based Authentication
- Unique X.509 certificates for each device
- Secure private key generation
- Certificate lifecycle management

### 2. Fine-Grained IoT Policies
- Least privilege access controls
- Device-specific topic permissions
- Dynamic policy variables

### 3. Advanced Security Policies (Optional)
- Time-based access restrictions
- Location-based access controls
- Device quarantine capabilities

### 4. Continuous Monitoring
- AWS IoT Device Defender integration
- CloudWatch metrics and alarms
- Security event processing and storage

### 5. Automated Compliance
- Certificate expiry monitoring
- AWS Config rules for compliance
- Automated security assessments

## Device Onboarding

After deployment, follow these steps to onboard new devices:

1. **Retrieve Device Certificates**:
   ```bash
   # Get certificates for device configuration
   terraform output -json device_certificates_pem > device_certs.json
   terraform output -json device_private_keys > device_keys.json
   ```

2. **Download Amazon Root CA**:
   ```bash
   curl -o AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem
   ```

3. **Configure Device with**:
   - Device certificate (.cert.pem)
   - Device private key (.private.key)
   - Amazon Root CA certificate
   - IoT endpoint (from terraform output)

4. **Test Device Connection**:
   ```bash
   # Use AWS IoT Device SDK or MQTT client
   # Connect to: <iot_endpoint>:8883
   # Use certificate-based authentication
   ```

## Monitoring and Alerting

### CloudWatch Dashboard
Access the security dashboard:
```bash
terraform output cloudwatch_dashboard_url
```

### Security Events
Monitor security events in:
- CloudWatch Logs: `/aws/iot/security-events`
- DynamoDB Table: `{project_name}-{environment}-iot-security-events-{suffix}`

### Alerts
Configure email notifications by setting the `notification_email` variable.

## Certificate Management

### Certificate Rotation
The infrastructure includes automated certificate rotation monitoring:

- **Schedule**: Weekly checks via EventBridge
- **Lambda Function**: Monitors certificate expiry
- **Threshold**: Configurable days before expiry (default: 30 days)
- **Actions**: Generates rotation plans and notifications

### Manual Certificate Operations
```bash
# List all certificates
aws iot list-certificates

# Check certificate details
aws iot describe-certificate --certificate-id <cert-id>

# Monitor certificate health
aws logs filter-log-events --log-group-name "/aws/iot/security-events"
```

## Testing and Validation

### 1. Verify Infrastructure Deployment
```bash
# Check IoT things
aws iot list-things --thing-type-name $(terraform output -raw thing_type_name)

# Verify security profiles
aws iot list-security-profiles

# Check Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `iot-security`)]'
```

### 2. Test Security Policies
```bash
# Validate policy syntax
aws iot validate-security-profile-behaviors --behaviors file://security_behaviors.json

# Check policy attachments
aws iot list-attached-policies --target <certificate-arn>
```

### 3. Monitor Security Events
```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name Connect.Success \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum

# Query security events
aws dynamodb scan --table-name <security-events-table>
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name iot-security-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name iot-security-stack
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy -var="project_name=iot-security-demo" -var="environment=dev"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources in this order:

1. Detach and delete IoT policies from certificates
2. Detach certificates from things
3. Delete certificates (deactivate first)
4. Delete IoT things and thing types
5. Delete Lambda functions and IAM roles
6. Delete CloudWatch resources
7. Delete DynamoDB tables

## Security Considerations

### Default Security Features

- **Certificate-based Authentication**: Each device uses unique X.509 certificates
- **Least Privilege Policies**: IoT policies restrict device access to authorized resources only
- **Behavioral Monitoring**: Device Defender detects anomalous device behavior
- **Encryption in Transit**: All communications use TLS 1.2 or higher
- **Audit Logging**: Comprehensive logging of all IoT operations

### Production Hardening

For production deployments, consider:

1. **Certificate Management**: Implement proper certificate lifecycle management
2. **Network Isolation**: Use VPC endpoints for private connectivity
3. **Key Storage**: Consider AWS CloudHSM for certificate authority operations
4. **Monitoring**: Enhance monitoring with additional security metrics
5. **Compliance**: Configure additional controls for regulatory requirements

## Monitoring and Troubleshooting

### CloudWatch Resources

The infrastructure creates:

- **Dashboard**: IoT Security Dashboard with key metrics
- **Log Groups**: Device connection and security event logs
- **Alarms**: Automated alerts for security violations
- **Metrics**: Custom metrics for device behavior analysis

### Common Issues

1. **Certificate Errors**: Verify certificate activation and policy attachment
2. **Connection Failures**: Check IoT endpoint configuration and TLS settings
3. **Policy Violations**: Review IoT policy permissions and device attributes
4. **Monitoring Gaps**: Verify Device Defender security profile configuration

### Debugging Commands

```bash
# Check device registration
aws iot list-things --thing-type-name IndustrialSensor

# Verify certificate status
aws iot list-certificates --page-size 50

# Check security profile status
aws iot describe-security-profile --security-profile-name IndustrialSensorSecurity

# View recent security events
aws logs filter-log-events \
    --log-group-name "/aws/iot/security-events" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cost Optimization

### Cost Factors

- **IoT Core**: Message charges and device registry storage
- **CloudWatch**: Log storage and custom metrics
- **Lambda**: Function invocations for event processing
- **DynamoDB**: Storage and read/write capacity
- **Device Defender**: Security profile evaluations

### Optimization Tips

1. **Log Retention**: Adjust CloudWatch log retention periods
2. **Monitoring Frequency**: Optimize Device Defender evaluation frequency
3. **Demo Resources**: Remove demo devices in production
4. **Reserved Capacity**: Consider DynamoDB reserved capacity for predictable workloads

## Integration Examples

### Device Client Code

```python
# Example Python client using generated certificates
import paho.mqtt.client as mqtt
import ssl
import json

def create_secure_client(thing_name, cert_file, key_file, ca_file):
    client = mqtt.Client(thing_name)
    
    # Configure TLS
    client.tls_set(ca_certs=ca_file,
                   certfile=cert_file,
                   keyfile=key_file,
                   cert_reqs=ssl.CERT_REQUIRED,
                   tls_version=ssl.PROTOCOL_TLS)
    
    return client
```

### Custom Security Policies

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iot:Connect",
            "Resource": "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
            "Condition": {
                "Bool": {
                    "iot:Connection.Thing.IsAttached": "true"
                }
            }
        }
    ]
}
```

## Support

### Documentation References

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [AWS IoT Device Defender](https://docs.aws.amazon.com/iot/latest/developerguide/device-defender.html)
- [IoT Security Best Practices](https://docs.aws.amazon.com/iot/latest/developerguide/security-best-practices.html)

### Common Resources

- Original recipe documentation: `../iot-security-device-certificates-policies.md`
- AWS IoT Policy Examples: [AWS Documentation](https://docs.aws.amazon.com/iot/latest/developerguide/iot-policies.html)
- Certificate Management: [AWS Certificate Management](https://docs.aws.amazon.com/iot/latest/developerguide/x509-client-certs.html)

### Getting Help

For issues with:
- **Infrastructure deployment**: Check CloudFormation/CDK/Terraform logs
- **Device connectivity**: Verify certificates and IoT policies
- **Security monitoring**: Review Device Defender configuration
- **Cost concerns**: Use AWS Cost Explorer and billing alerts

For questions about the implementation, refer to the original recipe documentation or AWS support resources.

## Customization

### Adding New Device Types
1. Modify `factory_locations` variable
2. Update device attributes in `aws_iot_thing` resource
3. Create type-specific security policies if needed

### Extending Security Monitoring
1. Add new behaviors to Device Defender security profile
2. Create additional CloudWatch alarms
3. Enhance Lambda functions for custom processing

### Integration with External Systems
1. Modify Lambda functions to integrate with SIEM
2. Add API Gateway for external security tool integration
3. Implement custom certificate authorities

## Cost Optimization

### Estimated Monthly Costs (us-east-1)
- **IoT Core**: $0.08 per 100,000 messages
- **Device Defender**: $0.0011 per device per month
- **CloudWatch Logs**: $0.50 per GB ingested
- **Lambda**: $0.20 per 1M requests + compute time
- **DynamoDB**: Pay-per-request pricing

### Optimization Tips
- Adjust log retention periods based on compliance requirements
- Use DynamoDB On-Demand for variable workloads
- Optimize Lambda memory allocation
- Monitor message volumes and consider batching
- Review Device Defender profile frequency

## Production Considerations

### Security Hardening
- Store certificates in hardware security modules (HSMs)
- Implement certificate pinning on devices
- Use VPC endpoints for enhanced network security
- Enable AWS CloudTrail for audit logging

### Scalability
- Use IoT Device Management for fleet management
- Implement device groups for policy management
- Consider AWS IoT SiteWise for industrial data
- Plan for certificate rotation at scale

### Compliance
- Enable AWS Config for continuous compliance
- Implement Security Hub for centralized findings
- Regular security assessments and penetration testing
- Document security procedures and incident response

## Troubleshooting

### Common Issues
1. **Certificate Authentication Failures**
   - Verify certificate is active
   - Check policy attachments
   - Validate IoT endpoint configuration

2. **Device Defender Alerts**
   - Review security profile thresholds
   - Check device behavior patterns
   - Validate legitimate vs. malicious activity

3. **Lambda Function Errors**
   - Check CloudWatch Logs for error details
   - Verify IAM permissions
   - Monitor DynamoDB capacity

### Support Resources
- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [AWS IoT Device Defender Guide](https://docs.aws.amazon.com/iot-device-defender/)
- [IoT Security Best Practices](https://docs.aws.amazon.com/iot/latest/developerguide/security-best-practices.html)

## Contributing

To improve this infrastructure:
1. Follow Terraform best practices
2. Test changes in a development environment
3. Update documentation for new features
4. Consider backward compatibility

## License

This infrastructure code is provided as an example implementation for the IoT Security recipe. Modify as needed for your specific requirements and compliance needs.