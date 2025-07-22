# Amazon Q Developer Prompt Templates

## Infrastructure Generation Prompts

### Basic Web Application Stack
"Generate a CloudFormation template for a serverless web application with:
- S3 bucket for static hosting with CloudFront distribution
- API Gateway with Lambda backend functions
- DynamoDB table for user data storage
- IAM roles with appropriate permissions
Include proper security configurations and follow AWS best practices."

### Microservices Architecture
"Create infrastructure code for a microservices architecture using:
- ECS Fargate for container orchestration
- Application Load Balancer for traffic distribution
- RDS Aurora for relational data storage
- ElastiCache for session management
- VPC with public and private subnets across multiple AZs"

### Data Processing Pipeline
"Design a data processing infrastructure with:
- S3 buckets for data ingestion and processed output
- Kinesis Data Streams for real-time data processing
- Lambda functions for data transformation
- Glue for ETL operations
- Redshift for data warehousing and analytics"

### AI/ML Infrastructure
"Generate infrastructure for machine learning workflows with:
- SageMaker for model training and hosting
- S3 for training data and model artifacts
- Lambda for inference endpoints
- Step Functions for ML pipeline orchestration
- CloudWatch for model monitoring"

### Event-Driven Architecture
"Create an event-driven system with:
- EventBridge for event routing
- Lambda functions for event processing
- SQS for message queuing
- SNS for notifications
- DynamoDB for event storage"

## Security-Focused Prompts

### Zero-Trust Network Architecture
"Generate infrastructure for a zero-trust security model including:
- VPC with no internet gateways
- VPC endpoints for AWS service access
- Transit Gateway for network connectivity
- AWS Config for compliance monitoring
- GuardDuty for threat detection"

### Data Encryption Infrastructure
"Create a comprehensive data encryption setup with:
- KMS keys for encryption at rest
- Certificate Manager for SSL/TLS certificates
- Secrets Manager for credential storage
- IAM roles with encryption policies
- CloudTrail for encryption audit logging"

### Multi-Account Security
"Design a multi-account security architecture using:
- Organizations for account management
- Control Tower for governance
- Single Sign-On for centralized authentication
- Cross-account IAM roles
- Centralized logging with CloudTrail"

## Container and Orchestration Prompts

### Kubernetes on EKS
"Generate infrastructure for an Amazon EKS cluster with:
- EKS cluster with managed node groups
- Fargate profiles for serverless pods
- Application Load Balancer controller
- EBS CSI driver for persistent storage
- Cluster autoscaler for dynamic scaling"

### Docker Container Platform
"Create a container platform using:
- ECS cluster with EC2 and Fargate capacity
- ECR for container image registry
- Application Load Balancer for service discovery
- EFS for shared persistent storage
- CloudWatch Container Insights"

### Service Mesh Architecture
"Design a service mesh infrastructure with:
- App Mesh for service communication
- EKS cluster for container orchestration
- X-Ray for distributed tracing
- CloudWatch for service monitoring
- Certificate Manager for mTLS"

## Database and Storage Prompts

### Multi-Database Architecture
"Create a polyglot persistence solution with:
- RDS Aurora for relational data
- DynamoDB for NoSQL requirements
- ElastiCache for caching layer
- S3 for object storage
- Database migration tools"

### Data Lake Infrastructure
"Generate a comprehensive data lake with:
- S3 buckets with intelligent tiering
- Glue Data Catalog for metadata management
- Lake Formation for access control
- Athena for ad-hoc querying
- QuickSight for data visualization"

### Backup and Disaster Recovery
"Design a disaster recovery solution including:
- Cross-region replication for databases
- S3 Cross-Region Replication
- AWS Backup for centralized backup
- Route 53 health checks and failover
- Lambda for automated recovery procedures"

## DevOps and CI/CD Prompts

### Complete CI/CD Pipeline
"Generate a full CI/CD infrastructure with:
- CodeCommit for source control
- CodeBuild for build automation
- CodeDeploy for deployment orchestration
- CodePipeline for workflow management
- Artifact storage in S3"

### Infrastructure as Code Pipeline
"Create an IaC deployment pipeline using:
- CodeCommit for Terraform/CloudFormation storage
- CodeBuild for template validation
- CodePipeline for multi-environment deployment
- Parameter Store for configuration management
- CloudFormation StackSets for multi-account deployment"

### Monitoring and Observability
"Design comprehensive monitoring infrastructure with:
- CloudWatch for metrics and logs
- X-Ray for distributed tracing
- Systems Manager for operational insights
- SNS for alerting and notifications
- Grafana for custom dashboards"

## Cost Optimization Prompts

### Cost-Optimized Architecture
"Generate cost-optimized infrastructure using:
- Spot instances for batch processing
- Reserved instances for predictable workloads
- S3 intelligent tiering for storage optimization
- Lambda for event-driven processing
- Auto Scaling for dynamic capacity"

### Resource Management
"Create resource optimization infrastructure with:
- AWS Config for resource inventory
- Cost Explorer API for cost analysis
- Lambda for automated resource cleanup
- CloudWatch Events for scheduling
- SNS for cost alerting"

## Compliance and Governance Prompts

### SOC 2 Compliant Infrastructure
"Generate SOC 2 compliant infrastructure including:
- Comprehensive logging with CloudTrail
- Encryption for all data stores
- Access controls with IAM policies
- Network segmentation with VPCs
- Automated compliance checking"

### HIPAA Compliant Healthcare Platform
"Create HIPAA-compliant infrastructure with:
- Dedicated tenancy for sensitive workloads
- End-to-end encryption for PHI
- Audit logging for all access
- Network isolation and monitoring
- Automated compliance reporting"

### Financial Services Compliance
"Design financial services infrastructure with:
- PCI DSS compliant payment processing
- Multi-factor authentication requirements
- Data residency controls
- Real-time fraud detection
- Comprehensive audit trails"

## Usage Tips for Amazon Q Developer

1. **Be Specific**: Include exact AWS service names and configuration requirements
2. **Context Matters**: Provide business context and technical constraints
3. **Security First**: Always mention security requirements and compliance needs
4. **Best Practices**: Ask for AWS Well-Architected Framework alignment
5. **Environment Awareness**: Specify if this is for development, testing, or production
6. **Integration Requirements**: Mention existing systems and integration points
7. **Performance Needs**: Include performance and scalability requirements
8. **Cost Considerations**: Specify budget constraints and cost optimization needs

## Example Conversation Flow

**User**: "I need infrastructure for a real-time chat application"

**Enhanced Prompt**: "Generate CloudFormation infrastructure for a real-time chat application that needs to:
- Support 10,000 concurrent users
- Handle message delivery with sub-second latency
- Store chat history for 90 days
- Include user authentication and authorization
- Provide mobile and web client support
- Ensure messages are encrypted in transit and at rest
- Support file sharing up to 10MB per message
- Include moderation capabilities for content filtering
- Provide analytics on user engagement
- Be cost-optimized for a startup budget under $500/month
Please follow AWS Well-Architected principles and include comprehensive monitoring."