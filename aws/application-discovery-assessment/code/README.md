# Infrastructure as Code for Application Discovery and Migration Assessment

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Application Discovery and Migration Assessment".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Application Discovery Service
  - AWS Migration Hub
  - Amazon S3
  - AWS IAM
  - Amazon Athena
  - AWS CloudWatch Events
  - AWS Lambda
- On-premises environment with VMware vCenter (for agentless discovery) or direct server access (for agent-based discovery)
- Network connectivity between on-premises environment and AWS
- Basic understanding of network topologies and server infrastructure

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name application-discovery-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=MigrationHubHomeRegion,ParameterValue=us-west-2

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name application-discovery-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name application-discovery-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Deploy the infrastructure
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy the infrastructure
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
echo "Check AWS console for Migration Hub and Application Discovery Service resources"
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to complete these manual steps:

### 1. Deploy Agentless Collector (VMware Environments)
```bash
# Download the Agentless Collector OVA from AWS Migration Hub console
# Navigate to: AWS Migration Hub -> Discover -> Tools
# Deploy the OVA file to your VMware vCenter environment
# Configure collector with AWS credentials and region
```

### 2. Install Discovery Agents (Physical/Non-VMware Servers)
```bash
# Download and install Discovery Agent for Linux
wget https://s3-us-west-2.amazonaws.com/aws-discovery-agent.us-west-2/linux/latest/aws-discovery-agent.tar.gz
tar -xzf aws-discovery-agent.tar.gz
sudo ./install -r us-west-2 -k <ACCESS_KEY> -s <SECRET_KEY>

# Start the discovery agent
sudo /opt/aws/discovery/bin/aws-discovery-daemon --start
```

### 3. Start Data Collection
```bash
# Get your AWS region
AWS_REGION=$(aws configure get region)

# List discovery agents
aws discovery describe-agents --region ${AWS_REGION}

# Start data collection for all agents
AGENT_IDS=$(aws discovery describe-agents \
    --query 'agentConfigurations[*].agentId' \
    --output text --region ${AWS_REGION})

if [ ! -z "$AGENT_IDS" ]; then
    aws discovery start-data-collection-by-agent-ids \
        --agent-ids ${AGENT_IDS} --region ${AWS_REGION}
fi
```

### 4. Configure Migration Hub Home Region
```bash
# Set Migration Hub home region (if not already configured)
aws migrationhub create-progress-update-stream \
    --progress-update-stream-name "DiscoveryAssessment" \
    --region us-west-2
```

## Monitoring and Validation

### Check Discovery Status
```bash
# Monitor agent health
aws discovery describe-agents --region ${AWS_REGION}

# View discovered servers
aws discovery describe-configurations \
    --configuration-type SERVER \
    --region ${AWS_REGION}

# Check continuous export status
aws discovery describe-continuous-exports --region ${AWS_REGION}
```

### Validate S3 Data Export
```bash
# List exported discovery data
aws s3 ls s3://$(aws cloudformation describe-stacks \
    --stack-name application-discovery-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DiscoveryBucketName`].OutputValue' \
    --output text)/continuous-export/ --recursive
```

### Query Data with Athena
```bash
# List Athena databases
aws athena list-databases \
    --catalog-name AwsDataCatalog \
    --query-execution-context Database=discovery_analysis

# Execute sample query
aws athena start-query-execution \
    --query-string "SELECT server_hostname, server_os_name, server_total_ram_kb FROM discovery_analysis.servers LIMIT 10" \
    --result-configuration OutputLocation=s3://your-discovery-bucket/athena-results/
```

## Cost Optimization

### Estimated Monthly Costs
- **Application Discovery Service**: Free for data collection
- **S3 Storage**: $0.023/GB for Standard storage
- **Athena Queries**: $5.00/TB of data scanned
- **CloudWatch Events**: $1.00/million events
- **Lambda Execution**: $0.0000002/request + $0.0000166667/GB-second

### Cost Management Tips
```bash
# Configure S3 lifecycle policies for cost optimization
aws s3api put-bucket-lifecycle-configuration \
    --bucket your-discovery-bucket \
    --lifecycle-configuration file://lifecycle-policy.json

# Monitor S3 storage usage
aws s3 ls s3://your-discovery-bucket --recursive --human-readable --summarize
```

## Security Considerations

### IAM Permissions
The infrastructure creates the following IAM roles:
- **ApplicationDiscoveryServiceRole**: For continuous data export
- **DiscoveryLambdaRole**: For automated reporting functions
- **AthenaExecutionRole**: For query execution

### Data Encryption
- S3 bucket encryption is enabled by default
- Data in transit is encrypted using TLS
- Discovery agents use encrypted communication

### Network Security
- Ensure proper network connectivity between on-premises and AWS
- Configure security groups and NACLs appropriately
- Use VPC endpoints for enhanced security

## Troubleshooting

### Common Issues

1. **Agent Installation Failures**
   ```bash
   # Check agent logs
   sudo tail -f /var/log/aws-discovery-agent.log
   
   # Verify network connectivity
   curl -I https://arsenal-discovery.us-west-2.amazonaws.com
   ```

2. **Data Collection Not Starting**
   ```bash
   # Verify agent registration
   aws discovery describe-agents --region ${AWS_REGION}
   
   # Check IAM permissions
   aws sts get-caller-identity
   ```

3. **S3 Export Issues**
   ```bash
   # Check export task status
   aws discovery describe-export-tasks --region ${AWS_REGION}
   
   # Verify S3 bucket permissions
   aws s3api get-bucket-policy --bucket your-discovery-bucket
   ```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name application-discovery-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name application-discovery-stack
```

### Using CDK
```bash
# Destroy the infrastructure
cd cdk-typescript/  # or cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup Steps
After running the automated cleanup, ensure these items are removed:

1. **Stop Discovery Agents**
   ```bash
   # Stop agents on each server
   sudo /opt/aws/discovery/bin/aws-discovery-daemon --stop
   
   # Uninstall agents
   sudo /opt/aws/discovery/bin/uninstall
   ```

2. **Remove Agentless Collector**
   - Delete the OVA from your VMware environment
   - Remove collector from vCenter inventory

3. **Clear Migration Hub Data**
   ```bash
   # Remove application associations
   aws discovery list-applications --region ${AWS_REGION}
   # Delete applications as needed
   ```

## Customization

### Environment Variables
The infrastructure supports customization through these variables:

- `MigrationHubHomeRegion`: AWS region for Migration Hub (default: us-west-2)
- `DiscoveryBucketName`: S3 bucket name for data export
- `ReportingSchedule`: CloudWatch Events schedule for automated reports
- `DataRetentionDays`: S3 object retention period
- `AthenaResultsLocation`: S3 path for Athena query results

### Terraform Variables
```bash
# Create terraform.tfvars file
cat > terraform/terraform.tfvars << 'EOF'
migration_hub_home_region = "us-west-2"
discovery_bucket_name = "my-discovery-bucket"
reporting_schedule = "rate(7 days)"
data_retention_days = 90
EOF
```

### CloudFormation Parameters
```bash
# Use parameter overrides
aws cloudformation create-stack \
    --stack-name application-discovery-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=MigrationHubHomeRegion,ParameterValue=us-east-1 \
                 ParameterKey=DataRetentionDays,ParameterValue=30 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
```

## Advanced Features

### Automated Reporting
The infrastructure includes automated weekly reporting:
- CloudWatch Events trigger Lambda functions
- Reports are generated and stored in S3
- Email notifications via SNS (optional)

### Data Analysis
Pre-configured Athena tables for:
- Server inventory and configurations
- Performance metrics analysis
- Network dependency mapping
- Application grouping insights

### Integration Options
- **AWS Migration Hub**: Centralized migration tracking
- **AWS Server Migration Service**: Automated server migrations
- **AWS Database Migration Service**: Database migration workflows
- **Amazon QuickSight**: Business intelligence dashboards

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../application-discovery-assessment-aws-application-discovery-service.md)
- [AWS Application Discovery Service Documentation](https://docs.aws.amazon.com/application-discovery/latest/userguide/)
- [AWS Migration Hub Documentation](https://docs.aws.amazon.com/migrationhub/)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/discovery/)

## Additional Resources

- [AWS Application Discovery Service Best Practices](https://docs.aws.amazon.com/application-discovery/latest/userguide/discovery-best-practices.html)
- [Migration Hub Integration Guide](https://docs.aws.amazon.com/migrationhub/latest/ug/whatishub.html)
- [Discovery Agent Deployment Guide](https://docs.aws.amazon.com/application-discovery/latest/userguide/discovery-agent.html)
- [Agentless Collector Setup](https://docs.aws.amazon.com/application-discovery/latest/userguide/agentless-collector.html)