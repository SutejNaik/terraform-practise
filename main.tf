terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# ============================================================
# DATA
# ============================================================

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ============================================================
# LOCALS
# ============================================================

locals {
  project = "terraform-practise"

  common_tags = {
    Project   = local.project
    ManagedBy = "Terraform"
  }

  github_owner    = "SutejNaik"
  github_owner_id = "181818616"
  github_repo     = "terraform-practise"
  github_repo_id  = "1381486313"
  github_branch   = "main"
}

# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-vpc"
  })
}

# ============================================================
# PUBLIC SUBNET
# ============================================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project}-public-subnet"
  })
}

# ============================================================
# INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project}-igw"
  })
}

# ============================================================
# ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# SECURITY GROUP
# ============================================================

resource "aws_security_group" "app" {
  name        = "${local.project}-sg"
  description = "Security group for Terraform practice application"
  vpc_id      = aws_vpc.main.id

  # Flask application
  ingress {
    description = "Flask application"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound internet access for Docker/ECR/SSM
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-sg"
  })
}

# ============================================================
# ECR
# ============================================================

resource "aws_ecr_repository" "app" {
  name                 = local.project
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.project}-ecr"
  })
}

# ============================================================
# EC2 IAM ROLE
# ============================================================

resource "aws_iam_role" "ec2" {
  name = "${local.project}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.project}-ec2-role"
  })
}

# SSM access
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ============================================================
# EC2 ECR PULL POLICY
# ============================================================

resource "aws_iam_role_policy" "ec2_ecr" {
  name = "${local.project}-ec2-ecr"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]

        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}

# ============================================================
# EC2 INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.project}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = merge(local.common_tags, {
    Name = "${local.project}-ec2-profile"
  })
}

# ============================================================
# EC2
# ============================================================

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.amazon_linux.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile = aws_iam_instance_profile.ec2.name

  key_name = "devops-key"

  user_data = <<-EOF
    #!/bin/bash

    # Install Docker
    dnf install -y docker

    # Start Docker
    systemctl enable docker
    systemctl start docker

    # Allow ec2-user to use Docker
    usermod -aG docker ec2-user

    # Ensure SSM Agent is running
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  tags = merge(local.common_tags, {
    Name = "${local.project}-ec2"
  })

  depends_on = [
    aws_iam_role_policy_attachment.ec2_ssm,
    aws_iam_role_policy.ec2_ecr
  ]
}

# ============================================================
# GITHUB OIDC PROVIDER
# ============================================================

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = merge(local.common_tags, {
    Name = "${local.project}-github-oidc"
  })
}

# ============================================================
# GITHUB ACTIONS IAM ROLE
# ============================================================

resource "aws_iam_role" "github_actions" {
  name = "${local.project}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"

            "token.actions.githubusercontent.com:sub" = "repo:${local.github_owner}@${local.github_owner_id}/${local.github_repo}@${local.github_repo_id}:ref:refs/heads/${local.github_branch}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.project}-github-actions-role"
  })
}

# ============================================================
# GITHUB ACTIONS ECR + SSM PERMISSIONS
# ============================================================

resource "aws_iam_role_policy" "github_actions" {
  name = "${local.project}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # ECR login
      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },

      # Push Docker image
      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]

        Resource = aws_ecr_repository.app.arn
      },

      # Deploy to EC2 through SSM
      {
        Effect = "Allow"

        Action = [
          "ssm:SendCommand"
        ]

        Resource = [
          aws_instance.app.arn,
          "arn:aws:ssm:ap-south-1::document/AWS-RunShellScript"
        ]
      },

      # Check deployment status
      {
        Effect = "Allow"

        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommands"
        ]

        Resource = "*"
      }
    ]
  })
}

# ============================================================
# OUTPUTS
# ============================================================

output "vpc_id" {
  value = aws_vpc.main.id
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "ec2_public_ip" {
  value = aws_instance.app.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
