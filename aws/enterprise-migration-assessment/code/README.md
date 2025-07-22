# Infrastructure as Code for Enterprise Migration Assessment and Planning

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Migration Assessment and Planning".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Application Discovery Service
  - Migration Hub
  - S3 bucket creation and management
  - CloudWatch Logs
  - EventBridge
  - IAM role creation
- On-premises servers for agent deployment (Windows Server 2008 R2+ or Linux RHEL 6+, CentOS 6+, Ubuntu 12+)
- Network connectivity from on-premises to AWS (port 443 HTTPS outbound)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name enterprise-migration-discovery \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-migration \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name enterprise-migration-discovery

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name enterprise-migration-discovery \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_name=my-migration"

# Apply the configuration
terraform apply -var="project_name=my-migration"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the script prompts for configuration
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to:

1. **Download and Install Discovery Agents**:
   ```bash
   # Windows Agent
   curl -O https://aws-discovery-agent.s3.amazonaws.com/windows/latest/AWSApplicationDiscoveryAgentInstaller.exe
   
   # Linux Agent
   curl -O https://aws-discovery-agent.s3.amazonaws.com/linux/latest/aws-discovery-agent.tar.gz
   ```

2. **Configure VMware Discovery Connector** (if using VMware):
   - Download the OVA from: `https://aws-discovery-connector.s3.amazonaws.com/VMware/latest/AWS-Discovery-Connector.ova`
   - Deploy to your vSphere environment
   - Configure with your AWS credentials and vCenter details

3. **Start Data Collection**:
   ```bash
   # Enable Application Discovery Service
   aws discovery start-data-collection-by-agent-ids --agent-ids []
   
   # Verify agents are reporting
   aws discovery describe-agents
   ```

4. **Monitor Discovery Progress**:
   - Access AWS Migration Hub dashboard
   - Review discovered servers and applications
   - Export discovery data for analysis

## Infrastructure Components

The deployed infrastructure includes:

- **S3 Bucket**: For storing discovery data exports with versioning enabled
- **CloudWatch Log Group**: For monitoring discovery service logs
- **EventBridge Rule**: For automated weekly data exports
- **IAM Roles**: For Application Discovery Service and Migration Hub access
- **Migration Hub Configuration**: Centralized migration tracking

## Customization

### CloudFormation Parameters

- `ProjectName`: Name for the migration project (default: enterprise-migration)
- `S3BucketName`: Custom S3 bucket name for discovery data
- `ExportSchedule`: CloudWatch Events schedule for automated exports

### CDK Configuration

Modify the stack configuration in the CDK app files:

```typescript
// TypeScript example
const migrationStack = new MigrationDiscoveryStack(app, 'MigrationDiscoveryStack', {
  projectName: 'my-migration-project',
  exportSchedule: 'rate(7 days)',
});
```

### Terraform Variables

```hcl
# terraform.tfvars
project_name = "my-migration-project"
export_schedule = "rate(7 days)"
enable_continuous_export = true
```

## Monitoring and Validation

### Check Discovery Agent Health

```bash
# List all discovered agents
aws discovery describe-agents \
    --query 'agentsInfo[*].[agentId,health,collectionStatus,lastHealthPingTime]' \
    --output table
```

### Review Discovered Infrastructure

```bash
# List discovered servers
aws discovery list-configurations \
    --configuration-type SERVER \
    --query 'configurations[*].[configurationId,serverType,osName]' \
    --output table

# Check network connections
aws discovery list-configurations \
    --configuration-type NETWORK_CONNECTION \
    --max-results 10
```

### Monitor Export Status

```bash
# Check export task status
aws discovery describe-export-tasks \
    --query 'exportsInfo[*].[exportId,exportStatus,exportRequestTime]' \
    --output table

# List exported files in S3
aws s3 ls s3://your-discovery-bucket/exports/ --recursive
```

## Security Considerations

- Discovery agents communicate over HTTPS (port 443) to AWS endpoints
- All discovery data is encrypted in transit and at rest
- IAM roles follow least privilege principle
- S3 bucket has versioning enabled for data protection
- No actual application data is collected, only metadata and performance metrics

## Cost Optimization

- Discovery agents cost approximately $0.10-$0.50 per server per day
- S3 storage costs for discovery data are typically minimal
- Consider data retention policies for long-term cost management
- Use discovery insights to identify over-provisioned resources for cost savings

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name enterprise-migration-discovery

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name enterprise-migration-discovery
```

### Using CDK

```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy -var="project_name=my-migration"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Tasks

After infrastructure cleanup, manually:

1. **Uninstall Discovery Agents** from on-premises servers:
   ```bash
   # Windows
   msiexec /x {APPLICATION-DISCOVERY-AGENT-GUID} /quiet
   
   # Linux
   sudo /opt/aws/discovery/uninstall
   ```

2. **Remove Discovery Connector** from VMware environment (delete VM)

3. **Verify S3 bucket deletion** and remove any remaining objects if needed

## Troubleshooting

### Common Issues

1. **Agents not appearing in console**:
   - Verify network connectivity (port 443 outbound)
   - Check AWS credentials configuration
   - Ensure Application Discovery Service is enabled

2. **Export tasks failing**:
   - Verify S3 bucket permissions
   - Check IAM role policies
   - Ensure sufficient data has been collected

3. **Missing dependency data**:
   - Allow 24-48 hours for initial data collection
   - Verify agent configuration includes network monitoring
   - Check that applications are actively running

### Support Resources

- [AWS Application Discovery Service User Guide](https://docs.aws.amazon.com/application-discovery/latest/userguide/)
- [AWS Migration Hub Documentation](https://docs.aws.amazon.com/migrationhub/)
- [Migration Planning Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-tools/discovery.html)

## Support

For issues with this infrastructure code, refer to:
- The original recipe documentation
- AWS Application Discovery Service documentation
- AWS Migration Hub documentation
- AWS Support (for account-specific issues)