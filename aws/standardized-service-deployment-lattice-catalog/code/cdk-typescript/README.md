# CDK TypeScript Implementation: Standardized Service Deployment with VPC Lattice and Service Catalog

This directory contains a production-ready CDK TypeScript implementation of the "Standardized Service Deployment with VPC Lattice and Service Catalog" recipe.

## Architecture Overview

This implementation creates a comprehensive solution for standardized VPC Lattice service deployments using AWS Service Catalog for governance and self-service capabilities.

### Components

1. **VPC Lattice Templates Stack** (`VpcLatticeTemplatesStack`)
   - Creates S3 bucket for CloudFormation template storage
   - Deploys standardized VPC Lattice service network and service templates
   - Implements encryption and lifecycle policies for security and cost optimization

2. **Service Catalog Stack** (`ServiceCatalogStack`)
   - Creates Service Catalog portfolio and products
   - Configures IAM roles and launch constraints
   - Implements governance controls and template constraints

3. **Main Infrastructure Stack** (`StandardizedServiceDeploymentStack`)
   - Provides demonstration VPC and ECS infrastructure
   - Creates sample containerized service for testing
   - Implements monitoring and observability components

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Appropriate AWS permissions for:
  - VPC Lattice services
  - Service Catalog management
  - IAM roles and policies
  - S3 bucket operations
  - ECS and CloudWatch resources

## Cost Considerations

This implementation is designed for production use but includes cost optimizations:

- S3 bucket lifecycle policies for template versioning
- ECS Fargate services with minimal resource allocation
- CloudWatch log retention set to 7 days for demo purposes
- VPC flow logs enabled only for rejected traffic

**Estimated monthly cost**: $15-30 for minimal usage (primarily ECS Fargate and NAT Gateway costs)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

Set up your CDK environment (if not already done):

```bash
cdk bootstrap
```

### 3. Deploy All Stacks

Deploy the complete solution:

```bash
npm run deploy
```

Or deploy individual stacks in order:

```bash
npm run deploy:templates
npm run deploy:catalog
npm run deploy:main
```

### 4. Verify Deployment

Check the CloudFormation outputs for important resource IDs and ARNs:

```bash
aws cloudformation describe-stacks --stack-name standardized-lattice-templates-dev
aws cloudformation describe-stacks --stack-name standardized-lattice-catalog-dev
aws cloudformation describe-stacks --stack-name standardized-lattice-main-dev
```

## Service Catalog Usage

### Accessing the Portfolio

1. Navigate to AWS Service Catalog in the AWS Console
2. Select "Products" from the left menu
3. You should see two products:
   - "Standardized VPC Lattice Service Network"
   - "Standardized VPC Lattice Service"

### Deploying a Service Network

1. Select the "Standardized VPC Lattice Service Network" product
2. Click "Launch Product"
3. Provide parameters:
   - **NetworkName**: Unique name for your service network
   - **AuthType**: Choose "AWS_IAM" for secure access
   - **EnableLogging**: Set to "true" for access logging
4. Launch the product

### Deploying a VPC Lattice Service

1. Select the "Standardized VPC Lattice Service" product
2. Click "Launch Product"
3. Provide parameters:
   - **ServiceName**: Unique name for your service
   - **ServiceNetworkId**: Use the ID from the deployed service network
   - **VpcId**: Use the VPC ID from the main stack output
   - **TargetType**: Choose "ALB" to use the sample load balancer
   - **Port**: 80 for HTTP traffic
   - **Protocol**: HTTP

## Customization

### Environment Configuration

Modify `cdk.json` to change default values:

```json
{
  "context": {
    "environment": "dev",
    "projectName": "your-project-name"
  }
}
```

### Template Modifications

To customize the CloudFormation templates:

1. Edit the template generation methods in `lib/vpc-lattice-templates-stack.ts`
2. Redeploy the templates stack: `npm run deploy:templates`
3. Update the Service Catalog product versions if needed

### Adding New Products

To add additional Service Catalog products:

1. Create new template generation methods in `VpcLatticeTemplatesStack`
2. Add new product creation methods in `ServiceCatalogStack`
3. Associate the new products with the portfolio

### Security Customization

Modify IAM policies in `ServiceCatalogStack.createLaunchRole()` to adjust permissions:

- Add service-specific permissions
- Implement resource-level restrictions
- Configure condition-based access controls

## Monitoring and Observability

### CloudWatch Dashboard

The implementation creates a CloudWatch dashboard with:
- ECS service CPU and memory metrics
- Application Load Balancer health metrics
- Custom alarms for critical thresholds

Access the dashboard: **AWS Console > CloudWatch > Dashboards > VPC-Lattice-Standardized-Deployment**

### Alarms

Pre-configured alarms monitor:
- High CPU utilization (>80%)
- Unhealthy load balancer targets

### Logging

- ECS service logs: `/ecs/demo-service`
- VPC flow logs: Enabled for rejected traffic
- VPC Lattice access logs: Configured when enabled in Service Network template

## Security Features

### CDK Nag Integration

The implementation includes CDK Nag security scanning with appropriate suppressions for demo patterns. To run security checks:

```bash
npm run synth
```

### IAM Security

- Launch roles follow least privilege principle
- Cross-service access controlled via IAM conditions
- Service Catalog products isolated with launch constraints

### Network Security

- VPC with private subnets for ECS services
- Security groups with minimal required access
- VPC flow logs for security monitoring

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Permission Denied Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies for VPC Lattice, Service Catalog, and supporting services

3. **Service Catalog Product Launch Failures**
   - Verify the launch role has appropriate permissions
   - Check CloudFormation events in the Service Catalog console
   - Ensure template parameters are valid

4. **Template Upload Issues**
   - Verify S3 bucket creation was successful
   - Check that CloudFormation templates are syntactically valid

### Debugging

Enable debug logging:

```bash
export CDK_DEBUG=true
npm run synth
```

View detailed CloudFormation events:

```bash
aws cloudformation describe-stack-events --stack-name STACK-NAME
```

## Cleanup

### Remove All Resources

```bash
npm run destroy
```

This will remove all stacks in reverse dependency order.

### Manual Cleanup

If automatic cleanup fails:

1. Terminate any active Service Catalog provisioned products
2. Delete CloudFormation stacks manually in the AWS console
3. Remove the S3 bucket if it wasn't automatically deleted

## Development

### Code Structure

```
lib/
├── vpc-lattice-templates-stack.ts    # CloudFormation template management
├── service-catalog-stack.ts          # Service Catalog portfolio and products
└── standardized-service-deployment-stack.ts  # Main infrastructure
```

### Testing

Run TypeScript compilation and CDK synthesis:

```bash
npm run build
npm run synth
```

### Code Quality

Format code with Prettier:

```bash
npm run format
```

Run ESLint:

```bash
npm run lint
```

## Production Considerations

### Multi-Environment Deployment

For production deployment:

1. Update `cdk.json` context for each environment
2. Use environment-specific parameter values
3. Configure proper IAM access controls for different teams
4. Implement approval workflows for Service Catalog products

### Security Hardening

- Enable AWS Config for compliance monitoring
- Implement AWS CloudTrail for audit logging
- Use AWS Secrets Manager for sensitive configuration
- Enable AWS GuardDuty for threat detection

### Monitoring Enhancement

- Integrate with AWS Systems Manager for operational insights
- Configure AWS X-Ray for distributed tracing
- Set up custom CloudWatch metrics for business KPIs
- Implement AWS SNS notifications for critical alarms

### Cost Optimization

- Implement S3 Intelligent Tiering for template storage
- Use Spot instances for non-critical ECS workloads
- Configure auto-scaling policies for variable workloads
- Regular review of CloudWatch log retention policies

## Support

For issues with this CDK implementation:

1. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
2. Review [VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
3. Consult [Service Catalog Documentation](https://docs.aws.amazon.com/servicecatalog/)
4. Open an issue in your organization's repository

## Contributing

When contributing to this implementation:

1. Follow TypeScript and CDK best practices
2. Update documentation for any changes
3. Test changes in a development environment
4. Ensure CDK Nag security checks pass
5. Update version numbers appropriately