#!/bin/bash

# This script is used to manage github tickets in a project
ghtik() {
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
        echo "ghtik"
        echo "Checks and changes the status of tickets on github"
        echo "The tickets will be checked in the current directory's git repo"
        echo ""
        echo "Usage: ghtik [flags]"
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

    # get the repo owner
    gh_name=$(git remote get-url origin | sed -e 's/.*github.com\///' -e 's/\/.*//')
    gh_name=${gh_name#*:}
    # get the repo name from path
    repo_name=$(basename $(git rev-parse --show-toplevel))

    repo_id="$(gh api graphql -f ownerrepo="$gh_name" -f reponame="$repo_name" -f query='
    query($ownerrepo: String!, $reponame: String!) {
        repository(owner: $ownerrepo, name: $reponame) {
            id
            projectsV2(first: 1, orderBy: {field: CREATED_AT, direction: DESC}) {
                nodes {
                    id
                    number
                }
            }
        }
    }')"
    repo_id=${repo_id#*\"id\":\"}
    project_id=${repo_id#*\"id\":\"}
    repo_id=${repo_id%%\"*}
    project_id=${project_id%%\"*}

    issues="$(gh api graphql -f project="$project_id" -f field="$status_field_id" -f query='
    query($project: ID!) {
        node(id: $project) {
            ... on ProjectV2 {
                items(last: 100 ) {
                    nodes {
                        fieldValues(first: 100) {
                            nodes {
                                ... on ProjectV2ItemFieldSingleSelectValue {
                                    name
                                }
                            }
                        }
                        id
                        content {
                            ... on Issue {
                                id
                                title
                                number
                                createdAt
                                state
                                body
                                assignees(first: 3) {
                                    nodes {
                                    ...on User {
                                        login
                                    }
                                }
                                }
                                labels(first: 10) {
                                    nodes {
                                        name
                                    }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }')"
    declare -a issues_arr
    while [[ $issues == *"\"id\":\""* ]]; do
        status_column=${issues#*'{}','{'\"name\":\"}
        status_column=${status_column%%\"*}

        item_id=${issues#*\"id\":\"}
        item_id=${item_id%%\"*}
        issues=${issues#*\"id\":\"$item_id\"}

        issue_id=${issues#*\"id\":\"}
        issue_id=${issue_id%%\"*}
        issues=${issues#*\"id\":\"$issue_id\"}

        issue_name=${issues#*\"title\":\"}
        issue_name=${issue_name%%\"*}

        issue_num=${issues#*\"number\":}
        issue_num=${issue_num%%,*}

        issue_state=${issues#*\"state\":\"}
        issue_state=${issue_state%%\"*}

        issue_assignees=${issues#*\"assignees\":{\"nodes\":[}
        issue_assignees=${issue_assignees%%]*}
        assignees=""
        while [[ $issue_assignees == *"\"login\":\""* ]]; do
            assignee=${issue_assignees#*\"login\":\"}
            assignee=${assignee%%\"*}
            issue_assignees=${issue_assignees#*\"login\":\"$assignee\"}
            if [ -z "$assignees" ]; then
                assignees="$assignee"
            else
                assignees="$assignees $assignee"
            fi
        done
        issue_created=${issues#*\"createdAt\":\"}
        issue_created=${issue_created%%\"*}

        issue_labels=${issues#*\"labels\":{\"nodes\":[}
        issue_labels=${issue_labels%%]*}
        labels=""
        while [[ $issue_labels == *"\"name\":\""* ]]; do
            label=${issue_labels#*\"name\":\"}
            label=${label%%\"*}
            issue_labels=${issue_labels#*\"name\":\"$label\"}
            if [ -z "$labels" ]; then
                labels="$label"
            else
                labels="$labels $label"
            fi
        done
        issue_body=${issues#*\"body\":\"}
        issue_body=${issue_body%%\"*}
        issues_arr[$issue_num]="$issue_num"";""$issue_name"";""$status_column"";""$labels"";""$issue_state"";""$assignees"";""$issue_created"";""$issue_id"";""$item_id"";""$issue_body"

    done
    # if only listing, print and exit
    if [ "$only_list" = true ]; then
        if [ "$show_all" = true ]; then
            printf '%s\n' "${issues_arr[@]}" | cut -d ";" -f 1,2,3,4,5,6,7 | sort -t ';' -k 3 -r | column -s$';' -t
        else
            printf '%s\n' "${issues_arr[@]}" | cut -d ";" -f 1,2,3,4,5,6,7 | sort -t ';' -k 3 -r | awk -F ';' '$3 != "Done" && $3 != "done"' | column -s$';' -t
        fi
        return 0
    fi
    # print the issues
    if [ "$show_all" = true ]; then
        # show the 5th column (status)
        issuei="$(printf '%s\n' "${issues_arr[@]}" | cut -d ";" -f 1,2,3,4,5,6,7 | sort -t ';' -k 3 -r | column -s$';' -t | fzf)"
    else
        issuei="$(printf '%s\n' "${issues_arr[@]}" | cut -d ";" -f 1,2,3,4,5,6,7 | sort -t ';' -k 3 -r | awk -F ';' '$3 != "Done" && $3 != "done"' | column -s$';' -t | fzf)"
    fi
    if [ -z "$issuei" ]; then
        echo "No issue selected"
        return 0
    fi
    issue_num=${issuei%% *}
    # printf '%s\n' "${issues_arr[$issue_num]}"
    issue_without_body="$(printf '%s\n' "${issues_arr[$issue_num]}" | cut -d ";" -f 1,2,3,4,5,6,7 | column -s$';' -t)"
    item_id=$(printf '%s\n' "${issues_arr[$issue_num]}" | cut -d ";" -f 9)
    # make sure id starts with PV
    if [[ $item_id != PV* ]]; then
        item_id=$(printf '%s\n' "${issues_arr[$issue_num]}" | cut -d ";" -f 8)
    fi
    # print the issue
    gh issue view "$issue_num"
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
