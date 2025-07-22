# Infrastructure as Code for VMware Cloud Migration with VMware Cloud on AWS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "VMware Cloud Migration with VMware Cloud on AWS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- VMware Cloud on AWS service enabled in your AWS account
- My VMware account with appropriate licensing
- Appropriate AWS permissions for:
  - VMware Cloud on AWS service management
  - VPC and networking resources
  - IAM role creation
  - S3 bucket operations
  - CloudWatch and monitoring services
  - Application Migration Service
  - Direct Connect (if using dedicated connectivity)
- Network connectivity planning between on-premises and AWS
- Estimated cost: $8,000-15,000/month for 3-host SDDC cluster

> **Warning**: VMware Cloud on AWS incurs significant monthly costs. Plan your deployment timeline carefully to minimize infrastructure costs.

## Architecture Overview

This solution deploys:

- **Networking Foundation**: VPC, subnets, security groups, and routing for VMware Cloud connectivity
- **Migration Services**: AWS Application Migration Service configuration for non-VMware workloads
- **Connectivity**: Direct Connect gateway and virtual interfaces for dedicated connectivity
- **Monitoring**: CloudWatch dashboards, alarms, and log groups for operational visibility
- **Backup & DR**: S3 buckets with lifecycle policies for backup and disaster recovery
- **Cost Management**: AWS Budgets and Cost Anomaly Detection for cost optimization
- **Migration Orchestration**: Lambda functions and DynamoDB for migration tracking

> **Note**: The actual VMware Cloud on AWS SDDC deployment must be completed through the VMware Cloud Console as it requires specific VMware licensing and configuration.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name vmware-migration-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=AdminEmail,ParameterValue=admin@company.com \
                 ParameterKey=ManagementSubnet,ParameterValue=10.0.0.0/16

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name vmware-migration-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk bootstrap
cdk deploy

# View stack outputs
cdk output
```

### Using CDK Python (AWS)

```bash
# Set up Python environment
cd cdk-python/
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk bootstrap
cdk deploy

# View stack outputs
cdk output
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
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
./scripts/deploy.sh --status
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these manual steps:

1. **VMware Cloud on AWS SDDC Creation**:
   - Login to VMware Cloud Console (vmc.vmware.com)
   - Create new SDDC with the following parameters:
     - Use the VPC ID from the infrastructure outputs
     - Use the subnet ID from the infrastructure outputs
     - Select 3-host cluster (minimum for production)
     - Configure management subnet (10.0.0.0/16)

2. **HCX Configuration**:
   - Deploy HCX Manager on-premises
   - Configure HCX Cloud Manager in VMware Cloud on AWS
   - Set up network profiles and service mesh
   - Create compute and network profiles

3. **Direct Connect Setup** (if using dedicated connectivity):
   - Configure Direct Connect connection
   - Set up virtual interfaces
   - Update routing tables

4. **Migration Planning**:
   - Assess on-premises workloads
   - Create migration waves
   - Configure HCX migration policies
   - Test migration with non-critical workloads

## Monitoring and Alerts

The deployment includes:

- **CloudWatch Dashboard**: "VMware-Migration-Dashboard" for operational visibility
- **CloudWatch Alarms**: SDDC health monitoring and migration progress tracking
- **SNS Notifications**: Email alerts for critical events and cost thresholds
- **EventBridge Rules**: Automated response to SDDC state changes
- **Cost Monitoring**: Budget alerts and anomaly detection

## Security Considerations

- **Least Privilege Access**: IAM roles follow principle of least privilege
- **Network Security**: Security groups restrict access to necessary ports only
- **Encryption**: S3 buckets use default encryption, Direct Connect uses MACsec when available
- **Monitoring**: All API calls are logged to CloudTrail
- **Backup Security**: S3 bucket policies prevent unauthorized access

## Customization

### Variables and Parameters

Key customizable values include:

- **Network Configuration**: VPC CIDR, subnet ranges, management subnet
- **SDDC Configuration**: Host count, instance type, storage policy
- **Cost Controls**: Budget thresholds, alert recipients
- **Backup Policies**: Retention periods, lifecycle transitions
- **Migration Settings**: Wave configurations, batch sizes

### Environment-Specific Settings

Create environment-specific configurations:

```bash
# Development environment
export ENVIRONMENT=dev
export SDDC_HOST_COUNT=1
export BACKUP_RETENTION_DAYS=7

# Production environment
export ENVIRONMENT=prod
export SDDC_HOST_COUNT=3
export BACKUP_RETENTION_DAYS=2555  # 7 years
```

## Cost Optimization

### Expected Costs

- **VMware Cloud on AWS**: $8,000-15,000/month (3-host cluster)
- **AWS Services**: $200-500/month (supporting infrastructure)
- **Data Transfer**: Variable based on migration volume
- **Direct Connect**: $500-2,000/month (if using dedicated connectivity)

### Cost Optimization Strategies

1. **Right-sizing**: Start with minimum cluster size, scale as needed
2. **Reserved Instances**: Use reserved capacity for predictable workloads
3. **Storage Optimization**: Implement S3 lifecycle policies for backup data
4. **Network Optimization**: Use Direct Connect for high-volume data transfer
5. **Monitoring**: Set up cost alerts and anomaly detection

## Troubleshooting

### Common Issues

1. **SDDC Deployment Failures**:
   - Verify VPC and subnet configuration
   - Check IAM permissions
   - Ensure sufficient AWS service limits

2. **Network Connectivity Issues**:
   - Verify security group rules
   - Check route table configurations
   - Validate Direct Connect setup

3. **Migration Failures**:
   - Test HCX connectivity
   - Verify network profiles
   - Check resource availability

### Log Locations

- **CloudWatch Logs**: `/aws/vmware/migration` log group
- **SDDC Events**: EventBridge rules capture state changes
- **Cost Alerts**: SNS notifications for budget thresholds

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name vmware-migration-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name vmware-migration-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Verify cleanup
aws cloudformation list-stacks \
    --stack-status-filter DELETE_COMPLETE
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/destroy.sh --verify
```

### Manual Cleanup Required

Some resources require manual cleanup:

1. **VMware Cloud on AWS SDDC**: Delete through VMware Cloud Console
2. **Direct Connect**: Remove virtual interfaces and connections
3. **S3 Bucket Contents**: Empty buckets before deletion (if versioning enabled)
4. **CloudWatch Logs**: May be retained beyond stack deletion

## Migration Best Practices

### Pre-Migration

1. **Assessment**: Inventory all VMware workloads and dependencies
2. **Network Planning**: Design network architecture for hybrid operations
3. **Testing**: Validate connectivity and performance with test workloads
4. **Training**: Ensure team familiarity with VMware Cloud on AWS

### During Migration

1. **Phased Approach**: Start with non-critical workloads
2. **Monitoring**: Track migration progress and performance
3. **Rollback Planning**: Maintain ability to rollback critical workloads
4. **Communication**: Keep stakeholders informed of progress

### Post-Migration

1. **Optimization**: Right-size resources based on actual usage
2. **Monitoring**: Establish ongoing operational procedures
3. **Security**: Implement cloud security best practices
4. **Training**: Provide team training on hybrid operations

## Support and Documentation

### Official Documentation

- [VMware Cloud on AWS Documentation](https://docs.vmware.com/en/VMware-Cloud-on-AWS/)
- [VMware HCX Documentation](https://docs.vmware.com/en/VMware-HCX/)
- [AWS Application Migration Service](https://docs.aws.amazon.com/mgn/)
- [AWS Direct Connect](https://docs.aws.amazon.com/directconnect/)

### Community Resources

- [VMware Cloud on AWS Community](https://communities.vmware.com/t5/VMware-Cloud-on-AWS/ct-p/2618)
- [AWS Migration Hub](https://aws.amazon.com/migration-hub/)
- [VMware Cloud Provider Hub](https://cloud.vmware.com/providers)

### Enterprise Support

- VMware Professional Services for migration planning
- AWS Professional Services for cloud architecture
- VMware Cloud on AWS Support for operational issues

## License and Disclaimer

This infrastructure code is provided as-is for educational and demonstration purposes. Users are responsible for:

- Ensuring compliance with VMware licensing requirements
- Validating security configurations for their environment
- Testing thoroughly before production deployment
- Monitoring and managing ongoing costs

For production deployments, consider engaging VMware and AWS Professional Services for architecture review and implementation guidance.