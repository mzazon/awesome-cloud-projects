#!/bin/bash

# Deploy script for Analytics Workload Isolation with Redshift Workload Management
# This script implements the complete infrastructure deployment for workload isolation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check logs at: $LOG_FILE"
    log_error "To clean up partially created resources, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log_info "Verifying AWS permissions..."
    local test_operations=(
        "redshift:DescribeClusters"
        "redshift:CreateClusterParameterGroup"
        "sns:CreateTopic"
        "cloudwatch:PutMetricAlarm"
        "iam:GetCallerIdentity"
    )
    
    for operation in "${test_operations[@]}"; do
        service=$(echo "$operation" | cut -d':' -f1)
        action=$(echo "$operation" | cut -d':' -f2)
        if ! aws iam simulate-principal-policy \
            --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
            --action-names "$operation" \
            --resource-arns "*" \
            --query 'EvaluationResults[0].EvalDecision' \
            --output text 2>/dev/null | grep -q "allowed"; then
            log_warning "Permission check for $operation might fail during deployment"
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Load or generate configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading existing configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log_info "Generating new deployment configuration..."
        
        # Set environment variables
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Generate unique identifiers
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
        
        export CLUSTER_IDENTIFIER="analytics-wlm-cluster-${RANDOM_SUFFIX}"
        export PARAMETER_GROUP_NAME="analytics-wlm-pg-${RANDOM_SUFFIX}"
        export SNS_TOPIC_NAME="redshift-wlm-alerts-${RANDOM_SUFFIX}"
        export PARAMETER_GROUP_FAMILY="redshift-1.0"
        
        # Save configuration
        cat > "$CONFIG_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
CLUSTER_IDENTIFIER=$CLUSTER_IDENTIFIER
PARAMETER_GROUP_NAME=$PARAMETER_GROUP_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
PARAMETER_GROUP_FAMILY=$PARAMETER_GROUP_FAMILY
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
        
        log_success "Configuration saved to $CONFIG_FILE"
    fi
    
    log_info "Using configuration:"
    log_info "  Region: $AWS_REGION"
    log_info "  Account: $AWS_ACCOUNT_ID"
    log_info "  Cluster ID: $CLUSTER_IDENTIFIER"
    log_info "  Parameter Group: $PARAMETER_GROUP_NAME"
}

# Create parameter group
create_parameter_group() {
    log_info "Creating custom parameter group for WLM configuration..."
    
    if aws redshift describe-cluster-parameter-groups \
        --parameter-group-name "$PARAMETER_GROUP_NAME" &>/dev/null; then
        log_warning "Parameter group $PARAMETER_GROUP_NAME already exists, skipping creation"
        return 0
    fi
    
    aws redshift create-cluster-parameter-group \
        --parameter-group-name "$PARAMETER_GROUP_NAME" \
        --parameter-group-family "$PARAMETER_GROUP_FAMILY" \
        --description "Analytics workload isolation parameter group"
    
    log_success "Created parameter group: $PARAMETER_GROUP_NAME"
}

# Configure WLM with query monitoring rules
configure_wlm() {
    log_info "Configuring WLM with workload isolation and query monitoring rules..."
    
    # Create WLM configuration with query monitoring rules
    cat > "${SCRIPT_DIR}/wlm_config_with_qmr.json" << 'EOF'
[
  {
    "user_group": "bi-dashboard-group",
    "query_group": "dashboard",
    "query_concurrency": 15,
    "memory_percent_to_use": 25,
    "max_execution_time": 120000,
    "query_group_wild_card": 0,
    "rules": [
      {
        "rule_name": "dashboard_timeout_rule",
        "predicate": "query_execution_time > 120",
        "action": "abort"
      },
      {
        "rule_name": "dashboard_cpu_rule", 
        "predicate": "query_cpu_time > 30",
        "action": "log"
      }
    ]
  },
  {
    "user_group": "data-science-group",
    "query_group": "analytics", 
    "query_concurrency": 3,
    "memory_percent_to_use": 40,
    "max_execution_time": 7200000,
    "query_group_wild_card": 0,
    "rules": [
      {
        "rule_name": "analytics_memory_rule",
        "predicate": "query_temp_blocks_to_disk > 100000",
        "action": "log"
      },
      {
        "rule_name": "analytics_nested_loop_rule",
        "predicate": "nested_loop_join_row_count > 1000000",
        "action": "hop"
      }
    ]
  },
  {
    "user_group": "etl-process-group",
    "query_group": "etl",
    "query_concurrency": 5, 
    "memory_percent_to_use": 25,
    "max_execution_time": 3600000,
    "query_group_wild_card": 0,
    "rules": [
      {
        "rule_name": "etl_timeout_rule",
        "predicate": "query_execution_time > 3600",
        "action": "abort"
      },
      {
        "rule_name": "etl_scan_rule",
        "predicate": "scan_row_count > 1000000000",
        "action": "log"
      }
    ]
  },
  {
    "query_concurrency": 2,
    "memory_percent_to_use": 10, 
    "max_execution_time": 1800000,
    "query_group_wild_card": 1,
    "rules": [
      {
        "rule_name": "default_timeout_rule",
        "predicate": "query_execution_time > 1800",
        "action": "abort"
      }
    ]
  }
]
EOF
    
    # Apply WLM configuration to parameter group
    WLM_CONFIG=$(cat "${SCRIPT_DIR}/wlm_config_with_qmr.json" | tr -d '\n' | tr -d ' ')
    
    aws redshift modify-cluster-parameter-group \
        --parameter-group-name "$PARAMETER_GROUP_NAME" \
        --parameters ParameterName=wlm_json_configuration,ParameterValue="$WLM_CONFIG"
    
    log_success "Applied WLM configuration with query monitoring rules"
}

# Create SNS topic for alerts
create_sns_topic() {
    log_info "Creating SNS topic for WLM monitoring alerts..."
    
    if SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text 2>/dev/null); then
        log_warning "SNS topic already exists: $SNS_TOPIC_ARN"
    else
        SNS_TOPIC_ARN=$(aws sns create-topic \
            --name "$SNS_TOPIC_NAME" \
            --query 'TopicArn' \
            --output text)
        log_success "Created SNS topic: $SNS_TOPIC_ARN"
    fi
    
    # Save SNS topic ARN to config
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> "$CONFIG_FILE"
    
    # Prompt for email subscription if not in non-interactive mode
    if [[ "${DEPLOY_NON_INTERACTIVE:-false}" != "true" ]]; then
        read -p "Enter email address for WLM alerts (press Enter to skip): " EMAIL_ADDRESS
        if [[ -n "$EMAIL_ADDRESS" ]]; then
            aws sns subscribe \
                --topic-arn "$SNS_TOPIC_ARN" \
                --protocol email \
                --notification-endpoint "$EMAIL_ADDRESS"
            log_success "Email subscription created. Please check your email and confirm."
        fi
    fi
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms for queue performance monitoring..."
    
    # Create CloudWatch alarm for high queue wait time
    if aws cloudwatch describe-alarms \
        --alarm-names "RedshiftWLM-HighQueueWaitTime-${RANDOM_SUFFIX}" &>/dev/null; then
        log_warning "Queue wait time alarm already exists"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "RedshiftWLM-HighQueueWaitTime-${RANDOM_SUFFIX}" \
            --alarm-description "Alert when WLM queue wait time is high" \
            --metric-name QueueLength \
            --namespace AWS/Redshift \
            --statistic Average \
            --period 300 \
            --threshold 5 \
            --comparison-operator GreaterThanThreshold \
            --dimensions Name=ClusterIdentifier,Value="$CLUSTER_IDENTIFIER" \
            --evaluation-periods 2 \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --treat-missing-data notBreaching
        log_success "Created queue wait time alarm"
    fi
    
    # Create alarm for CPU utilization
    if aws cloudwatch describe-alarms \
        --alarm-names "RedshiftWLM-HighCPUUtilization-${RANDOM_SUFFIX}" &>/dev/null; then
        log_warning "CPU utilization alarm already exists"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "RedshiftWLM-HighCPUUtilization-${RANDOM_SUFFIX}" \
            --alarm-description "Alert when cluster CPU utilization is high" \
            --metric-name CPUUtilization \
            --namespace AWS/Redshift \
            --statistic Average \
            --period 300 \
            --threshold 85 \
            --comparison-operator GreaterThanThreshold \
            --dimensions Name=ClusterIdentifier,Value="$CLUSTER_IDENTIFIER" \
            --evaluation-periods 3 \
            --alarm-actions "$SNS_TOPIC_ARN"
        log_success "Created CPU utilization alarm"
    fi
    
    # Create alarm for query abort rate
    if aws cloudwatch describe-alarms \
        --alarm-names "RedshiftWLM-HighQueryAbortRate-${RANDOM_SUFFIX}" &>/dev/null; then
        log_warning "Query abort rate alarm already exists"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "RedshiftWLM-HighQueryAbortRate-${RANDOM_SUFFIX}" \
            --alarm-description "Alert when query abort rate is high" \
            --metric-name QueriesCompletedPerSecond \
            --namespace AWS/Redshift \
            --statistic Sum \
            --period 900 \
            --threshold 10 \
            --comparison-operator LessThanThreshold \
            --dimensions Name=ClusterIdentifier,Value="$CLUSTER_IDENTIFIER" \
            --evaluation-periods 2 \
            --alarm-actions "$SNS_TOPIC_ARN"
        log_success "Created query abort rate alarm"
    fi
    
    # Save alarm names to config
    cat >> "$CONFIG_FILE" << EOF
ALARM_QUEUE_WAIT=RedshiftWLM-HighQueueWaitTime-${RANDOM_SUFFIX}
ALARM_CPU_UTIL=RedshiftWLM-HighCPUUtilization-${RANDOM_SUFFIX}
ALARM_QUERY_ABORT=RedshiftWLM-HighQueryAbortRate-${RANDOM_SUFFIX}
EOF
}

# Create CloudWatch dashboard
create_dashboard() {
    log_info "Creating CloudWatch dashboard for WLM monitoring..."
    
    cat > "${SCRIPT_DIR}/wlm_dashboard.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/Redshift", "QueueLength", "ClusterIdentifier", "$CLUSTER_IDENTIFIER" ],
                    [ ".", "QueriesCompletedPerSecond", ".", "." ],
                    [ ".", "CPUUtilization", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Redshift WLM Performance Metrics",
                "view": "timeSeries"
            }
        },
        {
            "type": "metric", 
            "properties": {
                "metrics": [
                    [ "AWS/Redshift", "DatabaseConnections", "ClusterIdentifier", "$CLUSTER_IDENTIFIER" ],
                    [ ".", "HealthStatus", ".", "." ]
                ],
                "period": 300,
                "stat": "Average", 
                "region": "$AWS_REGION",
                "title": "Cluster Health and Connections",
                "view": "timeSeries"
            }
        }
    ]
}
EOF
    
    DASHBOARD_NAME="RedshiftWLM-${RANDOM_SUFFIX}"
    
    if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &>/dev/null; then
        log_warning "Dashboard already exists: $DASHBOARD_NAME"
    else
        aws cloudwatch put-dashboard \
            --dashboard-name "$DASHBOARD_NAME" \
            --dashboard-body "file://${SCRIPT_DIR}/wlm_dashboard.json"
        log_success "Created CloudWatch dashboard: $DASHBOARD_NAME"
    fi
    
    # Save dashboard name to config
    echo "DASHBOARD_NAME=$DASHBOARD_NAME" >> "$CONFIG_FILE"
}

# Create SQL scripts for setup and monitoring
create_sql_scripts() {
    log_info "Creating SQL scripts for user setup and monitoring..."
    
    # Create user group setup script
    cat > "${SCRIPT_DIR}/setup_users_groups.sql" << 'EOF'
-- Create user groups for workload isolation
CREATE GROUP "bi-dashboard-group";
CREATE GROUP "data-science-group"; 
CREATE GROUP "etl-process-group";

-- Create users for different workload types
CREATE USER dashboard_user1 PASSWORD 'BiUser123!@#' IN GROUP "bi-dashboard-group";
CREATE USER dashboard_user2 PASSWORD 'BiUser123!@#' IN GROUP "bi-dashboard-group";
CREATE USER analytics_user1 PASSWORD 'DsUser123!@#' IN GROUP "data-science-group";
CREATE USER analytics_user2 PASSWORD 'DsUser123!@#' IN GROUP "data-science-group";
CREATE USER etl_user1 PASSWORD 'EtlUser123!@#' IN GROUP "etl-process-group";

-- Grant appropriate permissions
GRANT ALL ON SCHEMA public TO GROUP "bi-dashboard-group";
GRANT ALL ON SCHEMA public TO GROUP "data-science-group";
GRANT ALL ON SCHEMA public TO GROUP "etl-process-group";
EOF
    
    # Create monitoring views script
    cat > "${SCRIPT_DIR}/wlm_monitoring_views.sql" << 'EOF'
-- Create view to monitor queue performance
CREATE OR REPLACE VIEW wlm_queue_performance AS
SELECT 
    service_class,
    CASE 
        WHEN service_class = 6 THEN 'BI Dashboard Queue'
        WHEN service_class = 7 THEN 'Data Science Queue' 
        WHEN service_class = 8 THEN 'ETL Queue'
        WHEN service_class = 5 THEN 'Default Queue'
        ELSE 'System Queue'
    END AS queue_name,
    num_query_tasks,
    num_executing_queries,
    num_executed_queries,
    num_queued_queries,
    query_working_mem,
    available_query_mem,
    ROUND(100.0 * num_executing_queries / num_query_tasks, 2) AS utilization_pct
FROM stv_wlm_service_class_state
WHERE service_class >= 5
ORDER BY service_class;

-- Create view to monitor query monitoring rule actions  
CREATE OR REPLACE VIEW wlm_rule_actions AS
SELECT
    userid,
    query,
    service_class,
    rule,
    action,
    recordtime,
    CASE 
        WHEN service_class = 6 THEN 'BI Dashboard Queue'
        WHEN service_class = 7 THEN 'Data Science Queue'
        WHEN service_class = 8 THEN 'ETL Queue' 
        WHEN service_class = 5 THEN 'Default Queue'
        ELSE 'System Queue'
    END AS queue_name
FROM stl_wlm_rule_action
WHERE recordtime >= DATEADD(hour, -24, GETDATE())
ORDER BY recordtime DESC;

-- Create view to analyze queue wait times
CREATE OR REPLACE VIEW wlm_queue_wait_analysis AS
SELECT
    service_class,
    CASE 
        WHEN service_class = 6 THEN 'BI Dashboard Queue'
        WHEN service_class = 7 THEN 'Data Science Queue'
        WHEN service_class = 8 THEN 'ETL Queue'
        WHEN service_class = 5 THEN 'Default Queue'
        ELSE 'System Queue'
    END AS queue_name,
    COUNT(*) AS total_queries,
    AVG(total_queue_time/1000000.0) AS avg_queue_wait_seconds,
    MAX(total_queue_time/1000000.0) AS max_queue_wait_seconds,
    AVG(total_exec_time/1000000.0) AS avg_execution_seconds
FROM stl_query
WHERE starttime >= DATEADD(hour, -24, GETDATE())
AND service_class >= 5
GROUP BY service_class
ORDER BY service_class;
EOF
    
    log_success "Created SQL scripts for user setup and monitoring"
}

# Apply parameter group to cluster if it exists
apply_parameter_group() {
    log_info "Checking for existing cluster and applying parameter group..."
    
    if aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER_IDENTIFIER" \
        --query 'Clusters[0].ClusterIdentifier' \
        --output text >/dev/null 2>&1; then
        
        log_info "Found cluster $CLUSTER_IDENTIFIER, applying parameter group..."
        
        # Check current parameter group
        CURRENT_PG=$(aws redshift describe-clusters \
            --cluster-identifier "$CLUSTER_IDENTIFIER" \
            --query 'Clusters[0].ClusterParameterGroups[0].ParameterGroupName' \
            --output text)
        
        if [[ "$CURRENT_PG" == "$PARAMETER_GROUP_NAME" ]]; then
            log_warning "Parameter group already applied to cluster"
        else
            aws redshift modify-cluster \
                --cluster-identifier "$CLUSTER_IDENTIFIER" \
                --cluster-parameter-group-name "$PARAMETER_GROUP_NAME" \
                --apply-immediately
            
            log_success "Applied parameter group to cluster: $CLUSTER_IDENTIFIER"
            log_warning "Cluster will reboot to apply WLM configuration"
        fi
        
    else
        log_warning "Cluster $CLUSTER_IDENTIFIER not found"
        log_info "To apply parameter group to your cluster, run:"
        log_info "aws redshift modify-cluster \\"
        log_info "    --cluster-identifier YOUR_CLUSTER_ID \\"
        log_info "    --cluster-parameter-group-name $PARAMETER_GROUP_NAME \\"
        log_info "    --apply-immediately"
    fi
}

# Generate deployment summary
generate_summary() {
    log_info "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment_summary.txt" << EOF
Analytics Workload Isolation Deployment Summary
===============================================

Deployment Date: $(date)
Region: $AWS_REGION
Account: $AWS_ACCOUNT_ID

Resources Created:
- Parameter Group: $PARAMETER_GROUP_NAME
- SNS Topic: $SNS_TOPIC_ARN
- CloudWatch Alarms: 3 alarms created
- CloudWatch Dashboard: $DASHBOARD_NAME

Configuration Files:
- WLM Configuration: wlm_config_with_qmr.json
- User Setup SQL: setup_users_groups.sql
- Monitoring Views SQL: wlm_monitoring_views.sql
- Dashboard Config: wlm_dashboard.json

Next Steps:
1. Apply parameter group to your Redshift cluster (if not done automatically)
2. Execute setup_users_groups.sql to create database users and groups
3. Execute wlm_monitoring_views.sql to create monitoring views
4. Test workload isolation with different user groups

Cluster Configuration:
- To apply to existing cluster: 
  aws redshift modify-cluster --cluster-identifier YOUR_CLUSTER \\
    --cluster-parameter-group-name $PARAMETER_GROUP_NAME --apply-immediately

- After cluster reboot, connect and run the SQL scripts

Monitoring:
- CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME
- SNS Topic for alerts: $SNS_TOPIC_ARN

Cleanup:
- Run ./destroy.sh to remove all created resources
EOF
    
    log_success "Deployment summary saved to: ${SCRIPT_DIR}/deployment_summary.txt"
}

# Main deployment function
main() {
    log_info "Starting Analytics Workload Isolation deployment..."
    log_info "Log file: $LOG_FILE"
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "Running in dry-run mode - no resources will be created"
        export DRY_RUN=true
    fi
    
    # Check if running in non-interactive mode
    if [[ "${1:-}" == "--non-interactive" ]] || [[ "${DEPLOY_NON_INTERACTIVE:-}" == "true" ]]; then
        export DEPLOY_NON_INTERACTIVE=true
        log_info "Running in non-interactive mode"
    fi
    
    check_prerequisites
    load_configuration
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "Dry-run mode: Would create the following resources:"
        log_info "- Parameter Group: $PARAMETER_GROUP_NAME"
        log_info "- SNS Topic: $SNS_TOPIC_NAME"
        log_info "- CloudWatch Alarms: 3 alarms"
        log_info "- CloudWatch Dashboard: RedshiftWLM-${RANDOM_SUFFIX}"
        log_info "- SQL Scripts for setup and monitoring"
        exit 0
    fi
    
    create_parameter_group
    configure_wlm
    create_sns_topic
    create_cloudwatch_alarms
    create_dashboard
    create_sql_scripts
    apply_parameter_group
    generate_summary
    
    log_success "Analytics Workload Isolation deployment completed successfully!"
    log_info "Check deployment_summary.txt for next steps and configuration details"
    log_info "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi