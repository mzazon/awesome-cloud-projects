import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { UptimeMonitoringStack } from '../lib/uptime-monitoring-stack';

describe('UptimeMonitoringStack', () => {
  let app: cdk.App;
  let stack: UptimeMonitoringStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new UptimeMonitoringStack(app, 'TestStack', {
      websiteUrl: 'https://example.com',
      adminEmail: 'test@example.com',
      environment: 'Test',
    });
    template = Template.fromStack(stack);
  });

  test('Creates SNS Topic with correct properties', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Website Uptime Alerts for example.com',
    });
  });

  test('Creates SNS Subscription for email', () => {
    template.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'email',
      Endpoint: 'test@example.com',
    });
  });

  test('Creates Route53 Health Check', () => {
    template.hasResourceProperties('AWS::Route53::HealthCheck', {
      HealthCheckConfig: {
        Type: 'HTTPS',
        FullyQualifiedDomainName: 'example.com',
        Port: 443,
        ResourcePath: '/',
        RequestInterval: 30,
        FailureThreshold: 3,
        EnableSNI: true,
      },
    });
  });

  test('Creates CloudWatch Alarms', () => {
    // Test website down alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'HealthCheckStatus',
      Namespace: 'AWS/Route53',
      Statistic: 'Minimum',
      Threshold: 1,
      ComparisonOperator: 'LessThanThreshold',
      EvaluationPeriods: 1,
    });

    // Test website recovered alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'HealthCheckStatus',
      Namespace: 'AWS/Route53',
      Statistic: 'Minimum',
      Threshold: 1,
      ComparisonOperator: 'GreaterThanOrEqualToThreshold',
      EvaluationPeriods: 2,
    });
  });

  test('Creates correct number of resources', () => {
    template.resourceCountIs('AWS::SNS::Topic', 1);
    template.resourceCountIs('AWS::SNS::Subscription', 1);
    template.resourceCountIs('AWS::Route53::HealthCheck', 1);
    template.resourceCountIs('AWS::CloudWatch::Alarm', 2);
  });

  test('Stack outputs are created', () => {
    const outputs = template.findOutputs('*');
    expect(Object.keys(outputs)).toContain('WebsiteUrl');
    expect(Object.keys(outputs)).toContain('AdminEmail');
    expect(Object.keys(outputs)).toContain('SnsTopicArn');
    expect(Object.keys(outputs)).toContain('HealthCheckId');
  });

  test('Proper tags are applied', () => {
    // Check that health check has tags - just verify they exist with correct keys
    const healthCheckResources = template.findResources('AWS::Route53::HealthCheck');
    const healthCheckResource = Object.values(healthCheckResources)[0] as any;
    
    const tags = healthCheckResource.Properties.HealthCheckTags;
    expect(tags).toBeDefined();
    expect(tags.length).toBe(4);
    
    const tagKeys = tags.map((tag: any) => tag.Key);
    expect(tagKeys).toContain('Name');
    expect(tagKeys).toContain('Website');
    expect(tagKeys).toContain('Purpose');
    expect(tagKeys).toContain('Environment');
    
    // Check specific values
    const websiteTag = tags.find((tag: any) => tag.Key === 'Website');
    expect(websiteTag.Value).toBe('https://example.com');
    
    const purposeTag = tags.find((tag: any) => tag.Key === 'Purpose');
    expect(purposeTag.Value).toBe('UptimeMonitoring');
  });

  test('HTTP website creates correct health check', () => {
    const httpApp = new cdk.App();
    const httpStack = new UptimeMonitoringStack(httpApp, 'HttpTestStack', {
      websiteUrl: 'http://example.com',
      adminEmail: 'test@example.com',
      environment: 'Test',
    });
    
    const httpTemplate = Template.fromStack(httpStack);
    
    httpTemplate.hasResourceProperties('AWS::Route53::HealthCheck', {
      HealthCheckConfig: {
        Type: 'HTTP',
        FullyQualifiedDomainName: 'example.com',
        Port: 80,
        EnableSNI: false,
      },
    });
  });

  test('Custom port website creates correct health check', () => {
    const customPortApp = new cdk.App();
    const customPortStack = new UptimeMonitoringStack(customPortApp, 'CustomPortTestStack', {
      websiteUrl: 'https://example.com:8443/health',
      adminEmail: 'test@example.com',
      environment: 'Test',
    });
    
    const customPortTemplate = Template.fromStack(customPortStack);
    
    customPortTemplate.hasResourceProperties('AWS::Route53::HealthCheck', {
      HealthCheckConfig: {
        Type: 'HTTPS',
        FullyQualifiedDomainName: 'example.com',
        Port: 8443,
        ResourcePath: '/health',
      },
    });
  });

  test('Validates required parameters', () => {
    const invalidApp = new cdk.App();
    expect(() => {
      new UptimeMonitoringStack(invalidApp, 'InvalidStack', {
        websiteUrl: '',
        adminEmail: 'test@example.com',
        environment: 'Test',
      });
    }).toThrow();
  });
});