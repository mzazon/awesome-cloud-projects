"""
Setup configuration for GitOps Workflows CDK Python Application

This setup.py file configures the Python package for the GitOps Workflows
CDK application, including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "GitOps Workflows with EKS, ArgoCD, and CodeCommit - CDK Python Implementation"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

setup(
    name="gitops-workflows-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="developer@example.com",
    description="CDK Python application for GitOps Workflows with EKS, ArgoCD, and CodeCommit",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/gitops-workflows-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "gitops-deploy=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "gitops",
        "eks",
        "kubernetes",
        "argocd",
        "codecommit",
        "devops",
        "infrastructure",
        "cloud"
    ],
    
    # Include additional files
    include_package_data=True,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/gitops-workflows-cdk/issues",
        "Source": "https://github.com/your-org/gitops-workflows-cdk",
        "Documentation": "https://your-org.github.io/gitops-workflows-cdk/",
    },
    
    # License
    license="MIT",
    
    # Minimum supported CDK version
    # This ensures compatibility with the CDK constructs used
    zip_safe=False,
)