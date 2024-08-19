#!/bin/bash

# This script is used to manage github tickets in a project
ttik() {
    check_yes_no_internal() {
    while true; do
        sleep 0.1
        # check which shell is being used
        if [ -n "$BASH_VERSION" ]; then
            read -p "$1" yn
        elif [ -n "$ZSH_VERSION" ]; then
            vared -p "$1" -c yn
        fi
        # read -p "$1" yn
        if [ "$yn" = "" ]; then
            yn='Y'
        fi
        case "$yn" in
        [Yy]) return 0 ;;
        [Nn]) return 1 ;;
        *) echo -n "Not a valid option. Please enter y or n: " ;;
        esac
    done
}
    show_help() {
        echo "ttik"
        echo "Checks and changes the status of tickets on github"
        echo "The tickets will be checked in the current directory's git repo"
        echo ""
        echo "Usage: ttik [flags]"
        echo ""
        echo "Flags"
        echo ""
        echo "-h, --help: Show help"
        echo ""
        echo "-a, --all: Show all tickets, otherwise don't show done tickets"
        ehco ""
        echo "-l, --list: List all tickets in the current project"
        echo ""
        echo "-o, --options: Show all status options"
        echo ""
        echo "Tickets can be searched by fuzzy searching"
        echo "Selecting a ticket will move on to the next step where you can manipulate the ticket"
        echo "The ticket can be moved to a different status column, or closed"
        echo "The ticket can be assigned to a user, @me will assign it to you"
        return 0
    }
    show_all=false
    only_list=false
    for arg in "$@"; do
        case $arg in
        -h | --help)
            show_help
            return 0
            ;;
        -a | --all)
            show_all=true
            ;;
        -l | --list)
            only_list=true
            ;;
        -o | --options)
            all_options=true
            ;;
        -la | -al)
            show_all=true
            only_list=true
            ;;
        -lo | -ol)
            only_list=true
            all_options=true
            ;;
        -ao | -oa)
            show_all=true
            all_options=true
            ;;
        -lao | -loa | -alo | -aol | -ola | -oal)
            show_all=true
            only_list=true
            all_options=true
            ;;
        *)
            echo "Invalid flag $arg"
            return 1
            ;;
        esac
    done

    if [ $show_all = true ]; then
        show_issues="all"
    else
        show_issues="open"
    fi

    # check if token is set
    if [ -z "$TEA_TOKEN" ]; then
        # let th user enter the token and set it
        read -sp "Please enter your token: " my_token
        echo
    fi
    # set the token
    export TEA_TOKEN="$my_token"
    
    gh_name=$(git config user.name)
    
    touch "/tmp/$gh_name.tea_cookies.txt"
    chmod 600 "/tmp/$gh_name.tea_cookies.txt"
    
    repo_url=$(git remote get-url origin)
    repo_url=$(echo $repo_url | sed -E 's/(https:\/\/|git@)//g' | sed -E 's/(\/|:).*//')

    repo_owner=$(git remote get-url origin | sed -E 's/(https:\/\/|git@)([a-zA-Z0-9\-\.]*)(:|\/)//g' | sed 's/\/.*//')
    
    repo_name=$(basename $(git rev-parse --show-toplevel))

    get_login_page=$(curl -s -i -k 'GET' \
    'https://'"$repo_url"'/user/login' \
    -c "/tmp/$gh_name.tea_cookies.txt" \
    -b "/tmp/$gh_name.tea_cookies.txt" \
    -H 'accept: text/html,application/xhtml+xml,application/xml')
    
    # this gets the repo and it's projects
    get_project_request=$(curl -s -i -k 'GET' \
        'https://'"$repo_url"'/'"$repo_owner"'/'"$repo_name"'/projects' \
        -b "/tmp/$gh_name.tea_cookies.txt" \
        -c "/tmp/$gh_name.tea_cookies.txt" \
        -H 'accept: text/html,application/xhtml+xml,application/xml' 
    )
    
    # get response code
    response_code=$(echo "$get_project_request" | grep -oP "HTTP\/[0-9\.]+ \K[0-9]{3}" | head -n 1)
    if [ "$response_code" == "404" ]; then # if we get a 404 then we need to login
        echo "You need to login to Gitea"
        # ask for password
        read -sp "Please enter your gitea password:" gtpw
        # new line
        echo
          login_response=$(curl -s -i -L 'https://'"$repo_url"'/user/login' \
          -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' \
          -H 'Content-Type: application/json' \
          -b "/tmp/$gh_name.tea_cookies.txt" \
          -c "/tmp/$gh_name.tea_cookies.txt" \
          -d '{
              "UserName": "'"$gh_name"'",
              "Password": "'"$gtpw"'"
          }' \
          --compressed \
          --insecure)
        response_code=$(echo "$login_response" | grep -oP "HTTP\/[0-9\.]+ \K[0-9]{3}" | head -n 1)
        echo "Login response code $response_code"
        if [ "$response_code" != "303" ]; then
            echo "Login failed"
            echo "$login_response"
            return 1
        fi
        if [ $(echo "$login_response" | wc -l) -lt 350 ]; then
            echo "Login failed, page too short"
            echo "$login_response"
            return 1
        fi
        
        get_project_request=$(curl -s -i -k 'GET' \
            'https://'"$repo_url"'/'"$repo_owner"'/'"$repo_name"'/projects' \
            -H 'accept: text/html,application/xhtml+xml,application/xml' \
            -b "/tmp/$gh_name.tea_cookies.txt" \
            -c "/tmp/$gh_name.tea_cookies.txt" \
        )
        

    fi
    project_id=$(echo $get_project_request | grep -oP 'href=".*projects\/\K\d+' | head -n 1)

    # TODO: rename
    remaining_string=$(echo $get_page_request | sed  's/project-column-issue-count\"> [0-9]\+ <\/div> /project-column-issue-count\"><\/div> /')

    declare -A columns

    # iterate until remaining_string is empty
    while [ -n "$remaining_string" ]; do
        old_string=$remaining_string
        remaining_string=${remaining_string#*ui segment project-column}

        if [ "$old_string" == "$remaining_string" ]; then
            break
        fi

        variable2=${remaining_string#*data-id=\"}
        # echo "variable2 $variable2"
        column_id=$(echo $variable2 | sed -n 's/^\([0-9]\{1,2\}\).*/\1/p')
        remaining_string=${remaining_string#*div> } 
        column_name=$(echo $remaining_string | sed 's/ <\/div>.*//')

        columns[$column_name]=$column_id
    done
    
    issues=$(curl -s -k 'GET' \
      'https://'"$repo_url"'/api/v1/repos/'"$repo_owner"'/'"$repo_name"'/issues?state='"$show_issues"'' \
      -H 'accept: application/json' \
      -H 'Authorization: token '"$my_token" \
      -H 'Content-Type: application/json')
    
    # now we need to get the issues from the project page to get the columns
    get_project_page=$(curl -s -i -k 'GET' \
        'https://'"$repo_url"'/'"$repo_owner"'/'"$repo_name"'/projects/'"$project_id"'' \
        -H 'Accept: text/html,application/xhtml+xml,application/xml' \
        -b "/tmp/$gh_name.tea_cookies.txt" \
        -c "/tmp/$gh_name.tea_cookies.txt" \
        )

    colunns_headers=$(echo $get_project_page | grep -n -oP "project-column-issue-count\">" | cut -d ":" -f 1 | tac)
    # we build a json array of issues
    issues_to_columns="[]"
    while IFS= read -r colunn_header; do
            colunn_name=$(echo $get_project_page | tail -n +"$((colunn_header + 3))" | head -n 1 | sed 's/^[[:space:]]*//g')
            # now we get the issues
            issues_section=$(echo $get_project_page | tail -n +"$((colunn_header + 3))")
            # the project page has the issues listed in the following format
            issues_numbers=$(echo $issues_section | grep -oP 'href="/'"$repo_owner"'/'"$repo_name"'/issues/\K\d+')
            if [ -z "$issues_numbers" ]; then
                continue
            fi
            # now we add the issues to the array
            while IFS= read -r issue; do
                # add the issue to the issues_to_columns array
                issue_to_add="{\"number\":$issue,\"issueState\":\"$colunn_name\"}"
                issues_to_columns=$(echo $issues_to_columns | jq  ". += [$issue_to_add]")
            done <<< "$issues_numbers"
            # cut that section out of the page
            get_project_page=$(echo $get_project_page | head -n $((colunn_header + 3)))
    done <<< "$colunns_headers"
    

    # Combine issues and issues_to_columns
    combined_issues=$(jq -n --argjson issues "$issues" --argjson issues_to_columns "$issues_to_columns" ' [$issues[] as $i | $issues_to_columns[] | select(.number == $i.number) | $i + {issueState: .issueState}] ')
    
    # if only listing, print and exit
    if [ "$only_list" = true ]; then
        if [ "$show_all" = true ]; then
            # we now use the combined issues array
            echo "$combined_issues" | jq -r '.[] | {number, title, issueState, labels[].name, state, assignees, createdAt}' | sed 's/null/-/g' | sort -t ';' -k 3 -r | column -s$';' -t
        else
            echo "$combined_issues" | jq -r '.[] | {number, title, issueState, labels[].name, state, assignees, createdAt}' | sed 's/null/-/g' | sort -t ';' -k 3 -r | awk -F ';' '$3 != "Done" && $3 != "done"' | column -s$';' -t
        fi
        return 0
    fi
    # print the issues
    if [ "$show_all" = true ]; then
        # show the 5th column (status)
        issuei="$(echo "$combined_issues" | jq -r '.[] | "\(.number);\(.title);\(.issueState);\(.labels[].name);\(.state);\(.assignees);\(.created_at)"' | sed 's/null/-/g' | sort -t ';' -k 3 -r | column -s$';' -t | fzf)"
    else
        issuei="$(echo "$combined_issues" | jq -r '.[] | "\(.number);\(.title);\(.issueState);\(.labels[].name);\(.state);\(.assignees);\(.created_at)"' | sed 's/null/-/g' | sort -t ';' -k 3 -r | awk -F ';' '$3 != "Done" && $3 != "done"' | column -s$';' -t | fzf)"
    fi
    if [ -z "$issuei" ]; then
        echo "No issue selected"
        return 0
    fi
    issue_num=${issuei%% *}
    # echo "issue_num $issue_num"
    # we grab the issue from the combined issues json, we know it's number is $issue_num and it is at the beginning of the line
    full_issue=$(echo "$combined_issues" | jq -r '.[] | "\(.number);\(.title);\(.issueState);\(.labels[].name);\(.state);\(.assignees);\(.created_at);\(.repository.full_name);\(.url);\(.body)"' | sed 's/null/-/g' | grep -w "^$issue_num")
    # | column -s$';' -t)
    issue_body=$(echo "$full_issue" | awk -F ';' '{print $10}')
    indent="    "  # 4 spaces
    indented_body=$(echo "$issue_body" | fold -s -w 80 | sed "s/^/$indent/")
    echo "$indented_body"

    # print the issue nicely, first line is the issue title, repo name and number
    echo "$full_issue" | awk -v indented_body="$indented_body" -F ';' '{printf "\033[1m%s\033[0m %s#%s\n%s - %s\n\nAssignees:%s\n\n%s\n\n%s\n", $2, $8, $1, $5, $3, $6,indented_body, $9}'
    # echo "$full_issue"
    return 0
    # print the issue
    # get the state
    issue_state=$(printf '%s\n' "${issues_arr[$issue_num]}" | cut -d ";" -f 5)
    issue_name="$(printf '%s\n' "${issues_arr[$issue_num]}" | cut -d ";" -f 2)"
    current_column="$(printf '%s\n' "${issues_arr[$issue_num]}" | cut -d ";" -f 3)"

    project_field_id="$(gh api graphql -f project="$project_id" -f query='
    query($project: ID!) {
        node(id: $project) {
            ... on ProjectV2 {
                fields(first: 100) {
                        nodes {
                            ... on ProjectV2SingleSelectField {
                                id
                                name
                                options {
                                    id
                                    name
                                }
                            }
                        }
                    }
                }
            }
        }')"

    status_field_id=${project_field_id#*\"id\":\"}
    status_field_id=${status_field_id%%\"*}
    status_options=${project_field_id#*\"options\":\[}
    status_options=${status_options%%\]*}

    declare -a status_array
    counter=0
    while [[ $status_options == *"\"id\":\""* ]]; do
        option_id=${status_options#*\"id\":\"}
        option_id=${option_id%%\"*}
        status_options=${status_options#*\"id\":\"$option_id\"}

        option_name=${status_options#*\"name\":\"}
        option_name=${option_name%%\"*}
        
        # if the --options flag is set, show all options
        if [ "$all_options" = true ]; then
            status_array[$counter]=$option_id"-"$option_name
            counter=$((counter + 1))
        else
            if [ "$option_name" == "in progress" ] || [ "$option_name" == "In Progress" ] || [ "$option_name" == "sprint backlog" ] || [ "$option_name" == "Sprint Backlog" ] ; then
                status_array[$counter]=$option_id"-"$option_name
                counter=$((counter + 1))
            fi
        fi

    done
    if [ "$all_options" = true ]; then
        # if the issue is not closed, show the status options
        if [ "$issue_state" != "CLOSED" ]; then
            status_array[$((counter + 1))]="none-Close issue"
        fi
        status_array[$((counter + 3))]="none-Assign"
    fi
    status_array[$((counter + 2))]="none-Jump to branch"
    # let the user choose the status

    status=$(printf '%s\n' "${status_array[@]}" | cut -d "-" -f 2- | fzf)

    if [ "$status" == "$current_column" ]; then
        echo "No change"
        return 0
    elif [ "$status" == "Close issue" ]; then
        check_yes_no_internal "Close issue $issue_name? [Y/n]: "
        gh issue close $issue_num
        return 0
    elif [ "$status" == "Jump to branch" ]; then
        branches="$(compgen -F __git_wrap_git_checkout 2>/dev/null | grep -vE 'HEAD|origin/*|FETCH_HEAD|ORIG_HEAD')"
        branches="$(echo "$branches" | sort -u)"
        branches="$(echo "$branches" | sed 's/^/  /')"
        branch_name="$(echo "$branches" | grep $issue_num)"
        if [ -z "$branch_name" ]; then
            echo "No branch $branch_name found"
            return 0
        fi
        git checkout $branch_name
        return 0
    #  let the user choose the assignees
    elif [ "$status" == "Assign" ]; then
        #     # get people on the project
        # let the user enter the assignee in the command line, listen for enter
        echo "Enter assignee: "
        read assignee
        if [ -z "$assignee" ]; then
            echo "No assignee selected"
            return 0
        else
            issue_assigned=$(gh issue edit $issue_num --add-assignee $assignee)
            if [ -z "$issue_assigned" ]; then
                echo "Issue not assigned"
                return 1
            else
                return 0
            fi
        fi
    fi

    if [ -z "$status" ]; then
        echo "No status selected"
        return 0
    elif [ "$status" != "Done" ] && [ "$status" != "done" ] && [[ "$status" != *"acklog" ]] && [ -z "$(echo "${issues_arr[$issue_num]}" | grep "nocode\|epic")" ]; then
        #remove  [0-9]+ from $issue_name
        issue_name=$(echo $issue_name | sed 's/^\[[0-9]\+\] //')
        branch_name=$issue_num"-"$issue_name
        #substitute all spaces with dashes
        branch_name=${branch_name// /-}
        # remove all non-alphanumeric characters
        branch_name=${branch_name//[^a-zA-Z0-9-]/}
        # convert to lowercase
        branch_name=${branch_name,,}
        # check if branch exists
        if [ -z "$(git branch --list | grep " $branch_name"$)" ]; then
            if check_yes_no_internal "It's dangerous to go alone! Take a branch with you? [Y/n]: "; then
                #make sure we are on main or dev
                #check if dev exists
                if [ -z "$(git branch --list | grep " dev$")" ]; then
                    if [ "$(git branch --show-current)" != "main" ]; then
                        if check_yes_no_internal "You are not on main, switch to main and pull before creating branch? [Y/n]: "; then
                            git checkout main
                            git pull
                        elif ! check_yes_no_internal "Continue without switching to main? [Y/n]: "; then
                            echo "Aborting"
                            return 0
                        fi
                    fi
                else
                    if [ "$(git branch --show-current)" != "dev" ]; then
                        if check_yes_no_internal "You are not on dev, switch to dev and pull before creating branch? [Y/n]: "; then
                            git checkout dev
                            git pull
                        elif ! check_yes_no_internal "Continue without switching to dev? [Y/n]: "; then
                            echo "Aborting"
                            return 0
                        fi
                    fi
                fi
                git checkout -b $branch_name
            fi
        elif [ "$(git branch --show-current)" != "$branch_name" ]; then
            if check_yes_no_internal "Switch to $branch_name? [Y/n]: "; then
                git checkout $branch_name
            fi
        fi
    fi
    # match the status to the id
    status_id=$(printf '%s\n' "${status_array[@]}" | grep -w "$status" | cut -d "-" -f 1)
    if [ -z "$status_id" ]; then
        echo "Error: Could not find status id"
        return 0
    fi
    add_to_col="$(gh api graphql -f project="$project_id" -f issueid="$item_id" -f field="$status_field_id" -f newstatus="$status_id" -f query='
            mutation ($project: ID!, $issueid: ID!, $field: ID!, $newstatus: String!) {
              updateProjectV2ItemFieldValue(
                input: {
                      projectId: $project
                      itemId: $issueid
                      fieldId: $field
                      value: { 
                          singleSelectOptionId: $newstatus
                      }
                }
                ) {
                projectV2Item {
                  id
                }
              }
            }')"

    return 0
}
