# EC2 Fleet Management CDK TypeScript Application

This CDK TypeScript application implements EC2 Fleet Management with Spot Instances for cost optimization and high availability.

## Architecture

The application deploys:
- **EC2 Fleet**: Mixed instance types with Spot and On-Demand instances
- **Spot Fleet**: Pure Spot instance fleet for comparison
- **VPC**: Multi-AZ VPC with public subnets
- **Security Groups**: Secure access configuration
- **Launch Template**: Standardized instance configuration
- **CloudWatch Dashboard**: Real-time monitoring and metrics
- **IAM Roles**: Proper service permissions

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ installed
- AWS CDK CLI v2 installed (`npm install -g aws-cdk`)
- TypeScript installed (`npm install -g typescript`)

## Required AWS Permissions

Your AWS credentials need permissions for:
- EC2 Fleet and Spot Fleet operations
- VPC and Security Group management
- IAM role creation and management
- CloudWatch dashboard creation
- Launch Template management

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **Monitor the deployment**:
   ```bash
   # Check fleet status
   aws ec2 describe-fleets --fleet-ids <FLEET_ID>
   
   # Check instances
   aws ec2 describe-fleet-instances --fleet-id <FLEET_ID>
   ```

## Configuration

### Context Parameters

Customize the deployment using CDK context parameters:

```bash
# Deploy with custom fleet configuration
cdk deploy -c fleetName=my-custom-fleet \
           -c totalCapacity=10 \
           -c onDemandCapacity=3 \
           -c spotCapacity=7 \
           -c instanceTypes='["t3.micro","t3.small","t3.medium"]' \
           -c enableMonitoring=true
```

### Environment Variables

Set these environment variables for configuration:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### Key Pair Configuration

To enable SSH access to instances:

```bash
# Create a key pair first
aws ec2 create-key-pair --key-name my-fleet-key --query 'KeyMaterial' --output text > my-fleet-key.pem
chmod 400 my-fleet-key.pem

# Deploy with key pair
cdk deploy -c keyPairName=my-fleet-key
```

## Available Commands

```bash
# Build the TypeScript code
npm run build

# Watch for changes and rebuild
npm run watch

# Run tests
npm run test

# Synthesize CloudFormation template
npm run synth

# Deploy the stack
npm run deploy

# Destroy the stack
npm run destroy

# Show differences
npm run diff
```

## Monitoring

The application creates a CloudWatch dashboard with:
- CPU utilization across fleet instances
- Spot fleet available instance pools
- Total fleet capacity metrics
- Spot interruption counts

Access the dashboard through the AWS Console or use the URL provided in the stack outputs.

## Cost Optimization Features

1. **Mixed Instance Types**: Automatically distributes across multiple instance types
2. **Capacity-Optimized Allocation**: Minimizes Spot interruptions
3. **Diversified On-Demand**: Spreads On-Demand instances across instance types
4. **Automatic Rebalancing**: Replaces interrupted instances seamlessly

## Security Features

- **IMDSv2 Enforcement**: Requires secure instance metadata access
- **Security Groups**: Controlled network access
- **IAM Least Privilege**: Minimal required permissions
- **VPC Isolation**: Network-level security

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**: Ensure your AWS credentials have the required permissions
2. **Instance Capacity Issues**: Try different instance types or regions
3. **Spot Interruptions**: Monitor Spot pricing and consider capacity-optimized allocation
4. **Key Pair Not Found**: Create the key pair before deployment

### Useful Commands

```bash
# Check fleet status
aws ec2 describe-fleets --fleet-ids <FLEET_ID>

# List fleet instances
aws ec2 describe-fleet-instances --fleet-id <FLEET_ID>

# Check Spot prices
aws ec2 describe-spot-price-history --instance-types t3.micro --product-descriptions "Linux/UNIX"

# View launch template
aws ec2 describe-launch-templates --launch-template-names <TEMPLATE_NAME>
```

## Cleanup

To avoid ongoing costs, destroy the stack when done:

```bash
npm run destroy
```

This will:
- Terminate all fleet instances
- Delete the EC2 Fleet and Spot Fleet
- Remove the launch template
- Delete security groups and IAM roles
- Remove the CloudWatch dashboard

## Testing

Run the test suite:

```bash
npm run test
```

## Stack Outputs

The stack provides these outputs:
- **VpcId**: VPC where the fleet is deployed
- **SecurityGroupId**: Security group for fleet instances
- **LaunchTemplateId**: Launch template used by fleets
- **EC2FleetId**: EC2 Fleet identifier
- **SpotFleetId**: Spot Fleet identifier
- **DashboardUrl**: CloudWatch dashboard URL
- **MonitoringCommands**: CLI commands for monitoring

## Best Practices

1. **Instance Types**: Choose instance types based on your workload requirements
2. **Capacity Planning**: Start with smaller capacity and scale based on demand
3. **Monitoring**: Regularly check fleet health and cost metrics
4. **Security**: Use VPC endpoints for secure AWS service access
5. **Cost Control**: Set up AWS Budgets and Cost Alerts

## Related Documentation

- [AWS EC2 Fleet Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-ec2-fleet.html)
- [AWS Spot Fleet Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-fleet.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Cost Optimization with Spot Instances](https://docs.aws.amazon.com/whitepapers/latest/cost-optimization-leveraging-ec2-spot-instances/cost-optimization-leveraging-ec2-spot-instances.html)

## License

This project is licensed under the MIT License.