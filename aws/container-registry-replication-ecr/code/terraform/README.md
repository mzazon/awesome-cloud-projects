# ECR Container Registry Replication Strategies - Terraform Implementation

This Terraform configuration implements a comprehensive container registry replication strategy using Amazon ECR (Elastic Container Registry) with automated lifecycle management, cross-region replication, and monitoring capabilities.

## Architecture Overview

The infrastructure creates:

- **ECR Repositories**: Production and testing repositories with different image tag mutability settings
- **Cross-Region Replication**: Automated replication to multiple AWS regions
- **Lifecycle Policies**: Automated image cleanup based on age and count
- **IAM Roles**: Secure access control for different use cases
- **CloudWatch Monitoring**: Dashboards and alarms for replication health
- **Lambda Automation**: Automated cleanup functions with scheduling
- **SNS Notifications**: Alert system for monitoring events

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.5.0
- Appropriate AWS permissions for ECR, IAM, CloudWatch, SNS, and Lambda services
- Docker (for testing image operations)

## Required AWS Permissions

Your AWS credentials must have the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRole",
        "iam:ListRolePolicies",
        "cloudwatch:*",
        "sns:*",
        "lambda:*",
        "events:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

1. **Clone and Navigate**:
   ```bash
   git clone <repository-url>
   cd aws/container-registry-replication-strategies-ecr/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Review and Customize Variables**:
   ```bash
   # Copy example variables file
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit variables to match your requirements
   vi terraform.tfvars
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan -var-file="terraform.tfvars"
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply -var-file="terraform.tfvars"
   ```

## Configuration Variables

### Required Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `source_region` | string | AWS region for source ECR registries | `us-east-1` |
| `destination_region` | string | AWS region for destination ECR registries | `us-west-2` |
| `secondary_region` | string | AWS region for secondary ECR registries | `eu-west-1` |

### Optional Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `repository_prefix` | string | Prefix for ECR repository names | `enterprise-apps` |
| `environment` | string | Environment name for tagging | `production` |
| `project_name` | string | Project name for resource naming | `ecr-replication-strategy` |
| `enable_image_scanning` | bool | Enable ECR image scanning | `true` |
| `enable_monitoring` | bool | Enable CloudWatch monitoring | `true` |
| `enable_sns_notifications` | bool | Enable SNS notifications | `true` |
| `notification_email` | string | Email for SNS notifications | `""` |
| `production_image_retention_count` | number | Number of production images to retain | `10` |
| `testing_image_retention_count` | number | Number of testing images to retain | `5` |
| `create_iam_roles` | bool | Create new IAM roles | `true` |

### Example terraform.tfvars

```hcl
# Regional Configuration
source_region      = "us-east-1"
destination_region = "us-west-2"
secondary_region   = "eu-west-1"

# Repository Configuration
repository_prefix = "my-company-apps"
environment      = "production"
project_name     = "container-registry-replication"

# Monitoring Configuration
enable_monitoring        = true
enable_sns_notifications = true
notification_email       = "devops@company.com"

# Lifecycle Configuration
production_image_retention_count = 15
testing_image_retention_count    = 8
untagged_image_retention_days    = 2

# Security Configuration
enable_image_scanning = true
create_iam_roles     = true

# Custom Tags
default_tags = {
  Project     = "Container-Registry-Replication"
  Environment = "production"
  Team        = "DevOps"
  CostCenter  = "Engineering"
  ManagedBy   = "terraform"
}
```

## Regional Deployment

This configuration deploys resources across multiple regions:

- **Source Region** (us-east-1): Primary ECR repositories, replication configuration, monitoring
- **Destination Region** (us-west-2): Replicated repositories (automatically created)
- **Secondary Region** (eu-west-1): Replicated repositories (automatically created)

## Repository Structure

The Terraform configuration creates two types of repositories:

### Production Repository
- **Tag Mutability**: `IMMUTABLE` (prevents tag overwrites)
- **Lifecycle Policy**: Keeps last 10 production images, deletes untagged after 1 day
- **Repository Policy**: Restricted push/pull access via IAM roles
- **Scanning**: Enabled by default

### Testing Repository
- **Tag Mutability**: `MUTABLE` (allows tag overwrites)
- **Lifecycle Policy**: Keeps last 5 testing images, deletes all after 7 days
- **Repository Policy**: More permissive access for development
- **Scanning**: Enabled by default

## Monitoring and Alerting

### CloudWatch Dashboard
- Repository pull/push activity metrics
- Repository size monitoring
- Replication health indicators

### CloudWatch Alarms
- **Replication Failure Rate**: Triggers when > 10% failure rate
- **High Pull Rate**: Monitors unusual pull activity
- **Repository Size**: Monitors storage growth

### SNS Notifications
- Email alerts for critical events
- Integration with existing notification systems
- Configurable alert thresholds

## Automated Cleanup

The Lambda function provides advanced cleanup capabilities:

- **Scheduled Execution**: Runs daily at 2 AM UTC
- **Intelligent Cleanup**: Preserves production-tagged images
- **Configurable Retention**: Environment-based retention periods
- **Multi-Repository Support**: Processes all repositories with matching prefix

## Security Features

### IAM Roles and Policies
- **ECR Production Role**: Read-only access to production repositories
- **ECR CI Pipeline Role**: Push/pull access for CI/CD systems
- **Lambda Execution Role**: Minimal permissions for cleanup operations

### Repository Policies
- Fine-grained access control per repository
- Separate permissions for production vs. testing
- Integration with existing IAM structure

### Encryption
- All repositories use AES-256 encryption at rest
- In-transit encryption via HTTPS/TLS
- AWS KMS integration available

## Using the Infrastructure

### Docker Commands

After deployment, use these commands to interact with your repositories:

```bash
# Get repository URLs from Terraform output
PROD_REPO=$(terraform output -raw production_repository_uri)
TEST_REPO=$(terraform output -raw testing_repository_uri)

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $PROD_REPO

# Build and tag your application
docker build -t my-app:latest .
docker tag my-app:latest $PROD_REPO:prod-v1.0.0

# Push to production repository
docker push $PROD_REPO:prod-v1.0.0
```

### Validation Commands

```bash
# Check replication status
terraform output -raw replication_validation_commands

# Verify repositories in destination regions
aws ecr describe-repositories --region us-west-2 --repository-names $(terraform output -raw production_repository_name)

# List replicated images
aws ecr describe-images --region eu-west-1 --repository-name $(terraform output -raw production_repository_name)
```

## Troubleshooting

### Common Issues

1. **Replication Delays**:
   - Check CloudWatch metrics for replication status
   - Verify network connectivity between regions
   - Review IAM permissions for replication service

2. **Image Push Failures**:
   - Verify Docker login credentials
   - Check repository policies and IAM roles
   - Ensure image scanning is not blocking pushes

3. **Cleanup Issues**:
   - Review Lambda function logs in CloudWatch
   - Check IAM permissions for Lambda execution role
   - Verify lifecycle policies are correctly configured

### Monitoring Commands

```bash
# Check CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name $(terraform output -raw cloudwatch_dashboard_name)

# Review alarm status
aws cloudwatch describe-alarms --alarm-names $(terraform output -raw replication_failure_alarm_name)

# Check Lambda function logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_cleanup_function_name) --follow
```

## Cost Optimization

### Storage Costs
- Lifecycle policies automatically clean up old images
- Adjust retention periods based on your needs
- Monitor repository sizes via CloudWatch

### Data Transfer Costs
- Cross-region replication incurs data transfer charges
- Consider repository filtering to limit replicated content
- Use regional endpoints for image pulls

### Monitoring Costs
- CloudWatch metrics and alarms have associated costs
- SNS notifications charged per message
- Lambda execution costs scale with cleanup frequency

## Customization

### Adding New Regions
1. Add new provider block in `versions.tf`
2. Update replication configuration in `main.tf`
3. Add new region outputs in `outputs.tf`

### Custom Lifecycle Policies
1. Modify lifecycle policy JSON in `main.tf`
2. Adjust retention variables in `variables.tf`
3. Test policies with ECR preview functionality

### Extended Monitoring
1. Add custom CloudWatch metrics
2. Create additional alarms for specific use cases
3. Integrate with external monitoring systems

## Maintenance

### Regular Tasks
- Review and update lifecycle policies
- Monitor costs and adjust retention periods
- Update Lambda function code for new features
- Review IAM permissions and rotate credentials

### Updates
- Keep Terraform and providers updated
- Review AWS service updates and new features
- Update Lambda runtime versions
- Refresh monitoring dashboards

## Cleanup

To destroy all resources:

```bash
# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Clean up local state
rm -rf .terraform/
rm terraform.tfstate*
rm ecr_cleanup_lambda.zip
```

**Warning**: This will delete all ECR repositories and container images. Ensure you have backups if needed.

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../container-registry-replication-strategies-ecr.md)
2. Review AWS ECR documentation
3. Consult Terraform AWS provider documentation
4. Check CloudWatch logs for runtime issues

## Security Considerations

- Regularly rotate IAM credentials
- Review and audit repository policies
- Enable AWS CloudTrail for API logging
- Use AWS Config for compliance monitoring
- Implement least privilege access principles

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any new variables or resources
3. Validate security implications of changes
4. Update monitoring and alerting as needed
5. Test disaster recovery procedures