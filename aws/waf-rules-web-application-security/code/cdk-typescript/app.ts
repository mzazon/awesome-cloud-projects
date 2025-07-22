#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

/**
 * Interface for WAF Security Stack properties
 */
interface WafSecurityStackProps extends cdk.StackProps {
  /**
   * Name prefix for all resources
   */
  resourcePrefix?: string;
  
  /**
   * Rate limit threshold for requests per 5 minutes
   */
  rateLimitThreshold?: number;
  
  /**
   * Countries to block (ISO 3166-1 alpha-2 codes)
   */
  blockedCountries?: string[];
  
  /**
   * IP addresses or CIDR blocks to block
   */
  blockedIpAddresses?: string[];
  
  /**
   * CloudWatch alarm threshold for blocked requests
   */
  alarmThreshold?: number;
  
  /**
   * Enable comprehensive logging
   */
  enableLogging?: boolean;
  
  /**
   * Create monitoring dashboard
   */
  createDashboard?: boolean;
}

/**
 * AWS WAF Security Stack
 * 
 * This stack implements a comprehensive web application firewall using AWS WAF v2
 * with managed rule groups, custom rules, rate limiting, geographic restrictions,
 * bot protection, and comprehensive monitoring capabilities.
 */
class WafSecurityStack extends cdk.Stack {
  public readonly webAcl: wafv2.CfnWebACL;
  public readonly ipSet: wafv2.CfnIPSet;
  public readonly regexPatternSet: wafv2.CfnRegexPatternSet;
  public readonly logGroup: logs.LogGroup;
  public readonly snsTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: WafSecurityStackProps = {}) {
    super(scope, id, props);

    // Default configuration values
    const resourcePrefix = props.resourcePrefix || 'webapp-security';
    const rateLimitThreshold = props.rateLimitThreshold || 10000;
    const blockedCountries = props.blockedCountries || ['CN', 'RU', 'KP'];
    const blockedIpAddresses = props.blockedIpAddresses || ['192.0.2.44/32', '203.0.113.0/24'];
    const alarmThreshold = props.alarmThreshold || 1000;
    const enableLogging = props.enableLogging !== false;
    const createDashboard = props.createDashboard !== false;

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);
    const wafName = `${resourcePrefix}-waf-${uniqueSuffix}`;

    // Create IP Set for blocking specific IP addresses
    this.ipSet = new wafv2.CfnIPSet(this, 'BlockedIPSet', {
      name: `blocked-ips-${uniqueSuffix}`,
      scope: 'CLOUDFRONT',
      ipAddressVersion: 'IPV4',
      addresses: blockedIpAddresses,
      description: 'IP addresses and CIDR blocks to block for security',
      tags: [
        {
          key: 'Purpose',
          value: 'WAF Security'
        },
        {
          key: 'ManagedBy',
          value: 'CDK'
        }
      ]
    });

    // Create Regex Pattern Set for detecting suspicious patterns
    this.regexPatternSet = new wafv2.CfnRegexPatternSet(this, 'SuspiciousPatterns', {
      name: `suspicious-patterns-${uniqueSuffix}`,
      scope: 'CLOUDFRONT',
      regularExpressionList: [
        // SQL Injection patterns
        '(?i)(union.*select|select.*from|insert.*into|drop.*table)',
        // XSS patterns
        '(?i)(<script|javascript:|onerror=|onload=)',
        // Directory traversal patterns
        '(?i)(\\.\\./)|(\\\\\\.\\.\\\\)',
        // Command injection patterns
        '(?i)(cmd\\.exe|powershell|/bin/bash|/bin/sh)'
      ],
      description: 'Regex patterns for detecting common attack signatures',
      tags: [
        {
          key: 'Purpose',
          value: 'WAF Security'
        },
        {
          key: 'ManagedBy',
          value: 'CDK'
        }
      ]
    });

    // Create comprehensive WAF Web ACL with multiple protection layers
    this.webAcl = new wafv2.CfnWebACL(this, 'WebACL', {
      name: wafName,
      scope: 'CLOUDFRONT',
      defaultAction: {
        allow: {}
      },
      description: 'Comprehensive WAF for web application security with managed rules, custom rules, and bot protection',
      
      rules: [
        // AWS Managed Rules - Common Rule Set (OWASP Top 10 protection)
        {
          name: 'AWSManagedRulesCommonRuleSet',
          priority: 1,
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesCommonRuleSet'
            }
          },
          overrideAction: {
            none: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'CommonRuleSetMetric'
          }
        },

        // AWS Managed Rules - Known Bad Inputs
        {
          name: 'AWSManagedRulesKnownBadInputsRuleSet',
          priority: 2,
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesKnownBadInputsRuleSet'
            }
          },
          overrideAction: {
            none: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'KnownBadInputsMetric'
          }
        },

        // AWS Managed Rules - SQL Injection Protection
        {
          name: 'AWSManagedRulesSQLiRuleSet',
          priority: 3,
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesSQLiRuleSet'
            }
          },
          overrideAction: {
            none: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'SQLiRuleSetMetric'
          }
        },

        // AWS Managed Rules - Bot Control
        {
          name: 'AWSManagedRulesBotControlRuleSet',
          priority: 4,
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesBotControlRuleSet'
            }
          },
          overrideAction: {
            none: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'BotControlMetric'
          }
        },

        // Rate Limiting Rule
        {
          name: 'RateLimitRule',
          priority: 5,
          statement: {
            rateBasedStatement: {
              limit: rateLimitThreshold,
              aggregateKeyType: 'IP'
            }
          },
          action: {
            block: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'RateLimitMetric'
          }
        },

        // Geographic Blocking Rule
        {
          name: 'BlockHighRiskCountries',
          priority: 6,
          statement: {
            geoMatchStatement: {
              countryCodes: blockedCountries
            }
          },
          action: {
            block: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'GeoBlockMetric'
          }
        },

        // IP Blocking Rule
        {
          name: 'BlockMaliciousIPs',
          priority: 7,
          statement: {
            ipSetReferenceStatement: {
              arn: this.ipSet.attrArn
            }
          },
          action: {
            block: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'IPBlockMetric'
          }
        },

        // Custom Pattern Matching Rule
        {
          name: 'BlockSuspiciousPatterns',
          priority: 8,
          statement: {
            regexPatternSetReferenceStatement: {
              arn: this.regexPatternSet.attrArn,
              fieldToMatch: {
                body: {
                  oversizeHandling: 'CONTINUE'
                }
              },
              textTransformations: [
                {
                  priority: 0,
                  type: 'URL_DECODE'
                },
                {
                  priority: 1,
                  type: 'HTML_ENTITY_DECODE'
                }
              ]
            }
          },
          action: {
            block: {}
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'SuspiciousPatternsMetric'
          }
        }
      ],

      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: `${wafName}Metric`
      },

      tags: [
        {
          key: 'Purpose',
          value: 'Web Application Security'
        },
        {
          key: 'ManagedBy',
          value: 'CDK'
        },
        {
          key: 'Environment',
          value: 'Production'
        }
      ]
    });

    // Create CloudWatch Log Group for WAF logs (if logging enabled)
    if (enableLogging) {
      this.logGroup = new logs.LogGroup(this, 'WAFLogGroup', {
        logGroupName: `/aws/wafv2/${wafName}`,
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: cdk.RemovalPolicy.DESTROY
      });

      // Enable WAF logging
      new wafv2.CfnLoggingConfiguration(this, 'WAFLoggingConfig', {
        resourceArn: this.webAcl.attrArn,
        logDestinationConfigs: [this.logGroup.logGroupArn],
        logType: 'WAF_LOGS',
        logScope: 'SECURITY_EVENTS',
        redactedFields: []
      });
    }

    // Create SNS topic for security alerts
    this.snsTopic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `waf-security-alerts-${uniqueSuffix}`,
      displayName: 'WAF Security Alerts',
      fifo: false
    });

    // Create CloudWatch alarms for security monitoring
    const blockedRequestsAlarm = new cloudwatch.Alarm(this, 'BlockedRequestsAlarm', {
      alarmName: `waf-high-blocked-requests-${uniqueSuffix}`,
      alarmDescription: 'High number of blocked requests detected - potential attack in progress',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/WAFV2',
        metricName: 'BlockedRequests',
        dimensionsMap: {
          WebACL: wafName,
          Region: this.region
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: alarmThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to the alarm
    blockedRequestsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // Create comprehensive monitoring dashboard (if enabled)
    if (createDashboard) {
      this.dashboard = new cloudwatch.Dashboard(this, 'WAFSecurityDashboard', {
        dashboardName: `WAF-Security-Dashboard-${uniqueSuffix}`,
        
        widgets: [
          // Overall request statistics
          [
            new cloudwatch.GraphWidget({
              title: 'WAF Request Statistics',
              left: [
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'AllowedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5)
                }),
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5)
                })
              ],
              width: 12,
              height: 6
            }),

            // Blocked requests by rule
            new cloudwatch.GraphWidget({
              title: 'Blocked Requests by Rule',
              left: [
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region,
                    Rule: 'CommonRuleSetMetric'
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                  label: 'Common Rules'
                }),
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region,
                    Rule: 'RateLimitMetric'
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                  label: 'Rate Limiting'
                }),
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region,
                    Rule: 'GeoBlockMetric'
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                  label: 'Geographic Blocking'
                }),
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region,
                    Rule: 'BotControlMetric'
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5),
                  label: 'Bot Control'
                })
              ],
              width: 12,
              height: 6
            })
          ],

          // Rate limiting and SQL injection metrics
          [
            new cloudwatch.GraphWidget({
              title: 'Rate Limiting Activity',
              left: [
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region,
                    Rule: 'RateLimitMetric'
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.minutes(5)
                })
              ],
              width: 8,
              height: 6
            }),

            new cloudwatch.SingleValueWidget({
              title: 'Total Blocked Requests (24h)',
              metrics: [
                new cloudwatch.Metric({
                  namespace: 'AWS/WAFV2',
                  metricName: 'BlockedRequests',
                  dimensionsMap: {
                    WebACL: wafName,
                    Region: this.region
                  },
                  statistic: 'Sum',
                  period: cdk.Duration.hours(24)
                })
              ],
              width: 4,
              height: 6
            })
          ]
        ]
      });
    }

    // Stack outputs for integration and verification
    new cdk.CfnOutput(this, 'WebACLArn', {
      value: this.webAcl.attrArn,
      description: 'ARN of the WAF Web ACL for association with CloudFront or ALB',
      exportName: `${id}-WebACLArn`
    });

    new cdk.CfnOutput(this, 'WebACLId', {
      value: this.webAcl.attrId,
      description: 'ID of the WAF Web ACL',
      exportName: `${id}-WebACLId`
    });

    new cdk.CfnOutput(this, 'IPSetArn', {
      value: this.ipSet.attrArn,
      description: 'ARN of the IP Set for dynamic IP blocking',
      exportName: `${id}-IPSetArn`
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'ARN of the SNS Topic for security alerts',
      exportName: `${id}-SNSTopicArn`
    });

    if (enableLogging) {
      new cdk.CfnOutput(this, 'LogGroupName', {
        value: this.logGroup.logGroupName,
        description: 'CloudWatch Log Group for WAF logs',
        exportName: `${id}-LogGroupName`
      });
    }

    if (createDashboard) {
      new cdk.CfnOutput(this, 'DashboardUrl', {
        value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
        description: 'URL to the CloudWatch dashboard for WAF monitoring',
        exportName: `${id}-DashboardUrl`
      });
    }
  }
}

/**
 * CDK Application Entry Point
 */
const app = new cdk.App();

// Create the WAF Security Stack with default configuration
new WafSecurityStack(app, 'WafSecurityStack', {
  description: 'Comprehensive AWS WAF implementation for web application security with managed rules, custom protection, and monitoring',
  
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1' // WAF for CloudFront must be in us-east-1
  },

  // Customizable properties - modify these based on your requirements
  resourcePrefix: 'webapp-security',
  rateLimitThreshold: 10000,
  blockedCountries: ['CN', 'RU', 'KP'], // Modify based on your business requirements
  blockedIpAddresses: ['192.0.2.44/32', '203.0.113.0/24'], // Example blocked IPs
  alarmThreshold: 1000,
  enableLogging: true,
  createDashboard: true,

  // Stack tags for resource management and cost allocation
  tags: {
    Project: 'WAF-Security',
    Environment: 'Production',
    Owner: 'SecurityTeam',
    CostCenter: 'Security',
    Compliance: 'SOC2'
  }
});

app.synth();