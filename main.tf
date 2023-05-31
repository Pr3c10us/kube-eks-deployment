data "aws_region" "current" {}

provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${data.aws_region.current.name}a", "${data.aws_region.current.name}b", "${data.aws_region.current.name}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "my-eks-cluster"
  cluster_version = "1.24"

  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.private_subnets
}

resource "aws_launch_template" "worker_nodes" {
  name                   = "my-eks-worker-nodes"
  image_id               = "ami-0c94855ba95c71c99"  # Replace with the desired worker node AMI ID
  instance_type          = "t3.medium"  # Replace with the desired instance type
  key_name               = "my-keypair"  # Replace with the desired SSH key name
  security_group_names     = [aws_security_group.worker_nodes.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.worker_nodes.name
  }
  user_data              = <<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${module.eks_cluster.cluster_id} >> /etc/ecs/ecs.config
    EOF
}

resource "aws_iam_instance_profile" "worker_nodes" {
  name = "my-eks-worker-nodes"
  role = aws_iam_role.worker_nodes.id
}

resource "aws_iam_role" "worker_nodes" {
  name = "my-eks-worker-nodes"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_security_group" "worker_nodes" {
  name        = "my-eks-worker-nodes"
  description = "Security group for EKS worker nodes"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.cluster_name]
    }
  }
}

resource "kubernetes_namespace" "dev" {
  metadata {
    name = "dev"
  }
}

resource "kubernetes_namespace" "prod" {
  metadata {
    name = "prod"
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = kubernetes_namespace.dev.metadata.0.name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  version    = "6.20.3"

  set {
    name  = "txtOwnerId"
    value = "YOUR_UNIQUE_OWNER_ID"  # Update with your unique owner ID
  }

  set {
    name  = "domainFilters"
    value = "example.com"  # Update with your desired domain
  }

  set {
    name  = "aws.zoneType"
    value = "public"
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  namespace  = kubernetes_namespace.dev.metadata.0.name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "nginx-ingress"
  version    = "9.1.10"

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }
}

# resource "kubernetes_secret" "app_secret" {
#   metadata {
#     name      = "app-secret"
#     namespace = kubernetes_namespace.dev.metadata.0.name
#   }

#   string_data = {
#     "sensitive_data" = "Oswald"
#   }

#   type = "Opaque"
# }

# resource "helm_release" "python_api_dev" {
#   name       = "python-api-dev"
#   namespace  = kubernetes_namespace.dev.metadata.0.name
#   repository = "https://charts.example.com/my-charts"
#   chart      = "python-api"
#   version    = "1.0.0"

#   set {
#     name  = "extraDays[0].name"
#     value = "Oswald"
#   }

#   set {
#     name  = "extraDays[0].id"
#     value = "8"
#   }

#   set {
#     name      = "extraDays[0].sensitive_data"
#     valueFrom = kubernetes_secret.app_secret.metadata[0].name
#   }

#   set {
#     name  = "ingress.host"
#     value = "dev.foo"  # Update with the desired host
#   }
# }

# resource "helm_release" "python_api_prod" {
#   name       = "python-api-prod"
#   namespace  = kubernetes_namespace.prod.metadata.0.name
#   repository = "https://charts.example.com/my-charts"
#   chart      = "python-api"
#   version    = "1.0.0"

#   set {
#     name  = "extraDays[0].name"
#     value = "Oswald"
#   }

#   set {
#     name  = "extraDays[0].id"
#     value = "9"
#   }

#   set {
#     name      = "extraDays[0].sensitive_data"
#     valueFrom = kubernetes_secret.app_secret.metadata[0].name
#   }

#   set {
#     name  = "ingress.host"
#     value = "prod.foo"  # Update with the desired host
#   }
# }

output "cluster_id" {
  value = module.eks_cluster.cluster_id
}
output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks_cluster.cluster_certificate_authority_data
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = module.eks_cluster.cluster_endpoint
}
