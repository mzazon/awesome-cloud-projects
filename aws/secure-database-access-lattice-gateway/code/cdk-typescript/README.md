# Secure Database Access with VPC Lattice Resource Gateway - CDK TypeScript

This CDK TypeScript application deploys a complete secure database access solution using AWS VPC Lattice Resource Gateway, RDS, and AWS RAM for cross-account resource sharing.

## Architecture

The application creates:
- RDS MySQL database in private subnets with encryption
- VPC Lattice Service Network for secure communication
- Resource Gateway for database access abstraction
- Resource Configuration for RDS endpoint mapping
- Security groups with least privilege access
- AWS RAM resource share for cross-account access
- IAM policies for fine-grained access control

## Prerequisites

- AWS CDK v2.100.0 or later
- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- Existing VPC with at least 2 subnets in different AZs
- Consumer AWS account ID for cross-account sharing

## Required Permissions

The deployment requires permissions for:
- VPC Lattice operations (service networks, resource gateways, configurations)
- RDS instance creation and management
- EC2 security group management
- Secrets Manager for database credentials
- AWS RAM for resource sharing
- IAM policy creation and management

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012  # Your AWS account ID
export CDK_DEFAULT_REGION=us-east-1      # Your preferred region
```

### CDK Context Parameters

Configure the deployment using CDK context parameters:

```bash
# Required parameters
cdk deploy --context vpcId=vpc-xxxxxxxxx \
           --context subnetIds=subnet-aaaaaaaa,subnet-bbbbbbbb \
           --context consumerAccountId=123456789012

# Optional parameters with defaults
cdk deploy --context resourcePrefix=my-lattice-db \
           --context dbInstanceClass=db.t3.micro \
           --context dbEngine=mysql \
           --context dbAllocatedStorage=20 \
           --context enableEncryption=true \
           --context backupRetentionPeriod=7 \
           --context environment=production
```

### Parameter Details

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `vpcId` | VPC ID where resources will be created | None | Yes |
| `subnetIds` | Comma-separated list of subnet IDs (min 2) | None | Yes |
| `consumerAccountId` | AWS account ID for cross-account access | None | Yes |
| `resourcePrefix` | Prefix for resource names | `lattice-db` | No |
| `dbInstanceClass` | RDS instance class | `db.t3.micro` | No |
| `dbEngine` | Database engine | `mysql` | No |
| `dbAllocatedStorage` | Storage size in GB | `20` | No |
| `enableEncryption` | Enable storage encryption | `true` | No |
| `backupRetentionPeriod` | Backup retention in days | `7` | No |
| `environment` | Environment tag | `development` | No |

## Installation

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Build the project:**
   ```bash
   npm run build
   ```

3. **Bootstrap CDK (if not done previously):**
   ```bash
   cdk bootstrap
   ```

## Deployment

### Standard Deployment

Deploy with minimum required parameters:

```bash
cdk deploy --context vpcId=vpc-xxxxxxxxx \
           --context subnetIds=subnet-aaaaaaaa,subnet-bbbbbbbb \
           --context consumerAccountId=123456789012
```

### Production Deployment

Deploy with production-grade settings:

```bash
cdk deploy --context vpcId=vpc-xxxxxxxxx \
           --context subnetIds=subnet-aaaaaaaa,subnet-bbbbbbbb \
           --context consumerAccountId=123456789012 \
           --context dbInstanceClass=db.r6g.large \
           --context dbAllocatedStorage=100 \
           --context backupRetentionPeriod=30 \
           --context environment=production
```

### Preview Changes

Review what will be deployed:

```bash
cdk diff --context vpcId=vpc-xxxxxxxxx \
         --context subnetIds=subnet-aaaaaaaa,subnet-bbbbbbbb \
         --context consumerAccountId=123456789012
```

## Post-Deployment Steps

After successful deployment:

1. **Note the outputs** - The stack provides important outputs including database endpoint, Resource Gateway ARN, and RAM share ARN.

2. **Consumer account setup** - The consumer account must:
   - Accept the AWS RAM invitation
   - Associate their VPC with the shared Service Network
   - Configure security groups to allow access

3. **Database access** - Connect to the database using the VPC Lattice DNS name provided in the outputs.

## Outputs

The stack provides these outputs:

| Output | Description |
|--------|-------------|
| `DatabaseEndpoint` | RDS database endpoint |
| `DatabaseCredentialsSecretArn` | ARN of the secret containing database credentials |
| `ResourceGatewayArn` | ARN of the VPC Lattice Resource Gateway |
| `ServiceNetworkArn` | ARN of the VPC Lattice Service Network |
| `ResourceConfigurationArn` | ARN of the VPC Lattice Resource Configuration |
| `RAMResourceShareArn` | ARN of the AWS RAM resource share |
| `ConsumerAccountId` | Consumer account ID for reference |
| `ResourceGatewayDNS` | DNS name for accessing the database through VPC Lattice |

## Testing

### Connection Test

Test database connectivity from the consumer account:

```bash
# Get database credentials from Secrets Manager
aws secretsmanager get-secret-value \
    --secret-id <DatabaseCredentialsSecretArn> \
    --query SecretString --output text

# Connect using MySQL client
mysql -h <ResourceGatewayDNS> -P 3306 -u admin -p
```

### Resource Verification

Verify resources are created correctly:

```bash
# Check VPC Lattice resources
aws vpc-lattice describe-service-network --service-network-id <ServiceNetworkArn>
aws vpc-lattice describe-resource-gateway --resource-gateway-id <ResourceGatewayArn>

# Check RDS instance
aws rds describe-db-instances --db-instance-identifier <database-id>

# Check RAM resource share
aws ram get-resource-shares --resource-share-arns <RAMResourceShareArn>
```

## Monitoring and Observability

### CloudWatch Metrics

Monitor these key metrics:
- RDS database performance metrics
- VPC Lattice request metrics
- Security group traffic patterns

### Logging

Configure these logging options:
- VPC Lattice access logs
- RDS database logs
- CloudTrail for API calls

### Alarms

Consider setting up alarms for:
- Database connection failures
- High database CPU utilization
- VPC Lattice error rates

## Security Considerations

### Network Security
- Database deployed in private subnets only
- Security groups follow least privilege principle
- No internet gateway access for database

### Access Control
- IAM policies restrict cross-account access
- AWS RAM provides secure resource sharing
- Database credentials stored in Secrets Manager

### Encryption
- Storage encryption enabled by default
- Encryption in transit using SSL/TLS
- Secrets Manager handles credential encryption

## Cost Optimization

### Cost Components
- RDS instance charges (instance class dependent)
- VPC Lattice charges (per hour + data processing)
- AWS RAM charges (no additional cost)
- Storage charges for database and backups

### Optimization Tips
- Use appropriate instance classes for workload
- Enable automated backups with reasonable retention
- Monitor VPC Lattice data transfer charges
- Consider Reserved Instances for production workloads

## Troubleshooting

### Common Issues

1. **VPC/Subnet not found**
   - Verify VPC and subnet IDs are correct
   - Ensure subnets are in different Availability Zones

2. **Database connection failures**
   - Check security group rules
   - Verify Resource Gateway configuration
   - Confirm RAM resource share acceptance

3. **Cross-account access denied**
   - Verify consumer account ID is correct
   - Check IAM policy configuration
   - Ensure RAM invitation is accepted

### Debug Commands

```bash
# Check CDK context
cdk context

# View synthesized CloudFormation
cdk synth

# Check deployment status
aws cloudformation describe-stacks --stack-name SecureDatabaseAccessStack
```

## Cleanup

Remove all resources:

```bash
cdk destroy
```

**Note:** Deletion protection is disabled for development environments. For production, ensure proper backup procedures before cleanup.

## Development

### Project Structure

```
├── app.ts                      # CDK application entry point
├── lib/
│   └── secure-database-access-stack.ts  # Main stack implementation
├── package.json                # Dependencies and scripts
├── tsconfig.json              # TypeScript configuration
├── cdk.json                   # CDK configuration
└── README.md                  # This file
```

### Available Scripts

| Script | Description |
|--------|-------------|
| `npm run build` | Compile TypeScript |
| `npm run watch` | Watch for changes and recompile |
| `npm run test` | Run unit tests |
| `npm run cdk` | Run CDK CLI commands |
| `npm run deploy` | Deploy the stack |
| `npm run destroy` | Destroy the stack |

### Adding Tests

Create unit tests in the `test/` directory:

```typescript
import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { SecureDatabaseAccessStack } from '../lib/secure-database-access-stack';

test('RDS Instance Created', () => {
  const app = new cdk.App();
  const stack = new SecureDatabaseAccessStack(app, 'TestStack', {
    vpcId: 'vpc-12345',
    subnetIds: ['subnet-12345', 'subnet-67890'],
    consumerAccountId: '123456789012',
    // ... other required props
  });
  
  const template = Template.fromStack(stack);
  template.hasResourceProperties('AWS::RDS::DBInstance', {
    Engine: 'mysql'
  });
});
```

## Support

For issues related to this CDK application:
1. Check the troubleshooting section above
2. Review AWS documentation for VPC Lattice and RDS
3. Consult the original recipe documentation
4. Check AWS service health dashboards

## Contributing

When modifying this application:
1. Follow TypeScript best practices
2. Update tests for any changes
3. Ensure security best practices are maintained
4. Update documentation as needed
5. Test in a development environment first