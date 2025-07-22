# IoT Device Provisioning and Certificate Management - Terraform Infrastructure

This Terraform configuration deploys a complete IoT device provisioning and certificate management solution on AWS. The infrastructure implements automated, secure device onboarding using AWS IoT Core fleet provisioning capabilities with validation hooks and comprehensive monitoring.

## Architecture Overview

The solution deploys the following components:

- **AWS IoT Core**: Fleet provisioning templates and device management
- **AWS Lambda**: Pre-provisioning hooks for device validation
- **Amazon DynamoDB**: Device registry for tracking device lifecycle
- **AWS IAM**: Fine-grained security policies and roles
- **Amazon CloudWatch**: Monitoring and alerting for provisioning events
- **AWS IoT Policies**: Device-specific permissions for secure communication

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- AWS account with appropriate permissions for:
  - AWS IoT Core
  - AWS Lambda
  - Amazon DynamoDB
  - AWS IAM
  - Amazon CloudWatch
  - Amazon SNS (optional, for alerts)

## Quick Start

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Review and customize variables** (optional):
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your desired values
   ```

3. **Plan the deployment**:
   ```bash
   terraform plan
   ```

4. **Deploy the infrastructure**:
   ```bash
   terraform apply
   ```

5. **Note the outputs** for use in your device provisioning workflows.

## Configuration Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` |
| `environment` | Environment name (dev/staging/prod) | `dev` |
| `resource_prefix` | Prefix for resource names | `iot-provisioning` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `device_types` | List of supported device types | `["temperature-sensor", "humidity-sensor", "pressure-sensor", "gateway"]` |
| `enable_monitoring` | Enable CloudWatch monitoring | `true` |
| `enable_audit_logging` | Enable audit logging | `true` |
| `lambda_timeout` | Lambda function timeout (seconds) | `60` |
| `lambda_memory_size` | Lambda function memory (MB) | `256` |
| `dynamodb_billing_mode` | DynamoDB billing mode | `PAY_PER_REQUEST` |
| `alarm_threshold` | CloudWatch alarm threshold | `5` |
| `sns_endpoint` | Email for SNS alerts | `""` |
| `additional_tags` | Additional tags for resources | `{}` |

## Example terraform.tfvars

```hcl
aws_region      = "us-west-2"
environment     = "prod"
resource_prefix = "my-iot-provisioning"

device_types = [
  "temperature-sensor",
  "humidity-sensor",
  "pressure-sensor",
  "gateway",
  "actuator"
]

enable_monitoring     = true
enable_audit_logging  = true
lambda_timeout        = 90
lambda_memory_size    = 512
sns_endpoint         = "alerts@example.com"

additional_tags = {
  Owner       = "IoT-Team"
  CostCenter  = "Engineering"
  Compliance  = "Required"
}
```

## Key Outputs

After successful deployment, Terraform will output:

- **provisioning_template_name**: Name of the IoT provisioning template
- **claim_certificate_id**: ID of the claim certificate for device manufacturing
- **device_registry_table_name**: Name of the DynamoDB device registry table
- **provisioning_hook_function_name**: Name of the Lambda validation function
- **iot_endpoint**: AWS IoT Core endpoint for device connections
- **deployment_instructions**: Detailed next steps and usage instructions

## Security Features

### IAM Policies
- **Least Privilege**: Each component has minimal required permissions
- **Resource-Specific**: Policies are scoped to specific resources where possible
- **Separation of Concerns**: Different roles for different functions

### Device Validation
- **Pre-Provisioning Hook**: Lambda function validates devices before certificate issuance
- **Device Registry**: Tracks device status and prevents duplicate provisioning
- **Claim Certificates**: Bootstrap certificates with limited permissions

### Monitoring and Auditing
- **CloudWatch Logs**: Comprehensive logging of all provisioning events
- **CloudWatch Alarms**: Alerts on provisioning failures
- **IoT Rules**: Real-time event processing for audit trails

## Device Provisioning Workflow

1. **Manufacturing**: Devices are embedded with claim certificates during manufacturing
2. **Provisioning Request**: Device uses claim certificate to request operational certificate
3. **Validation**: Lambda hook validates device metadata and authorization
4. **Certificate Issuance**: AWS IoT Core generates unique device certificate
5. **Policy Attachment**: Device-specific policies are attached automatically
6. **Thing Registration**: Device is registered as AWS IoT Thing with metadata
7. **Group Assignment**: Device is added to appropriate thing groups
8. **Shadow Initialization**: Device shadow is created with initial configuration

## Testing the Deployment

### 1. Verify Core Components

```bash
# Check provisioning template
aws iot describe-provisioning-template --template-name $(terraform output -raw provisioning_template_name)

# Verify device registry table
aws dynamodb describe-table --table-name $(terraform output -raw device_registry_table_name)

# Test Lambda function
aws lambda invoke --function-name $(terraform output -raw provisioning_hook_function_name) \
  --payload '{"parameters":{"SerialNumber":"TEST123","DeviceType":"temperature-sensor","Manufacturer":"TestCorp","FirmwareVersion":"v1.0.0","Location":"TestLab"}}' \
  response.json && cat response.json
```

### 2. Simulate Device Provisioning

```bash
# Create test device data
cat > test-device.json << 'EOF'
{
  "parameters": {
    "SerialNumber": "SN123456789",
    "DeviceType": "temperature-sensor",
    "FirmwareVersion": "v1.2.3",
    "Manufacturer": "AcmeIoT",
    "Location": "Factory-Floor-A"
  },
  "certificatePem": "-----BEGIN CERTIFICATE-----\nMIIBXTCCAP...TEST...CERTIFICATE\n-----END CERTIFICATE-----",
  "templateArn": "arn:aws:iot:us-east-1:123456789012:provisioningtemplate/test-template"
}
EOF

# Test the provisioning hook
aws lambda invoke --function-name $(terraform output -raw provisioning_hook_function_name) \
  --payload file://test-device.json \
  hook-response.json && cat hook-response.json
```

### 3. Verify Device Registry

```bash
# Check if test device was registered
aws dynamodb get-item \
  --table-name $(terraform output -raw device_registry_table_name) \
  --key '{"serialNumber":{"S":"SN123456789"}}'
```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View Lambda function logs
aws logs filter-log-events \
  --log-group-name "/aws/lambda/$(terraform output -raw provisioning_hook_function_name)" \
  --start-time $(date -d '1 hour ago' +%s)000

# View IoT provisioning logs (if enabled)
aws logs filter-log-events \
  --log-group-name "/aws/iot/provisioning" \
  --start-time $(date -d '1 hour ago' +%s)000
```

### CloudWatch Metrics

```bash
# Check provisioning failures
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=$(terraform output -raw provisioning_hook_function_name) \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Customization and Extension

### Adding New Device Types

1. Update the `device_types` variable in your `terraform.tfvars`:
   ```hcl
   device_types = [
     "temperature-sensor",
     "humidity-sensor", 
     "pressure-sensor",
     "gateway",
     "new-device-type"  # Add new type
   ]
   ```

2. Create a new IoT policy for the device type:
   ```hcl
   resource "aws_iot_policy" "new_device_policy" {
     name = "NewDevicePolicy"
     policy = jsonencode({
       # Define policy document
     })
   }
   ```

3. Update the Lambda function to handle the new device type validation logic.

### Enhancing Security

1. **Certificate Rotation**: Implement automated certificate rotation using AWS IoT Device Management Jobs
2. **HSM Integration**: Use AWS CloudHSM for hardware-backed certificate storage
3. **Device Attestation**: Add hardware attestation validation in the pre-provisioning hook
4. **Network Security**: Implement VPC endpoints for enhanced network security

### Scaling Considerations

1. **DynamoDB**: Consider provisioned capacity for high-volume provisioning
2. **Lambda**: Increase memory and timeout for complex validation logic
3. **Multi-Region**: Deploy across multiple regions for global device support
4. **Caching**: Implement caching for frequently accessed device data

## Cleanup

To remove all resources created by this Terraform configuration:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including:
- Device registry data
- Provisioning templates
- Claim certificates
- CloudWatch logs
- All associated IAM roles and policies

Make sure to backup any important data before running destroy.

## Cost Optimization

### Estimated Monthly Costs (US East 1)

- **AWS IoT Core**: $0.08 per million messages
- **Lambda**: $0.20 per million requests + $0.0000166667 per GB-second
- **DynamoDB**: $0.25 per million read/write requests (Pay-per-Request)
- **CloudWatch**: $0.50 per million API requests
- **Data Transfer**: $0.09 per GB (first 1GB free)

### Cost Optimization Tips

1. Use DynamoDB Pay-per-Request for variable workloads
2. Implement Lambda reserved concurrency for predictable workloads
3. Set appropriate log retention periods
4. Use lifecycle policies for long-term log storage
5. Monitor and optimize certificate generation frequency

## Support and Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure AWS credentials have sufficient permissions
2. **Lambda Timeout**: Increase `lambda_timeout` for complex validation logic
3. **DynamoDB Throttling**: Consider provisioned capacity for high-volume scenarios
4. **Certificate Errors**: Verify claim certificate format and permissions

### Getting Help

- Review AWS IoT Core documentation
- Check CloudWatch logs for detailed error messages
- Verify IAM permissions and policies
- Contact AWS support for service-specific issues

### Useful Resources

- [AWS IoT Core Developer Guide](https://docs.aws.amazon.com/iot/latest/developerguide/)
- [AWS IoT Device Provisioning](https://docs.aws.amazon.com/iot/latest/developerguide/provision-wo-cert.html)
- [AWS IoT Security Best Practices](https://docs.aws.amazon.com/iot/latest/developerguide/security-best-practices.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

When contributing to this infrastructure:

1. Follow Terraform best practices
2. Add appropriate variable validation
3. Include comprehensive comments
4. Update documentation for new features
5. Test changes in development environment first
6. Consider backward compatibility

## License

This infrastructure code is provided as-is under the MIT License. See the recipe documentation for full terms and conditions.