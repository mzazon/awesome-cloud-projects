# AWS Direct Connect Hybrid Cloud Connectivity - CDK TypeScript

This CDK TypeScript application deploys infrastructure for hybrid cloud connectivity using AWS Direct Connect, Transit Gateway, and multiple VPCs.

## Architecture

The solution creates:

- **3 VPCs**: Production (10.1.0.0/16), Development (10.2.0.0/16), and Shared Services (10.3.0.0/16)
- **Transit Gateway**: Central hub for VPC connectivity with BGP ASN 64512
- **Direct Connect Gateway**: Bridge between Direct Connect and Transit Gateway
- **Route 53 Resolver Endpoints**: For hybrid DNS resolution
- **VPC Flow Logs**: For network traffic monitoring
- **CloudWatch Monitoring**: For connection health and performance metrics

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18 or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Direct Connect physical connection established
- Appropriate AWS permissions for creating networking resources

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

## Configuration

### CDK Context Values

You can customize the deployment by setting CDK context values:

```bash
# Set on-premises network configuration
cdk deploy -c onPremisesCidr=10.0.0.0/8 -c onPremisesAsn=65000

# Disable optional features
cdk deploy -c enableDnsResolution=false -c enableMonitoring=false

# Set project identifier
cdk deploy -c projectId=my-hybrid-project
```

### Environment Variables

Set these environment variables for deployment:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

## Post-Deployment Configuration

### 1. Create Virtual Interface

After deployment, you'll need to create a Transit Virtual Interface:

```bash
# Get the Direct Connect Gateway ID from stack outputs
DX_GATEWAY_ID=$(aws cloudformation describe-stacks \
    --stack-name HybridConnectivityStack \
    --query 'Stacks[0].Outputs[?OutputKey==`DirectConnectGatewayId`].OutputValue' \
    --output text)

# Create Transit VIF (replace <CONNECTION_ID> with your Direct Connect connection ID)
aws directconnect create-transit-virtual-interface \
    --connection-id <CONNECTION_ID> \
    --new-transit-virtual-interface \
        vlan=200,asn=65000,mtu=1500,directConnectGatewayId=$DX_GATEWAY_ID
```

### 2. Configure On-Premises BGP

Configure BGP on your on-premises router using the provided configuration template:

```bash
# View BGP configuration from stack outputs
aws cloudformation describe-stacks \
    --stack-name HybridConnectivityStack \
    --query 'Stacks[0].Outputs[?OutputKey==`BgpConfiguration`].OutputValue' \
    --output text
```

### 3. Configure DNS Forwarders

Set up DNS forwarders on your on-premises DNS servers:

```bash
# Get DNS resolver endpoint IPs
INBOUND_IP=$(aws cloudformation describe-stacks \
    --stack-name HybridConnectivityStack \
    --query 'Stacks[0].Outputs[?OutputKey==`InboundResolverEndpointIp`].OutputValue' \
    --output text)

echo "Configure DNS forwarder for *.amazonaws.com to $INBOUND_IP"
```

## Monitoring

The stack includes CloudWatch monitoring for:

- Transit Gateway traffic metrics
- VPC Flow Logs for security monitoring
- Custom alarms for high traffic conditions

Access the dashboard:
```bash
aws cloudwatch get-dashboard --dashboard-name DirectConnect-<PROJECT_ID>
```

## Testing Connectivity

### 1. Verify Transit Gateway Attachments

```bash
# Get Transit Gateway ID
TGW_ID=$(aws cloudformation describe-stacks \
    --stack-name HybridConnectivityStack \
    --query 'Stacks[0].Outputs[?OutputKey==`TransitGatewayId`].OutputValue' \
    --output text)

# Check attachments
aws ec2 describe-transit-gateway-attachments \
    --filters Name=transit-gateway-id,Values=$TGW_ID
```

### 2. Test DNS Resolution

```bash
# Test DNS resolution from EC2 instance in any VPC
nslookup your-onprem-server.corp.local
```

### 3. Test Network Connectivity

```bash
# Test connectivity from EC2 instance to on-premises
ping 10.0.1.100  # Replace with your on-premises IP
```

## Security Considerations

### Network Access Control

- VPC Flow Logs are enabled for all VPCs
- Security groups restrict DNS traffic to authorized sources
- Route tables isolate traffic between production and development

### DNS Security

- Resolver endpoints use dedicated security groups
- DNS traffic is isolated to specific subnets
- Query logging can be enabled for audit trails

## Cost Optimization

### Resource Costs

- Transit Gateway: ~$36/month + $0.02/GB processed
- Direct Connect Gateway: No additional charge
- VPC Flow Logs: ~$0.50/GB ingested
- Route 53 Resolver Endpoints: ~$0.125/hour per endpoint

### Optimization Tips

1. **Right-size NAT Gateways**: Consider using NAT instances for dev environments
2. **Monitor Data Transfer**: Use CloudWatch to track and optimize data transfer
3. **Cleanup Unused Resources**: Remove test VPCs and attachments when not needed

## Troubleshooting

### Common Issues

1. **BGP Session Not Established**:
   - Check Virtual Interface configuration
   - Verify BGP ASN and authentication key
   - Ensure proper routing on on-premises router

2. **DNS Resolution Failures**:
   - Verify security group rules for resolver endpoints
   - Check Route 53 resolver rule configurations
   - Validate DNS forwarder configuration

3. **Connectivity Issues**:
   - Review Transit Gateway route tables
   - Check VPC route table configurations
   - Verify security group and NACL rules

### Debugging Commands

```bash
# Check Direct Connect virtual interface status
aws directconnect describe-virtual-interfaces

# View Transit Gateway route table
aws ec2 describe-transit-gateway-route-tables

# Check VPC Flow Logs
aws logs describe-log-groups --log-group-name-prefix /aws/vpc/flowlogs
```

## Cleanup

To remove all resources:

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
```

**Warning**: This will delete all networking resources. Ensure you have proper backups and that no critical workloads depend on these resources.

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [AWS Direct Connect documentation](https://docs.aws.amazon.com/directconnect/)
3. Consult [AWS Transit Gateway documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)

## License

This code is licensed under the MIT-0 License. See the LICENSE file for details.