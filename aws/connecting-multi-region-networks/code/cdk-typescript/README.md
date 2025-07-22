# Multi-Region VPC Connectivity with Transit Gateway - CDK TypeScript

This CDK TypeScript application implements a complete multi-region networking architecture using AWS Transit Gateway with cross-region peering to enable secure communication between VPCs across regions.

## Architecture Overview

The solution creates:

- **Multiple VPCs** in primary (us-east-1) and secondary (us-west-2) regions with non-overlapping CIDR blocks
- **Transit Gateways** in each region serving as networking hubs
- **Cross-region peering** connections between Transit Gateways
- **Custom route tables** for granular traffic control
- **Security groups** configured for cross-region communication
- **CloudWatch monitoring** with dashboards and alarms
- **SNS alerts** for operational notifications

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for:
  - EC2 (VPC, Transit Gateway, Security Groups)
  - CloudWatch (Dashboards, Alarms, Logs)
  - SNS (Topics, Subscriptions)
  - Lambda (Functions for custom resources)
  - IAM (Roles and policies)

## Project Structure

```
cdk-typescript/
├── app.ts                                    # Main CDK application
├── lib/
│   ├── multi-region-vpc-connectivity-stack.ts  # Core networking infrastructure
│   ├── transit-gateway-peering-stack.ts        # Cross-region peering and routing
│   └── monitoring-stack.ts                     # CloudWatch monitoring and alerts
├── package.json                              # Dependencies and scripts
├── tsconfig.json                             # TypeScript configuration
├── cdk.json                                  # CDK configuration
└── README.md                                 # This file
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
# Required - AWS account and regions
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"

# Optional - Project customization
export PROJECT_NAME="multi-region-tgw"

# Optional - Alert notifications
export ALERT_EMAIL="your-email@example.com"
```

### Network Configuration

The application uses these CIDR blocks by default:

- **Primary Region VPC A**: 10.1.0.0/16
- **Primary Region VPC B**: 10.2.0.0/16
- **Secondary Region VPC A**: 10.3.0.0/16
- **Secondary Region VPC B**: 10.4.0.0/16

These can be modified in `app.ts` if needed for your environment.

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/multi-region-vpc-connectivity-transit-gateway/code/cdk-typescript/
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK in both regions** (if not already done):
   ```bash
   cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$PRIMARY_REGION
   cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$SECONDARY_REGION
   ```

## Deployment

### Quick Deploy (All Stacks)

```bash
# Deploy all stacks
npm run deploy

# Or using CDK directly
cdk deploy --all --require-approval never
```

### Step-by-Step Deployment

1. **Deploy regional infrastructure first**:
   ```bash
   cdk deploy MultiRegionVpcConnectivity-Primary
   cdk deploy MultiRegionVpcConnectivity-Secondary
   ```

2. **Deploy cross-region peering**:
   ```bash
   cdk deploy TransitGatewayPeering
   ```

3. **Deploy monitoring**:
   ```bash
   cdk deploy MultiRegionMonitoring
   ```

### Deployment Options

```bash
# Preview changes before deployment
cdk diff

# Deploy with manual approval for each change
cdk deploy --all

# Deploy specific stack only
cdk deploy MultiRegionVpcConnectivity-Primary

# Deploy with custom parameters
PROJECT_NAME="my-custom-tgw" cdk deploy --all
```

## Verification

After deployment, verify the infrastructure:

1. **Check stack outputs**:
   ```bash
   # View all outputs
   aws cloudformation describe-stacks \
     --stack-name MultiRegionVpcConnectivity-Primary \
     --query 'Stacks[0].Outputs'
   ```

2. **Verify Transit Gateway status**:
   ```bash
   # Check primary region
   aws ec2 describe-transit-gateways \
     --region $PRIMARY_REGION \
     --query 'TransitGateways[?State==`available`]'
   
   # Check secondary region
   aws ec2 describe-transit-gateways \
     --region $SECONDARY_REGION \
     --query 'TransitGateways[?State==`available`]'
   ```

3. **Check peering connection**:
   ```bash
   aws ec2 describe-transit-gateway-peering-attachments \
     --region $PRIMARY_REGION \
     --query 'TransitGatewayPeeringAttachments[?State==`available`]'
   ```

4. **Access CloudWatch Dashboard**:
   - Navigate to CloudWatch in the AWS Console
   - Look for dashboard named `{PROJECT_NAME}-tgw-dashboard`
   - Verify metrics are being collected

## Testing Connectivity

### Deploy Test Instances (Optional)

```bash
# Create test instances in each VPC for connectivity testing
# This is not included in the CDK app but can be added if needed

# Example: Launch EC2 instances in each VPC
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --subnet-id subnet-xxxxx \
  --security-group-ids sg-xxxxx \
  --region $PRIMARY_REGION
```

### Test Cross-Region Connectivity

1. **Ping test between regions**:
   ```bash
   # From instance in primary region to secondary region VPC
   ping 10.3.1.10
   ```

2. **Check route tables**:
   ```bash
   aws ec2 search-transit-gateway-routes \
     --transit-gateway-route-table-id tgw-rtb-xxxxx \
     --filters "Name=state,Values=active" \
     --region $PRIMARY_REGION
   ```

## Monitoring and Alerting

### CloudWatch Dashboard

The deployment creates a comprehensive dashboard showing:

- **Data Transfer Metrics**: Bytes in/out for both regions
- **Packet Metrics**: Packets in/out and drop counts
- **Cross-Region Comparison**: Bandwidth usage comparison
- **Cost Information**: Estimated costs and optimization tips

### Alarms

The following alarms are configured:

- **High Packet Drops**: Alerts when packet drop count exceeds 1000
- **High Data Transfer**: Alerts when data transfer exceeds 100GB/hour

### SNS Notifications

If you set the `ALERT_EMAIL` environment variable, you'll receive email notifications for:

- Critical network issues
- High cost scenarios
- Performance degradation

## Cost Optimization

### Estimated Costs

- **Transit Gateway Attachments**: ~$36/month per attachment (4 VPC + 1 peering)
- **Data Processing**: $0.02 per GB processed
- **Cross-Region Data Transfer**: $0.02 per GB between regions
- **Total Estimated**: $150-500/month depending on usage

### Cost Optimization Tips

1. **Monitor Data Transfer**: Use CloudWatch metrics to track data usage
2. **Route Optimization**: Use route tables to control traffic flow
3. **VPC Endpoints**: Consider VPC endpoints for AWS services
4. **Resource Tagging**: All resources are tagged for cost allocation

## Customization

### Adding More VPCs

To add additional VPCs to either region:

1. **Update the stack**:
   ```typescript
   // In multi-region-vpc-connectivity-stack.ts
   const vpcC = new ec2.Vpc(this, 'VpcC', {
     // VPC configuration
   });
   
   // Add attachment to Transit Gateway
   const vpcCAttachment = new ec2.CfnTransitGatewayVpcAttachment(this, 'VpcCAttachment', {
     // Attachment configuration
   });
   ```

2. **Update routing**:
   ```typescript
   // Add route table associations and propagations
   ```

### Modifying CIDR Blocks

Update the CIDR blocks in `app.ts`:

```typescript
cidrs: {
  primaryVpcA: '172.16.0.0/16',    // Changed from 10.1.0.0/16
  primaryVpcB: '172.17.0.0/16',    // Changed from 10.2.0.0/16
  secondaryVpcA: '172.18.0.0/16',  // Changed from 10.3.0.0/16
  secondaryVpcB: '172.19.0.0/16'   // Changed from 10.4.0.0/16
}
```

### Adding More Regions

To extend to additional regions:

1. **Create new stack instances** in `app.ts`
2. **Add peering connections** between all regions
3. **Update monitoring** to include new regions

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   ```bash
   # Check CDK bootstrap status
   cdk doctor
   
   # View detailed error logs
   cdk deploy --verbose
   ```

2. **Connectivity Issues**:
   ```bash
   # Check route table status
   aws ec2 describe-transit-gateway-route-tables --region $PRIMARY_REGION
   
   # Verify security group rules
   aws ec2 describe-security-groups --region $PRIMARY_REGION
   ```

3. **Peering Problems**:
   ```bash
   # Check peering attachment status
   aws ec2 describe-transit-gateway-peering-attachments --region $PRIMARY_REGION
   ```

### Debug Commands

```bash
# View all stack resources
cdk ls

# Compare deployed vs. local changes
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name MultiRegionVpcConnectivity-Primary

# Check CDK context
cdk context --clear  # Clear cached context if needed
```

## Cleanup

### Full Cleanup

```bash
# Destroy all stacks (in reverse order)
npm run destroy

# Or using CDK directly
cdk destroy --all
```

### Selective Cleanup

```bash
# Destroy specific stacks
cdk destroy MultiRegionMonitoring
cdk destroy TransitGatewayPeering
cdk destroy MultiRegionVpcConnectivity-Secondary
cdk destroy MultiRegionVpcConnectivity-Primary
```

### Verify Cleanup

```bash
# Check for remaining resources
aws ec2 describe-transit-gateways --region $PRIMARY_REGION
aws ec2 describe-transit-gateways --region $SECONDARY_REGION

# Check CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter DELETE_COMPLETE
```

## Security Considerations

### Network Security

- **Security Groups**: Configured with minimal required access
- **Network ACLs**: Default VPC ACLs applied
- **Route Tables**: Custom routing for traffic control
- **Encryption**: All cross-region traffic is encrypted in transit

### IAM Security

- **Least Privilege**: Lambda functions have minimal required permissions
- **Resource-Based Policies**: Used where appropriate
- **Temporary Credentials**: Lambda uses IAM roles, not access keys

### Monitoring Security

- **CloudTrail Integration**: All API calls are logged
- **VPC Flow Logs**: Can be enabled for detailed traffic analysis
- **Transit Gateway Flow Logs**: Available for security analysis

## Support and Documentation

### AWS Documentation

- [AWS Transit Gateway Guide](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [Cross-Region Peering](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-peering.html)
- [CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)

### Additional Resources

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Networking Best Practices](https://aws.amazon.com/blogs/networking-and-content-delivery/)
- [CDK Workshop](https://cdkworkshop.com/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.