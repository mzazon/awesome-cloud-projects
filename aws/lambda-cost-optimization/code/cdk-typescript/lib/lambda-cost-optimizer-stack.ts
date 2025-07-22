import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

/**
 * Stack Properties for Lambda Cost Optimizer
 */
export interface LambdaCostOptimizerStackProps extends cdk.StackProps {
  /**
   * Email address for notifications (optional)
   */
  notificationEmail?: string;
  
  /**
   * Minimum monthly savings threshold for automatic optimization
   * @default 1.0
   */
  savingsThreshold?: number;
  
  /**
   * Whether to enable automatic optimization application
   * @default false
   */
  enableAutoOptimization?: boolean;
}

/**
 * AWS CDK Stack for Lambda Cost Optimization with Compute Optimizer
 * 
 * This stack creates:
 * 1. Sample Lambda functions with different memory configurations for testing
 * 2. IAM roles and policies for Compute Optimizer access
 * 3. Lambda function to retrieve and apply Compute Optimizer recommendations
 * 4. CloudWatch monitoring and alarms for performance tracking
 * 5. SNS topic for notifications
 * 6. EventBridge rule for scheduled optimization checks
 */
export class LambdaCostOptimizerStack extends cdk.Stack {
  public readonly optimizerFunction: lambda.Function;
  public readonly monitoringTopic: sns.Topic;
  public readonly testFunctions: lambda.Function[];

  constructor(scope: Construct, id: string, props?: LambdaCostOptimizerStackProps) {
    super(scope, id, props);

    // Configuration from props with defaults
    const savingsThreshold = props?.savingsThreshold ?? 1.0;
    const enableAutoOptimization = props?.enableAutoOptimization ?? false;

    // Create SNS topic for notifications
    this.monitoringTopic = new sns.Topic(this, 'OptimizationNotifications', {
      topicName: 'lambda-cost-optimizer-notifications',
      displayName: 'Lambda Cost Optimizer Notifications',
      description: 'Notifications for Lambda cost optimization activities'
    });

    // Subscribe email if provided
    if (props?.notificationEmail) {
      this.monitoringTopic.addSubscription(
        new subscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create IAM role for Compute Optimizer access
    const computeOptimizerRole = new iam.Role(this, 'ComputeOptimizerRole', {
      roleName: 'lambda-cost-optimizer-role',
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Lambda Cost Optimizer to access Compute Optimizer and modify Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ComputeOptimizerAccess: new iam.PolicyDocument({
          statements: [
            // Compute Optimizer permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'compute-optimizer:GetEnrollmentStatus',
                'compute-optimizer:PutEnrollmentStatus',
                'compute-optimizer:GetLambdaFunctionRecommendations',
                'compute-optimizer:GetRecommendationSummaries'
              ],
              resources: ['*']
            }),
            // Lambda permissions for optimization
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:ListFunctions',
                'lambda:GetFunction',
                'lambda:GetFunctionConfiguration',
                'lambda:UpdateFunctionConfiguration',
                'lambda:ListAliases',
                'lambda:GetAlias'
              ],
              resources: ['*']
            }),
            // CloudWatch permissions for metrics analysis
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics',
                'cloudwatch:PutMetricData'
              ],
              resources: ['*']
            }),
            // SNS permissions for notifications
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish'
              ],
              resources: [this.monitoringTopic.topicArn]
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create the main optimizer Lambda function
    this.optimizerFunction = new lambda.Function(this, 'OptimizerFunction', {
      functionName: 'lambda-cost-optimizer',
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: computeOptimizerRole,
      timeout: cdk.Duration.minutes(15),
      memorySize: 512,
      description: 'Function to analyze and apply Compute Optimizer recommendations for Lambda functions',
      environment: {
        'SNS_TOPIC_ARN': this.monitoringTopic.topicArn,
        'SAVINGS_THRESHOLD': savingsThreshold.toString(),
        'AUTO_OPTIMIZATION_ENABLED': enableAutoOptimization.toString(),
        'LOG_LEVEL': 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# Initialize AWS clients
compute_optimizer = boto3.client('compute-optimizer')
lambda_client = boto3.client('lambda')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

# Configuration from environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
SAVINGS_THRESHOLD = float(os.environ.get('SAVINGS_THRESHOLD', '1.0'))
AUTO_OPTIMIZATION_ENABLED = os.environ.get('AUTO_OPTIMIZATION_ENABLED', 'false').lower() == 'true'

def lambda_handler(event, context):
    """
    Main Lambda handler for cost optimization analysis and application
    """
    try:
        logger.info("Starting Lambda cost optimization analysis")
        
        # Check if Compute Optimizer is enabled
        enrollment_status = check_compute_optimizer_enrollment()
        if not enrollment_status:
            return create_response(400, "Compute Optimizer is not enabled")
        
        # Get Lambda function recommendations
        recommendations = get_lambda_recommendations()
        
        if not recommendations:
            logger.info("No Lambda function recommendations available")
            return create_response(200, "No recommendations available")
        
        # Analyze recommendations
        analysis_results = analyze_recommendations(recommendations)
        
        # Send notification with analysis results
        send_notification(analysis_results)
        
        # Apply optimizations if auto-optimization is enabled
        if AUTO_OPTIMIZATION_ENABLED:
            optimization_results = apply_optimizations(recommendations)
            analysis_results['optimization_results'] = optimization_results
        
        logger.info(f"Analysis complete. Found {len(recommendations)} recommendations")
        return create_response(200, "Analysis completed successfully", analysis_results)
        
    except Exception as e:
        logger.error(f"Error in cost optimization analysis: {str(e)}")
        error_message = f"Lambda cost optimization failed: {str(e)}"
        
        if SNS_TOPIC_ARN:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject="Lambda Cost Optimization Error",
                Message=error_message
            )
        
        return create_response(500, error_message)

def check_compute_optimizer_enrollment() -> bool:
    """Check if Compute Optimizer is enrolled and active"""
    try:
        response = compute_optimizer.get_enrollment_status()
        status = response.get('status', 'Inactive')
        logger.info(f"Compute Optimizer enrollment status: {status}")
        return status == 'Active'
    except Exception as e:
        logger.error(f"Error checking Compute Optimizer enrollment: {str(e)}")
        return False

def get_lambda_recommendations() -> List[Dict[str, Any]]:
    """Retrieve Lambda function recommendations from Compute Optimizer"""
    try:
        paginator = compute_optimizer.get_paginator('get_lambda_function_recommendations')
        recommendations = []
        
        for page in paginator.paginate():
            recommendations.extend(page.get('lambdaFunctionRecommendations', []))
        
        logger.info(f"Retrieved {len(recommendations)} Lambda recommendations")
        return recommendations
        
    except Exception as e:
        logger.error(f"Error retrieving Lambda recommendations: {str(e)}")
        return []

def analyze_recommendations(recommendations: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Analyze recommendations and categorize them"""
    analysis = {
        'total_functions': len(recommendations),
        'optimized_functions': 0,
        'over_provisioned_functions': 0,
        'under_provisioned_functions': 0,
        'total_potential_savings': 0.0,
        'recommendations_above_threshold': 0,
        'function_details': []
    }
    
    for rec in recommendations:
        function_name = rec.get('functionName', '')
        finding = rec.get('finding', '')
        current_memory = rec.get('currentMemorySize', 0)
        
        function_detail = {
            'function_name': function_name,
            'finding': finding,
            'current_memory': current_memory
        }
        
        if finding == 'Optimized':
            analysis['optimized_functions'] += 1
            function_detail['status'] = 'Already optimized'
        else:
            # Get best recommendation option
            options = rec.get('memorySizeRecommendationOptions', [])
            if options:
                best_option = options[0]
                recommended_memory = best_option.get('memorySize', 0)
                savings = best_option.get('estimatedMonthlySavings', {}).get('value', 0)
                
                function_detail.update({
                    'recommended_memory': recommended_memory,
                    'estimated_savings': savings
                })
                
                analysis['total_potential_savings'] += savings
                
                if savings >= SAVINGS_THRESHOLD:
                    analysis['recommendations_above_threshold'] += 1
                
                if current_memory > recommended_memory:
                    analysis['over_provisioned_functions'] += 1
                    function_detail['category'] = 'over_provisioned'
                else:
                    analysis['under_provisioned_functions'] += 1
                    function_detail['category'] = 'under_provisioned'
        
        analysis['function_details'].append(function_detail)
    
    return analysis

def apply_optimizations(recommendations: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Apply optimization recommendations above the savings threshold"""
    results = {
        'applied_optimizations': 0,
        'failed_optimizations': 0,
        'skipped_optimizations': 0,
        'optimization_details': []
    }
    
    for rec in recommendations:
        function_name = rec.get('functionName', '')
        finding = rec.get('finding', '')
        current_memory = rec.get('currentMemorySize', 0)
        
        if finding != 'Optimized':
            options = rec.get('memorySizeRecommendationOptions', [])
            if options:
                best_option = options[0]
                recommended_memory = best_option.get('memorySize', 0)
                savings = best_option.get('estimatedMonthlySavings', {}).get('value', 0)
                
                if savings >= SAVINGS_THRESHOLD:
                    try:
                        # Apply the optimization
                        lambda_client.update_function_configuration(
                            FunctionName=function_name,
                            MemorySize=recommended_memory
                        )
                        
                        logger.info(f"Successfully optimized {function_name}: {current_memory}MB -> {recommended_memory}MB")
                        results['applied_optimizations'] += 1
                        results['optimization_details'].append({
                            'function_name': function_name,
                            'status': 'success',
                            'old_memory': current_memory,
                            'new_memory': recommended_memory,
                            'estimated_savings': savings
                        })
                        
                    except Exception as e:
                        logger.error(f"Failed to optimize {function_name}: {str(e)}")
                        results['failed_optimizations'] += 1
                        results['optimization_details'].append({
                            'function_name': function_name,
                            'status': 'failed',
                            'error': str(e)
                        })
                else:
                    results['skipped_optimizations'] += 1
                    results['optimization_details'].append({
                        'function_name': function_name,
                        'status': 'skipped',
                        'reason': f'Savings ${savings:.2f} below threshold ${SAVINGS_THRESHOLD:.2f}'
                    })
    
    return results

def send_notification(analysis_results: Dict[str, Any]) -> None:
    """Send notification with analysis results"""
    if not SNS_TOPIC_ARN:
        return
    
    try:
        subject = "Lambda Cost Optimization Analysis Results"
        
        message = f"""
Lambda Cost Optimization Analysis Results
========================================

Total Functions Analyzed: {analysis_results['total_functions']}
Already Optimized: {analysis_results['optimized_functions']}
Over-provisioned: {analysis_results['over_provisioned_functions']}
Under-provisioned: {analysis_results['under_provisioned_functions']}

Total Potential Monthly Savings: ${ analysis_results['total_potential_savings']:.2f}
Total Potential Annual Savings: ${analysis_results['total_potential_savings'] * 12:.2f}

Functions Above Savings Threshold (${SAVINGS_THRESHOLD:.2f}): {analysis_results['recommendations_above_threshold']}

Auto-optimization Status: {'Enabled' if AUTO_OPTIMIZATION_ENABLED else 'Disabled'}

Detailed recommendations are available in the CloudWatch logs.
        """
        
        # Add optimization results if available
        if 'optimization_results' in analysis_results:
            opt_results = analysis_results['optimization_results']
            message += f"""

Optimization Results:
- Applied: {opt_results['applied_optimizations']}
- Failed: {opt_results['failed_optimizations']}
- Skipped: {opt_results['skipped_optimizations']}
"""
        
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message.strip()
        )
        
        logger.info("Notification sent successfully")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")

def create_response(status_code: int, message: str, data: Optional[Dict] = None) -> Dict:
    """Create standardized response"""
    response = {
        'statusCode': status_code,
        'message': message,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    if data:
        response['data'] = data
    
    return response
`)
    });

    // Create CloudWatch Log Group for the optimizer function
    const optimizerLogGroup = new logs.LogGroup(this, 'OptimizerLogGroup', {
      logGroupName: `/aws/lambda/${this.optimizerFunction.functionName}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create sample Lambda functions for testing optimization
    this.testFunctions = this.createTestFunctions();

    // Create EventBridge rule for scheduled optimization checks
    const optimizationSchedule = new events.Rule(this, 'OptimizationSchedule', {
      ruleName: 'lambda-cost-optimizer-schedule',
      description: 'Schedule for running Lambda cost optimization analysis',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '9',
        weekDay: 'MON'  // Run every Monday at 9 AM UTC
      })
    });

    // Add the optimizer function as target
    optimizationSchedule.addTarget(new targets.LambdaFunction(this.optimizerFunction));

    // Create CloudWatch alarms for monitoring post-optimization performance
    this.createMonitoringAlarms();

    // Create CloudWatch dashboard for cost optimization metrics
    this.createDashboard();

    // Output important information
    new cdk.CfnOutput(this, 'OptimizerFunctionName', {
      value: this.optimizerFunction.functionName,
      description: 'Name of the Lambda cost optimizer function'
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.monitoringTopic.topicArn,
      description: 'ARN of the SNS topic for notifications'
    });

    new cdk.CfnOutput(this, 'ScheduleRuleName', {
      value: optimizationSchedule.ruleName,
      description: 'Name of the EventBridge rule for scheduled optimization'
    });

    new cdk.CfnOutput(this, 'TestFunctionNames', {
      value: this.testFunctions.map(fn => fn.functionName).join(', '),
      description: 'Names of the test Lambda functions created for optimization testing'
    });
  }

  /**
   * Create sample Lambda functions with different memory configurations for testing
   */
  private createTestFunctions(): lambda.Function[] {
    const testFunctions: lambda.Function[] = [];

    // Test function configurations with intentionally suboptimal memory settings
    const testConfigs = [
      {
        name: 'high-memory-test-function',
        memorySize: 1024,
        description: 'Test function with high memory allocation (likely over-provisioned)'
      },
      {
        name: 'low-memory-test-function',
        memorySize: 128,
        description: 'Test function with low memory allocation (may be under-provisioned)'
      },
      {
        name: 'medium-memory-test-function',
        memorySize: 512,
        description: 'Test function with medium memory allocation'
      }
    ];

    testConfigs.forEach((config, index) => {
      const testFunction = new lambda.Function(this, `TestFunction${index}`, {
        functionName: config.name,
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'index.lambda_handler',
        memorySize: config.memorySize,
        timeout: cdk.Duration.seconds(30),
        description: config.description,
        code: lambda.Code.fromInline(`
import json
import time
import random
import math

def lambda_handler(event, context):
    """
    Test function that performs various computational tasks
    to generate realistic memory and CPU usage patterns
    """
    
    # Simulate different types of workloads
    workload_type = event.get('workload_type', 'cpu_bound')
    
    if workload_type == 'cpu_bound':
        # CPU-intensive task that may benefit from more memory (more CPU)
        result = perform_cpu_intensive_task()
    elif workload_type == 'memory_bound':
        # Memory-intensive task
        result = perform_memory_intensive_task()
    else:
        # Lightweight task
        result = perform_lightweight_task()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Test function executed successfully with workload: {workload_type}',
            'function_name': context.function_name,
            'memory_size': context.memory_limit_in_mb,
            'remaining_time': context.get_remaining_time_in_millis(),
            'result': result
        })
    }

def perform_cpu_intensive_task():
    """Simulate CPU-intensive computation"""
    start_time = time.time()
    
    # Calculate prime numbers (CPU-intensive)
    primes = []
    for num in range(2, 1000):
        is_prime = True
        for i in range(2, int(math.sqrt(num)) + 1):
            if num % i == 0:
                is_prime = False
                break
        if is_prime:
            primes.append(num)
    
    execution_time = time.time() - start_time
    return {
        'task_type': 'cpu_intensive',
        'primes_found': len(primes),
        'execution_time_ms': round(execution_time * 1000, 2)
    }

def perform_memory_intensive_task():
    """Simulate memory-intensive operations"""
    start_time = time.time()
    
    # Create and manipulate large data structures
    large_list = [random.randint(1, 1000) for _ in range(50000)]
    
    # Sort the list multiple times
    for _ in range(5):
        large_list.sort(reverse=True)
        large_list.sort()
    
    # Calculate statistics
    total = sum(large_list)
    average = total / len(large_list)
    
    execution_time = time.time() - start_time
    return {
        'task_type': 'memory_intensive',
        'list_size': len(large_list),
        'average': round(average, 2),
        'execution_time_ms': round(execution_time * 1000, 2)
    }

def perform_lightweight_task():
    """Simulate lightweight operations"""
    start_time = time.time()
    
    # Simple calculations
    result = sum(range(100))
    
    # Small delay to simulate I/O
    time.sleep(0.1)
    
    execution_time = time.time() - start_time
    return {
        'task_type': 'lightweight',
        'calculation_result': result,
        'execution_time_ms': round(execution_time * 1000, 2)
    }
`)
      });

      // Create CloudWatch Log Group for each test function
      new logs.LogGroup(this, `TestFunction${index}LogGroup`, {
        logGroupName: `/aws/lambda/${testFunction.functionName}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY
      });

      testFunctions.push(testFunction);
    });

    return testFunctions;
  }

  /**
   * Create CloudWatch alarms for monitoring optimization impact
   */
  private createMonitoringAlarms(): void {
    // Create alarm for Lambda error rate increase
    const errorRateAlarm = new cloudwatch.Alarm(this, 'LambdaErrorRateAlarm', {
      alarmName: 'lambda-optimization-error-rate-alarm',
      alarmDescription: 'Monitor Lambda error rate increase after optimization',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Lambda',
        metricName: 'Errors',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to the alarm
    errorRateAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.monitoringTopic));

    // Create alarm for Lambda duration increase
    const durationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: 'lambda-optimization-duration-alarm',
      alarmDescription: 'Monitor Lambda duration increase after optimization',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Lambda',
        metricName: 'Duration',
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 10000, // 10 seconds
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    durationAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.monitoringTopic));
  }

  /**
   * Create CloudWatch dashboard for cost optimization metrics
   */
  private createDashboard(): void {
    const dashboard = new cloudwatch.Dashboard(this, 'CostOptimizationDashboard', {
      dashboardName: 'lambda-cost-optimization-dashboard',
      defaultInterval: cdk.Duration.hours(24)
    });

    // Add widgets for Lambda metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Invocations',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Invocations',
            statistic: 'Sum'
          })
        ]
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Duration',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Duration',
            statistic: 'Average'
          })
        ]
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Errors',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Errors',
            statistic: 'Sum'
          })
        ]
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Throttles',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Throttles',
            statistic: 'Sum'
          })
        ]
      })
    );
  }
}