"""
Setup configuration for the Multi-Agent AI Workflows CDK Python application.
"""

from setuptools import find_packages, setup

with open("README.md", encoding="utf-8") as fp:
    long_description = fp.read()

setup(
    name="multi-agent-ai-workflows-bedrock-agentcore",
    version="1.0.0",
    description="AWS CDK Python application for multi-agent AI workflows using Amazon Bedrock AgentCore",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    packages=find_packages(),
    install_requires=[
        "aws-cdk-lib==2.172.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "botocore>=1.35.0",
    ],
    extras_require={
        "dev": [
            "pytest>=6.0.0",
            "pytest-cov>=2.10.0",
            "mypy>=0.910",
            "black>=21.0.0",
            "flake8>=3.8.0",
        ]
    },
    project_urls={
        "Repository": "https://github.com/aws-recipes/multi-agent-ai-workflows",
        "Documentation": "https://docs.aws.amazon.com/bedrock/latest/userguide/",
    },
)