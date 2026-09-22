# Terraform Practice — DevOps CI/CD Project

A small Flask application deployed using a production-style DevOps workflow with **Docker, Terraform, AWS, GitHub Actions, Trivy, Amazon ECR, EC2, and GitHub OIDC**.

The application itself is intentionally simple. The main focus of this project is the **DevOps infrastructure and deployment pipeline**.

---

## Architecture

```text
Developer
    │
    │ git push / Pull Request
    ▼
 GitHub
    │
    ▼
GitHub Actions
    │
    ├── Test application
    ├── Build Docker image
    ├── Trivy security scan
    ├── Authenticate to AWS using OIDC
    │
    ▼
Amazon ECR
    │
    │ Docker image
    ▼
EC2 Instance
    │
    ▼
Docker Container
    │
    ▼
Flask Application
    │
    ▼
Browser
```

---

## Technologies Used

| Technology          | Purpose                            |
| ------------------- | ---------------------------------- |
| Python / Flask      | Simple application                 |
| Docker              | Containerization                   |
| Git                 | Version control                    |
| GitHub              | Source code repository             |
| GitHub Actions      | CI/CD                              |
| Trivy               | Container security scanning        |
| Terraform           | Infrastructure as Code             |
| AWS VPC             | Network infrastructure             |
| AWS EC2             | Application server                 |
| Amazon ECR          | Docker image registry              |
| AWS IAM             | Permissions and access control     |
| GitHub OIDC         | Secure GitHub → AWS authentication |
| AWS Systems Manager | EC2 deployment commands            |

---

## Project Structure

```text
terraform-practise/
│
├── .github/
│   └── workflows/
│       └── deploy.yml
│
├── app.py
├── requirements.txt
├── Dockerfile
├── .dockerignore
├── .gitignore
├── main.tf
├── terraform.tfvars
└── README.md
```

---

## Application

The application is a minimal Flask server.

```python
from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "Terraform Practice Application is running!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

The application runs on:

```text
Port 5000
```

---

## Docker

The Flask application is packaged into a Docker image.

The Dockerfile:

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
```

The container exposes port `5000`.

---

## Terraform Infrastructure

Terraform provisions the AWS infrastructure required for the application.

### Networking

Terraform creates:

* VPC
* Public subnet
* Internet Gateway
* Route table
* Public route
* Security group

The EC2 instance is placed inside the public subnet.

### Security Group

The security group allows:

```text
TCP 5000 → Application
Outbound traffic → Allowed
```

SSH access is not required for the deployment pipeline because AWS Systems Manager is used for deployment.

---

## Amazon ECR

Terraform creates an Amazon ECR repository for Docker images.

The GitHub Actions pipeline builds the Docker image and pushes it to ECR.

Images are tagged using the GitHub commit SHA.

Example:

```text
terraform-practise:<commit-sha>
```

Using the commit SHA provides an identifiable version for every deployment.

---

## EC2

Terraform creates the EC2 application server.

The EC2 instance:

* Runs Amazon Linux
* Runs Docker
* Has access to Amazon ECR
* Has AWS Systems Manager access
* Runs the application container

---

## IAM

Terraform creates the required IAM resources.

### EC2 IAM Role

The EC2 role provides permissions for:

* AWS Systems Manager
* Pulling Docker images from ECR

### GitHub Actions IAM Role

GitHub Actions receives only the AWS permissions required by the pipeline.

The role is assumed using **GitHub OIDC** instead of storing long-lived AWS access keys inside GitHub.

```text
GitHub Actions
      │
      │ OIDC token
      ▼
AWS IAM
      │
      ▼
GitHub Actions IAM Role
```

This avoids storing an AWS access key and secret key in GitHub.

---

## CI/CD Pipeline

The workflow is located at:

```text
.github/workflows/deploy.yml
```

### CI

When code is pushed or a pull request is created, GitHub Actions:

1. Checks out the repository
2. Installs Python dependencies
3. Tests the Python application
4. Builds the Docker image
5. Runs a Trivy security scan

### CD

When changes are pushed to the `main` branch:

1. GitHub Actions authenticates to AWS using OIDC
2. Logs in to Amazon ECR
3. Builds the Docker image
4. Tags the image with the Git commit SHA
5. Pushes the image to ECR
6. Sends a deployment command to EC2 using AWS Systems Manager
7. EC2 pulls the new image
8. The previous container is stopped and removed
9. A new container is started

---

## Deployment Flow

```text
git push
    │
    ▼
GitHub Actions
    │
    ├── Python test
    │
    ├── Docker build
    │
    ├── Trivy scan
    │
    ├── OIDC authentication
    │
    ▼
AWS IAM
    │
    ▼
Amazon ECR
    │
    │ Push image
    ▼
AWS Systems Manager
    │
    ▼
EC2
    │
    ├── Pull image
    ├── Stop old container
    ├── Remove old container
    └── Start new container
    │
    ▼
Flask Application
```

---

## Running Locally

### Run the application directly

```bash
python3 app.py
```

Then open:

```text
http://localhost:5000
```

### Run with Docker

Build the image:

```bash
docker build -t terraform-practise:test .
```

Run the container:

```bash
docker run --rm -p 5000:5000 terraform-practise:test
```

Then open:

```text
http://localhost:5000
```

---

## Terraform Commands

Initialize Terraform:

```bash
terraform init
```

Validate the configuration:

```bash
terraform validate
```

Review the infrastructure plan:

```bash
terraform plan
```

Apply the infrastructure:

```bash
terraform apply
```

Display Terraform outputs:

```bash
terraform output
```

---

## AWS Deployment

After infrastructure is created, GitHub Actions handles application deployment automatically.

The developer only needs to push changes to GitHub.

```text
Developer
    ↓
git push
    ↓
GitHub Actions
    ↓
Docker image
    ↓
ECR
    ↓
EC2
    ↓
Application
```

---

## Security

This project demonstrates several basic DevSecOps practices:

* GitHub OIDC instead of long-lived AWS credentials
* IAM roles instead of hard-coded AWS credentials
* ECR image scanning
* Trivy container vulnerability scanning
* Separate IAM permissions for EC2 and GitHub Actions
* Terraform-managed infrastructure

---

## What This Project Demonstrates

This project demonstrates an end-to-end DevOps workflow:

* Infrastructure as Code
* Cloud infrastructure
* Linux-based application server
* Docker containerization
* Git and GitHub
* CI/CD automation
* Container security scanning
* AWS IAM
* GitHub OIDC
* Amazon ECR
* EC2 deployment
* AWS Systems Manager

The application is intentionally small so that the majority of the project focuses on the **DevOps lifecycle** rather than application development.

---

## Future Improvements

Possible future additions include:

* Terraform remote state with S3
* Terraform state locking
* Ansible configuration management
* Kubernetes deployment
* Monitoring and logging
* HTTPS with a domain
* Load balancing
* Blue/green or rolling deployments
* More advanced security scanning
* Production-style observability
