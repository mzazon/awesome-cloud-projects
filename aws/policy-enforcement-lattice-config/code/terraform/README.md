# VPC Lattice Policy Enforcement Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive policy enforcement system that monitors VPC Lattice resources for compliance violations and provides automated remediation capabilities.

## Architecture Overview

The infrastructure deploys:

- **AWS Config** - Continuous monitoring of VPC Lattice resources
- **Lambda Functions** - Compliance evaluation and automated remediation
- **SNS Topic** - Real-time notifications for violations
- **IAM Roles** - Secure permissions for all components
- **S3 Bucket** - AWS Config delivery channel storage
- **Demo Resources** - Optional VPC Lattice resources for testing

## Features

✅ **Continuous Compliance Monitoring** - Real-time tracking of VPC Lattice configuration changes  
✅ **Automated Policy Evaluation** - Custom AWS Config rules with Lambda-based evaluation logic  
✅ **Intelligent Remediation** - Automatic correction of common compliance violations  
✅ **Multi-Channel Notifications** - Email and Lambda-based alert systems  
✅ **Comprehensive Logging** - CloudWatch integration for audit trails  
✅ **Demo Environment** - Pre-configured test resources for validation  

## Prerequisites

- **AWS CLI** installed and configured with appropriate credentials
- **Terraform** >= 1.0 installed
- **AWS Account** with permissions for:
  - VPC Lattice management
  - AWS Config configuration
  - Lambda function deployment
  - IAM role/policy management
  - SNS topic operations
  - S3 bucket operations
- **Valid Email Address** for compliance notifications

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/policy-enforcement-lattice-config/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required Variables
aws_region         = "us-west-2"
environment        = "dev"
notification_email = "your-security-team@company.com"

# Optional Customizations
project_name              = "my-lattice-compliance"
enable_auto_remediation   = true
create_demo_resources     = true
require_auth_policy       = true
service_name_prefix       = "secure-"
require_service_auth      = true

# Resource Configuration
lambda_timeout      = 120
lambda_memory_size  = 256
vpc_cidr           = "10.0.0.0/16"
```

### 4. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Confirm Email Subscription

After deployment, check your email for an SNS subscription confirmation and click the confirmation link to receive compliance notifications.

## Configuration Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `notification_email` | Email address for compliance notifications | `admin@company.com` |

### Core Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-west-2` |
| `environment` | Environment name (dev/staging/prod) | `dev` |
| `project_name` | Project name for resource naming | `lattice-compliance` |
| `enable_auto_remediation` | Enable automatic remediation | `true` |

### Compliance Policy Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `require_auth_policy` | Require auth policies on service networks | `true` |
| `service_name_prefix` | Required prefix for service network names | `secure-` |
| `require_service_auth` | Require authentication on services | `true` |

### Resource Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `lambda_timeout` | Lambda function timeout (seconds) | `120` |
| `lambda_memory_size` | Lambda memory allocation (MB) | `256` |
| `vpc_cidr` | CIDR block for demo VPC | `10.0.0.0/16` |
| `create_demo_resources` | Create demo resources for testing | `true` |

## Validation and Testing

### 1. Verify AWS Config Status

```bash
# Check Config recorder status
aws configservice describe-configuration-recorder-status \
    --region $(terraform output -raw aws_region)

# Check Config rule compliance
aws configservice get-compliance-details-by-config-rule \
    --config-rule-name $(terraform output -raw config_rule_name) \
    --region $(terraform output -raw aws_region)
```

### 2. Test Compliance Detection

If demo resources are enabled, the system will automatically detect non-compliant resources:

```bash
# View demo service network (should be non-compliant)
aws vpc-lattice get-service-network \
    --service-network-identifier $(terraform output -raw demo_service_network_id) \
    --region $(terraform output -raw aws_region)

# View demo service (should be non-compliant)
aws vpc-lattice get-service \
    --service-identifier $(terraform output -raw demo_service_id) \
    --region $(terraform output -raw aws_region)
```

### 3. Monitor Lambda Logs

```bash
# View compliance evaluator logs
aws logs tail /aws/lambda/$(terraform output -raw compliance_evaluator_function_name) \
    --follow --region $(terraform output -raw aws_region)

# View auto-remediation logs (if enabled)
aws logs tail /aws/lambda/$(terraform output -raw auto_remediation_function_name) \
    --follow --region $(terraform output -raw aws_region)
```

### 4. Test Manual Remediation

```bash
# Create a non-compliant service for testing
aws vpc-lattice create-service \
    --name "test-non-compliant-service" \
    --auth-type NONE \
    --region $(terraform output -raw aws_region)

# Wait for Config evaluation (may take 5-10 minutes)
# Check email for compliance notifications
# Monitor auto-remediation in CloudWatch logs
```

## Outputs Reference

After deployment, Terraform provides these key outputs:

```bash
# View all outputs
terraform output

# Key outputs for monitoring and validation
terraform output sns_topic_arn                    # SNS topic for notifications
terraform output compliance_evaluator_function_name # Lambda function name
terraform output config_rule_name                 # AWS Config rule name
terraform output config_bucket_name               # S3 bucket for Config
```

## Monitoring and Observability

### CloudWatch Log Groups

- **Compliance Evaluator**: `/aws/lambda/{project_name}-compliance-evaluator-{suffix}`
- **Auto-Remediation**: `/aws/lambda/{project_name}-auto-remediation-{suffix}`

### Key Metrics to Monitor

1. **Config Rule Evaluations** - Number of resources evaluated
2. **Compliance Violations** - Non-compliant resource count
3. **Lambda Invocations** - Function execution frequency
4. **SNS Message Delivery** - Notification success rate
5. **Remediation Success** - Automatic fix success rate

### CloudWatch Dashboards

Create custom dashboards to monitor:

```bash
# Example CloudWatch Insights queries
fields @timestamp, @message
| filter @message like /NON_COMPLIANT/
| sort @timestamp desc

fields @timestamp, @message  
| filter @message like /Remediation successful/
| sort @timestamp desc
```

## Customization Examples

### Custom Compliance Rules

To add custom compliance checks, modify the `compliance_evaluator.py` Lambda function:

```python
# Example: Check for specific tags
def check_required_tags(resource, required_tags):
    resource_tags = resource.get('tags', {})
    for tag_key in required_tags:
        if tag_key not in resource_tags:
            return False, f"Missing required tag: {tag_key}"
    return True, "All required tags present"
```

### Advanced Remediation Logic

Extend the `auto_remediation.py` function for complex remediation scenarios:

```python
# Example: Apply organization-specific auth policies
def apply_org_auth_policy(client, network_id, org_unit):
    # Custom logic based on organizational unit
    pass
```

### Integration with External Systems

Connect with external compliance systems using SNS:

```bash
# Add webhook subscription to SNS topic
aws sns subscribe \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --protocol https \
    --notification-endpoint https://your-compliance-system.com/webhook
```

## Troubleshooting

### Common Issues

1. **Config Recorder Not Starting**
   ```bash
   # Check IAM permissions for Config service role
   aws iam get-role-policy --role-name $(terraform output -raw config_service_role_arn | cut -d'/' -f2) --policy-name ConfigS3DeliveryRolePolicy
   ```

2. **Lambda Functions Not Triggering**
   ```bash
   # Verify Lambda permissions
   aws lambda get-policy --function-name $(terraform output -raw compliance_evaluator_function_name)
   ```

3. **SNS Notifications Not Received**
   ```bash
   # Check subscription status
   aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw sns_topic_arn)
   ```

4. **Config Rule Evaluation Errors**
   ```bash
   # Check Config rule status
   aws configservice describe-config-rules --config-rule-names $(terraform output -raw config_rule_name)
   ```

### Debug Mode

Enable debug logging by setting environment variables in the Lambda functions:

```hcl
environment {
  variables = {
    LOG_LEVEL = "DEBUG"
    # ... other variables
  }
}
```

## Security Considerations

### IAM Permissions

The infrastructure follows the principle of least privilege:

- **Config Service Role** - Minimal permissions for resource monitoring and S3 delivery
- **Lambda Execution Role** - Scoped permissions for VPC Lattice, Config, and SNS operations
- **S3 Bucket** - Restricted access with encryption enabled

### Data Protection

- **S3 Encryption** - AES-256 server-side encryption enabled
- **VPC Isolation** - Demo resources deployed in dedicated VPC
- **Secret Management** - No hardcoded credentials in code

### Compliance Features

- **Audit Trails** - All actions logged to CloudWatch
- **Change Tracking** - AWS Config maintains configuration history
- **Notification Security** - SNS topics use encryption in transit

## Cost Optimization

### Estimated Monthly Costs (us-west-2)

- **AWS Config** - ~$2-5 (configuration items and rule evaluations)
- **Lambda** - ~$1-3 (based on invocation frequency)
- **SNS** - ~$0.50 (email notifications)
- **S3 Storage** - ~$1-2 (Config delivery channel)
- **CloudWatch Logs** - ~$1-2 (log retention)

**Total Estimated Cost: $5-15/month**

### Cost Optimization Tips

1. **Adjust Config Rule Scope** - Monitor only critical resource types
2. **Optimize Lambda Memory** - Reduce memory allocation if sufficient
3. **Log Retention** - Adjust CloudWatch log retention periods
4. **S3 Lifecycle** - Implement lifecycle policies for Config bucket

## Cleanup

### Complete Infrastructure Removal

```bash
# Destroy all resources
terraform destroy
```

### Partial Cleanup (Keep Core Infrastructure)

```bash
# Remove only demo resources
terraform apply -var="create_demo_resources=false"
```

### Manual Cleanup (if needed)

If Terraform destroy fails, manually remove resources:

```bash
# Remove Config resources
aws configservice delete-config-rule --config-rule-name $(terraform output -raw config_rule_name)
aws configservice stop-configuration-recorder --configuration-recorder-name default
aws configservice delete-configuration-recorder --configuration-recorder-name default
aws configservice delete-delivery-channel --delivery-channel-name default

# Remove S3 bucket contents
aws s3 rm s3://$(terraform output -raw config_bucket_name) --recursive
```

## Advanced Usage

### Multi-Account Deployment

Deploy across multiple AWS accounts using AWS Organizations:

```hcl
# Use AWS Config aggregation for multi-account compliance
resource "aws_config_aggregate_authorization" "example" {
  account_id = var.security_account_id
  region     = var.aws_region
}
```

### Custom Policy Templates

Store reusable policy templates in Systems Manager Parameter Store:

```hcl
resource "aws_ssm_parameter" "auth_policy_template" {
  name  = "/lattice-compliance/auth-policy-template"
  type  = "String"
  value = jsonencode(var.default_auth_policy)
}
```

### Integration with AWS Security Hub

Send findings to Security Hub for centralized security management:

```python
# Add to Lambda function
security_hub = boto3.client('securityhub')
security_hub.batch_import_findings(
    Findings=[{
        'SchemaVersion': '2018-10-08',
        'Id': resource_id,
        'ProductArn': f'arn:aws:securityhub:{region}:{account_id}:product/{account_id}/lattice-compliance',
        'GeneratorId': 'lattice-compliance-evaluator',
        'AwsAccountId': account_id,
        'Types': ['Security/Compliance/Policy'],
        'Title': 'VPC Lattice Compliance Violation',
        'Description': annotation
    }]
)
```

## Support and Maintenance

### Version Updates

- **Terraform Provider Updates** - Regularly update AWS provider version
- **Lambda Runtime Updates** - Monitor Python runtime deprecation notices
- **AWS Service Updates** - Stay informed about VPC Lattice feature changes

### Monitoring Best Practices

1. **Set up CloudWatch Alarms** for Lambda errors and Config rule failures
2. **Create SNS subscriptions** for operations teams
3. **Implement log aggregation** for centralized monitoring
4. **Regular compliance reviews** using Config compliance dashboards

### Contributing

To contribute improvements:

1. Test changes in a development environment
2. Update documentation for new features
3. Ensure backward compatibility
4. Follow AWS Well-Architected Framework principles

For questions or issues, refer to the original recipe documentation or AWS service documentation.