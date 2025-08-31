# Task Queue System with Cloud Tasks and Functions - Terraform Infrastructure

This Terraform configuration deploys a complete task queue system on Google Cloud Platform using Cloud Tasks and Cloud Functions, following the recipe "Task Queue System with Cloud Tasks and Functions".

## Architecture Overview

The infrastructure includes:

- **Cloud Tasks Queue**: Managed queue service with retry logic and rate limiting
- **Cloud Function**: Serverless task processor with HTTP trigger
- **Cloud Storage**: Bucket for processed files and audit logs
- **IAM Service Account**: Dedicated service account with least privilege permissions
- **Monitoring**: Optional alerting and dashboard configuration
- **Dead Letter Queue**: Optional queue for failed tasks

## Prerequisites

- Google Cloud Platform account with billing enabled
- Terraform >= 1.0 installed
- `gcloud` CLI installed and authenticated
- Appropriate IAM permissions for resource creation

Required APIs will be automatically enabled by this configuration:
- Cloud Functions API
- Cloud Tasks API
- Cloud Build API
- Cloud Storage API
- Cloud Logging API
- Cloud Monitoring API

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd gcp/task-queue-system-tasks-functions/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Configure Variables** (create `terraform.tfvars`):
   ```hcl
   project_id = "your-gcp-project-id"
   region     = "us-central1"
   
   # Optional customizations
   queue_name                               = "my-background-tasks"
   function_name                            = "my-task-processor"
   notification_email                       = "admin@yourcompany.com"
   enable_monitoring                        = true
   allow_unauthenticated_function_invocation = true
   
   labels = {
     environment = "production"
     team        = "backend"
     cost_center = "engineering"
   }
   ```

4. **Plan and Apply**:
   ```bash
   terraform plan
   terraform apply
   ```

5. **Test the System**:
   ```bash
   # Use the generated task creation script
   python create_task.py process_file --filename="test.txt" --content="Hello World"
   
   # Or use gcloud CLI directly
   gcloud tasks create-http-task test-task-$(date +%s) \
     --queue=background-tasks \
     --location=us-central1 \
     --url=$(terraform output -raw function_url) \
     --method=POST \
     --header=Content-Type:application/json \
     --body-content='{"task_type":"process_file","filename":"example.txt","content":"Sample content"}'
   ```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |

### Task Queue Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `queue_name` | Cloud Tasks queue name | `background-tasks` |
| `queue_max_attempts` | Maximum retry attempts | `3` |
| `queue_max_retry_duration` | Maximum retry duration | `300s` |
| `queue_max_doublings` | Maximum retry doublings | `5` |

### Cloud Function Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `function_name` | Cloud Function name | `task-processor` |
| `function_memory` | Memory allocation | `256M` |
| `function_timeout` | Timeout in seconds | `60` |
| `function_runtime` | Runtime environment | `python311` |

### Storage Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `bucket_name_prefix` | Bucket name prefix | `""` (uses project ID) |
| `bucket_storage_class` | Storage class | `STANDARD` |
| `bucket_lifecycle_age` | Object lifecycle age in days | `30` |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_monitoring` | Enable monitoring resources | `true` |
| `notification_email` | Email for alerts | `""` |

### Feature Flags

| Variable | Description | Default |
|----------|-------------|---------|
| `create_sample_tasks` | Create task creation script | `true` |
| `enable_dead_letter_queue` | Create dead letter queue | `false` |
| `allow_unauthenticated_function_invocation` | Allow public function access | `true` |

## Outputs

After successful deployment, Terraform provides various outputs:

```bash
# View all outputs
terraform output

# Get specific values
terraform output function_url
terraform output storage_bucket_name
terraform output environment_variables
```

Key outputs include:
- `function_url`: Cloud Function HTTP trigger URL
- `queue_name`: Created queue name
- `storage_bucket_name`: Results storage bucket
- `task_creation_command`: Example gcloud command
- `python_client_example`: Python code example
- `validation_commands`: Commands to verify deployment

## Task Types Supported

The deployed Cloud Function supports multiple task types:

### 1. File Processing Tasks
```json
{
  "task_type": "process_file",
  "filename": "document.pdf",
  "content": "File content to process",
  "content_type": "application/pdf"
}
```

### 2. Email Tasks (Simulated)
```json
{
  "task_type": "send_email",
  "recipient": "user@example.com",
  "subject": "Task Complete",
  "body": "Your task has been processed"
}
```

### 3. Data Transformation Tasks
```json
{
  "task_type": "data_transform",
  "transform_type": "json_flatten",
  "input_data": {"nested": {"data": "value"}}
}
```

### 4. Webhook Notifications
```json
{
  "task_type": "webhook_notification",
  "webhook_url": "https://api.example.com/notify",
  "payload": {"event": "task_complete"}
}
```

## Monitoring and Observability

When `enable_monitoring` is true, the configuration creates:

1. **Monitoring Dashboard**: Custom dashboard showing:
   - Queue depth over time
   - Function invocations per second
   - Function execution time
   - Storage bucket object count

2. **Alert Policies**:
   - High queue depth alert (> 100 tasks)
   - Function error rate alert (> 5 errors/minute)

3. **Access Monitoring**:
   ```bash
   # View dashboard
   echo "$(terraform output monitoring_dashboard_url)"
   
   # Check queue metrics
   gcloud logging read 'resource.type="cloud_tasks_queue"' --limit=10
   
   # View function logs
   gcloud functions logs read $(terraform output -raw function_name) --gen2 --region=$(terraform output -raw region)
   ```

## Security Considerations

### IAM and Permissions
- Dedicated service account with minimal required permissions
- Cloud Tasks service account granted function invoker role
- Uniform bucket-level access enabled for storage security

### Network Security
- Function allows ingress from all sources (required for Cloud Tasks)
- Optional authentication can be enabled by setting `allow_unauthenticated_function_invocation = false`

### Data Security
- All data encrypted at rest and in transit
- Structured logging without sensitive data exposure
- Audit logs stored in Cloud Storage with retention policies

## Cost Optimization

### Estimated Costs (USD/month)
- **Cloud Functions**: ~$0.01-5.00 (depending on invocations)
- **Cloud Tasks**: ~$0.40/million operations
- **Cloud Storage**: ~$0.50-2.00 (depending on data volume)
- **Cloud Monitoring**: Free tier covers most usage

### Cost Controls
- Function timeout limits resource consumption
- Storage lifecycle rules automatically delete old files
- Queue rate limits prevent cost spikes
- Monitoring alerts help identify unexpected usage

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   gcloud services enable cloudfunctions.googleapis.com cloudtasks.googleapis.com
   ```

2. **IAM Permissions**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id)
   ```

3. **Function Deployment Fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   gcloud builds log <BUILD_ID>
   ```

4. **Tasks Not Processing**:
   ```bash
   # Check queue status
   gcloud tasks queues describe $(terraform output -raw queue_name) --location=$(terraform output -raw region)
   
   # Check function logs
   gcloud functions logs read $(terraform output -raw function_name) --gen2
   ```

### Debugging Commands

```bash
# Test function directly
curl -X POST $(terraform output -raw function_url) \
  -H "Content-Type: application/json" \
  -d '{"task_type":"process_file","filename":"test.txt","content":"debug test"}'

# List storage bucket contents
gsutil ls -la gs://$(terraform output -raw storage_bucket_name)/

# Monitor queue in real-time
watch -n 5 'gcloud tasks list --queue=$(terraform output -raw queue_name) --location=$(terraform output -raw region)'
```

## Customization and Extension

### Adding New Task Types

1. **Modify Function Code**: Edit `function_code_template/main.py` to add new task handlers
2. **Update Script**: Modify `scripts_template/create_task.py` to support new task types
3. **Redeploy**: Run `terraform apply` to update the function

### Scaling Configuration

```hcl
# High-throughput configuration
queue_max_attempts        = 5
queue_max_retry_duration = "600s"
function_memory          = "1024M"
function_timeout         = 300

# Production monitoring
enable_monitoring    = true
notification_email   = "alerts@yourcompany.com"
enable_audit_logs   = true
```

### Multi-Environment Setup

```bash
# Development
terraform workspace new dev
terraform apply -var-file="environments/dev.tfvars"

# Production
terraform workspace new prod
terraform apply -var-file="environments/prod.tfvars"
```

## Cleanup

### Complete Cleanup
```bash
terraform destroy
```

### Manual Cleanup (if needed)
```bash
# Delete remaining storage objects
gsutil -m rm -r gs://$(terraform output -raw storage_bucket_name)

# Delete Cloud Build artifacts
gcloud builds list --filter="status=SUCCESS" --format="value(id)" | head -10 | xargs -I {} gcloud builds cancel {}
```

## Support and Resources

- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Original Recipe](../../../task-queue-system-tasks-functions.md)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any new variables or outputs
3. Validate with `terraform plan` and `terraform validate`
4. Submit changes with clear descriptions

---

*This infrastructure code was generated for the recipe "Task Queue System with Cloud Tasks and Functions" and follows Google Cloud and Terraform best practices.*