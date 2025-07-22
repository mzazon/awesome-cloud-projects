# Infrastructure as Code for Database Connection Pooling with RDS Proxy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Connection Pooling with RDS Proxy".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - RDS (create instances, proxies, subnet groups)
  - EC2 (VPC, subnets, security groups)
  - IAM (create roles and policies)
  - Secrets Manager (create and manage secrets)
  - Lambda (create and configure functions)
- Basic understanding of VPC networking and database concepts
- Estimated cost: $25-50/month for RDS instance, $0.015/hour for RDS Proxy, minimal Lambda costs

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 16.x or later
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI: `pip install aws-cdk-lib`

#### Terraform
- Terraform 1.0 or later
- AWS provider permissions

## Architecture Overview

This implementation deploys:
- VPC with private subnets across two Availability Zones
- RDS MySQL instance in private subnets
- RDS Proxy for connection pooling
- Security groups for network isolation
- IAM roles for secure access
- Secrets Manager for credential storage
- Lambda function for testing connection pooling

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name rds-proxy-demo \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DBPassword,ParameterValue=MySecurePassword123!

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name rds-proxy-demo

# Get outputs
aws cloudformation describe-stacks \
    --stack-name rds-proxy-demo \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters dbPassword=MySecurePassword123!

# Get outputs
cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters dbPassword=MySecurePassword123!

# Get outputs
cdk ls --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="db_password=MySecurePassword123!"

# Deploy infrastructure
terraform apply -var="db_password=MySecurePassword123!"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Testing the Deployment

After deployment, test the RDS Proxy connection pooling:

```bash
# Get the Lambda function name from outputs
LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name rds-proxy-demo \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test connection through RDS Proxy
aws lambda invoke \
    --function-name $LAMBDA_FUNCTION_NAME \
    --payload '{}' \
    response.json

# View response
cat response.json

# Test multiple invocations to see connection pooling
for i in {1..5}; do
    echo "Test $i:"
    aws lambda invoke \
        --function-name $LAMBDA_FUNCTION_NAME \
        --payload '{}' \
        response_$i.json
    cat response_$i.json
    echo ""
done
```

## Monitoring and Metrics

Monitor RDS Proxy performance using CloudWatch:

```bash
# View proxy connection metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name rds-proxy-demo

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name rds-proxy-demo
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="db_password=MySecurePassword123!"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Key Configuration Options

#### Database Configuration
- **Instance Class**: Modify `db_instance_class` to change RDS instance size
- **Storage**: Adjust `allocated_storage` for database storage requirements
- **Engine Version**: Update `engine_version` for specific MySQL version

#### RDS Proxy Configuration
- **Connection Limits**: Tune `max_connections_percent` and `max_idle_connections_percent`
- **Timeouts**: Adjust `idle_client_timeout` based on application patterns
- **Authentication**: Modify authentication method (SECRETS or IAM)

#### Network Configuration
- **CIDR Blocks**: Update VPC and subnet CIDR ranges
- **Availability Zones**: Modify AZ selection for regional requirements
- **Security Groups**: Adjust ingress/egress rules for security requirements

### Variable Reference

#### CloudFormation Parameters
- `DBPassword`: Master password for RDS instance
- `DBInstanceClass`: RDS instance class (default: db.t3.micro)
- `VpcCidr`: VPC CIDR block (default: 10.0.0.0/16)

#### CDK Context Variables
- `dbPassword`: Database master password
- `instanceClass`: RDS instance class
- `vpcCidr`: VPC CIDR block

#### Terraform Variables
- `db_password`: Database master password
- `db_instance_class`: RDS instance class
- `vpc_cidr`: VPC CIDR block
- `region`: AWS region for deployment

## Security Considerations

### Implemented Security Features
- **Network Isolation**: RDS instance in private subnets
- **Security Groups**: Least privilege network access
- **Encryption**: RDS encryption at rest enabled
- **Secrets Management**: Database credentials in Secrets Manager
- **IAM Roles**: Least privilege access principles

### Additional Security Recommendations
- Enable VPC Flow Logs for network monitoring
- Configure AWS Config for compliance monitoring
- Set up CloudTrail for API audit logging
- Implement AWS GuardDuty for threat detection
- Regular security assessments and penetration testing

## Performance Tuning

### RDS Proxy Optimization
- Monitor connection pool utilization metrics
- Adjust `max_connections_percent` based on application load
- Tune `idle_client_timeout` for your traffic patterns
- Enable debug logging for troubleshooting

### Database Performance
- Monitor RDS Performance Insights
- Configure appropriate parameter groups
- Consider read replicas for read-heavy workloads
- Implement proper indexing strategies

## Troubleshooting

### Common Issues

#### Connection Timeouts
- Verify security group configurations
- Check VPC routing and NAT gateway setup
- Validate IAM permissions for Lambda VPC access

#### Authentication Failures
- Verify Secrets Manager permissions
- Check secret format and content
- Validate IAM role trust relationships

#### High Connection Usage
- Monitor proxy connection metrics
- Adjust connection pool settings
- Implement connection retry logic in applications

### Debug Commands

```bash
# Check RDS instance status
aws rds describe-db-instances --db-instance-identifier <instance-id>

# Check proxy status
aws rds describe-db-proxies --db-proxy-name <proxy-name>

# Validate security groups
aws ec2 describe-security-groups --group-ids <security-group-id>

# Check secret content
aws secretsmanager get-secret-value --secret-id <secret-name>
```

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS RDS Proxy documentation: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html
3. Review AWS VPC networking guide: https://docs.aws.amazon.com/vpc/latest/userguide/
4. Consult AWS Lambda VPC configuration: https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html

## Additional Resources

- [AWS RDS Proxy Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-connections.html)
- [Database Connection Pooling Patterns](https://aws.amazon.com/builders-library/amazon-s3-design-patterns-and-best-practices/)
- [Serverless Database Access Patterns](https://aws.amazon.com/lambda/serverless-database-access-patterns/)
- [VPC Security Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)