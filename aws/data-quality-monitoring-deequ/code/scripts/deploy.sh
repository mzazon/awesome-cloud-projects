#!/bin/bash

# AWS Real-time Data Quality Monitoring with Deequ on EMR - Deployment Script
# This script deploys the complete infrastructure for data quality monitoring
# using Amazon Deequ on EMR with CloudWatch monitoring and SNS alerting

set -euo pipefail

# Colors for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [ -z "$account_id" ]; then
        error "Unable to retrieve AWS account ID. Check your permissions."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Core environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    export CLUSTER_NAME="deequ-quality-monitor-${random_suffix}"
    export S3_BUCKET_NAME="deequ-data-quality-${random_suffix}"
    export SNS_TOPIC_NAME="data-quality-alerts-${random_suffix}"
    
    # Store variables in file for cleanup script
    cat > /tmp/deequ-deployment-vars.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CLUSTER_NAME=${CLUSTER_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
EOF
    
    success "Environment variables configured"
    log "Cluster Name: ${CLUSTER_NAME}"
    log "S3 Bucket: ${S3_BUCKET_NAME}"
    log "SNS Topic: ${SNS_TOPIC_NAME}"
}

# Function to create S3 bucket and structure
create_s3_resources() {
    log "Creating S3 bucket and directory structure..."
    
    # Create S3 bucket
    if aws s3 ls "s3://${S3_BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://${S3_BUCKET_NAME}"
        else
            aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
        fi
        success "Created S3 bucket: ${S3_BUCKET_NAME}"
    fi
    
    # Create directory structure
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key raw-data/ || true
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key quality-reports/ || true
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key logs/ || true
    aws s3api put-object --bucket "${S3_BUCKET_NAME}" --key scripts/ || true
    
    success "Created S3 directory structure"
}

# Function to create SNS topic and subscription
create_sns_resources() {
    log "Creating SNS topic for alerts..."
    
    # Create SNS topic
    aws sns create-topic --name "${SNS_TOPIC_NAME}" > /dev/null
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    # Store SNS topic ARN for cleanup
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> /tmp/deequ-deployment-vars.env
    
    success "Created SNS topic: ${SNS_TOPIC_NAME}"
    
    # Prompt for email subscription
    if [ -t 0 ]; then  # Check if running interactively
        echo
        read -p "Enter your email address for data quality alerts (or press Enter to skip): " EMAIL_ADDRESS
        if [ -n "$EMAIL_ADDRESS" ]; then
            aws sns subscribe --topic-arn "${SNS_TOPIC_ARN}" \
                --protocol email --notification-endpoint "${EMAIL_ADDRESS}"
            warning "Please check your email and confirm the SNS subscription"
        fi
    else
        warning "Running non-interactively. SNS email subscription skipped."
    fi
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating EMR IAM roles..."
    
    # Create EMR service role
    local emr_trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "elasticmapreduce.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    # Check if role exists
    if aws iam get-role --role-name EMR_DefaultRole &>/dev/null; then
        warning "EMR_DefaultRole already exists"
    else
        aws iam create-role --role-name EMR_DefaultRole \
            --assume-role-policy-document "$emr_trust_policy"
        aws iam attach-role-policy --role-name EMR_DefaultRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole
        success "Created EMR service role"
    fi
    
    # Create EC2 instance role
    local ec2_trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    if aws iam get-role --role-name EMR_EC2_DefaultRole &>/dev/null; then
        warning "EMR_EC2_DefaultRole already exists"
    else
        aws iam create-role --role-name EMR_EC2_DefaultRole \
            --assume-role-policy-document "$ec2_trust_policy"
        aws iam attach-role-policy --role-name EMR_EC2_DefaultRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role
        success "Created EMR EC2 role"
    fi
    
    # Create instance profile
    if aws iam get-instance-profile --instance-profile-name EMR_EC2_DefaultRole &>/dev/null; then
        warning "EMR_EC2_DefaultRole instance profile already exists"
    else
        aws iam create-instance-profile --instance-profile-name EMR_EC2_DefaultRole
        aws iam add-role-to-instance-profile --instance-profile-name EMR_EC2_DefaultRole \
            --role-name EMR_EC2_DefaultRole
        success "Created EMR instance profile"
        
        # Wait for instance profile to propagate
        log "Waiting for instance profile to propagate..."
        sleep 10
    fi
}

# Function to create and upload bootstrap script
create_bootstrap_script() {
    log "Creating Deequ bootstrap script..."
    
    cat > /tmp/install-deequ.sh << 'EOF'
#!/bin/bash

# Download and install Deequ JAR
sudo mkdir -p /usr/lib/spark/jars
sudo wget -O /usr/lib/spark/jars/deequ-2.0.4-spark-3.4.jar \
    https://repo1.maven.org/maven2/com/amazon/deequ/deequ/2.0.4-spark-3.4/deequ-2.0.4-spark-3.4.jar

# Install required Python packages
sudo pip3 install boto3 pyarrow pandas numpy

# Create directories for custom scripts
sudo mkdir -p /opt/deequ-scripts
sudo chmod 755 /opt/deequ-scripts

echo "Deequ installation completed successfully"
EOF
    
    # Upload bootstrap script to S3
    aws s3 cp /tmp/install-deequ.sh "s3://${S3_BUCKET_NAME}/scripts/"
    
    success "Created and uploaded Deequ bootstrap script"
}

# Function to create and upload sample data
create_sample_data() {
    log "Creating sample data with quality issues..."
    
    cat > /tmp/sample-data.py << 'EOF'
import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta

# Generate sample customer data with intentional quality issues
np.random.seed(42)
num_records = 10000

# Create base dataset
data = {
    'customer_id': range(1, num_records + 1),
    'email': [f'user{i}@example.com' for i in range(1, num_records + 1)],
    'age': np.random.randint(18, 80, num_records),
    'income': np.random.normal(50000, 20000, num_records),
    'region': np.random.choice(['US', 'EU', 'APAC'], num_records),
    'signup_date': [datetime.now() - timedelta(days=random.randint(1, 365)) 
                   for _ in range(num_records)]
}

# Introduce quality issues
# 1. Missing values in income
missing_indices = np.random.choice(num_records, size=int(num_records * 0.05), replace=False)
for idx in missing_indices:
    data['income'][idx] = None

# 2. Invalid email formats
invalid_email_indices = np.random.choice(num_records, size=int(num_records * 0.02), replace=False)
for idx in invalid_email_indices:
    data['email'][idx] = f'invalid-email-{idx}'

# 3. Negative ages
negative_age_indices = np.random.choice(num_records, size=int(num_records * 0.01), replace=False)
for idx in negative_age_indices:
    data['age'][idx] = -abs(data['age'][idx])

# 4. Duplicate customer IDs
duplicate_indices = np.random.choice(num_records, size=int(num_records * 0.03), replace=False)
for idx in duplicate_indices:
    data['customer_id'][idx] = data['customer_id'][idx - 1]

# Convert to DataFrame and save
df = pd.DataFrame(data)
df.to_csv('/tmp/sample_customer_data.csv', index=False)
print(f"Generated {len(df)} customer records with quality issues")
EOF
    
    # Generate the sample data
    python3 /tmp/sample-data.py
    
    # Upload sample data to S3
    aws s3 cp /tmp/sample_customer_data.csv "s3://${S3_BUCKET_NAME}/raw-data/"
    
    success "Created and uploaded sample data with quality issues"
}

# Function to create and upload monitoring application
create_monitoring_application() {
    log "Creating Deequ quality monitoring application..."
    
    cat > /tmp/deequ-quality-monitor.py << 'EOF'
import sys
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, lit
import boto3
import json
from datetime import datetime

# Initialize Spark session with Deequ
spark = SparkSession.builder \
    .appName("DeeQuDataQualityMonitor") \
    .config("spark.jars.packages", "com.amazon.deequ:deequ:2.0.4-spark-3.4") \
    .getOrCreate()

# Import Deequ classes
from pydeequ.analyzers import *
from pydeequ.checks import *
from pydeequ.verification import *
from pydeequ.suggestions import *

def publish_metrics_to_cloudwatch(metrics, bucket_name):
    """Publish data quality metrics to CloudWatch"""
    cloudwatch = boto3.client('cloudwatch')
    
    for metric_name, metric_value in metrics.items():
        cloudwatch.put_metric_data(
            Namespace='DataQuality/Deequ',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': metric_value,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'DataSource',
                            'Value': bucket_name
                        }
                    ]
                }
            ]
        )

def send_alert_if_needed(verification_result, sns_topic_arn):
    """Send SNS alert if data quality issues are found"""
    failed_checks = []
    
    for check_result in verification_result.checkResults:
        if check_result.status != CheckStatus.Success:
            failed_checks.append({
                'check': str(check_result.check),
                'status': str(check_result.status),
                'constraint': str(check_result.constraint)
            })
    
    if failed_checks:
        sns = boto3.client('sns')
        message = {
            'timestamp': datetime.now().isoformat(),
            'alert_type': 'DATA_QUALITY_FAILURE',
            'failed_checks': failed_checks,
            'total_failed_checks': len(failed_checks)
        }
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(message, indent=2),
            Subject='Data Quality Alert - Issues Detected'
        )

def main():
    # Get parameters
    if len(sys.argv) != 4:
        print("Usage: deequ-quality-monitor.py <s3_bucket> <data_path> <sns_topic_arn>")
        sys.exit(1)
    
    s3_bucket = sys.argv[1]
    data_path = sys.argv[2]
    sns_topic_arn = sys.argv[3]
    
    # Read data
    df = spark.read.option("header", "true").option("inferSchema", "true").csv(data_path)
    
    print(f"Processing {df.count()} records from {data_path}")
    
    # Define data quality checks
    verification_result = VerificationSuite(spark) \
        .onData(df) \
        .addCheck(
            Check(spark, CheckLevel.Error, "Customer Data Quality Checks")
            .hasSize(lambda x: x > 0)  # Non-empty dataset
            .isComplete("customer_id")  # No null customer IDs
            .isUnique("customer_id")   # Unique customer IDs
            .isComplete("email")       # No null emails
            .containsEmail("email")    # Valid email format
            .isNonNegative("age")      # Age must be non-negative
            .isContainedIn("region", ["US", "EU", "APAC"])  # Valid regions
            .hasCompleteness("income", lambda x: x > 0.9)  # At least 90% income data
        ) \
        .run()
    
    # Run analysis for detailed metrics
    analysis_result = AnalysisRunner(spark) \
        .onData(df) \
        .addAnalyzer(Size()) \
        .addAnalyzer(Completeness("customer_id")) \
        .addAnalyzer(Completeness("email")) \
        .addAnalyzer(Completeness("income")) \
        .addAnalyzer(Uniqueness("customer_id")) \
        .addAnalyzer(Mean("age")) \
        .addAnalyzer(StandardDeviation("age")) \
        .addAnalyzer(CountDistinct("region")) \
        .run()
    
    # Extract metrics
    metrics = {}
    for analyzer_name, analyzer_result in analysis_result.analyzerContext.metricMap.items():
        if analyzer_result.value.isSuccess():
            metric_name = str(analyzer_name).replace(":", "_").replace("(", "_").replace(")", "_")
            metrics[metric_name] = analyzer_result.value.get()
    
    # Publish metrics to CloudWatch
    publish_metrics_to_cloudwatch(metrics, s3_bucket)
    
    # Send alerts if needed
    send_alert_if_needed(verification_result, sns_topic_arn)
    
    # Save detailed results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Save verification results
    verification_df = VerificationResult.checkResultsAsDataFrame(spark, verification_result)
    verification_df.write.mode("overwrite").json(f"s3://{s3_bucket}/quality-reports/verification_{timestamp}")
    
    # Save analysis results
    analysis_df = AnalysisResult.successMetricsAsDataFrame(spark, analysis_result)
    analysis_df.write.mode("overwrite").json(f"s3://{s3_bucket}/quality-reports/analysis_{timestamp}")
    
    print("✅ Data quality monitoring completed successfully")
    print(f"Metrics published to CloudWatch namespace: DataQuality/Deequ")
    print(f"Reports saved to: s3://{s3_bucket}/quality-reports/")
    
    # Print summary
    print("\n=== VERIFICATION RESULTS ===")
    verification_df.show(truncate=False)
    
    print("\n=== ANALYSIS RESULTS ===")
    analysis_df.show(truncate=False)

if __name__ == "__main__":
    main()
EOF
    
    # Upload the monitoring application to S3
    aws s3 cp /tmp/deequ-quality-monitor.py "s3://${S3_BUCKET_NAME}/scripts/"
    
    success "Created and uploaded Deequ quality monitoring application"
}

# Function to create EMR cluster
create_emr_cluster() {
    log "Creating EMR cluster with Deequ..."
    
    # Create EMR cluster configuration
    local cluster_config=$(cat << EOF
{
    "Name": "${CLUSTER_NAME}",
    "ReleaseLabel": "emr-6.15.0",
    "Applications": [
        {"Name": "Spark"}
    ],
    "Instances": {
        "InstanceGroups": [
            {
                "Name": "Primary",
                "Market": "ON_DEMAND",
                "InstanceRole": "MASTER",
                "InstanceType": "m5.xlarge",
                "InstanceCount": 1
            },
            {
                "Name": "Core",
                "Market": "ON_DEMAND",
                "InstanceRole": "CORE",
                "InstanceType": "m5.xlarge",
                "InstanceCount": 2
            }
        ],
        "Ec2KeyName": null,
        "KeepJobFlowAliveWhenNoSteps": true,
        "TerminationProtected": false
    },
    "ServiceRole": "EMR_DefaultRole",
    "JobFlowRole": "EMR_EC2_DefaultRole",
    "BootstrapActions": [
        {
            "Name": "Install Deequ",
            "ScriptBootstrapAction": {
                "Path": "s3://${S3_BUCKET_NAME}/scripts/install-deequ.sh"
            }
        }
    ],
    "LogUri": "s3://${S3_BUCKET_NAME}/logs/",
    "EnableDebugging": true,
    "Configurations": [
        {
            "Classification": "spark-defaults",
            "Properties": {
                "spark.sql.adaptive.enabled": "true",
                "spark.sql.adaptive.coalescePartitions.enabled": "true",
                "spark.serializer": "org.apache.spark.serializer.KryoSerializer"
            }
        }
    ]
}
EOF
)
    
    # Create cluster
    local create_response
    create_response=$(aws emr create-cluster --cli-input-json "$cluster_config")
    export CLUSTER_ID=$(echo "$create_response" | grep -o '"JobFlowId": "[^"]*"' | cut -d'"' -f4)
    
    # Store cluster ID for cleanup
    echo "CLUSTER_ID=${CLUSTER_ID}" >> /tmp/deequ-deployment-vars.env
    
    success "EMR cluster created with ID: ${CLUSTER_ID}"
    log "Waiting for cluster to be ready..."
    
    # Wait for cluster to be ready with timeout
    local max_wait=1800  # 30 minutes
    local wait_time=0
    local sleep_interval=30
    
    while [ $wait_time -lt $max_wait ]; do
        local cluster_state
        cluster_state=$(aws emr describe-cluster --cluster-id "${CLUSTER_ID}" \
            --query 'Cluster.Status.State' --output text)
        
        case "$cluster_state" in
            "RUNNING")
                success "EMR cluster is now running and ready"
                return 0
                ;;
            "TERMINATING"|"TERMINATED"|"TERMINATED_WITH_ERRORS")
                error "EMR cluster failed to start. State: $cluster_state"
                return 1
                ;;
            *)
                log "Cluster state: $cluster_state. Waiting..."
                sleep $sleep_interval
                wait_time=$((wait_time + sleep_interval))
                ;;
        esac
    done
    
    error "Timeout waiting for EMR cluster to be ready"
    return 1
}

# Function to submit data quality job
submit_quality_job() {
    log "Submitting data quality monitoring job..."
    
    # Submit the Spark job
    local step_response
    step_response=$(aws emr add-steps --cluster-id "${CLUSTER_ID}" --steps '[
        {
            "Name": "DeeQuDataQualityMonitoring",
            "ActionOnFailure": "CONTINUE",
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "spark-submit",
                    "--deploy-mode", "cluster",
                    "--master", "yarn",
                    "--conf", "spark.sql.adaptive.enabled=true",
                    "s3://'${S3_BUCKET_NAME}'/scripts/deequ-quality-monitor.py",
                    "'${S3_BUCKET_NAME}'",
                    "s3://'${S3_BUCKET_NAME}'/raw-data/sample_customer_data.csv",
                    "'${SNS_TOPIC_ARN}'"
                ]
            }
        }
    ]')
    
    local step_id
    step_id=$(echo "$step_response" | grep -o '"StepIds": \[[^]]*\]' | grep -o '"[^"]*"' | head -1 | tr -d '"')
    
    success "Data quality monitoring job submitted with Step ID: ${step_id}"
    log "Monitoring job execution..."
    
    # Wait for step completion
    local max_wait=1200  # 20 minutes
    local wait_time=0
    local sleep_interval=30
    
    while [ $wait_time -lt $max_wait ]; do
        local step_state
        step_state=$(aws emr describe-step --cluster-id "${CLUSTER_ID}" --step-id "${step_id}" \
            --query 'Step.Status.State' --output text)
        
        case "$step_state" in
            "COMPLETED")
                success "Data quality monitoring job completed successfully"
                return 0
                ;;
            "FAILED"|"CANCELLED"|"INTERRUPTED")
                error "Data quality monitoring job failed. State: $step_state"
                return 1
                ;;
            *)
                log "Step state: $step_state. Waiting..."
                sleep $sleep_interval
                wait_time=$((wait_time + sleep_interval))
                ;;
        esac
    done
    
    warning "Timeout waiting for step completion, but continuing..."
    return 0
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    local dashboard_config=$(cat << EOF
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
                    [ "DataQuality/Deequ", "Size", "DataSource", "${S3_BUCKET_NAME}" ],
                    [ ".", "Completeness_customer_id_", ".", "." ],
                    [ ".", "Completeness_email_", ".", "." ],
                    [ ".", "Completeness_income_", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Data Quality Metrics"
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
                    [ "DataQuality/Deequ", "Uniqueness_customer_id_", "DataSource", "${S3_BUCKET_NAME}" ],
                    [ ".", "Mean_age_", ".", "." ],
                    [ ".", "StandardDeviation_age_", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Data Distribution Metrics"
            }
        }
    ]
}
EOF
)
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "DeeQuDataQualityMonitoring" \
        --dashboard-body "$dashboard_config"
    
    success "CloudWatch dashboard created: DeeQuDataQualityMonitoring"
}

# Function to display deployment summary
show_summary() {
    echo
    echo "=========================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
    echo "=========================================="
    echo
    echo "📊 Resources Created:"
    echo "   • EMR Cluster: ${CLUSTER_NAME} (${CLUSTER_ID})"
    echo "   • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "   • SNS Topic: ${SNS_TOPIC_NAME}"
    echo "   • CloudWatch Dashboard: DeeQuDataQualityMonitoring"
    echo
    echo "🔗 Access Points:"
    echo "   • EMR Console: https://${AWS_REGION}.console.aws.amazon.com/emr/home?region=${AWS_REGION}#cluster-details:${CLUSTER_ID}"
    echo "   • S3 Console: https://s3.console.aws.amazon.com/s3/buckets/${S3_BUCKET_NAME}"
    echo "   • CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=DeeQuDataQualityMonitoring"
    echo
    echo "📁 Generated Files:"
    echo "   • Environment variables: /tmp/deequ-deployment-vars.env"
    echo
    echo "⚠️  Important Notes:"
    echo "   • The EMR cluster is running and will incur charges (~$15-25/hour)"
    echo "   • Use the destroy.sh script to clean up all resources"
    echo "   • Check your email for SNS subscription confirmation"
    echo
    echo "🚀 Next Steps:"
    echo "   1. Confirm SNS email subscription if provided"
    echo "   2. View the CloudWatch dashboard for data quality metrics"
    echo "   3. Check S3 bucket for quality reports"
    echo "   4. Run additional quality jobs as needed"
    echo
}

# Main execution
main() {
    echo "=================================================="
    echo "🔧 AWS Real-time Data Quality Monitoring with Deequ"
    echo "=================================================="
    echo
    
    check_prerequisites
    setup_environment
    create_s3_resources
    create_sns_resources
    create_iam_roles
    create_bootstrap_script
    create_sample_data
    create_monitoring_application
    create_emr_cluster
    submit_quality_job
    create_dashboard
    show_summary
    
    log "Deployment script completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"