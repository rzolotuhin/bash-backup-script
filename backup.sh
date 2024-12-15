#!/bin/bash

list=(
    # -------------------------------------------------------------------------------------
    # vpn
    # -------------------------------------------------------------------------------------
    '/etc/openvpn'
    # -------------------------------------------------------------------------------------
    # ntp
    # -------------------------------------------------------------------------------------
    '/etc/ntp.conf'
    # -------------------------------------------------------------------------------------
    # hostname / hosts
    # -------------------------------------------------------------------------------------
    '/etc/<host(name|s)$>'
    # -------------------------------------------------------------------------------------
    # cron.d / cron.daily / cron.hourly / cron.monthly / cron.weekly
    # -------------------------------------------------------------------------------------
    '/etc/cron.*'
    # -------------------------------------------------------------------------------------
    # docker
    # -------------------------------------------------------------------------------------
    '/etc/docker'
    '/root/.docker/<\.json$><R>'
    # -------------------------------------------------------------------------------------
    # nginx
    # -------------------------------------------------------------------------------------
    '/etc/nginx/nginx.conf'
    '/etc/nginx/conf.d/<\.conf$><R>'
    # -------------------------------------------------------------------------------------
    # udev
    # -------------------------------------------------------------------------------------
    '/etc/udev/rules.d/<\.rules$><R>'
    # -------------------------------------------------------------------------------------
    # ssh
    # -------------------------------------------------------------------------------------
    '/home/*/.ssh'
    '/etc/ssh/<_config$>'
    '/etc/ssh/*_config.d'
    # -------------------------------------------------------------------------------------
    # etc
    # -------------------------------------------------------------------------------------
    '/etc/logrotate.d'
    '/etc/sysctl.conf'
    '/etc/timezone'
    '/etc/environment'
    '/etc/fstab'
    '/etc/group'
    '/etc/gshadow'
    '/etc/passwd'
    '/etc/shadow'
    '/etc/subgid'
    '/etc/subuid'
    '/etc/sudoers'    
)

dirBackupLocal=/srv/backup
dirBackupTemp=/tmp/backup

function log() {
    local template=$1

    shift
    for param in $*; do
        template=${template/\%s/$param}
    done
    echo ${template//\%s/}
}

function sync() {
    local type=$1
    local src=$2
    local dst=$3

    if [ -z $src ] || [ -z $dst ]; then
        log "sync: source path and destination path must be specified"
        exit 1
    else
        dst=$dst`dirname $src`
    fi
    [ -d $dst ] || mkdir -p $dst
    case "$type" in
        "obj") cp -p "$src" "$dst" 2> /dev/null;;
        "dir") rsync -a "$src" "$dst" 2> /dev/null;;
    esac
}

function search() {
    local path=$1
    local template=$2
    local param=$3
    local maxdepth=1
    local inversion=false

    for (( i=0; i<${#param}; i++ )); do
        case "${param:$i:1}" in
            "R") maxdepth=999;;
            "I") inversion=true;;
        esac
    done

    IFS=""
    find "$path" -maxdepth $maxdepth -type f -print0 | while read -r -d '' file; do
        local regexFile=`basename $file | grep -iP "$template"`
        if [[ ! -z $regexFile && $inversion == false ]] || [[ -z $regexFile && $inversion == true ]]; then
            log " + %s" $file
            sync "obj" "$file" "$dirBackupTemp"
        fi
    done
    IFS=$'\n'
}

function backupNameGenerator() {
    local prefix="backup"
    local postfix=`hostname`

    echo "$prefix"_"$postfix"
}

function readList() {
    local list=$1

    for obj in ${list[*]}; do
        local param=''
        local template=''
        local path=$obj
        local regexParam='(<[^/>]+>){1,2}$'
        local type='unknown'

        # Поиск щаблона в заданиях бэкапа
        if [[ $obj =~ $regexParam ]]; then
            path=`dirname $obj`
            sublist=($path)

            # Поиск путей которые можно раскрыть и преобразовать в список
            if (( ${#sublist[*]} > 1 )); then
                for subobj in ${sublist[*]}; do
                    [ -d $subobj ] && readList "$subobj/`basename $obj`"
                done
                continue
            fi

            # Исключение, шаблон указывает не на каталог или каталог не существует
            if [ ! -d $path ]; then
                log " - error: regex template \"%s\" detected, but destination object not found or this is not a directory: %s" $template $path
                continue
            fi

            # Заполняем параметры для поиска по шаблону
            param=`basename $obj | grep -ioP '<[^>]+><(\K[^\>]+)>$' | grep -ioP '[^<>]+'`
            template=`basename $obj | grep -ioP '^<\K[^>]+'`
            type='template'
        else
            [ -d $path ] && type='directory' || type='object'
        fi

        log "[%s] %s %s %s" $type "$path" $template $param

        # Действие в зависимости от типа объекта в конфиге
        case "$type" in
            "template")  search "$path" "$template" "$param";;
            "directory") sync "dir" "$path" "$dirBackupTemp";;
            "object")    sync "obj" "$path" "$dirBackupTemp";;
        esac
    done
}

function makeBackup() {
    [ -d $dirBackupTemp ] && rm -rf $dirBackupTemp
    mkdir -p $dirBackupTemp

    readList "${list[*]}"

    [ -d $dirBackupLocal ] || mkdir -p $dirBackupLocal

    local md5Path=$dirBackupTemp/fingerprint.md5

    find $dirBackupTemp -type f ! -name "fingerprint.md5" -print0 | sort -z | xargs -r0 md5sum > $md5Path
    sed -i "s/${dirBackupTemp//\//\\\/}//" $md5Path

    local md5Hash=`md5sum $md5Path | grep -ioP "^[^\s]+"`
    local timestamp=`date +'%Y.%m.%d_%H%M%S'`
    local tarPath=/tmp/`backupNameGenerator`_${timestamp}_${md5Hash}.tar.gz
    local lastBackupHash=`ls $dirBackupLocal | grep -ioP "[^_]+_[a-z0-9]{32}\.tar\.gz$" | sort -t _ -k 1 -r | grep -m1 -ioP "[a-z0-9]{32}"`

    if [ "$md5Hash" != "$lastBackupHash" ]; then
        cd $dirBackupTemp && tar -zcf $tarPath ./
        mv $tarPath $dirBackupLocal
    else
        log "stop: the checksum of the current backup matches the previous one: %s" $md5Hash
    fi

    log "done"

    # Удаление старый архивов
    clean
}

function clean() {
    [ -d $dirBackupTemp ] && rm -rf $dirBackupTemp
    find $dirBackupLocal -type f -regex ".*_[a-z0-9]+.tar.gz" -mtime +30 -delete
}

function help() {
    echo "Скрипт резервного копирования"
    echo "`basename $0` <param>"
    echo "  help - данная справка"
    echo "  make - начать формирование резервной копии"
    echo "  clean - очистка временного каталога и удаление старых архивов"
    echo "Вызов без параметров покажет эту справку"
    echo "Шаблон конфига <path><<template>><<param>>"
    echo "  '/etc/hostname' - сделает копию файла с помощью утилиты cp"
    echo "  '/root' - сделает копию каталога со всеми вложениями с помощью утилиты rsync"
    echo "  '/etc/nginx/<\.conf$>' - сделает копии всех файлов с расширением .conf в каталоге /etc/nginx"
    echo "Использование дополнительных параметров в шаблоне: R - рекурсивный поиск, I - инверсия шаблона"
    echo "  '/etc/nginx/<\.conf$><R>' - сделает тоже самое, что и в прошлом варианте, только рекурсивно обойдет все подкаталоги"
    echo "  '/etc/nginx/<\.conf$><RI>' - инвертирует шаблон и ищет все, что не совпадает с ним во всех подкаталогах"
    echo "Поддерживается раскрытие пути"
    echo "  '/etc/cron.*' - сделает копии всех каталогов планировщика cron"
    echo "  '/etc/network/*/<\.sh$>' - сделает копии всех файлов с расширением .sh в подкаталогах /etc/network/* с глубиной +1'"
    echo "После сбора файлов, они будут запакованы в архив .tar.gz"
    echo "В архив также будет добавлен файл fingerprint.md5, в котором будет полный список архива с указанием md5 хэша каждого файла"
}

case "$1" in
    "make") makeBackup;;
    "help") help;;
    "clean") clean;;
    *) help;;
esac