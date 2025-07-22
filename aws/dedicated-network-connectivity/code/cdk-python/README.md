# AWS CDK Python - Hybrid Cloud Connectivity with Direct Connect

This AWS CDK Python application creates a comprehensive hybrid cloud connectivity solution using AWS Direct Connect, Transit Gateway, and multiple VPCs for enterprise-grade network architecture.

## Architecture Overview

The solution implements a hub-and-spoke architecture with the following components:

- **Multiple VPCs**: Production, Development, and Shared Services VPCs with non-overlapping CIDR blocks
- **Transit Gateway**: Centralized routing hub for inter-VPC and on-premises connectivity
- **Direct Connect Gateway**: Dedicated network connectivity to on-premises infrastructure
- **Route 53 Resolver**: DNS resolution between on-premises and AWS environments
- **CloudWatch Monitoring**: Comprehensive monitoring and alerting for network performance
- **VPC Flow Logs**: Security monitoring and compliance logging
- **Security Controls**: Network ACLs and security groups for defense-in-depth

## Prerequisites

- AWS CLI configured with appropriate permissions
- Python 3.8 or later
- Node.js 18.x or later (for CDK CLI)
- AWS CDK CLI installed globally (`npm install -g aws-cdk`)
- Direct Connect physical connection established (coordination with AWS or partner required)

## Installation

1. Clone the repository and navigate to the CDK Python directory:
```bash
cd aws/hybrid-cloud-connectivity-aws-direct-connect/code/cdk-python
```

2. Create and activate a Python virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Bootstrap your AWS account for CDK (first time only):
```bash
cdk bootstrap
```

## Configuration

The application uses the following default configuration (can be modified in `app.py`):

- **On-premises CIDR**: `10.0.0.0/8`
- **On-premises ASN**: `65000`
- **AWS ASN**: `64512`
- **VPC CIDRs**: 
  - Production: `10.1.0.0/16`
  - Development: `10.2.0.0/16`
  - Shared Services: `10.3.0.0/16`
- **VLAN IDs**: Private VIF (100), Transit VIF (200)

## Deployment

1. Review the planned changes:
```bash
cdk diff
```

2. Deploy the stack:
```bash
cdk deploy
```

3. Confirm deployment when prompted (or use `--require-approval never` to skip)

## Post-Deployment Configuration

After the CDK deployment completes, you'll need to configure the following manually:

### 1. Virtual Interface Configuration

Create a Transit Virtual Interface (VIF) in the AWS Console:
- Navigate to Direct Connect Console
- Select your Direct Connect connection
- Create a new Virtual Interface:
  - Type: Transit
  - VLAN: 200 (or as configured)
  - BGP ASN: 65000 (your on-premises ASN)
  - Direct Connect Gateway: Use the ID from CDK output

### 2. BGP Router Configuration

Configure BGP on your on-premises router using the template generated during deployment:

```bash
# Example BGP configuration (adjust for your router)
router bgp 65000
 bgp router-id 192.168.100.1
 neighbor 192.168.100.2 remote-as 64512
 neighbor 192.168.100.2 password <BGP-AUTH-KEY>
 neighbor 192.168.100.2 timers 10 30
 
 address-family ipv4
  network 10.0.0.0/8
  neighbor 192.168.100.2 activate
  neighbor 192.168.100.2 prefix-list ALLOWED-PREFIXES out
  neighbor 192.168.100.2 prefix-list AWS-PREFIXES in
 exit-address-family
```

### 3. DNS Configuration

Configure your on-premises DNS servers to forward queries for AWS domains to:
- Inbound Resolver Endpoint: `10.3.1.100`

## Monitoring and Troubleshooting

### CloudWatch Dashboard

Access the monitoring dashboard:
1. Navigate to CloudWatch Console
2. Select "Dashboards" from the left menu
3. Open the dashboard named `DirectConnect-{project-id}`

### Key Metrics to Monitor

- **Transit Gateway Bytes In/Out**: Monitor traffic volume
- **Packet Drop Count**: Detect network issues
- **BGP Session State**: Ensure connectivity is established
- **VPC Flow Logs**: Security and compliance monitoring

### Troubleshooting Common Issues

1. **BGP Session Not Established**:
   - Verify VLAN configuration matches on both sides
   - Check BGP ASN configuration
   - Ensure firewall rules allow BGP traffic (TCP 179)

2. **Routing Issues**:
   - Verify route propagation in Transit Gateway
   - Check on-premises route advertisements
   - Ensure VPC route tables are correctly configured

3. **DNS Resolution Problems**:
   - Verify Route 53 Resolver endpoint security groups
   - Check DNS forwarder configuration on-premises
   - Test DNS resolution using `nslookup` or `dig`

## Security Considerations

- **Encryption**: All traffic over Direct Connect is private but not encrypted by default
- **Network Segmentation**: VPCs are isolated by default with controlled routing
- **Access Control**: Security groups and NACLs provide layered security
- **Monitoring**: VPC Flow Logs capture all network traffic for analysis
- **Compliance**: Flow logs stored in CloudWatch for audit trails

## Cost Optimization

- **Right-sizing**: Monitor bandwidth utilization to optimize connection capacity
- **Data Transfer**: Direct Connect reduces data transfer costs for high-volume workloads
- **Regional Optimization**: Consider multiple regions for global applications
- **Reserved Capacity**: Use AWS Direct Connect dedicated connections for predictable workloads

## Cleanup

To remove all resources created by this stack:

```bash
cdk destroy
```

**Warning**: This will permanently delete all resources. Ensure you have backups of any important data.

## Stack Outputs

The deployed stack provides the following outputs:

- **VPC IDs**: Production, Development, and Shared Services VPC identifiers
- **Transit Gateway ID**: Central routing hub identifier
- **Direct Connect Gateway ID**: Dedicated connectivity gateway identifier
- **DNS Resolver Endpoints**: IP addresses for hybrid DNS resolution
- **Configuration Guidance**: BGP and VIF configuration instructions

## Support

For issues related to:
- **AWS CDK**: Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
- **Direct Connect**: See [AWS Direct Connect documentation](https://docs.aws.amazon.com/directconnect/)
- **Transit Gateway**: Reference [AWS Transit Gateway documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Version History

- **1.0.0**: Initial release with full hybrid connectivity features
  - Multiple VPC support
  - Transit Gateway integration
  - Direct Connect Gateway configuration
  - DNS resolution with Route 53 Resolver
  - Comprehensive monitoring and logging
  - Security controls and compliance features