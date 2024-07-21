provider "aws" {
  region     = "us-east-1"
  access_key = "xxxx"
  secret_key = "xxx"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Dev vpc"
  }
}

variable "public_cidr_subnets" {
  type        = list(string)
  description = "dev public"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "private"
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "azs" {
  type        = list(string)
  description = "azs"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

resource "aws_subnet" "public" {
  count             = length(var.public_cidr_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_cidr_subnets, count.index)
  availability_zone = element(var.azs, count.index)
  tags = {
    Name = "Public Subnet ${terraform.workspace} ${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)
  tags = {
    Name = "Private Subnet ${terraform.workspace} ${count.index + 1}"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
  depends_on = [
    aws_internet_gateway.example
  ]
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${terraform.workspace}"
  }
}

resource "aws_security_group" "security_group" {
  name        = "mqtt-sg"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${terraform.workspace} ${terraform.workspace}-Sg"
  }
}

resource "aws_key_pair" "mqtt_key" {
  key_name   = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD3F6tyPEFEzV0LX3X8BsXdMsQz1x2cEikKDEY0aIj41qgxMCP/iteneqXSIFZBp5vizPvaoIR3Um9xK7PGoW8giupGn+EPuxIA4cDM4vzOqOkiMPhz5XK0whEjkVzTo4+S0puvDZuwIsdiW9mxhJc7tgBNL0cYlWSYVkz4G/fslNfRPW5mYAM49f4fhtxPb5ok4Q2Lg9dPKVHO/Bgeu5woMc7RY0p1ej6D4CKFE6lymSDJpW0YHX/wqE9+cfEauh7xZcG0q9t2ta6F6fmX0agvpFyZo8aFbXeUBr7osSCJNgvavWbM/06niWrOvYX2xwWdhXmXSrbX8ZbabVohBK41 email@example.com"
}

resource "aws_instance" "ec2_instance" {
  count                       = length(var.public_cidr_subnets)
  ami                         = "ami-04a81a99f5ec58529"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  availability_zone           = element(var.azs, count.index)
  subnet_id                   = element(aws_subnet.public[*].id, count.index)
  security_groups             = [aws_security_group.security_group.id]
  key_name                    = aws_key_pair.mqtt_key.key_name
  tags = {
    Name = "${terraform.workspace}-${count.index + 1}"
  }
}

resource "aws_ebs_volume" "ebs_volume" {
  count             = length(var.azs)
  availability_zone = element(var.azs, count.index)
  size              = 4
  tags = {
    Name = "${terraform.workspace}-ebs${count.index + 1}"
  }
}

resource "aws_volume_attachment" "volume_attachment" {
  count       = length(var.azs)
  device_name = "/dev/sdh"
  volume_id   = element(aws_ebs_volume.ebs_volume[*].id, count.index)
  instance_id = element(aws_instance.ec2_instance[*].id, count.index)
}
