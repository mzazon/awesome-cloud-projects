![Cloud Projects](.publish/docs/og-image.png?raw=true "Cloud Projects")

[![Total projects](https://img.shields.io/badge/Total_Projects-1103-blue)](https://github.com/mzazon/cloud-projects)
[![AWS projects](https://img.shields.io/badge/AWS-492-orange)](https://github.com/mzazon/cloud-projects/tree/main/aws)
[![Azure projects](https://img.shields.io/badge/Azure-268-0078d4)](https://github.com/mzazon/cloud-projects/tree/main/azure)
[![GCP projects](https://img.shields.io/badge/GCP-350-DB4437)](https://github.com/mzazon/cloud-projects/tree/main/gcp)
[![GitHub stars](https://img.shields.io/github/stars/mzazon/cloud-projects.svg?style=social&label=Star)](https://github.com/mzazon/cloud-projects)
[![GitHub forks](https://img.shields.io/github/forks/mzazon/cloud-projects.svg?style=social&label=Fork)](https://github.com/mzazon/cloud-projects/fork)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## CloudProjects.dev

NEW (beta!): use our FREE site at [https://cloudprojects.dev/](https://cloudprojects.dev/) to search, sort, filter, group and discover cloud projects. no login, all local storage. Feedback is welcome!

## Introduction

Level up your cloud knowledge and experience with 1100+ cloud rojects in this repository. Get something to talk about during your next interview, see how cloud services are used together, and learn in depth by getting hands on. Real solutions from real professionals and organizations.

_A collection of cloud architecture recipes, tutorials, and real-world solutions across Amazon Web Services (AWS), Microsoft Azure, and Google Cloud Platform (GCP)._

Each and every project brings together a few cloud services to build a working scenario. Each contains a problem/solution format, diagram, command line steps to accomplish the solution, a short discussion section, and (*IMPORTANT!*) cleanup steps, to ensure you do not incur runaway costs. As a bonus, all popular formats of infrastructure as code that you can take, deploy, and customize to your liking (Terraform, CloudFormation, AWS CDK (typescript and python both), Azure Bicep, and even Bash shell scripts that run a cloud provider CLI commands.

> TIP: We recommend that you use your cloud providers "Cloud Shell" to run these commands to get learning quickly! Just make sure to set up budget alerts with your chosen provider.

The format of these recipes has been inspired by [AWS Cookbook, by O'Reilly Media](https://www.oreilly.com/library/view/aws-cookbook/9781492092599/). As a co-author of this book, my readers' feedback about the format and approach was overwhealmingly positive with many readers using this content to gain experience they can talk about during job interviews. So I brought the format to this batch of content to help readers build cloud skills across the top 3 public cloud providers using real-world scenarios.

> NOTE: These all use the cloud provider CLI (Command Line Interfaces) rather than GUI (browser consoles). One of the first things you should learn about cloud providers is that their interfaces are just APIs that perform actions on infrastructure. Because of that, it is important to understand the parameters that go into API requests to services! The CLI is the perfect way to learn this. Dust off your terminal window or preferred cloud shell and enjoy!

## 📊 Project Statistics

- **Total Projects**: 1110+- **AWS Projects**: 492- **AZURE Projects**: 268- **GCP Projects**: 350- **Categories**: 12
- **Average Difficulty**: 235.5/400

### 🏆 Most Used Services
- **Lambda**: 217 recipes- **Cloudwatch**: 185 recipes- **Cloud Functions**: 185 recipes- **S3**: 168 recipes- **Iam**: 137 recipes
## 📚 Table of Contents

- [🖥️ Compute & Infrastructure](#compute--infrastructure) (287 projects)
- [🗄️ Storage & Data Management](#storage--data-management) (53 projects)
- [🛢️ Databases & Analytics](#databases--analytics) (203 projects)
- [🌐 Networking & Content Delivery](#networking--content-delivery) (77 projects)
- [🔐 Security & Identity](#security--identity) (108 projects)
- [🤖 AI & Machine Learning](#ai--machine-learning) (126 projects)
- [🛠️ Application Development & Deployment](#application-development--deployment) (106 projects)
- [📊 Monitoring & Management](#monitoring--management) (77 projects)
- [🔗 Integration & Messaging](#integration--messaging) (24 projects)
- [📱 IoT & Edge Computing](#iot--edge-computing) (27 projects)
- [🎬 Media & Content](#media--content) (17 projects)
- [🏢 Specialized Solutions](#specialized-solutions) (5 projects)

---

## 🖥️ Compute & Infrastructure

*Virtual machines, containers, serverless computing, and basic infrastructure components*

- **[Advanced API Gateway Deployment Strategies](aws/advanced-api-deployment-strategies/advanced-api-deployment-strategies.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: API Gateway, Lambda, CloudWatch, Route 53* • ⏱️ 180 minutes
- **[Age Calculator API with Cloud Run and Storage](gcp/age-calculator-api-run-storage/age-calculator-api-run-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Cloud Storage* • ⏱️ 20 minutes
- **[AI Assistant with Custom Functions using OpenAI and Functions](azure/ai-assistant-custom-functions-openai-functions/ai-assistant-custom-functions-openai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI, Azure Functions, Azure Storage* • ⏱️ 45 minutes
- **[AI Code Review Assistant with Reasoning and Functions](azure/ai-code-review-assistant-reasoning-functions/ai-code-review-assistant-reasoning-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI, Azure Functions, Blob Storage* • ⏱️ 45 minutes
- **[AI Training Optimization with Dynamic Workload Scheduler and Batch](gcp/ai-training-optimization-scheduler-batch/ai-training-optimization-scheduler-batch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Dynamic Workload Scheduler, Cloud Batch, Cloud Monitoring* • ⏱️ 45 minutes
- **[AI-Powered Document Processing Automation with OpenAI Assistants](azure/ai-powered-document-processing-automation/ai-powered-document-processing-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Azure Container Apps Jobs, Azure Service Bus, Azure Monitor* • ⏱️ 120 minutes
- **[AI-Powered Email Marketing Campaigns with OpenAI and Logic Apps](azure/ai-email-marketing-openai-logic-apps/ai-email-marketing-openai-logic-apps.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI, Logic Apps, Communication Services* • ⏱️ 45 minutes
- **[AI-Powered Infrastructure Code Generation](aws/ai-infrastructure-code-generation/ai-infrastructure-code-generation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Q Developer, AWS Infrastructure Composer, AWS Lambda, Amazon S3* • ⏱️ 120 minutes
- **[Amplify Mobile Backend with Authentication and APIs](aws/amplify-mobile-backend/amplify-mobile-backend.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amplify, appsync, cognito, dynamodb* • ⏱️ 120 minutes
- **[API Composition with Step Functions](aws/api-composition-step-functions/api-composition-step-functions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Step Functions, API Gateway, Lambda, DynamoDB* • ⏱️ 180 minutes
- **[API Middleware with Cloud Run MCP Servers and Service Extensions](gcp/api-middleware-cloud-run-mcp-servers-service-extensions/api-middleware-cloud-run-mcp-servers-service-extensions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Service Extensions, Cloud Endpoints, Vertex AI* • ⏱️ 120 minutes
- **[API Rate Limiting and Analytics with Cloud Run and Firestore](gcp/api-rate-limiting-analytics-run-firestore/api-rate-limiting-analytics-run-firestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Firestore, Cloud Monitoring* • ⏱️ 45 minutes
- **[API Throttling and Rate Limiting with API Gateway and Lambda](aws/api-throttling-rate-limiting/api-throttling-rate-limiting.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: API Gateway, CloudWatch, Lambda, IAM* • ⏱️ 60 minutes
- **[Application Modernization with App2Container](aws/application-modernization-app2container/application-modernization-app2container.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: App2Container, ECS, EKS, ECR* • ⏱️ 240 minutes
- **[Architecting Global EKS Resilience with Cross-Region Networking](aws/architecting-global-eks-resilience/architecting-global-eks-resilience.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EKS, Transit Gateway, Route 53, VPC Lattice* • ⏱️ 240 minutes
- **[ARM-based Workloads with Graviton Processors](aws/arm-graviton-workloads/arm-graviton-workloads.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2, CloudWatch, Auto Scaling, Application Load Balancer* • ⏱️ 180 minutes
- **[Asynchronous API Patterns with SQS](aws/async-api-patterns-gateway-sqs/async-api-patterns-gateway-sqs.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: API Gateway, SQS, Lambda, DynamoDB* • ⏱️ 180 minutes
- **[Asynchronous File Processing Workflows with Cloud Tasks and Cloud Storage](gcp/asynchronous-file-processing-cloud-tasks-storage/asynchronous-file-processing-cloud-tasks-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Tasks, Cloud Storage, Cloud Run, Cloud Pub/Sub* • ⏱️ 120 minutes
- **[Automated API Testing with Gemini and Functions](gcp/automated-api-testing-gemini-functions/automated-api-testing-gemini-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Run, Cloud Storage* • ⏱️ 45 minutes
- **[Automated Audio Summarization with OpenAI and Functions](azure/automated-audio-summarization-openai-functions/automated-audio-summarization-openai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure OpenAI, Blob Storage* • ⏱️ 45 minutes
- **[Automated Content Generation with Prompt Flow and OpenAI](azure/automated-content-generation-prompt-flow-openai/automated-content-generation-prompt-flow-openai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Prompt Flow, Azure OpenAI Service, Azure Functions* • ⏱️ 45 minutes
- **[Automated Data Analysis with Bedrock AgentCore Runtime](aws/automated-data-analysis-bedrock-agentcore/automated-data-analysis-bedrock-agentcore.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock AgentCore, Lambda, S3, CloudWatch* • ⏱️ 50 minutes
- **[Automated Event Creation with Apps Script and Calendar API](gcp/automated-event-creation-apps-script-calendar/automated-event-creation-apps-script-calendar.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Apps Script, Calendar API* • ⏱️ 15 minutes
- **[Automated Infrastructure Documentation using Asset Inventory and Cloud Functions](gcp/automated-infrastructure-documentation-asset-inventory-functions/automated-infrastructure-documentation-asset-inventory-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Asset Inventory, Cloud Functions, Cloud Storage* • ⏱️ 30 minutes
- **[Automated Processing with S3 Event Triggers](aws/s3-event-processing/s3-event-processing.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, lambda, sqs, sns* • ⏱️ 120 minutes
- **[Automated Report Generation with EventBridge Scheduler](aws/automated-report-generation-eventbridge/automated-report-generation-eventbridge.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EventBridge Scheduler, S3, Lambda, SES* • ⏱️ 60 minutes
- **[Automatic Image Resizing with Cloud Functions and Storage](gcp/image-resizing-functions-storage/image-resizing-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Automating Email Processing with SES and Lambda](aws/automating-email-processing-ses/automating-email-processing-ses.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ses, lambda, s3, sns* • ⏱️ 120 minutes
- **[Automating Text Analysis Pipelines with Amazon Comprehend](aws/automating-text-analysis-pipelines/automating-text-analysis-pipelines.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: comprehend, s3, lambda, iam* • ⏱️ 120 minutes
- **[Background Task Processing with Cloud Run Worker Pools](gcp/background-task-processing-worker-pools-pubsub/background-task-processing-worker-pools-pubsub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Pub/Sub, Cloud Storage* • ⏱️ 25 minutes
- **[Base64 Encoder Decoder with Cloud Functions](gcp/base64-encoder-decoder-functions/base64-encoder-decoder-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Basic Application Logging with Cloud Functions](gcp/basic-application-logging-functions/basic-application-logging-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Logging* • ⏱️ 15 minutes
- **[Basic Push Notifications with Notification Hubs](azure/basic-push-notifications-hubs/basic-push-notifications-hubs.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Notification Hubs, Resource Groups* • ⏱️ 15 minutes
- **[Basic Web App Monitoring with App Service and Azure Monitor](azure/basic-web-monitoring-app-service-monitor/basic-web-monitoring-app-service-monitor.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: App Service, Azure Monitor* • ⏱️ 20 minutes
- **[Batch Processing Workloads with AWS Batch](aws/batch-processing-aws-batch/batch-processing-aws-batch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Batch, EC2, ECR, CloudWatch* • ⏱️ 150 minutes
- **[Blue-Green Deployments for ECS Applications](aws/blue-green-deployments-ecs/blue-green-deployments-ecs.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECS, ALB, CodeDeploy, CloudWatch* • ⏱️ 120 minutes
- **[BMI Calculator API with Cloud Functions](gcp/bmi-calculator-functions-storage/bmi-calculator-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Building Collaborative Task Management with Aurora DSQL](aws/collaborative-task-management-aurora-dsql/collaborative-task-management-aurora-dsql.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Aurora DSQL, EventBridge, Lambda, CloudWatch* • ⏱️ 90 minutes
- **[Building High-Performance Computing Workloads with Cloud Filestore and Cloud Batch](gcp/high-performance-computing-workloads-cloud-filestore-batch/high-performance-computing-workloads-cloud-filestore-batch.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Filestore, Cloud Batch, Cloud Monitoring* • ⏱️ 75 minutes
- **[Business Process Automation with Step Functions](aws/business-process-automation-stepfunctions/business-process-automation-stepfunctions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Step Functions, Lambda, SNS, SQS* • ⏱️ 150 minutes
- **[Business Task Scheduling with EventBridge](aws/business-task-scheduling-eventbridge/business-task-scheduling-eventbridge.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EventBridge Scheduler, Lambda, SNS, S3* • ⏱️ 90 minutes
- **[Capturing Database Changes with DynamoDB Streams](aws/database-change-streams-dynamodb/database-change-streams-dynamodb.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: dynamodb, lambda, cloudwatch, iam* • ⏱️ 120 minutes
- **[Chat Notifications with SNS and Chatbot](aws/chat-notifications-sns-chatbot/chat-notifications-sns-chatbot.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SNS, Chatbot* • ⏱️ 25 minutes
- **[Circuit Breaker Patterns with Step Functions](aws/circuit-breaker-patterns-stepfunctions/circuit-breaker-patterns-stepfunctions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Step Functions, Lambda, DynamoDB, CloudWatch* • ⏱️ 120 minutes
- **[Code Tutorial Generator with OpenAI and Functions](azure/code-tutorial-generator-openai-functions/code-tutorial-generator-openai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI, Azure Functions, Azure Blob Storage* • ⏱️ 25 minutes
- **[Color Palette Generator with Cloud Functions and Storage](gcp/color-palette-generator-functions-storage/color-palette-generator-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 20 minutes
- **[Comprehensive Container Monitoring with Azure Container Storage and Managed Prometheus](azure/comprehensive-container-monitoring-azure-prometheus/comprehensive-container-monitoring-azure-prometheus.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Storage, Azure Managed Prometheus, Azure Container Apps, Azure Monitor* • ⏱️ 75 minutes
- **[Comprehensive Infrastructure Migration with Resource Mover and Update Manager](azure/comprehensive-infrastructure-migration/comprehensive-infrastructure-migration.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Resource Mover, Azure Update Manager, Azure Workbooks* • ⏱️ 120 minutes
- **[Configuration Management with Systems Manager](aws/configuration-management-systems-manager/configuration-management-systems-manager.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager, EC2, CloudWatch, IAM* • ⏱️ 150 minutes
- **[Container Health Checks and Self-Healing](aws/container-health-checks-healing/container-health-checks-healing.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECS, CloudWatch, Lambda, Auto Scaling* • ⏱️ 85 minutes
- **[Container Observability and Performance Monitoring](aws/container-observability-monitoring/container-observability-monitoring.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECS, CloudWatch, X-Ray, Prometheus* • ⏱️ 100 minutes
- **[Container Registry Replication with ECR](aws/container-registry-replication-ecr/container-registry-replication-ecr.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECR, Lambda, CloudWatch, EventBridge* • ⏱️ 70 minutes
- **[Container Resource Optimization with EKS](aws/container-resource-optimization-eks/container-resource-optimization-eks.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EKS, CloudWatch, Cost Explorer, VPA* • ⏱️ 150 minutes
- **[Container Secrets Management with Secrets Manager](aws/container-secrets-management/container-secrets-management.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Secrets Manager, ECS, EKS, IAM* • ⏱️ 150 minutes
- **[Container Security Scanning Pipelines](aws/container-security-pipelines-ecr/container-security-pipelines-ecr.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECR, Inspector, CodeBuild, EventBridge* • ⏱️ 150 minutes
- **[Containerized Web Applications with App Runner](aws/containerized-web-apps-apprunner/containerized-web-apps-apprunner.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: App Runner, RDS, Secrets Manager, CloudWatch* • ⏱️ 120 minutes
- **[Content Approval Workflows with AI Builder and Power Automate](azure/content-approval-workflows-ai-builder-automate/content-approval-workflows-ai-builder-automate.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: AI Builder, Power Automate, SharePoint, Teams* • ⏱️ 45 minutes
- **[Converting Text to Speech with Polly](aws/converting-text-speech-polly/converting-text-speech-polly.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: polly, s3, lambda, iam* • ⏱️ 60 minutes
- **[Cost Optimization Automation with Lambda](aws/cost-optimization-automation-lambda/cost-optimization-automation-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: lambda, trusted-advisor, sns, cloudwatch* • ⏱️ 120 minutes
- **[Cost-Effective ECS Clusters with Spot Instances](aws/cost-effective-ecs-spot/cost-effective-ecs-spot.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECS, EC2, Auto Scaling, CloudWatch* • ⏱️ 180 minutes
- **[Cost-Efficient Batch Processing with Azure Compute Fleet and Azure Batch](azure/cost-efficient-batch-processing-compute-fleet-batch/cost-efficient-batch-processing-compute-fleet-batch.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Compute Fleet, Azure Batch, Azure Storage, Azure Monitor* • ⏱️ 120 minutes
- **[Cost-Optimized Batch Processing with Spot](aws/cost-optimized-batch-spot/cost-optimized-batch-spot.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: aws-batch, ec2, ecr, iam* • ⏱️ 120 minutes
- **[Cost-Optimized Content Generation using Model Router and Functions](azure/cost-optimized-content-generation-model-router-functions/cost-optimized-content-generation-model-router-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure Functions, Blob Storage* • ⏱️ 45 minutes
- **[Cost-Optimized EKS Node Groups with Spot and Mixed Instances](aws/eks-nodegroups-spot-mixed/eks-nodegroups-spot-mixed.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eks, ec2, iam, cloudwatch* • ⏱️ 120 minutes
- **[Creating Contact Forms with SES and Lambda](aws/creating-contact-forms-ses/creating-contact-forms-ses.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SES, Lambda, API Gateway* • ⏱️ 60 minutes
- **[Creating No-Code AI Applications with PartyRock and S3](aws/no-code-ai-applications-partyrock-s3/no-code-ai-applications-partyrock-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: PartyRock, S3, CloudFront* • ⏱️ 60 minutes
- **[Creating Progressive Web Apps with Amplify Hosting](aws/progressive-web-apps-amplify-hosting/progressive-web-apps-amplify-hosting.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amplify, cloudfront, route53, acm* • ⏱️ 120 minutes
- **[Currency Converter API with Cloud Functions](gcp/currency-converter-api-functions/currency-converter-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Secret Manager* • ⏱️ 20 minutes
- **[Custom CloudFormation Resources with Lambda](aws/custom-cloudformation-resources-lambda/custom-cloudformation-resources-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cloudformation, lambda, iam, s3* • ⏱️ 180 minutes
- **[Custom Video Conferencing with Amazon Chime SDK](aws/video-conferencing-chime-sdk/video-conferencing-chime-sdk.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: chime-sdk, lambda, api-gateway, dynamodb* • ⏱️ 120 minutes
- **[Customer Service Chatbots with Lex](aws/customer-service-chatbots-lex/customer-service-chatbots-lex.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amazon-lex, aws-lambda, dynamodb, amazon-connect* • ⏱️ 120 minutes
- **[Dead Letter Queue Processing with SQS](aws/dead-letter-queue-sqs-lambda/dead-letter-queue-sqs-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SQS, Lambda, CloudWatch* • ⏱️ 45 minutes
- **[Delivering Scheduled Reports with App Runner and SES](aws/delivering-reports-with-app-runner/delivering-reports-with-app-runner.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: App Runner, SES, EventBridge Scheduler, CloudWatch* • ⏱️ 90 minutes
- **[Deploying Fargate Containers with Application Load Balancer](aws/deploying-fargate-containers-alb/deploying-fargate-containers-alb.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECS, Fargate, ALB, ECR* • ⏱️ 60 minutes
- **[Deploying GPU-Accelerated Multi-Agent AI Systems with Cloud Run and Vertex AI Agent Engine](gcp/gpu-accelerated-multi-agent-ai-systems-cloud-run-vertex-ai-agent-engine/gpu-accelerated-multi-agent-ai-systems-cloud-run-vertex-ai-agent-engine.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Vertex AI Agent Engine, Cloud Memorystore, Cloud Monitoring* • ⏱️ 120 minutes
- **[Deploying Multi-Container Applications with Cloud Run and Docker Compose](gcp/multi-container-applications-cloud-run-docker-compose/multi-container-applications-cloud-run-docker-compose.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Cloud SQL, Secret Manager, Artifact Registry* • ⏱️ 120 minutes
- **[Developing APIs with SAM and API Gateway](aws/developing-apis-with-sam/developing-apis-with-sam.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SAM, API Gateway, Lambda, DynamoDB* • ⏱️ 180 minutes
- **[Developing Offline-First Mobile Applications with Amplify DataStore](aws/offline-first-mobile-applications-amplify-datastore/offline-first-mobile-applications-amplify-datastore.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amplify, appsync, dynamodb, cognito* • ⏱️ 180 minutes
- **[Developing Progressive Web Applications with AWS Amplify](aws/progressive-web-applications-amplify/progressive-web-applications-amplify.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amplify, cognito, appsync, s3* • ⏱️ 120 minutes
- **[Developing Web Apps with Amplify and Lambda](aws/developing-web-apps-amplify/developing-web-apps-amplify.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amplify, lambda, apigateway, cognito* • ⏱️ 120 minutes
- **[Distributed Cache Warm-up Automation with Container Apps Jobs and Redis Enterprise](azure/distributed-cache-warm-up-automation/distributed-cache-warm-up-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Container Apps Jobs, Cache for Redis Enterprise, Monitor, Storage* • ⏱️ 120 minutes
- **[Distributed Microservices Architecture with Container Apps and Dapr](azure/distributed-microservices-with-dapr/distributed-microservices-with-dapr.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Apps, Dapr, Azure Service Bus, Azure Cosmos DB* • ⏱️ 90 minutes
- **[Document Auto-Summarization with Bedrock](aws/document-auto-summarization/document-auto-summarization.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock, Lambda, S3, Textract* • ⏱️ 45 minutes
- **[Document Processing Pipelines with Textract](aws/document-processing-textract-pipelines/document-processing-textract-pipelines.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: textract, step-functions, s3, lambda* • ⏱️ 90 minutes
- **[Document Validation Workflows with Document AI and Cloud Workflows](gcp/document-validation-workflows-document-ai-workflows/document-validation-workflows-document-ai-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Cloud Workflows, Cloud Storage, Eventarc* • ⏱️ 75 minutes
- **[Dynamic Configuration with Parameter Store](aws/dynamic-configuration-parameter-store/dynamic-configuration-parameter-store.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager Parameter Store, Lambda, CloudWatch, EventBridge* • ⏱️ 90 minutes
- **[EC2 Fleet Management with Spot Instances](aws/ec2-fleet-management-spot/ec2-fleet-management-spot.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2, Spot Fleet, CloudWatch, IAM* • ⏱️ 60 minutes
- **[EC2 Hibernate for Cost Optimization](aws/ec2-hibernate-cost-optimization/ec2-hibernate-cost-optimization.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ec2, cloudwatch, sns* • ⏱️ 45 minutes
- **[EC2 Image Building Pipelines with Image Builder](aws/ec2-image-building-pipelines/ec2-image-building-pipelines.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2 Image Builder, EC2, IAM, S3* • ⏱️ 120 minutes
- **[EC2 Launch Templates with Auto Scaling](aws/ec2-launch-templates-auto-scaling/ec2-launch-templates-auto-scaling.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2, Auto Scaling, CloudWatch* • ⏱️ 25 minutes
- **[ECS Service Discovery with Route 53](aws/ecs-service-discovery-route53/ecs-service-discovery-route53.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ecs, route53, elasticloadbalancing, cloudmap* • ⏱️ 120 minutes
- **[ECS Task Environment Variable Management](aws/ecs-task-environment-variables/ecs-task-environment-variables.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECS, Systems Manager, S3, IAM* • ⏱️ 90 minutes
- **[EKS Ingress with AWS Load Balancer Controller](aws/eks-ingress-alb-controller/eks-ingress-alb-controller.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eks, elbv2, ec2, iam* • ⏱️ 180 minutes
- **[EKS Logging and Monitoring with Prometheus](aws/eks-logging-monitoring-prometheus/eks-logging-monitoring-prometheus.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EKS, CloudWatch, AMP, VPC* • ⏱️ 120 minutes
- **[EKS Microservices with App Mesh Integration](aws/eks-microservices-mesh/eks-microservices-mesh.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EKS, App Mesh, ECR, CloudWatch* • ⏱️ 180 minutes
- **[EKS Microservices with App Mesh Service Mesh](aws/eks-app-mesh-microservices/eks-app-mesh-microservices.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eks, app-mesh, ecr, elastic-load-balancing* • ⏱️ 180 minutes
- **[EKS Monitoring with CloudWatch Container Insights](aws/eks-monitoring-cloudwatch-insights/eks-monitoring-cloudwatch-insights.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eks, cloudwatch, sns* • ⏱️ 45 minutes
- **[EKS Workload Auto Scaling](aws/eks-workload-auto-scaling/eks-workload-auto-scaling.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EKS, Auto Scaling, CloudWatch, EC2* • ⏱️ 240 minutes
- **[Elastic Web Applications with VM Auto-Scaling](azure/elastic-web-applications-vm-scaling/elastic-web-applications-vm-scaling.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Virtual Machine Scale Sets, Load Balancer, Monitor, Application Insights* • ⏱️ 120 minutes
- **[Email Automation with Agent Builder and MCP](gcp/email-automation-agent-builder-mcp/email-automation-agent-builder-mcp.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Agent Builder, Gmail API, Cloud Functions, Pub/Sub* • ⏱️ 45 minutes
- **[Email List Management with SES and DynamoDB](aws/email-list-management-ses-dynamodb/email-list-management-ses-dynamodb.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SES, DynamoDB, Lambda* • ⏱️ 25 minutes
- **[Email Marketing Campaigns with SES](aws/email-marketing-campaigns-ses/email-marketing-campaigns-ses.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amazon-ses, amazon-sns, amazon-s3, amazon-cloudwatch* • ⏱️ 60 minutes
- **[Email Notification Automation with SES](aws/email-notification-automation-ses/email-notification-automation-ses.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SES, Lambda, EventBridge, CloudWatch* • ⏱️ 90 minutes
- **[Email Signature Generator with Cloud Functions and Storage](gcp/email-signature-generator-functions-storage/email-signature-generator-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Email Validation with Cloud Functions](gcp/email-validation-functions-storage/email-validation-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 20 minutes
- **[Energy-Efficient Web Hosting with C4A and Hyperdisk](gcp/energy-efficient-web-hosting-c4a-hyperdisk/energy-efficient-web-hosting-c4a-hyperdisk.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Compute Engine, Load Balancing, Cloud Monitoring, Hyperdisk* • ⏱️ 45 minutes
- **[Enterprise API Integration with AgentCore Gateway and Step Functions](aws/api-integration-agentcore-gateway/api-integration-agentcore-gateway.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Bedrock AgentCore Gateway, Step Functions, Lambda, API Gateway* • ⏱️ 45 minutes
- **[Enterprise GraphQL API Architecture](aws/enterprise-graphql-api/enterprise-graphql-api.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: appsync, dynamodb, lambda, opensearch* • ⏱️ 180 minutes
- **[Enterprise Kubernetes Fleet Management with GKE Fleet and Backup for GKE](gcp/enterprise-kubernetes-fleet-management-gke-fleet-backup/enterprise-kubernetes-fleet-management-gke-fleet-backup.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: GKE Fleet, Backup for GKE, Config Connector, Cloud Build* • ⏱️ 120 minutes
- **[Enterprise Server Migration with Application Migration Service](aws/enterprise-server-migration/enterprise-server-migration.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: mgn, ec2, iam, vpc* • ⏱️ 240 minutes
- **[Enterprise Video Conferencing with Container Deployment](azure/enterprise-video-conferencing-containers/enterprise-video-conferencing-containers.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Web App for Containers, Azure Communication Services, Azure Blob Storage, Azure Container Registry* • ⏱️ 120 minutes
- **[Establishing Multi-Cluster Service Mesh Governance with Anthos Service Mesh and Config Management](gcp/multi-cluster-service-mesh-governance-anthos-service-mesh-config-management/multi-cluster-service-mesh-governance-anthos-service-mesh-config-management.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Anthos Service Mesh, Anthos Config Management, Google Kubernetes Engine, Binary Authorization* • ⏱️ 180 minutes
- **[Event Replay with EventBridge Archive](aws/event-replay-system/event-replay-system.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, lambda, s3, iam* • ⏱️ 120 minutes
- **[Event-Driven AI Agent Workflows with AI Foundry and Logic Apps](azure/event-driven-ai-agent-workflows-foundry-logic-apps/event-driven-ai-agent-workflows-foundry-logic-apps.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry Agent Service, Azure Logic Apps, Azure Service Bus* • ⏱️ 45 minutes
- **[Event-Driven Architecture with EventBridge](aws/eventbridge-architecture/eventbridge-architecture.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, lambda, sns, sqs* • ⏱️ 45 minutes
- **[Event-Driven Data Validation with Azure Table Storage and Event Grid](azure/event-driven-data-validation-azure-table-storage/event-driven-data-validation-azure-table-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Table Storage, Azure Event Grid, Azure Logic Apps, Azure Functions* • ⏱️ 105 minutes
- **[Event-Driven Microservices with EventBridge Routing](aws/eventbridge-microservices/eventbridge-microservices.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, lambda, sqs, sns* • ⏱️ 90 minutes
- **[Event-Driven Serverless Workflows with Azure Container Apps Jobs and Azure Service Bus](azure/event-driven-serverless-workflows-container-apps-jobs-service-bus/event-driven-serverless-workflows-container-apps-jobs-service-bus.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Apps, Azure Service Bus, Azure Container Registry* • ⏱️ 75 minutes
- **[Event-Driven Video Processing with MediaConvert](aws/video-processing-mediaconvert/video-processing-mediaconvert.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, lambda, mediaconvert, eventbridge* • ⏱️ 120 minutes
- **[Fault-Tolerant HPC with Step Functions](aws/hpc-workflows/hpc-workflows.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: step-functions, ec2, batch, lambda* • ⏱️ 180 minutes
- **[FHIR-Compliant Healthcare API Orchestration with Azure Container Apps and Azure Health Data Services](azure/fhir-compliant-healthcare-api-orchestration-container-apps-health-data/fhir-compliant-healthcare-api-orchestration-container-apps-health-data.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Container Apps, Health Data Services, API Management, Communication Services* • ⏱️ 150 minutes
- **[File Upload Processing with Functions and Blob Storage](azure/file-upload-processing-functions-blob/file-upload-processing-functions-blob.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Storage* • ⏱️ 15 minutes
- **[Fleet Operations with Fleet Engine and Cloud Run Jobs](gcp/fleet-operations-fleet-engine-run-jobs/fleet-operations-fleet-engine-run-jobs.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Fleet Engine, Cloud Run Jobs, Cloud Scheduler, Maps Platform* • ⏱️ 120 minutes
- **[Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler](gcp/flexible-hpc-workloads-cluster-director-scheduler/flexible-hpc-workloads-cluster-director-scheduler.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cluster Toolkit, Batch, Compute Engine, Cloud Storage* • ⏱️ 45 minutes
- **[Form Data Validation with Cloud Functions and Firestore](gcp/form-data-validation-functions-firestore/form-data-validation-functions-firestore.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore, Cloud Logging* • ⏱️ 20 minutes
- **[Full-Stack Serverless Web Applications with Azure Static Web Apps and Azure Functions](azure/full-stack-serverless-web-applications-static-web-apps-functions/full-stack-serverless-web-applications-static-web-apps-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Static Web Apps, Azure Functions, Azure Storage Account* • ⏱️ 75 minutes
- **[Generating Speech with Amazon Polly](aws/generating-speech-amazon-polly/generating-speech-amazon-polly.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: polly, s3* • ⏱️ 120 minutes
- **[Hash Generator API with Cloud Functions](gcp/hash-generator-api-functions/hash-generator-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 15 minutes
- **[High-Performance GPU Computing Workloads](aws/high-performance-gpu-computing/high-performance-gpu-computing.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ec2, cloudwatch, systems-manager, sns* • ⏱️ 120 minutes
- **[HPC Workloads with Managed Lustre and CycleCloud](azure/hpc-workloads-managed-lustre-cyclecloud/hpc-workloads-managed-lustre-cyclecloud.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Managed Lustre, Azure CycleCloud, Azure Batch, Azure Monitor* • ⏱️ 120 minutes
- **[Hybrid Edge Infrastructure with Stack HCI and Arc](azure/hybrid-edge-infrastructure-stack-hci-arc/hybrid-edge-infrastructure-stack-hci-arc.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Stack HCI, Azure Arc, Azure Monitor, Azure Storage* • ⏱️ 150 minutes
- **[Hybrid Kubernetes Monitoring with EKS Hybrid Nodes](aws/hybrid-kubernetes-monitoring/hybrid-kubernetes-monitoring.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon EKS, AWS Fargate, Amazon CloudWatch, AWS Systems Manager* • ⏱️ 150 minutes
- **[Hybrid Quantum-Classical ML Optimization Workflows](azure/hybrid-quantum-classical-ml-optimization/hybrid-quantum-classical-ml-optimization.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Quantum, Azure Machine Learning, Azure Batch, Azure Data Lake Storage* • ⏱️ 120 minutes
- **[Implementing Dedicated Hosts for License Compliance](aws/dedicated-hosts-license-compliance/dedicated-hosts-license-compliance.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2, License Manager, AWS Config, Systems Manager* • ⏱️ 150 minutes
- **[Implementing Predictive Scaling for EC2 with Auto Scaling and Machine Learning](aws/predictive-scaling-ec2-autoscaling-ml/predictive-scaling-ec2-autoscaling-ml.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: autoscaling, cloudwatch, ec2, iam* • ⏱️ 60 minutes
- **[Implementing Real-Time Chat Applications with AppSync and GraphQL](aws/real-time-chat-applications-appsync-graphql/real-time-chat-applications-appsync-graphql.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: appsync, dynamodb, cognito* • ⏱️ 180 minutes
- **[Intelligent Business Process Automation with Agent Development Kit and Workflows](gcp/intelligent-business-process-automation-adk-workflows/intelligent-business-process-automation-adk-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Agent Development Kit, Workflows, Cloud SQL, Cloud Functions* • ⏱️ 45 minutes
- **[Intelligent Document Processing with AI Extraction](azure/intelligent-document-processing-pipeline/intelligent-document-processing-pipeline.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cosmos DB for MongoDB, Azure Event Hubs, Azure Functions, Azure AI Document Intelligence* • ⏱️ 120 minutes
- **[Intelligent GPU Resource Orchestration with Container Apps and Azure Batch](azure/intelligent-gpu-resource-orchestration/intelligent-gpu-resource-orchestration.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Apps, Azure Batch, Azure Monitor, Azure Key Vault* • ⏱️ 120 minutes
- **[Intelligent Infrastructure ChatBots with Azure Copilot Studio and Azure Monitor](azure/intelligent-infrastructure-chatbots-copilot-studio-monitor/intelligent-infrastructure-chatbots-copilot-studio-monitor.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Copilot Studio, Azure Monitor, Azure Functions* • ⏱️ 75 minutes
- **[Intelligent Invoice Processing Workflows with Azure Logic Apps and AI Document Intelligence](azure/intelligent-invoice-processing-logic-apps-document-intelligence/intelligent-invoice-processing-logic-apps-document-intelligence.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Logic Apps, Azure AI Document Intelligence, Azure Service Bus, Azure Blob Storage* • ⏱️ 120 minutes
- **[Intelligent Product Catalog with OpenAI and Functions](azure/intelligent-product-catalog-openai-functions/intelligent-product-catalog-openai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Azure Functions, Azure Blob Storage* • ⏱️ 25 minutes
- **[Interactive Business Process Automation with Bedrock AgentCore and EventBridge](aws/business-process-automation-agentcore-eventbridge/business-process-automation-agentcore-eventbridge.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock, EventBridge, Lambda, S3* • ⏱️ 45 minutes
- **[JSON Validator API with Cloud Functions](gcp/json-validator-api-functions-storage/json-validator-api-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Knowledge Management Assistant with Bedrock Agents](aws/knowledge-management-assistant-bedrock/knowledge-management-assistant-bedrock.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock, API Gateway, S3, Lambda* • ⏱️ 35 minutes
- **[Kubernetes Operators for AWS Resources](aws/kubernetes-aws-operators/kubernetes-aws-operators.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eks, iam, s3, lambda* • ⏱️ 120 minutes
- **[Lambda Cost Optimization with Compute Optimizer](aws/lambda-cost-optimization/lambda-cost-optimization.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, Compute Optimizer, CloudWatch* • ⏱️ 35 minutes
- **[Lambda Safe Deployments with Blue-Green and Canary](aws/lambda-safe-deployments/lambda-safe-deployments.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: lambda, api-gateway, cloudwatch, iam* • ⏱️ 60 minutes
- **[Learning Assessment Generator with Document Intelligence and OpenAI](azure/learning-assessment-generator-document-intelligence-openai/learning-assessment-generator-document-intelligence-openai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Document Intelligence, Azure OpenAI, Azure Functions, Azure Cosmos DB* • ⏱️ 25 minutes
- **[Lorem Ipsum Generator Cloud Functions API](gcp/lorem-ipsum-generator-functions/lorem-ipsum-generator-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Managing WebSocket APIs with Route and Connection Handling](aws/websocket-apis-connection-management/websocket-apis-connection-management.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: api-gateway, lambda, dynamodb, cloudwatch* • ⏱️ 120 minutes
- **[Meeting Summary Generation with Speech-to-Text and Gemini](gcp/meeting-summary-generation-speech-gemini/meeting-summary-generation-speech-gemini.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Speech-to-Text, Gemini, Cloud Storage, Cloud Functions* • ⏱️ 45 minutes
- **[Microservices Orchestration with EventBridge](aws/microservices-orchestration/microservices-orchestration.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, step-functions, lambda, dynamodb* • ⏱️ 120 minutes
- **[Mixed Instance Auto Scaling Groups](aws/mixed-instance-auto-scaling/mixed-instance-auto-scaling.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2, Auto Scaling, CloudWatch* • ⏱️ 60 minutes
- **[Mobile App A/B Testing with Pinpoint Analytics](aws/mobile-app-ab-testing-pinpoint/mobile-app-ab-testing-pinpoint.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: pinpoint, iam, s3, cloudwatch* • ⏱️ 150 minutes
- **[Multi-Cluster Kubernetes Fleet Management with GitOps](azure/multi-cluster-kubernetes-fleet-management-gitops/multi-cluster-kubernetes-fleet-management-gitops.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Kubernetes Fleet Manager, Azure Service Operator, Azure Container Registry, Azure Key Vault* • ⏱️ 120 minutes
- **[Multi-Language Content Optimization with Cloud Translation Advanced and Cloud Run Jobs](gcp/multi-language-content-optimization-translation-worker-pools/multi-language-content-optimization-translation-worker-pools.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Translation Advanced, Cloud Run Jobs, Cloud Storage, Pub/Sub* • ⏱️ 120 minutes
- **[Newsletter Content Generation with Gemini and Scheduler](gcp/newsletter-content-generation-gemini-scheduler/newsletter-content-generation-gemini-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Gemini, Cloud Scheduler, Cloud Functions, Cloud Storage* • ⏱️ 25 minutes
- **[Optimizing HPC Workloads with AWS Batch and Spot Instances](aws/optimizing-hpc-workloads-batch-spot/optimizing-hpc-workloads-batch-spot.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Batch, EC2 Spot Instances, CloudWatch, S3* • ⏱️ 90 minutes
- **[Orchestrating Global Event Replication with EventBridge](aws/orchestrating-global-event-replication/orchestrating-global-event-replication.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, lambda, cloudwatch, route53* • ⏱️ 120 minutes
- **[Orchestrating Notifications with SNS SQS and Lambda](aws/orchestrating-notifications-sns-sqs/orchestrating-notifications-sns-sqs.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sns, sqs, lambda* • ⏱️ 120 minutes
- **[Performance Monitoring AI Agents with AgentCore and CloudWatch](aws/performance-monitoring-agentcore-cloudwatch/performance-monitoring-agentcore-cloudwatch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock AgentCore, CloudWatch, Lambda, S3* • ⏱️ 45 minutes
- **[Persistent AI Customer Support with Agent Engine Memory](gcp/persistent-customer-support-agentcore-memory/persistent-customer-support-agentcore-memory.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Agent Engine, Firestore, Cloud Functions* • ⏱️ 35 minutes
- **[Persistent Containers with Serverless Deployment](azure/persistent-containers-serverless-deployment/persistent-containers-serverless-deployment.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Container Instances, Azure Files, Container Registry, Monitor* • ⏱️ 120 minutes
- **[Persistent Customer Support Agent with Bedrock AgentCore Memory](aws/persistent-customer-support-agentcore-memory/persistent-customer-support-agentcore-memory.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock AgentCore, Lambda, DynamoDB, API Gateway* • ⏱️ 35 minutes
- **[Personal Expense Tracker with App Engine and Cloud SQL](gcp/expense-tracker-app-engine-sql/expense-tracker-app-engine-sql.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: App Engine, Cloud SQL* • ⏱️ 30 minutes
- **[Personal Task Manager with Cloud Functions and Google Tasks](gcp/personal-task-manager-functions-tasks/personal-task-manager-functions-tasks.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Google Tasks API* • ⏱️ 15 minutes
- **[Pinpoint Mobile Push Notifications](aws/pinpoint-push-notifications/pinpoint-push-notifications.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: pinpoint, sns, iam* • ⏱️ 120 minutes
- **[Proactive Cost Anomaly Detection with Serverless Analytics](azure/proactive-cost-anomaly-detection/proactive-cost-anomaly-detection.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Cost Management, Functions, Cosmos DB, Logic Apps* • ⏱️ 90 minutes
- **[Processing Event-Driven Streams with Kinesis and Lambda](aws/event-driven-stream-processing/event-driven-stream-processing.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Kinesis, Lambda, DynamoDB, CloudWatch* • ⏱️ 90 minutes
- **[Processing Serverless Streams with Kinesis and Lambda](aws/serverless-stream-processing-kinesis/serverless-stream-processing-kinesis.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kinesis, lambda, cloudwatch, iam* • ⏱️ 120 minutes
- **[Progressive Web Apps with Static Hosting and CDN](azure/progressive-web-apps-static-hosting-cdn/progressive-web-apps-static-hosting-cdn.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Static Web Apps, Azure CDN, Azure Application Insights* • ⏱️ 120 minutes
- **[QR Code Generator with Cloud Run and Storage](gcp/qr-code-generator-cloud-run-storage/qr-code-generator-cloud-run-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Cloud Storage* • ⏱️ 15 minutes
- **[Quantum Computing Pipelines with Braket](aws/quantum-computing-braket-lambda/quantum-computing-braket-lambda.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Braket, AWS Lambda, Amazon S3, CloudWatch* • ⏱️ 150 minutes
- **[Quantum Supply Chain Network Optimization with Azure Quantum and Digital Twins](azure/quantum-supply-chain-network-optimization/quantum-supply-chain-network-optimization.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Quantum, Azure Digital Twins, Azure Functions, Azure Stream Analytics* • ⏱️ 120 minutes
- **[RAG Knowledge Base with AI Search and Functions](azure/rag-knowledge-base-ai-search-functions/rag-knowledge-base-ai-search-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Search, Azure Functions, Azure OpenAI Service, Azure Blob Storage* • ⏱️ 45 minutes
- **[Random Quote API with Cloud Functions and Firestore](gcp/random-quote-api-functions-firestore/random-quote-api-functions-firestore.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore* • ⏱️ 15 minutes
- **[Real-Time Apps with Amplify and AppSync](aws/realtime-apps-amplify/realtime-apps-amplify.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amplify, appsync, cognito, dynamodb* • ⏱️ 180 minutes
- **[Real-Time Collaborative Applications with Firebase Realtime Database and Cloud Functions](gcp/real-time-collaborative-applications-firebase-database-functions/real-time-collaborative-applications-firebase-database-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Realtime Database, Cloud Functions, Firebase Auth, Firebase Hosting* • ⏱️ 120 minutes
- **[Real-Time Data Synchronization with AppSync](aws/realtime-data-sync-appsync/realtime-data-sync-appsync.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AppSync, DynamoDB, Lambda, CloudWatch* • ⏱️ 120 minutes
- **[Real-Time Event Processing with Cloud Memorystore and Pub/Sub](gcp/real-time-event-processing-memorystore-pub-sub/real-time-event-processing-memorystore-pub-sub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Memorystore, Pub/Sub, Cloud Functions, Cloud Monitoring* • ⏱️ 120 minutes
- **[Real-Time GraphQL API with AppSync](aws/real-time-graphql-api/real-time-graphql-api.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AppSync, DynamoDB, Cognito* • ⏱️ 40 minutes
- **[Real-Time Multiplayer Gaming Infrastructure with Game Servers and Cloud Firestore](gcp/real-time-multiplayer-gaming-infrastructure-game-servers-firestore/real-time-multiplayer-gaming-infrastructure-game-servers-firestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Kubernetes Engine, Cloud Firestore, Cloud Run, Cloud Load Balancing* • ⏱️ 120 minutes
- **[Real-time Status Notifications with SignalR and Functions](azure/realtime-status-notifications-signalr-functions/realtime-status-notifications-signalr-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure SignalR Service, Azure Functions* • ⏱️ 15 minutes
- **[Real-time Video Collaboration with WebRTC and Cloud Run](gcp/real-time-video-collaboration-webrtc-run/real-time-video-collaboration-webrtc-run.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Firestore, Identity-Aware Proxy* • ⏱️ 45 minutes
- **[Recipe Generation and Meal Planning with Gemini and Storage](gcp/recipe-generation-meal-planning-gemini-storage/recipe-generation-meal-planning-gemini-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Resilient Stateful Microservices with Azure Service Fabric and Durable Functions](azure/resilient-stateful-microservices-azure-service-fabric/resilient-stateful-microservices-azure-service-fabric.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Service Fabric, SQL Database, Functions, Application Insights* • ⏱️ 120 minutes
- **[Resource Cleanup Automation with Lambda and Tags](aws/simple-resource-cleanup-lambda-tags/simple-resource-cleanup-lambda-tags.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, EC2, SNS* • ⏱️ 30 minutes
- **[Running Containers with AWS Fargate](aws/running-containers-fargate/running-containers-fargate.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECS, Fargate, ECR, Application Auto Scaling* • ⏱️ 45 minutes
- **[SageMaker ML Workflows with Step Functions](aws/sagemaker-ml-workflows/sagemaker-ml-workflows.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sagemaker, step-functions, s3, iam* • ⏱️ 240 minutes
- **[Scalable AI Prompt Workflows with Azure AI Studio and Container Apps](azure/scalable-ai-prompt-workflows-azure-container-apps/scalable-ai-prompt-workflows-azure-container-apps.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Studio, Azure Container Apps, Azure Container Registry, Azure Monitor* • ⏱️ 120 minutes
- **[Scalable HPC Cluster with Auto-Scaling](aws/scalable-hpc-cluster/scalable-hpc-cluster.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ec2, parallelcluster, s3, fsx* • ⏱️ 120 minutes
- **[Scalable HPC Workload Processing with Elastic SAN and Azure Batch](azure/scalable-hpc-workload-processing/scalable-hpc-workload-processing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Elastic SAN, Azure Batch, Azure Storage, Azure Virtual Network* • ⏱️ 120 minutes
- **[Scalable Webhook Processing with SQS](aws/webhook-processing-sqs/webhook-processing-sqs.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: api-gateway, sqs, lambda, dynamodb* • ⏱️ 120 minutes
- **[Scheduling Notifications with EventBridge and SNS](aws/scheduling-notifications-eventbridge/scheduling-notifications-eventbridge.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EventBridge Scheduler, SNS, IAM* • ⏱️ 60 minutes
- **[Scientific Computing with Batch Multi-Node](aws/scientific-computing-batch-multinode/scientific-computing-batch-multinode.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: batch, ec2, ecr, efs* • ⏱️ 120 minutes
- **[Secure EC2 Management with Systems Manager](aws/ec2-secure-management-ssm/ec2-secure-management-ssm.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2, Systems Manager, IAM* • ⏱️ 45 minutes
- **[Secure Sandboxed Code Execution with Dynamic Sessions](azure/secure-sandboxed-code-execution/secure-sandboxed-code-execution.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Apps, Azure Event Grid, Azure Key Vault, Azure Monitor* • ⏱️ 120 minutes
- **[Secure Serverless Microservices with Container Apps](azure/secure-serverless-microservices/secure-serverless-microservices.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Apps, Azure Key Vault, Azure Container Registry, Azure Monitor* • ⏱️ 75 minutes
- **[Securing APIs with Lambda Authorizers and API Gateway](aws/securing-apis-lambda-authorizers/securing-apis-lambda-authorizers.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: API Gateway, Lambda, IAM, CloudWatch* • ⏱️ 90 minutes
- **[Self-Managed Kubernetes Integration with VPC Lattice IP Targets](aws/kubernetes-integration-lattice-ip/kubernetes-integration-lattice-ip.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, EC2, CloudWatch* • ⏱️ 45 minutes
- **[Serverless AI Agents with OpenAI Service and Container Instances](azure/serverless-ai-agents-openai-container-instances/serverless-ai-agents-openai-container-instances.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Azure Container Instances, Azure Event Grid, Azure Functions* • ⏱️ 120 minutes
- **[Serverless Batch Processing with Fargate](aws/batch-processing-fargate/batch-processing-fargate.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Batch, Fargate, IAM, CloudWatch* • ⏱️ 150 minutes
- **[Serverless Containers with Event Grid and Container Instances](azure/serverless-containers-event-grid-aci/serverless-containers-event-grid-aci.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Event Grid, Azure Container Instances, Azure Storage Account, Azure Functions* • ⏱️ 75 minutes
- **[Serverless GPU Computing Pipelines with Cloud Run GPU and Cloud Workflows](gcp/serverless-gpu-computing-pipelines-run-gpu-workflows/serverless-gpu-computing-pipelines-run-gpu-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Cloud Workflows, Cloud Storage, Vertex AI* • ⏱️ 120 minutes
- **[Serverless GraphQL APIs with AppSync and Scheduler](aws/serverless-graphql-apis/serverless-graphql-apis.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS AppSync, EventBridge Scheduler, DynamoDB, Lambda* • ⏱️ 90 minutes
- **[Session Management with Cloud Memorystore and Firebase Auth](gcp/session-management-memorystore-firebase-auth/session-management-memorystore-firebase-auth.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Memorystore, Firebase Authentication, Cloud Functions, Secret Manager* • ⏱️ 105 minutes
- **[Simple Color Palette Generator with Lambda and S3](aws/simple-color-palette-generator-lambda-s3/simple-color-palette-generator-lambda-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, S3* • ⏱️ 25 minutes
- **[Simple Contact Form with Functions and Table Storage](azure/simple-contact-form-functions-table-storage/simple-contact-form-functions-table-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Table Storage* • ⏱️ 20 minutes
- **[Simple Container App Deployment with Container Apps](azure/simple-container-deployment-container-apps/simple-container-deployment-container-apps.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Container Apps, Container Registry* • ⏱️ 20 minutes
- **[Simple Daily Quote Generator with Functions and Storage](azure/simple-daily-quote-generator-functions-storage/simple-daily-quote-generator-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Table Storage* • ⏱️ 20 minutes
- **[Simple Daily Quote Generator with Lambda and S3](aws/simple-daily-quote-generator-lambda-s3/simple-daily-quote-generator-lambda-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, S3* • ⏱️ 25 minutes
- **[Simple Data Collection API Functions Cosmos DB](azure/simple-data-collection-api-functions-cosmos/simple-data-collection-api-functions-cosmos.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Cosmos DB, Storage Account* • ⏱️ 20 minutes
- **[Simple Email Notifications with Communication Services](azure/simple-email-notifications-communication-functions/simple-email-notifications-communication-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Communication Services, Functions* • ⏱️ 20 minutes
- **[Simple Event Notifications with Event Grid and Functions](azure/simple-event-notifications-event-grid-functions/simple-event-notifications-event-grid-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Event Grid, Azure Functions* • ⏱️ 20 minutes
- **[Simple File Compression with Functions and Storage](azure/simple-file-compression-functions-storage/simple-file-compression-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Blob Storage* • ⏱️ 15 minutes
- **[Simple File Organization with S3 and Lambda](aws/simple-file-organization-s3-lambda/simple-file-organization-s3-lambda.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, Lambda, IAM, CloudWatch* • ⏱️ 25 minutes
- **[Simple File Validation with S3 and Lambda](aws/simple-file-validation-s3-lambda/simple-file-validation-s3-lambda.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, Lambda* • ⏱️ 25 minutes
- **[Simple Habit Tracker with Cloud Functions and Firestore](gcp/habit-tracker-functions-firestore/habit-tracker-functions-firestore.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore* • ⏱️ 15 minutes
- **[Simple Healthcare Chatbot with Azure Health Bot](azure/simple-healthcare-chatbot-health-bot/simple-healthcare-chatbot-health-bot.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Health Bot, Azure Bot Service* • ⏱️ 15 minutes
- **[Simple Image Metadata Extractor with Lambda and S3](aws/simple-image-metadata-extractor-lambda-s3/simple-image-metadata-extractor-lambda-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, S3* • ⏱️ 25 minutes
- **[Simple Image Resizing with Functions and Blob Storage](azure/simple-image-resizing-functions-blob/simple-image-resizing-functions-blob.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Blob Storage* • ⏱️ 20 minutes
- **[Simple JSON to CSV Converter with Lambda and S3](aws/simple-json-csv-converter-lambda-s3/simple-json-csv-converter-lambda-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, S3* • ⏱️ 25 minutes
- **[Simple Markdown to HTML Converter with Lambda and S3](aws/markdown-html-converter-lambda-s3/markdown-html-converter-lambda-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, S3, IAM, CloudWatch* • ⏱️ 25 minutes
- **[Simple Password Generator with Cloud Functions](gcp/password-generator-cloud-functions/password-generator-cloud-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 15 minutes
- **[Simple QR Code Generator with Functions and Blob Storage](azure/simple-qr-generator-functions-blob/simple-qr-generator-functions-blob.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Blob Storage* • ⏱️ 15 minutes
- **[Simple QR Code Generator with Lambda and S3](aws/simple-qr-generator-lambda-s3/simple-qr-generator-lambda-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, S3, API Gateway* • ⏱️ 25 minutes
- **[Simple Random Data API with Lambda and API Gateway](aws/simple-random-data-api-lambda-gateway/simple-random-data-api-lambda-gateway.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, API Gateway* • ⏱️ 25 minutes
- **[Simple Schedule Reminders with Logic Apps and Outlook](azure/simple-schedule-reminders-logic-apps-outlook/simple-schedule-reminders-logic-apps-outlook.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Logic Apps, Office 365 Outlook* • ⏱️ 15 minutes
- **[Simple Service Status Page with Static Web Apps and Functions](azure/simple-service-status-static-web-apps-functions/simple-service-status-static-web-apps-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Static Web Apps, Azure Functions* • ⏱️ 20 minutes
- **[Simple SMS Notifications with Communication Services and Functions](azure/simple-sms-notifications-communication-functions/simple-sms-notifications-communication-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Communication Services, Azure Functions* • ⏱️ 30 minutes
- **[Simple Team Poll System with Functions and Service Bus](azure/simple-team-poll-functions-service-bus/simple-team-poll-functions-service-bus.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Service Bus* • ⏱️ 20 minutes
- **[Simple Text Processing with CloudShell and S3](aws/simple-text-processing-cloudshell-s3/simple-text-processing-cloudshell-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudShell, S3* • ⏱️ 25 minutes
- **[Simple Text Translation with Functions and Translator](azure/simple-text-translation-functions-translator/simple-text-translation-functions-translator.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Translator* • ⏱️ 15 minutes
- **[Simple Time Zone Converter with Lambda and API Gateway](aws/simple-timezone-converter-lambda-gateway/simple-timezone-converter-lambda-gateway.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, API Gateway* • ⏱️ 25 minutes
- **[Simple Todo API with Functions and Table Storage](azure/simple-todo-api-functions-table/simple-todo-api-functions-table.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Table Storage* • ⏱️ 20 minutes
- **[Simple URL Shortener with API Gateway and DynamoDB](aws/simple-url-shortener-gateway-dynamodb/simple-url-shortener-gateway-dynamodb.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: API Gateway, DynamoDB, Lambda* • ⏱️ 25 minutes
- **[Simple URL Shortener with Functions and Table Storage](azure/simple-url-shortener-functions-table/simple-url-shortener-functions-table.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Table Storage* • ⏱️ 20 minutes
- **[Simple Visitor Counter with Cloud Functions and Firestore](gcp/visitor-counter-functions-firestore/visitor-counter-functions-firestore.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore* • ⏱️ 15 minutes
- **[Simple Voting System with Cloud Functions and Firestore](gcp/simple-voting-system-functions-firestore/simple-voting-system-functions-firestore.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore* • ⏱️ 15 minutes
- **[Simple Weather Dashboard with Functions and Static Web Apps](azure/simple-weather-dashboard-functions-static-apps/simple-weather-dashboard-functions-static-apps.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Static Web Apps* • ⏱️ 20 minutes
- **[Simple Web Application Deployment with Elastic Beanstalk and CloudWatch](aws/simple-web-deployment-beanstalk-cloudwatch/simple-web-deployment-beanstalk-cloudwatch.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Elastic Beanstalk, CloudWatch, IAM* • ⏱️ 25 minutes
- **[Simple Web Container with Azure Container Instances](azure/simple-web-container-aci-registry/simple-web-container-aci-registry.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Instances, Azure Container Registry* • ⏱️ 15 minutes
- **[Simple Website Hosting with Lightsail](aws/simple-website-hosting-lightsail/simple-website-hosting-lightsail.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lightsail* • ⏱️ 25 minutes
- **[Simple Website Hosting with Static Web Apps and CLI](azure/simple-website-hosting-static-web-apps-cli/simple-website-hosting-static-web-apps-cli.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Static Web Apps, Azure CLI* • ⏱️ 15 minutes
- **[Smart Calendar Intelligence with Cloud Calendar API and Cloud Run Worker Pools](gcp/smart-calendar-intelligence-calendar-api-worker-pools/smart-calendar-intelligence-calendar-api-worker-pools.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Calendar API, Cloud Run, Vertex AI, Cloud Tasks* • ⏱️ 120 minutes
- **[Smart Code Documentation with Agent Development Kit and Functions](gcp/smart-code-documentation-adk-functions/smart-code-documentation-adk-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Agent Development Kit, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Smart Document Review Workflow with ADK and Storage](gcp/smart-document-review-adk-storage/smart-document-review-adk-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Agent Development Kit, Cloud Storage, Cloud Functions, Vertex AI* • ⏱️ 45 minutes
- **[Smart Email Template Generation with Gemini and Firestore](gcp/smart-email-template-generation-gemini-firestore/smart-email-template-generation-gemini-firestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Firestore, Cloud Functions* • ⏱️ 25 minutes
- **[Smart Writing Feedback System with OpenAI and Cosmos](azure/smart-writing-feedback-openai-cosmos/smart-writing-feedback-openai-cosmos.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Azure Cosmos DB, Azure Functions* • ⏱️ 35 minutes
- **[SMS Compliance Automation with Communication Services](azure/sms-compliance-automation-communication-functions/sms-compliance-automation-communication-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Communication Services, Functions* • ⏱️ 20 minutes
- **[SNS Message Fan-out with Multiple SQS Queues](aws/sns-message-fanout/sns-message-fanout.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sns, sqs, iam, cloudwatch* • ⏱️ 45 minutes
- **[Social Media Video Creation with Veo 3 and Vertex AI](gcp/social-media-video-creation-veo-vertex-ai/social-media-video-creation-veo-vertex-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Storage, Cloud Functions* • ⏱️ 45 minutes
- **[Standardized Service Deployment with VPC Lattice and Service Catalog](aws/standardized-service-deployment-lattice-catalog/standardized-service-deployment-lattice-catalog.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Service Catalog, CloudFormation, IAM* • ⏱️ 45 minutes
- **[Step Functions Microservices Orchestration](aws/step-functions-orchestration/step-functions-orchestration.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Step Functions, Lambda, EventBridge* • ⏱️ 90 minutes
- **[Task Queue System with Cloud Tasks and Functions](gcp/task-queue-system-tasks-functions/task-queue-system-tasks-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Tasks, Cloud Functions* • ⏱️ 20 minutes
- **[Tax Calculator API with Cloud Functions and Firestore](gcp/tax-calculator-api-functions-firestore/tax-calculator-api-functions-firestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore* • ⏱️ 25 minutes
- **[Text Case Converter API with Cloud Functions](gcp/text-case-converter-functions/text-case-converter-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 15 minutes
- **[Time Zone Converter API with Cloud Functions](gcp/timezone-converter-api-functions/timezone-converter-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 20 minutes
- **[Timestamp Converter API with Cloud Functions](gcp/timestamp-converter-api-functions/timestamp-converter-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Tip Calculator API with Cloud Functions](gcp/tip-calculator-api-functions/tip-calculator-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 20 minutes
- **[Transforming API Requests with VTL Templates](aws/api-transformation-vtl-templates/api-transformation-vtl-templates.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: API Gateway, Lambda, CloudWatch, S3* • ⏱️ 120 minutes
- **[Unit Converter API with Cloud Functions](gcp/unit-converter-api-cloud-functions/unit-converter-api-cloud-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 15 minutes
- **[Unit Converter API with Cloud Functions and Storage](gcp/unit-converter-api-functions-storage/unit-converter-api-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[URL Shortener Service with Lambda](aws/url-shortener-lambda-dynamodb/url-shortener-lambda-dynamodb.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, DynamoDB, API Gateway, CloudWatch* • ⏱️ 90 minutes
- **[URL Shortener with Cloud Functions and Firestore](gcp/url-shortener-functions-firestore/url-shortener-functions-firestore.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore* • ⏱️ 30 minutes
- **[User Lifecycle Management with Firebase Authentication and Cloud Tasks](gcp/user-lifecycle-management-firebase-auth-tasks/user-lifecycle-management-firebase-auth-tasks.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Authentication, Cloud SQL, Cloud Tasks, Cloud Scheduler* • ⏱️ 120 minutes
- **[VMware Workload Migration and Modernization with Google Cloud VMware Engine and Migrate to Containers](gcp/vmware-workload-migration-modernization-vmware-engine-migrate-anthos/vmware-workload-migration-modernization-vmware-engine-migrate-anthos.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Cloud VMware Engine, Migrate to Containers, Cloud Monitoring, Cloud Operations* • ⏱️ 150 minutes
- **[Voice-Controlled Task Automation with Speech-to-Text and Workflows](gcp/voice-controlled-task-automation-speech-workflows/voice-controlled-task-automation-speech-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Speech-to-Text, Cloud Workflows, Cloud Functions, Cloud Tasks* • ⏱️ 35 minutes
- **[Voice-Driven Workflow Automation with Speech Recognition](azure/voice-driven-workflow-automation/voice-driven-workflow-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Speech, Power Platform, Azure Logic Apps* • ⏱️ 120 minutes
- **[Voice-to-Multilingual Content Pipeline with Speech and OpenAI](azure/voice-multilingual-content-speech-openai/voice-multilingual-content-speech-openai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Speech, Azure OpenAI, Azure Translator, Azure Functions* • ⏱️ 45 minutes
- **[Weather Alert Notifications with Lambda and SNS](aws/weather-alert-notifications-lambda-sns/weather-alert-notifications-lambda-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, SNS, EventBridge, IAM* • ⏱️ 25 minutes
- **[Weather API Gateway with Cloud Run](gcp/weather-api-gateway-cloud-run/weather-api-gateway-cloud-run.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Cloud Storage* • ⏱️ 15 minutes
- **[Weather API Service with Cloud Functions](gcp/weather-api-service-functions/weather-api-service-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Storage* • ⏱️ 15 minutes
- **[Weather API with Cloud Functions](gcp/weather-api-cloud-functions/weather-api-cloud-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 15 minutes
- **[Weather API with Cloud Functions and Firestore](gcp/weather-api-functions-firestore/weather-api-functions-firestore.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Firestore* • ⏱️ 30 minutes
- **[Weather API with Cloud Functions and Storage](gcp/weather-api-functions-storage/weather-api-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Weather Dashboard with Cloud Functions and Storage](gcp/weather-dashboard-functions-storage/weather-dashboard-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Weather Forecast API with Cloud Functions](gcp/weather-forecast-api-functions/weather-forecast-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 15 minutes
- **[Weather Information API with Cloud Functions](gcp/weather-information-api-functions/weather-information-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 15 minutes
- **[Weather-Aware Infrastructure Scaling with Google Maps Platform Weather API and Cluster Toolkit](gcp/weather-aware-infrastructure-scaling-maps-weather-api-cluster-toolkit/weather-aware-infrastructure-scaling-maps-weather-api-cluster-toolkit.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Maps Platform Weather API, Cluster Toolkit, Cloud Monitoring, Compute Engine* • ⏱️ 120 minutes
- **[Web Application Deployment with App Engine](gcp/web-application-deployment-app-engine/web-application-deployment-app-engine.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: App Engine, Cloud Build* • ⏱️ 30 minutes
- **[Website Contact Form with Cloud Functions and Gmail API](gcp/contact-form-functions-gmail/contact-form-functions-gmail.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Gmail API* • ⏱️ 20 minutes
- **[Website Screenshot API with Cloud Functions and Storage](gcp/website-screenshot-api-functions-storage/website-screenshot-api-functions-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 20 minutes
- **[Website Status Monitor with Cloud Functions](gcp/website-status-monitor-functions/website-status-monitor-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions* • ⏱️ 20 minutes
- **[Word Count API with Cloud Functions](gcp/word-count-api-functions/word-count-api-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Storage* • ⏱️ 15 minutes
- **[Zero-Trust Virtual Desktop Infrastructure with Azure Virtual Desktop and Bastion](azure/zero-trust-virtual-desktop-infrastructure-azure-bastion/zero-trust-virtual-desktop-infrastructure-azure-bastion.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Virtual Desktop, Azure Bastion, Azure Active Directory, Azure Key Vault* • ⏱️ 120 minutes

---

## 🗄️ Storage & Data Management

*Object storage, block storage, file systems, and data archival solutions*

- **[Application Discovery and Migration Assessment](aws/application-discovery-assessment/application-discovery-assessment.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Application Discovery Service, Migration Hub, S3, IAM* • ⏱️ 180 minutes
- **[Archiving Data with S3 Intelligent Tiering](aws/archiving-data-s3-intelligent-tiering/archiving-data-s3-intelligent-tiering.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudwatch, cloudtrail* • ⏱️ 90 minutes
- **[Automated Data Archiving with S3 Glacier](aws/data-archiving-s3-glacier/data-archiving-s3-glacier.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, Glacier, SNS* • ⏱️ 60 minutes
- **[Automated File Backup with Storage and Scheduler](gcp/automated-file-backup-storage-scheduler/automated-file-backup-storage-scheduler.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Cloud Scheduler, Cloud Functions* • ⏱️ 18 minutes
- **[Automated Storage Lifecycle Management with Cloud Storage](gcp/automated-storage-lifecycle-management/automated-storage-lifecycle-management.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Cloud Scheduler* • ⏱️ 20 minutes
- **[Automating Backups with S3 Lifecycle Policies](aws/automating-backups-with-s3-lifecycle/automating-backups-with-s3-lifecycle.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, EventBridge, Lambda, IAM* • ⏱️ 45 minutes
- **[Automating File Processing with S3 Event Notifications](aws/automating-file-processing-with-s3-events/automating-file-processing-with-s3-events.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, lambda, sqs, sns* • ⏱️ 60 minutes
- **[Automating Multi-Region Backup Strategies using AWS Backup](aws/automating-multi-region-backup-strategies-aws-backup/automating-multi-region-backup-strategies-aws-backup.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Backup, EventBridge, IAM, Lambda* • ⏱️ 90 minutes
- **[AWS CLI Setup and First Commands](aws/aws-cli-setup-first-commands/aws-cli-setup-first-commands.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CLI, S3* • ⏱️ 25 minutes
- **[Backup and Archive Strategies with S3 Glacier](aws/backup-archive-s3-glacier-policies/backup-archive-s3-glacier-policies.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, Glacier, IAM, CloudWatch* • ⏱️ 120 minutes
- **[Backup Strategies with S3 and Glacier](aws/backup-strategies-s3-glacier/backup-strategies-s3-glacier.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, Glacier, Lambda, EventBridge* • ⏱️ 90 minutes
- **[Basic File Storage with Blob Storage and Portal](azure/basic-file-storage-blob-portal/basic-file-storage-blob-portal.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Storage Account, Blob Storage* • ⏱️ 15 minutes
- **[Building File Portals with Transfer Family](aws/building-file-portals-with-transfer-family/building-file-portals-with-transfer-family.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Transfer Family, S3, IAM Identity Center, Access Grants* • ⏱️ 90 minutes
- **[Contact Center Solutions with Amazon Connect](aws/contact-center-solutions-connect/contact-center-solutions-connect.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: connect, s3, cloudwatch, iam* • ⏱️ 120 minutes
- **[Cross-Cloud Data Migration with Cloud Storage Transfer Service and Cloud Composer](gcp/cross-cloud-data-migration-storage-transfer-service-composer/cross-cloud-data-migration-storage-transfer-service-composer.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage Transfer Service, Cloud Composer, Cloud Logging, Cloud Storage* • ⏱️ 120 minutes
- **[Data Archiving Solutions with S3 Lifecycle](aws/data-archiving-s3-lifecycle/data-archiving-s3-lifecycle.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudwatch, iam* • ⏱️ 60 minutes
- **[Data Locality Optimization with Cloud Storage Bucket Relocation and Cloud Monitoring](gcp/data-locality-optimization-storage-bucket-relocation-monitoring/data-locality-optimization-storage-bucket-relocation-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Cloud Monitoring, Cloud Functions, Cloud Scheduler* • ⏱️ 75 minutes
- **[Data Migration Workflows with Cloud Storage Bucket Relocation and Eventarc](gcp/data-migration-workflows-storage-bucket-relocation-eventarc/data-migration-workflows-storage-bucket-relocation-eventarc.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Eventarc, Cloud Functions, Cloud Audit Logs* • ⏱️ 120 minutes
- **[DataSync Data Transfer Automation](aws/datasync-transfer-automation/datasync-transfer-automation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: datasync, s3, iam, cloudwatch* • ⏱️ 120 minutes
- **[Distributed File Systems with EFS](aws/distributed-filesystems-efs/distributed-filesystems-efs.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: efs, ec2, vpc* • ⏱️ 120 minutes
- **[EFS Mounting Strategies and Optimization](aws/efs-mounting-strategies/efs-mounting-strategies.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: efs, ec2, iam* • ⏱️ 120 minutes
- **[EFS Performance Optimization and Monitoring](aws/efs-performance-optimization/efs-performance-optimization.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: efs, cloudwatch, vpc, ec2* • ⏱️ 75 minutes
- **[Enterprise Migration Assessment and Planning](aws/enterprise-migration-assessment/enterprise-migration-assessment.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: application-discovery-service, migration-hub, s3, cloudwatch* • ⏱️ 120 minutes
- **[Establishing Global Data Replication with S3 Cross-Region Replication](aws/establishing-global-data-replication/establishing-global-data-replication.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, kms, iam, cloudwatch* • ⏱️ 120 minutes
- **[File Lifecycle Management with FSx](aws/file-lifecycle-management-fsx/file-lifecycle-management-fsx.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: FSx, Lambda, CloudWatch, EventBridge* • ⏱️ 90 minutes
- **[File System Sync with DataSync and EFS](aws/file-sync-datasync/file-sync-datasync.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: datasync, efs, s3, iam* • ⏱️ 60 minutes
- **[File Upload Notifications with Cloud Storage and Pub/Sub](gcp/file-upload-notifications-storage-pubsub/file-upload-notifications-storage-pubsub.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Pub/Sub* • ⏱️ 15 minutes
- **[High-Performance Database Workloads with Elastic SAN and VMSS](azure/high-performance-database-elastic-san-vmss/high-performance-database-elastic-san-vmss.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Elastic SAN, Virtual Machine Scale Sets, Database for PostgreSQL, Load Balancer* • ⏱️ 120 minutes
- **[High-Throughput Shared Storage System](aws/high-throughput-shared-storage/high-throughput-shared-storage.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: fsx, ec2, s3, cloudwatch* • ⏱️ 120 minutes
- **[Implementing Cross-Region Backup Automation with AWS Backup](aws/implementing-cross-region-backup-automation/implementing-cross-region-backup-automation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Backup, EventBridge, IAM, Lambda* • ⏱️ 60 minutes
- **[Intelligent Blob Storage Lifecycle Management with Cost Optimization](azure/intelligent-blob-lifecycle-management/intelligent-blob-lifecycle-management.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Storage Account, Azure Monitor, Azure Logic Apps* • ⏱️ 75 minutes
- **[Managing Files with Web Interfaces](aws/managing-files-with-web-interfaces/managing-files-with-web-interfaces.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Transfer Family, S3, IAM Identity Center, S3 Access Grants* • ⏱️ 90 minutes
- **[Monitoring S3 Access with CloudTrail and EventBridge](aws/monitoring-s3-access-with-cloudtrail/monitoring-s3-access-with-cloudtrail.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudtrail, cloudwatch, eventbridge* • ⏱️ 120 minutes
- **[Multi-Cloud Data Migration with Azure Storage Mover and Azure Monitor](azure/multi-cloud-data-migration-storage-mover-monitor/multi-cloud-data-migration-storage-mover-monitor.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Storage Mover, Azure Blob Storage, Azure Monitor, Azure Logic Apps* • ⏱️ 120 minutes
- **[Multi-Region Backup Automation with Backup and DR Service and Cloud Workflows](gcp/multi-region-backup-automation-backup-dr-service-workflows/multi-region-backup-automation-backup-dr-service-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Backup and DR Service, Cloud Workflows, Cloud Scheduler, Cloud Monitoring* • ⏱️ 120 minutes
- **[Optimizing Large File Uploads with S3 Multipart Strategies](aws/optimizing-large-file-uploads/optimizing-large-file-uploads.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudwatch* • ⏱️ 45 minutes
- **[Optimizing Storage Costs with S3 Storage Classes](aws/optimizing-storage-costs-s3/optimizing-storage-costs-s3.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudwatch, budgets, cost-explorer* • ⏱️ 90 minutes
- **[Optimizing Storage with S3 Analytics and Reporting](aws/optimizing-storage-with-s3-analytics/optimizing-storage-with-s3-analytics.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, athena, quicksight, cloudwatch* • ⏱️ 90 minutes
- **[Proactive Disaster Recovery with Backup Center Automation](azure/proactive-disaster-recovery-backup-automation/proactive-disaster-recovery-backup-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Backup Center, Azure Recovery Services Vault, Azure Monitor, Azure Logic Apps* • ⏱️ 120 minutes
- **[Replicating S3 Data Across Regions with Encryption](aws/replicating-s3-data-across-regions/replicating-s3-data-across-regions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, kms, iam, cloudwatch* • ⏱️ 120 minutes
- **[S3 Automated Tiering and Lifecycle Management](aws/s3-automated-tiering/s3-automated-tiering.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudwatch, iam* • ⏱️ 45 minutes
- **[S3 Cross-Region Disaster Recovery](aws/disaster-recovery-s3-replication/disaster-recovery-s3-replication.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, iam, cloudtrail, cloudwatch* • ⏱️ 120 minutes
- **[S3 Disaster Recovery Solutions](aws/disaster-recovery-solutions-s3/disaster-recovery-solutions-s3.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, CloudWatch, CloudTrail, IAM* • ⏱️ 180 minutes
- **[S3 Glacier Deep Archive for Long-term Storage](aws/s3-glacier-archiving/s3-glacier-archiving.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, glacier* • ⏱️ 30 minutes
- **[Seamless Hybrid Cloud Storage](aws/seamless-hybrid-storage/seamless-hybrid-storage.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: storage-gateway, s3, cloudwatch, kms* • ⏱️ 120 minutes
- **[Secure File Sharing with S3 Presigned URLs](aws/secure-file-sharing/secure-file-sharing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, iam* • ⏱️ 30 minutes
- **[Serving Static Content with S3 and CloudFront](aws/serving-static-content-s3/serving-static-content-s3.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudfront, acm, route53* • ⏱️ 45 minutes
- **[Sharing Files Securely with Web Portals](aws/sharing-files-securely-with-web-portals/sharing-files-securely-with-web-portals.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Transfer Family, S3, IAM Identity Center, CloudTrail* • ⏱️ 90 minutes
- **[Simple File Backup Automation using Logic Apps and Storage](azure/simple-file-backup-logic-apps-storage/simple-file-backup-logic-apps-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Logic Apps, Blob Storage* • ⏱️ 20 minutes
- **[Simple File Backup Notifications with S3 and SNS](aws/simple-file-backup-notifications-s3-sns/simple-file-backup-notifications-s3-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, SNS* • ⏱️ 20 minutes
- **[Simple File Sharing with Cloud Storage and Functions](gcp/file-sharing-storage-functions/file-sharing-storage-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Cloud Functions, Cloud Console* • ⏱️ 18 minutes
- **[Simple File Sharing with Transfer Family Web Apps](aws/simple-file-sharing-transfer-web-apps/simple-file-sharing-transfer-web-apps.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Transfer Family, S3, IAM* • ⏱️ 25 minutes
- **[Simple File Sync with Azure File Sync and Storage](azure/simple-file-sync-azure-file-sync-storage/simple-file-sync-azure-file-sync-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure File Sync, Azure Storage, Azure Files* • ⏱️ 30 minutes

---

## 🛢️ Databases & Analytics

*Relational databases, NoSQL, data warehousing, and big data analytics*

- **[Accelerating High-Performance Analytics Workflows with Cloud Storage FUSE and Parallelstore](gcp/high-performance-analytics-cloud-storage-fuse-parallelstore/high-performance-analytics-cloud-storage-fuse-parallelstore.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage FUSE, Parallelstore, Cloud Dataproc, BigQuery* • ⏱️ 150 minutes
- **[ACID-Compliant Distributed Databases with Amazon QLDB](aws/acid-compliant-distributed-databases/acid-compliant-distributed-databases.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: QLDB, IAM, S3, Kinesis* • ⏱️ 240 minutes
- **[ACID-Compliant Ledger Database with QLDB](aws/acid-compliant-ledger-qldb/acid-compliant-ledger-qldb.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: QLDB, IAM, S3, Kinesis* • ⏱️ 210 minutes
- **[Adaptive Marketing Campaign Intelligence with Vertex AI Agents and Google Workspace Flows](gcp/adaptive-marketing-campaign-intelligence-vertex-ai-agents-workspace-flows/adaptive-marketing-campaign-intelligence-vertex-ai-agents-workspace-flows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Google Workspace, BigQuery, Gmail API* • ⏱️ 120 minutes
- **[AI Cost Monitoring with Foundry and Application Insights](azure/ai-cost-monitoring-foundry-insights/ai-cost-monitoring-foundry-insights.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Application Insights, Azure Monitor* • ⏱️ 45 minutes
- **[AI-Powered Cost Analytics with BigQuery Analytics Hub and Vertex AI](gcp/ai-powered-cost-analytics-bigquery-analytics-hub-vertex-ai/ai-powered-cost-analytics-bigquery-analytics-hub-vertex-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Analytics Hub, Vertex AI, Cloud Monitoring* • ⏱️ 120 minutes
- **[Analytics-Optimized S3 Tables Storage](aws/analytics-optimized-s3-tables/analytics-optimized-s3-tables.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3 Tables, Amazon Athena, AWS Glue, Amazon QuickSight* • ⏱️ 120 minutes
- **[Analytics-Ready S3 Tables Storage](aws/analytics-ready-s3-tables/analytics-ready-s3-tables.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, S3 Tables, Athena, Glue* • ⏱️ 75 minutes
- **[Analyzing Operational Data with CloudWatch Insights](aws/operational-analytics-cloudwatch-insights/operational-analytics-cloudwatch-insights.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cloudwatch, lambda, sns, iam* • ⏱️ 120 minutes
- **[Analyzing Streaming Data with EMR on EKS and Flink](aws/streaming-analytics-emr-eks-flink/streaming-analytics-emr-eks-flink.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EMR, EKS, Kinesis, S3* • ⏱️ 180 minutes
- **[Analyzing Time-Series Data with Timestream](aws/analyzing-timeseries-data-timestream/analyzing-timeseries-data-timestream.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: timestream, lambda, iot-core, cloudwatch* • ⏱️ 120 minutes
- **[Architecting Distributed Database Applications with Aurora DSQL](aws/architecting-distributed-database-applications/architecting-distributed-database-applications.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Aurora DSQL, Lambda, EventBridge* • ⏱️ 120 minutes
- **[Architecting Enterprise-Grade Database Performance with NetApp Volumes and AlloyDB](gcp/enterprise-database-performance-netapp-alloydb/enterprise-database-performance-netapp-alloydb.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: NetApp Volumes, AlloyDB, Cloud Monitoring, Cloud Build* • ⏱️ 150 minutes
- **[Architecting Intelligent Retail Inventory Optimization with Fleet Engine and Route Optimization API](gcp/intelligent-retail-inventory-optimization/intelligent-retail-inventory-optimization.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Maps Platform, Route Optimization API, Cloud Run, BigQuery* • ⏱️ 150 minutes
- **[Architecting NoSQL Databases with DynamoDB Global Tables](aws/nosql-database-architectures-dynamodb-global-tables/nosql-database-architectures-dynamodb-global-tables.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: DynamoDB, IAM, CloudWatch, KMS* • ⏱️ 90 minutes
- **[Aurora Migration with Minimal Downtime](aws/aurora-migration-minimal-downtime/aurora-migration-minimal-downtime.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: dms, aurora, route53, cloudwatch* • ⏱️ 120 minutes
- **[Aurora Serverless Cost Optimization Patterns](aws/aurora-serverless-cost-optimization/aurora-serverless-cost-optimization.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Aurora Serverless v2, CloudWatch, RDS, IAM* • ⏱️ 180 minutes
- **[Automated Query Performance Alerts with Cloud SQL and Functions](gcp/automated-query-alerts-sql-functions/automated-query-alerts-sql-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud SQL, Cloud Functions, Cloud Monitoring* • ⏱️ 30 minutes
- **[Automated Solar Assessment with Solar API and Functions](gcp/automated-solar-assessment-maps-functions/automated-solar-assessment-maps-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Maps Platform Solar API, Cloud Functions, Cloud Storage* • ⏱️ 25 minutes
- **[Automated Video Analysis with Video Indexer and Functions](azure/automated-video-analysis-indexer-functions/automated-video-analysis-indexer-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Video Indexer, Azure Functions, Azure Blob Storage* • ⏱️ 45 minutes
- **[Automating Database Performance with AlloyDB AI and Cloud Monitoring Intelligence](gcp/database-performance-automation-alloydb-ai-monitoring-intelligence/database-performance-automation-alloydb-ai-monitoring-intelligence.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: AlloyDB, Cloud Monitoring, Cloud Functions, Vertex AI* • ⏱️ 120 minutes
- **[Autonomous Data Pipeline Optimization with AI Agents](azure/autonomous-data-pipeline-optimization-agents/autonomous-data-pipeline-optimization-agents.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure Data Factory, Azure Monitor, Azure Event Grid* • ⏱️ 150 minutes
- **[Basic Database Web App with SQL Database and App Service](azure/basic-database-web-app-sql-app-service/basic-database-web-app-sql-app-service.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure SQL Database, Azure App Service* • ⏱️ 20 minutes
- **[Bedrock Multi-Agent AI Workflows with AgentCore](aws/bedrock-multi-agent-ai/bedrock-multi-agent-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Bedrock, Amazon EventBridge, AWS Lambda, DynamoDB* • ⏱️ 120 minutes
- **[Building Real-time Analytics Dashboards with Kinesis Analytics and QuickSight](aws/real-time-analytics-dashboards-kinesis-quicksight/real-time-analytics-dashboards-kinesis-quicksight.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Kinesis Data Streams, Managed Service for Apache Flink, QuickSight, S3* • ⏱️ 90 minutes
- **[Business Intelligence Dashboards with QuickSight](aws/business-intelligence-quicksight-dashboards/business-intelligence-quicksight-dashboards.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: QuickSight, S3, IAM, RDS* • ⏱️ 90 minutes
- **[Business Intelligence Query Assistant with OpenAI and SQL Database](azure/business-intelligence-query-assistant-openai-sql/business-intelligence-query-assistant-openai-sql.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Azure SQL Database, Azure Functions* • ⏱️ 30 minutes
- **[Business Intelligence Solutions with QuickSight](aws/business-intelligence-solutions-quicksight/business-intelligence-solutions-quicksight.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: QuickSight, S3, Athena, Redshift* • ⏱️ 120 minutes
- **[Carbon Footprint Analytics with QuickSight](aws/carbon-footprint-analytics/carbon-footprint-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Customer Carbon Footprint Tool, Amazon QuickSight, AWS Cost Explorer, AWS Lambda* • ⏱️ 120 minutes
- **[Carbon Footprint Monitoring with Cloud Asset Inventory and Vertex AI Agents](gcp/carbon-footprint-monitoring-asset-inventory-vertex-ai-agents/carbon-footprint-monitoring-asset-inventory-vertex-ai-agents.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Asset Inventory, Vertex AI, BigQuery, Cloud Monitoring* • ⏱️ 105 minutes
- **[Carbon-Intelligent Manufacturing with Azure Industrial IoT and Sustainability Manager](azure/carbon-intelligent-manufacturing-azure-industrial-iot/carbon-intelligent-manufacturing-azure-industrial-iot.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Industrial IoT, Azure Sustainability Manager, Azure Event Grid, Azure Data Explorer* • ⏱️ 120 minutes
- **[CloudWatch Log Analytics with Insights](aws/cloudwatch-log-analytics/cloudwatch-log-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch Logs, Lambda, SNS, EventBridge* • ⏱️ 120 minutes
- **[Collaborative Data Science Workflows with Colab Enterprise and Dataform](gcp/collaborative-data-science-workflows-colab-enterprise-dataform/collaborative-data-science-workflows-colab-enterprise-dataform.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Colab Enterprise, Dataform, BigQuery, Cloud Storage* • ⏱️ 120 minutes
- **[Collaborative Monitoring Dashboards with WebSocket Synchronization](azure/collaborative-monitoring-dashboards-websocket/collaborative-monitoring-dashboards-websocket.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Web PubSub, Azure Monitor, Azure Static Web Apps, Azure Functions* • ⏱️ 90 minutes
- **[Comprehensive Data Governance Pipeline with Purview Discovery](azure/comprehensive-data-governance-pipeline/comprehensive-data-governance-pipeline.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Purview, Azure Data Lake Storage, Azure Synapse Analytics* • ⏱️ 120 minutes
- **[Comprehensive Database Modernization with Migration Service and Azure Backup](azure/comprehensive-database-modernization/comprehensive-database-modernization.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Database Migration Service, Azure Backup, Azure Monitor, Azure SQL Database* • ⏱️ 120 minutes
- **[Computer Vision Applications with Rekognition](aws/computer-vision-rekognition-apps/computer-vision-rekognition-apps.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Rekognition, S3, Lambda, Kinesis* • ⏱️ 75 minutes
- **[Computer Vision Solutions with Rekognition](aws/computer-vision-solutions-rekognition/computer-vision-solutions-rekognition.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Rekognition, S3, Lambda, DynamoDB* • ⏱️ 75 minutes
- **[Content Performance Optimization using Gemini and Analytics](gcp/content-performance-optimization-gemini-analytics/content-performance-optimization-gemini-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, BigQuery* • ⏱️ 35 minutes
- **[Content Syndication with Hierarchical Namespace Storage and Agent Development Kit](gcp/content-syndication-hierarchical-namespace-storage-agent-development-kit/content-syndication-hierarchical-namespace-storage-agent-development-kit.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Agent Development Kit, Vertex AI, Cloud Workflows* • ⏱️ 120 minutes
- **[Coordinated Database Migration with Airflow Workflows](azure/coordinated-database-migration-airflow-workflows/coordinated-database-migration-airflow-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Factory, Azure Database Migration Service, Azure Monitor* • ⏱️ 120 minutes
- **[Cost-Optimized Analytics with S3 Tiering](aws/cost-optimized-analytics-s3/cost-optimized-analytics-s3.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, Athena, Glue, CloudWatch* • ⏱️ 120 minutes
- **[Cross-Account Data Sharing with Data Exchange](aws/cross-account-data-sharing-exchange/cross-account-data-sharing-exchange.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Data Exchange, S3, IAM, EventBridge* • ⏱️ 180 minutes
- **[Cross-Database Analytics Federation with AlloyDB Omni and BigQuery](gcp/cross-database-analytics-federation-alloydb-omni-bigquery/cross-database-analytics-federation-alloydb-omni-bigquery.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: AlloyDB Omni, BigQuery, Dataplex, Cloud Functions* • ⏱️ 120 minutes
- **[Data Catalog Governance with AWS Glue](aws/data-catalog-governance-glue/data-catalog-governance-glue.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: glue, lake-formation, cloudtrail, iam* • ⏱️ 120 minutes
- **[Data Expiration Automation with DynamoDB TTL](aws/simple-data-expiration-dynamodb-ttl/simple-data-expiration-dynamodb-ttl.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: DynamoDB* • ⏱️ 25 minutes
- **[Data Governance Pipelines with DataZone](aws/data-governance-datazone-config/data-governance-datazone-config.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: DataZone, Config, EventBridge, Lambda* • ⏱️ 120 minutes
- **[Data Governance Workflows with Dataplex and Cloud Workflows](gcp/data-governance-workflows-dataplex-workflows/data-governance-workflows-dataplex-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Dataplex, Cloud Workflows, Cloud DLP, BigQuery* • ⏱️ 120 minutes
- **[Data Lake Architectures with Lake Formation](aws/data-lake-s3-lakeformation/data-lake-s3-lakeformation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, lakeformation, glue, iam* • ⏱️ 180 minutes
- **[Data Lake Architectures with S3 and Glue](aws/data-lake-s3-glue-athena/data-lake-s3-glue-athena.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: S3, Glue, Athena, IAM* • ⏱️ 120 minutes
- **[Data Lake Fine-Grained Access Control with Lake Formation](aws/data-lake-fine-grained-access/data-lake-fine-grained-access.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lake Formation, Glue, IAM, S3* • ⏱️ 180 minutes
- **[Data Lake Governance with Dataplex and BigLake](gcp/data-lake-governance-dataplex-biglake/data-lake-governance-dataplex-biglake.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Dataplex, BigLake, Cloud Functions, BigQuery* • ⏱️ 120 minutes
- **[Data Lake Governance with Lake Formation](aws/data-lake-governance-formation/data-lake-governance-formation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lake Formation, DataZone, S3, Glue* • ⏱️ 240 minutes
- **[Data Lake Ingestion Pipelines with Glue](aws/data-lake-ingestion-glue/data-lake-ingestion-glue.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Glue, S3, IAM, CloudWatch* • ⏱️ 240 minutes
- **[Data Pipeline Automation with BigQuery Continuous Queries and Cloud KMS](gcp/data-pipeline-automation-bigquery-continuous-queries-kms/data-pipeline-automation-bigquery-continuous-queries-kms.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Cloud KMS, Cloud Scheduler, Cloud Logging* • ⏱️ 120 minutes
- **[Data Pipeline Orchestration with Glue Workflows](aws/data-pipeline-orchestration-glue/data-pipeline-orchestration-glue.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: glue, s3, iam, cloudwatch* • ⏱️ 120 minutes
- **[Data Pipeline Recovery Workflows with Dataform and Cloud Tasks](gcp/data-pipeline-recovery-dataform-tasks/data-pipeline-recovery-dataform-tasks.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Dataform, Cloud Tasks, Cloud Monitoring, Cloud Functions* • ⏱️ 120 minutes
- **[Data Quality Monitoring with DataBrew](aws/data-quality-monitoring-databrew/data-quality-monitoring-databrew.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: glue-databrew, s3, cloudwatch, eventbridge* • ⏱️ 120 minutes
- **[Data Quality Monitoring with Dataform and Cloud Scheduler](gcp/data-quality-monitoring-dataform-scheduler/data-quality-monitoring-dataform-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Dataform, Cloud Scheduler, Cloud Monitoring, BigQuery* • ⏱️ 120 minutes
- **[Data Quality Pipelines with DataBrew](aws/data-quality-pipelines-databrew/data-quality-pipelines-databrew.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Glue DataBrew, Amazon EventBridge, Amazon S3, AWS Lambda* • ⏱️ 120 minutes
- **[Data Visualization Pipelines with QuickSight](aws/data-visualization-quicksight-s3/data-visualization-quicksight-s3.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: QuickSight, S3, Athena, Glue* • ⏱️ 180 minutes
- **[Data Warehousing Solutions with Redshift](aws/data-warehousing-redshift/data-warehousing-redshift.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: redshift, s3, iam, cloudwatch* • ⏱️ 120 minutes
- **[Database Backup and Recovery with RDS](aws/database-backup-recovery-rds/database-backup-recovery-rds.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds, backup, kms, iam* • ⏱️ 120 minutes
- **[Database Connection Pooling with RDS Proxy](aws/database-connection-pooling-rds/database-connection-pooling-rds.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds-proxy, rds, lambda, secrets-manager* • ⏱️ 90 minutes
- **[Database Development Workflows with AlloyDB Omni and Cloud Workstations](gcp/database-development-alloydb-omni-workstations/database-development-alloydb-omni-workstations.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: AlloyDB Omni, Cloud Workstations, Cloud Source Repositories, Cloud Build* • ⏱️ 120 minutes
- **[Database Disaster Recovery with Backup and DR Service and Cloud SQL](gcp/database-disaster-recovery-backup-dr-service-sql/database-disaster-recovery-backup-dr-service-sql.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Backup and DR Service, Cloud SQL, Cloud Scheduler, Cloud Functions* • ⏱️ 120 minutes
- **[Database Disaster Recovery with Read Replicas](aws/database-dr-cross-region/database-dr-cross-region.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: RDS, CloudWatch, SNS, Lambda* • ⏱️ 240 minutes
- **[Database Maintenance Automation with Cloud SQL and Cloud Scheduler](gcp/database-maintenance-automation-sql-scheduler/database-maintenance-automation-sql-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud SQL, Cloud Scheduler, Cloud Monitoring, Cloud Functions* • ⏱️ 90 minutes
- **[Database Migration Health and Performance with Cloud Workload Manager and Cloud Functions](gcp/database-migration-health-performance-workload-manager-functions/database-migration-health-performance-workload-manager-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Workload Manager, Database Migration Service, Cloud Functions, Cloud Monitoring* • ⏱️ 120 minutes
- **[Database Migration Strategies with DMS](aws/database-migration-strategies-dms/database-migration-strategies-dms.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: dms, rds, vpc, s3* • ⏱️ 180 minutes
- **[Database Migration with AWS DMS](aws/database-migration-dms/database-migration-dms.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: dms, rds, vpc, iam* • ⏱️ 180 minutes
- **[Database Migration with Schema Conversion Tool](aws/database-migration-sct-dms/database-migration-sct-dms.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: dms, sct, rds, ec2* • ⏱️ 180 minutes
- **[Database Monitoring Dashboards with CloudWatch](aws/database-monitoring-cloudwatch/database-monitoring-cloudwatch.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cloudwatch, rds, sns, iam* • ⏱️ 120 minutes
- **[Database Performance Monitoring with Cloud SQL Insights and Cloud Monitoring](gcp/database-performance-monitoring-sql-insights-monitoring/database-performance-monitoring-sql-insights-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud SQL, Cloud SQL Insights, Cloud Monitoring, Cloud Functions* • ⏱️ 75 minutes
- **[Database Performance Monitoring with RDS Insights](aws/database-performance-monitoring-rds/database-performance-monitoring-rds.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds, cloudwatch, lambda, sns* • ⏱️ 120 minutes
- **[Database Performance Optimization with AlloyDB Omni and Hyperdisk Extreme](gcp/database-performance-optimization-alloydb-omni-hyperdisk-extreme/database-performance-optimization-alloydb-omni-hyperdisk-extreme.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: AlloyDB Omni, Hyperdisk Extreme, Cloud Monitoring, Cloud Functions* • ⏱️ 45 minutes
- **[Database Performance Tuning with Parameters](aws/database-performance-tuning-parameters/database-performance-tuning-parameters.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds, cloudwatch, performance-insights, ec2* • ⏱️ 120 minutes
- **[Database Query Caching with ElastiCache](aws/database-query-caching-elasticache/database-query-caching-elasticache.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: elasticache, rds, vpc, ec2* • ⏱️ 120 minutes
- **[Database Query Optimization with BigQuery AI and Cloud Composer](gcp/database-query-optimization-bigquery-ai-composer/database-query-optimization-bigquery-ai-composer.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Cloud Composer, Vertex AI, Cloud Monitoring* • ⏱️ 120 minutes
- **[Database Scaling with Aurora Serverless](aws/database-scaling-aurora-serverless/database-scaling-aurora-serverless.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds, aurora, cloudwatch, iam* • ⏱️ 60 minutes
- **[Deploying Global Database Replication with Aurora Global Database](aws/deploying-global-database-replication/deploying-global-database-replication.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: aurora, rds, cloudwatch, iam* • ⏱️ 240 minutes
- **[Detecting Real-time Anomalies with Kinesis Data Analytics](aws/real-time-anomaly-detection-kinesis-flink/real-time-anomaly-detection-kinesis-flink.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kinesis-data-streams, managed-service-for-apache-flink, cloudwatch, sns* • ⏱️ 120 minutes
- **[Developing Distributed Serverless Applications with Aurora DSQL](aws/developing-distributed-serverless-applications/developing-distributed-serverless-applications.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Aurora DSQL, Lambda, API Gateway, Route 53* • ⏱️ 120 minutes
- **[Distributed Data Processing Workflows with Cloud Dataproc and Cloud Scheduler](gcp/distributed-data-processing-workflows-dataproc-scheduler/distributed-data-processing-workflows-dataproc-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Dataproc, Cloud Scheduler, Cloud Storage, BigQuery* • ⏱️ 120 minutes
- **[Document Processing Pipelines with Textract and Step Functions](aws/document-processing-textract-stepfunctions/document-processing-textract-stepfunctions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Textract, Step Functions, S3, Lambda* • ⏱️ 120 minutes
- **[Dynamic Delivery Route Optimization with Maps Platform and BigQuery](gcp/dynamic-delivery-route-optimization-maps-bigquery/dynamic-delivery-route-optimization-maps-bigquery.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Maps Platform Route Optimization API, BigQuery, Cloud Functions* • ⏱️ 45 minutes
- **[Dynamic Pricing Optimization using BigQuery and Vertex AI](gcp/dynamic-pricing-optimization-bigquery-vertex-ai/dynamic-pricing-optimization-bigquery-vertex-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Vertex AI, Cloud Functions, Cloud Scheduler* • ⏱️ 45 minutes
- **[DynamoDB Global Tables for Multi-Region Apps](aws/dynamodb-global-tables-multiregion/dynamodb-global-tables-multiregion.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: dynamodb, cloudwatch, iam, lambda* • ⏱️ 120 minutes
- **[DynamoDB Global Tables with Streaming](aws/dynamodb-global-streaming/dynamodb-global-streaming.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: DynamoDB, Kinesis Data Streams, Lambda, EventBridge* • ⏱️ 180 minutes
- **[Edge-to-Cloud Video Analytics with Media CDN and Vertex AI](gcp/edge-to-cloud-video-analytics-media-cdn-vertex-ai/edge-to-cloud-video-analytics-media-cdn-vertex-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Media CDN, Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 120 minutes
- **[Enabling Operational Analytics with Amazon Redshift Spectrum](aws/operational-analytics-amazon-redshift-spectrum/operational-analytics-amazon-redshift-spectrum.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Redshift, S3, Glue, IAM* • ⏱️ 180 minutes
- **[Enterprise Data Discovery with Data Catalog and Cloud Workflows](gcp/enterprise-data-discovery-catalog-workflows/enterprise-data-discovery-catalog-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Data Catalog, Cloud Workflows, BigQuery, Cloud Functions* • ⏱️ 120 minutes
- **[Enterprise Database Analytics with Oracle and Vertex AI](gcp/enterprise-database-analytics-oracle-vertex-ai/enterprise-database-analytics-oracle-vertex-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Oracle Database@Google Cloud, Vertex AI, Cloud Monitoring, BigQuery* • ⏱️ 45 minutes
- **[Enterprise-Grade ML Model Lifecycle Management with AI Hypercomputer and Vertex AI Training](gcp/enterprise-ml-model-lifecycle-management-ai-hypercomputer-vertex-ai-training/enterprise-ml-model-lifecycle-management-ai-hypercomputer-vertex-ai-training.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: AI Hypercomputer, Vertex AI Training, Cloud Workstations, Cloud Storage* • ⏱️ 150 minutes
- **[Environmental Sustainability Data Pipelines with Data Factory and Sustainability Manager](azure/environmental-sustainability-data-pipelines/environmental-sustainability-data-pipelines.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Factory, Azure Sustainability Manager, Azure Monitor, Azure Functions* • ⏱️ 120 minutes
- **[Establishing Centralized Data Lake Governance with Dataproc Metastore and BigQuery](gcp/centralized-data-lake-governance-dataproc-metastore-bigquery/centralized-data-lake-governance-dataproc-metastore-bigquery.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Dataproc Metastore, BigQuery, Cloud Storage, Dataproc* • ⏱️ 120 minutes
- **[Establishing Database High Availability with Multi-AZ Deployments](aws/establishing-database-high-availability/establishing-database-high-availability.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds, vpc, cloudwatch, systems-manager* • ⏱️ 120 minutes
- **[ETL Pipelines with Glue Data Catalog](aws/glue-etl-catalog/glue-etl-catalog.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: glue, s3, athena, iam* • ⏱️ 120 minutes
- **[Event-Driven Data Synchronization with Cloud Datastore and Cloud Pub/Sub](gcp/event-driven-data-synchronization-datastore-pub-sub/event-driven-data-synchronization-datastore-pub-sub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Datastore, Cloud Pub/Sub, Cloud Functions, Cloud Logging* • ⏱️ 90 minutes
- **[Financial Analytics Dashboard with QuickSight](aws/financial-analytics-dashboard-quicksight/financial-analytics-dashboard-quicksight.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: QuickSight, Cost Explorer, S3, Lambda* • ⏱️ 300 minutes
- **[Financial Trading Algorithm Optimization with Quantum and Elastic SAN](azure/financial-trading-optimization-quantum-elastic-san/financial-trading-optimization-quantum-elastic-san.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Quantum, Azure Elastic SAN, Azure Machine Learning, Azure Monitor* • ⏱️ 150 minutes
- **[Fleet Tracking with Geospatial Analytics](azure/fleet-tracking-geospatial-analytics/fleet-tracking-geospatial-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Maps, Azure Stream Analytics, Azure Event Hubs, Azure Monitor* • ⏱️ 90 minutes
- **[Global E-commerce with Distributed SQL](aws/distributed-sql-ecommerce-platform/distributed-sql-ecommerce-platform.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Aurora DSQL, API Gateway, Lambda, CloudFront* • ⏱️ 90 minutes
- **[Governed Cross-Tenant Data Collaboration with Data Share and Purview](azure/governed-cross-tenant-data-collaboration/governed-cross-tenant-data-collaboration.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Share, Microsoft Purview, Azure Storage, Azure Active Directory* • ⏱️ 120 minutes
- **[Graph-Based Recommendation Engine](aws/graph-based-recommendation-system/graph-based-recommendation-system.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: neptune, vpc, ec2, iam* • ⏱️ 180 minutes
- **[Healthcare Edge Analytics with SQL Edge and FHIR Compliance](azure/healthcare-edge-analytics-sql-fhir-compliance/healthcare-edge-analytics-sql-fhir-compliance.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure SQL Edge, Azure Health Data Services, Azure IoT Hub, Azure Functions* • ⏱️ 120 minutes
- **[High-Frequency Trading Risk Analytics with TPU v6e and Cloud Datastream](gcp/high-frequency-trading-risk-analytics-tpu-ironwood-cloud-datastream/high-frequency-trading-risk-analytics-tpu-ironwood-cloud-datastream.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: TPU v6e, Cloud Datastream, BigQuery, Cloud Run* • ⏱️ 180 minutes
- **[High-Velocity Financial Analytics with Azure Data Explorer and Event Hubs](azure/high-velocity-financial-analytics-azure-data-explorer/high-velocity-financial-analytics-azure-data-explorer.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Explorer, Azure Event Hubs, Azure Functions, Azure Event Grid* • ⏱️ 120 minutes
- **[HIPAA-Compliant Healthcare Analytics](aws/hipaa-compliant-healthcare-analytics/hipaa-compliant-healthcare-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: HealthLake, Lambda, S3, EventBridge* • ⏱️ 90 minutes
- **[Hybrid PostgreSQL Database Replication with Azure Arc and Cloud Database](azure/hybrid-postgresql-database-replication/hybrid-postgresql-database-replication.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Arc-enabled Data Services, Azure Database for PostgreSQL, Azure Event Grid, Azure Data Factory* • ⏱️ 120 minutes
- **[Hybrid Search Document Analysis with OpenAI and PostgreSQL](azure/hybrid-search-document-analysis-openai-postgresql/hybrid-search-document-analysis-openai-postgresql.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Azure AI Search, Azure Database for PostgreSQL, Azure Functions* • ⏱️ 120 minutes
- **[Hybrid SQL Management with Arc-enabled Data Services](azure/hybrid-sql-management-arc-data-services/hybrid-sql-management-arc-data-services.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Arc, SQL Managed Instance, Azure Monitor, Azure Kubernetes Service* • ⏱️ 120 minutes
- **[Implementing Climate Risk Assessment with Earth Engine and BigQuery](gcp/climate-risk-assessment-earth-engine-bigquery/climate-risk-assessment-earth-engine-bigquery.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Earth Engine, BigQuery, Cloud Functions, Cloud Monitoring* • ⏱️ 105 minutes
- **[Implementing Enterprise Search with OpenSearch Service](aws/implementing-enterprise-search-with-opensearch/implementing-enterprise-search-with-opensearch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: OpenSearch Service, Lambda, S3, IAM* • ⏱️ 240 minutes
- **[Implementing Real-Time Analytics with Amazon Kinesis Data Streams](aws/real-time-analytics-kinesis-data-streams/real-time-analytics-kinesis-data-streams.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kinesis, lambda, cloudwatch, s3* • ⏱️ 180 minutes
- **[Infrastructure Cost Optimization with Cloud Billing API and Cloud Functions](gcp/infrastructure-cost-optimization-billing-api-functions/infrastructure-cost-optimization-billing-api-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Billing API, Cloud Functions, Cloud Monitoring, BigQuery* • ⏱️ 120 minutes
- **[Intelligent Database Scaling with SQL Hyperscale and Logic Apps](azure/intelligent-database-scaling/intelligent-database-scaling.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure SQL Database Hyperscale, Azure Logic Apps, Azure Monitor, Azure Key Vault* • ⏱️ 90 minutes
- **[Intelligent Product Search with Cloud SQL and Vertex AI](gcp/intelligent-product-search-mysql-vertex-ai/intelligent-product-search-mysql-vertex-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud SQL, Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 120 minutes
- **[Intelligent Web Scraping with AgentCore Browser and Code Interpreter](aws/intelligent-web-scraping-browser-codeinterpreter/intelligent-web-scraping-browser-codeinterpreter.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock AgentCore, Lambda, S3, CloudWatch* • ⏱️ 60 minutes
- **[Interactive Data Analytics with Bedrock AgentCore Code Interpreter](aws/interactive-data-analytics-bedrock-codeinterpreter/interactive-data-analytics-bedrock-codeinterpreter.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock, S3, Lambda, CloudWatch* • ⏱️ 45 minutes
- **[Interactive Data Pipeline Prototypes with Cloud Data Fusion and Colab Enterprise](gcp/interactive-data-pipeline-prototypes-data-fusion-colab-enterprise/interactive-data-pipeline-prototypes-data-fusion-colab-enterprise.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Data Fusion, Colab Enterprise, BigQuery, Cloud Storage* • ⏱️ 120 minutes
- **[Interactive Data Storytelling with BigQuery Data Canvas and Looker Studio](gcp/interactive-data-storytelling-bigquery-data-canvas-looker-studio/interactive-data-storytelling-bigquery-data-canvas-looker-studio.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Looker Studio, Cloud Scheduler, Vertex AI* • ⏱️ 90 minutes
- **[IoT Dashboard Visualization with QuickSight](aws/iot-dashboard-visualization/iot-dashboard-visualization.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, kinesis, s3, quicksight* • ⏱️ 120 minutes
- **[IoT Telemetry Analytics with Kinesis and Timestream](aws/iot-telemetry-analytics/iot-telemetry-analytics.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IoT Core, Kinesis, Timestream, Lambda* • ⏱️ 90 minutes
- **[Large-Scale Data Processing with BigQuery Serverless Spark](gcp/large-scale-data-processing-bigquery-serverless-spark/large-scale-data-processing-bigquery-serverless-spark.md)** - ![Unknown](https://img.shields.io/badge/Unknown-lightgrey) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Serverless Spark, Cloud Storage* • ⏱️ 45 minutes
- **[Legacy Database Applications with Database Migration Service and Application Design Center](gcp/legacy-database-applications-database-migration-service-application-design-center/legacy-database-applications-database-migration-service-application-design-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Database Migration Service, Application Design Center, Cloud SQL, Gemini Code Assist* • ⏱️ 120 minutes
- **[Live Search Results with Cognitive Search and SignalR](azure/live-search-results-cognitive-search/live-search-results-cognitive-search.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cognitive Search, Azure SignalR Service, Azure Functions, Azure Event Grid* • ⏱️ 90 minutes
- **[Location-Based Service Recommendations with Google Maps Platform and Vertex AI](gcp/location-based-service-recommendations-maps-platform-vertex-ai/location-based-service-recommendations-maps-platform-vertex-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Maps Platform, Vertex AI, Cloud Run, Cloud Firestore* • ⏱️ 120 minutes
- **[Migrate Multi-tenant MariaDB Workloads to MySQL Flexible Server](azure/migrate-mariadb-mysql-flexible-server-multi-tenant/migrate-mariadb-mysql-flexible-server-multi-tenant.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Database for MariaDB, Azure Database for MySQL, Azure Monitor, Azure Application Insights* • ⏱️ 120 minutes
- **[MongoDB to Firestore Migration with API Compatibility](gcp/mongodb-firestore-migration-compatibility/mongodb-firestore-migration-compatibility.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firestore, Cloud Functions, Cloud Build* • ⏱️ 45 minutes
- **[Monitor Distributed Cassandra Databases with Managed Grafana](azure/monitor-cassandra-distributed-databases-managed-grafana/monitor-cassandra-distributed-databases-managed-grafana.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Managed Instance for Apache Cassandra, Azure Managed Grafana, Azure Monitor, Azure Virtual Network* • ⏱️ 90 minutes
- **[Monitoring Data Quality with Deequ on EMR](aws/data-quality-monitoring-deequ/data-quality-monitoring-deequ.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: emr, s3, cloudwatch, sns* • ⏱️ 120 minutes
- **[Multi-AZ PostgreSQL Cluster](aws/multi-az-postgresql-cluster/multi-az-postgresql-cluster.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds, cloudwatch, sns, iam* • ⏱️ 180 minutes
- **[Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner](gcp/multi-database-disaster-recovery-alloydb-spanner/multi-database-disaster-recovery-alloydb-spanner.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: AlloyDB, Cloud Spanner, Cloud Storage, Cloud Scheduler* • ⏱️ 150 minutes
- **[Multi-Database ETL Orchestration with Data Factory](azure/multi-database-etl-orchestration-data-factory/multi-database-etl-orchestration-data-factory.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Factory, Azure Database for MySQL, Azure Key Vault, Azure Monitor* • ⏱️ 120 minutes
- **[Multi-Database Migration Workflows with Database Migration Service and Dynamic Workload Scheduler](gcp/multi-database-migration-workflows-database-migration-service-dynamic-workload-scheduler/multi-database-migration-workflows-database-migration-service-dynamic-workload-scheduler.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Database Migration Service, Cloud Functions, Cloud SQL, AlloyDB* • ⏱️ 120 minutes
- **[Multi-Region Disaster Recovery with Aurora DSQL](aws/multi-region-dr-aurora-dsql/multi-region-dr-aurora-dsql.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Aurora DSQL, EventBridge, Lambda, CloudWatch* • ⏱️ 120 minutes
- **[Multi-Regional Energy Consumption with Cloud Carbon Footprint and Smart Analytics Hub](gcp/multi-regional-energy-consumption-carbon-footprint-smart-analytics-hub/multi-regional-energy-consumption-carbon-footprint-smart-analytics-hub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Analytics Hub, Cloud Scheduler, Cloud Functions* • ⏱️ 120 minutes
- **[Multi-Stream Data Processing Workflows with Pub/Sub Lite and Application Integration](gcp/multi-stream-data-processing-workflows-pub-sub-lite-application-integration/multi-stream-data-processing-workflows-pub-sub-lite-application-integration.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Pub/Sub Lite, Application Integration, Cloud Dataflow, BigQuery* • ⏱️ 120 minutes
- **[Multi-Tenant Database Optimization with Elastic Pools and Backup Vault](azure/multi-tenant-database-optimization/multi-tenant-database-optimization.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure SQL Database, Azure Elastic Database Pool, Azure Backup Vault, Azure Cost Management* • ⏱️ 120 minutes
- **[Multi-Tenant SaaS Analytics and Cost Attribution Platform](azure/multi-tenant-saas-analytics-platform/multi-tenant-saas-analytics-platform.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Application Insights, Data Explorer, Cost Management* • ⏱️ 120 minutes
- **[OpenSearch Data Ingestion Pipelines](aws/data-ingestion-opensearch-eventbridge/data-ingestion-opensearch-eventbridge.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: OpenSearch Ingestion, EventBridge Scheduler, S3, IAM* • ⏱️ 120 minutes
- **[Optimizing Amazon Redshift Performance](aws/redshift-performance-optimization/redshift-performance-optimization.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: redshift, cloudwatch, sns, lambda* • ⏱️ 90 minutes
- **[Oracle to PostgreSQL Migration with DMS](aws/oracle-postgresql-migration-dms/oracle-postgresql-migration-dms.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: DMS, RDS, Aurora PostgreSQL, Schema Conversion Tool* • ⏱️ 300 minutes
- **[Patient Sentiment Analysis with Cloud Healthcare API and Natural Language AI](gcp/patient-sentiment-analysis-healthcare-api-natural-language-ai/patient-sentiment-analysis-healthcare-api-natural-language-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Healthcare API, Cloud Natural Language, Cloud Functions, BigQuery* • ⏱️ 90 minutes
- **[PostgreSQL Disaster Recovery Automation with Flexible Server and Backup Services](azure/postgresql-disaster-recovery-automation/postgresql-disaster-recovery-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Database for PostgreSQL, Azure Backup, Azure Monitor, Azure Storage* • ⏱️ 120 minutes
- **[Precision Agriculture Analytics with AI-Driven Insights](azure/precision-agriculture-analytics-platform/precision-agriculture-analytics-platform.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Manager for Agriculture, Azure AI Services, Azure Maps, Azure Stream Analytics* • ⏱️ 150 minutes
- **[Privacy-Preserving Analytics with Clean Rooms](aws/privacy-preserving-analytics-cleanrooms/privacy-preserving-analytics-cleanrooms.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Clean Rooms, QuickSight, S3, Glue* • ⏱️ 120 minutes
- **[Processing Data with AWS Glue and Lambda](aws/processing-data-glue-lambda/processing-data-glue-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Glue, Lambda, S3, CloudWatch* • ⏱️ 150 minutes
- **[Processing IoT Analytics with Kinesis and Flink](aws/iot-analytics-kinesis-flink/iot-analytics-kinesis-flink.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kinesis, kinesisanalyticsv2, lambda, s3* • ⏱️ 180 minutes
- **[Processing Streaming Data with Kinesis Data Firehose](aws/streaming-data-processing-firehose/streaming-data-processing-firehose.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Kinesis, Lambda, S3, OpenSearch* • ⏱️ 120 minutes
- **[Quantum-Enhanced Financial Risk Analytics Platform](azure/quantum-enhanced-financial-risk-analytics/quantum-enhanced-financial-risk-analytics.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Quantum, Azure Synapse Analytics, Azure Machine Learning, Azure Key Vault* • ⏱️ 150 minutes
- **[Quantum-Enhanced Manufacturing Quality Control with Azure Quantum and Machine Learning](azure/quantum-enhanced-manufacturing-quality-control/quantum-enhanced-manufacturing-quality-control.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Quantum, Azure Machine Learning, Azure IoT Hub, Azure Stream Analytics* • ⏱️ 180 minutes
- **[Querying Data Across Sources with Athena](aws/querying-data-across-sources-with-athena/querying-data-across-sources-with-athena.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: athena, lambda, s3, rds* • ⏱️ 120 minutes
- **[RDS Disaster Recovery Solutions](aws/disaster-recovery-rds/disaster-recovery-rds.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: RDS, EventBridge, SNS, Lambda, +1 more* • ⏱️ 90 minutes
- **[RDS Multi-Region Failover Strategy](aws/rds-multi-region-failover/rds-multi-region-failover.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: RDS, Route 53, CloudWatch, Lambda* • ⏱️ 240 minutes
- **[Real-Time Analytics Automation with BigQuery Continuous Queries and Agentspace](gcp/real-time-analytics-automation-bigquery-continuous-queries-agentspace/real-time-analytics-automation-bigquery-continuous-queries-agentspace.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Vertex AI Agent Builder, Cloud Workflows, Pub/Sub* • ⏱️ 90 minutes
- **[Real-Time Analytics Dashboards with Datastream and Looker Studio](gcp/real-time-analytics-dashboards-datastream-looker-studio/real-time-analytics-dashboards-datastream-looker-studio.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Datastream, BigQuery, Looker Studio* • ⏱️ 120 minutes
- **[Real-Time Analytics with Cloud Dataflow and Firestore](gcp/real-time-analytics-dataflow-firestore/real-time-analytics-dataflow-firestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Dataflow, Cloud Pub/Sub, Firestore, Cloud Storage* • ⏱️ 120 minutes
- **[Real-Time Behavioral Analytics with Cloud Run Worker Pools and Cloud Firestore](gcp/real-time-behavioral-analytics-run-worker-pools-firestore/real-time-behavioral-analytics-run-worker-pools-firestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Cloud Firestore, Pub/Sub, Cloud Monitoring* • ⏱️ 120 minutes
- **[Real-Time Data Science Model Training with Vertex AI Workbench and Memorystore Redis](gcp/real-time-data-science-model-training-vertex-ai-workbench-memorystore-redis/real-time-data-science-model-training-vertex-ai-workbench-memorystore-redis.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Workbench, Memorystore Redis, Cloud Batch, Cloud Monitoring* • ⏱️ 120 minutes
- **[Real-Time Document Intelligence Pipelines with Cloud Storage and Document AI](gcp/real-time-document-intelligence-pipelines-storage-document-ai/real-time-document-intelligence-pipelines-storage-document-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Document AI, Cloud Pub/Sub, Firestore* • ⏱️ 120 minutes
- **[Real-Time Fleet Optimization with Cloud Fleet Routing API and Cloud Bigtable](gcp/real-time-fleet-optimization-fleet-routing-api-bigtable/real-time-fleet-optimization-fleet-routing-api-bigtable.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Fleet Routing API, Cloud Bigtable, Pub/Sub, Cloud Functions* • ⏱️ 120 minutes
- **[Real-Time Fraud Detection with Machine Learning](azure/real-time-fraud-detection-pipeline/real-time-fraud-detection-pipeline.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Stream Analytics, Azure Machine Learning, Azure Event Hubs, Azure Functions* • ⏱️ 120 minutes
- **[Real-Time IoT Data Processing with Cloud IoT Core and Cloud Dataprep](gcp/real-time-iot-data-processing-iot-core-dataprep/real-time-iot-data-processing-iot-core-dataprep.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud IoT Core, Cloud Dataprep, BigQuery, Cloud Pub/Sub* • ⏱️ 120 minutes
- **[Real-Time ML Feature Engineering Pipelines with Cloud Batch and Vertex AI Feature Store](gcp/real-time-ml-feature-engineering-pipelines-batch-vertex-ai-feature-store/real-time-ml-feature-engineering-pipelines-batch-vertex-ai-feature-store.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Batch, Vertex AI Feature Store, Pub/Sub, BigQuery* • ⏱️ 120 minutes
- **[Real-Time Stream Enrichment with Kinesis and EventBridge](aws/real-time-stream-enrichment/real-time-stream-enrichment.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Kinesis Data Streams, EventBridge Pipes, Lambda, DynamoDB* • ⏱️ 90 minutes
- **[Real-Time Supply Chain Visibility with Cloud Dataflow and Cloud Spanner](gcp/real-time-supply-chain-visibility-dataflow-spanner/real-time-supply-chain-visibility-dataflow-spanner.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Dataflow, Cloud Spanner, Pub/Sub, BigQuery* • ⏱️ 120 minutes
- **[Real-Time Trading Signal Analysis with Multimodal AI](azure/real-time-trading-signal-analysis-multimodal/real-time-trading-signal-analysis-multimodal.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cognitive Services, Azure Stream Analytics, Azure Functions, Azure Event Hubs* • ⏱️ 120 minutes
- **[Redshift Analytics Workload Isolation](aws/redshift-workload-isolation/redshift-workload-isolation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Redshift, CloudWatch, IAM, SNS* • ⏱️ 180 minutes
- **[Route Optimization with Google Maps Routes API and Cloud Optimization AI](gcp/route-optimization-maps-routes-api-optimization-ai/route-optimization-maps-routes-api-optimization-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Maps Routes API, Cloud Run, Cloud SQL, Pub/Sub* • ⏱️ 120 minutes
- **[SageMaker AutoML for Time Series Forecasting](aws/sagemaker-automl-forecasting/sagemaker-automl-forecasting.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sagemaker, s3, iam, lambda* • ⏱️ 180 minutes
- **[Satellite Imagery Analytics with Azure Orbital and AI Services](azure/satellite-imagery-analytics-azure-orbital-ai/satellite-imagery-analytics-azure-orbital-ai.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Orbital, Synapse Analytics, AI Services, Azure Maps* • ⏱️ 150 minutes
- **[Scalable Serverless Data Pipeline with Synapse and Data Factory](azure/scalable-serverless-data-pipeline/scalable-serverless-data-pipeline.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Synapse Analytics, Azure Data Factory, Azure Data Lake Storage Gen2, Azure Key Vault* • ⏱️ 120 minutes
- **[Scalable Video Content Moderation Pipeline](azure/scalable-video-content-moderation/scalable-video-content-moderation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Content Safety, Azure Event Hubs, Azure Stream Analytics, Azure Logic Apps* • ⏱️ 120 minutes
- **[Scientific Video Analysis Workflows with Cluster Toolkit and Gemini Fine-tuning](gcp/scientific-video-analysis-workflows-cluster-toolkit-gemini-fine-tuning/scientific-video-analysis-workflows-cluster-toolkit-gemini-fine-tuning.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cluster Toolkit, Vertex AI, Cloud Dataflow, Cloud Storage* • ⏱️ 150 minutes
- **[Scientific Workflow Orchestration with Cloud Batch API and Vertex AI Workbench](gcp/scientific-workflow-orchestration-batch-api-vertex-ai-workbench/scientific-workflow-orchestration-batch-api-vertex-ai-workbench.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Batch, Vertex AI Workbench, Cloud Storage, BigQuery* • ⏱️ 150 minutes
- **[Semantic Image Content Discovery with AI Vision](azure/semantic-image-content-discovery/semantic-image-content-discovery.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Vision, Azure AI Search, Azure Storage, Azure Functions* • ⏱️ 120 minutes
- **[Serverless Data Lake Architecture](aws/serverless-data-lake-architecture/serverless-data-lake-architecture.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, Glue, EventBridge, S3* • ⏱️ 300 minutes
- **[Serverless Data Mesh with Databricks and API Management](azure/serverless-data-mesh-databricks-api-management/serverless-data-mesh-databricks-api-management.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Databricks, Azure API Management, Azure Event Grid, Azure Key Vault* • ⏱️ 120 minutes
- **[Serverless Graph Analytics with Cosmos DB Gremlin and Functions](azure/serverless-graph-analytics-cosmos-gremlin-functions/serverless-graph-analytics-cosmos-gremlin-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cosmos DB for Apache Gremlin, Azure Functions, Azure Event Grid, Azure Monitor* • ⏱️ 90 minutes
- **[Serverless Medical Image Processing with HealthImaging](aws/serverless-medical-image-processing/serverless-medical-image-processing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS HealthImaging, Step Functions, Lambda, EventBridge* • ⏱️ 90 minutes
- **[Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights](aws/service-performance-cost-analytics-lattice-insights/service-performance-cost-analytics-lattice-insights.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, CloudWatch Insights, Cost Explorer, Lambda* • ⏱️ 45 minutes
- **[Simple Expense Tracker with Cosmos DB and Functions](azure/simple-expense-tracker-cosmos-functions/simple-expense-tracker-cosmos-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cosmos DB, Azure Functions* • ⏱️ 20 minutes
- **[Simulating Cities with SimSpace Weaver and IoT](aws/simulating-cities-simspace-weaver/simulating-cities-simspace-weaver.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SimSpace Weaver, IoT Core, DynamoDB, Lambda* • ⏱️ 120 minutes
- **[Smart Energy Grid Analytics with Digital Twins](azure/smart-energy-grid-analytics-digital-twins/smart-energy-grid-analytics-digital-twins.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Manager for Energy, Azure Digital Twins, Azure AI Services, Azure Time Series Insights* • ⏱️ 150 minutes
- **[Smart Product Review Analysis with Translation and Natural Language AI](gcp/smart-product-review-analysis-translation-natural-language/smart-product-review-analysis-translation-natural-language.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Translation, Natural Language AI, Cloud Functions, BigQuery* • ⏱️ 35 minutes
- **[Streaming Analytics with Kinesis and Lambda](aws/streaming-analytics-kinesis-lambda/streaming-analytics-kinesis-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kinesis, lambda, dynamodb, cloudwatch* • ⏱️ 120 minutes
- **[Streaming Clickstream Analytics with Kinesis Data Streams](aws/streaming-clickstream-analytics-kinesis/streaming-clickstream-analytics-kinesis.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Kinesis Data Streams, Lambda, DynamoDB, CloudWatch* • ⏱️ 180 minutes
- **[Streaming Data Enrichment with Kinesis and Lambda](aws/data-enrichment-kinesis-lambda/data-enrichment-kinesis-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kinesis, lambda, dynamodb, s3* • ⏱️ 120 minutes
- **[Streaming ETL with Kinesis Data Firehose](aws/streaming-etl-firehose/streaming-etl-firehose.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kinesis-firehose, lambda, s3, cloudwatch* • ⏱️ 90 minutes
- **[Streamlining Smart City Data Processing with Cloud Dataprep and BigQuery DataCanvas](gcp/streamlining-smart-city-data-processing-with-cloud-dataprep-and-bigquery-datacanvas/streamlining-smart-city-data-processing-with-cloud-dataprep-and-bigquery-datacanvas.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Dataprep, BigQuery, Pub/Sub, Cloud Storage* • ⏱️ 120 minutes
- **[Supply Chain Analytics with Cloud Bigtable and Cloud Dataproc](gcp/supply-chain-analytics-bigtable-dataproc/supply-chain-analytics-bigtable-dataproc.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Bigtable, Cloud Dataproc, Cloud Scheduler, Cloud Monitoring* • ⏱️ 120 minutes
- **[Supply Chain Carbon Tracking with AI Agents](azure/supply-chain-carbon-tracking-ai-agents/supply-chain-carbon-tracking-ai-agents.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Services, Microsoft Sustainability Manager, Azure Service Bus, Azure Functions* • ⏱️ 120 minutes
- **[Sustainability Compliance Automation with Carbon Footprint and Functions](gcp/sustainability-compliance-automation-carbon-footprint-functions/sustainability-compliance-automation-carbon-footprint-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Carbon Footprint, BigQuery, Cloud Scheduler* • ⏱️ 30 minutes
- **[Sustainable Infrastructure Intelligence with Smart Analytics Hub and Cloud Carbon Footprint](gcp/sustainable-infrastructure-intelligence-smart-analytics-hub-carbon-footprint/sustainable-infrastructure-intelligence-smart-analytics-hub-carbon-footprint.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Cloud Carbon Footprint, Looker Studio, Cloud Functions* • ⏱️ 120 minutes
- **[Synchronizing Real-time Data with AWS AppSync](aws/real-time-sync-appsync/real-time-sync-appsync.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: appsync, dynamodb, iam, cloudwatch* • ⏱️ 120 minutes
- **[Team Collaboration Insights with Workspace Events API and Cloud Functions](gcp/team-collaboration-insights-workspace-events-functions/team-collaboration-insights-workspace-events-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Workspace Events API, Cloud Functions, Cloud Firestore, Pub/Sub* • ⏱️ 90 minutes
- **[Time Series Forecasting with TimesFM and BigQuery DataCanvas](gcp/time-series-forecasting-timesfm-bigquery-datacanvas/time-series-forecasting-timesfm-bigquery-datacanvas.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, BigQuery, Cloud Functions, Cloud Scheduler* • ⏱️ 120 minutes
- **[Transforming Data with Kinesis Data Firehose](aws/data-transformation-firehose/data-transformation-firehose.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Kinesis Data Firehose, Lambda, S3, CloudWatch* • ⏱️ 45 minutes
- **[Visual Document Processing with Cloud Filestore and Vision AI](gcp/visual-document-processing-filestore-vision-ai/visual-document-processing-filestore-vision-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Filestore, Cloud Vision AI, Cloud Pub/Sub, Cloud Functions* • ⏱️ 120 minutes
- **[Workforce Analytics with Workspace Events API and Cloud Run Worker Pools](gcp/workforce-analytics-workspace-events-api-run-worker-pools/workforce-analytics-workspace-events-api-run-worker-pools.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Workspace Events API, Cloud Run, BigQuery, Cloud Monitoring* • ⏱️ 180 minutes
- **[Zero-Downtime Database Migrations with Cloud SQL and Database Migration Service](gcp/zero-downtime-database-migrations-sql-database-migration-service/zero-downtime-database-migrations-sql-database-migration-service.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Database Migration Service, Cloud SQL, Cloud Monitoring, Cloud Logging* • ⏱️ 120 minutes

---

## 🌐 Networking & Content Delivery

*Virtual networks, load balancing, CDN, DNS, and network security*

- **[Accelerating Gaming Backend Performance with Cloud Memorystore and Cloud CDN](gcp/gaming-backend-performance-cloud-memorystore-cdn/gaming-backend-performance-cloud-memorystore-cdn.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Memorystore, Cloud CDN, Cloud Load Balancing, Compute Engine* • ⏱️ 120 minutes
- **[Accelerating Global Web Application Performance with Firebase App Hosting and Cloud CDN](gcp/global-web-application-performance-firebase-app-hosting-cdn/global-web-application-performance-firebase-app-hosting-cdn.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase App Hosting, Cloud CDN, Cloud Monitoring, Cloud Functions* • ⏱️ 90 minutes
- **[Advanced Request Routing with VPC Lattice and ALB](aws/advanced-request-routing-lattice-alb/advanced-request-routing-lattice-alb.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Application Load Balancer, EC2* • ⏱️ 45 minutes
- **[API Gateway with Custom Domain Names](aws/api-gateway-custom-domains/api-gateway-custom-domains.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: API Gateway, Route 53, ACM, Lambda* • ⏱️ 90 minutes
- **[Application Health Monitoring with VPC Lattice and CloudWatch](aws/application-health-monitoring-lattice-cloudwatch/application-health-monitoring-lattice-cloudwatch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, CloudWatch, Lambda, SNS* • ⏱️ 45 minutes
- **[Architecting Distributed Edge Computing Networks with Cloud CDN and Compute Engine](gcp/distributed-edge-computing-networks-cloud-cdn-compute-engine/distributed-edge-computing-networks-cloud-cdn-compute-engine.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud CDN, Compute Engine, Cloud Load Balancing, Cloud DNS* • ⏱️ 120 minutes
- **[Auto Scaling with Load Balancers](aws/auto-scaling-alb-target-groups/auto-scaling-alb-target-groups.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Application Load Balancer, Auto Scaling, EC2, CloudWatch* • ⏱️ 180 minutes
- **[Automated Service Lifecycle with VPC Lattice and EventBridge](aws/automated-service-lifecycle-lattice-eventbridge/automated-service-lifecycle-lattice-eventbridge.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, EventBridge, Lambda, CloudWatch* • ⏱️ 45 minutes
- **[Basic Network Setup with Virtual Network and Subnets](azure/basic-network-setup-vnet-subnets/basic-network-setup-vnet-subnets.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Virtual Network, Resource Groups* • ⏱️ 15 minutes
- **[Blue-Green Deployments with VPC Lattice and Lambda](aws/blue-green-deployments-lattice-lambda/blue-green-deployments-lattice-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Lambda, CloudWatch, IAM* • ⏱️ 45 minutes
- **[Building Global Active-Active Architecture with AWS Global Accelerator](aws/building-global-active-active-architecture/building-global-active-active-architecture.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: GlobalAccelerator, DynamoDB, Lambda, ApplicationLoadBalancer* • ⏱️ 90 minutes
- **[Canary Deployments with VPC Lattice and Lambda](aws/canary-deployments-lattice-lambda/canary-deployments-lattice-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Lambda, CloudWatch* • ⏱️ 45 minutes
- **[CDN with CloudFront Origin Access Controls](aws/cdn-cloudfront-origin-access/cdn-cloudfront-origin-access.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFront, S3, WAF, CloudWatch* • ⏱️ 75 minutes
- **[Cloud-Native Service Connectivity with Application Gateway for Containers](azure/cloud-native-service-connectivity/cloud-native-service-connectivity.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Application Gateway for Containers, Service Connector, Azure Workload Identity, Azure Kubernetes Service* • ⏱️ 120 minutes
- **[CloudFront Cache Invalidation Strategies](aws/cloudfront-cache-invalidation-strategies/cloudfront-cache-invalidation-strategies.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFront, Lambda, S3, CloudWatch* • ⏱️ 120 minutes
- **[CloudFront Real-Time Monitoring and Analytics](aws/cloudfront-realtime-monitoring/cloudfront-realtime-monitoring.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFront, Kinesis, Lambda, OpenSearch* • ⏱️ 90 minutes
- **[Comprehensive Network Performance Monitoring Solution](azure/comprehensive-network-performance-monitoring/comprehensive-network-performance-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Network Watcher, Application Insights, Azure Monitor, Log Analytics* • ⏱️ 120 minutes
- **[Connecting Multi-Region Networks with Transit Gateway](aws/connecting-multi-region-networks/connecting-multi-region-networks.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: transit-gateway, vpc, cloudwatch, ec2* • ⏱️ 180 minutes
- **[Content Delivery Networks with CloudFront](aws/content-delivery-networks-cloudfront/content-delivery-networks-cloudfront.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFront, S3, Lambda, WAF* • ⏱️ 200 minutes
- **[Content Delivery Networks with CloudFront S3](aws/cdn-cloudfront-s3/cdn-cloudfront-s3.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFront, S3, Route 53, CloudWatch* • ⏱️ 150 minutes
- **[Cross-Account Database Sharing with VPC Lattice and RDS](aws/cross-account-database-sharing-lattice-rds/cross-account-database-sharing-lattice-rds.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, RDS, IAM, CloudWatch* • ⏱️ 45 minutes
- **[Cross-Account Service Discovery with VPC Lattice and ECS](aws/cross-account-service-discovery-lattice-ecs/cross-account-service-discovery-lattice-ecs.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, ECS, EventBridge, CloudWatch* • ⏱️ 45 minutes
- **[Cross-Region Service Failover with VPC Lattice and Route53](aws/cross-region-service-failover-lattice-route53/cross-region-service-failover-lattice-route53.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Route53, Lambda, CloudWatch* • ⏱️ 90 minutes
- **[Dedicated Hybrid Cloud Connectivity](aws/dedicated-network-connectivity/dedicated-network-connectivity.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: direct-connect, vpc, transit-gateway, route-53* • ⏱️ 120 minutes
- **[Designing Advanced VPC Peering with Complex Routing Scenarios](aws/designing-advanced-vpc-peering/designing-advanced-vpc-peering.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC, Route Tables, Route 53, CloudWatch* • ⏱️ 240 minutes
- **[Distributed Service Tracing with VPC Lattice and X-Ray](aws/distributed-service-tracing-lattice-xray/distributed-service-tracing-lattice-xray.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, X-Ray, Lambda, CloudWatch* • ⏱️ 45 minutes
- **[Distributed Session Management with MemoryDB](aws/session-management-memorydb-alb/session-management-memorydb-alb.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: MemoryDB, Application Load Balancer, ECS, Systems Manager* • ⏱️ 90 minutes
- **[DNS-Based Load Balancing with Route 53](aws/dns-load-balancing-route53/dns-load-balancing-route53.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: route53, ec2, elb* • ⏱️ 120 minutes
- **[Domain Health Monitoring with Cloud Domains and Cloud Functions](gcp/domain-health-monitoring-domains-functions/domain-health-monitoring-domains-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Domains, Cloud Functions, Cloud Monitoring* • ⏱️ 75 minutes
- **[Dynamic Content Delivery with Firebase Hosting and Cloud CDN](gcp/dynamic-content-delivery-firebase-hosting-cdn/dynamic-content-delivery-firebase-hosting-cdn.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Hosting, Cloud CDN, Cloud Functions, Cloud Storage* • ⏱️ 75 minutes
- **[Edge Caching Performance with Cloud CDN and Memorystore](gcp/edge-caching-performance-cdn-memorystore/edge-caching-performance-cdn-memorystore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud CDN, Memorystore for Redis, Cloud Load Balancing, Cloud Storage* • ⏱️ 120 minutes
- **[Elastic Load Balancing with ALB and NLB](aws/elastic-load-balancing-alb-nlb/elastic-load-balancing-alb-nlb.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: alb, nlb, ec2, target, +1 more* • ⏱️ 60 minutes
- **[Enterprise Oracle Database Connectivity with VPC Lattice and S3](aws/enterprise-oracle-connectivity-lattice-s3/enterprise-oracle-connectivity-lattice-s3.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Oracle Database@AWS, S3, Redshift* • ⏱️ 50 minutes
- **[Establishing Global Content Delivery Infrastructure with Network Connectivity Center and Anywhere Cache](gcp/global-content-delivery-infrastructure-cloud-wan-anywhere-cache/global-content-delivery-infrastructure-cloud-wan-anywhere-cache.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Network Connectivity Center, Cloud Storage, Cloud Monitoring, Cloud CDN* • ⏱️ 105 minutes
- **[Establishing Global Network Performance Optimization with Cloud WAN and Network Intelligence Center](gcp/global-network-performance-optimization-cloud-wan-network-intelligence-center/global-network-performance-optimization-cloud-wan-network-intelligence-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud WAN, Network Intelligence Center, Cloud Monitoring, Cloud Load Balancing* • ⏱️ 120 minutes
- **[Global API Gateway with Multi-Region Distribution](azure/global-api-gateway-architecture/global-api-gateway-architecture.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure API Management, Azure Cosmos DB, Azure Traffic Manager, Azure Monitor* • ⏱️ 120 minutes
- **[Global Content Delivery with High-Performance Storage](azure/global-content-delivery-high-performance/global-content-delivery-high-performance.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Front Door Premium, Azure NetApp Files, Azure Private Link, Azure Monitor* • ⏱️ 120 minutes
- **[Global Traffic Distribution with Traffic Manager and Application Gateway](azure/global-traffic-distribution-traffic-manager-application-gateway/global-traffic-distribution-traffic-manager-application-gateway.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Traffic Manager, Application Gateway, Virtual Machine Scale Sets, Azure Monitor* • ⏱️ 120 minutes
- **[Global Web Application Performance Acceleration with Redis Cache and CDN](azure/global-web-application-performance-acceleration/global-web-application-performance-acceleration.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure App Service, Azure Cache for Redis, Azure CDN, Azure Database for PostgreSQL* • ⏱️ 120 minutes
- **[gRPC Microservices with VPC Lattice and CloudWatch](aws/grpc-microservices-lattice-cloudwatch/grpc-microservices-lattice-cloudwatch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, CloudWatch, EC2* • ⏱️ 45 minutes
- **[High-Performance Hybrid Database Connectivity with ExpressRoute](azure/high-performance-hybrid-database-connectivity/high-performance-hybrid-database-connectivity.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: ExpressRoute, Application Gateway, PostgreSQL Flexible Server* • ⏱️ 150 minutes
- **[Hosting Websites with S3 CloudFront and Route 53](aws/hosting-websites-s3-cloudfront/hosting-websites-s3-cloudfront.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: s3, cloudfront, route53, acm* • ⏱️ 120 minutes
- **[Hybrid DNS Resolution with Private Resolver and Network Manager](azure/hybrid-dns-resolution-private-resolver-vnm/hybrid-dns-resolution-private-resolver-vnm.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure DNS Private Resolver, Azure Virtual Network Manager, Azure Private DNS* • ⏱️ 120 minutes
- **[Hybrid Network Threat Protection with Premium Firewall](azure/hybrid-network-threat-protection/hybrid-network-threat-protection.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Firewall Premium, Azure ExpressRoute, Azure Virtual Network Gateway, Azure Monitor* • ⏱️ 150 minutes
- **[Industrial 5G Networks for Edge Computing](azure/industrial-5g-networks-edge-computing/industrial-5g-networks-edge-computing.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Operator Nexus, Azure Private 5G Core, Azure Arc* • ⏱️ 150 minutes
- **[Intelligent API Lifecycle with API Center and AI Services](azure/intelligent-api-lifecycle-center-ai-services/intelligent-api-lifecycle-center-ai-services.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure API Center, Azure AI Services, Azure API Management, Azure Monitor* • ⏱️ 90 minutes
- **[Intelligent DDoS Protection with Adaptive BGP Routing](azure/intelligent-ddos-protection-and-routing/intelligent-ddos-protection-and-routing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure DDoS Protection, Azure Route Server, Azure Network Watcher, Azure Monitor* • ⏱️ 120 minutes
- **[Intelligent Global Traffic Routing with Route53 and CloudFront](aws/intelligent-traffic-routing/intelligent-traffic-routing.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: route53, cloudfront, alb, s3* • ⏱️ 120 minutes
- **[Isolated Web Apps with Enterprise Security Controls](azure/isolated-web-apps-enterprise-security/isolated-web-apps-enterprise-security.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure App Service Environment v3, Azure Private DNS, Azure NAT Gateway, Azure Virtual Network* • ⏱️ 150 minutes
- **[Load Balancer Traffic Routing with Service Extensions and BigQuery Data Canvas](gcp/load-balancer-traffic-routing-service-extensions-bigquery-data-canvas/load-balancer-traffic-routing-service-extensions-bigquery-data-canvas.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Application Load Balancer, Service Extensions, BigQuery, Cloud Run* • ⏱️ 120 minutes
- **[Low-Latency Edge Applications with Wavelength](aws/low-latency-edge-wavelength/low-latency-edge-wavelength.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Wavelength, Amazon CloudFront, Amazon EC2, Amazon Route 53* • ⏱️ 150 minutes
- **[Managing Enterprise VPC Architectures with Transit Gateway](aws/managing-enterprise-vpc-architectures/managing-enterprise-vpc-architectures.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: transit-gateway, vpc, route-53, cloudwatch* • ⏱️ 120 minutes
- **[Monitoring Network Traffic with VPC Flow Logs](aws/network-monitoring-vpc-flow-logs/network-monitoring-vpc-flow-logs.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: vpc, cloudwatch, s3, athena* • ⏱️ 120 minutes
- **[Multi-Region Traffic Optimization with Cloud Load Balancing and Performance Monitoring](gcp/multi-region-traffic-optimization-load-balancing-performance-monitoring/multi-region-traffic-optimization-load-balancing-performance-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Load Balancing, Cloud CDN, Network Intelligence Center, Cloud Monitoring* • ⏱️ 105 minutes
- **[Multi-Tenant Resource Sharing with VPC Lattice and RAM](aws/multi-tenant-resource-sharing-lattice-ram/multi-tenant-resource-sharing-lattice-ram.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, AWS RAM, RDS, IAM* • ⏱️ 45 minutes
- **[Multi-Tier Content Caching with CloudFront and ElastiCache](aws/content-caching-cloudfront-elasticache/content-caching-cloudfront-elasticache.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFront, ElastiCache, Lambda, API Gateway* • ⏱️ 90 minutes
- **[Network Performance Optimization with Cloud WAN and Network Intelligence Center](gcp/network-performance-optimization-wan-network-intelligence-center/network-performance-optimization-wan-network-intelligence-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud WAN, Network Intelligence Center, Cloud Monitoring, Cloud Functions* • ⏱️ 120 minutes
- **[Network Troubleshooting VPC Lattice with Network Insights](aws/network-troubleshooting-lattice-insights/network-troubleshooting-lattice-insights.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, VPC Reachability Analyzer, CloudWatch, Systems Manager* • ⏱️ 50 minutes
- **[Private API Integration with VPC Lattice and EventBridge](aws/private-api-integration-lattice-eventbridge/private-api-integration-lattice-eventbridge.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, EventBridge, Step Functions, API Gateway* • ⏱️ 50 minutes
- **[Satellite Telemetry Edge Processing with Azure Orbital and Azure Local](azure/satellite-telemetry-edge-processing/satellite-telemetry-edge-processing.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Orbital, Azure Local, Azure Event Grid, Azure IoT Hub* • ⏱️ 150 minutes
- **[Secure API Gateway Architecture with Cloud Endpoints and Cloud Armor](gcp/secure-api-gateway-architecture-endpoints-armor/secure-api-gateway-architecture-endpoints-armor.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Endpoints, Cloud Armor, Cloud Load Balancing, Compute Engine* • ⏱️ 105 minutes
- **[Secure Database Access with VPC Lattice and RDS](aws/secure-database-access-lattice-gateway/secure-database-access-lattice-gateway.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, RDS, CloudWatch, IAM* • ⏱️ 45 minutes
- **[Secure Hybrid Network Architecture with VPN Gateway and Private Link](azure/secure-hybrid-network-architecture/secure-hybrid-network-architecture.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: VPN Gateway, Private Link, Key Vault, Virtual Network* • ⏱️ 120 minutes
- **[Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center](gcp/secure-multi-cloud-connectivity-nat-network-connectivity-center/secure-multi-cloud-connectivity-nat-network-connectivity-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud NAT, Network Connectivity Center, Cloud Router, Cloud VPN* • ⏱️ 120 minutes
- **[Securing Networks with Micro-Segmentation using NACLs and Security Groups](aws/securing-networks-with-micro-segmentation/securing-networks-with-micro-segmentation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC, EC2, CloudWatch, IAM* • ⏱️ 180 minutes
- **[Self-Healing Infrastructure with Traffic Manager and Load Testing](azure/self-healing-infrastructure-traffic-manager-load-testing/self-healing-infrastructure-traffic-manager-load-testing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Traffic Manager, Azure Load Testing, Azure Monitor, Azure Functions* • ⏱️ 120 minutes
- **[Service Discovery with Traffic Director and Cloud DNS](gcp/service-discovery-traffic-director-dns/service-discovery-traffic-director-dns.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Traffic Director, Cloud DNS, Cloud Load Balancing, Compute Engine* • ⏱️ 120 minutes
- **[Service Mesh Cost Analytics with VPC Lattice and Cost Explorer](aws/service-mesh-cost-analytics-lattice-explorer/service-mesh-cost-analytics-lattice-explorer.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Cost Explorer, CloudWatch, SNS* • ⏱️ 45 minutes
- **[Simple Store Locator with Azure Maps](azure/simple-store-locator-azure-maps/simple-store-locator-azure-maps.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Maps* • ⏱️ 30 minutes
- **[Site-to-Site VPN Connections with AWS](aws/site-to-site-vpn/site-to-site-vpn.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPN, VPC, EC2, CloudWatch* • ⏱️ 120 minutes
- **[Static Website Acceleration with CDN and Storage](azure/simple-static-website-acceleration-cdn-storage/simple-static-website-acceleration-cdn-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Storage Account, CDN* • ⏱️ 20 minutes
- **[Static Website Hosting with Cloud Storage and DNS](gcp/static-website-hosting-storage-dns/static-website-hosting-storage-dns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Storage, Cloud DNS* • ⏱️ 15 minutes
- **[TCP Resource Connectivity with VPC Lattice and CloudWatch](aws/tcp-resource-connectivity-lattice-cloudwatch/tcp-resource-connectivity-lattice-cloudwatch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, RDS, CloudWatch, IAM* • ⏱️ 45 minutes
- **[Traffic Analytics with VPC Lattice and OpenSearch](aws/traffic-analytics-lattice-opensearch/traffic-analytics-lattice-opensearch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, OpenSearch, Kinesis, Lambda* • ⏱️ 60 minutes
- **[Virtual Desktop Infrastructure with WorkSpaces](aws/workforce-productivity-workspaces/workforce-productivity-workspaces.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: workspaces, ds, vpc, ec2* • ⏱️ 120 minutes
- **[Zero Trust Network with VPC Endpoints](aws/zero-trust-vpc-privatelink/zero-trust-vpc-privatelink.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC, PrivateLink, Route53, IAM* • ⏱️ 180 minutes
- **[Zero-Trust Microservices Segmentation with Service Mesh](azure/zero-trust-microservices-segmentation/zero-trust-microservices-segmentation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Kubernetes Service, Azure DNS Private Zones, Azure Application Gateway, Azure Monitor* • ⏱️ 150 minutes

---

## 🔐 Security & Identity

*Identity management, access control, encryption, and security monitoring*

- **[Accessing Instances with Session Manager](aws/accessing-instances-with-session-manager/accessing-instances-with-session-manager.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager, EC2, IAM, CloudWatch* • ⏱️ 60 minutes
- **[AI Agent Governance Framework with Entra ID and Logic Apps](azure/ai-agent-governance-framework/ai-agent-governance-framework.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Entra ID, Azure Logic Apps, Azure Monitor, Azure Key Vault* • ⏱️ 120 minutes
- **[API Governance and Compliance Monitoring with Apigee X and Cloud Logging](gcp/api-governance-compliance-monitoring-apigee-x-logging/api-governance-compliance-monitoring-apigee-x-logging.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Apigee X, Cloud Logging, Eventarc, Cloud Functions* • ⏱️ 90 minutes
- **[API Security with WAF and Gateway](aws/api-security-waf-gateway/api-security-waf-gateway.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: WAF, API Gateway, CloudWatch* • ⏱️ 45 minutes
- **[Authenticating Users with Cognito User Pools](aws/authenticating-users-cognito/authenticating-users-cognito.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cognito, iam, ses, sns* • ⏱️ 120 minutes
- **[Automated Content Moderation with Content Safety and Logic Apps](azure/automated-content-moderation-safety-logic-apps/automated-content-moderation-safety-logic-apps.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Content Safety, Logic Apps, Storage Accounts* • ⏱️ 25 minutes
- **[Automated Content Safety Moderation with Logic Apps](azure/automated-content-safety-moderation-workflows/automated-content-safety-moderation-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Content Safety, Azure Logic Apps, Azure Event Grid, Azure Storage* • ⏱️ 90 minutes
- **[Automated DNS Security Monitoring](aws/dns-security-monitoring/dns-security-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Route 53 Resolver, CloudWatch, Lambda, SNS* • ⏱️ 90 minutes
- **[Automated Security Policy Governance with Policy Intelligence and Asset Inventory](gcp/automated-security-policy-governance-policy-intelligence-asset-inventory/automated-security-policy-governance-policy-intelligence-asset-inventory.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Policy Intelligence, Cloud Asset Inventory, Cloud Functions, Cloud Scheduler* • ⏱️ 45 minutes
- **[Automated Security Policy Governance with Policy Intelligence and Asset Inventory](gcp/automated-security-policy-governance/automated-security-policy-governance.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Policy Intelligence, Cloud Asset Inventory, Cloud Functions, Cloud Scheduler* • ⏱️ 45 minutes
- **[Automated Security Response with EventBridge](aws/security-automation/security-automation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, lambda, security-hub, sns* • ⏱️ 120 minutes
- **[Automated Security Response with Playbook Loops and Chronicle](gcp/automated-security-response-playbook-loops-chronicle/automated-security-response-playbook-loops-chronicle.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Chronicle SOAR, Security Command Center, Cloud Functions, Pub/Sub* • ⏱️ 45 minutes
- **[Automated Threat Response with Unified Security and Functions](gcp/automated-threat-response-unified-security-functions/automated-threat-response-unified-security-functions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Security Command Center, Cloud Functions, Cloud Logging, Pub/Sub* • ⏱️ 50 minutes
- **[Basic Secret Management with Secrets Manager and Lambda](aws/basic-secret-management-secrets-lambda/basic-secret-management-secrets-lambda.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Secrets Manager, Lambda* • ⏱️ 25 minutes
- **[Centralized Identity Federation with IAM Identity Center](aws/centralized-identity-federation/centralized-identity-federation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iam, identity-center, organizations, cloudtrail* • ⏱️ 180 minutes
- **[Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions](gcp/certificate-lifecycle-management-authority-service-functions/certificate-lifecycle-management-authority-service-functions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Certificate Authority Service, Cloud Functions, Cloud Scheduler, Secret Manager* • ⏱️ 120 minutes
- **[Compliance Monitoring with AWS Config](aws/compliance-monitoring-config/compliance-monitoring-config.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Config, Lambda, SNS, CloudWatch* • ⏱️ 85 minutes
- **[Compliance Reporting with Cloud Audit Logs and Vertex AI Document Extraction](gcp/compliance-reporting-audit-logs-vertex-ai-document-extraction/compliance-reporting-audit-logs-vertex-ai-document-extraction.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Audit Logs, Document AI, Cloud Storage, Cloud Scheduler* • ⏱️ 120 minutes
- **[Compliance Violation Detection with Cloud Audit Logs and Eventarc](gcp/compliance-violation-detection-audit-logs-eventarc/compliance-violation-detection-audit-logs-eventarc.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Audit Logs, Eventarc, Cloud Functions, Cloud Logging* • ⏱️ 75 minutes
- **[Confidential Computing with Hardware-Protected Enclaves](azure/confidential-computing-secure-enclaves/confidential-computing-secure-enclaves.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Confidential Computing, Azure Attestation, Azure Managed HSM, Azure Key Vault* • ⏱️ 120 minutes
- **[Container Security Pipeline with Binary Authorization and Cloud Deploy](gcp/container-security-pipeline-binary-authorization-deploy/container-security-pipeline-binary-authorization-deploy.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Binary Authorization, Cloud Deploy, Artifact Registry, Cloud Build* • ⏱️ 75 minutes
- **[Container Security Scanning with Artifact Registry and Cloud Build](gcp/container-security-scanning-artifact-registry-build/container-security-scanning-artifact-registry-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Artifact Registry, Cloud Build, Binary Authorization, Security Command Center* • ⏱️ 120 minutes
- **[Container Security Scanning with Registry and Defender for Cloud](azure/container-security-scanning/container-security-scanning.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Registry, Microsoft Defender for Cloud, Azure Policy, Azure DevOps* • ⏱️ 90 minutes
- **[Container Vulnerability Remediation Pipeline with DevSecOps](azure/container-vulnerability-remediation-pipeline/container-vulnerability-remediation-pipeline.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Registry, Azure DevOps, Azure Policy, Azure Monitor* • ⏱️ 90 minutes
- **[Container Vulnerability Scanning with ECR](aws/container-vulnerability-scanning-ecr/container-vulnerability-scanning-ecr.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ECR, Inspector, CloudWatch, EventBridge* • ⏱️ 150 minutes
- **[Cross-Account Compliance Monitoring with Security Hub](aws/multi-account-compliance-monitoring/multi-account-compliance-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager, Security Hub, CloudTrail, IAM* • ⏱️ 120 minutes
- **[Cross-Account Data Access with Lake Formation](aws/cross-account-data-access-lakeformation/cross-account-data-access-lakeformation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lake Formation, Glue, IAM, S3* • ⏱️ 90 minutes
- **[Cross-Account IAM Role Federation](aws/cross-account-iam-federation/cross-account-iam-federation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IAM, STS, CloudTrail, Organizations* • ⏱️ 120 minutes
- **[Data Encryption at Rest and in Transit](aws/data-encryption-rest-transit/data-encryption-rest-transit.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kms, s3, rds, certificate-manager* • ⏱️ 120 minutes
- **[Data Privacy Compliance with Cloud Data Loss Prevention and Security Command Center](gcp/data-privacy-compliance-data-loss-prevention-security-command-center/data-privacy-compliance-data-loss-prevention-security-command-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Data Loss Prevention, Security Command Center, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes
- **[Data Privacy Compliance with Cloud DLP and BigQuery](gcp/data-privacy-compliance-dlp-bigquery/data-privacy-compliance-dlp-bigquery.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Data Loss Prevention, BigQuery, Cloud Storage, Cloud Functions* • ⏱️ 105 minutes
- **[Database Security with Encryption and IAM](aws/database-security-encryption-iam/database-security-encryption-iam.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rds, kms, iam, cloudwatch* • ⏱️ 120 minutes
- **[Decentralized Identity Management with Blockchain](aws/decentralized-identity-blockchain/decentralized-identity-blockchain.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: managed-blockchain, qldb, iam, lambda* • ⏱️ 240 minutes
- **[Defense-in-Depth API Security with Azure API Management and Web Application Firewall](azure/defense-in-depth-api-security-azure-waf/defense-in-depth-api-security-azure-waf.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure API Management, Azure Web Application Firewall, Azure Application Gateway, Azure Private Link* • ⏱️ 105 minutes
- **[DNS Threat Detection with Armor and Security Center](gcp/dns-threat-detection-armor-security/dns-threat-detection-armor-security.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Armor, Security Command Center, Cloud Functions* • ⏱️ 45 minutes
- **[Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager](gcp/domain-certificate-lifecycle-dns-manager/domain-certificate-lifecycle-dns-manager.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud DNS, Certificate Manager, Cloud Scheduler, Cloud Functions* • ⏱️ 75 minutes
- **[Edge-Secured Web Applications with Azure Static Web Apps and Front Door WAF](azure/edge-secured-web-applications-azure-front-door/edge-secured-web-applications-azure-front-door.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Static Web Apps, Azure Front Door, Azure Web Application Firewall* • ⏱️ 90 minutes
- **[EKS Multi-Tenant Security with Namespaces](aws/eks-multitenant-security/eks-multitenant-security.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EKS, IAM, Kubernetes, VPC* • ⏱️ 180 minutes
- **[End-to-End Encryption with VPC Lattice TLS Passthrough](aws/tls-passthrough-lattice-acm/tls-passthrough-lattice-acm.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, Certificate Manager, Route 53, EC2* • ⏱️ 40 minutes
- **[Enterprise API Protection with Premium Management and WAF](azure/enterprise-api-protection-premium-waf/enterprise-api-protection-premium-waf.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure API Management Premium, Azure Web Application Firewall, Azure Cache for Redis Enterprise, Azure Application Insights* • ⏱️ 150 minutes
- **[Enterprise Authentication with Amplify and Identity Providers](aws/enterprise-auth-amplify-idp/enterprise-auth-amplify-idp.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amplify, Cognito, IAM, CloudFormation* • ⏱️ 120 minutes
- **[Enterprise Identity Federation with Bedrock AgentCore](aws/enterprise-identity-federation-bedrock-agentcore/enterprise-identity-federation-bedrock-agentcore.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock, Cognito, IAM, Lambda* • ⏱️ 45 minutes
- **[Enterprise Identity Federation Workflows with Cloud IAM and Service Directory](gcp/enterprise-identity-federation-workflows-iam-service-directory/enterprise-identity-federation-workflows-iam-service-directory.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud IAM, Service Directory, Cloud Functions, Secret Manager* • ⏱️ 120 minutes
- **[Enterprise KMS Envelope Encryption](aws/enterprise-kms-envelope-encryption/enterprise-kms-envelope-encryption.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: kms, s3, lambda* • ⏱️ 120 minutes
- **[Establishing Multi-Environment Development Isolation with VPC Service Controls and Cloud Workstations](gcp/multi-environment-development-isolation-vpc-service-controls-cloud-workstations/multi-environment-development-isolation-vpc-service-controls-cloud-workstations.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: VPC Service Controls, Cloud Workstations, Cloud Filestore, Identity-Aware Proxy* • ⏱️ 150 minutes
- **[Event-Driven Security Governance with Event Grid and Managed Identity](azure/event-driven-security-governance/event-driven-security-governance.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Event Grid, Managed Identity, Resource Manager, Monitor* • ⏱️ 90 minutes
- **[Federated Container Storage Security with Azure Workload Identity and Container Storage](azure/federated-container-storage-security-azure-workload-identity/federated-container-storage-security-azure-workload-identity.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Workload Identity, Azure Container Storage, Azure Key Vault, Azure Kubernetes Service* • ⏱️ 120 minutes
- **[Financial Compliance Monitoring with AML AI and BigQuery](gcp/financial-compliance-aml-ai-bigquery/financial-compliance-aml-ai-bigquery.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: BigQuery, Cloud Functions, Cloud Scheduler, Pub/Sub* • ⏱️ 60 minutes
- **[Financial Fraud Detection with Accessible Alert Summaries](azure/financial-fraud-detection-accessible-alerts/financial-fraud-detection-accessible-alerts.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Metrics Advisor, Azure AI Immersive Reader, Azure Logic Apps, Azure Storage* • ⏱️ 105 minutes
- **[Fine-Grained Access Control with IAM](aws/iam-access-control/iam-access-control.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iam, s3, cloudwatch, sts* • ⏱️ 120 minutes
- **[Fine-Grained API Authorization with Verified Permissions](aws/fine-grained-api-auth-verified/fine-grained-api-auth-verified.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: verified-permissions, api-gateway, cognito, lambda* • ⏱️ 120 minutes
- **[Governing Costs with Strategic Resource Tagging](aws/governing-costs-with-tagging/governing-costs-with-tagging.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Config, Cost Explorer, Resource Groups, SNS* • ⏱️ 120 minutes
- **[Healthcare Data Compliance Workflows with Cloud Healthcare API and Cloud Tasks](gcp/healthcare-data-compliance-workflows-healthcare-api-tasks/healthcare-data-compliance-workflows-healthcare-api-tasks.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Healthcare API, Cloud Tasks, Cloud Functions, Cloud Audit Logs* • ⏱️ 120 minutes
- **[Immutable Audit Trails with Blockchain Technology](azure/immutable-audit-trails-blockchain/immutable-audit-trails-blockchain.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Confidential Ledger, Azure Logic Apps, Azure Key Vault, Azure Event Hubs* • ⏱️ 90 minutes
- **[Intelligent Cloud Threat Detection with GuardDuty](aws/intelligent-threat-detection/intelligent-threat-detection.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: guardduty, eventbridge, sns, s3* • ⏱️ 45 minutes
- **[IoT Certificate Security with X.509 Authentication](aws/iot-certificate-security/iot-certificate-security.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, iot-device-defender, iam, cloudwatch* • ⏱️ 120 minutes
- **[IoT Security Monitoring with Device Defender](aws/iot-security-monitoring/iot-security-monitoring.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot, sns, cloudwatch, iam* • ⏱️ 90 minutes
- **[Managing Secrets with Automated Rotation](aws/managing-secrets-with-rotation/managing-secrets-with-rotation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Secrets Manager, Lambda, IAM, KMS* • ⏱️ 120 minutes
- **[Microservice Authorization with VPC Lattice and IAM](aws/microservice-authorization-lattice-iam/microservice-authorization-lattice-iam.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, IAM, Lambda, CloudWatch* • ⏱️ 45 minutes
- **[Multi-Account Resource Discovery Automation](aws/multi-account-resource-discovery/multi-account-resource-discovery.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Resource Explorer, Config, EventBridge, Lambda* • ⏱️ 120 minutes
- **[Network Security Monitoring with VPC Flow Logs and Cloud Security Command Center](gcp/network-security-monitoring-vpc-flow-logs-security-command-center/network-security-monitoring-vpc-flow-logs-security-command-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: VPC Flow Logs, Cloud Security Command Center, Cloud Logging, Cloud Monitoring* • ⏱️ 120 minutes
- **[Network Security Orchestration with Logic Apps and NSG Rules](azure/network-security-orchestration/network-security-orchestration.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Logic Apps, Network Security Groups, Monitor, Key Vault* • ⏱️ 120 minutes
- **[Network Threat Detection Automation with Watcher and Analytics](azure/network-threat-detection-automation/network-threat-detection-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Network Watcher, Log Analytics, Logic Apps, Monitor* • ⏱️ 120 minutes
- **[Policy Enforcement Automation with VPC Lattice and Config](aws/policy-enforcement-lattice-config/policy-enforcement-lattice-config.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, AWS Config, Lambda, SNS* • ⏱️ 35 minutes
- **[Privacy-Preserving Analytics with Confidential GKE and BigQuery](gcp/privacy-preserving-analytics-confidential-gke-bigquery/privacy-preserving-analytics-confidential-gke-bigquery.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Confidential GKE, BigQuery, Cloud KMS, Vertex AI* • ⏱️ 60 minutes
- **[Quantum-Safe Security Posture Management with Security Command Center and Cloud Key Management Service](gcp/quantum-safe-security-posture-management-command-center-key-management-service/quantum-safe-security-posture-management-command-center-key-management-service.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Security Command Center, Cloud Key Management Service, Cloud Asset Inventory, Cloud Monitoring* • ⏱️ 150 minutes
- **[Real-time Fraud Detection with Spanner and Vertex AI](gcp/real-time-fraud-detection-spanner-vertex-ai/real-time-fraud-detection-spanner-vertex-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Spanner, Vertex AI, Cloud Functions, Pub/Sub* • ⏱️ 45 minutes
- **[Real-time Privilege Escalation Monitoring with PAM and Pub/Sub](gcp/privilege-escalation-monitoring-pam-pubsub/privilege-escalation-monitoring-pam-pubsub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Privileged Access Manager, Cloud Audit Logs, Pub/Sub* • ⏱️ 25 minutes
- **[Responding to Incidents with Security Hub](aws/responding-to-incidents-with-security-hub/responding-to-incidents-with-security-hub.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Security Hub, EventBridge, Lambda, SNS* • ⏱️ 150 minutes
- **[SaaS Security Monitoring with AppFabric](aws/saas-security-monitoring-appfabric/saas-security-monitoring-appfabric.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AppFabric, EventBridge, Lambda, SNS* • ⏱️ 90 minutes
- **[Secure AI-Enhanced Development Workflows with Cloud Identity-Aware Proxy and Gemini Code Assist](gcp/secure-ai-enhanced-development-workflows-identity-proxy-gemini-assist/secure-ai-enhanced-development-workflows-identity-proxy-gemini-assist.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Identity-Aware Proxy, Gemini Code Assist, Cloud Secrets Manager, Cloud Build* • ⏱️ 120 minutes
- **[Secure API Configuration Management with Secret Manager and Cloud Run](gcp/secure-api-configuration-management-secret-manager-run/secure-api-configuration-management-secret-manager-run.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Secret Manager, Cloud Run, API Gateway* • ⏱️ 75 minutes
- **[Secure CI/CD Authentication with Workload Identity Federation and GitHub Actions](gcp/secure-cicd-authentication-workload-identity-federation-github-actions/secure-cicd-authentication-workload-identity-federation-github-actions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: IAM, Cloud Build, Artifact Registry, Cloud Run* • ⏱️ 75 minutes
- **[Secure Content Delivery with CloudFront WAF](aws/content-delivery-cloudfront-waf/content-delivery-cloudfront-waf.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFront, WAF, S3, CloudWatch* • ⏱️ 90 minutes
- **[Secure Multi-Tenant Identity Isolation with External ID](azure/secure-multi-tenant-identity-isolation/secure-multi-tenant-identity-isolation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure External ID, Azure Private Link, Azure API Management, Azure Key Vault* • ⏱️ 150 minutes
- **[Secure Remote Development Access with Cloud Identity-Aware Proxy and Cloud Code](gcp/secure-remote-development-access-identity-proxy-cloud-code/secure-remote-development-access-identity-proxy-cloud-code.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Identity-Aware Proxy, Cloud Code, Artifact Registry, Compute Engine* • ⏱️ 90 minutes
- **[Secure Remote Development Environments with Cloud Workstations and Cloud Build](gcp/secure-remote-development-environments-workstations-build/secure-remote-development-environments-workstations-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Workstations, Cloud Build, Cloud Source Repositories, IAM* • ⏱️ 120 minutes
- **[Secure SSH Access with EC2 Instance Connect](aws/ec2-instance-connect-ssh/ec2-instance-connect-ssh.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: ec2, iam, cloudtrail* • ⏱️ 45 minutes
- **[Secure Traffic Processing with Service Extensions and Confidential Computing](gcp/secure-traffic-processing-service-extensions-confidential/secure-traffic-processing-service-extensions-confidential.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Service Extensions, Confidential Computing, Cloud KMS* • ⏱️ 45 minutes
- **[Secure User Onboarding Workflows with Azure Entra ID and Azure Service Bus](azure/secure-user-onboarding-workflows-entra-id-service-bus/secure-user-onboarding-workflows-entra-id-service-bus.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Entra ID, Azure Service Bus, Azure Logic Apps, Azure Key Vault* • ⏱️ 105 minutes
- **[Securing Multi-Regional API Gateways with Apigee and Cloud Armor](gcp/multi-regional-api-gateways-apigee-cloud-armor/multi-regional-api-gateways-apigee-cloud-armor.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Apigee, Cloud Armor, Cloud Load Balancing* • ⏱️ 120 minutes
- **[Securing Websites with SSL Certificates](aws/securing-websites-with-ssl-certificates/securing-websites-with-ssl-certificates.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Certificate Manager, CloudFront, S3* • ⏱️ 45 minutes
- **[Security Compliance Auditing with VPC Lattice and GuardDuty](aws/security-compliance-auditing-lattice-guardduty/security-compliance-auditing-lattice-guardduty.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VPC Lattice, GuardDuty, CloudWatch, Lambda* • ⏱️ 45 minutes
- **[Security Compliance Monitoring with Security Command Center and Cloud Workflows](gcp/security-compliance-monitoring-command-center-workflows/security-compliance-monitoring-command-center-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Security Command Center, Cloud Workflows, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes
- **[Security Incident Response Automation](aws/security-incident-response-automation/security-incident-response-automation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Security Hub, EventBridge, Lambda, SNS* • ⏱️ 240 minutes
- **[Security Posture Assessment with Security Command Center and Workload Manager](gcp/security-posture-assessment-command-center-workload-manager/security-posture-assessment-command-center-workload-manager.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Security Command Center, Workload Manager, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes
- **[Security Scanning Automation with Inspector](aws/security-scanning-automation-inspector/security-scanning-automation-inspector.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Inspector, Security Hub, EC2, Lambda* • ⏱️ 180 minutes
- **[Simple API Logging with CloudTrail and S3](aws/simple-api-logging-cloudtrail-s3/simple-api-logging-cloudtrail-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudTrail, S3, CloudWatch* • ⏱️ 30 minutes
- **[Simple Password Generator with Functions and Key Vault](azure/simple-password-generator-functions-key-vault/simple-password-generator-functions-key-vault.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Key Vault* • ⏱️ 15 minutes
- **[Simple Password Generator with Lambda and S3](aws/simple-password-generator-lambda-s3/simple-password-generator-lambda-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, S3* • ⏱️ 25 minutes
- **[Simple Secrets Management with Key Vault and App Service](azure/simple-secrets-management-key-vault-app-service/simple-secrets-management-key-vault-app-service.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Key Vault, App Service* • ⏱️ 20 minutes
- **[Simple SSL Certificate Monitoring with Certificate Manager and SNS](aws/simple-ssl-certificate-monitoring-acm-sns/simple-ssl-certificate-monitoring-acm-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Certificate Manager, SNS, CloudWatch* • ⏱️ 25 minutes
- **[Smart Contract Security Auditing with Document AI and Vertex AI](gcp/smart-contract-security-auditing-document-ai-vertex/smart-contract-security-auditing-document-ai-vertex.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 50 minutes
- **[Software Supply Chain Security with Binary Authorization and Cloud Build](gcp/software-supply-chain-security-binary-authorization-build/software-supply-chain-security-binary-authorization-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Binary Authorization, Cloud Build, Artifact Registry, Cloud KMS* • ⏱️ 105 minutes
- **[SSO with External Identity Providers](aws/sso-external-identity-providers/sso-external-identity-providers.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IAM Identity Center, Organizations, CloudTrail, Identity Store* • ⏱️ 120 minutes
- **[Strengthening Authentication Security with IAM and MFA Devices](aws/strengthening-authentication-security/strengthening-authentication-security.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IAM, CloudTrail, CloudWatch* • ⏱️ 45 minutes
- **[Tamper-Proof Compliance Reporting with Confidential Ledger](azure/tamper-proof-compliance-reporting/tamper-proof-compliance-reporting.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Confidential Ledger, Azure Logic Apps, Azure Monitor, Azure Blob Storage* • ⏱️ 90 minutes
- **[Threat Detection Pipelines with Cloud IDS and BigQuery Data Canvas](gcp/threat-detection-pipelines-ids-bigquery-data-canvas/threat-detection-pipelines-ids-bigquery-data-canvas.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud IDS, BigQuery Data Canvas, Cloud Functions, Pub/Sub* • ⏱️ 150 minutes
- **[Trusted Container Supply Chain with Attestation Service and Image Builder](azure/trusted-container-supply-chain-attestation-image-builder/trusted-container-supply-chain-attestation-image-builder.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Attestation Service, Azure Image Builder, Azure Container Registry, Azure Key Vault* • ⏱️ 120 minutes
- **[Unified Identity Management System](aws/unified-identity-management/unified-identity-management.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Directory Service, WorkSpaces, RDS, IAM* • ⏱️ 90 minutes
- **[Unified Security Incident Response with Sentinel and Defender XDR](azure/unified-security-incident-response/unified-security-incident-response.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Microsoft Sentinel, Azure Monitor Workbooks, Azure Logic Apps, Microsoft Defender XDR* • ⏱️ 120 minutes
- **[URL Safety Validation using Web Risk and Functions](gcp/url-safety-validation-web-risk-functions/url-safety-validation-web-risk-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Web Risk API, Cloud Functions, Cloud Storage* • ⏱️ 25 minutes
- **[WAF Rate Limiting for Web Application Protection](aws/waf-rate-limiting-rules/waf-rate-limiting-rules.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: waf, cloudfront, application-load-balancer, cloudwatch* • ⏱️ 120 minutes
- **[Web Application Security with WAF Rules](aws/waf-rules-web-application-security/waf-rules-web-application-security.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: waf, cloudfront, alb, cloudwatch* • ⏱️ 120 minutes
- **[Zero Trust Security Architecture with AWS](aws/zero-trust-security-architecture-aws/zero-trust-security-architecture-aws.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iam, identity, center, security, +3 more* • ⏱️ 240 minutes
- **[Zero-Trust Backup Security with Workload Identity and Backup Center](azure/zero-trust-backup-security-workload-identity-backup-center/zero-trust-backup-security-workload-identity-backup-center.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Workload Identity, Azure Backup Center, Azure Key Vault, Recovery Services Vault* • ⏱️ 120 minutes
- **[Zero-Trust Network Security with Service Extensions and Cloud Armor](gcp/zero-trust-network-security-service-extensions-armor/zero-trust-network-security-service-extensions-armor.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Load Balancing, Cloud Armor, Identity-Aware Proxy, Service Extensions* • ⏱️ 180 minutes
- **[Zero-Trust Remote Access with Bastion and Firewall Manager](azure/zero-trust-remote-access-bastion-firewall-manager/zero-trust-remote-access-bastion-firewall-manager.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Bastion, Azure Firewall Manager, Azure Virtual Network, Azure Policy* • ⏱️ 90 minutes

---

## 🤖 AI & Machine Learning

*Machine learning platforms, AI services, and cognitive computing*

- **[Adaptive Healthcare Chatbots with AI-Driven Personalization](azure/adaptive-healthcare-chatbots/adaptive-healthcare-chatbots.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Health Bot, Azure Machine Learning, Azure SQL Managed Instance* • ⏱️ 180 minutes
- **[Adaptive ML Model Scaling with Azure AI Foundry and Compute Fleet](azure/adaptive-ml-model-scaling-ai-foundry-compute-fleet/adaptive-ml-model-scaling-ai-foundry-compute-fleet.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure Compute Fleet, Azure Machine Learning, Azure Monitor* • ⏱️ 150 minutes
- **[AI Application Testing with Evaluation Flows and AI Foundry](azure/ai-application-testing-evaluation-flows-foundry/ai-application-testing-evaluation-flows-foundry.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Prompt Flow, Azure DevOps* • ⏱️ 35 minutes
- **[AI Content Moderation with Bedrock and EventBridge](aws/content-moderation-bedrock-eventbridge/content-moderation-bedrock-eventbridge.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Bedrock, Amazon EventBridge, AWS Lambda, Amazon S3* • ⏱️ 120 minutes
- **[AI Content Validation with Vertex AI and Functions](gcp/ai-content-validation-vertex-ai-functions/ai-content-validation-vertex-ai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 25 minutes
- **[AI Model Bias Detection with Vertex AI Monitoring and Functions](gcp/ai-model-bias-detection-vertex-monitoring-functions/ai-model-bias-detection-vertex-monitoring-functions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Model Monitoring, Cloud Functions, Cloud Logging, Cloud Scheduler* • ⏱️ 45 minutes
- **[AI Model Evaluation and Benchmarking with Azure AI Foundry](azure/ai-model-evaluation-benchmarking-foundry-openai/ai-model-evaluation-benchmarking-foundry-openai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure OpenAI, Prompt Flow* • ⏱️ 45 minutes
- **[AI-Powered Migration Assessment and Modernization Planning](azure/ai-powered-migration-assessment/ai-powered-migration-assessment.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Migrate, Azure OpenAI Service, Azure Functions, Azure Storage* • ⏱️ 120 minutes
- **[Analyzing Video Streams with Rekognition and Kinesis](aws/video-analytics-rekognition-kinesis/video-analytics-rekognition-kinesis.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rekognition, kinesis-video-streams, lambda, dynamodb* • ⏱️ 180 minutes
- **[Architecting Multi-Modal AI Content Generation with Lyria and Vertex AI](gcp/multi-modal-ai-content-generation-lyria-cloud-hub/multi-modal-ai-content-generation-lyria-cloud-hub.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Storage, Cloud Functions, Cloud Run* • ⏱️ 150 minutes
- **[Automated Document Extraction with Textract](aws/automated-document-extraction/automated-document-extraction.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: textract, s3, lambda* • ⏱️ 60 minutes
- **[Automated Image Analysis with ML](aws/automated-image-analysis/automated-image-analysis.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Rekognition, Amazon S3, AWS CLI* • ⏱️ 45 minutes
- **[Automated Job Description Generation with Gemini and Firestore](gcp/job-description-generation-gemini-firestore/job-description-generation-gemini-firestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Firestore, Cloud Functions* • ⏱️ 35 minutes
- **[Automated Marketing Asset Generation with OpenAI and Content Safety](azure/automated-marketing-asset-generation-openai-content-safety/automated-marketing-asset-generation-openai-content-safety.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI, Content Safety, Functions, Blob Storage* • ⏱️ 45 minutes
- **[Automated Multimodal Content Generation Workflows](azure/automated-multimodal-content-generation-workflows/automated-multimodal-content-generation-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure Container Registry, Azure Event Grid, Azure Key Vault* • ⏱️ 120 minutes
- **[Automated Video Content Generation using Veo 3 and Storage](gcp/automated-video-generation-veo3-storage/automated-video-generation-veo3-storage.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Storage, Cloud Scheduler, Cloud Functions* • ⏱️ 45 minutes
- **[AutoML Solutions with SageMaker Autopilot](aws/automl-sagemaker-autopilot/automl-sagemaker-autopilot.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: SageMaker, S3, IAM* • ⏱️ 180 minutes
- **[Blockchain Audit Trails for Compliance](aws/blockchain-audit-trails-qldb/blockchain-audit-trails-qldb.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: QLDB, CloudTrail, IAM, EventBridge* • ⏱️ 120 minutes
- **[Blockchain Supply Chain Tracking Systems](aws/blockchain-supply-chain-tracking/blockchain-supply-chain-tracking.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Managed Blockchain, IoT Core, Lambda, EventBridge* • ⏱️ 180 minutes
- **[Blockchain Supply Chain Transparency with Confidential Ledger and Cosmos DB](azure/blockchain-supply-chain-transparency/blockchain-supply-chain-transparency.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Confidential Ledger, Azure Cosmos DB, Azure Logic Apps, Azure Event Grid* • ⏱️ 120 minutes
- **[Blockchain-Based Voting Systems](aws/blockchain-voting-systems/blockchain-voting-systems.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Managed Blockchain, IAM, Cognito, Lambda* • ⏱️ 180 minutes
- **[Budget Alert Notifications with Cost Management and Logic Apps](azure/budget-alert-notifications-cost-management-logic-apps/budget-alert-notifications-cost-management-logic-apps.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Cost Management, Logic Apps* • ⏱️ 45 minutes
- **[Building Advanced Recommendation Systems with Amazon Personalize](aws/advanced-recommendation-systems-personalize/advanced-recommendation-systems-personalize.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amazon-personalize, s3, lambda, eventbridge* • ⏱️ 180 minutes
- **[Building Cloud-Native Development Environments with Firebase Studio and Gemini Code Assist](gcp/cloud-native-development-environments-firebase-studio-gemini-code-assist/cloud-native-development-environments-firebase-studio-gemini-code-assist.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Studio, Gemini Code Assist, Cloud Source Repositories, Artifact Registry* • ⏱️ 120 minutes
- **[Building High-Performance AI Inference Pipelines with Cloud Bigtable and TPU](gcp/high-performance-ai-inference-pipelines-cloud-bigtable-tpu/high-performance-ai-inference-pipelines-cloud-bigtable-tpu.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Bigtable, Vertex AI, Cloud Functions, Cloud Monitoring* • ⏱️ 150 minutes
- **[Building Recommendation Systems with Amazon Personalize](aws/recommendation-systems-personalize/recommendation-systems-personalize.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Personalize, API Gateway, Lambda, S3* • ⏱️ 180 minutes
- **[Business Proposal Generator with Vertex AI and Storage](gcp/business-proposal-generator-vertex-ai-storage/business-proposal-generator-vertex-ai-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 35 minutes
- **[Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence](gcp/carbon-efficient-batch-processing-batch-sustainability-intelligence/carbon-efficient-batch-processing-batch-sustainability-intelligence.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Batch, Carbon Footprint, Cloud Monitoring, Pub/Sub* • ⏱️ 120 minutes
- **[Chatbot Development with Amazon Lex](aws/chatbot-development-lex/chatbot-development-lex.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lex, Lambda, DynamoDB, CloudWatch* • ⏱️ 120 minutes
- **[Content Accessibility Compliance with Document AI and Gemini](gcp/content-accessibility-compliance-document-ai-gemini/content-accessibility-compliance-document-ai-gemini.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Gemini, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Content Moderation with Vertex AI and Cloud Storage](gcp/content-moderation-vertex-ai-storage/content-moderation-vertex-ai-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Storage, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes
- **[Content Personalization Engine with AI Foundry and Cosmos](azure/content-personalization-ai-foundry-cosmos/content-personalization-ai-foundry-cosmos.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure Cosmos DB, Azure OpenAI, Azure Functions* • ⏱️ 45 minutes
- **[Content Quality Scoring with Vertex AI and Functions](gcp/content-quality-scoring-vertex-ai-functions/content-quality-scoring-vertex-ai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 25 minutes
- **[Conversational AI Applications with Bedrock](aws/conversational-ai-bedrock-claude/conversational-ai-bedrock-claude.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock, Lambda, API Gateway, DynamoDB* • ⏱️ 90 minutes
- **[Conversational AI Backends with Agent Development Kit and Firestore](gcp/conversational-ai-backends-agent-development-kit-firestore/conversational-ai-backends-agent-development-kit-firestore.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Agent Development Kit, Cloud Functions, Firestore, Cloud Storage* • ⏱️ 120 minutes
- **[Conversational AI Training Data Generation with Gemini and Cloud Storage](gcp/conversational-training-data-gemini-storage/conversational-training-data-gemini-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Storage, Cloud Functions* • ⏱️ 45 minutes
- **[Cross-Organization Data Sharing with Blockchain](aws/cross-org-data-sharing-blockchain/cross-org-data-sharing-blockchain.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: managed-blockchain, lambda, eventbridge, s3* • ⏱️ 240 minutes
- **[Custom Entity Recognition with Comprehend](aws/custom-entity-recognition-comprehend/custom-entity-recognition-comprehend.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: comprehend, s3, lambda, stepfunctions* • ⏱️ 240 minutes
- **[Custom Music Generation with Vertex AI and Storage](gcp/custom-music-generation-vertex-ai-storage/custom-music-generation-vertex-ai-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Storage, Cloud Functions* • ⏱️ 35 minutes
- **[Custom Voice Generation with Chirp 3 and Functions](gcp/custom-voice-generation-chirp-functions/custom-voice-generation-chirp-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Text-to-Speech API, Cloud Functions, Cloud Storage, Cloud SQL* • ⏱️ 35 minutes
- **[Customer Service Automation with Contact Center AI and Vertex AI Search](gcp/customer-service-automation-contact-center-ai-vertex-ai-search/customer-service-automation-contact-center-ai-vertex-ai-search.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Contact Center AI, Vertex AI Search, Cloud Run, Cloud Storage* • ⏱️ 120 minutes
- **[Customer Support Assistant with OpenAI Assistants and Functions](azure/customer-support-assistant-openai-functions/customer-support-assistant-openai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Azure Functions, Azure Storage* • ⏱️ 45 minutes
- **[Detecting Fraud with Amazon Fraud Detector](aws/fraud-detection-amazon-fraud-detector/fraud-detection-amazon-fraud-detector.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: frauddetector, kinesis, lambda, dynamodb* • ⏱️ 180 minutes
- **[Developing Browser-Based AI Applications with Cloud Shell Editor and Vertex AI](gcp/browser-based-ai-applications-cloud-shell-editor-vertex-ai/browser-based-ai-applications-cloud-shell-editor-vertex-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Shell Editor, Vertex AI, Cloud Build, Cloud Run* • ⏱️ 120 minutes
- **[Developing Carbon-Aware Workload Orchestration with Cloud Carbon Footprint and Cloud Workflows](gcp/carbon-aware-workload-orchestration-cloud-carbon-footprint-workflows/carbon-aware-workload-orchestration-cloud-carbon-footprint-workflows.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Carbon Footprint, Cloud Workflows, Cloud Scheduler, Compute Engine* • ⏱️ 120 minutes
- **[Document Analysis Solutions with Amazon Textract](aws/document-analysis-textract/document-analysis-textract.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: textract, step-functions, s3, lambda* • ⏱️ 120 minutes
- **[Document Analysis Solutions with Textract](aws/document-analysis-solutions-textract/document-analysis-solutions-textract.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: textract, lambda, s3, sns* • ⏱️ 120 minutes
- **[Document Intelligence Workflows with Agentspace and Sensitive Data Protection](gcp/document-intelligence-workflows-agentspace-sensitive-data-protection/document-intelligence-workflows-agentspace-sensitive-data-protection.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Agentspace, Sensitive Data Protection, Document AI, Cloud Workflows* • ⏱️ 120 minutes
- **[Document Processing with AI Intelligence and Logic Apps](azure/document-processing-ai-intelligence-logic-apps/document-processing-ai-intelligence-logic-apps.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Document Intelligence, Logic Apps, Azure Storage, Azure Key Vault* • ⏱️ 90 minutes
- **[Document Processing Workflows with Document AI and Cloud Run](gcp/document-processing-document-ai-run/document-processing-document-ai-run.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Cloud Run, Pub/Sub, Cloud Storage* • ⏱️ 120 minutes
- **[Document Q&A with AI Search and OpenAI](azure/document-qa-ai-search-openai/document-qa-ai-search-openai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Search, Azure OpenAI Service, Azure Functions* • ⏱️ 45 minutes
- **[Document QA System with Bedrock and Kendra](aws/document-qa-system/document-qa-system.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock, Kendra, S3, Lambda* • ⏱️ 120 minutes
- **[E-commerce Personalization with Vertex AI Search for Commerce and Cloud Functions](gcp/e-commerce-personalization-retail-api-functions/e-commerce-personalization-retail-api-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Search for Commerce, Cloud Functions, Cloud Firestore, Cloud Storage* • ⏱️ 120 minutes
- **[Edge-to-Cloud MLOps Pipelines with Distributed Cloud Edge and Vertex AI Pipelines](gcp/edge-to-cloud-mlops-pipelines-distributed-cloud-edge-vertex-ai-pipelines/edge-to-cloud-mlops-pipelines-distributed-cloud-edge-vertex-ai-pipelines.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Distributed Cloud Edge, Vertex AI Pipelines, Cloud Storage, Cloud Monitoring* • ⏱️ 150 minutes
- **[Educational Content Generation with Gemini and Text-to-Speech](gcp/educational-content-generation-gemini-text-speech/educational-content-generation-gemini-text-speech.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Text-to-Speech, Cloud Functions, Firestore* • ⏱️ 30 minutes
- **[End-to-End MLOps with SageMaker Pipelines](aws/mlops-sagemaker-pipelines/mlops-sagemaker-pipelines.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sagemaker, codecommit, s3, iam* • ⏱️ 180 minutes
- **[Enterprise Blockchain Network](aws/enterprise-blockchain-network/enterprise-blockchain-network.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: managed-blockchain, vpc, ec2, cloudformation* • ⏱️ 240 minutes
- **[Enterprise Knowledge Discovery with Google Agentspace and Vertex AI Search](gcp/enterprise-knowledge-discovery-agentspace-vertex-ai-search/enterprise-knowledge-discovery-agentspace-vertex-ai-search.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Search, Cloud Storage, BigQuery, Agentspace Enterprise* • ⏱️ 120 minutes
- **[Enterprise MLflow Lifecycle Management with Containers](azure/enterprise-mlflow-lifecycle-management-containers/enterprise-mlflow-lifecycle-management-containers.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Machine Learning, Azure Container Apps, Azure Monitor, Azure Container Registry* • ⏱️ 120 minutes
- **[Environmental Impact Dashboards with Azure Sustainability Manager and Power BI](azure/environmental-impact-dashboards-sustainability-manager-power-bi/environmental-impact-dashboards-sustainability-manager-power-bi.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Microsoft Sustainability Manager, Power BI, Azure Monitor, Logic Apps* • ⏱️ 75 minutes
- **[Establishing Private Blockchain Networks with Amazon Managed Blockchain](aws/private-blockchain-networks-managed-blockchain/private-blockchain-networks-managed-blockchain.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: managed-blockchain, vpc, iam, ec2* • ⏱️ 180 minutes
- **[Extracting Insights from Text with Amazon Comprehend](aws/extracting-insights-from-text/extracting-insights-from-text.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: amazon comprehend, aws lambda, amazon s3, amazon eventbridge* • ⏱️ 120 minutes
- **[Fraud Detection with Amazon Fraud Detector](aws/fraud-detection/fraud-detection.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: fraud-detector, s3, iam, lambda* • ⏱️ 120 minutes
- **[Healthcare Data Processing with Cloud Batch and Vertex AI Agents](gcp/healthcare-data-processing-batch-vertex-ai-agents/healthcare-data-processing-batch-vertex-ai-agents.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Batch, Vertex AI Agent Builder, Cloud Healthcare API, Cloud Storage* • ⏱️ 120 minutes
- **[High-Performance Data Science Workflows with Cloud NetApp Volumes and Vertex AI Workbench](gcp/high-performance-data-science-workflows-netapp-volumes-vertex-ai-workbench/high-performance-data-science-workflows-netapp-volumes-vertex-ai-workbench.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud NetApp Volumes, Vertex AI Workbench, Cloud Storage, Compute Engine* • ⏱️ 120 minutes
- **[Hybrid Classical-Quantum AI Workflows with Cirq and Vertex AI](gcp/hybrid-classical-quantum-ai-workflows-cirq-vertex-ai/hybrid-classical-quantum-ai-workflows-cirq-vertex-ai.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Quantum Computing Service, Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 150 minutes
- **[Inclusive AI Chatbots with Accessibility Features](azure/inclusive-ai-chatbots-accessibility/inclusive-ai-chatbots-accessibility.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Immersive Reader, Azure Bot Framework, Azure Language Understanding, Azure App Service* • ⏱️ 120 minutes
- **[Intelligent Content Moderation with Bedrock](aws/intelligent-content-moderation-bedrock/intelligent-content-moderation-bedrock.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Bedrock, Amazon EventBridge, AWS Lambda, Amazon S3* • ⏱️ 120 minutes
- **[Intelligent Document Classification with Cloud Functions and Vertex AI](gcp/intelligent-document-classification-functions-vertex-ai/intelligent-document-classification-functions-vertex-ai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Vertex AI, Cloud Storage* • ⏱️ 30 minutes
- **[Intelligent Document Validation Workflows with Dataverse and AI Document Intelligence](azure/intelligent-document-validation-workflows/intelligent-document-validation-workflows.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Document Intelligence, Azure Logic Apps, Azure Dataverse, Power Apps* • ⏱️ 120 minutes
- **[Intelligent Document Verification Systems with Azure Document Intelligence and Azure Computer Vision](azure/intelligent-document-verification-systems-document-intelligence-computer-vision/intelligent-document-verification-systems-document-intelligence-computer-vision.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Document Intelligence, Azure Computer Vision, Azure Logic Apps, Azure Functions* • ⏱️ 120 minutes
- **[Intelligent Model Selection with Model Router and Event Grid](azure/intelligent-model-selection-router-event-grid/intelligent-model-selection-router-event-grid.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Model Router, Event Grid, Functions, Application Insights* • ⏱️ 25 minutes
- **[Intelligent Vision Model Retraining with Custom Vision MLOps](azure/intelligent-vision-model-retraining/intelligent-vision-model-retraining.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Custom Vision, Logic Apps, Blob Storage, Monitor* • ⏱️ 120 minutes
- **[Interactive Quiz Generation with Vertex AI and Functions](gcp/interactive-quiz-generation-vertex-ai-functions/interactive-quiz-generation-vertex-ai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Interview Practice Assistant using Gemini and Speech-to-Text](gcp/interview-practice-assistant-gemini-speech/interview-practice-assistant-gemini-speech.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Speech-to-Text, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Large Language Model Inference with TPU Ironwood and GKE Volume Populator](gcp/large-language-model-inference-tpu-ironwood-gke-volume-populator/large-language-model-inference-tpu-ironwood-gke-volume-populator.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Google Kubernetes Engine, Cloud Storage, TPU* • ⏱️ 150 minutes
- **[Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing](gcp/large-scale-ai-model-inference-ironwood-tpu-load-balancing/large-scale-ai-model-inference-ironwood-tpu-load-balancing.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Ironwood TPU, Cloud Load Balancing, Vertex AI, Cloud Monitoring* • ⏱️ 120 minutes
- **[Large-Scale Machine Learning Training Pipelines with Cloud TPU v6e and Dataproc Serverless](gcp/large-scale-ml-training-pipelines-tpu-v6e-dataproc-serverless/large-scale-ml-training-pipelines-tpu-v6e-dataproc-serverless.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud TPU, Dataproc Serverless, Cloud Storage, Vertex AI* • ⏱️ 120 minutes
- **[Legal Document Analysis with Gemini Fine-Tuning and Document AI](gcp/legal-document-analysis-gemini-fine-tuning/legal-document-analysis-gemini-fine-tuning.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Document AI, Cloud Functions, Cloud Storage* • ⏱️ 90 minutes
- **[Location-Aware Content Generation with Gemini and Maps](gcp/location-aware-content-gemini-maps/location-aware-content-gemini-maps.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 30 minutes
- **[Medical Imaging Analysis with Cloud Healthcare API and Vision AI](gcp/medical-imaging-analysis-healthcare-api-vision-ai/medical-imaging-analysis-healthcare-api-vision-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Healthcare API, Vision AI, Cloud Functions, Cloud Storage* • ⏱️ 120 minutes
- **[Meeting Intelligence with Speech Services and OpenAI](azure/meeting-intelligence-speech-openai/meeting-intelligence-speech-openai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Speech Services, OpenAI, Service Bus, Functions* • ⏱️ 45 minutes
- **[Mixed Reality Industrial Training with Remote Rendering and Object Anchors](azure/mixed-reality-industrial-training/mixed-reality-industrial-training.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Remote Rendering, Azure Object Anchors, Azure Spatial Anchors, Azure Storage* • ⏱️ 150 minutes
- **[ML Pipeline Governance with Hyperdisk ML and Vertex AI Model Registry](gcp/ml-pipeline-governance-hyperdisk-ml-vertex-ai-registry/ml-pipeline-governance-hyperdisk-ml-vertex-ai-registry.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Hyperdisk ML, Vertex AI Model Registry, Cloud Workflows, Cloud Monitoring* • ⏱️ 120 minutes
- **[Model Improvement Pipeline with Stored Completions and Prompt Flow](azure/model-improvement-stored-completions-prompt-flow/model-improvement-stored-completions-prompt-flow.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI Service, Prompt Flow, Azure Functions* • ⏱️ 45 minutes
- **[Multi-Agent Content Workflows with Gemini 2.5 Reasoning and Cloud Workflows](gcp/multi-agent-content-workflows-gemini-reasoning/multi-agent-content-workflows-gemini-reasoning.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Workflows, Cloud Storage, Cloud Functions* • ⏱️ 120 minutes
- **[Multi-Agent Customer Service with Agent2Agent and Contact Center AI](gcp/multi-agent-customer-service-agent2agent-contact-center-ai/multi-agent-customer-service-agent2agent-contact-center-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Contact Center AI, Vertex AI, Cloud Functions, Firestore* • ⏱️ 45 minutes
- **[Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business](aws/multi-agent-knowledge-management-agentcore-q/multi-agent-knowledge-management-agentcore-q.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Bedrock AgentCore, Q Business, S3, IAM* • ⏱️ 45 minutes
- **[Multi-Language Content Localization Workflows with Cloud Translation Advanced and Cloud Scheduler](gcp/multi-language-content-localization-translation-scheduler/multi-language-content-localization-translation-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Translation API, Cloud Scheduler, Cloud Storage, Pub/Sub* • ⏱️ 120 minutes
- **[Multi-Language Customer Support Automation with Cloud AI Services](gcp/multi-language-customer-support-automation-ai-services/multi-language-customer-support-automation-ai-services.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Speech-to-Text, Cloud Translation, Cloud Natural Language, Cloud Text-to-Speech* • ⏱️ 120 minutes
- **[Multi-Modal AI Content Generation with Cloud Composer and Vertex AI Agent Development Kit](gcp/multi-modal-ai-content-generation-composer-vertex-ai-agent-development-kit/multi-modal-ai-content-generation-composer-vertex-ai-agent-development-kit.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Composer, Vertex AI, Cloud Storage, Cloud Run* • ⏱️ 150 minutes
- **[Multi-Speaker Transcription with Chirp and Cloud Functions](gcp/multi-speaker-transcription-chirp-functions/multi-speaker-transcription-chirp-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Speech-to-Text, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Optimizing Personalized Recommendations with A/B Testing](aws/personalized-recommendations-ab-testing/personalized-recommendations-ab-testing.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Personalize, API Gateway, Lambda, DynamoDB* • ⏱️ 240 minutes
- **[Personal Productivity Assistant with Gemini and Functions](gcp/personal-productivity-assistant-gemini-functions/personal-productivity-assistant-gemini-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Gmail API* • ⏱️ 45 minutes
- **[Personalized Recommendation APIs with Vertex AI and Cloud Run](gcp/personalized-recommendation-apis-vertex-ai-run/personalized-recommendation-apis-vertex-ai-run.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Run, Cloud Storage, BigQuery* • ⏱️ 120 minutes
- **[Processing Multilingual Voice Content with Transcribe and Polly](aws/processing-multilingual-voice-content/processing-multilingual-voice-content.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: transcribe, polly, translate, lambda* • ⏱️ 180 minutes
- **[Product Description Generation with AI Vision and OpenAI](azure/product-description-generation-vision-openai/product-description-generation-vision-openai.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: AI Vision, OpenAI Service, Functions, Blob Storage* • ⏱️ 45 minutes
- **[Real-time AI Chat with WebRTC and Model Router](azure/realtime-ai-chat-webrtc-model-router/realtime-ai-chat-webrtc-model-router.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure OpenAI, Azure Functions, Azure SignalR Service* • ⏱️ 50 minutes
- **[Real-Time Edge AI Inference with IoT Greengrass and ONNX](aws/real-time-edge-ai-inference/real-time-edge-ai-inference.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IoT Greengrass, EventBridge, S3, IoT Core* • ⏱️ 120 minutes
- **[Real-Time Fraud Detection with Vertex AI and Cloud Dataflow](gcp/real-time-fraud-detection-vertex-ai-dataflow/real-time-fraud-detection-vertex-ai-dataflow.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Dataflow, Cloud Pub/Sub, BigQuery* • ⏱️ 150 minutes
- **[Real-Time Text Analytics Streaming Workflows](azure/real-time-text-analytics-streaming-workflows/real-time-text-analytics-streaming-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cognitive Services, Azure Event Hubs, Azure Logic Apps, Azure Storage* • ⏱️ 120 minutes
- **[Real-Time Translation Services with Cloud Speech-to-Text and Cloud Translation](gcp/real-time-translation-services-speech-text-translation/real-time-translation-services-speech-text-translation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: cloud-speech-to-text, cloud-translation, cloud-run, firestore* • ⏱️ 120 minutes
- **[Real-Time Voice Support Agent with ADK and Live API](gcp/real-time-voice-support-agent-adk-live-api/real-time-voice-support-agent-adk-live-api.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Agent Development Kit, Gemini Live API, Cloud Functions* • ⏱️ 45 minutes
- **[SageMaker MLOps Pipeline with CodePipeline](aws/sagemaker-mlops-pipeline/sagemaker-mlops-pipeline.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sagemaker, codepipeline, codebuild, s3* • ⏱️ 180 minutes
- **[SageMaker Model Endpoints for ML Inference](aws/sagemaker-model-endpoints/sagemaker-model-endpoints.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sagemaker, ecr, cloudwatch, s3* • ⏱️ 120 minutes
- **[SageMaker Model Monitoring and Drift Detection](aws/sagemaker-model-monitoring/sagemaker-model-monitoring.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sagemaker, cloudwatch, s3, lambda* • ⏱️ 180 minutes
- **[Scalable Content Moderation with Container Apps Jobs](azure/scalable-content-moderation-container-jobs/scalable-content-moderation-container-jobs.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Content Safety, Azure Container Apps Jobs, Azure Service Bus, Azure Storage Accounts* • ⏱️ 120 minutes
- **[Scalable Multi-Agent AI Orchestration Platform](azure/scalable-multi-agent-ai-orchestration/scalable-multi-agent-ai-orchestration.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure Container Apps, Azure Event Grid, Azure Storage* • ⏱️ 150 minutes
- **[Secure AI Model Training Workflows with Dynamic Workload Scheduler and Confidential Computing](gcp/secure-ai-model-training-workflows-dynamic-workload-scheduler-confidential-computing/secure-ai-model-training-workflows-dynamic-workload-scheduler-confidential-computing.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Compute Engine, Confidential Computing, Vertex AI, Cloud KMS* • ⏱️ 180 minutes
- **[Simple Image Analysis with Computer Vision and Functions](azure/simple-image-analysis-computer-vision-functions/simple-image-analysis-computer-vision-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Computer Vision* • ⏱️ 20 minutes
- **[Smart Content Classification with Gemini and Cloud Storage](gcp/smart-content-classification-gemini-storage/smart-content-classification-gemini-storage.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Storage, Cloud Functions* • ⏱️ 35 minutes
- **[Smart Contract Development on Ethereum with Managed Blockchain](aws/ethereum-smart-contracts/ethereum-smart-contracts.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: managed-blockchain, lambda, api-gateway, s3* • ⏱️ 120 minutes
- **[Smart Document Summarization with Vertex AI and Functions](gcp/smart-document-summarization-vertex-ai-functions/smart-document-summarization-vertex-ai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 35 minutes
- **[Smart Expense Processing using Document AI and Gemini](gcp/smart-expense-processing-document-ai-gemini/smart-expense-processing-document-ai-gemini.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Gemini, Cloud Workflows, Cloud SQL* • ⏱️ 45 minutes
- **[Smart Form Processing with Document AI and Gemini](gcp/smart-form-processing-document-ai-gemini/smart-form-processing-document-ai-gemini.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Smart Model Selection with AI Foundry and Functions](azure/smart-model-selection-ai-foundry-functions/smart-model-selection-ai-foundry-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Foundry, Azure Functions, Azure Storage* • ⏱️ 45 minutes
- **[Smart Product Catalog Management with Vertex AI Search and Cloud Run](gcp/smart-product-catalog-vertex-search-run/smart-product-catalog-vertex-search-run.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Search, Cloud Run, Firestore* • ⏱️ 45 minutes
- **[Smart Resume Screening with Vertex AI and Cloud Functions](gcp/smart-resume-screening-vertex-ai-functions/smart-resume-screening-vertex-ai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage, Firestore* • ⏱️ 25 minutes
- **[Smart Survey Analysis with Gemini and Cloud Functions](gcp/smart-survey-analysis-gemini-functions/smart-survey-analysis-gemini-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Firestore* • ⏱️ 25 minutes
- **[Supply Chain Transparency with Cloud SQL and Blockchain Node Engine](gcp/supply-chain-transparency-sql-blockchain-node-engine/supply-chain-transparency-sql-blockchain-node-engine.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud SQL, Blockchain Node Engine, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes
- **[Sustainable Workload Optimization for Carbon Reduction](azure/sustainable-workload-optimization/sustainable-workload-optimization.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Carbon Optimization, Azure Advisor, Azure Monitor, Azure Automation* • ⏱️ 120 minutes
- **[Text Sentiment Analysis with Cognitive Services](azure/text-sentiment-analysis-cognitive-functions/text-sentiment-analysis-cognitive-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cognitive Services, Azure Functions* • ⏱️ 15 minutes
- **[Text-to-Speech Converter with Text-to-Speech and Storage](gcp/text-speech-converter-texttospeech-storage/text-speech-converter-texttospeech-storage.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Text-to-Speech, Cloud Storage* • ⏱️ 15 minutes
- **[Training Data Quality Assessment with Vertex AI and Functions](gcp/training-data-quality-vertex-ai-functions/training-data-quality-vertex-ai-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Transcribing Speech with Amazon Transcribe](aws/transcribing-speech-amazon-transcribe/transcribing-speech-amazon-transcribe.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: transcribe, s3, iam, lambda* • ⏱️ 120 minutes
- **[Voice Recording Analysis with AI Speech and Functions](azure/voice-recording-analysis-speech-functions/voice-recording-analysis-speech-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure AI Speech, Azure Functions, Blob Storage* • ⏱️ 15 minutes

---

## 🛠️ Application Development & Deployment

*Development tools, CI/CD, API management, and application hosting*

- **[Adaptive Code Quality Enforcement with DevOps Extensions](azure/adaptive-code-quality-enforcement-pipelines/adaptive-code-quality-enforcement-pipelines.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure DevOps, Azure Test Plans, Azure Application Insights, Azure Logic Apps* • ⏱️ 120 minutes
- **[Advanced Blue-Green Deployments with CodeDeploy](aws/advanced-blue-green-deployments/advanced-blue-green-deployments.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CodeDeploy, ECS, Lambda, ALB* • ⏱️ 300 minutes
- **[Advanced CodeBuild Pipelines with Caching](aws/advanced-codebuild-pipelines/advanced-codebuild-pipelines.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CodeBuild, S3, ECR, IAM* • ⏱️ 240 minutes
- **[AI Code Assistant Setup with Amazon Q Developer](aws/ai-code-assistant-amazon-q-developer/ai-code-assistant-amazon-q-developer.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Amazon Q Developer, IAM* • ⏱️ 25 minutes
- **[AI-Driven Infrastructure Cost Optimization with Azure Copilot and Azure Monitor](azure/ai-driven-infrastructure-cost-optimization-copilot-monitor/ai-driven-infrastructure-cost-optimization-copilot-monitor.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Copilot, Azure Monitor, Azure Cost Management, Azure Automation* • ⏱️ 90 minutes
- **[AI-Powered App Development with Firebase Studio and Gemini](gcp/ai-powered-app-development-firebase-studio-gemini/ai-powered-app-development-firebase-studio-gemini.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Studio, Gemini, App Hosting, Firestore* • ⏱️ 45 minutes
- **[API Schema Generation with Gemini Code Assist and Cloud Build](gcp/api-schema-generation-gemini-build/api-schema-generation-gemini-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Gemini Code Assist, Cloud Build, Cloud Storage, Cloud Functions* • ⏱️ 45 minutes
- **[Application Debugging Workflows with Cloud Debugger and Cloud Workstations](gcp/application-debugging-workflows-debugger-workstations/application-debugging-workflows-debugger-workstations.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Workstations, Artifact Registry, Cloud Run* • ⏱️ 75 minutes
- **[Artifact Management with CodeArtifact](aws/artifact-management-codeartifact/artifact-management-codeartifact.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CodeArtifact, IAM, KMS* • ⏱️ 180 minutes
- **[Automated Accessibility Compliance with Document AI and Build](gcp/accessibility-compliance-document-ai-build/accessibility-compliance-document-ai-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Cloud Build, Security Command Center, Cloud Functions* • ⏱️ 35 minutes
- **[Automated Application Migration Workflows](aws/automated-migration-workflows-mgn/automated-migration-workflows-mgn.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Application Migration Service, Migration Hub Orchestrator, CloudFormation, Systems Manager* • ⏱️ 120 minutes
- **[Automated Chaos Engineering with Fault Injection Service](aws/chaos-engineering-resilience-testing/chaos-engineering-resilience-testing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Fault Injection Service, EventBridge, CloudWatch, SNS* • ⏱️ 90 minutes
- **[Automated Code Documentation with Gemini and Cloud Build](gcp/automated-code-documentation-gemini-build/automated-code-documentation-gemini-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI, Cloud Build, Cloud Storage, Cloud Functions* • ⏱️ 75 minutes
- **[Automated Code Refactoring with Gemini Code Assist and Source Repositories](gcp/automated-code-refactoring-gemini-source-repositories/automated-code-refactoring-gemini-source-repositories.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Gemini Code Assist, Source Repositories, Cloud Build* • ⏱️ 25 minutes
- **[Automated Code Review Pipelines with Firebase Studio and Cloud Build](gcp/automated-code-review-firebase-studio-build/automated-code-review-firebase-studio-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Studio, Cloud Build, Cloud Tasks* • ⏱️ 25 minutes
- **[Batch Processing Workflows with Cloud Run Jobs and Cloud Scheduler](gcp/batch-processing-cloud-run-jobs-scheduler/batch-processing-cloud-run-jobs-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run Jobs, Cloud Scheduler, Cloud Build, Artifact Registry* • ⏱️ 75 minutes
- **[Centralized Configuration Management with App Configuration and Key Vault](azure/centralized-configuration-management/centralized-configuration-management.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure App Configuration, Azure Key Vault, Azure Web Apps* • ⏱️ 75 minutes
- **[Centralized Infrastructure Provisioning with Azure Automation and ARM Templates](azure/centralized-infrastructure-provisioning-automation-arm-templates/centralized-infrastructure-provisioning-automation-arm-templates.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Automation, Azure Resource Manager, Azure Storage, Azure Monitor* • ⏱️ 90 minutes
- **[Chaos Engineering for Application Resilience Testing](azure/chaos-engineering-resilience-testing/chaos-engineering-resilience-testing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Chaos Studio, Application Insights, Azure Monitor, Azure Virtual Machines* • ⏱️ 90 minutes
- **[Cloud Development Workflows with CloudShell](aws/cloud-dev-workflows-cloudshell/cloud-dev-workflows-cloudshell.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudShell, CodeCommit, IAM* • ⏱️ 60 minutes
- **[Cloud Operations Automation with Gemini Cloud Assist and Hyperdisk ML](gcp/cloud-operations-automation-gemini-cloud-assist-hyperdisk-ml/cloud-operations-automation-gemini-cloud-assist-hyperdisk-ml.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Gemini Cloud Assist, Hyperdisk ML, Cloud Monitoring, Vertex AI* • ⏱️ 120 minutes
- **[CloudFormation Nested Stacks Management](aws/cloudformation-nested-stacks/cloudformation-nested-stacks.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFormation, S3, IAM, VPC* • ⏱️ 150 minutes
- **[CloudFormation StackSets Multi-Account Management](aws/cloudformation-stacksets-multi-account/cloudformation-stacksets-multi-account.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFormation, Organizations, IAM, S3* • ⏱️ 210 minutes
- **[Code Quality Automation with Cloud Source Repositories and Artifact Registry](gcp/code-quality-automation-source-repositories-artifact-registry/code-quality-automation-source-repositories-artifact-registry.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Source Repositories, Artifact Registry, Cloud Build, Cloud Code* • ⏱️ 120 minutes
- **[Code Quality Enforcement with Cloud Build Triggers and Security Command Center](gcp/code-quality-enforcement-build-triggers-security-command-center/code-quality-enforcement-build-triggers-security-command-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Build, Security Command Center, Cloud Source Repositories, Binary Authorization* • ⏱️ 90 minutes
- **[Code Quality Gates with Cloud Build Triggers and Cloud Deploy](gcp/code-quality-gates-build-triggers-deploy/code-quality-gates-build-triggers-deploy.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Build, Cloud Deploy, Cloud Source Repositories, Binary Authorization* • ⏱️ 120 minutes
- **[Code Quality Gates with CodeBuild](aws/code-quality-gates-codebuild/code-quality-gates-codebuild.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CodeBuild, Systems Manager, SNS, S3* • ⏱️ 75 minutes
- **[Code Review and Documentation Workflows with Google Workspace APIs and Cloud Run](gcp/code-review-documentation-workflows-workspace-apis-run/code-review-documentation-workflows-workspace-apis-run.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Pub/Sub, Cloud Scheduler, Secret Manager* • ⏱️ 120 minutes
- **[Code Review Automation with CodeGuru](aws/code-review-automation-codeguru/code-review-automation-codeguru.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CodeGuru, CodeCommit, IAM* • ⏱️ 90 minutes
- **[Code Review Automation with Firebase Studio and Cloud Source Repositories](gcp/code-review-automation-firebase-studio-source-repositories/code-review-automation-firebase-studio-source-repositories.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Studio, Cloud Source Repositories, Vertex AI, Cloud Functions* • ⏱️ 120 minutes
- **[CodeCommit Git Workflows and Policies](aws/codecommit-git-workflows/codecommit-git-workflows.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CodeCommit, Lambda, EventBridge, SNS* • ⏱️ 80 minutes
- **[Comprehensive Static App Testing Workflows with Container Jobs](azure/comprehensive-static-app-testing-workflows/comprehensive-static-app-testing-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Static Web Apps, Azure Container Apps Jobs, Azure Load Testing, Azure Monitor* • ⏱️ 120 minutes
- **[Container CI/CD Pipelines with CodePipeline](aws/container-cicd-pipelines-codepipeline/container-cicd-pipelines-codepipeline.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CodePipeline, CodeDeploy, CodeBuild, ECS* • ⏱️ 210 minutes
- **[Continuous Deployment with CodeDeploy](aws/continuous-deployment-codedeploy/continuous-deployment-codedeploy.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: codedeploy, codecommit, codebuild, iam* • ⏱️ 180 minutes
- **[Continuous Performance Optimization with Cloud Build Triggers and Cloud Monitoring](gcp/continuous-performance-optimization-build-triggers-monitoring/continuous-performance-optimization-build-triggers-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Build, Cloud Monitoring, Cloud Source Repositories, Cloud Run* • ⏱️ 120 minutes
- **[Continuous Performance Testing with Azure Load Testing and Azure DevOps](azure/continuous-performance-testing-load-testing-devops/continuous-performance-testing-load-testing-devops.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: azure-load-testing, azure-devops, azure-monitor* • ⏱️ 90 minutes
- **[Cost-Aware Resource Lifecycle with MemoryDB](aws/cost-aware-lifecycle-memorydb/cost-aware-lifecycle-memorydb.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EventBridge Scheduler, MemoryDB for Redis, Lambda, Cost Explorer* • ⏱️ 90 minutes
- **[Cross-Platform Mobile Development Workflows with Firebase App Distribution and Cloud Build](gcp/cross-platform-mobile-development-workflows-firebase-distribution-build/cross-platform-mobile-development-workflows-firebase-distribution-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase App Distribution, Cloud Build, Firebase Test Lab, Cloud Source Repositories* • ⏱️ 75 minutes
- **[Daily System Status Reports with Cloud Scheduler and Gmail](gcp/daily-status-reports-scheduler-gmail/daily-status-reports-scheduler-gmail.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Scheduler, Cloud Functions, Gmail API* • ⏱️ 15 minutes
- **[Developer Environments with Cloud9](aws/developer-environments-cloud9/developer-environments-cloud9.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Cloud9, EC2, IAM, CodeCommit* • ⏱️ 150 minutes
- **[Development Environment Provisioning with WorkSpaces](aws/dev-environment-workspaces-provisioning/dev-environment-workspaces-provisioning.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: WorkSpaces, Systems Manager, Lambda, EventBridge* • ⏱️ 90 minutes
- **[Development Lifecycle Automation with Cloud Composer and Datastream](gcp/development-lifecycle-automation-composer-datastream/development-lifecycle-automation-composer-datastream.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Composer, Datastream, Artifact Registry, Cloud Workflows* • ⏱️ 120 minutes
- **[Development Workflow Automation with Firebase Studio and Gemini Code Assist](gcp/development-workflow-automation-firebase-studio-gemini-code-assist/development-workflow-automation-firebase-studio-gemini-code-assist.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Studio, Gemini Code Assist, Cloud Storage, Eventarc* • ⏱️ 120 minutes
- **[DevOps Monitoring with Live Dashboard Updates](azure/devops-monitoring-live-dashboards/devops-monitoring-live-dashboards.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure DevOps, Azure SignalR Service, Azure Monitor, Azure Functions* • ⏱️ 120 minutes
- **[Enhancing Application Performance with Cloud Profiler and Cloud Trace](gcp/application-performance-monitoring-cloud-profiler-trace/application-performance-monitoring-cloud-profiler-trace.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Profiler, Cloud Trace, Cloud Run, Cloud Monitoring* • ⏱️ 75 minutes
- **[Enterprise Deployment Pipeline Management with Cloud Build, Cloud Deploy, and Service Catalog](gcp/enterprise-deployment-pipeline-build-deploy-catalog/enterprise-deployment-pipeline-build-deploy-catalog.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Build, Cloud Deploy, Service Catalog, Google Kubernetes Engine* • ⏱️ 120 minutes
- **[Error Monitoring and Debugging with Cloud Error Reporting and Cloud Functions](gcp/error-monitoring-debugging-error-reporting-functions/error-monitoring-debugging-error-reporting-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Error Reporting, Cloud Functions, Cloud Monitoring, Cloud Logging* • ⏱️ 90 minutes
- **[Event-Driven Configuration with App Configuration and Service Bus](azure/event-driven-configuration-app-config-service-bus/event-driven-configuration-app-config-service-bus.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure App Configuration, Azure Service Bus, Azure Functions, Azure Logic Apps* • ⏱️ 75 minutes
- **[Event-Driven Incident Response with Eventarc and Cloud Operations Suite](gcp/event-driven-incident-response-eventarc-operations-suite/event-driven-incident-response-eventarc-operations-suite.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Eventarc, Cloud Operations Suite, Cloud Functions, Cloud Run* • ⏱️ 120 minutes
- **[Event-Driven Infrastructure Deployments with Azure Bicep and Event Grid](azure/event-driven-infrastructure-deployments-bicep-event-grid/event-driven-infrastructure-deployments-bicep-event-grid.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Bicep, Azure Event Grid, Azure Container Instances, Azure Functions* • ⏱️ 90 minutes
- **[Feature Flags with AWS AppConfig](aws/feature-flags-appconfig/feature-flags-appconfig.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AppConfig, Lambda, CloudWatch* • ⏱️ 90 minutes
- **[Feature Flags with CloudWatch Evidently](aws/feature-flags-evidently/feature-flags-evidently.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cloudwatch-evidently, lambda, iam* • ⏱️ 60 minutes
- **[GitOps Development Workflows with Workstations and Deploy](gcp/gitops-development-workstations-deploy/gitops-development-workstations-deploy.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Workstations, Cloud Deploy, Cloud Build, Cloud Source Repositories* • ⏱️ 45 minutes
- **[GitOps for EKS with ArgoCD](aws/gitops-eks-argocd/gitops-eks-argocd.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EKS, ArgoCD, CodeCommit, ALB* • ⏱️ 180 minutes
- **[GitOps with CodeCommit and CodeBuild](aws/gitops-codecommit/gitops-codecommit.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: codecommit, codebuild, codepipeline, ecr* • ⏱️ 120 minutes
- **[Golden Image Automation with CI/CD Pipelines](azure/golden-image-automation-pipelines/golden-image-automation-pipelines.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure VM Image Builder, Azure Private DNS Resolver, Azure DevOps, Azure Compute Gallery* • ⏱️ 120 minutes
- **[Governed Infrastructure Provisioning with Azure Deployment Environments and Service Connector](azure/governed-infrastructure-provisioning-azure-service-connector/governed-infrastructure-provisioning-azure-service-connector.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Deployment Environments, Azure Service Connector, Azure Logic Apps, Azure Event Grid* • ⏱️ 105 minutes
- **[Hybrid Infrastructure Health Monitoring with Functions and Update Manager](azure/hybrid-infrastructure-health-monitoring/hybrid-infrastructure-health-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Azure Update Manager, Azure Event Grid, Azure Monitor* • ⏱️ 120 minutes
- **[Infrastructure as Code with Terraform](aws/infrastructure-as-code-terraform/infrastructure-as-code-terraform.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: EC2, S3, DynamoDB, ALB* • ⏱️ 120 minutes
- **[Infrastructure Automation with AWS Proton and CDK](aws/infrastructure-automation-proton/infrastructure-automation-proton.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: proton, cdk, ecs, iam* • ⏱️ 90 minutes
- **[Infrastructure Automation with CloudShell PowerShell](aws/infrastructure-automation-cloudshell/infrastructure-automation-cloudshell.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudShell, Systems Manager, Lambda, EventBridge* • ⏱️ 90 minutes
- **[Infrastructure Automation with Proton and CDK](aws/infrastructure-automation-proton-cdk/infrastructure-automation-proton-cdk.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Proton, CDK, CodePipeline, CloudFormation* • ⏱️ 90 minutes
- **[Infrastructure Cost Optimization with Cloud Batch and Cloud Monitoring](gcp/infrastructure-cost-optimization-batch-monitoring/infrastructure-cost-optimization-batch-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Batch, Cloud Monitoring, Cloud Functions, Compute Engine* • ⏱️ 120 minutes
- **[Infrastructure Deployment Pipelines with CDK](aws/infrastructure-deployment-pipelines/infrastructure-deployment-pipelines.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CDK, CodePipeline, CodeBuild, CodeCommit* • ⏱️ 120 minutes
- **[Infrastructure Health Assessment with Cloud Workload Manager and Cloud Deploy](gcp/infrastructure-health-assessment-workload-manager-deploy/infrastructure-health-assessment-workload-manager-deploy.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Workload Manager, Cloud Deploy, Cloud Monitoring, Cloud Functions* • ⏱️ 120 minutes
- **[Infrastructure Lifecycle Management with Deployment Stacks and Update Manager](azure/infrastructure-lifecycle-deployment-stacks-update-manager/infrastructure-lifecycle-deployment-stacks-update-manager.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Deployment Stacks, Azure Update Manager, Azure Resource Manager, Azure Monitor* • ⏱️ 120 minutes
- **[Infrastructure Policy Validation with CloudFormation Guard](aws/infrastructure-policy-validation/infrastructure-policy-validation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFormation Guard, CloudFormation, S3, IAM* • ⏱️ 90 minutes
- **[Infrastructure Testing Strategies for IaC](aws/iac-testing-strategies/iac-testing-strategies.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFormation, CodeBuild, CodePipeline, CDK* • ⏱️ 240 minutes
- **[Infrastructure Testing with TaskCat and CloudFormation](aws/infrastructure-testing-taskcat/infrastructure-testing-taskcat.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cloudformation, taskcat, s3, iam* • ⏱️ 120 minutes
- **[Intelligent Cloud Resource Rightsizing with Cost Management and Developer CLI](azure/intelligent-cloud-resource-rightsizing/intelligent-cloud-resource-rightsizing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cost Management, Azure Monitor, Azure Developer CLI, Azure Functions* • ⏱️ 120 minutes
- **[Intelligent Resource Optimization with Agent Builder and Asset Inventory](gcp/intelligent-resource-optimization-agent-builder-asset-inventory/intelligent-resource-optimization-agent-builder-asset-inventory.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Vertex AI Agent Builder, Cloud Asset Inventory, Cloud Scheduler, BigQuery* • ⏱️ 50 minutes
- **[Legacy Application Modernization with Migration Center and Cloud Deploy](gcp/legacy-application-architectures-application-design-center-migration-center/legacy-application-architectures-application-design-center-migration-center.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Migration Center, Cloud Build, Cloud Deploy, Cloud Run* • ⏱️ 120 minutes
- **[License Compliance Scanner with Source Repositories and Functions](gcp/license-compliance-scanner-repositories-functions/license-compliance-scanner-repositories-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Source Repositories, Cloud Functions, Cloud Storage, Cloud Scheduler* • ⏱️ 35 minutes
- **[Log-Driven Automation with Cloud Logging and Pub/Sub](gcp/log-driven-automation-logging-pub-sub/log-driven-automation-logging-pub-sub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Logging, Pub/Sub, Cloud Functions, Cloud Monitoring* • ⏱️ 75 minutes
- **[Monitoring Application Resilience with AWS Resilience Hub and EventBridge](aws/proactive-resilience-monitoring-resiliencehub-eventbridge/proactive-resilience-monitoring-resiliencehub-eventbridge.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Resilience Hub, Amazon EventBridge, Systems Manager, CloudWatch* • ⏱️ 120 minutes
- **[Multi-Cloud Cost Optimization with Cloud Billing API and Cloud Recommender](gcp/multi-cloud-cost-optimization-billing-api-recommender/multi-cloud-cost-optimization-billing-api-recommender.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Billing API, Cloud Recommender, Cloud Pub/Sub, Cloud Functions* • ⏱️ 120 minutes
- **[Multi-Environment Application Deployment with Cloud Deploy and Cloud Build](gcp/multi-environment-application-deployment-deploy-build/multi-environment-application-deployment-deploy-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Deploy, Cloud Build, Cloud Storage, GKE* • ⏱️ 120 minutes
- **[Multi-Environment Software Testing Pipelines with Cloud Code and Cloud Deploy](gcp/multi-environment-testing-pipelines-code-deploy/multi-environment-testing-pipelines-code-deploy.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Code, Cloud Deploy, Cloud Build, Cloud Monitoring* • ⏱️ 120 minutes
- **[Multi-Tenant Resource Scheduling with Cloud Scheduler and Cloud Filestore](gcp/multi-tenant-resource-scheduling-scheduler-filestore/multi-tenant-resource-scheduling-scheduler-filestore.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Scheduler, Cloud Filestore, Cloud Functions, Cloud Monitoring* • ⏱️ 120 minutes
- **[Multi-Tenant SaaS Isolation with Resource Governance](azure/multi-tenant-saas-isolation-governance/multi-tenant-saas-isolation-governance.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Deployment Stacks, Azure Workload Identity, Azure Resource Manager, Azure Policy* • ⏱️ 150 minutes
- **[Orchestrating Multi-Branch CI/CD Automation with CodePipeline](aws/orchestrating-multi-branch-cicd-automation/orchestrating-multi-branch-cicd-automation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: codepipeline, codecommit, codebuild, lambda* • ⏱️ 180 minutes
- **[Organizing Resources with Groups and Automated Management](aws/organizing-resources-with-groups/organizing-resources-with-groups.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Resource Groups, Systems Manager, CloudWatch, SNS* • ⏱️ 75 minutes
- **[Performance Regression Detection with Load Testing and Monitor Workbooks](azure/performance-regression-detection/performance-regression-detection.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Load Testing, Azure Monitor Workbooks, Azure DevOps, Azure Container Apps* • ⏱️ 90 minutes
- **[Performance Testing Pipelines with Cloud Load Balancing and Cloud Monitoring](gcp/performance-testing-pipelines-load-balancing-monitoring/performance-testing-pipelines-load-balancing-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Load Balancing, Cloud Monitoring, Cloud Functions, Cloud Scheduler* • ⏱️ 120 minutes
- **[Production MLOps Pipelines with Kubernetes](azure/production-mlops-pipelines-kubernetes/production-mlops-pipelines-kubernetes.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Kubernetes Service, Azure Machine Learning, Azure Container Registry, Azure DevOps* • ⏱️ 120 minutes
- **[Progressive Web Application Deployment with Cloud Build and Google Kubernetes Engine](gcp/progressive-web-application-deployment-build-kubernetes-engine/progressive-web-application-deployment-build-kubernetes-engine.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Build, Google Kubernetes Engine, Cloud Storage, Cloud Load Balancing* • ⏱️ 120 minutes
- **[Quality Assurance Workflows with Firebase Extensions and Cloud Tasks](gcp/quality-assurance-workflows-firebase-extensions-tasks/quality-assurance-workflows-firebase-extensions-tasks.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Firebase Extensions, Cloud Tasks, Cloud Storage, Vertex AI* • ⏱️ 120 minutes
- **[Resource Governance Automation with Policy and Resource Graph](azure/resource-governance-automation/resource-governance-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Policy, Azure Resource Graph, Azure Monitor, Log Analytics* • ⏱️ 75 minutes
- **[Scalable Browser Testing Pipeline with Playwright Testing and Application Insights](azure/scalable-browser-testing-pipeline/scalable-browser-testing-pipeline.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Playwright Testing, Application Insights, Azure Key Vault* • ⏱️ 90 minutes
- **[Scalable Browser Testing Pipelines with Playwright and DevOps](azure/scalable-browser-testing-pipelines/scalable-browser-testing-pipelines.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Playwright Testing, Azure DevOps, Azure Container Registry* • ⏱️ 120 minutes
- **[Secure Database Modernization Workflows with Cloud Workstations and Database Migration Service](gcp/secure-database-modernization-workflows-workstations-migration-service/secure-database-modernization-workflows-workstations-migration-service.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Workstations, Database Migration Service, Cloud Build, Secret Manager* • ⏱️ 120 minutes
- **[Secure GitOps CI/CD with Workload Identity and ArgoCD](azure/secure-gitops-cicd-workload-identity-argocd/secure-gitops-cicd-workload-identity-argocd.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Kubernetes Service, Azure Key Vault, Azure Workload Identity, ArgoCD* • ⏱️ 120 minutes
- **[Secure Package Distribution Workflows with Artifact Registry and Secret Manager](gcp/secure-package-distribution-workflows-artifact-registry-secret-manager/secure-package-distribution-workflows-artifact-registry-secret-manager.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: artifact-registry, secret-manager, cloud-scheduler, cloud-tasks* • ⏱️ 75 minutes
- **[Self-Service Developer Infrastructure with Dev Box and Deployment Environments](azure/self-service-developer-infrastructure/self-service-developer-infrastructure.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Dev Box, Azure Deployment Environments, Azure DevCenter* • ⏱️ 90 minutes
- **[Self-Service Infrastructure Lifecycle with Azure Deployment Environments and Developer CLI](azure/self-service-infrastructure-lifecycle-azure-deployment-environments/self-service-infrastructure-lifecycle-azure-deployment-environments.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Deployment Environments, Azure Developer CLI, Azure DevCenter, Azure Resource Manager* • ⏱️ 120 minutes
- **[Serverless Infrastructure Deployment with Container Apps Jobs and ARM Templates](azure/serverless-infrastructure-deployment/serverless-infrastructure-deployment.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Apps, Azure Resource Manager, Azure Storage, Azure Key Vault* • ⏱️ 120 minutes
- **[Serverless QA Pipeline Automation with Container Apps and Load Testing](azure/serverless-qa-pipeline-automation/serverless-qa-pipeline-automation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Apps Jobs, Azure Load Testing, Azure Monitor, Azure DevOps* • ⏱️ 120 minutes
- **[Simple Application Configuration with AppConfig and Lambda](aws/simple-app-configuration-appconfig-lambda/simple-app-configuration-appconfig-lambda.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AppConfig, Lambda* • ⏱️ 25 minutes
- **[Simple Configuration Management with App Configuration and App Service](azure/simple-config-management-app-config-service/simple-config-management-app-config-service.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure App Configuration, Azure App Service* • ⏱️ 15 minutes
- **[Simple Cost Budget Tracking with Cost Management](azure/simple-cost-budget-tracking-cost-management/simple-cost-budget-tracking-cost-management.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cost Management, Azure Monitor* • ⏱️ 15 minutes
- **[Simple Infrastructure Templates with CloudFormation and S3](aws/simple-infrastructure-templates-cloudformation-s3/simple-infrastructure-templates-cloudformation-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudFormation, S3* • ⏱️ 25 minutes
- **[Simple Resource Cleanup with Automation and PowerShell](azure/simple-resource-cleanup-automation-powershell/simple-resource-cleanup-automation-powershell.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Automation, PowerShell Runbooks* • ⏱️ 20 minutes
- **[Streamlining Multi-Environment Application Deployment with Cloud Deploy and Cloud Build](gcp/streamlining-multi-environment-application-deployment-with-cloud-deploy-and-cloud-build/streamlining-multi-environment-application-deployment-with-cloud-deploy-and-cloud-build.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Deploy, Cloud Build, Google Kubernetes Engine, Cloud Storage* • ⏱️ 90 minutes
- **[Visual Infrastructure Design with Application Composer and CloudFormation](aws/visual-infrastructure-composer-cloudformation/visual-infrastructure-composer-cloudformation.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Application Composer, CloudFormation, S3* • ⏱️ 25 minutes
- **[Visual Serverless Applications with Infrastructure Composer](aws/visual-serverless-apps-composer/visual-serverless-apps-composer.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Application Composer, CodeCatalyst, Lambda, CloudFormation* • ⏱️ 120 minutes
- **[Workload Carbon Efficiency with FinOps Hub 2.0 and Cloud Carbon Footprint](gcp/workload-carbon-efficiency-finops-hub-carbon-footprint/workload-carbon-efficiency-finops-hub-carbon-footprint.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: FinOps Hub, Cloud Carbon Footprint, Cloud Monitoring, Recommender* • ⏱️ 120 minutes

---

## 📊 Monitoring & Management

*Observability, logging, monitoring, resource management, and cost optimization*

- **[Account Optimization Monitoring with Trusted Advisor and CloudWatch](aws/account-optimization-trusted-advisor-cloudwatch/account-optimization-trusted-advisor-cloudwatch.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Trusted Advisor, CloudWatch, SNS* • ⏱️ 25 minutes
- **[Application Performance Monitoring Automation](aws/app-performance-monitoring-cloudwatch/app-performance-monitoring-cloudwatch.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, EventBridge, Lambda, SNS* • ⏱️ 120 minutes
- **[Application Performance Monitoring with Cloud Monitoring and Cloud Trace](gcp/application-performance-monitoring-monitoring-trace/application-performance-monitoring-monitoring-trace.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Monitoring, Cloud Trace, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes
- **[Architecting Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory](gcp/centralized-database-fleet-governance-database-center-asset-inventory/centralized-database-fleet-governance-database-center-asset-inventory.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Database Center, Cloud Asset Inventory, Cloud Workflows, Cloud Monitoring* • ⏱️ 75 minutes
- **[Architecture Assessment with AWS Well-Architected Tool](aws/architecture-assessment-well-architected-tool/architecture-assessment-well-architected-tool.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Well-Architected Tool, CloudWatch* • ⏱️ 25 minutes
- **[Auto-Remediation with Config and Lambda](aws/auto-remediation-config-lambda/auto-remediation-config-lambda.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Config, Lambda, IAM, SNS* • ⏱️ 120 minutes
- **[Automated Backup Solutions with AWS Backup](aws/automated-backup-solutions/automated-backup-solutions.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Backup, CloudWatch, IAM, SNS* • ⏱️ 120 minutes
- **[Automated Carbon Footprint Optimization](aws/carbon-footprint-optimization/carbon-footprint-optimization.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Cost Explorer, EventBridge, Lambda, DynamoDB* • ⏱️ 120 minutes
- **[Automated Cost Analytics with Worker Pools and BigQuery](gcp/automated-cost-analytics-worker-pools-bigquery/automated-cost-analytics-worker-pools-bigquery.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, BigQuery, Cloud Billing API, Pub/Sub* • ⏱️ 30 minutes
- **[Automated Cost Optimization with Intelligent Monitoring](azure/automated-cost-optimization-system/automated-cost-optimization-system.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Advisor, Azure Cost Management, Azure Monitor, Azure Logic Apps* • ⏱️ 120 minutes
- **[Automated Patching with Systems Manager](aws/automated-patching-systems-manager/automated-patching-systems-manager.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager, EC2, CloudWatch, SNS* • ⏱️ 120 minutes
- **[Automated Regulatory Compliance Reporting with Document AI and Scheduler](gcp/automated-regulatory-compliance-document-ai-scheduler/automated-regulatory-compliance-document-ai-scheduler.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Cloud Scheduler, Cloud Functions, Cloud Storage* • ⏱️ 45 minutes
- **[Automated Server Patching with Update Manager and Notifications](azure/automated-server-patching-update-manager-notifications/automated-server-patching-update-manager-notifications.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Update Manager, Action Groups, Virtual Machines* • ⏱️ 20 minutes
- **[Basic Log Monitoring with CloudWatch](aws/basic-log-monitoring-cloudwatch/basic-log-monitoring-cloudwatch.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, SNS, Lambda* • ⏱️ 60 minutes
- **[Basic Monitoring with CloudWatch Alarms](aws/basic-monitoring-cloudwatch-alarms/basic-monitoring-cloudwatch-alarms.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, SNS* • ⏱️ 30 minutes
- **[Business Continuity Testing with Systems Manager](aws/business-continuity-testing-systems/business-continuity-testing-systems.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager, CloudFormation, EventBridge, CloudWatch* • ⏱️ 180 minutes
- **[Carbon-Aware Cost Optimization with Azure Carbon Optimization and Azure Automation](azure/carbon-aware-cost-optimization-sustainability-automation/carbon-aware-cost-optimization-sustainability-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Carbon Optimization, Automation, Cost Management, Logic Apps* • ⏱️ 120 minutes
- **[Centralized Alert Management with User Notifications and CloudWatch](aws/centralized-alert-management-notifications/centralized-alert-management-notifications.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: User Notifications, CloudWatch, S3* • ⏱️ 25 minutes
- **[Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory](gcp/database-fleet-governance-database-center-cloud-asset-inventory/database-fleet-governance-database-center-cloud-asset-inventory.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Database Center, Cloud Asset Inventory, Cloud Workflows, Cloud Monitoring* • ⏱️ 75 minutes
- **[Centralized Hybrid Cloud Governance with Arc and Policy](azure/centralized-hybrid-cloud-governance/centralized-hybrid-cloud-governance.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Arc, Azure Policy, Azure Monitor, Azure Resource Graph* • ⏱️ 120 minutes
- **[Centralized Logging with OpenSearch Service](aws/centralized-logging-opensearch/centralized-logging-opensearch.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: OpenSearch Service, CloudWatch, Lambda, Kinesis* • ⏱️ 55 minutes
- **[Cloud Asset Governance with Cloud Asset Inventory and Cloud Workflows](gcp/cloud-asset-governance-asset-inventory-workflows/cloud-asset-governance-asset-inventory-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Asset Inventory, Cloud Workflows, Cloud Functions, Cloud Monitoring* • ⏱️ 120 minutes
- **[Communication Monitoring with Communication Services and Application Insights](azure/communication-monitoring-services-insights/communication-monitoring-services-insights.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Communication Services, Application Insights* • ⏱️ 20 minutes
- **[Cost Allocation and Chargeback Systems](aws/cost-allocation-chargeback-systems/cost-allocation-chargeback-systems.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: organizations, cost-explorer, budgets, lambda, +1 more* • ⏱️ 120 minutes
- **[Cost Estimation Planning with Pricing Calculator and S3](aws/cost-estimation-pricing-calculator-s3/cost-estimation-pricing-calculator-s3.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Pricing Calculator, S3, Budgets, SNS* • ⏱️ 25 minutes
- **[Cost Monitoring with Cost Explorer and Budgets](aws/cost-monitoring-explorer-budgets/cost-monitoring-explorer-budgets.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Cost Explorer, Budgets, SNS* • ⏱️ 25 minutes
- **[Cost Optimization Workflows with Budgets](aws/cost-optimization-workflows-budgets/cost-optimization-workflows-budgets.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Cost Optimization Hub, AWS Budgets, SNS, Lambda* • ⏱️ 90 minutes
- **[Cross-Region Disaster Recovery Automation](aws/cross-region-dr-automation/cross-region-dr-automation.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: elastic-disaster-recovery, lambda, cloudwatch, systems-manager* • ⏱️ 180 minutes
- **[Cross-Tenant Governance Framework with Lighthouse and Automanage](azure/cross-tenant-governance-framework/cross-tenant-governance-framework.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Lighthouse, Azure Automanage, Azure Monitor* • ⏱️ 120 minutes
- **[Disaster Recovery Orchestration with Service Extensions and Backup and DR Service](gcp/disaster-recovery-orchestration-service-extensions-backup-dr-service/disaster-recovery-orchestration-service-extensions-backup-dr-service.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Load Balancing, Backup and DR Service, Cloud Functions, Service Extensions* • ⏱️ 180 minutes
- **[Dynamic Resource Governance with Cloud Asset Inventory and Policy Simulator](gcp/dynamic-resource-governance-asset-inventory-policy-simulator/dynamic-resource-governance-asset-inventory-policy-simulator.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Asset Inventory, Policy Simulator, Cloud Functions, Cloud Pub/Sub* • ⏱️ 90 minutes
- **[Enterprise Cost Governance Dashboard with Resource Graph](azure/enterprise-cost-governance-dashboard/enterprise-cost-governance-dashboard.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Resource Graph, Azure Cost Management, Power BI, Azure Logic Apps* • ⏱️ 120 minutes
- **[Global Financial Compliance Monitoring with Cloud Spanner and Cloud Tasks](gcp/global-financial-compliance-monitoring-spanner-tasks/global-financial-compliance-monitoring-spanner-tasks.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Spanner, Cloud Tasks, Cloud Functions, Cloud Logging* • ⏱️ 150 minutes
- **[Governance Automation with Blueprints and Well-Architected Framework](azure/governance-automation-blueprints-well-architected/governance-automation-blueprints-well-architected.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Blueprints, Azure Policy, Azure Resource Manager, Azure Advisor* • ⏱️ 120 minutes
- **[Governance Dashboard Automation with Resource Graph and Monitor Workbooks](azure/governance-dashboard-automation/governance-dashboard-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Resource Graph, Azure Monitor Workbooks, Azure Policy, Azure Logic Apps* • ⏱️ 120 minutes
- **[Infrastructure Anomaly Detection with Cloud Monitoring and Gemini](gcp/infrastructure-anomaly-detection-monitoring-gemini/infrastructure-anomaly-detection-monitoring-gemini.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Monitoring, Vertex AI, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes
- **[Infrastructure Change Monitoring with Cloud Asset Inventory and Pub/Sub](gcp/infrastructure-change-monitoring-asset-inventory-pub-sub/infrastructure-change-monitoring-asset-inventory-pub-sub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Asset Inventory, Pub/Sub, Cloud Functions, BigQuery* • ⏱️ 75 minutes
- **[Infrastructure Inventory Reports with Resource Graph](azure/infrastructure-inventory-resource-graph/infrastructure-inventory-resource-graph.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Resource Graph, Azure CLI* • ⏱️ 15 minutes
- **[Infrastructure Monitoring Setup with Systems Manager](aws/infrastructure-monitoring-quick-setup/infrastructure-monitoring-quick-setup.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager, CloudWatch* • ⏱️ 25 minutes
- **[Infrastructure Monitoring with CloudTrail and Config](aws/infrastructure-monitoring-governance/infrastructure-monitoring-governance.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cloudtrail, config, systems-manager* • ⏱️ 120 minutes
- **[Intelligent Alert Response Automation with Monitor Workbooks and Azure Functions](azure/intelligent-alert-response-automation/intelligent-alert-response-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Monitor Workbooks, Azure Functions, Azure Event Grid, Azure Logic Apps* • ⏱️ 120 minutes
- **[Intelligent Cost Anomaly Detection](aws/intelligent-cost-anomaly-detection/intelligent-cost-anomaly-detection.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, Lambda, SNS, Cost Explorer* • ⏱️ 90 minutes
- **[Microservices Observability with Service Fabric and Application Insights](azure/microservices-observability-service-fabric-insights/microservices-observability-service-fabric-insights.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Service Fabric, Application Insights, Azure Functions, Event Hubs* • ⏱️ 120 minutes
- **[Migrate On-Premises SCOM to Azure Monitor Managed Instance](azure/migrate-scom-azure-monitor-managed-instance/migrate-scom-azure-monitor-managed-instance.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Monitor SCOM Managed Instance, Azure SQL Managed Instance, Azure Virtual Network* • ⏱️ 150 minutes
- **[Monitor High-Performance Computing with HPC Cache and Workbooks](azure/monitor-hpc-workloads-cache-monitor-workbooks/monitor-hpc-workloads-cache-monitor-workbooks.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure HPC Cache, Azure Monitor Workbooks, Azure Batch, Azure Storage* • ⏱️ 90 minutes
- **[Multi-Cloud Resource Discovery with Cloud Location Finder and Pub/Sub](gcp/multi-cloud-resource-discovery-location-finder-pub-sub/multi-cloud-resource-discovery-location-finder-pub-sub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Location Finder, Pub/Sub, Cloud Functions, Cloud Storage* • ⏱️ 120 minutes
- **[Multi-Service Monitoring Dashboards](aws/multi-service-monitoring-dashboards/multi-service-monitoring-dashboards.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, Lambda, ECS, RDS* • ⏱️ 180 minutes
- **[Optimizing Costs with Automated Savings Plans](aws/optimizing-costs-with-savings-plans/optimizing-costs-with-savings-plans.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cost-explorer, savings-plans, lambda, s3* • ⏱️ 60 minutes
- **[Organizations Multi-Account Governance with SCPs](aws/organizations-governance/organizations-governance.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Organizations, IAM, CloudTrail, Budgets* • ⏱️ 180 minutes
- **[OS Patch Management with VM Manager and Cloud Scheduler](gcp/os-patch-management-vm-manager-scheduler/os-patch-management-vm-manager-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: VM Manager, Cloud Scheduler, Compute Engine, Cloud Monitoring* • ⏱️ 75 minutes
- **[Proactive Infrastructure Health Monitoring Service Health Update Manager](azure/proactive-resource-health-monitoring-automation/proactive-resource-health-monitoring-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Resource Health, Azure Service Bus, Azure Logic Apps, Azure Monitor* • ⏱️ 120 minutes
- **[Proactive Infrastructure Health Monitoring with Azure Service Health and Azure Update Manager](azure/proactive-infrastructure-health-monitoring-service-health-update-manager/proactive-infrastructure-health-monitoring-service-health-update-manager.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Service Health, Azure Update Manager, Azure Logic Apps, Azure Monitor* • ⏱️ 75 minutes
- **[Resource Allocation with Cloud Quotas API and Cloud Run GPU](gcp/resource-allocation-quotas-api-run-gpu/resource-allocation-quotas-api-run-gpu.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Quotas API, Cloud Run GPU, Cloud Monitoring, Cloud Functions* • ⏱️ 120 minutes
- **[Resource Governance with Policy Simulator and Resource Manager](gcp/resource-governance-policy-simulator-resource-manager/resource-governance-policy-simulator-resource-manager.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Policy Simulator, Resource Manager, Cloud Billing API, Cloud Functions* • ⏱️ 120 minutes
- **[Resource Organization with Resource Groups and Tags](azure/resource-organization-groups-tags/resource-organization-groups-tags.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Resource Manager, Azure Portal* • ⏱️ 15 minutes
- **[Resource Tagging and Cost Allocation with Policy Simulator and Cloud Asset Inventory](gcp/resource-tagging-cost-allocation-policy-simulator-asset-inventory/resource-tagging-cost-allocation-policy-simulator-asset-inventory.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Asset Inventory, Organization Policy, Cloud Billing, Cloud Functions* • ⏱️ 75 minutes
- **[Resource Tagging Automation with Lambda and EventBridge](aws/resource-tagging-automation-lambda-eventbridge/resource-tagging-automation-lambda-eventbridge.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Lambda, EventBridge, Resource Groups* • ⏱️ 25 minutes
- **[Secure Cross-Organization Data Sharing with Data Share and Service Fabric](azure/secure-cross-organization-data-sharing/secure-cross-organization-data-sharing.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Data Share, Azure Service Fabric, Azure Key Vault, Azure Monitor* • ⏱️ 120 minutes
- **[Service Catalog Portfolio with CloudFormation Templates](aws/service-catalog-portfolio-cloudformation/service-catalog-portfolio-cloudformation.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Service Catalog, CloudFormation* • ⏱️ 25 minutes
- **[Service Health Monitoring with Azure Service Health and Monitor](azure/service-health-monitoring-alerts/service-health-monitoring-alerts.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Service Health, Azure Monitor* • ⏱️ 15 minutes
- **[Service Health Notifications with Health and SNS](aws/service-health-notifications-health-sns/service-health-notifications-health-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Health, SNS, EventBridge* • ⏱️ 25 minutes
- **[Service Quota Monitoring with CloudWatch Alarms](aws/service-quota-monitoring-cloudwatch/service-quota-monitoring-cloudwatch.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Service Quotas, CloudWatch, SNS* • ⏱️ 25 minutes
- **[Simple Application Health Monitoring with Cloud Monitoring](gcp/simple-health-monitoring-cloud-monitoring-functions/simple-health-monitoring-cloud-monitoring-functions.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Monitoring, Cloud Functions* • ⏱️ 15 minutes
- **[Simple Configuration Management with Parameter Store and CloudShell](aws/simple-configuration-management-parameter-store-cloudshell/simple-configuration-management-parameter-store-cloudshell.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager Parameter Store, CloudShell* • ⏱️ 25 minutes
- **[Simple Environment Health Check with Systems Manager and SNS](aws/simple-environment-health-check-ssm-sns/simple-environment-health-check-ssm-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Systems Manager, SNS, Lambda, EventBridge* • ⏱️ 25 minutes
- **[Simple Log Analysis with CloudWatch Insights and SNS](aws/simple-log-analysis-insights-sns/simple-log-analysis-insights-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, SNS, Lambda* • ⏱️ 25 minutes
- **[Simple Log Retention Management with CloudWatch and Lambda](aws/simple-log-retention-cloudwatch-lambda/simple-log-retention-cloudwatch-lambda.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch Logs, Lambda* • ⏱️ 25 minutes
- **[Simple Resource Monitoring Dashboard with Azure Monitor Workbooks](azure/simple-resource-monitoring-dashboard-workbooks/simple-resource-monitoring-dashboard-workbooks.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Monitor, Workbooks* • ⏱️ 15 minutes
- **[Simple Resource Monitoring with CloudWatch and SNS](aws/simple-resource-monitoring-cloudwatch-sns/simple-resource-monitoring-cloudwatch-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, SNS, EC2* • ⏱️ 25 minutes
- **[Simple Website Uptime Checker with Functions and Application Insights](azure/simple-uptime-checker-functions-insights/simple-uptime-checker-functions-insights.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Functions, Application Insights* • ⏱️ 15 minutes
- **[Simple Website Uptime Monitoring with Cloud Monitoring and Pub/Sub](gcp/simple-website-uptime-monitoring-cloud-monitoring-pubsub/simple-website-uptime-monitoring-cloud-monitoring-pubsub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Monitoring, Pub/Sub, Cloud Functions* • ⏱️ 30 minutes
- **[Simple Website Uptime Monitoring with Route53 and SNS](aws/simple-uptime-monitoring-route53-sns/simple-uptime-monitoring-route53-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Route53, SNS* • ⏱️ 25 minutes
- **[Site Recovery Automation with Integrated Update Management](azure/site-recovery-automation-with-updates/site-recovery-automation-with-updates.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Site Recovery, Azure Update Manager, Azure Monitor, Azure Automation* • ⏱️ 120 minutes
- **[Virtual Desktop Cost Optimization with Reserved Instances](azure/virtual-desktop-cost-optimization-automation/virtual-desktop-cost-optimization-automation.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Virtual Desktop, Azure Reserved VM Instances, Azure Cost Management, Azure Logic Apps* • ⏱️ 120 minutes
- **[VMware Cloud Migration with VMware Cloud on AWS](aws/vmware-cloud-migration/vmware-cloud-migration.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: VMware Cloud on AWS, AWS Application Migration Service, AWS Direct Connect, CloudWatch* • ⏱️ 180 minutes
- **[Website Monitoring with CloudWatch Synthetics](aws/website-monitoring-synthetics-cloudwatch/website-monitoring-synthetics-cloudwatch.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: CloudWatch, Synthetics* • ⏱️ 25 minutes
- **[Website Uptime Monitoring with Route 53](aws/website-uptime-monitoring/website-uptime-monitoring.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Route 53, CloudWatch, SNS* • ⏱️ 60 minutes

---

## 🔗 Integration & Messaging

*Message queues, event streaming, workflow orchestration, and system integration*

- **[Automated Service Discovery with Service Connector and Tables](azure/automated-service-discovery-connector-tables/automated-service-discovery-connector-tables.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Service Connector, Azure Tables, Azure Functions, Azure App Service* • ⏱️ 120 minutes
- **[Automating Reserved Instance Management](aws/reserved-instance-automation/reserved-instance-automation.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cost-explorer, lambda, eventbridge, sns* • ⏱️ 120 minutes
- **[Budget Alerts and Automated Cost Actions](aws/budget-alerts-automated-actions/budget-alerts-automated-actions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Budgets, SNS, Lambda, CloudWatch* • ⏱️ 60 minutes
- **[Budget Monitoring with Budgets and SNS](aws/budget-monitoring-budgets-sns/budget-monitoring-budgets-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Budgets, SNS* • ⏱️ 25 minutes
- **[Business File Processing with Transfer Family](aws/business-file-processing-transfer/business-file-processing-transfer.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: transfer-family, step-functions, lambda, s3* • ⏱️ 120 minutes
- **[Business Productivity Workflows with Google Workspace APIs and Cloud Functions](gcp/business-productivity-workspace-apis-functions/business-productivity-workspace-apis-functions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Functions, Cloud Scheduler, Cloud SQL, Google Workspace APIs* • ⏱️ 75 minutes
- **[Community Knowledge Base with re:Post Private and SNS](aws/community-knowledge-base-repost-sns/community-knowledge-base-repost-sns.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS re:Post Private, SNS* • ⏱️ 25 minutes
- **[Cost Anomaly Detection with Machine Learning](aws/cost-anomaly-detection/cost-anomaly-detection.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: cost-anomaly-detection, sns, cloudwatch, eventbridge* • ⏱️ 60 minutes
- **[Cost Governance Automation with Config](aws/cost-governance-automation-config/cost-governance-automation-config.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Config, Lambda, SNS, EventBridge* • ⏱️ 180 minutes
- **[CQRS and Event Sourcing with EventBridge](aws/cqrs-event-sourcing-eventbridge/cqrs-event-sourcing-eventbridge.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, dynamodb, lambda* • ⏱️ 120 minutes
- **[Cross-Platform Push Notifications with Spring Microservices](azure/cross-platform-push-notifications/cross-platform-push-notifications.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Notification Hubs, Azure Spring Apps, Azure Key Vault, Azure Monitor* • ⏱️ 90 minutes
- **[Distributed Tracing with X-Ray and EventBridge](aws/distributed-tracing-xray-eventbridge/distributed-tracing-xray-eventbridge.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: x-ray, eventbridge, lambda, api-gateway* • ⏱️ 120 minutes
- **[Distributed Transaction Processing with SQS](aws/distributed-transactions-sqs-dynamodb/distributed-transactions-sqs-dynamodb.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sqs, dynamodb, lambda, cloudwatch* • ⏱️ 120 minutes
- **[Dynamic Email Campaign Workflows with Gmail API and Cloud Scheduler](gcp/dynamic-email-campaign-workflows-gmail-api-scheduler/dynamic-email-campaign-workflows-gmail-api-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Gmail API, Cloud Scheduler, Cloud Functions, Cloud Storage* • ⏱️ 90 minutes
- **[Event Sourcing with EventBridge and DynamoDB](aws/event-sourcing/event-sourcing.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: eventbridge, dynamodb, lambda, iam* • ⏱️ 120 minutes
- **[Microservices Choreography with Service Bus and Observability](azure/microservices-choreography-service-bus-observability/microservices-choreography-service-bus-observability.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Service Bus, Azure Monitor, Azure Functions, Azure Container Apps* • ⏱️ 105 minutes
- **[Multi-Language Content Localization Workflows with Azure Translator and Azure AI Document Intelligence](azure/multi-language-content-localization-translator-document-intelligence/multi-language-content-localization-translator-document-intelligence.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Translator, Azure AI Document Intelligence, Azure Logic Apps, Azure Blob Storage* • ⏱️ 120 minutes
- **[Orchestrating Distributed Transactions with Saga Patterns](aws/orchestrating-distributed-transactions-with-sagas/orchestrating-distributed-transactions-with-sagas.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Step Functions, Lambda, DynamoDB, SNS* • ⏱️ 120 minutes
- **[Processing Ordered Messages with SQS FIFO and Dead Letter Queues](aws/ordered-message-processing-sqs-fifo-dlq/ordered-message-processing-sqs-fifo-dlq.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: sqs, lambda, cloudwatch, dynamodb* • ⏱️ 120 minutes
- **[Real-Time Collaborative Workspace with Video Integration](azure/real-time-collaborative-workspace/real-time-collaborative-workspace.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Communication Services, Azure Fluid Relay, Azure Functions, Azure Storage* • ⏱️ 90 minutes
- **[Simple Message Queue with Service Bus](azure/simple-message-queue-service-bus/simple-message-queue-service-bus.md)** - ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Service Bus, Azure CLI* • ⏱️ 15 minutes
- **[Smart Invoice Processing with Document AI and Workflows](gcp/smart-invoice-processing-document-ai-workflows/smart-invoice-processing-document-ai-workflows.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Document AI, Workflows, Cloud Tasks, Gmail API* • ⏱️ 45 minutes
- **[Unified Customer Communication Platform with Event-Driven Messaging](azure/unified-customer-communication-platform/unified-customer-communication-platform.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Communication Services, Azure Event Grid, Azure Functions, Azure Cosmos DB* • ⏱️ 120 minutes
- **[Workflow Automation with Google Workspace Flows and Service Extensions](gcp/workflow-automation-workspace-flows-service-extensions/workflow-automation-workspace-flows-service-extensions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Workspace Flows, Service Extensions, Cloud Functions, Pub/Sub* • ⏱️ 120 minutes

---

## 📱 IoT & Edge Computing

*Internet of Things platforms, edge computing, and device management*

- **[Digital Twin Manufacturing Resilience with IoT and Vertex AI](gcp/digital-twin-manufacturing-resilience-iot-vertex/digital-twin-manufacturing-resilience-iot-vertex.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Pub/Sub, Vertex AI, BigQuery, Cloud Functions* • ⏱️ 45 minutes
- **[Edge Analytics with Cloud Run WebAssembly and Pub/Sub](gcp/edge-analytics-cloud-run-webassembly-pub-sub/edge-analytics-cloud-run-webassembly-pub-sub.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Run, Pub/Sub, Cloud Storage, Cloud Monitoring* • ⏱️ 120 minutes
- **[Edge Computing with IoT Greengrass and Lambda](aws/edge-computing-iot-greengrass/edge-computing-iot-greengrass.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, greengrass, lambda, iam* • ⏱️ 120 minutes
- **[Industrial IoT Data Collection with SiteWise](aws/industrial-iot-data-collection/industrial-iot-data-collection.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-sitewise, iot-core, timestream, cloudwatch* • ⏱️ 120 minutes
- **[IoT Data Ingestion with IoT Core](aws/iot-data-ingestion/iot-data-ingestion.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IoT Core, Lambda, DynamoDB, SNS* • ⏱️ 60 minutes
- **[IoT Device Fleet Management with MQTT and Pub/Sub](gcp/iot-device-fleet-management-mqtt-pubsub/iot-device-fleet-management-mqtt-pubsub.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: IoT Core, Cloud Pub/Sub, Cloud Functions, Cloud Monitoring* • ⏱️ 45 minutes
- **[IoT Device Lifecycle Management with AWS IoT Core](aws/iot-device-lifecycle/iot-device-lifecycle.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, iot-device-management, cloudwatch, iot-jobs* • ⏱️ 120 minutes
- **[IoT Device Provisioning and Certificate Management](aws/iot-device-provisioning/iot-device-provisioning.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, lambda, dynamodb, iam* • ⏱️ 120 minutes
- **[IoT Device Registry with IoT Core](aws/iot-device-registry/iot-device-registry.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, iot-device-management, lambda, cloudwatch* • ⏱️ 60 minutes
- **[IoT Device Shadow Synchronization](aws/iot-device-shadow-sync/iot-device-shadow-sync.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IoT Core, Device Shadow, Lambda, DynamoDB* • ⏱️ 180 minutes
- **[IoT Device Shadows for State Management](aws/iot-device-shadows/iot-device-shadows.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, device-shadows, lambda, iam* • ⏱️ 60 minutes
- **[IoT Event Processing with Rules Engine](aws/iot-event-processing/iot-event-processing.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, lambda, dynamodb, sns* • ⏱️ 120 minutes
- **[IoT Firmware Updates with Device Management Jobs](aws/iot-firmware-updates/iot-firmware-updates.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot, lambda, s3, signer* • ⏱️ 180 minutes
- **[IoT Fleet Monitoring with Device Defender](aws/iot-fleet-monitoring/iot-fleet-monitoring.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, iot-device-defender, cloudwatch, lambda* • ⏱️ 120 minutes
- **[IoT Over-the-Air Updates with Device Management](aws/iot-ota-updates/iot-ota-updates.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: iot-core, iot-device-management, s3, cloudwatch* • ⏱️ 120 minutes
- **[Predictive Maintenance with IoT Digital Twins](azure/predictive-maintenance-iot-digital-twins/predictive-maintenance-iot-digital-twins.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Digital Twins, Azure Data Explorer, Azure IoT Central, Event Hubs* • ⏱️ 120 minutes
- **[Predictive Maintenance with IoT Edge Analytics](azure/predictive-maintenance-iot-edge-analytics/predictive-maintenance-iot-edge-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure IoT Edge, Azure Monitor, Azure Stream Analytics, Azure Storage* • ⏱️ 90 minutes
- **[Predictive Manufacturing Digital Twins with Azure IoT Hub and Digital Twins](azure/predictive-manufacturing-digital-twins-azure-iot/predictive-manufacturing-digital-twins-azure-iot.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure IoT Hub, Azure Digital Twins, Azure Data Explorer, Azure Machine Learning* • ⏱️ 120 minutes
- **[Real-Time Anomaly Detection with Azure IoT Edge and Azure ML](azure/real-time-anomaly-detection-iot-edge-ml/real-time-anomaly-detection-iot-edge-ml.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: IoT Edge, Machine Learning, IoT Hub, Stream Analytics* • ⏱️ 120 minutes
- **[Real-Time Inventory Intelligence with Google Distributed Cloud Edge and Cloud Vision](gcp/real-time-inventory-intelligence-distributed-cloud-edge-vision/real-time-inventory-intelligence-distributed-cloud-edge-vision.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Google Distributed Cloud Edge, Cloud Vision API, Cloud SQL, Cloud Monitoring* • ⏱️ 120 minutes
- **[Secure IoT Edge Analytics with Azure Sphere and IoT Edge](azure/secure-iot-edge-analytics-percept-sphere/secure-iot-edge-analytics-percept-sphere.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Sphere, Azure IoT Hub, Azure IoT Edge, Azure Stream Analytics* • ⏱️ 150 minutes
- **[Smart City Infrastructure Monitoring with IoT and AI](gcp/smart-city-infrastructure-monitoring-iot-ai/smart-city-infrastructure-monitoring-iot-ai.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Pub/Sub, Vertex AI, Cloud Monitoring, BigQuery* • ⏱️ 45 minutes
- **[Smart Factory Edge-to-Cloud Analytics with IoT Operations and Event Hubs](azure/smart-factory-edge-to-cloud-analytics/smart-factory-edge-to-cloud-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure IoT Operations, Azure Event Hubs, Azure Stream Analytics, Azure Monitor* • ⏱️ 120 minutes
- **[Smart Parking Management with Maps Platform and IoT Core](gcp/smart-parking-management-maps-iot/smart-parking-management-maps-iot.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Maps Platform, Pub/Sub, Firestore, Cloud Functions* • ⏱️ 45 minutes
- **[Sustainable Manufacturing Monitoring with IoT SiteWise](aws/sustainable-manufacturing-monitoring/sustainable-manufacturing-monitoring.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: IoT SiteWise, CloudWatch, Lambda, QuickSight* • ⏱️ 120 minutes
- **[Unified Edge-to-Cloud Security Updates with IoT Device Update and Update Manager](azure/unified-edge-to-cloud-security-updates/unified-edge-to-cloud-security-updates.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure IoT Device Update, Azure Update Manager, Azure IoT Hub, Azure Monitor* • ⏱️ 105 minutes
- **[Vehicle Telemetry Analytics with IoT FleetWise](aws/vehicle-telemetry-analytics/vehicle-telemetry-analytics.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS IoT FleetWise, Amazon Timestream, Amazon Managed Grafana, S3* • ⏱️ 120 minutes

---

## 🎬 Media & Content

*Media processing, streaming, content management, and digital asset handling*

- **[Adaptive Bitrate Video Streaming with CloudFront](aws/adaptive-video-streaming-cloudfront/adaptive-video-streaming-cloudfront.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: MediaConvert, S3, CloudFront, Lambda* • ⏱️ 180 minutes
- **[Audio Processing Pipelines with MediaConvert](aws/audio-processing-mediaconvert/audio-processing-mediaconvert.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: MediaConvert, S3, Lambda, IAM* • ⏱️ 180 minutes
- **[Automated Video Content Analysis with Rekognition](aws/video-content-analysis-rekognition/video-content-analysis-rekognition.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: rekognition, stepfunctions, lambda, s3* • ⏱️ 180 minutes
- **[Immersive XR Content Delivery with Immersive Stream for XR and Cloud CDN](gcp/immersive-xr-content-delivery-immersive-stream-xr-cdn/immersive-xr-content-delivery-immersive-stream-xr-cdn.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Immersive Stream for XR, Cloud CDN, Cloud Storage* • ⏱️ 120 minutes
- **[Live Event Broadcasting with Elemental MediaConnect](aws/live-event-broadcasting/live-event-broadcasting.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: mediaconnect, medialive, mediapackage, cloudwatch* • ⏱️ 180 minutes
- **[Live Video Streaming Platform with MediaLive](aws/video-streaming-medialive/video-streaming-medialive.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: medialive, mediapackage, cloudfront, s3* • ⏱️ 120 minutes
- **[Orchestrating Media Workflows with MediaConnect and Step Functions](aws/orchestrating-media-workflows-mediaconnect-stepfunctions/orchestrating-media-workflows-mediaconnect-stepfunctions.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: AWS Elemental MediaConnect, AWS Step Functions, CloudWatch, SNS* • ⏱️ 90 minutes
- **[Podcast Content Generation with Text-to-Speech and Natural Language](gcp/podcast-content-generation-text-speech-natural-language/podcast-content-generation-text-speech-natural-language.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Text-to-Speech, Natural Language API, Cloud Storage, Cloud Functions* • ⏱️ 120 minutes
- **[Real-Time Streaming Analytics with Cloud Media CDN and Live Stream API](gcp/real-time-streaming-analytics-media-cdn-live-stream-api/real-time-streaming-analytics-media-cdn-live-stream-api.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Live Stream API, Media CDN, Cloud Functions, BigQuery* • ⏱️ 120 minutes
- **[Scalable Audio Content Distribution with Chirp 3 and Memorystore Valkey](gcp/scalable-audio-content-distribution-chirp-memorystore-valkey/scalable-audio-content-distribution-chirp-memorystore-valkey.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Text-to-Speech, Memorystore for Valkey, Cloud Storage, Cloud CDN* • ⏱️ 120 minutes
- **[Scalable Live Streaming with Elemental MediaLive](aws/scalable-live-streaming/scalable-live-streaming.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: medialive, mediapackage, cloudfront, s3* • ⏱️ 120 minutes
- **[Serverless Video Transcription with Video Indexer and Event Grid](azure/serverless-video-transcription-video-indexer-event-grid/serverless-video-transcription-video-indexer-event-grid.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Video Indexer, Azure Event Grid, Azure Blob Storage, Azure Functions* • ⏱️ 90 minutes
- **[Video Content Moderation Workflows with Video Intelligence API and Cloud Scheduler](gcp/video-content-moderation-video-intelligence-scheduler/video-content-moderation-video-intelligence-scheduler.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Video Intelligence API, Cloud Scheduler, Cloud Functions, Cloud Storage* • ⏱️ 120 minutes
- **[Video Content Processing Workflows with Azure Container Instances and Azure Logic Apps](azure/video-content-processing-workflows-container-instances-logic-apps/video-content-processing-workflows-container-instances-logic-apps.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Container Instances, Azure Logic Apps, Azure Event Grid, Azure Blob Storage* • ⏱️ 120 minutes
- **[Video DRM Protection with MediaPackage](aws/video-drm-protection-mediapackage/video-drm-protection-mediapackage.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: mediapackage, medialive, secrets, manager, +2 more* • ⏱️ 180 minutes
- **[Video Workflow Orchestration with Step Functions](aws/video-workflow-orchestration-stepfunctions/video-workflow-orchestration-stepfunctions.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: Step Functions, MediaConvert, S3, Lambda* • ⏱️ 240 minutes
- **[Video-on-Demand Platform with MediaStore](aws/video-on-demand-mediastore/video-on-demand-mediastore.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![AWS](https://img.shields.io/badge/AWS-FF9900) 
<br>*Services: mediastore, cloudfront, s3, iam* • ⏱️ 120 minutes

---

## 🏢 Specialized Solutions

*Industry-specific solutions, blockchain, gaming, and emerging technologies*

- **[Collaborative Spatial Computing Applications with Cloud Rendering](azure/collaborative-spatial-computing-applications/collaborative-spatial-computing-applications.md)** - ![Advanced](https://img.shields.io/badge/Advanced-orange) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Remote Rendering, Azure Spatial Anchors, Azure Blob Storage, Azure Active Directory* • ⏱️ 120 minutes
- **[Disaster Recovery Orchestration with Cloud WAN and Parallelstore](gcp/disaster-recovery-cloud-wan-parallelstore/disaster-recovery-cloud-wan-parallelstore.md)** - ![Expert](https://img.shields.io/badge/Expert-red) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Network Connectivity Center, Parallelstore, Cloud Workflows, Cloud Monitoring* • ⏱️ 150 minutes
- **[Location-Based AR Gaming with Multiplayer Support](azure/location-based-ar-gaming-multiplayer/location-based-ar-gaming-multiplayer.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: PlayFab, Spatial Anchors, Functions, Event Grid* • ⏱️ 120 minutes
- **[Remote Developer Onboarding with Cloud Workstations and Firebase Studio](gcp/remote-developer-onboarding-workstations-firebase-studio/remote-developer-onboarding-workstations-firebase-studio.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Google Cloud Platform](https://img.shields.io/badge/Google%20Cloud%20Platform-4285F4) 
<br>*Services: Cloud Workstations, Firebase Studio, Cloud Source Repositories, Identity and Access Management* • ⏱️ 120 minutes
- **[Scalable Session Management with Redis and App Service](azure/scalable-session-management-redis-app-service/scalable-session-management-redis-app-service.md)** - ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) ![Microsoft Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4) 
<br>*Services: Azure Cache for Redis, Azure App Service, Azure Monitor* • ⏱️ 90 minutes

---


## 🚀 Getting Started

### Prerequisites

Before implementing any recipe, ensure you have:

- ☁️ Active cloud provider account(s) (AWS, Azure, or GCP)
- 💻 Cloud CLI tools installed and configured
- 🔧 Basic understanding of cloud architecture concepts
- 📚 Familiarity with Infrastructure as Code (IaC) tools

### Usage

1. **Browse by Category**: Find recipes organized by service type and use case
2. **Check Difficulty**: Start with ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) recipes if you're new to cloud
3. **Follow Prerequisites**: Each recipe lists required tools and knowledge
4. **Implement Step-by-Step**: All recipes include detailed implementation guides
5. **Customize**: Adapt recipes to your specific requirements and constraints

### Difficulty Levels

- ![Beginner](https://img.shields.io/badge/Beginner-brightgreen) **Beginner (100)**: Basic concepts, minimal configuration
- ![Intermediate](https://img.shields.io/badge/Intermediate-yellow) **Intermediate (200)**: Multiple services integration  
- ![Advanced](https://img.shields.io/badge/Advanced-orange) **Advanced (300)**: Complex architectures, optimization
- ![Expert](https://img.shields.io/badge/Expert-red) **Expert (400)**: Enterprise patterns, advanced use cases

## 🏗️ Architecture Patterns

This collection covers major cloud architecture patterns:

- **Microservices & Containers**: Containerization, orchestration, service mesh
- **Serverless Computing**: Function-as-a-Service, event-driven architectures  
- **Data & Analytics**: Big data processing, real-time analytics, data lakes
- **Security & Compliance**: Identity management, encryption, governance
- **DevOps & CI/CD**: Automated deployment, infrastructure as code
- **Monitoring & Observability**: Logging, metrics, distributed tracing

## 🌍 Multi-Cloud Support

| Provider | Projects | Key Services |
|----------|----------|--------------|
| ☁️ **AWS** | 492 | Lambda, EC2, S3, RDS, VPC |
| ☁️ **Microsoft Azure** | 268 | Functions, VMs, Blob Storage, SQL Database |  
| ☁️ **Google Cloud** | 350 | Cloud Functions, Compute Engine, Cloud Storage |

## 🤝 Contributing

We welcome contributions! Here's how you can help:

### Adding New Recipes

1. **Fork** this repository
2. **Create** a new branch for your recipe
3. **Follow** our [recipe template](RECIPE_TEMPLATE.md)
4. **Test** your implementation thoroughly
5. **Submit** a pull request with detailed description

### Recipe Requirements

- ✅ **Complete Implementation**: Working code and configuration
- ✅ **Clear Documentation**: Step-by-step instructions
- ✅ **Architecture Diagram**: Visual representation using Mermaid
- ✅ **Prerequisites**: Required tools and knowledge
- ✅ **Cleanup Instructions**: Resource removal steps
- ✅ **Best Practices**: Security and cost optimization notes

### Guidelines

- Focus on **real-world scenarios** and practical solutions
- Include **cost estimates** and optimization tips
- Follow **cloud security best practices**
- Provide **troubleshooting** guidance
- Use **consistent formatting** and structure

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

### Attribution

If you use these recipes in your projects, please consider:
- ⭐ **Starring** this repository
- 🔗 **Linking back** to this project
- 📝 **Sharing** your implementations and improvements

## 🙏 Acknowledgments

- **Cloud Providers**: AWS, Microsoft Azure, Google Cloud Platform
- **Contributors**: All the amazing developers who shared their expertise
- **Community**: Cloud architecture enthusiasts and practitioners worldwide

## 📞 Support & Community

- 🐛 **Bug Reports**: [Open an Issue](https://github.com/mzazon/awesome-cloud-projects/issues)
- 💡 **Feature Requests**: [Start a Discussion](https://github.com/mzazon/awesome-cloud-projects/discussions)
- 💬 **Questions**: Join our [Community Chat](#) (coming soon)
- 📧 **Contact**: [mzazon@gmail.com](mailto:mzazon@gmail.com)

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=mzazon/awesome-cloud-projects&type=Date)](https://www.star-history.com/#mzazon/awesome-cloud-projects&Date)

---

<div align="center">

**[⬆ Back to Top](#-awesome-cloud-projects)**

*Last updated: 2025-12-12 16:13:35 UTC*  
*Generated automatically from 1110 cloud recipes*

**Made with ❤️ for the cloud community**

</div>