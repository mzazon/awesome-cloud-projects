#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Properties for the WAF Rate Limiting Stack
 */
interface WafRateLimitingStackProps extends cdk.StackProps {
  /**
   * The rate limit threshold for requests per 5-minute window
   * @default 2000
   */
  readonly rateLimitThreshold?: number;

  /**
   * Whether to enable detailed CloudWatch logging
   * @default true
   */
  readonly enableDetailedLogging?: boolean;

  /**
   * Whether to create a CloudWatch dashboard
   * @default true
   */
  readonly createDashboard?: boolean;

  /**
   * Log retention period in days
   * @default 30
   */
  readonly logRetentionDays?: logs.RetentionDays;
}

/**
 * CDK Stack implementing AWS WAF with rate limiting rules for DDoS protection
 * 
 * This stack creates:
 * - AWS WAF Web ACL with rate limiting and IP reputation rules
 * - CloudWatch log group for WAF logs
 * - CloudWatch dashboard for monitoring
 * - Proper IAM roles and permissions
 */
export class WafRateLimitingStack extends cdk.Stack {
  /**
   * The WAF Web ACL created by this stack
   */
  public readonly webAcl: wafv2.CfnWebACL;

  /**
   * The CloudWatch log group for WAF logs
   */
  public readonly logGroup: logs.LogGroup;

  /**
   * The CloudWatch dashboard for monitoring (if enabled)
   */
  public readonly dashboard?: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: WafRateLimitingStackProps = {}) {
    super(scope, id, props);

    // Default values for configuration
    const rateLimitThreshold = props.rateLimitThreshold ?? 2000;
    const enableDetailedLogging = props.enableDetailedLogging ?? true;
    const createDashboard = props.createDashboard ?? true;
    const logRetentionDays = props.logRetentionDays ?? logs.RetentionDays.ONE_MONTH;

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Create CloudWatch log group for WAF logs
    this.logGroup = new logs.LogGroup(this, 'WafSecurityLogs', {
      logGroupName: '/aws/wafv2/security-logs',
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create the rate limiting rule
    const rateLimitRule: wafv2.CfnWebACL.RuleProperty = {
      name: `rate-limit-rule-${uniqueSuffix}`,
      priority: 1,
      statement: {
        rateBasedStatement: {
          limit: rateLimitThreshold,
          aggregateKeyType: 'IP',
        },
      },
      action: {
        block: {},
      },
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: 'RateLimitRule',
      },
    };

    // Create the IP reputation rule using AWS managed rule group
    const ipReputationRule: wafv2.CfnWebACL.RuleProperty = {
      name: `ip-reputation-rule-${uniqueSuffix}`,
      priority: 2,
      statement: {
        managedRuleGroupStatement: {
          vendorName: 'AWS',
          name: 'AWSManagedRulesAmazonIpReputationList',
        },
      },
      action: {
        block: {},
      },
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: 'IPReputationRule',
      },
      overrideAction: {
        none: {},
      },
    };

    // Create the WAF Web ACL with both rules
    this.webAcl = new wafv2.CfnWebACL(this, 'WebApplicationFirewall', {
      name: `waf-protection-${uniqueSuffix}`,
      scope: 'CLOUDFRONT',
      defaultAction: {
        allow: {},
      },
      description: 'Web ACL for rate limiting and security protection with DDoS mitigation',
      rules: [rateLimitRule, ipReputationRule],
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: 'WebACL',
      },
      tags: [
        {
          key: 'Purpose',
          value: 'DDoS Protection and Rate Limiting',
        },
        {
          key: 'Environment',
          value: 'Security',
        },
        {
          key: 'CreatedBy',
          value: 'CDK',
        },
      ],
    });

    // Configure logging for the Web ACL if detailed logging is enabled
    if (enableDetailedLogging) {
      const loggingConfiguration = new wafv2.CfnLoggingConfiguration(this, 'WafLoggingConfig', {
        resourceArn: this.webAcl.attrArn,
        logDestinationConfigs: [this.logGroup.logGroupArn],
        redactedFields: [
          {
            singleHeader: {
              name: 'authorization',
            },
          },
          {
            singleHeader: {
              name: 'cookie',
            },
          },
        ],
      });

      // Ensure the Web ACL is created before the logging configuration
      loggingConfiguration.addDependency(this.webAcl);
    }

    // Create CloudWatch dashboard for monitoring if enabled
    if (createDashboard) {
      this.dashboard = new cloudwatch.Dashboard(this, 'WafSecurityDashboard', {
        dashboardName: `WAF-Security-Dashboard-${uniqueSuffix}`,
        widgets: [
          [
            // Allowed vs Blocked Requests Widget
            new cloudwatch.GraphWidget({
              title: 'WAF Allowed vs Blocked Requests',
              width: 12,
              height: 6,
              left: [
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'AllowedRequests',
                  dimensionsMap: {
                    WebACL: this.webAcl.name!,
                    Region: 'CloudFront',
                    Rule: 'ALL',
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: this.webAcl.name!,
                    Region: 'CloudFront',
                    Rule: 'ALL',
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
              ],
            }),
            // Blocked Requests by Rule Widget
            new cloudwatch.GraphWidget({
              title: 'Blocked Requests by Rule',
              width: 12,
              height: 6,
              left: [
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: this.webAcl.name!,
                    Region: 'CloudFront',
                    Rule: rateLimitRule.name,
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                  label: 'Rate Limit Rule',
                }),
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: this.webAcl.name!,
                    Region: 'CloudFront',
                    Rule: ipReputationRule.name,
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                  label: 'IP Reputation Rule',
                }),
              ],
            }),
          ],
          [
            // Rate Limit Threshold Monitoring
            new cloudwatch.SingleValueWidget({
              title: 'Current Rate Limit Threshold',
              width: 6,
              height: 3,
              metrics: [
                new cloudwatch.MathExpression({
                  expression: `${rateLimitThreshold}`,
                  label: 'Requests per 5 minutes',
                }),
              ],
            }),
            // Log Group Metrics
            new cloudwatch.GraphWidget({
              title: 'WAF Log Events',
              width: 18,
              height: 6,
              left: [
                this.logGroup.metricIncomingLogEvents({
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                }),
              ],
            }),
          ],
        ],
      });
    }

    // Output important resource information
    new cdk.CfnOutput(this, 'WebACLArn', {
      description: 'ARN of the created WAF Web ACL',
      value: this.webAcl.attrArn,
      exportName: `${id}-WebACLArn`,
    });

    new cdk.CfnOutput(this, 'WebACLId', {
      description: 'ID of the created WAF Web ACL',
      value: this.webAcl.attrId,
      exportName: `${id}-WebACLId`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      description: 'Name of the CloudWatch log group for WAF logs',
      value: this.logGroup.logGroupName,
      exportName: `${id}-LogGroupName`,
    });

    new cdk.CfnOutput(this, 'LogGroupArn', {
      description: 'ARN of the CloudWatch log group for WAF logs',
      value: this.logGroup.logGroupArn,
      exportName: `${id}-LogGroupArn`,
    });

    if (this.dashboard) {
      new cdk.CfnOutput(this, 'DashboardUrl', {
        description: 'URL of the CloudWatch dashboard for WAF monitoring',
        value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
        exportName: `${id}-DashboardUrl`,
      });
    }

    new cdk.CfnOutput(this, 'RateLimitThreshold', {
      description: 'Configured rate limit threshold (requests per 5 minutes)',
      value: rateLimitThreshold.toString(),
      exportName: `${id}-RateLimitThreshold`,
    });

    // Add deployment instructions as outputs
    new cdk.CfnOutput(this, 'NextSteps', {
      description: 'Next steps for WAF deployment',
      value: 'Associate this Web ACL with your CloudFront distribution or Application Load Balancer using the AWS Console or CLI',
    });

    new cdk.CfnOutput(this, 'CloudFrontAssociationCommand', {
      description: 'AWS CLI command to associate with CloudFront (replace DISTRIBUTION_ID)',
      value: `aws cloudfront update-distribution --id DISTRIBUTION_ID --distribution-config '{"WebACLId":"${this.webAcl.attrArn}"}'`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the WAF Rate Limiting Stack
new WafRateLimitingStack(app, 'WafRateLimitingStack', {
  description: 'AWS WAF with rate limiting rules for DDoS protection and application security',
  
  // Configure stack properties
  env: {
    // CloudFront/WAF Global resources must be deployed to us-east-1
    region: 'us-east-1',
    // account: process.env.CDK_DEFAULT_ACCOUNT,
  },

  // Customize WAF configuration through context or props
  rateLimitThreshold: app.node.tryGetContext('rateLimitThreshold') || 2000,
  enableDetailedLogging: app.node.tryGetContext('enableDetailedLogging') !== false,
  createDashboard: app.node.tryGetContext('createDashboard') !== false,
  logRetentionDays: logs.RetentionDays.ONE_MONTH,

  // Add stack tags for resource management
  tags: {
    Project: 'WAF-Rate-Limiting',
    Environment: 'Production',
    Owner: 'Security-Team',
    CostCenter: 'Security',
    Purpose: 'DDoS-Protection',
  },
});

// Add application-level tags
cdk.Tags.of(app).add('Application', 'WAF-Rate-Limiting');
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'recipes');