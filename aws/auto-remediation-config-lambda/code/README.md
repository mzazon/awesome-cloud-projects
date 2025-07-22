# Infrastructure as Code for Auto-Remediation with Config and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Auto-Remediation with Config and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements automated compliance remediation using:
- AWS Config for continuous monitoring and evaluation
- Lambda functions for custom remediation actions
- Systems Manager for standardized automation
- SNS for notifications and audit trails
- CloudWatch for monitoring and dashboards

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for Config, Lambda, Systems Manager, IAM, SNS, and CloudWatch
- Understanding of AWS Config rules and compliance concepts
- Basic knowledge of Lambda functions and Systems Manager automation
- Estimated cost: $30-100/month depending on resource count and rule evaluations

> **Note**: AWS Config charges for configuration items recorded and rule evaluations. Monitor usage and optimize rules to control costs while maintaining compliance coverage.

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name config-auto-remediation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev \
                ParameterKey=NotificationEmail,ParameterValue=your-email@example.com
```

Monitor deployment progress:
```bash
aws cloudformation describe-stacks \
    --stack-name config-auto-remediation-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
cdk bootstrap  # Only needed once per account/region
cdk deploy --parameters notificationEmail=your-email@example.com
```

### Using CDK Python
```bash
cd cdk-python/
python -m pip install -r requirements.txt
cdk bootstrap  # Only needed once per account/region
cdk deploy --parameters notificationEmail=your-email@example.com
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="notification_email=your-email@example.com"
terraform apply -var="notification_email=your-email@example.com"
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
export NOTIFICATION_EMAIL=your-email@example.com
./scripts/deploy.sh
```

## Post-Deployment Testing

After deployment, test the auto-remediation system:

1. **Create a non-compliant security group**:
   ```bash
   # Create test security group with unrestricted SSH access
   TEST_SG_ID=$(aws ec2 create-security-group \
       --group-name "test-sg-$(date +%s)" \
       --description "Test security group for Config remediation" \
       --query 'GroupId' --output text)
   
   # Add unrestricted SSH rule
   aws ec2 authorize-security-group-ingress \
       --group-id ${TEST_SG_ID} \
       --protocol tcp \
       --port 22 \
       --cidr 0.0.0.0/0
   
   echo "Created test security group: ${TEST_SG_ID}"
   ```

2. **Monitor remediation**:
   ```bash
   # Wait for Config evaluation (2-3 minutes)
   sleep 180
   
   # Check if rule was remediated
   aws ec2 describe-security-groups \
       --group-ids ${TEST_SG_ID} \
       --query 'SecurityGroups[0].IpPermissions'
   
   # Check remediation execution status
   aws configservice describe-remediation-execution-status \
       --config-rule-name "security-group-ssh-restricted"
   ```

3. **View compliance dashboard**:
   ```bash
   # Get dashboard URL
   echo "https://console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#dashboards:name=Config-Compliance-Dashboard"
   ```

## Configuration Options

### Environment Variables
- `NOTIFICATION_EMAIL`: Email address for SNS notifications
- `AWS_REGION`: AWS region for deployment (defaults to CLI configured region)
- `ENVIRONMENT`: Environment tag (dev, staging, prod)

### Terraform Variables
```hcl
variable "notification_email" {
  description = "Email address for compliance notifications"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "auto_remediation_enabled" {
  description = "Enable automatic remediation"
  type        = bool
  default     = true
}

variable "max_remediation_attempts" {
  description = "Maximum automatic remediation attempts"
  type        = number
  default     = 3
}
```

### CloudFormation Parameters
```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
    Description: Environment name for resource tagging
  
  NotificationEmail:
    Type: String
    Description: Email address for compliance notifications
    
  AutoRemediationEnabled:
    Type: String
    Default: "true"
    AllowedValues: ["true", "false"]
    Description: Enable automatic remediation
```

## Monitored Resources and Rules

### Security Group Rules
- **Rule**: `security-group-ssh-restricted`
- **Description**: Checks if security groups allow unrestricted SSH access (0.0.0.0/0)
- **Remediation**: Automatically removes unrestricted inbound SSH rules
- **Scope**: AWS::EC2::SecurityGroup

### S3 Bucket Rules
- **Rule**: `s3-bucket-public-access-prohibited`
- **Description**: Checks if S3 buckets allow public access
- **Remediation**: Enables S3 bucket public access block configuration
- **Scope**: AWS::S3::Bucket

## Remediation Functions

### Security Group Remediation
- **Function**: `SecurityGroupRemediationFunction`
- **Runtime**: Python 3.9
- **Timeout**: 60 seconds
- **Actions**: 
  - Removes unrestricted inbound rules (0.0.0.0/0)
  - Tags remediated resources
  - Sends SNS notifications

### S3 Bucket Remediation
- **Automation Document**: `S3-RemediatePublicAccess`
- **Actions**:
  - Enables public access block
  - Applies bucket-level restrictions
  - Logs remediation actions

## Monitoring and Alerting

### CloudWatch Dashboard
- Config rule compliance status
- Remediation function metrics (invocations, errors, duration)
- Resource compliance trends
- Remediation success rates

### SNS Notifications
- Compliance violations detected
- Remediation actions completed
- Remediation failures requiring manual intervention

### CloudWatch Alarms
- High rate of compliance violations
- Remediation function errors
- Config service health

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name config-auto-remediation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name config-auto-remediation-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="notification_email=your-email@example.com"
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# Clean up any remaining test resources
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=test-sg-*" \
    --query 'SecurityGroups[*].GroupId' --output text | \
xargs -n1 -I {} aws ec2 delete-security-group --group-id {}
```

## Troubleshooting

### Common Issues

1. **Config recorder not starting**:
   ```bash
   # Check IAM role permissions
   aws iam get-role --role-name AWSConfigRole
   
   # Verify S3 bucket policy
   aws s3api get-bucket-policy --bucket your-config-bucket
   ```

2. **Lambda function errors**:
   ```bash
   # Check function logs
   aws logs tail /aws/lambda/SecurityGroupRemediationFunction --follow
   
   # Check function configuration
   aws lambda get-function --function-name SecurityGroupRemediationFunction
   ```

3. **Remediation not executing**:
   ```bash
   # Check remediation configuration
   aws configservice describe-remediation-configurations \
       --config-rule-names security-group-ssh-restricted
   
   # Check Config rule status
   aws configservice describe-config-rules \
       --config-rule-names security-group-ssh-restricted
   ```

### Debug Commands
```bash
# Check Config service status
aws configservice describe-configuration-recorders
aws configservice describe-delivery-channels

# Check compliance summary
aws configservice get-compliance-summary-by-config-rule

# View recent evaluations
aws configservice get-compliance-details-by-config-rule \
    --config-rule-name security-group-ssh-restricted \
    --compliance-types NON_COMPLIANT
```

## Security Considerations

- IAM roles follow least privilege principle
- Lambda functions have minimal required permissions
- All remediation actions are logged and auditable
- SNS topics use encryption in transit
- S3 buckets for Config use server-side encryption
- Resource tagging enables governance and cost tracking

## Cost Optimization

- Config rules are scoped to specific resource types
- Lambda functions use ARM-based processors for cost efficiency
- CloudWatch log retention is set to reasonable periods
- Unused remediation rules can be disabled

## Customization

### Adding New Rules
1. Create new Config rule in IaC templates
2. Add corresponding remediation Lambda function or SSM document
3. Update IAM permissions for new resource types
4. Add monitoring to CloudWatch dashboard

### Custom Remediation Logic
1. Modify Lambda function code in the templates
2. Update IAM permissions as needed
3. Test remediation logic in development environment
4. Deploy updates using your chosen IaC method

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS Config and Lambda documentation
3. Refer to the original recipe documentation
4. Check AWS service health dashboard

## Additional Resources

- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/)
- [AWS Config Remediation Documentation](https://docs.aws.amazon.com/config/latest/developerguide/setup-autoremediation.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS Systems Manager Automation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-automation.html)