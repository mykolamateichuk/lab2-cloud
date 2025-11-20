terraform {
  required_version = ">= 1.0"
  backend "s3" {
    bucket         = "horse-zombie-warden-pixel-state-bucker-23984"
    key            = "sharded-kv/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"  # For state locking
  }
}

provider "aws" {
  region = var.region
}

# Generate SSH key pair
resource "tls_private_key" "deploy" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "deploy" {
  key_name   = "sharded-kv-key"
  public_key = tls_private_key.deploy.public_key_openssh
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_security_group" "allow_all" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Coordinator
resource "aws_instance" "coordinator" {
  ami           = "ami-0ecb62995f68bb549"  # Ubuntu 22.04 LTS in your region
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  key_name               = aws_key_pair.deploy.key_name
  user_data = base64encode(<<-EOF
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              sleep 15
              
              # Pull the image first
              docker pull mateichukmykola/coordinator:latest
              
              # Run coordinator with properly quoted environment variable
              docker run -d -p 8000:8000 \
                -e SHARD_URLS="http://${aws_instance.shard1.private_ip}:8000,http://${aws_instance.shard2.private_ip}:8000" \
                --name coordinator_app \
                mateichukmykola/coordinator:latest
              EOF
  )
  tags = { Name = "coordinator" }
}

# Shards
resource "aws_instance" "shard1" {
  ami           = "ami-0ecb62995f68bb549"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  key_name               = aws_key_pair.deploy.key_name
  user_data = base64encode(<<-EOF
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              sleep 15
              
              # Pull image first
              docker pull mateichukmykola/shard:latest
              
              docker run -d -p 8000:8000 --name shard1_app mateichukmykola/shard:latest
              EOF
  )
  tags = { Name = "shard1" }
}

resource "aws_instance" "shard2" {
  ami           = "ami-0ecb62995f68bb549"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  key_name               = aws_key_pair.deploy.key_name
  user_data = base64encode(<<-EOF
              #!/bin/bash
              export DEBIAN_FRONTEND=noninteractive
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              sleep 15
              
              # Pull image first
              docker pull mateichukmykola/shard:latest
              
              docker run -d -p 8000:8000 --name shard2_app mateichukmykola/shard:latest
              EOF
  )
  tags = { Name = "shard2" }
}

output "coordinator_public_ip" {
  value = aws_instance.coordinator.public_ip
}

output "ssh_private_key" {
  value     = tls_private_key.deploy.private_key_pem
  sensitive = true
}