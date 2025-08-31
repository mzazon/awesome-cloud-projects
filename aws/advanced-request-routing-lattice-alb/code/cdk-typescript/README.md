# Advanced Request Routing with VPC Lattice and ALB - CDK TypeScript

This CDK TypeScript application demonstrates sophisticated layer 7 routing using AWS VPC Lattice integrated with Application Load Balancers across multiple VPCs.

## Architecture Overview

The solution creates:

- **VPC Lattice Service Network**: Provides application-layer networking across VPCs
- **Two VPCs**: Primary VPC (10.0.0.0/16) and Target VPC (10.1.0.0/16) for cross-VPC demonstration
- **Internal Application Load Balancer**: Serves as VPC Lattice target with advanced routing capabilities
- **EC2 Web Servers**: Demonstrate different routing scenarios with varied content
- **Advanced Routing Rules**: Path-based, header-based, and method-based routing
- **IAM Authentication**: Fine-grained access control for service-to-service communication

## Features

### Sophisticated Routing Capabilities
- **Path-based routing**: Routes `/api/v1/*` requests to specific targets
- **Header-based routing**: Routes requests with `X-Service-Version: beta` header
- **Method-based routing**: Special handling for POST requests
- **Security rules**: Blocks access to `/admin` endpoints with HTTP 403 response

### Security & Best Practices
- IAM-based authentication for VPC Lattice services
- Security groups with least privilege access
- Internal ALBs for secure target integration
- Comprehensive health checks and monitoring

### Infrastructure as Code
- Type-safe TypeScript implementation
- Configurable parameters via CDK context
- Comprehensive CloudFormation outputs
- Resource tagging and organization

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for VPC Lattice, EC2, ELB, and IAM

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure AWS Environment

```bash
# Set your AWS account and region
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### 3. Bootstrap CDK (if first time)

```bash
npm run bootstrap
```

### 4. Deploy the Stack

```bash
# Deploy with default configuration
npm run deploy

# Or deploy with custom parameters
npx cdk deploy \
  --context stackPrefix=MyRouting \
  --context environment=prod \
  --context vpcCidr=172.16.0.0/16
```

### 5. Test the Routing

After deployment, use the VPC Lattice service domain from the stack outputs:

```bash
# Get the service domain from outputs
LATTICE_DOMAIN=$(aws cloudformation describe-stacks \
  --stack-name AdvancedRouting-dev \
  --query 'Stacks[0].Outputs[?OutputKey==`LatticeServiceDomain`].OutputValue' \
  --output text)

# Test path-based routing
curl -v "http://${LATTICE_DOMAIN}/api/v1/"
curl -v "http://${LATTICE_DOMAIN}/"

# Test header-based routing
curl -v -H "X-Service-Version: beta" "http://${LATTICE_DOMAIN}/"

# Test security controls
curl -v "http://${LATTICE_DOMAIN}/admin"  # Should return 403
```

## Configuration Options

### Context Variables

Set these in `cdk.json` or pass via `--context` flag:

- `stackPrefix`: Prefix for stack name (default: "AdvancedRouting")
- `environment`: Environment name (default: "dev")
- `vpcCidr`: Primary VPC CIDR block (default: "10.0.0.0/16")
- `targetVpcCidr`: Target VPC CIDR block (default: "10.1.0.0/16")

### Example Custom Deployment

```bash
npx cdk deploy \
  --context stackPrefix=ProductionRouting \
  --context environment=prod \
  --context vpcCidr=172.16.0.0/16 \
  --context targetVpcCidr=172.17.0.0/16
```

## Stack Outputs

The stack provides these outputs for integration and testing:

- `ServiceNetworkId`: VPC Lattice Service Network ID
- `LatticeServiceId`: VPC Lattice Service ID  
- `LatticeServiceDomain`: VPC Lattice Service Domain Name
- `AlbDnsName`: Internal ALB DNS Name
- `PrimaryVpcId`: Primary VPC ID
- `TargetVpcId`: Target VPC ID
- `WebServer1Id`: Web Server 1 Instance ID
- `WebServer2Id`: Web Server 2 Instance ID

## Available Scripts

- `npm run build`: Compile TypeScript to JavaScript
- `npm run watch`: Watch for changes and compile
- `npm run test`: Run unit tests
- `npm run deploy`: Deploy the stack
- `npm run destroy`: Destroy the stack
- `npm run diff`: Show differences between deployed and local stack
- `npm run synth`: Synthesize CloudFormation template

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics for VPC Lattice:

- `RequestCount`: Number of requests processed
- `TargetResponseTime`: Response time from targets
- `HTTPCode_Target_2XX_Count`: Successful responses
- `HTTPCode_Target_4XX_Count`: Client errors
- `HTTPCode_Target_5XX_Count`: Server errors

### Health Checks

The ALB target group includes health checks:
- **Path**: `/`
- **Interval**: 10 seconds
- **Healthy threshold**: 2 consecutive successes
- **Unhealthy threshold**: 3 consecutive failures
- **Timeout**: 5 seconds

## Security Considerations

### IAM Authentication Policy

The VPC Lattice service uses IAM authentication with these rules:
- **Allow**: All requests from the same AWS account
- **Deny**: All requests to `/admin` endpoints

### Security Groups

- **ALB Security Group**: Allows HTTP/HTTPS from VPC CIDR ranges
- **EC2 Security Group**: Allows HTTP from ALB and SSH from VPC

### Network Security

- Internal ALBs (not internet-facing)
- Private subnets for EC2 instances
- Cross-VPC communication through VPC Lattice (no peering required)

## Cost Optimization

### Estimated Costs (per hour)
- EC2 t3.micro instances: ~$0.0104 each
- Application Load Balancer: ~$0.0225
- VPC Lattice: Based on processed requests (~$0.025 per million requests)
- VPC and networking: Minimal costs

### Cost-Saving Tips
- Use Spot instances for non-production environments
- Configure appropriate ALB idle timeout
- Monitor VPC Lattice request metrics to optimize routing

## Troubleshooting

### Common Issues

1. **VPC Lattice service not accessible**
   - Verify VPC associations with service network
   - Check IAM authentication policies
   - Ensure security groups allow traffic

2. **ALB targets unhealthy**
   - Check EC2 instance security groups
   - Verify web server is running on instances
   - Review ALB target group health check settings

3. **Routing rules not working**
   - Verify rule priorities (lower numbers = higher priority)
   - Check rule match conditions
   - Test with specific curl commands

### Debug Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice get-service --service-identifier <service-id>

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# Check VPC Lattice service network
aws vpc-lattice get-service-network --service-network-identifier <network-id>
```

## Clean Up

To avoid ongoing charges, destroy the stack when done:

```bash
npm run destroy
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This code is licensed under the MIT-0 License. See the LICENSE file for details.

## Additional Resources

- [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [Application Load Balancer Integration](https://docs.aws.amazon.com/vpc-lattice/latest/ug/alb-target.html)
- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws-vpclattice-readme.html)
- [VPC Lattice Pricing](https://aws.amazon.com/vpc-lattice/pricing/)