# Terraform Infrastructure for Scheduled Email Reports

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless email reporting system using AWS App Runner, Amazon SES, EventBridge Scheduler, and CloudWatch.

## Architecture Overview

The infrastructure creates:

- **AWS App Runner Service**: Hosts a containerized Flask application that generates and sends email reports
- **Amazon SES**: Provides reliable email delivery with authentication and reputation management
- **EventBridge Scheduler**: Triggers automated report generation on a configurable schedule
- **IAM Roles**: Secure access controls following least-privilege principles
- **CloudWatch Monitoring**: Comprehensive logging, metrics, and alerting capabilities

## Prerequisites

### Required Tools

- **Terraform** >= 1.5
- **AWS CLI** >= 2.0, configured with appropriate credentials
- **Git** for version control (if using GitHub repository)

### Required Permissions

Your AWS credentials must have permissions to create and manage:

- App Runner services and configurations
- IAM roles and policies
- SES email identities
- EventBridge Scheduler rules
- CloudWatch alarms, dashboards, and log groups

### Required Resources

1. **Verified Email Address**: You must have a verified email address in Amazon SES
2. **GitHub Repository**: A public GitHub repository containing your Flask application code
3. **Application Code**: Your repository must contain the Flask application with proper containerization files

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your configuration
nano terraform.tfvars
```

### 2. Set Required Variables

Edit `terraform.tfvars` with your specific values:

```hcl
# Required: Your verified SES email address
ses_verified_email = "your-email@example.com"

# Required: Your GitHub repository URL
github_repository_url = "https://github.com/your-username/email-reports-app"

# Optional: Environment and scheduling
environment = "dev"
schedule_expression = "cron(0 9 * * ? *)"  # Daily at 9 AM UTC
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Post-Deployment Steps

1. **Verify SES Email**: Check your email inbox and click the verification link
2. **Push Application Code**: Ensure your Flask app code is in the GitHub repository
3. **Monitor Deployment**: App Runner will build and deploy your application (5-10 minutes)
4. **Test the System**: Use the provided test commands from `terraform output`

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ses_verified_email` | Verified SES email address | `reports@company.com` |
| `github_repository_url` | Public GitHub repository URL | `https://github.com/user/repo` |

### Optional Variables

#### Scheduling Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `schedule_expression` | `cron(0 9 * * ? *)` | EventBridge cron expression |
| `schedule_timezone` | `UTC` | Timezone for schedule |

#### App Runner Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `app_runner_cpu` | `0.25 vCPU` | CPU allocation |
| `app_runner_memory` | `0.5 GB` | Memory allocation |
| `health_check_path` | `/health` | Health check endpoint |

#### Monitoring Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_cloudwatch_dashboard` | `true` | Create monitoring dashboard |
| `enable_cloudwatch_alarms` | `true` | Create failure alerts |
| `cloudwatch_alarm_threshold` | `1` | Alert threshold |

## Outputs

After successful deployment, Terraform provides important information:

```bash
# View all outputs
terraform output

# View specific output
terraform output app_runner_service_url
```

### Key Outputs

- **`app_runner_service_url`**: Your application's public URL
- **`app_runner_health_check_url`**: Health check endpoint
- **`schedule_name`**: EventBridge schedule name
- **`cloudwatch_dashboard_url`**: Direct link to monitoring dashboard
- **`next_steps`**: Post-deployment configuration steps

## Validation and Testing

### Manual Testing Commands

```bash
# Test health check
curl -s $(terraform output -raw app_runner_service_url)/health

# Manually trigger report generation
curl -X POST $(terraform output -raw app_runner_service_url)/generate-report \
  -H "Content-Type: application/json" -d '{}'

# Check EventBridge schedule
aws scheduler get-schedule --name $(terraform output -raw schedule_name)
```

### Monitoring and Logs

```bash
# View App Runner logs
aws logs describe-log-streams \
  --log-group-name /aws/apprunner/$(terraform output -raw app_runner_service_name)

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace EmailReports \
  --metric-name ReportsGenerated \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

## Customization Examples

### Daily Business Hours Reports

```hcl
# Monday to Friday, 8 AM Eastern Time
schedule_expression = "cron(0 8 * * MON-FRI *)"
schedule_timezone = "America/New_York"
```

### High-Performance Configuration

```hcl
# More resources for complex reports
app_runner_cpu = "1 vCPU"
app_runner_memory = "2 GB"
scheduler_retry_attempts = 5
```

### Production Environment

```hcl
environment = "prod"
common_tags = {
  Environment = "production"
  Owner      = "data-team@company.com"
  CostCenter = "engineering"
}
```

## Troubleshooting

### Common Issues

1. **SES Email Not Verified**
   ```bash
   aws ses get-identity-verification-attributes \
     --identities your-email@example.com
   ```

2. **App Runner Build Failures**
   - Check your GitHub repository has proper `Dockerfile` and `apprunner.yaml`
   - Verify repository is public and accessible
   - Review App Runner service logs in CloudWatch

3. **Schedule Not Triggering**
   - Verify EventBridge Scheduler permissions
   - Check cron expression format
   - Review CloudWatch logs for invocation attempts

### Debug Commands

```bash
# Check App Runner service status
aws apprunner describe-service \
  --service-name $(terraform output -raw app_runner_service_name)

# View recent EventBridge invocations
aws logs filter-log-events \
  --log-group-name /aws/events/rule/$(terraform output -raw schedule_name)

# Check IAM role permissions
aws iam get-role-policy \
  --role-name $(terraform output -raw app_runner_role_name) \
  --policy-name EmailReportsPolicy
```

## Cost Optimization

### Estimated Monthly Costs

- **App Runner**: ~$5-10 (0.25 vCPU, 0.5 GB, minimal traffic)
- **SES**: $0.10 per 1,000 emails (62,000 free per month)
- **EventBridge Scheduler**: $1.00 per million invocations (14 million free)
- **CloudWatch**: ~$1-3 (metrics, alarms, dashboard)

**Total: ~$6-14/month** for basic usage

### Cost Reduction Tips

- Use smaller App Runner instance for simple reports
- Optimize health check intervals
- Disable unnecessary CloudWatch features
- Implement SES bounce and complaint handling

## Security Best Practices

### Implemented Security Features

- **IAM Least Privilege**: Minimal permissions for each role
- **Encryption**: Default encryption for all resources
- **VPC Security**: App Runner uses AWS-managed security
- **Access Logging**: Comprehensive audit trails

### Additional Security Recommendations

1. **Rotate IAM Keys**: Regularly rotate AWS access keys
2. **Monitor Usage**: Set up AWS Config rules for compliance
3. **Network Security**: Consider VPC endpoints for internal communication
4. **Secret Management**: Use AWS Secrets Manager for sensitive data

## Maintenance

### Regular Tasks

1. **Update Dependencies**: Keep Terraform and provider versions current
2. **Review Logs**: Monitor CloudWatch for errors and performance
3. **Cost Review**: Check AWS Cost Explorer monthly
4. **Security Updates**: Update Flask and container dependencies

### Backup and Recovery

```bash
# Export Terraform state for backup
terraform show -json > infrastructure-backup.json

# Document resource ARNs for disaster recovery
terraform output -json > resource-inventory.json
```

## Cleanup

To remove all infrastructure:

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
aws apprunner list-services
aws scheduler list-schedules
```

**Note**: Some resources like CloudWatch logs may have retention policies and won't be immediately deleted.

## Support

For issues related to:

- **Terraform Configuration**: Review this documentation and Terraform AWS provider docs
- **AWS Services**: Consult AWS documentation and support
- **Application Code**: Refer to the original recipe documentation

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new variables or outputs
3. Follow Terraform best practices for resource naming and tagging
4. Validate with `terraform plan` before applying changes

## License

This infrastructure code is provided as part of the AWS recipes collection. Refer to the main repository license for terms and conditions.