#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as appconfig from 'aws-cdk-lib/aws-appconfig';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for the Simple AppConfig Lambda Configuration Management solution
 * 
 * This stack creates:
 * - AppConfig Application with environment and configuration profile
 * - Lambda function with AppConfig extension layer
 * - IAM roles and policies for secure access
 * - CloudWatch log groups for monitoring
 */
export class SimpleAppConfigLambdaStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Create AppConfig Application
    const appConfigApplication = new appconfig.CfnApplication(this, 'ConfigApplication', {
      name: `simple-config-app-${uniqueSuffix}`,
      description: 'Simple configuration management demo application',
    });

    // Create AppConfig Environment (Development)
    const appConfigEnvironment = new appconfig.CfnEnvironment(this, 'ConfigEnvironment', {
      applicationId: appConfigApplication.ref,
      name: 'development',
      description: 'Development environment for configuration testing',
    });

    // Create AppConfig Configuration Profile
    const configurationProfile = new appconfig.CfnConfigurationProfile(this, 'ConfigProfile', {
      applicationId: appConfigApplication.ref,
      name: 'app-settings',
      description: 'Application settings configuration profile',
      locationUri: 'hosted',
    });

    // Create initial configuration data as hosted configuration
    const initialConfig = {
      database: {
        max_connections: 100,
        timeout_seconds: 30,
        retry_attempts: 3
      },
      features: {
        enable_logging: true,
        enable_metrics: true,
        debug_mode: false
      },
      api: {
        rate_limit: 1000,
        cache_ttl: 300
      }
    };

    const hostedConfigurationVersion = new appconfig.CfnHostedConfigurationVersion(this, 'ConfigData', {
      applicationId: appConfigApplication.ref,
      configurationProfileId: configurationProfile.ref,
      content: JSON.stringify(initialConfig, null, 2),
      contentType: 'application/json',
      description: 'Initial application configuration',
    });

    // Create deployment strategy for immediate deployment
    const deploymentStrategy = new appconfig.CfnDeploymentStrategy(this, 'DeploymentStrategy', {
      name: `immediate-deployment-${uniqueSuffix}`,
      description: 'Immediate deployment strategy for testing',
      deploymentDurationInMinutes: 0,
      finalBakeTimeInMinutes: 0,
      growthFactor: 100,
      growthType: 'LINEAR',
      replicateTo: 'NONE',
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `lambda-appconfig-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda function to access AppConfig',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        AppConfigPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'appconfig:StartConfigurationSession',
                'appconfig:GetLatestConfiguration',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/config-demo-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Lambda function code
    const lambdaCode = `
import json
import urllib3
import os

def lambda_handler(event, context):
    # AppConfig extension endpoint (local to Lambda execution environment)
    appconfig_endpoint = 'http://localhost:2772'
    
    # AppConfig parameters from environment variables
    application_id = os.environ.get('APPCONFIG_APPLICATION_ID')
    environment_id = os.environ.get('APPCONFIG_ENVIRONMENT_ID')
    configuration_profile_id = os.environ.get('APPCONFIG_CONFIGURATION_PROFILE_ID')
    
    try:
        # Create HTTP connection to AppConfig extension
        http = urllib3.PoolManager()
        
        # Retrieve configuration from AppConfig
        config_url = f"{appconfig_endpoint}/applications/{application_id}/environments/{environment_id}/configurations/{configuration_profile_id}"
        response = http.request('GET', config_url)
        
        if response.status == 200:
            config_data = json.loads(response.data.decode('utf-8'))
            
            # Use configuration in application logic
            max_connections = config_data.get('database', {}).get('max_connections', 50)
            enable_logging = config_data.get('features', {}).get('enable_logging', False)
            rate_limit = config_data.get('api', {}).get('rate_limit', 500)
            
            # Log configuration usage if logging is enabled
            if enable_logging:
                print(f"Configuration loaded - Max connections: {max_connections}, Rate limit: {rate_limit}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Configuration loaded successfully',
                    'config_summary': {
                        'database_max_connections': max_connections,
                        'logging_enabled': enable_logging,
                        'api_rate_limit': rate_limit
                    }
                })
            }
        else:
            print(f"Failed to retrieve configuration: {response.status}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Configuration retrieval failed'})
            }
            
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
`;

    // Create Lambda function
    const lambdaFunction = new lambda.Function(this, 'ConfigDemoFunction', {
      functionName: `config-demo-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      description: 'Lambda function demonstrating AppConfig integration',
      environment: {
        APPCONFIG_APPLICATION_ID: appConfigApplication.ref,
        APPCONFIG_ENVIRONMENT_ID: appConfigEnvironment.ref,
        APPCONFIG_CONFIGURATION_PROFILE_ID: configurationProfile.ref,
      },
      layers: [
        // AppConfig Lambda Extension Layer (region-specific ARN)
        lambda.LayerVersion.fromLayerVersionArn(
          this,
          'AppConfigExtension',
          `arn:aws:lambda:${this.region}:027255383542:layer:AWS-AppConfig-Extension:207`
        ),
      ],
      logGroup: logGroup,
    });

    // Create AppConfig deployment to activate the configuration
    const deployment = new appconfig.CfnDeployment(this, 'ConfigDeployment', {
      applicationId: appConfigApplication.ref,
      environmentId: appConfigEnvironment.ref,
      deploymentStrategyId: deploymentStrategy.ref,
      configurationProfileId: configurationProfile.ref,
      configurationVersion: hostedConfigurationVersion.ref,
      description: 'Initial configuration deployment',
    });

    // Ensure deployment happens after all resources are created
    deployment.addDependency(hostedConfigurationVersion);
    deployment.addDependency(deploymentStrategy);
    deployment.addDependency(lambdaFunction);

    // Stack Outputs
    new cdk.CfnOutput(this, 'AppConfigApplicationId', {
      value: appConfigApplication.ref,
      description: 'AppConfig Application ID',
      exportName: `${this.stackName}-AppConfigApplicationId`,
    });

    new cdk.CfnOutput(this, 'AppConfigEnvironmentId', {
      value: appConfigEnvironment.ref,
      description: 'AppConfig Environment ID',
      exportName: `${this.stackName}-AppConfigEnvironmentId`,
    });

    new cdk.CfnOutput(this, 'ConfigurationProfileId', {
      value: configurationProfile.ref,
      description: 'AppConfig Configuration Profile ID',
      exportName: `${this.stackName}-ConfigurationProfileId`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: lambdaFunction.functionName,
      description: 'Lambda Function Name',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: lambdaFunction.functionArn,
      description: 'Lambda Function ARN',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'DeploymentStrategyId', {
      value: deploymentStrategy.ref,
      description: 'AppConfig Deployment Strategy ID',
      exportName: `${this.stackName}-DeploymentStrategyId`,
    });

    new cdk.CfnOutput(this, 'TestCommand', {
      value: `aws lambda invoke --function-name ${lambdaFunction.functionName} --payload '{}' response.json && cat response.json`,
      description: 'AWS CLI command to test the Lambda function',
    });
  }
}

// CDK App
const app = new cdk.App();

// Create the stack
new SimpleAppConfigLambdaStack(app, 'SimpleAppConfigLambdaStack', {
  description: 'Simple Application Configuration with AppConfig and Lambda - A dynamic configuration management system using AWS AppConfig integrated with AWS Lambda',
  
  // Stack-level tags
  tags: {
    Project: 'SimpleAppConfiguration',
    Environment: 'Development',
    ManagedBy: 'CDK',
    Recipe: 'simple-app-configuration-appconfig-lambda',
  },

  // Enable termination protection for production deployments
  // terminationProtection: true,
});

// Synthesize the app
app.synth();