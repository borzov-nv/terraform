Файлы terraform:
- vm.tf (виртуальные машины)
- network.tf (сеть и группы безопасности)
- variables.tf (объявление переменных, значения в приватном tfvars)
- hosts.tftpl (шаблон инвентаря для ансибла)

Пароли для создаваемых ансиблом учеток - в приватном файле group_vars/all.yml

---

**Карта**

![](img/map.png)

![](img/vms.png)

---

**Балансировщик**

![](img/alb.png)

![](img/alb-map.png)

---

**Тест**

![](img/alb-curl.png)


---

**Кибана**

![](img/kibana.png)

---

![](img/security-groups.png)

---

**Заббикс**

![](img/zabbix-hosts.png)

![](img/zabbix-zabbix.png)

![](img/zabbix-bastion.png)

![](img/zabbix-elastic.png)

![](img/zabbix-kibana.png)

![](img/zabbix-web-1.png)

![](img/zabbix-web-2.png)

---

![](img/snapshot-schedule.png)

![](img/snapshots.png)

