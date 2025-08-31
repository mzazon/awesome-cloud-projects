#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as servicecatalog from 'aws-cdk-lib/aws-servicecatalog';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as path from 'path';

/**
 * Properties for the Service Catalog Portfolio Stack
 */
export interface ServiceCatalogPortfolioStackProps extends cdk.StackProps {
  /**
   * The name of the portfolio
   * @default 'enterprise-infrastructure'
   */
  portfolioName?: string;

  /**
   * The display name for the S3 product
   * @default 'managed-s3-bucket'
   */
  s3ProductName?: string;

  /**
   * The display name for the Lambda product
   * @default 'serverless-function'
   */
  lambdaProductName?: string;

  /**
   * Principal ARN to grant portfolio access
   * If not provided, no principal will be associated
   */
  principalArn?: string;
}

/**
 * CDK Stack for Service Catalog Portfolio with CloudFormation Templates
 * 
 * This stack creates a Service Catalog portfolio containing two products:
 * 1. S3 Bucket Product - Secure S3 bucket with encryption and versioning
 * 2. Lambda Function Product - Lambda function with IAM role and logging
 * 
 * The implementation includes:
 * - CloudFormation templates stored in S3
 * - Service Catalog portfolio and products
 * - Launch constraints with dedicated IAM role
 * - Portfolio access for specified principals
 */
export class ServiceCatalogPortfolioStack extends cdk.Stack {
  public readonly portfolio: servicecatalog.Portfolio;
  public readonly s3Product: servicecatalog.CloudFormationProduct;
  public readonly lambdaProduct: servicecatalog.CloudFormationProduct;
  public readonly launchRole: iam.Role;
  public readonly templatesBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: ServiceCatalogPortfolioStackProps) {
    super(scope, id, props);

    const portfolioName = props?.portfolioName || 'enterprise-infrastructure';
    const s3ProductName = props?.s3ProductName || 'managed-s3-bucket';
    const lambdaProductName = props?.lambdaProductName || 'serverless-function';

    // Create S3 bucket for CloudFormation templates
    this.templatesBucket = new s3.Bucket(this, 'TemplatesBucket', {
      bucketName: `service-catalog-templates-${cdk.Stack.of(this).account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Deploy CloudFormation templates to S3
    this.deployTemplates();

    // Create IAM role for launch constraints
    this.launchRole = this.createLaunchRole();

    // Create Service Catalog portfolio
    this.portfolio = new servicecatalog.Portfolio(this, 'Portfolio', {
      displayName: portfolioName,
      providerName: 'IT Infrastructure Team',
      description: 'Enterprise infrastructure templates for development teams',
      messageLanguage: servicecatalog.MessageLanguage.EN,
    });

    // Create S3 bucket product
    this.s3Product = this.createS3Product(s3ProductName);

    // Create Lambda function product
    this.lambdaProduct = this.createLambdaProduct(lambdaProductName);

    // Associate products with portfolio
    this.portfolio.addProduct(this.s3Product);
    this.portfolio.addProduct(this.lambdaProduct);

    // Add launch constraints to products
    this.addLaunchConstraints();

    // Associate principal with portfolio if provided
    if (props?.principalArn) {
      this.portfolio.giveAccessToRole(iam.Role.fromRoleArn(this, 'PrincipalRole', props.principalArn));
    }

    // Add stack outputs
    this.addOutputs();
  }

  /**
   * Deploy CloudFormation templates to S3 bucket
   */
  private deployTemplates(): void {
    // Create the templates as assets and deploy them
    new s3deploy.BucketDeployment(this, 'DeployS3Template', {
      sources: [s3deploy.Source.data('s3-bucket-template.yaml', this.getS3BucketTemplate())],
      destinationBucket: this.templatesBucket,
      destinationKeyPrefix: 'templates/',
    });

    new s3deploy.BucketDeployment(this, 'DeployLambdaTemplate', {
      sources: [s3deploy.Source.data('lambda-function-template.yaml', this.getLambdaFunctionTemplate())],
      destinationBucket: this.templatesBucket,
      destinationKeyPrefix: 'templates/',
    });
  }

  /**
   * Create IAM role for launch constraints
   */
  private createLaunchRole(): iam.Role {
    const role = new iam.Role(this, 'LaunchRole', {
      roleName: `ServiceCatalogLaunchRole-${cdk.Stack.of(this).stackName}`,
      assumedBy: new iam.ServicePrincipal('servicecatalog.amazonaws.com'),
      description: 'IAM role for Service Catalog launch constraints',
    });

    // Add policy with required permissions for S3 and Lambda resources
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        // S3 permissions
        's3:CreateBucket',
        's3:DeleteBucket',
        's3:PutBucketEncryption',
        's3:PutBucketVersioning',
        's3:PutBucketPublicAccessBlock',
        's3:PutBucketTagging',
        // Lambda permissions
        'lambda:CreateFunction',
        'lambda:DeleteFunction',
        'lambda:UpdateFunctionCode',
        'lambda:UpdateFunctionConfiguration',
        'lambda:TagResource',
        'lambda:UntagResource',
        // IAM permissions
        'iam:CreateRole',
        'iam:DeleteRole',
        'iam:AttachRolePolicy',
        'iam:DetachRolePolicy',
        'iam:PassRole',
        'iam:TagRole',
        'iam:UntagRole',
      ],
      resources: ['*'],
    }));

    return role;
  }

  /**
   * Create S3 bucket Service Catalog product
   */
  private createS3Product(productName: string): servicecatalog.CloudFormationProduct {
    return new servicecatalog.CloudFormationProduct(this, 'S3Product', {
      productName: productName,
      owner: 'IT Infrastructure Team',
      description: 'Managed S3 bucket with security best practices',
      productVersions: [
        {
          productVersionName: 'v1.0',
          description: 'Initial version with encryption and versioning',
          cloudFormationTemplate: servicecatalog.CloudFormationTemplate.fromUrl(
            `https://${this.templatesBucket.bucketName}.s3.${this.region}.amazonaws.com/templates/s3-bucket-template.yaml`
          ),
        },
      ],
    });
  }

  /**
   * Create Lambda function Service Catalog product
   */
  private createLambdaProduct(productName: string): servicecatalog.CloudFormationProduct {
    return new servicecatalog.CloudFormationProduct(this, 'LambdaProduct', {
      productName: productName,
      owner: 'IT Infrastructure Team',
      description: 'Managed Lambda function with IAM role and logging',
      productVersions: [
        {
          productVersionName: 'v1.0',
          description: 'Initial version with execution role',
          cloudFormationTemplate: servicecatalog.CloudFormationTemplate.fromUrl(
            `https://${this.templatesBucket.bucketName}.s3.${this.region}.amazonaws.com/templates/lambda-function-template.yaml`
          ),
        },
      ],
    });
  }

  /**
   * Add launch constraints to products
   */
  private addLaunchConstraints(): void {
    // Add launch constraint to S3 product
    this.portfolio.constrainCloudFormationParameters(this.s3Product, {
      rule: servicecatalog.TemplateRule.assertDescription('Environment parameter must be one of: development, staging, production'),
    });

    this.portfolio.setLaunchRole(this.s3Product, this.launchRole);

    // Add launch constraint to Lambda product
    this.portfolio.constrainCloudFormationParameters(this.lambdaProduct, {
      rule: servicecatalog.TemplateRule.assertDescription('Runtime parameter must be supported'),
    });

    this.portfolio.setLaunchRole(this.lambdaProduct, this.launchRole);
  }

  /**
   * Add stack outputs
   */
  private addOutputs(): void {
    new cdk.CfnOutput(this, 'PortfolioId', {
      value: this.portfolio.portfolioId,
      description: 'Service Catalog Portfolio ID',
      exportName: `${this.stackName}-PortfolioId`,
    });

    new cdk.CfnOutput(this, 'S3ProductId', {
      value: this.s3Product.productId,
      description: 'S3 Bucket Product ID',
      exportName: `${this.stackName}-S3ProductId`,
    });

    new cdk.CfnOutput(this, 'LambdaProductId', {
      value: this.lambdaProduct.productId,
      description: 'Lambda Function Product ID',
      exportName: `${this.stackName}-LambdaProductId`,
    });

    new cdk.CfnOutput(this, 'LaunchRoleArn', {
      value: this.launchRole.roleArn,
      description: 'Launch Role ARN',
      exportName: `${this.stackName}-LaunchRoleArn`,
    });

    new cdk.CfnOutput(this, 'TemplatesBucketName', {
      value: this.templatesBucket.bucketName,
      description: 'CloudFormation Templates Bucket Name',
      exportName: `${this.stackName}-TemplatesBucketName`,
    });
  }

  /**
   * Get S3 bucket CloudFormation template content
   */
  private getS3BucketTemplate(): string {
    return `AWSTemplateFormatVersion: '2010-09-09'
Description: 'Managed S3 bucket with security best practices'

Parameters:
  BucketName:
    Type: String
    Description: 'Name for the S3 bucket'
    AllowedPattern: '^[a-z0-9][a-z0-9-]*[a-z0-9]$'
    ConstraintDescription: 'Bucket name must be lowercase alphanumeric with hyphens'

  Environment:
    Type: String
    Default: 'development'
    AllowedValues: ['development', 'staging', 'production']
    Description: 'Environment for resource tagging'

Resources:
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref BucketName
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      VersioningConfiguration:
        Status: Enabled
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

Outputs:
  BucketName:
    Description: 'Name of the created S3 bucket'
    Value: !Ref S3Bucket
  BucketArn:
    Description: 'ARN of the created S3 bucket'
    Value: !GetAtt S3Bucket.Arn`;
  }

  /**
   * Get Lambda function CloudFormation template content
   */
  private getLambdaFunctionTemplate(): string {
    return `AWSTemplateFormatVersion: '2010-09-09'
Description: 'Managed Lambda function with IAM role and CloudWatch logging'

Parameters:
  FunctionName:
    Type: String
    Description: 'Name for the Lambda function'
    AllowedPattern: '^[a-zA-Z0-9-_]+$'

  Runtime:
    Type: String
    Default: 'python3.12'
    AllowedValues: ['python3.12', 'python3.11', 'nodejs20.x', 'nodejs22.x']
    Description: 'Runtime environment for the function'

  Environment:
    Type: String
    Default: 'development'
    AllowedValues: ['development', 'staging', 'production']
    Description: 'Environment for resource tagging'

Resources:
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

  LambdaFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Ref FunctionName
      Runtime: !Ref Runtime
      Handler: 'index.handler'
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          def handler(event, context):
              return {
                  'statusCode': 200,
                  'body': 'Hello from Service Catalog managed Lambda!'
              }
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

Outputs:
  FunctionName:
    Description: 'Name of the created Lambda function'
    Value: !Ref LambdaFunction
  FunctionArn:
    Description: 'ARN of the created Lambda function'
    Value: !GetAtt LambdaFunction.Arn`;
  }
}

/**
 * CDK App entry point
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const portfolioName = app.node.tryGetContext('portfolioName') || process.env.PORTFOLIO_NAME;
const s3ProductName = app.node.tryGetContext('s3ProductName') || process.env.S3_PRODUCT_NAME;
const lambdaProductName = app.node.tryGetContext('lambdaProductName') || process.env.LAMBDA_PRODUCT_NAME;
const principalArn = app.node.tryGetContext('principalArn') || process.env.PRINCIPAL_ARN;

// Create the stack
new ServiceCatalogPortfolioStack(app, 'ServiceCatalogPortfolioStack', {
  portfolioName,
  s3ProductName,
  lambdaProductName,
  principalArn,
  description: 'Service Catalog Portfolio with CloudFormation Templates - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ServiceCatalogPortfolio',
    Environment: 'Development',
    ManagedBy: 'CDK',
  },
});