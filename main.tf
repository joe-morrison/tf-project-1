provider "aws" {
  region = "us-east-1"
}

#*********************************************************  IAM **************************************
resource "aws_iam_instance_profile" "ec2standard_profile" {
  name = "ec2standard_profile"
  role = aws_iam_role.ec2standard_role.name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2standard_role" {
  name               = "ec2standard_role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2ssm_policy" {
  role       = aws_iam_role.ec2standard_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#*********************************************************  VPC **************************************
resource "aws_vpc" "Main" {            # Creating VPC here
  cidr_block       = var.main_vpc_cidr # Defining the CIDR block use 10.0.0.0/24 for demo
  instance_tenancy = "default"
  tags = {
    Name        = "Test-Main-VPC"
    Environment = "DEV"
    OS          = "NA"
    Managed     = "IAC"
  }
}

resource "aws_internet_gateway" "IGW" { # Creating Internet Gateway
  vpc_id = aws_vpc.Main.id              # vpc_id will be generated after we create VPC
}

resource "aws_subnet" "publicsubnet1" { # Creating Public Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.public_subnet1 # CIDR block of public subnets
  availability_zone = "us-east-1a"
  tags = {
    Name        = "public-subnet-1"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_subnet" "publicsubnet2" { # Creating Public Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.public_subnet2 # CIDR block of public subnets
  availability_zone = "us-east-1b"
  tags = {
    Name        = "public-subnet-2"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_subnet" "privatesubnet1" { # Creating Private Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.private_subnet1 # CIDR block of private subnets
  availability_zone = "us-east-1a"
  tags = {
    Name        = "private-subnet-1"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_subnet" "privatesubnet2" { # Creating Private Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.private_subnet2 # CIDR block of private subnets
  availability_zone = "us-east-1b"
  tags = {
    Name        = "private-subnet-2"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_route_table" "PublicRT" { # Creating RT for Public Subnet
  vpc_id = aws_vpc.Main.id
  route {
    cidr_block = "0.0.0.0/0" # Traffic from Public Subnet reaches Internet via Internet Gateway
    gateway_id = aws_internet_gateway.IGW.id
  }
}

resource "aws_route_table" "PrivateRT" { # Creating RT for Private Subnet
  vpc_id = aws_vpc.Main.id
  route {
    cidr_block     = "0.0.0.0/0" # Traffic from Private Subnet reaches Internet via NAT Gateway
    nat_gateway_id = aws_nat_gateway.NATgw.id
  }
}

resource "aws_route_table_association" "PublicRTassociation1" {
  subnet_id      = aws_subnet.publicsubnet1.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "PublicRTassociation2" {
  subnet_id      = aws_subnet.publicsubnet2.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "PrivateRTassociation1" {
  subnet_id      = aws_subnet.privatesubnet1.id
  route_table_id = aws_route_table.PrivateRT.id
}

resource "aws_route_table_association" "PrivateRTassociation2" {
  subnet_id      = aws_subnet.privatesubnet2.id
  route_table_id = aws_route_table.PrivateRT.id
}
resource "aws_eip" "nateIP" {
  vpc = true
}

resource "aws_nat_gateway" "NATgw" {
  allocation_id = aws_eip.nateIP.id
  subnet_id     = aws_subnet.publicsubnet1.id
}
#*********************************************************  EC2 **************************************
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "myKey" # Create a "myKey" to AWS!!
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.kp.key_name}.pem"
  content  = tls_private_key.pk.private_key_pem
}

resource "aws_instance" "bastion" {
  ami                         = "ami-053b0d53c279acc90"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.publicsubnet1.id
  key_name                    = aws_key_pair.kp.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2standard_profile.name

  user_data = <<-EOF
    #!/bin/bash
 
    sudo apt update -y

    sudo apt install git

    sudo apt install software-properties-common -y
    sudo add-apt-repository --yes --update ppa:ansible/ansible -y
    sudo apt install ansible -y

    sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
    gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt-get install terraform

    sudo mkdir /repos;sudo cd /repos;sudo git clone https://github.com/joe-morrison/tf-project-1.git
    
    EOF

  user_data_replace_on_change = true

  provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is ready'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(local_file.ssh_key.filename)
      host        = aws_instance.bastion.public_ip
    }
  }
  provisioner "local-exec" {
    command  = "echo ${aws_instance.bastion.public_ip} > ./bastion;ansible-playbook -i ${aws_instance.bastion.public_ip}, --private-key ${local_file.ssh_key.filename} bastion.yaml"
  }

  tags = {  
    Name        = "Bastion"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}


#********************************************************* SG **************************************
resource "aws_security_group" "bastion_sg" {
  name   = "bastion_sg"
  vpc_id = aws_vpc.Main.id
  ingress {
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
}
