"""
Setup configuration for EKS Auto-Scaling CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys an Amazon EKS cluster with comprehensive auto-scaling capabilities.
"""

from setuptools import setup, find_packages

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for EKS Auto-Scaling with HPA and Cluster Autoscaler"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="eks-autoscaling-cdk",
    version="1.0.0",
    description="CDK Python application for EKS Auto-Scaling with HPA and Cluster Autoscaler",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/eks-autoscaling-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "eks-autoscaling-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "autoscaling",
        "hpa",
        "cluster-autoscaler",
        "infrastructure-as-code",
        "cloud-formation",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/eks-autoscaling-cdk/issues",
        "Source": "https://github.com/aws-samples/eks-autoscaling-cdk",
        "Documentation": "https://docs.aws.amazon.com/eks/latest/userguide/",
    },
    include_package_data=True,
    package_data={
        "": ["*.yaml", "*.yml", "*.json", "*.md"],
    },
    zip_safe=False,
    platforms=["any"],
)