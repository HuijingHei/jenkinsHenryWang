#!/bin/bash

function GetInfo()
{
    local ci=$1
    local taskUrl=$2
    local brewAPI=$3
    # get package name
    _PKG_NAME=$(echo ${ci} | jq -r '.info.request[0]')
    PKG_NAME=$(basename $_PKG_NAME | awk -F'#' '{print $1}')

    # get task id
    TASK_ID=$(echo ${ci} | jq -r '.info.id')
    [ "x$TASK_ID" == "x" ] && exit 100

    # get scratch
    SCRATCH=$(echo ${ci} | jq -r '.info.request[2].scratch')
    [ "x$SCRATCH" == "x" ] && SCRATCH="false"

    file="./taskinfoOutput.txt"
    curl -s --retry 5 --insecure ${taskUrl}${TASK_ID} > $file
    # get issuer
    ISSUER=`grep '<a href=\"userinfo?userID=' $file | cut -d '>' -f 2 | cut -d '<' -f 1`
    # get NVR
    NVR=`grep '<th>Build</th><td>' $file | cut -d '>' -f 5 | cut -d '<' -f 1`
    # If NVR is empty, set as rpm name
    if [ "x$NVR" == "x" ]; then
        # get package brew url
        URL_LIST=`python3 docker/brew.py $PKG_NAME $brewAPI --id $TASK_ID --arch x86_64`
        for i in $URL_LIST
        do
            _hv=`echo $i | grep $PKG_NAME | grep -v $PKG_NAME-license`
            if [ "x$_hv" != "x" ]; then
                break
            fi
        done  
        NVR=`basename $_hv | sed 's/.x86_64.rpm//g'`  
    else
        URL_LIST=`python3 docker/brew.py $NVR $brewAPI --id $TASK_ID --arch x86_64`
    fi   
    THREAD_ID=`echo $NVR | md5sum | awk '{print $1}'`
    
}

# main script
if [ $# -ne 3 ]; then
    echo "Usage: $0 ${CI_MESSAGE} ${TASK_URL_PRI} ${BREW_API}"
    exit 100
fi
CI_MESSAGE=$1
TASK_URL_PRI=$2
BREW_API=$3

TASK_ID=""
SCRATCH=""
ISSUER=""
NVR=""
URL_LIST=""
THREAD_ID=""

GetInfo "$CI_MESSAGE" $TASK_URL_PRI $BREW_API

vars="./vars.properties"
[ -f $vars ] && rm -rf $vars
touch $vars
[ "x$TASK_ID" != "x" ] && ( echo "TASK_ID=$TASK_ID" >> $vars ) || (echo "ERROR: TASK_ID is empty"; exit 100)
[ "x$SCRATCH" != "x" ] && ( echo "SCRATCH=$SCRATCH" >> $vars ) || (echo "ERROR: SCRATCH is empty"; exit 100)
[ "x$ISSUER" != "x" ] && ( echo "ISSUER=$ISSUER" >> $vars ) || (echo "ERROR: ISSUER is empty"; exit 100)
[ "x$NVR" != "x" ] && ( echo "NVR=$NVR" >> $vars ) || (echo "ERROR: NVR is empty"; exit 100)
[ "x$URL_LIST" != "x" ] && ( echo "URL_LIST=\"$URL_LIST\"" >> $vars ) || (echo "ERROR: URL_LIST is empty"; exit 100)
[ "x$THREAD_ID" != "x" ] && ( echo "THREAD_ID=$THREAD_ID" >> $vars ) || (echo "ERROR: THREAD_ID is empty"; exit 100)

echo "==========="
cat $vars
echo "==========="