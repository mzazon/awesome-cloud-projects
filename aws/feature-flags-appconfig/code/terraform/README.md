# Terraform Infrastructure for AWS AppConfig Feature Flags

This directory contains Terraform Infrastructure as Code (IaC) for implementing a comprehensive feature flag management system using AWS AppConfig with Lambda integration, CloudWatch monitoring, and automatic rollback capabilities.

## Overview

This Terraform configuration creates:

- **AWS AppConfig Application** with feature flag management
- **AppConfig Environment** with monitoring integration
- **Feature Flag Configuration Profile** with validation
- **Deployment Strategy** for gradual rollouts
- **Lambda Function** demonstrating feature flag consumption
- **CloudWatch Alarm** for automatic rollback monitoring
- **IAM Roles and Policies** with least privilege access
- **Service-Linked Role** for AppConfig monitoring

## Architecture

The infrastructure implements a production-ready feature flag system that enables:

- Safe, gradual feature rollouts with automatic monitoring
- Real-time feature flag retrieval via Lambda extension
- Automatic rollback based on application health metrics
- Centralized configuration management with version control
- Comprehensive logging and monitoring integration

## Prerequisites

- **AWS CLI**: Version 2.x installed and configured
- **Terraform**: Version 1.0+ installed
- **AWS Account**: With appropriate permissions for:
  - AppConfig services
  - Lambda functions
  - CloudWatch alarms
  - IAM roles and policies
- **Estimated Cost**: $5-15 per month for development/testing workloads

### Required AWS Permissions

Your AWS credentials must have permissions for:
```
- appconfig:*
- lambda:*
- iam:*
- cloudwatch:*
- logs:*
```

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or download the repository
cd aws/feature-flags-appconfig/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your specific values
# Key variables to customize:
# - aws_region: Your preferred AWS region
# - app_name: Unique name for your AppConfig application
# - lambda_function_name: Unique name for your Lambda function
# - initial_feature_flags: Initial feature flag configuration
```

### 3. Plan and Apply

```bash
# Review the planned infrastructure changes
terraform plan

# Apply the configuration
terraform apply

# Confirm with 'yes' when prompted
```

### 4. Test the Infrastructure

```bash
# Test the Lambda function (using output from terraform apply)
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload '{}' \
    response.json && cat response.json

# Check deployment status
aws appconfig get-deployment \
    --application-id $(terraform output -raw appconfig_application_id) \
    --environment-id $(terraform output -raw appconfig_environment_id) \
    --deployment-number $(terraform output -raw initial_deployment_number)
```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name | `production` | No |
| `app_name` | AppConfig application name | `feature-demo-app` | No |

### Lambda Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `lambda_function_name` | Lambda function name | `feature-flag-demo` | No |
| `lambda_runtime` | Lambda runtime | `python3.9` | No |
| `lambda_timeout` | Function timeout (seconds) | `30` | No |
| `lambda_memory_size` | Function memory (MB) | `256` | No |

### Deployment Strategy

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `deployment_duration_minutes` | Deployment duration | `20` | No |
| `final_bake_time_minutes` | Final bake time | `10` | No |
| `growth_factor` | Growth rate percentage | `25` | No |

### Feature Flags Configuration

The `initial_feature_flags` variable allows you to configure the initial state of your feature flags:

```hcl
initial_feature_flags = {
  new_checkout_flow = {
    enabled             = false
    rollout_percentage  = 0
    target_audience     = "beta-users"
  }
  enhanced_search = {
    enabled          = true
    search_algorithm = "elasticsearch"
    cache_ttl        = 300
  }
  premium_features = {
    enabled      = false
    feature_list = "advanced-analytics,priority-support"
  }
}
```

## Outputs

After successful deployment, Terraform provides key outputs:

- **Application IDs**: AppConfig application, environment, and profile IDs
- **Lambda Information**: Function name, ARN, and role details
- **Monitoring**: CloudWatch alarm names and ARNs
- **Console URLs**: Direct links to AWS Console resources
- **Test Commands**: Ready-to-use CLI commands for testing

## Feature Flag Updates

To update feature flags after initial deployment:

1. **Create new configuration version**:
   ```bash
   # Update your feature flags JSON
   aws appconfig create-hosted-configuration-version \
       --application-id $(terraform output -raw appconfig_application_id) \
       --configuration-profile-id $(terraform output -raw configuration_profile_id) \
       --content-type "application/json" \
       --content file://updated-flags.json
   ```

2. **Deploy the new configuration**:
   ```bash
   aws appconfig start-deployment \
       --application-id $(terraform output -raw appconfig_application_id) \
       --environment-id $(terraform output -raw appconfig_environment_id) \
       --deployment-strategy-id $(terraform output -raw deployment_strategy_id) \
       --configuration-profile-id $(terraform output -raw configuration_profile_id) \
       --configuration-version NEW_VERSION_NUMBER \
       --description "Updated feature flags"
   ```

## Monitoring and Rollback

The infrastructure includes automatic monitoring and rollback:

- **CloudWatch Alarm**: Monitors Lambda function errors
- **Automatic Rollback**: Triggered when error threshold is exceeded
- **Service-Linked Role**: Enables AppConfig to access CloudWatch metrics

### Viewing Metrics

```bash
# View Lambda invocation metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=$(terraform output -raw lambda_function_name) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Check alarm status
aws cloudwatch describe-alarms \
    --alarm-names $(terraform output -raw cloudwatch_alarm_name)
```

## Security Considerations

This configuration follows AWS security best practices:

- **Least Privilege**: IAM roles grant minimal required permissions
- **Encryption**: All data in transit and at rest is encrypted
- **VPC**: Can be deployed in private subnets (modify as needed)
- **Monitoring**: Comprehensive logging and alerting

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure your AWS credentials have sufficient permissions
2. **Resource Limits**: Check AWS service limits in your account
3. **Region Availability**: Verify AppConfig is available in your chosen region
4. **Lambda Layer**: The AppConfig extension layer ARN is region-specific

### Debugging

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/$(terraform output -raw lambda_function_name)

# View deployment status
aws appconfig list-deployments \
    --application-id $(terraform output -raw appconfig_application_id) \
    --environment-id $(terraform output -raw appconfig_environment_id)

# Test AppConfig endpoint directly
curl "http://localhost:2772/applications/$(terraform output -raw appconfig_application_id)/environments/$(terraform output -raw appconfig_environment_id)/configurations/$(terraform output -raw configuration_profile_id)"
```

## Cleanup

To remove all infrastructure:

```bash
# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

**Note**: This will permanently delete all resources. Ensure you have backups of any important configuration data.

## Cost Optimization

- **AppConfig**: First 1,000 requests per month are free
- **Lambda**: Generous free tier for function executions
- **CloudWatch**: Basic monitoring included in free tier
- **Total Cost**: Typically $5-15/month for development workloads

## Additional Resources

- [AWS AppConfig Documentation](https://docs.aws.amazon.com/appconfig/)
- [Lambda Extension Documentation](https://docs.aws.amazon.com/appconfig/latest/userguide/appconfig-integration-lambda-extensions.html)
- [Feature Flag Best Practices](https://docs.aws.amazon.com/appconfig/latest/userguide/what-is-appconfig.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues with this infrastructure code:
1. Check the [AWS AppConfig troubleshooting guide](https://docs.aws.amazon.com/appconfig/latest/userguide/troubleshooting.html)
2. Review Terraform plan output for resource conflicts
3. Verify AWS service limits and quotas
4. Check CloudWatch logs for detailed error information