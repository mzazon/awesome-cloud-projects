#!/bin/bash
set -e

# Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights
# Deployment Script
#
# This script deploys the complete infrastructure for correlating VPC Lattice 
# service mesh performance metrics with AWS costs using CloudWatch Insights 
# and Cost Explorer API integration.

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        error "AWS CLI version 2.x or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required tools
    for tool in jq zip; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is required but not installed"
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured. Set AWS_REGION environment variable or configure AWS CLI"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Set resource names
    export SERVICE_NETWORK_NAME="analytics-mesh-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/vpclattice/performance-analytics"
    export LAMBDA_ROLE_NAME="lattice-analytics-role-${RANDOM_SUFFIX}"
    
    # Create state file for cleanup
    cat > deployment_state.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
SERVICE_NETWORK_NAME=${SERVICE_NETWORK_NAME}
LOG_GROUP_NAME=${LOG_GROUP_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Environment initialized with unique suffix: ${RANDOM_SUFFIX}"
}

# Create CloudWatch Log Group
create_log_group() {
    log "Creating CloudWatch Log Group for VPC Lattice logs..."
    
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query "logGroups[?logGroupName=='${LOG_GROUP_NAME}']" --output text | grep -q "${LOG_GROUP_NAME}"; then
        warning "Log group ${LOG_GROUP_NAME} already exists, skipping creation"
    else
        aws logs create-log-group \
            --log-group-name ${LOG_GROUP_NAME} \
            --retention-in-days 7 \
            --tags Key=Purpose,Value=PerformanceCostAnalytics,Key=Environment,Value=Demo
        success "CloudWatch Log Group created: ${LOG_GROUP_NAME}"
    fi
}

# Create IAM role for Lambda functions
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    # Check if role already exists
    if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        warning "IAM role ${LAMBDA_ROLE_NAME} already exists, skipping creation"
        export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
        return
    fi
    
    # Create trust policy for Lambda
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
    
    # Create IAM role
    aws iam create-role \
        --role-name ${LAMBDA_ROLE_NAME} \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --tags Key=Purpose,Value=PerformanceCostAnalytics
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 15
    
    success "IAM role created: ${LAMBDA_ROLE_NAME}"
}

# Create custom policy for Cost Explorer access
create_cost_explorer_policy() {
    log "Creating custom policy for Cost Explorer access..."
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostExplorerAnalyticsPolicy-${RANDOM_SUFFIX} &> /dev/null; then
        warning "Cost Explorer policy already exists, skipping creation"
        return
    fi
    
    # Create custom policy for Cost Explorer access
    cat > cost-explorer-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetDimensionValues",
        "ce:GetMetricsAndUsage",
        "ce:ListCostCategoryDefinitions",
        "ce:GetUsageReport",
        "ce:GetAnomalyDetectors",
        "ce:GetAnomalySubscriptions"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:StartQuery",
        "logs:GetQueryResults",
        "vpc-lattice:GetService",
        "vpc-lattice:GetServiceNetwork",
        "vpc-lattice:ListServices",
        "vpc-lattice:ListServiceNetworks"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Create and attach the policy
    aws iam create-policy \
        --policy-name CostExplorerAnalyticsPolicy-${RANDOM_SUFFIX} \
        --policy-document file://cost-explorer-policy.json \
        --description "Policy for VPC Lattice performance cost analytics"
    
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostExplorerAnalyticsPolicy-${RANDOM_SUFFIX}
    
    success "Cost Explorer permissions configured"
}

# Create VPC Lattice service network
create_vpc_lattice_network() {
    log "Creating VPC Lattice service network..."
    
    # Check if service network already exists
    if aws vpc-lattice list-service-networks --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].id" --output text | grep -q .; then
        warning "VPC Lattice service network ${SERVICE_NETWORK_NAME} already exists"
        export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
            --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].id" \
            --output text)
        export SERVICE_NETWORK_ARN=$(aws vpc-lattice list-service-networks \
            --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].arn" \
            --output text)
        return
    fi
    
    # Create VPC Lattice service network with monitoring enabled
    aws vpc-lattice create-service-network \
        --name ${SERVICE_NETWORK_NAME} \
        --auth-type AWS_IAM \
        --tags Key=Purpose,Value=PerformanceCostAnalytics,Key=Environment,Value=Demo
    
    # Wait for creation and store service network details
    log "Waiting for service network creation..."
    sleep 10
    
    export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
        --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].id" \
        --output text)
    
    export SERVICE_NETWORK_ARN=$(aws vpc-lattice list-service-networks \
        --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].arn" \
        --output text)
    
    success "VPC Lattice service network created: ${SERVICE_NETWORK_ID}"
}

# Configure CloudWatch Logs integration
configure_cloudwatch_integration() {
    log "Configuring CloudWatch Logs integration for VPC Lattice..."
    
    # Check if access log subscription already exists
    if aws vpc-lattice get-access-log-subscription --resource-identifier ${SERVICE_NETWORK_ARN} &> /dev/null; then
        warning "Access log subscription already exists for service network"
        return
    fi
    
    # Configure access logs for the service network
    aws vpc-lattice put-access-log-subscription \
        --resource-identifier ${SERVICE_NETWORK_ARN} \
        --destination-arn arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}
    
    # Wait for configuration to propagate
    log "Waiting for access log configuration to propagate..."
    sleep 15
    
    success "CloudWatch Logs integration configured"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions for performance and cost analysis..."
    
    # Create performance analyzer function code
    cat > performance_analyzer.py << 'EOF'
import json
import boto3
import time
from datetime import datetime, timedelta

def lambda_handler(event, context):
    logs_client = boto3.client('logs')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Calculate time range for analysis (last 24 hours)
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        # CloudWatch Insights query for VPC Lattice performance
        query = """
        fields @timestamp, sourceVpc, targetService, responseTime, requestSize, responseSize
        | filter @message like /requestId/
        | stats avg(responseTime) as avgResponseTime, 
                sum(requestSize) as totalRequests,
                sum(responseSize) as totalBytes,
                count() as requestCount by targetService
        | sort avgResponseTime desc
        """
        
        # Start CloudWatch Insights query
        query_response = logs_client.start_query(
            logGroupName=event.get('log_group', '/aws/vpclattice/performance-analytics'),
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = query_response['queryId']
        
        # Wait for query completion
        for attempt in range(30):  # Wait up to 30 seconds
            query_status = logs_client.get_query_results(queryId=query_id)
            if query_status['status'] == 'Complete':
                break
            elif query_status['status'] == 'Failed':
                raise Exception(f"Query failed: {query_status.get('statistics', {})}")
            time.sleep(1)
        else:
            raise Exception("Query timeout after 30 seconds")
        
        # Process results and publish custom metrics
        performance_data = []
        for result in query_status.get('results', []):
            service_metrics = {}
            for field in result:
                service_metrics[field['field']] = field['value']
            
            if service_metrics:
                performance_data.append(service_metrics)
                
                # Publish custom CloudWatch metrics
                if 'targetService' in service_metrics and 'avgResponseTime' in service_metrics:
                    try:
                        cloudwatch.put_metric_data(
                            Namespace='VPCLattice/Performance',
                            MetricData=[
                                {
                                    'MetricName': 'AverageResponseTime',
                                    'Dimensions': [
                                        {
                                            'Name': 'ServiceName',
                                            'Value': service_metrics['targetService']
                                        }
                                    ],
                                    'Value': float(service_metrics['avgResponseTime']),
                                    'Unit': 'Milliseconds',
                                    'Timestamp': datetime.now()
                                }
                            ]
                        )
                    except Exception as metric_error:
                        print(f"Error publishing metrics: {metric_error}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'services_analyzed': len(performance_data),
                'performance_data': performance_data,
                'query_id': query_id
            })
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Performance analysis failed'
            })
        }
EOF
    
    # Create cost correlator function code
    cat > cost_correlator.py << 'EOF'
import json
import boto3
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ce_client = boto3.client('ce')
    
    try:
        # Calculate date range for cost analysis
        end_date = datetime.now()
        start_date = end_date - timedelta(days=7)
        
        # Get cost and usage data for VPC Lattice and related services
        cost_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ],
            Filter={
                'Dimensions': {
                    'Key': 'SERVICE',
                    'Values': ['Amazon Virtual Private Cloud', 'Amazon Elastic Compute Cloud - Compute', 'AWS Lambda'],
                    'MatchOptions': ['EQUALS']
                }
            }
        )
        
        # Process cost data
        cost_analysis = {}
        total_cost = 0.0
        
        for result_by_time in cost_response['ResultsByTime']:
            date = result_by_time['TimePeriod']['Start']
            cost_analysis[date] = {}
            
            for group in result_by_time['Groups']:
                service = group['Keys'][0]
                cost = float(group['Metrics']['BlendedCost']['Amount'])
                usage = float(group['Metrics']['UsageQuantity']['Amount'])
                
                cost_analysis[date][service] = {
                    'cost': cost,
                    'usage': usage,
                    'cost_per_unit': cost / usage if usage > 0 else 0
                }
                total_cost += cost
        
        # Correlate with performance data from event
        performance_data = event.get('performance_data', [])
        
        correlations = []
        for service_perf in performance_data:
            service_name = service_perf.get('targetService', 'unknown')
            avg_response_time = float(service_perf.get('avgResponseTime', 0)) if service_perf.get('avgResponseTime') else 0
            request_count = int(service_perf.get('requestCount', 0)) if service_perf.get('requestCount') else 0
            
            # Calculate cost efficiency metric
            vpc_cost = sum(
                day_data.get('Amazon Virtual Private Cloud', {}).get('cost', 0) 
                for day_data in cost_analysis.values()
            )
            
            if request_count > 0 and avg_response_time > 0:
                cost_per_request = vpc_cost / request_count if request_count > 0 else 0
                # Efficiency score: higher is better (inverse relationship with cost and response time)
                efficiency_score = 1000 / (avg_response_time * (cost_per_request + 0.001)) if (avg_response_time > 0 and cost_per_request >= 0) else 0
            else:
                cost_per_request = 0
                efficiency_score = 0
            
            correlations.append({
                'service': service_name,
                'avg_response_time': avg_response_time,
                'request_count': request_count,
                'estimated_cost': vpc_cost,
                'cost_per_request': cost_per_request,
                'efficiency_score': efficiency_score
            })
        
        # Sort by efficiency score to identify optimization opportunities
        correlations.sort(key=lambda x: x['efficiency_score'], reverse=True)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cost_analysis': cost_analysis,
                'total_cost_analyzed': total_cost,
                'service_correlations': correlations,
                'optimization_candidates': [
                    corr for corr in correlations 
                    if corr['efficiency_score'] < 50  # Low efficiency threshold
                ]
            })
        }
        
    except Exception as e:
        print(f"Error in cost correlation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Cost correlation analysis failed'
            })
        }
EOF
    
    # Create report generator function code
    cat > report_generator.py << 'EOF'
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    lambda_client = boto3.client('lambda')
    
    try:
        suffix = event.get('suffix', '')
        log_group = event.get('log_group', '/aws/vpclattice/performance-analytics')
        
        # Invoke performance analyzer
        perf_response = lambda_client.invoke(
            FunctionName=f"performance-analyzer-{suffix}",
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'log_group': log_group
            })
        )
        
        perf_data = json.loads(perf_response['Payload'].read())
        
        # Check for errors in performance analysis
        if perf_data.get('statusCode') != 200:
            raise Exception(f"Performance analysis failed: {perf_data.get('body', 'Unknown error')}")
        
        perf_body = json.loads(perf_data.get('body', '{}'))
        
        # Invoke cost correlator with performance data
        cost_response = lambda_client.invoke(
            FunctionName=f"cost-correlator-{suffix}",
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'performance_data': perf_body.get('performance_data', [])
            })
        )
        
        cost_data = json.loads(cost_response['Payload'].read())
        
        # Check for errors in cost analysis
        if cost_data.get('statusCode') != 200:
            raise Exception(f"Cost analysis failed: {cost_data.get('body', 'Unknown error')}")
        
        cost_body = json.loads(cost_data.get('body', '{}'))
        
        # Generate comprehensive report
        optimization_candidates = cost_body.get('optimization_candidates', [])
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'summary': {
                'services_analyzed': perf_body.get('services_analyzed', 0),
                'optimization_opportunities': len(optimization_candidates),
                'total_cost_analyzed': cost_body.get('total_cost_analyzed', 0),
                'analysis_period': '24 hours (performance) / 7 days (cost)'
            },
            'performance_insights': perf_body.get('performance_data', []),
            'cost_correlations': cost_body.get('service_correlations', []),
            'optimization_recommendations': optimization_candidates
        }
        
        # Generate actionable recommendations
        recommendations = []
        for candidate in optimization_candidates:
            service_name = candidate.get('service', 'unknown')
            avg_response_time = candidate.get('avg_response_time', 0)
            cost_per_request = candidate.get('cost_per_request', 0)
            
            if avg_response_time > 500:  # High response time threshold
                recommendations.append(f"Service {service_name}: Consider optimizing for performance (avg response time: {avg_response_time:.2f}ms)")
            
            if cost_per_request > 0.01:  # High cost per request threshold
                recommendations.append(f"Service {service_name}: Review resource allocation (cost per request: ${cost_per_request:.4f})")
            
            if candidate.get('efficiency_score', 0) < 10:  # Very low efficiency
                recommendations.append(f"Service {service_name}: Critical efficiency review needed (efficiency score: {candidate.get('efficiency_score', 0):.2f})")
        
        if not recommendations:
            recommendations.append("No critical optimization opportunities identified. Continue monitoring for trends.")
        
        report['actionable_recommendations'] = recommendations
        
        return {
            'statusCode': 200,
            'body': json.dumps(report, default=str, indent=2)
        }
        
    except Exception as e:
        print(f"Error in report generation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Report generation failed',
                'timestamp': datetime.now().isoformat()
            })
        }
EOF
    
    # Create and deploy Lambda functions
    local functions=("performance-analyzer" "cost-correlator" "report-generator")
    local timeouts=(90 120 180)
    local memories=(256 512 256)
    
    for i in "${!functions[@]}"; do
        local func_name="${functions[$i]}-${RANDOM_SUFFIX}"
        local timeout="${timeouts[$i]}"
        local memory="${memories[$i]}"
        local python_file="${functions[$i]//-/_}.py"
        
        # Check if function already exists
        if aws lambda get-function --function-name "$func_name" &> /dev/null; then
            warning "Lambda function $func_name already exists, updating code..."
            zip "${functions[$i]}.zip" "$python_file"
            aws lambda update-function-code \
                --function-name "$func_name" \
                --zip-file "fileb://${functions[$i]}.zip"
        else
            log "Creating Lambda function: $func_name"
            zip "${functions[$i]}.zip" "$python_file"
            
            aws lambda create-function \
                --function-name "$func_name" \
                --runtime python3.12 \
                --role ${LAMBDA_ROLE_ARN} \
                --handler "${functions[$i]//-/_}.lambda_handler" \
                --zip-file "fileb://${functions[$i]}.zip" \
                --timeout "$timeout" \
                --memory-size "$memory" \
                --environment Variables="{LOG_GROUP_NAME=${LOG_GROUP_NAME}}" \
                --description "VPC Lattice ${functions[$i]} for performance cost analytics" \
                --tags Key=Purpose,Value=PerformanceCostAnalytics
        fi
    done
    
    success "Lambda functions created/updated successfully"
}

# Create sample VPC Lattice service
create_sample_service() {
    log "Creating sample VPC Lattice service for testing..."
    
    local service_name="sample-analytics-service-${RANDOM_SUFFIX}"
    
    # Check if service already exists
    if aws vpc-lattice list-services --query "services[?name=='${service_name}'].id" --output text | grep -q .; then
        warning "Sample service already exists"
        export SAMPLE_SERVICE_ID=$(aws vpc-lattice list-services \
            --query "services[?name=='${service_name}'].id" --output text)
    else
        # Create a sample service in VPC Lattice
        aws vpc-lattice create-service \
            --name "$service_name" \
            --tags Key=Purpose,Value=AnalyticsDemo,Key=CostCenter,Value=Analytics
        
        # Get service details
        export SAMPLE_SERVICE_ID=$(aws vpc-lattice list-services \
            --query "services[?name=='${service_name}'].id" --output text)
    fi
    
    # Associate service with the service network
    if ! aws vpc-lattice list-service-network-service-associations \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --query "serviceNetworkServiceAssociations[?serviceId=='${SAMPLE_SERVICE_ID}']" \
        --output text | grep -q .; then
        
        aws vpc-lattice create-service-network-service-association \
            --service-network-identifier ${SERVICE_NETWORK_ID} \
            --service-identifier ${SAMPLE_SERVICE_ID} \
            --tags Key=Purpose,Value=AnalyticsDemo
    fi
    
    success "Sample VPC Lattice service created: ${SAMPLE_SERVICE_ID}"
}

# Configure automated scheduling
configure_scheduling() {
    log "Configuring automated scheduling with EventBridge..."
    
    local rule_name="analytics-scheduler-${RANDOM_SUFFIX}"
    
    # Check if rule already exists
    if aws events describe-rule --name "$rule_name" &> /dev/null; then
        warning "EventBridge rule already exists"
        return
    fi
    
    # Create EventBridge rule for scheduled analytics
    aws events put-rule \
        --name "$rule_name" \
        --schedule-expression "rate(6 hours)" \
        --state ENABLED \
        --description "Trigger VPC Lattice performance cost analytics every 6 hours"
    
    # Add Lambda target to the rule
    aws events put-targets \
        --rule "$rule_name" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:report-generator-${RANDOM_SUFFIX}","Input"="{\"suffix\":\"${RANDOM_SUFFIX}\",\"log_group\":\"${LOG_GROUP_NAME}\"}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "report-generator-${RANDOM_SUFFIX}" \
        --statement-id "analytics-eventbridge-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/$rule_name" \
        2>/dev/null || warning "Permission already exists"
    
    success "Automated scheduling configured for 6-hour analytics cycles"
}

# Create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard for performance cost analytics..."
    
    local dashboard_name="VPC-Lattice-Performance-Cost-Analytics-${RANDOM_SUFFIX}"
    
    # Create CloudWatch dashboard configuration
    cat > dashboard-config.json << EOF
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
                    [ "AWS/VPCLattice", "NewConnectionCount", "ServiceNetwork", "${SERVICE_NETWORK_NAME}" ],
                    [ ".", "ActiveConnectionCount", ".", "." ],
                    [ "VPCLattice/Performance", "AverageResponseTime", "ServiceName", "sample-analytics-service-${RANDOM_SUFFIX}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "VPC Lattice Performance Metrics",
                "view": "timeSeries",
                "stacked": false
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '${LOG_GROUP_NAME}' | fields @timestamp, targetService, responseTime, requestSize\\n| filter @message like /requestId/\\n| stats avg(responseTime) as avgResponseTime by targetService\\n| sort avgResponseTime desc",
                "region": "${AWS_REGION}",
                "title": "Service Response Time Analysis",
                "view": "table"
            }
        },
        {
            "type": "log",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '${LOG_GROUP_NAME}' | fields @timestamp, responseCode\\n| filter @message like /requestId/\\n| stats count() as requestCount by responseCode\\n| sort requestCount desc",
                "region": "${AWS_REGION}",
                "title": "Response Code Distribution",
                "view": "pie"
            }
        }
    ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body file://dashboard-config.json
    
    success "Performance cost analytics dashboard created"
    log "Access dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=$dashboard_name"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Update state file with additional information
    cat >> deployment_state.env << EOF
SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}
SERVICE_NETWORK_ARN=${SERVICE_NETWORK_ARN}
SAMPLE_SERVICE_ID=${SAMPLE_SERVICE_ID}
LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}
EOF
    
    # Create deployment summary
    cat > deployment_summary.json << EOF
{
  "deployment": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}"
  },
  "resources": {
    "service_network": {
      "name": "${SERVICE_NETWORK_NAME}",
      "id": "${SERVICE_NETWORK_ID}",
      "arn": "${SERVICE_NETWORK_ARN}"
    },
    "log_group": "${LOG_GROUP_NAME}",
    "iam_role": {
      "name": "${LAMBDA_ROLE_NAME}",
      "arn": "${LAMBDA_ROLE_ARN}"
    },
    "lambda_functions": [
      "performance-analyzer-${RANDOM_SUFFIX}",
      "cost-correlator-${RANDOM_SUFFIX}",
      "report-generator-${RANDOM_SUFFIX}"
    ],
    "sample_service_id": "${SAMPLE_SERVICE_ID}",
    "dashboard": "VPC-Lattice-Performance-Cost-Analytics-${RANDOM_SUFFIX}",
    "eventbridge_rule": "analytics-scheduler-${RANDOM_SUFFIX}"
  },
  "access_urls": {
    "dashboard": "https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=VPC-Lattice-Performance-Cost-Analytics-${RANDOM_SUFFIX}",
    "vpc_lattice_console": "https://console.aws.amazon.com/vpc/home?region=${AWS_REGION}#ServiceNetworks:",
    "lambda_console": "https://console.aws.amazon.com/lambda/home?region=${AWS_REGION}#/functions"
  }
}
EOF
    
    success "Deployment information saved to deployment_summary.json"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    
    # Remove temporary files
    rm -f lambda-trust-policy.json cost-explorer-policy.json dashboard-config.json
    rm -f *.py *.zip
    
    # Note: Keep deployment_state.env for manual cleanup if needed
    warning "Check deployment_state.env for resource identifiers if manual cleanup is needed"
}

# Main deployment function
main() {
    log "Starting Service Performance Cost Analytics deployment..."
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_log_group
    create_iam_role
    create_cost_explorer_policy
    create_vpc_lattice_network
    configure_cloudwatch_integration
    create_lambda_functions
    create_sample_service
    configure_scheduling
    create_dashboard
    save_deployment_info
    
    # Cleanup temporary files
    rm -f lambda-trust-policy.json cost-explorer-policy.json dashboard-config.json
    rm -f *.py *.zip
    
    success "Deployment completed successfully!"
    echo
    log "Next steps:"
    echo "1. Access the CloudWatch dashboard to monitor performance metrics"
    echo "2. Trigger the analytics pipeline manually or wait for scheduled execution"
    echo "3. Review the generated reports for optimization opportunities"
    echo
    log "To test the analytics pipeline immediately:"
    echo "aws lambda invoke --function-name report-generator-${RANDOM_SUFFIX} \\"
    echo "    --payload '{\"suffix\":\"${RANDOM_SUFFIX}\",\"log_group\":\"${LOG_GROUP_NAME}\"}' \\"
    echo "    --cli-binary-format raw-in-base64-out analytics-report.json"
    echo
    log "To clean up all resources, run: ./destroy.sh"
}

# Run main function
main "$@"