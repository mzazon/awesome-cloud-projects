# Real-Time Fleet Optimization Infrastructure

This Terraform configuration deploys a complete real-time fleet optimization system on Google Cloud Platform using Cloud Fleet Routing API, Cloud Bigtable, Pub/Sub, and Cloud Functions.

## Architecture Overview

The infrastructure creates a scalable, real-time fleet optimization platform with the following components:

- **Cloud Bigtable**: High-performance NoSQL database for storing historical traffic patterns and vehicle location data
- **Pub/Sub**: Real-time message processing for fleet events and optimization requests
- **Cloud Functions**: Serverless processing for location updates, route optimization, and dashboard
- **Cloud Fleet Routing API**: Google's advanced optimization algorithms for vehicle routing
- **Secret Manager**: Secure storage for API keys and sensitive configuration
- **Cloud KMS**: Customer-managed encryption keys for data at rest
- **Cloud Monitoring**: Alerting and performance monitoring

## Features

### Real-Time Processing
- Vehicle location tracking and storage
- Traffic condition monitoring and analysis
- Automatic route optimization triggers
- Event-driven architecture with Pub/Sub

### Advanced Optimization
- Integration with Google Cloud Fleet Routing API
- Historical traffic data analysis
- Multi-objective optimization (time, distance, cost)
- Batch processing for large fleets

### Monitoring and Management
- Web-based fleet management dashboard
- Real-time system health monitoring
- Performance metrics and alerting
- Comprehensive audit logging

### Security and Compliance
- Customer-managed encryption keys
- IAM roles with least privilege
- VPC security controls
- Audit logging for compliance

## Prerequisites

### Required Tools
- [Terraform](https://terraform.io/downloads) >= 1.5.0
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- [cbt tool](https://cloud.google.com/bigtable/docs/cbt-overview) for Bigtable management

### Google Cloud Setup
1. Create a Google Cloud Project
2. Enable billing for the project
3. Install and authenticate gcloud CLI:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```

### Required Permissions
Your Google Cloud user or service account needs the following IAM roles:
- `roles/owner` (or combination of individual roles below)
- `roles/bigtable.admin`
- `roles/pubsub.admin`
- `roles/cloudfunctions.admin`
- `roles/storage.admin`
- `roles/cloudkms.admin`
- `roles/secretmanager.admin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/iam.serviceAccountAdmin`
- `roles/resourcemanager.projectIamAdmin`

## Quick Start

### 1. Configure Variables
```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration
vim terraform.tfvars
```

At minimum, update these required variables:
```hcl
project_id = "your-fleet-optimization-project"
region     = "us-central1"
zone       = "us-central1-a"
```

### 2. Configure API Key (Optional)
For Google Maps Platform integration, either:
- Set environment variable: `export TF_VAR_maps_api_key="your-api-key"`
- Or configure in terraform.tfvars: `maps_api_key = "your-api-key"`

### 3. Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment
```bash
# Check system health
curl $(terraform output -raw function_urls.dashboard)/health

# Open the fleet dashboard
open $(terraform output -raw function_urls.dashboard)

# Test Bigtable connection
gcloud bigtable instances list

# Test Pub/Sub topics
gcloud pubsub topics list
```

## Configuration

### Environment-Specific Configurations

#### Development Environment
```hcl
environment = "development"
bigtable_min_nodes = 1
bigtable_max_nodes = 3
enable_bigtable_replication = false
max_function_instances = 10
dashboard_public_access = true
enable_debug_logging = true
simulate_traffic_events = true
```

#### Production Environment
```hcl
environment = "production"
bigtable_min_nodes = 3
bigtable_max_nodes = 10
enable_bigtable_replication = true
max_function_instances = 100
dashboard_public_access = false
enable_monitoring_alerts = true
enable_audit_logging = true
enable_high_availability = true
```

### Key Configuration Options

| Variable | Description | Default | Recommended for Production |
|----------|-------------|---------|---------------------------|
| `bigtable_min_nodes` | Minimum Bigtable nodes | 3 | 3+ |
| `enable_bigtable_replication` | Enable multi-region replication | false | true |
| `dashboard_public_access` | Allow public dashboard access | false | false |
| `enable_monitoring_alerts` | Enable monitoring alerts | true | true |
| `data_retention_days` | Days to retain data | 30 | 30-90 |
| `enable_kms_encryption` | Use customer-managed keys | true | true |

## Usage

### Publishing Vehicle Location Events
```python
from google.cloud import pubsub_v1
import json

publisher = pubsub_v1.PublisherClient()
topic_path = "projects/YOUR_PROJECT/topics/fleet-events-SUFFIX"

location_data = {
    "vehicle_id": "vehicle-001",
    "latitude": 37.7749,
    "longitude": -122.4194,
    "timestamp": 1703721600,
    "speed": 45.5,
    "road_segment": "highway-101-north"
}

future = publisher.publish(topic_path, json.dumps(location_data).encode())
```

### Requesting Route Optimization
```python
optimization_request = {
    "vehicles": [
        {
            "vehicle_id": "truck-001",
            "start_location": {"latitude": 37.7749, "longitude": -122.4194},
            "capacity": 1000
        }
    ],
    "shipments": [
        {
            "shipment_id": "delivery-001",
            "pickup_location": {"latitude": 37.7849, "longitude": -122.4094},
            "delivery_location": {"latitude": 37.7649, "longitude": -122.4294},
            "weight": 100
        }
    ]
}

topic_path = "projects/YOUR_PROJECT/topics/route-optimization-requests-SUFFIX"
publisher.publish(topic_path, json.dumps(optimization_request).encode())
```

### Querying Bigtable Data
```bash
# List tables
cbt -project=YOUR_PROJECT -instance=INSTANCE_NAME ls

# Read traffic data
cbt -project=YOUR_PROJECT -instance=INSTANCE_NAME \
    read traffic_patterns start=highway-101# count=10

# Read vehicle locations
cbt -project=YOUR_PROJECT -instance=INSTANCE_NAME \
    read vehicle_locations start=vehicle-001# count=5
```

## Monitoring and Maintenance

### Dashboard Access
The fleet management dashboard provides real-time monitoring:
- Vehicle locations and status
- Traffic conditions
- Recent route optimizations
- System health metrics

Access URL: Available in Terraform outputs as `function_urls.dashboard`

### Health Checks
```bash
# System health endpoint
curl https://FUNCTION_URL/health

# API endpoints
curl https://FUNCTION_URL/api/vehicles
curl https://FUNCTION_URL/api/traffic
curl https://FUNCTION_URL/api/routes
curl https://FUNCTION_URL/api/metrics
```

### Log Monitoring
```bash
# Function logs
gcloud functions logs read location-processor-SUFFIX --limit=50
gcloud functions logs read route-optimizer-SUFFIX --limit=50

# Pub/Sub monitoring
gcloud pubsub subscriptions list
gcloud pubsub topics list-subscriptions TOPIC_NAME
```

### Performance Tuning

#### Bigtable Optimization
- Monitor CPU utilization and adjust node count
- Review query patterns and optimize row key design
- Configure garbage collection policies for data lifecycle

#### Function Optimization
- Adjust memory allocation based on workload
- Monitor cold start times and concurrency
- Optimize code for better performance

#### Cost Optimization
- Enable data lifecycle management
- Use appropriate storage classes
- Monitor and adjust resource allocation
- Implement budget alerts

## Troubleshooting

### Common Issues

#### Deployment Failures
```bash
# Check API enablement
gcloud services list --enabled

# Verify permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID

# Check quotas
gcloud compute project-info describe --project=YOUR_PROJECT_ID
```

#### Function Errors
```bash
# Check function logs
gcloud functions logs read FUNCTION_NAME --limit=100

# Test function locally
functions-framework --target=process_location --source=function_source/
```

#### Bigtable Connection Issues
```bash
# Test Bigtable connectivity
cbt -project=YOUR_PROJECT -instance=INSTANCE_NAME ls

# Check instance status
gcloud bigtable instances describe INSTANCE_NAME
```

#### Pub/Sub Message Processing
```bash
# Check subscription status
gcloud pubsub subscriptions describe SUBSCRIPTION_NAME

# Pull messages manually
gcloud pubsub subscriptions pull SUBSCRIPTION_NAME --limit=5
```

### Debug Mode
Enable debug logging for detailed troubleshooting:
```hcl
enable_debug_logging = true
```

## Security Considerations

### Data Protection
- All data is encrypted at rest using Cloud KMS
- Bigtable tables use customer-managed encryption keys
- Secret Manager stores sensitive API keys securely

### Network Security
- Functions use internal-only ingress settings
- Bigtable clusters are in private networks
- API access controlled through IAM

### Access Control
- Service accounts follow least privilege principle
- IAM roles are granularly assigned
- Dashboard access can be restricted to internal networks

### Compliance
- Audit logging enabled for all API calls
- Data retention policies configured
- Encryption key rotation automated

## Scaling

### Horizontal Scaling
- Bigtable autoscaling based on CPU utilization
- Cloud Functions auto-scale based on demand
- Pub/Sub handles message bursts automatically

### Vertical Scaling
- Increase function memory allocation for complex optimizations
- Add more Bigtable nodes for higher throughput
- Adjust batch sizes for optimization requests

### Multi-Region Deployment
Enable high availability with:
```hcl
enable_high_availability = true
enable_bigtable_replication = true
```

## Cost Management

### Resource Optimization
- Start with minimum Bigtable nodes and scale up
- Use appropriate Cloud Function memory allocation
- Implement data lifecycle policies

### Monitoring Costs
- Set up budget alerts in Google Cloud Console
- Monitor resource usage with Cloud Monitoring
- Review and optimize regularly

### Estimated Costs (Monthly)
- **Development**: $50-100
- **Staging**: $200-500
- **Production**: $500-2000

*Costs vary based on fleet size, optimization frequency, and data volume*

## Cleanup

### Destroy Infrastructure
```bash
# Destroy all resources (WARNING: This deletes all data)
terraform destroy

# Remove specific resources
terraform destroy -target=google_bigtable_instance.fleet_data
```

### Partial Cleanup
```bash
# Delete only function deployments
terraform destroy -target=google_cloudfunctions2_function.location_processor
terraform destroy -target=google_cloudfunctions2_function.route_optimizer
```

## Support and Contributing

### Getting Help
1. Check the [Google Cloud Documentation](https://cloud.google.com/docs)
2. Review [Cloud Fleet Routing API docs](https://cloud.google.com/optimization/docs/routing)
3. File issues in the project repository
4. Contact your cloud architecture team

### Contributing
1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request

## License

This infrastructure code is provided under the Apache 2.0 License. See LICENSE file for details.

---

**Note**: This infrastructure code is designed for production use but should be thoroughly tested in a development environment before deploying to production systems.