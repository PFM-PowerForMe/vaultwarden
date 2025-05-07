#!/bin/sh
set -eu

# Docker日志输出函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" > /proc/1/fd/1 2>/proc/1/fd/2
}

# 验证必要环境变量
check_env() {
    for var in OSS_ACCESSKEY_SECRET OSS_ENDPOINT OSS_ACCESSKEY_ID \
               ENCRYPTION_PUB_ID ENCRYPTION_PUB_KEY; do
        eval "value=\$$var"
        if [ -z "${value}" ]; then
            log "错误: 必须的环境变量 $var 未设置"
            exit 1
        fi
    done
}

# 配置OSS
configure_oss() {
    cat << EOF > /tmp/ossconfig
[Credentials]
language=CH
accessKeySecret=$OSS_ACCESSKEY_SECRET
endpoint=$OSS_ENDPOINT
accessKeyID=$OSS_ACCESSKEY_ID
EOF
    chmod 600 /tmp/ossconfig
}

# 处理GPG密钥
handle_gpg_key() {
    if gpg --fingerprint "$ENCRYPTION_PUB_ID" >/dev/null 2>&1; then
        log "密钥 $ENCRYPTION_PUB_ID 已存在,无须导入."
    else
        log "密钥 $ENCRYPTION_PUB_ID 未导入,导入中..."
        if ! echo "$ENCRYPTION_PUB_KEY" | gpg --import; then
            log "GPG密钥导入失败"
            exit 1
        fi
        if [ -f "/gpg.sh" ] && ! expect -f /gpg.sh; then
            log "GPG密钥信任设置失败"
            exit 1
        fi
    fi
}

# 执行备份
perform_backup() {
    timestamp=$(date +'%Y-%m-%d')
    backup_file="/tmp/vaultwarden_${timestamp}.enc"
    temp_file="/tmp/vaultwarden_temp.tar.gz"
    
    log "开始备份 /data 目录"
    if ! tar -zcvf "$temp_file" -C /data .; then
        log "备份打包失败"
        rm -f "$temp_file"
        exit 1
    fi
    
    if ! gpg --recipient "$ENCRYPTION_PUB_ID" --encrypt --output "$backup_file" "$temp_file"; then
        log "备份加密失败"
        rm -f "$temp_file"
        exit 1
    fi
    
    rm -f "$temp_file"
    
    log "上传备份到 OSS"
    max_retries=3
    retry_count=0
    
    while [ "$retry_count" -lt "$max_retries" ]; do
        if ossutil cp "$backup_file" "oss://my-server-backup/file/" \
            -c /tmp/ossconfig \
            --maxupspeed 4096; then
            log "备份成功: vaultwarden_${timestamp}.enc"
            rm -f "$backup_file"
            return 0
        fi
        
        retry_count=$((retry_count+1))
        log "上传尝试 $retry_count 失败，正在重试..."
        sleep 5
    done
    
    log "上传失败，已达最大重试次数 $max_retries"
    exit 1
}

# 清理旧备份(保留最近7天)
clean_old_backups() {
    log "开始清理7天前的旧备份"
    cutoff_date=$(date -d "7 days ago" +'%Y-%m-%d')
    
    if ! backup_list=$(ossutil ls oss://my-server-backup/file/ -c /tmp/ossconfig); then
        log "获取备份列表失败"
        return 1
    fi
    
    echo "$backup_list" | while read -r line; do
        object=$(echo "$line" | awk '{print $NF}')
        file_date=$(echo "$object" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        
        if [ -n "$file_date" ] && [ "$file_date" \< "$cutoff_date" ]; then
            log "删除旧备份: $object"
            if ! ossutil rm "$object" -c /tmp/ossconfig; then
                log "警告: 删除 $object 失败"
            fi
        fi
    done
    
    log "旧备份清理完成"
}

# 主流程
main() {
    check_env
    handle_gpg_key
    configure_oss
    
    # 检查OSS连接
    if ! ossutil ls oss://my-server-backup -c /tmp/ossconfig >/dev/null; then
        log "无法连接到OSS存储桶，请检查凭证"
        exit 1
    fi
    
    perform_backup
    clean_old_backups
    
    # 清理临时文件
    rm -f /tmp/ossconfig
    rm -f /tmp/vaultwarden_*.enc
}

main
exit 0
