#!/bin/bash

##############################################################################
# A shell script that takes a list of commit hash and follows the log 
# to find where it becomes an orphan.
# Regex explinations are modified explinations from https://regex101.com/
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

###
# This is a logging function
###
function log() {
   if [ "$1" = "info" ]; then
      echo " $1: ${2}" >> $blame_log;
   else 
      if [ "$verbose_logging" = true ] && [ "$1" = "debug" ]; then
         echo "$1: ${2}" >> $blame_log;
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

current_file_previous_percent=-1;
current_file_percent=0;
current_file_total=0;
current_file_count=0;

current_commit_previous_percent=-1;
current_commit_percent=0;
current_commit_total=0;
current_commit_count=0;
progress_string="";
function update_progress_bar() {
   if [ $count -gt $total_records ]; then
      total_records=$count;
	   extra_progress_info="(file count exceeds $total_records)";
   fi
   if [ "${1}" = true ]; then
      total_records=$count;
      current_commit_total=2;
      current_commit_count=2;
      current_file_total=2;
      current_file_count=2;
   fi
   if [ "${1}" = true ] || [ "$show_progress" = true ]; then
      if [ $count -gt 0 ]; then
         percent=$(( 200 * $count / $total_records % 2  +  100 * $count / $total_records ));
      fi
      if [ $current_file_count -gt 0 ]; then
         current_file_percent=$(( 200 * $current_file_count / $current_file_total % 2  +  100 * $current_file_count / $current_file_total ));
      fi
      if [ $current_commit_count -gt 0 ]; then
         current_commit_percent=$(( 200 * $current_commit_count / $current_commit_total % 2  +  100 * $current_commit_count / $current_commit_total ));
      fi
      if [ $percent -gt $previous_percent ] || [ $current_file_percent -gt $current_file_previous_percent ] || [ $current_commit_percent -gt $current_commit_previous_percent ] || [ $error_count -gt $previous_error_count ]; then
         progress_string="Total: "
         update_progress_string $percent;
         progress_string="$progress_string, Check Commit: "
         update_progress_string $current_file_percent;
         progress_string="$progress_string, Traverse History: "
         update_progress_string $current_commit_percent;
         
         echo -ne "$progress_string"\\r;
         previous_percent=$percent;
         previous_error_count=$error_count;
         current_file_previous_percent=$current_file_percent;
         current_commit_previous_percent=$current_commit_percent;
      fi
   fi
   if [ "${1}" = true ] ; then
      echo "$(printf "%0.s " {1..${#progress_string}})";
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
   progress_string="${progress_string}| ${extra_space}${ps_percent}%";
}

function setup_progress_bar() {
   total_records=$1;
   count=0;
}

################
# OVERVIEW:
# 1) Accept
#     - branch
#     - list of commit hash 
# 2) process
#     - translate list into map of orphaned hash/files (space seperated list of entries, 
#        comma #seperated files, colon for key value seperateion 
#        hash:file,file,file;hash:file;hash:file,file
#     - for each entry
#        -- get the ancestorial history from the commit to HEAD (like the gitk thing)
#        -- traverse each commit, one by one
#           --- checkout that commit
#           --- check file log for missing commit
#              ---- if found, contiue to next commit
#              ---- if not found, flag this commit as the culprit.
###############

# 1) Accept
#     - branch
#     - list of orphaned hash (comma seperated list of entries)

while test $# -gt 0
do
   case "$1" in
      -b | --branch )
         # REQUIRED
         # branch name
         current_branch="$2";
         ;;
      -i | --input-map ) 
         # REQUIRED
         orphan_list="$2";
         ;;
      -l | --log )
         # log file name
         blame_log="$2";
         ;;
      -g | --git-directory ) 
         git_directory="$2";
         ;;
      -w | --working-dir )
         working_directory="$2";
         ;;
      --no-progress )
         show_progress=false;
         ;;
      -r | --repo )
         git_repo_url="$2";
         ;;
      -o | --git-remote-origin )
         git_remote_name="$2";
         ;;
      -n | --no-suspect-message )
         no_suspect_message="$2";
         ;;
      --help )
         show_usage;
         exit 1;
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
   esac
   shift
done

###
# Set default values for properties
###
if [ -z "$working_directory" -a "$working_directory" != " " ]; then working_directory="$(pwd)/working_dir"; fi;
if [ -z "$git_directory" -a "$git_directory" != " " ]; then git_directory="$working_directory/gitrepo"; fi;
if [ -z "$blame_log" -a "$blame_log" != " " ]; then blame_log="$working_directory/BlameLog.log"; fi;
if [ -z "$show_progress" -a "$show_progress" != " " ]; then show_progress=true; fi;
if [ -z "$git_remote_name" -a "$git_remote_name" != " " ]; then git_remote_name="origin"; fi;
if [ -z "$verbose_logging" -a "$verbose_logging" != " " ]; then verbose_logging=false; fi;
if [ -z "$super_verbose_logging" -a "$super_verbose_logging" != " " ]; then super_verbose_logging=false; fi;
if [ -z "$ultra_mega_verbose_logging" -a "$ultra_mega_verbose_logging" != " " ]; then ultra_mega_verbose_logging=false; fi;
if [ -z "$no_suspect_message" -a "$no_suspect_message" != " " ]; then no_suspect_message="All in working order, please check ccommit again"; fi;

# Exit if a required value is not set
if [ -z "$current_branch" -a "$current_branch" != " " ] ; then 
   echo "The needed variable '-b | --branch' is missing, exiting"; 
   exit 1
fi 
if [ -z "$orphan_list" -a "$orphan_list" != " " ] ; then 
   echo "The needed variable '-i | --input-map' is missing, exiting"; 
   exit 1; 
fi;

if [ "$git_directory" = "$working_directory" ]; then 
   echo "Specify a Git directory that is diferent than the Working directory"; 
   exit 1;
fi

# Initialize Log
echo "Logging to $blame_log";
mkdir "$working_directory" &>> /dev/null;
echo "Starting Orphaned-Commit Blame Check " > $blame_log;

START_TIME=$SECONDS;

log debug "move to git directory";
pushd $git_directory;
###
# Clone repo if specified
###
if [ ! -z "$git_repo_url" -a "$git_repo_url" != " " ]; then
   echo -ne "Initializing repository, this may take a minute..."\\r;
   log debug "\nRemove repository";
   git rm -rf * >> $blame_log;
   rm -rf .git* >> $blame_log;
   log debug "clone the branch to bne analyzed";
   if [ "$super_verbose_logging" = true ]; then
      (git clone --no-tags --branch $current_branch $git_repo_url $git_directory) >> $blame_log;
   else 
      if [ "$verbose_logging" = true ]; then
         (git clone --no-tags --branch $current_branch $git_repo_url $git_directory) &>> $blame_log;
      else
         (git clone --no-tags --branch $current_branch $git_repo_url $git_directory) &>> /dev/null;
      fi
   fi 
fi

declare -A hashMap;
log debug "Create Hash mapping"
for commit_hash in $orphan_list; do
   hash_info=$(git log -p $commit_hash -1 --name-only --oneline | tr '\n' '@' | sed 's/^[^\@]*\@//' | tr '@' ' ' | sed 's/\(.*\),/\1 /');
   hashMap[$commit_hash]+="$hash_info";
#   orphan_map="${commit_hash}:$hash_info $orphan_map";
done;
log debug "Orphan map is now: $orphan_map";

log debug "Process input hash mapping";

declare -A suspectMap;
log debug "hashMap = $hashMap";

log debug "setup progress bar using the number of hashmap records to scan for";
orphan_words=( $orphan_list );
log debug "number of orphaned commits = ${#orphan_words[@]}";
setup_progress_bar ${#orphan_words[@]};

log debug "for each hash-to-file mapping loop using the key"
for i in $orphan_list; do 
   filesInCommit="${hashMap[$i]}";
   words=( $filesInCommit );
   current_file_total=$((${#words[@]} * 3));
   current_file_count=0;
   update_progress_bar;
   for j in ${hashMap[$i]}; do
      log info "   Checking history for missing hash $i and file $j ";
      # retrieve the ancestory-path, or commit history, from the commit to the head revision 
      # only outpuyt the lines that contain the commit hash (pretty=format:"%H")
      # grap only the commit hash from the line (remove special characters) (grep -woe "\s{40}")
      # transform list to space sperated, rather than line seperated (tr '\n' ' ')
      git reset --hard origin/$current_branch &>> $blame_log;
      current_file_count=$(($current_file_count + 1));
      update_progress_bar;
      
      hash_hisotry=$(git log --graph --pretty=format:"%H" --ancestry-path $i..HEAD -- $j | grep -woE '\w{40}' | tr '\n' ' ');
      log debug "   hash_history raw: $hash_hisotry";
      # reverse hash to be from oldest to newest
      hisotry_desc=$(echo $hash_hisotry | awk '{ for (k=NF; k>1; k--) printf("%s ",$k); print $k; }');
      log debug "   hash history cronological order: $hisotry_desc";
      current_file_count=$(($current_file_count + 1));
      update_progress_bar;
      
      commit_words=( $hisotry_desc );
      current_commit_total=$((${#commit_words[@]} * 3));
      current_commit_count=0;
      update_progress_bar;
      #loop through the hash history
      for child in $hisotry_desc; do
         # skip this evaluation if the history_hash is the same as the one beign evaluated
         if [ "$child" = "$i" ]; then
            log debug "      Skipping $1";
            current_commit_count=$(($current_commit_count + 3));
            update_progress_bar;
            continue;
         fi
         log debug "      checkout the branch at the time of the history commit $child";
         git reset --hard origin/$current_branch &>> $blame_log;
         current_commit_count=$(($current_commit_count + 1));
         update_progress_bar;
         
         git checkout $child &>> $blame_log;
         current_commit_count=$(($current_commit_count + 1));
         update_progress_bar;
         
         log debug "      look for hash at the file level"
         commit_exist=$(git log -- $j | grep $i);
         log debug "      commit exists = $commit_exist";
         # if it does not exists, this commit is the culprit
         if [ -z "$commit_exist" -a "$commit_exist" != " " ]; then
            log info "      $i was overwritten by $child";
            # book'm dann'o
            suspectMap[$i]="$child";
            break 2;
         fi
         log debug "      No Porblem foun with: $child";
         current_commit_count=$(($current_commit_count + 1));
         update_progress_bar
      done
      current_file_count=$(($current_file_count + 1));
      update_progress_bar;
   done 
   # if no matching commit is found, log it
   if [ -z "${suspectMap[$i]}" -a "${suspectMap[$i]}" != " " ]; then 
      log debug "   $i did not find an offending culprit";
      suspectMap[$i]="$no_suspect_message";
   fi
   count=$(($count + 1));
   update_progress_bar;
done;

detailed_result_file="$working_directory/who_dunnit_with_history";
result_file="$working_directory/who_dunnit";
echo "" > $result_file;
echo "" > $detailed_result_file;
update_progress_bar true; echo "";
for m in $orphan_list; do 
   log info "Commit $m was overritten by [ ${suspectMap[$m]} ]" true;
   echo "$m=${suspectMap[$m]}" >> $result_file;
   echo $(git log --graph --pretty --ancestry-path $m..HEAD) >> $detailed_result_file;
   echo "\n#############################################################\n" >> $detailed_result_file;
done

set +x;

echo "";

exit 0;