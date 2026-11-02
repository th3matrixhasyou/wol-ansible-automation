#!/bin/bash
cd /home/neo/ansible/pwrmgmt/green
INI_FILE="hosts.ini"
LOG_FILE="check_ip.log"

# Инициализируем счетчик выключенных хостов
down_count=0

# Добавляем разделитель и штамп времени в лог
echo -e "\n============================================" >> "$LOG_FILE"
echo "=== Запуск проверки: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"

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

    # Сбрасываем порт, если он указан (например, 10.219.34.246:101 -> 10.219.34.246)
    ip=$(echo "$first_word" | cut -d: -f1)

    if ! ping -c 1 -W 1 "$ip" &>/dev/null; then
        echo "DOWN: $ip" >> "$LOG_FILE"
        # Увеличиваем счетчик выключенных хостов на 1
        ((down_count++))
    fi
done < "$INI_FILE"

# Записываем итоговое количество недоступных хостов в лог без лишних символов \n
echo "--------------------------------------------" >> "$LOG_FILE"
echo "Всего выключено хостов: $down_count" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"
