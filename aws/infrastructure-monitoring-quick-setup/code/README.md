# Infrastructure as Code for Infrastructure Monitoring Setup with Systems Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Monitoring Setup with Systems Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - IAM role creation and policy attachment
  - Systems Manager parameter creation and associations
  - CloudWatch dashboard, alarm, and log group management
  - EC2 instance access for monitoring validation
- At least one running EC2 instance for monitoring setup validation
- Estimated cost: $5-15 per month depending on instance count and monitoring frequency

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure monitoring stack
aws cloudformation create-stack \
    --stack-name infrastructure-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name infrastructure-monitoring-stack \
    --query 'Stacks[0].StackStatus'
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
cdk deploy

# View outputs
cdk output
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
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# The script will:
# 1. Validate prerequisites
# 2. Create IAM roles and policies
# 3. Configure CloudWatch Agent parameters
# 4. Set up monitoring dashboard and alarms
# 5. Configure compliance monitoring
# 6. Set up centralized logging
```

## Validation

After deployment, validate the monitoring setup:

### Check Systems Manager Managed Instances

```bash
# Verify managed instances
aws ssm describe-instance-information \
    --query 'InstanceInformationList[*].[InstanceId,ComputerName,ResourceType,IPAddress]' \
    --output table
```

### Validate CloudWatch Metrics

```bash
# Check CloudWatch metrics collection
aws cloudwatch list-metrics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --query 'Metrics[0:3].[MetricName,Namespace]' \
    --output table
```

### Test Alarm Functionality

```bash
# Check alarm status
aws cloudwatch describe-alarms \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table
```

### Verify Compliance Data Collection

```bash
# Check compliance summary
aws ssm list-compliance-summary-by-compliance-type \
    --query 'ComplianceSummaryItems[*].[ComplianceType,OverallSeverity,CompliantCount]' \
    --output table
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name infrastructure-monitoring-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name infrastructure-monitoring-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before:
# 1. Removing CloudWatch alarms and dashboards
# 2. Deleting Systems Manager associations
# 3. Removing CloudWatch log groups
# 4. Cleaning up SSM parameters and IAM resources
```

## Customization

### Variables and Parameters

Each implementation uses configurable variables for customization:

- **Environment**: Tag value for resource organization (default: "production")
- **MonitoringInterval**: Metrics collection interval in seconds (default: 300)
- **CPUThreshold**: CPU utilization alarm threshold percentage (default: 80)
- **DiskThreshold**: Disk usage alarm threshold percentage (default: 85)
- **LogRetentionDays**: CloudWatch log retention period (default: 30)
- **PatchScanningSchedule**: Patch compliance scanning frequency (default: "rate(7 days)")

### CloudFormation Parameters

```bash
# Deploy with custom parameters
aws cloudformation create-stack \
    --stack-name infrastructure-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=staging \
        ParameterKey=CPUThreshold,ParameterValue=70 \
        ParameterKey=LogRetentionDays,ParameterValue=14
```

### Terraform Variables

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
environment = "staging"
cpu_threshold = 70
disk_threshold = 80
log_retention_days = 14
monitoring_interval = 60
EOF

terraform apply
```

### CDK Context

```bash
# Set CDK context variables
cdk deploy \
    --context environment=staging \
    --context cpuThreshold=70 \
    --context logRetentionDays=14
```

## Architecture Components

The infrastructure creates the following resources:

### IAM Resources
- Service role for Systems Manager operations
- Policies for EC2 instance management and CloudWatch operations

### Systems Manager Configuration
- CloudWatch Agent configuration in Parameter Store
- Compliance associations for inventory collection
- Patch baseline associations for security scanning

### CloudWatch Resources
- Infrastructure monitoring dashboard
- CPU and disk utilization alarms
- Log groups for system and application logs
- Metric collection for performance monitoring

### Monitoring and Compliance
- Automated inventory collection (daily)
- Patch compliance scanning (weekly)
- Real-time performance metrics
- Centralized log aggregation

## Best Practices Implemented

- **Security**: IAM roles follow least privilege principle
- **Cost Optimization**: Log retention policies prevent indefinite storage costs
- **Operational Excellence**: Automated compliance monitoring and alerting
- **Reliability**: Multi-metric monitoring with configurable thresholds
- **Performance**: Efficient metric collection intervals
- **Sustainability**: Resource tagging for cost allocation and governance

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Verify IAM policies allow Systems Manager and CloudWatch operations

2. **No Managed Instances**
   - Check that EC2 instances have SSM Agent installed and running
   - Verify instances have appropriate IAM instance profile

3. **Missing Metrics**
   - Allow time for initial metric collection (5-10 minutes)
   - Check CloudWatch Agent installation and configuration

4. **Alarm State Issues**
   - Verify metric data is available before alarms evaluate
   - Check alarm thresholds are appropriate for your workload

### Logs and Debugging

```bash
# Check Systems Manager agent status
aws ssm describe-instance-information \
    --instance-information-filter-list "key=ResourceType,valueSet=EC2Instance"

# View CloudWatch Agent logs
aws logs describe-log-streams \
    --log-group-name "/aws/amazoncloudwatch-agent"

# Check association execution history
aws ssm describe-association-executions \
    --association-id <association-id>
```

## Cost Considerations

- **Systems Manager**: No additional charges for Quick Setup
- **CloudWatch Metrics**: Standard CloudWatch metric charges apply
- **CloudWatch Logs**: Charges based on ingestion and storage
- **CloudWatch Alarms**: Standard alarm pricing
- **CloudWatch Dashboards**: No charge for up to 3 dashboards

Estimated monthly costs range from $5-15 depending on:
- Number of monitored instances
- Frequency of metric collection
- Log volume and retention settings
- Number of custom metrics

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for detailed implementation guidance
2. Check AWS Systems Manager documentation for service-specific troubleshooting
3. Consult CloudWatch documentation for monitoring best practices
4. Use AWS Support for account-specific issues

## Extensions

Consider these enhancements for production environments:

- **Multi-Account Setup**: Deploy across AWS Organizations for centralized monitoring
- **Custom Metrics**: Add application-specific monitoring with CloudWatch Agent
- **Automated Remediation**: Integrate with Systems Manager Automation documents
- **Advanced Alerting**: Configure SNS topics for multi-channel notifications
- **Anomaly Detection**: Enable CloudWatch Anomaly Detection for dynamic baselines