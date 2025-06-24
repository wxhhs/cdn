#!/bin/bash

set -o errexit
export PIP_DISABLE_PIP_VERSION_CHECK=1

download(){
  # wget安装
  if [[ ! `which wget` ]]; then
    if check_sys sysRelease ubuntu;then
        apt-get install -y wget
    elif check_sys sysRelease centos;then
        yum install -y wget
    fi 
  fi

  local url1=$1
  local url2=$2
  local filename=$3
  
  speed1=`curl -m 5 -L -s -w '%{speed_download}' "$url1" -o /dev/null || true`
  speed1=${speed1%%.*}
  speed2=`curl -m 5 -L -s -w '%{speed_download}' "$url2" -o /dev/null || true`
  speed2=${speed2%%.*}
  echo "speed1:"$speed1
  echo "speed2:"$speed2
  url=$url1
  if [[ $speed2 -gt $speed1 ]]; then
    url=$url2
  fi
  echo "using url:"$url
  wget "$url" -O $filename

}

#判断系统版本
check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''
    local packageSupport=''

    if [[ "$release" == "" ]] || [[ "$systemPackage" == "" ]] || [[ "$packageSupport" == "" ]];then

        if [[ -f /etc/redhat-release ]];then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "debian";then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "ubuntu";then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat";then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "debian";then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "ubuntu";then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "centos|red hat|redhat";then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        else
            release="other"
            systemPackage="other"
            packageSupport=false
        fi
    fi

    echo -e "release=$release\nsystemPackage=$systemPackage\npackageSupport=$packageSupport\n" > /tmp/ezhttp_sys_check_result

    if [[ $checkType == "sysRelease" ]]; then
        if [ "$value" == "$release" ];then
            return 0
        else
            return 1
        fi

    elif [[ $checkType == "packageManager" ]]; then
        if [ "$value" == "$systemPackage" ];then
            return 0
        else
            return 1
        fi

    elif [[ $checkType == "packageSupport" ]]; then
        if $packageSupport;then
            return 0
        else
            return 1
        fi
    fi
}

get_sys_ver() {
cat > /tmp/sys_ver.py <<EOF
import platform
import re

sys_ver = platform.platform()
sys_ver = re.sub(r'.*-with-(.*)','\g<1>',sys_ver)
if sys_ver.startswith("centos-7"):
    sys_ver = "centos-7"
if sys_ver.startswith("centos-6"):
    sys_ver = "centos-6"
if sys_ver.startswith("debian-11"):
    sys_ver = "debian-11"

if sys_ver.startswith("Ubuntu-16.04"):
    sys_ver = "Ubuntu-16.04"

if sys_ver.startswith("Ubuntu-22.04"):
    sys_ver = "Ubuntu-22.04"

print sys_ver
EOF
echo `python2 /tmp/sys_ver.py`
}


upgrade_db() {
eval `grep MYSQL_PASS /opt/cdnfly/master/conf/config.py`
eval `grep MYSQL_IP /opt/cdnfly/master/conf/config.py`
eval `grep MYSQL_PORT /opt/cdnfly/master/conf/config.py`
eval `grep MYSQL_DB /opt/cdnfly/master/conf/config.py`
eval `grep MYSQL_USER /opt/cdnfly/master/conf/config.py`


mysql -h$MYSQL_IP -u$MYSQL_USER -p$MYSQL_PASS -P$MYSQL_PORT $MYSQL_DB -e "show processlist"  | awk '{print $1}' | grep -v Id | xargs kill || true

cat > /tmp/_db.py <<'EOF'
# -*- coding: utf-8 -*-

import sys
sys.path.append("/opt/cdnfly/master/")
from view.util import get_ip_location,is_empty
from model.db import Db
import pymysql
import json
import datetime
reload(sys) 
sys.setdefaultencoding('utf8')

conn = Db()
try:

    # 转换cc_rule表
    rows = conn.fetchall("select id,data from cc_rule;")
    for row in rows:
        rule_id = row['id']
        data = row['data']
        if not data:
            continue
            
        data = json.loads(data)
        for d in data:
            d["mode"] = "break"

        conn.execute("update cc_rule set data=%s where id=%s",(json.dumps(data),rule_id,))
        conn.commit()

    # 转换site表的extra_cc_rule字段
    rows = conn.fetchall("select id,extra_cc_rule from site;")
    for row in rows:
        site_id = row['id']
        extra_cc_rule = json.loads(row['extra_cc_rule'])
        for d in extra_cc_rule:
            d["mode"] = "break"

        conn.execute("update site set extra_cc_rule=%s where id=%s",(json.dumps(extra_cc_rule),site_id,))
        conn.commit()
    
    

except:
    conn.rollback()
    raise

finally:
    conn.close()
EOF

/opt/venv/bin/python /tmp/_db.py



# 更新panel或conf
cd /opt/cdnfly/master/panel;
\cp dashboard/img/{ad.jpeg,favicon.ico,logo.png} /opt/$dir_name/master/panel/dashboard/img;  # 保存logo
rm -rf /opt/cdnfly/master/panel/dashboard # 删除旧的dashboard
\cp -a /opt/$dir_name/master/panel/dashboard /opt/cdnfly/master/panel/ # 复制新的dashboard

flist='master/conf/nginx_global.tpl
master/conf/nginx_http_default.tpl'
for f in `echo $flist`;do
\cp -a /opt/$dir_name/$f /opt/cdnfly/$f
done

# 清理宝塔缓存
rm -rf /www/server/nginx/proxy_cache_dir/*


}

update_file() {
cd /opt/$dir_name/master/
for i in `find ./ | grep -vE "^./$|^./agent$|^./conf$|conf/config.py|conf/nginx_global.tpl|conf/supervisord.conf|conf/supervisor_master.conf|conf/nginx_http_default.tpl|conf/nginx_http_vhost.tpl|conf/nginx_stream_vhost.tpl|conf/ssl.cert|conf/ssl.key|^./panel"`;do
    \cp -aT $i /opt/cdnfly/master/$i
done

}

# 定义版本
version_name="v5.8.0"
version_num="50800"
dir_name="cdnfly-master-$version_name"
tar_gz_name="$dir_name-$(get_sys_ver).tar.gz"

# 下载安装包
cd /opt
echo "开始下载$tar_gz_name..."
download "https://raw.githubusercontent.com/wxhhs/cdn/main/$tar_gz_name" "https://raw.githubusercontent.com/wxhhs/cdn/main/$tar_gz_name" "$tar_gz_name"
echo "下载完成"

echo "开始解压..."
rm -rf $dir_name
tar xf $tar_gz_name
echo "解压完成"

cd /opt
echo "准备升级数据库..."
upgrade_db
echo "升级数据库完成"

echo "更新文件..."
update_file
echo "更新文件完成." 

echo "修改config.py版本..."
sed -i "s/VERSION_NAME=.*/VERSION_NAME=\"$version_name\"/" /opt/cdnfly/master/conf/config.py
sed -i "s/VERSION_NUM=.*/VERSION_NUM=\"$version_num\"/" /opt/cdnfly/master/conf/config.py
rm -f /opt/cdnfly/master/conf/config.pyc
echo "修改完成"

echo "开始重启主控..."
supervisorctl  -c /opt/cdnfly/master/conf/supervisord.conf restart all
#supervisorctl  -c /opt/cdnfly/master/conf/supervisord.conf reload
echo "重启完成"

echo "清理文件"
rm -rf /opt/$dir_name
rm -f /opt/$tar_gz_name
echo "清理完成"

echo "完成$version_name版本升级"