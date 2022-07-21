output_dir=./collection_output

# Declare associative array (BASH version > 4.0)
declare -A valuesaa

# Modify IFS to not use :space: as separator
IFS=$'\n'

# Iterate over all query explain output files
for file in $(ls -1 $output_dir/*.txt | grep '[A-Z,0-9]')
do

    # For each file, iterate over query values found
    for value in $(grep -o -P "'([^']*)'" $file | sort -u; grep -e "attached_condition" -e "Message:" -e "expanded_query" -e "original_condition" -e "resulting_condition" -e "attached" -e "constant_condition_in_bnl" $file  | awk -F ":" '{print $2}' | sed  's/"//' | sed 's/"$//'| grep -o -P '"([^"]*)"' | sort -u)
    #for value in $(grep -o -P "'([^']*)'" $file | sort -u)
    do
        valuecode=""

        # Remove single-quotes
        value=${value:1:-1}

        # If value was not added before
        if [ ! ${valuesaa[$value]+_} ]
        then
            if [[ $value =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}.*$ ]]
            then
                valuecode=date
            else
                # Check for % at the begining
                if [ "${value:0:1}" == "%" ]
                then
                    valuecode="%"
                fi

                # Check for _ at the begining
                if [ "${value:0:1}" == "_" ]
                then
                    valuecode="_"
                fi

                matched=0
                # Check if integer
                echo "$value" | grep '^[0-9]*$' > /dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    valuecode=$valuecode"int"
                    matched=1
                fi

                # Check if decimal
                echo "$value" | grep '^[0-9.,]*$' > /dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    valuecode=$valuecode"float"
                    matched=1
                fi

                # If not decimal or int, then alpha
                if [ $matched -eq 0 ]
                then
                    valuecode=$valuecode"alpha"    
                fi

                # Check if we have % in between
                echo "${value:1:-1}" | grep '%' > /dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    valuecode=$valuecode"-perc"
                fi

                # Check if we have _ in between
                echo "${value:1:-1}" | grep '_' > /dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    valuecode=$valuecode"-unders"
                fi

                # Check for % at the end
                echo "${value:0-1}" | grep '%' > /dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    valuecode=$valuecode"%"
                fi

                # Check for _ at the end
                echo "${value:0-1}" | grep '_' > /dev/null 2>&1
                if [ $? -eq 0 ]
                then
                    valuecode=$valuecode"_"
                fi
            fi
            valuesaa+=([$value]=$valuecode)
        fi
    done
done


for key in "${!valuesaa[@]}"
do
    echo "$key => ${valuesaa[$key]}"
done
# Iterate over all query explain output files
for file in $(ls -1 $output_dir/*.txt | grep '[A-Z,0-9]')
do
    for key in "${!valuesaa[@]}"
    do
        sed -i "s|$key|${valuesaa[$key]}|g" $file
    done
done
