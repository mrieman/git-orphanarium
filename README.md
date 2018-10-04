# git-orphanarium
A bash script that finds lost, or "orphaned" commits by recursivley checking each file's git log against the branches's main git log since the creation of the branch. The output is a log file (and optional sysout of the missing commits).

The basic steps used in the script are below. These can be used to find orphans manually, or make scripts in other languages:
1. Checkout Repository
2. Find th ecommon ancestor betwen the branch being analyzed, and th parent branch. This marks the branch creation (for the most part).
3. Retrieve the log from for the branch since beginning, cal it BRANCH_LOG.
4. For each file in the git repo: 
   - Get the log from the individual file level, call it FILE_LOG
   - Extract the commits associated with the current file from both the BRANCH_LOG and the FILE_LOG 
   - Run a Diff between the results. 
   - Exract any extra commits, from the diff, that are in the BRANCH_LOG, and not in the FILE_LOG.
   - Note/log these extra commits, they are "Orphaned"

## Attributes:
find-orphans.sh accepts the following attributes
```        
   -b | --analyze-branch <BRANCH NAME>
      REQUIRED
      The name of the git branch to be analyzed
         
   -p | --parent-brnach <PARENT BRANCH>
      REQUIRED
      Name of the branch from which the analyze-branch was created, This is used to find the first commit of the analyze-branch
      
   -g | --git-directory <PATH> 
      Sets the path to an existing git repository. If used in conjuction
	  with --repo, sets the location for the git clone.
	  DEFAULT: <WORKING DIRECTORY>/gitrepo
   
   -l | --log <PATH>
      Sets the location of the log file
	  DEFAULT: <WORKING_DIRECTORY>/orphans-found.log   

   -w | --working-directory <PATH>
      Sets the working directory for this scan
	  DEFAULT: <CURRENT DIRECTORY>

   -t | --temp-dir <PATH>
      Sets the location for temporaty files while scanning
	  DEFAULT: <WORKING DIRECTORY>/theOrphanage
   
   -r | --repo <URL>
      Sets the git repository url to pull from. If none set, no repo
	  will be cloned, and GIT_DIRECTORY will be scanned.   
	  	  
   -i | --ignore <REGEX>
      Skips files who's full path matches the regex

   -n | --number-scan-limit <NUMBER>
      Limits the number of files to be scanned

   -f | --fail [<NUMBER>]
      If present, the script will return an error code if errors exist.
	  Optional number will stop the script after NUMBER number of errors
	  appear.

   --git-remote-name 
      Sets the remote name for the git repository. Used in the 
	  'git refresh' step to pull the latest from the repository.
      Default: origin

   -e | --error-only  
      Limits logging to include only the missing commits
	  
   --no-progress
      Stops the progress bar from displaying
	  
   --keep-temp-files 
      Keeps all temporary files. By default, the script only retains 
	  temporary files for the scans resulting in error
	  
   -c | --cleanup
      Remove all temporary files. By default, the script only retains 
	  temporary files for the scans resulting in error
	  
   --skip-git-refresh 
      Stops the 'git refresh' step to pull the latest code from the 
	  origin repository.
	  
   --skip-cherry-check
      UNTESTED
	  Skips the 'check for cherry picked commits' step.
	  This is untested, and may not work. 
	  
   --show-error-report-per (file|commit|none)
      Limits the 'faked unit test' error files created. 
	  DEFAULT: 2 files will be created.
	  
   --blame 
      Runs 'find-orphans.sh' if errors exist
	  
   -s | --silent
      No console output
	  
   -v | --verbose 
      Displays 'debug' statements. ie. voice calm but full of infomration, like your mom when you did something stupid.
	  
   -vv | --super-verbose 
      Dipslays more console output. ie. Louder like your manager 
	  when you don't meet artificial deadlines that you had no 
      say in setting. 	  
	  
   -vvv | --ultra-mega-verbose
      Displays way too much information. ie. Much louder, like your
	  dad after you did something that you knew was Stoopid.
	  
   --help 
      Displays help
```
