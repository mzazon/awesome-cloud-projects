#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * Props for the SecretsManagerStack
 */
export interface SecretsManagerStackProps extends cdk.StackProps {
  /**
   * The name of the secret to create
   * @default 'demo-db-credentials'
   */
  readonly secretName?: string;
  
  /**
   * The rotation schedule expression
   * @default 'rate(7 days)'
   */
  readonly rotationSchedule?: string;
  
  /**
   * Environment tag for the resources
   * @default 'Demo'
   */
  readonly environmentTag?: string;
  
  /**
   * Application tag for the resources
   * @default 'MyApp'
   */
  readonly applicationTag?: string;
}

/**
 * CDK Stack for AWS Secrets Manager with automatic rotation
 * 
 * This stack creates:
 * - KMS key for encryption
 * - Secrets Manager secret with structured database credentials
 * - Lambda function for rotation
 * - IAM roles and policies
 * - CloudWatch dashboard and alarms
 * - Cross-account access policies
 */
export class SecretsManagerStack extends cdk.Stack {
  
  public readonly secret: secretsmanager.Secret;
  public readonly kmsKey: kms.Key;
  public readonly rotationLambda: lambda.Function;
  public readonly dashboard: cloudwatch.Dashboard;
  
  constructor(scope: Construct, id: string, props: SecretsManagerStackProps = {}) {
    super(scope, id, props);
    
    const {
      secretName = 'demo-db-credentials',
      rotationSchedule = 'rate(7 days)',
      environmentTag = 'Demo',
      applicationTag = 'MyApp'
    } = props;
    
    // Create KMS key for encryption
    this.kmsKey = new kms.Key(this, 'SecretsManagerKey', {
      description: 'KMS key for Secrets Manager encryption',
      enableKeyRotation: true,
      alias: `secrets-manager-key-${this.stackName}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });
    
    // Create IAM role for Lambda rotation function
    const rotationRole = new iam.Role(this, 'SecretsManagerRotationRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Secrets Manager rotation Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });
    
    // Create custom policy for Secrets Manager access
    const secretsManagerPolicy = new iam.Policy(this, 'SecretsManagerRotationPolicy', {
      policyName: `SecretsManagerRotationPolicy-${this.stackName}`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'secretsmanager:GetSecretValue',
            'secretsmanager:DescribeSecret',
            'secretsmanager:PutSecretValue',
            'secretsmanager:UpdateSecretVersionStage',
          ],
          resources: [`arn:aws:secretsmanager:${this.region}:${this.account}:secret:*`],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'kms:Decrypt',
            'kms:DescribeKey',
            'kms:Encrypt',
            'kms:GenerateDataKey*',
            'kms:ReEncrypt*',
          ],
          resources: [this.kmsKey.keyArn],
        }),
      ],
    });
    
    rotationRole.attachInlinePolicy(secretsManagerPolicy);
    
    // Create Lambda function for rotation
    this.rotationLambda = new lambda.Function(this, 'RotationLambda', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'rotation_lambda.lambda_handler',
      timeout: Duration.seconds(60),
      role: rotationRole,
      description: 'Lambda function for rotating Secrets Manager secrets',
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to handle secret rotation
    """
    secretsmanager = boto3.client('secretsmanager')
    
    secret_arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']
    
    logger.info(f"Rotation step: {step} for secret: {secret_arn}")
    
    if step == "createSecret":
        create_secret(secretsmanager, secret_arn, token)
    elif step == "setSecret":
        set_secret(secretsmanager, secret_arn, token)
    elif step == "testSecret":
        test_secret(secretsmanager, secret_arn, token)
    elif step == "finishSecret":
        finish_secret(secretsmanager, secret_arn, token)
    else:
        logger.error(f"Invalid step parameter: {step}")
        raise ValueError(f"Invalid step parameter: {step}")
    
    return {"statusCode": 200, "body": "Rotation completed successfully"}

def create_secret(secretsmanager, secret_arn, token):
    """Create a new secret version"""
    try:
        current_secret = secretsmanager.get_secret_value(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT"
        )
        
        # Parse current secret
        current_data = json.loads(current_secret['SecretString'])
        
        # Generate new password
        new_password = secretsmanager.get_random_password(
            PasswordLength=20,
            ExcludeCharacters='"@/\\\\',
            RequireEachIncludedType=True
        )['RandomPassword']
        
        # Update password in secret data
        current_data['password'] = new_password
        
        # Create new secret version
        secretsmanager.put_secret_value(
            SecretId=secret_arn,
            ClientRequestToken=token,
            SecretString=json.dumps(current_data),
            VersionStages=['AWSPENDING']
        )
        
        logger.info("createSecret: Successfully created new secret version")
        
    except Exception as e:
        logger.error(f"createSecret: Error creating secret: {str(e)}")
        raise

def set_secret(secretsmanager, secret_arn, token):
    """Set the secret in the service"""
    logger.info("setSecret: In a real implementation, this would update the database user password")
    # In a real implementation, you would connect to the database
    # and update the user's password here

def test_secret(secretsmanager, secret_arn, token):
    """Test the secret"""
    logger.info("testSecret: In a real implementation, this would test database connectivity")
    # In a real implementation, you would test the database connection
    # with the new credentials here

def finish_secret(secretsmanager, secret_arn, token):
    """Finish the rotation"""
    try:
        # Get current version ID
        current_version = get_current_version_id(secretsmanager, secret_arn)
        
        # Move AWSCURRENT to AWSPREVIOUS and AWSPENDING to AWSCURRENT
        secretsmanager.update_secret_version_stage(
            SecretId=secret_arn,
            VersionStage="AWSCURRENT",
            MoveToVersionId=token,
            RemoveFromVersionId=current_version
        )
        
        logger.info("finishSecret: Successfully completed rotation")
        
    except Exception as e:
        logger.error(f"finishSecret: Error finishing rotation: {str(e)}")
        raise

def get_current_version_id(secretsmanager, secret_arn):
    """Get the current version ID"""
    versions = secretsmanager.list_secret_version_ids(SecretId=secret_arn)
    
    for version in versions['Versions']:
        if 'AWSCURRENT' in version['VersionStages']:
            return version['VersionId']
    
    return None
      `),
    });
    
    // Create the secret with structured database credentials
    this.secret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      secretName: secretName,
      description: 'Database credentials for demo application',
      encryptionKey: this.kmsKey,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          engine: 'mysql',
          host: 'demo-database.cluster-abc123.us-east-1.rds.amazonaws.com',
          username: 'admin',
          dbname: 'myapp',
          port: 3306,
        }),
        generateStringKey: 'password',
        passwordLength: 20,
        excludeCharacters: '"@/\\',
        requireEachIncludedType: true,
      },
    });
    
    // Add tags to the secret
    cdk.Tags.of(this.secret).add('Environment', environmentTag);
    cdk.Tags.of(this.secret).add('Application', applicationTag);
    
    // Configure automatic rotation
    this.secret.addRotationSchedule('RotationSchedule', {
      rotationLambda: this.rotationLambda,
      automaticallyAfter: Duration.days(7),
    });
    
    // Grant Secrets Manager permission to invoke the Lambda function
    this.rotationLambda.addPermission('SecretsManagerInvoke', {
      principal: new iam.ServicePrincipal('secretsmanager.amazonaws.com'),
      action: 'lambda:InvokeFunction',
    });
    
    // Create resource-based policy for cross-account access
    const resourcePolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          sid: 'AllowCrossAccountAccess',
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['secretsmanager:GetSecretValue'],
          resources: ['*'],
          conditions: {
            StringEquals: {
              'secretsmanager:ResourceTag/Environment': environmentTag,
            },
          },
        }),
      ],
    });
    
    // Apply resource policy to the secret
    const cfnSecret = this.secret.node.defaultChild as secretsmanager.CfnSecret;
    cfnSecret.addPropertyOverride('ResourcePolicy', resourcePolicy);
    
    // Create CloudWatch dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'SecretsManagerDashboard', {
      dashboardName: `SecretsManager-${this.stackName}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Secret Rotation Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/SecretsManager',
                metricName: 'RotationSucceeded',
                dimensionsMap: {
                  SecretName: this.secret.secretName,
                },
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/SecretsManager',
                metricName: 'RotationFailed',
                dimensionsMap: {
                  SecretName: this.secret.secretName,
                },
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });
    
    // Create CloudWatch alarm for rotation failures
    const rotationFailureAlarm = new cloudwatch.Alarm(this, 'RotationFailureAlarm', {
      alarmName: `SecretsManager-RotationFailure-${this.stackName}`,
      alarmDescription: 'Alert when secret rotation fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SecretsManager',
        metricName: 'RotationFailed',
        dimensionsMap: {
          SecretName: this.secret.secretName,
        },
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
    });
    
    // Output important information
    new cdk.CfnOutput(this, 'SecretArn', {
      value: this.secret.secretArn,
      description: 'ARN of the created secret',
    });
    
    new cdk.CfnOutput(this, 'SecretName', {
      value: this.secret.secretName,
      description: 'Name of the created secret',
    });
    
    new cdk.CfnOutput(this, 'KmsKeyId', {
      value: this.kmsKey.keyId,
      description: 'KMS Key ID for encryption',
    });
    
    new cdk.CfnOutput(this, 'RotationLambdaArn', {
      value: this.rotationLambda.functionArn,
      description: 'ARN of the rotation Lambda function',
    });
    
    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
    });
    
    new cdk.CfnOutput(this, 'SampleApplicationCode', {
      value: this.createSampleApplicationCode(),
      description: 'Sample Python code for retrieving the secret',
    });
  }
  
  /**
   * Creates sample application code for secret retrieval
   */
  private createSampleApplicationCode(): string {
    return `
import boto3
import json
from botocore.exceptions import ClientError

def get_secret():
    secret_name = "${this.secret.secretName}"
    region_name = "${this.region}"
    
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    
    try:
        response = client.get_secret_value(SecretId=secret_name)
        secret_data = json.loads(response['SecretString'])
        return secret_data
    except ClientError as e:
        raise e

# Usage example
credentials = get_secret()
print(f"Host: {credentials['host']}")
print(f"Username: {credentials['username']}")
print("Password: [REDACTED]")
    `;
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack
new SecretsManagerStack(app, 'SecretsManagerStack', {
  description: 'AWS Secrets Manager with automatic rotation demonstration',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SecretsManagerDemo',
    Environment: 'Demo',
  },
});

// Synthesize the app
app.synth();