# Infrastructure as Code for IoT Device Lifecycle Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "IoT Device Lifecycle Management".

## Overview

This infrastructure implements a comprehensive IoT device management solution using AWS IoT Device Management services. The solution provides centralized device provisioning, fleet organization, remote management capabilities, and comprehensive monitoring for IoT devices at scale.

## Architecture

The infrastructure deploys the following components:

- **AWS IoT Core**: Message broker and device registry
- **IoT Device Management**: Fleet indexing, thing groups, and device organization
- **IoT Thing Types**: Device templates and attribute schemas
- **IoT Policies**: Security and access control policies
- **CloudWatch Logs**: Centralized logging for device activities
- **IoT Jobs**: Over-the-air update and remote management capabilities
- **Device Shadows**: Device state management and offline handling
- **Fleet Metrics**: Aggregated device monitoring and analytics

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for IoT Core, Device Management, and CloudWatch
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform deployments: Terraform 1.0+

### Required AWS Permissions

The following IAM permissions are required:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:*",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name iot-device-management \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=FleetName,ParameterValue=my-fleet \
                 ParameterKey=Environment,ParameterValue=dev

# Check stack status
aws cloudformation describe-stacks \
    --stack-name iot-device-management

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name iot-device-management \
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
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws iot list-thing-types
aws iot list-thing-groups
```

## Configuration

### Environment Variables

The following environment variables can be set to customize the deployment:

- `FLEET_NAME`: Name prefix for IoT fleet resources (default: "fleet")
- `ENVIRONMENT`: Environment name (default: "dev")
- `AWS_REGION`: AWS region for deployment (default: current CLI region)
- `LOG_RETENTION_DAYS`: CloudWatch log retention in days (default: 30)

### Parameters

Each implementation supports the following customizable parameters:

- **FleetName**: Prefix for all IoT fleet resources
- **Environment**: Environment tag applied to all resources
- **DeviceCount**: Number of sample devices to create (default: 4)
- **LogRetentionDays**: CloudWatch log retention period
- **EnableFleetIndexing**: Enable IoT fleet indexing (default: true)
- **JobTimeoutMinutes**: Default timeout for IoT jobs (default: 30)

## Deployment Features

### Device Management Components

1. **Thing Types**: Standardized device templates with searchable attributes
2. **Thing Groups**: Logical organization of devices (static and dynamic)
3. **IoT Policies**: Fine-grained access control with least privilege principles
4. **Fleet Indexing**: Real-time device search and filtering capabilities
5. **Device Shadows**: Persistent device state management
6. **IoT Jobs**: Over-the-air update and remote management framework
7. **Fleet Metrics**: Aggregated monitoring and analytics

### Security Features

- Certificate-based device authentication
- IAM-based access control for management operations
- Encrypted communication channels
- Audit logging for all device activities
- Policy-based resource access control

### Monitoring and Logging

- CloudWatch log groups for device activities
- Fleet metrics for aggregate monitoring
- Device connectivity tracking
- Job execution monitoring
- Security event logging

## Testing the Deployment

After deployment, you can test the IoT device management infrastructure:

```bash
# List created thing types
aws iot list-thing-types

# List thing groups
aws iot list-thing-groups

# Search for devices by attribute
aws iot search-index \
    --index-name "AWS_Things" \
    --query-string "attributes.location:Building-A"

# Check fleet indexing status
aws iot describe-index \
    --index-name "AWS_Things"

# List IoT jobs
aws iot list-jobs

# Check fleet metrics
aws iot list-fleet-metrics
```

## Customization

### Adding New Device Types

To add additional device types, modify the thing type definitions in your chosen IaC template. Each thing type should include:

- Descriptive name and description
- Searchable attributes for fleet indexing
- Appropriate attribute validation

### Scaling Considerations

- **Device Limits**: AWS IoT Core supports millions of devices per account
- **Fleet Indexing**: Consider costs for indexed attributes and search queries
- **Job Concurrency**: Adjust job execution limits based on network capacity
- **Log Retention**: Balance monitoring needs with storage costs

### Integration Examples

The infrastructure can be extended with:

- **AWS Lambda**: Custom device management logic
- **Amazon Kinesis**: Real-time device data processing
- **Amazon S3**: Firmware and configuration file storage
- **Amazon SNS**: Device alert notifications
- **AWS Step Functions**: Complex device workflow orchestration

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name iot-device-management

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name iot-device-management
```

### Using CDK

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
aws iot list-thing-types
aws iot list-thing-groups
```

## Cost Optimization

### Cost Considerations

- **Fleet Indexing**: Charges apply for indexed attributes and search queries
- **CloudWatch Logs**: Log storage and ingestion costs
- **IoT Jobs**: Charges for job executions and data transfer
- **Device Shadows**: Storage costs for shadow documents
- **Fleet Metrics**: CloudWatch metric charges

### Optimization Strategies

1. **Selective Indexing**: Only index attributes required for search
2. **Log Retention**: Set appropriate retention periods for logs
3. **Job Batching**: Use continuous jobs for efficient updates
4. **Shadow Optimization**: Minimize shadow document size
5. **Metric Sampling**: Use appropriate sampling rates for metrics

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure AWS CLI has sufficient IoT permissions
2. **Certificate Issues**: Verify certificate attachment to devices
3. **Fleet Indexing**: Allow time for indexing to complete after deployment
4. **Policy Conflicts**: Check IoT policy syntax and resource ARNs
5. **Job Failures**: Verify job document format and device connectivity

### Debugging Steps

```bash
# Check IoT service status
aws iot describe-account-attributes

# Verify fleet indexing configuration
aws iot describe-index --index-name AWS_Things

# List device certificates
aws iot list-certificates

# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/iot/
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS IoT Device Management documentation
3. Verify AWS service limits and quotas
4. Review CloudWatch logs for error details
5. Consult AWS support for service-specific issues

## Contributing

To contribute improvements to this infrastructure:

1. Test changes in a development environment
2. Follow AWS best practices for security and cost optimization
3. Update documentation for any new features
4. Ensure backward compatibility with existing deployments

## License

This infrastructure code is provided under the same license as the parent recipe repository.