provider "aws" {
  region = "ca-central-1"
}

locals {
  all_tags = {
    createdBy   = "Terraform"
    Application = "Single AZ Application"
  }
}

resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.all_tags, tomap({ Name = "main" }))
}

resource "aws_subnet" "private-subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.az[0]
  tags              = merge(local.all_tags, tomap({ Name = "private-subnet" }))
}

resource "aws_subnet" "public-subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.az[0]
  tags              = merge(local.all_tags, tomap({ Name = "public-subnet" }))
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.all_tags, tomap({ Name = "gw" }))
}

resource "aws_eip" "ngw-ip" {
  domain   = "vpc"
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.ngw-ip.allocation_id
  subnet_id     = aws_subnet.public-subnet.id

  tags              = merge(local.all_tags, tomap({ Name = "ngw" }))

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}
resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw.id
  }

  tags = merge(local.all_tags, tomap({ Name = "private-route-table" }))
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = merge(local.all_tags, tomap({ Name = "public-route-table" }))
}

resource "aws_route_table_association" "private-route-asso" {
  subnet_id      = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.private-route-table.id

}

resource "aws_route_table_association" "public-route-asso" {
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.public-route-table.id
}

data "aws_ami" "amazon-linux" {
  most_recent = true
  # name_regex = "^ami-0748249a1ffd1b4d2"
  filter {
    name = "image-id"
    values = ["ami-0748249a1ffd1b4d2"]
  }
}

resource "aws_instance" "private-ec2" {
  ami                    = data.aws_ami.amazon-linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private-subnet.id
  vpc_security_group_ids = [aws_security_group.private-ec2-sg.id]
  user_data              = file("user-data.sh")
  tags                   = merge(local.all_tags, tomap({ Name = "private-ec2" }))
}

resource "aws_security_group" "private-ec2-sg" {
  name        = "private-ec2-sg"
  description = "Allow HTTP traffic"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.all_tags, tomap({ Name = "private-ec2-sg" }))
}

resource "aws_vpc_security_group_ingress_rule" "allow_http_ipv4" {
  security_group_id = aws_security_group.private-ec2-sg.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.private-ec2-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_key_pair" "key" {
  public_key = tls_private_key.rsa-2046-bastian.public_key_openssh
  key_name   = "AWSKey"
  #   provisioner "local-exec" {
  #     command = "echo ${tls_private_key.rsa-2046-bastian.private_key_openssh} > /tmp/private.pem"
  #   }
}

resource "aws_instance" "bastian" {
  ami                    = data.aws_ami.amazon-linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public-subnet.id
  vpc_security_group_ids = [aws_security_group.bastian-ec2-sg.id]
  tags                   = merge(local.all_tags, tomap({ Name = "bastian" }))
  key_name               = aws_key_pair.key.key_name
  provisioner "local-exec" {
    command = "chmod 600 ${local_file.private_key_pem.filename}"
  }

}

resource "aws_security_group" "bastian-ec2-sg" {
  name        = "bastian-ec2-sg"
  description = "Allow ssh traffic"
  vpc_id      = aws_vpc.main.id
  tags        = merge(local.all_tags, tomap({ Name = "bastian-ec2-sg" }))
}

resource "aws_vpc_security_group_ingress_rule" "bastian-ssh" {
  security_group_id = aws_security_group.bastian-ec2-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "bastian-all-traffic" {
  security_group_id = aws_security_group.bastian-ec2-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

# RSA key of size 4096 bits
resource "tls_private_key" "rsa-2046-bastian" {
  algorithm = "RSA"
  rsa_bits  = 2046
}

resource "aws_eip" "ec2-bastian-eip" {
  instance = aws_instance.bastian.id
  domain   = "vpc"
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.rsa-2046-bastian.private_key_pem
  filename = "AWSKey.pem"
}