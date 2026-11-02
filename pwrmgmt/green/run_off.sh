#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green

# Добавляем разделитель и штамп времени в лог
echo -e "\n========================================" >> cron_poweroff.log
echo "=== Запуск: $(date '+%Y-%m-%d %H:%M:%S') ===" >> cron_poweroff.log
echo "========================================" >> cron_poweroff.log

# Запуск Ansible-плейбука с перенаправлением вывода
/usr/bin/ansible-playbook -i hosts.ini poweroff.yml --vault-password-file vault_pass.txt >> cron_poweroff.log 2>&1
