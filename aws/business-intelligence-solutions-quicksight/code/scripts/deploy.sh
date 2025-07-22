#!/bin/bash

# Deploy script for Business Intelligence Solutions with QuickSight
# This script creates a complete BI solution using Amazon QuickSight with S3 and RDS data sources

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

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    if ! aws quicksight list-users --aws-account-id "$(aws sts get-caller-identity --query Account --output text)" --namespace default --region "$(aws configure get region)" &> /dev/null; then
        warn "QuickSight is not enabled or configured. You'll need to enable QuickSight manually."
        warn "Please visit https://quicksight.aws.amazon.com/ to enable QuickSight before continuing."
        read -p "Press Enter after enabling QuickSight to continue..."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export BUCKET_NAME="quicksight-bi-data-${RANDOM_SUFFIX}"
    export DB_IDENTIFIER="quicksight-demo-db-${RANDOM_SUFFIX}"
    export QUICKSIGHT_USER="quicksight-user-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .env_quicksight << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
DB_IDENTIFIER=${DB_IDENTIFIER}
QUICKSIGHT_USER=${QUICKSIGHT_USER}
EOF
    
    log "Environment variables set:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "  S3 Bucket: ${BUCKET_NAME}"
    log "  RDS Instance: ${DB_IDENTIFIER}"
}

# Function to create S3 bucket and sample data
create_s3_resources() {
    log "Creating S3 bucket and sample data..."
    
    # Create S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warn "Bucket ${BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
        success "Created S3 bucket: ${BUCKET_NAME}"
    fi
    
    # Create sample CSV data for sales analytics
    cat > sales_data.csv << 'EOF'
date,region,product,sales_amount,quantity,customer_segment
2024-01-15,North America,Product A,1200.50,25,Enterprise
2024-01-15,Europe,Product B,850.75,15,SMB
2024-01-16,Asia Pacific,Product A,2100.25,42,Enterprise
2024-01-16,North America,Product C,675.00,18,Consumer
2024-01-17,Europe,Product A,1450.80,29,Enterprise
2024-01-17,Asia Pacific,Product B,920.45,21,SMB
2024-01-18,North America,Product B,1100.30,22,SMB
2024-01-18,Europe,Product C,780.90,16,Consumer
2024-01-19,Asia Pacific,Product C,1350.60,35,Enterprise
2024-01-19,North America,Product A,1680.75,33,Enterprise
2024-01-20,Europe,Product B,1050.25,20,SMB
2024-01-20,Asia Pacific,Product C,1875.40,38,Enterprise
2024-01-21,North America,Product A,1320.65,27,Enterprise
2024-01-21,Europe,Product C,695.80,14,Consumer
2024-01-22,Asia Pacific,Product B,1150.90,23,SMB
EOF
    
    # Upload sample data to S3
    aws s3 cp sales_data.csv "s3://${BUCKET_NAME}/sales/"
    aws s3 cp sales_data.csv "s3://${BUCKET_NAME}/sales/historical/"
    
    success "Sample data uploaded to S3"
}

# Function to create IAM role for QuickSight
create_iam_role() {
    log "Creating IAM role for QuickSight S3 access..."
    
    # Create trust policy for QuickSight
    cat > quicksight-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "quicksight.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Check if role already exists
    if aws iam get-role --role-name QuickSight-S3-Role &>/dev/null; then
        warn "IAM role QuickSight-S3-Role already exists"
    else
        # Create IAM role
        aws iam create-role --role-name QuickSight-S3-Role \
            --assume-role-policy-document file://quicksight-trust-policy.json
        success "Created IAM role: QuickSight-S3-Role"
    fi
    
    # Create S3 access policy
    cat > quicksight-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy --role-name QuickSight-S3-Role \
        --policy-name QuickSight-S3-Access \
        --policy-document file://quicksight-s3-policy.json
    
    success "IAM role configured with S3 access"
}

# Function to create RDS database
create_rds_database() {
    log "Creating RDS database..."
    
    # Check if RDS instance already exists
    if aws rds describe-db-instances --db-instance-identifier "${DB_IDENTIFIER}" &>/dev/null; then
        warn "RDS instance ${DB_IDENTIFIER} already exists"
        return 0
    fi
    
    # Get default VPC subnets
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --query 'Subnets[0:2].SubnetId' --output text)
    
    if [ -z "$SUBNET_IDS" ]; then
        error "No default subnets found. Please ensure you have a default VPC."
        exit 1
    fi
    
    # Create RDS subnet group
    if ! aws rds describe-db-subnet-groups --db-subnet-group-name quicksight-subnet-group &>/dev/null; then
        aws rds create-db-subnet-group \
            --db-subnet-group-name quicksight-subnet-group \
            --db-subnet-group-description "Subnet group for QuickSight demo" \
            --subnet-ids $SUBNET_IDS
        success "Created RDS subnet group"
    fi
    
    # Create RDS MySQL instance
    log "Creating RDS MySQL instance (this may take 10-15 minutes)..."
    aws rds create-db-instance \
        --db-instance-identifier "${DB_IDENTIFIER}" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password "TempPassword123!" \
        --allocated-storage 20 \
        --db-subnet-group-name quicksight-subnet-group \
        --publicly-accessible \
        --region "${AWS_REGION}"
    
    # Wait for RDS instance to be available
    log "Waiting for RDS instance to be available..."
    aws rds wait db-instance-available --db-instance-identifier "${DB_IDENTIFIER}"
    
    # Get RDS endpoint
    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_IDENTIFIER}" \
        --query 'DBInstances[0].Endpoint.Address' --output text)
    
    echo "RDS_ENDPOINT=${RDS_ENDPOINT}" >> .env_quicksight
    success "RDS instance created at: ${RDS_ENDPOINT}"
}

# Function to create QuickSight data source
create_quicksight_data_source() {
    log "Creating QuickSight S3 data source..."
    
    # Create S3 data source configuration
    cat > s3-data-source.json << EOF
{
    "Name": "Sales-Data-S3",
    "Type": "S3",
    "DataSourceParameters": {
        "S3Parameters": {
            "ManifestFileLocation": {
                "Bucket": "${BUCKET_NAME}",
                "Key": "sales/sales_data.csv"
            }
        }
    }
}
EOF
    
    # Check if data source already exists
    if aws quicksight describe-data-source \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-source-id sales-data-s3 \
        --region "${AWS_REGION}" &>/dev/null; then
        warn "QuickSight data source already exists"
    else
        # Create the data source
        aws quicksight create-data-source \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-source-id sales-data-s3 \
            --cli-input-json file://s3-data-source.json \
            --region "${AWS_REGION}"
        success "S3 data source created"
    fi
}

# Function to create QuickSight dataset
create_quicksight_dataset() {
    log "Creating QuickSight dataset..."
    
    # Create dataset from S3 data source
    cat > dataset-s3.json << EOF
{
    "Name": "Sales Analytics Dataset",
    "PhysicalTableMap": {
        "sales_table": {
            "S3Source": {
                "DataSourceArn": "arn:aws:quicksight:${AWS_REGION}:${AWS_ACCOUNT_ID}:datasource/sales-data-s3",
                "InputColumns": [
                    {"Name": "date", "Type": "STRING"},
                    {"Name": "region", "Type": "STRING"},
                    {"Name": "product", "Type": "STRING"},
                    {"Name": "sales_amount", "Type": "DECIMAL"},
                    {"Name": "quantity", "Type": "INTEGER"},
                    {"Name": "customer_segment", "Type": "STRING"}
                ]
            }
        }
    },
    "LogicalTableMap": {
        "sales_logical": {
            "Alias": "Sales Data",
            "Source": {
                "PhysicalTableId": "sales_table"
            },
            "DataTransforms": [
                {
                    "CastColumnTypeOperation": {
                        "ColumnName": "date",
                        "NewColumnType": "DATETIME",
                        "Format": "yyyy-MM-dd"
                    }
                }
            ]
        }
    }
}
EOF
    
    # Check if dataset already exists
    if aws quicksight describe-data-set \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-set-id sales-dataset \
        --region "${AWS_REGION}" &>/dev/null; then
        warn "QuickSight dataset already exists"
    else
        # Create the dataset
        aws quicksight create-data-set \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-set-id sales-dataset \
            --cli-input-json file://dataset-s3.json \
            --region "${AWS_REGION}"
        success "QuickSight dataset created"
    fi
}

# Function to create QuickSight analysis
create_quicksight_analysis() {
    log "Creating QuickSight analysis..."
    
    # Check if analysis already exists
    if aws quicksight describe-analysis \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --analysis-id sales-analysis \
        --region "${AWS_REGION}" &>/dev/null; then
        warn "QuickSight analysis already exists"
        return 0
    fi
    
    # Create analysis configuration
    cat > analysis-config.json << EOF
{
    "Name": "Sales Performance Analysis",
    "Definition": {
        "DataSetIdentifierDeclarations": [
            {
                "DataSetArn": "arn:aws:quicksight:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/sales-dataset",
                "Identifier": "sales_data"
            }
        ],
        "Sheets": [
            {
                "SheetId": "sales_overview",
                "Name": "Sales Overview",
                "Visuals": [
                    {
                        "BarChartVisual": {
                            "VisualId": "sales_by_region",
                            "Title": {
                                "Text": "Sales by Region"
                            },
                            "ChartConfiguration": {
                                "FieldWells": {
                                    "BarChartAggregatedFieldWells": {
                                        "Category": [
                                            {
                                                "CategoricalDimensionField": {
                                                    "FieldId": "region",
                                                    "Column": {
                                                        "DataSetIdentifier": "sales_data",
                                                        "ColumnName": "region"
                                                    }
                                                }
                                            }
                                        ],
                                        "Values": [
                                            {
                                                "NumericalMeasureField": {
                                                    "FieldId": "sales_amount",
                                                    "Column": {
                                                        "DataSetIdentifier": "sales_data",
                                                        "ColumnName": "sales_amount"
                                                    },
                                                    "AggregationFunction": {
                                                        "SimpleNumericalAggregation": "SUM"
                                                    }
                                                }
                                            }
                                        ]
                                    }
                                }
                            }
                        }
                    }
                ]
            }
        ]
    }
}
EOF
    
    # Create the analysis
    aws quicksight create-analysis \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --analysis-id sales-analysis \
        --cli-input-json file://analysis-config.json \
        --region "${AWS_REGION}"
    
    success "QuickSight analysis created"
}

# Function to create QuickSight dashboard
create_quicksight_dashboard() {
    log "Creating QuickSight dashboard..."
    
    # Check if dashboard already exists
    if aws quicksight describe-dashboard \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --dashboard-id sales-dashboard \
        --region "${AWS_REGION}" &>/dev/null; then
        warn "QuickSight dashboard already exists"
        return 0
    fi
    
    # Create dashboard from analysis
    cat > dashboard-config.json << EOF
{
    "Name": "Sales Performance Dashboard",
    "DashboardId": "sales-dashboard",
    "Definition": {
        "DataSetIdentifierDeclarations": [
            {
                "DataSetArn": "arn:aws:quicksight:${AWS_REGION}:${AWS_ACCOUNT_ID}:dataset/sales-dataset",
                "Identifier": "sales_data"
            }
        ],
        "Sheets": [
            {
                "SheetId": "dashboard_sheet",
                "Name": "Sales Dashboard",
                "Visuals": [
                    {
                        "BarChartVisual": {
                            "VisualId": "sales_by_region_chart",
                            "Title": {
                                "Text": "Sales by Region"
                            }
                        }
                    },
                    {
                        "PieChartVisual": {
                            "VisualId": "sales_by_product_pie",
                            "Title": {
                                "Text": "Sales Distribution by Product"
                            }
                        }
                    }
                ]
            }
        ]
    }
}
EOF
    
    # Create the dashboard
    aws quicksight create-dashboard \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --dashboard-id sales-dashboard \
        --cli-input-json file://dashboard-config.json \
        --region "${AWS_REGION}"
    
    success "QuickSight dashboard created"
}

# Function to configure dashboard permissions
configure_dashboard_permissions() {
    log "Configuring dashboard permissions..."
    
    # Get QuickSight user ARN
    QUICKSIGHT_USER_ARN=$(aws quicksight list-users \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --namespace default --region "${AWS_REGION}" \
        --query 'UserList[0].Arn' --output text 2>/dev/null || echo "")
    
    if [ -z "$QUICKSIGHT_USER_ARN" ]; then
        warn "No QuickSight users found. Skipping permission configuration."
        return 0
    fi
    
    # Create sharing permissions for dashboard
    cat > dashboard-permissions.json << EOF
[
    {
        "Principal": "${QUICKSIGHT_USER_ARN}",
        "Actions": [
            "quicksight:DescribeDashboard",
            "quicksight:ListDashboardVersions",
            "quicksight:QueryDashboard"
        ]
    }
]
EOF
    
    # Update dashboard permissions
    aws quicksight update-dashboard-permissions \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --dashboard-id sales-dashboard \
        --grant-permissions file://dashboard-permissions.json \
        --region "${AWS_REGION}" || warn "Failed to update dashboard permissions"
    
    # Publish dashboard
    aws quicksight update-dashboard-published-version \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --dashboard-id sales-dashboard \
        --version-number 1 \
        --region "${AWS_REGION}" || warn "Failed to publish dashboard"
    
    success "Dashboard permissions configured and published"
}

# Function to create refresh schedule
create_refresh_schedule() {
    log "Creating data refresh schedule..."
    
    # Create refresh schedule for dataset
    cat > refresh-schedule.json << EOF
{
    "ScheduleId": "daily-refresh",
    "RefreshType": "FULL_REFRESH",
    "StartAfterDateTime": "$(date -u -d '+1 day' +%Y-%m-%dT%H:%M:%S)Z",
    "ScheduleFrequency": {
        "Interval": "DAILY",
        "TimeOfTheDay": "06:00"
    }
}
EOF
    
    # Create refresh schedule
    aws quicksight create-refresh-schedule \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-set-id sales-dataset \
        --schedule file://refresh-schedule.json \
        --region "${AWS_REGION}" || warn "Failed to create refresh schedule"
    
    success "Scheduled data refresh configured for daily at 6 AM UTC"
}

# Function to test embedded analytics
test_embedded_analytics() {
    log "Testing embedded analytics URL generation..."
    
    # Generate embed URL for dashboard
    EMBED_URL=$(aws quicksight generate-embed-url-for-anonymous-user \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --namespace default \
        --session-lifetime-in-minutes 60 \
        --authorized-resource-arns \
        "arn:aws:quicksight:${AWS_REGION}:${AWS_ACCOUNT_ID}:dashboard/sales-dashboard" \
        --experience-configuration \
        'DashboardVisual={InitialDashboardVisualId={DashboardId=sales-dashboard,SheetId=dashboard_sheet,VisualId=sales_by_region_chart}}' \
        --region "${AWS_REGION}" \
        --query 'EmbedUrl' --output text 2>/dev/null || echo "")
    
    if [ -n "$EMBED_URL" ]; then
        success "Embedded analytics URL generated successfully"
        log "Embed URL: ${EMBED_URL}"
        echo "EMBED_URL=${EMBED_URL}" >> .env_quicksight
    else
        warn "Failed to generate embedded analytics URL"
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        success "✅ S3 bucket is accessible"
    else
        error "❌ S3 bucket validation failed"
    fi
    
    # Check RDS instance
    RDS_STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_IDENTIFIER}" \
        --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "not-found")
    
    if [ "$RDS_STATUS" = "available" ]; then
        success "✅ RDS instance is available"
    else
        warn "⚠️ RDS instance status: ${RDS_STATUS}"
    fi
    
    # Check QuickSight data source
    DS_STATUS=$(aws quicksight describe-data-source \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-source-id sales-data-s3 \
        --region "${AWS_REGION}" \
        --query 'DataSource.Status' --output text 2>/dev/null || echo "not-found")
    
    if [ "$DS_STATUS" = "CREATION_SUCCESSFUL" ]; then
        success "✅ QuickSight data source is ready"
    else
        warn "⚠️ QuickSight data source status: ${DS_STATUS}"
    fi
    
    # Check QuickSight dataset
    DATASET_STATUS=$(aws quicksight describe-data-set \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-set-id sales-dataset \
        --region "${AWS_REGION}" \
        --query 'DataSet.Name' --output text 2>/dev/null || echo "not-found")
    
    if [ "$DATASET_STATUS" = "Sales Analytics Dataset" ]; then
        success "✅ QuickSight dataset is ready"
    else
        warn "⚠️ QuickSight dataset not found or not ready"
    fi
    
    # Check QuickSight dashboard
    DASHBOARD_STATUS=$(aws quicksight describe-dashboard \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --dashboard-id sales-dashboard \
        --region "${AWS_REGION}" \
        --query 'Dashboard.Version.Status' --output text 2>/dev/null || echo "not-found")
    
    if [ "$DASHBOARD_STATUS" = "CREATION_SUCCESSFUL" ]; then
        success "✅ QuickSight dashboard is ready"
    else
        warn "⚠️ QuickSight dashboard status: ${DASHBOARD_STATUS}"
    fi
}

# Function to display completion message
display_completion_message() {
    success "🎉 Deployment completed successfully!"
    echo ""
    echo "=== QuickSight Business Intelligence Solution Deployed ==="
    echo ""
    echo "📊 Resources Created:"
    echo "  • S3 Bucket: ${BUCKET_NAME}"
    echo "  • RDS Instance: ${DB_IDENTIFIER}"
    echo "  • QuickSight Data Source: sales-data-s3"
    echo "  • QuickSight Dataset: sales-dataset"
    echo "  • QuickSight Analysis: sales-analysis"
    echo "  • QuickSight Dashboard: sales-dashboard"
    echo ""
    echo "🔗 Access your dashboard at:"
    echo "  https://${AWS_REGION}.quicksight.aws.amazon.com/sn/dashboards/sales-dashboard"
    echo ""
    echo "💡 Next Steps:"
    echo "  1. Open QuickSight console to view and customize your dashboard"
    echo "  2. Add more data sources and create additional visualizations"
    echo "  3. Share dashboards with team members"
    echo "  4. Set up additional data refresh schedules"
    echo ""
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo ""
    echo "📄 Environment variables saved to .env_quicksight"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f sales_data.csv quicksight-trust-policy.json quicksight-s3-policy.json
    rm -f s3-data-source.json dataset-s3.json analysis-config.json
    rm -f dashboard-config.json dashboard-permissions.json refresh-schedule.json
}

# Main deployment function
main() {
    log "Starting QuickSight Business Intelligence Solution deployment..."
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_resources
    create_iam_role
    create_rds_database
    create_quicksight_data_source
    create_quicksight_dataset
    create_quicksight_analysis
    create_quicksight_dashboard
    configure_dashboard_permissions
    create_refresh_schedule
    test_embedded_analytics
    validate_deployment
    cleanup_temp_files
    display_completion_message
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up any created resources."; exit 1' INT TERM

# Run main function
main "$@"