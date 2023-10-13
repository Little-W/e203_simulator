#!/bin/bash

update_pkgconfig_prefix()
{
    filePath=$1
	prefixDir=$2
    for file in `ls -a $filePath`
    do
        if [ -d ${filePath}/$file ]
        then
            if [[ $file != '.' && $file != '..' ]]
            then
                update_pkgconfig_prefix ${filePath}/$file $prefixDir
            fi
        else
			filename=${filePath}/$file
			if [ "${filename##*.}"x = "pc"x ]
			then
				prefix_line=`grep -n "prefix=/" $filename | cut -d ":" -f 1`
				prefix_str="prefix=$prefixDir"
				sed -i "$prefix_line c $prefix_str" $filename
			fi
        fi
    done
}

workdir=$(cd $(dirname $0); pwd)
update_pkgconfig_prefix $workdir/share/pkgconfig $workdir
