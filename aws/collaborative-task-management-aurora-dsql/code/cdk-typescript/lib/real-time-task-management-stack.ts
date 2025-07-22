import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as rds from 'aws-cdk-lib/aws-rds';
import { Construct } from 'constructs';

export interface RealTimeTaskManagementStackProps extends cdk.StackProps {
  region: string;
  isSecondaryRegion: boolean;
}

export class RealTimeTaskManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RealTimeTaskManagementStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    
    // Resource naming with region identifier
    const regionIdentifier = props.isSecondaryRegion ? 'secondary' : 'primary';
    const clusterName = `task-mgmt-cluster-${regionIdentifier}-${uniqueSuffix}`;
    const eventBusName = `task-events-${regionIdentifier}-${uniqueSuffix}`;
    const lambdaFunctionName = `task-processor-${regionIdentifier}-${uniqueSuffix}`;

    // ========================================
    // Aurora DSQL Cluster
    // ========================================
    
    // Note: Aurora DSQL is relatively new and may not have full CDK L2 constructs yet.
    // Using L1 constructs (CfnResource) for Aurora DSQL cluster creation.
    const dsqlCluster = new rds.CfnDBCluster(this, 'AuroraDSQLCluster', {
      engine: 'aurora-dsql',
      dbClusterIdentifier: clusterName,
      engineMode: 'multimaster', // Multi-region active-active mode
      globalClusterIdentifier: props.isSecondaryRegion ? undefined : `global-${clusterName}`,
      enableCloudwatchLogsExports: ['audit'],
      backupRetentionPeriod: 7,
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      deletionProtection: false, // Set to true for production
      storageEncrypted: true,
      tags: [
        {
          key: 'Name',
          value: clusterName
        },
        {
          key: 'Environment',
          value: 'development'
        },
        {
          key: 'Application',
          value: 'TaskManagement'
        },
        {
          key: 'Region',
          value: regionIdentifier
        }
      ]
    });

    // ========================================
    // EventBridge Custom Event Bus
    // ========================================
    
    const customEventBus = new events.EventBus(this, 'TaskManagementEventBus', {
      eventBusName: eventBusName,
      description: `Custom event bus for task management events in ${regionIdentifier} region`
    });

    // ========================================
    // IAM Role for Lambda Function
    // ========================================
    
    const lambdaRole = new iam.Role(this, 'TaskProcessorLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for task processor Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        TaskProcessorPolicy: new iam.PolicyDocument({
          statements: [
            // Aurora DSQL permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dsql:DescribeCluster',
                'dsql:Execute',
                'dsql:BatchExecute',
                'dsql:Connect'
              ],
              resources: ['*'] // Aurora DSQL doesn't support resource-level permissions yet
            }),
            // EventBridge permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'events:PutEvents',
                'events:DescribeEventBus'
              ],
              resources: [
                customEventBus.eventBusArn,
                `arn:aws:events:${props.region}:${this.account}:event-bus/*`
              ]
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: [`arn:aws:logs:${props.region}:${this.account}:log-group:/aws/lambda/${lambdaFunctionName}:*`]
            }),
            // RDS Connect for Aurora DSQL
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'rds-db:connect'
              ],
              resources: [`arn:aws:rds-db:${props.region}:${this.account}:dbuser:${clusterName}/*`]
            })
          ]
        })
      }
    });

    // ========================================
    // Lambda Function for Task Processing
    // ========================================
    
    const taskProcessorFunction = new lambda.Function(this, 'TaskProcessorFunction', {
      functionName: lambdaFunctionName,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'task_processor.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
events_client = boto3.client('events')
rds_client = boto3.client('rds')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing task management events
    """
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Process EventBridge event
        if 'source' in event and event['source'] == 'task.management':
            return process_task_event(event)
        
        # Process direct invocation (API Gateway)
        if 'httpMethod' in event:
            return process_api_request(event, context)
        
        # Process test events
        if 'Records' in event:
            return process_batch_events(event['Records'])
            
        # Default response for unrecognized event types
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'region': os.environ.get('AWS_REGION'),
                'function': context.function_name if context else 'unknown'
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'region': os.environ.get('AWS_REGION')
            })
        }

def process_task_event(event):
    """Process task management events from EventBridge"""
    try:
        detail = event.get('detail', {})
        event_type = detail.get('eventType', 'unknown')
        
        logger.info(f"Processing task event type: {event_type}")
        
        # Route to specific handlers based on event type
        if event_type == 'task.created':
            return handle_task_created(detail)
        elif event_type == 'task.updated':
            return handle_task_updated(detail)
        elif event_type == 'task.completed':
            return handle_task_completed(detail)
        else:
            logger.warning(f"Unhandled event type: {event_type}")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': f'Processed {event_type} event'})
            }
            
    except Exception as e:
        logger.error(f"Error processing task event: {str(e)}")
        raise

def handle_task_created(detail):
    """Handle task creation events"""
    task_data = detail.get('taskData', {})
    logger.info(f"Creating task: {task_data.get('title', 'Unknown')}")
    
    # In a real implementation, this would connect to Aurora DSQL
    # and insert the task into the database
    # For now, we'll simulate the database operation
    
    task_id = simulate_database_insert(task_data)
    
    # Publish notification event
    publish_task_notification('task.created', task_id, task_data)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'task_id': task_id,
            'message': 'Task created successfully',
            'region': os.environ.get('AWS_REGION')
        })
    }

def handle_task_updated(detail):
    """Handle task update events"""
    task_id = detail.get('taskId')
    updates = detail.get('updates', {})
    updated_by = detail.get('updatedBy', 'system')
    
    logger.info(f"Updating task {task_id} with {len(updates)} changes")
    
    # Simulate database update
    simulate_database_update(task_id, updates, updated_by)
    
    # Publish notification event
    publish_task_notification('task.updated', task_id, updates)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Task {task_id} updated successfully',
            'region': os.environ.get('AWS_REGION')
        })
    }

def handle_task_completed(detail):
    """Handle task completion events"""
    task_id = detail.get('taskId')
    completed_by = detail.get('completedBy', 'system')
    
    logger.info(f"Marking task {task_id} as completed by {completed_by}")
    
    # Simulate database update for completion
    simulate_task_completion(task_id, completed_by)
    
    # Publish notification event
    publish_task_notification('task.completed', task_id, {'completed_by': completed_by})
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Task {task_id} completed successfully',
            'region': os.environ.get('AWS_REGION')
        })
    }

def process_api_request(event, context):
    """Process direct API requests (for API Gateway integration)"""
    try:
        method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')
        
        logger.info(f"Processing API request: {method} {path}")
        
        if method == 'GET' and path == '/tasks':
            return get_all_tasks()
        elif method == 'POST' and path == '/tasks':
            body = json.loads(event.get('body', '{}'))
            return create_task_via_api(body)
        elif method == 'PUT' and '/tasks/' in path:
            task_id = path.split('/')[-1]
            body = json.loads(event.get('body', '{}'))
            return update_task_via_api(task_id, body)
        
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Not found'})
        }
        
    except Exception as e:
        logger.error(f"Error processing API request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_all_tasks():
    """Simulate getting all tasks"""
    # In real implementation, query Aurora DSQL
    sample_tasks = [
        {
            'id': 1,
            'title': 'Implement user authentication',
            'status': 'in-progress',
            'assigned_to': 'developer@company.com',
            'created_at': datetime.utcnow().isoformat(),
            'region': os.environ.get('AWS_REGION')
        },
        {
            'id': 2,
            'title': 'Code review for authentication feature',
            'status': 'pending',
            'assigned_to': 'senior.dev@company.com',
            'created_at': datetime.utcnow().isoformat(),
            'region': os.environ.get('AWS_REGION')
        }
    ]
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'tasks': sample_tasks})
    }

def create_task_via_api(task_data):
    """Create task via API"""
    task_id = simulate_database_insert(task_data)
    
    return {
        'statusCode': 201,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'task_id': task_id,
            'message': 'Task created successfully',
            'region': os.environ.get('AWS_REGION')
        })
    }

def update_task_via_api(task_id, updates):
    """Update task via API"""
    simulate_database_update(task_id, updates, 'api-user')
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': f'Task {task_id} updated successfully',
            'region': os.environ.get('AWS_REGION')
        })
    }

def simulate_database_insert(task_data):
    """Simulate database insert operation"""
    # In real implementation, this would use Aurora DSQL connection
    import random
    task_id = random.randint(1000, 9999)
    logger.info(f"Simulated database insert for task: {task_data.get('title')} with ID: {task_id}")
    return task_id

def simulate_database_update(task_id, updates, updated_by):
    """Simulate database update operation"""
    logger.info(f"Simulated database update for task {task_id} by {updated_by}: {updates}")

def simulate_task_completion(task_id, completed_by):
    """Simulate task completion database operation"""
    logger.info(f"Simulated task completion for task {task_id} by {completed_by}")

def publish_task_notification(event_type, task_id, data):
    """Publish task notification to EventBridge"""
    try:
        response = events_client.put_events(
            Entries=[
                {
                    'Source': 'task.management.notifications',
                    'DetailType': 'Task Notification',
                    'Detail': json.dumps({
                        'eventType': event_type,
                        'taskId': task_id,
                        'data': data,
                        'timestamp': datetime.utcnow().isoformat(),
                        'region': os.environ.get('AWS_REGION')
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        logger.info(f"Published notification event: {event_type} for task {task_id}")
        return response
    except Exception as e:
        logger.error(f"Failed to publish notification: {str(e)}")
        return None

def process_batch_events(records):
    """Process batch events from SQS or similar sources"""
    processed = 0
    for record in records:
        try:
            # Process each record
            logger.info(f"Processing record: {record}")
            processed += 1
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {processed} records',
            'region': os.environ.get('AWS_REGION')
        })
    }
      `),
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      role: lambdaRole,
      environment: {
        'DSQL_CLUSTER_NAME': clusterName,
        'EVENT_BUS_NAME': eventBusName,
        'AWS_REGION': props.region,
        'REGION_IDENTIFIER': regionIdentifier
      },
      description: `Task processor Lambda function for ${regionIdentifier} region`
    });

    // ========================================
    // CloudWatch Log Group for Lambda
    // ========================================
    
    const logGroup = new logs.LogGroup(this, 'TaskProcessorLogGroup', {
      logGroupName: `/aws/lambda/${lambdaFunctionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // ========================================
    // EventBridge Rules and Targets
    // ========================================
    
    // Rule for task processing events
    const taskProcessingRule = new events.Rule(this, 'TaskProcessingRule', {
      eventBus: customEventBus,
      ruleName: `task-processing-rule-${regionIdentifier}`,
      description: `Route task management events to processor function in ${regionIdentifier} region`,
      eventPattern: {
        source: ['task.management'],
        detailType: ['Task Created', 'Task Updated', 'Task Completed']
      }
    });

    // Add Lambda function as target for the rule
    taskProcessingRule.addTarget(new targets.LambdaFunction(taskProcessorFunction, {
      retryAttempts: 3
    }));

    // Rule for notification events
    const notificationRule = new events.Rule(this, 'NotificationRule', {
      eventBus: customEventBus,
      ruleName: `task-notification-rule-${regionIdentifier}`,
      description: `Route task notification events for logging in ${regionIdentifier} region`,
      eventPattern: {
        source: ['task.management.notifications'],
        detailType: ['Task Notification']
      }
    });

    // Add Lambda function as target for notifications (for logging purposes)
    notificationRule.addTarget(new targets.LambdaFunction(taskProcessorFunction, {
      retryAttempts: 2
    }));

    // ========================================
    // CloudWatch Monitoring and Alarms
    // ========================================
    
    // Lambda function error alarm
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${lambdaFunctionName}-errors`,
      alarmDescription: `Monitor Lambda function errors for ${regionIdentifier} region`,
      metric: taskProcessorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Lambda function duration alarm
    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `${lambdaFunctionName}-duration`,
      alarmDescription: `Monitor Lambda function duration for ${regionIdentifier} region`,
      metric: taskProcessorFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE
      }),
      threshold: 30000, // 30 seconds
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // EventBridge custom metric for failed invocations
    const eventBridgeFailedInvocationsAlarm = new cloudwatch.Alarm(this, 'EventBridgeFailedInvocationsAlarm', {
      alarmName: `${eventBusName}-failed-invocations`,
      alarmDescription: `Monitor EventBridge failed invocations for ${regionIdentifier} region`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Events',
        metricName: 'FailedInvocations',
        dimensionsMap: {
          'EventBusName': eventBusName
        },
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM
      }),
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // ========================================
    // CloudWatch Dashboard
    // ========================================
    
    const dashboard = new cloudwatch.Dashboard(this, 'TaskManagementDashboard', {
      dashboardName: `TaskManagement-${regionIdentifier}-Dashboard`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              taskProcessorFunction.metricInvocations(),
              taskProcessorFunction.metricErrors(),
              taskProcessorFunction.metricThrottles()
            ],
            right: [taskProcessorFunction.metricDuration()],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'EventBridge Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'SuccessfulInvocations',
                dimensionsMap: {
                  'EventBusName': eventBusName
                }
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'FailedInvocations',
                dimensionsMap: {
                  'EventBusName': eventBusName
                }
              })
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6
          })
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Recent Lambda Logs',
            logGroups: [logGroup],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /ERROR/ or @message like /INFO/',
              'sort @timestamp desc',
              'limit 100'
            ],
            width: 24,
            height: 6
          })
        ]
      ]
    });

    // ========================================
    // Stack Outputs
    // ========================================
    
    new cdk.CfnOutput(this, 'DSQLClusterIdentifier', {
      value: dsqlCluster.dbClusterIdentifier || clusterName,
      description: `Aurora DSQL cluster identifier for ${regionIdentifier} region`,
      exportName: `${id}-DSQLClusterIdentifier`
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: customEventBus.eventBusName,
      description: `EventBridge custom bus name for ${regionIdentifier} region`,
      exportName: `${id}-EventBusName`
    });

    new cdk.CfnOutput(this, 'EventBusArn', {
      value: customEventBus.eventBusArn,
      description: `EventBridge custom bus ARN for ${regionIdentifier} region`,
      exportName: `${id}-EventBusArn`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: taskProcessorFunction.functionName,
      description: `Lambda function name for task processing in ${regionIdentifier} region`,
      exportName: `${id}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: taskProcessorFunction.functionArn,
      description: `Lambda function ARN for task processing in ${regionIdentifier} region`,
      exportName: `${id}-LambdaFunctionArn`
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroupName', {
      value: logGroup.logGroupName,
      description: `CloudWatch log group name for ${regionIdentifier} region`,
      exportName: `${id}-LogGroupName`
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardName', {
      value: dashboard.dashboardName,
      description: `CloudWatch dashboard name for ${regionIdentifier} region`,
      exportName: `${id}-DashboardName`
    });

    new cdk.CfnOutput(this, 'Region', {
      value: props.region,
      description: 'Deployment region',
      exportName: `${id}-Region`
    });

    new cdk.CfnOutput(this, 'IsSecondaryRegion', {
      value: props.isSecondaryRegion.toString(),
      description: 'Whether this is the secondary region deployment',
      exportName: `${id}-IsSecondaryRegion`
    });

    // ========================================
    // Resource Tags
    // ========================================
    
    // Apply consistent tags to all resources in the stack
    cdk.Tags.of(this).add('Application', 'TaskManagement');
    cdk.Tags.of(this).add('Environment', 'development');
    cdk.Tags.of(this).add('Region', regionIdentifier);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Project', 'RealTimeCollaborativeTaskManagement');
  }
}