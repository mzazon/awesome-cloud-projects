#!/bin/bash

# Deploy script for Business Intelligence Dashboards with Amazon QuickSight
# This script automates the deployment of a complete QuickSight BI solution

set -euo pipefail

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive 2>/dev/null || true
        aws s3 rb s3://${S3_BUCKET_NAME} 2>/dev/null || true
    fi
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess 2>/dev/null || true
        aws iam delete-role --role-name ${IAM_ROLE_NAME} 2>/dev/null || true
    fi
    rm -f sales_data.csv quicksight-trust-policy.json 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is available (helpful for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    # Verify required AWS permissions
    log "Verifying AWS permissions..."
    local caller_identity=$(aws sts get-caller-identity)
    local aws_account_id=$(echo $caller_identity | jq -r '.Account' 2>/dev/null || aws sts get-caller-identity --query Account --output text)
    local user_arn=$(echo $caller_identity | jq -r '.Arn' 2>/dev/null || aws sts get-caller-identity --query Arn --output text)
    
    log "Deploying as: $user_arn"
    log "AWS Account: $aws_account_id"
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Set resource names
    export QUICKSIGHT_ACCOUNT_NAME="quicksight-demo-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="quicksight-data-${RANDOM_SUFFIX}"
    export RDS_DB_NAME="quicksight-db-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="QuickSight-DataSource-Role-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .deployment_vars << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export QUICKSIGHT_ACCOUNT_NAME="$QUICKSIGHT_ACCOUNT_NAME"
export S3_BUCKET_NAME="$S3_BUCKET_NAME"
export RDS_DB_NAME="$RDS_DB_NAME"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    success "Environment variables configured"
    log "S3 Bucket: $S3_BUCKET_NAME"
    log "IAM Role: $IAM_ROLE_NAME"
    log "Region: $AWS_REGION"
}

# Function to create sample data
create_sample_data() {
    log "Creating sample data..."
    
    # Create S3 bucket for sample data
    if aws s3 ls s3://${S3_BUCKET_NAME} 2>/dev/null; then
        warning "S3 bucket already exists: ${S3_BUCKET_NAME}"
    else
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb s3://${S3_BUCKET_NAME}
        else
            aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
        fi
        success "S3 bucket created: ${S3_BUCKET_NAME}"
    fi
    
    # Create sample CSV data
    cat > sales_data.csv << 'EOF'
date,region,product,sales_amount,quantity
2024-01-01,North,Widget A,1200,10
2024-01-01,South,Widget B,800,8
2024-01-02,North,Widget A,1400,12
2024-01-02,South,Widget B,900,9
2024-01-03,East,Widget C,1100,11
2024-01-03,West,Widget A,1300,13
2024-01-04,North,Widget B,1600,16
2024-01-04,South,Widget C,1000,10
2024-01-05,East,Widget A,1500,15
2024-01-05,West,Widget B,1100,11
2024-01-06,North,Widget C,1750,17
2024-01-06,South,Widget A,950,9
2024-01-07,East,Widget B,1350,13
2024-01-07,West,Widget C,1450,14
2024-01-08,North,Widget A,1650,16
EOF
    
    # Upload sample data to S3
    aws s3 cp sales_data.csv s3://${S3_BUCKET_NAME}/data/sales_data.csv
    
    success "Sample data uploaded to S3"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for QuickSight..."
    
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
    if aws iam get-role --role-name ${IAM_ROLE_NAME} &>/dev/null; then
        warning "IAM role already exists: ${IAM_ROLE_NAME}"
    else
        # Create IAM role
        aws iam create-role \
            --role-name ${IAM_ROLE_NAME} \
            --assume-role-policy-document file://quicksight-trust-policy.json \
            --description "Role for QuickSight to access data sources"
        
        # Attach S3 read permissions
        aws iam attach-role-policy \
            --role-name ${IAM_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
        
        # Wait for role to be ready
        log "Waiting for IAM role to be ready..."
        sleep 10
        
        success "IAM role created: ${IAM_ROLE_NAME}"
    fi
}

# Function to check QuickSight account
check_quicksight_account() {
    log "Checking QuickSight account status..."
    
    if aws quicksight describe-account-settings \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --region ${AWS_REGION} &>/dev/null; then
        success "QuickSight account is already set up"
        return 0
    else
        warning "QuickSight account not found"
        echo ""
        echo "Please set up your QuickSight account manually:"
        echo "1. Visit: https://quicksight.aws.amazon.com"
        echo "2. Choose your edition (Standard or Enterprise)"
        echo "3. Set account name to: ${QUICKSIGHT_ACCOUNT_NAME}"
        echo "4. Grant access to Amazon S3"
        echo ""
        read -p "Press Enter after completing QuickSight account setup..."
        
        # Verify setup
        if aws quicksight describe-account-settings \
            --aws-account-id ${AWS_ACCOUNT_ID} \
            --region ${AWS_REGION} &>/dev/null; then
            success "QuickSight account verified"
        else
            error "QuickSight account setup verification failed"
            exit 1
        fi
    fi
}

# Function to create QuickSight resources
create_quicksight_resources() {
    log "Creating QuickSight resources..."
    
    # Store resource IDs
    S3_DATA_SOURCE_ID="s3-sales-data-${RANDOM_SUFFIX}"
    DATASET_ID="sales-dataset-${RANDOM_SUFFIX}"
    ANALYSIS_ID="sales-analysis-${RANDOM_SUFFIX}"
    DASHBOARD_ID="sales-dashboard-${RANDOM_SUFFIX}"
    
    # Add to deployment vars
    echo "export S3_DATA_SOURCE_ID=\"$S3_DATA_SOURCE_ID\"" >> .deployment_vars
    echo "export DATASET_ID=\"$DATASET_ID\"" >> .deployment_vars
    echo "export ANALYSIS_ID=\"$ANALYSIS_ID\"" >> .deployment_vars
    echo "export DASHBOARD_ID=\"$DASHBOARD_ID\"" >> .deployment_vars
    
    # Create S3 data source
    log "Creating S3 data source..."
    aws quicksight create-data-source \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --data-source-id "$S3_DATA_SOURCE_ID" \
        --name "Sales Data S3 Source" \
        --type "S3" \
        --data-source-parameters '{
            "S3Parameters": {
                "ManifestFileLocation": {
                    "Bucket": "'${S3_BUCKET_NAME}'",
                    "Key": "data/sales_data.csv"
                }
            }
        }' \
        --region ${AWS_REGION} || warning "Data source may already exist"
    
    success "S3 data source created: ${S3_DATA_SOURCE_ID}"
    
    # Create dataset
    log "Creating dataset..."
    aws quicksight create-data-set \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --data-set-id "$DATASET_ID" \
        --name "Sales Dataset" \
        --physical-table-map '{
            "SalesTable": {
                "S3Source": {
                    "DataSourceArn": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':datasource/'${S3_DATA_SOURCE_ID}'",
                    "UploadSettings": {
                        "Format": "CSV",
                        "StartFromRow": 1,
                        "ContainsHeader": true,
                        "Delimiter": ","
                    },
                    "InputColumns": [
                        {
                            "Name": "date",
                            "Type": "DATETIME"
                        },
                        {
                            "Name": "region",
                            "Type": "STRING"
                        },
                        {
                            "Name": "product",
                            "Type": "STRING"
                        },
                        {
                            "Name": "sales_amount",
                            "Type": "DECIMAL"
                        },
                        {
                            "Name": "quantity",
                            "Type": "INTEGER"
                        }
                    ]
                }
            }
        }' \
        --permissions '[
            {
                "Principal": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':user/default/'$(aws sts get-caller-identity --query UserName --output text)'",
                "Actions": [
                    "quicksight:DescribeDataSet",
                    "quicksight:DescribeDataSetPermissions",
                    "quicksight:PassDataSet",
                    "quicksight:DescribeIngestion",
                    "quicksight:ListIngestions"
                ]
            }
        ]' \
        --region ${AWS_REGION} || warning "Dataset may already exist"
    
    success "Dataset created: ${DATASET_ID}"
    
    # Create analysis
    log "Creating analysis..."
    aws quicksight create-analysis \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --analysis-id "$ANALYSIS_ID" \
        --name "Sales Analysis" \
        --definition '{
            "DataSetIdentifierDeclarations": [
                {
                    "DataSetArn": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':dataset/'${DATASET_ID}'",
                    "Identifier": "SalesDataSet"
                }
            ],
            "Sheets": [
                {
                    "SheetId": "sheet1",
                    "Name": "Sales Overview",
                    "Visuals": [
                        {
                            "BarChartVisual": {
                                "VisualId": "sales-by-region",
                                "Title": {
                                    "Visibility": "VISIBLE",
                                    "FormatText": {
                                        "PlainText": "Sales by Region"
                                    }
                                },
                                "FieldWells": {
                                    "BarChartAggregatedFieldWells": {
                                        "Category": [
                                            {
                                                "CategoricalDimensionField": {
                                                    "FieldId": "region",
                                                    "Column": {
                                                        "DataSetIdentifier": "SalesDataSet",
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
                                                        "DataSetIdentifier": "SalesDataSet",
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
                    ]
                }
            ]
        }' \
        --permissions '[
            {
                "Principal": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':user/default/'$(aws sts get-caller-identity --query UserName --output text)'",
                "Actions": [
                    "quicksight:RestoreAnalysis",
                    "quicksight:UpdateAnalysisPermissions",
                    "quicksight:DeleteAnalysis",
                    "quicksight:QueryAnalysis",
                    "quicksight:DescribeAnalysisPermissions",
                    "quicksight:DescribeAnalysis",
                    "quicksight:UpdateAnalysis"
                ]
            }
        ]' \
        --region ${AWS_REGION} || warning "Analysis may already exist"
    
    success "Analysis created: ${ANALYSIS_ID}"
    
    # Create dashboard
    log "Creating dashboard..."
    aws quicksight create-dashboard \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --dashboard-id "$DASHBOARD_ID" \
        --name "Sales Dashboard" \
        --source-entity '{
            "SourceTemplate": {
                "DataSetReferences": [
                    {
                        "DataSetArn": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':dataset/'${DATASET_ID}'",
                        "DataSetPlaceholder": "SalesDataSet"
                    }
                ],
                "Arn": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':analysis/'${ANALYSIS_ID}'"
            }
        }' \
        --permissions '[
            {
                "Principal": "arn:aws:quicksight:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':user/default/'$(aws sts get-caller-identity --query UserName --output text)'",
                "Actions": [
                    "quicksight:DescribeDashboard",
                    "quicksight:ListDashboardVersions",
                    "quicksight:UpdateDashboardPermissions",
                    "quicksight:QueryDashboard",
                    "quicksight:UpdateDashboard",
                    "quicksight:DeleteDashboard",
                    "quicksight:DescribeDashboardPermissions",
                    "quicksight:UpdateDashboardPublishedVersion"
                ]
            }
        ]' \
        --region ${AWS_REGION} || warning "Dashboard may already exist"
    
    success "Dashboard created: ${DASHBOARD_ID}"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Source the deployment variables
    source .deployment_vars
    
    # Check data source
    if aws quicksight describe-data-source \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --data-source-id ${S3_DATA_SOURCE_ID} \
        --region ${AWS_REGION} &>/dev/null; then
        success "Data source verification passed"
    else
        error "Data source verification failed"
    fi
    
    # Check dataset
    if aws quicksight describe-data-set \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --data-set-id ${DATASET_ID} \
        --region ${AWS_REGION} &>/dev/null; then
        success "Dataset verification passed"
    else
        error "Dataset verification failed"
    fi
    
    # Check dashboard
    if aws quicksight describe-dashboard \
        --aws-account-id ${AWS_ACCOUNT_ID} \
        --dashboard-id ${DASHBOARD_ID} \
        --region ${AWS_REGION} &>/dev/null; then
        success "Dashboard verification passed"
    else
        error "Dashboard verification failed"
    fi
}

# Function to display deployment summary
display_summary() {
    source .deployment_vars
    
    echo ""
    echo "=========================================="
    echo "   DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo ""
    success "QuickSight Business Intelligence Dashboard deployed successfully!"
    echo ""
    echo "📊 Dashboard Details:"
    echo "   Dashboard ID: ${DASHBOARD_ID}"
    echo "   Dashboard URL: https://quicksight.aws.amazon.com/sn/dashboards/${DASHBOARD_ID}"
    echo ""
    echo "🗂️  Resources Created:"
    echo "   S3 Bucket: ${S3_BUCKET_NAME}"
    echo "   IAM Role: ${IAM_ROLE_NAME}"
    echo "   Data Source: ${S3_DATA_SOURCE_ID}"
    echo "   Dataset: ${DATASET_ID}"
    echo "   Analysis: ${ANALYSIS_ID}"
    echo ""
    echo "🌍 Region: ${AWS_REGION}"
    echo "🔑 Account: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Access your dashboard at the URL above"
    echo "   2. Customize visualizations in the QuickSight console"
    echo "   3. Share dashboards with team members"
    echo "   4. Set up automated data refresh if needed"
    echo ""
    echo "💰 Cost Monitoring:"
    echo "   QuickSight charges apply based on your edition and user count"
    echo "   S3 storage costs are minimal for this demo dataset"
    echo ""
    echo "🧹 Cleanup:"
    echo "   Run './destroy.sh' to remove all resources when done"
    echo ""
    echo "=========================================="
}

# Main execution
main() {
    log "Starting QuickSight Business Intelligence Dashboard deployment..."
    
    check_prerequisites
    setup_environment
    create_sample_data
    create_iam_role
    check_quicksight_account
    create_quicksight_resources
    verify_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"