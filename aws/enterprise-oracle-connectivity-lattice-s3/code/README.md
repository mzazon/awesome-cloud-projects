# Infrastructure as Code for Enterprise Oracle Database Connectivity with VPC Lattice and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Oracle Database Connectivity with VPC Lattice and S3".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Oracle Database@AWS administration
  - VPC Lattice service network management
  - Amazon S3 bucket creation and management
  - Amazon Redshift cluster administration
  - IAM role and policy management
  - CloudWatch monitoring configuration

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Ability to create IAM resources (CAPABILITY_IAM)

#### CDK TypeScript
- Node.js 16.x or later
- AWS CDK CLI v2.x
- TypeScript compiler

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI v2.x

#### Terraform
- Terraform v1.0 or later
- AWS provider v5.0 or later

### Cost Considerations
- Estimated cost: $50-200/month for testing resources
- Oracle Database@AWS charges apply based on usage
- Amazon Redshift cluster costs (can be paused when not in use)
- S3 storage costs with lifecycle policies for optimization
- VPC Lattice charges based on data processing

> **Note**: Oracle Database@AWS is available in select AWS regions. Verify regional availability before deployment.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name oracle-enterprise-connectivity \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=OdbNetworkId,ParameterValue=your-odb-network-id \
        ParameterKey=RedshiftMasterPassword,ParameterValue=OracleAnalytics123! \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name oracle-enterprise-connectivity

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name oracle-enterprise-connectivity \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set required environment variables
export ODB_NETWORK_ID=your-odb-network-id
export REDSHIFT_MASTER_PASSWORD=OracleAnalytics123!

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set required environment variables
export ODB_NETWORK_ID=your-odb-network-id
export REDSHIFT_MASTER_PASSWORD=OracleAnalytics123!

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
odb_network_id = "your-odb-network-id"
redshift_master_password = "OracleAnalytics123!"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export ODB_NETWORK_ID=your-odb-network-id
export REDSHIFT_MASTER_PASSWORD=OracleAnalytics123!
export AWS_REGION=us-east-1

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/validate.sh
```

## Configuration Parameters

### Required Parameters
- **ODB Network ID**: Existing Oracle Database@AWS network identifier
- **Redshift Master Password**: Password for Redshift cluster master user (minimum 8 characters)
- **AWS Region**: Target AWS region for deployment

### Optional Parameters
- **Environment Name**: Environment identifier (default: "prod")
- **S3 Bucket Prefix**: Custom prefix for S3 bucket naming
- **Redshift Node Type**: Instance type for Redshift cluster (default: "dc2.large")
- **Enable Monitoring**: Whether to create CloudWatch dashboard (default: true)

## Deployment Architecture

The IaC implementations deploy the following resources:

### Core Infrastructure
- **Amazon S3 Bucket**: Encrypted storage for Oracle database backups with lifecycle policies
- **Amazon Redshift Cluster**: Single-node analytics cluster with encryption enabled
- **IAM Roles and Policies**: Least-privilege access for service integrations

### Networking and Security
- **VPC Lattice Integration**: Managed service network connectivity for Oracle Database@AWS
- **Resource Gateway Configuration**: Secure pathways to AWS services
- **S3 Access Policies**: Restricted access for Oracle database operations

### Monitoring and Operations
- **CloudWatch Log Groups**: Centralized logging for Oracle operations
- **CloudWatch Dashboard**: Real-time monitoring of integration metrics
- **CloudWatch Alarms**: Proactive alerting for system health

### Database Integration
- **Zero-ETL Configuration**: Automated data synchronization to Redshift
- **S3 Backup Integration**: Managed backup workflows to S3 storage

## Post-Deployment Configuration

After successful deployment, complete these manual steps:

### 1. Verify Oracle Database@AWS Integration
```bash
# Check S3 access status
aws odb get-odb-network \
    --odb-network-id $ODB_NETWORK_ID \
    --query 'S3Access.Status'

# Verify Zero-ETL access
aws odb get-odb-network \
    --odb-network-id $ODB_NETWORK_ID \
    --query 'ZeroEtlAccess.Status'
```

### 2. Test Connectivity
```bash
# List VPC Lattice service networks
aws vpc-lattice list-service-networks \
    --query 'Items[?contains(Name, `default-odb-network`)]'

# Verify S3 bucket accessibility
aws s3 ls s3://your-bucket-name
```

### 3. Configure Database Backup
```bash
# Test Oracle to S3 backup (from Oracle Database@AWS)
# This requires connecting to your Oracle instance
sqlplus admin/password@your-oracle-endpoint
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name oracle-enterprise-connectivity

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name oracle-enterprise-connectivity
```

### Using CDK
```bash
# From the appropriate CDK directory
cdk destroy --force

# Clean up CDK bootstrap resources (optional)
# aws cloudformation delete-stack --stack-name CDKToolkit
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
./scripts/validate-cleanup.sh
```

## Customization

### Environment-Specific Configuration

Each implementation supports environment-specific customization:

#### CloudFormation Parameters
Modify the `Parameters` section in `cloudformation.yaml` or provide custom parameter files:

```yaml
Parameters:
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
  
  RedshiftNodeType:
    Type: String
    Default: dc2.large
    AllowedValues: [dc2.large, dc2.8xlarge, ra3.xlplus]
```

#### CDK Context Variables
Use `cdk.json` to define environment-specific settings:

```json
{
  "context": {
    "environment": "prod",
    "enableMonitoring": true,
    "redshiftNodeType": "dc2.large"
  }
}
```

#### Terraform Variables
Define custom values in `terraform.tfvars`:

```hcl
environment = "prod"
enable_monitoring = true
redshift_node_type = "dc2.large"
s3_lifecycle_enabled = true
```

### Security Hardening

For production deployments, consider these security enhancements:

1. **Enable VPC Flow Logs** for network monitoring
2. **Configure AWS Config Rules** for compliance monitoring
3. **Implement AWS Security Hub** for centralized security findings
4. **Enable GuardDuty** for threat detection
5. **Use AWS KMS Customer Managed Keys** for encryption

### Performance Optimization

1. **Redshift Performance Tuning**:
   - Configure appropriate node types based on workload
   - Implement distribution keys for large tables
   - Set up automatic table optimization

2. **S3 Storage Optimization**:
   - Configure Intelligent Tiering for automated cost optimization
   - Implement multipart upload for large files
   - Use S3 Transfer Acceleration for global access

3. **Monitoring Enhancement**:
   - Set up custom CloudWatch metrics
   - Configure detailed monitoring for all services
   - Implement AWS X-Ray for distributed tracing

## Troubleshooting

### Common Issues

#### Oracle Database@AWS Connection Issues
```bash
# Check ODB network status
aws odb describe-odb-network --odb-network-id $ODB_NETWORK_ID

# Verify VPC Lattice service network
aws vpc-lattice list-service-networks
```

#### S3 Access Denied Errors
```bash
# Verify IAM policies
aws iam get-role-policy --role-name YourRoleName --policy-name YourPolicyName

# Check S3 bucket policies
aws s3api get-bucket-policy --bucket your-bucket-name
```

#### Redshift Connection Issues
```bash
# Check cluster status
aws redshift describe-clusters --cluster-identifier your-cluster-id

# Verify security groups and networking
aws redshift describe-cluster-security-groups
```

### Logs and Monitoring

Access deployment and runtime logs:

```bash
# CloudFormation events
aws cloudformation describe-stack-events --stack-name your-stack-name

# CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/oracle-database"

# VPC Lattice access logs
aws logs describe-log-groups --log-group-name-prefix "/aws/vpc-lattice"
```

## Support

### Documentation References
- [Oracle Database@AWS User Guide](https://docs.aws.amazon.com/odb/latest/UserGuide/)
- [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Amazon Redshift Management Guide](https://docs.aws.amazon.com/redshift/latest/mgmt/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Getting Help
1. Review the original recipe documentation for step-by-step guidance
2. Check AWS service documentation for specific configuration requirements
3. Consult provider tool documentation (CDK, Terraform, CloudFormation)
4. Use AWS Support for account-specific issues

### Contributing
To improve these IaC implementations:
1. Test deployments in multiple regions
2. Validate against AWS Well-Architected Framework
3. Submit improvements for security and performance optimization
4. Document any environment-specific requirements

---

**Note**: This infrastructure code implements the complete solution described in the Enterprise Oracle Database Connectivity recipe. Ensure you understand the cost implications and have proper AWS permissions before deployment.