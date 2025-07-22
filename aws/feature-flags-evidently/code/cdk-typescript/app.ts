#!/usr/bin/env node

import * as cdk from 'aws-cdk-lib';
import * as evidently from 'aws-cdk-lib/aws-evidently';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Feature Flags with CloudWatch Evidently Stack
 * 
 * This stack implements a complete feature flag solution using Amazon CloudWatch Evidently,
 * demonstrating controlled feature rollouts, A/B testing, and real-time monitoring capabilities.
 * 
 * Key Components:
 * - CloudWatch Evidently Project for feature management
 * - Feature flags with multiple variations
 * - Launch configuration for gradual traffic splitting
 * - Lambda function for feature evaluation
 * - IAM roles with least privilege principles
 * - CloudWatch logging for audit trails
 */
export class FeatureFlagsEvidentlyStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique identifiers for resources
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const projectName = `feature-demo-${randomSuffix}`;
    const lambdaFunctionName = `evidently-demo-${randomSuffix}`;

    // Create CloudWatch Log Group for Evidently evaluations
    const evidentlyLogGroup = new logs.LogGroup(this, 'EvidentlyEvaluationLogs', {
      logGroupName: '/aws/evidently/evaluations',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create Evidently Project for feature management
    const evidentlyProject = new evidently.CfnProject(this, 'FeatureDemoProject', {
      name: projectName,
      description: 'Feature flag demonstration project for safe deployments and A/B testing',
      dataDelivery: {
        cloudWatchLogs: {
          logGroup: evidentlyLogGroup.logGroupName
        }
      },
      tags: [
        {
          key: 'Environment',
          value: 'demo'
        },
        {
          key: 'Purpose',
          value: 'feature-flags-demonstration'
        }
      ]
    });

    // Create feature flag with boolean variations for checkout flow
    const checkoutFeature = new evidently.CfnFeature(this, 'NewCheckoutFlowFeature', {
      project: evidentlyProject.name,
      name: 'new-checkout-flow',
      description: 'Controls visibility of the new checkout experience for e-commerce platform',
      variations: [
        {
          variationName: 'enabled',
          booleanValue: true
        },
        {
          variationName: 'disabled',
          booleanValue: false
        }
      ],
      defaultVariation: 'disabled', // Safe default - feature disabled by default
      tags: [
        {
          key: 'FeatureType',
          value: 'ui-enhancement'
        },
        {
          key: 'RiskLevel',
          value: 'medium'
        }
      ]
    });

    // Ensure feature depends on project creation
    checkoutFeature.addDependsOn(evidentlyProject);

    // Create IAM role for Lambda function with Evidently permissions
    const lambdaExecutionRole = new iam.Role(this, 'EvidentlyLambdaRole', {
      roleName: `evidently-lambda-role-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda function to evaluate CloudWatch Evidently feature flags',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        EvidentlyAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'evidently:EvaluateFeature',
                'evidently:GetProject',
                'evidently:GetFeature'
              ],
              resources: [
                evidentlyProject.attrArn,
                `${evidentlyProject.attrArn}/feature/*`
              ]
            })
          ]
        })
      }
    });

    // Create Lambda function for feature evaluation
    const featureEvaluationFunction = new lambda.Function(this, 'FeatureEvaluationFunction', {
      functionName: lambdaFunctionName,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      description: 'Evaluates feature flags using CloudWatch Evidently for controlled rollouts',
      environment: {
        PROJECT_NAME: evidentlyProject.name,
        FEATURE_NAME: checkoutFeature.name,
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Evaluates feature flags using CloudWatch Evidently.
    
    This function demonstrates best practices for feature flag evaluation including:
    - Proper error handling with safe defaults
    - User identification for consistent experiences
    - Structured logging for debugging and audit trails
    - Performance optimization with client reuse
    """
    
    # Initialize Evidently client (reuse across invocations)
    if not hasattr(lambda_handler, 'evidently_client'):
        lambda_handler.evidently_client = boto3.client('evidently')
    
    # Extract user information from event
    user_id = event.get('userId', 'anonymous-user')
    project_name = os.environ['PROJECT_NAME']
    feature_name = os.environ['FEATURE_NAME']
    
    try:
        # Evaluate feature flag for the specific user
        response = lambda_handler.evidently_client.evaluate_feature(
            project=project_name,
            feature=feature_name,
            entityId=user_id
        )
        
        # Determine if feature is enabled based on variation
        feature_enabled = response['variation'] == 'enabled'
        
        # Log evaluation for debugging and audit purposes
        logger.info(f"Feature evaluation - User: {user_id}, Variation: {response['variation']}, "
                   f"Reason: {response.get('reason', 'default')}")
        
        # Return structured response with feature status
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache'  # Prevent caching of feature flag responses
            },
            'body': json.dumps({
                'userId': user_id,
                'featureEnabled': feature_enabled,
                'variation': response['variation'],
                'reason': response.get('reason', 'default'),
                'timestamp': context.aws_request_id
            })
        }
        
    except Exception as e:
        # Log error for troubleshooting
        logger.error(f"Error evaluating feature for user {user_id}: {str(e)}")
        
        # Return safe default response on error
        return {
            'statusCode': 200,  # Return 200 to prevent application breakage
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'userId': user_id,
                'featureEnabled': False,  # Safe default - feature disabled
                'variation': 'disabled',
                'reason': 'error-fallback',
                'error': 'Feature evaluation failed - using safe default',
                'timestamp': context.aws_request_id
            })
        }
`),
      tags: {
        'Purpose': 'feature-flag-evaluation',
        'Environment': 'demo'
      }
    });

    // Ensure Lambda function depends on project and feature creation
    featureEvaluationFunction.node.addDependency(evidentlyProject);
    featureEvaluationFunction.node.addDependency(checkoutFeature);

    // Create launch configuration for gradual rollout (10% traffic to new feature)
    const gradualRolloutLaunch = new evidently.CfnLaunch(this, 'CheckoutGradualRollout', {
      project: evidentlyProject.name,
      name: 'checkout-gradual-rollout',
      description: 'Gradual rollout of new checkout flow to 10% of users with monitoring',
      groups: [
        {
          groupName: 'control-group',
          description: 'Users with existing checkout flow (90% of traffic)',
          feature: checkoutFeature.name,
          variation: 'disabled'
        },
        {
          groupName: 'treatment-group',
          description: 'Users with new checkout flow (10% of traffic)',
          feature: checkoutFeature.name,
          variation: 'enabled'
        }
      ],
      scheduledSplitsConfig: {
        steps: [
          {
            startTime: new Date().toISOString(),
            groupWeights: {
              'control-group': 90,
              'treatment-group': 10
            }
          }
        ]
      },
      tags: [
        {
          key: 'RolloutStrategy',
          value: 'gradual-10-percent'
        },
        {
          key: 'Environment',
          value: 'demo'
        }
      ]
    });

    // Ensure launch depends on project and feature creation
    gradualRolloutLaunch.addDependsOn(evidentlyProject);
    gradualRolloutLaunch.addDependsOn(checkoutFeature);

    // CloudFormation Outputs for verification and integration
    new cdk.CfnOutput(this, 'EvidentlyProjectName', {
      value: evidentlyProject.name,
      description: 'Name of the CloudWatch Evidently project for feature management',
      exportName: `${this.stackName}-ProjectName`
    });

    new cdk.CfnOutput(this, 'EvidentlyProjectArn', {
      value: evidentlyProject.attrArn,
      description: 'ARN of the CloudWatch Evidently project',
      exportName: `${this.stackName}-ProjectArn`
    });

    new cdk.CfnOutput(this, 'FeatureName', {
      value: checkoutFeature.name,
      description: 'Name of the checkout flow feature flag',
      exportName: `${this.stackName}-FeatureName`
    });

    new cdk.CfnOutput(this, 'LaunchName', {
      value: gradualRolloutLaunch.name,
      description: 'Name of the gradual rollout launch configuration',
      exportName: `${this.stackName}-LaunchName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: featureEvaluationFunction.functionName,
      description: 'Name of the Lambda function for feature evaluation',
      exportName: `${this.stackName}-LambdaFunctionName`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: featureEvaluationFunction.functionArn,
      description: 'ARN of the Lambda function for feature evaluation',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: evidentlyLogGroup.logGroupName,
      description: 'CloudWatch Log Group for Evidently evaluations',
      exportName: `${this.stackName}-LogGroupName`
    });
  }
}

// Create CDK App and instantiate the stack
const app = new cdk.App();

new FeatureFlagsEvidentlyStack(app, 'FeatureFlagsEvidentlyStack', {
  description: 'CloudWatch Evidently Feature Flags demonstration with Lambda evaluation and gradual rollout',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    'Project': 'feature-flags-evidently-demo',
    'ManagedBy': 'AWS-CDK',
    'Environment': 'demo'
  }
});

// Synthesize CloudFormation template
app.synth();