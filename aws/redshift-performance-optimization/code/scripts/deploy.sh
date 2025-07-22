#!/bin/bash

# Redshift Performance Optimization Deployment Script
# This script deploys the complete Redshift performance optimization solution
# including monitoring, alerting, and automated maintenance components

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_DIR}/deployment.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Configuration variables with defaults
CLUSTER_IDENTIFIER="${CLUSTER_IDENTIFIER:-my-redshift-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DB_NAME="${DB_NAME:-mydb}"
DB_USER="${DB_USER:-admin}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-admin@example.com}"
PARAMETER_GROUP_NAME="optimized-wlm-config-${TIMESTAMP}"
MAINTENANCE_PASSWORD="${MAINTENANCE_PASSWORD:-SecureMaintenancePassword123!}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Colored output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    error "Script failed at line $line_number with exit code $exit_code"
    error "Check the log file at: $LOG_FILE"
    exit $exit_code
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Cleanup function for partial deployments
cleanup_on_failure() {
    warning "Cleaning up partial deployment due to failure..."
    
    # Remove CloudWatch resources if they exist
    aws cloudwatch delete-alarms \
        --alarm-names "Redshift-High-CPU-Usage" "Redshift-High-Queue-Length" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    aws cloudwatch delete-dashboards \
        --dashboard-names "Redshift-Performance-Dashboard" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Remove Lambda function if it exists
    aws lambda delete-function \
        --function-name redshift-maintenance \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Remove IAM role if it exists
    aws iam detach-role-policy \
        --role-name RedshiftMaintenanceLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        2>/dev/null || true
    aws iam delete-role \
        --role-name RedshiftMaintenanceLambdaRole \
        2>/dev/null || true
    
    warning "Partial cleanup completed"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        error "AWS credentials not configured or invalid. Please configure AWS CLI."
        exit 1
    fi
    
    # Check if psql is available (optional but recommended)
    if ! command -v psql &> /dev/null; then
        warning "psql is not installed. Some database operations may not work."
        warning "Consider installing PostgreSQL client tools."
    fi
    
    # Check if zip is available (required for Lambda deployment)
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Verify Redshift cluster exists
    if ! aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER_IDENTIFIER" \
        --region "$AWS_REGION" &> /dev/null; then
        error "Redshift cluster '$CLUSTER_IDENTIFIER' not found in region '$AWS_REGION'"
        error "Please create the cluster first or update CLUSTER_IDENTIFIER variable"
        exit 1
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_ACCOUNT_ID
    
    success "Prerequisites check completed"
}

# Function to validate email address format
validate_email() {
    local email=$1
    if [[ $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get cluster endpoint
get_cluster_endpoint() {
    info "Getting Redshift cluster endpoint..."
    
    CLUSTER_ENDPOINT=$(aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER_IDENTIFIER" \
        --region "$AWS_REGION" \
        --query 'Clusters[0].Endpoint.Address' \
        --output text)
    
    if [ "$CLUSTER_ENDPOINT" = "None" ] || [ -z "$CLUSTER_ENDPOINT" ]; then
        error "Could not retrieve cluster endpoint. Cluster may not be available."
        exit 1
    fi
    
    export CLUSTER_ENDPOINT
    success "Cluster endpoint retrieved: $CLUSTER_ENDPOINT"
}

# Function to create CloudWatch log group
create_log_group() {
    info "Creating CloudWatch log group..."
    
    if aws logs describe-log-groups \
        --log-group-name-prefix "/aws/redshift/performance-metrics" \
        --region "$AWS_REGION" \
        --query 'logGroups[?logGroupName==`/aws/redshift/performance-metrics`]' \
        --output text | grep -q "/aws/redshift/performance-metrics"; then
        info "Log group already exists, skipping creation"
    else
        aws logs create-log-group \
            --log-group-name /aws/redshift/performance-metrics \
            --region "$AWS_REGION"
        success "CloudWatch log group created"
    fi
}

# Function to create SNS topic
create_sns_topic() {
    info "Creating SNS topic for performance alerts..."
    
    # Check if topic already exists
    EXISTING_TOPIC=$(aws sns list-topics \
        --region "$AWS_REGION" \
        --query "Topics[?contains(TopicArn, 'redshift-performance-alerts')].TopicArn" \
        --output text)
    
    if [ -n "$EXISTING_TOPIC" ]; then
        TOPIC_ARN="$EXISTING_TOPIC"
        info "Using existing SNS topic: $TOPIC_ARN"
    else
        TOPIC_ARN=$(aws sns create-topic \
            --name redshift-performance-alerts \
            --region "$AWS_REGION" \
            --query 'TopicArn' \
            --output text)
        success "SNS topic created: $TOPIC_ARN"
    fi
    
    # Subscribe email if provided and valid
    if [ "$NOTIFICATION_EMAIL" != "admin@example.com" ] && validate_email "$NOTIFICATION_EMAIL"; then
        info "Subscribing email $NOTIFICATION_EMAIL to SNS topic..."
        aws sns subscribe \
            --topic-arn "$TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$NOTIFICATION_EMAIL" \
            --region "$AWS_REGION"
        info "Email subscription created. Please check your email and confirm the subscription."
    else
        warning "No valid notification email provided. Skipping email subscription."
        warning "You can manually subscribe to SNS topic: $TOPIC_ARN"
    fi
    
    export TOPIC_ARN
}

# Function to create parameter group
create_parameter_group() {
    info "Creating Redshift parameter group..."
    
    # Check if parameter group already exists
    if aws redshift describe-cluster-parameter-groups \
        --parameter-group-name "$PARAMETER_GROUP_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        info "Parameter group already exists: $PARAMETER_GROUP_NAME"
    else
        aws redshift create-cluster-parameter-group \
            --parameter-group-name "$PARAMETER_GROUP_NAME" \
            --parameter-group-family redshift-1.0 \
            --description "Optimized WLM configuration for performance - Created $(date)" \
            --region "$AWS_REGION"
        success "Parameter group created: $PARAMETER_GROUP_NAME"
    fi
    
    # Configure automatic WLM
    info "Configuring automatic WLM..."
    aws redshift modify-cluster-parameter-group \
        --parameter-group-name "$PARAMETER_GROUP_NAME" \
        --parameters "ParameterName=wlm_json_configuration,ParameterValue=[{\"query_group\":[],\"query_group_wild_card\":0,\"user_group\":[],\"user_group_wild_card\":0,\"concurrency_scaling\":\"auto\"}]" \
        --region "$AWS_REGION"
    
    # Apply parameter group to cluster
    info "Applying parameter group to cluster..."
    aws redshift modify-cluster \
        --cluster-identifier "$CLUSTER_IDENTIFIER" \
        --cluster-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --apply-immediately \
        --region "$AWS_REGION"
    
    success "Parameter group applied to cluster"
}

# Function to create Lambda function
create_lambda_function() {
    info "Creating Lambda function for automated maintenance..."
    
    # Create the Lambda function code
    cat > "${PROJECT_DIR}/maintenance_function.py" << 'EOF'
import json
import psycopg2
import os
from datetime import datetime
import boto3

def lambda_handler(event, context):
    # Environment variables
    host = os.environ.get('REDSHIFT_HOST')
    database = os.environ.get('REDSHIFT_DATABASE', 'mydb')
    user = os.environ.get('REDSHIFT_USER', 'admin')
    password = os.environ.get('REDSHIFT_PASSWORD')
    
    # CloudWatch client for custom metrics
    cloudwatch = boto3.client('cloudwatch')
    
    results = {
        'tables_vacuumed': 0,
        'tables_analyzed': 0,
        'errors': []
    }
    
    try:
        # Connect to Redshift
        conn = psycopg2.connect(
            host=host,
            database=database,
            user=user,
            password=password,
            port=5439,
            connect_timeout=30
        )
        
        cur = conn.cursor()
        
        # Get tables that need VACUUM
        cur.execute("""
            SELECT TRIM(name) as table_name,
                   unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 as pct_unsorted,
                   rows
            FROM stv_tbl_perm
            WHERE unsorted > 0 
                AND rows > 1000
                AND TRIM(name) NOT LIKE 'pg_%'
                AND TRIM(name) NOT LIKE 'information_schema%'
            ORDER BY pct_unsorted DESC
            LIMIT 10;
        """)
        
        tables_to_maintain = cur.fetchall()
        
        for table_name, pct_unsorted, row_count in tables_to_maintain:
            try:
                # Only VACUUM if >10% unsorted to avoid unnecessary work
                if pct_unsorted > 10:
                    print(f"Vacuuming table: {table_name} ({pct_unsorted:.1f}% unsorted, {row_count} rows)")
                    
                    # Use VACUUM with minimal locking
                    cur.execute(f"VACUUM {table_name};")
                    results['tables_vacuumed'] += 1
                    
                    # Always run ANALYZE after VACUUM
                    cur.execute(f"ANALYZE {table_name};")
                    results['tables_analyzed'] += 1
                    
                    # Send custom metric to CloudWatch
                    cloudwatch.put_metric_data(
                        Namespace='Redshift/Maintenance',
                        MetricData=[
                            {
                                'MetricName': 'TableMaintenance',
                                'Dimensions': [
                                    {
                                        'Name': 'TableName',
                                        'Value': table_name
                                    },
                                    {
                                        'Name': 'Operation',
                                        'Value': 'VACUUM'
                                    }
                                ],
                                'Value': pct_unsorted,
                                'Unit': 'Percent'
                            }
                        ]
                    )
                    
                elif pct_unsorted > 5:
                    # Just analyze tables that are moderately unsorted
                    print(f"Analyzing table: {table_name} ({pct_unsorted:.1f}% unsorted)")
                    cur.execute(f"ANALYZE {table_name};")
                    results['tables_analyzed'] += 1
                    
            except Exception as e:
                error_msg = f"Error processing table {table_name}: {str(e)}"
                print(error_msg)
                results['errors'].append(error_msg)
                continue
        
        conn.commit()
        cur.close()
        conn.close()
        
        # Send summary metric
        cloudwatch.put_metric_data(
            Namespace='Redshift/Maintenance',
            MetricData=[
                {
                    'MetricName': 'MaintenanceJobsCompleted',
                    'Value': results['tables_vacuumed'] + results['tables_analyzed'],
                    'Unit': 'Count'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Maintenance completed',
                'tables_vacuumed': results['tables_vacuumed'],
                'tables_analyzed': results['tables_analyzed'],
                'errors': results['errors']
            })
        }
        
    except Exception as e:
        error_msg = f"Maintenance job failed: {str(e)}"
        print(error_msg)
        
        # Send failure metric
        try:
            cloudwatch.put_metric_data(
                Namespace='Redshift/Maintenance',
                MetricData=[
                    {
                        'MetricName': 'MaintenanceJobsFailures',
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        except:
            pass
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg
            })
        }
EOF

    # Create deployment package
    cd "$PROJECT_DIR"
    zip -q maintenance_function.zip maintenance_function.py
    
    # Create IAM role for Lambda
    info "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if aws iam get-role --role-name RedshiftMaintenanceLambdaRole --region "$AWS_REGION" &> /dev/null; then
        info "IAM role already exists"
        LAMBDA_ROLE_ARN=$(aws iam get-role \
            --role-name RedshiftMaintenanceLambdaRole \
            --query 'Role.Arn' \
            --output text)
    else
        LAMBDA_ROLE_ARN=$(aws iam create-role \
            --role-name RedshiftMaintenanceLambdaRole \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {"Service": "lambda.amazonaws.com"},
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' \
            --query 'Role.Arn' \
            --output text \
            --region "$AWS_REGION")
        
        success "IAM role created: $LAMBDA_ROLE_ARN"
        
        # Attach basic execution policy
        aws iam attach-role-policy \
            --role-name RedshiftMaintenanceLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            --region "$AWS_REGION"
        
        # Attach CloudWatch policy for custom metrics
        aws iam attach-role-policy \
            --role-name RedshiftMaintenanceLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
            --region "$AWS_REGION"
        
        # Wait for role to be ready
        info "Waiting for IAM role to be ready..."
        sleep 10
    fi
    
    # Create or update Lambda function
    if aws lambda get-function --function-name redshift-maintenance --region "$AWS_REGION" &> /dev/null; then
        info "Updating existing Lambda function..."
        aws lambda update-function-code \
            --function-name redshift-maintenance \
            --zip-file fileb://maintenance_function.zip \
            --region "$AWS_REGION"
        
        aws lambda update-function-configuration \
            --function-name redshift-maintenance \
            --environment Variables="{REDSHIFT_HOST=$CLUSTER_ENDPOINT,REDSHIFT_DATABASE=$DB_NAME,REDSHIFT_USER=$DB_USER,REDSHIFT_PASSWORD=$MAINTENANCE_PASSWORD}" \
            --timeout 300 \
            --region "$AWS_REGION"
    else
        info "Creating new Lambda function..."
        LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
            --function-name redshift-maintenance \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler maintenance_function.lambda_handler \
            --zip-file fileb://maintenance_function.zip \
            --environment Variables="{REDSHIFT_HOST=$CLUSTER_ENDPOINT,REDSHIFT_DATABASE=$DB_NAME,REDSHIFT_USER=$DB_USER,REDSHIFT_PASSWORD=$MAINTENANCE_PASSWORD}" \
            --timeout 300 \
            --description "Automated Redshift maintenance tasks - VACUUM and ANALYZE" \
            --region "$AWS_REGION" \
            --query 'FunctionArn' \
            --output text)
        
        success "Lambda function created: $LAMBDA_FUNCTION_ARN"
    fi
    
    # Clean up local files
    rm -f maintenance_function.zip maintenance_function.py
    
    export LAMBDA_FUNCTION_ARN
}

# Function to create CloudWatch dashboard
create_dashboard() {
    info "Creating CloudWatch dashboard..."
    
    cat > "${PROJECT_DIR}/dashboard_config.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Redshift", "CPUUtilization", "ClusterIdentifier", "$CLUSTER_IDENTIFIER"],
                    [".", "DatabaseConnections", ".", "."],
                    [".", "HealthStatus", ".", "."],
                    [".", "MaintenanceMode", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Redshift Cluster Health Metrics",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Redshift", "QueueLength", "ClusterIdentifier", "$CLUSTER_IDENTIFIER"],
                    [".", "WLMQueueLength", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Query Queue Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Redshift", "NetworkReceiveThroughput", "ClusterIdentifier", "$CLUSTER_IDENTIFIER"],
                    [".", "NetworkTransmitThroughput", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Network Throughput",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["Redshift/Maintenance", "MaintenanceJobsCompleted"],
                    [".", "MaintenanceJobsFailures"],
                    [".", "TableMaintenance"]
                ],
                "period": 3600,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "Maintenance Job Metrics"
            }
        }
    ]
}
EOF

    aws cloudwatch put-dashboard \
        --dashboard-name "Redshift-Performance-Dashboard" \
        --dashboard-body file://"${PROJECT_DIR}/dashboard_config.json" \
        --region "$AWS_REGION"
    
    rm -f "${PROJECT_DIR}/dashboard_config.json"
    success "CloudWatch dashboard created"
}

# Function to create CloudWatch alarms
create_alarms() {
    info "Creating CloudWatch alarms..."
    
    # High CPU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Redshift-High-CPU-Usage" \
        --alarm-description "Alert when Redshift CPU usage is consistently high" \
        --metric-name CPUUtilization \
        --namespace AWS/Redshift \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions "$TOPIC_ARN" \
        --ok-actions "$TOPIC_ARN" \
        --dimensions Name=ClusterIdentifier,Value="$CLUSTER_IDENTIFIER" \
        --region "$AWS_REGION"
    
    # High queue length alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Redshift-High-Queue-Length" \
        --alarm-description "Alert when query queue length indicates capacity constraints" \
        --metric-name QueueLength \
        --namespace AWS/Redshift \
        --statistic Average \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$TOPIC_ARN" \
        --ok-actions "$TOPIC_ARN" \
        --dimensions Name=ClusterIdentifier,Value="$CLUSTER_IDENTIFIER" \
        --region "$AWS_REGION"
    
    # Low health status alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Redshift-Health-Check" \
        --alarm-description "Alert when Redshift cluster health is degraded" \
        --metric-name HealthStatus \
        --namespace AWS/Redshift \
        --statistic Average \
        --period 300 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$TOPIC_ARN" \
        --dimensions Name=ClusterIdentifier,Value="$CLUSTER_IDENTIFIER" \
        --region "$AWS_REGION"
    
    # Maintenance job failure alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Redshift-Maintenance-Failures" \
        --alarm-description "Alert when automated maintenance jobs fail" \
        --metric-name MaintenanceJobsFailures \
        --namespace Redshift/Maintenance \
        --statistic Sum \
        --period 3600 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$TOPIC_ARN" \
        --treat-missing-data breaching \
        --region "$AWS_REGION"
    
    success "CloudWatch alarms created"
}

# Function to schedule automated maintenance
schedule_maintenance() {
    info "Setting up automated maintenance schedule..."
    
    # Create EventBridge rule for nightly maintenance
    aws events put-rule \
        --name "redshift-nightly-maintenance" \
        --schedule-expression "cron(0 2 * * ? *)" \
        --description "Run Redshift maintenance tasks nightly at 2 AM UTC" \
        --state ENABLED \
        --region "$AWS_REGION"
    
    # Get Lambda function ARN
    LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name redshift-maintenance \
        --region "$AWS_REGION" \
        --query 'Configuration.FunctionArn' \
        --output text)
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "redshift-nightly-maintenance" \
        --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN" \
        --region "$AWS_REGION"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name redshift-maintenance \
        --statement-id "allow-eventbridge-$(date +%s)" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/redshift-nightly-maintenance" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    success "Automated maintenance scheduled for 2 AM UTC daily"
}

# Function to create SQL analysis scripts
create_analysis_scripts() {
    info "Creating SQL analysis scripts..."
    
    cat > "${PROJECT_DIR}/analyze_performance.sql" << 'EOF'
-- Redshift Performance Analysis Queries
-- Run these queries to analyze your cluster's performance

-- Top 10 slowest queries in the last 24 hours
SELECT 
    query,
    TRIM(database) as database,
    TRIM(user_name) as user_name,
    starttime,
    total_exec_time/1000000.0 as exec_time_seconds,
    aborted,
    LEFT(TRIM(querytxt), 100) as query_text_preview
FROM stl_query 
WHERE starttime >= CURRENT_DATE - 1
    AND total_exec_time > 0
ORDER BY total_exec_time DESC 
LIMIT 10;

-- Query queue wait times
SELECT 
    w.query,
    w.service_class,
    w.queue_start_time,
    w.queue_end_time,
    DATEDIFF(seconds, w.queue_start_time, w.queue_end_time) as queue_seconds,
    q.total_exec_time/1000000.0 as exec_time_seconds,
    LEFT(TRIM(q.querytxt), 100) as query_text_preview
FROM stl_wlm_query w
JOIN stl_query q ON w.query = q.query
WHERE w.queue_start_time >= CURRENT_DATE - 1
    AND DATEDIFF(seconds, w.queue_start_time, w.queue_end_time) > 0
ORDER BY queue_seconds DESC
LIMIT 10;

-- Table distribution analysis (check for skew)
SELECT
    TRIM(name) as table_name,
    max_blocks_per_slice - min_blocks_per_slice as skew,
    tbl_rows,
    max_blocks_per_slice,
    min_blocks_per_slice,
    CASE 
        WHEN max_blocks_per_slice - min_blocks_per_slice > 5 THEN 'HIGH_SKEW'
        WHEN max_blocks_per_slice - min_blocks_per_slice > 2 THEN 'MODERATE_SKEW'
        ELSE 'LOW_SKEW'
    END as skew_level
FROM (
    SELECT 
        TRIM(t.name) as name,
        t.tbl_rows,
        MIN(ti.max_blocks_per_slice) as min_blocks_per_slice,
        MAX(ti.max_blocks_per_slice) as max_blocks_per_slice
    FROM (
        SELECT 
            tbl,
            slice,
            COUNT(blocknum) as max_blocks_per_slice
        FROM stv_blocklist 
        GROUP BY tbl, slice
    ) ti
    JOIN stv_tbl_perm t ON ti.tbl = t.id
    WHERE t.name NOT LIKE 'pg_%'
        AND t.name NOT LIKE 'information_schema%'
    GROUP BY t.name, t.tbl_rows
) tmp
WHERE tbl_rows > 1000
ORDER BY skew DESC
LIMIT 20;

-- Tables needing VACUUM
SELECT 
    TRIM(name) as table_name,
    unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 as pct_unsorted,
    rows,
    CASE 
        WHEN unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 > 20 THEN 'URGENT'
        WHEN unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 > 10 THEN 'RECOMMENDED'
        WHEN unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 > 5 THEN 'CONSIDER'
        ELSE 'OK'
    END as vacuum_priority
FROM stv_tbl_perm
WHERE unsorted > 0 
    AND rows > 1000
    AND name NOT LIKE 'pg_%'
    AND name NOT LIKE 'information_schema%'
ORDER BY pct_unsorted DESC
LIMIT 20;

-- WLM queue utilization
SELECT 
    service_class,
    COUNT(*) as total_queries,
    AVG(total_queue_time)/1000000.0 as avg_queue_time_seconds,
    MAX(total_queue_time)/1000000.0 as max_queue_time_seconds,
    AVG(total_exec_time)/1000000.0 as avg_exec_time_seconds
FROM stl_wlm_query 
WHERE queue_start_time >= CURRENT_DATE - 7
GROUP BY service_class
ORDER BY service_class;
EOF

    success "SQL analysis scripts created at: ${PROJECT_DIR}/analyze_performance.sql"
}

# Function to test Lambda function
test_lambda_function() {
    info "Testing Lambda function..."
    
    # Invoke the Lambda function with a test event
    aws lambda invoke \
        --function-name redshift-maintenance \
        --payload '{"test": true}' \
        --region "$AWS_REGION" \
        "${PROJECT_DIR}/lambda_test_response.json"
    
    if [ -f "${PROJECT_DIR}/lambda_test_response.json" ]; then
        if grep -q '"statusCode": 200' "${PROJECT_DIR}/lambda_test_response.json"; then
            success "Lambda function test completed successfully"
        else
            warning "Lambda function test completed with warnings. Check the response:"
            cat "${PROJECT_DIR}/lambda_test_response.json"
        fi
        rm -f "${PROJECT_DIR}/lambda_test_response.json"
    else
        warning "Lambda function test response not found"
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    echo ""
    echo "=========================================="
    echo "   DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo ""
    echo "Resources created:"
    echo "  ✓ Redshift Parameter Group: $PARAMETER_GROUP_NAME"
    echo "  ✓ CloudWatch Log Group: /aws/redshift/performance-metrics"
    echo "  ✓ SNS Topic: $TOPIC_ARN"
    echo "  ✓ Lambda Function: redshift-maintenance"
    echo "  ✓ CloudWatch Dashboard: Redshift-Performance-Dashboard"
    echo "  ✓ CloudWatch Alarms: 4 performance monitoring alarms"
    echo "  ✓ EventBridge Rule: redshift-nightly-maintenance (runs at 2 AM UTC)"
    echo ""
    echo "Configuration:"
    echo "  • Cluster: $CLUSTER_IDENTIFIER ($CLUSTER_ENDPOINT)"
    echo "  • Region: $AWS_REGION"
    echo "  • Database: $DB_NAME"
    echo "  • Automatic WLM: Enabled with concurrency scaling"
    echo "  • Maintenance Schedule: Daily at 2 AM UTC"
    echo ""
    echo "Next steps:"
    echo "  1. Access CloudWatch dashboard: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=Redshift-Performance-Dashboard"
    echo "  2. Confirm SNS email subscription if configured"
    echo "  3. Run analysis queries: psql -h $CLUSTER_ENDPOINT -U $DB_USER -d $DB_NAME -f ${PROJECT_DIR}/analyze_performance.sql"
    echo "  4. Monitor performance improvements over the next few days"
    echo ""
    echo "Important files:"
    echo "  • Deployment log: $LOG_FILE"
    echo "  • Analysis queries: ${PROJECT_DIR}/analyze_performance.sql"
    echo ""
    echo "For cleanup, run: ${SCRIPT_DIR}/destroy.sh"
    echo ""
}

# Main deployment function
main() {
    echo "=========================================="
    echo "  Redshift Performance Optimization"
    echo "        Deployment Script"
    echo "=========================================="
    echo ""
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    info "Starting deployment with configuration:"
    info "  Cluster: $CLUSTER_IDENTIFIER"
    info "  Region: $AWS_REGION"
    info "  Database: $DB_NAME"
    info "  User: $DB_USER"
    info "  Notification Email: $NOTIFICATION_EMAIL"
    info "  Log File: $LOG_FILE"
    echo ""
    
    # Set trap for cleanup on failure
    trap cleanup_on_failure ERR
    
    # Execute deployment steps
    check_prerequisites
    get_cluster_endpoint
    create_log_group
    create_sns_topic
    create_parameter_group
    create_lambda_function
    create_dashboard
    create_alarms
    schedule_maintenance
    create_analysis_scripts
    test_lambda_function
    
    # Show deployment summary
    show_deployment_summary
    
    success "Deployment completed successfully!"
    echo "Check the deployment log at: $LOG_FILE"
}

# Script entry point
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi