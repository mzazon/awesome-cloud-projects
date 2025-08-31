# Infrastructure as Code for TCP Resource Connectivity with VPC Lattice and CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "TCP Resource Connectivity with VPC Lattice and CloudWatch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2.0 or later installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice service management
  - RDS instance creation and management
  - CloudWatch dashboard and alarm management
  - IAM role creation and management
  - EC2 VPC and security group access
- Two VPCs in the same AWS region (one for application, one for database)
- Understanding of TCP networking and database connectivity concepts
- Estimated cost: $25-40/month for RDS db.t3.micro instance and VPC Lattice service charges

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name tcp-lattice-connectivity \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DatabasePassword,ParameterValue=MySecurePassword123! \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name tcp-lattice-connectivity

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name tcp-lattice-connectivity \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters DatabasePassword=MySecurePassword123!

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters DatabasePassword=MySecurePassword123!

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="database_password=MySecurePassword123!" \
    -var="aws_region=us-east-1"

# Apply configuration
terraform apply \
    -var="database_password=MySecurePassword123!" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export AWS_REGION=us-east-1
export DATABASE_PASSWORD=MySecurePassword123!

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
aws vpc-lattice list-service-networks
aws rds describe-db-instances
```

## Architecture Overview

This infrastructure deploys:

- **VPC Lattice Service Network**: Provides service mesh networking layer
- **RDS MySQL Instance**: Database server in private subnet (db.t3.micro)
- **VPC Lattice Service**: Database service endpoint for applications
- **TCP Target Group**: Routes traffic to RDS instance with health checks
- **CloudWatch Dashboard**: Monitors connection metrics and traffic volume
- **CloudWatch Alarms**: Alerts on connection errors and performance issues
- **IAM Roles**: Service-linked roles for VPC Lattice operations
- **Security Groups**: Network access controls for database connectivity

## Configuration Options

### CloudFormation Parameters

- `DatabasePassword`: Master password for RDS instance (required)
- `VPCId`: Target VPC ID (defaults to default VPC)
- `SubnetIds`: Comma-separated list of subnet IDs for RDS
- `DatabaseInstanceClass`: RDS instance type (default: db.t3.micro)
- `ResourceNameSuffix`: Unique suffix for resource names

### CDK Context Variables

```json
{
  "database-password": "MySecurePassword123!",
  "vpc-id": "vpc-12345678",
  "subnet-ids": ["subnet-12345678", "subnet-87654321"],
  "instance-class": "db.t3.micro"
}
```

### Terraform Variables

```hcl
# terraform.tfvars
database_password    = "MySecurePassword123!"
aws_region          = "us-east-1"
vpc_id              = "vpc-12345678"
subnet_ids          = ["subnet-12345678", "subnet-87654321"]
db_instance_class   = "db.t3.micro"
environment         = "dev"
```

## Validation & Testing

### Verify VPC Lattice Service

```bash
# List service networks
aws vpc-lattice list-service-networks

# Check service status
aws vpc-lattice get-service --service-identifier <service-id>

# Verify target health
aws vpc-lattice list-targets --target-group-identifier <target-group-id>
```

### Test Database Connectivity

```bash
# Get service endpoint from outputs
SERVICE_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name tcp-lattice-connectivity \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceEndpoint`].OutputValue' \
    --output text)

# Test TCP connectivity (requires EC2 instance or network access)
telnet ${SERVICE_ENDPOINT} 3306

# Alternative: Use netcat for connectivity testing
timeout 5 nc -zv ${SERVICE_ENDPOINT} 3306
```

### Monitor CloudWatch Metrics

```bash
# View VPC Lattice metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/VpcLattice \
    --metric-name NewConnectionCount \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name tcp-lattice-connectivity

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name tcp-lattice-connectivity
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="database_password=MySecurePassword123!" \
    -var="aws_region=us-east-1"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws vpc-lattice list-service-networks
aws rds describe-db-instances
```

## Troubleshooting

### Common Issues

1. **RDS Instance Creation Timeout**:
   - Verify subnet group has subnets in multiple AZs
   - Check security group allows VPC Lattice access
   - Ensure adequate RDS quota in region

2. **VPC Lattice Target Health Issues**:
   - Verify RDS instance is in "available" state
   - Check security group rules allow TCP port 3306
   - Confirm target group health check configuration

3. **Connection Failures**:
   - Verify VPC association with service network
   - Check IAM permissions for VPC Lattice
   - Confirm service listener configuration

4. **CloudWatch Metrics Missing**:
   - Allow 5-10 minutes for metrics to appear
   - Verify service network has active connections
   - Check CloudWatch service availability

### Debug Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice describe-service-network-service-association \
    --service-network-service-association-identifier <association-id>

# Verify RDS connectivity
aws rds describe-db-instances \
    --db-instance-identifier <instance-id> \
    --query 'DBInstances[0].Endpoint'

# List CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names VPCLattice-Database-Connection-Errors-*
```

## Security Considerations

- RDS instance is deployed in private subnets with no public access
- IAM roles follow least privilege principle
- VPC Lattice uses AWS_IAM authentication
- Security groups restrict access to necessary ports only
- Database password should be stored in AWS Secrets Manager for production
- Enable encryption at rest for RDS instance
- Consider using AWS Certificate Manager for TLS termination

## Cost Optimization

- RDS instance uses db.t3.micro for cost-effectiveness
- VPC Lattice charges based on service network hours and data processed
- CloudWatch dashboard and alarms included in basic monitoring
- Consider Reserved Instances for production RDS workloads
- Monitor CloudWatch costs for high-volume deployments

## Customization

### Scaling Considerations

- Upgrade RDS instance class for higher throughput requirements
- Implement RDS read replicas for read scaling
- Configure Multi-AZ deployment for high availability
- Add additional target groups for load distribution

### Security Enhancements

- Integrate with AWS Secrets Manager for password management
- Implement resource-based policies for fine-grained access control
- Enable VPC Flow Logs for network monitoring
- Add AWS Config rules for compliance monitoring

### Monitoring Improvements

- Create custom CloudWatch Insights queries for log analysis
- Implement AWS X-Ray for distributed tracing
- Add performance monitoring with Enhanced Monitoring
- Configure SNS notifications for critical alarms

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for VPC Lattice and RDS
3. Verify AWS CLI version compatibility
4. Consult AWS support for service-specific issues

## Additional Resources

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Amazon RDS User Guide](https://docs.aws.amazon.com/rds/)
- [AWS CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)
- [VPC Lattice Pricing](https://aws.amazon.com/vpc/lattice/pricing/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)