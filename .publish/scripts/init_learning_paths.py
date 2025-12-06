#!/usr/bin/env python3
"""
Initialize learning-paths.json with curated learning paths.

This script creates an initial set of learning paths based on actual
project IDs from the awesome-cloud-projects repository.

Usage:
    python init_learning_paths.py [--output PATH]
"""

import argparse
import json
from pathlib import Path


def create_initial_paths():
    """Create initial learning paths."""
    paths = [
        {
            "id": "aws-serverless-fundamentals",
            "name": "AWS Serverless Fundamentals",
            "description": "Master serverless architecture with Lambda, API Gateway, and event-driven patterns",
            "projectIds": [
                "automated-report-generation-eventbridge",
                "s3-event-processing",
                "api-throttling-rate-limiting",
                "advanced-api-gateway-deployment-strategies",
                "async-api-patterns-gateway-sqs"
            ]
        },
        {
            "id": "multi-cloud-containers",
            "name": "Multi-Cloud Container Orchestration",
            "description": "Learn Kubernetes and container services across AWS EKS, Azure AKS, and Google GKE",
            "projectIds": [
                "application-modernization-app2container",
                "architecting-global-eks-resilience",
                "arm-graviton-workloads"
            ]
        },
        {
            "id": "ai-ml-quick-start",
            "name": "AI/ML Quick Start",
            "description": "Get started with cloud AI services - OpenAI, Bedrock, Vertex AI",
            "projectIds": [
                "ai-assistant-custom-functions-openai-functions",
                "ai-code-review-assistant-reasoning-functions",
                "automated-data-analysis-bedrock-agentcore",
                "automated-api-testing-gemini-functions"
            ]
        },
        {
            "id": "beginner-friendly-projects",
            "name": "Beginner-Friendly Projects (Under 30 Minutes)",
            "description": "Quick wins to build confidence and learn cloud basics",
            "projectIds": [
                "age-calculator-api-run-storage",
                "image-resizing-functions-storage",
                "base64-encoder-decoder-functions",
                "automated-event-creation-apps-script-calendar"
            ]
        },
        {
            "id": "gcp-serverless-mastery",
            "name": "GCP Serverless Mastery",
            "description": "Deep dive into Cloud Run, Cloud Functions, and Pub/Sub patterns",
            "projectIds": [
                "age-calculator-api-run-storage",
                "api-rate-limiting-analytics-run-firestore",
                "asynchronous-file-processing-cloud-tasks-storage",
                "background-task-processing-worker-pools-pubsub"
            ]
        },
        {
            "id": "azure-openai-exploration",
            "name": "Azure OpenAI Exploration",
            "description": "Build AI-powered applications with Azure OpenAI Service",
            "projectIds": [
                "ai-assistant-custom-functions-openai-functions",
                "ai-code-review-assistant-reasoning-functions",
                "ai-email-marketing-openai-logic-apps",
                "automated-audio-summarization-openai-functions",
                "automated-content-generation-prompt-flow-openai"
            ]
        },
        {
            "id": "cloud-security-essentials",
            "name": "Cloud Security Essentials",
            "description": "Implement security best practices across identity, encryption, and compliance",
            "projectIds": []
        },
        {
            "id": "data-engineering-pipeline",
            "name": "Data Engineering Pipeline",
            "description": "Build end-to-end data pipelines with storage, processing, and analytics",
            "projectIds": []
        }
    ]

    return paths


def main():
    parser = argparse.ArgumentParser(
        description='Initialize learning-paths.json with curated paths'
    )
    parser.add_argument(
        '--output', '-o',
        type=Path,
        default=Path('.publish/data/learning-paths.json'),
        help='Output file path (default: .publish/data/learning-paths.json)'
    )

    args = parser.parse_args()

    print("🚀 Learning Paths Initializer")
    print("=" * 40)

    # Create initial paths
    paths = create_initial_paths()

    # Ensure output directory exists
    args.output.parent.mkdir(parents=True, exist_ok=True)

    # Write to file
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(paths, f, indent=2, ensure_ascii=False)

    print(f"✅ Created {len(paths)} learning paths")
    print(f"📁 Output: {args.output}")
    print("\nLearning paths created:")
    for path in paths:
        project_count = len(path['projectIds'])
        print(f"   - {path['name']}: {project_count} projects")

    print("\n💡 Next steps:")
    print("   1. Review the generated learning-paths.json")
    print("   2. Add more project IDs to each path")
    print("   3. Parse README.md to get all project IDs")
    print("   4. Build the static site with: python .publish/scripts/build_site.py")


if __name__ == '__main__':
    main()
