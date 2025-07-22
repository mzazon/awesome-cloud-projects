#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Props for the ApiSecurityStack
 */
interface ApiSecurityStackProps extends cdk.StackProps {
  /** Rate limit for requests per 5-minute window per IP */
  readonly rateLimitPerIp?: number;
  /** Countries to block (ISO 3166-1 alpha-2 codes) */
  readonly blockedCountries?: string[];
  /** Enable WAF logging to CloudWatch */
  readonly enableWafLogging?: boolean;
  /** Name prefix for resources */
  readonly resourcePrefix?: string;
}

/**
 * CDK Stack for securing API Gateway with AWS WAF
 * 
 * This stack creates:
 * - API Gateway REST API with a test endpoint
 * - AWS WAF Web ACL with rate limiting and geo-blocking rules
 * - CloudWatch Log Group for WAF logging
 * - Association between WAF and API Gateway
 */
export class ApiSecurityStack extends cdk.Stack {
  /** The API Gateway REST API */
  public readonly api: apigateway.RestApi;
  
  /** The WAF Web ACL */
  public readonly webAcl: wafv2.CfnWebACL;
  
  /** The CloudWatch Log Group for WAF logs */
  public readonly wafLogGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: ApiSecurityStackProps = {}) {
    super(scope, id, props);

    // Set default values
    const rateLimitPerIp = props.rateLimitPerIp ?? 1000;
    const blockedCountries = props.blockedCountries ?? ['CN', 'RU', 'KP'];
    const enableWafLogging = props.enableWafLogging ?? true;
    const resourcePrefix = props.resourcePrefix ?? 'api-security';

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Create CloudWatch Log Group for WAF logging
    this.wafLogGroup = new logs.LogGroup(this, 'WafLogGroup', {
      logGroupName: `/aws/waf/${resourcePrefix}-acl-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create WAF Web ACL with security rules
    this.webAcl = new wafv2.CfnWebACL(this, 'WebACL', {
      name: `${resourcePrefix}-acl-${uniqueSuffix}`,
      scope: 'REGIONAL',
      defaultAction: { allow: {} },
      description: 'Web ACL for API Gateway protection with rate limiting and geo-blocking',
      rules: [
        // Rate limiting rule - blocks IPs that exceed request threshold
        {
          name: 'RateLimitRule',
          priority: 1,
          statement: {
            rateBasedStatement: {
              limit: rateLimitPerIp,
              aggregateKeyType: 'IP',
            },
          },
          action: { block: {} },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'RateLimitRule',
          },
        },
        // Geographic blocking rule - blocks requests from specified countries
        {
          name: 'GeoBlockRule',
          priority: 2,
          statement: {
            geoMatchStatement: {
              countryCodes: blockedCountries,
            },
          },
          action: { block: {} },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'GeoBlockRule',
          },
        },
      ],
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: `${resourcePrefix}-web-acl`,
      },
    });

    // Create API Gateway REST API
    this.api = new apigateway.RestApi(this, 'ProtectedApi', {
      restApiName: `${resourcePrefix}-api-${uniqueSuffix}`,
      description: 'REST API protected by AWS WAF',
      deployOptions: {
        stageName: 'prod',
        throttlingRateLimit: 1000,
        throttlingBurstLimit: 2000,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
      // Disable CloudWatch role creation (managed separately)
      cloudWatchRole: false,
      // Enable CORS for web applications
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'Authorization'],
      },
    });

    // Create a test resource and method
    const testResource = this.api.root.addResource('test');
    testResource.addMethod('GET', new apigateway.MockIntegration({
      integrationResponses: [{
        statusCode: '200',
        responseTemplates: {
          'application/json': JSON.stringify({
            message: 'Hello from protected API!',
            timestamp: '$context.requestTime',
            requestId: '$context.requestId',
          }),
        },
      }],
      requestTemplates: {
        'application/json': '{"statusCode": 200}',
      },
    }), {
      methodResponses: [{
        statusCode: '200',
        responseModels: {
          'application/json': apigateway.Model.EMPTY_MODEL,
        },
      }],
    });

    // Associate WAF Web ACL with API Gateway stage
    new wafv2.CfnWebACLAssociation(this, 'WebACLAssociation', {
      resourceArn: this.api.deploymentStage.stageArn,
      webAclArn: this.webAcl.attrArn,
    });

    // Configure WAF logging if enabled
    if (enableWafLogging) {
      // Create IAM role for WAF logging
      const wafLoggingRole = new iam.Role(this, 'WafLoggingRole', {
        assumedBy: new iam.ServicePrincipal('wafv2.amazonaws.com'),
        inlinePolicies: {
          WafLoggingPolicy: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  'logs:CreateLogGroup',
                  'logs:CreateLogStream',
                  'logs:PutLogEvents',
                ],
                resources: [this.wafLogGroup.logGroupArn],
              }),
            ],
          }),
        },
      });

      // Enable WAF logging to CloudWatch
      new wafv2.CfnLoggingConfiguration(this, 'WafLoggingConfiguration', {
        resourceArn: this.webAcl.attrArn,
        logDestinationConfigs: [this.wafLogGroup.logGroupArn],
        // Optional: Filter log records to reduce volume and costs
        loggingFilter: {
          defaultBehavior: 'KEEP',
          filters: [
            {
              behavior: 'KEEP',
              conditions: [
                {
                  actionCondition: {
                    action: 'BLOCK',
                  },
                },
              ],
              requirement: 'MEETS_ANY',
            },
          ],
        },
      });
    }

    // CloudFormation outputs for easy access to key resources
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'ApiTestEndpoint', {
      value: `${this.api.url}test`,
      description: 'Test endpoint URL for validation',
      exportName: `${this.stackName}-ApiTestEndpoint`,
    });

    new cdk.CfnOutput(this, 'WebACLId', {
      value: this.webAcl.attrId,
      description: 'WAF Web ACL ID',
      exportName: `${this.stackName}-WebACLId`,
    });

    new cdk.CfnOutput(this, 'WebACLArn', {
      value: this.webAcl.attrArn,
      description: 'WAF Web ACL ARN',
      exportName: `${this.stackName}-WebACLArn`,
    });

    new cdk.CfnOutput(this, 'WafLogGroupName', {
      value: this.wafLogGroup.logGroupName,
      description: 'CloudWatch Log Group for WAF logs',
      exportName: `${this.stackName}-WafLogGroupName`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ApiSecurity');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CreatedBy', 'CDK');
  }
}

// CDK App
const app = new cdk.App();

// Create the stack with customizable properties
new ApiSecurityStack(app, 'ApiSecurityStack', {
  description: 'AWS CDK Stack for securing API Gateway with WAF (Recipe: api-access-waf-gateway)',
  
  // Customize these values as needed
  rateLimitPerIp: 1000,           // Requests per 5-minute window per IP
  blockedCountries: ['CN', 'RU', 'KP'], // Countries to block (ISO codes)
  enableWafLogging: true,         // Enable detailed WAF logging
  resourcePrefix: 'api-security', // Prefix for resource names
  
  // Standard stack properties
  env: {
    // Specify account and region if needed
    // account: process.env.CDK_DEFAULT_ACCOUNT,
    // region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Enable termination protection for production deployments
  terminationProtection: false,
});

// Synthesize the stack
app.synth();