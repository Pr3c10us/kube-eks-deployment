data "aws_region" "current" {}
data "aws_eks_cluster" "eks" {
  name = module.eks_cluster.cluster_id
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks_cluster.cluster_id
}



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
  #kubeconfig_aws_authenticator_additional_args = ["--region", data.aws_region.current.name]


    
    
  }
}
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
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
    value = var.unique_owner_id
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

output "cluster_id" {
  value = module.eks_cluster.cluster_id
}
