# **salmin_ansible**

====================================
v1.2
====================================
# 🚀 salmin_ansible — Руководство по развертыванию и управлению (NLRC Lab)

Централизованный хаб инфраструктурной автоматизации на базе Ansible для
управления питанием и конфигурацией пула ПК в подсети 192.168.0.0/24. 
Проект поддерживает инкрементальную миграцию: новые хосты добавляются 
по мере настройки, а управляющие команды затрагивают только те устройства, 
для которых явно прописаны MAC-адреса.

---

## 📁 1. Архитектура и структура проекта

Проект разделен на контуры (green — продакшен, yellow — тестирование) 
и содержит полную обвязку для автоматизации, логирования и развертывания.

~/ansible/
├── README.md               # Общая документация проекта
├── README_RUS.md           # Русскоязычное руководство (этот файл)
└── pwrmgmt/
    ├── green/              # Стабильный пул (Production)
    │   ├── hosts.ini       # Инвентарь хостов и MAC-адресов
    │   ├── group_vars/     # Зашифрованные переменные (логины/пароли)
    │   ├── poweron.yml     # Плейбук дистанционного включения (WOL)
    │   ├── poweroff.yml    # Плейбук выключения через SSH (shutdown)
    │   ├── poweroff_shutdown.yml # Выключение через шедуллер (SYSTEM)
    │   ├── install_ssh_key.yml   # Распространение SSH-ключей на узлы
    │   ├── setup_wol_ubuntu_only.yml # Настройка Wake-on-LAN на Linux
    │   ├── get_macs.yml    # Автоматический сбор MAC-адресов с хостов
    │   ├── check_ip.sh     # Скрипт проверки доступности хостов
    │   ├── wake_pc_pool.sh # Bash-скрипт резервного включения
    │   ├── run_on.sh       # Обертка для запуска включения через cron
    │   ├── run_off.sh      # Обертка для запуска выключения через cron
    │   ├── vault_pass.txt  # Мастер-пароль для Ansible Vault
    │   ├── cron_poweron.log  # Лог автоматического включения
    │   ├── cron_poweroff.log # Лог автоматического выключения
    │   ├── id_rsa_project  # Приватный ключ SSH
    │   └── id_rsa_project.pub # Публичный ключ SSH
    └── yellow/             # Тестовый контур (Staging)

### Назначение ключевых компонентов:
* hosts.ini — централизованный файл инвентаря. Хосты без mac= пропускаются.
* group_vars/all.yml — зашифрованные учетные данные для Linux и Windows.
* poweroff.yml — отправляет shutdown -h now напрямую через SSH.
* poweroff_shutdown.yml — выключение через системный шедуллер от SYSTEM.
* check_ip.sh — опрашивает все хосты из hosts.ini и выводит список DOWN.

---

## 🛠 2. Подготовка управляющего узла (Ubuntu)

Установите необходимые системные утилиты:
sudo apt update
sudo apt install -y ansible wakeonlan

### Решение проблемы со старой версией Python (например, Python 3.8)
Если пакет python3.10 не находится через apt, используйте standalone сборку:

# Временно убираем проблемные списки репозиториев NVIDIA
sudo mv /etc/apt/sources.list.d/nvidia* /tmp/ 2>/dev/null || true

# Создаем директорию и скачиваем оптимизированный бинарник Python 3.10
sudo mkdir -p /opt/python3.10
cd /tmp
wget https://github.com/indygreg/python-build-standalone/releases/download/20240224/cpython-3.10.13+20240224-x86_64-unknown-linux-gnu-install_only.tar.gz

# Распаковываем в системную папку
sudo tar -xzf cpython-3.10.13+20240224-x86_64-unknown-linux-gnu-install_only.tar.gz -C /opt/python3.10 --strip-components=1

# Проверка
/opt/python3.10/bin/python3 --version

*После этого пропишите путь в hosts.ini через параметр:*
`ansible_python_interpreter=/opt/python3.10/bin/python3`

---

## 🔑 3. Управление SSH-ключами и доступом

Если ключи повреждены (error in libcrypto) или создаются заново:
cd ~/ansible/pwrmgmt/green
rm -f id_rsa_project id_rsa_project.pub
ssh-keygen -t rsa -b 4096 -f id_rsa_project -N ""
chmod 600 id_rsa_project

Рассылка ключей на целевые хосты:
ansible-playbook -i hosts.ini install_ssh_key.yml --ask-pass
*(Флаг --ask-pass запрашивает пароль SSH-подключения к пользователю ansible).*

---

## 📋 4. Настройка инвентаря (hosts.ini)

Пример заполнения инвентаря:

[pc_pool]
192.168.0.216 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project ansible_python_interpreter=/opt/python3.10/bin/python3 mac=d8:5e:d3:53:39:17
192.168.0.217 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project mac=d8:5e:d3:53:39:00
192.168.0.228 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project

*(Хост .228 без параметра mac будет автоматически пропущен).*

---

## 🪟 5. Подготовка целевых ПК (Windows)

### Создание администратора Ansible (выполнить в PowerShell от Администратора):
$Password = ConvertTo-SecureString "engNN!52" -AsPlainText -Force
New-LocalUser -Name "ansible" -Password $Password -FullName "ANSIBLE" -Description "The Matrix has You..." -PasswordNeverExpires
Add-LocalGroupMember -Group "Administrators" -Member "ansible"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Force

### Настройка Wake-on-LAN (WoL) в Windows:
1. **Fast Startup:** Панель управления -> Электропитание -> «Действие кнопок питания» -> снять галочку с «Включить быстрый запуск».
2. **Диспетчер устройств -> Сетевые адаптеры -> Свойства карты:**
   * **Управление питанием:** включить «Разрешить этому устройству будить компьютер» и «Разрешить пробуждение только магическим пакетом».
   * **Дополнительно:**
     * `Energy Efficient Ethernet` — Disabled
     * `Enable PME` — Enabled
     * `Ultra Low Power Mode` — Disabled
     * `Wake on Link Settings` — Disabled
     * `Wake on Pattern Match` — Disabled

---

## 🚀 6. Запуск пайплайнов и команд управления

### Синхронизация времени (Москва, NTP)
sudo timedatectl set-timezone Europe/Moscow
sudo timedatectl set-ntp on
timedatectl

### Справочник команд Ansible:
* **Проверка доступности хостов:**
  `./check_ip.sh`
* **Настройка службы Wake-on-LAN на Linux:**
  `ansible-playbook -i hosts.ini setup_wol_ubuntu_only.yml --ask-become-pass`
* **Включение компьютеров (WOL):**
  `ansible-playbook -i hosts.ini poweron.yml --vault-password-file vault_pass.txt`
* **Включение через Bash-скрипт:**
  `chmod +x wake_pc_pool.sh && ./wake_pc_pool.sh`
* **Выключение через SSH:**
  `ansible-playbook -i hosts.ini poweroff.yml --vault-password-file vault_pass.txt`
* **Выключение через планировщик (SYSTEM):**
  `ansible-playbook -i hosts.ini poweroff_shutdown.yml --vault-password-file vault_pass.txt`

---

## ⏰ 7. Автоматизация по расписанию (Cron)

### Шаг 1. Защита пароля Vault
cd /home/neo/ansible/pwrmgmt/green
echo "ваш_пароль_vault" > vault_pass.txt
chmod 600 vault_pass.txt

### Шаг 2. Создание скриптов-оберток с логированием

* **`run_off.sh` (Выключение):**
#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green
echo -e "\n========================================" >> cron_poweroff.log
echo "=== Запуск: $(date '+%Y-%m-%d %H:%M:%S') ===" >> cron_poweroff.log
echo "========================================" >> cron_poweroff.log
/usr/bin/ansible-playbook -i hosts.ini poweroff.yml --vault-password-file vault_pass.txt >> cron_poweroff.log 2>&1

* **`run_on.sh` (Включение):**
#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green
echo -e "\n========================================" >> cron_poweron.log
echo "=== Запуск: $(date '+%Y-%m-%d %H:%M:%S') ===" >> cron_poweron.log
echo "========================================" >> cron_poweron.log
/usr/bin/ansible-playbook -i hosts.ini poweron.yml --vault-password-file vault_pass.txt >> cron_poweron.log 2>&1

Дайте права на исполнение:
`chmod +x run_off.sh run_on.sh`

### Шаг 3. Настройка Crontab
`crontab -e`

Добавьте расписание:
# Выключение по будням (Пн-Пт) в 18:00 и страховка в 18:15
0 18 * * 1-5 /home/neo/ansible/pwrmgmt/green/run_off.sh
15 18 * * 1-5 /home/neo/ansible/pwrmgmt/green/run_off.sh

# Включение по будням (Пн-Пт) ровно в 09:30
30 9 * * 1-5 /home/neo/ansible/pwrmgmt/green/run_on.sh

### Мониторинг и проверка логов:
* Проверить расписание: `crontab -l`
* Логи выключения: `cat cron_poweroff.log`
* Логи включения: `cat cron_poweron.log`



## 8. Обновленный код скрипта check_ip.sh
Замените содержимое файла на следующий вариант:

#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green
INI_FILE="hosts.ini"
LOG_FILE="check_ip.log"

# Добавляем разделитель и штамп времени в лог
echo -e "\n========================================" >> "$LOG_FILE"
echo "=== Запуск проверки: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

if [[ ! -f "$INI_FILE" ]]; then
    echo "Error: $INI_FILE not found!" >> "$LOG_FILE"
    exit 1
fi

while IFS= read -r line; do
    # Убираем пробелы по краям
    line=$(echo "$line" | xargs)

    # Пропускаем пустые строки и комментарии
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Достаем первое слово (это может быть IP или заголовок секции/переменная)
    first_word=$(echo "$line" | awk '{print $1}')

    # Пропускаем заголовки секций вроде [pc_pool] или [windows_pool:vars]
    [[ "$first_word" =~ ^\[ ]] && continue

    # Проверяем, похоже ли первое слово на IP-адрес (начинается с цифры)
    [[ ! "$first_word" =~ ^[0-9] ]] && continue

    # Сбрасываем порт, если он указан (например, 192.168.0.246:101 -> 192.168.0.246)
    ip=$(echo "$first_word" | cut -d: -f1)

    if ! ping -c 1 -W 1 "$ip" &>/dev/null; then
        echo "DOWN: $ip" >> "$LOG_FILE"
    fi
done < "$INI_FILE"

2. Добавление в cron
Откройте редактор расписания:

crontab -e

Добавьте строку для запуска скрипта каждый день в 20:00:

# Проверка доступности хостов ежедневно в 20:00
0 20 * * * /home/neo/ansible/pwrmgmt/green/check_ip.sh

Сохраните файл и выйдите (в зависимости от выбранного редактора: для nano — Ctrl + O, Enter, Ctrl + X; для vim — Esc, затем :wq и Enter).

Как посмотреть результат:

cat /home/neo/ansible/pwrmgmt/green/check_ip.log
========================================================================================================================================


Old versions:
=====================================
v1.0
=====================================

Central Ansible infrastructure automation hub for NLRC Lab. Manages configuration, deployment, and orchestration across segmented environments. Serves as the primary repository for Infrastructure as Code (IaC) maintenance and automated system operations.

iWTC PC Power Management (Ansible)
Комплекс плейбуков Ansible для автоматизированного управления питанием пула ПК в подсети 192.168.0.0/24. Проект поддерживает инкрементальную (постепенную) миграцию: новые машины добавляются в общий пул по мере настройки, а управляющие команды затрагивают исключительно те хосты, для которых явно прописаны MAC-адреса.

Структура проекта
Plaintext
├── hosts.ini            # Централизованный инвентарь с перечнем хостов и MAC-адресами
├── poweroff.yml         # Плейбук для удаленного выключения настроенных ПК
├── wake_ready.yml       # Плейбук для включения (Wake-on-LAN) настроенных ПК
└── id_rsa_project       # Закрытый SSH-ключ для доступа к узлам

Требования
* Установленный Ansible на управляющей машине (localhost).
* Утилита wakeonlan на управляющей машине (для отправки магических пакетов).
* Настроенный доступ по SSH к целевым ПК под пользователем ansible с использованием приватного ключа id_rsa_project.
* Настроенный беспарольный sudo (или готовность вводить пароль sudo интерактивно при выключении) на целевых хостах.

Настройка инвентаря (hosts.ini)
Все хосты описываются в группе [pc_pool].
Если компьютер настроен (готов к управлению питанием), ему добавляется параметр mac=XX:XX:XX:XX:XX:XX.
Если компьютер еще не настроен (находится в процессе ввода в эксплуатацию), параметр mac опускается. Плейбуки автоматически пропустят такие хосты.

Пример файла hosts.ini:

[pc_pool]
192.168.0.216 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project ansible_python_interpreter=/opt/python3.10/bin/python3 mac=d8:5e:d3:53:39:17
192.168.0.217 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project mac=d8:5e:d3:53:39:00

# Хост без MAC-адреса (будет пропущен автоматикой):
192.168.0.228 ansible_user=ansible ansible_ssh_private_key_file=./id_rsa_project

Использование

1. Выключение настроенных компьютеров
Плейбук подключается по SSH к каждому хосту из pc_pool, проверяет наличие параметра mac и выполняет безопасное выключение (shutdown -h now).

    ansible-playbook -i hosts.ini poweroff.yml -K

*(Флаг -K используется, если на целевых узлах требуется ввод пароля sudo).*

2. Включение настроенных компьютеров (Wake-on-LAN)
Плейбук выполняется локально (localhost), сканирует инвентарь pc_pool, находит все машины с заполненным параметром mac и отправляет широковещательный пакет WOL (192.168.0.255).

    ansible-playbook -i hosts.ini wake_ready.yml

Как добавить новый компьютер в проект:
* Настройте ОС и базовое окружение на целевом ПК.
* Убедитесь, что пользователь ansible и SSH-ключ (id_rsa_project) имеют корректный доступ.
* Узнайте MAC-адрес сетевой карты целевой машины.
* Добавьте IP-адрес хоста в секцию [pc_pool] файла hosts.ini вместе с параметром mac=XX:XX:XX:XX:XX:XX.
* После этого компьютер начнет автоматически учитываться при выполнении плейбуков включения и выключения.


==================================================
v1.1
=================================================

Руководство по развертыванию и управлению проектом (Power Management Ansible Project)

1. Развертывание проекта на новой машине (Управляющий узел)
Если вы переносите проект на чистую машину (например, с Ubuntu), выполните следующие шаги для подготовки окружения:

* Установите Ansible и необходимые системные утилиты:

    sudo apt update
    sudo apt install -y ansible wakeonlan

* Перенесите файлы проекта в рабочую директорию (например, ~/ansible/pwrmgmt/yellow/).

2. Генерация и пересоздание SSH-ключей (Решение проблем с доступом)
Если у вас возникли ошибки авторизации, поврежден файл ключа (error in libcrypto) или требуется полностью обновить связку ключей безопасности:

* Удалите старые ключи (если они повреждены) в папке проекта:

    rm -f id_rsa_project id_rsa_project.pub

* Сгенерируйте новую пару RSA-ключей без парольной фразы (-N ""):

    ssh-keygen -t rsa -b 4096 -f id_rsa_project -N ""

* Установите правильные права доступа на приватный ключ (SSH строго требует права 600, иначе выдаст ошибку bad permissions):

    chmod 600 id_rsa_project

* Разошлите новые ключи на целевые хосты (модуль запросит SSH-пароль пользователя ansible на удаленных машинах):

    ansible-playbook -i hosts.ini install_ssh_key.yml --ask-pass

3. Описание файлов проекта
В вашем проекте используются следующие ключевые файлы:

* hosts.ini — файл инвентаря (Inventory). В нем прописаны IP-адреса целевых компьютеров (входящих в пул pc_pool), объединенных для управления питанием.
* install_ssh_key.yml — плейбук для первоначальной настройки безопасности. Подключается к хостам и прописывает ваш публичный ключ (id_rsa_project.pub) в файл ~/.ssh/authorized_keys на удаленных машинах.
* setup_wol_ubuntu_only.yml — плейбук конфигурации Wake-on-LAN. Автоматически проверяет сетевые интерфейсы, создает системную службу wol.service с использованием ethtool и активирует режим ожидания магического пакета (wol g).
* poweron.yml — плейбук для дистанционного включения компьютеров. Запускается локально (localhost) и отправляет «магические пакеты» (Magic Packets) на бродкаст-адрес подсети для каждого MAC-адреса из инвентаря.
* poweroff.yml — плейбук для централизованного выключения всех компьютеров из пула (hosts: pc_pool). Работает в параллельном режиме (strategy: free) и отправляет команду shutdown -h now.
* get_macs.yml — вспомогательный универсальный плейбук для автоматического сбора MAC-адресов сетевых интерфейсов с целевых машин.

4. Запуск пайплайнов и плейбуков (С правильными ключами)
Чтобы все команды выполнялись без сбоев и ошибок прав доступа, используйте следующие команды:

* Шаг 1. Настройка службы Wake-on-LAN на хостах
Выполняет настройку ethtool и службы wol.service на удаленных серверах/ПК. Так как задача требует административных привилегий на целевых машинах, обязательно используется флаг --ask-become-pass:

    ansible-playbook -i hosts.ini setup_wol_ubuntu_only.yml --ask-become-pass

*(При запросе BECOME password: введите пароль суперпользователя sudo удаленной машины).*

* Шаг 2. Включение компьютеров (Wake-on-LAN)
Запускает отправку сетевых пакетов пробуждения (выполняется на управляющей машине localhost):

    ansible-playbook -i hosts.ini poweron.yml

* Шаг 3. Выключение компьютеров
Посылает сигнал безопасного выключения на все активные хосты из пула:

    ansible-playbook -i hosts.ini poweroff.yml --ask-become-pass
