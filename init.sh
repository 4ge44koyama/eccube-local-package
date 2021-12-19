#!/bin/bash

# shell実行時オプション
# https://qiita.com/keitean/items/83c7d0d6221ec1b9c63c
set -eux

# 必要なパッケージのインストール
apt update
apt upgrade -y
apt install --no-install-recommends -y apt-transport-https apt-utils build-essential curl debconf-utils gcc git vim gnupg2 libfreetype6-dev libicu-dev libpng-dev libpq-dev libzip-dev locales ssl-cert unzip zlib1g-dev libwebp-dev

apt upgrade -y ca-certificates
apt clean

# パッケージの削除
rm -rf /var/lib/apt/lists/*
echo "en_US.UTF-8 UTF-8" >/etc/locale.gen
locale-gen

# PHP7.4とApache2のインストール
add-apt-repository ppa:ondrej/php
apt -y install php7.4

# MySQL用モジュール
apt -y install php7.4-mysql

# その他必要なPHPモジュールのインストール
# 参考：https://doc4.ec-cube.net/quickstart/requirement
apt -y install php7.4-curl php7.4-cli php7.4-zip php7.4-intl php7.4-xml php7.4-mbstring

# MySQLのインストール
apt -y install mysql-server mysql-client

# MySQLの文字コードと照合順序を設定ファイルとして書き出し
cat << EOS | sudo tee /etc/my.cnf
[mysqld]
character_set_server = utf8mb4
collation_server = utf8mb4_ja_0900_as_cs
EOS

# MySQLを再起動
systemctl restart mysql

# MySQLのデータディレクトリを初期化
# mysqld --initialize-insecure --user=mysql

# EC-CUBE用のdatabaseを作成
mysql -u root << EOT
CREATE DATABASE eccube_db;
CREATE USER eccube@'%' IDENTIFIED WITH mysql_native_password BY 'secret';
GRANT ALL PRIVILEGES on eccube_db.* to eccube@'%';
EOT

# /var/www/ にec-cube 4.1を設置
git clone -b 4.1 https://github.com/EC-CUBE/ec-cube /var/www/ec-cube

# Composerのインストール
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === '906a84df04cea2aa72f40b5f787e49f22d4c2f19492ac310e8cba5b96ac8b64115ac402c8cd292b8a03482574915d1a8') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"

mv ./composer.phar $(dirname $(which php))/composer && chmod +x "$_"
composer --version

# EC-CUBEに必要なパッケージを取得
composer update -d /var/www/ec-cube

echo "インストール完了！"