# Infrastructure as Code for Zero Trust Network with VPC Endpoints

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero Trust Network with VPC Endpoints".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- IAM permissions for VPC, EC2, Lambda, IAM, Route53, CloudWatch, and ELB operations
- Two AWS accounts or separate VPCs for cross-account demonstration (optional)
- Basic understanding of VPC networking, security groups, and DNS
- Estimated cost: $50-100 per month for VPC endpoints and data processing charges

### Required IAM Permissions

Your AWS credentials must have permissions for:
- VPC and subnet management
- Security group configuration
- VPC endpoint creation and management
- PrivateLink service configuration
- Network Load Balancer operations
- Lambda function deployment
- IAM role creation and policy attachment
- Route53 private hosted zone management
- CloudWatch Logs operations
- VPC Flow Logs configuration

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name zero-trust-network-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name zero-trust-network-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name zero-trust-network-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
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
echo "Deployment completed. Check AWS Console for resource status."
```

## Architecture Overview

This infrastructure deploys a comprehensive zero trust network architecture including:

### Core Components

- **Consumer VPC**: Private network with zero internet access
- **Provider VPC**: Service hosting network for PrivateLink demonstration
- **Private Subnets**: Multi-AZ deployment for high availability
- **Security Groups**: Least privilege access controls

### VPC Endpoints

- **S3 Interface Endpoint**: Private access to Amazon S3
- **Lambda Interface Endpoint**: Private access to AWS Lambda
- **CloudWatch Logs Endpoint**: Private access to CloudWatch Logs
- **Custom Service Endpoint**: PrivateLink connection to provider service

### PrivateLink Configuration

- **Network Load Balancer**: High-performance load balancing
- **VPC Endpoint Service**: Cross-account service sharing
- **Private DNS Resolution**: Service discovery without internet exposure

### Monitoring and Security

- **VPC Flow Logs**: Comprehensive network traffic monitoring
- **Route Tables**: Zero internet access enforcement
- **CloudWatch Integration**: Centralized logging and monitoring

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Environment name (dev/staging/prod) | production | Yes |
| VpcCidr | CIDR block for consumer VPC | 10.0.0.0/16 | No |
| ProviderVpcCidr | CIDR block for provider VPC | 10.1.0.0/16 | No |
| EnableVpcFlowLogs | Enable VPC Flow Logs | true | No |
| CreateTestLambda | Create test Lambda function | true | No |

### CDK Context Variables

```json
{
  "environment": "production",
  "vpcCidr": "10.0.0.0/16",
  "providerVpcCidr": "10.1.0.0/16",
  "enableVpcFlowLogs": true,
  "createTestLambda": true
}
```

### Terraform Variables

```hcl
# terraform.tfvars
environment = "production"
vpc_cidr = "10.0.0.0/16"
provider_vpc_cidr = "10.1.0.0/16"
enable_vpc_flow_logs = true
create_test_lambda = true
aws_region = "us-west-2"
```

## Validation and Testing

After deployment, validate the zero trust architecture:

### 1. Check VPC Endpoints Status

```bash
# Using AWS CLI
aws ec2 describe-vpc-endpoints \
    --filters Name=vpc-id,Values=<VPC_ID> \
    --query 'VpcEndpoints[*].[VpcEndpointId,State,ServiceName]' \
    --output table

# Expected: All endpoints should show "available" state
```

### 2. Test Lambda Function (if deployed)

```bash
# Invoke test function
aws lambda invoke \
    --function-name <LAMBDA_FUNCTION_NAME> \
    --payload '{}' \
    response.json

# Check response
cat response.json
```

Expected response should show:
- S3 access: Working through VPC endpoint
- Internet access: Blocked (zero trust validation)
- VPC endpoint connectivity: Functional

### 3. Verify Network Isolation

```bash
# Check route tables for internet routes (should be none)
aws ec2 describe-route-tables \
    --filters Name=vpc-id,Values=<VPC_ID> \
    --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0`]'

# Expected: Empty result (no internet routes)
```

### 4. Test Private DNS Resolution

```bash
# Check VPC endpoint DNS entries
aws ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids <ENDPOINT_ID> \
    --query 'VpcEndpoints[0].DnsEntries[*].DnsName'
```

### 5. Monitor VPC Flow Logs

```bash
# Check flow logs are active
aws ec2 describe-flow-logs \
    --filters Name=resource-id,Values=<VPC_ID> \
    --query 'FlowLogs[*].[FlowLogId,FlowLogStatus,TrafficType]'

# View recent log entries
aws logs describe-log-streams \
    --log-group-name /aws/vpc/zero-trust-flowlogs \
    --order-by LastEventTime \
    --descending
```

## Troubleshooting

### Common Issues

1. **VPC Endpoints Not Working**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups \
       --group-ids <SECURITY_GROUP_ID> \
       --query 'SecurityGroups[0].IpPermissions'
   
   # Ensure port 443 is allowed from VPC CIDR
   ```

2. **Lambda Function Timeout**
   ```bash
   # Check CloudWatch logs
   aws logs filter-log-events \
       --log-group-name /aws/lambda/<FUNCTION_NAME> \
       --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **DNS Resolution Issues**
   ```bash
   # Verify private DNS is enabled
   aws ec2 describe-vpc-endpoints \
       --vpc-endpoint-ids <ENDPOINT_ID> \
       --query 'VpcEndpoints[0].PrivateDnsEnabled'
   ```

4. **PrivateLink Connection Failures**
   ```bash
   # Check endpoint service status
   aws ec2 describe-vpc-endpoint-service-configurations \
       --query 'ServiceConfigurations[*].[ServiceName,ServiceState]'
   
   # Verify connection permissions
   aws ec2 describe-vpc-endpoint-service-permissions \
       --service-id <SERVICE_ID>
   ```

### Cost Optimization

- VPC endpoints cost ~$7.20/month each plus data processing fees
- Consider using S3 Gateway endpoints instead of Interface endpoints for cost savings
- Monitor data transfer charges through VPC endpoints
- Use CloudWatch cost anomaly detection for unexpected charges

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name zero-trust-network-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name zero-trust-network-stack
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy --force

# Deactivate virtual environment (Python only)
deactivate  # If using Python CDK
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Remove state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run destroy script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

```bash
# Check for remaining VPC endpoints
aws ec2 describe-vpc-endpoints \
    --filters Name=tag:Environment,Values=<ENVIRONMENT> \
    --query 'VpcEndpoints[*].[VpcEndpointId,State]'

# Check for remaining VPCs
aws ec2 describe-vpcs \
    --filters Name=tag:Environment,Values=<ENVIRONMENT> \
    --query 'Vpcs[*].[VpcId,State]'

# Check for remaining security groups
aws ec2 describe-security-groups \
    --filters Name=tag:Environment,Values=<ENVIRONMENT> \
    --query 'SecurityGroups[*].[GroupId,GroupName]'
```

## Security Considerations

### Best Practices Implemented

- **Zero Internet Access**: No internet gateways or NAT devices in private subnets
- **Least Privilege**: Security groups with minimal required access
- **Encryption in Transit**: All VPC endpoint communication is encrypted
- **Private DNS**: Internal service discovery without external exposure
- **Network Monitoring**: Comprehensive VPC Flow Logs for audit trails
- **Access Controls**: PrivateLink service permissions and endpoint policies

### Additional Security Measures

1. **Enable GuardDuty** for threat detection
2. **Configure AWS Config** for compliance monitoring
3. **Set up CloudTrail** for API activity logging
4. **Implement AWS Systems Manager Session Manager** for secure instance access
5. **Use AWS Secrets Manager** for credential management

## Support and Documentation

### Related AWS Documentation

- [VPC Endpoints User Guide](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [AWS PrivateLink Guide](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
- [VPC Security Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [Zero Trust Architecture on AWS](https://aws.amazon.com/architecture/security-identity-compliance/zero-trust/)

### Community Resources

- [AWS Samples GitHub Repository](https://github.com/aws-samples/)
- [AWS Security Blog](https://aws.amazon.com/blogs/security/)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudWatch logs for error details
3. Consult the original recipe documentation
4. Refer to AWS documentation for specific services
5. Contact AWS Support for service-specific issues

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any configuration changes
4. Validate all IaC implementations work consistently