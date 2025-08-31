# AWS Well-Architected Tool Assessment - Terraform Infrastructure

This Terraform configuration creates the necessary infrastructure for conducting AWS Well-Architected Framework assessments, including workload definition, monitoring resources, and optional sample infrastructure.

## Overview

The AWS Well-Architected Tool helps you review your architectures against AWS best practices across six pillars:

- **Operational Excellence**: Running and monitoring systems
- **Security**: Protecting information and systems  
- **Reliability**: Ensuring systems recover from failures
- **Performance Efficiency**: Using computing resources effectively
- **Cost Optimization**: Avoiding unnecessary costs
- **Sustainability**: Minimizing environmental impact

This Terraform configuration automates the setup of:

- Well-Architected Tool workload for assessment
- CloudWatch dashboard for monitoring assessment progress
- SNS notifications for assessment milestones (optional)
- IAM roles for automation and API access
- Sample infrastructure for demonstration (optional)

## Architecture Components

### Core Resources

- **aws_wellarchitected_workload**: Main workload definition for assessment
- **aws_wellarchitected_milestone**: Initial milestone to track assessment progress
- **aws_iam_role**: Role for programmatic access to Well-Architected APIs
- **aws_iam_role_policy**: Permissions for Well-Architected operations

### Monitoring Resources (Optional)

- **aws_cloudwatch_log_group**: Log group for assessment activity
- **aws_cloudwatch_dashboard**: Dashboard for visualizing assessment progress
- **aws_cloudwatch_metric_alarm**: Alarm for monitoring assessment activity

### Notification Resources (Optional)

- **aws_sns_topic**: Topic for assessment notifications
- **aws_sns_topic_subscription**: Email subscription for notifications

### Sample Infrastructure (Optional)

- **aws_vpc**: Virtual Private Cloud for demonstration
- **aws_subnet**: Public subnet with internet access
- **aws_internet_gateway**: Internet gateway for public access
- **aws_security_group**: Security group with HTTP/HTTPS access

## Prerequisites

1. **AWS CLI**: Version 2.0 or later, configured with appropriate credentials
2. **Terraform**: Version 1.6 or later
3. **AWS Permissions**: IAM permissions for Well-Architected Tool, CloudWatch, SNS, and IAM operations
4. **Email Access**: Valid email address if enabling notifications

### Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "wellarchitected:*",
        "cloudwatch:*",
        "logs:*",
        "sns:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required variables
project_name = "my-application"
environment  = "production"

# Optional variables
workload_description    = "My web application for Well-Architected assessment"
industry_type          = "InfoTech"
notification_email     = "architect@company.com"
enable_notifications   = true
enable_cloudwatch_dashboard = true
create_sample_resources = false

# Additional tags
workload_tags = {
  Team        = "platform"
  Application = "web-app"
  Version     = "1.0"
}
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Access Your Assessment

After deployment, use the provided outputs to access your Well-Architected assessment:

```bash
# View outputs
terraform output

# Access workload in AWS Console (use the provided URL)
terraform output wellarchitected_console_url
```

## Configuration Options

### Basic Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Name of the project | `"well-architected-assessment"` | No |
| `environment` | Environment type | `"development"` | No |
| `workload_description` | Workload description | `"Sample web application..."` | No |
| `industry_type` | Industry classification | `"InfoTech"` | No |

### Assessment Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `architectural_design` | Architecture description | `"Three-tier web application..."` | No |
| `review_owner` | Review owner (email/ARN) | Current user ARN | No |
| `lenses` | Assessment lenses | `["wellarchitected"]` | No |
| `aws_regions` | Target regions | Current region | No |

### Optional Features

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_cloudwatch_dashboard` | Enable monitoring dashboard | `true` | No |
| `enable_notifications` | Enable SNS notifications | `false` | No |
| `notification_email` | Email for notifications | `""` | No |
| `create_sample_resources` | Create demo infrastructure | `false` | No |

## Usage Examples

### Basic Assessment Setup

```hcl
# Minimal configuration for assessment
project_name = "my-app"
environment  = "production"
```

### Full Monitoring Setup

```hcl
# Complete setup with monitoring and notifications
project_name               = "critical-app"
environment               = "production"
enable_cloudwatch_dashboard = true
enable_notifications      = true
notification_email        = "devops@company.com"
```

### Development Environment with Sample Resources

```hcl
# Development setup with sample infrastructure
project_name            = "dev-app"
environment            = "development"
create_sample_resources = true
enable_cloudwatch_dashboard = true
```

## Post-Deployment Steps

### 1. Begin Assessment

Access your workload in the AWS Well-Architected Tool console:

```bash
# Get the console URL
terraform output wellarchitected_console_url
```

### 2. Conduct Lens Review

1. Navigate to the workload in the AWS Console
2. Start the Well-Architected Framework lens review
3. Answer questions for each of the six pillars
4. Review improvement recommendations

### 3. Monitor Progress

If CloudWatch dashboard is enabled:

```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

### 4. Set Up Automation (Optional)

Use the created IAM role for programmatic access:

```bash
# Get automation role ARN
terraform output automation_role_arn

# Example: Assume role for automation
aws sts assume-role \
  --role-arn $(terraform output -raw automation_role_arn) \
  --role-session-name "wellarchitected-automation"
```

## AWS CLI Integration

The configuration outputs useful AWS CLI commands for workload management:

```bash
# Get all available commands
terraform output aws_cli_commands

# Example usage:
# Get workload details
aws wellarchitected get-workload --workload-id $(terraform output -raw workload_id)

# List assessment questions for operational excellence
aws wellarchitected list-answers \
  --workload-id $(terraform output -raw workload_id) \
  --lens-alias wellarchitected \
  --pillar-id operationalExcellence
```

## Monitoring and Alerting

### CloudWatch Dashboard

When enabled, the dashboard provides:

- Assessment activity metrics
- Recent assessment logs
- Workload overview information

### SNS Notifications

Configure email notifications for:

- Assessment milestone completions
- Risk level changes
- Review completion status

## Security Considerations

### IAM Permissions

The configuration follows the principle of least privilege:

- Workload-specific permissions only
- Read/write access limited to created resources
- Separate role for automation vs. human access

### Data Protection

- Assessment data remains within your AWS account
- No sensitive information is exposed in Terraform state
- CloudWatch logs have configurable retention periods

## Cost Optimization

### Free Resources

The following resources incur no charges:
- Well-Architected Tool workload and assessments
- IAM roles and policies
- SNS topic (without messages)

### Billable Resources

Potential costs from optional features:
- CloudWatch dashboard: ~$3/month per dashboard
- CloudWatch logs: $0.50/GB ingested + $0.03/GB stored
- SNS notifications: $0.50/million email notifications

### Cost Management

```hcl
# Minimal cost configuration
enable_cloudwatch_dashboard = false
enable_notifications        = false
create_sample_resources     = false
```

## Troubleshooting

### Common Issues

**Permission Denied**:
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check IAM permissions
aws wellarchitected list-workloads
```

**Workload Creation Failed**:
```bash
# Check region support
aws wellarchitected list-lenses --region your-region

# Verify account status
aws support describe-service-status
```

**Dashboard Not Visible**:
```bash
# Confirm dashboard creation
aws cloudwatch list-dashboards

# Check dashboard URL format
terraform output cloudwatch_dashboard_url
```

## Cleanup

To remove all created resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm removal
terraform show
```

**Note**: Well-Architected assessments and milestones cannot be recovered after deletion.

## Advanced Usage

### Custom Lens Integration

```hcl
# Use custom organizational lens
lenses = ["wellarchitected", "custom-org-lens-alias"]
```

### Multi-Region Assessment

```hcl
# Assess workload across multiple regions
aws_regions = ["us-east-1", "us-west-2", "eu-west-1"]
```

### API Automation

```python
import boto3

# Use the created IAM role for automation
client = boto3.client('wellarchitected')

# Update workload programmatically
response = client.update_workload(
    WorkloadId='workload-id',
    Description='Updated via automation'
)
```

## Support and Documentation

- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [Well-Architected Tool User Guide](https://docs.aws.amazon.com/wellarchitected/latest/userguide/intro.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)

## Contributing

When modifying this configuration:

1. Follow Terraform best practices
2. Update variable validations
3. Add appropriate comments
4. Test with `terraform plan`
5. Update documentation

## License

This configuration is provided as-is for educational and operational purposes. Refer to your organization's infrastructure policies for production usage guidelines.