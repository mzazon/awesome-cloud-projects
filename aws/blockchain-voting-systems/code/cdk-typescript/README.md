# Blockchain Voting System CDK Application

This AWS CDK (Cloud Development Kit) application deploys a comprehensive blockchain-based voting system using Amazon Managed Blockchain with Ethereum smart contracts. The system provides secure, transparent, and immutable voting capabilities with real-time monitoring and comprehensive audit trails.

## Architecture Overview

The system consists of three main stacks:

1. **Security Stack** - Foundational security infrastructure
2. **Core System Stack** - Main voting system components
3. **Monitoring Stack** - Observability and alerting

## Key Features

### Core Voting System
- **Amazon Managed Blockchain** - Ethereum network for immutable vote storage
- **AWS Lambda** - Serverless functions for voter authentication and monitoring
- **Amazon DynamoDB** - Voter registry and election management
- **Amazon S3** - Voting data storage and DApp hosting
- **Amazon Cognito** - User authentication and authorization
- **API Gateway** - REST API for voting operations
- **EventBridge** - Real-time event processing

### Security Features
- **AWS KMS** - Encryption at rest and in transit
- **IAM Roles** - Least privilege access control
- **CloudTrail** - Comprehensive audit logging
- **AWS GuardDuty** - Threat detection
- **AWS Config** - Compliance monitoring
- **Multi-factor Authentication** - Enhanced voter security

### Monitoring & Observability
- **CloudWatch Dashboards** - Real-time system metrics
- **CloudWatch Alarms** - Automated alerting
- **X-Ray Tracing** - Distributed request tracing
- **Custom Metrics** - Voting-specific monitoring
- **SNS Notifications** - Multi-channel alerting
- **Log Aggregation** - Centralized logging

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI** installed and configured
2. **Node.js** 18.x or later
3. **AWS CDK** v2.132.0 or later
4. **TypeScript** 5.x or later
5. **AWS Account** with appropriate permissions
6. **Domain Name** (optional, for custom domain)

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd blockchain-voting-system-cdk
```

2. Install dependencies:
```bash
npm install
```

3. Build the TypeScript code:
```bash
npm run build
```

4. Bootstrap CDK (if not already done):
```bash
npm run bootstrap
```

## Configuration

The application supports configuration through CDK context parameters. You can set these in `cdk.json` or pass them via command line.

### Environment Variables

Set these environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=us-east-1
```

### Context Parameters

Configure the application behavior using CDK context:

```json
{
  "appName": "blockchain-voting-system",
  "environment": "dev",
  "blockchainNetwork": "GOERLI",
  "blockchainInstanceType": "bc.t3.medium",
  "enableEncryption": true,
  "enableMFA": true,
  "enableDApp": true,
  "enableAlarming": true,
  "adminEmail": "admin@example.com",
  "auditorsEmail": "auditors@example.com",
  "logRetentionDays": 30
}
```

## Deployment

### Deploy All Stacks

Deploy the complete voting system:

```bash
npm run deploy
```

### Deploy Individual Stacks

Deploy stacks individually:

```bash
# Deploy security stack first
cdk deploy blockchain-voting-system-Security-dev

# Deploy core system stack
cdk deploy blockchain-voting-system-Core-dev

# Deploy monitoring stack
cdk deploy blockchain-voting-system-Monitoring-dev
```

### Environment-Specific Deployment

Deploy to different environments:

```bash
# Development environment
cdk deploy --all --context environment=dev

# Production environment
cdk deploy --all --context environment=prod
```

## Usage

### Voter Registration

1. **Admin Registration**: Use the admin role to register voters
2. **Identity Verification**: Voters verify their identity through multi-factor authentication
3. **Voting Token**: Generate time-limited voting tokens

### Voting Process

1. **Authentication**: Voters authenticate using Cognito
2. **Election Selection**: Choose from active elections
3. **Vote Casting**: Cast votes which are recorded on the blockchain
4. **Confirmation**: Receive confirmation of successful vote

### Election Management

1. **Create Election**: Admin creates new elections with candidates
2. **Configure Voting Period**: Set start and end times
3. **Monitor Progress**: View real-time voting statistics
4. **End Election**: Close voting and generate results

### Monitoring

Access the CloudWatch dashboard to monitor:
- System health and performance
- Voting activity and patterns
- Security events and alerts
- Resource utilization

## API Endpoints

The system provides the following API endpoints:

### Authentication
- `POST /auth` - Voter authentication and registration
- `POST /auth/verify` - Identity verification
- `POST /auth/token` - Generate voting token

### Voting
- `POST /vote` - Cast a vote
- `GET /vote/history` - View voting history (admin only)

### Elections
- `GET /election/{electionId}` - Get election details
- `POST /election` - Create new election (admin only)
- `PUT /election/{electionId}` - Update election (admin only)

### Results
- `GET /results/{electionId}` - Get election results
- `GET /results/{electionId}/detailed` - Get detailed results (admin only)

## Security Considerations

### Data Protection
- All sensitive data is encrypted using AWS KMS
- Voter information is hashed for privacy
- GDPR-compliant data handling

### Access Control
- Role-based access control (RBAC)
- Least privilege principle
- Multi-factor authentication

### Audit and Compliance
- Comprehensive audit trails
- Immutable blockchain records
- Regular security scans

### Threat Detection
- AWS GuardDuty integration
- Real-time security monitoring
- Automated incident response

## Testing

### Unit Tests
Run unit tests for the CDK application:
```bash
npm run test
```

### Integration Tests
Run integration tests:
```bash
npm run test:integration
```

### Load Testing
Perform load testing on the deployed system:
```bash
npm run test:load
```

## Monitoring and Alerting

### CloudWatch Dashboards
- System overview and health
- Voting activity metrics
- Performance indicators
- Security events

### Alarms
- Lambda function errors
- DynamoDB throttling
- API Gateway errors
- High voting volume
- Security events

### Notifications
- Email notifications for admins
- Slack integration for teams
- PagerDuty for critical alerts

## Backup and Recovery

### Data Backup
- DynamoDB point-in-time recovery
- S3 versioning and lifecycle policies
- CloudTrail log retention

### Disaster Recovery
- Multi-region deployment capability
- Automated failover procedures
- Data replication strategies

## Cost Optimization

### Resource Sizing
- Right-size Lambda functions
- Optimize DynamoDB capacity
- Use S3 intelligent tiering

### Monitoring Costs
- CloudWatch cost alerts
- Regular cost reviews
- Resource cleanup automation

## Troubleshooting

### Common Issues

1. **Deployment Failures**
   - Check IAM permissions
   - Verify resource limits
   - Review error logs

2. **Authentication Problems**
   - Verify Cognito configuration
   - Check user pool settings
   - Validate MFA setup

3. **Performance Issues**
   - Monitor Lambda duration
   - Check DynamoDB capacity
   - Review API Gateway throttling

### Debug Mode
Enable debug logging:
```bash
export LOG_LEVEL=DEBUG
```

### Log Analysis
Use CloudWatch Logs Insights for troubleshooting:
```sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Create an issue in the repository
- Contact the development team
- Review the documentation

## Changelog

### v1.0.0
- Initial release
- Core voting system functionality
- Security and monitoring features
- Comprehensive documentation

## Acknowledgments

- AWS CDK team for the excellent framework
- Ethereum community for blockchain technology
- Open source contributors

---

For more information about AWS CDK, visit the [official documentation](https://docs.aws.amazon.com/cdk/).