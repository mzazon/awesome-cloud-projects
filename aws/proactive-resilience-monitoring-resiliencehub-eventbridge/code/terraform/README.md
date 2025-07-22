# Terraform Infrastructure for AWS Resilience Hub and EventBridge Monitoring

This Terraform configuration deploys a complete proactive application resilience monitoring solution using AWS Resilience Hub, EventBridge, Lambda, and CloudWatch. The infrastructure automatically responds to resilience assessment changes and provides comprehensive monitoring capabilities.

## Architecture Overview

The solution implements:

- **Sample Application**: EC2 instance and RDS database for resilience testing
- **AWS Resilience Hub**: Continuous resilience assessment with customizable policies
- **EventBridge**: Real-time event processing for resilience state changes
- **Lambda Function**: Automated response to resilience events with intelligent processing
- **CloudWatch**: Comprehensive monitoring, dashboards, and multi-tier alerting
- **SNS**: Proactive notifications for resilience issues
- **IAM Roles**: Secure automation workflows with least privilege access

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** version 1.0 or later installed
3. **AWS Account** with permissions for:
   - EC2, RDS, VPC management
   - AWS Resilience Hub access
   - EventBridge, Lambda, CloudWatch operations
   - IAM role and policy management
   - SNS topic management
4. **Existing IAM Instance Profile**: `AmazonSSMRoleForInstancesQuickSetup` (created via Systems Manager Quick Setup)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/proactive-application-resilience-monitoring-resilience-hub-eventbridge/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# Basic Configuration
name_prefix = "my-resilience-demo"
environment = "demo"

# Application Settings
app_name = "my-demo-application"

# Network Configuration (adjust as needed)
vpc_cidr                = "10.0.0.0/16"
public_subnet_1_cidr    = "10.0.1.0/24"
private_subnet_2_cidr   = "10.0.2.0/24"
allowed_ssh_cidr        = "203.0.113.0/24"  # Your IP range for SSH access

# Instance Configuration
instance_type      = "t3.micro"
db_instance_class  = "db.t3.micro"

# Database Configuration (change the password!)
database_password = "YourSecurePassword123!"

# Alerting Configuration
alert_email = "your-email@example.com"

# Resilience Thresholds
critical_resilience_threshold = 70
warning_resilience_threshold  = 80

# Resilience Policy RTO/RPO (in minutes)
az_rto_minutes       = 5
az_rpo_minutes       = 1
hardware_rto_minutes = 10
hardware_rpo_minutes = 5
software_rto_minutes = 5
software_rpo_minutes = 1
region_rto_minutes   = 60
region_rpo_minutes   = 30

# Additional tags
tags = {
  Project     = "resilience-monitoring"
  Environment = "demo"
  Owner       = "platform-team"
  CostCenter  = "engineering"
}
```

### 4. Plan and Apply

```bash
# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Confirm Email Subscription (if configured)

If you provided an email address, check your inbox and confirm the SNS subscription to receive resilience alerts.

## Post-Deployment Steps

After successful deployment, complete these steps to enable full resilience monitoring:

### 1. Register Application with Resilience Hub

```bash
# Get the application ARN from Terraform outputs
APP_NAME=$(terraform output -raw app_name)
REGION=$(terraform output -raw region)

# Create application in Resilience Hub (use AWS Console or CLI)
aws resiliencehub create-app \
    --app-name "$APP_NAME" \
    --description "Demo application for proactive resilience monitoring"
```

### 2. Import Application Resources

```bash
# Get resource ARNs from Terraform outputs
EC2_INSTANCE_ID=$(terraform output -raw ec2_instance_id)
RDS_INSTANCE_ID=$(terraform output -raw rds_instance_id)
ACCOUNT_ID=$(terraform output -raw account_id)

# Import EC2 and RDS resources
aws resiliencehub import-resources-to-draft-app-version \
    --app-arn "arn:aws:resiliencehub:$REGION:$ACCOUNT_ID:app/$APP_NAME" \
    --source-arns \
        "arn:aws:ec2:$REGION:$ACCOUNT_ID:instance/$EC2_INSTANCE_ID" \
        "arn:aws:rds:$REGION:$ACCOUNT_ID:db:$RDS_INSTANCE_ID"
```

### 3. Associate Resilience Policy

```bash
# Get policy ARN from Terraform outputs
POLICY_ARN=$(terraform output -raw resilience_policy_arn)

# Associate policy with application
aws resiliencehub put-draft-app-version-template \
    --app-arn "arn:aws:resiliencehub:$REGION:$ACCOUNT_ID:app/$APP_NAME" \
    --resiliency-policy-arn "$POLICY_ARN"
```

### 4. Run Initial Assessment

```bash
# Publish application version and start assessment
aws resiliencehub publish-app-version \
    --app-arn "arn:aws:resiliencehub:$REGION:$ACCOUNT_ID:app/$APP_NAME"

aws resiliencehub start-app-assessment \
    --app-arn "arn:aws:resiliencehub:$REGION:$ACCOUNT_ID:app/$APP_NAME" \
    --assessment-name "initial-assessment-$(date +%Y%m%d)"
```

## Monitoring and Verification

### Access the CloudWatch Dashboard

```bash
# Get dashboard URL from Terraform outputs
terraform output cloudwatch_dashboard_url
```

### Test the Demo Application

```bash
# Get application URL
echo "http://$(terraform output -raw ec2_instance_public_ip)/"

# Test health endpoint
curl "http://$(terraform output -raw ec2_instance_public_ip)/health"
```

### Monitor Lambda Function Logs

```bash
# View Lambda function logs
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name)
aws logs tail "/aws/lambda/$LAMBDA_FUNCTION_NAME" --follow
```

### Test EventBridge Processing

```bash
# Send a test resilience event
aws events put-events \
    --entries '[{
        "Source": "aws.resiliencehub",
        "DetailType": "Resilience Assessment State Change",
        "Detail": "{\"applicationName\":\"'$APP_NAME'\",\"assessmentStatus\":\"ASSESSMENT_COMPLETED\",\"resilienceScore\":75,\"state\":\"ASSESSMENT_COMPLETED\"}"
    }]'
```

## Resource Management

### View All Created Resources

```bash
# List all outputs
terraform output

# Get specific resource information
terraform output application_endpoints
terraform output post_deployment_steps
terraform output useful_commands
```

### Scale Resources

Modify variables in `terraform.tfvars` and re-apply:

```bash
# Update instance type for higher performance
instance_type = "t3.medium"
db_instance_class = "db.t3.small"

# Apply changes
terraform plan
terraform apply
```

## Security Considerations

### Database Security

**⚠️ Important**: Change the default database password immediately:

```bash
# Generate a secure password
NEW_PASSWORD=$(openssl rand -base64 32)

# Update RDS password
RDS_INSTANCE_ID=$(terraform output -raw rds_instance_id)
aws rds modify-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --master-user-password "$NEW_PASSWORD" \
    --apply-immediately
```

### Network Security

- SSH access is controlled by the `allowed_ssh_cidr` variable
- Database access is restricted to VPC security groups
- Web traffic is allowed from the internet (for demo purposes)

### IAM Security

- All IAM roles follow least privilege principle
- Lambda function has minimal required permissions
- Automation role is scoped to specific services

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

The Terraform outputs include detailed cost estimates:

```bash
terraform output estimated_monthly_cost
```

### Cost Reduction Options

1. **Use Spot Instances** (not recommended for production):
   ```hcl
   use_spot_instances = true
   ```

2. **Reduce RDS Backup Retention**:
   ```hcl
   rds_backup_retention_days = 1
   ```

3. **Disable Detailed Monitoring**:
   ```hcl
   enable_detailed_monitoring = false
   ```

## Troubleshooting

### Common Issues

1. **Lambda Function Not Processing Events**:
   ```bash
   # Check Lambda function logs
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
   
   # Verify EventBridge rule
   aws events describe-rule --name "$(terraform output -raw eventbridge_rule_name)"
   ```

2. **CloudWatch Metrics Missing**:
   ```bash
   # Check EC2 instance CloudWatch agent status
   EC2_INSTANCE_ID=$(terraform output -raw ec2_instance_id)
   aws ssm send-command \
       --instance-ids "$EC2_INSTANCE_ID" \
       --document-name "AmazonCloudWatch-ManageAgent" \
       --parameters action=query
   ```

3. **SNS Notifications Not Received**:
   ```bash
   # Check SNS subscription status
   SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)
   aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN"
   ```

4. **RDS Connection Issues**:
   ```bash
   # Test database connectivity from EC2
   RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
   aws ssm start-session --target "$(terraform output -raw ec2_instance_id)"
   # Then in the session:
   # mysql -h $RDS_ENDPOINT -u admin -p
   ```

### Debug Resources

Access troubleshooting resources:

```bash
terraform output troubleshooting_resources
```

### Enable Debug Logging

Set Lambda function log level to DEBUG:

```bash
LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name)
aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --environment Variables='{LOG_LEVEL=DEBUG}'
```

## Cleanup

To destroy all resources and avoid ongoing costs:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm when prompted
```

**Note**: Some resources may require manual cleanup:
- CloudWatch Log Groups (if retention is set)
- RDS Snapshots (if created)
- SNS Topic Subscriptions

## Advanced Configuration

### Custom Resilience Policies

Modify the resilience policy in `main.tf`:

```hcl
resource "aws_resiliencehub_resiliency_policy" "demo_policy" {
  # Adjust RTO/RPO values based on business requirements
  policy {
    az {
      rto = "${var.az_rto_minutes}m"
      rpo = "${var.az_rpo_minutes}m"
    }
    # ... other configurations
  }
}
```

### Custom Lambda Processing Logic

Modify `lambda_function.py` to implement custom business logic:

```python
def handle_critical_resilience_score(app_name, score, status, context):
    # Add custom remediation logic
    # Integrate with external systems
    # Implement organization-specific workflows
    pass
```

### Multi-Environment Deployment

Use Terraform workspaces for multiple environments:

```bash
# Create and switch to production workspace
terraform workspace new production
terraform workspace select production

# Deploy with production-specific variables
terraform apply -var-file="production.tfvars"
```

## Support and Documentation

### AWS Documentation

- [AWS Resilience Hub User Guide](https://docs.aws.amazon.com/resilience-hub/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)

### Terraform Documentation

- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Configuration Language](https://www.terraform.io/docs/language/index.html)

### Additional Resources

For questions or issues with this infrastructure:

1. Check the troubleshooting section above
2. Review AWS CloudWatch logs and metrics
3. Consult AWS documentation for specific services
4. Consider opening a support case with AWS for service-specific issues

## Contributing

To contribute improvements to this infrastructure:

1. Test changes thoroughly in a development environment
2. Follow Terraform best practices and code formatting
3. Update documentation for any new features or changes
4. Ensure all security considerations are addressed

## License

This Terraform configuration is provided under the same license as the parent repository.