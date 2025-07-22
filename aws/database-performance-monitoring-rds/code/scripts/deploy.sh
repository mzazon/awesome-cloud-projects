#!/bin/bash
# Deploy script for RDS Performance Insights monitoring solution
# This script sets up comprehensive database performance monitoring using Performance Insights, 
# CloudWatch, and Lambda for automated analysis and alerting

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed! Cleaning up resources..."
    if [ -f "cleanup_manifest.txt" ]; then
        log "Removing created resources..."
        while IFS= read -r resource; do
            log "Cleaning up: $resource"
            eval "$resource" || true
        done < cleanup_manifest.txt
        rm -f cleanup_manifest.txt
    fi
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Initialize cleanup manifest
> cleanup_manifest.txt

# Function to add cleanup commands
add_cleanup() {
    echo "$1" >> cleanup_manifest.txt
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region is not configured. Please set it using 'aws configure set region <region>'"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export DB_INSTANCE_ID="performance-test-db-${RANDOM_SUFFIX}"
    export DB_SUBNET_GROUP="perf-insights-subnet-group-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="db-performance-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="performance-analyzer-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="db-performance-reports-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "DB Instance ID: $DB_INSTANCE_ID"
    log "S3 Bucket: $S3_BUCKET_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
}

# Create S3 bucket for performance reports
create_s3_bucket() {
    log "Creating S3 bucket for performance reports..."
    
    # Create bucket with appropriate region configuration
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${S3_BUCKET_NAME}
    else
        aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Add cleanup command
    add_cleanup "aws s3 rm s3://${S3_BUCKET_NAME} --recursive || true"
    add_cleanup "aws s3 rb s3://${S3_BUCKET_NAME} || true"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${S3_BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    log_success "S3 bucket created: ${S3_BUCKET_NAME}"
}

# Create SNS topic for alerts
create_sns_topic() {
    log "Creating SNS topic for performance alerts..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    
    # Add cleanup command
    add_cleanup "aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN} || true"
    
    log_success "SNS topic created: ${SNS_TOPIC_ARN}"
    
    # Prompt for email subscription
    read -p "Enter your email address for alerts (optional, press Enter to skip): " EMAIL_ADDRESS
    if [ ! -z "$EMAIL_ADDRESS" ]; then
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${EMAIL_ADDRESS}"
        log_success "Email subscription added. Please check your email and confirm the subscription."
    fi
}

# Create IAM role for enhanced monitoring
create_monitoring_role() {
    log "Creating IAM role for enhanced monitoring..."
    
    # Create trust policy
    cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "monitoring.rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name "rds-monitoring-role" \
        --assume-role-policy-document file://trust-policy.json
    
    # Add cleanup command
    add_cleanup "aws iam detach-role-policy --role-name rds-monitoring-role --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole || true"
    add_cleanup "aws iam delete-role --role-name rds-monitoring-role || true"
    
    # Attach policy
    aws iam attach-role-policy \
        --role-name "rds-monitoring-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    # Clean up temporary file
    rm -f trust-policy.json
    
    log_success "Enhanced monitoring role created"
}

# Create RDS instance with Performance Insights
create_rds_instance() {
    log "Creating RDS instance with Performance Insights..."
    
    # Get default VPC and subnets
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        log_error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[*].SubnetId" --output text)
    
    if [ -z "$SUBNET_IDS" ]; then
        log_error "No subnets found in default VPC. Please create subnets first."
        exit 1
    fi
    
    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name "${DB_SUBNET_GROUP}" \
        --db-subnet-group-description "Subnet group for Performance Insights demo" \
        --subnet-ids ${SUBNET_IDS}
    
    # Add cleanup command
    add_cleanup "aws rds delete-db-subnet-group --db-subnet-group-name ${DB_SUBNET_GROUP} || true"
    
    # Create RDS instance
    aws rds create-db-instance \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --db-instance-class "db.t3.micro" \
        --engine "mysql" \
        --engine-version "8.0.35" \
        --master-username "admin" \
        --master-user-password "SecurePassword123!" \
        --allocated-storage 20 \
        --db-subnet-group-name "${DB_SUBNET_GROUP}" \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --monitoring-interval 60 \
        --monitoring-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role" \
        --no-publicly-accessible \
        --enable-cloudwatch-logs-exports "error" "general" "slow-query"
    
    # Add cleanup command
    add_cleanup "aws rds delete-db-instance --db-instance-identifier ${DB_INSTANCE_ID} --skip-final-snapshot --delete-automated-backups || true"
    
    log_success "RDS instance creation initiated"
    
    # Wait for instance to be available
    log "Waiting for RDS instance to become available (this may take 5-10 minutes)..."
    aws rds wait db-instance-available --db-instance-identifier "${DB_INSTANCE_ID}"
    
    log_success "RDS instance is now available"
}

# Create Lambda function for performance analysis
create_lambda_function() {
    log "Creating Lambda function for performance analysis..."
    
    # Create Lambda function code
    cat > performance_analyzer.py << 'EOF'
import json
import boto3
import datetime
import os
from decimal import Decimal

def lambda_handler(event, context):
    pi_client = boto3.client('pi')
    s3_client = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    # Get Performance Insights resource ID from environment
    resource_id = os.environ.get('PI_RESOURCE_ID')
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    
    # Define time range for analysis (last hour)
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        # Get database load metrics
        response = pi_client.get_resource_metrics(
            ServiceType='RDS',
            Identifier=resource_id,
            StartTime=start_time,
            EndTime=end_time,
            PeriodInSeconds=300,
            MetricQueries=[
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {'Group': 'db.wait_event', 'Limit': 10}
                },
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {'Group': 'db.sql_tokenized', 'Limit': 10}
                }
            ]
        )
        
        # Analyze performance patterns
        analysis_results = analyze_performance_data(response)
        
        # Store results in S3
        report_key = f"performance-reports/{datetime.datetime.utcnow().strftime('%Y/%m/%d/%H')}/analysis.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(analysis_results, default=str),
            ContentType='application/json'
        )
        
        # Send custom metrics to CloudWatch
        publish_custom_metrics(cloudwatch, analysis_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'report_location': f's3://{bucket_name}/{report_key}'
            })
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def analyze_performance_data(response):
    """Analyze Performance Insights data for anomalies and patterns"""
    analysis = {
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'metrics_analyzed': len(response['MetricList']),
        'high_load_events': [],
        'problematic_queries': [],
        'recommendations': []
    }
    
    for metric in response['MetricList']:
        if 'Dimensions' in metric['Key']:
            # Analyze wait events
            if 'db.wait_event.name' in metric['Key']['Dimensions']:
                wait_event = metric['Key']['Dimensions']['db.wait_event.name']
                avg_load = sum(dp['Value'] for dp in metric['DataPoints']) / len(metric['DataPoints'])
                
                if avg_load > 1.0:  # High load threshold
                    analysis['high_load_events'].append({
                        'wait_event': wait_event,
                        'average_load': avg_load
                    })
            
            # Analyze SQL queries
            if 'db.sql_tokenized.statement' in metric['Key']['Dimensions']:
                sql_statement = metric['Key']['Dimensions']['db.sql_tokenized.statement']
                avg_load = sum(dp['Value'] for dp in metric['DataPoints']) / len(metric['DataPoints'])
                
                if avg_load > 0.5:  # Problematic query threshold
                    analysis['problematic_queries'].append({
                        'sql_statement': sql_statement[:200] + '...' if len(sql_statement) > 200 else sql_statement,
                        'average_load': avg_load
                    })
    
    # Generate recommendations
    if analysis['high_load_events']:
        analysis['recommendations'].append("Consider investigating high wait events and optimizing queries")
    
    if analysis['problematic_queries']:
        analysis['recommendations'].append("Review and optimize high-load SQL queries")
    
    return analysis

def publish_custom_metrics(cloudwatch, analysis):
    """Publish custom metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='RDS/PerformanceInsights',
            MetricData=[
                {
                    'MetricName': 'HighLoadEvents',
                    'Value': len(analysis['high_load_events']),
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                },
                {
                    'MetricName': 'ProblematicQueries',
                    'Value': len(analysis['problematic_queries']),
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing custom metrics: {str(e)}")
EOF
    
    # Create deployment package
    zip -r lambda_function.zip performance_analyzer.py
    
    # Create Lambda trust policy
    cat > lambda-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create Lambda role
    aws iam create-role \
        --role-name "performance-analyzer-role" \
        --assume-role-policy-document file://lambda-trust-policy.json
    
    # Add cleanup command
    add_cleanup "aws iam detach-role-policy --role-name performance-analyzer-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true"
    add_cleanup "aws iam detach-role-policy --role-name performance-analyzer-role --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PerformanceInsightsLambdaPolicy || true"
    add_cleanup "aws iam delete-role --role-name performance-analyzer-role || true"
    add_cleanup "aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PerformanceInsightsLambdaPolicy || true"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "performance-analyzer-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create custom policy for Performance Insights
    cat > pi-lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "pi:DescribeDimensionKeys",
                "pi:GetResourceMetrics",
                "pi:ListAvailableResourceDimensions",
                "pi:ListAvailableResourceMetrics",
                "s3:PutObject",
                "s3:GetObject",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name "PerformanceInsightsLambdaPolicy" \
        --policy-document file://pi-lambda-policy.json
    
    aws iam attach-role-policy \
        --role-name "performance-analyzer-role" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PerformanceInsightsLambdaPolicy"
    
    # Wait for role to be available
    log "Waiting for Lambda IAM role to be available..."
    sleep 10
    
    # Get Performance Insights resource ID
    PI_RESOURCE_ID=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query "DBInstances[0].DbiResourceId" \
        --output text)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/performance-analyzer-role" \
        --handler performance_analyzer.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment "Variables={PI_RESOURCE_ID=${PI_RESOURCE_ID},S3_BUCKET_NAME=${S3_BUCKET_NAME}}"
    
    # Add cleanup command
    add_cleanup "aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME} || true"
    
    # Clean up temporary files
    rm -f lambda-trust-policy.json pi-lambda-policy.json performance_analyzer.py lambda_function.zip
    
    log_success "Lambda function created successfully"
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # Create alarm for high database load
    aws cloudwatch put-metric-alarm \
        --alarm-name "RDS-HighDatabaseLoad-${DB_INSTANCE_ID}" \
        --alarm-description "High database load detected" \
        --metric-name "DatabaseConnections" \
        --namespace "AWS/RDS" \
        --statistic "Average" \
        --period 300 \
        --threshold 80 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=DBInstanceIdentifier,Value=${DB_INSTANCE_ID}" \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}"
    
    # Create alarm for CPU utilization
    aws cloudwatch put-metric-alarm \
        --alarm-name "RDS-HighCPUUtilization-${DB_INSTANCE_ID}" \
        --alarm-description "High CPU utilization on RDS instance" \
        --metric-name "CPUUtilization" \
        --namespace "AWS/RDS" \
        --statistic "Average" \
        --period 300 \
        --threshold 75 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=DBInstanceIdentifier,Value=${DB_INSTANCE_ID}" \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}"
    
    # Create alarm for custom Performance Insights metrics
    aws cloudwatch put-metric-alarm \
        --alarm-name "RDS-HighLoadEvents-${DB_INSTANCE_ID}" \
        --alarm-description "High number of database load events detected" \
        --metric-name "HighLoadEvents" \
        --namespace "RDS/PerformanceInsights" \
        --statistic "Sum" \
        --period 300 \
        --threshold 5 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}"
    
    # Create alarm for problematic queries
    aws cloudwatch put-metric-alarm \
        --alarm-name "RDS-ProblematicQueries-${DB_INSTANCE_ID}" \
        --alarm-description "High number of problematic SQL queries detected" \
        --metric-name "ProblematicQueries" \
        --namespace "RDS/PerformanceInsights" \
        --statistic "Sum" \
        --period 300 \
        --threshold 3 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}"
    
    # Add cleanup commands
    add_cleanup "aws cloudwatch delete-alarms --alarm-names RDS-HighDatabaseLoad-${DB_INSTANCE_ID} RDS-HighCPUUtilization-${DB_INSTANCE_ID} RDS-HighLoadEvents-${DB_INSTANCE_ID} RDS-ProblematicQueries-${DB_INSTANCE_ID} || true"
    
    log_success "CloudWatch alarms created"
}

# Set up EventBridge automation
setup_eventbridge() {
    log "Setting up EventBridge automation..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name "PerformanceAnalysisTrigger-${DB_INSTANCE_ID}" \
        --schedule-expression "rate(15 minutes)" \
        --description "Trigger performance analysis Lambda function" \
        --state ENABLED
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "PerformanceAnalysisTrigger-${DB_INSTANCE_ID}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "allow-eventbridge" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/PerformanceAnalysisTrigger-${DB_INSTANCE_ID}"
    
    # Add cleanup commands
    add_cleanup "aws events remove-targets --rule PerformanceAnalysisTrigger-${DB_INSTANCE_ID} --ids 1 || true"
    add_cleanup "aws events delete-rule --name PerformanceAnalysisTrigger-${DB_INSTANCE_ID} || true"
    
    log_success "EventBridge automation configured"
}

# Create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    # Create dashboard configuration
    cat > dashboard-body.json << EOF
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
                    ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    [".", "CPUUtilization", ".", "."],
                    [".", "ReadLatency", ".", "."],
                    [".", "WriteLatency", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "RDS Core Performance Metrics",
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
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["RDS/PerformanceInsights", "HighLoadEvents"],
                    [".", "ProblematicQueries"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Performance Insights Analysis Results"
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
                    ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", "${DB_INSTANCE_ID}"],
                    [".", "WriteIOPS", ".", "."],
                    [".", "ReadThroughput", ".", "."],
                    [".", "WriteThroughput", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "I/O Performance Metrics"
            }
        },
        {
            "type": "log",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/rds/instance/${DB_INSTANCE_ID}/slowquery'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 20",
                "region": "${AWS_REGION}",
                "title": "Recent Slow Query Log Entries"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "RDS-Performance-${DB_INSTANCE_ID}" \
        --dashboard-body file://dashboard-body.json
    
    # Add cleanup command
    add_cleanup "aws cloudwatch delete-dashboards --dashboard-names RDS-Performance-${DB_INSTANCE_ID} || true"
    
    # Clean up temporary file
    rm -f dashboard-body.json
    
    log_success "CloudWatch dashboard created"
}

# Display deployment summary
show_deployment_summary() {
    log "Deployment completed successfully!"
    
    # Get RDS endpoint
    DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query "DBInstances[0].Endpoint.Address" \
        --output text)
    
    # Get Performance Insights resource ID
    PI_RESOURCE_ID=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query "DBInstances[0].DbiResourceId" \
        --output text)
    
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "RDS Instance ID: ${DB_INSTANCE_ID}"
    echo "RDS Endpoint: ${DB_ENDPOINT}"
    echo "Performance Insights Resource ID: ${PI_RESOURCE_ID}"
    echo "S3 Bucket: ${S3_BUCKET_NAME}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo ""
    echo "=== USEFUL LINKS ==="
    echo "Performance Insights Dashboard:"
    echo "https://${AWS_REGION}.console.aws.amazon.com/rds/home?region=${AWS_REGION}#performance-insights-v20206:/resourceId/${PI_RESOURCE_ID}"
    echo ""
    echo "CloudWatch Dashboard:"
    echo "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=RDS-Performance-${DB_INSTANCE_ID}"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Connect to your database at: ${DB_ENDPOINT}"
    echo "2. Run queries to generate performance data"
    echo "3. Check Performance Insights dashboard for analysis"
    echo "4. Monitor CloudWatch alarms for automated alerting"
    echo "5. Review S3 bucket for analysis reports"
    echo ""
    echo "Database credentials:"
    echo "  Username: admin"
    echo "  Password: SecurePassword123!"
    echo ""
    echo "Run './destroy.sh' to clean up all resources when done."
}

# Main deployment function
main() {
    log "Starting deployment of RDS Performance Insights monitoring solution..."
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_sns_topic
    create_monitoring_role
    create_rds_instance
    create_lambda_function
    create_cloudwatch_alarms
    setup_eventbridge
    create_dashboard
    show_deployment_summary
    
    # Remove cleanup manifest on success
    rm -f cleanup_manifest.txt
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"