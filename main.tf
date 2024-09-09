resource "aws_instance" "project1-front" {
  ami           = "ami-066784287e358dad1"
  instance_type = "t2.micro"
  key_name = aws_key_pair.project1-key.key_name
  vpc_security_group_ids = [aws_security_group.pub_sg.id]
  subnet_id = aws_subnet.pub_sbnet.id
  associate_public_ip_address = true

  tags = {
    Name = "project1-front"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              # Install Git
              yum install git -y
              # Install Jenkins
              wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              dnf install java-17-amazon-corretto -y
              yum install jenkins -y
              systemctl start jenkins
              systemctl enable jenkins
              EOF
}

resource "aws_instance" "project1-back" {
  ami           = "ami-066784287e358dad1"
  instance_type = "t2.micro"
  key_name = aws_key_pair.project1-key.key_name
  vpc_security_group_ids = [aws_security_group.prv_sg.id]
  subnet_id = aws_subnet.prv_sbnet.id
  associate_public_ip_address = false

  tags = {
    Name = "project1-back"
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              # Install Docker
              yum install docker -y
              systemctl start docker
              systemctl enable docker
              EOF
}

resource "aws_security_group" "pub_sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "project1-pub-sg"
  description = "Security group for public subnet"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
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
    Name = "project1-pub-sg"
  }
}

resource "aws_security_group" "prv_sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "project1-prv-sg"
  description = "Security group for private subnet"

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.pub_sg.id]
  }

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.pub_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "project1-prv-sg"
  }
}


resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "project1-vpc"
  }
}

resource "aws_subnet" "pub_sbnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "project1-pub_sbnet"
  }
}

resource "aws_subnet" "prv_sbnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "project1-prv_sbnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "project1-igw"
  }
}

resource "aws_eip" "eip" {
  tags = {
    Name = "project1-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.pub_sbnet.id

  tags = {
    Name = "project1-nat"
  }
}

resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "project1-pub-rt"
  }
}

resource "aws_route_table" "prv_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "project1-prv-rt"
  }
}

resource "aws_route_table_association" "pub_sbnet" {
  subnet_id      = aws_subnet.pub_sbnet.id
  route_table_id = aws_route_table.pub_rt.id
}

resource "aws_route_table_association" "prv_sbnet" {
  subnet_id      = aws_subnet.prv_sbnet.id
  route_table_id = aws_route_table.prv_rt.id
}

# Generate SSH key pair

resource "tls_private_key" "project1-key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "project1-key" {
  key_name   = "project1-key"
  public_key = tls_private_key.project1-key.public_key_openssh
}

resource "local_file" "project1-key" {
  content  = tls_private_key.project1-key.private_key_pem
  filename = pathexpand("~/.ssh/project1-key.pem")
  file_permission = 0400
}

# Generate ansible hosts file

resource "local_file" "ansible_hosts" {
  content = templatefile("${path.module}/ansible_hosts.tftpl",
    {
      pub_ip_front = aws_instance.project1-front.public_ip,
      prv_ip_back = aws_instance.project1-back.private_ip,
      filename = local_file.project1-key.filename,
    }
  )
  filename = "/etc/ansible/hosts"
}

# Generate ssh config file

resource "local_file" "ssh_config" {
  content = templatefile("${path.module}/ssh_config.tftpl",
    {
      pub_ip_front = aws_instance.project1-front.public_ip,
      prv_ip_back = aws_instance.project1-back.private_ip,
      filename = local_file.project1-key.filename,
    }
  )
  filename = pathexpand("~/.ssh/config")
}