#!/bin/bash
#
# Script v2.0 by Natallia Bo (webxdata.com)
# script modificated from https://neblog.info/skript-bekapa-na-yandeks-disk
#

MYSQL_SERVER=mysql
MYSQL_USER=wordpress
MYSQL_PASSWORD=password
BACKUP_DIR='/var/www/html/'
PROJECT='wp'
MAX_BACKUPS='3'
DATE=`date '+%Y-%m-%d--%H-%M'`
TOKEN='AAAAAAAAAAAAAAAAAAAAAAAA'
LOGFILE='backup.log'
sendLog='support@site.com'
sendLogErrorsOnly='false'

function mailing()
{
    if [ ! $sendLog = '' ];then
        if [ "$sendLogErrorsOnly" == true ];
        then
            if echo "$1" | grep -q 'error'
            then   
                echo "$2" | mail -s "$1" $sendLog > /dev/null
            fi
        else
            echo "$2" | mail -s "$1" $sendLog > /dev/null
        fi
    fi
}

function logger()
{
    echo "["`date "+%Y-%m-%d %H:%M:%S"`"] File $BACKUP_DIR: $1" >> $BACKUP_DIR/$LOGFILE
}

function parseJson()
{
    local output
    regex="(\"$1\":[\"]?)([^\",\}]+)([\"]?)"
    [[ $2 =~ $regex ]] && output=${BASH_REMATCH[2]}
    echo $output
}

function checkError()
{
    echo $(parseJson 'error' "$1")
}

function getUploadUrl()
{
    json_out=`curl -s -H "Authorization: OAuth $TOKEN" https://cloud-api.yandex.net:443/v1/disk/resources/upload/?path=app:/$backupName&overwrite=true`
    json_error=$(checkError "$json_out")
    if [[ $json_error != '' ]];
    then
        logger "$PROJECT - Yandex.Disk error: $json_error"
        mailing "$PROJECT - Yandex.Disk backup error" "ERROR copy file $FILENAME. Yandex.Disk error: $json_error"
    echo ''
    else
        output=$(parseJson 'href' $json_out)
        echo $output
    fi
}

function uploadFile
{
    local json_out
    local uploadUrl
    local json_error
    uploadUrl=$(getUploadUrl)
    if [[ $uploadUrl != '' ]];
    then
    echo $UploadUrl
        json_out=`curl -s -T $1 -H "Authorization: OAuth $TOKEN" $uploadUrl`
        json_error=$(checkError "$json_out")
    if [[ $json_error != '' ]];
    then
        logger "$PROJECT - Yandex.Disk error: $json_error"
        mailing "$PROJECT - Yandex.Disk backup error" "ERROR copy file $FILENAME. Yandex.Disk error: $json_error"

    else
        logger "$PROJECT - Copying file to Yandex.Disk success"
        mailing "$PROJECT - Yandex.Disk backup success" "SUCCESS copy file $FILENAME"

    fi
    else
    	echo 'Some errors occured. Check log file for detail'
    fi
}

function backups_list() {
    curl -s -H "Authorization: OAuth $TOKEN" "https://cloud-api.yandex.net:443/v1/disk/resources?path=app:/&sort=created&limit=100" | tr "{},[]" "\n" | grep "name" |grep mysql | cut -d: -f 2 | tr -d '"' | grep -v "https"
}

function backups_count() {
    local bkps=$(backups_list | wc -l)
    expr $bkps / 1
}

function remove_old_backups() {
    bkps=$(backups_count)
    old_bkps=$((bkps - MAX_BACKUPS))
    if [ "$old_bkps" -gt "0" ];then
        logger "Deleting old backups"
        for i in `eval echo {1..$((old_bkps * 1))}`; do
            curl -X DELETE -s -H "Authorization: OAuth $TOKEN" "https://cloud-api.yandex.net:443/v1/disk/resources?path=app:/$(backups_list | awk '(NR == 1)')&permanently=true"
        done
    fi
}

logger "--- $PROJECT START BACKUP $DATE ---"
logger "Dumping databases"
mkdir $BACKUP_DIR/$DATE
for i in `mysql -h $MYSQL_SERVER -u $MYSQL_USER -p$MYSQL_PASSWORD -e'show databases;' | grep -v information_schema | grep -v Database`;
    do mysqldump --skip-add-locks -h $MYSQL_SERVER -u $MYSQL_USER -p$MYSQL_PASSWORD $i > $BACKUP_DIR/$DATE/$i.sql;
done

logger "Creating archive mysql $BACKUP_DIR/$DATE-mysql-$PROJECT.tar.gz"
tar -czf $BACKUP_DIR/$DATE-mysql-$PROJECT.tar.gz $BACKUP_DIR/$DATE
rm -rf $BACKUP_DIR/$DATE

#tar -czf $BACKUP_DIR/$DATE-files-$PROJECT.tar.gz $DIRS

FILENAME=$DATE-mysql-$PROJECT.tar.gz
logger "Uploading archive with mysql $BACKUP_DIR/$DATE-mysql-$PROJECT.tar.gz"
backupName=$DATE-mysql-$PROJECT.tar.gz
uploadFile $BACKUP_DIR/$DATE-mysql-$PROJECT.tar.gz

#FILENAME=$DATE-files-$PROJECT.tar.gz
#logger "Uploading archive $BACKUP_DIR/$DATE-files-$PROJECT.tar.gz"
#backupName=$DATE-files-$PROJECT.tar.gz
#uploadFile $BACKUP_DIR/$DATE-files-$PROJECT.tar.gz

logger "Clearing temp dir"
find $BACKUP_DIR -type f -name "*mysql*.gz" -exec rm '{}' \;

if [ $MAX_BACKUPS -gt 0 ];then remove_old_backups; fi

logger "Finish"
