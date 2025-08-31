# Infrastructure as Code for Cross-Account Database Sharing with VPC Lattice and RDS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Account Database Sharing with VPC Lattice and RDS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Two AWS accounts with administrative access (Account A for database owner, Account B for consumer)
- Appropriate IAM permissions for:
  - VPC Lattice (CreateServiceNetwork, CreateResourceGateway, CreateResourceConfiguration)
  - RDS (CreateDBInstance, CreateDBSubnetGroup)
  - IAM (CreateRole, AttachRolePolicy)
  - AWS RAM (CreateResourceShare)
  - EC2 (CreateVPC, CreateSubnet, CreateSecurityGroup)
  - CloudWatch (CreateLogGroup, PutDashboard)
- Understanding of cross-account resource sharing and VPC concepts
- Estimated cost: $15-25 per day for RDS db.t3.micro instance, VPC Lattice service network, and CloudWatch monitoring

> **Note**: Ensure Account B ID is available before deployment as it's required for cross-account sharing configuration.

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name cross-account-database-sharing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AccountBId,ParameterValue=123456789012 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name cross-account-database-sharing

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cross-account-database-sharing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set required environment variables
export ACCOUNT_B_ID=123456789012
export CDK_DEFAULT_REGION=us-east-1

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set required environment variables
export ACCOUNT_B_ID=123456789012
export CDK_DEFAULT_REGION=us-east-1

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

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
account_b_id = "123456789012"
aws_region = "us-east-1"
db_instance_class = "db.t3.micro"
db_allocated_storage = 20
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Set required environment variables
export AWS_ACCOUNT_B=123456789012
export AWS_REGION=us-east-1

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment results
./scripts/deploy.sh --status
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| AccountBId | AWS Account ID for database consumer | - | Yes |
| VPCCidr | CIDR block for the VPC | 10.0.0.0/16 | No |
| DBInstanceClass | RDS instance type | db.t3.micro | No |
| DBAllocatedStorage | RDS storage size in GB | 20 | No |
| DBMasterUsername | Database master username | admin | No |
| ExternalId | External ID for cross-account role | unique-external-id-12345 | No |

### CDK Context Variables

```json
{
  "account-b-id": "123456789012",
  "vpc-cidr": "10.0.0.0/16",
  "db-instance-class": "db.t3.micro",
  "db-allocated-storage": 20,
  "external-id": "unique-external-id-12345"
}
```

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| account_b_id | AWS Account ID for database consumer | string | - | Yes |
| aws_region | AWS region for deployment | string | us-east-1 | No |
| vpc_cidr | CIDR block for the VPC | string | 10.0.0.0/16 | No |
| db_instance_class | RDS instance type | string | db.t3.micro | No |
| db_allocated_storage | RDS storage size in GB | number | 20 | No |
| db_master_username | Database master username | string | admin | No |
| external_id | External ID for cross-account role | string | unique-external-id-12345 | No |
| resource_prefix | Prefix for resource names | string | cross-account-db | No |

## Architecture Components

The IaC implementations deploy the following components:

### Networking Infrastructure
- **VPC**: Isolated network environment with internet gateway
- **Subnets**: Multi-AZ subnets for RDS and VPC Lattice resource gateway
- **Security Groups**: Properly configured security groups for database and gateway access

### Database Infrastructure
- **RDS MySQL Instance**: Encrypted database with multi-AZ backup configuration
- **DB Subnet Group**: Database subnet group spanning multiple availability zones
- **Database Security**: Security group allowing access from VPC CIDR

### VPC Lattice Infrastructure
- **Resource Gateway**: Network entry point for VPC Lattice resource configurations
- **Service Network**: Centralized governance layer with IAM authentication
- **Resource Configuration**: Logical representation of the database endpoint
- **Resource Configuration Association**: Links database to service network

### Cross-Account Sharing
- **IAM Role**: Cross-account role with external ID for secure access
- **Authentication Policy**: Service network policy controlling access permissions
- **AWS RAM Share**: Resource sharing mechanism for cross-account access

### Monitoring and Observability
- **CloudWatch Log Group**: Centralized logging for VPC Lattice operations
- **CloudWatch Dashboard**: Real-time monitoring of database access metrics
- **Performance Metrics**: Request count, response time, and connection monitoring

## Validation and Testing

After deployment, verify the infrastructure using these commands:

### Verify Service Network Status
```bash
# Get service network ID from outputs
SERVICE_NETWORK_ID=$(aws cloudformation describe-stacks \
    --stack-name cross-account-database-sharing \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceNetworkId`].OutputValue' \
    --output text)

# Check service network status
aws vpc-lattice get-service-network \
    --service-network-identifier ${SERVICE_NETWORK_ID}
```

### Verify Resource Configuration
```bash
# Get resource configuration ID from outputs
RESOURCE_CONFIG_ID=$(aws cloudformation describe-stacks \
    --stack-name cross-account-database-sharing \
    --query 'Stacks[0].Outputs[?OutputKey==`ResourceConfigurationId`].OutputValue' \
    --output text)

# Check resource configuration status
aws vpc-lattice get-resource-configuration \
    --resource-configuration-identifier ${RESOURCE_CONFIG_ID}
```

### Test Database Connectivity
```bash
# Get database endpoint from outputs
DB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name cross-account-database-sharing \
    --query 'Stacks[0].Outputs[?OutputKey==`DatabaseEndpoint`].OutputValue' \
    --output text)

# Test database connection (requires MySQL client)
mysql -h ${DB_ENDPOINT} -u admin -p
```

### Verify AWS RAM Share
```bash
# Get resource share ARN from outputs
SHARE_ARN=$(aws cloudformation describe-stacks \
    --stack-name cross-account-database-sharing \
    --query 'Stacks[0].Outputs[?OutputKey==`ResourceShareArn`].OutputValue' \
    --output text)

# Check resource share status
aws ram get-resource-shares \
    --resource-share-arns ${SHARE_ARN}
```

## Account B Setup Instructions

After deploying the infrastructure in Account A, follow these steps in Account B:

### 1. Accept Resource Share
```bash
# List pending resource share invitations
aws ram get-resource-share-invitations \
    --resource-share-arns RESOURCE_SHARE_ARN_FROM_ACCOUNT_A

# Accept the resource share invitation
aws ram accept-resource-share-invitation \
    --resource-share-invitation-arn INVITATION_ARN
```

### 2. Create Consumer VPC and Associate with Service Network
```bash
# Create VPC in Account B
CONSUMER_VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.1.0.0/16 \
    --query 'Vpc.VpcId' --output text)

# Associate consumer VPC with shared service network
aws vpc-lattice create-service-network-vpc-association \
    --service-network-identifier SERVICE_NETWORK_ID_FROM_ACCOUNT_A \
    --vpc-identifier ${CONSUMER_VPC_ID}
```

### 3. Create Application Role
```bash
# Create IAM role for applications in Account B
aws iam create-role \
    --role-name DatabaseConsumerRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ec2.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

# Attach policy for assuming cross-account role
aws iam put-role-policy \
    --role-name DatabaseConsumerRole \
    --policy-name AssumeDbAccessRole \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "CROSS_ACCOUNT_ROLE_ARN_FROM_ACCOUNT_A",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "unique-external-id-12345"
                }
            }
        }]
    }'
```

## Cleanup

### Using CloudFormation
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name cross-account-database-sharing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cross-account-database-sharing
```

### Using CDK
```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

### Network Security
- RDS database is deployed in private subnets with restricted security group access
- VPC Lattice resource gateway uses dedicated subnet with controlled access
- Security groups implement least privilege access principles

### IAM Security
- Cross-account role uses external ID for additional security
- Service network authentication policy restricts access to specific principals
- IAM policies follow least privilege principles for VPC Lattice operations

### Data Security
- RDS database encryption is enabled at rest
- Backup retention is configured for data protection
- Database credentials should be stored in AWS Secrets Manager for production use

### Monitoring Security
- CloudWatch logging captures all VPC Lattice operations for audit trails
- CloudTrail integration provides comprehensive API call logging
- Security Hub integration available for centralized security monitoring

## Troubleshooting

### Common Issues

1. **Resource Share Not Visible in Account B**
   - Verify Account B ID is correct in deployment parameters
   - Check AWS RAM service is enabled in both accounts
   - Ensure proper cross-account trust policies

2. **Database Connection Failures**
   - Verify RDS security group allows traffic from VPC CIDR
   - Check database is in available state
   - Validate database credentials and endpoint

3. **VPC Lattice Resource Gateway Issues**
   - Ensure gateway subnet has /28 or larger CIDR block
   - Verify security group allows required traffic
   - Check resource gateway is in active state

4. **Service Network Authentication Failures**
   - Validate authentication policy allows required principals
   - Check IAM role trust relationships are correct
   - Verify external ID matches in role and policy

### Debugging Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice list-service-networks

# Review CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/vpc-lattice

# Check resource associations
aws vpc-lattice list-resource-configuration-associations \
    --service-network-identifier SERVICE_NETWORK_ID

# Validate IAM role assumability
aws sts assume-role \
    --role-arn CROSS_ACCOUNT_ROLE_ARN \
    --role-session-name test-session \
    --external-id unique-external-id-12345
```

## Cost Optimization

### Resource Sizing
- Use db.t3.micro for development/testing environments
- Consider Aurora Serverless v2 for variable workloads
- Right-size VPC Lattice service network based on traffic patterns

### Monitoring Costs
- Set up billing alerts for unexpected cost increases
- Use AWS Cost Explorer to track VPC Lattice and RDS costs
- Monitor CloudWatch logs retention to control logging costs

### Resource Cleanup
- Implement automated cleanup for development environments
- Use AWS Config to monitor resource compliance
- Set up lifecycle policies for log group retention

## Support and Documentation

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Amazon RDS User Guide](https://docs.aws.amazon.com/rds/latest/userguide/)
- [AWS Resource Access Manager User Guide](https://docs.aws.amazon.com/ram/latest/userguide/)
- [Cross-Account IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html)

For issues with this infrastructure code, refer to the original recipe documentation or submit issues to the repository maintainers.