# AWS re:Post Private Setup Guide for ${organization_name}

This guide provides step-by-step instructions for setting up AWS re:Post Private for your organization's community knowledge base, integrated with the SNS notification system deployed via Terraform.

## Prerequisites Verification

### 1. Enterprise Support Plan
- ✅ Verify your AWS account has Enterprise Support or Enterprise On-Ramp
- ❌ If not available, contact your AWS account team to upgrade your support plan
- 📞 re:Post Private is included at no additional cost with Enterprise Support plans

### 2. Administrative Access
- ✅ Ensure you have administrative access to AWS Console
- ✅ Verify IAM Identity Center access (if using SSO) or appropriate IAM permissions
- ✅ Confirm access to AWS Organizations (if applicable)

## SNS Integration Information

Your Terraform deployment has created the following SNS infrastructure:

- **SNS Topic ARN**: `${sns_topic_arn}`
- **SNS Topic Name**: `${sns_topic_name}`
- **AWS Region**: `${aws_region}`
- **AWS Account**: `${aws_account_id}`
- **Project**: `${project_name}-${environment}`

## re:Post Private Setup Steps

### Step 1: Access re:Post Private Console

1. Navigate to the AWS re:Post Private console:
   ```
   https://console.aws.amazon.com/repost-private/
   ```

2. Sign in using your AWS credentials or IAM Identity Center

3. If this is your first time accessing re:Post Private, you'll see the initial setup wizard

### Step 2: Initial Configuration

#### Organization Branding
- **Organization Title**: Set to "${organization_name} Knowledge Base"
- **Welcome Message**: Customize with your organization's knowledge sharing goals
- **Logo Upload**: Upload your company logo (max 2 MiB, recommended 150x50px)
- **Color Scheme**: Set primary and button colors to match your brand

#### Content Management Settings
- **Custom Tags**: Create tags for your internal projects and teams
- **Custom Topics**: Define knowledge areas relevant to your AWS usage
- **Blocked Terminology**: Configure any compliance-required content filtering

### Step 3: Knowledge Area Selection

Select AWS service topics that align with your organization's cloud usage:

**Recommended Selections for Enterprise Teams:**
- ✅ Amazon EC2 and compute services
- ✅ Amazon S3 and storage services  
- ✅ AWS Lambda and serverless
- ✅ Amazon RDS and database services
- ✅ AWS IAM and security
- ✅ Amazon VPC and networking
- ✅ AWS CloudFormation and infrastructure as code
- ✅ Amazon CloudWatch and monitoring

**Optional Based on Your Stack:**
- Amazon EKS (if using Kubernetes)
- Amazon ECS (if using containers)
- AWS Step Functions (if using workflow orchestration)
- Amazon API Gateway (if building APIs)
- AWS Glue (if doing data processing)

### Step 4: User Access and Permissions

#### Invite Team Members
1. Navigate to "User Management" in re:Post Private console
2. Add team member email addresses
3. Assign appropriate roles:
   - **Admin**: Full access to configuration and moderation
   - **Moderator**: Can review and moderate content
   - **Member**: Can ask questions, provide answers, and participate in discussions

#### Access Control
- Configure which users can create articles vs. ask questions
- Set up approval workflows for public content (if needed)
- Define who can access different knowledge areas or topics

### Step 5: Integration with SNS Notifications

Currently, re:Post Private doesn't have direct API integration for triggering SNS notifications. However, you can implement the following workflows:

#### Manual Notification Workflow
When valuable discussions or solutions emerge in re:Post Private:

1. Copy the relevant content or discussion link
2. Use the AWS CLI to send notifications:
   ```bash
   aws sns publish \
       --topic-arn ${sns_topic_arn} \
       --subject "Knowledge Update: [Topic]" \
       --message "New valuable discussion in re:Post Private: [URL and summary]"
   ```

#### Scheduled Summary Workflow
Set up a periodic summary of re:Post Private activity:

1. Export or review weekly/monthly activity from re:Post Private
2. Create summary notifications highlighting:
   - Top questions and answers
   - New knowledge articles
   - Most active contributors
   - Trending topics

### Step 6: Content Creation Strategy

#### Initial Content Plan
Create foundational articles to encourage participation:

1. **Getting Started Articles**
   - "Welcome to ${organization_name} AWS Knowledge Base"
   - "How to Use This Knowledge Platform"
   - "Escalation Procedures and Support Contacts"

2. **Technical Foundation**
   - "Our AWS Account Structure and Access Patterns"
   - "Standard Architectures and Approved Services"
   - "Security Best Practices for Our Environment"

3. **Process Documentation**
   - "Code Review and Deployment Procedures"
   - "Incident Response and Troubleshooting"
   - "Resource Tagging and Cost Management Standards"

#### Ongoing Content Strategy
- Weekly highlights of interesting AWS discussions
- Monthly deep-dives on specific services or architectures
- Quarterly reviews of lessons learned and knowledge gaps
- Annual assessment of knowledge base effectiveness

## Testing and Validation

### Test SNS Integration
Send a test notification to verify the integration:

```bash
aws sns publish \
    --topic-arn ${sns_topic_arn} \
    --subject "Knowledge Base Test: re:Post Private Setup Complete" \
    --message "re:Post Private has been successfully configured for ${organization_name}. Team members can now access the knowledge base and begin sharing AWS expertise."
```

### Validate re:Post Private Access
1. ✅ Confirm all team members can access re:Post Private
2. ✅ Test creating a sample question and answer
3. ✅ Verify search functionality works across curated and private content
4. ✅ Check that AWS expert content appears in relevant sections

## Governance and Maintenance

### Content Moderation
- Establish clear guidelines for appropriate content
- Define processes for reviewing and promoting valuable discussions
- Set up regular content audits to remove outdated information

### Knowledge Harvesting
- Weekly reviews to identify valuable discussions
- Convert ephemeral discussions to permanent articles
- Tag and categorize content for better discoverability

### Performance Monitoring
- Track participation rates and content creation
- Monitor question response times and solution quality
- Measure knowledge base effectiveness through user feedback

## Troubleshooting

### Common Issues

**"re:Post Private not available"**
- Verify Enterprise Support plan is active
- Check AWS account status and region availability
- Contact AWS Support if the service doesn't appear

**"Cannot invite team members"**
- Verify administrative permissions in re:Post Private
- Check email addresses for typos
- Ensure team members have AWS account access

**"SNS notifications not received"**
- Confirm email subscriptions are confirmed (check spam folders)
- Test SNS topic with AWS CLI
- Verify SNS topic permissions and policies

### Support Resources
- AWS re:Post Private documentation: https://docs.aws.amazon.com/repostprivate/
- AWS Support (available with Enterprise Support plan)
- Internal documentation for ${project_name} project
- Team knowledge sharing channels

## Success Metrics

Track these metrics to measure knowledge base effectiveness:

- Number of active users per month
- Questions asked and answered per week
- Average time to receive answers
- Content creation rate (articles, discussions)
- User satisfaction scores
- Knowledge gap identification and resolution

---

Generated by Terraform for ${project_name} deployment in ${environment} environment.
Last updated: $(date)