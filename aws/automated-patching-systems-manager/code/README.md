# Infrastructure as Code for Automated Patching with Systems Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Patching with Systems Manager".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with Systems Manager and EC2 permissions
- EC2 instances with SSM Agent installed and proper IAM roles
- Appropriate IAM permissions for creating:
  - Systems Manager resources (patch baselines, maintenance windows)
  - IAM roles and policies
  - S3 buckets
  - SNS topics
  - CloudWatch alarms

## Quick Start

### Using CloudFormation

```bash
aws cloudformation create-stack \
    --stack-name automated-patching-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PatchGroupName,ParameterValue=Production \
                 ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install
npm run build
cdk deploy --parameters NotificationEmail=admin@example.com
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt
cdk deploy --parameters NotificationEmail=admin@example.com
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan -var="notification_email=admin@example.com"
terraform apply -var="notification_email=admin@example.com"
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Options

### CloudFormation Parameters

- `PatchGroupName`: Name of the patch group (default: Production)
- `NotificationEmail`: Email address for patch notifications
- `MaintenanceWindowSchedule`: Cron expression for patching window (default: Sunday 2 AM UTC)
- `ScanWindowSchedule`: Cron expression for scanning window (default: Daily 1 AM UTC)
- `PatchConcurrency`: Maximum percentage of instances to patch simultaneously (default: 50%)
- `PatchErrorThreshold`: Maximum percentage of patch failures allowed (default: 10%)

### CDK Context Variables

Set these in `cdk.context.json` or pass as parameters:

```json
{
  "patchGroupName": "Production",
  "notificationEmail": "admin@example.com",
  "maintenanceWindowSchedule": "cron(0 2 ? * SUN *)",
  "scanWindowSchedule": "cron(0 1 * * ? *)",
  "patchConcurrency": "50%",
  "patchErrorThreshold": "10%"
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
notification_email = "admin@example.com"
patch_group_name = "Production"
maintenance_window_schedule = "cron(0 2 ? * SUN *)"
scan_window_schedule = "cron(0 1 * * ? *)"
patch_concurrency = "50%"
patch_error_threshold = "10%"
```

## Deployed Resources

This infrastructure creates the following AWS resources:

- **Systems Manager Patch Baseline**: Custom patch baseline for approved patches
- **Maintenance Windows**: Scheduled windows for patching and scanning operations
- **IAM Role**: Service role for Systems Manager operations
- **S3 Bucket**: Storage for patch operation logs and reports
- **SNS Topic**: Notification topic for patch compliance alerts
- **CloudWatch Alarms**: Monitoring for patch compliance status
- **Patch Group Association**: Links patch baseline to target instances

## Target Instance Requirements

Instances must meet these requirements to be managed by this solution:

1. **SSM Agent**: Must be installed and running
2. **IAM Role**: Must have `AmazonSSMManagedInstanceCore` policy attached
3. **Tags**: Must have `Environment=Production` tag (or customize target selection)
4. **Network**: Must have internet access or VPC endpoints for Systems Manager

## Maintenance Windows

### Patching Window
- **Schedule**: Every Sunday at 2:00 AM UTC (configurable)
- **Duration**: 4 hours
- **Cutoff**: 1 hour before window ends
- **Operation**: Install approved patches
- **Concurrency**: 50% of instances (configurable)
- **Error Threshold**: 10% failure rate (configurable)

### Scanning Window
- **Schedule**: Daily at 1:00 AM UTC (configurable)
- **Duration**: 2 hours
- **Cutoff**: 1 hour before window ends
- **Operation**: Scan for missing patches
- **Concurrency**: 100% of instances
- **Error Threshold**: 5% failure rate

## Monitoring and Alerting

- **CloudWatch Alarms**: Monitor patch compliance metrics
- **SNS Notifications**: Email alerts for compliance issues
- **S3 Logging**: Detailed logs of all patch operations
- **Compliance Reports**: Available through Systems Manager console

## Security Considerations

- IAM roles follow least privilege principle
- All resources use appropriate encryption
- Patch baselines include security patches with 7-day approval delay
- Logging enabled for audit trails
- Network access controlled through security groups

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name automated-patching-stack
```

### Using CDK

```bash
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Modifying Patch Approval Rules

To customize which patches are approved:

1. Edit the patch baseline configuration
2. Modify the `ApprovalRules` to include different classifications
3. Adjust the `ApproveAfterDays` value for your testing timeline
4. Update compliance levels as needed

### Changing Maintenance Schedules

To modify maintenance window timing:

1. Update the cron expressions in parameters/variables
2. Adjust window duration and cutoff times
3. Consider timezone requirements for your operations

### Adding Instance Targeting

To target different instances:

1. Modify the target selection criteria
2. Update tags or use different selection methods
3. Consider creating multiple maintenance windows for different environments

## Troubleshooting

### Common Issues

1. **SSM Agent Not Running**: Verify SSM Agent is installed and running on target instances
2. **IAM Permissions**: Ensure instances have proper IAM roles for Systems Manager
3. **Network Connectivity**: Verify instances can reach Systems Manager endpoints
4. **Patch Failures**: Check CloudWatch logs for detailed error information

### Monitoring Commands

```bash
# Check patch compliance
aws ssm describe-instance-patch-states

# View maintenance window executions
aws ssm describe-maintenance-window-executions --window-id WINDOW_ID

# Monitor CloudWatch alarms
aws cloudwatch describe-alarms --alarm-names PatchComplianceAlarm
```

## Cost Considerations

- Systems Manager Patch Manager core features are free
- Charges apply for:
  - EC2 instance hours during patching
  - S3 storage for logs
  - CloudWatch metrics and alarms
  - SNS message delivery

Estimated monthly cost: $0.10-$2.00 per managed instance

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../automated-patching-maintenance-windows-systems-manager.md)
- [AWS Systems Manager documentation](https://docs.aws.amazon.com/systems-manager/)
- [AWS Patch Manager User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html)

## Best Practices

1. **Test in Non-Production**: Always test patch baselines in development environments first
2. **Monitor Compliance**: Set up regular compliance reporting and review
3. **Gradual Rollout**: Start with lower concurrency settings and increase as confidence builds
4. **Backup Strategy**: Ensure proper backup procedures before major patching cycles
5. **Documentation**: Maintain documentation of approved patches and exceptions