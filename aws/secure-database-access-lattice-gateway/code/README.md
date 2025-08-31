# Infrastructure as Code for Secure Database Access with VPC Lattice Resource Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Database Access with VPC Lattice Resource Gateway".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with administrative access
- Two AWS accounts (database owner and consumer)
- Appropriate IAM permissions for:
  - VPC Lattice operations
  - RDS instance creation and management
  - IAM policy management
  - AWS RAM resource sharing
  - EC2 security group management
- Basic understanding of VPC networking and cross-account resource sharing
- Estimated cost: $15-25 for testing duration

## Architecture Overview

This solution implements:
- RDS MySQL database in private subnet with encryption
- VPC Lattice Resource Gateway for secure database access
- Service Network for cross-account connectivity
- Resource Configuration for database endpoint abstraction
- AWS RAM sharing for cross-account resource access
- IAM policies for fine-grained access control

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name secure-database-lattice-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ConsumerAccountId,ParameterValue=123456789012 \
               ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxxx \
               ParameterKey=SubnetId1,ParameterValue=subnet-xxxxxxxxx \
               ParameterKey=SubnetId2,ParameterValue=subnet-yyyyyyyyy \
    --capabilities CAPABILITY_IAM

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name secure-database-lattice-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name secure-database-lattice-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment context
npx cdk context --set consumerAccountId=123456789012
npx cdk context --set vpcId=vpc-xxxxxxxxx
npx cdk context --set subnetId1=subnet-xxxxxxxxx
npx cdk context --set subnetId2=subnet-yyyyyyyyy

# Deploy the stack
npx cdk deploy --require-approval never

# View outputs
npx cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export CONSUMER_ACCOUNT_ID=123456789012
export VPC_ID=vpc-xxxxxxxxx
export SUBNET_ID_1=subnet-xxxxxxxxx
export SUBNET_ID_2=subnet-yyyyyyyyy

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
consumer_account_id = "123456789012"
vpc_id             = "vpc-xxxxxxxxx"
subnet_id_1        = "subnet-xxxxxxxxx"
subnet_id_2        = "subnet-yyyyyyyyy"
aws_region         = "us-east-1"
db_master_password = "SecurePassword123!"
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
export CONSUMER_ACCOUNT_ID=123456789012
export VPC_ID=vpc-xxxxxxxxx
export SUBNET_ID_1=subnet-xxxxxxxxx
export SUBNET_ID_2=subnet-yyyyyyyyy

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Configuration

### Consumer Account Setup

After deploying the infrastructure, the consumer account must:

1. **Accept RAM Invitation**:
   ```bash
   # Switch to consumer account credentials
   aws configure set profile consumer_account
   
   # List pending invitations
   aws ram get-resource-share-invitations \
       --query 'resourceShareInvitations[?status==`PENDING`]'
   
   # Accept invitation
   aws ram accept-resource-share-invitation \
       --resource-share-invitation-arn <invitation-arn>
   ```

2. **Associate Consumer VPC**:
   ```bash
   # Associate consumer VPC with shared service network
   aws vpc-lattice create-service-network-vpc-association \
       --service-network-identifier <service-network-arn> \
       --vpc-identifier <consumer-vpc-id>
   ```

### Database Access Testing

```bash
# Get VPC Lattice DNS endpoint from outputs
LATTICE_DNS_NAME="<lattice-dns-from-outputs>"

# Test database connectivity
mysql -h ${LATTICE_DNS_NAME} -P 3306 -u admin -p
```

## Configuration Parameters

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ConsumerAccountId | AWS Account ID for database consumer | - | Yes |
| VpcId | VPC ID for resource deployment | - | Yes |
| SubnetId1 | First subnet ID for multi-AZ deployment | - | Yes |
| SubnetId2 | Second subnet ID for multi-AZ deployment | - | Yes |
| DbMasterPassword | Master password for RDS instance | SecurePassword123! | No |
| DbInstanceClass | RDS instance class | db.t3.micro | No |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| consumer_account_id | AWS Account ID for database consumer | string | - |
| vpc_id | VPC ID for resource deployment | string | - |
| subnet_id_1 | First subnet ID for multi-AZ deployment | string | - |
| subnet_id_2 | Second subnet ID for multi-AZ deployment | string | - |
| aws_region | AWS region for deployment | string | us-east-1 |
| db_master_password | Master password for RDS instance | string | SecurePassword123! |
| db_instance_class | RDS instance class | string | db.t3.micro |

### CDK Context/Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| CONSUMER_ACCOUNT_ID | AWS Account ID for database consumer | - |
| VPC_ID | VPC ID for resource deployment | - |
| SUBNET_ID_1 | First subnet ID for multi-AZ deployment | - |
| SUBNET_ID_2 | Second subnet ID for multi-AZ deployment | - |
| DB_MASTER_PASSWORD | Master password for RDS instance | SecurePassword123! |

## Outputs

All implementations provide these key outputs:

- **RdsEndpoint**: RDS database endpoint URL
- **ServiceNetworkArn**: VPC Lattice Service Network ARN
- **ResourceGatewayId**: Resource Gateway identifier
- **ResourceConfigurationArn**: Resource Configuration ARN
- **ResourceShareArn**: AWS RAM resource share ARN
- **LatticeDnsName**: VPC Lattice DNS name for database access

## Security Considerations

This implementation includes:

- **Encryption**: RDS instance with encryption at rest enabled
- **Network Isolation**: Database deployed in private subnets only
- **Access Control**: IAM policies restricting cross-account access
- **Security Groups**: Least privilege network access rules
- **Audit Trail**: CloudTrail logging for all API calls
- **Resource Sharing**: Controlled sharing via AWS RAM

## Monitoring and Observability

Enable monitoring with:

- CloudWatch metrics for RDS and VPC Lattice
- VPC Flow Logs for network traffic analysis
- CloudTrail for API access auditing
- AWS Config for compliance monitoring

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name secure-database-lattice-stack

# Wait for deletion completion
aws cloudformation wait stack-delete-complete \
    --stack-name secure-database-lattice-stack
```

### Using CDK

```bash
# Destroy the stack
cdk destroy --force

# Clean up CDK context
cdk context --clear
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Clean up state files
rm -f terraform.tfstate*
rm -f terraform.tfvars
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

1. **RAM Invitation Not Received**:
   - Verify consumer account ID is correct
   - Check AWS RAM console for pending invitations
   - Ensure external principals are allowed in RAM share

2. **Database Connection Failures**:
   - Verify security group rules allow MySQL traffic
   - Check VPC Lattice service network associations
   - Confirm resource configuration is active

3. **Cross-Account Access Denied**:
   - Verify IAM policies are correctly applied
   - Check service network auth policy configuration
   - Ensure consumer account has accepted RAM invitation

### Debug Commands

```bash
# Check VPC Lattice resources
aws vpc-lattice list-service-networks
aws vpc-lattice list-resource-gateways
aws vpc-lattice list-resource-configurations

# Verify RAM shares
aws ram get-resource-shares --resource-owner SELF
aws ram get-resource-share-associations

# Check RDS status
aws rds describe-db-instances
aws rds describe-db-subnet-groups
```

## Cost Optimization

- Use smaller RDS instance classes for testing
- Enable RDS deletion protection for production
- Monitor VPC Lattice data processing charges
- Consider RDS Proxy for connection pooling in production

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS VPC Lattice documentation
3. Review AWS RAM sharing guides
4. Consult AWS RDS best practices

## Additional Resources

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [AWS Resource Access Manager User Guide](https://docs.aws.amazon.com/ram/latest/userguide/)
- [Amazon RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/)