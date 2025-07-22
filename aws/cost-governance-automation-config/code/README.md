# Infrastructure as Code for Cost Governance Automation with Config

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost Governance Automation with Config".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with administrator access
- Appropriate IAM permissions for creating Config, Lambda, EventBridge, SNS, SQS, and IAM resources
- Understanding of cost governance policies and your organization's compliance requirements
- For CDK: Node.js 14+ (TypeScript) or Python 3.7+ (Python)
- For Terraform: Terraform v1.0+

> **Cost Considerations**: This solution includes AWS Config rules, Lambda functions, and storage resources. Estimated monthly cost: $100-200 depending on resource count and activity levels.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the cost governance infrastructure
aws cloudformation create-stack \
    --stack-name cost-governance-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name cost-governance-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cost-governance-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
cdk deploy --all

# Verify deployment
cdk list
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
cdk deploy --all

# Verify deployment
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="notification_email=your-email@example.com" \
    -var="aws_region=us-east-1"

# Apply the configuration
terraform apply \
    -var="notification_email=your-email@example.com" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
aws configservice describe-configuration-recorders
aws lambda list-functions --query 'Functions[?contains(FunctionName, `Cost`)]'
```

## Deployed Resources

This infrastructure creates the following AWS resources:

### Core Infrastructure
- **AWS Config**: Configuration recorder and delivery channel for compliance monitoring
- **S3 Buckets**: Configuration storage and cost reports storage with versioning enabled
- **IAM Roles**: Service-linked roles for Config and Lambda execution with least-privilege permissions

### Cost Monitoring
- **Config Rules**: Automated compliance rules for idle instances, unattached volumes, and unused load balancers
- **EventBridge Rules**: Event-driven triggers for compliance violations and scheduled scans
- **CloudWatch Metrics**: Custom metrics for cost optimization tracking

### Automated Remediation
- **Lambda Functions**:
  - `IdleInstanceDetector`: Identifies EC2 instances with low CPU utilization
  - `VolumeCleanup`: Manages unattached EBS volumes with safety snapshots
  - `CostReporter`: Generates comprehensive cost governance reports

### Notification System
- **SNS Topics**: Multi-tier notification system for alerts and reports
- **SQS Queues**: Reliable event processing with dead letter queue for error handling
- **Email Subscriptions**: Automated delivery of cost optimization alerts

### Governance Controls
- **IAM Policies**: Granular permissions for automated cost actions
- **CloudTrail Integration**: Audit logging for all remediation activities
- **Resource Tagging**: Automated tagging for cost tracking and optimization

## Configuration Options

### Email Notifications

All implementations support configuring email addresses for cost governance notifications:

```bash
# CloudFormation parameter
--parameters ParameterKey=NotificationEmail,ParameterValue=finance-team@company.com

# CDK environment variable
export NOTIFICATION_EMAIL=finance-team@company.com

# Terraform variable
-var="notification_email=finance-team@company.com"

# Bash script environment variable
export NOTIFICATION_EMAIL=finance-team@company.com
```

### Customizable Thresholds

Configure cost optimization thresholds by modifying variables:

- **Idle CPU Threshold**: Default 5% average CPU utilization over 7 days
- **Volume Age Threshold**: Default 7 days for unattached volume cleanup
- **Scan Frequency**: Default weekly comprehensive scans

### Multi-Account Deployment

For Organizations with multiple accounts, deploy to the management account and configure cross-account access:

```bash
# Set organization management account ID
export ORG_MANAGEMENT_ACCOUNT=123456789012

# Deploy with cross-account permissions
terraform apply -var="enable_cross_account=true" -var="organization_id=o-1234567890"
```

## Validation & Testing

### Verify Config Rules

```bash
# Check Config rule status
aws configservice describe-config-rules \
    --query 'ConfigRules[*].[ConfigRuleName,ConfigRuleState]' \
    --output table

# Verify configuration recorder
aws configservice describe-configuration-recorders
```

### Test Lambda Functions

```bash
# Manual invoke idle instance detector
aws lambda invoke \
    --function-name IdleInstanceDetector \
    --payload '{"source": "manual-test"}' \
    --cli-binary-format raw-in-base64-out \
    response.json

# Check volume cleanup function
aws lambda invoke \
    --function-name VolumeCleanup \
    --payload '{"source": "manual-test"}' \
    --cli-binary-format raw-in-base64-out \
    response2.json
```

### Validate EventBridge Integration

```bash
# List EventBridge rules
aws events list-rules \
    --name-prefix "Cost" \
    --query 'Rules[*].[Name,State,ScheduleExpression]' \
    --output table

# Test SNS notifications
aws sns publish \
    --topic-arn $(terraform output -raw cost_notification_topic_arn) \
    --subject "Cost Governance Test" \
    --message "Testing cost governance notification system"
```

## Monitoring & Operations

### Cost Governance Dashboard

Access cost optimization metrics through:

1. **CloudWatch Dashboards**: Custom metrics for optimization actions
2. **S3 Reports**: Weekly governance reports with savings analysis
3. **Config Compliance**: Real-time compliance status for cost rules
4. **SNS Notifications**: Immediate alerts for optimization opportunities

### Operational Procedures

#### Weekly Review Process
1. Review automated cost governance report delivered via email
2. Analyze S3-stored detailed reports for trends and opportunities
3. Validate automated remediation actions through CloudTrail logs
4. Adjust thresholds based on business requirements and false positives

#### Incident Response
1. Critical cost alerts trigger immediate notification via separate SNS topic
2. Dead letter queue captures failed remediation attempts for investigation
3. CloudTrail provides complete audit trail for all automated actions
4. Manual override capabilities through resource tagging

### Troubleshooting

#### Common Issues

**Config Rules Not Evaluating**
```bash
# Check Config service status
aws configservice get-configuration-recorder-status

# Verify S3 bucket permissions
aws s3api get-bucket-policy --bucket $(terraform output -raw config_bucket_name)
```

**Lambda Functions Failing**
```bash
# Check function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/Cost"

# Review execution errors
aws lambda get-function --function-name IdleInstanceDetector
```

**Missing Notifications**
```bash
# Verify SNS topic subscription
aws sns list-subscriptions-by-topic \
    --topic-arn $(terraform output -raw cost_notification_topic_arn)

# Check EventBridge rule targets
aws events list-targets-by-rule --rule ConfigComplianceChanges
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name cost-governance-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cost-governance-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy all stacks
cdk destroy --all

# Confirm all resources removed
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="notification_email=your-email@example.com" \
    -var="aws_region=us-east-1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
aws configservice describe-configuration-recorders
aws lambda list-functions --query 'Functions[?contains(FunctionName, `Cost`)]'
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

```bash
# Check S3 buckets (may need manual deletion if not empty)
aws s3 ls | grep -E "(config|cost-governance)"

# Verify IAM roles removed
aws iam list-roles --query 'Roles[?contains(RoleName, `Cost`)]'

# Check EventBridge rules
aws events list-rules --query 'Rules[?contains(Name, `Cost`)]'
```

## Customization

### Extending Cost Rules

Add additional cost optimization rules by:

1. **Custom Config Rules**: Create organization-specific compliance rules
2. **Additional Lambda Functions**: Implement custom remediation logic
3. **Enhanced Reporting**: Integrate with business intelligence tools
4. **Workflow Integration**: Connect to ITSM systems for approval processes

### Integration Options

#### Cost Management Integration
```python
# Example: Integrate with AWS Cost Explorer API
import boto3

def get_cost_and_usage():
    ce = boto3.client('ce')
    response = ce.get_cost_and_usage(
        TimePeriod={
            'Start': '2025-01-01',
            'End': '2025-01-31'
        },
        Granularity='MONTHLY',
        Metrics=['BlendedCost']
    )
    return response
```

#### Multi-Account Governance
```hcl
# Example: Terraform configuration for Organizations
resource "aws_organizations_policy" "cost_governance" {
  name = "CostGovernancePolicy"
  type = "SERVICE_CONTROL_POLICY"
  
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Deny"
        Action = [
          "ec2:RunInstances"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "ec2:InstanceType" = [
              "t3.micro",
              "t3.small",
              "t3.medium"
            ]
          }
        }
      }
    ]
  })
}
```

## Security Considerations

### IAM Best Practices
- All roles implement least-privilege access principles
- Cross-service permissions limited to required actions only
- CloudTrail logging enabled for all automated actions
- Resource-based policies prevent unauthorized access

### Data Protection
- S3 buckets encrypted with AWS KMS
- Lambda environment variables use AWS Systems Manager Parameter Store
- SNS topics encrypted in transit and at rest
- Config data retention follows compliance requirements

### Audit and Compliance
- All remediation actions logged to CloudTrail
- Config compliance history maintained for audit purposes
- SNS notifications provide real-time action tracking
- Dead letter queues capture failed operations for investigation

## Support

For issues with this infrastructure code, refer to:

1. **Original Recipe Documentation**: Complete implementation guide with troubleshooting
2. **AWS Documentation**: [AWS Config](https://docs.aws.amazon.com/config/), [Lambda](https://docs.aws.amazon.com/lambda/), [EventBridge](https://docs.aws.amazon.com/eventbridge/)
3. **Provider Documentation**: [CloudFormation](https://docs.aws.amazon.com/cloudformation/), [CDK](https://docs.aws.amazon.com/cdk/), [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
4. **Cost Optimization**: [AWS Well-Architected Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/)

## Contributing

To improve this infrastructure code:

1. Follow AWS best practices and security guidelines
2. Test changes in isolated environments before proposing updates
3. Update documentation to reflect configuration changes
4. Ensure backward compatibility with existing deployments
5. Include cost impact analysis for proposed modifications