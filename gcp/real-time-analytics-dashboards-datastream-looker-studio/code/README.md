# Infrastructure as Code for Real-Time Analytics Dashboards with Datastream and Looker Studio

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Analytics Dashboards with Datastream and Looker Studio".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Datastream Admin (`roles/datastream.admin`)
  - BigQuery Admin (`roles/bigquery.admin`)
  - Project IAM Admin (`roles/resourcemanager.projectIamAdmin`)
  - Service Usage Admin (`roles/serviceusage.serviceUsageAdmin`)
- Source database (MySQL 5.7+, PostgreSQL 10+, Oracle 11g+, or SQL Server 2016+) with:
  - Binary logging enabled (MySQL) or logical replication (PostgreSQL)
  - Datastream user with appropriate permissions
  - Network connectivity from Google Cloud (public IP, VPN, or Private Service Connect)

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SOURCE_DB_HOST="your-database-host"
export SOURCE_DB_USER="datastream_user"
export SOURCE_DB_PASSWORD="your-secure-password"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/analytics-pipeline \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source=infrastructure-manager/ \
    --inputs-file=infrastructure-manager/inputs.yaml \
    --labels=environment=production,purpose=analytics
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Configure variables (copy and edit the example file)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SOURCE_DB_HOST="your-database-host"
export SOURCE_DB_USER="datastream_user"
export SOURCE_DB_PASSWORD="your-secure-password"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration

### Environment Variables

The following environment variables are required for deployment:

| Variable | Description | Example |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud project ID | `analytics-demo-123456` |
| `REGION` | Google Cloud region for resources | `us-central1` |
| `SOURCE_DB_HOST` | Source database hostname/IP | `10.0.0.10` |
| `SOURCE_DB_PORT` | Source database port | `3306` (MySQL) or `5432` (PostgreSQL) |
| `SOURCE_DB_USER` | Database user for Datastream | `datastream_user` |
| `SOURCE_DB_PASSWORD` | Database password | `your-secure-password` |
| `SOURCE_DB_TYPE` | Database type | `mysql`, `postgresql`, `oracle`, or `sqlserver` |
| `DATABASE_NAME` | Source database name | `ecommerce_db` |

### Optional Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `DATASET_NAME` | BigQuery dataset name | `ecommerce_analytics` |
| `STREAM_NAME` | Datastream name | `sales-stream` |
| `TABLES_TO_REPLICATE` | Comma-separated list of tables | `sales_orders,customers,products` |

### Terraform Variables

When using Terraform, configure variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
source_db_host = "your-database-host"
source_db_port = 3306
source_db_user = "datastream_user"
source_db_password = "your-secure-password"
source_db_type = "mysql"
database_name = "ecommerce_db"
dataset_name = "ecommerce_analytics"
stream_name = "sales-stream"
tables_to_replicate = ["sales_orders", "customers", "products"]
```

## Post-Deployment Steps

After infrastructure deployment, complete these manual steps:

### 1. Configure Source Database

For MySQL:
```sql
-- Enable binary logging (if not already enabled)
SET GLOBAL log_bin = ON;
SET GLOBAL binlog_format = 'ROW';
SET GLOBAL binlog_row_image = 'FULL';

-- Create Datastream user
CREATE USER 'datastream_user'@'%' IDENTIFIED BY 'your-secure-password';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'datastream_user'@'%';
FLUSH PRIVILEGES;
```

For PostgreSQL:
```sql
-- Enable logical replication
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;
-- Restart PostgreSQL

-- Create Datastream user
CREATE USER datastream_user WITH REPLICATION PASSWORD 'your-secure-password';
GRANT CONNECT ON DATABASE ecommerce_db TO datastream_user;
GRANT USAGE ON SCHEMA public TO datastream_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream_user;
```

### 2. Start Datastream Replication

```bash
# Start the Datastream (if not automatically started)
gcloud datastream streams start ${STREAM_NAME} --location=${REGION}

# Monitor stream status
gcloud datastream streams describe ${STREAM_NAME} --location=${REGION}
```

### 3. Create Looker Studio Dashboard

1. Navigate to [Looker Studio](https://lookerstudio.google.com/)
2. Click "Create" > "Report"
3. Select "BigQuery" as data source
4. Choose your project and the `ecommerce_analytics` dataset
5. Select the `daily_sales_summary` view or other analytical views
6. Create visualizations for:
   - Daily revenue trends (time series)
   - Total revenue, orders, customers (scorecards)
   - Top products by sales (bar chart)
   - Recent orders (table)
   - Sales by region (geo map)

## Validation

### Verify Infrastructure Deployment

```bash
# Check enabled APIs
gcloud services list --enabled --filter="name:(datastream OR bigquery)"

# Verify BigQuery dataset
bq ls ${DATASET_NAME}

# Check Datastream connection profiles
gcloud datastream connection-profiles list --location=${REGION}

# Verify Datastream status
gcloud datastream streams describe ${STREAM_NAME} --location=${REGION} \
    --format="table(state,backfillAll.completed)"
```

### Test Data Replication

```bash
# Check replicated data in BigQuery
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as total_records, 
            MAX(_metadata_timestamp) as latest_update
     FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_orders\`"

# Verify analytical views
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.daily_sales_summary\` 
     ORDER BY sales_date DESC LIMIT 5"
```

### Monitor Data Freshness

```bash
# Check replication lag
bq query --use_legacy_sql=false \
    "SELECT 
        TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(_metadata_timestamp), SECOND) as seconds_behind
     FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_orders\`"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/analytics-pipeline
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

### Manual Cleanup

Some resources may require manual cleanup:

```bash
# Delete Looker Studio reports manually at https://lookerstudio.google.com/
# Remove any custom IAM bindings if created manually
# Clean up any additional BigQuery datasets created during testing
```

## Cost Optimization

### BigQuery Cost Management

- Enable query cost controls and set daily spending limits
- Use partitioned tables for time-based queries
- Implement BI Engine for frequently accessed data
- Set up data retention policies for old data

### Datastream Cost Optimization

- Monitor throughput and adjust concurrent task limits
- Use appropriate replication modes (full vs. CDC only)
- Implement table-level filtering to reduce unnecessary data transfer

### Looker Studio Performance

- Use BI Engine acceleration for better performance
- Implement data extracts for complex calculations
- Optimize dashboard design to minimize query complexity

## Troubleshooting

### Common Issues

1. **Datastream Connection Failures**:
   - Verify database connectivity and firewall rules
   - Check database user permissions
   - Validate binary logging/logical replication settings

2. **BigQuery Schema Issues**:
   - Monitor Datastream error logs
   - Check for unsupported data types
   - Verify table and column naming conventions

3. **Dashboard Performance**:
   - Enable BI Engine for your dataset
   - Optimize SQL queries in analytical views
   - Consider materializing frequently accessed aggregations

### Monitoring and Alerting

Set up monitoring for:
- Datastream replication lag
- BigQuery query performance
- Dashboard load times
- Data quality metrics

## Security Considerations

- Use least privilege IAM roles
- Enable audit logging for all services
- Implement VPC Service Controls if required
- Use Customer-Managed Encryption Keys (CMEK) for sensitive data
- Configure private connectivity for database access
- Implement row-level security in BigQuery for sensitive data

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review Google Cloud Datastream documentation
3. Consult BigQuery best practices guide
4. Reference Looker Studio developer documentation
5. Contact your Google Cloud support representative

## Additional Resources

- [Google Cloud Datastream Documentation](https://cloud.google.com/datastream/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Looker Studio Help](https://support.google.com/looker-studio)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)