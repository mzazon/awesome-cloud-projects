#!/usr/bin/env python3
"""
Generate comprehensive learning paths from projects.json
"""
import json
from pathlib import Path
from collections import defaultdict

def load_projects(filepath):
    """Load projects from JSON file"""
    with open(filepath, 'r') as f:
        return json.load(f)

def generate_learning_paths(projects):
    """Generate comprehensive learning paths"""
    paths = []

    # 1. AWS Serverless Fundamentals (beginner → intermediate)
    aws_serverless = [p for p in projects if
                      p.get('provider') == 'aws' and
                      any(s.lower() in ['lambda', 'api gateway', 'step functions', 'eventbridge', 'sqs', 'sns']
                          for s in p.get('services', []))]
    aws_serverless_sorted = sorted(aws_serverless, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "aws-serverless-fundamentals",
        "name": "AWS Serverless Fundamentals",
        "description": "Master serverless architecture with Lambda, API Gateway, and event-driven patterns",
        "projectIds": [p['id'] for p in aws_serverless_sorted]
    })

    # 2. GCP Serverless Mastery
    gcp_serverless = [p for p in projects if
                      p.get('provider') == 'gcp' and
                      any(s.lower() in ['cloud functions', 'cloud run', 'pub/sub', 'cloud tasks', 'eventarc']
                          for s in p.get('services', []))]
    gcp_serverless_sorted = sorted(gcp_serverless, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "gcp-serverless-mastery",
        "name": "GCP Serverless Mastery",
        "description": "Deep dive into Cloud Run, Cloud Functions, and Pub/Sub patterns",
        "projectIds": [p['id'] for p in gcp_serverless_sorted]
    })

    # 3. Azure Serverless & Integration
    azure_serverless = [p for p in projects if
                        p.get('provider') == 'azure' and
                        any(s.lower() in ['azure functions', 'logic apps', 'event grid', 'service bus']
                            for s in p.get('services', []))]
    azure_serverless_sorted = sorted(azure_serverless, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "azure-serverless-integration",
        "name": "Azure Serverless & Integration",
        "description": "Build event-driven solutions with Azure Functions and Logic Apps",
        "projectIds": [p['id'] for p in azure_serverless_sorted]
    })

    # 4. AI & Machine Learning Quick Start (multi-cloud)
    ai_ml_projects = [p for p in projects if
                      p.get('category') == 'AI & Machine Learning']
    ai_ml_sorted = sorted(ai_ml_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:15]

    paths.append({
        "id": "ai-ml-quick-start",
        "name": "AI/ML Quick Start",
        "description": "Get started with cloud AI services - OpenAI, Bedrock, Vertex AI",
        "projectIds": [p['id'] for p in ai_ml_sorted]
    })

    # 5. Cloud Security Essentials (multi-cloud)
    security_projects = [p for p in projects if
                         p.get('category') == 'Security & Identity']
    security_sorted = sorted(security_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "cloud-security-essentials",
        "name": "Cloud Security Essentials",
        "description": "Implement security best practices across identity, encryption, and compliance",
        "projectIds": [p['id'] for p in security_sorted]
    })

    # 6. Container Orchestration Journey (Kubernetes focus)
    container_projects = [p for p in projects if
                          any(s.lower() in ['kubernetes', 'eks', 'aks', 'gke', 'docker', 'container']
                              for s in p.get('services', []) + [p.get('name', '').lower()])]
    container_sorted = sorted(container_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "container-orchestration-journey",
        "name": "Container Orchestration Journey",
        "description": "Master Kubernetes and container services across AWS EKS, Azure AKS, and Google GKE",
        "projectIds": [p['id'] for p in container_sorted]
    })

    # 7. Data Engineering Pipeline (databases & analytics)
    data_projects = [p for p in projects if
                     p.get('category') == 'Databases & Analytics']
    data_sorted = sorted(data_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "data-engineering-pipeline",
        "name": "Data Engineering Pipeline",
        "description": "Build end-to-end data pipelines with storage, processing, and analytics",
        "projectIds": [p['id'] for p in data_sorted]
    })

    # 8. Beginner-Friendly Projects (Under 30 Minutes)
    beginner_quick = [p for p in projects if
                      p.get('difficulty') == 'beginner' and
                      p.get('duration', 999) <= 30]
    beginner_sorted = sorted(beginner_quick, key=lambda x: x.get('duration', 999))[:15]

    paths.append({
        "id": "beginner-friendly-projects",
        "name": "Beginner-Friendly Projects (Under 30 Minutes)",
        "description": "Quick wins to build confidence and learn cloud basics",
        "projectIds": [p['id'] for p in beginner_sorted]
    })

    # 9. AWS Deep Dive (comprehensive AWS path)
    aws_projects = [p for p in projects if p.get('provider') == 'aws']
    aws_sorted = sorted(aws_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:20]

    paths.append({
        "id": "aws-deep-dive",
        "name": "AWS Deep Dive",
        "description": "Comprehensive AWS journey from basics to advanced architectures",
        "projectIds": [p['id'] for p in aws_sorted]
    })

    # 10. Azure Cloud Expert Path
    azure_projects = [p for p in projects if p.get('provider') == 'azure']
    azure_sorted = sorted(azure_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:20]

    paths.append({
        "id": "azure-cloud-expert",
        "name": "Azure Cloud Expert Path",
        "description": "Master Azure services from fundamentals to enterprise solutions",
        "projectIds": [p['id'] for p in azure_sorted]
    })

    # 11. GCP Professional Path
    gcp_projects = [p for p in projects if p.get('provider') == 'gcp']
    gcp_sorted = sorted(gcp_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:20]

    paths.append({
        "id": "gcp-professional-path",
        "name": "GCP Professional Path",
        "description": "Comprehensive Google Cloud Platform learning journey",
        "projectIds": [p['id'] for p in gcp_sorted]
    })

    # 12. Monitoring & Observability
    monitoring_projects = [p for p in projects if
                           p.get('category') == 'Monitoring & Management']
    monitoring_sorted = sorted(monitoring_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "monitoring-observability",
        "name": "Monitoring & Observability",
        "description": "Master cloud monitoring, logging, and observability practices",
        "projectIds": [p['id'] for p in monitoring_sorted]
    })

    # 13. Networking & CDN Mastery
    networking_projects = [p for p in projects if
                           p.get('category') == 'Networking & Content Delivery']
    networking_sorted = sorted(networking_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "networking-cdn-mastery",
        "name": "Networking & CDN Mastery",
        "description": "Learn cloud networking, VPCs, load balancing, and content delivery",
        "projectIds": [p['id'] for p in networking_sorted]
    })

    # 14. Application Modernization
    app_dev_projects = [p for p in projects if
                        p.get('category') == 'Application Development & Deployment']
    app_dev_sorted = sorted(app_dev_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "application-modernization",
        "name": "Application Modernization",
        "description": "Modernize applications with cloud-native patterns and DevOps practices",
        "projectIds": [p['id'] for p in app_dev_sorted]
    })

    # 15. IoT & Edge Computing
    iot_projects = [p for p in projects if
                    p.get('category') == 'IoT & Edge Computing']
    iot_sorted = sorted(iot_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:10]

    paths.append({
        "id": "iot-edge-computing",
        "name": "IoT & Edge Computing",
        "description": "Build IoT solutions with edge computing and device management",
        "projectIds": [p['id'] for p in iot_sorted]
    })

    # 16. Storage & Data Management
    storage_projects = [p for p in projects if
                        p.get('category') == 'Storage & Data Management']
    storage_sorted = sorted(storage_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:12]

    paths.append({
        "id": "storage-data-management",
        "name": "Storage & Data Management",
        "description": "Master cloud storage solutions and data lifecycle management",
        "projectIds": [p['id'] for p in storage_sorted]
    })

    # 17. Integration & Messaging Patterns
    integration_projects = [p for p in projects if
                            p.get('category') == 'Integration & Messaging']
    integration_sorted = sorted(integration_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:10]

    paths.append({
        "id": "integration-messaging",
        "name": "Integration & Messaging Patterns",
        "description": "Learn event-driven architectures and messaging patterns",
        "projectIds": [p['id'] for p in integration_sorted]
    })

    # 18. Cost Optimization & FinOps
    cost_projects = [p for p in projects if
                     any(keyword in p.get('name', '').lower() or keyword in p.get('description', '').lower()
                         for keyword in ['cost', 'budget', 'billing', 'savings', 'optimization', 'chargeback'])]
    cost_sorted = sorted(cost_projects, key=lambda x: (
        0 if x.get('difficulty') == 'beginner' else 1 if x.get('difficulty') == 'intermediate' else 2,
        x.get('duration', 999)
    ))[:10]

    paths.append({
        "id": "cost-optimization-finops",
        "name": "Cost Optimization & FinOps",
        "description": "Learn cloud cost management and financial operations best practices",
        "projectIds": [p['id'] for p in cost_sorted]
    })

    return paths

def main():
    # Load projects
    projects_file = Path('.publish/data/projects.json')
    projects = load_projects(projects_file)

    print(f"📊 Loaded {len(projects)} projects")

    # Generate learning paths
    paths = generate_learning_paths(projects)

    print(f"✨ Generated {len(paths)} learning paths")

    # Print summary
    for path in paths:
        print(f"\n  • {path['name']} ({len(path['projectIds'])} projects)")

    # Save to file
    output_file = Path('.publish/data/learning-paths.json')
    with open(output_file, 'w') as f:
        json.dump(paths, f, indent=2)

    print(f"\n✅ Saved to {output_file}")
    print(f"📈 Total learning paths: {len(paths)}")
    print(f"📚 Total project placements: {sum(len(p['projectIds']) for p in paths)}")

if __name__ == '__main__':
    main()
