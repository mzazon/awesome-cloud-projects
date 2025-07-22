# Infrastructure as Code for Implementing Dedicated Hosts for License Compliance

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Dedicated Hosts for License Compliance". This solution provides comprehensive license management and compliance framework using AWS EC2 Dedicated Hosts, License Manager, Config, and Systems Manager.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys:
- **EC2 Dedicated Hosts** for BYOL workloads (m5 and r5 families)
- **AWS License Manager** configurations for Windows Server and Oracle licensing
- **AWS Config** rules for compliance monitoring
- **Systems Manager** inventory for license tracking
- **CloudWatch** dashboards and alarms for monitoring
- **Lambda function** for automated compliance reporting
- **SNS topics** for compliance alerts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - EC2 (Dedicated Hosts, instances, launch templates)
  - License Manager (license configurations, associations)
  - AWS Config (configuration recorders, rules)
  - Systems Manager (associations, inventory)
  - CloudWatch (dashboards, alarms)
  - Lambda (functions, execution roles)
  - SNS (topics, subscriptions)
  - IAM (roles, policies)
- Valid software licenses for BYOL (Windows Server, Oracle, etc.)
- Key pair for EC2 instance access
- Estimated cost: $100-500/month for Dedicated Hosts + software licensing costs

> **Note**: Dedicated Hosts incur hourly charges regardless of instance usage. Review [AWS Dedicated Host pricing](https://aws.amazon.com/ec2/dedicated-hosts/pricing/) for accurate cost estimates.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name dedicated-hosts-license-compliance \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-key-pair \
                 ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name dedicated-hosts-license-compliance \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name dedicated-hosts-license-compliance
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy DedicatedHostsLicenseComplianceStack \
    --parameters KeyPairName=your-key-pair \
    --parameters NotificationEmail=admin@example.com

# View outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy DedicatedHostsLicenseComplianceStack \
    --parameters KeyPairName=your-key-pair \
    --parameters NotificationEmail=admin@example.com

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan \
    -var="key_pair_name=your-key-pair" \
    -var="notification_email=admin@example.com"

# Deploy the infrastructure
terraform apply \
    -var="key_pair_name=your-key-pair" \
    -var="notification_email=admin@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export KEY_PAIR_NAME="your-key-pair"
export NOTIFICATION_EMAIL="admin@example.com"

# Deploy the solution
./scripts/deploy.sh

# The script will prompt for confirmation and provide progress updates
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `KeyPairName` | EC2 Key Pair for instance access | - | Yes |
| `NotificationEmail` | Email for compliance alerts | - | Yes |
| `WindowsLicenseCount` | Number of Windows Server licenses | 10 | No |
| `OracleLicenseCount` | Number of Oracle core licenses | 16 | No |
| `EnvironmentTag` | Environment identifier | Production | No |
| `ProjectTag` | Project identifier | LicenseCompliance | No |

### Customizing License Configurations

The solution creates license configurations for:
- **Windows Server**: Socket-based licensing (default: 10 licenses)
- **Oracle Enterprise Edition**: Core-based licensing (default: 16 licenses)

To modify license counts, update the parameters in your chosen deployment method.

### Dedicated Host Configuration

The solution allocates:
- **m5 family host**: For Windows Server and SQL Server workloads
- **r5 family host**: For Oracle Database workloads

Both hosts are configured with:
- Auto-placement disabled for precise control
- Host recovery enabled for high availability
- Comprehensive tagging for cost allocation

## Post-Deployment Configuration

### 1. Subscribe to SNS Notifications

```bash
# Get the SNS topic ARN from stack outputs
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name dedicated-hosts-license-compliance \
    --query 'Stacks[0].Outputs[?OutputKey==`ComplianceAlertsTopic`].OutputValue' \
    --output text)

# Subscribe your email to notifications
aws sns subscribe \
    --topic-arn $SNS_TOPIC_ARN \
    --protocol email \
    --notification-endpoint admin@example.com
```

### 2. Verify License Manager Configuration

```bash
# List license configurations
aws license-manager list-license-configurations \
    --query 'LicenseConfigurations[].[Name,LicenseCount,ConsumedLicenses]' \
    --output table
```

### 3. Access Compliance Dashboard

```bash
# Get dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#dashboards:name=license-compliance-dashboard"
```

## Validation and Testing

### Verify Dedicated Hosts

```bash
# Check Dedicated Host status
aws ec2 describe-hosts \
    --query 'Hosts[].[HostId,State,InstanceFamily,AvailabilityZone,HostProperties.Cores,HostProperties.Sockets]' \
    --output table
```

### Test License Compliance

```bash
# Launch a test Windows instance
aws ec2 run-instances \
    --image-id ami-0c02fb55956c7d316 \
    --instance-type m5.large \
    --key-name your-key-pair \
    --placement Tenancy=host \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-byol-instance},{Key=LicenseType,Value=WindowsServer}]'
```

### Monitor Compliance

```bash
# Check Config rule compliance
aws configservice get-compliance-details-by-config-rule \
    --config-rule-name license-compliance-host-compliance \
    --query 'EvaluationResults[].[ComplianceType,ConfigRuleInvokedTime]' \
    --output table
```

## Monitoring and Alerts

### CloudWatch Dashboards

The solution provides dashboards for:
- License utilization across all configurations
- Dedicated Host capacity and usage
- Instance placement and compliance status
- Cost tracking and optimization metrics

### Automated Alerts

Alerts are configured for:
- License utilization exceeding 80% threshold
- Instances placed outside Dedicated Hosts
- Configuration drift detection
- Compliance rule violations

### Compliance Reporting

- **Automated Reports**: Weekly compliance reports via Lambda
- **Manual Reports**: On-demand license usage reports
- **Audit Trail**: Complete configuration change history via Config

## Troubleshooting

### Common Issues

1. **Dedicated Host Allocation Failures**
   ```bash
   # Check available capacity in your region
   aws ec2 describe-host-reservation-offerings \
       --query 'OfferingSet[].[InstanceFamily,HostOfferingType,OfferingId]' \
       --output table
   ```

2. **License Association Errors**
   ```bash
   # Verify instance is on Dedicated Host
   aws ec2 describe-instances \
       --instance-ids i-1234567890abcdef0 \
       --query 'Reservations[].Instances[].[InstanceId,Placement.Tenancy,Placement.HostId]'
   ```

3. **Config Rule Non-Compliance**
   ```bash
   # Get detailed compliance information
   aws configservice get-compliance-details-by-resource \
       --resource-type AWS::EC2::Instance \
       --resource-id i-1234567890abcdef0
   ```

### Support Resources

- [AWS Dedicated Hosts User Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/dedicated-hosts-overview.html)
- [AWS License Manager User Guide](https://docs.aws.amazon.com/license-manager/latest/userguide/license-manager.html)
- [BYOL on AWS Best Practices](https://docs.aws.amazon.com/whitepapers/latest/aws-overview/aws-overview.html)

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name dedicated-hosts-license-compliance

# Wait for completion
aws cloudformation wait stack-delete-complete \
    --stack-name dedicated-hosts-license-compliance
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy DedicatedHostsLicenseComplianceStack
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy DedicatedHostsLicenseComplianceStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="key_pair_name=your-key-pair" \
    -var="notification_email=admin@example.com"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Cost Optimization

### Cost Considerations

- **Dedicated Hosts**: $2-5/hour depending on instance family
- **License Manager**: No additional charges for usage tracking
- **Config**: $0.003 per configuration item recorded
- **CloudWatch**: Standard pricing for metrics and dashboards
- **Lambda**: Minimal charges for compliance reporting function

### Optimization Strategies

1. **Right-size Dedicated Hosts**: Choose instance families that match your workload requirements
2. **Monitor Utilization**: Use CloudWatch metrics to optimize host utilization
3. **Reserved Instances**: Consider Dedicated Host Reservations for long-term workloads
4. **License Optimization**: Track usage patterns to optimize license allocation

## Security Considerations

### IAM Permissions

The solution follows least privilege principles:
- Service-specific roles with minimal required permissions
- Resource-based policies for cross-service access
- No hardcoded credentials or secrets

### Network Security

- Instances deployed in private subnets (configurable)
- Security groups with minimal required access
- VPC Flow Logs enabled for network monitoring

### Data Protection

- All data encrypted at rest and in transit
- S3 buckets with server-side encryption
- CloudWatch Logs encrypted with KMS

## Support

For issues with this infrastructure code:
1. Review the troubleshooting section above
2. Check AWS service health dashboard
3. Refer to the original recipe documentation
4. Consult AWS documentation for specific services

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any configuration changes
4. Validate compliance with organizational policies