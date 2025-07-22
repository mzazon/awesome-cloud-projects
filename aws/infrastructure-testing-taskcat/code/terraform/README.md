# Terraform Infrastructure for TaskCat CloudFormation Testing

This Terraform configuration creates a comprehensive infrastructure testing environment using TaskCat and CloudFormation. It provides automated deployment validation across multiple AWS regions with integrated monitoring, reporting, and cleanup capabilities.

## Architecture Overview

The infrastructure includes:

- **S3 Bucket**: Stores TaskCat artifacts, templates, and test results
- **IAM Roles**: Secure execution roles for TaskCat and Lambda automation
- **Lambda Function**: Automated test execution and orchestration
- **CloudWatch**: Logging and monitoring for test activities
- **SNS**: Optional notifications for test results
- **CloudTrail**: Optional audit logging for testing operations
- **EC2 Key Pair**: For testing EC2-related CloudFormation templates

## Prerequisites

- **Terraform**: Version 1.0 or higher
- **AWS CLI**: Version 2.x configured with appropriate credentials
- **AWS Account**: With permissions for CloudFormation, S3, IAM, EC2, Lambda, and CloudWatch
- **Python**: 3.7+ (for Lambda function runtime)

## Quick Start

### 1. Clone and Navigate

```bash
cd aws/infrastructure-testing-taskcat-cloudformation/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration
```

### 4. Plan and Apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### 5. Use the Infrastructure

After deployment, use the outputs to configure TaskCat:

```bash
# Get the S3 bucket name
export TASKCAT_BUCKET=$(terraform output -raw s3_bucket_name)

# Get the execution role ARN
export TASKCAT_ROLE=$(terraform output -raw taskcat_execution_role_arn)

# Download the generated TaskCat configuration
aws s3 cp s3://$TASKCAT_BUCKET/config/.taskcat.yml ./.taskcat.yml
```

## Configuration Variables

### Required Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `project_name` | Name of the TaskCat testing project | `"taskcat-demo"` | `"my-infrastructure-tests"` |
| `environment_name` | Environment name for resource tagging | `"testing"` | `"development"` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_regions` | List of AWS regions for testing | `["us-east-1", "us-west-2", "eu-west-1"]` |
| `s3_bucket_force_destroy` | Force destroy S3 bucket with objects | `true` |
| `s3_bucket_versioning_enabled` | Enable S3 bucket versioning | `true` |
| `enable_cloudtrail_logging` | Enable CloudTrail for audit logging | `false` |
| `notification_email` | Email for test notifications | `""` (disabled) |
| `key_pair_name` | Existing EC2 key pair name | `""` (auto-generated) |

### Advanced Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_cidr_blocks` | CIDR blocks for test scenarios | See variables.tf |
| `test_timeout_minutes` | Maximum test execution time | `60` |
| `cloudtrail_retention_days` | Log retention period | `7` |
| `enable_cost_monitoring` | Enable cost tracking | `false` |
| `enable_security_scanning` | Enable security scanning | `false` |

## Example Configuration Files

### terraform.tfvars.example

```hcl
# Basic Configuration
project_name     = "my-taskcat-tests"
environment_name = "development"

# Testing Regions
aws_regions = [
  "us-east-1",
  "us-west-2",
  "eu-west-1",
  "ap-southeast-1"
]

# Notifications
notification_email = "devops-team@example.com"

# Monitoring and Logging
enable_cloudtrail_logging = true
cloudtrail_retention_days = 30

# Security
s3_bucket_force_destroy = false  # Set to false for production
enable_security_scanning = true

# Custom VPC CIDR blocks for testing
vpc_cidr_blocks = {
  basic    = "10.0.0.0/16"
  no_nat   = "10.1.0.0/16"
  custom   = "172.16.0.0/16"
  dynamic  = "10.2.0.0/16"
  regional = "10.3.0.0/16"
}

# Additional tags
tags = {
  Department = "DevOps"
  Team       = "Infrastructure"
  Cost_Center = "IT-001"
}
```

### .taskcat.yml (Generated)

The Terraform configuration automatically generates a TaskCat configuration file based on your variables:

```yaml
project:
  name: my-taskcat-tests
  owner: 'taskcat-demo@example.com'
  s3_bucket: my-taskcat-tests-artifacts-abc123
  regions:
    - us-east-1
    - us-west-2
    - eu-west-1

tests:
  vpc-basic-test:
    template: templates/vpc-template.yaml
    parameters:
      VpcCidr: '10.0.0.0/16'
      EnvironmentName: 'TaskCatBasic'
      CreateNatGateway: 'true'
  
  # Additional test configurations...
```

## Usage Instructions

### 1. Install TaskCat

```bash
pip install taskcat
```

### 2. Prepare CloudFormation Templates

Create your CloudFormation templates in a `templates/` directory:

```bash
mkdir templates/
# Add your CloudFormation templates (*.yaml, *.yml, *.json)
```

### 3. Upload Templates to S3

```bash
aws s3 sync ./templates/ s3://$(terraform output -raw s3_bucket_name)/templates/
```

### 4. Run TaskCat Tests

```bash
# Download the generated configuration
aws s3 cp s3://$(terraform output -raw s3_bucket_name)/config/.taskcat.yml ./.taskcat.yml

# Run all tests
taskcat test run --output-directory ./taskcat_outputs

# Run specific test
taskcat test run vpc-basic-test --output-directory ./taskcat_outputs

# Run with custom parameters
taskcat test run --dry-run  # Validate configuration first
```

### 5. View Test Results

```bash
# List generated reports
ls -la ./taskcat_outputs/

# Open HTML report (if generated)
open ./taskcat_outputs/index.html

# Check S3 for stored results
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/test-results/ --recursive
```

## Lambda Automation

The infrastructure includes a Lambda function for automated TaskCat operations:

### Invoke Lambda Function

```bash
# Run tests programmatically
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"action": "run_tests"}' \
  response.json

# Cleanup test stacks
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"action": "cleanup_stacks"}' \
  response.json

# Validate templates
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"action": "validate_templates"}' \
  response.json
```

### Schedule Automated Tests

Enable the CloudWatch Event Rule for scheduled testing:

```bash
aws events enable-rule --name $(terraform output -raw cloudwatch_event_rule_name)
```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View TaskCat execution logs
aws logs describe-log-streams \
  --log-group-name $(terraform output -raw cloudwatch_log_group_name)

# Tail logs in real-time
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### S3 Artifact Structure

```
s3://bucket-name/
├── config/
│   └── .taskcat.yml
├── templates/
│   ├── vpc-template.yaml
│   └── advanced-vpc-template.yaml
├── test-results/
│   └── 2024/01/15/
│       ├── taskcat_report.json
│       └── test-outputs/
└── reports/
    └── test-report-20240115-143022.json
```

### Security Considerations

1. **IAM Permissions**: The execution role has broad permissions for testing. Review and restrict as needed for production use.

2. **S3 Security**: 
   - Public access is blocked by default
   - Server-side encryption is enabled
   - Versioning is enabled (configurable)

3. **Network Security**: 
   - Security groups created during testing follow least privilege
   - VPC configurations use private subnets where appropriate

4. **Secrets Management**: 
   - Private keys are stored in AWS Secrets Manager
   - Database passwords use TaskCat's secure generation

## Cost Optimization

### Lifecycle Policies

- S3 objects transition to IA after 30 days
- Objects move to Glacier after 90 days
- Objects are deleted after 365 days
- Incomplete uploads are cleaned up after 7 days

### Resource Cleanup

```bash
# Manual cleanup of test stacks
for region in us-east-1 us-west-2 eu-west-1; do
  aws cloudformation list-stacks \
    --region $region \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?starts_with(StackName, `taskcat-demo`)].StackName' \
    --output text | \
  xargs -I {} aws cloudformation delete-stack --region $region --stack-name {}
done

# Use Lambda automation
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"action": "cleanup_stacks", "notify": true}' \
  response.json
```

## Advanced Features

### Multi-Account Testing

Configure cross-account roles for testing in different AWS accounts:

```hcl
# In terraform.tfvars
cross_account_roles = {
  "development" = "arn:aws:iam::123456789012:role/TaskCatCrossAccountRole"
  "staging"     = "arn:aws:iam::123456789013:role/TaskCatCrossAccountRole"
}
```

### Custom Validation Scripts

Add custom Python validation scripts:

```bash
# Upload validation scripts
aws s3 cp ./validation_scripts/ s3://$(terraform output -raw s3_bucket_name)/validation/ --recursive

# Reference in TaskCat configuration
# post_test_scripts:
#   - s3://bucket/validation/test_vpc_resources.py
```

### Integration with CI/CD

Use the infrastructure in CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Run TaskCat Tests
  run: |
    aws s3 sync ./templates/ s3://${{ secrets.TASKCAT_BUCKET }}/templates/
    aws lambda invoke \
      --function-name ${{ secrets.TASKCAT_LAMBDA }} \
      --payload '{"action": "run_tests", "notify": false}' \
      response.json
```

## Cleanup

### Destroy Infrastructure

```bash
# Remove all test stacks first
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"action": "cleanup_stacks"}' \
  response.json

# Wait for stack deletions to complete, then destroy Terraform infrastructure
terraform destroy
```

### Manual S3 Cleanup (if needed)

```bash
# Empty S3 bucket before destroying (if force_destroy is false)
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your AWS credentials have sufficient permissions
2. **Template Validation Errors**: Check CloudFormation template syntax
3. **Region Availability**: Verify services are available in target regions
4. **Resource Limits**: Check AWS service limits for your account

### Debug Mode

Enable debug logging in TaskCat:

```bash
taskcat test run --debug --output-directory ./debug_outputs
```

### Support Resources

- [TaskCat Documentation](https://aws-quickstart.github.io/taskcat/)
- [CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/)

## Contributing

To extend this infrastructure:

1. Fork the repository
2. Create feature branch
3. Add your enhancements
4. Test thoroughly
5. Submit pull request

## License

This infrastructure code is provided under the MIT License. See LICENSE file for details.