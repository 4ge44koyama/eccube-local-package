タイトル通りにはなりますが、弊社でも採用しているEC-CUBEのローカル環境構築について今回は記事を書いてみようと思います。

なお、今回はEC-CUBE.coを利用せずに自社でホスティング環境を用意し、運用していく場合の環境構築を想定しています。

<br>

先に今回構築する際の流れだけをまとめますと

1. ローカルにてVirtualBox＋Vagrantを使用して仮想マシンを構築し、仮想マシンの中でEC-CUBEをGithubからクローン
2. VSCodeのRemote Developmentを使用してホストマシンから仮想マシンにssh接続
3. 仮想マシンの中で直接ファイル操作を行う

<br>

今回のポイントはVagrantのディレクトリマウントを使用せずにサーバー(仮想マシン)の中で直接ファイル操作を行うというところです。
今回この構成で構築した時のメリットはいくつかあるのですが
- ディレクトリマウントをするよりもファイル編集時のレスポンスが早い
- 仮想マシン側のVSCodeに拡張プラグインを導入するだけで言語(FW)などの補完がきく
- Vagrant+VirtualBoxの構成なのでホストマシン(Mac,Windows)の環境差分を吸収できる
- boxファイルをパッケージして共有することで、メンバー間で発生しがちな環境差分を吸収できる
- 仮想マシンの構築手順をAnsible等のプロビジョニングツールで自動化することで本番環境にも適用できる
などが挙げられるかと思います。
<br>

# 検証環境
- MacOS Catalina, Windows10
- VirtualBox 6.1.30
- Vagrant 2.2.19
- VSCode

<br>

# 手順解説
# 1. ローカルにてVirtualBox＋Vagrantを使用して仮想マシンを構築
この章では開発に使用する仮想マシン(サーバー)を構築していきます。<br>
なお今回は下記の構成で仮想マシンを構築していきます。
- Ubuntu 20.04
- Apache 2.4
- MySQL 8.0
- PHP 7.4
- EC-CUBE 4.1

弊社は本番環境でAmazonLinuxを使用する場合はUbuntuではなくCentOSで構築していますが、今回はEC-CUBE公式の情報に合わせてUbuntuで構築していきます。

<br>

まずここから先の手順を進める前にVirutualBoxとVagrant(プラグイン含め)のインストールをしてください。<br>
下記ハンズオン形式の記事が非常に参考になりますので一読されることをオススメします。<br>
また、本記事では今回使用するツールやそれに関するコマンドなどの解説は割愛させていただきます。<br>
- [【ペチオブ】仮想環境ハンズオン 第3回 Vagrant編](https://qiita.com/ucan-lab/items/e14a26081229c8bef98a)

<br>

```
// Vagrant(プラグイン含め)とVirtualBoxのインストールを確認
$ vagrant -v
Vagrant 2.2.19

$ vagrant plugin list
vagrant-share (2.0.0, global)
vagrant-vbguest (0.30.0, global)

$ VBoxManage -v
6.1.30r148432

// 今回使用するUbuntuのboxイメージを追加
$ vagrant box add ubuntu/focal64

$ vagrant box list
ubuntu/focal64 (virtualbox, 20200326.0.0)
```

```
// 任意のディレクトリに作業ディレクトリを作成
$ mkdir ec-cube

// 移動
$ cd ec-cube
```

```
// 先ほど取得したUbuntuのBoxファイルを使用してVagrantファイルの雛形を作成
$ vagrant init -m ubuntu/focal64
```

<br>

今回はUbuntuのパッケージやミドルウェア等のインストールをshellで実行します。
これを作成しておくだけでも環境構築の手順書代わりになるのでオススメです。<br>
なお、必要なパッケージ等はEC-CUBE開発者情報と公式GithubのDockerファイル等を参考に選定しています。<br>
- [EC-CUBE4 開発者ドキュメントサイト](https://doc4.ec-cube.net/quickstart/requirement)
- [EC-CUBE - Github](https://github.com/EC-CUBE/ec-cube)

<br>

```
// 仮想マシンを初回起動時に各種モジュール等をインストールするshellを作成
$ vim init.shell

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

# /var/www/ にec-cube 4.1を設置(ドキュメントルート)
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
```




```
// 作成したshellを初回起動時に実行するようにVagrantfileを編集
$ vim Vagrantfile

# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  config.vm.network "forwarded_port", guest: 80, host: 8000
  config.vm.provision :init, type: "shell", path: "init.sh"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"
    vb.cpus = "2"
  end
end
```

```
// 仮想マシンを起動
$ vagrant up
```

<br>

仮想マシンを起動するとshellの内容を初回のみ実行して各種パッケージをインストールします。<br>
無事起動が完了したら仮想マシンにsshで入ります。<br>
```
// 仮想マシンにsshで入る
$ vagrant ssh
```

<br>

# 2. VSCodeのRemote Developmentを使用してホストマシンから仮想マシンにssh接続
この章では前の章で作成した仮想マシンにVSCodeの拡張プラグインを導入したホストマシンからssh接続を行います。

<br>

```
// 1度仮想マシンから出る
$ exit
```

- VSCodeを起動する
- 画面左側の拡張機能タブを選択し、検索窓に「remote develop」と入力
- 検索結果からRemote Developmentを選択し、プラグインをインストール
- 左下の緑アイコンからリモートウィンドウを開く
- メニューからOpen SSH Configuration File...を選択
- /Users/ユーザー名/.ssh/config を選択し、ファイルを開く
- 仮想マシンを起動しているコンソールに切り替えて下記コマンドを実行
  ```
  // 仮想マシンが起動している状態で
  $ vagrant ssh-config

  // 下記情報をコピー
  Host default
    HostName 127.0.0.1
    User vagrant
    Port 2222
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
    PasswordAuthentication no
    IdentityFile /Users/ユーザー名/vagrant/ec-cube/.vagrant/machines/default/virtualbox/private_key
    IdentitiesOnly yes
    LogLevel FATAL
  ```
- コピーした内容を/Users/ユーザー名/.ssh/config に貼り付け and 上書き保存
  - 捕捉: Host defaultのdefault部分は自分がわかりやすい名前に変更すると良い
  - 今回はeccube-defaultに設定
  ```
  /Users/ユーザー名/.ssh/configの中身

  Host eccube-default
    HostName 127.0.0.1
    User vagrant
    Port 2222
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
    PasswordAuthentication no
    IdentityFile /Users/ユーザー名/vagrant/ec-cube/.vagrant/machines/default/virtualbox/private_key
    IdentitiesOnly yes
    LogLevel FATAL
  ```
- 再度左下の緑アイコンからリモートウィンドウを開く
- メニューからConnect To Host...を選択
- eccube-defaultを選択し、仮想マシンにssh接続(別ウィンドウでVSCodeが開きます)

ここまでの手順で無事仮想環境にssh接続したVSCodeが開ければ一旦OKです。<br>

<br>

次にEC-CUBEを初期状態で動かせるようにしていきます。
- コンソールから起動中の仮想マシンにsshで入る
  ```
  $ vagrant ssh
  ```
- Apacheのドキュメントルートをec-cubeに変更する
  ```
  // 設定ファイルを開く
  $ sudo vim /etc/apache2/sites-available/000-default.conf

  // INSERTモードに切り替えてから下記の修正をして上書き保存
  # DocumentRoot /var/www/html
  DocumentRoot /var/www/ec-cube
  <Directory /var/www/ec-cube/>
    RewriteEngine On
  </Directory>
  ```
- Apacheのmod_rewriteを有効化とし再起動する
  ```
  $ sudo a2enmod rewrite

  $ sudo systemctl restart apache2
  ```
- Apacheを再起動する
  ```
  $ sudo systemctl restart apache2
  ```
- ec-cubeインストールコマンドを実行
  ```
  $ cd /var/www/ec-cube

  $ sudo bin/console e:i

  // プロビジョニング用のshellで登録した内容を入力(コピペでOKです)
  Database Url
  > mysql://eccube:secret@127.0.0.1/eccube_db

  // Mailer Urlは今回設定しないのでエンター
  // Auth Magicはそのままでエンター
  ```
<br>
ここまでの手順が終わったらブラウザで http://localhost:8000 へアクセスしてみましょう。<br>
EC-CUBEデフォルトTOPページが表示されればOKです<br>
管理画面はデフォルトだと http://localhost:8000/admin です。<br>
id: admin<br>
pass: password<br>
<br>

ここからがやや面倒なのですが、VSCodeのRemote Developmentは接続する仮想マシンごとにVSCodeのプラグインをインストールしなければいけません。そのため、今回紹介するのは必要最低限ではありますが、下記プラグインをeccube-defaultに接続しているVSCodeでもインストールしておきましょう。<br>
※プラグインによってはローカルでインストールしているものが既に仮想マシンでも有効化されている場合もあります。

- Japanese Language Pack for Visual Studio Code
- zenkaku
- indent railbow
- Bracket Pair Colorizer
- Symfony extensions pack

※その他必要に応じてPHP Debugやphp cs fixerなど...

<br>

# 仮想マシンの中で直接ファイル操作を行う
この章では仮想マシンの中でファイル編集などの操作ができるようにしていきます。

<br>

ポイントはRemote Developmentでssh接続して仮想マシンをVSCodeで操作しているユーザーがvagrantユーザーという点です。<br>
なのでまずはVSCode側で直接ファイルを編集できるようにファイル/ディレクトリの権限を変更する必要があります。<br>
<br>

```
$ sudo chown -R vagrant:www-data /var/www/
```
これでVSCode側でファイル内容を変更やファイルの追加・削除ができるようになります。<br>
<br>

〜以下略〜
<br>

# 参考

- [【ペチオブ】仮想環境ハンズオン 第3回 Vagrant編](https://qiita.com/ucan-lab/items/e14a26081229c8bef98a)
- [Ubuntu 最低限抑えておきたい初期設定](https://qiita.com/kotarella1110/items/f638822d64a43824dfa4)
- [VagrantでVScodeのRemote Developmentを使おう！](https://qiita.com/hppRC/items/9a46fdb4af792a454921)
- [EC-CUBE4 開発者ドキュメントサイト](https://doc4.ec-cube.net)
  - [コマンドラインからインストールする](https://doc4.ec-cube.net/quickstart/command_install)
- [EC-CUBE - Github](https://github.com/EC-CUBE/ec-cube)
- [Ubuntu 20.04にApache Webサーバーをインストールする方法](https://www.digitalocean.com/community/tutorials/how-to-install-the-apache-web-server-on-ubuntu-20-04-ja)
- [Ubuntu+Apache2の設定ファイルの場所とか構成とかメモ](https://penpen-dev.com/blog/ubuntuapache2/)
- [Ubuntu版Apache2でmod_rewriteを有効にする](https://qiita.com/u-akihiro/items/c7a5bb38c34858d00c2a)