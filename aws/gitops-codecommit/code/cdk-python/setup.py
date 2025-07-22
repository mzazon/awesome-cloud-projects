"""
Setup configuration for GitOps Workflows CDK Python Application.

This setup.py file configures the Python package for the CDK application
that implements GitOps workflows with AWS CodeCommit and CodeBuild.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for GitOps Workflows with AWS CodeCommit and CodeBuild"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            requirements = []
            for line in req_file:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib==2.170.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.28.0",
            "botocore>=1.31.0",
        ]

setup(
    name="gitops-workflows-cdk",
    version="1.0.0",
    description="CDK Python application for GitOps Workflows with AWS CodeCommit and CodeBuild",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="gitops-team@example.com",
    url="https://github.com/example/gitops-workflows-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
            "types-PyYAML>=6.0.0",
            "types-requests>=2.28.0",
            "boto3-stubs[essential]>=1.28.0",
        ],
        "docs": [
            "pdoc>=12.0.0",
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "gitops-cdk=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/example/gitops-workflows-cdk/issues",
        "Source": "https://github.com/example/gitops-workflows-cdk",
        "Documentation": "https://github.com/example/gitops-workflows-cdk/blob/main/README.md",
    },
    keywords=[
        "aws",
        "cdk",
        "gitops",
        "codecommit",
        "codebuild",
        "ecs",
        "docker",
        "containers",
        "ci-cd",
        "devops",
        "infrastructure-as-code",
        "cloud-formation",
        "automation",
    ],
    include_package_data=True,
    zip_safe=False,
    license="MIT",
    platforms="any",
)