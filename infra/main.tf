provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
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
  ami           = "ami-00174bba02cf96021"  # Ubuntu 22.04 LTS in your region
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  user_data = templatefile("${path.module}/docker-compose.yml.j2", {
    coordinator_port = 8000,
    shard1_host = aws_instance.shard1.private_ip,
    shard2_host = aws_instance.shard2.private_ip
  })
  tags = { Name = "coordinator" }
}

# Shards
resource "aws_instance" "shard1" {
  ami           = "ami-00174bba02cf96021"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              usermod -aG docker ubuntu
              docker run -d -p 8000:8000 your_docker_hub/shard:latest
              EOF
  tags = { Name = "shard1" }
}

resource "aws_instance" "shard2" {
  ami           = "ami-00174bba02cf96021"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              usermod -aG docker ubuntu
              docker run -d -p 8000:8000 your_docker_hub/shard:latest
              EOF
  tags = { Name = "shard2" }
}

output "coordinator_public_ip" {
  value = aws_instance.coordinator.public_ip
}