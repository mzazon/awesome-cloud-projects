# Terraform Infrastructure for CloudWatch Evidently Feature Flags

This Terraform configuration deploys the complete infrastructure for implementing feature flags with Amazon CloudWatch Evidently, including a demonstration Lambda function for feature evaluation.

## Architecture Overview

The infrastructure creates:

- **CloudWatch Evidently Project**: Container for feature flags and launch configurations
- **Feature Flag**: Boolean flag controlling the new checkout flow experience
- **Launch Configuration**: Manages gradual traffic rollout between control and treatment groups
- **Lambda Function**: Demonstrates feature flag evaluation with proper error handling
- **IAM Role & Policies**: Secure access for Lambda to evaluate features
- **CloudWatch Log Groups**: Centralized logging for both Evidently evaluations and Lambda execution

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- AWS account with appropriate permissions for:
  - CloudWatch Evidently
  - Lambda
  - IAM
  - CloudWatch Logs

## Quick Start

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Review the planned changes**:
   ```bash
   terraform plan
   ```

3. **Deploy the infrastructure**:
   ```bash
   terraform apply
   ```

4. **Start the launch** (optional - enables traffic splitting):
   ```bash
   # Get the project and launch names from outputs
   PROJECT_NAME=$(terraform output -raw evidently_project_name)
   LAUNCH_NAME=$(terraform output -raw launch_name)
   
   # Start the launch to begin traffic splitting
   aws evidently start-launch --project $PROJECT_NAME --launch $LAUNCH_NAME
   ```

## Configuration Variables

### Required Variables
- `aws_region`: AWS region for deployment (default: "us-east-1")

### Optional Variables
- `project_name`: Name prefix for the Evidently project (default: "feature-demo")
- `lambda_function_name`: Name prefix for the Lambda function (default: "evidently-demo")
- `feature_flag_name`: Name of the feature flag (default: "new-checkout-flow")
- `launch_name`: Name of the launch configuration (default: "checkout-gradual-rollout")
- `treatment_traffic_percentage`: Percentage of traffic for new feature (default: 10)
- `lambda_timeout`: Lambda timeout in seconds (default: 30)
- `lambda_memory_size`: Lambda memory in MB (default: 128)
- `lambda_runtime`: Lambda runtime version (default: "python3.9")
- `enable_data_delivery`: Enable CloudWatch Logs delivery (default: true)
- `log_retention_days`: Log retention period (default: 7)

### Example terraform.tfvars

```hcl
aws_region                   = "us-west-2"
project_name                = "my-feature-demo"
treatment_traffic_percentage = 25
lambda_memory_size          = 256
log_retention_days          = 14

default_tags = {
  Environment = "production"
  Team        = "platform"
  Project     = "feature-flags"
}
```

## Testing the Infrastructure

1. **Test Lambda function**:
   ```bash
   # Get function name from outputs
   FUNCTION_NAME=$(terraform output -raw lambda_function_name)
   
   # Invoke with test user
   aws lambda invoke \
     --function-name $FUNCTION_NAME \
     --payload '{"userId": "test-user-123"}' \
     response.json
   
   # View the response
   cat response.json | jq '.'
   ```

2. **Monitor feature evaluations**:
   ```bash
   # Check CloudWatch logs for evaluations
   aws logs describe-log-streams \
     --log-group-name "/aws/evidently/evaluations" \
     --order-by LastEventTime \
     --descending
   ```

3. **Verify launch status**:
   ```bash
   PROJECT_NAME=$(terraform output -raw evidently_project_name)
   LAUNCH_NAME=$(terraform output -raw launch_name)
   
   aws evidently get-launch \
     --project $PROJECT_NAME \
     --launch $LAUNCH_NAME \
     --query 'status'
   ```

## Useful Commands

The Terraform outputs provide sample AWS CLI commands for common operations:

```bash
# View all available commands
terraform output feature_evaluation_commands
```

## Monitoring and Observability

### CloudWatch Logs
- **Evidently Evaluations**: `/aws/evidently/evaluations`
- **Lambda Function**: `/aws/lambda/<function-name>`

### Metrics to Monitor
- Feature evaluation success/failure rates
- Lambda function duration and errors
- Traffic distribution between control and treatment groups

### Sample CloudWatch Insights Queries

```sql
# Feature evaluation patterns
fields @timestamp, userId, variation, reason
| filter @message like /Feature evaluation/
| stats count() by variation

# Lambda errors
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
```

## Launch Management

### Starting a Launch
```bash
aws evidently start-launch --project <project-name> --launch <launch-name>
```

### Stopping a Launch
```bash
aws evidently stop-launch --project <project-name> --launch <launch-name>
```

### Updating Traffic Allocation
Use the AWS Console or update the Terraform configuration and re-apply.

## Security Considerations

- The Lambda function uses least-privilege IAM permissions
- Feature evaluations are logged for audit purposes
- All resources are tagged for governance and cost allocation
- CloudWatch Logs have configurable retention periods

## Cost Optimization

- CloudWatch Evidently charges per feature evaluation
- Lambda charges based on execution time and memory
- Log retention periods are configurable to manage storage costs
- Use the `treatment_traffic_percentage` variable to control evaluation volume

## Cleanup

To destroy all resources:

```bash
# Stop the launch first (if started)
PROJECT_NAME=$(terraform output -raw evidently_project_name)
LAUNCH_NAME=$(terraform output -raw launch_name)
aws evidently stop-launch --project $PROJECT_NAME --launch $LAUNCH_NAME

# Wait for launch to stop, then destroy
terraform destroy
```

## Troubleshooting

### Common Issues

1. **"ResourceNotFoundException"**: Ensure the Evidently project and feature exist before starting the launch
2. **"AccessDeniedException"**: Verify IAM permissions for Evidently operations
3. **Lambda timeout**: Increase `lambda_timeout` if evaluations are slow
4. **Feature evaluation errors**: Check CloudWatch logs for detailed error messages

### Debugging Commands

```bash
# Check resource status
terraform state list
terraform show

# Validate configuration
terraform validate
terraform plan

# Check AWS resources directly
aws evidently list-projects
aws evidently list-features --project <project-name>
```

## Best Practices

1. **Start Small**: Begin with low traffic percentages (5-10%)
2. **Monitor Metrics**: Set up CloudWatch alarms for error rates
3. **Use Safe Defaults**: Always default to the existing experience (disabled)
4. **Gradual Rollout**: Increase traffic percentage based on success metrics
5. **Quick Rollback**: Be prepared to stop launches immediately if issues arise

## Integration Examples

### API Gateway Integration
Add an API Gateway to expose the Lambda function as a REST endpoint for web applications.

### Application Load Balancer Integration
Use ALB with Lambda targets for high-traffic web applications.

### CI/CD Integration
Automate feature flag management as part of your deployment pipeline.

## Support

For issues with this Terraform configuration:
1. Check the [AWS CloudWatch Evidently documentation](https://docs.aws.amazon.com/evidently/)
2. Review CloudWatch logs for detailed error messages
3. Validate IAM permissions and resource configurations
4. Use `terraform plan` to verify configuration changes