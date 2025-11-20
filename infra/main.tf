provider "aws" {
  region = var.region
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # Дозволяє публічний IP для доступу
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
  name   = "allow_all_traffic"
  description = "Allows all inbound and outbound traffic"
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Вхідний трафік (включно з портом 8000)
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Coordinator (Залежність розірвана: більше не залежить від IP шардів)
resource "aws_instance" "coordinator" {
  ami           = "ami-00174bba02cf96021"  # Ubuntu 22.04 LTS
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]

  # Оновлений user_data: прибрані shard1_host та shard2_host з аргументів templatefile
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              # Встановлюємо Docker та Docker Compose
              apt-get install -y docker.io docker-compose
              usermod -aG docker ubuntu

              # Записуємо згенерований docker-compose.yml.j2 на інстанс
              cat > /home/ubuntu/docker-compose.yml << EOL
              ${templatefile("${path.module}/docker-compose.yml.j2", {
                coordinator_port = 8000
                # IP-адреси шардів тут видалено для уникнення кругової залежності
              })}
              EOL

              # Запускаємо сервіси
              docker-compose -f /home/ubuntu/docker-compose.yml up -d
              EOF

  tags = { Name = "coordinator" }
}

# Shard 1 (Залежить від Coordinator)
resource "aws_instance" "shard1" {
  ami           = "ami-00174bba02cf96021"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]

  # user_data залишається, оскільки залежність від coordinator.private_ip тепер одностороння
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              usermod -aG docker ubuntu

              # Запускаємо Shard 1 з необхідними змінними середовища
              docker run -d \
                -p 8000:8000 \
                -e SHARD_ID="shard1" \
                -e DYNAMODB_TABLE="ShardData-1" \
                -e COORDINATOR_URL="http://${aws_instance.coordinator.private_ip}:8000" \
                mateichukmykola/shard:latest
              EOF
  tags = { Name = "shard1" }
}

# Shard 2 (Залежить від Coordinator)
resource "aws_instance" "shard2" {
  ami           = "ami-00174bba02cf96021"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_all.id]

  # user_data залишається, оскільки залежність від coordinator.private_ip тепер одностороння
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              usermod -aG docker ubuntu

              # Запускаємо Shard 2 з необхідними змінними середовища
              docker run -d \
                -p 8000:8000 \
                -e SHARD_ID="shard2" \
                -e DYNAMODB_TABLE="ShardData-2" \
                -e COORDINATOR_URL="http://${aws_instance.coordinator.private_ip}:8000" \
                mateichukmykola/shard:latest
              EOF
  tags = { Name = "shard2" }
}

output "coordinator_public_ip" {
  description = "Public IP address of the Coordinator instance."
  value = aws_instance.coordinator.public_ip
}