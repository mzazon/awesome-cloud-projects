# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_suffix = random_id.suffix.hex
  common_tags = merge(var.additional_tags, {
    Purpose     = "PerformanceCostAnalytics"
    Environment = var.environment
  })
}

#################################
# CloudWatch Log Group for VPC Lattice
#################################

resource "aws_cloudwatch_log_group" "vpc_lattice_logs" {
  name              = "/aws/vpclattice/performance-analytics"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Performance Analytics Logs"
  })
}

#################################
# IAM Role and Policies for Lambda Functions
#################################

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.name_prefix}-lambda-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Lambda Execution Role for VPC Lattice Analytics"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Attach CloudWatch Logs full access
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.lambda_execution_role.name
}

# Custom policy for Cost Explorer and additional permissions
resource "aws_iam_policy" "cost_explorer_analytics" {
  name        = "CostExplorerAnalyticsPolicy-${local.name_suffix}"
  description = "Policy for Cost Explorer access and VPC Lattice analytics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetDimensionValues",
          "ce:GetMetricsAndUsage",
          "ce:ListCostCategoryDefinitions",
          "ce:GetUsageReport",
          "ce:GetAnomalyDetectors",
          "ce:GetAnomalySubscriptions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "vpc-lattice:GetService",
          "vpc-lattice:GetServiceNetwork",
          "vpc-lattice:ListServices",
          "vpc-lattice:ListServiceNetworks"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_cost_explorer" {
  policy_arn = aws_iam_policy.cost_explorer_analytics.arn
  role       = aws_iam_role.lambda_execution_role.name
}

#################################
# VPC Lattice Service Network
#################################

resource "aws_vpclattice_service_network" "analytics_network" {
  name      = "${var.name_prefix}-mesh-${local.name_suffix}"
  auth_type = var.service_network_auth_type

  tags = merge(local.common_tags, {
    Name = "Performance Cost Analytics Service Network"
  })
}

# Configure CloudWatch Logs integration for VPC Lattice
resource "aws_vpclattice_access_log_subscription" "service_network_logs" {
  resource_identifier = aws_vpclattice_service_network.analytics_network.arn
  destination_arn     = aws_cloudwatch_log_group.vpc_lattice_logs.arn

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Access Log Subscription"
  })
}

# Sample VPC Lattice service for testing (optional)
resource "aws_vpclattice_service" "sample_service" {
  count = var.create_sample_service ? 1 : 0

  name = "sample-analytics-service-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name       = "Sample Analytics Service"
    CostCenter = "Analytics"
  })
}

# Associate sample service with service network
resource "aws_vpclattice_service_network_service_association" "sample_association" {
  count = var.create_sample_service ? 1 : 0

  service_identifier         = aws_vpclattice_service.sample_service[0].id
  service_network_identifier = aws_vpclattice_service_network.analytics_network.id

  tags = merge(local.common_tags, {
    Name = "Sample Service Association"
  })
}

#################################
# Lambda Functions
#################################

# Archive Lambda function code
data "archive_file" "performance_analyzer" {
  type        = "zip"
  output_path = "${path.module}/performance_analyzer.zip"
  source {
    content = file("${path.module}/lambda_functions/performance_analyzer.py")
    filename = "performance_analyzer.py"
  }
}

data "archive_file" "cost_correlator" {
  type        = "zip"
  output_path = "${path.module}/cost_correlator.zip"
  source {
    content = file("${path.module}/lambda_functions/cost_correlator.py")
    filename = "cost_correlator.py"
  }
}

data "archive_file" "report_generator" {
  type        = "zip"
  output_path = "${path.module}/lambda_functions/report_generator.zip"
  source {
    content = file("${path.module}/lambda_functions/report_generator.py")
    filename = "report_generator.py"
  }
}

# Performance Analyzer Lambda Function
resource "aws_lambda_function" "performance_analyzer" {
  filename         = data.archive_file.performance_analyzer.output_path
  function_name    = "performance-analyzer-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "performance_analyzer.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout_seconds
  memory_size     = var.lambda_memory_mb
  source_code_hash = data.archive_file.performance_analyzer.output_base64sha256

  environment {
    variables = {
      LOG_GROUP_NAME = aws_cloudwatch_log_group.vpc_lattice_logs.name
    }
  }

  description = "Analyzes VPC Lattice performance metrics using CloudWatch Insights"

  tags = merge(local.common_tags, {
    Name = "Performance Analyzer Function"
  })
}

# Cost Correlator Lambda Function
resource "aws_lambda_function" "cost_correlator" {
  filename         = data.archive_file.cost_correlator.output_path
  function_name    = "cost-correlator-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "cost_correlator.lambda_handler"
  runtime         = "python3.12"
  timeout         = 120
  memory_size     = var.lambda_memory_mb
  source_code_hash = data.archive_file.cost_correlator.output_base64sha256

  description = "Correlates VPC Lattice performance with AWS costs"

  tags = merge(local.common_tags, {
    Name = "Cost Correlator Function"
  })
}

# Report Generator Lambda Function
resource "aws_lambda_function" "report_generator" {
  filename         = data.archive_file.report_generator.output_path
  function_name    = "report-generator-${local.name_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "report_generator.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout_seconds
  memory_size     = 256
  source_code_hash = data.archive_file.report_generator.output_base64sha256

  description = "Orchestrates performance and cost analysis reporting"

  tags = merge(local.common_tags, {
    Name = "Report Generator Function"
  })
}

#################################
# EventBridge Scheduling
#################################

# EventBridge rule for scheduled analytics
resource "aws_cloudwatch_event_rule" "analytics_scheduler" {
  name                = "analytics-scheduler-${local.name_suffix}"
  description         = "Trigger VPC Lattice performance cost analytics"
  schedule_expression = var.analytics_schedule
  state              = "ENABLED"

  tags = merge(local.common_tags, {
    Name = "Analytics Scheduler Rule"
  })
}

# EventBridge target for report generator Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.analytics_scheduler.name
  target_id = "ReportGeneratorTarget"
  arn       = aws_lambda_function.report_generator.arn

  input = jsonencode({
    suffix    = local.name_suffix
    log_group = aws_cloudwatch_log_group.vpc_lattice_logs.name
  })
}

# Lambda permission for EventBridge to invoke report generator
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge-${local.name_suffix}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.analytics_scheduler.arn
}

#################################
# Cost Anomaly Detection
#################################

# Cost anomaly detector for VPC and Lambda services
resource "aws_ce_anomaly_detector" "vpc_lattice_costs" {
  count = var.enable_cost_anomaly_detection ? 1 : 0

  name         = "vpc-lattice-cost-anomalies-${local.name_suffix}"
  monitor_type = "DIMENSIONAL"

  dimension_key = "SERVICE"
  monitor_specification {
    dimension_key    = "SERVICE"
    match_options    = ["EQUALS"]
    values          = ["Amazon Virtual Private Cloud"]
  }

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Cost Anomaly Detector"
  })
}

# Cost anomaly subscription for notifications
resource "aws_ce_anomaly_subscription" "cost_alerts" {
  count = var.enable_cost_anomaly_detection ? 1 : 0

  name      = "lattice-cost-alerts-${local.name_suffix}"
  frequency = "DAILY"
  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = [tostring(var.cost_anomaly_threshold)]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  monitor_arn_list = [aws_ce_anomaly_detector.vpc_lattice_costs[0].arn]

  subscriber {
    type    = "EMAIL"
    address = var.notification_email
  }

  tags = merge(local.common_tags, {
    Name = "Lattice Cost Alert Subscription"
  })
}

#################################
# CloudWatch Dashboard
#################################

# CloudWatch dashboard for performance cost analytics
resource "aws_cloudwatch_dashboard" "performance_analytics" {
  count = var.enable_dashboard ? 1 : 0

  dashboard_name = "VPC-Lattice-Performance-Cost-Analytics-${local.name_suffix}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/VPCLattice", "NewConnectionCount", "ServiceNetwork", aws_vpclattice_service_network.analytics_network.name],
            [".", "ActiveConnectionCount", ".", "."],
            ["VPCLattice/Performance", "AverageResponseTime", "ServiceName", var.create_sample_service ? aws_vpclattice_service.sample_service[0].name : "sample-service"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "VPC Lattice Performance Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.vpc_lattice_logs.name}' | fields @timestamp, targetService, responseTime, requestSize\n| filter @message like /requestId/\n| stats avg(responseTime) as avgResponseTime by targetService\n| sort avgResponseTime desc"
          region = data.aws_region.current.name
          title  = "Service Response Time Analysis"
          view   = "table"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.vpc_lattice_logs.name}' | fields @timestamp, responseCode\n| filter @message like /requestId/\n| stats count() as requestCount by responseCode\n| sort requestCount desc"
          region = data.aws_region.current.name
          title  = "Response Code Distribution"
          view   = "pie"
        }
      }
    ]
  })
}

#################################
# Lambda Function Source Files
#################################

# Create lambda functions directory and source files
resource "local_file" "performance_analyzer_source" {
  content = <<-EOT
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
EOT
  filename = "${path.module}/lambda_functions/performance_analyzer.py"
}

resource "local_file" "cost_correlator_source" {
  content = <<-EOT
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
EOT
  filename = "${path.module}/lambda_functions/cost_correlator.py"
}

resource "local_file" "report_generator_source" {
  content = <<-EOT
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
EOT
  filename = "${path.module}/lambda_functions/report_generator.py"
}