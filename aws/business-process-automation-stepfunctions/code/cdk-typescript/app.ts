#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as stepfunctionsTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * CDK Stack for Business Process Automation with Step Functions
 * 
 * This stack implements a comprehensive business process automation solution using:
 * - AWS Step Functions for workflow orchestration
 * - Lambda functions for business logic processing
 * - SNS for notifications and human approval workflows
 * - SQS for durable message queuing
 * - API Gateway for human task callbacks
 * 
 * The solution demonstrates enterprise-grade patterns including:
 * - Human-in-the-loop workflows with waitForTaskToken
 * - Error handling and retry logic
 * - Service integrations without Lambda proxy
 * - Comprehensive logging and monitoring
 */
export class BusinessProcessAutomationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const resourcePrefix = `business-process-${uniqueSuffix}`;

    // ============================================================================
    // Lambda Function for Business Logic Processing
    // ============================================================================
    
    // IAM role for Lambda function with minimal required permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${resourcePrefix}-lambda-execution-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Lambda function for processing business logic
    const businessProcessorFunction = new lambda.Function(this, 'BusinessProcessorFunction', {
      functionName: `${resourcePrefix}-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(30),
      memorySize: 256,
      description: 'Processes business logic for automated workflows',
      code: lambda.Code.fromInline(`
import json
import time
from datetime import datetime, timezone

def lambda_handler(event, context):
    """
    Business logic processor for automated workflows.
    
    Handles validation, processing, and result generation for business processes.
    Includes configurable processing time for testing different scenarios.
    """
    try:
        # Extract business process data from event
        process_data = event.get('processData', {})
        process_type = process_data.get('type', 'unknown')
        process_id = process_data.get('processId', 'unknown')
        
        print(f"Processing business logic for {process_type} with ID {process_id}")
        
        # Simulate business logic processing with configurable delay
        processing_time = process_data.get('processingTime', 2)
        time.sleep(min(processing_time, 25))  # Cap at 25 seconds for Lambda timeout safety
        
        # Validate business rules based on process type
        validation_result = validate_business_rules(process_data)
        if not validation_result['valid']:
            raise ValueError(f"Business rule validation failed: {validation_result['reason']}")
        
        # Generate processing result with enriched data
        result = {
            'processId': process_id,
            'processType': process_type,
            'status': 'processed',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'result': f"Successfully processed {process_type} business process",
            'validationResult': validation_result,
            'metadata': {
                'processingDuration': processing_time,
                'functionVersion': context.function_version,
                'requestId': context.aws_request_id
            }
        }
        
        print(f"Business process completed successfully: {json.dumps(result, default=str)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, default=str),
            'processResult': result
        }
        
    except Exception as e:
        error_result = {
            'processId': process_data.get('processId', 'unknown'),
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        print(f"Business process failed: {json.dumps(error_result, default=str)}")
        
        # Re-raise the exception to trigger Step Functions error handling
        raise e

def validate_business_rules(process_data):
    """
    Validate business rules based on process type and data.
    
    Returns:
        dict: Validation result with 'valid' boolean and optional 'reason'
    """
    process_type = process_data.get('type', '')
    
    # Example validation rules for different process types
    if process_type == 'expense-approval':
        amount = process_data.get('amount', 0)
        if amount <= 0:
            return {'valid': False, 'reason': 'Amount must be greater than zero'}
        if amount > 10000:
            return {'valid': False, 'reason': 'Amount exceeds approval limit'}
            
    elif process_type == 'document-review':
        if not process_data.get('documentId'):
            return {'valid': False, 'reason': 'Document ID is required'}
            
    elif process_type == 'contract-approval':
        if not process_data.get('contractValue'):
            return {'valid': False, 'reason': 'Contract value is required'}
        if not process_data.get('approver'):
            return {'valid': False, 'reason': 'Approver is required'}
    
    return {'valid': True, 'reason': 'All business rules passed'}
      `),
      environment: {
        'LOG_LEVEL': 'INFO',
      },
    });

    // CloudWatch Log Group for Lambda function with retention policy
    new logs.LogGroup(this, 'BusinessProcessorLogGroup', {
      logGroupName: `/aws/lambda/${businessProcessorFunction.functionName}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ============================================================================
    // SQS Queue for Task Management and Audit Trail
    // ============================================================================
    
    // Dead letter queue for failed message processing
    const deadLetterQueue = new sqs.Queue(this, 'ProcessDeadLetterQueue', {
      queueName: `${resourcePrefix}-dlq`,
      retentionPeriod: Duration.days(14),
    });

    // Main queue for completed tasks and audit logs
    const completedTasksQueue = new sqs.Queue(this, 'CompletedTasksQueue', {
      queueName: `${resourcePrefix}-queue`,
      visibilityTimeout: Duration.minutes(5),
      retentionPeriod: Duration.days(14),
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // ============================================================================
    // SNS Topic for Notifications and Human Approval
    // ============================================================================
    
    // SNS topic for process notifications and human approval requests
    const processNotificationsTopic = new sns.Topic(this, 'ProcessNotificationsTopic', {
      topicName: `${resourcePrefix}-notifications`,
      displayName: 'Business Process Notifications',
    });

    // ============================================================================
    // API Gateway for Human Task Callbacks
    // ============================================================================
    
    // Lambda function to handle approval callbacks
    const approvalCallbackFunction = new lambda.Function(this, 'ApprovalCallbackFunction', {
      functionName: `${resourcePrefix}-approval-callback`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(30),
      description: 'Handles human approval callbacks for Step Functions',
      code: lambda.Code.fromInline(`
import json
import boto3

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    Handle human approval callbacks from API Gateway.
    
    Processes approval decisions and resumes Step Functions execution
    using the task token provided in the original approval request.
    """
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        task_token = body.get('taskToken')
        approved = body.get('approved', False)
        approver = body.get('approver', 'unknown')
        comments = body.get('comments', '')
        
        if not task_token:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'taskToken is required'})
            }
        
        # Prepare response data for Step Functions
        approval_result = {
            'approved': approved,
            'approver': approver,
            'comments': comments,
            'timestamp': context.aws_request_id
        }
        
        # Send task success or failure based on approval
        if approved:
            stepfunctions.send_task_success(
                taskToken=task_token,
                output=json.dumps(approval_result)
            )
            message = 'Approval submitted successfully'
        else:
            stepfunctions.send_task_failure(
                taskToken=task_token,
                error='ApprovalRejected',
                cause=f'Process rejected by {approver}: {comments}'
            )
            message = 'Rejection submitted successfully'
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': message,
                'approval': approval_result
            })
        }
        
    except Exception as e:
        print(f"Error processing approval callback: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }
      `),
    });

    // Grant the callback function permission to send task results to Step Functions
    approvalCallbackFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'states:SendTaskSuccess',
        'states:SendTaskFailure',
      ],
      resources: ['*'], // Will be restricted to specific state machine ARN in production
    }));

    // API Gateway for human approval callbacks
    const approvalApi = new apigateway.RestApi(this, 'ApprovalApi', {
      restApiName: `${resourcePrefix}-approval-api`,
      description: 'API for business process approval callbacks',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
    });

    // Approval resource and method
    const approvalResource = approvalApi.root.addResource('approval');
    approvalResource.addMethod('POST', new apigateway.LambdaIntegration(approvalCallbackFunction), {
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // ============================================================================
    // Step Functions State Machine
    // ============================================================================
    
    // IAM role for Step Functions with specific service permissions
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsExecutionRole', {
      roleName: `${resourcePrefix}-stepfunctions-role`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      inlinePolicies: {
        StepFunctionsExecutionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [businessProcessorFunction.functionArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [processNotificationsTopic.topicArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sqs:SendMessage'],
              resources: [completedTasksQueue.queueArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Define the state machine workflow using CDK constructs
    
    // Step 1: Validate Input
    const validateInput = new stepfunctions.Pass(this, 'ValidateInput', {
      comment: 'Validate and enrich input data for business process',
      parameters: {
        'processData.$': '$.processData',
        'validationResult': 'Input validated successfully',
        'workflowStartTime.$': '$$.State.EnteredTime',
      },
    });

    // Step 2: Process Business Logic
    const processBusinessLogic = new stepfunctionsTasks.LambdaInvoke(this, 'ProcessBusinessLogic', {
      lambdaFunction: businessProcessorFunction,
      comment: 'Execute core business logic processing',
      retryOnServiceExceptions: true,
      payload: stepfunctions.TaskInput.fromObject({
        'processData.$': '$.processData',
        'validationResult.$': '$.validationResult',
      }),
      resultPath: '$.processResult',
    });

    // Configure retry policy for business logic processing
    processBusinessLogic.addRetry({
      errors: ['States.TaskFailed', 'Lambda.ServiceException', 'Lambda.AWSLambdaException'],
      intervalSeconds: 5,
      maxAttempts: 3,
      backoffRate: 2.0,
    });

    // Step 3: Human Approval Required
    const humanApprovalRequired = new stepfunctionsTasks.SnsPublish(this, 'HumanApprovalRequired', {
      topic: processNotificationsTopic,
      message: stepfunctions.TaskInput.fromObject({
        'processId.$': '$.processResult.Payload.processResult.processId',
        'processType.$': '$.processResult.Payload.processResult.processType',
        'approvalRequired': 'Please review and approve this business process',
        'apiEndpoint': `https://${approvalApi.restApiId}.execute-api.${this.region}.amazonaws.com/prod/approval`,
        'taskToken.$': '$$.Task.Token',
        'workflowId.$': '$$.Execution.Name',
      }),
      subject: 'Business Process Approval Required',
      comment: 'Send approval request and wait for human decision',
      integrationPattern: stepfunctions.IntegrationPattern.WAIT_FOR_TASK_TOKEN,
      heartbeatTimeout: Duration.hours(1),
      timeout: Duration.hours(24),
      resultPath: '$.approvalResult',
    });

    // Step 4: Send Completion Notification
    const sendCompletionNotification = new stepfunctionsTasks.SnsPublish(this, 'SendCompletionNotification', {
      topic: processNotificationsTopic,
      message: stepfunctions.TaskInput.fromObject({
        'processId.$': '$.processResult.Payload.processResult.processId',
        'processType.$': '$.processResult.Payload.processResult.processType',
        'status': 'completed',
        'approver.$': '$.approvalResult.approver',
        'completionTime.$': '$$.State.EnteredTime',
        'message': 'Business process completed successfully',
      }),
      subject: 'Business Process Completed',
      comment: 'Notify stakeholders of successful completion',
      resultPath: '$.notificationResult',
    });

    // Step 5: Log to Audit Queue
    const logToQueue = new stepfunctionsTasks.SqsSendMessage(this, 'LogToQueue', {
      queue: completedTasksQueue,
      messageBody: stepfunctions.TaskInput.fromObject({
        'processId.$': '$.processResult.Payload.processResult.processId',
        'processType.$': '$.processResult.Payload.processResult.processType',
        'completionTime.$': '$$.State.EnteredTime',
        'approver.$': '$.approvalResult.approver',
        'workflowExecutionArn.$': '$$.Execution.Name',
        'status': 'completed',
        'auditTrail': {
          'workflowStartTime.$': '$.workflowStartTime',
          'processingResult.$': '$.processResult.Payload.processResult',
          'approvalResult.$': '$.approvalResult',
        },
      }),
      comment: 'Create audit trail entry for completed process',
    });

    // Error handling: Processing Failed
    const processingFailed = new stepfunctionsTasks.SnsPublish(this, 'ProcessingFailed', {
      topic: processNotificationsTopic,
      message: stepfunctions.TaskInput.fromObject({
        'error': 'Business process failed during execution',
        'errorDetails.$': '$.Error',
        'errorCause.$': '$.Cause',
        'processData.$': '$.processData',
        'failureTime.$': '$$.State.EnteredTime',
      }),
      subject: 'Business Process Failed',
      comment: 'Notify stakeholders of process failure',
    });

    // Error handling: Approval Rejected
    const approvalRejected = new stepfunctionsTasks.SnsPublish(this, 'ApprovalRejected', {
      topic: processNotificationsTopic,
      message: stepfunctions.TaskInput.fromObject({
        'processId.$': '$.processResult.Payload.processResult.processId',
        'status': 'rejected',
        'rejectionReason.$': '$.approvalResult.comments',
        'rejectedBy.$': '$.approvalResult.approver',
        'rejectionTime.$': '$$.State.EnteredTime',
      }),
      subject: 'Business Process Rejected',
      comment: 'Notify stakeholders of process rejection',
    });

    // Define the workflow chain with error handling
    const definition = validateInput
      .next(processBusinessLogic
        .addCatch(processingFailed, {
          errors: ['States.ALL'],
          resultPath: '$.error',
        })
      )
      .next(humanApprovalRequired
        .addCatch(approvalRejected, {
          errors: ['ApprovalRejected'],
          resultPath: '$.error',
        })
      )
      .next(sendCompletionNotification)
      .next(logToQueue);

    // Create the Step Functions state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'BusinessProcessStateMachine', {
      stateMachineName: `${resourcePrefix}-workflow`,
      definition,
      role: stepFunctionsRole,
      timeout: Duration.hours(25), // Allow for 24-hour approval window plus processing
      comment: 'Business Process Automation Workflow with Human Approval',
      logs: {
        destination: new logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/${resourcePrefix}-workflow`,
          retention: logs.RetentionDays.TWO_WEEKS,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true,
      },
      tracingEnabled: true,
    });

    // ============================================================================
    // Outputs
    // ============================================================================
    
    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'ARN of the business process automation state machine',
      exportName: `${resourcePrefix}-state-machine-arn`,
    });

    new cdk.CfnOutput(this, 'StateMachineName', {
      value: stateMachine.stateMachineName,
      description: 'Name of the business process automation state machine',
      exportName: `${resourcePrefix}-state-machine-name`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: businessProcessorFunction.functionName,
      description: 'Name of the business logic processing Lambda function',
      exportName: `${resourcePrefix}-lambda-function-name`,
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: processNotificationsTopic.topicArn,
      description: 'ARN of the SNS topic for process notifications',
      exportName: `${resourcePrefix}-sns-topic-arn`,
    });

    new cdk.CfnOutput(this, 'SqsQueueUrl', {
      value: completedTasksQueue.queueUrl,
      description: 'URL of the SQS queue for completed tasks',
      exportName: `${resourcePrefix}-sqs-queue-url`,
    });

    new cdk.CfnOutput(this, 'ApprovalApiEndpoint', {
      value: approvalApi.url,
      description: 'API Gateway endpoint for human approval callbacks',
      exportName: `${resourcePrefix}-approval-api-endpoint`,
    });

    new cdk.CfnOutput(this, 'ResourcePrefix', {
      value: resourcePrefix,
      description: 'Unique prefix used for all resources in this stack',
      exportName: `${resourcePrefix}-resource-prefix`,
    });
  }
}

// ============================================================================
// CDK App
// ============================================================================

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1',
};

// Create the stack
new BusinessProcessAutomationStack(app, 'BusinessProcessAutomationStack', {
  env,
  description: 'Business Process Automation with AWS Step Functions, Lambda, SNS, and SQS',
  tags: {
    Project: 'BusinessProcessAutomation',
    Environment: process.env.ENVIRONMENT || 'development',
    Owner: process.env.OWNER || 'CDK',
    Purpose: 'Automated business workflow orchestration',
  },
});

app.synth();