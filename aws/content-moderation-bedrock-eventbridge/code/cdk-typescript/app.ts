#\!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as bedrock from 'aws-cdk-lib/aws-bedrock';

/**
 * Stack for AI Content Moderation with Bedrock
 */
export class ContentModerationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
      Math.random().toString(36).substring(2, 8);

    // S3 Buckets
    const contentBucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `content-moderation-bucket-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    const approvedBucket = new s3.Bucket(this, 'ApprovedBucket', {
      bucketName: `approved-content-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    const rejectedBucket = new s3.Bucket(this, 'RejectedBucket', {
      bucketName: `rejected-content-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // SNS Topic
    const notificationTopic = new sns.Topic(this, 'ModerationNotifications', {
      topicName: `content-moderation-notifications-${uniqueSuffix}`,
      displayName: 'Content Moderation Notifications',
    });

    const notificationEmail = this.node.tryGetContext('notificationEmail');
    if (notificationEmail) {
      notificationTopic.addSubscription(
        new subscriptions.EmailSubscription(notificationEmail)
      );
    }

    // EventBridge
    const customEventBus = new events.EventBus(this, 'ContentModerationBus', {
      eventBusName: 'content-moderation-bus',
    });

    // Bedrock Guardrails
    const contentGuardrail = new bedrock.CfnGuardrail(this, 'ContentModerationGuardrail', {
      name: 'ContentModerationGuardrail',
      description: 'Guardrail for content moderation to prevent harmful content',
      blockedInputMessaging: 'This content violates our content policy.',
      blockedOutputsMessaging: 'I cannot provide that type of content.',
      contentPolicyConfig: {
        filtersConfig: [
          { type: 'SEXUAL', inputStrength: 'HIGH', outputStrength: 'HIGH' },
          { type: 'VIOLENCE', inputStrength: 'HIGH', outputStrength: 'HIGH' },
          { type: 'HATE', inputStrength: 'HIGH', outputStrength: 'HIGH' },
          { type: 'INSULTS', inputStrength: 'MEDIUM', outputStrength: 'MEDIUM' },
          { type: 'MISCONDUCT', inputStrength: 'HIGH', outputStrength: 'HIGH' },
        ],
      },
    });

    // IAM Roles
    const contentAnalysisRole = new iam.Role(this, 'ContentAnalysisRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ContentAnalysisPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['bedrock:InvokeModel', 'bedrock:InvokeModelWithResponseStream'],
              resources: [`arn:aws:bedrock:${this.region}::foundation-model/anthropic.*`],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:GetObjectVersion'],
              resources: [contentBucket.bucketArn + '/*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['events:PutEvents'],
              resources: [customEventBus.eventBusArn],
            }),
          ],
        }),
      },
    });

    const workflowRole = new iam.Role(this, 'WorkflowRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        WorkflowPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:GetObjectVersion'],
              resources: [contentBucket.bucketArn + '/*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject', 's3:PutObjectAcl'],
              resources: [approvedBucket.bucketArn + '/*', rejectedBucket.bucketArn + '/*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Lambda Functions
    const contentAnalysisFunction = new lambda.Function(this, 'ContentAnalysisFunction', {
      functionName: `ContentAnalysisFunction-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: contentAnalysisRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 512,
      environment: {
        CUSTOM_BUS_NAME: customEventBus.eventBusName,
        GUARDRAIL_ID: contentGuardrail.attrGuardrailId,
      },
      code: lambda.Code.fromInline(\`
import json
import boto3
import urllib.parse
from datetime import datetime
import os

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [{
                "role": "user", 
                "content": f"Analyze this content for policy violations: {content[:2000]}"
            }]
        })
        
        bedrock_response = bedrock.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=body,
            contentType='application/json'
        )
        
        response_body = json.loads(bedrock_response['body'].read())
        decision = "approved"  # Simplified for demo
        
        eventbridge.put_events(
            Entries=[{
                'Source': 'content.moderation',
                'DetailType': f"Content {decision.title()}",
                'Detail': json.dumps({
                    'bucket': bucket,
                    'key': key,
                    'decision': decision,
                    'timestamp': datetime.utcnow().isoformat()
                }),
                'EventBusName': os.environ['CUSTOM_BUS_NAME']
            }]
        )
        
        return {'statusCode': 200, 'body': json.dumps({'decision': decision})}
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
\`),
    });

    // Workflow Lambda functions
    const decisions = ['approved', 'rejected', 'review'];
    const workflowFunctions: { [key: string]: lambda.Function } = {};
    
    decisions.forEach(decision => {
      workflowFunctions[decision] = new lambda.Function(this, \`\${decision.charAt(0).toUpperCase() + decision.slice(1)}HandlerFunction\`, {
        functionName: \`\${decision.charAt(0).toUpperCase() + decision.slice(1)}HandlerFunction-\${uniqueSuffix}\`,
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.lambda_handler',
        role: workflowRole,
        timeout: cdk.Duration.seconds(30),
        memorySize: 256,
        environment: {
          TARGET_BUCKET: decision === 'approved' ? approvedBucket.bucketName : rejectedBucket.bucketName,
          SNS_TOPIC_ARN: notificationTopic.topicArn,
          DECISION_TYPE: decision,
        },
        code: lambda.Code.fromInline(\`
import json
import boto3
from datetime import datetime
import os

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        source_bucket = detail['bucket']
        source_key = detail['key']
        
        target_bucket = os.environ['TARGET_BUCKET']
        decision_type = os.environ['DECISION_TYPE']
        target_key = f"{decision_type}/{datetime.utcnow().strftime('%Y/%m/%d')}/{source_key}"
        
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        s3.copy_object(
            CopySource=copy_source,
            Bucket=target_bucket,
            Key=target_key,
            MetadataDirective='REPLACE',
            Metadata={
                'moderation-decision': detail['decision'],
                'processed-timestamp': datetime.utcnow().isoformat()
            }
        )
        
        message = f"Content {detail['decision'].upper()}: {source_key}"
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'Content {detail["decision"].title()}: {source_key}',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Content processed for {decision_type}',
                'target_location': f's3://{target_bucket}/{target_key}'
            })
        }
        
    except Exception as e:
        print(f"Error in {decision_type} handler: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
\`),
      });
    });

    // S3 Event Notification
    contentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(contentAnalysisFunction),
      { suffix: '.txt' }
    );

    // EventBridge Rules
    decisions.forEach(decision => {
      const rule = new events.Rule(this, \`\${decision}ContentRule\`, {
        eventBus: customEventBus,
        eventPattern: {
          source: ['content.moderation'],
          detailType: [\`Content \${decision.charAt(0).toUpperCase() + decision.slice(1)}\`],
        },
        targets: [new targets.LambdaFunction(workflowFunctions[decision])],
      });
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'ContentBucketName', {
      value: contentBucket.bucketName,
      description: 'S3 bucket for uploading content to be moderated',
    });

    new cdk.CfnOutput(this, 'ApprovedBucketName', {
      value: approvedBucket.bucketName,
      description: 'S3 bucket for approved content',
    });

    new cdk.CfnOutput(this, 'RejectedBucketName', {
      value: rejectedBucket.bucketName,
      description: 'S3 bucket for rejected content',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for moderation notifications',
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: customEventBus.eventBusName,
      description: 'EventBridge custom bus for content moderation events',
    });
  }
}

// App instantiation
const app = new cdk.App();
new ContentModerationStack(app, 'ContentModerationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});
EOF < /dev/null