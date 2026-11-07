#!/bin/bash

# Переходим в папку, где находится скрипт
cd "$(dirname "$0")"

echo "Запуск MongoDB..."

# Настройка для совместимости с ядром
sudo mkdir -p /etc/systemd/system/mongod.service.d

sudo tee /etc/systemd/system/mongod.service.d/rseq.conf > /dev/null <<'EOF'
[Service]
Environment="GLIBC_TUNABLES=glibc.pthread.rseq=1"
EOF

# Перезагрузка systemd
sudo systemctl daemon-reload

# Включаем MongoDB при запуске компьютера
sudo systemctl enable mongod

# Запускаем MongoDB
sudo systemctl start mongod

# Проверяем работу MongoDB
if ! systemctl is-active --quiet mongod; then
    echo "Ошибка: MongoDB не запустилась!"
    sudo systemctl status mongod --no-pager
    exit 1
fi

echo "MongoDB успешно запущена!"

# Установка зависимостей Go
echo "Проверка зависимостей..."
go mod tidy

# Запуск программы
echo "Запуск Go-программы..."
go run .

# Проверка данных в MongoDB
echo "Проверка коллекций..."

mongosh service_center --quiet --eval '
print("Клиенты: " + db.clients.countDocuments());
print("Заявки: " + db.requests.countDocuments());
print("Запчасти: " + db.parts.countDocuments());
'

echo "Работа скрипта завершена!"