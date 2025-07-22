#!/usr/bin/env python3
"""
Circuit Breaker Patterns with Step Functions CDK Application

This CDK application implements a comprehensive circuit breaker pattern using AWS Step Functions,
Lambda, DynamoDB, and CloudWatch. The solution provides fault tolerance and graceful degradation
for distributed systems by automatically detecting service failures and preventing cascading failures.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_lambda as _lambda,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class CircuitBreakerStack(Stack):
    """
    CDK Stack for Circuit Breaker Patterns with Step Functions.
    
    This stack creates:
    - DynamoDB table for circuit breaker state management
    - Lambda functions for downstream service, fallback service, and health checks
    - Step Functions state machine implementing circuit breaker logic
    - CloudWatch alarms for monitoring and alerting
    - IAM roles and policies with least privilege access
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        failure_threshold: int = 3,
        timeout_seconds: int = 60,
        **kwargs
    ) -> None:
        """
        Initialize the Circuit Breaker Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            failure_threshold: Number of failures before circuit breaker opens
            timeout_seconds: Timeout for Step Functions state machine
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.failure_threshold = failure_threshold
        self.timeout_seconds = timeout_seconds
        
        # Create DynamoDB table for circuit breaker state
        self.circuit_breaker_table = self._create_circuit_breaker_table()
        
        # Create Lambda functions
        self.downstream_service_function = self._create_downstream_service_function()
        self.fallback_service_function = self._create_fallback_service_function()
        self.health_check_function = self._create_health_check_function()
        
        # Create Step Functions state machine
        self.state_machine = self._create_circuit_breaker_state_machine()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create outputs
        self._create_outputs()

    def _create_circuit_breaker_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing circuit breaker state.
        
        The table uses the service name as the partition key and stores:
        - Current state (CLOSED, OPEN, HALF_OPEN)
        - Failure count
        - Last failure and success timestamps
        
        Returns:
            DynamoDB Table construct
        """
        table = dynamodb.Table(
            self,
            "CircuitBreakerStateTable",
            table_name=f"circuit-breaker-state-{self.stack_name.lower()}",
            partition_key=dynamodb.Attribute(
                name="ServiceName", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add tags for resource management
        cdk.Tags.of(table).add("Purpose", "CircuitBreaker")
        cdk.Tags.of(table).add("Component", "StateManagement")
        
        return table

    def _create_downstream_service_function(self) -> _lambda.Function:
        """
        Create Lambda function that simulates a downstream service.
        
        This function simulates an external service that may experience failures.
        The failure rate and latency can be configured via environment variables
        to test circuit breaker behavior under various conditions.
        
        Returns:
            Lambda Function construct
        """
        function = _lambda.Function(
            self,
            "DownstreamServiceFunction",
            function_name=f"downstream-service-{self.stack_name.lower()}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import random
import time
import os

def lambda_handler(event, context):
    \"\"\"
    Simulate downstream service with configurable failure rate and latency.
    
    Environment Variables:
        FAILURE_RATE: Probability of failure (0.0 to 1.0)
        LATENCY_MS: Simulated latency in milliseconds
    \"\"\"
    # Get configuration from environment variables
    failure_rate = float(os.environ.get('FAILURE_RATE', '0.3'))
    latency_ms = int(os.environ.get('LATENCY_MS', '100'))
    
    # Simulate processing latency
    time.sleep(latency_ms / 1000)
    
    # Simulate random failures based on configured rate
    if random.random() < failure_rate:
        raise Exception(f"Service temporarily unavailable (failure rate: {failure_rate})")
    
    # Return successful response
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Service response successful',
            'timestamp': context.aws_request_id,
            'service': 'downstream-service',
            'latency_ms': latency_ms
        })
    }
            """),
            timeout=Duration.seconds(30),
            environment={
                "FAILURE_RATE": "0.5",  # 50% failure rate for testing
                "LATENCY_MS": "200"     # 200ms simulated latency
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Add tags for resource management
        cdk.Tags.of(function).add("Purpose", "CircuitBreaker")
        cdk.Tags.of(function).add("Component", "DownstreamService")
        
        return function

    def _create_fallback_service_function(self) -> _lambda.Function:
        """
        Create Lambda function that provides fallback responses.
        
        This function provides a degraded but functional response when the
        circuit breaker is open, ensuring users receive meaningful feedback
        rather than errors during service disruptions.
        
        Returns:
            Lambda Function construct
        """
        function = _lambda.Function(
            self,
            "FallbackServiceFunction",
            function_name=f"fallback-service-{self.stack_name.lower()}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
from datetime import datetime, timezone

def lambda_handler(event, context):
    \"\"\"
    Provide fallback response when primary service is unavailable.
    
    This function returns a degraded but functional response that includes:
    - Fallback data or cached responses
    - Clear indication that fallback is being used
    - Original request context for downstream processing
    \"\"\"
    # Extract original request from event
    original_request = event.get('original_request', {})
    circuit_state = event.get('circuit_breaker_state', 'UNKNOWN')
    
    # Generate fallback response
    fallback_data = {
        'message': 'Fallback service response - primary service unavailable',
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'source': 'fallback-service',
        'circuit_breaker_state': circuit_state,
        'original_request': original_request,
        'fallback_reason': 'Circuit breaker is open due to repeated failures',
        'service_status': 'degraded',
        # In production, this could include cached data or alternative responses
        'cached_data': {
            'default_response': 'Service temporarily unavailable, please try again later',
            'estimated_recovery_time': '5-10 minutes'
        }
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(fallback_data)
    }
            """),
            timeout=Duration.seconds(30),
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Add tags for resource management
        cdk.Tags.of(function).add("Purpose", "CircuitBreaker")
        cdk.Tags.of(function).add("Component", "FallbackService")
        
        return function

    def _create_health_check_function(self) -> _lambda.Function:
        """
        Create Lambda function for health checking and circuit breaker recovery.
        
        This function periodically tests downstream service availability and
        updates circuit breaker state to enable automatic recovery when
        services become healthy again.
        
        Returns:
            Lambda Function construct
        """
        function = _lambda.Function(
            self,
            "HealthCheckFunction",
            function_name=f"health-check-{self.stack_name.lower()}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import json
import boto3
import random
from datetime import datetime, timezone
from typing import Dict, Any

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context) -> Dict[str, Any]:
    \"\"\"
    Perform health check and update circuit breaker state.
    
    This function:
    1. Retrieves current circuit breaker state from DynamoDB
    2. Performs health check on the downstream service
    3. Updates circuit breaker state based on health check results
    4. Returns current service and circuit breaker status
    \"\"\"
    table_name = event['table_name']
    service_name = event['service_name']
    
    try:
        table = dynamodb.Table(table_name)
        
        # Get current circuit breaker state
        response = table.get_item(Key={'ServiceName': service_name})
        
        if 'Item' not in response:
            # Initialize circuit breaker state if not exists
            initial_state = {
                'ServiceName': service_name,
                'State': 'CLOSED',
                'FailureCount': 0,
                'LastFailureTime': None,
                'LastSuccessTime': datetime.now(timezone.utc).isoformat()
            }
            table.put_item(Item=initial_state)
            current_state = 'CLOSED'
            failure_count = 0
        else:
            item = response['Item']
            current_state = item['State']
            failure_count = item.get('FailureCount', 0)
        
        # Simulate health check (in production, call actual service endpoint)
        # Gradually improve health check success rate over time
        base_success_rate = 0.7
        health_check_success = random.random() < base_success_rate
        
        if health_check_success:
            # Service is healthy - reset circuit breaker to CLOSED
            updated_state = {
                'ServiceName': service_name,
                'State': 'CLOSED',
                'FailureCount': 0,
                'LastFailureTime': None,
                'LastSuccessTime': datetime.now(timezone.utc).isoformat(),
                'HealthCheckTime': datetime.now(timezone.utc).isoformat()
            }
            table.put_item(Item=updated_state)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'service_name': service_name,
                    'health_status': 'healthy',
                    'circuit_state': 'CLOSED',
                    'message': 'Service recovered - circuit breaker reset to CLOSED'
                })
            }
        else:
            # Service still unhealthy
            return {
                'statusCode': 503,
                'body': json.dumps({
                    'service_name': service_name,
                    'health_status': 'unhealthy',
                    'circuit_state': current_state,
                    'failure_count': failure_count,
                    'message': 'Service still unhealthy - circuit breaker remains in current state'
                })
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Health check failed: {str(e)}',
                'service_name': service_name
            })
        }
            """),
            timeout=Duration.seconds(30),
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Grant DynamoDB permissions to health check function
        self.circuit_breaker_table.grant_read_write_data(function)
        
        # Add tags for resource management
        cdk.Tags.of(function).add("Purpose", "CircuitBreaker")
        cdk.Tags.of(function).add("Component", "HealthCheck")
        
        return function

    def _create_circuit_breaker_state_machine(self) -> sfn.StateMachine:
        """
        Create Step Functions state machine implementing circuit breaker logic.
        
        The state machine orchestrates the complete circuit breaker pattern:
        1. Check current circuit breaker state
        2. Route requests based on state (CLOSED, OPEN, HALF_OPEN)
        3. Handle service invocations with proper error handling
        4. Update circuit breaker state based on success/failure
        5. Provide fallback responses when needed
        
        Returns:
            Step Functions StateMachine construct
        """
        # Define state machine tasks
        
        # Check circuit breaker state in DynamoDB
        check_circuit_state = sfn_tasks.DynamoGetItem(
            self,
            "CheckCircuitBreakerState",
            table=self.circuit_breaker_table,
            key={"ServiceName": sfn_tasks.DynamoAttributeValue.from_string(
                sfn.JsonPath.string_at("$.service_name")
            )},
            result_path="$.circuit_state"
        ).add_catch(
            sfn.Pass(self, "InitializeCircuitBreaker").next(
                sfn_tasks.DynamoPutItem(
                    self,
                    "CreateInitialState",
                    table=self.circuit_breaker_table,
                    item={
                        "ServiceName": sfn_tasks.DynamoAttributeValue.from_string(
                            sfn.JsonPath.string_at("$.service_name")
                        ),
                        "State": sfn_tasks.DynamoAttributeValue.from_string("CLOSED"),
                        "FailureCount": sfn_tasks.DynamoAttributeValue.from_number(0),
                        "LastSuccessTime": sfn_tasks.DynamoAttributeValue.from_string(
                            sfn.JsonPath.string_at("$$.State.EnteredTime")
                        )
                    }
                ).next(self._create_call_downstream_service_task())
            ),
            errors=["States.ALL"]
        )
        
        # Evaluate circuit breaker state
        evaluate_circuit_state = sfn.Choice(self, "EvaluateCircuitState")
        
        # Health check for OPEN state
        health_check_task = sfn_tasks.LambdaInvoke(
            self,
            "PerformHealthCheck",
            lambda_function=self.health_check_function,
            payload=sfn.TaskInput.from_object({
                "table_name": self.circuit_breaker_table.table_name,
                "service_name.$": "$.service_name"
            }),
            result_path="$.health_check_result"
        ).add_retry(
            sfn.RetryProps(
                errors=["States.ALL"],
                interval=Duration.seconds(2),
                max_attempts=3,
                backoff_rate=2.0
            )
        )
        
        # Evaluate health check results
        evaluate_health_check = sfn.Choice(self, "EvaluateHealthCheck")
        
        # Call downstream service
        call_downstream_service = self._create_call_downstream_service_task()
        
        # Record success
        record_success = sfn_tasks.DynamoUpdateItem(
            self,
            "RecordSuccess",
            table=self.circuit_breaker_table,
            key={"ServiceName": sfn_tasks.DynamoAttributeValue.from_string(
                sfn.JsonPath.string_at("$.service_name")
            )},
            update_expression="SET #state = :closed_state, FailureCount = :zero, LastSuccessTime = :timestamp",
            expression_attribute_names={"#state": "State"},
            expression_attribute_values={
                ":closed_state": sfn_tasks.DynamoAttributeValue.from_string("CLOSED"),
                ":zero": sfn_tasks.DynamoAttributeValue.from_number(0),
                ":timestamp": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$$.State.EnteredTime")
                )
            }
        )
        
        # Record failure
        record_failure = sfn_tasks.DynamoUpdateItem(
            self,
            "RecordFailure",
            table=self.circuit_breaker_table,
            key={"ServiceName": sfn_tasks.DynamoAttributeValue.from_string(
                sfn.JsonPath.string_at("$.service_name")
            )},
            update_expression="SET FailureCount = FailureCount + :inc, LastFailureTime = :timestamp",
            expression_attribute_values={
                ":inc": sfn_tasks.DynamoAttributeValue.from_number(1),
                ":timestamp": sfn_tasks.DynamoAttributeValue.from_string(
                    sfn.JsonPath.string_at("$$.State.EnteredTime")
                )
            },
            result_path="$.update_result"
        )
        
        # Check failure threshold
        check_failure_threshold = sfn_tasks.DynamoGetItem(
            self,
            "CheckFailureThreshold",
            table=self.circuit_breaker_table,
            key={"ServiceName": sfn_tasks.DynamoAttributeValue.from_string(
                sfn.JsonPath.string_at("$.service_name")
            )},
            result_path="$.current_state"
        )
        
        # Evaluate failure count
        evaluate_failure_count = sfn.Choice(self, "EvaluateFailureCount")
        
        # Trip circuit breaker
        trip_circuit_breaker = sfn_tasks.DynamoUpdateItem(
            self,
            "TripCircuitBreaker",
            table=self.circuit_breaker_table,
            key={"ServiceName": sfn_tasks.DynamoAttributeValue.from_string(
                sfn.JsonPath.string_at("$.service_name")
            )},
            update_expression="SET #state = :open_state",
            expression_attribute_names={"#state": "State"},
            expression_attribute_values={
                ":open_state": sfn_tasks.DynamoAttributeValue.from_string("OPEN")
            }
        )
        
        # Call fallback service
        call_fallback_service = sfn_tasks.LambdaInvoke(
            self,
            "CallFallbackService",
            lambda_function=self.fallback_service_function,
            payload=sfn.TaskInput.from_object({
                "original_request.$": "$.request_payload",
                "circuit_breaker_state.$": "$.circuit_state.Item.State.S"
            }),
            result_path="$.fallback_result"
        )
        
        # Return success
        return_success = sfn.Pass(
            self,
            "ReturnSuccess",
            parameters={
                "statusCode": 200,
                "body.$": "$.service_result.Payload.body",
                "circuit_breaker_state": "CLOSED"
            }
        )
        
        # Return fallback
        return_fallback = sfn.Pass(
            self,
            "ReturnFallback",
            parameters={
                "statusCode": 200,
                "body.$": "$.fallback_result.Payload.body",
                "circuit_breaker_state": "OPEN",
                "fallback_used": True
            }
        )
        
        # Define state machine flow
        definition = check_circuit_state.next(
            evaluate_circuit_state.when(
                sfn.Condition.string_equals("$.circuit_state.Item.State.S", "OPEN"),
                health_check_task.next(
                    evaluate_health_check.when(
                        sfn.Condition.number_equals("$.health_check_result.Payload.statusCode", 200),
                        call_downstream_service
                    ).otherwise(call_fallback_service.next(return_fallback))
                )
            ).when(
                sfn.Condition.string_equals("$.circuit_state.Item.State.S", "HALF_OPEN"),
                call_downstream_service
            ).when(
                sfn.Condition.string_equals("$.circuit_state.Item.State.S", "CLOSED"),
                call_downstream_service
            ).otherwise(call_downstream_service)
        )
        
        # Configure downstream service task flow
        call_downstream_service.next(record_success.next(return_success)).add_catch(
            record_failure.next(
                check_failure_threshold.next(
                    evaluate_failure_count.when(
                        sfn.Condition.number_greater_than_equals(
                            "$.current_state.Item.FailureCount.N", 
                            self.failure_threshold
                        ),
                        trip_circuit_breaker.next(call_fallback_service.next(return_fallback))
                    ).otherwise(call_fallback_service.next(return_fallback))
                )
            ),
            errors=["States.ALL"],
            result_path="$.error"
        )
        
        # Create state machine
        state_machine = sfn.StateMachine(
            self,
            "CircuitBreakerStateMachine",
            state_machine_name=f"circuit-breaker-{self.stack_name.lower()}",
            definition=definition,
            timeout=Duration.seconds(self.timeout_seconds),
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self,
                    "StateMachineLogGroup",
                    log_group_name=f"/aws/stepfunctions/circuit-breaker-{self.stack_name.lower()}",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY
                ),
                level=sfn.LogLevel.ALL
            )
        )
        
        # Grant permissions to state machine
        self.circuit_breaker_table.grant_read_write_data(state_machine.role)
        self.downstream_service_function.grant_invoke(state_machine.role)
        self.fallback_service_function.grant_invoke(state_machine.role)
        self.health_check_function.grant_invoke(state_machine.role)
        
        # Add tags for resource management
        cdk.Tags.of(state_machine).add("Purpose", "CircuitBreaker")
        cdk.Tags.of(state_machine).add("Component", "StateMachine")
        
        return state_machine

    def _create_call_downstream_service_task(self) -> sfn_tasks.LambdaInvoke:
        """
        Create the Lambda invoke task for calling downstream service.
        
        Returns:
            LambdaInvoke task with proper error handling and retries
        """
        return sfn_tasks.LambdaInvoke(
            self,
            "CallDownstreamService",
            lambda_function=self.downstream_service_function,
            payload=sfn.TaskInput.from_json_path_at("$.request_payload"),
            result_path="$.service_result"
        ).add_retry(
            sfn.RetryProps(
                errors=["States.TaskFailed"],
                interval=Duration.seconds(1),
                max_attempts=2,
                backoff_rate=2.0
            )
        )

    def _create_cloudwatch_alarms(self) -> None:
        """
        Create CloudWatch alarms for monitoring circuit breaker behavior.
        
        Creates alarms for:
        - Circuit breaker state changes to OPEN
        - High failure rates in downstream services
        - Step Functions execution failures
        """
        # Alarm for circuit breaker opening
        circuit_breaker_open_alarm = cloudwatch.Alarm(
            self,
            "CircuitBreakerOpenAlarm",
            alarm_name=f"circuit-breaker-open-{self.stack_name.lower()}",
            alarm_description="Circuit breaker has been tripped to OPEN state",
            metric=cloudwatch.Metric(
                namespace="AWS/States",
                metric_name="ExecutionsFailed",
                dimensions_map={
                    "StateMachineArn": self.state_machine.state_machine_arn
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )
        
        # Alarm for high service failure rate
        service_failure_alarm = cloudwatch.Alarm(
            self,
            "ServiceFailureRateAlarm",
            alarm_name=f"service-failure-rate-{self.stack_name.lower()}",
            alarm_description="High failure rate detected in downstream service",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={
                    "FunctionName": self.downstream_service_function.function_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )
        
        # Add tags for resource management
        cdk.Tags.of(circuit_breaker_open_alarm).add("Purpose", "CircuitBreaker")
        cdk.Tags.of(service_failure_alarm).add("Purpose", "CircuitBreaker")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="ARN of the Circuit Breaker State Machine",
            export_name=f"{self.stack_name}-StateMachineArn"
        )
        
        CfnOutput(
            self,
            "CircuitBreakerTableName",
            value=self.circuit_breaker_table.table_name,
            description="Name of the Circuit Breaker State DynamoDB Table",
            export_name=f"{self.stack_name}-CircuitBreakerTableName"
        )
        
        CfnOutput(
            self,
            "DownstreamServiceFunctionName",
            value=self.downstream_service_function.function_name,
            description="Name of the Downstream Service Lambda Function",
            export_name=f"{self.stack_name}-DownstreamServiceFunctionName"
        )
        
        CfnOutput(
            self,
            "FallbackServiceFunctionName",
            value=self.fallback_service_function.function_name,
            description="Name of the Fallback Service Lambda Function",
            export_name=f"{self.stack_name}-FallbackServiceFunctionName"
        )
        
        CfnOutput(
            self,
            "HealthCheckFunctionName",
            value=self.health_check_function.function_name,
            description="Name of the Health Check Lambda Function",
            export_name=f"{self.stack_name}-HealthCheckFunctionName"
        )


class CircuitBreakerApp(cdk.App):
    """
    CDK Application for Circuit Breaker Patterns.
    
    This application creates a complete circuit breaker implementation
    that can be deployed across different environments (dev, staging, prod).
    """

    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
        
        # Create the circuit breaker stack
        CircuitBreakerStack(
            self,
            "CircuitBreakerStack",
            env=env,
            description="Circuit Breaker Patterns with Step Functions - Production-ready fault tolerance solution",
            failure_threshold=3,  # Trip circuit breaker after 3 failures
            timeout_seconds=300   # 5 minute timeout for state machine
        )


# Application entry point
app = CircuitBreakerApp()
app.synth()