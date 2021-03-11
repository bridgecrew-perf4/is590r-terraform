provider "aws" {
    region = "us-east-1"
    access_key = "AKIAU7KIJ25UTKOM65K6"
    secret_key = "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"
}

# 1.    VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block       = "10.0.0.0/16"
  tags = {
    Name = "prod"
  }
}

# 2.    Internet Gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.prod_vpc.id
    tags = {
        Name = "prod"
    }
}

# 3.    Custom Route Table (might be optional)
resource "aws_route_table" "prod_route_table" {
    vpc_id = aws_vpc.prod_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.gw.id
    }
    route {
        ipv6_cidr_block = "::0/0"
        gateway_id = aws_internet_gateway.gw.id
    }
    tags = {
        Name = "prod"
    }
}

### Associate Subnet with Route Table
resource "aws_route_table_association" "a" {
    subnet_id = aws_subnet.subnet_1.id
    route_table_id = aws_route_table.prod_route_table.id
}

# 4.    Private Subnet for Staging ENV
resource "aws_subnet" "subnet_1" {
    vpc_id     = aws_vpc.prod_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1a"
    tags = {
        Name = "prod_subnet"
    }
}

# 5.    Public Subnet for Prod ENV
############# TODO ###############


# 6.    Security Group for Staging
############# TODO ###############

# 7.    Security Group or Prod
resource "aws_security_group" "allow_web" {
    name        = "allow_web"
    description = "Allow web traffic"
    vpc_id      = aws_vpc.prod_vpc.id

    ingress {
        description = "HTTPS from VPC"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "HTTP from VPC"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "SSH from VPC"
        from_port   = 22
        to_port     = 22
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
        Name = "allow_web"
    }
}

# 8.    Network Interface
resource "aws_network_interface" "web_server_nic" {
    subnet_id       = aws_subnet.subnet_1.id
    private_ips     = ["10.0.1.50"]
    security_groups = [aws_security_group.allow_web.id]
}

# 9.    Elastic IP Address
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

# 10.   Ubuntu Server with Apache for the Front-end
resource "aws_instance" "ec2" {
    ami           = "ami-02fe94dee086c0c37"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "russianhackers" #1:33:42
    network_interface {
        device_index          = 0
        network_interface_id  = aws_network_interface.web_server_nic.id
    }

    user_data = <<-EOF
                #! /bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c echo 'echo your very first web server > /var/www/html/index.html'
                EOF
    tags = {
        Name = "web_server"
    }
}

# 11.   ECS (container service)
############# TODO ###############

# 12.   RDS
############# TODO ###############

#   12.1 Staging DB
############# TODO ###############

#   12.2 Prod DB
############# TODO ###############