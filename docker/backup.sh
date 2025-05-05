#!/bin/sh

# 获取阿里云环境变量
ACCESSKEY_SECRET=$OSS_ACCESSKEY_SECRET
ENDPOINT=$OSS_ENDPOINT
ACCESSKEY_ID=$OSS_ACCESSKEY_ID

# 获取文件加密GPG公钥
GPG_KEYID=$ENCRYPTION_PUB_ID
GPG_PUBKEY=$ENCRYPTION_PUB_KEY
if [ -n "$GPG_PUBKEY" ] && [ -n "$GPG_KEYID" ]; then
    if gpg --fingerprint "$GPG_KEYID" >/dev/null 2>&1; then
        echo "密钥 $GPG_KEYID 已存在,无须导入." > /proc/1/fd/1 2>/proc/1/fd/2
    else
        echo "密钥 $GPG_KEYID 未导入,导入中..." > /proc/1/fd/1 2>/proc/1/fd/2
        echo "$GPG_PUBKEY" | gpg --import
    fi
else
    echo "未配置GPG环境变量" > /proc/1/fd/1 2>/proc/1/fd/2
    exit 1
fi

if [ -n "$ACCESSKEY_SECRET" ] && [ -n "$ENDPOINT" ] && [ -n "$ACCESSKEY_ID" ]; then
    cat << EOF > /tmp/ossconfig
[Credentials]
language=CH
accessKeySecret=$ACCESSKEY_SECRET
endpoint=$ENDPOINT
accessKeyID=$ACCESSKEY_ID
EOF
    
    # 开始备份
    tar -zcvf - /data | gpg --recipient "$GPG_KEYID" -e -o - | dd of=/tmp/vaultwarden.enc
    ossutil cp /tmp/vaultwarden.enc oss://my-server-backup/file/ -f --maxupspeed 4096 -c /tmp/ossconfig
    # 上传成功
    echo "$(date +'%Y-%m-%d') 备份成功." > /proc/1/fd/1 2>/proc/1/fd/2
else
    echo "未配置OSS环境变量" > /proc/1/fd/1 2>/proc/1/fd/2
    exit 1
fi

# 清理文件
rm -rf /tmp/ossconfig
rm -rf /tmp/vaultwarden.enc
exit 0
