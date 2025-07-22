#!/bin/bash

# AWS Data Visualization Pipeline Deployment Script
# Creates a complete data visualization pipeline with QuickSight, S3, Athena, and Glue
# Based on recipe: Data Visualization Pipelines with QuickSight

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Default values
DRY_RUN=false
SKIP_CLEANUP=false
FORCE=false

# Help function
show_help() {
    cat << EOF
AWS Data Visualization Pipeline Deployment Script

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -f, --force         Force deployment even if resources exist
    -s, --skip-cleanup  Skip cleanup of temporary files
    --region REGION     AWS region to deploy to (default: current AWS CLI region)

EXAMPLES:
    ./deploy.sh                    # Deploy with default settings
    ./deploy.sh --dry-run          # Show what would be deployed
    ./deploy.sh --force            # Force deployment
    ./deploy.sh --region us-west-2 # Deploy to specific region

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions for S3, Glue, Athena, QuickSight, Lambda, EventBridge
    - QuickSight account activated (Standard or Enterprise edition)
    - jq installed for JSON processing
    - Node.js and npm installed for Lambda function

ESTIMATED COST:
    $50-100/month for moderate usage (10GB data, 100 queries/day)
    QuickSight Standard edition: $9/user/month

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -s|--skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check if node and npm are installed
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        error "Node.js and npm are required for Lambda function deployment."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check QuickSight status
    log "Checking QuickSight availability..."
    if ! aws quicksight list-users --aws-account-id $(aws sts get-caller-identity --query Account --output text) --namespace default &> /dev/null; then
        warning "QuickSight may not be activated. Please ensure QuickSight is set up in your account."
        warning "Manual QuickSight configuration will be required after deployment."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "No AWS region configured, using default: $AWS_REGION"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    if command -v aws &> /dev/null && aws secretsmanager get-random-password --help &> /dev/null; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    export PROJECT_NAME="data-viz-pipeline-${RANDOM_SUFFIX}"
    export RAW_BUCKET="${PROJECT_NAME}-raw-data"
    export PROCESSED_BUCKET="${PROJECT_NAME}-processed-data"
    export ATHENA_RESULTS_BUCKET="${PROJECT_NAME}-athena-results"
    export GLUE_ROLE_NAME="GlueDataVizRole-${RANDOM_SUFFIX}"
    
    log "Project Name: $PROJECT_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    success "Environment setup completed"
}

# Create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create buckets: $RAW_BUCKET, $PROCESSED_BUCKET, $ATHENA_RESULTS_BUCKET"
        return 0
    fi
    
    # Create buckets
    for bucket in "$RAW_BUCKET" "$PROCESSED_BUCKET" "$ATHENA_RESULTS_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" &> /dev/null; then
            if [ "$FORCE" = true ]; then
                warning "Bucket $bucket already exists, continuing due to --force flag"
            else
                error "Bucket $bucket already exists. Use --force to continue or choose a different name."
                exit 1
            fi
        else
            if [ "$AWS_REGION" = "us-east-1" ]; then
                aws s3api create-bucket --bucket "$bucket"
            else
                aws s3api create-bucket --bucket "$bucket" --create-bucket-configuration LocationConstraint="$AWS_REGION"
            fi
            
            # Enable versioning
            aws s3api put-bucket-versioning \
                --bucket "$bucket" \
                --versioning-configuration Status=Enabled
            
            # Add bucket tagging
            aws s3api put-bucket-tagging \
                --bucket "$bucket" \
                --tagging "TagSet=[{Key=Project,Value=$PROJECT_NAME},{Key=Environment,Value=development},{Key=Recipe,Value=data-visualization-pipeline}]"
            
            success "Created bucket: $bucket"
        fi
    done
    
    success "S3 buckets creation completed"
}

# Create sample datasets
create_sample_data() {
    log "Creating and uploading sample datasets..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create sample data and upload to $RAW_BUCKET"
        return 0
    fi
    
    # Create sample data directory
    mkdir -p sample-data
    
    # Create sales data
    cat > sample-data/sales_2024_q1.csv << 'EOF'
order_id,customer_id,product_category,product_name,quantity,unit_price,order_date,region,sales_rep
1001,C001,Electronics,Laptop,1,1200.00,2024-01-15,North,John Smith
1002,C002,Clothing,T-Shirt,3,25.00,2024-01-16,South,Jane Doe
1003,C003,Electronics,Smartphone,2,800.00,2024-01-17,East,Bob Johnson
1004,C001,Books,Programming Guide,1,45.00,2024-01-18,North,John Smith
1005,C004,Electronics,Tablet,1,500.00,2024-01-19,West,Alice Brown
1006,C005,Clothing,Jeans,2,60.00,2024-01-20,South,Jane Doe
1007,C002,Electronics,Headphones,1,150.00,2024-01-21,South,Jane Doe
1008,C006,Books,Data Science Book,2,35.00,2024-01-22,East,Bob Johnson
1009,C003,Clothing,Jacket,1,120.00,2024-01-23,East,Bob Johnson
1010,C007,Electronics,Monitor,1,300.00,2024-01-24,West,Alice Brown
EOF
    
    # Create customer data
    cat > sample-data/customers.csv << 'EOF'
customer_id,customer_name,email,registration_date,customer_tier,city,state
C001,Michael Johnson,mjohnson@email.com,2023-06-15,Gold,New York,NY
C002,Sarah Williams,swilliams@email.com,2023-08-22,Silver,Atlanta,GA
C003,David Brown,dbrown@email.com,2023-09-10,Gold,Boston,MA
C004,Lisa Davis,ldavis@email.com,2023-11-05,Bronze,Los Angeles,CA
C005,Robert Wilson,rwilson@email.com,2023-12-01,Silver,Miami,FL
C006,Jennifer Garcia,jgarcia@email.com,2024-01-10,Bronze,Chicago,IL
C007,Christopher Lee,clee@email.com,2024-01-15,Gold,Seattle,WA
EOF
    
    # Create product catalog
    cat > sample-data/products.json << 'EOF'
[
  {"product_id": "P001", "product_name": "Laptop", "category": "Electronics", "cost": 800.00, "margin": 0.50},
  {"product_id": "P002", "product_name": "T-Shirt", "category": "Clothing", "cost": 10.00, "margin": 1.50},
  {"product_id": "P003", "product_name": "Smartphone", "category": "Electronics", "cost": 500.00, "margin": 0.60},
  {"product_id": "P004", "product_name": "Programming Guide", "category": "Books", "cost": 20.00, "margin": 1.25},
  {"product_id": "P005", "product_name": "Tablet", "category": "Electronics", "cost": 300.00, "margin": 0.67},
  {"product_id": "P006", "product_name": "Jeans", "category": "Clothing", "cost": 25, "margin": 1.40},
  {"product_id": "P007", "product_name": "Headphones", "category": "Electronics", "cost": 75.00, "margin": 1.00},
  {"product_id": "P008", "product_name": "Data Science Book", "category": "Books", "cost": 15.00, "margin": 1.33},
  {"product_id": "P009", "product_name": "Jacket", "category": "Clothing", "cost": 60.00, "margin": 1},
  {"product_id": "P010", "product_name": "Monitor", "category": "Electronics", "cost":200.00, "margin": 0.50}
]
EOF
    
    # Upload sample data to S3
    aws s3 cp sample-data/ s3://"$RAW_BUCKET"/sales-data/ --recursive
    
    success "Sample data created and uploaded"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles for Glue..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create IAM role: $GLUE_ROLE_NAME"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$GLUE_ROLE_NAME" &> /dev/null; then
        if [ "$FORCE" = true ]; then
            warning "IAM role $GLUE_ROLE_NAME already exists, continuing due to --force flag"
        else
            error "IAM role $GLUE_ROLE_NAME already exists. Use --force to continue."
            exit 1
        fi
    else
        # Create Glue trust policy
        cat > glue-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "glue.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        # Create Glue service role
        aws iam create-role \
            --role-name "$GLUE_ROLE_NAME" \
            --assume-role-policy-document file://glue-trust-policy.json
        
        # Attach managed policies
        aws iam attach-role-policy \
            --role-name "$GLUE_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
        
        # Create custom S3 policy
        cat > glue-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${RAW_BUCKET}",
                "arn:aws:s3:::${RAW_BUCKET}/*",
                "arn:aws:s3:::${PROCESSED_BUCKET}",
                "arn:aws:s3:::${PROCESSED_BUCKET}/*"
            ]
        }
    ]
}
EOF
        
        aws iam put-role-policy \
            --role-name "$GLUE_ROLE_NAME" \
            --policy-name S3AccessPolicy \
            --policy-document file://glue-s3-policy.json
        
        success "Created IAM role: $GLUE_ROLE_NAME"
    fi
    
    export GLUE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${GLUE_ROLE_NAME}"
    
    # Wait for role to be available
    log "Waiting for IAM role to propagate..."
    sleep 10
    
    success "IAM roles setup completed"
}

# Create Glue database and crawler
create_glue_resources() {
    log "Creating Glue database and crawler..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create Glue database and crawler"
        return 0
    fi
    
    # Create Glue database
    if aws glue get-database --name "${PROJECT_NAME}-database" &> /dev/null; then
        warning "Glue database ${PROJECT_NAME}-database already exists"
    else
        aws glue create-database \
            --database-input Name="${PROJECT_NAME}-database",Description="Database for data visualization pipeline"
        success "Created Glue database: ${PROJECT_NAME}-database"
    fi
    
    # Create crawler for raw data
    if aws glue get-crawler --name "${PROJECT_NAME}-raw-crawler" &> /dev/null; then
        warning "Glue crawler ${PROJECT_NAME}-raw-crawler already exists"
    else
        aws glue create-crawler \
            --name "${PROJECT_NAME}-raw-crawler" \
            --role "$GLUE_ROLE_ARN" \
            --database-name "${PROJECT_NAME}-database" \
            --targets "S3Targets=[{Path=s3://${RAW_BUCKET}/sales-data/}]" \
            --description "Crawler for raw sales data"
        success "Created Glue crawler: ${PROJECT_NAME}-raw-crawler"
    fi
    
    # Run crawler
    log "Starting crawler to discover schema..."
    aws glue start-crawler --name "${PROJECT_NAME}-raw-crawler" || warning "Crawler may already be running"
    
    # Wait for crawler to complete
    local max_attempts=20
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local crawler_state=$(aws glue get-crawler \
            --name "${PROJECT_NAME}-raw-crawler" \
            --query 'Crawler.State' --output text)
        
        if [ "$crawler_state" = "READY" ]; then
            success "Crawler completed successfully"
            break
        elif [ "$crawler_state" = "STOPPING" ] || [ "$crawler_state" = "RUNNING" ]; then
            log "Crawler state: $crawler_state, waiting... (attempt $((attempt + 1))/$max_attempts)"
            sleep 30
            attempt=$((attempt + 1))
        else
            warning "Unexpected crawler state: $crawler_state"
            break
        fi
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warning "Crawler did not complete within expected time, continuing..."
    fi
    
    success "Glue resources setup completed"
}

# Create ETL job
create_etl_job() {
    log "Creating Glue ETL job..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create Glue ETL job"
        return 0
    fi
    
    # Create ETL script directory
    mkdir -p glue-scripts
    
    # Create ETL script
    cat > glue-scripts/sales-etl.py << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_DATABASE', 'TARGET_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read sales data
    sales_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['SOURCE_DATABASE'],
        table_name="sales_2024_q1_csv"
    ).toDF()
    
    # Read customer data
    customers_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['SOURCE_DATABASE'],
        table_name="customers_csv"
    ).toDF()
    
    # Data transformations
    # Convert data types
    sales_df = sales_df.withColumn("quantity", F.col("quantity").cast(IntegerType())) \
                      .withColumn("unit_price", F.col("unit_price").cast(DoubleType())) \
                      .withColumn("order_date", F.to_date(F.col("order_date"), "yyyy-MM-dd"))
    
    # Calculate total amount
    sales_df = sales_df.withColumn("total_amount", F.col("quantity") * F.col("unit_price"))
    
    # Add derived columns
    sales_df = sales_df.withColumn("order_month", F.month(F.col("order_date"))) \
                      .withColumn("order_year", F.year(F.col("order_date"))) \
                      .withColumn("order_quarter", F.quarter(F.col("order_date")))
    
    # Join with customer data
    enriched_sales = sales_df.join(customers_df, "customer_id", "left")
    
    # Create aggregated views
    # Monthly sales summary
    monthly_sales = enriched_sales.groupBy("order_year", "order_month", "region") \
        .agg(
            F.sum("total_amount").alias("total_revenue"),
            F.count("order_id").alias("total_orders"),
            F.avg("total_amount").alias("avg_order_value"),
            F.countDistinct("customer_id").alias("unique_customers")
        )
    
    # Product category performance
    category_performance = enriched_sales.groupBy("product_category", "region") \
        .agg(
            F.sum("total_amount").alias("category_revenue"),
            F.sum("quantity").alias("total_quantity"),
            F.count("order_id").alias("total_orders")
        )
    
    # Customer tier analysis
    customer_analysis = enriched_sales.groupBy("customer_tier", "region") \
        .agg(
            F.sum("total_amount").alias("tier_revenue"),
            F.count("order_id").alias("tier_orders"),
            F.countDistinct("customer_id").alias("tier_customers")
        )
    
    # Write processed data to S3 in Parquet format
    target_bucket = args['TARGET_BUCKET']
    
    # Write enriched sales data
    enriched_sales.write.mode("overwrite").parquet(f"s3://{target_bucket}/enriched-sales/")
    
    # Write aggregated views
    monthly_sales.write.mode("overwrite").parquet(f"s3://{target_bucket}/monthly-sales/")
    category_performance.write.mode("overwrite").parquet(f"s3://{target_bucket}/category-performance/")
    customer_analysis.write.mode("overwrite").parquet(f"s3://{target_bucket}/customer-analysis/")
    
    print("ETL job completed successfully")
    
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise e

job.commit()
EOF
    
    # Upload ETL script to S3
    aws s3 cp glue-scripts/sales-etl.py s3://"$PROCESSED_BUCKET"/scripts/
    
    # Create Glue ETL job
    if aws glue get-job --job-name "${PROJECT_NAME}-etl-job" &> /dev/null; then
        warning "Glue ETL job ${PROJECT_NAME}-etl-job already exists"
    else
        aws glue create-job \
            --name "${PROJECT_NAME}-etl-job" \
            --role "$GLUE_ROLE_ARN" \
            --command "Name=glueetl,ScriptLocation=s3://${PROCESSED_BUCKET}/scripts/sales-etl.py,PythonVersion=3" \
            --default-arguments "{
                \"--SOURCE_DATABASE\":\"${PROJECT_NAME}-database\",
                \"--TARGET_BUCKET\":\"${PROCESSED_BUCKET}\",
                \"--enable-metrics\":\"\",
                \"--enable-continuous-cloudwatch-log\":\"true\"
            }" \
            --max-retries 1 \
            --timeout 60 \
            --glue-version "4.0"
        success "Created Glue ETL job: ${PROJECT_NAME}-etl-job"
    fi
    
    success "ETL job setup completed"
}

# Run ETL job and create processed data crawler
run_etl_and_crawler() {
    log "Running ETL job and creating processed data crawler..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would run ETL job and create processed data crawler"
        return 0
    fi
    
    # Start ETL job
    log "Starting ETL job..."
    local job_run_id
    job_run_id=$(aws glue start-job-run --job-name "${PROJECT_NAME}-etl-job" --query 'JobRunId' --output text)
    
    # Wait for job to complete
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local job_state=$(aws glue get-job-run \
            --job-name "${PROJECT_NAME}-etl-job" \
            --run-id "$job_run_id" \
            --query 'JobRun.JobRunState' --output text)
        
        if [ "$job_state" = "SUCCEEDED" ]; then
            success "ETL job completed successfully"
            break
        elif [ "$job_state" = "RUNNING" ]; then
            log "ETL job still running, waiting... (attempt $((attempt + 1))/$max_attempts)"
            sleep 60
            attempt=$((attempt + 1))
        elif [ "$job_state" = "FAILED" ]; then
            error "ETL job failed"
            # Get error details
            aws glue get-job-run \
                --job-name "${PROJECT_NAME}-etl-job" \
                --run-id "$job_run_id" \
                --query 'JobRun.ErrorMessage' --output text
            exit 1
        else
            warning "ETL job state: $job_state"
            sleep 30
            attempt=$((attempt + 1))
        fi
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error "ETL job did not complete within expected time"
        exit 1
    fi
    
    # Create crawler for processed data
    if aws glue get-crawler --name "${PROJECT_NAME}-processed-crawler" &> /dev/null; then
        warning "Processed data crawler already exists"
    else
        aws glue create-crawler \
            --name "${PROJECT_NAME}-processed-crawler" \
            --role "$GLUE_ROLE_ARN" \
            --database-name "${PROJECT_NAME}-database" \
            --targets "S3Targets=[{Path=s3://${PROCESSED_BUCKET}/}]" \
            --description "Crawler for processed data"
        success "Created processed data crawler"
    fi
    
    # Run processed data crawler
    log "Starting processed data crawler..."
    aws glue start-crawler --name "${PROJECT_NAME}-processed-crawler" || warning "Crawler may already be running"
    
    success "ETL job and crawler setup completed"
}

# Create Athena workgroup
create_athena_workgroup() {
    log "Creating Athena workgroup..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create Athena workgroup"
        return 0
    fi
    
    # Create Athena workgroup
    if aws athena get-work-group --work-group "${PROJECT_NAME}-workgroup" &> /dev/null; then
        warning "Athena workgroup ${PROJECT_NAME}-workgroup already exists"
    else
        aws athena create-work-group \
            --name "${PROJECT_NAME}-workgroup" \
            --description "Workgroup for data visualization pipeline" \
            --configuration "ResultConfiguration={OutputLocation=s3://${ATHENA_RESULTS_BUCKET}/}"
        success "Created Athena workgroup: ${PROJECT_NAME}-workgroup"
    fi
    
    # Create sample queries
    mkdir -p athena-queries
    cat > athena-queries/monthly_revenue.sql << EOF
SELECT 
    order_year,
    order_month,
    region,
    total_revenue,
    total_orders,
    avg_order_value,
    unique_customers
FROM "${PROJECT_NAME}-database"."monthly_sales"
ORDER BY order_year, order_month, region;
EOF
    
    cat > athena-queries/top_categories.sql << EOF
SELECT 
    product_category,
    region,
    category_revenue,
    total_quantity,
    total_orders,
    ROUND(category_revenue / total_orders, 2) as avg_order_value
FROM "${PROJECT_NAME}-database"."category_performance"
ORDER BY category_revenue DESC;
EOF
    
    success "Athena workgroup and sample queries created"
}

# Create Lambda automation function
create_lambda_automation() {
    log "Creating Lambda automation function..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would create Lambda automation function"
        return 0
    fi
    
    # Create Lambda function directory
    mkdir -p lambda-automation
    cd lambda-automation
    
    # Create Lambda function code
    cat > index.js << 'EOF'
const AWS = require('aws-sdk');
const glue = new AWS.Glue();

const PROJECT_NAME = process.env.PROJECT_NAME;

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        // Check if new data was uploaded to raw bucket
        for (const record of event.Records) {
            if (record.eventSource === 'aws:s3' && record.eventName.startsWith('ObjectCreated')) {
                const bucketName = record.s3.bucket.name;
                const objectKey = record.s3.object.key;
                
                console.log(`New file uploaded: ${objectKey} in bucket ${bucketName}`);
                
                // Trigger crawler to update schema
                await triggerCrawler(`${PROJECT_NAME}-raw-crawler`);
                
                // Wait a bit then trigger ETL job
                setTimeout(async () => {
                    await triggerETLJob(`${PROJECT_NAME}-etl-job`);
                }, 60000); // Wait 1 minute for crawler to complete
            }
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify('Pipeline triggered successfully')
        };
        
    } catch (error) {
        console.error('Error:', error);
        throw error;
    }
};

async function triggerCrawler(crawlerName) {
    try {
        const params = { Name: crawlerName };
        await glue.startCrawler(params).promise();
        console.log(`Started crawler: ${crawlerName}`);
    } catch (error) {
        if (error.code === 'CrawlerRunningException') {
            console.log(`Crawler ${crawlerName} is already running`);
        } else {
            throw error;
        }
    }
}

async function triggerETLJob(jobName) {
    try {
        const params = { JobName: jobName };
        const result = await glue.startJobRun(params).promise();
        console.log(`Started ETL job: ${jobName}, Run ID: ${result.JobRunId}`);
    } catch (error) {
        console.error(`Error starting ETL job ${jobName}:`, error);
        throw error;
    }
}
EOF
    
    # Create package.json
    npm init -y &> /dev/null
    npm install aws-sdk &> /dev/null
    
    # Create deployment package
    zip -r ../automation-function.zip . &> /dev/null
    cd ..
    
    # Create Lambda function
    if aws lambda get-function --function-name "${PROJECT_NAME}-automation" &> /dev/null; then
        warning "Lambda function ${PROJECT_NAME}-automation already exists"
    else
        aws lambda create-function \
            --function-name "${PROJECT_NAME}-automation" \
            --runtime nodejs18.x \
            --role "$GLUE_ROLE_ARN" \
            --handler index.handler \
            --zip-file fileb://automation-function.zip \
            --timeout 300 \
            --environment "Variables={PROJECT_NAME=${PROJECT_NAME}}" \
            --description "Automation function for data visualization pipeline"
        success "Created Lambda function: ${PROJECT_NAME}-automation"
    fi
    
    # Add S3 trigger permission
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-automation" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn "arn:aws:s3:::${RAW_BUCKET}" &> /dev/null || warning "Lambda permission may already exist"
    
    # Configure S3 event notification
    cat > s3-notification.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "DataUploadTrigger",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-automation",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "sales-data/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-notification-configuration \
        --bucket "$RAW_BUCKET" \
        --notification-configuration file://s3-notification.json
    
    success "Lambda automation function and S3 triggers created"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Check Glue tables
    log "Checking Glue catalog tables..."
    local tables=$(aws glue get-tables \
        --database-name "${PROJECT_NAME}-database" \
        --query 'TableList[].Name' --output text)
    
    if [ -n "$tables" ]; then
        success "Glue tables found: $tables"
    else
        warning "No Glue tables found yet, may still be processing"
    fi
    
    # Test Athena query
    log "Testing Athena query..."
    local query_id
    query_id=$(aws athena start-query-execution \
        --query-string "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = '${PROJECT_NAME}-database'" \
        --work-group "${PROJECT_NAME}-workgroup" \
        --query 'QueryExecutionId' --output text)
    
    if [ -n "$query_id" ]; then
        success "Athena query submitted successfully: $query_id"
    else
        warning "Failed to submit Athena query"
    fi
    
    # Check processed data in S3
    log "Checking processed data in S3..."
    local processed_files=$(aws s3 ls "s3://${PROCESSED_BUCKET}/" --recursive 2>/dev/null | wc -l)
    
    if [ "$processed_files" -gt 0 ]; then
        success "Found $processed_files processed files in S3"
    else
        warning "No processed files found yet, ETL may still be running"
    fi
    
    success "Validation completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    if [ "$SKIP_CLEANUP" = true ]; then
        log "Skipping cleanup of temporary files"
        return 0
    fi
    
    log "Cleaning up temporary files..."
    
    # Remove temporary files and directories
    rm -rf sample-data glue-scripts lambda-automation athena-queries
    rm -f glue-trust-policy.json glue-s3-policy.json s3-notification.json automation-function.zip
    
    success "Temporary files cleaned up"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY RUN] Would save deployment information"
        return 0
    fi
    
    # Create deployment info file
    cat > deployment-info.txt << EOF
AWS Data Visualization Pipeline Deployment Information
=====================================================

Deployment Time: $(date)
AWS Region: $AWS_REGION
AWS Account ID: $AWS_ACCOUNT_ID
Project Name: $PROJECT_NAME

S3 Buckets:
- Raw Data: $RAW_BUCKET
- Processed Data: $PROCESSED_BUCKET
- Athena Results: $ATHENA_RESULTS_BUCKET

Glue Resources:
- Database: ${PROJECT_NAME}-database
- Raw Crawler: ${PROJECT_NAME}-raw-crawler
- Processed Crawler: ${PROJECT_NAME}-processed-crawler
- ETL Job: ${PROJECT_NAME}-etl-job

IAM Role:
- Glue Role: $GLUE_ROLE_NAME (ARN: $GLUE_ROLE_ARN)

Athena:
- Workgroup: ${PROJECT_NAME}-workgroup

Lambda:
- Automation Function: ${PROJECT_NAME}-automation

Next Steps:
1. Configure QuickSight data source to connect to the Athena workgroup
2. Create QuickSight datasets using the processed tables
3. Build dashboards and visualizations in QuickSight
4. Upload additional data files to test automation

QuickSight Configuration:
- Data Source Type: Amazon Athena
- Athena Workgroup: ${PROJECT_NAME}-workgroup
- Database: ${PROJECT_NAME}-database

Estimated Monthly Cost: \$50-100 for moderate usage
- S3 Storage: \$5-20/month
- Glue: \$10-30/month
- Athena: \$5-20/month
- QuickSight: \$9/user/month (Standard edition)

For cleanup, run: ./destroy.sh
EOF
    
    success "Deployment information saved to deployment-info.txt"
}

# Main deployment function
main() {
    log "Starting AWS Data Visualization Pipeline deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_sample_data
    create_iam_roles
    create_glue_resources
    create_etl_job
    run_etl_and_crawler
    create_athena_workgroup
    create_lambda_automation
    validate_deployment
    save_deployment_info
    cleanup_temp_files
    
    if [ "$DRY_RUN" = true ]; then
        log "Dry run completed. No actual resources were created."
        exit 0
    fi
    
    success "🎉 AWS Data Visualization Pipeline deployment completed successfully!"
    
    cat << EOF

${GREEN}Next Steps:${NC}
1. Configure QuickSight data source in the AWS Console
2. Create datasets and dashboards in QuickSight
3. Upload additional data to test automation
4. Review the deployment-info.txt file for details

${YELLOW}QuickSight Setup:${NC}
- Navigate to QuickSight in the AWS Console
- Create new data source > Amazon Athena
- Select workgroup: ${PROJECT_NAME}-workgroup
- Choose database: ${PROJECT_NAME}-database

${BLUE}For cleanup, run:${NC} ./destroy.sh

Deployment details saved in: deployment-info.txt
EOF
}

# Run main function
main "$@"