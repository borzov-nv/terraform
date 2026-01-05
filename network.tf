# 1. The Core Network
resource "yandex_vpc_network" "main" {
  name = "production-network"
}

# 2. Subnets
# Public Subnet (Bastion, Zabbix, Kibana, Balancer)
resource "yandex_vpc_subnet" "public" {
  name           = "public-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

# Private Subnets (Webservers, Elasticsearch)
resource "yandex_vpc_subnet" "private-1" {
  name           = "private-subnet-1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.2.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

resource "yandex_vpc_subnet" "private-2" {
  name           = "private-subnet-2"
  zone           = "ru-central1-b" # Different zone for high availability
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.3.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

# 3. NAT Gateway (So private VMs can reach the internet for updates/apt-get)
resource "yandex_vpc_gateway" "nat_gw" {
  name = "main-nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private_rt" {
  name       = "private-route-table"
  network_id = yandex_vpc_network.main.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gw.id
  }
}

# 4. Security Groups

# --- BASTION SECURITY GROUP ---
resource "yandex_vpc_security_group" "bastion_sg" {
  name       = "bastion-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "SSH from my home IP"
    v4_cidr_blocks = [var.my_ip] # Replace with your actual IP
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- LOAD BALANCER SECURITY GROUP ---
resource "yandex_vpc_security_group" "alb_sg" {
  name       = "alb-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "Public HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol          = "ANY"
    description       = "Health checks"
    predefined_target = "loadbalancer_healthchecks"
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- WEBSERVER SECURITY GROUP ---
resource "yandex_vpc_security_group" "web_sg" {
  name       = "webserver-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol          = "TCP"
    description       = "Traffic from Load Balancer"
    security_group_id = yandex_vpc_security_group.alb_sg.id
    port              = 80
  }

  ingress {
    protocol          = "TCP"
    description       = "SSH from Bastion"
    security_group_id = yandex_vpc_security_group.bastion_sg.id
    port              = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Zabbix Agent monitoring"
    v4_cidr_blocks = ["10.0.1.0/24"] # Traffic from public subnet (where Zabbix lives)
    port           = 10050
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- MONITORING (ZABBIX & KIBANA) SECURITY GROUP ---
resource "yandex_vpc_security_group" "monitoring_sg" {
  name       = "monitoring-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "Zabbix Web UI"
    v4_cidr_blocks = ["0.0.0.0/0"] # Or your IP for better security
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Kibana Web UI"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5601
  }

  ingress {
    protocol          = "TCP"
    description       = "SSH from Bastion"
    security_group_id = yandex_vpc_security_group.bastion_sg.id
    port              = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ELASTICSEARCH SECURITY GROUP ---
resource "yandex_vpc_security_group" "elastic_sg" {
  name       = "elastic-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol          = "TCP"
    description       = "Logs from Webservers (Filebeat)"
    security_group_id = yandex_vpc_security_group.web_sg.id
    port              = 9200
  }

  ingress {
    protocol          = "TCP"
    description       = "Queries from Kibana"
    security_group_id = yandex_vpc_security_group.monitoring_sg.id
    port              = 9200
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}