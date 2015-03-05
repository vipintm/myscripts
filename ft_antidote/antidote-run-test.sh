#!/bin/bash

# paths
export PATH=/usr/local/Cellar/erlang/R16B02/bin:$PATH

# misc
log_sep="---------------------------------------------"

# Messages
error_cc="Unable to get Code change information"

# files
riakbin="$WORKSPACE/riak_test/riak_test"
test_cases="$WORKSPACE/antidote/riak_test/*.erl"
antidote_bin="$HOME/rt/antidote/current/dev/dev*/bin/antidote"
riak_configf="$HOME/.riak_test.config"
antidote_current="$WORKSPACE/antidote/riak_test/bin/antidote-current.sh"
antidote_setup="$WORKSPACE/antidote/riak_test/bin/antidote-setup.sh"
code_histroy="$HOME/.code_histroy"

# Vars
is_timeout=0
is_perl=0
is_awk=0
is_sed=0
is_erl=0
is_erlc=0
is_git=0
is_grep=0
riak_changed=0
antidote_changed=0
test_pass_cnt=0
test_failed_cnt=0
test_cnt=0
declare -a failed_fns
declare -a failed_errors

# Time out
max_time=3600 #in seconds

# requirment test -1
if type "timeout" > /dev/null 2>&1 ; then
	is_timeout=1
fi
if type "perl" > /dev/null 2>&1 ; then
    is_perl=1
fi
if type "awk" > /dev/null 2>&1 ; then
    is_sed=1
fi
if type "sed" > /dev/null 2>&1 ; then
    is_sed=1
fi
if type "erl" > /dev/null 2>&1 ; then
	is_erl=1
fi
if type "erlc" > /dev/null 2>&1 ; then
	is_erlc=1
fi
if type "git" > /dev/null 2>&1 ; then
	is_git=1
fi
if type "grep" > /dev/null 2>&1 ; then
	is_grep=1
fi


# min req.
if [ -z $WORKSPACE ] || [ -z $HOME ] || [ "$is_sed" -eq 0 ] \
	|| [ "$is_erl" -eq 0 ] || [ "$is_erlc" -eq 0 ] \
    || [ "$is_grep" -eq 0 ] #do we need sed ?
then
	echo "Required support not found, exiting ..."
    exit 1
fi
if [ -d $WORKSPACE ] && [ -d $HOME ] 
then
	echo ""
	echo $log_sep
else
	echo "Required support not found, exiting ..."
    exit 1
fi

# select time out
if [ "$is_timeout" -eq 1 ]; then
	echo "Using bash timeout function ..."
	function alarm() { timeout "$@"; }
elif [ "$is_perl" -eq 1 ] ; then
	echo "Using perl script for timeout function ..."
	function alarm() { perl -e 'alarm shift; exec @ARGV' "$@"; }
else
	echo "Time out support not found ..."
    function alarm() { bash "${@:2}"; }
fi

# timer
function timer()
{
    if [[ $# -eq 0 ]]; then
        echo $(date '+%s')
    else
        local  stime=$1
        etime=$(date '+%s')

        if [[ -z "$stime" ]]; then stime=$etime; fi

        dt=$((etime - stime))
        printf '%d' $dt
    fi
}

# clean old dev's
function clean_dev()
{
	echo "Clearing all old dev's ...." 
	for dev_bin in $(ls -1 $antidote_bin); do
		is_antinode_up=$($dev_bin ping 2>/dev/null \
        | grep "pong" | wc -l | sed 's/^ *//g')
    	if [ "$is_antinode_up" -eq 1  ]
    	then
    		echo "$dev_bin is up, stoping it ..."
    		$dev_bin stop
    	fi
	done
}

# riak config file
if [ -f $riak_configf ]
then
	echo "The riak test config file found"
    #cat $riak_configf
    #echo ""
else
	echo "The riak test config file not found, creating it .."
cat > $riak_configf << EOL
{default, [
    {platform, "osx-64"},
    {rt_max_wait_time, 600000},
    {rt_retry_delay, 1000},
    {rt_harness, rtdev},
    {rt_scratch_dir, "/tmp/riak_test_scratch"},
    {basho_bench, "/Users/cmeiklejohn/Basho/basho_bench"},
    {load_workers, 10},
    {lager_level, info}
]}.
{antidote, [
    {rt_project, "antidote"},
    {cluster_a_size, 3},
    {num_nodes, 6},
    {exec_name, "antidote"},
    {rt_cookie, antidote},
    {test_paths, ["$WORKSPACE/antidote/riak_test/ebin"]},
    {rtdev_path, [{root, "$HOME/rt/antidote"},
                  {current, "$HOME/rt/antidote/current"}]}
]}.

{intercept_example,
 [
  {load_intercepts, true},
  {intercepts,
   [
    {riak_kv_vnode, [{{put,7}, dropped_put}]}
   ]}
 ]}.
EOL
fi

# dir chmod
chmod -R 755 $WORKSPACE/riak_test
chmod -R 755 $WORKSPACE/antidote

# clean old files
if [ -d $WORKSPACE/utest ]; then
	echo "Clearing old test result temp files ..."
    rm -rf $WORKSPACE/utest/*.xml
else
	echo "Creating test result temp dir ..."
	mkdir $WORKSPACE/utest
fi

if [ -d $WORKSPACE/tlog ]; then
	echo "Clearing old temp logs ..."
    rm -rf $WORKSPACE/tlog/*.log
else
	echo "Creating temp logs dir ..."
	mkdir $WORKSPACE/tlog
fi

# setup antinode
cd $WORKSPACE/antidote/ # Nevr remove this the script need 
			  			# to run inside antidote dir
if [ -d $HOME/rt ]; then
	echo "Updating with antidote current ..."
    if [ -f $antidote_current ]
    then
    	$antidote_current
    else
    	echo "Unable to read $antidote_current .."
        exit 1
    fi
else
	echo "Creating antidote setup ..."
    if [ -f $antidote_setup ]
    then
    	mkdir $HOME/rt
    	$antidote_setup
    else
    	echo "Unable to read $antidote_setup .."
        exit 1
    fi
fi

# dir chmod
chmod -R 755 $HOME/rt

# requirment test -2
is_antidote_bin=$(ls -1 $antidote_bin 2>/dev/null \
	| wc -l | sed 's/^ *//g')
if [ -f "$riakbin" ] && [ "$is_antidote_bin" -ge 6 ] \
	&& [ -f "$riak_configf" ]
then
	echo "Going good .."
else
	echo "Required support not found, exiting ..."
    exit 1
fi

# clean old dev's
clean_dev

# test loop
for file_test in $(grep -l confirm/0 $test_cases 2>/dev/null)
do
    fn_test=$(basename $file_test .erl)
     
	# local vars
    t=0
    test_fail=0
    test_pass=0
    
    # default messages
    fail_message="$fn_test Failed"
    fail_type="Unknown"
    error_message="Error in $fn_test"
    error_type="Unknown"
    
    # local files
    test_logf="$WORKSPACE/tlog/$fn_test.log"
    utest_file="$WORKSPACE/utest/Test-"$fn_test".xml"

	test_cnt=$((test_cnt+1))

	# Test exec
    echo ""
    echo $log_sep
    echo "$test_cnt) Test : $fn_test"
    echo ""
    
    echo "$riakbin -v -c antidote -t $fn_test"
    t=$(timer)
    
    # Keep this as single line
	alarm $max_time $riakbin -v -c antidote -t $fn_test 2>&1 | tee -a $test_logf
       
    time_sec=$(timer $t)
    echo ""
    echo $log_sep
    
    # Test result processing
    echo "Time taken for $fn_test (seconds) :$time_sec"
     
    if [ -f $test_logf ]
    then
    	test_pass=$(cat $test_logf 2>/dev/null \
        	| grep "$fn_test-error: pass" | wc -l | sed 's/^ *//g')
     	test_fail=$(cat $test_logf 2>/dev/null \
        	| grep "$fn_test-error: fail" | wc -l | sed 's/^ *//g')
    else
     	echo "Error : The test log not found .."
    fi
    
    if [ "$test_pass" -eq 0 ] 
    then
		clean_dev
    fi
    
	if [ -f $test_logf ] && [ "$test_pass" -eq 1 ] && [ "$test_fail" -eq 0 ]
    then
        echo "The test is detected as passed[$test_pass]"
        test_pass_cnt=$((test_pass_cnt+1))
    elif [ -f $test_logf ] && [ "$test_pass" -eq 0 ] && [ "$test_fail" -eq 1 ]
    then
    	echo "The test is detected as failed[$test_pass]"
        failed_fns[test_failed_cnt]="$fn_test "       
        if [ "$time_sec" -ge "$max_time" ]
        then
            error_message="$fn_test is stopped forcefully, \
as it exceeded maximum run time($max_time sec)"
            error_type="stopped"
            fail_message="$fn_test is stopped forcefully, \
as it exceeded maximum run time($max_time sec)"
            fail_type="stopped"
            failed_errors[test_failed_cnt]="$fail_message"
        else
        	if [ "$is_perl" -eq 1 ]; then
        		failed_errors[test_failed_cnt]=$(cat $test_logf \
            		2>/dev/null | perl -ne \
            		'print "$1\n" if /(?<=$fn_test-error: fail <<")(.+?)(?=">>)/')
            elif [ "$is_awk" -eq 1 ]; then
            	failed_errors[test_failed_cnt]=$(cat $test_logf \
            		2>/dev/null | awk -v \
                    FS="($fn_test-error: fail <<\"|\">>)" '{print $2}')
            elif [ "$is_sed" -eq 1 ]; then
        		failed_errors[test_failed_cnt]=$(cat $test_logf \
            		2>/dev/null | sed -n \
            		'/$fn_test-error: fail <<\"/,/\">>/')
            else
            	failed_errors[test_failed_cnt]="Unable to Parse"
            fi
            error_type="exicution-error"
            error_message="$fn_test is failed, \
as it has exicution-error(check the logs : $BUILD_URL)"
            fail_message="$fn_test is failed, \
as it has exicution-error(check the logs : $BUILD_URL)"
            fail_type="exicution-error"
        fi
        test_failed_cnt=$((test_failed_cnt+1))
	else
    	failed_fns[test_failed_cnt]="$fn_test "
        if [ -f $test_logf ] && [ "$time_sec" -ge "$max_time" ]
        then
        	echo "The test is stoped, marking as failed[$test_pass]"
            error_message="$fn_test is stopped forcefully, \
as it exceeded maximum run time($max_time sec)"
            error_type="stopped"
            fail_message="$fn_test is stopped forcefully, \
as it exceeded maximum run time($max_time sec)"
            fail_type="stopped"
        elif [ -f $test_logf ]
        then
         	echo "Something was wrong with $fn_test after started .."
            echo "The test is marked as failed[$test_pass]"
            fail_message="$fn_test Failed, Unknown"
     		fail_type="Unknown"
     		error_message="Error in $fn_test, Unknown"
     		error_type="Unknown"
        else
         	echo "Something was wrong with $fn_test, \
it dosen't look like started .."
            echo "The test is marked as failed[$test_pass]"
            error_message="$fn_test not executed, \
something was wrong with $fn_test"
            error_type="not-executed"
            fail_message="$fn_test not executed, \
something was wrong with $fn_test"
            fail_type="not-executed"
        fi
        failed_errors[test_failed_cnt]="$fail_message"
        test_failed_cnt=$((test_failed_cnt+1))
	fi
    
    touch $utest_file
    
    if [ -f $test_logf ] && [ "$test_pass" -eq 1 ]
    then

cat > $utest_file << EOL
<?xml version="1.0" encoding="UTF-8" ?>
<testsuite tests="1" failures="0" errors="0" skipped="0" time="$time_sec" name="$fn_test">
  <testcase time="$time_sec" name="$fn_test"/>
</testsuite>
EOL

	else

cat > $utest_file << EOL
<?xml version="1.0" encoding="UTF-8" ?>
<testsuite tests="1" failures="1" errors="1" skipped="0" time="$time_sec" name="$fn_test">
  <testcase time="$time_sec" name="$fn_test">
    <error message="$error_message" type="$error_type"/>
    <failure message="$fail_message" type="$fail_type"/>
  </testcase>
</testsuite>
EOL

	fi 

    if [ -f  $utest_file ]
    then
    	echo "Test result file (xml) created ..."
    	#cat $utest_file
    else
    	echo "Error in test result file (xml) creation ..."
    fi

done

# Collecting Code Change information
riak_HEAD=$(cat $WORKSPACE/riak_test/.git/HEAD)
riak_name=$(cat $WORKSPACE/riak_test/.git/FETCH_HEAD | grep -w "$riak_HEAD" | cut -d"'" -f2)
mkdir -p $code_histroy/riak_test/$riak_name
if [ -f $code_histroy/riak_test/$riak_name/sHEAD ]
then
  	riak_HEAD_old=$(cat $code_histroy/riak_test/$riak_name/sHEAD 2>/dev/null)
else
   	riak_HEAD_old="NA"
fi
riak_log="$WORKSPACE/tlog/riak_git_change.log"
if [ "$riak_HEAD" != "$riak_HEAD_old" ] 
then
	if [ "$is_git" -eq 1 ] ; then
    	cd $WORKSPACE/riak_test
   		git log -n5 > $riak_log
    else
    	echo "$error_cc" > $riak_log
    fi
   	riak_changed=1
else
   	riak_changed=0
fi
if [ "$test_pass_cnt" -eq "$test_cnt" ]
then
   	cp $WORKSPACE/riak_test/.git/HEAD $code_histroy/riak_test/$riak_name/sHEAD
fi
    
antidote_HEAD=$(cat $WORKSPACE/antidote/.git/HEAD)
antidote_name=$(cat $WORKSPACE/antidote/.git/FETCH_HEAD | grep -w "$antidote_HEAD" | cut -d"'" -f2)
mkdir -p $code_histroy/antidote/$antidote_name
if [ -f $code_histroy/antidote/$antidote_name/sHEAD ]
then
   	antidote_HEAD_old=$(cat $code_histroy/antidote/$antidote_name/sHEAD 2>/dev/null)
else
   	antidote_HEAD_old="NA"
fi
antidote_log="$WORKSPACE/tlog/riak_git_change.log" 
if [ "$antidote_HEAD" != "$antidote_HEAD_old" ]
then
    if [ "$is_git" -eq 1 ] ; then
    	cd $WORKSPACE/antidote
   		git log -n5 > $antidote_log
    else
    	echo "$error_cc" > $antidote_log
    fi
   	antidote_changed=1
else
	antidote_changed=0
fi
if [ "$test_pass_cnt" -eq "$test_cnt" ]
then
   	cp $WORKSPACE/antidote/.git/HEAD $code_histroy/antidote/$antidote_name/sHEAD
fi

# Summary
echo ""
echo $log_sep
echo "Code Changes from Last successful test"
echo ""
echo "# riak_test" 
echo "branch    		  : $riak_name"
if [ "$riak_changed" -eq 1 ]
then
    if [ "$riak_changed" -gt 0 ]
    then
    	echo $log_sep
		echo "Change Log (last 5) :"
    	cat $riak_log
    	echo ""
    else
    	echo ""
    fi
else
	
echo "Change Log          : No change found"
fi
echo $log_sep

echo "# antidote"
echo "branch              : $antidote_name"
if [ "$antidote_changed" -eq 1 ]
then
    if [ "$antidote_changed" -gt 0 ]
    then
    	echo $log_sep
		echo "Change Log (last 5) :"
    	cat $antidote_log
    	echo ""
    else
    	echo ""
    fi
else
	echo $log_sep
	echo "Change Log          : No change found"
fi

echo $log_sep
echo "Total no of tests   :$test_cnt"
echo "No of tests passed  :$test_pass_cnt"
if [ "$test_pass_cnt" -ne "$test_cnt" ]
then
	echo "No of tests failed  :$test_failed_cnt"
    echo "Marking as FAILED"
    loop_cnt=0
    echo ""
    echo "Failed tests summary -"
    echo $log_sep
    for failed_fn_name in "${failed_fns[@]}"
    do
    	echo "# $failed_fn_name"
        error_temp="${failed_errors[$loop_cnt]}"
        #there is somthing in first few characters
        is_error=$(echo ${error_temp:1:5})
        if [ -z $is_error ]
        then
        	echo "Unable to parse error info, refer the build log"
        else
			echo "Error : "
        fi
        echo "${failed_errors[$loop_cnt]}"
        echo ""        
        loop_cnt=$((loop_cnt+1))
    done
    echo $log_sep
    echo ""
    exit 1
else
	echo "Marking as PASSED"
    echo $log_sep
    echo ""
fi

