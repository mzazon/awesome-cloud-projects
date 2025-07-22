#!/usr/bin/env node
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
 * 
 * This stack creates:
 * - S3 buckets for content storage (upload, approved, rejected)
 * - Lambda functions for content analysis and workflow processing
 * - EventBridge custom bus for event-driven processing
 * - SNS topic for notifications
 * - Bedrock guardrails for enhanced AI safety
 * - IAM roles with least privilege access
 */
export class ContentModerationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
      Math.random().toString(36).substring(2, 8);

    // ==================== S3 BUCKETS ====================
    
    // Content upload bucket - where users upload content for moderation
    const contentBucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `content-moderation-bucket-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: cdk.Duration.days(30),
          noncurrentVersionExpiration: cdk.Duration.days(7),
        },
      ],
    });

    // Approved content bucket - stores content that passes moderation
    const approvedBucket = new s3.Bucket(this, 'ApprovedBucket', {
      bucketName: `approved-content-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Rejected content bucket - stores content that fails moderation
    const rejectedBucket = new s3.Bucket(this, 'RejectedBucket', {
      bucketName: `rejected-content-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ==================== SNS TOPIC ====================
    
    // SNS topic for moderation notifications
    const notificationTopic = new sns.Topic(this, 'ModerationNotifications', {
      topicName: `content-moderation-notifications-${uniqueSuffix}`,
      displayName: 'Content Moderation Notifications',
    });

    // Add email subscription if provided via context
    const notificationEmail = this.node.tryGetContext('notificationEmail');
    if (notificationEmail) {
      notificationTopic.addSubscription(
        new subscriptions.EmailSubscription(notificationEmail)
      );
    }

    // ==================== EVENTBRIDGE ====================
    
    // Custom EventBridge bus for content moderation events
    const customEventBus = new events.EventBus(this, 'ContentModerationBus', {
      eventBusName: 'content-moderation-bus',
    });

    // ==================== BEDROCK GUARDRAILS ====================
    
    // Create Bedrock guardrails for enhanced content safety
    const contentGuardrail = new bedrock.CfnGuardrail(this, 'ContentModerationGuardrail', {
      name: 'ContentModerationGuardrail',
      description: 'Guardrail for content moderation to prevent harmful content',
      blockedInputMessaging: 'This content violates our content policy.',
      blockedOutputsMessaging: 'I cannot provide that type of content.',
      
      // Content policy configuration for filtering harmful content
      contentPolicyConfig: {
        filtersConfig: [
          { type: 'SEXUAL', inputStrength: 'HIGH', outputStrength: 'HIGH' },
          { type: 'VIOLENCE', inputStrength: 'HIGH', outputStrength: 'HIGH' },
          { type: 'HATE', inputStrength: 'HIGH', outputStrength: 'HIGH' },
          { type: 'INSULTS', inputStrength: 'MEDIUM', outputStrength: 'MEDIUM' },
          { type: 'MISCONDUCT', inputStrength: 'HIGH', outputStrength: 'HIGH' },
        ],
      },
      
      // Topic policy configuration for specific restricted topics
      topicPolicyConfig: {
        topicsConfig: [
          {
            name: 'IllegalActivities',
            definition: 'Content promoting or instructing illegal activities',
            examples: ['How to make illegal substances', 'Tax evasion strategies'],
            type: 'DENY',
          },
        ],
      },
      
      // Sensitive information policy for PII protection
      sensitiveInformationPolicyConfig: {
        piiEntitiesConfig: [
          { type: 'EMAIL', action: 'ANONYMIZE' },
          { type: 'PHONE', action: 'ANONYMIZE' },
          { type: 'CREDIT_DEBIT_CARD_NUMBER', action: 'BLOCK' },
        ],
      },
    });

    // ==================== IAM ROLES ====================
    
    // IAM role for content analysis Lambda function
    const contentAnalysisRole = new iam.Role(this, 'ContentAnalysisRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ContentAnalysisPolicy: new iam.PolicyDocument({
          statements: [
            // Bedrock model invocation permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock:InvokeModel',
                'bedrock:InvokeModelWithResponseStream',
              ],
              resources: [
                `arn:aws:bedrock:${this.region}::foundation-model/anthropic.*`,
              ],
            }),
            // S3 read permissions for content bucket
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:GetObjectVersion'],
              resources: [contentBucket.bucketArn + '/*'],
            }),
            // EventBridge permissions to publish events
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['events:PutEvents'],
              resources: [customEventBus.eventBusArn],
            }),
          ],
        }),
      },
    });

    // IAM role for workflow Lambda functions (approved, rejected, review)
    const workflowRole = new iam.Role(this, 'WorkflowRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        WorkflowPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions to read from content bucket and write to workflow buckets
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:GetObjectVersion'],
              resources: [contentBucket.bucketArn + '/*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject', 's3:PutObjectAcl'],
              resources: [
                approvedBucket.bucketArn + '/*',
                rejectedBucket.bucketArn + '/*',
              ],
            }),
            // SNS permissions to publish notifications
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // ==================== LAMBDA FUNCTIONS ====================
    
    // Content analysis Lambda function - processes uploaded content with Bedrock
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
      code: lambda.Code.fromInline(`
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
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # Get content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Prepare moderation prompt for Bedrock Claude
        prompt = f"""Human: Please analyze the following content for policy violations. 
Consider harmful content including hate speech, violence, harassment, 
inappropriate sexual content, misinformation, and spam.

Content to analyze:
{content[:2000]}

Respond with a JSON object containing:
- "decision": "approved", "rejected", or "review"
- "confidence": score from 0.0 to 1.0
- "reason": brief explanation
- "categories": array of policy categories if violations found