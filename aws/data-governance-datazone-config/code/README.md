# Infrastructure as Code for Data Governance Pipelines with DataZone

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Governance Pipelines with DataZone".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon DataZone (domain and project management)
  - AWS Config (configuration recorder and rules)
  - AWS Lambda (function creation and execution)
  - Amazon EventBridge (rules and targets)
  - Amazon SNS (topic creation and management)
  - Amazon S3 (bucket creation for Config delivery)
  - AWS IAM (role and policy management)
  - Amazon CloudWatch (alarms and monitoring)
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform >= 1.0
- Estimated deployment cost: $50-100/month for moderate usage

> **Note**: Amazon DataZone is available in select AWS regions. Verify regional availability before deployment.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name data-governance-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DomainName,ParameterValue=my-governance-domain

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name data-governance-pipeline \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name data-governance-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws datazone list-domains --query 'items[?contains(name, `governance-domain`)]'
```

## Architecture Overview

This infrastructure deploys:

1. **Amazon DataZone Domain**: Central data cataloging and governance hub
2. **AWS Config**: Continuous compliance monitoring with rules for:
   - S3 bucket encryption enforcement
   - RDS storage encryption validation
   - S3 public access prevention
3. **AWS Lambda**: Automated governance event processing
4. **Amazon EventBridge**: Event-driven automation trigger
5. **Amazon SNS**: Governance alerts and notifications
6. **CloudWatch**: Monitoring and alerting for the governance pipeline
7. **IAM Roles**: Least-privilege access for all services

## Configuration Options

### CloudFormation Parameters

- `DomainName`: Name for the DataZone domain (default: auto-generated)
- `EnableAdvancedMonitoring`: Enable additional CloudWatch alarms (default: true)
- `NotificationEmail`: Email for governance alerts (optional)

### CDK Context Variables

```json
{
  "domainName": "my-governance-domain",
  "enableAdvancedMonitoring": true,
  "notificationEmail": "admin@example.com"
}
```

### Terraform Variables

```hcl
# terraform.tfvars
domain_name = "my-governance-domain"
enable_advanced_monitoring = true
notification_email = "admin@example.com"
aws_region = "us-east-1"
```

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Check DataZone domain status
aws datazone list-domains --query 'items[].{Name:name,Status:status}'

# Verify Config is recording
aws configservice describe-configuration-recorders

# List active Config rules
aws configservice describe-config-rules --query 'ConfigRules[].ConfigRuleName'

# Check EventBridge rule
aws events describe-rule --name <event-rule-name>

# Test Lambda function
aws lambda invoke \
    --function-name <lambda-function-name> \
    --payload '{"test": true}' \
    response.json
```

## Monitoring & Observability

The deployment includes:

- **CloudWatch Alarms**:
  - Lambda function errors
  - Lambda function duration
  - Config compliance ratio
- **SNS Notifications**: Real-time alerts for governance events
- **CloudWatch Logs**: Detailed logging for all components

Access logs:

```bash
# View Lambda logs
aws logs tail /aws/lambda/<function-name> --follow

# View Config compliance
aws configservice get-compliance-summary-by-config-rule
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name data-governance-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name data-governance-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Adding Custom Config Rules

1. **CloudFormation**: Add new `AWS::Config::ConfigRule` resources
2. **CDK**: Use `aws-cdk-lib/aws-config` constructs
3. **Terraform**: Add `aws_config_config_rule` resources

### Extending Lambda Functionality

The Lambda function can be customized to:
- Integrate with external governance tools
- Implement custom remediation logic
- Send notifications to multiple channels
- Update DataZone metadata automatically

### Multi-Account Deployment

For organization-wide governance:
1. Deploy in the management account
2. Use Config aggregators for cross-account monitoring
3. Implement cross-account DataZone sharing
4. Configure organization-wide EventBridge rules

## Security Considerations

- All IAM roles follow least-privilege principles
- S3 buckets are encrypted by default
- Lambda functions run with minimal required permissions
- Config delivery channel uses secure S3 bucket policies
- DataZone domain uses AWS-managed encryption

## Troubleshooting

### Common Issues

1. **DataZone Domain Creation Fails**:
   - Verify service-linked role exists
   - Check regional availability
   - Ensure adequate permissions

2. **Config Rules Not Evaluating**:
   - Verify Config recorder is enabled
   - Check IAM permissions for Config service
   - Ensure delivery channel is configured

3. **Lambda Function Errors**:
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions for DataZone and Config APIs
   - Ensure EventBridge rule is properly configured

4. **EventBridge Rule Not Triggering**:
   - Verify event pattern matches Config event structure
   - Check Lambda function permissions
   - Review EventBridge rule state

### Debug Commands

```bash
# Check service status
aws configservice describe-configuration-recorder-status
aws configservice describe-delivery-channel-status

# Verify IAM role trust relationships
aws iam get-role --role-name <role-name>

# Test Config rule evaluation
aws configservice start-config-rules-evaluation \
    --config-rule-names <rule-name>
```

## Cost Optimization

- **Config Rules**: Evaluate only necessary resource types
- **Lambda**: Optimize memory allocation based on usage patterns
- **S3 Storage**: Use lifecycle policies for Config data retention
- **CloudWatch**: Set appropriate log retention periods
- **DataZone**: Monitor project and environment usage

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation:
   - [Amazon DataZone User Guide](https://docs.aws.amazon.com/datazone/latest/userguide/)
   - [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/)
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
3. Consult provider-specific troubleshooting guides
4. Review CloudWatch logs for detailed error information

## Advanced Configuration

### Environment-Specific Deployments

Use parameter files or tfvars for different environments:

```bash
# Development
terraform apply -var-file="environments/dev.tfvars"

# Production
terraform apply -var-file="environments/prod.tfvars"
```

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy Data Governance Pipeline
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Deploy with Terraform
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

This infrastructure provides a solid foundation for automated data governance that can be extended and customized based on your organization's specific compliance and governance requirements.