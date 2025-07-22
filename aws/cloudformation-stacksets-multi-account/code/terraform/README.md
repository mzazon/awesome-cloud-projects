# CloudFormation StackSets Multi-Account Multi-Region Terraform Implementation

This Terraform configuration deploys a comprehensive CloudFormation StackSets solution for managing governance policies across multiple AWS accounts and regions within an AWS Organizations structure.

## Architecture Overview

The implementation creates:

- **StackSet Administrator Role**: Enables centralized StackSet management
- **Execution Role StackSet**: Deploys cross-account execution roles
- **Governance StackSet**: Deploys organization-wide security policies
- **Monitoring Infrastructure**: CloudWatch dashboards, alarms, and drift detection
- **Automation**: Lambda-based drift detection with SNS notifications

## Features

### Core StackSet Components
- Service-managed permissions with AWS Organizations integration
- Auto-deployment to new accounts in organizational units
- Multi-region deployment with configurable operation preferences
- Comprehensive template management in S3

### Governance Policies
- IAM password policies with configurable compliance levels
- Multi-region CloudTrail with KMS encryption
- AWS Config for compliance monitoring
- GuardDuty for threat detection
- S3 bucket policies and encryption

### Monitoring and Alerting
- CloudWatch dashboards for StackSet operations
- SNS notifications for operation failures
- Automated drift detection with Lambda
- Comprehensive logging and audit trails

### Security Features
- KMS encryption for all audit logs
- Least privilege IAM policies
- Cross-account role-based access
- Multi-region backup and replication

## Prerequisites

1. **AWS Organizations Setup**:
   - Management account with Organizations enabled
   - Target accounts joined to the organization
   - Organizational units (OUs) configured (optional)

2. **AWS CLI Configuration**:
   ```bash
   aws configure
   # Ensure you're authenticated with the management account
   ```

3. **Terraform Installation**:
   ```bash
   # Install Terraform >= 1.0
   terraform --version
   ```

4. **Required Permissions**:
   - `AWSCloudFormationFullAccess`
   - `AWSOrganizationsFullAccess`
   - `IAMFullAccess`
   - `S3FullAccess`
   - `CloudWatchFullAccess`
   - `SNSFullAccess`
   - `LambdaFullAccess`

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Core configuration
aws_region = "us-east-1"
environment = "production"
project_name = "stacksets-governance"

# Target deployment
target_accounts = ["123456789012", "234567890123"]
target_regions = ["us-east-1", "us-west-2", "eu-west-1"]

# Optional: Target organizational units instead of accounts
# target_organizational_units = ["ou-root-1a2b3c4d5e", "ou-root-2f3g4h5i6j"]

# Governance configuration
compliance_level = "standard"

# Monitoring
enable_monitoring = true
alert_email = "admin@example.com"

# Operation preferences
operation_preferences = {
  region_concurrency_type      = "PARALLEL"
  max_concurrent_percentage    = 50
  failure_tolerance_percentage = 10
}
```

### 3. Plan and Deploy

```bash
# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Check StackSet status
aws cloudformation describe-stack-set \
    --stack-set-name $(terraform output -raw governance_stackset_name) \
    --region $(terraform output -raw aws_region)

# List stack instances
aws cloudformation list-stack-instances \
    --stack-set-name $(terraform output -raw governance_stackset_name) \
    --region $(terraform output -raw aws_region)
```

## Configuration Options

### Compliance Levels

#### Basic (`compliance_level = "basic"`)
- 8-character minimum password length
- MFA not required
- Basic CloudTrail logging
- Standard GuardDuty settings

#### Standard (`compliance_level = "standard"`)
- 12-character minimum password length
- MFA required for users
- Full CloudTrail logging
- Enhanced GuardDuty settings

#### Strict (`compliance_level = "strict"`)
- 16-character minimum password length
- MFA required for users
- Full CloudTrail logging with insights
- Maximum GuardDuty settings

### Deployment Targets

#### Account-Based Deployment
```hcl
target_accounts = ["123456789012", "234567890123"]
target_organizational_units = []
```

#### Organizational Unit-Based Deployment
```hcl
target_accounts = []
target_organizational_units = ["ou-root-1a2b3c4d5e"]
```

### Operation Preferences

#### Conservative (Recommended for Production)
```hcl
operation_preferences = {
  region_concurrency_type      = "SEQUENTIAL"
  max_concurrent_percentage    = 25
  failure_tolerance_percentage = 5
}
```

#### Aggressive (For Development/Testing)
```hcl
operation_preferences = {
  region_concurrency_type      = "PARALLEL"
  max_concurrent_percentage    = 100
  failure_tolerance_percentage = 10
}
```

## Monitoring and Alerting

### CloudWatch Dashboard

Access your StackSet monitoring dashboard:
```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

### SNS Notifications

Configure email alerts for StackSet operations:
```hcl
enable_monitoring = true
alert_email = "admin@example.com"
```

### Drift Detection

Automated drift detection runs daily at 2 AM by default:
```hcl
drift_detection_schedule = "cron(0 2 * * ? *)"
```

### Manual Drift Detection

Trigger drift detection manually:
```bash
# Get Lambda function name
FUNCTION_NAME=$(terraform output -raw drift_detection_lambda_function_name)

# Invoke the function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{"stackset_name": "'$(terraform output -raw governance_stackset_name)'"}' \
    response.json
```

## Management Operations

### Update StackSet Templates

1. Modify template files in `templates/` directory
2. Run `terraform apply` to update S3 templates
3. Update StackSet:
   ```bash
   STACKSET_NAME=$(terraform output -raw governance_stackset_name)
   aws cloudformation update-stack-set \
       --stack-set-name $STACKSET_NAME \
       --template-url $(terraform output -raw governance_template_url) \
       --capabilities CAPABILITY_IAM
   ```

### Add New Accounts

For account-based deployment:
```hcl
# Add account to target_accounts in terraform.tfvars
target_accounts = ["123456789012", "234567890123", "345678901234"]
```

For OU-based deployment, accounts are added automatically when they join the OU.

### Monitor Operations

```bash
# List recent operations
STACKSET_NAME=$(terraform output -raw governance_stackset_name)
aws cloudformation list-stack-set-operations \
    --stack-set-name $STACKSET_NAME \
    --max-results 10
```

## Troubleshooting

### Common Issues

#### 1. StackSet Creation Fails
```bash
# Check Organizations integration
aws organizations describe-organization

# Verify trusted access
aws organizations list-aws-service-access-for-organization
```

#### 2. Stack Instance Deployment Fails
```bash
# Check execution role in target account
aws sts assume-role \
    --role-arn "arn:aws:iam::TARGET_ACCOUNT:role/AWSCloudFormationStackSetExecutionRole" \
    --role-session-name "StackSetTest"
```

#### 3. Drift Detection Issues
```bash
# Check Lambda logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/stackset-drift-detection"

# View recent logs
aws logs tail "/aws/lambda/stackset-drift-detection-XXXX" --follow
```

### Debugging Commands

```bash
# Get validation commands
terraform output validation_commands

# Check StackSet status
terraform output -json validation_commands | jq -r '.describe_governance_stackset'

# List stack instances
terraform output -json validation_commands | jq -r '.list_governance_instances'
```

## Security Considerations

### IAM Policies
- Execution roles use broad permissions (`*`) for demonstration
- In production, implement least privilege access
- Regular review and rotation of cross-account roles

### Encryption
- All audit logs encrypted with KMS
- S3 buckets use AES-256 encryption
- CloudTrail logs encrypted in transit and at rest

### Network Security
- S3 buckets block all public access
- CloudTrail integrates with CloudWatch for monitoring
- VPC Flow Logs can be enabled via governance template

## Cost Optimization

### Estimated Monthly Costs

| Component | Estimated Cost |
|-----------|---------------|
| CloudTrail | $2-10 per account |
| Config | $5-15 per account |
| GuardDuty | $1-30 per account |
| S3 Storage | $0.50-5 per account |
| Lambda | $0.10-1 per execution |
| **Total** | **$8-60 per account** |

### Cost Optimization Tips

1. **Lifecycle Policies**: Automatic transition to cheaper storage
2. **Log Retention**: Configure appropriate retention periods
3. **Regional Deployment**: Deploy only to required regions
4. **Monitoring**: Use CloudWatch alarms to track costs

## Cleanup

### Gradual Cleanup (Recommended)

1. **Delete Stack Instances**:
   ```bash
   # Get cleanup commands
   terraform output -json cleanup_commands
   
   # Delete instances
   terraform output -json cleanup_commands | jq -r '.delete_governance_instances'
   ```

2. **Delete StackSets**:
   ```bash
   terraform output -json cleanup_commands | jq -r '.delete_governance_stackset'
   ```

3. **Destroy Terraform**:
   ```bash
   terraform destroy
   ```

### Complete Cleanup

```bash
# WARNING: This will delete all resources
terraform destroy -auto-approve
```

## Advanced Configuration

### Custom Templates

Modify templates in `templates/` directory:
- `execution-role-template.yaml.tpl`: Cross-account execution role
- `governance-template.yaml.tpl`: Organization-wide governance policies

### Custom Lambda Functions

Extend drift detection in `lambda/drift_detection.py.tpl`:
- Add custom remediation logic
- Integrate with ticketing systems
- Enhanced reporting capabilities

### Multi-Organization Support

For complex enterprise scenarios:
```hcl
# Configure multiple organization deployments
# (Requires custom implementation)
```

## Support and Documentation

### AWS Documentation
- [CloudFormation StackSets User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html)
- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/)
- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/)

### Terraform Documentation
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [CloudFormation StackSet Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudformation_stack_set)

### Community Resources
- [AWS StackSets Workshop](https://stacksets.workshop.aws/)
- [AWS CloudFormation GitHub](https://github.com/aws-cloudformation)

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the MIT License. See LICENSE file for details.

---

**Note**: This implementation is designed for production use but should be thoroughly tested in a development environment before deploying to production accounts.