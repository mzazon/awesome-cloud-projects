# Infrastructure as Code for Governing Costs with Strategic Resource Tagging

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Governing Costs with Strategic Resource Tagging".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Config (ConfigServiceRole permissions)
  - AWS Cost Explorer access
  - IAM role creation and policy attachment
  - S3 bucket creation and management
  - Lambda function creation and execution
  - SNS topic creation and subscription
  - EC2, S3, and RDS resource management
- Cost Explorer enabled in your AWS account
- Billing access for cost allocation tag activation

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name tagging-strategy-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@company.com
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npx cdk bootstrap  # Only needed first time in account/region
npx cdk deploy --parameters notificationEmail=your-email@company.com
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # Only needed first time in account/region
cdk deploy --parameters notificationEmail=your-email@company.com
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="notification_email=your-email@company.com"
terraform apply -var="notification_email=your-email@company.com"
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
export NOTIFICATION_EMAIL="your-email@company.com"
./scripts/deploy.sh
```

## What Gets Deployed

This infrastructure code deploys a complete resource tagging strategy for cost management including:

### Core Components
- **AWS Config Service**: Configuration recorder and delivery channel for continuous compliance monitoring
- **Config Rules**: Four compliance rules validating required tags (CostCenter, Environment, Project, Owner)
- **S3 Bucket**: Secure storage for AWS Config configuration snapshots and compliance reports
- **IAM Roles**: Service roles for AWS Config and Lambda with least privilege permissions

### Automation & Remediation
- **Lambda Function**: Automated tag remediation function that applies default tags to non-compliant resources
- **SNS Topic**: Notification system for tag compliance alerts and remediation notifications
- **CloudWatch Logs**: Centralized logging for Lambda function execution and troubleshooting

### Demo Resources
- **Tagged EC2 Instance**: Sample t2.micro instance demonstrating proper tag implementation
- **Tagged S3 Bucket**: Sample storage bucket with comprehensive tag taxonomy applied
- **Resource Groups**: Logical groupings of resources by Environment and CostCenter tags

### Tag Taxonomy
The implementation enforces a standardized tag taxonomy with:
- **Required Tags**: CostCenter, Environment, Project, Owner
- **Optional Tags**: Application, Backup
- **Validation Rules**: Predefined allowed values for consistent cost allocation

## Post-Deployment Configuration

### 1. Confirm SNS Subscription
After deployment, check your email and confirm the SNS subscription to receive tag compliance notifications.

### 2. Activate Cost Allocation Tags
Navigate to AWS Billing Console > Cost allocation tags and activate:
- CostCenter
- Environment
- Project
- Owner
- Application

*Note: Activated tags will appear in Cost Explorer within 24 hours.*

### 3. Verify Config Rules
Check AWS Config console to ensure all compliance rules are active and evaluating resources.

## Customization

### Variables/Parameters

All implementations support these customization options:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| NotificationEmail | Email address for tag compliance notifications | - | Yes |
| ProjectName | Project identifier for resource naming | tagging-strategy | No |
| Environment | Deployment environment | development | No |
| ConfigBucketRetention | S3 bucket retention period in days | 365 | No |
| LambdaTimeout | Lambda function timeout in seconds | 60 | No |
| EnableDemoResources | Whether to create demo EC2 and S3 resources | true | No |

### CloudFormation Parameters
```yaml
Parameters:
  NotificationEmail:
    Type: String
    Description: Email address for notifications
  ProjectName:
    Type: String
    Default: tagging-strategy
  EnableDemoResources:
    Type: String
    Default: "true"
    AllowedValues: ["true", "false"]
```

### Terraform Variables
```hcl
variable "notification_email" {
  description = "Email address for tag compliance notifications"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "tagging-strategy"
}

variable "enable_demo_resources" {
  description = "Create demo EC2 instance and S3 bucket"
  type        = bool
  default     = true
}
```

### CDK Context Values
```json
{
  "notificationEmail": "your-email@company.com",
  "projectName": "tagging-strategy",
  "enableDemoResources": true
}
```

## Validation & Testing

After deployment, validate the implementation:

### 1. Check Config Rules Status
```bash
aws configservice describe-config-rules \
    --query 'ConfigRules[*].[ConfigRuleName,ConfigRuleState]' \
    --output table
```

### 2. Test Compliance Evaluation
```bash
aws configservice start-config-rules-evaluation \
    --config-rule-names required-tag-costcenter required-tag-environment

# Wait 30 seconds then check results
aws configservice get-compliance-details-by-config-rule \
    --config-rule-name required-tag-costcenter \
    --query 'EvaluationResults[*].[EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,ComplianceType]' \
    --output table
```

### 3. Verify Resource Groups
```bash
aws resource-groups list-groups \
    --query 'GroupList[?contains(Name, `tagging-strategy`)].[Name,Description]' \
    --output table
```

### 4. Test Cost Explorer Integration
```bash
# Query costs by CostCenter tag (requires activated cost allocation tags)
aws ce get-cost-and-usage \
    --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=TAG,Key=CostCenter \
    --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
    --output table
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name tagging-strategy-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="notification_email=your-email@company.com"
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Cost Considerations

### Estimated Monthly Costs
- **AWS Config**: ~$2-10/month (depending on configuration items recorded)
- **S3 Storage**: ~$1-5/month (for Config data storage)
- **Lambda**: <$1/month (for remediation function executions)
- **SNS**: <$1/month (for notification delivery)
- **Demo Resources**: ~$5-15/month (t2.micro instance + S3 storage)

### Cost Optimization Tips
- Set appropriate S3 lifecycle policies for Config data retention
- Use S3 Intelligent Tiering for Config bucket storage
- Monitor Lambda function execution metrics to optimize memory allocation
- Consider using Config rule periodic evaluation instead of configuration change triggers for less critical compliance

## Security Best Practices

This implementation follows AWS security best practices:

### IAM Principles
- **Least Privilege**: All roles have minimum required permissions
- **Service-Specific Roles**: Separate roles for Config, Lambda, and other services
- **Resource-Level Permissions**: Specific resource ARNs where possible

### Data Protection
- **S3 Bucket Security**: Server-side encryption enabled with bucket policies
- **Lambda Security**: Function runs with minimal IAM permissions
- **SNS Security**: Topic access restricted to service principals

### Compliance Features
- **Config Rules**: Continuous compliance monitoring for tag governance
- **CloudTrail Integration**: All API calls logged for audit purposes
- **Resource Tagging**: Comprehensive tagging for security and compliance tracking

## Troubleshooting

### Common Issues

**Config Rules Not Evaluating**
```bash
# Check Config service status
aws configservice describe-configuration-recorders
aws configservice describe-delivery-channels

# Restart if needed
aws configservice start-configuration-recorder --configuration-recorder-name default
```

**Lambda Function Errors**
```bash
# Check function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/tag-remediation

# View recent logs
aws logs tail /aws/lambda/tag-remediation-[function-name] --follow
```

**SNS Delivery Failures**
```bash
# Check topic and subscription status
aws sns get-topic-attributes --topic-arn arn:aws:sns:region:account:topic-name
aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:region:account:topic-name
```

**Cost Explorer Data Missing**
- Ensure cost allocation tags are activated in Billing Console
- Wait 24 hours after tag activation for data to appear
- Verify resources have required tags applied

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export AWS_DEBUG=1
export TF_LOG=DEBUG  # For Terraform
export CDK_DEBUG=true  # For CDK
```

## Integration with Existing Infrastructure

### Existing AWS Config Setup
If AWS Config is already enabled in your account:
- Update the CloudFormation/Terraform to reference existing Config resources
- Modify IAM roles to use existing Config service role
- Ensure delivery channel points to your existing S3 bucket

### Enterprise Integration
- **ITSM Integration**: Modify SNS notifications to integrate with ServiceNow or Jira
- **Cost Management Tools**: Export tag data to third-party cost management platforms
- **Compliance Frameworks**: Map tag requirements to SOC2, PCI-DSS, or other compliance standards

## Advanced Configuration

### Custom Tag Validation
Modify Lambda function to implement custom validation logic:
```python
def validate_custom_tags(config_item):
    # Add custom validation rules
    # Example: Project tag must match approved project list
    # Example: Environment tag must match deployment pipeline
    pass
```

### Multi-Account Setup
For AWS Organizations with multiple accounts:
- Deploy Config Aggregator for centralized compliance reporting
- Use AWS Organizations tag policies for enforcement
- Implement cross-account IAM roles for centralized management

### Integration with CI/CD
Add tag validation to deployment pipelines:
```bash
# Pre-deployment tag validation
aws configservice get-compliance-details-by-config-rule \
    --config-rule-name required-tag-costcenter \
    --compliance-types NON_COMPLIANT \
    --query 'length(EvaluationResults[])' \
    --output text
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS Config, Lambda, and SNS service documentation
3. Refer to the original recipe documentation for implementation details
4. Consult AWS Support for service-specific issues

## Contributing

When modifying this infrastructure code:
- Follow AWS Well-Architected principles
- Test changes in a development environment first
- Update documentation for any new parameters or features
- Validate security implications of modifications
- Ensure cost optimization recommendations are maintained