data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_vpc" "main" {
  id = local.vpc_id
}

data "aws_subnet" "subnet" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn"]
  }
}

data "aws_subnet" "private_1" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn"]
  }
}

data "aws_subnet" "private_2" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn-2"]
  }
}

data "aws_subnet" "public_1" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn-pub-1"]
  }
}

data "aws_subnet" "public_2" {
  filter {
    name   = "tag:Name"
    values = ["esgi-sn-pub-2"]
  }
}

data "aws_security_group" "web" {
  filter {
    name   = "group-name"
    values = ["esgi-web-sg"]
  }
  vpc_id = local.vpc_id
}

data "aws_security_group" "app" {
  filter {
    name   = "group-name"
    values = ["esgi-app-sg"]
  }
  vpc_id = local.vpc_id
}

data "aws_security_group" "db" {
  filter {
    name   = "group-name"
    values = ["esgi-db-sg"]
  }
  vpc_id = local.vpc_id
}

data "aws_key_pair" "esgi" {
  key_name = "esgi-key-pair"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
