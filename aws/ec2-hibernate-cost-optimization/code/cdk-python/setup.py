"""
Setup configuration for EC2 Hibernation Cost Optimization CDK application.
"""

import os
from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="ec2-hibernation-cost-optimization",
    version="1.0.0",
    description="CDK application for EC2 hibernation cost optimization with CloudWatch monitoring",
    long_description=open("README.md", "r", encoding="utf-8").read() if os.path.exists("README.md") else "",
    long_description_content_type="text/markdown",
    author="AWS Cloud Recipes",
    author_email="admin@example.com",
    url="https://github.com/aws-samples/cloud-recipes",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.900",
            "isort>=5.0.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "ec2-hibernation-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "ec2",
        "hibernation",
        "cost-optimization",
        "cloudwatch",
        "sns",
        "infrastructure",
        "devops",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Tracker": "https://github.com/aws-samples/cloud-recipes/issues",
    },
)