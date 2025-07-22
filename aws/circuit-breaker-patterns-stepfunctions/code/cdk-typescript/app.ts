#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as path from 'path';

/**
 * Props for the CircuitBreakerStack
 */
interface CircuitBreakerStackProps extends cdk.StackProps {
  /** Failure threshold before circuit breaker opens */
  readonly failureThreshold?: number;
  /** Circuit breaker timeout in minutes */
  readonly timeoutMinutes?: number;
  /** Environment name for resource tagging */
  readonly environment?: string;
}

/**
 * Stack implementing Circuit Breaker Pattern with AWS Step Functions
 * 
 * This stack creates a comprehensive circuit breaker implementation that:
 * - Monitors downstream service health
 * - Automatically trips circuit breaker on failures
 * - Provides fallback responses during outages
 * - Includes health checks for automatic recovery
 * - Implements comprehensive monitoring and alerting
 */
export class CircuitBreakerStack extends cdk.Stack {
  // Public properties for accessing created resources
  public readonly stateMachine: stepfunctions.StateMachine;
  public readonly circuitBreakerTable: dynamodb.Table;
  public readonly downstreamServiceFunction: lambda.Function;
  public readonly fallbackServiceFunction: lambda.Function;
  public readonly healthCheckFunction: lambda.Function;

  constructor(scope: Construct, id: string, props?: CircuitBreakerStackProps) {
    super(scope, id, props);

    // Extract configuration with defaults
    const failureThreshold = props?.failureThreshold ?? 3;
    const timeoutMinutes = props?.timeoutMinutes ?? 5;
    const environment = props?.environment ?? 'dev';

    // Create DynamoDB table for circuit breaker state management
    this.circuitBreakerTable = this.createCircuitBreakerTable();

    // Create Lambda functions for the circuit breaker pattern
    this.downstreamServiceFunction = this.createDownstreamServiceFunction(environment);
    this.fallbackServiceFunction = this.createFallbackServiceFunction();
    this.healthCheckFunction = this.createHealthCheckFunction(this.circuitBreakerTable);

    // Create the Step Functions state machine
    this.stateMachine = this.createCircuitBreakerStateMachine(
      this.circuitBreakerTable,
      this.downstreamServiceFunction,
      this.fallbackServiceFunction,
      this.healthCheckFunction,
      failureThreshold
    );

    // Create CloudWatch alarms for monitoring
    this.createMonitoringAlarms();

    // Add tags to all resources
    this.addResourceTags(environment);

    // Create outputs for easy access to resource information
    this.createOutputs();
  }

  /**
   * Creates DynamoDB table for storing circuit breaker state
   * Uses on-demand billing and point-in-time recovery for production resilience
   */
  private createCircuitBreakerTable(): dynamodb.Table {
    return new dynamodb.Table(this, 'CircuitBreakerTable', {
      tableName: `circuit-breaker-state-${this.stackName}`,
      partitionKey: {
        name: 'ServiceName',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.ON_DEMAND,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      tags: [
        { key: 'Purpose', value: 'CircuitBreakerState' },
        { key: 'Component', value: 'StateManagement' }
      ]
    });
  }

  /**
   * Creates downstream service Lambda function that simulates external dependencies
   * Includes configurable failure rates for testing circuit breaker behavior
   */
  private createDownstreamServiceFunction(environment: string): lambda.Function {
    return new lambda.Function(this, 'DownstreamServiceFunction', {
      functionName: `downstream-service-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import random
import time
import os

def lambda_handler(event, context):
    """
    Simulates a downstream service with configurable failure rate and latency.
    Environment variables:
    - FAILURE_RATE: Probability of failure (0.0 to 1.0)
    - LATENCY_MS: Simulated response time in milliseconds
    """
    # Get configuration from environment variables
    failure_rate = float(os.environ.get('FAILURE_RATE', '0.3'))
    latency_ms = int(os.environ.get('LATENCY_MS', '100'))
    
    # Simulate network latency
    time.sleep(latency_ms / 1000)
    
    # Simulate service failures based on configured rate
    if random.random() < failure_rate:
        raise Exception(f"Service temporarily unavailable - simulated failure")
    
    # Return successful response
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Downstream service response successful',
            'timestamp': context.aws_request_id,
            'service_name': 'payment-service',
            'environment': os.environ.get('ENVIRONMENT', 'unknown')
        })
    }
      `),
      timeout: cdk.Duration.seconds(30),
      environment: {
        'FAILURE_RATE': environment === 'prod' ? '0.1' : '0.5', // Lower failure rate in production
        'LATENCY_MS': '200',
        'ENVIRONMENT': environment
      },
      description: 'Simulates downstream service with configurable failure patterns for circuit breaker testing'
    });
  }

  /**
   * Creates fallback service Lambda function
   * Provides degraded but functional responses when circuit breaker is open
   */
  private createFallbackServiceFunction(): lambda.Function {
    return new lambda.Function(this, 'FallbackServiceFunction', {
      functionName: `fallback-service-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    """
    Provides fallback response when primary service is unavailable.
    Returns cached data or default responses to maintain user experience.
    """
    # Extract original request details
    original_request = event.get('original_request', {})
    circuit_state = event.get('circuit_breaker_state', 'UNKNOWN')
    
    # Create fallback response with relevant information
    fallback_data = {
        'message': 'Fallback service response - primary service temporarily unavailable',
        'timestamp': datetime.utcnow().isoformat(),
        'source': 'fallback-service',
        'circuit_breaker_state': circuit_state,
        'fallback_reason': 'Circuit breaker is open - protecting downstream service',
        'original_request_id': original_request.get('request_id'),
        'service_status': 'degraded',
        'estimated_recovery_time': '5-10 minutes',
        # In production, this could return cached data or alternative responses
        'cached_data': {
            'last_known_good_response': 'Sample cached response',
            'cache_timestamp': '2025-01-01T12:00:00Z'
        }
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(fallback_data),
        'headers': {
            'X-Service-Status': 'fallback',
            'X-Circuit-Breaker-State': circuit_state
        }
    }
      `),
      timeout: cdk.Duration.seconds(30),
      description: 'Provides fallback responses when circuit breaker is open, ensuring graceful degradation'
    });
  }

  /**
   * Creates health check Lambda function for circuit breaker recovery
   * Periodically tests downstream service health and updates circuit breaker state
   */
  private createHealthCheckFunction(table: dynamodb.Table): lambda.Function {
    const healthCheckFunction = new lambda.Function(this, 'HealthCheckFunction', {
      functionName: `health-check-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta
import random

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Performs health checks on downstream services and manages circuit breaker state.
    Implements HALF_OPEN state logic for gradual recovery.
    """
    table_name = event['table_name']
    service_name = event['service_name']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get current circuit breaker state
        response = table.get_item(
            Key={'ServiceName': service_name}
        )
        
        if 'Item' not in response:
            # Initialize circuit breaker state if not exists
            table.put_item(
                Item={
                    'ServiceName': service_name,
                    'State': 'CLOSED',
                    'FailureCount': 0,
                    'LastFailureTime': None,
                    'LastSuccessTime': datetime.utcnow().isoformat(),
                    'LastHealthCheck': datetime.utcnow().isoformat()
                }
            )
            return create_health_response(service_name, 'healthy', 'CLOSED')
        
        item = response['Item']
        current_state = item['State']
        failure_count = item.get('FailureCount', 0)
        
        # Simulate health check (in production, call actual service endpoint)
        health_check_success = perform_health_check()
        
        if health_check_success:
            # Service is healthy - reset circuit breaker to CLOSED
            table.put_item(
                Item={
                    'ServiceName': service_name,
                    'State': 'CLOSED',
                    'FailureCount': 0,
                    'LastFailureTime': None,
                    'LastSuccessTime': datetime.utcnow().isoformat(),
                    'LastHealthCheck': datetime.utcnow().isoformat()
                }
            )
            return create_health_response(service_name, 'healthy', 'CLOSED')
        else:
            # Health check failed - maintain current state
            table.update_item(
                Key={'ServiceName': service_name},
                UpdateExpression='SET LastHealthCheck = :timestamp',
                ExpressionAttributeValues={
                    ':timestamp': datetime.utcnow().isoformat()
                }
            )
            return create_health_response(service_name, 'unhealthy', current_state)
    
    except Exception as e:
        print(f"Health check error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Health check failed: {str(e)}',
                'service_name': service_name
            })
        }

def perform_health_check():
    """
    Simulates health check logic. In production, this would:
    - Make HTTP request to service health endpoint
    - Check service metrics
    - Validate service dependencies
    """
    # Simulate health check with 70% success rate for demonstration
    return random.random() > 0.3

def create_health_response(service_name, health_status, circuit_state):
    """Creates standardized health check response"""
    status_code = 200 if health_status == 'healthy' else 503
    
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'service_name': service_name,
            'health_status': health_status,
            'circuit_state': circuit_state,
            'check_timestamp': datetime.utcnow().isoformat()
        })
    }
      `),
      timeout: cdk.Duration.seconds(30),
      description: 'Performs health checks and manages circuit breaker recovery logic'
    });

    // Grant DynamoDB permissions to health check function
    table.grantReadWriteData(healthCheckFunction);

    return healthCheckFunction;
  }

  /**
   * Creates the Step Functions state machine implementing circuit breaker pattern
   * Implements comprehensive circuit breaker logic with error handling and monitoring
   */
  private createCircuitBreakerStateMachine(
    table: dynamodb.Table,
    downstreamFunction: lambda.Function,
    fallbackFunction: lambda.Function,
    healthCheckFunction: lambda.Function,
    failureThreshold: number
  ): stepfunctions.StateMachine {

    // Define state machine tasks
    const checkCircuitState = new sfnTasks.DynamoGetItem(this, 'CheckCircuitBreakerState', {
      table: table,
      key: {
        ServiceName: sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.service_name')
        )
      },
      resultPath: '$.circuit_state'
    });

    const initializeCircuitBreaker = new sfnTasks.DynamoPutItem(this, 'InitializeCircuitBreaker', {
      table: table,
      item: {
        ServiceName: sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.service_name')
        ),
        State: sfnTasks.DynamoAttributeValue.fromString('CLOSED'),
        FailureCount: sfnTasks.DynamoAttributeValue.fromNumber(0),
        LastFailureTime: sfnTasks.DynamoAttributeValue.fromNullValue(),
        LastSuccessTime: sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')
        )
      }
    });

    const callDownstreamService = new sfnTasks.LambdaInvoke(this, 'CallDownstreamService', {
      lambdaFunction: downstreamFunction,
      payload: stepfunctions.TaskInput.fromJsonPathAt('$.request_payload'),
      resultPath: '$.service_result',
      retryOnServiceExceptions: false
    });

    const callFallbackService = new sfnTasks.LambdaInvoke(this, 'CallFallbackService', {
      lambdaFunction: fallbackFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'original_request.$': '$.request_payload',
        'circuit_breaker_state.$': '$.circuit_state.Item.State.S'
      }),
      resultPath: '$.fallback_result'
    });

    const performHealthCheck = new sfnTasks.LambdaInvoke(this, 'PerformHealthCheck', {
      lambdaFunction: healthCheckFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'table_name': table.tableName,
        'service_name.$': '$.service_name'
      }),
      resultPath: '$.health_check_result'
    });

    const recordSuccess = new sfnTasks.DynamoUpdateItem(this, 'RecordSuccess', {
      table: table,
      key: {
        ServiceName: sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.service_name')
        )
      },
      updateExpression: 'SET #state = :closed_state, FailureCount = :zero, LastSuccessTime = :timestamp',
      expressionAttributeNames: {
        '#state': 'State'
      },
      expressionAttributeValues: {
        ':closed_state': sfnTasks.DynamoAttributeValue.fromString('CLOSED'),
        ':zero': sfnTasks.DynamoAttributeValue.fromNumber(0),
        ':timestamp': sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')
        )
      }
    });

    const recordFailure = new sfnTasks.DynamoUpdateItem(this, 'RecordFailure', {
      table: table,
      key: {
        ServiceName: sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.service_name')
        )
      },
      updateExpression: 'SET FailureCount = FailureCount + :inc, LastFailureTime = :timestamp',
      expressionAttributeValues: {
        ':inc': sfnTasks.DynamoAttributeValue.fromNumber(1),
        ':timestamp': sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')
        )
      },
      resultPath: '$.update_result'
    });

    const checkFailureCount = new sfnTasks.DynamoGetItem(this, 'CheckFailureCount', {
      table: table,
      key: {
        ServiceName: sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.service_name')
        )
      },
      resultPath: '$.current_state'
    });

    const tripCircuitBreaker = new sfnTasks.DynamoUpdateItem(this, 'TripCircuitBreaker', {
      table: table,
      key: {
        ServiceName: sfnTasks.DynamoAttributeValue.fromString(
          stepfunctions.JsonPath.stringAt('$.service_name')
        )
      },
      updateExpression: 'SET #state = :open_state',
      expressionAttributeNames: {
        '#state': 'State'
      },
      expressionAttributeValues: {
        ':open_state': sfnTasks.DynamoAttributeValue.fromString('OPEN')
      }
    });

    // Define choice states for circuit breaker logic
    const evaluateCircuitState = new stepfunctions.Choice(this, 'EvaluateCircuitState')
      .when(
        stepfunctions.Condition.stringEquals('$.circuit_state.Item.State.S', 'OPEN'),
        performHealthCheck
      )
      .when(
        stepfunctions.Condition.stringEquals('$.circuit_state.Item.State.S', 'HALF_OPEN'),
        callDownstreamService
      )
      .when(
        stepfunctions.Condition.stringEquals('$.circuit_state.Item.State.S', 'CLOSED'),
        callDownstreamService
      )
      .otherwise(callDownstreamService);

    const evaluateHealthCheck = new stepfunctions.Choice(this, 'EvaluateHealthCheck')
      .when(
        stepfunctions.Condition.numberEquals('$.health_check_result.Payload.statusCode', 200),
        callDownstreamService
      )
      .otherwise(callFallbackService);

    const evaluateFailureThreshold = new stepfunctions.Choice(this, 'EvaluateFailureThreshold')
      .when(
        stepfunctions.Condition.numberGreaterThanEquals(
          '$.current_state.Item.FailureCount.N',
          failureThreshold
        ),
        tripCircuitBreaker
      )
      .otherwise(callFallbackService);

    // Define final states
    const returnSuccess = new stepfunctions.Pass(this, 'ReturnSuccess', {
      parameters: {
        'statusCode': 200,
        'body.$': '$.service_result.Payload.body',
        'circuit_breaker_state': 'CLOSED',
        'response_source': 'primary_service'
      }
    });

    const returnFallback = new stepfunctions.Pass(this, 'ReturnFallback', {
      parameters: {
        'statusCode': 200,
        'body.$': '$.fallback_result.Payload.body',
        'circuit_breaker_state': 'OPEN',
        'fallback_used': true,
        'response_source': 'fallback_service'
      }
    });

    // Build the state machine definition
    const definition = checkCircuitState
      .addCatch(initializeCircuitBreaker.next(callDownstreamService), {
        errors: ['States.ALL']
      })
      .next(evaluateCircuitState);

    callDownstreamService
      .addCatch(recordFailure.next(checkFailureCount.next(evaluateFailureThreshold)), {
        errors: ['States.ALL'],
        resultPath: '$.error'
      })
      .addRetry({
        errors: ['States.TaskFailed'],
        intervalSeconds: 1,
        maxAttempts: 2,
        backoffRate: 2.0
      })
      .next(recordSuccess.next(returnSuccess));

    tripCircuitBreaker.next(callFallbackService);
    callFallbackService.next(returnFallback);
    performHealthCheck.next(evaluateHealthCheck);

    // Create the state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'CircuitBreakerStateMachine', {
      stateMachineName: `CircuitBreakerStateMachine-${this.stackName}`,
      definition: definition,
      timeout: cdk.Duration.minutes(5),
      tracingEnabled: true,
      logs: {
        destination: new cloudwatch.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/CircuitBreaker-${this.stackName}`,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
          retention: cloudwatch.RetentionDays.ONE_WEEK
        }),
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true
      }
    });

    // Grant necessary permissions
    table.grantReadWriteData(stateMachine);
    downstreamFunction.grantInvoke(stateMachine);
    fallbackFunction.grantInvoke(stateMachine);
    healthCheckFunction.grantInvoke(stateMachine);

    return stateMachine;
  }

  /**
   * Creates CloudWatch alarms for monitoring circuit breaker behavior
   * Provides operational visibility and alerting for system health
   */
  private createMonitoringAlarms(): void {
    // Create alarm for Step Functions execution failures
    new cloudwatch.Alarm(this, 'StateMachineFailureAlarm', {
      alarmName: `CircuitBreaker-ExecutionFailures-${this.stackName}`,
      alarmDescription: 'Monitors Step Functions execution failures',
      metric: this.stateMachine.metricFailed({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM
      }),
      threshold: 3,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Create alarm for downstream service failures
    new cloudwatch.Alarm(this, 'DownstreamServiceFailureAlarm', {
      alarmName: `CircuitBreaker-DownstreamFailures-${this.stackName}`,
      alarmDescription: 'Monitors downstream service failure rate',
      metric: this.downstreamServiceFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Create alarm for high execution duration
    new cloudwatch.Alarm(this, 'StateMachineLatencyAlarm', {
      alarmName: `CircuitBreaker-HighLatency-${this.stackName}`,
      alarmDescription: 'Monitors Step Functions execution latency',
      metric: this.stateMachine.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE
      }),
      threshold: 30000, // 30 seconds
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
  }

  /**
   * Adds consistent tags to all resources for organization and cost tracking
   */
  private addResourceTags(environment: string): void {
    const commonTags = {
      'Project': 'CircuitBreakerPattern',
      'Environment': environment,
      'Purpose': 'ResiliencePattern',
      'ManagedBy': 'CDK',
      'Recipe': 'circuit-breaker-patterns-step-functions'
    };

    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }

  /**
   * Creates CloudFormation outputs for easy access to resource information
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: this.stateMachine.stateMachineArn,
      description: 'ARN of the Circuit Breaker State Machine',
      exportName: `${this.stackName}-StateMachineArn`
    });

    new cdk.CfnOutput(this, 'CircuitBreakerTableName', {
      value: this.circuitBreakerTable.tableName,
      description: 'Name of the Circuit Breaker State DynamoDB Table',
      exportName: `${this.stackName}-CircuitBreakerTable`
    });

    new cdk.CfnOutput(this, 'DownstreamServiceFunctionName', {
      value: this.downstreamServiceFunction.functionName,
      description: 'Name of the Downstream Service Lambda Function',
      exportName: `${this.stackName}-DownstreamFunction`
    });

    new cdk.CfnOutput(this, 'FallbackServiceFunctionName', {
      value: this.fallbackServiceFunction.functionName,
      description: 'Name of the Fallback Service Lambda Function',
      exportName: `${this.stackName}-FallbackFunction`
    });

    new cdk.CfnOutput(this, 'HealthCheckFunctionName', {
      value: this.healthCheckFunction.functionName,
      description: 'Name of the Health Check Lambda Function',
      exportName: `${this.stackName}-HealthCheckFunction`
    });

    // Output for testing the circuit breaker
    new cdk.CfnOutput(this, 'TestExecutionCommand', {
      value: `aws stepfunctions start-execution --state-machine-arn ${this.stateMachine.stateMachineArn} --input '{"service_name":"payment-service","request_payload":{"amount":100.00,"currency":"USD","customer_id":"12345"}}'`,
      description: 'AWS CLI command to test the circuit breaker',
      exportName: `${this.stackName}-TestCommand`
    });
  }
}

/**
 * CDK App definition
 * Creates and deploys the Circuit Breaker stack with configurable parameters
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const failureThreshold = parseInt(app.node.tryGetContext('failureThreshold') || '3');
const timeoutMinutes = parseInt(app.node.tryGetContext('timeoutMinutes') || '5');

// Create the stack
new CircuitBreakerStack(app, 'CircuitBreakerPatternsStack', {
  description: 'Circuit Breaker Pattern implementation using AWS Step Functions, Lambda, and DynamoDB',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  failureThreshold,
  timeoutMinutes,
  environment,
  tags: {
    Project: 'CircuitBreakerPattern',
    Environment: environment,
    ManagedBy: 'CDK'
  }
});

// Synthesize the CloudFormation template
app.synth();