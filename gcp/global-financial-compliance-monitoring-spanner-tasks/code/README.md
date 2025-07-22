# Infrastructure as Code for Global Financial Compliance Monitoring with Cloud Spanner and Cloud Tasks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Global Financial Compliance Monitoring with Cloud Spanner and Cloud Tasks".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Spanner administration
  - Cloud Tasks administration
  - Cloud Functions deployment
  - Cloud Logging configuration
  - IAM role management
  - Pub/Sub topic management
  - Cloud Storage bucket creation
- Understanding of financial compliance requirements (KYC, AML, cross-border regulations)
- Estimated cost: $200-400/month for development environment

> **Warning**: This solution handles sensitive financial data. Ensure proper encryption, access controls, and audit logging are configured before processing real financial transactions.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-monitor \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/global-financial-compliance-monitoring-spanner-tasks/code/infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
region     = "${REGION}"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SPANNER_INSTANCE="compliance-monitor"
export SPANNER_DATABASE="financial-compliance"

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This implementation creates a comprehensive financial compliance monitoring system with the following components:

### Core Infrastructure
- **Cloud Spanner**: Globally distributed database for transaction storage and compliance state management
- **Cloud Tasks**: Reliable task queuing for asynchronous compliance processing
- **Cloud Functions**: Serverless compute for compliance rules engine, transaction processing, and reporting
- **Pub/Sub**: Event-driven messaging for compliance workflow orchestration

### Monitoring & Security
- **Cloud Logging**: Comprehensive audit logging for compliance events
- **Cloud Monitoring**: Performance metrics and alerting for compliance operations
- **IAM Service Accounts**: Secure access control with least privilege principles
- **Cloud Storage**: Secure storage for compliance reports and audit data

### Key Features
- Real-time transaction compliance monitoring
- Automated KYC and AML checks
- Cross-border transaction regulation enforcement
- Immutable audit trails for regulatory compliance
- Automated compliance reporting across jurisdictions
- Global data consistency with strong ACID transactions

## Configuration Variables

### Infrastructure Manager Variables
- `project_id`: Google Cloud project ID
- `region`: Primary deployment region (default: us-central1)
- `spanner_instance_name`: Name for the Spanner instance (default: compliance-monitor)
- `spanner_database_name`: Name for the compliance database (default: financial-compliance)
- `task_queue_name`: Name for the Cloud Tasks queue (default: compliance-checks)
- `environment`: Environment label (default: production)

### Terraform Variables
- `project_id`: Google Cloud project ID (required)
- `region`: Primary deployment region (default: us-central1)
- `spanner_config`: Spanner instance configuration (default: regional-us-central1)
- `spanner_node_count`: Number of Spanner nodes (default: 2)
- `function_memory`: Memory allocation for Cloud Functions (default: 512Mi)
- `enable_audit_logging`: Enable comprehensive audit logging (default: true)
- `compliance_check_timeout`: Timeout for compliance checks in seconds (default: 540)

## Post-Deployment Configuration

After successful deployment, complete these additional configuration steps:

### 1. Verify Spanner Database Schema

```bash
# Check database tables
gcloud spanner databases ddl describe ${SPANNER_DATABASE} \
    --instance=${SPANNER_INSTANCE}
```

### 2. Test Transaction Processing

```bash
# Get the transaction processor URL
TRANSACTION_URL=$(gcloud functions describe transaction-processor \
    --region=${REGION} --format="value(serviceConfig.uri)")

# Submit a test transaction
curl -X POST ${TRANSACTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "account_id": "test-account-001",
        "amount": 5000.00,
        "currency": "USD",
        "source_country": "US",
        "destination_country": "CA",
        "transaction_type": "wire_transfer"
    }'
```

### 3. Verify Compliance Processing

```bash
# Check compliance processing logs
gcloud logging read "resource.type=\"cloud_function\" AND 
                     resource.labels.function_name=\"compliance-processor\"" \
    --limit=10

# Query transaction compliance status
gcloud spanner databases execute-sql ${SPANNER_DATABASE} \
    --instance=${SPANNER_INSTANCE} \
    --sql="SELECT transaction_id, compliance_status, risk_score FROM transactions LIMIT 5"
```

### 4. Generate Test Compliance Report

```bash
# Get compliance reporter URL
REPORTER_URL=$(gcloud functions describe compliance-reporter \
    --region=${REGION} --format="value(serviceConfig.uri)")

# Generate a test report
curl -X POST ${REPORTER_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "report_type": "daily",
        "jurisdiction": "US"
    }'
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Transaction Volume**: Monitor transaction throughput and processing latency
2. **Compliance Success Rate**: Track percentage of successful compliance checks
3. **Risk Score Distribution**: Monitor distribution of transaction risk scores
4. **System Health**: Monitor Cloud Functions execution success and error rates
5. **Spanner Performance**: Monitor read/write latency and CPU utilization

### Accessing Monitoring Dashboards

```bash
# View the compliance monitoring dashboard
gcloud monitoring dashboards list --filter="displayName:Financial Compliance Monitor"
```

### Log Analysis

```bash
# View compliance audit logs
gcloud logging read "resource.type=\"cloud_function\" AND 
                     jsonPayload.compliance_results IS NOT NULL" \
    --limit=50 --format="table(timestamp,jsonPayload.transaction_id,jsonPayload.compliance_results.compliance_status)"
```

## Security Considerations

### Data Protection
- All data is encrypted at rest using Google Cloud managed encryption keys
- Data in transit is encrypted using TLS 1.2+
- Cloud Spanner provides automatic encryption for all stored data

### Access Control
- Service accounts follow principle of least privilege
- IAM policies restrict access to compliance data
- Function invocation requires appropriate authentication

### Audit Compliance
- All compliance decisions are logged to Cloud Logging
- Immutable audit trails support regulatory requirements
- Comprehensive monitoring tracks all system activities

## Customization

### Modifying Compliance Rules

The compliance rules engine can be customized by editing the Cloud Function source code:

```bash
# Location of compliance rules engine
gcp/global-financial-compliance-monitoring-spanner-tasks/code/functions/compliance-processor/main.py
```

Key areas for customization:
- KYC verification logic
- AML risk scoring algorithms
- Cross-border transaction rules
- Regulatory reporting formats

### Adding New Jurisdictions

To support additional jurisdictions:
1. Update the compliance rules engine with jurisdiction-specific logic
2. Modify the reporting function to generate jurisdiction-specific reports
3. Update the database schema if new regulatory fields are required

### Scaling Configuration

For high-volume environments:
- Increase Spanner node count in variables
- Adjust Cloud Functions memory allocation
- Configure Cloud Tasks queue for higher throughput
- Implement regional Spanner instances for global distribution

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read compliance-processor --region=${REGION}
   ```

2. **Spanner Connection Issues**
   ```bash
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:serviceAccount:*compliance*"
   ```

3. **Compliance Check Failures**
   ```bash
   # Check task queue status
   gcloud tasks queues describe ${TASK_QUEUE} --location=${REGION}
   ```

### Performance Optimization

- Monitor Spanner query performance and optimize as needed
- Adjust Cloud Functions concurrency limits based on workload
- Implement caching for frequently accessed compliance rules
- Consider regional deployment for global workloads

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-monitor
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

After running automated cleanup, verify that all resources have been removed:

```bash
# Check for remaining Spanner instances
gcloud spanner instances list

# Check for remaining Cloud Functions
gcloud functions list --regions=${REGION}

# Check for remaining Cloud Tasks queues
gcloud tasks queues list --location=${REGION}

# Check for remaining storage buckets
gcloud storage buckets list --project=${PROJECT_ID}
```

## Cost Optimization

### Development Environment
- Use minimal Spanner node configuration (1-2 nodes)
- Set appropriate Cloud Functions timeout values
- Configure lifecycle policies for Cloud Storage buckets
- Use preemptible instances where appropriate

### Production Environment
- Implement Cloud Spanner autoscaling
- Use committed use discounts for predictable workloads
- Configure appropriate data retention policies
- Monitor and optimize query performance

## Support and Documentation

### Additional Resources
- [Cloud Spanner Documentation](https://cloud.google.com/spanner/docs)
- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Financial Services on Google Cloud](https://cloud.google.com/solutions/financial-services)

### Getting Help

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud status page for service issues
3. Consult the provider's documentation links above
4. Review Cloud Logging for detailed error messages

### Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate compliance with financial industry standards
3. Ensure security best practices are maintained
4. Update documentation for any configuration changes