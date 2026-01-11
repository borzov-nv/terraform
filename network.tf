# СЕТЬ
resource "yandex_vpc_network" "main" {
  name = "production-network"
}

# ПУБЛИЧНАЯ ПОДСЕТЬ
resource "yandex_vpc_subnet" "public" {
  name           = "public-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

# ПРИВАТНАЯ ПОДСЕТЬ 1
resource "yandex_vpc_subnet" "private-1" {
  name           = "private-subnet-1"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.2.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

# ПРИВАТНАЯ ПОДСЕТЬ 2 (В ДРУГОЙ ЗОНЕ)
resource "yandex_vpc_subnet" "private-2" {
  name           = "private-subnet-2"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.0.3.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

# NAT
resource "yandex_vpc_gateway" "nat_gw" {
  name = "main-nat-gateway"
  shared_egress_gateway {}
}

# ТАБЛИЦА МАРШРУТИЗАЦИИ
resource "yandex_vpc_route_table" "private_rt" {
  name       = "private-route-table"
  network_id = yandex_vpc_network.main.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gw.id
  }
}

# БАЗОВАЯ ГРУППА БЕЗОПАСНОСТИ
resource "yandex_vpc_security_group" "basic_sg" {
  name       = "basic-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "Allow SSH from anywhere internal"
    v4_cidr_blocks = ["10.0.0.0/8"]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["213.180.193.0/24"]
    port           = 80
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["213.180.204.0/24"]
    port           = 80
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["84.47.172.0/24"]
    port           = 443
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["84.201.181.0/24"]
    port           = 443
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["178.176.128.0/24"]
    port           = 443
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["213.180.193.0/24"]
    port           = 443
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["213.180.204.0/24"]
    port           = 443
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["84.47.172.0/24"]
    from_port      = 7770
    to_port        = 7800
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["84.47.172.0/24"]
    port           = 8443
  }

  egress {
    protocol       = "TCP"
    v4_cidr_blocks = ["51.250.1.0/24"]
    port           = 44445
  }
}

# ГРУППА БЕЗОПАСНОСТИ BASTION
resource "yandex_vpc_security_group" "bastion_sg" {
  name       = "bastion-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "SSH from my home IP"
    v4_cidr_blocks = [var.my_ip]
    port           = 22
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ГРУППА БЕЗОПАСНОСТИ БАЛАНСИРОВЩИКА
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
    protocol          = "TCP"
    description       = "Health checks"
    predefined_target = "loadbalancer_healthchecks"
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# ГРУППА БЕЗОПАСНОСТИ ВЕБСЕРВЕРОВ
resource "yandex_vpc_security_group" "web_sg" {
  name       = "webserver-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol          = "TCP"
    description       = "Traffic from Balancer"
    security_group_id = yandex_vpc_security_group.alb_sg.id
    port              = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Allow Yandex health checks to backend"
    predefined_target = "loadbalancer_healthchecks"
  }
}

# ГРУППА БЕЗОПАСНОСТИ ZABBIX
resource "yandex_vpc_security_group" "zabbix_sg" {
  name       = "zabbix-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "Web UI"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "Zabbix Agent active checks"
    v4_cidr_blocks = ["10.0.0.0/8"]
    port           = 10051
  }
}

# ГРУППА БЕЗОПАСНОСТИ KIBANA
resource "yandex_vpc_security_group" "kibana_sg" {
  name       = "kibana-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "Web UI"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 5601
  }
}

# ГРУППА БЕЗОПАСНОСТИ ELASTICSEARCH
resource "yandex_vpc_security_group" "elastic_sg" {
  name       = "elastic-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol          = "TCP"
    description       = "Logs from Filebeat"
    security_group_id = yandex_vpc_security_group.web_sg.id
    port              = 9200
  }

  ingress {
    protocol          = "TCP"
    description       = "Queries from Kibana"
    security_group_id = yandex_vpc_security_group.kibana_sg.id
    port              = 9200
  }
}
