#!/bin/bash

# requirment test -0
if [ -z $WORKSPACE ] || [ -z $HOME ]
then
	echo "Required support not found, exiting ..."
    exit 1
fi

code_histroy="$HOME/.code_histroy"


#clean old files
if [ -d $WORKSPACE/riak_test ]
then
	echo "Cleaning old riak_test ..."
	rm -rf $WORKSPACE/riak_test
fi
if [ -d $WORKSPACE/antidote ]
then
	echo "Cleaning old antidote ..."
	rm -rf $WORKSPACE/antidote
fi

