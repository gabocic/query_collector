#!/usr/bin/env bash

# Load configuration
parent_path=$(dirname "${BASH_SOURCE[0]}")
. $parent_path/config $parent_path

function log() {
    case $1 in
        ([eE][rR][rR][oO][rR]):
        level="ERROR"
        ;;
        ([iI][nN][fF][oO]):
        level="INFO"
        ;;
        ([wW][aA][rR][nN]):
        level="WARN"
        ;;
    esac    
    echo `date +'%Y-%m-%d-%H:%M:%S'` "[$level]" $2 | tee -a $log_file
}

function tool_exists() {
    toolpath=""
    local istoolinst=`which $1 > /dev/null 2>&1; echo $?`
    if [ $istoolinst -ne 0 ]
    then
        log error "$1 is not installed or is not on PATH. Exiting.."
        exit 1
    else
        log info "$1 is present on the system"
        toolpath=`which $1`
    fi
}

function banner() {
    echo "============================================" 
    echo "===   Slow query and Stats collection    ==="
    echo "============================================"
    echo ""
}

function request_db_params() {
    default_db_host="127.0.0.1"
    default_db_port=3306
    
    read -p "Please provide the Database user: " db_user
    read -sp "Please provide the Database password: " db_pass
    echo ""
    read -p "If connecting through socket, please specify the path: " db_sock
    if [ -z $db_sock ]
    then
        read -p "Please provide the Database host [$default_db_host]: " db_host
        db_host=${db_host:-$default_db_host}
        read -p "Please provide the Database port [$default_db_port]: " db_port
        db_port=${db_port:-$default_db_port}
    fi
}


function test_db_connection() {
    dbcli="$dbcli -A --connect-timeout 1"
    if [ -z $db_sock ]
    then
        local connerror="Unable to connect to the database server in $db_host, on port $db_port, with user $db_user"
        dbcli="$dbcli -h $db_host -u $db_user -p$db_pass -P$db_port"
    else
        local connerror="Unable to connect to the database server on socket $db_sock, with user $db_user"
        dbcli="$dbcli -S $db_sock -u $db_user -p$db_pass"
    fi

    $dbcli -e"select now()" > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "$connerror"
        exit 1
    else
        log info "Successfully connected to database server"
        dbclisil="$dbcli -NBs"
    fi
}

function retrieve_mysql_param() {
    #p1: parameter name
    #p2: return variable
    #p3: can fail
    
    local __resultvar=$2
    # Sanitize value
    local dbparam=`echo $1 | sed -e "s/[[',;]]\+//g" -e "s/[[:blank:]]\+//g"`
    dbparamval=`$dbclisil -e "select @@${dbparam}" 2>/dev/null`
    if [ $? -ne 0 ]
    then
        if [ $3 -eq 0 ]
        then
            log error "Failed trying to retrieve parameter '$dbparam'"
            exit 1
        else
            log warn "Failed trying to retrieve parameter '$dbparam'"
            dbparamval="NULL"
        fi
    fi
    eval $__resultvar="'$dbparamval'"
}

function execute_query() {
    #p1: database
    #p2: return variable
    #p3: can fail
    #p4: query
    
    local __resultvar=$2
    queryres=`$dbclisil $1 -e "$4" 2>/dev/null`
    if [ $? -ne 0 ]
    then
        if [ $3 -eq 0 ]
        then
            log error "Failed trying to execute query ${2}"
            exit 1
        else
            log warn "Failed trying to execute query ${2}"
            queryres="NULL"
        fi
    fi
    eval $__resultvar="'$queryres'"
}

function save_var_to_file() {
    #p1: parameter name
    #p2: parameter value
    #p3: file name
    echo \"$1\",\"$2\" >> $3
}

function init_dirs() {
    mkdir -p $output_dir > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "I was not able to create the directories I need to collect information. 
            Please review permissions on '$output_dir' or change the path in ./config"
        exit 1
    fi
    rm -fv $general_info_file > /dev/null 2>&1
    rm -fv $optimizer_switch_file > /dev/null 2>&1
    rm -fv $stats_conf_file > /dev/null 2>&1
    rm -fv $query_digest_file > /dev/null 2>&1
    rm -fv $output_dir/$sql_commands_file > /dev/null 2>&1
    rm -fv $table_list_file > /dev/null 2>&1
    rm -fv $schema_info_file > /dev/null 2>&1
    rm -fv $output_dir/$explain_stmt_file > /dev/null 2>&1
    rm -fv $output_dir/$mdb_costs_query_script > /dev/null 2>&1
    rm -fv $output_dir/*.txt > /dev/null 2>&1
    rm -fv $output_dir/*_querycollector.tar.gz > /dev/null 2>&1
}

function run_db_script() {
    #p1: script
    #p2: output file
    #p3: script description for logging purposes
    #p4: verbose? 

    if [ $4 -eq 1 ]
    then
        local mysqlcli="$dbcli -vvv"
    else
        local mysqlcli="$dbcli"
    fi
    $mysqlcli -s -e "source $1" > $2 2>/dev/null
    if [ $? -ne 0 ]
    then
        log error "Something went wrong when executing $3"
        exit 1
    fi
}

function output_sanitizer() {
    # Declare associative array (BASH version > 4.0)
    declare -A valuesaa

    # Modify IFS to not use :space: as separator
    IFS=$'\n'

    # Iterate over all query explain output files
    for file in $(ls -1 $output_dir/*.txt | grep '[A-Z,0-9]')
    do

        # For each file, iterate over query values found
        for value in $(grep -o -P "'([^']*)'" $file | sort -u; grep -e "attached_condition" -e "Message:" -e "expanded_query" -e "original_condition" -e "resulting_condition" -e "attached" -e "constant_condition_in_bnl" $file  | awk -F ":" '{print $2}' | sed  's/"//' | sed 's/"$//'| grep -o -P '"([^"]*)"' | sort -u)
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

    # Iterate over all query explain output files
    for file in $(ls -1 $output_dir/*.txt | grep '[A-Z,0-9]')
    do
        for key in "${!valuesaa[@]}"
        do
            sed -i "s|$key|${valuesaa[$key]}|g" $file
        done
    done
}

function main() {

    # Create collection directories and remove any files
    init_dirs
    log info "======= Starting collection process ========"

    # Check that the MySQL client is installed
    tool_exists mysql
    dbcli=$toolpath

    # Check that Perl is installed  
    tool_exists perl

    # Ask for the database server connection details"
    request_db_params

    # Test database connection
    test_db_connection

    # Retrieve relevant server configuration
    retrieve_mysql_param "version" dbparam_version 0
    save_var_to_file version $dbparam_version $general_info_file

    retrieve_mysql_param "innodb_version" dbparam_idb_version 0
    save_var_to_file version $dbparam_idb_version $general_info_file
    major_version=`echo $dbparam_idb_version | awk -F "." '{print $1"."$2}'`

    # Are we working with MariaDB?
    ismdb=`echo "$dbparam_version" | grep -i 'mariadb' | wc -l`

    # Check that we are running on a supported version
    if [[ ! " ${supported_major_versions[*]} " =~ " ${major_version} " ]]
    then
        log error "Server version is not supported. Supported versions are ${supported_major_versions}"
        exit 1
    else
        log info "Server version is ${major_version}"
    fi

    # Retrieve relevant server variables and ratios
    ## Check if we need to worry about show_compatibility_56
    if [ "${major_version}" == "5.7" ]
    then
        retrieve_mysql_param "show_compatibility_56" dbparam_compat56 1
    fi
    if ([ "$dbparam_compat56" == "0" ] && [ "${major_version}" == "5.7" ]) || ([ ${major_version} == "8.0" ])
    then
            sysschema="performance_schema"
            execute_query $sysschema dbrate_select 0 "select ifnull(round(((select count_star from events_statements_summary_global_by_event_name where event_name='statement/sql/select') + (select variable_value from global_status where VARIABLE_NAME='Qcache_hits'))/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
            execute_query $sysschema dbrate_insert 0 "select ifnull(round((select sum(count_star) from events_statements_summary_global_by_event_name where event_name='statement/sql/insert' or  event_name='statement/sql/insert_select')/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
            execute_query $sysschema dbrate_delete 0 "select ifnull(round((select sum(count_star) from events_statements_summary_global_by_event_name where event_name='statement/sql/delete' or  event_name='statement/sql/delete_multi')/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
            execute_query $sysschema dbrate_update 0 "select ifnull(round((select sum(count_star) from events_statements_summary_global_by_event_name where event_name='statement/sql/update' or event_name='statement/sql/update_multi')/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
            execute_query $sysschema dbrate_qchit 0 "select ifnull(round((select variable_value from global_status where VARIABLE_NAME='Qcache_hits') / ((select count_star from events_statements_summary_global_by_event_name where event_name='statement/sql/select') + (select variable_value from global_status where VARIABLE_NAME='Qcache_hits')),2)*100,0)"   
    else
        sysschema="information_schema"
        execute_query $sysschema dbrate_select 0 "select ifnull(round((select sum(variable_value) from global_status where VARIABLE_NAME='Com_select' or  VARIABLE_NAME='Qcache_hits')/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
        execute_query $sysschema dbrate_insert 0 "select ifnull(round((select sum(variable_value) from global_status where VARIABLE_NAME='Com_insert' or  VARIABLE_NAME='Com_insert_select')/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
        execute_query $sysschema dbrate_delete 0 "select ifnull(round((select sum(variable_value) from global_status where VARIABLE_NAME='Com_delete' or  VARIABLE_NAME='Com_delete_multi')/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
        execute_query $sysschema dbrate_update 0 "select ifnull(round((select sum(variable_value) from global_status where VARIABLE_NAME='Com_update' or  VARIABLE_NAME='Com_update_multi')/(select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
        execute_query $sysschema dbrate_qchit 0 "select ifnull(round((select variable_value from global_status where VARIABLE_NAME='Qcache_hits') / (select sum(variable_value) from global_status where VARIABLE_NAME='Com_select' or  VARIABLE_NAME='Qcache_hits'),2)*100,0)"
    fi
    
    execute_query $sysschema dbrate_bphit 1 "select ifnull(round((1-ifnull((select variable_value from global_status where VARIABLE_NAME='Innodb_buffer_pool_reads') / (select variable_value from global_status where VARIABLE_NAME='Innodb_buffer_pool_read_requests'),0))*100,2),0)"
    execute_query $sysschema dbrate_keychit 1 "select ifnull(round((1-ifnull((select variable_value from global_status where VARIABLE_NAME='Key_reads') / (select variable_value from global_status where VARIABLE_NAME='Key_read_requests'),0))*100,2),0)"
    execute_query $sysschema dbrate_idblogwaits 0 "select ifnull(round((select variable_value from global_status where VARIABLE_NAME='Innodb_log_waits') / (select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
    execute_query $sysschema dbrate_sortmergepasses 0 "select ifnull(round((select variable_value from global_status where VARIABLE_NAME='Sort_merge_passes') / (select variable_value from global_status where VARIABLE_NAME='Uptime'),2),0)"
    execute_query $sysschema dbrate_tmptables 0 "select ifnull(round((select variable_value from global_status where VARIABLE_NAME='created_tmp_disk_tables')/(select variable_value from global_status where VARIABLE_NAME='created_tmp_tables'),2)*100,0)"

    save_var_to_file bufferpool_hit_ratio $dbrate_bphit $general_info_file
    save_var_to_file key_cache_hit_ratio $dbrate_keychit $general_info_file
    save_var_to_file idb_log_waits_per_sec $dbrate_idblogwaits $general_info_file
    save_var_to_file sort_merge_passes_per_sec $dbrate_sortmergepasses $general_info_file
    save_var_to_file tmp_tables_on_disk_perc $dbrate_tmptables $general_info_file
    save_var_to_file select_rate $dbrate_select $general_info_file
    save_var_to_file insert_rate $dbrate_insert $general_info_file
    save_var_to_file delete_rate $dbrate_delete $general_info_file
    save_var_to_file update_rate $dbrate_update $general_info_file
    save_var_to_file qchit_ratio $dbrate_qchit $general_info_file

    retrieve_mysql_param "innodb_stats_on_metadata" dbparam_stats_on_md 0
    save_var_to_file innodb_stats_on_metadata $dbparam_stats_on_md $general_info_file

    retrieve_mysql_param "query_cache_type" dbparam_qct 1
    save_var_to_file query_cache_type $dbparam_qct $general_info_file
    
    retrieve_mysql_param "query_cache_size" dbparam_qcs 1
    save_var_to_file query_cache_size $dbparam_qcs $general_info_file
    
    retrieve_mysql_param "query_cache_limit" dbparam_qcl 1
    save_var_to_file query_cache_limit $dbparam_qcl $general_info_file

    retrieve_mysql_param "tmp_table_size" dbparam_tmp_table_size 1
    save_var_to_file tmp_table_size $dbparam_tmp_table_size $general_info_file

    retrieve_mysql_param "max_heap_table_size" dbparam_max_heap_table_size 1
    save_var_to_file max_heap_table_size $dbparam_max_heap_table_size $general_info_file

    retrieve_mysql_param "sort_buffer_size" dbparam_sort_buffer_size 1
    save_var_to_file sort_buffer_size $dbparam_sort_buffer_size $general_info_file

    retrieve_mysql_param "join_buffer_size" dbparam_join_buffer_size 1
    save_var_to_file join_buffer_size $dbparam_join_buffer_size $general_info_file

    retrieve_mysql_param "max_sort_length" dbparam_max_sort_length 1
    save_var_to_file max_sort_length $dbparam_max_sort_length $general_info_file


    # Retrieve relevant statistics configuration
    retrieve_mysql_param "innodb_stats_persistent" dbparam_idbstatspersistent 0
    save_var_to_file innodb_stats_persistent  $dbparam_idbstatspersistent $stats_conf_file
    
    retrieve_mysql_param "innodb_stats_auto_recalc" dbparam_innodb_stats_auto_recalc 0
    save_var_to_file innodb_stats_auto_recalc $dbparam_innodb_stats_auto_recalc $stats_conf_file
    
    retrieve_mysql_param "innodb_stats_include_delete_marked" dbparam_innodb_stats_include_delete_marked 0
    save_var_to_file innodb_stats_include_delete_marked $dbparam_innodb_stats_include_delete_marked $stats_conf_file
    
    retrieve_mysql_param "innodb_stats_method" dbparam_innodb_stats_method 0
    save_var_to_file innodb_stats_method $dbparam_innodb_stats_method $stats_conf_file
    
    retrieve_mysql_param "innodb_stats_on_metadata" dbparam_innodb_stats_on_metadata 0
    save_var_to_file innodb_stats_on_metadata $dbparam_innodb_stats_on_metadata $stats_conf_file
        
    retrieve_mysql_param "innodb_stats_persistent_sample_pages" dbparam_innodb_stats_persistent_sample_pages 0
    save_var_to_file innodb_stats_persistent_sample_pages $dbparam_innodb_stats_persistent_sample_pages $stats_conf_file
    
    retrieve_mysql_param "innodb_stats_sample_pages" dbparam_innodb_stats_sample_pages 1
    save_var_to_file innodb_stats_sample_pages $dbparam_innodb_stats_sample_pages $stats_conf_file
    
    retrieve_mysql_param "innodb_stats_transient_sample_pages" dbparam_innodb_stats_transient_sample_pages 0
    save_var_to_file innodb_stats_transient_sample_pages $dbparam_innodb_stats_transient_sample_pages $stats_conf_file

    
    # Retrieve relevant optimizer configuration
    retrieve_mysql_param "optimizer_switch" dbparam_optimizerswitch 0
    save_var_to_file optimizer_switch $dbparam_optimizerswitch $optimizer_switch_file

    # Check slow query log configuration
    retrieve_mysql_param "slow_query_log" dbparam_slowquerylog
    if [ "$dbparam_slowquerylog" == "1" ]
    then
        log info "Slow query log is enabled"
    else
        log warn "Slow query log is disabled"
    fi
    
    retrieve_mysql_param "long_query_time" dbparam_longquerytime 0
    log info "Long query time set to $dbparam_longquerytime seconds"

    retrieve_mysql_param "log_slow_admin_statements" dbparam_logslowadminstatements 1
    if [ "$dbparam_logslowadminstatements" == 0 ]
    then 
        log info "Admin statements like ALTER TABLE or CREATE INDEX are NOT being logged"
    else
        log info "Admin statements like ALTER TABLE or CREATE INDEX *ARE* being logged"
    fi

    retrieve_mysql_param "log_slow_slave_statements" dbparam_logslowslavestatements 1
    if [ "$dbparam_logslowslavestatements" == 0 ]
    then 
        log info "Slow queries executed by slave threads are not being logged"
    else
        log info "Slow queries executed by slave threads *ARE* being logged"
    fi
    
    retrieve_mysql_param "min_examined_row_limit" dbparam_minexaminedrowlimit 0
    log info "Minimum rows read to be included in the slow query log: $dbparam_minexaminedrowlimit"
    
    retrieve_mysql_param "log_output" dbparam_logoutput 0
    log info "Slow query log output is set to $dbparam_logoutput"

    # Retrieve path for slow query log
    retrieve_mysql_param "slow_query_log_file" dbparam_slowquerylogfile 0
    log info "Slow query log file path: $dbparam_slowquerylogfile"

    # Check access to slow query log file
    ls $dbparam_slowquerylogfile > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log warn "I can't access the slow query log in '$dbparam_slowquerylogfile'"
        read -p "Please specify the location of the slow query log: " dbparam_slowquerylogfile
        ls $dbparam_slowquerylogfile > /dev/null 2>&1
        if [ $? -ne 0 ]
        then
            log error "I can't access the slow query log in '$dbparam_slowquerylogfile' either"
            exit 1
        fi
    fi

    # Check slow query log file size
    sqfsize=`wc -c $dbparam_slowquerylogfile | awk '{print $1}' 2>/dev/null`
    if [ $sqfsize -gt 1073741824 ]
    then
        log warn "The slow query log file size is `echo 'scale=2 ; '$sqfsize' / 1073741824' | bc` Gb. It might take a while to process the slow queries"
    fi

    # Create query digest
    log info "I now will aggregate slow queries and compute some stats.."
    $parent_path/pt-query-digest \
        --output=json-anon \
        --explain-dir=$output_dir \
        --explain-file=$explain_stmt_file \
        --schema-sql-file=$sql_commands_file \
        --mdb-costs-file=$mdb_costs_query_script \
        --no-version-check \
        --server-version=$major_version \
        --no-continue-on-error $dbparam_slowquerylogfile > $query_digest_file 2>>$log_file

    query_digest_lines=`wc -l $query_digest_file | awk '{print $1}'`
    if [ "$query_digest_lines" == "0" ]
    then
        log error "I was not able to extract any queries from the slow query log. The file is either empty or corrupted"
        exit 1
    fi
    
    sql_commands_file_fp=$output_dir/$sql_commands_file

    # Deduplicate statements
    cat $sql_commands_file_fp | sort -u > $output_dir/.tempfile
    mv $output_dir/.tempfile $sql_commands_file_fp > /dev/null 2>&1

    # Create a list of simple table names
    cat $sql_commands_file_fp | grep 'SHOW CREATE TABLE' | sed 's/SHOW CREATE TABLE //' | sed 's/\\G//' > $table_list_file

    # Run prepared commands
    default_colschema="N"
    if [ "$dbparam_stats_on_md" == "1" ]
    then
        log warn "'innodb_stats_on_metadata' is enabled, which means that the server will refresh object statistics before showing them. 
            If tables are big, this could have some performance impact. Do you wish to continue now or collect this info later, during
            off-peak hours?"
            read -p "Run now [Y] | or Later [N]: " colschema
    else
        colschema="Y"
    fi
    colschema=${colschema:-$default_colschema}
    
    if [ "$colschema" == "Y" ]
    then
        log info "Collecting additional schema information from the server"
        run_db_script $sql_commands_file_fp $schema_info_file "SQL commands to retrieve additional schema information" 1
    else
        log info "We will finish collection later"
        exit 0
    fi

    log info "Collecting queries execution plans"
    run_db_script $output_dir/$explain_stmt_file /dev/null "EXPLAIN for collected queries" 0

    # Make sure we are using the right page sample value
    if [ "$dbparam_idbstatspersistent" == "1" ]
    then
        log info "Persistent statistics are enabled and ${dbparam_innodb_stats_persistent_sample_pages} pages are sampled during calculation"
    else
        if [ "$ismdb" == "1" ]
        then
            retrieve_mysql_param "innodb_stats_traditional" dbparam_innodb_stats_traditional 0
            save_var_to_file innodb_stats_traditional $dbparam_innodb_stats_traditional $stats_conf_file

            retrieve_mysql_param "use_stat_tables" dbparam_use_stat_tables 0
            save_var_to_file use_stat_tables $dbparam_use_stat_tables $stats_conf_file

            if [ "$dbparam_innodb_stats_traditional" == "1" ]
            then
                log info "This a MariaDB server and pages sampled during stats calculation is dynamic"
            fi
        else
            log info "Transient statistics are used and ${dbparam_innodb_stats_transient_sample_pages} pages are sampled during calculation"
        fi
    fi

    # Stats tables collection
    log info "Collecting costs information"

    ## Version specific costs tables
    if [ "$ismdb" == "1" ]
    then
        run_db_script $output_dir/$mdb_costs_query_script $es_costs_query_file "MariaDB costs tables" 1
    elif [ "${major_version}" != "5.6" ]
    then
        run_db_script $mysql_costs_query_script $es_costs_query_file "MySQL/Percona costs tables" 1
    else
        echo "MySQL 5.6 does not support cost tables" > $es_costs_query_file
    fi

    # Delete EXPLAIN script to preserve any sensitive query values
    rm -f $output_dir/$explain_stmt_file

    # Sanitize optimizer trace output
    log info "Sanitizing output"
    output_sanitizer

    # Package output
    log info "Creating collection package"
    collection_pkg=$output_dir/`date '+%Y%m%d%H%M%S'`_querycollector.tar.gz
    tar -czf $collection_pkg $output_dir/* > /dev/null 2>>$log_file
    log info "Collection package can be found at '$collection_pkg'"

    log info "Collection completed successfully"
    exit 0

}    

banner
main
