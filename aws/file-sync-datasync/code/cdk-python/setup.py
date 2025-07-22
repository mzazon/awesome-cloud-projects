"""
Setup configuration for AWS CDK Python application
File System Synchronization with DataSync and EFS
"""

from setuptools import setup, find_packages

# Read the requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [
        line.strip()
        for line in f
        if line.strip() and not line.startswith("#")
    ]

# Read the README for long description
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for implementing file system synchronization
    between S3 and Amazon EFS using AWS DataSync service.
    """

setup(
    name="file-system-synchronization-datasync-efs",
    version="1.0.0",
    author="AWS Recipe Generator",
    author_email="aws-recipes@example.com",
    description="AWS CDK Python app for DataSync and EFS file synchronization",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/recipes",
    packages=find_packages(exclude=["tests*", "docs*"]),
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
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-datasync-efs=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "datasync",
        "efs",
        "file-synchronization",
        "storage",
        "infrastructure-as-code",
        "cloud",
        "automation",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/recipes",
        "AWS DataSync": "https://aws.amazon.com/datasync/",
        "Amazon EFS": "https://aws.amazon.com/efs/",
    },
    include_package_data=True,
    zip_safe=False,
)