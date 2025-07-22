#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { 
  Stack, 
  StackProps, 
  Duration, 
  RemovalPolicy,
  CfnOutput 
} from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Interface for stack configuration properties
 */
interface DatabaseConnectionPoolingStackProps extends StackProps {
  /** Database name for the RDS instance */
  databaseName?: string;
  /** Database master username */
  databaseUsername?: string;
  /** RDS instance class */
  instanceClass?: ec2.InstanceType;
  /** Whether to enable debug logging for RDS Proxy */
  enableDebugLogging?: boolean;
  /** Maximum connections percentage for RDS Proxy */
  maxConnectionsPercent?: number;
  /** Maximum idle connections percentage for RDS Proxy */
  maxIdleConnectionsPercent?: number;
  /** Idle client timeout in seconds */
  idleClientTimeout?: Duration;
}

/**
 * CDK Stack for Database Connection Pooling with RDS Proxy
 * 
 * This stack creates:
 * - VPC with private subnets for database deployment
 * - RDS MySQL instance with encryption enabled
 * - RDS Proxy for connection pooling and multiplexing
 * - Secrets Manager secret for database credentials
 * - Lambda function for testing proxy connectivity
 * - Appropriate security groups and IAM roles
 */
export class DatabaseConnectionPoolingStack extends Stack {
  /** VPC for hosting database and proxy resources */
  public readonly vpc: ec2.Vpc;
  
  /** RDS MySQL database instance */
  public readonly database: rds.DatabaseInstance;
  
  /** RDS Proxy for connection pooling */
  public readonly databaseProxy: rds.DatabaseProxy;
  
  /** Secret containing database credentials */
  public readonly databaseSecret: secretsmanager.Secret;
  
  /** Lambda function for testing connectivity */
  public readonly testFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: DatabaseConnectionPoolingStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const config = {
      databaseName: props.databaseName || 'testdb',
      databaseUsername: props.databaseUsername || 'admin',
      instanceClass: props.instanceClass || ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      enableDebugLogging: props.enableDebugLogging ?? true,
      maxConnectionsPercent: props.maxConnectionsPercent || 75,
      maxIdleConnectionsPercent: props.maxIdleConnectionsPercent || 25,
      idleClientTimeout: props.idleClientTimeout || Duration.minutes(15)
    };

    // Create VPC with public and private subnets
    this.vpc = this.createVpc();

    // Create database credentials secret
    this.databaseSecret = this.createDatabaseSecret(config.databaseUsername);

    // Create RDS database instance
    this.database = this.createDatabase(config);

    // Create RDS Proxy for connection pooling
    this.databaseProxy = this.createDatabaseProxy(config);

    // Create Lambda function for testing
    this.testFunction = this.createTestLambdaFunction(config);

    // Create stack outputs
    this.createOutputs();

    // Apply consistent tagging
    this.applyTags();
  }

  /**
   * Creates VPC with public and private subnets across two availability zones
   */
  private createVpc(): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'DatabaseProxyVpc', {
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for this demo
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true
    });

    // Add VPC endpoints for Secrets Manager (optional, for production use)
    vpc.addInterfaceEndpoint('SecretsManagerEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
      privateDnsEnabled: true
    });

    return vpc;
  }

  /**
   * Creates Secrets Manager secret for database credentials
   */
  private createDatabaseSecret(username: string): secretsmanager.Secret {
    return new secretsmanager.Secret(this, 'DatabaseSecret', {
      description: 'Database credentials for RDS Proxy demonstration',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        includeSpace: false,
        passwordLength: 16,
        requireEachIncludedType: true
      },
      removalPolicy: RemovalPolicy.DESTROY // For demo purposes only
    });
  }

  /**
   * Creates RDS MySQL database instance with security best practices
   */
  private createDatabase(config: any): rds.DatabaseInstance {
    // Create security group for RDS instance
    const databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for RDS MySQL instance',
      allowAllOutbound: false
    });

    // Create subnet group for RDS instance
    const subnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc: this.vpc,
      description: 'Subnet group for RDS MySQL instance',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED
      }
    });

    // Create RDS instance with encryption and backup enabled
    const database = new rds.DatabaseInstance(this, 'Database', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0_35
      }),
      instanceType: config.instanceClass,
      credentials: rds.Credentials.fromSecret(this.databaseSecret),
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED
      },
      subnetGroup,
      securityGroups: [databaseSecurityGroup],
      databaseName: config.databaseName,
      allocatedStorage: 20,
      storageEncrypted: true,
      backupRetention: Duration.days(7),
      deletionProtection: false, // For demo purposes
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      cloudwatchLogsExports: ['error', 'general', 'slow-query'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_WEEK
    });

    return database;
  }

  /**
   * Creates RDS Proxy for connection pooling and multiplexing
   */
  private createDatabaseProxy(config: any): rds.DatabaseProxy {
    // Create security group for RDS Proxy
    const proxySecurityGroup = new ec2.SecurityGroup(this, 'ProxySecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for RDS Proxy'
    });

    // Allow proxy to connect to database
    this.database.connections.allowFrom(
      proxySecurityGroup,
      ec2.Port.tcp(3306),
      'Allow RDS Proxy to connect to database'
    );

    // Allow applications in VPC to connect to proxy
    proxySecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow VPC resources to connect to RDS Proxy'
    );

    // Create IAM role for RDS Proxy to access Secrets Manager
    const proxyRole = new iam.Role(this, 'ProxyRole', {
      assumedBy: new iam.ServicePrincipal('rds.amazonaws.com'),
      description: 'IAM role for RDS Proxy to access Secrets Manager'
    });

    // Grant proxy permission to access the database secret
    this.databaseSecret.grantRead(proxyRole);

    // Create RDS Proxy
    const proxy = new rds.DatabaseProxy(this, 'DatabaseProxy', {
      proxyTarget: rds.ProxyTarget.fromInstance(this.database),
      secrets: [this.databaseSecret],
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED
      },
      securityGroups: [proxySecurityGroup],
      role: proxyRole,
      debugLogging: config.enableDebugLogging,
      idleClientTimeout: config.idleClientTimeout,
      maxConnectionsPercent: config.maxConnectionsPercent,
      maxIdleConnectionsPercent: config.maxIdleConnectionsPercent,
      requireTLS: false // Set to true for production
    });

    return proxy;
  }

  /**
   * Creates Lambda function for testing database connectivity through proxy
   */
  private createTestLambdaFunction(config: any): lambda.Function {
    // Create security group for Lambda function
    const lambdaSecurityGroup = new ec2.SecurityGroup(this, 'LambdaSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Lambda function',
      allowAllOutbound: true
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole')
      ]
    });

    // Grant Lambda permission to read the database secret
    this.databaseSecret.grantRead(lambdaRole);

    // Create Lambda function
    const testFunction = new lambda.Function(this, 'TestFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED
      },
      securityGroups: [lambdaSecurityGroup],
      timeout: Duration.seconds(30),
      environment: {
        PROXY_ENDPOINT: this.databaseProxy.endpoint,
        SECRET_ARN: this.databaseSecret.secretArn,
        DATABASE_NAME: config.databaseName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import pymysql
import os
import sys

def lambda_handler(event, context):
    """
    Test function to verify RDS Proxy connectivity and connection pooling
    """
    try:
        # Get database credentials from Secrets Manager
        secrets_client = boto3.client('secretsmanager')
        secret_response = secrets_client.get_secret_value(
            SecretId=os.environ['SECRET_ARN']
        )
        
        credentials = json.loads(secret_response['SecretString'])
        
        # Connect to database through RDS Proxy
        connection = pymysql.connect(
            host=os.environ['PROXY_ENDPOINT'],
            user=credentials['username'],
            password=credentials['password'],
            database=os.environ['DATABASE_NAME'],
            port=3306,
            cursorclass=pymysql.cursors.DictCursor,
            connect_timeout=10,
            read_timeout=10,
            write_timeout=10
        )
        
        with connection.cursor() as cursor:
            # Execute test queries
            cursor.execute("SELECT 1 as connection_test, CONNECTION_ID() as connection_id, NOW() as timestamp")
            result = cursor.fetchone()
            
            # Test connection info
            cursor.execute("SELECT USER() as current_user, DATABASE() as current_database")
            user_info = cursor.fetchone()
            
        connection.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully connected through RDS Proxy',
                'test_result': result,
                'user_info': user_info,
                'proxy_endpoint': os.environ['PROXY_ENDPOINT']
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__
            })
        }
      `),
      layers: [
        // You would typically create a layer with PyMySQL, but for demo purposes
        // we're using inline code. In production, create a proper layer.
      ]
    });

    return testFunction;
  }

  /**
   * Creates CloudFormation outputs for key resources
   */
  private createOutputs(): void {
    new CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the database infrastructure'
    });

    new CfnOutput(this, 'DatabaseEndpoint', {
      value: this.database.instanceEndpoint.hostname,
      description: 'RDS MySQL database endpoint'
    });

    new CfnOutput(this, 'ProxyEndpoint', {
      value: this.databaseProxy.endpoint,
      description: 'RDS Proxy endpoint for application connections'
    });

    new CfnOutput(this, 'SecretArn', {
      value: this.databaseSecret.secretArn,
      description: 'ARN of the Secrets Manager secret containing database credentials'
    });

    new CfnOutput(this, 'TestFunctionName', {
      value: this.testFunction.functionName,
      description: 'Lambda function name for testing proxy connectivity'
    });

    new CfnOutput(this, 'TestFunctionArn', {
      value: this.testFunction.functionArn,
      description: 'Lambda function ARN for testing proxy connectivity'
    });
  }

  /**
   * Applies consistent tags to all resources in the stack
   */
  private applyTags(): void {
    cdk.Tags.of(this).add('Project', 'DatabaseConnectionPooling');
    cdk.Tags.of(this).add('Recipe', 'database-connection-pooling-rds-proxy');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const config = {
  databaseName: app.node.tryGetContext('databaseName') || process.env.DATABASE_NAME || 'testdb',
  databaseUsername: app.node.tryGetContext('databaseUsername') || process.env.DATABASE_USERNAME || 'admin',
  enableDebugLogging: app.node.tryGetContext('enableDebugLogging') ?? true,
  maxConnectionsPercent: parseInt(app.node.tryGetContext('maxConnectionsPercent') || '75'),
  maxIdleConnectionsPercent: parseInt(app.node.tryGetContext('maxIdleConnectionsPercent') || '25'),
  idleClientTimeout: Duration.minutes(parseInt(app.node.tryGetContext('idleClientTimeoutMinutes') || '15'))
};

// Create the stack
new DatabaseConnectionPoolingStack(app, 'DatabaseConnectionPoolingStack', {
  description: 'Database Connection Pooling with RDS Proxy - CDK TypeScript Implementation',
  ...config,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});

// Synthesize the app
app.synth();