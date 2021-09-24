#!/bin/bash

## Get the list of all the projects from Bitbucket account across all the pages
get_total_project_list () {
   	start=0
   	total_project_list=()
   	is_last_page=false
	while ! $is_last_page
	do
		response=$(curl -k -u $u -X GET -H "Content-type: application/json" $bitbucket_url/rest/api/1.0/projects?start=$start) 2>&1
		is_last_page=$(echo "${response}" | tr '\r\n' ' ' | jq '.isLastPage')
		partial_project_list=$(echo "${response}" | tr '\r\n' ' ' | jq '.values[].key' | sed -e 's/"//g')
		start=$(echo "${response}" | tr '\r\n' ' ' | jq '.nextPageStart')
		total_project_list=("${total_project_list[@]}" "${partial_project_list[@]}")
	done
}


## Get the list of all repositories from each project listed above across the pages
get_total_repository_list() {
	echo ">>> Project is: $1"
	start=0
	total_repo_list=()
	is_last_page=false

	while ! $is_last_page
	do
		response=$(curl -k -u $u -X GET -H "Content-type: application/json" $bitbucket_url/rest/api/1.0/projects/$1/repos?start=$start) 2>&1
		is_last_page=$(echo "${response}" | tr '\r\n' ' ' | jq '.isLastPage')
		partial_repos_lists=$(echo "${response}" | tr '\r\n' ' ' | jq '.values[].name' | sed -e 's/"//g')
		start=$(echo "${response}" | tr '\r\n' ' ' | jq '.nextPageStart')
		total_repo_list=("${total_repo_list[@]}" "${partial_repos_lists[@]}")
	done
}



## Find the branches which are merged and older than 30 days to be deleted
delete_branch_if_merge_longer_than_30_days() {

	branch=$1
	last_commit=`git show --format="%ct" origin/$branch | head -1`
	last_merge=`git log -i --grep="Merge" --grep="$branch" --all-match --format="%ct" | head -1`
	
	if [ "$last_commit" \> "$last_merge" ] || [ -z "$last_commit" ] || [ -z "$last_merge" ]
	then
		echo -e "\\033[0;32m>>> SKIPPING: $branch has unmerged commits\e[0m"
	else
		odate=`git log -i --grep="Merge" --grep="$branch" --all-match --format="%ci" | head -1 | cut -c 1-10`
		cdate=`date +%F`
		merged_date=`date -d "$odate" +%s`
		today=`date -d "$cdate" +%s`
		ddiff=`echo "$(((today-merged_date)/86400))"`
		
		if [[ "$ddiff" -gt 30 ]]
		then
			echo -e "\\033[0;32m>>> DELETE: $branch > 30 DAYS\e[0m"
			echo "$project_key/$repository_key/$branch" >> /tmp/branches_deleted
			# git push origin --delete $branch
		else
			echo -e "\\033[0;32m>>> SKIPPING: $branch recently merged (<30 DAYS)\e[0m"
		fi
	fi
}

## List all branches per repository to match the condition of merged and 30 days older
check_branches_by_repository() {
	project_key=$1
	repository_key=$2

	if [[ -d "$repository_key" ]]
	then
		cd $repository_key
		git pull
		cd ../
	else
		git clone https://git.example.com/scm/$project_key/$repository_key.git
	fi
	cd $repository_key
	git checkout master
	git branch -r --merged master | egrep -v "^\*|master|HEAD|dev|release" | sed -e 's/  origin\///g' > /tmp/br_$repository_key

	for branch in `cat /tmp/br_$repository_key`
	do
		delete_branch_if_merge_longer_than_30_days $branch
	done
	
	cd ../
	rm -rf $repository_key
	rm -rf /tmp/br_$repository_key
}

## Variables defined
bitbucket_url=“https://git.example.com”
read -p "Enter your Bitbucket username: " u
# List of projects
get_total_project_list
echo ">>> total_project_list is: ${total_project_list[@]}"

for pkey in ${total_project_list[@]}
do
	get_total_repository_list $pkey
	echo ">>> total_repo_list is: ${total_repo_list[@]}"
	for rkey in ${total_repo_list[@]}
	do
		check_branches_by_repository $pkey $rkey
	done
done
echo -e "\\033[0;32m>>> Deleting temporary files\e[0m"
