# Zero Trust Network Architecture CDK Python Application

This CDK Python application implements a complete zero trust network architecture using AWS VPC endpoints and PrivateLink services. The solution eliminates internet connectivity while providing secure, private access to AWS services and cross-account resources.

## Architecture Overview

The application creates:

- **Consumer VPC** (10.0.0.0/16) with isolated private subnets
- **Provider VPC** (10.1.0.0/16) for hosting PrivateLink services
- **VPC Endpoints** for AWS services (S3, Lambda, CloudWatch Logs)
- **PrivateLink Service** with Network Load Balancer
- **Security Groups** implementing least privilege access
- **VPC Flow Logs** for comprehensive network monitoring
- **Private DNS** resolution for service discovery
- **Test Lambda Function** for validation

## Prerequisites

1. **AWS CLI** v2 installed and configured
   ```bash
   aws configure
   ```

2. **Python 3.8+** installed on your system

3. **AWS CDK** installed globally
   ```bash
   npm install -g aws-cdk
   ```

4. **AWS Account** with appropriate IAM permissions for:
   - VPC and subnet management
   - VPC endpoints and PrivateLink services
   - Lambda functions and IAM roles
   - CloudWatch Logs and Route53
   - Network Load Balancers

5. **Estimated Monthly Cost**: $50-100 USD
   - VPC endpoints: ~$7.20/month per endpoint
   - Data processing charges: ~$0.01/GB
   - CloudWatch Logs storage and Network Load Balancer charges

## Quick Start

### 1. Set Up Python Environment

```bash
# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Upgrade pip
pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt
```

### 2. Bootstrap CDK (First Time Only)

```bash
# Bootstrap CDK for your account/region
cdk bootstrap

# Or specify account and region explicitly
cdk bootstrap aws://ACCOUNT-NUMBER/REGION
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with custom parameters
cdk deploy --context random_suffix=demo123
```

### 4. Validate the Deployment

After deployment, test the zero trust architecture:

```bash
# Get the test Lambda function name from stack outputs
export LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name ZeroTrustNetworkStack \
    --query 'Stacks[0].Outputs[?OutputKey==`TestLambdaFunction`].OutputValue' \
    --output text)

# Invoke the test function
aws lambda invoke \
    --function-name $LAMBDA_FUNCTION_NAME \
    --payload '{}' \
    response.json

# Check the results
cat response.json
```

Expected results:
- `s3_access`: `true` (AWS services accessible via VPC endpoints)
- `internet_access`: `false` (No internet connectivity - zero trust validated)
- `vpc_endpoint_working`: `true` (VPC endpoints functioning correctly)

## Configuration Options

### Context Parameters

Customize the deployment using CDK context parameters:

```bash
# Deploy with custom suffix
cdk deploy --context random_suffix=prod001

# Disable flow logs
cdk deploy --context enable_flow_logs=false

# Disable private DNS
cdk deploy --context enable_private_dns=false

# Disable test Lambda
cdk deploy --context enable_test_lambda=false
```

### Environment Variables

Set environment variables for deployment:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
cdk deploy
```

## Testing and Validation

### 1. VPC Endpoints Validation

```bash
# Check VPC endpoint status
aws ec2 describe-vpc-endpoints \
    --filters Name=vpc-id,Values=VPC_ID \
    --query 'VpcEndpoints[*].[VpcEndpointId,State,ServiceName]' \
    --output table
```

### 2. PrivateLink Service Validation

```bash
# Check endpoint service status
aws ec2 describe-vpc-endpoint-service-configurations \
    --query 'ServiceConfigurations[*].[ServiceName,ServiceState]' \
    --output table
```

### 3. Network Connectivity Testing

```bash
# View VPC Flow Logs
aws logs describe-log-streams \
    --log-group-name "/aws/vpc/zero-trust-flowlogs-SUFFIX" \
    --order-by LastEventTime \
    --descending
```

### 4. Private DNS Resolution

```bash
# Test DNS resolution
aws route53 list-resource-record-sets \
    --hosted-zone-id HOSTED_ZONE_ID \
    --query 'ResourceRecordSets[?Type==`CNAME`]'
```

## Customization

### Modifying VPC CIDR Blocks

Edit the `app.py` file to change network ranges:

```python
# Consumer VPC CIDR
ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16")

# Provider VPC CIDR  
ip_addresses=ec2.IpAddresses.cidr("10.1.0.0/16")
```

### Adding Additional VPC Endpoints

Add more AWS service endpoints in the `_create_vpc_endpoints()` method:

```python
# Example: Adding SQS endpoint
self.sqs_endpoint = ec2.InterfaceVpcEndpoint(
    self, "SQSVpcEndpoint",
    vpc=self.consumer_vpc,
    service=ec2.InterfaceVpcEndpointAwsService.SQS,
    subnets=ec2.SubnetSelection(subnets=self.private_subnets),
    security_groups=[self.endpoint_security_group],
    private_dns_enabled=True
)
```

### Customizing Security Groups

Modify security group rules in the `_create_security_groups()` method:

```python
# Example: Allow additional ports
self.endpoint_security_group.add_ingress_rule(
    peer=ec2.Peer.ipv4("10.0.0.0/16"),
    connection=ec2.Port.tcp(80),
    description="HTTP from VPC CIDR"
)
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
# Destroy all resources
cdk destroy

# Force destroy without confirmation
cdk destroy --force
```

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error**
   ```bash
   # Ensure CDK is bootstrapped for your account/region
   cdk bootstrap
   ```

2. **Permission Denied Errors**
   ```bash
   # Check IAM permissions for VPC and endpoint operations
   aws iam list-attached-user-policies --user-name YOUR_USERNAME
   ```

3. **VPC Endpoint Creation Failures**
   ```bash
   # Check service availability in your region
   aws ec2 describe-vpc-endpoint-services --service-names com.amazonaws.REGION.s3
   ```

4. **Lambda Function Timeout**
   ```bash
   # Check VPC endpoint connectivity and security groups
   aws ec2 describe-vpc-endpoints --filters Name=state,Values=available
   ```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Deploy with verbose output
cdk deploy --verbose

# Show detailed diff
cdk diff --verbose
```

## Security Considerations

### Network Security
- No internet gateways or NAT devices
- All traffic flows through VPC endpoints
- Security groups implement least privilege access
- VPC Flow Logs capture all network traffic

### Access Control
- IAM policies restrict endpoint usage to account principals
- Endpoint policies provide additional network-level controls
- PrivateLink services require explicit connection approval

### Monitoring
- VPC Flow Logs to CloudWatch for analysis
- CloudTrail integration for API call auditing
- Private DNS prevents external DNS queries

## Best Practices

1. **Resource Tagging**: All resources include consistent tags for cost allocation and management

2. **Least Privilege**: Security groups deny all traffic by default, only allowing required connections

3. **Multi-AZ Deployment**: VPC endpoints span multiple availability zones for high availability

4. **Monitoring**: Comprehensive logging and monitoring for security analysis

5. **Documentation**: Inline code comments explain configuration decisions

## Additional Resources

- [AWS VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [AWS PrivateLink Guide](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
- [Zero Trust Security Model](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/zero-trust-network-with-aws.html)
- [CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)

## License

This code is released under the MIT-0 License. See the LICENSE file for details.

## Support

For issues related to this CDK application:
1. Check the troubleshooting section above
2. Review AWS CDK documentation
3. Consult AWS VPC and PrivateLink documentation
4. Contact AWS Support for service-specific issues