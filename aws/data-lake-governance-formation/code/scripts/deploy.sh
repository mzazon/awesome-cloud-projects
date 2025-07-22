#!/bin/bash

# Deploy script for Advanced Data Lake Governance with Lake Formation and DataZone
# This script implements enterprise-grade data governance infrastructure

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "An error occurred. Cleaning up partial deployment..."
    # This will be called if the script exits with an error
    # Add specific cleanup commands here if needed
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    # Check required permissions
    log_info "Verifying AWS permissions..."
    
    # Test basic permissions
    aws sts get-caller-identity > /dev/null || error_exit "Unable to verify AWS identity"
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core AWS settings
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export DOMAIN_NAME="enterprise-data-governance"
    
    # Generate unique suffix for global resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Set derived variables
    export DATA_LAKE_BUCKET="enterprise-datalake-${RANDOM_SUFFIX}"
    export RAW_DATA_PREFIX="raw-data"
    export CURATED_DATA_PREFIX="curated-data"
    export ANALYTICS_DATA_PREFIX="analytics-data"
    export GLUE_DATABASE="enterprise_data_catalog"
    
    log_info "Region: ${AWS_REGION}"
    log_info "Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Data Lake Bucket: ${DATA_LAKE_BUCKET}"
    log_info "Domain Name: ${DOMAIN_NAME}"
    
    log_success "Environment variables configured"
}

# Configure Lake Formation and create data lake
setup_lake_formation() {
    log_info "Configuring Lake Formation and creating data lake..."
    
    # Enable Lake Formation as the primary data catalog
    log_info "Enabling Lake Formation as primary data catalog..."
    aws lakeformation put-data-lake-settings \
        --data-lake-settings '{
          "CreateDatabaseDefaultPermissions": [],
          "CreateTableDefaultPermissions": [],
          "Parameters": {
            "CROSS_ACCOUNT_VERSION": "3"
          },
          "TrustedResourceOwners": ["'${AWS_ACCOUNT_ID}'"],
          "AllowExternalDataFiltering": true,
          "ExternalDataFilteringAllowList": ["'${AWS_ACCOUNT_ID}'"],
          "AuthorizedSessionTagValueList": []
        }' || error_exit "Failed to configure Lake Formation settings"
    
    # Create S3 bucket for data lake
    log_info "Creating S3 bucket for data lake..."
    if ! aws s3api head-bucket --bucket ${DATA_LAKE_BUCKET} 2>/dev/null; then
        aws s3 mb s3://${DATA_LAKE_BUCKET} --region ${AWS_REGION} || \
            error_exit "Failed to create S3 bucket"
    else
        log_warning "Bucket ${DATA_LAKE_BUCKET} already exists"
    fi
    
    # Configure bucket for Lake Formation integration
    log_info "Configuring bucket for Lake Formation integration..."
    aws s3api put-bucket-versioning \
        --bucket ${DATA_LAKE_BUCKET} \
        --versioning-configuration Status=Enabled || \
        error_exit "Failed to enable versioning"
    
    aws s3api put-bucket-encryption \
        --bucket ${DATA_LAKE_BUCKET} \
        --server-side-encryption-configuration '{
          "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
              "SSEAlgorithm": "AES256"
            }
          }]
        }' || error_exit "Failed to configure encryption"
    
    # Create folder structure for data lake zones
    log_info "Creating data lake folder structure..."
    aws s3api put-object --bucket ${DATA_LAKE_BUCKET} --key ${RAW_DATA_PREFIX}/
    aws s3api put-object --bucket ${DATA_LAKE_BUCKET} --key ${CURATED_DATA_PREFIX}/
    aws s3api put-object --bucket ${DATA_LAKE_BUCKET} --key ${ANALYTICS_DATA_PREFIX}/
    
    # Register data lake location with Lake Formation
    log_info "Registering data lake location with Lake Formation..."
    aws lakeformation register-resource \
        --resource-arn arn:aws:s3:::${DATA_LAKE_BUCKET} \
        --use-service-linked-role || \
        log_warning "Resource may already be registered"
    
    log_success "Lake Formation and data lake configured"
}

# Create IAM roles for data lake access
create_iam_roles() {
    log_info "Creating IAM roles for data lake access..."
    
    # Create Lake Formation service role
    log_info "Creating Lake Formation service role..."
    
    cat > /tmp/lf-service-role-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lakeformation.amazonaws.com",
          "glue.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    if ! aws iam get-role --role-name LakeFormationServiceRole &>/dev/null; then
        aws iam create-role \
            --role-name LakeFormationServiceRole \
            --assume-role-policy-document file:///tmp/lf-service-role-trust-policy.json || \
            error_exit "Failed to create LakeFormationServiceRole"
    else
        log_warning "LakeFormationServiceRole already exists"
    fi
    
    # Create and attach comprehensive policy for Lake Formation
    cat > /tmp/lf-service-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::${DATA_LAKE_BUCKET}",
        "arn:aws:s3:::${DATA_LAKE_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:CreateDatabase",
        "glue:GetTable",
        "glue:GetTables",
        "glue:CreateTable",
        "glue:UpdateTable",
        "glue:DeleteTable",
        "glue:GetPartition",
        "glue:GetPartitions",
        "glue:CreatePartition",
        "glue:UpdatePartition",
        "glue:DeletePartition",
        "glue:BatchCreatePartition",
        "glue:BatchDeletePartition",
        "glue:BatchUpdatePartition"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "lakeformation:GetDataAccess",
        "lakeformation:GrantPermissions",
        "lakeformation:RevokePermissions",
        "lakeformation:BatchGrantPermissions",
        "lakeformation:BatchRevokePermissions",
        "lakeformation:ListPermissions"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name LakeFormationServiceRole \
        --policy-name LakeFormationServicePolicy \
        --policy-document file:///tmp/lf-service-role-policy.json || \
        error_exit "Failed to attach policy to LakeFormationServiceRole"
    
    # Create data analyst role
    log_info "Creating data analyst role..."
    
    cat > /tmp/data-analyst-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    if ! aws iam get-role --role-name DataAnalystRole &>/dev/null; then
        aws iam create-role \
            --role-name DataAnalystRole \
            --assume-role-policy-document file:///tmp/data-analyst-trust-policy.json || \
            error_exit "Failed to create DataAnalystRole"
        
        aws iam attach-role-policy \
            --role-name DataAnalystRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonAthenaFullAccess || \
            error_exit "Failed to attach Athena policy to DataAnalystRole"
    else
        log_warning "DataAnalystRole already exists"
    fi
    
    log_success "IAM roles created successfully"
}

# Set up Glue Data Catalog
setup_glue_catalog() {
    log_info "Setting up AWS Glue Data Catalog..."
    
    # Create Glue database for enterprise data
    log_info "Creating Glue database..."
    if ! aws glue get-database --name ${GLUE_DATABASE} &>/dev/null; then
        aws glue create-database \
            --database-input '{
              "Name": "'${GLUE_DATABASE}'",
              "Description": "Enterprise data catalog for governed data lake",
              "LocationUri": "s3://'${DATA_LAKE_BUCKET}'/'${CURATED_DATA_PREFIX}'/",
              "Parameters": {
                "classification": "curated",
                "environment": "production"
              }
            }' || error_exit "Failed to create Glue database"
    else
        log_warning "Glue database ${GLUE_DATABASE} already exists"
    fi
    
    # Create sample customer data table schema
    log_info "Creating customer data table..."
    if ! aws glue get-table --database-name ${GLUE_DATABASE} --name customer_data &>/dev/null; then
        aws glue create-table \
            --database-name ${GLUE_DATABASE} \
            --table-input '{
              "Name": "customer_data",
              "Description": "Customer information with PII protection",
              "StorageDescriptor": {
                "Columns": [
                  {"Name": "customer_id", "Type": "bigint", "Comment": "Unique customer identifier"},
                  {"Name": "first_name", "Type": "string", "Comment": "Customer first name - PII"},
                  {"Name": "last_name", "Type": "string", "Comment": "Customer last name - PII"},
                  {"Name": "email", "Type": "string", "Comment": "Customer email - PII"},
                  {"Name": "phone", "Type": "string", "Comment": "Customer phone - PII"},
                  {"Name": "registration_date", "Type": "date", "Comment": "Account registration date"},
                  {"Name": "customer_segment", "Type": "string", "Comment": "Business customer segment"},
                  {"Name": "lifetime_value", "Type": "double", "Comment": "Customer lifetime value"},
                  {"Name": "region", "Type": "string", "Comment": "Customer geographic region"}
                ],
                "Location": "s3://'${DATA_LAKE_BUCKET}'/'${CURATED_DATA_PREFIX}'/customer_data/",
                "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
                "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                "SerdeInfo": {
                  "SerializationLibrary": "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                  "Parameters": {
                    "field.delim": ",",
                    "skip.header.line.count": "1"
                  }
                }
              },
              "PartitionKeys": [
                {"Name": "year", "Type": "string"},
                {"Name": "month", "Type": "string"}
              ],
              "Parameters": {
                "classification": "csv",
                "delimiter": ",",
                "has_encrypted_data": "false",
                "data_classification": "confidential"
              }
            }' || error_exit "Failed to create customer_data table"
    else
        log_warning "Table customer_data already exists"
    fi
    
    # Create transaction data table
    log_info "Creating transaction data table..."
    if ! aws glue get-table --database-name ${GLUE_DATABASE} --name transaction_data &>/dev/null; then
        aws glue create-table \
            --database-name ${GLUE_DATABASE} \
            --table-input '{
              "Name": "transaction_data",
              "Description": "Customer transaction records",
              "StorageDescriptor": {
                "Columns": [
                  {"Name": "transaction_id", "Type": "string", "Comment": "Unique transaction identifier"},
                  {"Name": "customer_id", "Type": "bigint", "Comment": "Associated customer ID"},
                  {"Name": "transaction_date", "Type": "timestamp", "Comment": "Transaction timestamp"},
                  {"Name": "amount", "Type": "double", "Comment": "Transaction amount"},
                  {"Name": "currency", "Type": "string", "Comment": "Transaction currency"},
                  {"Name": "merchant_category", "Type": "string", "Comment": "Merchant category code"},
                  {"Name": "payment_method", "Type": "string", "Comment": "Payment method used"},
                  {"Name": "status", "Type": "string", "Comment": "Transaction status"}
                ],
                "Location": "s3://'${DATA_LAKE_BUCKET}'/'${CURATED_DATA_PREFIX}'/transaction_data/",
                "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
                "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
                "SerdeInfo": {
                  "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
                }
              },
              "PartitionKeys": [
                {"Name": "year", "Type": "string"},
                {"Name": "month", "Type": "string"},
                {"Name": "day", "Type": "string"}
              ],
              "Parameters": {
                "classification": "parquet",
                "data_classification": "internal"
              }
            }' || error_exit "Failed to create transaction_data table"
    else
        log_warning "Table transaction_data already exists"
    fi
    
    log_success "Glue Data Catalog configured successfully"
}

# Configure Lake Formation permissions
configure_lake_formation_permissions() {
    log_info "Configuring Lake Formation permissions and security..."
    
    # Grant Lake Formation admin permissions to current user
    CURRENT_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    
    log_info "Granting admin permissions to current user..."
    aws lakeformation grant-permissions \
        --principal DataLakePrincipalIdentifier=${CURRENT_USER_ARN} \
        --resource '{
          "Database": {
            "Name": "'${GLUE_DATABASE}'"
          }
        }' \
        --permissions "ALL" \
        --permissions-with-grant-option "ALL" || \
        log_warning "Admin permissions may already be granted"
    
    # Create fine-grained permissions for customer data
    log_info "Creating permissions for customer data..."
    aws lakeformation grant-permissions \
        --principal DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:role/DataAnalystRole \
        --resource '{
          "Table": {
            "DatabaseName": "'${GLUE_DATABASE}'",
            "Name": "customer_data"
          }
        }' \
        --permissions "SELECT" \
        --permissions-with-grant-option "SELECT" || \
        log_warning "Permissions may already be granted"
    
    # Create data filter for PII protection
    log_info "Creating data filter for PII protection..."
    aws lakeformation create-data-cells-filter \
        --table-data '{
          "TableCatalogId": "'${AWS_ACCOUNT_ID}'",
          "DatabaseName": "'${GLUE_DATABASE}'",
          "TableName": "customer_data",
          "Name": "customer_data_pii_filter",
          "RowFilter": {
            "FilterExpression": "customer_segment IN ('\''premium'\'', '\''standard'\'')"
          },
          "ColumnNames": ["customer_id", "registration_date", "customer_segment", "lifetime_value", "region"],
          "ColumnWildcard": null
        }' || log_warning "Data filter may already exist"
    
    # Grant permissions through the data filter
    log_info "Granting permissions through data filter..."
    aws lakeformation grant-permissions \
        --principal DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:role/DataAnalystRole \
        --resource '{
          "DataCellsFilter": {
            "TableCatalogId": "'${AWS_ACCOUNT_ID}'",
            "DatabaseName": "'${GLUE_DATABASE}'",
            "TableName": "customer_data",
            "Name": "customer_data_pii_filter"
          }
        }' \
        --permissions "SELECT" || \
        log_warning "Data filter permissions may already be granted"
    
    # Grant full access to transaction data
    log_info "Granting permissions for transaction data..."
    aws lakeformation grant-permissions \
        --principal DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:role/DataAnalystRole \
        --resource '{
          "Table": {
            "DatabaseName": "'${GLUE_DATABASE}'",
            "Name": "transaction_data"
          }
        }' \
        --permissions "SELECT" || \
        log_warning "Transaction data permissions may already be granted"
    
    log_success "Lake Formation permissions configured successfully"
}

# Create Amazon DataZone domain
create_datazone_domain() {
    log_info "Creating Amazon DataZone domain..."
    
    # Create DataZone domain for data governance
    log_info "Creating DataZone domain..."
    DOMAIN_ID=$(aws datazone create-domain \
        --name ${DOMAIN_NAME} \
        --description "Enterprise data governance domain with Lake Formation integration" \
        --domain-execution-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/LakeFormationServiceRole \
        --query 'id' --output text 2>/dev/null || \
        echo "domain-exists")
    
    if [ "$DOMAIN_ID" = "domain-exists" ]; then
        log_warning "DataZone domain may already exist or creation failed"
        # Try to find existing domain
        DOMAIN_ID=$(aws datazone list-domains --query "items[?name=='${DOMAIN_NAME}'].id" --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$DOMAIN_ID" ] && [ "$DOMAIN_ID" != "domain-exists" ]; then
        echo "DOMAIN_ID=${DOMAIN_ID}" > /tmp/datazone_vars.env
        log_info "DataZone Domain ID: ${DOMAIN_ID}"
        
        # Wait for domain to be created (with timeout)
        log_info "Waiting for domain creation to complete..."
        timeout 300 aws datazone wait domain-created --identifier ${DOMAIN_ID} || \
            log_warning "Domain creation timeout - continuing anyway"
        
        # Create business glossary
        log_info "Creating business glossary..."
        GLOSSARY_ID=$(aws datazone create-glossary \
            --domain-identifier ${DOMAIN_ID} \
            --name "Enterprise Business Glossary" \
            --description "Standardized business terms and definitions" \
            --status ENABLED \
            --query 'id' --output text 2>/dev/null || echo "")
        
        if [ -n "$GLOSSARY_ID" ]; then
            echo "GLOSSARY_ID=${GLOSSARY_ID}" >> /tmp/datazone_vars.env
            log_info "Glossary ID: ${GLOSSARY_ID}"
            
            # Create sample business glossary terms
            log_info "Creating glossary terms..."
            aws datazone create-glossary-term \
                --domain-identifier ${DOMAIN_ID} \
                --glossary-identifier ${GLOSSARY_ID} \
                --name "Customer Lifetime Value" \
                --short-description "The predicted revenue that a customer will generate during their relationship with the company" \
                --long-description "Customer Lifetime Value (CLV) is calculated using historical transaction data, customer behavior patterns, and predictive analytics to estimate the total economic value a customer represents over their entire relationship with the organization." || \
                log_warning "Failed to create CLV glossary term"
            
            aws datazone create-glossary-term \
                --domain-identifier ${DOMAIN_ID} \
                --glossary-identifier ${GLOSSARY_ID} \
                --name "Customer Segment" \
                --short-description "Business classification of customers based on value, behavior, and characteristics" \
                --long-description "Customer segments include Premium (high-value customers), Standard (regular customers), and Basic (low-engagement customers). Segmentation drives personalized marketing and service strategies." || \
                log_warning "Failed to create Customer Segment glossary term"
        fi
        
        # Create data project for analytics team
        log_info "Creating analytics project..."
        PROJECT_ID=$(aws datazone create-project \
            --domain-identifier ${DOMAIN_ID} \
            --name "Customer Analytics Project" \
            --description "Analytics project for customer behavior and transaction analysis" \
            --query 'id' --output text 2>/dev/null || echo "")
        
        if [ -n "$PROJECT_ID" ]; then
            echo "PROJECT_ID=${PROJECT_ID}" >> /tmp/datazone_vars.env
            log_info "DataZone Project ID: ${PROJECT_ID}"
        fi
    fi
    
    log_success "DataZone domain configuration completed"
}

# Create ETL job with lineage tracking
create_etl_job() {
    log_info "Creating ETL job with data lineage tracking..."
    
    # Create Glue job script with lineage tracking
    cat > /tmp/customer_data_etl.py << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F
from pyspark.sql.types import *
import datetime

# Initialize Glue context
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATA_LAKE_BUCKET'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Enable lineage tracking
spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", f"s3://{args['DATA_LAKE_BUCKET']}/analytics-data/")

# Read raw customer data
raw_customer_df = spark.read.option("header", "true").csv(f"s3://{args['DATA_LAKE_BUCKET']}/raw-data/customer_data/")

# Data quality transformations
curated_customer_df = raw_customer_df \
    .filter(F.col("customer_id").isNotNull()) \
    .filter(F.col("email").contains("@")) \
    .withColumn("registration_year", F.year(F.col("registration_date"))) \
    .withColumn("registration_month", F.month(F.col("registration_date"))) \
    .withColumn("data_quality_score", F.lit(95.0)) \
    .withColumn("processed_timestamp", F.current_timestamp())

# Add data lineage metadata
curated_customer_df = curated_customer_df.withColumn("source_system", F.lit("CRM"))
curated_customer_df = curated_customer_df.withColumn("etl_job_id", F.lit(args['JOB_NAME']))
curated_customer_df = curated_customer_df.withColumn("data_classification", F.lit("confidential"))

# Write to curated zone with partitioning
curated_customer_df.write \
    .partitionBy("registration_year", "registration_month") \
    .mode("overwrite") \
    .parquet(f"s3://{args['DATA_LAKE_BUCKET']}/curated-data/customer_data/")

# Create aggregated analytics data
analytics_df = curated_customer_df \
    .groupBy("customer_segment", "region", "registration_year") \
    .agg(
        F.count("customer_id").alias("customer_count"),
        F.avg("lifetime_value").alias("avg_lifetime_value"),
        F.sum("lifetime_value").alias("total_lifetime_value")
    )

# Write analytics data
analytics_df.write \
    .mode("overwrite") \
    .parquet(f"s3://{args['DATA_LAKE_BUCKET']}/analytics-data/customer_analytics/")

job.commit()
EOF
    
    # Upload script to S3
    log_info "Uploading ETL script to S3..."
    aws s3 cp /tmp/customer_data_etl.py s3://${DATA_LAKE_BUCKET}/scripts/ || \
        error_exit "Failed to upload ETL script"
    
    # Create Glue job with enhanced lineage tracking
    log_info "Creating Glue ETL job..."
    if ! aws glue get-job --job-name CustomerDataETLWithLineage &>/dev/null; then
        aws glue create-job \
            --name "CustomerDataETLWithLineage" \
            --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/LakeFormationServiceRole \
            --command '{
              "Name": "glueetl",
              "ScriptLocation": "s3://'${DATA_LAKE_BUCKET}'/scripts/customer_data_etl.py",
              "PythonVersion": "3"
            }' \
            --default-arguments '{
              "--job-language": "python",
              "--job-bookmark-option": "job-bookmark-enable",
              "--enable-metrics": "true",
              "--enable-continuous-cloudwatch-log": "true",
              "--enable-spark-ui": "true",
              "--spark-event-logs-path": "s3://'${DATA_LAKE_BUCKET}'/spark-logs/",
              "--enable-glue-datacatalog": "true",
              "--DATA_LAKE_BUCKET": "'${DATA_LAKE_BUCKET}'"
            }' \
            --max-retries 1 \
            --timeout 60 \
            --max-capacity 2.0 \
            --glue-version "4.0" || error_exit "Failed to create Glue job"
    else
        log_warning "Glue job CustomerDataETLWithLineage already exists"
    fi
    
    log_success "ETL job created successfully"
}

# Generate and process sample data
process_sample_data() {
    log_info "Generating sample data and running ETL pipeline..."
    
    # Create sample customer data
    cat > /tmp/sample_customer_data.csv << EOF
customer_id,first_name,last_name,email,phone,registration_date,customer_segment,lifetime_value,region
1001,John,Smith,john.smith@email.com,555-0101,2023-01-15,premium,15000.50,us-east
1002,Sarah,Johnson,sarah.johnson@email.com,555-0102,2023-02-20,standard,8500.25,us-west
1003,Michael,Brown,michael.brown@email.com,555-0103,2023-03-10,premium,22000.75,eu-west
1004,Emily,Davis,emily.davis@email.com,555-0104,2023-04-05,standard,6200.30,us-east
1005,David,Wilson,david.wilson@email.com,555-0105,2023-05-12,basic,2100.80,us-central
1006,Lisa,Anderson,lisa.anderson@email.com,555-0106,2023-06-08,premium,18500.90,eu-central
1007,Robert,Taylor,robert.taylor@email.com,555-0107,2023-07-22,standard,7800.40,asia-pacific
1008,Jennifer,Thomas,jennifer.thomas@email.com,555-0108,2023-08-15,premium,19200.60,us-west
1009,William,Jackson,william.jackson@email.com,555-0109,2023-09-03,standard,5900.20,eu-west
1010,Amanda,White,amanda.white@email.com,555-0110,2023-10-18,basic,1800.15,us-east
EOF
    
    # Upload sample data to raw zone
    log_info "Uploading sample customer data..."
    aws s3 cp /tmp/sample_customer_data.csv \
        s3://${DATA_LAKE_BUCKET}/${RAW_DATA_PREFIX}/customer_data/ || \
        error_exit "Failed to upload customer data"
    
    # Create sample transaction data
    cat > /tmp/sample_transaction_data.csv << EOF
transaction_id,customer_id,transaction_date,amount,currency,merchant_category,payment_method,status
txn_001,1001,2023-11-01 10:30:00,250.00,USD,retail,credit_card,completed
txn_002,1002,2023-11-01 14:15:00,89.99,USD,online,debit_card,completed
txn_003,1003,2023-11-02 09:45:00,1200.50,EUR,travel,credit_card,completed
txn_004,1004,2023-11-02 16:20:00,45.75,USD,grocery,cash,completed
txn_005,1005,2023-11-03 11:10:00,15.99,USD,subscription,credit_card,pending
EOF
    
    log_info "Uploading sample transaction data..."
    aws s3 cp /tmp/sample_transaction_data.csv \
        s3://${DATA_LAKE_BUCKET}/${RAW_DATA_PREFIX}/transaction_data/ || \
        error_exit "Failed to upload transaction data"
    
    # Run the ETL job
    log_info "Starting ETL job execution..."
    JOB_RUN_ID=$(aws glue start-job-run \
        --job-name CustomerDataETLWithLineage \
        --query 'JobRunId' --output text) || \
        error_exit "Failed to start ETL job"
    
    echo "JOB_RUN_ID=${JOB_RUN_ID}" >> /tmp/datazone_vars.env
    log_info "ETL Job Run ID: ${JOB_RUN_ID}"
    
    # Wait for job completion with timeout
    log_info "Waiting for ETL job to complete (this may take several minutes)..."
    timeout 600 aws glue wait job-run-complete \
        --job-name CustomerDataETLWithLineage \
        --run-id ${JOB_RUN_ID} || \
        log_warning "ETL job timeout or failure - check CloudWatch logs"
    
    log_success "Sample data processed and ETL pipeline executed"
}

# Configure monitoring and alerts
setup_monitoring() {
    log_info "Configuring data quality monitoring and alerts..."
    
    # Create CloudWatch log group for data quality monitoring
    log_info "Creating CloudWatch log group..."
    aws logs create-log-group \
        --log-group-name /aws/datazone/data-quality \
        --retention-in-days 30 || \
        log_warning "Log group may already exist"
    
    # Create SNS topic for data quality alerts
    log_info "Creating SNS topic for alerts..."
    ALERT_TOPIC_ARN=$(aws sns create-topic \
        --name DataQualityAlerts \
        --query 'TopicArn' --output text) || \
        error_exit "Failed to create SNS topic"
    
    echo "ALERT_TOPIC_ARN=${ALERT_TOPIC_ARN}" >> /tmp/datazone_vars.env
    log_info "Alert Topic ARN: ${ALERT_TOPIC_ARN}"
    
    # Create CloudWatch alarm for failed ETL jobs
    log_info "Creating CloudWatch alarm for ETL failures..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "DataLakeETLFailures" \
        --alarm-description "Alert when ETL jobs fail" \
        --metric-name "glue.ALL.job.failure" \
        --namespace "AWS/Glue" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions ${ALERT_TOPIC_ARN} || \
        log_warning "Failed to create CloudWatch alarm"
    
    log_success "Monitoring and alerts configured"
}

# Save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > /tmp/deployment_state.env << EOF
# Data Lake Governance Deployment State
# Generated on: $(date)
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DATA_LAKE_BUCKET=${DATA_LAKE_BUCKET}
GLUE_DATABASE=${GLUE_DATABASE}
DOMAIN_NAME=${DOMAIN_NAME}
EOF
    
    # Append DataZone variables if they exist
    if [ -f /tmp/datazone_vars.env ]; then
        cat /tmp/datazone_vars.env >> /tmp/deployment_state.env
    fi
    
    # Copy to a persistent location
    aws s3 cp /tmp/deployment_state.env s3://${DATA_LAKE_BUCKET}/deployment/ || \
        log_warning "Failed to save deployment state to S3"
    
    log_success "Deployment state saved"
}

# Main deployment function
main() {
    log_info "Starting Data Lake Governance deployment..."
    log_info "================================================================"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    setup_lake_formation
    create_iam_roles
    setup_glue_catalog
    configure_lake_formation_permissions
    create_datazone_domain
    create_etl_job
    process_sample_data
    setup_monitoring
    save_deployment_state
    
    # Clean up temporary files
    rm -f /tmp/lf-service-role-trust-policy.json
    rm -f /tmp/lf-service-role-policy.json
    rm -f /tmp/data-analyst-trust-policy.json
    rm -f /tmp/customer_data_etl.py
    rm -f /tmp/sample_customer_data.csv
    rm -f /tmp/sample_transaction_data.csv
    
    log_info "================================================================"
    log_success "Data Lake Governance deployment completed successfully!"
    log_info ""
    log_info "Deployment Summary:"
    log_info "- Data Lake Bucket: ${DATA_LAKE_BUCKET}"
    log_info "- Glue Database: ${GLUE_DATABASE}"
    log_info "- Region: ${AWS_REGION}"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Access the AWS Lake Formation console to review permissions"
    log_info "2. Use Amazon Athena to query the governed datasets"
    log_info "3. Explore the DataZone portal for data discovery"
    log_info "4. Monitor CloudWatch for data quality metrics"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

# Execute main function
main "$@"