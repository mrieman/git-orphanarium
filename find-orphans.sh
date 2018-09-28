#!/bin/bash

##############################################################################
# A shell script that recursivley checks each file's 
#   git log against the bran's main git log since the creation
#   of the branch. Teh output is a log file (and optional
#   sysout of the missing commits.
# Regex explinations are modified from https://regex101.com/
##############################################################################
# Command/tools used:
#  Regex - a sequence of charactes that define a search pattern. Used here to 
#     find words/patterns in files, strings, and command output
#
#  Sed - replaces the pattern found between the first set of forward slashes 
#     (ie. the HERE in "s/HERE/notThis/") with the string found between the 
#     second set of forward slashes (ie. the HERE in "s/notThis/HERE/")
# 
#  Echo - command to print/display output. Also used to write values to files
#
#  Cat - reads the input of a file
#
#  Git - 
#     Git log - retrieves the git log
#     Git (checkout|pull|reset|status) - used to clean the git working directory
#     Git merge-base - used to find the common ansestor between two branches
#     Git show - very detailed commit information used to compare commits
#
#  Tail - retrieves lines from the end of a file
#
#  Tr - tranlates, or deletes characters (Use in this script is similar to sed)
##############################################################################

START_TIME=$SECONDS;

##############################################################################
## functions
##############################################################################

###
# This is a logging function
###
function log() {
   if [ "$1" = "info" ]; then
      echo " $1: ${2}" >> $orphan_log;
   else 
      if [ "$verbose_logging" = true ] && [ "$1" = "debug" ]; then
         echo "$1: ${2}" >> $orphan_log;
      fi
   fi 
   if [ "$super_verbose_logging" = true ] && [ "$1" = "debug" ]; then
      echo "$1: ${2}";
   else
      if [ "$verbose_logging" = true ] || { [ "${3}" = true ] && [ "$quiet_time" = false ]; }; then
         echo " $1: $2";
      fi 
   fi 
}

###
# This function produces a progress bar with percentage complete
###
previous_percent=-1;
percent=0;
previous_error_count=0;
extra_progress_info="";
function update_progress_bar() {
   if [ $count -gt $total_records ]; then
      total_records=$count;
	   extra_progress_info="(file count exceeds $total_records)";
   fi
   if [ "${1}" = true ]; then
      total_records=$count;
   fi
   if [ "${1}" = true ] || [ "$show_progress" = true ]; then
      if [ $count -gt 0 ]; then
         percent=$(( 200 * $count / $total_records % 2  +  100 * $count / $total_records ));
      fi
      if [ $percent -gt $previous_percent ] || [ $error_count -gt $previous_error_count ]; then
	      counter=$(expr ${count} % 75);
         if [ $counter -eq 0 ] && [ $total_records -eq 0 ]; then
            printf ".";
         fi
         if [ $total_records -gt 0 ]; then
            progress_string="Missing Commits: "
            update_progress_string $percent;
            echo -ne "$progress_string"\\r;
            previous_percent=$percent;
			   previous_error_count=$error_count;
         fi
      fi
   fi
   if [ "${1}" = true ] ; then
      echo "";
   fi
}

progress_bar_length=20;
progress_portion=$(( 100 / $progress_bar_length ));
function update_progress_string() {
   local ps_percent=$1;
   progress_string="${progress_string}|";
   local ps_out_count=0;
   local ps_percent_portion=$(( $ps_percent / $progress_portion ));
   local ps_in_count=$ps_percent_portion;
   while [ $ps_out_count -lt $ps_percent_portion ]; do
      progress_string="${progress_string}=";
      ps_out_count=$(($ps_out_count + 1));
   done
   while [ $ps_in_count -lt $progress_bar_length ]; do
      progress_string="${progress_string} ";
      ps_in_count=$(($ps_in_count + 1));
   done
   local extra_space="";
   if [ $ps_percent -lt 100 ]; then
      extra_space=" ";
   fi
   if [ $ps_percent -lt 10 ]; then
      extra_space=" $extra_space";
   fi
   progress_string="${progress_string}| $percent % Complete $extra_progress_info           \r";
}

###
# This function fills out the faked JUnit results for files
###
function test_file_report() {
   # Description: This line removes all characters up to, and including, '/', from the input
   # Regex : ".*" matches any character (except end-of-line chars) 
   #            (0 - unlimited times)
   #         "\/" matches the character '/' literally (case sensitive)
   # Sed : This line removes all charactes up to, and including, '/'
   classname="$(echo $1 | sed 's/.*\///')";
   echo "   <testcase classname=\"$classname\" name=\"compareBranchHistoryWithFileHistory\">" >> $test_report_dir;
   if [ ! -z "$2" -a "$2" != " " ]; then
      echo "      <failure type=\"CommitNotFoundInFileHistory\">" >> $test_report_dir;
      # Description: This line replaces '<' and '>' with the html decoded values
      # Regex : "<" matches the character '<' literally (case sensitive)
      # Sed : This line replaces '<' and '>' with the html decoded values
      echo -e "$(cat $2 | sed -e 's/</\&#60;/g' | sed -e 's/>/\&#62;/g')" >> $test_report_dir;
      echo "      </failure>" >> $test_report_dir;
   fi
   echo "   </testcase>" >> $test_report_dir;
}

###
# This function fills out the faked JUnit results for commits
###
function test_commit_report() {
   echo "   <testcase classname=\"$1\" name=\"compareBranchHistoryWithFileHistory\">" >> $test_report_dir_commit;
   if [ ! -z "$1" -a "$1" != " " ]; then
      echo "      <failure type=\"CommitNotFoundInFileHistory\">" >> $test_report_dir_commit;
      # Description: This line replaces '<' and '>' with the html decoded value
      #    to be added to the test results
      # 'Git log' explination: retrieve the full commit informaiton (--raw) for
      #    a single (-n 1) commit using the has send intot he funciton ($1)
      # Regex : "<" matches the character '<' literally (case sensitive)
      # Sed : This line replaces '<' and '>' with the html decoded values
      echo -e "$(git log -n 1 --raw $1 | sed -e 's/</\&#60;/g' | sed -e 's/>/\&#62;/g'))" >> $test_report_dir_commit;
      echo "      </failure>" >> $test_report_dir_commit;
   fi
   echo "   </testcase>" >> $test_report_dir_commit;
}

###
# This function completes the faked JUnit results
###
function finish_test_file_report() {
   log debug "Finishing 'per file' faked JUnit results";
   # Description: This line removes all characters up to, and including, '/', from the input
   # Regex : ".*" matches any character (except end-of-line chars) 
   #            (0 - unlimited times)
   #         "\/" matches the character '/' literally (case sensitive)
   # Sed : This line removes all charactes up to, and including, '/'
   classname="$(echo $1 | sed 's/.*\///')";
   echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<testsuite tests=\"$classname\" errors=\"$2\" failures=\"0\" >\n$(cat $test_report_dir)" > $test_report_dir;
   echo "</testsuite>" >> $test_report_dir;
}

###
# This function completes the faked JUnit results
###
function finish_test_commit_report() {
   log debug "Finishing 'per commit' faked JUnit results";
   if [ ! -s $test_report_dir_commit ]; then
      touch $test_report_dir_commit;
      echo "   <testcase classname=\"noProblemsFound\" name=\"compareBranchHistoryWithFileHistory\">" >> $test_report_dir_commit;
      echo "   </testcase>" >> $test_report_dir_commit;
   fi
   
   echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<testsuite tests=\"$1\" errors=\"0\" failures=\"$2\" >\n$(cat $test_report_dir_commit)" > $test_report_dir_commit;
   echo "</testsuite>" >> $test_report_dir_commit;
}

###
# Help display top displays script options
###
function show_usage() {
   echo "$(cat $working_directory/findOrphanAnnie.README)";
}

#######################
# function finalizes log and display
#######################
function show_final_output() {
   #######################
   # output counts to log
   #######################
   log info "Matching Cherry Picks Found:";
   log info "$CHERRY_MATCHES";
   log info "";
   log info "Space seperated missing git hash list:";
   log info "$hash_list"

   update_progress_bar true;
   
   log debug "Retrieving error hash count";
   hashes_in_error=( $hash_list );
   commit_error_count=${#hashes_in_error[@]};

   # Git log : retrieve only the hash (--pretty=format:"%h") of the commits 
   #   that have a timestamp between the current HEAD revision to given hash
   #   value (HEAD...$HASH)
   log debug "Retrieving commit hashes from log";
   commits_scanned=$(git log --pretty=format:"%h" HEAD...$HASH);   
   commit_scan_log=( $commits_scanned );
   # Next line retreives the number of values within the list
   log debug "Retrieving the number of values within the logs hash list";
   number_of_commits_scanned=${#commit_scan_log[@]};
   
   log debug "Outputting counts";
   log info "Commits with History Error: $commit_error_count";
   log info "Files with History Error: $error_count";
   log info "Examined Commits: $number_of_commits_scanned";
   log info "Examined records:";
   log info "$count";
   
   echo "Examined Commits: $number_of_commits_scanned";
   echo "Orphaned Commits: $commit_error_count";
   echo "";
   echo "Examined files: $count";
   echo "Files in Error: $error_count";
   
   #######################
   # output hash list
   #######################
   ELAPSED_TIME=$(($SECONDS - $START_TIME));

   hash_file="$temp_dir/missing_hash_list";
   echo "$hash_list" > $hash_file;
   if [ ! -z "$hash_list" -a "$hash_list" != " " ] ; then
      if [[ "$show_error_per_file" ]]; then
         test_file_report "fullListOfGitCommitHash" "$hash_file" ;
      fi 
      for k in $hash_list ; do
         test_commit_report "$k" ;
      done
   fi
   
   if [[ "$show_error_per_file" ]]; then
      finish_test_file_report "$count" "$error_count" "$ELAPSED_TIME" ;
   fi 
   if [[ "$show_error_per_commit" ]]; then
      finish_test_commit_report "$number_of_commits_scanned" "$commit_error_count";
   fi
}


##############################################################################
## Script Begin
##############################################################################
quiet_time=false;
only_log_error=false;

###
# Collect Input
###
while test $# -gt 0
do
   case "$1" in
      -l | --log )
         orphan_log="$2";
         ;;
      -b | --analyze-branch )
         current_branch="$2";
         ;;
      -p | --parent-brnach )
         parent_branch="$2";
         ;;
      -g | --git-directory ) 
         git_directory="$2";
         ;;
      -w | --working-directory ) 
         working_directory="$2";
         ;;
      -t | --temp-dir )
         temp_dir="$2";
         ;;
      -s | --silent ) 
         quiet_time=true; 
         ;;
      -e | --error-only ) 
         only_log_error=true;
         ;;
      -i | --ignore ) 
         IGNORE_REGEX="$2";
         ;;
      -n | --number-scan-limit ) 
         limit_records="$2";
         ;;
      -f | --fail )
         fail_on_error=true;
         if [[ "$2" =~ ^[^-]$ ]]; then  
            error_limit="$2";
         else
            error_limit="-1";
         fi
         ;;
      -v | --verbose ) 
         verbose_logging=true;
         ;;
      -vv | --super-verbose ) 
         super_verbose_logging=true; verbose_logging=true;
         ;;
      -vvv | --ultra-mega-verbose ) 
         ultra_mega_verbose_logging=true;
         super_verbose_logging=true; 
         verbose_logging=true; 
         set -x;
         ;;
      --no-progress )
         show_progress=false;
         ;;
      --keep-temp-files )
         keep_temp_files=true;
         ;;
      -c | --cleanup )
         clean_all_files=true;
         keep_temp_files=false;
         ;;
      --skip-git-refresh )
         skip_git_refresh=true;
		   ;;
      --skip-cherry-check )
         skip_cherry_check=true;
         ;;
      --show-error-report-per )
         case "$2" in
            "file" )
               show_error_per_file=true;
               show_error_per_commit=false;
               ;;
            commit )
               show_error_per_file=false;
               show_error_per_commit=true;
               ;;
            none )
               show_error_per_file=false;
               show_error_per_commit=false;
               ;;
            * )
               show_error_per_file=true;
               show_error_per_commit=true;
         esac
         ;;
      -r | --repo )
         git_repo_url="$2";
         ;;
      --git-remote-name )
         git_remote_name="$2";
         ;;
      --blame )
         find_culprit=true;
         ;;
      --help )
         show_usage;
         exit 1;
         ;;
   esac
   shift
done

###
# Set default values for properties
###
if [ -z "$working_directory" -a "$working_directory" != " " ]; then working_directory="$(pwd)"; fi;
if [ -z "$git_directory" -a "$git_directory" != " " ]; then git_directory="$working_directory/gitrepo"; fi;
if [ -z "$parent_branch" -a "$parent_branch" != " " ]; then parent_branch="master"; fi;
if [ -z "$current_branch" -a "$current_branch" != " " ]; then current_branch="develop"; fi;
if [ -z "$verbose_logging" -a "$verbose_logging" != " " ]; then verbose_logging=false; fi;
if [ -z "$super_verbose_logging" -a "$super_verbose_logging" != " " ]; then super_verbose_logging=false; fi;
if [ -z "$temp_dir" -a "$temp_dir" != " " ]; then temp_dir="$working_directory/theOrphanage"; fi;
if [ -z "$orphan_log" -a "$orphan_log" != " " ]; then orphan_log="$working_directory/orphans-found.log"; fi;
if [ -z "$show_progress" -a "$show_progress" != " " ]; then show_progress=true; fi;
if [ -z "$limit_records" -a "$limit_records" != " " ]; then limit_records=0; fi;
if [ -z "$fail_on_error" -a "$fail_on_error" != " " ]; then fail_on_error=false; fi;
if [ -z "$skip_cherry_check" -a "$skip_cherry_check" != " " ]; then skip_cherry_check=false; fi;
if [ -z "$show_error_per_file" -a "$show_error_per_file" != " " ]; then show_error_per_file=true; fi;
if [ -z "$show_error_per_commit" -a "$show_error_per_commit" != " " ]; then show_error_per_commit=true; fi;
if [ -z "$keep_temp_files" -a "$keep_temp_files" != " " ]; then keep_temp_files=false; fi;
if [ -z "$skip_git_refresh" -a "$skip_git_refresh" != " " ]; then skip_git_refresh=false; fi;
if [ -z "$clean_all_files" -a "$clean_all_files" != " " ]; then clean_all_files=false; fi;
if [ -z "$find_culprit" -a "$find_culprit" != " " ]; then find_culprit=false; fi;
if [ -z "$git_remote_name" -a "$git_remote_name" != " " ]; then git_remote_name="origin"; fi;
if [ "$clean_all_files" = true ]; then keep_temp_files=false; fi;

# Initialize Log
echo "Logging to $orphan_log";
echo "Starting Commit Orphan Check " > $orphan_log;

# initialize fake JUnit results
mkdir "$working_directory/target" &>> $orphan_log;
mkdir "$working_directory/target/test-reports/" &>> $orphan_log;
if [[ "$show_error_per_file" = true ]]; then
   test_report_dir="$working_directory/target/test-reports/orphanedCommitsByFile.xml";
   log debug "test_report_dir = $test_report_dir";
   touch "$test_report_dir" &>> $orphan_log;
   echo "" > $test_report_dir;
fi
if [[ "$show_error_per_commit" = true ]]; then
   test_report_dir_commit="$working_directory/target/test-reports/orphanedCommitsByCommit.xml";
   log debug "test_report_dir_commit = $test_report_dir_commit";
   touch "$test_report_dir_commit" &>> $orphan_log;
   echo "" > $test_report_dir_commit;
fi 

# Exit if a required value is not set
if [ -z "$working_directory" -a "$working_directory" != " " ] || [ -z "$git_directory" -a "$git_directory" != " " ] || [ -z "$parent_branch" -a "$parent_branch" != " " ] || [ -z "$current_branch" -a "$current_branch" != " " ] || [ -z "$temp_dir" -a "$temp_dir" != " " ] || [ -z "$orphan_log" -a "$orphan_log" != " " ]; then 
   echo "A required variable is missing, exiting"; 
   exit 1; 
fi;

# reset counts
error_count=0;
count=0;
cherry_picked_count=0;
total_records=0;
if [ -f "$orphan_log" ]; then
   # get the last line of the file
   total_records=$(tail -1 $orphan_log);
fi
re='^[0-9]+$';
if ! [[ $total_records =~ $re ]] ; then
   #a random default value
   total_records=10000;
fi

# Create/Initialize 'working' and 'git-repo' directories
if [ ! -d "$temp_dir" ]; then
   mkdir $temp_dir &> $orphan_log;
else
   if [ ! -z "${temp_dir}" -a "${temp_dir}" != " " ]; then 
      rm -rf ${temp_dir}/*;
   fi
fi

if [ ! -d "$git_directory" ]; then
   mkdir $git_directory &> $orphan_log;
fi

# move to git directory, pull Branches
pushd $git_directory &>> $orphan_log; 

log info "Refresh Repository:"
log debug "git repo url = $git_repo_url";
if [ ! -z "$git_repo_url" -a "$git_repo_url" != " " ]; then
   echo -ne "Initializing repository, this may take a minute..."\\r;
   log debug "Remove repository";
   git rm -rf * &>> $orphan_log;
   rm -rf .git* &>> $orphan_log;
   log debug "clone the branch to bne analyzed";
   if [ "$super_verbose_logging" = true ]; then
      (git clone --no-tags --branch $current_branch $git_repo_url $git_directory) >> $orphan_log;
   else 
      if [ "$verbose_logging" = true ]; then
         (git clone --no-tags --branch $current_branch $git_repo_url $git_directory) &>> $orphan_log;
      else
         (git clone --no-tags --branch $current_branch $git_repo_url $git_directory) &>> /dev/null;
      fi
   fi 
else
   if [ "$skip_git_refresh" = false ]; then
      log debug "Chekout the current branch to bne analyzed";
      log debug " git checkout $current_branch";
      (git checkout $current_branch) &>> $orphan_log;
      log debug "Clean it up";
      log debug " git reset --hard $git_remote_name/$current_branch";
      (git reset --hard $git_remote_name/$current_branch) &>> $orphan_log;
      log debug " git pull";
      (git pull) &>> $orphan_log;
      log debug "fetech the history of the parent branch";
      log debug " git fetch $git_$git_remote_name $parent_branch";
      (git fetch $git_remote_name $parent_branch) &>> $orphan_log;
   fi
fi 
# Analyze logs
hash_list="";
FULL_BRANCH_LOG_RAW="${temp_dir}/full_branch_log";

# Retrieve the commit in which the current_branch was created 
# Ie. The start of the branch
HASH=$(git merge-base $git_remote_name/$parent_branch $current_branch);

# Git command to retrieve the log history since branch creation
GIT_LOG_RAW_COMMAND="git log --raw HEAD...$HASH";

###
# Get the branch log, save it to a file
###
log info "$GIT_LOG_RAW_COMMAND > $FULL_BRANCH_LOG_RAW";
$GIT_LOG_RAW_COMMAND > $FULL_BRANCH_LOG_RAW;

if [ "$ultra_mega_verbose_logging" = true ] ; then
   log info "Git Log Raw: ";
   log info "$(cat $FULL_BRANCH_LOG_RAW)";   
   log info " ";
fi

###
# Iterate through the files in the git repo
###
shopt -s globstar
CHERRY_MATCHES="";
CHERRY_PICKED="";

for FILE in ./**/*
do
   if [ -f "$FILE" ];
   then
      # Ignore File if matches IGNORE REGEX
      if [ ! -z "$IGNORE_REGEX" -a "$IGNORE_REGEX" != " " ]  && [[ "$FILE" =~ ^$IGNORE_REGEX$ ]]; then
         log info "Ignored $FILE using regex [^${IGNORE_REGEX}$]";
         continue;
      fi

      # "Clean" filename string to create working directory for file
      prefix="./";
      # remove "./" from the begining of the filename
      FILE=${FILE#$prefix};
      if [ "$only_log_error" = false ]; then
         log info "File found: $FILE";
      fi 
      # Sed : replace all '/' with '_'
      CLEAN_FILE=$(echo "$FILE" | sed -r 's/[\/.]/_/g');
      
      # Initialize file log variables for diff
      DIFF_DIR="${temp_dir}/$CLEAN_FILE";
      FULL_FILE_LOG_RAW="$DIFF_DIR/full_file_log";
      diff1="$DIFF_DIR/grep_branch_log";
      diff2="$DIFF_DIR/grep_file_log";
      diff_log="$DIFF_DIR/diff_log";
      
      # make directory for file specific logs and diff
      mkdir $DIFF_DIR;
   
      # Get the log from the individual file level
      $GIT_LOG_RAW_COMMAND -- $FILE > $FULL_FILE_LOG_RAW;
      
      # Extract the commits associated with the current file
      # from both the Full Branch Git Log and the File Git Log
      # Grep:
      #   '-P' stands for Perl regular expresion
      #   '-z' essentially ignores newlines
      #   '-o' output only the found sequences matching the pattern
      # Regex : (?s)\bcommit\b(?:(?!\bcommit\b).)*?\b\sFILENAME\b
      #   Simply put: Only retrieve the commit message from the log of commit 
      #      messages that contain the file-name. 
      #   Complexly put:   
      #      '(?s)' match the remainder of the pattern with the following effective flags: gms
      #         g modifier: global. All mathces (do not return after first match)
      #         m modifier: multi line. find across multiple lines
      #         s modifier: single line. Dot matches newline characters
      #      '\b' assert position at a word boundary (^\w|\w$|\W\w|\w\W)
      #      'commit' matches the characters 'commit' literally (case sensitive)
      #      '\b' assert position at a word boundary (^\w|\w$|\W\w|\w\W)
      #      Non-capturing group (?:(?!\bcommit\b).)*?
      #         '*?' Quantifier ÎíÎñ Matches between zero and unlimited times, as few times as possible, expanding as needed (lazy)
      #         Negative Lookahead (?!\bcommit\b) (*Assert that the Regex below does not match*)
      #            '\b' assert position at a word boundary (^\w|\w$|\W\w|\w\W)
      #            'commit' matches the characters commit literally (case sensitive)
      #            '\b' assert position at a word boundary (^\w|\w$|\W\w|\w\W)
      #         '.' matches any character
      #      '\b' assert position at a word boundary (^\w|\w$|\W\w|\w\W)
      #      '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
      #      '${FILE}' matches the filename variable passed in
      #      '\b' assert position at a word boundary (^\w|\w$|\W\w|\w\W)
      $(grep -Pzo "(?s)\bcommit\b(?:(?!\bcommit\b).)*?\b\s${FILE}\b" $FULL_BRANCH_LOG_RAW > ${diff1}_temp);
      $(grep -Pzo "(?s)\bcommit\b(?:(?!\bcommit\b).)*?\b\s${FILE}\b" $FULL_FILE_LOG_RAW > ${diff2}_temp);
   
      # Remove the filenames from the commit, to prepare for a diff call.
      #    This is done since the file log commit message only contains the 
      #    name of this file in the '--raw' message. The full branch log
      #    commit messages contain ALL files in a commit message when 
      #    '--raw' command is used. So all file referencesneed to be removed
      #    before calling diff
      # Regex: 
      #    '^' asserts position at start of a line
      #    '\:' matches the character : literally (case sensitive)
      #    '.+' matches any character (except for line terminators)
      #    '+' Quantifier ÎíÎñ Matches between one and unlimited times, as many times as possible, giving back as needed (greedy)
      #    '$' asserts position at the end of a line
      pattern="^\:.+$";
      grep -Pv "$pattern" ${diff1}_temp > $diff1;
      grep -Pv "$pattern" ${diff2}_temp > $diff2;
   
      # find the differences between the logs
      diff -w $diff1 $diff2 > $diff_log;
      DIFF_STRING=$(echo $(cat $diff_log)); 
   
      # weed out false positives that came from the earlier regex
      #    Some log files return just the word commit, due to the regex taht 
      #    retrieved them. This makes the diff return a '< commit <' message.
      #    If the diff matches the regex below, it is ignored. 
      false_positive_regex="^[0-9,a-zA-Z]*_<_commit_<_$";
	  

      # output the differences/errors
      if [ ! -z "$DIFF_STRING" -a "$DIFF_STRING" != " " ] && [[ ! $(echo "$DIFF_STRING" | tr ' \n' '__')  =~ $false_positive_regex ]]; then	
         if [ "$skip_cherry_check" = false ]; then
            FIND_CHERRY_LIST="";
            # Get List of potential cherry picked commits from diff
            # TODO: Test this to see if checking by "cherry picked from" works
            while IFS='' read -r line || [[ -n "$line" ]]; do
               # Regex :
               #   '\<' matches the character '<' literally (case sensitive)
               #   '\ ' matches the character ' ' literally (case sensitive)
               #   'commit' matches the characters 'commit' literally (case sensitive)
               #   '\ ' matches the character ' ' literally (case sensitive)
               #   Match a single character present in the list below [0-9a-zA-Z]*
               #      '*' Quantifier Matches between zero and unlimited times, as many times as possible, giving back as needed (greedy)
               #      '0-9' a single character in the range between 0 (index 48) and 9 (index 57) (case sensitive)
               #      'a-z' a single character in the range between a (index 97) and z (index 122) (case sensitive)
               #      'A-Z' a single character in the range between A (index 65) and Z (index 90) (case sensitive)
               #   '$' asserts position at the end of a line
               if [[ $line =~ \<\ commit\ [0-9a-zA-Z]*$ ]]; then
                  # Grep:
                  #   '-P' stands for Perl regular expresion
                  #   '-z' essentially ignores newlines
                  #   '-o' output only the found sequences matching the pattern
                  # Regex: (?<=< commit )[0-9a-zA-Z]*(?>=(?>=(\s\([\S\s]+\))|))
                  #   Positive Lookbehind (?<=< commit ) (*Assert that the Regex below matches*)
                  #      '< commit ' matches the characters '< commit ' literally (case sensitive)
                  #   Match a single character present in the list below [0-9a-zA-Z]*
                  #      '*' Quantifier Matches between zero and unlimited times, as many times as possible, giving back as needed (greedy)
                  #      '0-9' a single character in the range between 0 (index 48) and 9 (index 57) (case sensitive)
                  #      'a-z' a single character in the range between a (index 97) and z (index 122) (case sensitive)
                  #      'A-Z' a single character in the range between A (index 65) and Z (index 90) (case sensitive)
                  #   Atomic Group (?>=(?>=(\s\([\S\s]+\))|)) (*This group does not allow any backtracking to occur*)
                  #      '=' matches the character '=' literally (case sensitive)
                  #      Atomic Group (?>=(\s\([\S\s]+\))|) (*This group does not allow any backtracking to occur*)
                  #         1st Alternative =(\s\([\S\s]+\))
                  #         '=' matches the character '=' literally (case sensitive)
                  #            1st Capturing Group (\s\([\S\s]+\))
                  #               '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
                  #               '\(' matches the character '(' literally (case sensitive)
                  #               '[\S\s]+' Match a single character present in the brackets, at least once 
                  #               '\)' matches the character ) literally (case sensitive)
                  #         2nd Alternative null, matches any position
                  CHERRY_commit_hash=$(echo "$line" | grep -Pzo "(?<=< commit )[0-9a-zA-Z]*(?>=(\s\([\S\s]+\))|)");
                  # check for "Cherry picked from", files that were cherry picked with "git cherry-pick -x" option.
                  THIS_CHERRY_LINE=$(grep -Pzo "\(cherry picked from commit $CHERRY_commit_hash\)" ${diff2}_temp);
                  THIS_CHERRY_COUNT=$(grep -c "$CHERRY_commit_hash" ${diff1}_temp);
                  if [[ "$THIS_CHERRY_LINE" != "" ]] && [[ $THIS_CHERRY_COUNT -eq 2 ]]; then
                     CHERRY_PICKED="$CHERRY_PICKED,$CHERRY_commit_hash";
                     continue;
                  fi
                  if [[ $FIND_CHERRY_LIST != *"$CHERRY_commit_hash"* ]]; then
                     FIND_CHERRY_LIST="$FIND_CHERRY_LIST,$CHERRY_commit_hash";
                  fi
               fi
            done < "$diff_log";
            
            for i in $(echo "$FIND_CHERRY_LIST" | sed "s/,/ /g"); do
               # remove the first 2 characters from eac line in diff (figuratively
               sed 's/^..//' $diff_log > ${diff_log}_cleaned;
               
               # This gets the commit information for the Hash that I know (from diff file)
               commit_info="$(grep -Pzo "(?s)Author(.*?)(?=(commit|\[ ]*\(cherry picked from commit)|\Z)" ${diff_log}_cleaned)";
      
               # remove trailing while space
               commit_info="$(echo "$commit_info" | sed 's/\s*$//')";
               #commit_info="$(sed -e 's/[[:space:]]*$//' <<<${commit_info})";
         
               # grep main log for value from previous regex (pcregrep -M "$contact_info3" grep_branch_log)
               # pcregrep version of the line below: number_of_commits_in_branch_log="$(pcregrep -Mc "$commit_info" $diff1)";
               number_of_commits_in_branch_log="$(grep -Pzoc "$(echo $commit_info)" $diff1)";
               
               # grep file log for value from previous regex (pcregrep -M "$contact_info3" grep_branch_log)
               # pcregrep versionof the line below: number_of_commits_in_file_log="$(pcregrep -Mc "$commit_info" $diff2)";
               number_of_commits_in_file_log="$(grep -Pzoc "$(echo $commit_info)" $diff2)";
            
               if [[ $number_of_commits_in_branch_log -gt $number_of_commits_in_file_log ]]; then
                  #it may have been cherry picked; find all "same" commit data (author, date, message, etc, not commit id)
                  #   alt code 1: SUSPECTED_CHERRY_COMMITS=$(pcregrep -M "(?s)(?<=commit)\s[0-9a-zA-Z]*(?=(\s\([\S\s]+\)|\s+)(\s$commit_info)" $diff1 | grep -Pzo "(?<=commit )[0-9a-zA-Z]*(?>=(\s\([\S\s]+\))|)");
                  #   alt code 2:SUSPECTED_CHERRY_COMMITS=$(pcregrep -M "(?s)(?<=commit)\s[0-9a-zA-Z]*(?=(\s\([\S\s]+\)|\s+)(\s$(echo $commit_info))" $diff1 | grep -Pzo "(?<=commit )[0-9a-zA-Z]*(?>=(\s\([\S\s]+\))|)");
                  #
                  # Grep:
                  #   '-P' stands for Perl regular expresion
                  #   '-z' essentially ignores newlines
                  #   '-o' output only the found sequences matching the pattern
                  # Regex #1: ((?s)(?<=commit)\s[0-9a-zA-Z]*(?=(\s\([\S\s]+\)|\s+)(\sECHO__COMMIT_INFO))
                  #   (?s) match the remainder of the pattern with the following effective flags: gms
                  #      g modifier: global. All mathces (do not return after first match)
                  #      m modifier: multi line. find across multiple lines
                  #      s modifier: single line. Dot matches newline characters
                  #   Positive Lookbehind (?<=commit)
                  #      Assert that the Regex below matches
                  #      'commit' matches the characters 'commit' literally (case sensitive)
                  #   '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
                  #      Match a single character present in the list below [0-9a-zA-Z]*
                  #         '0-9' a single character in the range between 0 (index 48) and 9 (index 57) (case sensitive)
                  #         'a-z' a single character in the range between a (index 97) and z (index 122) (case sensitive)
                  #         'A-Z' a single character in the range between A (index 65) and Z (index 90) (case sensitive)
                  #         '*' Quantifier Matches between zero and unlimited times, as many times as possible, giving back as needed (greedy)
                  #      Positive Lookahead (?=(\s\([\S\s]+\)|\s+)(\s$(echo $commit_info)))
                  #         Assert that the Regex below matches
                  #         1st Capturing Group (\s\([\S\s]+\)|\s+)
                  #            1st Alternative \s\([\S\s]+\)
                  #               '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
                  #               '\(' matches the character ( literally (case sensitive)
                  #               Match a single character present in the list below [\S\s]+
                  #                  '\S' matches any non-whitespace character (equal to [^\r\n\t\f\v ])
                  #                  '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
                  #                  '+' Quantifier Matches between one and unlimited times, as many times as possible, giving back as needed (greedy)
                  #               '\)' matches the character ) literally (case sensitive)
                  #            2nd Alternative \s+
                  #               '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
                  #               '+' Quantifier Matches between one and unlimited times, as many times as possible, giving back as needed (greedy)
                  #         2nd Capturing Group (\sECHO__COMMIT_INFO)
                  #            '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
                  #            $(echo $commit_info) echos the variable $commit_info and matches it literally
                  #
                  # Regex #2: (?<=< commit )[0-9a-zA-Z]*(?>=(?>=(\s\([\S\s]+\))|))
                  #   Positive Lookbehind (?<=< commit ) (*Assert that the Regex below matches*)
                  #      '< commit ' matches the characters '< commit ' literally (case sensitive)
                  #   Match a single character present in the list below [0-9a-zA-Z]*
                  #      '*' Quantifier Matches between zero and unlimited times, as many times as possible, giving back as needed (greedy)
                  #      '0-9' a single character in the range between 0 (index 48) and 9 (index 57) (case sensitive)
                  #      'a-z' a single character in the range between a (index 97) and z (index 122) (case sensitive)
                  #      'A-Z' a single character in the range between A (index 65) and Z (index 90) (case sensitive)
                  #   Atomic Group (?>=(?>=(\s\([\S\s]+\))|)) (*This group does not allow any backtracking to occur*)
                  #      '=' matches the character '=' literally (case sensitive)
                  #      Atomic Group (?>=(\s\([\S\s]+\))|) (*This group does not allow any backtracking to occur*)
                  #         1st Alternative =(\s\([\S\s]+\))
                  #         '=' matches the character '=' literally (case sensitive)
                  #            1st Capturing Group (\s\([\S\s]+\))
                  #               '\s' matches any whitespace character (equal to [\r\n\t\f\v ])
                  #               '\(' matches the character '(' literally (case sensitive)
                  #               '[\S\s]+' Match a single character present in the brackets, at least once 
                  #               '\)' matches the character ) literally (case sensitive)
                  #         2nd Alternative null, matches any position
                  #
                  # Shortened Regex Description : 
                  #    The fisrt regex finds all commits mathing $commit_info, the second regex grabs the 'commit hash'
                  #    of the corresponding commit. Basically checking for matching cherry picked records within the branch.                  
                  SUSPECTED_CHERRY_COMMITS=$(grep -Pzo "(?s)(?<=commit)\s[0-9a-zA-Z]*(?=(\s\([\S\s]+\)|\s+)(\s$(echo $commit_info))" $diff1 | grep -Pzo "(?<=commit )[0-9a-zA-Z]*(?>=(\s\([\S\s]+\))|)");
                  
                  git show $i > ${diff1}_commit_show_suspect_$i;
                  for j in $SUSPECTED_CHERRY_COMMITS; do
                     if [ $i = $j ]; then
                        continue;
                     fi
                     # retrieves the full commit details (git show) of a specific commit
                     git show $j > ${diff1}_commit_show_person_of_interest_$j;
                     # compares the full commit details between the 2 commits to see if they are truely a match. 
                     diff ${diff1}_commit_show_suspect_$i ${diff1}_commit_show_person_of_interest_$j > ${diff1}_commit_show_diff_${i}_${j};
                     # Check the diff file for any lines not matching
                     #  - commit
                     #  - ---
                     #  - (cherry picked from commit
                     #  and other diff output such as @
                     ANY_DIFFS=$(grep -Pzo '^(?!(<|>) commit\s[0-9a-zA-Z]{40}|---|(<|>)\s{0,5}\(cherry picked from commit)(<|>)\s(-|@).*' ${diff1}_commit_show_diff_${i}_${j});
                     log info "$ANY_DIFFS";
                     # if there are no differences (minus the common diff output), it is a match.
                     if [ ! -z "$ANY_DIFFS" -a "$ANY_DIFFS" != " " ]; then
                        #if same (other than a few lines) add to CherryPicked variable
                        CHERRY_PICKED="$CHERRY_PICKED,$i";
                        if [[ $CHERRY_MATCHES != *"$i=$j"* ]]; then
                           # add matching git commits to be logged at the end
                           CHERRY_MATCHES="$CHERRY_MATCHES $i=$j";
                           cherry_picked_count=$(($cherry_picked_count + 1));
                        fi 
                     fi
                  done
               fi
            done
         fi 
         if [[ $CHERRY_MATCHES != *"$i"* ]]; then
            # output errors
            log info "File found with history errors: $FILE" true;
            log info "   Diff of '< Branch_log' and '> File_Log'" $show_error_per_file;
            while IFS='' read -r line || [[ -n "$line" ]]; do
               log info "      $line" $show_error_per_file;
               if [[ $line =~ \<\ commit\ [0-9a-zA-Z]*$ ]]; then
                  commit_hash=$(echo "$line" | grep -Pzo "(?<=< commit )[0-9a-zA-Z]*(?>=(\s\([\S\s]+\))|)");
                  ###
                  # Add to missing hash to hash_list if not already present
                  ###
                  if [[ $hash_list != *"$commit_hash"* ]]; then
                     hash_list="$hash_list $commit_hash";
                  fi 
               fi 
            done < "$diff_log";
            error_count=$(($error_count + 1));
            log info "Cherry picks found: $cherry_picked_count" $(! $skip_cherry_check);
            log info "Error File Number $error_count" $show_error_per_file;
            log info "###############################################################################" $show_error_per_file;
            log info "" $show_error_per_file;
            if [[ "$show_error_per_file" ]]; then
               test_file_report "$DIFF_DIR" "$diff_log" ;
            fi 
            # cleanup if flag is set
            if [ "$clean_all_files" = true ]; then
               rm -rf $DIFF_DIR;
            fi
         fi 
      else 
         # If no errors were found for this file, cleanup 
         # workign directory to simplify error research
         if [[ "$show_error_per_file" ]]; then
            test_file_report "$DIFF_DIR" "" ;
         fi 
         if [ "$keep_temp_files" = false ]; then
            rm -rf $DIFF_DIR;
         fi 
      fi

      # break loop if limit reached
      if [ ! -z "$limit_records" -a "$limit_records" != " " ] && [ $limit_records -gt 0 ] && [ $count -gt $limit_records ]; then
         break;
      fi

      # update the progress bar and file_count
      update_progress_bar;
      count=$(($count + 1));
      
      # break loop if limit reached
      if [ "$fail_on_error" = true ] && [ $error_limit -gt 0 ] && [ $error_count -gt $error_limit ]; then
         break;
      fi
   fi
done

# Show final output
show_final_output

popd &>> $orphan_log;

if [ "$find_culprit" = true ]; then
   echo $(pwd);
   echo "./find-culprits.sh -i '$hash_list' -b '$current_branch' -g '$git_directory';"
   . ./find-culprits.sh -i "$hash_list" -b "$current_branch" -g "$git_directory";
fi 
set +x;

# Exit with error code if errors are found
if [ "$fail_on_error" = true ] && [ $error_count -gt 0 ]; then
   exit 1;
fi 

exit 0;