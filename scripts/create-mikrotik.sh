#!/bin/bash
basedir=".."
outputdir="output/mikrotik"
path="${basedir}/cache_domains.json"
outputfile="${outputdir}/mikrotik_dns_static_entries.rsc"

export IFS=' '

test=$(which jq)
out=$?
if [ $out -gt 0 ] ; then
    echo "This script requires jq to be installed."
    echo "Your package manager should be able to find it"
    exit 1
fi

cachenamedefault="disabled"

# Create output directory
mkdir -p $outputdir
# Clear or create the output file
> $outputfile

# Parse IPs
while read line; do 
    ip=$(jq ".ips[\"${line}\"]" config.json)
    declare "cacheip$line"="$ip"
done <<< $(jq -r '.ips | to_entries[] | .key' config.json)

# Parse cache names
while read line; do 
    name=$(jq -r ".cache_domains[\"${line}\"]" config.json)
    declare "cachename$line"="$name"
done <<< $(jq -r '.cache_domains | to_entries[] | .key' config.json)

# Track processed domains to handle duplicates
declare -A processed_domains

# Generate MikroTik DNS entries
while read entry; do 
    unset cacheip
    unset cachename
    key=$(jq -r ".cache_domains[$entry].name" $path)
    cachename="cachename${key}"
    if [ -z "${!cachename}" ]; then
        cachename="cachenamedefault"
    fi
    if [[ ${!cachename} == "disabled" ]]; then
        continue
    fi
    cacheipname="cacheip${!cachename}"
    cacheip=$(jq -r 'if type == "array" then .[] else . end' <<< ${!cacheipname} | xargs)
    while read fileid; do
        while read filename; do
            while read fileentry; do
                # Ignore comments and newlines
                if [[ $fileentry == \#* ]] || [[ -z $fileentry ]]; then
                    continue
                fi

                match_subdomains=""
                if [[ $fileentry == \*.* ]]; then
                    match_subdomains="match-subdomains=yes"
                    parsed=$(echo $fileentry | sed -e "s/^\*\.//")
                else
                    parsed=$fileentry
                fi

                # Check if the domain was already processed
                if [[ ${processed_domains[$parsed]+_} ]]; then
                    # If we're now processing the wildcard version, remove the previous non-wildcard entry
                    if [[ $match_subdomains == "match-subdomains=yes" ]]; then
                        sed -i "/\/ip dns static add name=${parsed} /d" $outputfile
                    else
                        continue
                    fi
                fi

                for i in ${cacheip}; do
                    echo "/ip dns static add name=${parsed} address=${i} ${match_subdomains}" >> $outputfile
                done

                processed_domains[$parsed]=1
            done <<< $(cat ${basedir}/$filename | sort)
        done <<< $(jq -r ".cache_domains[$entry].domain_files[$fileid]" $path)
    done <<< $(jq -r ".cache_domains[$entry].domain_files | to_entries[] | .key" $path)
done <<< $(jq -r '.cache_domains | to_entries[] | .key' $path)

echo "MikroTik DNS configuration generation completed."
echo "Find the commands in: ${outputfile}"
