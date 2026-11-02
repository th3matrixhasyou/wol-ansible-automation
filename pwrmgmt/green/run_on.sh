#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green

# Добавляем разделитель и штамп времени в лог
echo -e "\n========================================" >> cron_poweron.log
echo "=== Запуск: $(date '+%Y-%m-%d %H:%M:%S') ===" >> cron_poweron.log
echo "========================================" >> cron_poweron.log

# Запуск Ansible-плейбука с перенаправлением вывода
/usr/bin/ansible-playbook -i hosts.ini poweron.yml --vault-password-file vault_pass.txt >> cron_poweron.log 2>&1
