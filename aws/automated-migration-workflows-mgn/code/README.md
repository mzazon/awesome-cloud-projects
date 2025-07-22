# Infrastructure as Code for Automated Application Migration Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Application Migration Workflows".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Administrative permissions for MGN, Migration Hub, CloudFormation, and Systems Manager
- On-premises servers with network connectivity to AWS (TCP 443 outbound)
- Basic understanding of VPC networking and security group configuration
- For CDK: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $150-300 for replication servers, storage, and data transfer during testing

## Quick Start

### Using CloudFormation
```bash
# Deploy the migration infrastructure
aws cloudformation create-stack \
    --stack-name migration-workflow-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-migration-project \
                ParameterKey=VpcCidr,ParameterValue=10.0.0.0/16

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name migration-workflow-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name migration-workflow-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the infrastructure
cdk deploy

# Get deployment outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the infrastructure
cdk deploy

# Get deployment outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
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
aws mgn describe-replication-configuration-templates \
    --query 'ReplicationConfigurationTemplates[0].ReplicationConfigurationTemplateID'
```

## Architecture Overview

This IaC deploys the following components:

### Core Migration Services
- **AWS Application Migration Service (MGN)**: Continuous replication and migration orchestration
- **Migration Hub Orchestrator**: Workflow automation and coordination
- **Migration Hub**: Centralized migration tracking and reporting

### Network Infrastructure
- **VPC**: Isolated network environment for migrated applications
- **Public/Private Subnets**: Segmented network topology
- **Internet Gateway**: Public internet connectivity
- **Route Tables**: Network routing configuration
- **Security Groups**: Network-level access control

### Automation & Monitoring
- **CloudWatch Dashboard**: Migration progress monitoring
- **CloudWatch Alarms**: Proactive issue detection
- **Systems Manager Documents**: Post-migration automation
- **IAM Roles**: Service permissions and access control

### Workflow Components
- **Orchestrator Templates**: Automated migration workflows
- **Launch Templates**: Consistent EC2 instance configuration
- **Replication Templates**: MGN replication settings

## Configuration Options

### Environment Variables
```bash
# Set before deployment
export AWS_REGION=us-east-1
export PROJECT_NAME=my-migration-project
export VPC_CIDR=10.0.0.0/16
export PUBLIC_SUBNET_CIDR=10.0.1.0/24
export PRIVATE_SUBNET_CIDR=10.0.2.0/24
```

### CloudFormation Parameters
- `ProjectName`: Unique identifier for migration project
- `VpcCidr`: CIDR block for migration VPC
- `PublicSubnetCidr`: CIDR for public subnet
- `PrivateSubnetCidr`: CIDR for private subnet
- `InstanceType`: EC2 instance type for replication servers

### Terraform Variables
```hcl
# terraform.tfvars
project_name = "my-migration-project"
vpc_cidr = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
instance_type = "t3.small"
```

## Deployment Validation

### Verify MGN Initialization
```bash
# Check MGN service status
aws mgn describe-replication-configuration-templates \
    --query 'ReplicationConfigurationTemplates[0].[ReplicationConfigurationTemplateID,ReplicationServerInstanceType]' \
    --output table
```

### Verify Network Configuration
```bash
# Check VPC and subnets
aws ec2 describe-vpcs \
    --filters "Name=tag:Purpose,Values=Migration" \
    --query 'Vpcs[0].[VpcId,State,CidrBlock]' \
    --output table

# Verify internet connectivity
aws ec2 describe-route-tables \
    --filters "Name=tag:Purpose,Values=Migration" \
    --query 'RouteTables[].Routes[?DestinationCidrBlock==`0.0.0.0/0`]' \
    --output table
```

### Verify Workflow Configuration
```bash
# Check Migration Hub Orchestrator templates
aws migrationhub-orchestrator list-templates \
    --query 'TemplateSummary[?contains(Name, `AutomatedMigrationWorkflow`)]' \
    --output table
```

### Verify Monitoring Setup
```bash
# Check CloudWatch dashboard
aws cloudwatch list-dashboards \
    --query 'DashboardEntries[?contains(DashboardName, `Migration`)]' \
    --output table

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "MGN-Replication-Health" \
    --query 'MetricAlarms[0].[AlarmName,StateValue,MetricName]' \
    --output table
```

## Using the Migration Workflow

### 1. Install MGN Agents on Source Servers
```bash
# Download agent installer (Linux example)
wget https://aws-application-migration-service-${AWS_REGION}.s3.amazonaws.com/latest/linux/aws-replication-installer-init.py

# Install with API key (obtained from MGN console)
sudo python3 aws-replication-installer-init.py --region ${AWS_REGION} --aws-access-key-id YOUR_ACCESS_KEY --aws-secret-access-key YOUR_SECRET_KEY
```

### 2. Monitor Replication Progress
```bash
# Check source server status
aws mgn describe-source-servers \
    --query 'SourceServers[*].[SourceServerID,ReplicationInfo.ReplicationState,DataReplicationInfo.DataReplicationState]' \
    --output table
```

### 3. Launch Test Instances
```bash
# Start test launch for a source server
aws mgn start-test \
    --source-server-id s-1234567890abcdef0

# Monitor test launch progress
aws mgn describe-job-log-items \
    --job-id j-1234567890abcdef0 \
    --query 'Items[*].[Event,EventDateTime]' \
    --output table
```

### 4. Execute Cutover
```bash
# Start cutover launch
aws mgn start-cutover \
    --source-server-id s-1234567890abcdef0

# Monitor cutover progress
aws mgn describe-job-log-items \
    --job-id j-1234567890abcdef0 \
    --query 'Items[*].[Event,EventDateTime]' \
    --output table
```

## Troubleshooting

### Common Issues

1. **MGN Service Not Initialized**
   ```bash
   # Initialize MGN service
   aws mgn initialize-service --region ${AWS_REGION}
   ```

2. **Network Connectivity Issues**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups \
       --filters "Name=group-name,Values=migration-sg-*" \
       --query 'SecurityGroups[0].IpPermissions'
   ```

3. **Replication Agent Issues**
   ```bash
   # Check agent logs on source server
   sudo cat /var/log/aws-replication-agent.log
   ```

4. **Workflow Execution Failures**
   ```bash
   # Check workflow step status
   aws migrationhub-orchestrator get-workflow-step \
       --workflow-id ${WORKFLOW_ID} \
       --step-group-id ${STEP_GROUP_ID} \
       --id ${STEP_ID}
   ```

### Monitoring and Logging

- **CloudWatch Logs**: `/aws/migrationhub-orchestrator` log group
- **MGN Metrics**: Available in CloudWatch under `AWS/MGN` namespace
- **VPC Flow Logs**: Enable for network troubleshooting
- **Systems Manager Session Manager**: For secure instance access

## Security Considerations

### IAM Permissions
The deployment creates IAM roles with minimum required permissions:
- **MGN Service Role**: Replication and launch operations
- **Orchestrator Execution Role**: Workflow coordination
- **Systems Manager Role**: Post-migration automation

### Network Security
- **Private Subnets**: Replication servers deployed in private subnets
- **Security Groups**: Restrictive rules with least privilege access
- **VPC Isolation**: Dedicated VPC for migration operations
- **Encryption**: All replication data encrypted in transit and at rest

### Data Protection
- **EBS Encryption**: Enabled for all migration storage
- **S3 Encryption**: Migration artifacts encrypted
- **CloudWatch Logs**: Encrypted log storage
- **KMS Integration**: Customer-managed keys supported

## Cost Optimization

### Resource Sizing
- **Replication Servers**: Right-sized based on source server requirements
- **Storage**: GP3 volumes for cost-effective performance
- **Data Transfer**: Optimized replication schedules

### Monitoring Costs
```bash
# Check MGN service costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["AWS Application Migration Service"]}}'
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name migration-workflow-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name migration-workflow-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining MGN resources
aws mgn describe-source-servers \
    --query 'SourceServers[*].SourceServerID' \
    --output text | xargs -I {} aws mgn disconnect-from-service --source-server-id {}

# Clean up any remaining replication instances
aws ec2 describe-instances \
    --filters "Name=tag:AWSApplicationMigrationServiceManaged,Values=true" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text | xargs -I {} aws ec2 terminate-instances --instance-ids {}
```

## Support and Documentation

- [AWS Application Migration Service User Guide](https://docs.aws.amazon.com/mgn/latest/ug/)
- [Migration Hub Orchestrator Documentation](https://docs.aws.amazon.com/migrationhub-orchestrator/latest/userguide/)
- [AWS Well-Architected Migration Lens](https://docs.aws.amazon.com/wellarchitected/latest/migration-lens/welcome.html)
- [Migration Hub Best Practices](https://docs.aws.amazon.com/migrationhub/latest/ug/best-practices.html)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.