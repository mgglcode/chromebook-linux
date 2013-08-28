#!/bin/bash
# combine.sh

# combine files into: fc19minimal.tgz
# verify against: fc19minimal-sha1


tgt=fc19minimal.tgz

if [ -f $tgt ]; then rm $tgt ; fi

echo
echo "Combine xa* files into:  $tgt ..."

for x in a b c d e f g h i j k l m ; do 
    sha1sum -c xa$x-sha1
    if [ $? -ne 0 ]; then
        echo "Failed sha1sum at file xa$x"
        exit 1
    fi
    cat xa$x  >> $tgt
done

echo
echo "Check $tgt..."
sha1sum -c fc19minimal-sha1

