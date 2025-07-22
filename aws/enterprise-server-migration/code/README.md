# Infrastructure as Code for Enterprise Server Migration with Application Migration Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Server Migration with Application Migration Service".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2.13.0 or later installed and configured
- Appropriate IAM permissions for:
  - AWS Application Migration Service (MGN)
  - EC2 instance management
  - IAM role creation and management
  - VPC and security group configuration
- On-premises servers with supported operating systems (Windows Server 2008 R2+, Linux distributions)
- Network connectivity from source servers to AWS (443/TCP outbound)
- Estimated cost: $50-200/month per server during migration (depends on server size and replication duration)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the MGN infrastructure
aws cloudformation create-stack \
    --stack-name mgn-migration-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=Environment,ParameterValue=Production

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name mgn-migration-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Install dependencies and deploy
cd cdk-typescript/
npm install

# Configure deployment environment
cdk bootstrap

# Deploy the infrastructure
cdk deploy MGNMigrationStack

# View deployed resources
cdk ls
```

### Using CDK Python (AWS)

```bash
# Set up Python environment and deploy
cd cdk-python/
pip install -r requirements.txt

# Configure deployment environment
cdk bootstrap

# Deploy the infrastructure
cdk deploy MGNMigrationStack

# View stack outputs
cdk ls
```

### Using Terraform

```bash
# Initialize and deploy with Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View created resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Monitor deployment progress
aws mgn describe-source-servers --region us-east-1
```

## Post-Deployment Steps

After deploying the infrastructure, you'll need to:

1. **Install MGN Agents on Source Servers**:
   ```bash
   # Download and install MGN agent on each source server
   # For Linux servers:
   curl -o aws-replication-installer-init.py \
       https://aws-application-migration-service-us-east-1.s3.us-east-1.amazonaws.com/latest/linux/aws-replication-installer-init.py
   
   # Install with appropriate AWS credentials
   sudo python3 aws-replication-installer-init.py \
       --region us-east-1 \
       --aws-access-key-id YOUR_ACCESS_KEY \
       --aws-secret-access-key YOUR_SECRET_KEY \
       --no-prompt
   ```

2. **Monitor Replication Progress**:
   ```bash
   # Check replication status
   aws mgn describe-source-servers \
       --query 'items[*].{ServerID:sourceServerID,Status:dataReplicationInfo.dataReplicationState}' \
       --output table
   ```

3. **Configure Launch Templates**:
   ```bash
   # Set up launch configurations for your specific requirements
   aws mgn put-launch-configuration \
       --source-server-id YOUR_SERVER_ID \
       --launch-configuration file://launch-config.json
   ```

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export MGN_ENVIRONMENT=Production
export MGN_REPLICATION_INSTANCE_TYPE=t3.small
export MGN_ENABLE_ENCRYPTION=true
export MGN_STAGING_AREA_TAGS='{"Environment":"Migration","Purpose":"MGN-Staging"}'
```

### Terraform Variables

Customize your deployment by modifying `terraform/terraform.tfvars`:

```hcl
# Core configuration
aws_region = "us-east-1"
environment = "Production"

# MGN configuration
mgn_replication_instance_type = "t3.small"
mgn_enable_encryption = true
mgn_create_public_ip = false
mgn_bandwidth_throttling = 0

# Tagging
common_tags = {
  Environment = "Production"
  Project     = "ServerMigration"
  Team        = "CloudOps"
}
```

### CloudFormation Parameters

Key parameters for CloudFormation deployment:

- `Environment`: Deployment environment (Production, Staging, Development)
- `ReplicationInstanceType`: EC2 instance type for replication servers
- `EnableEncryption`: Enable EBS encryption for replicated data
- `CreatePublicIP`: Whether to create public IPs for replication servers
- `BandwidthThrottling`: Bandwidth throttling for replication (0 = unlimited)

## Migration Workflow

### Phase 1: Infrastructure Setup

1. Deploy the IaC to create MGN service infrastructure
2. Configure replication settings and launch templates
3. Set up IAM roles and security groups

### Phase 2: Server Registration

1. Install MGN agents on source servers
2. Monitor initial replication progress
3. Verify all servers reach continuous replication

### Phase 3: Testing

1. Launch test instances for validation
2. Perform application and performance testing
3. Validate network connectivity and functionality

### Phase 4: Production Cutover

1. Execute coordinated cutover during maintenance window
2. Monitor cutover progress and verify success
3. Perform post-migration validation

### Phase 5: Finalization

1. Finalize migration to stop replication
2. Clean up test resources
3. Document migration completion

## Wave-Based Migration

For large-scale migrations, organize servers into waves:

```bash
# Create migration wave
aws mgn create-wave \
    --name "Wave-1-WebServers" \
    --description "First wave: Web tier servers"

# Associate servers with wave
aws mgn associate-source-servers \
    --wave-id WAVE_ID \
    --source-server-ids SERVER_ID_1 SERVER_ID_2
```

## Monitoring and Troubleshooting

### Key Metrics to Monitor

- Replication progress and lag
- Network utilization during replication
- Test instance launch success rates
- Cutover completion times

### Common Issues and Solutions

1. **Replication Lag**: Check network bandwidth and increase replication server size
2. **Agent Installation Failures**: Verify AWS credentials and network connectivity
3. **Launch Failures**: Review launch templates and target subnet configuration
4. **Connectivity Issues**: Validate security groups and network ACLs

### Logging and Monitoring

```bash
# Check MGN service logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/mgn"

# Monitor replication metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/MGN \
    --metric-name ReplicationLag \
    --dimensions Name=SourceServerID,Value=YOUR_SERVER_ID \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 300 \
    --statistics Average
```

## Security Considerations

### IAM Permissions

The infrastructure creates IAM roles with minimal required permissions:

- MGN service role for replication operations
- EC2 roles for launched instances
- Lambda execution roles for automation (if applicable)

### Network Security

- Replication traffic uses encrypted connections
- Security groups restrict access to necessary ports only
- VPC endpoints available for enhanced security

### Data Encryption

- EBS volumes encrypted at rest
- Replication data encrypted in transit
- Staging area storage encrypted

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name mgn-migration-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name mgn-migration-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the infrastructure
cd cdk-typescript/  # or cdk-python/
cdk destroy MGNMigrationStack

# Confirm deletion
cdk ls
```

### Using Terraform

```bash
# Plan and execute destruction
cd terraform/
terraform plan -destroy
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Execute cleanup script
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Manual cleanup verification
aws mgn describe-source-servers
```

### Manual Cleanup Steps

If automated cleanup fails, manually remove:

1. **Disconnect Source Servers**:
   ```bash
   aws mgn disconnect-from-service --source-server-id YOUR_SERVER_ID
   ```

2. **Delete Replication Configuration Templates**:
   ```bash
   aws mgn delete-replication-configuration-template \
       --replication-configuration-template-id TEMPLATE_ID
   ```

3. **Remove IAM Roles**:
   ```bash
   aws iam detach-role-policy \
       --role-name MGNServiceRole \
       --policy-arn arn:aws:iam::aws:policy/AWSApplicationMigrationServiceRolePolicy
   
   aws iam delete-role --role-name MGNServiceRole
   ```

## Cost Optimization

### Replication Costs

- Use smaller instance types for replication servers during off-peak hours
- Implement lifecycle policies for staging area storage
- Monitor bandwidth usage to optimize replication timing

### Testing Costs

- Terminate test instances promptly after validation
- Use spot instances for non-critical testing scenarios
- Schedule testing during off-peak hours for cost savings

### Storage Costs

- Clean up staging area storage after migration completion
- Use GP3 volumes for optimal cost-performance balance
- Implement automated cleanup of old snapshots

## Best Practices

### Migration Planning

1. **Assess Dependencies**: Map application dependencies before migration
2. **Test Thoroughly**: Validate all functionality in test environment
3. **Plan Rollback**: Prepare rollback procedures for critical applications
4. **Communicate**: Coordinate with stakeholders for cutover windows

### Performance Optimization

1. **Right-size Instances**: Use appropriate instance types for workloads
2. **Optimize Network**: Ensure sufficient bandwidth for replication
3. **Monitor Progress**: Track replication and cutover metrics
4. **Automate Tasks**: Use scripts for repetitive operations

### Security Best Practices

1. **Least Privilege**: Use minimal IAM permissions
2. **Encrypt Data**: Enable encryption for all data at rest and in transit
3. **Network Segmentation**: Use security groups and NACLs appropriately
4. **Audit Access**: Monitor and log all migration activities

## Support and Documentation

### AWS Documentation

- [AWS Application Migration Service User Guide](https://docs.aws.amazon.com/mgn/latest/ug/)
- [MGN API Reference](https://docs.aws.amazon.com/mgn/latest/APIReference/)
- [Migration Best Practices](https://aws.amazon.com/cloud-migration/best-practices/)

### Community Resources

- [AWS Migration Hub](https://aws.amazon.com/migration-hub/)
- [AWS Migration Acceleration Program](https://aws.amazon.com/migration-acceleration-program/)
- [AWS re:Post Migration Questions](https://repost.aws/tags/TA4IvCeRw9SRuIsj1F6V_8-g/migration)

### Getting Help

For issues with this infrastructure code:

1. Check the AWS MGN service health dashboard
2. Review CloudTrail logs for API errors
3. Consult the original recipe documentation
4. Contact AWS Support for service-specific issues

## Changelog

- v1.0: Initial infrastructure code generation
- v1.1: Added wave-based migration support and enhanced monitoring

---

*This infrastructure code was generated based on the recipe "Enterprise Server Migration with Application Migration Service" and follows AWS best practices for production deployments.*