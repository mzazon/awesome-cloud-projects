# Infrastructure as Code for Data Pipeline Automation with BigQuery Continuous Queries and Cloud KMS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Pipeline Automation with BigQuery Continuous Queries and Cloud KMS".

## Overview

This solution deploys an intelligent, always-on data processing pipeline that automatically ingests, processes, and enriches streaming data in real-time using BigQuery Continuous Queries with enterprise-grade security through Cloud KMS encryption.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code (HCL)
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following components:

- **Cloud KMS**: Key ring and encryption keys with automatic rotation
- **BigQuery**: Dataset with customer-managed encryption (CMEK)
- **Cloud Pub/Sub**: Topics and subscriptions with encryption
- **Cloud Storage**: Bucket with CMEK encryption and versioning
- **Cloud Functions**: Security audit and data encryption functions
- **Cloud Scheduler**: Automated security operations and audits
- **Cloud Logging**: Comprehensive audit trails and monitoring

## Prerequisites

- Google Cloud project with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Appropriate IAM permissions for:
  - BigQuery Admin
  - Cloud KMS Admin
  - Pub/Sub Admin
  - Storage Admin
  - Cloud Functions Developer
  - Cloud Scheduler Admin
  - Logging Admin
- Terraform (version >= 1.5) for Terraform deployment
- Basic understanding of data pipeline concepts and encryption principles

## Estimated Costs

Initial setup and testing: $50-100 (varies based on data volume and query complexity)

> **Note**: BigQuery Continuous Queries are currently available in select regions. Verify availability in your preferred region before deployment.

## Quick Start

### Using Infrastructure Manager

1. **Set up environment variables**:
   ```bash
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   ```

2. **Deploy the infrastructure**:
   ```bash
   cd infrastructure-manager/
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/data-pipeline \
       --config-file=main.yaml \
       --input-values=project_id=${PROJECT_ID},region=${REGION}
   ```

3. **Verify deployment**:
   ```bash
   gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/data-pipeline
   ```

### Using Terraform

1. **Initialize Terraform**:
   ```bash
   cd terraform/
   terraform init
   ```

2. **Configure variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Plan and apply**:
   ```bash
   terraform plan
   terraform apply
   ```

4. **Verify deployment**:
   ```bash
   terraform output
   ```

### Using Bash Scripts

1. **Set up environment**:
   ```bash
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   chmod +x scripts/deploy.sh
   ```

2. **Deploy the infrastructure**:
   ```bash
   ./scripts/deploy.sh
   ```

3. **Verify deployment**:
   ```bash
   # Check BigQuery dataset
   bq ls ${PROJECT_ID}:
   
   # Check KMS keys
   gcloud kms keys list --location=${REGION} --keyring=pipeline-keyring
   ```

## Configuration Options

### Common Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `dataset_id` | BigQuery dataset name | `streaming_analytics` | No |
| `keyring_name` | KMS key ring name | `pipeline-keyring` | No |
| `key_name` | KMS key name | `data-encryption-key` | No |
| `bucket_name` | Storage bucket name (auto-generated suffix) | `pipeline-data` | No |
| `pubsub_topic` | Pub/Sub topic name (auto-generated suffix) | `streaming-events` | No |
| `enable_monitoring` | Enable comprehensive monitoring | `true` | No |
| `key_rotation_period` | KMS key rotation period | `90d` | No |

### Advanced Configuration

For production deployments, consider customizing:

- **Security Settings**: Modify IAM roles and permissions
- **Monitoring**: Adjust alerting thresholds and notification channels
- **Performance**: Configure BigQuery slot allocation and query optimization
- **Compliance**: Enable additional audit logging and data retention policies

## Validation & Testing

After deployment, validate the infrastructure:

1. **Verify KMS Infrastructure**:
   ```bash
   gcloud kms keyrings list --location=${REGION}
   gcloud kms keys list --location=${REGION} --keyring=pipeline-keyring
   ```

2. **Test BigQuery Dataset Encryption**:
   ```bash
   bq show --format=prettyjson ${PROJECT_ID}:streaming_analytics | grep -A 5 "defaultEncryptionConfiguration"
   ```

3. **Validate Pub/Sub Topic Encryption**:
   ```bash
   gcloud pubsub topics describe streaming-events-* --format="value(kmsKeyName)"
   ```

4. **Test Security Audit Function**:
   ```bash
   gcloud functions call security-audit --data='{"project_id":"'${PROJECT_ID}'","location":"'${REGION}'","keyring_name":"pipeline-keyring"}'
   ```

5. **Verify Continuous Query Setup**:
   ```bash
   bq ls -j --max_results=10 --filter="jobType=QUERY AND state=RUNNING"
   ```

## Monitoring and Maintenance

### Key Metrics to Monitor

- **KMS Key Usage**: Track encryption/decryption operations
- **BigQuery Query Performance**: Monitor continuous query latency and throughput
- **Storage Costs**: Track data volume growth and storage costs
- **Security Audit Results**: Review automated security scan outcomes

### Maintenance Tasks

- **Key Rotation**: Automated 90-day rotation (configurable)
- **Security Audits**: Daily automated security scans
- **Performance Optimization**: Regular query performance reviews
- **Cost Optimization**: Monthly cost analysis and optimization

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify IAM roles and permissions
3. **Region Availability**: Confirm BigQuery Continuous Queries are available in your region
4. **Resource Naming**: Check for naming conflicts with existing resources

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check resource creation status
gcloud logging read "resource.type=\"gce_instance\" OR resource.type=\"bigquery_resource\"" --limit=10

# Monitor function logs
gcloud functions logs read security-audit --limit=50
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/data-pipeline
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Verification

After automated cleanup, verify resource removal:

```bash
# Check BigQuery datasets
bq ls ${PROJECT_ID}:

# Check KMS resources (keys are scheduled for deletion)
gcloud kms keys list --location=${REGION} --keyring=pipeline-keyring

# Check Storage buckets
gsutil ls gs://pipeline-data-*

# Check Pub/Sub topics
gcloud pubsub topics list --filter="name:streaming-events"
```

> **Important**: KMS keys cannot be immediately deleted. They are scheduled for destruction and will be automatically deleted after the specified time period (default: 30 days).

## Security Considerations

### Implemented Security Features

- **Customer-Managed Encryption Keys (CMEK)**: Complete control over encryption keys
- **Hardware Security Modules (HSM)**: Enterprise-grade key protection
- **Automatic Key Rotation**: 90-day rotation policy
- **Column-Level Encryption**: Granular protection for sensitive data
- **Comprehensive Audit Logging**: Complete activity trail
- **VPC Service Controls**: Network-level security (configurable)

### Security Best Practices

1. **Principle of Least Privilege**: Review and minimize IAM permissions
2. **Regular Security Audits**: Monitor automated security scan results
3. **Key Management**: Implement proper key backup and recovery procedures
4. **Network Security**: Consider VPC Service Controls for additional protection
5. **Access Monitoring**: Regularly review access logs and patterns

## Performance Optimization

### Query Performance

- **Slot Management**: Configure BigQuery slot allocation for consistent performance
- **Query Optimization**: Use query labels and performance insights
- **Partitioning**: Implement table partitioning for large datasets
- **Clustering**: Use clustering for frequently filtered columns

### Cost Optimization

- **Storage Classes**: Use appropriate Cloud Storage classes for different data lifecycle stages
- **BigQuery Pricing**: Monitor query costs and optimize expensive operations
- **Resource Scheduling**: Use Cloud Scheduler for non-critical batch operations
- **Data Retention**: Implement appropriate data retention policies

## Compliance and Governance

### Regulatory Compliance

- **GDPR**: Column-level encryption supports data privacy requirements
- **HIPAA**: Enterprise encryption and audit logging meet healthcare standards
- **SOC 2**: Comprehensive monitoring and access controls
- **PCI DSS**: Encryption and access management for payment data

### Data Governance

- **Data Lineage**: Track data flow through BigQuery audit logs
- **Access Controls**: Implement fine-grained IAM policies
- **Data Classification**: Use BigQuery labels for data classification
- **Retention Policies**: Automated data lifecycle management

## Support and Documentation

### Additional Resources

- [BigQuery Continuous Queries Documentation](https://cloud.google.com/bigquery/docs/continuous-queries-introduction)
- [Cloud KMS Best Practices](https://cloud.google.com/kms/docs/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Consult the original recipe documentation
4. Contact your Google Cloud support team for production issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Google Cloud best practices
3. Update documentation for any configuration changes
4. Ensure compatibility across all deployment methods

---

**Note**: This infrastructure code implements the complete solution described in the recipe "Data Pipeline Automation with BigQuery Continuous Queries and Cloud KMS". For detailed implementation steps and architectural explanations, refer to the original recipe documentation.