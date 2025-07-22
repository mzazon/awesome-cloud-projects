# Infrastructure as Code for Network Micro-Segmentation with NACLs and Advanced Security Groups

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Securing Networks with Micro-Segmentation using NACLs and Security Groupsexisting_folder_name".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for VPC, EC2, RDS, CloudWatch, and IAM operations
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform v1.0+ installed
- Understanding of network security principles and VPC architecture

## Architecture Overview

This infrastructure implements a comprehensive network micro-segmentation strategy with:

- **6 Security Zones**: DMZ, Web Tier, Application Tier, Database Tier, Management, and Monitoring
- **Custom NACLs**: Subnet-level traffic filtering with explicit allow/deny rules
- **Advanced Security Groups**: Instance-level controls with source group references
- **VPC Flow Logs**: Comprehensive network traffic monitoring
- **CloudWatch Integration**: Real-time alerting and analytics
- **Zero-Trust Networking**: Every connection explicitly authorized

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name network-microsegmentation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=VpcCidr,ParameterValue=10.0.0.0/16

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name network-microsegmentation-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build

# Deploy with custom parameters
cdk deploy NetworkMicroSegmentationStack \
    --parameters vpcCidr=10.0.0.0/16 \
    --require-approval never
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy the stack
cdk deploy NetworkMicroSegmentationStack \
    --parameters vpcCidr=10.0.0.0/16 \
    --require-approval never
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -var="vpc_cidr=10.0.0.0/16"

# Apply the configuration
terraform apply -var="vpc_cidr=10.0.0.0/16" -auto-approve
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration options
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|---------------|-----|-----------|
| VPC CIDR | CIDR block for the VPC | 10.0.0.0/16 | `VpcCidr` | `vpcCidr` | `vpc_cidr` |
| Environment | Environment name | production | `Environment` | `environment` | `environment` |
| Enable Flow Logs | Enable VPC Flow Logs | true | `EnableFlowLogs` | `enableFlowLogs` | `enable_flow_logs` |
| Key Pair Name | EC2 Key Pair name | microseg-key | `KeyPairName` | `keyPairName` | `key_pair_name` |
| Monitoring Enabled | Enable CloudWatch monitoring | true | `MonitoringEnabled` | `monitoringEnabled` | `monitoring_enabled` |

### Security Zone Configuration

Each implementation creates the following network segments:

- **DMZ Zone (10.0.1.0/24)**: Internet-facing Application Load Balancer
- **Web Tier (10.0.2.0/24)**: Web servers accessible from DMZ only
- **App Tier (10.0.3.0/24)**: Application servers accessible from Web Tier only
- **Database Tier (10.0.4.0/24)**: Database servers accessible from App Tier only
- **Management (10.0.5.0/24)**: Administrative access (SSH, monitoring)
- **Monitoring (10.0.6.0/24)**: CloudWatch agents and logging infrastructure

## Security Features

### Network Access Control Lists (NACLs)

- **Stateless filtering** at subnet level
- **Explicit allow/deny rules** for each security zone
- **Rule precedence** based on numerical order
- **Defense in depth** with multiple security layers

### Advanced Security Groups

- **Stateful filtering** at instance level
- **Source group references** for dynamic scaling
- **Least privilege access** principles
- **Automated rule management** based on group membership

### Monitoring and Alerting

- **VPC Flow Logs** capture all network traffic metadata
- **CloudWatch integration** for real-time monitoring
- **Automated alerting** on suspicious traffic patterns
- **Security event correlation** across all network segments

## Validation and Testing

### Post-Deployment Verification

```bash
# Verify VPC and subnets
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=microseg-vpc-*"

# Check NACL associations
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=vpc-xxxxxxxx"

# Validate security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=vpc-xxxxxxxx"

# Check Flow Logs status
aws ec2 describe-flow-logs --filters "Name=resource-id,Values=vpc-xxxxxxxx"
```

### Security Testing

```bash
# Test NACL rules (requires instances in each tier)
# This should be blocked by NACLs
aws ec2 describe-instances --filters "Name=subnet-id,Values=subnet-xxxxxxxx"

# Verify security group rules
aws ec2 describe-security-group-rules --group-ids sg-xxxxxxxx
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name network-microsegmentation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name network-microsegmentation-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy NetworkMicroSegmentationStack --force
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="vpc_cidr=10.0.0.0/16" -auto-approve

# Clean up state files
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Adding New Security Zones

1. **Update subnet configuration** in your chosen IaC tool
2. **Create new NACL** with appropriate rules
3. **Add security group** with zone-specific rules
4. **Update monitoring** to include new zone
5. **Test connectivity** between zones

### Modifying Security Rules

1. **Review current rules** using AWS CLI or console
2. **Update IaC templates** with new rule configurations
3. **Validate rule precedence** and dependencies
4. **Test changes** in non-production environment first
5. **Deploy incrementally** to avoid connectivity issues

### Scaling Considerations

- **Multi-AZ deployment**: Modify templates to span multiple availability zones
- **Additional subnets**: Add more granular network segments as needed
- **Cross-region**: Extend to multiple regions with VPC peering
- **Hybrid connectivity**: Integrate with on-premises networks via VPN/Direct Connect

## Cost Considerations

### Estimated Monthly Costs

- **VPC and subnets**: No additional cost
- **NACLs**: No additional cost
- **Security Groups**: No additional cost
- **VPC Flow Logs**: ~$0.50 per GB of log data
- **CloudWatch Logs**: ~$0.50 per GB ingested
- **CloudWatch Metrics**: ~$0.30 per metric per month

### Cost Optimization

- **Filter Flow Logs**: Reduce logging to accepted traffic only
- **Log retention**: Set appropriate retention periods
- **Metric filters**: Use specific filters to reduce metric costs
- **Reserved capacity**: Consider reserved capacity for predictable workloads

## Troubleshooting

### Common Issues

1. **NACL Rule Conflicts**
   - Check rule numbering and precedence
   - Verify protocol and port configurations
   - Ensure ephemeral port ranges are allowed

2. **Security Group Dependencies**
   - Verify source group references exist
   - Check for circular dependencies
   - Ensure proper rule order during creation

3. **VPC Flow Logs Issues**
   - Verify IAM role permissions
   - Check CloudWatch log group existence
   - Validate resource associations

### Debug Commands

```bash
# Check NACL effective rules
aws ec2 describe-network-acls --network-acl-ids acl-xxxxxxxx

# Verify security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxxxxx --output table

# Monitor Flow Logs
aws logs describe-log-streams \
    --log-group-name /aws/vpc/microsegmentation/flowlogs

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/VPC \
    --metric-name PacketsDropped \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

## Security Best Practices

### Network Security

- **Implement least privilege**: Grant minimum required access
- **Regular rule audits**: Review and update rules periodically
- **Monitor traffic patterns**: Analyze Flow Logs for anomalies
- **Automated response**: Set up automated incident response

### Operational Security

- **Change management**: Use version control for IaC changes
- **Testing procedures**: Test all changes in non-production first
- **Documentation**: Maintain current network diagrams and rules
- **Training**: Ensure team understands micro-segmentation concepts

## Support and Documentation

### AWS Documentation

- [VPC Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [Network ACLs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html)
- [VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [CloudWatch Monitoring](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)

### Further Reading

- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [Network Segmentation Strategies](https://aws.amazon.com/blogs/security/)
- [Zero Trust Architecture](https://aws.amazon.com/blogs/publicsector/how-to-think-about-zero-trust-architectures-on-aws/)

For issues with this infrastructure code, refer to the original recipe documentation or contact your cloud architecture team.