# Infrastructure as Code for Cross-Region Disaster Recovery Automation with AWS Elastic Disaster Recovery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Region Disaster Recovery Automation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Elastic Disaster Recovery (DRS)
  - Lambda functions
  - CloudWatch (alarms, dashboards, logs)
  - Systems Manager
  - Step Functions
  - Route 53 (for DNS failover)
  - IAM roles and policies
  - VPC and networking resources
  - SNS topics
- Source servers running supported operating systems (Windows Server 2008+, RHEL 6+, Ubuntu 14+)
- Network connectivity between source servers and AWS
- Estimated cost: $200-800/month depending on server count and storage requirements

## Architecture Overview

This solution implements automated cross-region disaster recovery using AWS Elastic Disaster Recovery with:

- Continuous data replication from primary to DR region
- Automated failover orchestration with Step Functions
- CloudWatch monitoring and alerting
- DNS failover with Route 53
- Automated testing and failback capabilities
- Comprehensive monitoring dashboards

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name dr-automation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=DRRegion,ParameterValue=us-west-2 \
                 ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name dr-automation-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure CDK (if first time)
npx cdk bootstrap --region us-east-1
npx cdk bootstrap --region us-west-2

# Set configuration
export PRIMARY_REGION=us-east-1
export DR_REGION=us-west-2
export NOTIFICATION_EMAIL=admin@example.com

# Deploy the stack
npx cdk deploy --all --require-approval never

# View outputs
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure CDK (if first time)
cdk bootstrap --region us-east-1
cdk bootstrap --region us-west-2

# Set configuration
export PRIMARY_REGION=us-east-1
export DR_REGION=us-west-2
export NOTIFICATION_EMAIL=admin@example.com

# Deploy the stack
cdk deploy --all --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="primary_region=us-east-1" \
               -var="dr_region=us-west-2" \
               -var="notification_email=admin@example.com"

# Apply configuration
terraform apply -var="primary_region=us-east-1" \
                -var="dr_region=us-west-2" \
                -var="notification_email=admin@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PRIMARY_REGION=us-east-1
export DR_REGION=us-west-2
export NOTIFICATION_EMAIL=admin@example.com

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws drs describe-replication-configuration-templates --region $PRIMARY_REGION
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to:

1. **Install DRS Agents on Source Servers**:
   ```bash
   # Download and run the generated installation script
   wget https://aws-elastic-disaster-recovery-us-east-1.s3.amazonaws.com/latest/linux/aws-replication-installer-init.py
   sudo python3 aws-replication-installer-init.py \
       --region us-east-1 \
       --aws-access-key-id YOUR_ACCESS_KEY \
       --aws-secret-access-key YOUR_SECRET_KEY \
       --no-prompt
   ```

2. **Configure Route 53 Health Checks**:
   ```bash
   # Create health check for your application
   aws route53 create-health-check \
       --caller-reference "app-health-$(date +%s)" \
       --health-check-config Type=HTTP,ResourcePath=/health,Port=80,RequestInterval=30
   ```

3. **Subscribe to SNS Notifications**:
   ```bash
   # Subscribe to DR alerts (replace with your email)
   aws sns subscribe \
       --topic-arn $(terraform output -raw sns_topic_arn) \
       --protocol email \
       --notification-endpoint admin@example.com
   ```

4. **Test Disaster Recovery**:
   ```bash
   # Trigger a DR drill
   aws lambda invoke \
       --function-name $(terraform output -raw dr_testing_function_name) \
       --payload '{"testMode": true}' \
       test-output.json
   ```

## Monitoring and Validation

### Check DRS Status

```bash
# View source servers and replication status
aws drs describe-source-servers \
    --region us-east-1 \
    --query 'sourceServers[*].{ID:sourceServerID,State:dataReplicationInfo.replicationState,Lag:dataReplicationInfo.lagDuration}'

# Check replication configuration
aws drs describe-replication-configuration-templates \
    --region us-east-1
```

### Monitor CloudWatch Dashboards

```bash
# View DR monitoring dashboard
aws cloudwatch get-dashboard \
    --dashboard-name $(terraform output -raw dashboard_name) \
    --region us-east-1
```

### Test Automation

```bash
# Test Step Functions workflow
aws stepfunctions start-execution \
    --state-machine-arn $(terraform output -raw step_functions_arn) \
    --input '{"testMode": true}' \
    --region us-east-1
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name dr-automation-stack \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name dr-automation-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Destroy all stacks
npx cdk destroy --all --force
```

### Using CDK Python

```bash
cd cdk-python/

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Destroy all stacks
cdk destroy --all --force

# Deactivate virtual environment
deactivate
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="primary_region=us-east-1" \
                  -var="dr_region=us-west-2" \
                  -var="notification_email=admin@example.com"

# Clean up state files (optional)
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws drs describe-source-servers --region $PRIMARY_REGION --query 'sourceServers'
```

## Customization

### Key Configuration Parameters

- **Regions**: Primary and DR regions can be customized
- **Instance Types**: Replication server and recovery instance types
- **Storage**: EBS volume types and sizes for staging areas
- **Network**: VPC CIDR blocks and subnet configurations
- **Monitoring**: CloudWatch alarm thresholds and notification settings
- **Scheduling**: DR testing frequency and automation triggers

### Common Customizations

1. **Multi-AZ Deployment**:
   ```bash
   # Modify Terraform variables
   echo 'enable_multi_az = true' >> terraform.tfvars
   ```

2. **Custom Encryption**:
   ```bash
   # Use custom KMS key
   echo 'kms_key_arn = "arn:aws:kms:region:account:key/key-id"' >> terraform.tfvars
   ```

3. **Network Isolation**:
   ```bash
   # Deploy in private subnets only
   echo 'enable_public_ip = false' >> terraform.tfvars
   ```

## Troubleshooting

### Common Issues

1. **DRS Service Not Initialized**:
   ```bash
   # Initialize DRS service
   aws drs initialize-service --region us-east-1
   ```

2. **Replication Lag Issues**:
   ```bash
   # Check network connectivity and bandwidth
   aws drs describe-source-servers --region us-east-1 \
       --query 'sourceServers[*].dataReplicationInfo'
   ```

3. **Lambda Function Errors**:
   ```bash
   # View function logs
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/dr-"
   ```

4. **IAM Permission Issues**:
   ```bash
   # Verify role permissions
   aws iam get-role --role-name DRAutomationRole
   ```

### Validation Commands

```bash
# Test connectivity to DRS endpoints
curl -I https://drs.us-east-1.amazonaws.com

# Verify Lambda function configuration
aws lambda get-function --function-name dr-automated-failover

# Check Step Functions execution history
aws stepfunctions list-executions --state-machine-arn <state-machine-arn>
```

## Security Considerations

- All data replication is encrypted in transit and at rest
- IAM roles follow principle of least privilege
- VPC security groups restrict access to necessary ports only
- CloudTrail logging enabled for audit trails
- SNS topics encrypted with AWS managed keys

## Cost Optimization

- DRS staging areas use cost-effective storage classes
- Recovery instances launched only during drills or actual recovery
- CloudWatch logs retention configured to minimize storage costs
- Lambda functions use appropriate memory allocations

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS Elastic Disaster Recovery documentation
3. Consult provider-specific troubleshooting guides
4. Verify IAM permissions and service quotas
5. Review CloudWatch logs for detailed error information

## Additional Resources

- [AWS Elastic Disaster Recovery User Guide](https://docs.aws.amazon.com/drs/latest/userguide/)
- [AWS Well-Architected Framework - Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/)
- [Disaster Recovery of Workloads on AWS](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/)